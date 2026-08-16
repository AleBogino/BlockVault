local Peripheral = {}

local function isInventory(name, viaModem)
    if not name then return false end
    local ok, res = pcall(peripheral.call, name, "list")
    if ok and type(res) == "table" then return true end
    if viaModem then
        local ok2, res2 = pcall(peripheral.call, viaModem, "callRemote", name, "list")
        if ok2 and type(res2) == "table" then return true end
    end
    return false
end

local function getTypes(name, viaModem)
    if not name then return {} end
    local ok, a, b, c, d, e = pcall(peripheral.getType, name)
    if ok then
        local types = {}
        for _, t in ipairs({ a, b, c, d, e }) do
            if t ~= nil then types[#types + 1] = t end
        end
        if #types > 0 then return types end
    end
    if viaModem then
        local ok2, t2 = pcall(peripheral.call, viaModem, "getTypeRemote", name)
        if ok2 and t2 ~= nil then return { t2 } end
    end
    return {}
end

local function hasType(name, wanted, viaModem)
    for _, t in ipairs(getTypes(name, viaModem)) do
        if t == wanted then return true end
    end
    return false
end

--- Classify one peripheral, return true if it was newly seen.
local function classify(cat, name, viaModem)
    if not name or cat.seen[name] then return false end
    cat.seen[name] = true

    cat.all[name] = getTypes(name, viaModem)[1]

    if hasType(name, "modem", viaModem) then
        table.insert(cat.modems, name)
        local ok, isWireless = pcall(peripheral.call, name, "isWireless")
        if ok and isWireless then
            table.insert(cat.wireless, name)
        else
            table.insert(cat.wired, name)
        end
    end
    if hasType(name, "monitor", viaModem) then
        table.insert(cat.monitors, name)
    end
    if hasType(name, "meBridge", viaModem) then
        table.insert(cat.meBridges, name)
    end
    if isInventory(name, viaModem) then
        table.insert(cat.inventories, name)
    end

    return true
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
        seen        = {},
    }
    local modemQueue = {}
    for _, name in ipairs(peripheral.getNames()) do
        local isNew = classify(cat, name)
        if isNew and hasType(name, "modem") then
            modemQueue[#modemQueue + 1] = name
        end
    end

    -- Explicitly enumerate remote peripherals
    local idx = 1
    while idx <= #modemQueue do
        local modemName = modemQueue[idx]
        idx = idx + 1

        local ok, remoteNames = pcall(peripheral.call, modemName, "getNamesRemote")
        if ok and type(remoteNames) == "table" then
            for _, rname in ipairs(remoteNames) do
                local isNew = classify(cat, rname, modemName)
                if isNew and hasType(rname, "modem", modemName) then
                    modemQueue[#modemQueue + 1] = rname
                end
            end
        end
    end

    cat.seen = nil
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