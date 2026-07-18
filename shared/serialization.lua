--wrapper on textutils.serialize 

local M = {}

local serializeFn = textutils.serialize
local unserializeFn = textutils.unserialize

--- Enconde e Lua table to a string
--- @return string | nil enconded (nil on failure)
--- @return string | nil err  (error message on failure, nil on success)
function M.encode(value)
    local ok, result = pcall(serializeFn, value, { compact = true })
    if not ok then
        return nil, "serialize failed: " .. tostring(result)
    end
    return result, nil 
end

--- Decode a string to a Lua table
--- @return any value (nil on failure)
--- @return string | nil err  (error message on failure, nil on success)
function M.decode(str)
    if type(str) ~= "string" then
        return nil, "decode failed: input is not a string"
    end
    local ok, result = pcall(unserializeFn, str)
    if not ok then
        return nil, "unserialize failed: " .. tostring(result)
    end
    if result == nil then
        return nil, "unserialize failed: result is nil (input is fucked)"
    end
    return result, nil
end

return M