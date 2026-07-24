-- u dont need a definition for this one.
local Button = require "client.ui.button"
local ScreenManager = require "client.ui.screen_manager"
local Router = require "client.ui.router"
local Net = require "client.ui.net"
local constants = require "shared.constants"

local Rest = require "client.ui.screens.rest"
local Deposit = require "client.ui.screens.deposit"
local Withdraw = require "client.ui.screens.withdraw"
local Transfer = require "client.ui.screens.transfer"

local MainMenu = {}

--- Draw da screen
--- @param state table shared state
--- @param acct table { username, balance, id, permission,  ...}
--- @param message? string optional status message
function MainMenu.draw(state, acct, message)
    local mon = state.monitor
    local lay = state.layout

    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Header
    mon.setBackgroundColor(colors.blue)
    mon.setTextColor(colors.white)
    mon.setCursorPos(1, 1)
    local headerText = " User: " .. (acct.username or "?")
    local balanceText = "$" .. string.format("%.2f", acct.balance or 0)
    local padding = lay.width - #headerText - #balanceText - 2
    if padding < 1 then
        padding = 1
    end
    mon.write(headerText .. string.rep(" ", padding) .. balanceText .. " ")
    mon.setBackgroundColor(colors.black)

    -- Status message
    if message then
        mon.setTextColor(colors.yellow)
        mon.setCursorPos(2, 2)
        mon.write(message:sub(1, lay.width - 2))
    end

    -- Buttons
    local btnW = 12
    local btnH = 3
    local row1 = 5
    local row2 = 10
    local centerX = math.floor(lay.width / 2)

    -- Deposit button
    local depX = centerX - math.floor(btnW / 2)
    ScreenManager.register(Button.new(depX, row1, depX + btnW - 1, row1 + btnH - 1, "  Deposit   ", function()
        Router.switch(Deposit, acct)
    end, {
        bg = colors.green,
        fg = colors.white
    })):draw(mon)

    -- Transfer button
    local trX = depX + btnW + 2
    ScreenManager.register(Button.new(trX, row1, trX + btnW - 1, row1 + btnH - 1, " Transfer   ", function()
        Router.switch(Transfer, acct)
    end, {
        bg = colors.orange,
        fg = colors.white
    })):draw(mon)

    -- Withdraw button
    local witX = centerX - math.floor(btnW / 2)
    ScreenManager.register(Button.new(witX, row1 + btnH + 1, witX + btnW - 1, row1 + btnH + btnH, " Withdraw   ",
        function()
            Router.switch(Withdraw, acct)
        end, {
            bg = colors.red,
            fg = colors.white
        })):draw(mon)

    -- Is admin?
    local isAdmin = (acct.permission == constants.PERMISSION.ADMIN or acct.permission == constants.PERMISSION.SYSTEM)
    local bottomY = lay.height - 2

    -- Logout
    local logoutW = 10
    ScreenManager.register(Button.new(lay.width - logoutW - 1, bottomY, lay.width - 2, bottomY, "  Logout  ",
        function()
            -- Send DISCONNECT packet (best-effort, don't block on response)
            local session = state.clientProtocol.session
            if session then
                local pkt = session:send(constants.PACKET.DISCONNECT, state.myId, state.sk, state.pk, {})
                state.network.send(state.serverId, pkt)
            end
            Router.switch(Rest)
        end, {
            bg = colors.gray,
            fg = colors.white
        })):draw(mon)

    -- Admin buttons
    if isAdmin then
        ScreenManager.register(Button.new(2, bottomY, 2 + logoutW, bottomY, "   Admin   ", function()
            Router.switch(Deposit, acct)
        end, {
            bg = colors.purple,
            fg = colors.white
        })):draw(mon)
    end
end
return MainMenu
