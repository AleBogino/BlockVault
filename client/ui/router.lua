-- Event loop for UI

local ScreenManager = require("client.ui.screen_manager")
local Layout = require "client.ui.layout"
local constants = require "shared.constants"

local Router = {
    current = nil,
    state = nil,
    drawArgs = nil,
}

local INACTIVITY_TIMEOUT = 60  -- seconds
local REDRAW_INTERVAL = 2      -- seconds
local inactivityTimer = nil
local redrawTimer = nil

--- Cancel and restart the inactivity timer.
local function resetInactivityTimer()
    if inactivityTimer then
        os.cancelTimer(inactivityTimer)
    end
    inactivityTimer = os.startTimer(INACTIVITY_TIMEOUT)
end

--- Re-validate monitor and redraw screen
function Router.redraw()
    local state = Router.state
    if not state or not Router.current then
        return
    end

    local m = state.refreshMonitor and state.refreshMonitor() or state.monitor
    if not m then
        return
    end

    state.monitor = m
    local ok, lay = pcall(Layout.compute, m)
    if ok then
        state.layout = lay
    end

    ScreenManager.reset()
    local args = Router.drawArgs or table.pack()
    pcall(Router.current.draw, state, table.unpack(args, 1, args.n or #args))
end

--- Switch to screen
--- @param screenModule table a screen to change to
--- @param ... any extra arguments to pass to the screen
function Router.switch(screenModule, ...)
    ScreenManager.reset()
    Router.current = screenModule
    Router.drawArgs = table.pack(...)

    if Router.state and Router.state.monitor then
        local ok, lay = pcall(Layout.compute, Router.state.monitor)
        if ok then
            Router.state.layout = lay
        end
    end

    screenModule.draw(Router.state, ...)
    resetInactivityTimer()
end

--- Main event loop
--- @param state table shared state (clientProtocol, network, monitor, …)
--- @param firstScreen table the screen module to show in the beginning of the flow
function Router.run(state, firstScreen)
    Router.state = state
    Router.switch(firstScreen)

    redrawTimer = os.startTimer(REDRAW_INTERVAL)

    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" then
            ScreenManager.dispatch(p2, p3)
            resetInactivityTimer()
        elseif event == "timer" and p1 == inactivityTimer then
            -- Inactivity timeout: log out and return to rest screen
            local session = state.clientProtocol.session
            if session then
                local pkt = session:send(
                    constants.PACKET.DISCONNECT,
                    state.myId, state.sk, state.pk, {}
                )
                state.network.send(state.serverId, pkt)
            end
            local Rest = require "client.ui.screens.rest"
            Router.switch(Rest)
            Rest.showMessage(state, "Session timed out.")
        elseif event == "timer" and p1 == redrawTimer then
            Router.redraw()
            redrawTimer = os.startTimer(REDRAW_INTERVAL)
        elseif event == "monitor_resize" then
            Router.redraw()
        end
    end
end

return Router