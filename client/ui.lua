-- menus for the client
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local constants = require "shared.constants"
local UI = {}
local REQUEST_TIMEOUT = 10

--- Send an encrypted request and return the decrypted response
--- @param state table { clientProtocol, network myId, sk, pk, serverId, ... }
--- @param packetType string from the constants
--- @param payloadTable table unencrypted payload to send
--- @return table|nil replyPayload {sucess = bool, data = ..., code = ...}
--- @return string|nil errorMessage
local function sendAndReceive(state, packetType, payloadTable)
    local session = state.clientProtocol.session
    if not session then
        return nil, "No active session. Please restart the client."
    end
    print("[CLI] Sending " .. packetType .. " (seq=" .. tostring(session.sendSeq + 1) .. ")...")
    local pkt = session:send(packetType, state.myId, state.sk, state.pk, payloadTable)
    state.network.send(state.serverId, pkt)
    print("[CLI] Sent, waiting for reply (timeout=" .. tostring(REQUEST_TIMEOUT) .. "s)...")

    local reply = state.network.receiveOnce(REQUEST_TIMEOUT)
    if not reply then
        print("[CLI] No reply received (timeout or invalid packet)")
        return nil, "Request timed out. Server may be offline or unreachable."
    end

    print("[CLI] Got reply type=" .. tostring(reply.type) .. " from=" .. tostring(reply.sender))
    local payload, decErr = session:receive(reply)
    if not payload then
        print("[CLI] Decrypt/verify reply failed: " .. tostring(decErr))
        return nil, "Failed to decrypt/verify server response: " .. tostring(decErr)
    end

    print("[CLI] Reply decrypted OK, success=" .. tostring(payload.success))
    return payload, nil
end

--- Print separator
local function hr()
    print(string.rep("=", 36))
end

--- Print centered header
local function header(title)
    hr()
    print("  " .. title)
    hr()
end

--- Prompt for number input
--- @param prompt string
--- @return number|nil
local function readNumber(prompt)
    print(prompt)
    local input = read()
    if input == nil then
        return nil
    end
    local n = tonumber(input)
    if n == nil or n <= 0 then
        return nil
    end
    return n
end

--- Prompt for string
local function readString(prompt)
    print(prompt)
    local input = read()
    if input == nil or #input == 0 then
        return nil
    end
    return input
end

--- Pause until input
local function pause()
    print()
    print("Press Enter to continue...")
    read()
end

-- ------------------------------- Login flow ------------------------------- --
--- Welcome screen: login or register
function UI.run(state)
    while true do
        print()
        header("BlockVault Client")

        -- Detect nearest player
        local playerDetector = require "shared.player_detector"
        print("Scanning for nearby players (range: " ..
            tostring(constants.PLAYER_DETECT_RANGE or 2) .. " blocks)...")
        local detectedUsername = playerDetector.detectOrRetry(
            state.playerDetector,
            constants.PLAYER_DETECT_RANGE
        )
        if not detectedUsername then
            print("Exiting.")
            return
        end

        print()
        print("Detected player: " .. detectedUsername)
        hr()
        print("0. Test Connection (PING)")
        print("1. Log in as " .. detectedUsername)
        print("2. Create a new account as " .. detectedUsername)
        print("3. Re-scan for player")
        print("4. Exit")
        print()
        print("Choose a number:")

        local choice = read()
        if choice == "0" then
            print("Pinging server...")
            local payload, err = sendAndReceive(state, constants.PACKET.PING, {})
            if payload and payload.success then
                print("PONG! Server is reachable and session is valid.")
            else
                print("PING failed: " .. tostring(err))
            end
            pause()
        elseif choice == "1" then
            -- Validate account exists
            local payload, err = sendAndReceive(state, constants.PACKET.GET_ACCOUNT, {
                username = detectedUsername
            })

            if not payload then
                print("Error: " .. tostring(err))
            elseif not payload.success then
                local code = payload.code or "UNKNOWN"
                if code == constants.ERROR.ACCOUNT_NOT_FOUND then
                    print("No account found for '" .. detectedUsername .. "'.")
                    print("Use option 2 to create one.")
                elseif code == constants.ERROR.PERMISSION_DENIED then
                    print("That account belongs to a different user.")
                else
                    print("Server error: " .. code)
                end
            else
                local acct = payload.data
                print("Welcome, " .. acct.username .. "!")
                local perm = acct.permission or constants.PERMISSION.USER
                print("Permission: " .. perm)
                UI.mainMenu(state, acct.username, perm)
            end
            pause()
        elseif choice == "2" then
            UI.createAccountScreen(state, detectedUsername)
        elseif choice == "3" then
            -- Loop back to re-scan
        elseif choice == "4" then
            print("Goodbye!")
            return
        else
            print("Invalid choice.")
        end
    end
end

-- ----------------------------- Create account ----------------------------- --

--- First time account creation.
function UI.createAccountScreen(state, detectedUsername)
    header("Create New Account")
    print("Player: " .. detectedUsername)
    print("New accounts start with $100 credits.")
    print()

    -- New accounts always start with 100 credits
    local initialBalance = 100

    print("Creating account for " .. detectedUsername .. "...")

    local payload, err = sendAndReceive(state, constants.PACKET.CREATE_ACCOUNT, {
        username = detectedUsername,
        initialBalance = initialBalance,
    })

    if not payload then
        print("Error: " .. tostring(err))
    elseif not payload.success then
        local code = payload.code or "UNKNOWN"
        if code == "USERNAME_TAKEN" then
            print("That username is already taken.")
        elseif code == "ALREADY_HAS_ACCOUNT" then
            print("You already have an account.")
            print("Use option 1 to log in.")
        else
            print("Server error: " .. code)
        end
    else
        local acct = payload.data
        print("Account created successfully!")
        print("Username:   " .. acct.username)
        print("Balance:    $" .. tostring(acct.balance))
        print("Permission: " .. (acct.permission or "USER"))
        print()
        print("Return to the welcome screen and log in with option 1.")
    end
    pause()
end

-- -------------------------------- Main menu ------------------------------- --

--- Main menu shown after login.
--- @param username string
--- @param permission string "USER" | "ADMIN" | "SYSTEM"
function UI.mainMenu(state, username, permission)
    local isAdmin = (permission == constants.PERMISSION.ADMIN or permission == constants.PERMISSION.SYSTEM)
    while true do
        print()
        header("BlockVault - " .. username)

        print("1. Check Balance")
        print("2. Deposit")
        print("3. Withdraw")
        print("4. Transfer")
        print("5. Transaction History")
        print("6. Account Info")

        if isAdmin then
            print("7. Admin Menu")
            print("8. Logout")
        else
            print("7. Logout")
        end

        print()
        print("Choice:")
        local choice = read()

        if choice == "1" then
            UI.balanceScreen(state, username, permission)
        elseif choice == "2" then
            UI.depositScreen(state, username, permission)
        elseif choice == "3" then
            UI.withdrawScreen(state, username, permission)
        elseif choice == "4" then
            UI.transferScreen(state, username, permission)
        elseif choice == "5" then
            UI.historyScreen(state, username, permission)
        elseif choice == "6" then
            UI.accountInfoScreen(state, username, permission)
        elseif choice == "7" and isAdmin then
            UI.adminMenu(state, username, permission)
        elseif (choice == "7" and not isAdmin) or choice == "8" then
            -- Disconnect
            local session = state.clientProtocol.session
            if session then
                local pkt = session:send(constants.PACKET.DISCONNECT, state.myId, state.sk, state.pk, {})
                state.network.send(state.serverId, pkt)
            end
            print("Logged out.")
            return
        else
            print("Invalid choice.  Enter a number from the menu.")
        end
    end
end

-- ------------------------------- Operations ------------------------------- --

function UI.balanceScreen(state, username, permission)
    header("Check Balance")

    local target = username
    if permission == constants.PERMISSION.ADMIN or permission == constants.PERMISSION.SYSTEM then
        local other = readString("Username (blank for your own):")
        if other and #other > 0 then
            target = other
        end
    end

    local payload, err = sendAndReceive(state, constants.PACKET.BALANCE, {
        username = target
    })
    if not payload then
        print("Error: " .. tostring(err))
    elseif not payload.success then
        print("Error: " .. (payload.code or "UNKNOWN"))
    else
        print("Account: " .. (payload.data.username or target))
        print("Balance: $" .. tostring(payload.data.balance))
    end
    pause()
end

function UI.depositScreen(state, username, permission)
    header("Deposit  [ADMIN required]")

    local target = readString("Account to deposit into:")
    if not target then
        print("Cancelled.");
        return
    end

    local amount = readNumber("Amount to deposit:")
    if not amount then
        print("Invalid amount. Cancelled.");
        return
    end

    local payload, err = sendAndReceive(state, constants.PACKET.DEPOSIT, {
        username = target,
        amount = amount
    })

    if not payload then
        print("Error: " .. tostring(err))
    elseif not payload.success then
        local code = payload.code or "UNKNOWN"
        if code == constants.ERROR.PERMISSION_DENIED then
            print("Permission denied - ADMIN or higher required.")
        elseif code == constants.ERROR.ACCOUNT_NOT_FOUND then
            print("Account '" .. target .. "' not found.")
        else
            print("Error: " .. code)
        end
    else
        print("Deposit successful!")
        print("New balance for " .. target .. ": $" .. tostring(payload.data.balance))
    end
    pause()
end

function UI.withdrawScreen(state, username, permission)
    header("Withdraw")

    local target = username
    if permission == constants.PERMISSION.ADMIN or permission == constants.PERMISSION.SYSTEM then
        local other = readString("Username (blank for your own):")
        if other and #other > 0 then
            target = other
        end
    end

    local amount = readNumber("Amount to withdraw:")
    if not amount then
        print("Invalid amount. Cancelled.");
        return
    end

    local payload, err = sendAndReceive(state, constants.PACKET.WITHDRAW, {
        username = target,
        amount = amount
    })

    if not payload then
        print("Error: " .. tostring(err))
    elseif not payload.success then
        local code = payload.code or "UNKNOWN"
        if code == constants.ERROR.INSUFFICIENT_FUNDS then
            print("Insufficient funds.")
        elseif code == constants.ERROR.PERMISSION_DENIED then
            print("You can only withdraw from your own account.")
        elseif code == constants.ERROR.ACCOUNT_NOT_FOUND then
            print("Account '" .. target .. "' not found.")
        else
            print("Error: " .. code)
        end
    else
        print("Withdrawal successful!")
        print("New balance for " .. target .. ": $" .. tostring(payload.data.balance))
    end
    pause()
end

function UI.transferScreen(state, username, permission)
    header("Transfer")

    local from = username
    if permission == constants.PERMISSION.ADMIN or permission == constants.PERMISSION.SYSTEM then
        local other = readString("From account (blank for your own):")
        if other and #other > 0 then
            from = other
        end
    end

    local to = readString("To account:")
    if not to then
        print("Cancelled.");
        return
    end
    if to == from then
        print("Source and destination are the same. Cancelled.")
        return
    end

    local amount = readNumber("Amount to transfer:")
    if not amount then
        print("Invalid amount. Cancelled.");
        return
    end

    local payload, err = sendAndReceive(state, constants.PACKET.TRANSFER, {
        from = from,
        to = to,
        amount = amount
    })

    if not payload then
        print("Error: " .. tostring(err))
    elseif not payload.success then
        local code = payload.code or "UNKNOWN"
        if code == constants.ERROR.INSUFFICIENT_FUNDS then
            print("Insufficient funds in source account.")
        elseif code == constants.ERROR.ACCOUNT_NOT_FOUND then
            print("Source or destination account not found.")
        elseif code == constants.ERROR.PERMISSION_DENIED then
            print("You can only transfer from your own account.")
        else
            print("Error: " .. code)
        end
    else
        print("Transfer successful!")
        print("Your balance:      $" .. tostring(payload.data.fromBalance))
        print("Recipient balance: $" .. tostring(payload.data.toBalance))
    end
    pause()
end

function UI.historyScreen(state, username, permission)
    header("Transaction History")

    local target = username
    if permission == constants.PERMISSION.ADMIN or permission == constants.PERMISSION.SYSTEM then
        local other = readString("Username (blank for your own):")
        if other and #other > 0 then
            target = other
        end
    end

    local payload, err = sendAndReceive(state, constants.PACKET.HISTORY, {
        username = target
    })

    if not payload then
        print("Error: " .. tostring(err))
    elseif not payload.success then
        print("Error: " .. (payload.code or "UNKNOWN"))
    else
        local txs = payload.data.transactions
        if not txs or #txs == 0 then
            print("No transactions found.")
        else
            for _, tx in ipairs(txs) do
                print(string.format("  %-8s  %s → %s   $%d", tx.type or "?", tx.from or "-", tx.to or "-",
                    tx.amount or 0))
            end
        end
    end
    pause()
end

function UI.accountInfoScreen(state, username, permission)
    header("Account Info")

    local target = username
    if permission == constants.PERMISSION.ADMIN or permission == constants.PERMISSION.SYSTEM then
        local other = readString("Username (blank for your own):")
        if other and #other > 0 then
            target = other
        end
    end

    local payload, err = sendAndReceive(state, constants.PACKET.GET_ACCOUNT, {
        username = target
    })

    if not payload then
        print("Error: " .. tostring(err))
    elseif not payload.success then
        print("Error: " .. (payload.code or "UNKNOWN"))
    else
        local acct = payload.data
        print("Username:   " .. (acct.username or "?"))
        print("ID:         " .. (acct.id or "?"))
        print("Balance:    $" .. tostring(acct.balance or 0))
        print("Permission: " .. (acct.permission or "USER"))
        print("Created:    " .. tostring(acct.createdAt or "?"))
    end
    pause()
end

-- ------------------------------- Admin menu ------------------------------- --
function UI.adminMenu(state, username, permission)
    while true do
        print()
        header("Admin Menu - " .. username)
        print("1. Create Account (for another player)")
        print("2. Delete Account")
        print("3. Update Account (rename / change permission)")
        print("4. Back to Main Menu")
        print()
        print("Choice:")

        local choice = read()

        if choice == "1" then
            UI.adminCreateAccountScreen(state)
        elseif choice == "2" then
            UI.adminDeleteAccountScreen(state)
        elseif choice == "3" then
            UI.adminUpdateAccountScreen(state)
        elseif choice == "4" then
            return
        else
            print("Invalid choice.")
        end
    end
end

function UI.adminCreateAccountScreen(state)
    header("Admin: Create Account")
    print("Note: the server requires CREATE_ACCOUNT to be")
    print("called by the *new user's own identity*.  If the")
    print("server rejects this with PERMISSION_DENIED, have")
    print("the player run this client themselves and use")
    print("option 2 (Create Account) from the welcome screen.")
    print()

    local username = readString("Username:")
    if not username then
        print("Cancelled.");
        return
    end
    local initialBalance = 100

    local pkHex = readString("User's public key (hex):")
    if not pkHex or #pkHex == 0 then
        print("Public key is required. Cancelled.")
        return
    end

    local payload, err = sendAndReceive(state, constants.PACKET.CREATE_ACCOUNT, {
        username = username,
        initialBalance = initialBalance,
        publicKey = pkHex
    })

    if not payload then
        print("Error: " .. tostring(err))
    elseif not payload.success then
        local code = payload.code or "UNKNOWN"
        if code == "USERNAME_TAKEN" then
            print("Username '" .. username .. "' is already taken.")
        elseif code == constants.ERROR.PERMISSION_DENIED then
            print("Permission denied.  See the note above.")
        else
            print("Error: " .. code)
        end
    else
        print("Account created: " .. payload.data.username)
    end
    pause()
end

function UI.adminDeleteAccountScreen(state)
    header("Admin: Delete Account")

    local target = readString("Username to delete:")
    if not target then
        print("Cancelled.");
        return
    end

    print()
    print("WARNING: this cannot be undone.")
    print("Type the username again to confirm:")
    local confirm = read()
    if confirm ~= target then
        print("Confirmation mismatch. Cancelled.")
        return
    end

    local payload, err = sendAndReceive(state, constants.PACKET.DELETE_ACCOUNT, {
        username = target
    })

    if not payload then
        print("Error: " .. tostring(err))
    elseif not payload.success then
        local code = payload.code or "UNKNOWN"
        if code == constants.ERROR.PERMISSION_DENIED then
            print("Permission denied.  You cannot delete your own account")
            print("or a SYSTEM-level account.")
        elseif code == constants.ERROR.ACCOUNT_NOT_FOUND then
            print("Account '" .. target .. "' not found.")
        else
            print("Error: " .. code)
        end
    else
        print("Account '" .. target .. "' deleted.")
    end
    pause()
end

function UI.adminUpdateAccountScreen(state)
    header("Admin: Update Account")

    local target = readString("Username to update:")
    if not target then
        print("Cancelled.");
        return
    end

    print("Leave a field blank to keep its current value.")
    local newUsername = readString("New username:")
    local newPermission = readString("New permission (USER / ADMIN):")

    -- Normalise permission input
    if newPermission then
        newPermission = newPermission:upper()
        if newPermission ~= "USER" and newPermission ~= "ADMIN" then
            newPermission = nil
        end
    end

    if not newUsername and not newPermission then
        print("Nothing to update. Cancelled.")
        return
    end

    local updatePayload = {
        username = target
    }
    if newUsername and #newUsername > 0 then
        updatePayload.newUsername = newUsername
    end
    if newPermission and #newPermission > 0 then
        updatePayload.permission = newPermission
    end

    local payload, err = sendAndReceive(state, constants.PACKET.UPDATE_ACCOUNT, updatePayload)

    if not payload then
        print("Error: " .. tostring(err))
    elseif not payload.success then
        local code = payload.code or "UNKNOWN"
        if code == constants.ERROR.PERMISSION_DENIED then
            print("Permission denied.  You cannot escalate to SYSTEM or")
            print("modify a SYSTEM-level account.")
        elseif code == "USERNAME_TAKEN" then
            print("The new username is already taken.")
        elseif code == constants.ERROR.ACCOUNT_NOT_FOUND then
            print("Account '" .. target .. "' not found.")
        else
            print("Error: " .. code)
        end
    else
        local acct = payload.data
        print("Account updated.")
        print("Username:   " .. acct.username)
        print("Permission: " .. (acct.permission or "USER"))
    end
    pause()
end

return UI
