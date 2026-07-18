-- Utility shit that client and server can share

local M = {}

--- current time (ms) since epoch
function M.now()
    return os.epoch("utc")
end

--- True if 'ts' is within 'windowMs' of the current time
function M.withinSkew(ts, windowMs)
    if type(ts) ~= "number" then return false end
    local delta = M.now() - ts
    if delta < 0 then delta = -delta end
    return delta <= windowMs
end

--- Shallow copy of a table (for building copies of packets/accounts)
function M.shallowCopy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

--- True if 't' is a table that contains all the 'fields' list
function M.hasFields(t, fields)
    if type(t) ~= "table" then return false end
    for _, key in ipairs(fields) do
        if t[key] == nil then return false end
    end
    return true
end

--- True if 'v' is a non empty string
function M.isNonEmptyString(v)
    return type(v) == "string" and #v > 0
end

--- True if 'v' is a finite non negative number
function M.isNonNegativeNumber(v)
    return type(v) == "number" and v >= 0 and v == v and v ~= math.huge
end

--- True if 'needle' appears in 'haystack' (array of strings)
function M.contains(haystack, needle)
    for _, v in ipairs(haystack) do
        if v == needle then return true end
    end
    return false
end

return M