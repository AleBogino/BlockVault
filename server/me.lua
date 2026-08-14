if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local constants = require "shared.constants"
local Peripheral = require "shared.peripheral"
local ME = require "shared.me"

local ServerME = {}
local bridge = nil

function ServerME.init()
    local cat = Peripheral.scan()
    local name = Peripheral.first(cat.meBridges)
    if not name then
        print("WARNING: No ME Bridge found on the server.")
        return false
    end

    bridge = ME.wrap(name)
    if not bridge then
        print("WARNING: Failed to wrap ME Bridge " .. tostring(name))
        return false
    end

    if ME.isConnected(bridge) then
        print("ME Bridge ready: " .. tostring(name))
        return true
    end

    print("WARNING: ME Bridge not connected to an AE2 network: " .. tostring(name))
    bridge = nil
    return false
end

function ServerME.verifyDeposit(required)
    if not bridge then
        return nil, constants.ERROR.NO_ME_BRIDGE
    end
    local value, err = ME.verifyCoins(bridge, required)
    if err then
        return nil, err
    end
    return value, nil
end

return ServerME
