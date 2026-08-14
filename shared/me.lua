if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local constants = require "shared.constants"

local ME = {}

-- DEBUG TEMP
local function dump(v)
    if v == nil then return "nil" end
    local ok, s = pcall(textutils.serialize, v)
    if ok then return s end
    return tostring(v)
end

function ME.wrap(name)
    if not name then return nil end
    local ok, me = pcall(peripheral.wrap, name)
    if ok and type(me) == "table" then return me end
    return nil
end

function ME.isConnected(me)
    if not me then return false end
    local ok, res = pcall(function() return me.isConnected() end)
    return ok == true and res == true
end

function ME.isOnline(me)
    if not me then return false end
    local ok, res = pcall(function() return me.isOnline() end)
    return ok == true and res == true
end

function ME.getAvailableItemStorage(me)
    if not me then return 0 end
    local ok, res = pcall(function() return me.getAvailableItemStorage() end)
    if ok and type(res) == "number" then return res end
    return 0
end

--- Extract stack size from an AP ME Bridge item table.
local function itemAmount(stack)
    if type(stack) ~= "table" then return nil end
    if type(stack.count) == "number" then return stack.count end
    if type(stack.amount) == "number" then return stack.amount end
    return nil
end

--- Count one coin denomination currently in the ME network.
--- @return number count
--- @return string|nil error
function ME.getCoinCount(me, coinId)
    if not ME.isConnected(me) then
        print("[ME] getCoinCount(" .. tostring(coinId) .. "): not connected")
        return 0, constants.ERROR.ME_NOT_CONNECTED
    end
    local ok, item, err = pcall(function()
        return me.getItem({ name = coinId })
    end)
    if not ok then
        print("[ME] getCoinCount(" .. tostring(coinId) .. ") pcall error: " .. tostring(item))
        return 0, constants.ERROR.ME_READ_FAILED
    end
    if err then
        print("[ME] getCoinCount(" .. tostring(coinId) .. ") error: " .. tostring(err))
        return 0, constants.ERROR.ME_READ_FAILED
    end
    local n = itemAmount(item)
    if n ~= nil then
        return n, nil
    end
    if type(item) == "table" and item[1] ~= nil then
        local total = 0
        for _, stack in ipairs(item) do
            local c = itemAmount(stack)
            if c ~= nil then total = total + c end
        end
        return total, nil
    end
    print("[ME] getCoinCount(" .. tostring(coinId) .. ") unexpected result: " .. dump(item))
    return 0, nil
end

--- All configured denominations currently in the ME network.
--- @return table { [coinId] = count }
function ME.listCoins(me)
    local out = {}
    for _, coinId in ipairs(constants.COIN_ORDER) do
        local n = ME.getCoinCount(me, coinId)
        if type(n) == "number" and n > 0 then
            out[coinId] = n
        end
    end
    return out
end

--- Import `wanted` coin counts from the inventory on `side` of the ME Bridge.
--- `side` is an absolute direction: "north", "south", "east", "west", "up", "down".
--- @param side string direction of the deposit barrel relative to the ME Bridge
--- @param wanted table { [coinId] = count }
--- @return table imported   { [coinId] = actualCountImported }
--- @return number totalValue
--- @return table errors     { [coinId] = errorString }
function ME.importCoins(me, side, wanted)
    local imported, errors = {}, {}
    local totalValue = 0

    for _, coinId in ipairs(constants.COIN_ORDER) do
        local want = wanted and wanted[coinId] or 0
        if type(want) == "number" and want > 0 then
            local value = constants.COIN_VALUES[coinId] or 0
            local ok, got, err = pcall(function()
                return me.importItem({ name = coinId, count = want }, side)
            end)
            if ok and err == nil and type(got) == "number" and got > 0 then
                imported[coinId] = got
                totalValue = totalValue + got * value
                print(("[ME] importCoins %s: wanted=%d imported=%d"):format(coinId, want, got))
            elseif ok and err == nil and type(got) == "number" then
                errors[coinId] = constants.ERROR.ME_IMPORT_FAILED
                print(("[ME] importCoins %s: import returned 0 (side=%s)"):format(coinId, tostring(side)))
            else
                errors[coinId] = constants.ERROR.ME_IMPORT_FAILED
                print(("[ME] importCoins %s: %s"):format(coinId, (err and tostring(err)) or tostring(got)))
            end
        end
    end

    return imported, totalValue, errors
end

--- Export `counts` back out of the ME network into the inventory on `side` (rollback).
--- @param side string direction of the deposit barrel relative to the ME Bridge
--- @return table exported { [coinId] = actualCountExported }
--- @return number totalValue
--- @return table errors
function ME.exportCoins(me, side, counts)
    local exported, errors = {}, {}
    local totalValue = 0

    for _, coinId in ipairs(constants.COIN_ORDER) do
        local want = counts and counts[coinId] or 0
        if type(want) == "number" and want > 0 then
            local value = constants.COIN_VALUES[coinId] or 0
            local ok, got, err = pcall(function()
                return me.exportItem({ name = coinId, count = want }, side)
            end)
            if ok and err == nil and type(got) == "number" and got > 0 then
                exported[coinId] = got
                totalValue = totalValue + got * value
                print(("[ME] exportCoins %s: wanted=%d exported=%d"):format(coinId, want, got))
            else
                errors[coinId] = "EXPORT_FAILED"
                print(("[ME] exportCoins %s: %s"):format(coinId, (err and tostring(err)) or tostring(got)))
            end
        end
    end

    return exported, totalValue, errors
end

--- Verify the ME network holds at least `required` of every denomination.
--- @param required table { [coinId] = count }
--- @return number verifiedValue  sum of required values actually present
--- @return string|nil error
function ME.verifyCoins(me, required)
    if not me then
        print("[ME] verifyCoins: no bridge")
        return 0, constants.ERROR.NO_ME_BRIDGE
    end
    if not ME.isConnected(me) then
        print("[ME] verifyCoins: not connected")
        return 0, constants.ERROR.ME_NOT_CONNECTED
    end

    local verifiedValue = 0
    for _, coinId in ipairs(constants.COIN_ORDER) do
        local need = required and required[coinId] or 0
        if type(need) == "number" and need > 0 then
            local have, err = ME.getCoinCount(me, coinId)
            print(("[ME] verifyCoins %s: need=%d have=%s err=%s")
                :format(coinId, need, tostring(have), tostring(err)))
            if err then return 0, err end
            if have < need then
                print(("[ME] verifyCoins %s: INSUFFICIENT (need=%d have=%d)")
                    :format(coinId, need, have))
                return 0, constants.ERROR.COINS_NOT_FOUND
            end
            verifiedValue = verifiedValue + need * (constants.COIN_VALUES[coinId] or 0)
        end
    end

    return verifiedValue, nil
end

return ME
