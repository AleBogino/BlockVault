-- Event loop for UI

local ScreenManager = require("client.ui.screen_manager")
local constants = require "shared.constants"

local Router = {
    current = nil,
    state = nil,
}

local INACTIVITY_TIMEOUT = 60  -- seconds
local inactivityTimer = nil

--- Cancel and restart the inactivity timer.
local function resetInactivityTimer()
    if inactivityTimer then
        os.cancelTimer(inactivityTimer)
    end
    inactivityTimer = os.startTimer(INACTIVITY_TIMEOUT)
end

--- Switch to screen
--- @param screenModule table a screen to change to
--- @param ... any extra arguments to pass to the screen
function Router.switch(screenModule, ...)
    ScreenManager.reset()
    Router.current = screenModule
    screenModule.draw(Router.state, ...)
    resetInactivityTimer()
end

--- Main event loop
--- @param state table shared state (clientProtocol, network, monitor, …)
--- @param firstScreen table the screen module to show in the beginning of the flow
function Router.run(state, firstScreen)
    Router.state = state
    Router.switch(firstScreen)

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
            Router.switch(Rest, "Session timed out due to inactivity.")
        end
    end
end

return Router