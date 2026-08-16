-- u dont need a definition for this one.
local Button = require "client.ui.button"
local ScreenManager = require "client.ui.screen_manager"
local Router = require "client.ui.router"
local Net = require "client.ui.net"
local constants = require "shared.constants"
local TextWrap = require "client.ui.textwrap"

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
    local balanceText = "$" .. string.format("%.2f", acct.balance or 0)
    local prefix = lay.width >= 20 and " User: " or ""
    local trailing = " "
    local maxUser = lay.width - #prefix - #balanceText - #trailing
    if maxUser < 1 then
        maxUser = 1
    end
    local username = acct.username or "?"
    if #username > maxUser then
        username = username:sub(1, maxUser)
    end
    local headerText = prefix .. username
    local padding = lay.width - #headerText - #balanceText - #trailing
    if padding < 0 then
        padding = 0
    end
    mon.write(headerText .. string.rep(" ", padding) .. balanceText .. trailing)
    mon.setBackgroundColor(colors.black)

    -- Status message
    if message then
        mon.setTextColor(colors.yellow)
        TextWrap.write(mon, message, 2, 2)
    end

    -- Buttons
    local btnW = 12
    local btnH = 3
    local row1 = 5
    local centerX = math.floor(lay.width / 2)
    local centered = centerX - math.floor(btnW / 2)

    local depositCb = function()
        Router.switch(state.screens.deposit, acct)
    end
    local transferCb = function()
        Router.switch(state.screens.transfer, acct)
    end
    local withdrawCb = function()
        Router.switch(state.screens.withdraw, acct)
    end

    if lay.width >= (btnW * 2) + 6 then
        -- Wide: Deposit + Transfer side by side, Withdraw below
        ScreenManager.register(Button.new(centered, row1, centered + btnW - 1, row1 + btnH - 1, "  Deposit   ", depositCb, {
            bg = colors.green, fg = colors.white
        })):draw(mon)

        ScreenManager.register(Button.new(centered + btnW + 2, row1, centered + btnW + 2 + btnW - 1, row1 + btnH - 1, " Transfer   ", transferCb, {
            bg = colors.orange, fg = colors.white
        })):draw(mon)

        ScreenManager.register(Button.new(centered, row1 + btnH + 1, centered + btnW - 1, row1 + btnH + btnH, " Withdraw   ", withdrawCb, {
            bg = colors.red, fg = colors.white
        })):draw(mon)
    else
        -- Narrow: stack the three vertically
        local gap = 1
        ScreenManager.register(Button.new(centered, row1, centered + btnW - 1, row1 + btnH - 1, "  Deposit   ", depositCb, {
            bg = colors.green, fg = colors.white
        })):draw(mon)

        ScreenManager.register(Button.new(centered, row1 + btnH + gap, centered + btnW - 1, row1 + btnH + gap + btnH - 1, " Transfer   ", transferCb, {
            bg = colors.orange, fg = colors.white
        })):draw(mon)

        ScreenManager.register(Button.new(centered, row1 + 2 * (btnH + gap), centered + btnW - 1, row1 + 2 * (btnH + gap) + btnH - 1, " Withdraw   ", withdrawCb, {
            bg = colors.red, fg = colors.white
        })):draw(mon)
    end

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
            Router.switch(state.screens.rest)
        end, {
            bg = colors.gray,
            fg = colors.white
        })):draw(mon)

    -- Admin buttons
    if isAdmin then
        ScreenManager.register(Button.new(2, bottomY, 2 + logoutW, bottomY, "   Admin   ", function()
            Router.switch(state.screens.deposit, acct)
        end, {
            bg = colors.purple,
            fg = colors.white
        })):draw(mon)
    end
end
return MainMenu
