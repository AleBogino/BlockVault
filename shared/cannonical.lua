-- stable string encoding between client and server


local M = {}

local function encodeValue(v, seen)
    local t = type(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "nil" then
        return "nil"
    elseif t == "table" then
        seen = seen or {}
        if seen[v] then
            error("canonical.encode: cannot encode a table with cycles")
        end
        seen[v] = true
 
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) < type(b)
        end)
 
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = encodeValue(k, seen) .. "=" .. encodeValue(v[k], seen)
        end
        seen[v] = nil
        return "{" .. table.concat(parts, ",") .. "}"
    else
        error("canonical.encode: cannot encode a " .. t)
    end
end

--- Enconde any plain Lua value into a string
--- El orden de los factores no altera el producto!
function M.encode(value)
    return encodeValue(value, nil)
end
 
return M
