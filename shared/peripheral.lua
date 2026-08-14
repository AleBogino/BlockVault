local Peripheral = {}

local function isInventory(name)
    local ok = pcall(peripheral.call, name, "list")
    return ok == true
end

--- Scan attached peripherals
--- @return table { all=map, inventories=string[], meBridges=string[], modems=string[], monitors=string[] }
function Peripheral.scan()
    local cat = {
        all        = {},
        inventories = {},
        meBridges  = {},
        modems     = {},
        monitors   = {},
    }

    for _, name in ipairs(peripheral.getNames()) do
        local ptype = peripheral.getType(name)
        cat.all[name] = ptype

        if ptype == "modem" then
            table.insert(cat.modems, name)
        elseif ptype == "monitor" then
            table.insert(cat.monitors, name)
        elseif ptype == "me_bridge" then
            table.insert(cat.meBridges, name)
        end

        if isInventory(name) then
            table.insert(cat.inventories, name)
        end
    end

    return cat
end

function Peripheral.first(list)
    if list and #list > 0 then return list[1] end
    return nil
end

return Peripheral