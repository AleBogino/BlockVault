if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local constants = require "shared.constants"
local Peripheral = require "shared.peripheral"
local ME = require "shared.me"

local ServerME = {}
local bridge = nil
local buffer = nil
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
    else
        bridge = ME.wrap(name)
        if not bridge then
            print("WARNING: Failed to wrap ME Bridge " .. tostring(name))
        elseif ME.isConnected(bridge) then
            print("ME Bridge ready: " .. tostring(name))
        else
            print("WARNING: ME Bridge not connected to an AE2 network: " .. tostring(name))
            bridge = nil
        end
    end
    local bufferName = constants.ME_BUFFER_NAME
    if not bufferName then
        -- Autodetect the dispense barrel
        for _, invName in ipairs(cat.inventories) do
            local ptype = tostring(cat.all[invName] or ""):lower()
            if ptype:find("barrel", 1, true) then
                bufferName = invName
                break
            end
        end
    end
    if bufferName then
        local ok, b = pcall(peripheral.wrap, bufferName)
        if ok and type(b) == "table" and type(b.list) == "function" then
            buffer = b
            print("Dispense buffer ready: " .. tostring(bufferName))
        else
            buffer = nil
            print("WARNING: Dispense buffer not found or not an inventory: " .. tostring(bufferName))
        end
    end

    if bridge then
        return true
    end
    return false
end

--- count coins currently in dispense buffer
local function bufferCoinCounts()
    if not buffer then
        return nil
    end
    local ok, items = pcall(function()
        return buffer.list()
    end)
    if not ok or type(items) ~= "table" then
        print("[SRV][ME] bufferCoinCounts: failed to list buffer contents")
        return nil
    end
    local out = {}
    for _, item in pairs(items) do
        if item and item.name and constants.COIN_VALUES[item.name] then
            local n = item.count or 0
            out[item.name] = (out[item.name] or 0) + n
        end
    end
    return out
end

--- verify an inventory of coins, at least 'required' of each denomination
--- @param counts table { [coinId] = count }
--- @param required table { [coinId] = count }
--- @return number|nil verifiedValue  sum of required values present (nil if short)
local function verifyInventoryCoins(counts, required)
    local verifiedValue = 0
    for _, coinId in ipairs(constants.COIN_ORDER) do
        local need = required and required[coinId] or 0
        if type(need) == "number" and need > 0 then
            local have = counts[coinId] or 0
            if have < need then
                return nil
            end
            verifiedValue = verifiedValue + need * (constants.COIN_VALUES[coinId] or 0)
        end
    end
    return verifiedValue
end

function ServerME.verifyDeposit(required)
    print("[SRV][ME] verifyDeposit required=" .. dump(required))

    -- Deposited coins land in the dispense buffer
    local counts = bufferCoinCounts()
    if counts then
        local value = verifyInventoryCoins(counts, required)
        if not value then
            print("[SRV][ME] verifyDeposit FAILED: coins not in buffer")
            return nil, constants.ERROR.COINS_NOT_FOUND
        end
        print("[SRV][ME] verifyDeposit OK value=" .. tostring(value))
        return value, nil
    end

    if not bridge then
        print("[SRV][ME] verifyDeposit: no bridge configured")
        return nil, constants.ERROR.NO_ME_BRIDGE
    end

    local side = constants.ME_BUFFER_SIDE
    local pulled, _, perr = ME.importCoins(bridge, side, required)
    for _, coinId in ipairs(constants.COIN_ORDER) do
        local need = required and required[coinId] or 0
        if type(need) == "number" and need > 0 and (pulled[coinId] or 0) < need then
            print(("[SRV][ME] verifyDeposit FAILED: %s need=%d pulled=%d (%s)"):format(
                coinId, need, pulled[coinId] or 0, tostring(perr and perr[coinId])))
            if next(pulled) then
                ME.exportCoins(bridge, side, pulled)
            end
            return nil, constants.ERROR.COINS_NOT_FOUND
        end
    end

    local verifiedValue = 0
    for _, coinId in ipairs(constants.COIN_ORDER) do
        local need = required and required[coinId] or 0
        if type(need) == "number" and need > 0 then
            verifiedValue = verifiedValue + need * (constants.COIN_VALUES[coinId] or 0)
        end
    end

    print("[SRV][ME] verifyDeposit OK value=" .. tostring(verifiedValue) .. " pulled=" .. dump(pulled))
    return verifiedValue, nil
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

--- Net-available coins (subtracts the reservation ledger).
local function netListCoins()
    if not bridge then return {} end
    return netAvailable(ME.listCoins(bridge))
end

--- Try to make exact change from what the vault currently holds.
local function tryBreakdown(target)
    return ME.makeChange(target, netListCoins())
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

--- Push approved withdrawal into dispense buffer
--- @param breakdown table { [coinId] = count }
--- @return boolean ok
function ServerME.stageWithdrawal(breakdown)
    if not bridge then
        print("[SRV][ME] stageWithdrawal: no bridge configured")
        return false
    end
    local side = constants.ME_BUFFER_SIDE
    local exported, totalValue, errors = ME.exportCoins(bridge, side, breakdown)
    if errors and next(errors) then
        print(("[SRV][ME] stageWithdrawal: export errors %s - rolling back partial stage"):format(dump(errors)))
        if exported and next(exported) then
            ME.importCoins(bridge, side, exported)
        end
        return false
    end
    print(("[SRV][ME] stageWithdrawal: staged %s (%d units) into buffer"):format(dump(exported), totalValue or 0))
    return true
end

--- Take every coin out of dispense buffer back into the vault
--- @return table|nil swept { [coinId] = count }
function ServerME.sweepBuffer(breakdown)
    if not bridge then
        return nil
    end
    local counts = bufferCoinCounts()
    if not counts then
        counts = breakdown
    end
    if not counts or not next(counts) then
        return {}
    end
    local side = constants.ME_BUFFER_SIDE
    local swept, _, errors = ME.importCoins(bridge, side, counts)
    if errors and next(errors) then
        print(("[SRV][ME] sweepBuffer: import errors %s"):format(dump(errors)))
    end
    print(("[SRV][ME] sweepBuffer: swept %s"):format(dump(swept)))
    return swept
end

--- Coin breakdown for a target value, crafting missing coins when needed.
--- @return table|nil breakdown { [coinId] = count }
--- @return string|nil error
function ServerME.coinBreakdown(target)
    if not bridge then
        print("[SRV][ME] coinBreakdown: no bridge configured")
        return nil, constants.ERROR.NO_ME_BRIDGE
    end

    local breakdown = tryBreakdown(target)
    if breakdown then
        return breakdown, nil
    end

    if not constants.CRAFT_ENABLED then
        print(("[SRV][ME] coinBreakdown: cannot make exact change for %d and crafting disabled"):format(target))
        return nil, constants.ERROR.COINS_NOT_FOUND
    end

    local deadline = os.epoch("utc") + constants.CRAFT_TIMEOUT_MS
    local cpu = ME.pickCraftingCpu(bridge)

    for attemptNo = 1, 3 do
        local plan = ME.planChange(target, netListCoins())
        if not plan or not next(plan) then
            print(("[SRV][ME] coinBreakdown: no craft plan for %d"):format(target))
            return nil, constants.ERROR.COINS_NOT_FOUND
        end

        -- Always re-check live stock before requesting a craft.
        local issued = false
        for _, coinId in ipairs(constants.COIN_ORDER) do
            local want = plan[coinId]
            if want and want > 0 then
                local have, rerr = ME.getCoinCount(bridge, coinId)
                if rerr then
                    print(("[SRV][ME] coinBreakdown: read failed for %s: %s"):format(coinId, tostring(rerr)))
                    return nil, constants.ERROR.ME_READ_FAILED
                end
                if have < want then
                    if not ME.isCoinCraftable(bridge, coinId) then
                        print(("[SRV][ME] coinBreakdown: %s not craftable"):format(coinId))
                        return nil, constants.ERROR.ME_CRAFT_UNAVAILABLE
                    end
                    local ok, err = ME.craftItem(bridge, coinId, want, cpu)
                    if not ok then
                        print(("[SRV][ME] coinBreakdown: craft %s x%d failed: %s"):format(coinId, want, tostring(err)))
                        return nil, constants.ERROR.ME_CRAFT_FAILED
                    end
                    print(("[SRV][ME] coinBreakdown: requested %s x%d (attempt %d)"):format(coinId, want, attemptNo))
                    issued = true
                end
            end
        end

        if not issued then
            return nil, constants.ERROR.ME_CRAFT_FAILED
        end

        -- Wait for the crafted coins to land
        while os.epoch("utc") < deadline do
            local allOk = true
            for coinId, want in pairs(plan) do
                local have = ME.getCoinCount(bridge, coinId)
                if have < want then
                    allOk = false
                end
            end
            if allOk then
                break
            end
            os.sleep(constants.CRAFT_POLL_MS / 1000)
        end

        local b = tryBreakdown(target)
        if b then
            print(("[SRV][ME] coinBreakdown: crafted change for %d"):format(target))
            return b, nil
        end
        if os.epoch("utc") >= deadline then
            print(("[SRV][ME] coinBreakdown: crafting timed out for %d"):format(target))
            return nil, constants.ERROR.ME_CRAFT_TIMEOUT
        end
    end

    print(("[SRV][ME] coinBreakdown: giving up on %d after 3 craft attempts"):format(target))
    return nil, constants.ERROR.COINS_NOT_FOUND
end

--- keep CRAFT_STOCK_TARGET of every denomination except netherite
function ServerME.maintainStock()
    if not bridge or not constants.CRAFT_ENABLED then
        return
    end

    local denoms = ME.denominations()          -- zinc..netherite
    local available = ME.listCoins(bridge)
    local target = constants.CRAFT_STOCK_TARGET

    for i = 1, #denoms do
        if ME.isCrafting(bridge, denoms[i]) then
            return
        end
    end

    -- Most-depleted small denomination
    local bestIdx = nil
    for i = 1, #denoms - 1 do
        local have = available[denoms[i]] or 0
        if have < target then
            if not bestIdx or have < (available[denoms[bestIdx]] or 0) then
                bestIdx = i
            end
        end
    end
    if not bestIdx then
        return
    end

    local cpu = ME.pickCraftingCpu(bridge)
    local coinId = denoms[bestIdx]

    -- 1) Split down from the nearest surplus above (one 1->9 recipe).
    for j = bestIdx + 1, #denoms do
        if (available[denoms[j]] or 0) > target then
            local ok, err = ME.craftItem(bridge, coinId, 9, cpu)
            if ok then
                print(("[SRV][ME] maintainStock: split %s -> 9x %s"):format(denoms[j], coinId))
            else
                print(("[SRV][ME] maintainStock: split into %s failed: %s"):format(coinId, tostring(err)))
            end
            return
        end
    end

    -- 2) Combine up from the next smaller denomination (9 -> 1).
    if bestIdx > 1 and (available[denoms[bestIdx - 1]] or 0) >= target + 9 then
        local ok, err = ME.craftItem(bridge, coinId, 1, cpu)
        if ok then
            print(("[SRV][ME] maintainStock: combined 9x %s -> 1x %s"):format(denoms[bestIdx - 1], coinId))
        else
            print(("[SRV][ME] maintainStock: combine into %s failed: %s"):format(coinId, tostring(err)))
        end
    end
end

return ServerME
