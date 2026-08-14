if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local constants = require "shared.constants"
local Peripheral = require "shared.peripheral"
local ME = require "shared.me"

local ServerME = {}
local bridge = nil

-- DEBUG TEMP
local function dump(v)
    if v == nil then return "nil" end
    local ok, s = pcall(textutils.serialize, v)
    if ok then return s end
    return tostring(v)
end

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
        print("[SRV][ME] verifyDeposit: no bridge configured")
        return nil, constants.ERROR.NO_ME_BRIDGE
    end
    print("[SRV][ME] verifyDeposit required=" .. dump(required))
    local value, err = ME.verifyCoins(bridge, required)
    if err then
        print("[SRV][ME] verifyDeposit FAILED: " .. tostring(err))
        return nil, err
    end
    print("[SRV][ME] verifyDeposit OK value=" .. tostring(value))
    return value, nil
end

return ServerME
