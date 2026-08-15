-- Withdraw screen: amount entry via keypad
local ScreenManager = require "client.ui.screen_manager"
local Router = require "client.ui.router"
local Net = require "client.ui.net"
local Keypad = require "client.ui.keypad"
local constants = require "shared.constants"
local ME = require "shared.me"

local MainMenu = require "client.ui.screens.main_menu"

local Withdraw = {}

local function shortName(coinId)
    return coinId:match(":([^:]+)$") or coinId
end

-- coin breakdown approved by server
local function drawReview(state, acct, amount, breakdown)
    local mon = state.monitor
    local lay = state.layout

    mon.setBackgroundColor(colors.black)
    mon.clear()

    mon.setTextColor(colors.cyan)
    mon.setCursorPos(3, lay.headerRow)
    mon.write("Withdraw - Review")

    local y = lay.headerRow + 1
    mon.setTextColor(colors.white)
    mon.setCursorPos(3, y)
    mon.write(("Amount: %d units"):format(amount))
    y = y + 1
    mon.setCursorPos(3, y)
    mon.write("Coins to dispense:")
    y = y + 1

    for _, coinId in ipairs(constants.COIN_ORDER) do
        local n = breakdown and breakdown[coinId]
        if n and n > 0 then
            local value = constants.COIN_VALUES[coinId] or 0
            mon.setCursorPos(3, y)
            mon.write(("%d x %s = %d units"):format(n, shortName(coinId), n * value))
            y = y + 1
        end
    end

    mon.setTextColor(colors.lime)
    mon.setCursorPos(3, y)
    mon.write(("Current balance: %d"):format(acct.balance or 0))
    y = y + 1
    mon.setCursorPos(3, y)
    mon.write(("After withdraw:  %d"):format((acct.balance or 0) - amount))
    y = y + 1

    local btnW = 14
    local bx = math.floor((lay.width - btnW) / 2) + 1

    ScreenManager.register(Button.new(bx, lay.confirmButtonRow - 2, bx + btnW - 1, lay.confirmButtonRow - 2,
        "  Confirm  ", function()
            local me = state.meBridge
            if not me then
                Withdraw.draw(state, acct, nil, "No ME Bridge on this terminal.")
                return
            end

            -- Dispense the coins server provided
            local exported, exportedValue, exportErrs = ME.exportCoins(me, state.meSide, breakdown)

            -- Partial export: rollback
            if exportedValue ~= amount or (exportErrs and next(exportErrs)) then
                if exportedValue and exportedValue > 0 then
                    ME.importCoins(me, state.meSide, exported)
                end
                local why = "Dispense failed"
                if exportErrs and next(exportErrs) then
                    local first = next(exportErrs)
                    why = "Dispense failed: " .. tostring(exportErrs[first])
                end
                Withdraw.draw(state, acct, nil, why .. " - coins returned.")
                return
            end

            -- Confirm to the server = debit the account
            local payload, err = Net.sendAndReceive(state, constants.PACKET.WITHDRAW_CONFIRM, {
                username = acct.username,
                amount = amount,
                coinBreakdown = exported,
            })

            if not payload then
                -- Network error after dispense: try to get the coins back
                ME.importCoins(me, state.meSide, exported)
                Withdraw.draw(state, acct, nil, "Network error - coins returned. " .. tostring(err))
                return
            end

            if not payload.success then
                ME.importCoins(me, state.meSide, exported)
                local code = payload.code or "UNKNOWN"
                Withdraw.draw(state, acct, nil, "Withdraw rejected (" .. code .. ") - coins returned.")
                return
            end

            local newBalance = payload.data.balance
            acct.balance = newBalance
            Router.switch(MainMenu, acct,
                ("Withdrew %d units. New balance: %d"):format(amount, newBalance))
        end, {
            bg = colors.green,
            fg = colors.white
        })):draw(mon)

    ScreenManager.register(Button.new(bx, lay.confirmButtonRow, bx + btnW - 1, lay.confirmButtonRow, "  Cancel  ",
        function()
            Withdraw.draw(state, acct, nil, "Withdraw cancelled.")
        end, {
            bg = colors.gray,
            fg = colors.white
        })):draw(mon)
end

--- Draw it!
--- @param state   table shared state
--- @param acct    table current user account
--- @param target? string username to withdraw from (nil = self)
--- @param message? string optional error/success banner
function Withdraw.draw(state, acct, target, message)
    local mon = state.monitor
    local lay = state.layout

    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- header
    mon.setTextColor(colors.cyan)
    mon.setCursorPos(3, lay.headerRow)
    mon.write("Withdraw")

    local targetUser = target or acct.username
    mon.setTextColor(colors.white)
    mon.setCursorPos(3, lay.headerRow + 1)
    mon.write("From: " .. targetUser)

    -- message
    if message then
        mon.setTextColor(colors.yellow)
        mon.setCursorPos(2, lay.headerRow + 2)
        mon.write(message:sub(1, lay.width - 2))
    end

    state.inputBuffer = ""

    -- keypad
    Keypad.draw(mon, lay, state, {
        fieldLabel = "Amount",
        onConfirm = function()
            local amount = tonumber(state.inputBuffer)
            if not amount or amount <= 0 then
                Withdraw.draw(state, acct, targetUser, "Invalid amount. Enter a positive number.")
                return
            end

            local payload, err = Net.sendAndReceive(state, constants.PACKET.WITHDRAW_REQUEST, {
                username = targetUser,
                amount = amount
            })

            if not payload then
                Withdraw.draw(state, acct, targetUser, "Network error: " .. tostring(err))
                return
            end

            if not payload.success then
                local code = payload.code or "UNKNOWN"
                local friendly
                if code == constants.ERROR.INSUFFICIENT_FUNDS then
                    friendly = "Insufficient funds."
                elseif code == constants.ERROR.COINS_NOT_FOUND then
                    friendly = "Not enough coins in the vault to make exact change."
                elseif code == constants.ERROR.PERMISSION_DENIED then
                    friendly = "You can only withdraw from your own account."
                elseif code == constants.ERROR.ACCOUNT_NOT_FOUND then
                    friendly = "Account '" .. targetUser .. "' not found."
                else
                    friendly = "Error: " .. code
                end
                Withdraw.draw(state, acct, targetUser, friendly)
                return
            end

            -- ??
            drawReview(state, acct, amount, payload.data.breakdown)
        end,
        onCancel = function()
            Router.switch(MainMenu, acct)
        end
    })
end

return Withdraw
