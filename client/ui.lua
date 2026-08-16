-- Touchscreen ui entrypoint
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local Router = require "client.ui.router"
local Layout = require "client.ui.layout"

local Screens = {
    rest       = require "client.ui.screens.rest",
    mainMenu   = require "client.ui.screens.main_menu",
    deposit    = require "client.ui.screens.deposit",
    withdraw   = require "client.ui.screens.withdraw",
    transfer   = require "client.ui.screens.transfer",
    fatalError = require "client.ui.screens.fatal_error",
}

local UI = {}

--- Start the touchscreen UI.
--- @param state table must include `monitor` and all fields
function UI.run(state)
    if not state.monitor then
        error("BlockBank ATM requires an Advanced Monitor peripheral.")
    end

    -- pin text scale 0.5
    -- monitor size 15 columns x 24 rows.
    -- monitor borders take 3 pixels horizontally, and 2 pixels vertically. 
    pcall(function() state.monitor.setTextScale(0.5) end)
    state.monitor.setBackgroundColor(colors.black)

    state.layout = Layout.compute(state.monitor)
    state.inputBuffer = ""
    state.screens = Screens
    Router.run(state, Screens.rest)
end

return UI