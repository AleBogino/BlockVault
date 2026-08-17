-- Chat-only command handling for the BlockBank server.

if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local Toast = require "server.toast"
local db = require "server.database"
local constants = require "shared.constants"
local utils = require "shared.utils"
local Accounts = require "server.accounts"
local Transactions = require "server.transactions"

local M = {}

M.protocol = nil

-- --------------------------------- Admin list -------------------------------- --

local ADMINS_FILE = "data/admins.json"
local admins = {} -- lowecase!!

--- Serialise a value to JSON
local function toJson(value)
    if textutils.serialiseJSON then
        local ok, json = pcall(textutils.serialiseJSON, value)
        if ok then return json end
    end
    if textutils.serializeJSON then
        local ok, json = pcall(textutils.serializeJSON, value)
        if ok then return json end
    end
    return nil
end

--- Deserialise a JSON string
local function fromJson(raw)
    if textutils.unserialiseJSON then
        local ok, data = pcall(textutils.unserialiseJSON, raw)
        if ok then return data end
    end
    if textutils.unserializeJSON then
        local ok, data = pcall(textutils.unserializeJSON, raw)
        if ok then return data end
    end
    return nil
end

--- Load (or generate) the admin list from data/admins.json
function M.loadAdmins()
    admins = {}
    if fs.exists(ADMINS_FILE) then
        local f = fs.open(ADMINS_FILE, "r")
        if f then
            local raw = f.readAll()
            f.close()
            local ok, data = pcall(fromJson, raw)
            if ok and type(data) == "table" and type(data.admins) == "table" then
                for _, name in ipairs(data.admins) do
                    if type(name) == "string" and name ~= "" then
                        admins[name:lower()] = true
                    end
                end
                print(("[CHAT] Loaded %d admin(s) from %s"):format(#data.admins, ADMINS_FILE))
            else
                print("[CHAT] WARNING: could not parse " .. ADMINS_FILE .. " - no admins loaded")
            end
        else
            print("[CHAT] WARNING: could not open " .. ADMINS_FILE .. " - no admins loaded")
        end
    else
        -- Generate starter file
        if not fs.exists("data") then
            fs.makeDir("data")
        end
        local f = fs.open(ADMINS_FILE, "w")
        if f then
            local json = toJson({ admins = {} })
            f.write(json or '{"admins": []}')
            f.close()
            print("[CHAT] Generated " .. ADMINS_FILE .. " - add player names to grant admin chat commands")
        end
    end
end

--- Is this player a chat admin?
--- @param username string
--- @return boolean
function M.isAdmin(username)
    if not utils.isNonEmptyString(username) then
        return false
    end
    return admins[username:lower()] == true
end

--- Build an AuthResult representing a chat admin.
--- @param username string the admin running the command
local function adminAuthResult(username)
    return {
        account = {
            username = username,
            permission = constants.PERMISSION.ADMIN,
        },
        permission = constants.PERMISSION.ADMIN,
    }
end

-- ---------------------------------- Parsing ---------------------------------- --

--- Parse a chat message into a command
--- @param message string the (already $-stripped) chat message
--- @return table|nil { name=, sub=, args= }
local function parse(message)
    if type(message) ~= "string" then return nil end
    local trimmed = message:match("^%s*(.-)%s*$")
    if not trimmed then return nil end

    local cmd, args = trimmed:match("^bank%s+(%S+)%s*(.*)$")
    if not cmd then return nil end
    cmd = cmd:lower()

    if cmd == "login" then
        local code = args:match("^%s*(%S+)%s*$")
        return { name = "login", args = code or "" }
    elseif cmd == "help" then
        return { name = "help" }
    elseif cmd == "transfer" then
        return { name = "transfer", args = args or "" }
    elseif cmd == "list" then
        return { name = "list" }
    elseif cmd == "balance" then
        return { name = "balance" }
    elseif cmd == "admin" then
        local sub, rest = args:match("^%s*(%S+)%s*(.*)$")
        if sub then sub = sub:lower() end
        return { name = "admin", sub = sub or "", args = rest or "" }
    end
    return nil
end

-- ------------------------------- User commands ------------------------------- --

--- Handle "$bank login <code>" - complete the chat login handshake.
--- @param username string
--- @param code     string
local function handleLogin(username, code)
    if not M.protocol then
        Toast.sendMessage(username, "Login is not ready yet. Try again in a moment.")
        return
    end
    M.protocol:completeChatLogin(username, code)
end

--- Handle "$bank help".
--- @param username string
local function handleHelp(username)
    local lines = {
        "bank help - show this list",
        "bank login <code> - link a computer",
        "bank balance - your balance",
        "bank transfer <player> <amount> - send money",
        "bank list - top 10 accounts",
    }
    if M.isAdmin(username) then
        lines[#lines + 1] = "bank admin help - admin commands"
    end
    Toast.sendMessage(username, table.concat(lines, "\n"))
end

--- Handle "$bank transfer <to> <amount>".
--- @param username string the sender
--- @param args     string raw args "<to> <amount>"
local function handleTransfer(username, args)
    if not utils.isNonEmptyString(args) then
        Toast.sendMessage(username, "Usage: bank transfer <player> <amount>")
        return
    end

    local to, amountStr = args:match("^%s*(%S+)%s+(%S+)%s*$")
    local amount = amountStr and tonumber(amountStr)
    if not to or not amount or amount <= 0 then
        Toast.sendMessage(username, "Usage: bank transfer <player> <amount>")
        return
    end

    local acct = db.getAccount(username)
    if not acct then
        Toast.sendMessage(username, "You don't have a BlockBank account yet.")
        print("[SRV][CHAT] transfer refused for " .. tostring(username) .. ": no account")
        return
    end
    if acct.paused then
        Toast.sendMessage(username, "Your account is paused. Transfers are disabled.")
        print("[SRV][CHAT] transfer refused for " .. tostring(username) .. ": account paused")
        return
    end

    local authResult = {
        account = acct,
        permission = acct.permission or constants.PERMISSION.USER,
    }

    local ok, result = Transactions.transfer({
        from = username,
        to = to,
        amount = amount,
    }, authResult)

    if not ok then
        local code = result
        local friendly
        if code == constants.ERROR.INSUFFICIENT_FUNDS then
            friendly = "Insufficient funds for that transfer."
        elseif code == constants.ERROR.DESTINATION_NO_ACCOUNT then
            friendly = "'" .. tostring(to) .. "' does not have a BlockBank account."
        elseif code == constants.ERROR.ACCOUNT_NOT_FOUND then
            friendly = "Your account was not found."
        elseif code == constants.ERROR.ACCOUNT_PAUSED then
            friendly = "'" .. tostring(to) .. "' has a paused account."
        elseif code == constants.ERROR.INVALID_PACKET then
            friendly = "Invalid transfer. Usage: bank transfer <player> <amount>"
        else
            friendly = "Transfer failed: " .. tostring(code)
        end
        Toast.sendMessage(username, friendly)
        print(("[SRV][CHAT] transfer failed for %s -> %s amount=%s: %s"):format(
            tostring(username), tostring(to), tostring(amount), tostring(code)))
        return
    end

    print(("[SRV][CHAT] transfer %s -> %s amount=%s ok (fromBalance=%s)"):format(
        tostring(username), tostring(to), tostring(amount),
        tostring(result and result.fromBalance or "?")))
    -- Success toasts + chat receipts are sent inside Transactions.transfer
end

--- Handle "$bank list" - show the top 10 accounts by balance
--- @param username string
local function handleList(username)
    local accounts = db.listAccounts()
    table.sort(accounts, function(a, b)
        return (a.balance or 0) > (b.balance or 0)
    end)

    local topN = math.min(10, #accounts)
    print(("[SRV][CHAT] list requested by %s (accounts=%d)"):format(tostring(username), #accounts))

    if topN == 0 then
        Toast.sendMessage(username, "No accounts yet.")
        return
    end

    local lines = {}
    for i = 1, topN do
        local acct = accounts[i]
        lines[#lines + 1] = ("%d. %s - $%.2f"):format(i, tostring(acct.username), acct.balance or 0)
    end
    Toast.sendMessage(username, table.concat(lines, "\n"))
end

--- Handle "$bank balance".
--- @param username string
local function handleBalance(username)
    local acct = db.getAccount(username)
    if not acct then
        Toast.sendMessage(username, "You don't have a BlockBank account yet.")
        print("[SRV][CHAT] balance refused for " .. tostring(username) .. ": no account")
        return
    end
    Toast.sendMessage(username, ("Your balance is $%.2f"):format(acct.balance or 0))
    print(("[SRV][CHAT] balance for %s = %s"):format(tostring(username), tostring(acct.balance or 0)))
end

-- ------------------------------- Admin commands ------------------------------ --

--- Show the admin command list.
--- @param username string
local function handleAdminHelp(username)
    Toast.sendMessage(username, table.concat({
        "bank admin help - show this list",
        "bank admin create <player> [amount] - create an account",
        "bank admin delete <player> - delete an account",
        "bank admin pause <player> - pause an account",
        "bank admin unpause <player> - unpause an account",
    }, "\n"))
end

--- Handle "$bank admin create <player> [initialBalance]".
--- @param username string the admin
--- @param args     string raw args
local function handleAdminCreate(username, args)
    local target, balanceStr = args:match("^%s*(%S+)%s*(%S*)%s*$")
    if not target then
        Toast.sendMessage(username, "Usage: bank admin create <player> [amount]")
        return
    end
    local initial = tonumber(balanceStr) or 0
    if initial < 0 then
        Toast.sendMessage(username, "Initial balance cannot be negative.")
        return
    end

    local ok, result = Accounts.adminCreateAccount({
        username = target,
        initialBalance = initial,
    }, adminAuthResult(username))

    if not ok then
        local code = result
        local friendly
        if code == "USERNAME_TAKEN" then
            friendly = "'" .. tostring(target) .. "' already has a BlockBank account."
        elseif code == constants.ERROR.INVALID_PACKET then
            friendly = "Invalid username."
        else
            friendly = "Account creation failed: " .. tostring(code)
        end
        Toast.sendMessage(username, friendly)
        print(("[SRV][CHAT] admin create failed for %s (by %s): %s"):format(
            tostring(target), tostring(username), tostring(code)))
        return
    end

    local created = type(result) == "table" and result or {}
    Toast.sendMessage(username, ("Created account '%s' with $%.2f"):format(
        tostring(created.username), created.balance or 0))
    print(("[SRV][CHAT] admin %s created account %s (balance=%s)"):format(
        tostring(username), tostring(target), tostring(created.balance)))
end

--- Handle "$bank admin delete <player>".
--- @param username string the admin
--- @param args     string raw args
local function handleAdminDelete(username, args)
    local target = args:match("^%s*(%S+)%s*$")
    if not target then
        Toast.sendMessage(username, "Usage: bank admin delete <player>")
        return
    end

    local ok, result = Accounts.deleteAccount({ username = target }, adminAuthResult(username))
    if not ok then
        local code = result
        local friendly
        if code == constants.ERROR.ACCOUNT_NOT_FOUND then
            friendly = "'" .. tostring(target) .. "' does not have an account."
        elseif code == constants.ERROR.PERMISSION_DENIED then
            friendly = "You cannot delete that account."
        else
            friendly = "Delete failed: " .. tostring(code)
        end
        Toast.sendMessage(username, friendly)
        print(("[SRV][CHAT] admin delete failed for %s (by %s): %s"):format(
            tostring(target), tostring(username), tostring(code)))
        return
    end

    Toast.sendMessage(username, ("Deleted account '%s'"):format(tostring(target)))
    print(("[SRV][CHAT] admin %s deleted account %s"):format(tostring(username), tostring(target)))
end

--- Handle "$bank admin pause|unpause <player>".
--- @param username string the admin
--- @param args     string raw args
--- @param paused   boolean true = pause, false = unpause
local function handleAdminPause(username, args, paused)
    local action = paused and "pause" or "unpause"
    local target = args:match("^%s*(%S+)%s*$")
    if not target then
        Toast.sendMessage(username, ("Usage: bank admin %s <player>"):format(action))
        return
    end

    local fn = paused and Accounts.pauseAccount or Accounts.unpauseAccount
    local ok, result = fn({ username = target }, adminAuthResult(username))
    if not ok then
        local code = result
        local friendly
        if code == constants.ERROR.ACCOUNT_NOT_FOUND then
            friendly = "'" .. tostring(target) .. "' does not have an account."
        elseif code == constants.ERROR.PERMISSION_DENIED then
            friendly = "You cannot " .. action .. " that account."
        else
            friendly = (action .. " failed: ") .. tostring(code)
        end
        Toast.sendMessage(username, friendly)
        print(("[SRV][CHAT] admin %s %s failed for %s: %s"):format(
            action, tostring(username), tostring(target), tostring(code)))
        return
    end

    Toast.sendMessage(username, ("%s account '%s'"):format(
        paused and "Paused" or "Unpaused", tostring(target)))
    print(("[SRV][CHAT] admin %s %s account %s"):format(tostring(username), action, tostring(target)))
end

--- Handle "$bank admin ..." - gate all admin commands behind the admin list.
--- @param username string
--- @param sub      string admin subcommand (may be "")
--- @param args     string
local function handleAdmin(username, sub, args)
    if not M.isAdmin(username) then
        Toast.sendMessage(username, "You don't have permission to use admin commands.")
        print("[SRV][CHAT] non-admin " .. tostring(username) .. " tried an admin command")
        return
    end

    if sub == "help" or sub == "" then
        handleAdminHelp(username)
    elseif sub == "create" then
        handleAdminCreate(username, args)
    elseif sub == "delete" then
        handleAdminDelete(username, args)
    elseif sub == "pause" then
        handleAdminPause(username, args, true)
    elseif sub == "unpause" then
        handleAdminPause(username, args, false)
    else
        Toast.sendMessage(username, "Unknown admin command. Try: bank admin help")
    end
end

-- ---------------------------------- Dispatch --------------------------------- --

--- Entry point called by server.network on every chat event.
--- @param message  string the (already $-stripped) chat message
--- @param username string the player who sent the message
function M.handleChat(message, username)
    if not utils.isNonEmptyString(message) or not utils.isNonEmptyString(username) then
        return
    end
    local cmd = parse(message)
    if not cmd then return end

    if cmd.name == "login" then
        handleLogin(username, cmd.args)
    elseif cmd.name == "help" then
        handleHelp(username)
    elseif cmd.name == "transfer" then
        handleTransfer(username, cmd.args)
    elseif cmd.name == "list" then
        handleList(username)
    elseif cmd.name == "balance" then
        handleBalance(username)
    elseif cmd.name == "admin" then
        handleAdmin(username, cmd.sub, cmd.args)
    end
end

--- Init the chat module.
--- @param protocolInstance table the ServerProtocol instance
function M.init(protocolInstance)
    M.protocol = protocolInstance
    M.loadAdmins()
end

return M
