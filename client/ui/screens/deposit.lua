-- Screen to deposit into a player's account (admin only for now)

local Button = require "client.ui.button"
local ScreenManager = require "client.ui.screen_manager"
local Router = require "client.ui.router"
local Net = require "client.ui.net"
local Keypad = require "client.ui.keypad"
local constants = require "shared.constants"

local MainMenu = require "client.ui.screens.main_menu"

local Deposit = {}

--- Draw it!
--- @param state   table shared state
--- @param acct    table current user account
--- @param target? string username to deposit into (nil = self)
--- @param message? string optional error/success banner
function Deposit.draw(state, acct, target, message)
    local mon = state.monitor
    local lay = state.layout

    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- header
        mon.setTextColor(colors.cyan)
    mon.setCursorPos(3, lay.headerRow)
    mon.write("Deposit")

    local targetUser = target or acct.username
    mon.setTextColor(colors.white)
    mon.setCursorPos(3, lay.headerRow + 1)
    mon.write("Into: " .. targetUser)

    -- Message
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
                Deposit.draw(state, acct, targetUser, "Invalid amount. Enter a positive number.")
                return
            end

            local payload, err = Net.sendAndReceive(state, constants.PACKET.DEPOSIT, {
                username = targetUser,
                amount = amount,
            })

            if not payload then
                Deposit.draw(state, acct, targetUser, "Network error: " .. tostring(err))
                return
            end

            if not payload.success then
                local code = payload.code or "UNKNOWN"
                local friendly
                if code == constants.ERROR.PERMISSION_DENIED then
                    friendly = "Permission denied — ADMIN or higher required."
                elseif code == constants.ERROR.ACCOUNT_NOT_FOUND then
                    friendly = "Account '" .. targetUser .. "' not found."
                else
                    friendly = "Error: " .. code
                end
                Deposit.draw(state, acct, targetUser, friendly)
                return
            end

            -- Success!
            local newBalance = payload.data.balance
            local successMsg = "Deposit of $" .. tostring(amount)
                .. " successful! New balance: $" .. tostring(newBalance)
            -- Refresh account data
            acct.balance = newBalance
            Router.switch(MainMenu, acct, successMsg)
        end,
        onCancel = function()
            Router.switch(MainMenu, acct)
        end,
    })
end

return Deposit