if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local constants = require "shared.constants"

local ME = {}

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

--- Count one coin denomination currently in the ME network.
--- @return number count
--- @return string|nil error
function ME.getCoinCount(me, coinId)
    if not ME.isConnected(me) then return 0, constants.ERROR.ME_NOT_CONNECTED end
    local ok, item, err = pcall(function()
        return me.getItem({ name = coinId })
    end)
    if not ok then return 0, tostring(item) end
    if err then return 0, tostring(err) end
    if type(item) == "table" and type(item.count) == "number" then
        return item.count, nil
    end
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
            elseif ok and err == nil and type(got) == "number" then
                errors[coinId] = "import returned 0 (check AE2 power, storage cell space, channels, or item id)"
            else
                errors[coinId] = (err and tostring(err)) or tostring(got) or constants.ERROR.ME_IMPORT_FAILED
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
            else
                errors[coinId] = (err and tostring(err)) or tostring(got) or "EXPORT_FAILED"
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
    if not me then return 0, constants.ERROR.NO_ME_BRIDGE end
    if not ME.isConnected(me) then return 0, constants.ERROR.ME_NOT_CONNECTED end

    local verifiedValue = 0
    for _, coinId in ipairs(constants.COIN_ORDER) do
        local need = required and required[coinId] or 0
        if type(need) == "number" and need > 0 then
            local have, err = ME.getCoinCount(me, coinId)
            if err then return 0, err end
            if have < need then
                return 0, constants.ERROR.COINS_NOT_FOUND
            end
            verifiedValue = verifiedValue + need * (constants.COIN_VALUES[coinId] or 0)
        end
    end

    return verifiedValue, nil
end

return ME
