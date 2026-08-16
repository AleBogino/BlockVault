local Peripheral = {}

local function isInventory(name)
    local ok = pcall(peripheral.call, name, "list")
    return ok == true
end

--- Scan attached peripherals
--- @return table { all=map, inventories=string[], meBridges=string[], modems=string[], wireless=string[], wired=string[], monitors=string[] }
function Peripheral.scan()
    local cat = {
        all         = {},
        inventories = {},
        meBridges   = {},
        modems      = {},
        wireless    = {},
        wired       = {},
        monitors    = {},
    }

    for _, name in ipairs(peripheral.getNames()) do
        local ptype = peripheral.getType(name)
        cat.all[name] = ptype

        if ptype == "modem" then
            table.insert(cat.modems, name)
            local ok, isWireless = pcall(peripheral.call, name, "isWireless")
            if ok and isWireless then
                table.insert(cat.wireless, name)
            else
                table.insert(cat.wired, name)
            end
        elseif ptype == "monitor" then
            table.insert(cat.monitors, name)
        elseif ptype == "meBridge" then
            table.insert(cat.meBridges, name)
        end

        if isInventory(name) then
            table.insert(cat.inventories, name)
        end
    end

    return cat
end

--- Pick the modem to use for rednet: always wireless.
--- @param cat table result from Peripheral.scan()
--- @return string|nil wireless modem side name
function Peripheral.pickModem(cat)
    if cat and cat.wireless and #cat.wireless > 0 then
        return cat.wireless[1]
    end
    return nil
end

function Peripheral.first(list)
    if list and #list > 0 then return list[1] end
    return nil
end

return Peripheral