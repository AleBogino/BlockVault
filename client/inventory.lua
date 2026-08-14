if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local constants = require "shared.constants"

local Inventory = {}
Inventory.__index = Inventory

--- @param barrelName string name of the barrel
--- @return table|nil self
--- @return string|nil error
function Inventory.new(barrelName)
    local self = setmetatable({}, Inventory)
    self.name = barrelName
    local ok, inv = pcall(peripheral.wrap, barrelName)
    if not ok or not inv or not inv.list then
        return nil, "barrel is not a valid inventory"
    end
    self.inv = inv
    return self, nil
end

--- Scan the barrel for recognized coins.
--- @return number total        total value in account units
--- @return table breakdown    { [coinId] = count }
--- @return string|nil error
function Inventory:scan()
    local ok, items = pcall(function()
        return self.inv.list()
    end)
    if not ok then
        return 0, {}, "failed to read barrel"
    end

    local breakdown, total = {}, 0
    for _, item in pairs(items) do
        if item and item.name and constants.COIN_VALUES[item.name] then
            local count = item.count or 0
            breakdown[item.name] = (breakdown[item.name] or 0) + count
            total = total + count * constants.COIN_VALUES[item.name]
        end
    end

    return total, breakdown, nil
end

return Inventory
