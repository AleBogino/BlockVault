-- u dont need a definition for this one.
local Button = require "client.ui.button"
local ScreenManager = require "client.ui.screen_manager"
local Router = require "client.ui.router"
local constants = require "shared.constants"
local Draw = require "client.ui.draw"

local MainMenu = {}

--- Draw da screen
--- @param state table shared state
--- @param acct table { username, balance, id, permission,  ...}
--- @param message? string optional status message
function MainMenu.draw(state, acct, message)
    local mon = state.monitor
    local lay = state.layout

    Draw.clear(mon)

    -- Header
    local balanceText = "$" .. string.format("%.2f", acct.balance or 0)
    local prefix = lay.width >= 20 and " User: " or ""
    local maxUser = lay.width - #prefix
    if maxUser < 1 then
        maxUser = 1
    end
    local username = Draw.truncate(acct.username or "?", maxUser)
    balanceText = Draw.truncate(balanceText, lay.width)

    mon.setBackgroundColor(colors.blue)
    mon.setTextColor(colors.white)
    Draw.fillLine(mon, 1, lay.width, { bg = colors.blue })
    Draw.fillLine(mon, 2, lay.width, { bg = colors.blue })
    mon.setCursorPos(1, 1)
    mon.write(prefix .. username)
    mon.setCursorPos(1, 2)
    mon.write(balanceText)
    mon.setBackgroundColor(colors.black)

    -- Status message
    if message then
        Draw.banner(mon, message, 2, 3)
    end

    -- Buttons
    local btnW = 13
    local btnH = 3
    local row1 = 8
    local centered = math.floor((lay.width - btnW) / 2) + 1

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
        ScreenManager.register(Button.new(centered, row1, centered + btnW - 1, row1 + btnH - 1, "  Deposit   ",
            depositCb, {
                bg = colors.green,
                fg = colors.white
            })):draw(mon)

        ScreenManager.register(Button.new(centered + btnW + 2, row1, centered + btnW + 2 + btnW - 1, row1 + btnH - 1,
            " Transfer   ", transferCb, {
                bg = colors.orange,
                fg = colors.white
            })):draw(mon)

        ScreenManager.register(Button.new(centered, row1 + btnH + 1, centered + btnW - 1, row1 + btnH + btnH,
            " Withdraw   ", withdrawCb, {
                bg = colors.red,
                fg = colors.white
            })):draw(mon)
    else
        -- Narrow: stack the three vertically
        local gap = 1
        ScreenManager.register(Button.new(centered, row1, centered + btnW - 1, row1 + btnH - 1, "  Deposit   ",
            depositCb, {
                bg = colors.green,
                fg = colors.white
            })):draw(mon)

        ScreenManager.register(Button.new(centered, row1 + btnH + gap, centered + btnW - 1,
            row1 + btnH + gap + btnH - 1, " Transfer   ", transferCb, {
                bg = colors.orange,
                fg = colors.white
            })):draw(mon)

        ScreenManager.register(Button.new(centered, row1 + 2 * (btnH + gap), centered + btnW - 1,
            row1 + 2 * (btnH + gap) + btnH - 1, " Withdraw   ", withdrawCb, {
                bg = colors.red,
                fg = colors.white
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
