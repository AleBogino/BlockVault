-- Touchscreen ui entrypoint
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local Router = require "client.ui.router"
local Layout = require "client.ui.layout"

local Screens = {
    rest      = require "client.ui.screens.rest",
    mainMenu  = require "client.ui.screens.main_menu",
    deposit   = require "client.ui.screens.deposit",
    withdraw  = require "client.ui.screens.withdraw",
    transfer  = require "client.ui.screens.transfer",
}

local UI = {}

--- Start the touchscreen UI.
--- @param state table must include `monitor` and all fields
function UI.run(state)
    if not state.monitor then
        error("BlockBank ATM requires an Advanced Monitor peripheral.")
    end

    state.layout = Layout.compute(state.monitor)
    state.inputBuffer = ""
    state.screens = Screens
    Router.run(state, Screens.rest)
end

return UI