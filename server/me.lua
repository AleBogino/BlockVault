if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local constants = require "shared.constants"
local Peripheral = require "shared.peripheral"
local ME = require "shared.me"

local ServerME = {}
local bridge = nil
local reserved = {}

-- DEBUG TEMP
local function dump(v)
    if v == nil then
        return "nil"
    end
    local ok, s = pcall(textutils.serialize, v)
    if ok then
        return s
    end
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

--- Check if the network hast at least 'required' of every denomination
--- @return number | nil verifiedValue
--- @return string | nil error
function ServerME.verifyAvailable(required)
    if not bridge then
        print("[SRV][ME] verifyAvailable: no bridge configured")
        return nil, constants.ERROR.NO_ME_BRIDGE
    end
    return ME.verifyCoins(bridge, required)
end

--- Subtract currently reserved coins from available
local function netAvailable(available)
    local net = {}
    for coinId, count in pairs(available) do
        net[coinId] = count
    end
    for coinId, count in pairs(reserved) do
        local left = (net[coinId] or 0) - count
        if left > 0 then
            net[coinId] = left
        else
            net[coinId] = nil
        end
    end
    return net
end

--- Add breakdown to reserved coins
function ServerME.reserve(breakdown)
    for coinId, count in pairs(breakdown or {}) do
        if type(count) == "number" and count > 0 then
            reserved[coinId] = (reserved[coinId] or 0) + count
        end
    end
end

--- Remove breakdown from reserved coins
function ServerME.release(breakdown)
    for coinId, count in pairs(breakdown or {}) do
        if type(count) == "number" and count > 0 then
            local left = (reserved[coinId] or 0) - count
            if left > 0 then
                reserved[coinId] = left
            else
                reserved[coinId] = nil
            end
        end
    end
end

--- Debug reserved coins
function ServerME.getReserved()
    local copy = {}
    for coinId, count in pairs(reserved) do
        copy[coinId] = count
    end
    return copy
end

--- Coin breakdown for a target value (using what we have)
function ServerME.coinBreakdown(target)
    if not bridge then
        print("[SRV][ME] coinBreakdown: no bridge configured")
        return nil, constants.ERROR.NO_ME_BRIDGE
    end
    local available = ME.listCoins(bridge)
    local net = netAvailable(available)
    local breakdown = ME.makeChange(target, net)
    if not breakdown then
        print(("[SRV][ME] coinBreakdown: cannot make exact change for %d (available=%s reserved=%s)"):format(target,
            dump(net), dump(reserved)))
        return nil, constants.ERROR.COINS_NOT_FOUND
    end
    return breakdown, nil
end

return ServerME
