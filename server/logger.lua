-- Audit log

if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local utils = require "shared.utils"

local AUDIT_FILE = "data/audit.log"
local MAX_LOG_SIZE = 512 * 1024 -- bytes

local Logger = {}

local function ensureDir()
    if not fs.exists("data") then
        fs.makeDir("data")
    end
end

--- Rotate the audit log once it exceeds MAX_LOG_SIZE.
local function rotateIfNeeded()
    local ok, size = pcall(fs.getSize, AUDIT_FILE)
    if not ok or type(size) ~= "number" then
        return
    end
    if size <= MAX_LOG_SIZE then
        return
    end

    local oldPath = AUDIT_FILE .. ".old"
    if fs.exists(oldPath) then
        pcall(fs.delete, oldPath)
    end
    pcall(fs.move, AUDIT_FILE, oldPath)
end


--- Record an entry
--- @param success      boolean   
--- @param packetType   string    "TRANSFER", "CREATE_ACCOUNT", etc
--- @param senderId     number    rednet computer ID of the caller
--- @param username     string|nil  username, nil if not resolved
--- @param details      string    error details
function Logger.log(success, packetType, senderId, username, details)
    ensureDir()

    local entry = {
        timestamp  = utils.now(),
        success    = success,
        type       = packetType,
        sender     = senderId,
    }

    -- Only include fields that actually carry information
    if username ~= nil and username ~= "" then
        entry.username = username
    end
    if details ~= nil and details ~= "" and details ~= "ok" then
        entry.details = details
    end

    local ok, line = pcall(textutils.serialize, entry, { compact = true })
    if not ok then
        return -- nos comemos un pito si falla el serialize
    end

    local f, openErr = fs.open(AUDIT_FILE, "a")
    if not f then
        return
    end
    f.write(line .. "\n")
    f.close()

    rotateIfNeeded()
end

--- Read the last N entries from the audit log
--- @param limit number|nil
--- @return table array audit entries
function Logger.read(limit)
    if not fs.exists(AUDIT_FILE) then
        return {}
    end

    local f = fs.open(AUDIT_FILE, "r")
    local results = {}

    local line = f.readLine()
    while line ~= nil do
        if line ~= "" then
            local ok, entry = pcall(textutils.unserialize, line)
            if ok and type(entry) == "table" then
                results[#results + 1] = entry
            end
        end
        line = f.readLine()
    end
    f.close()

    table.sort(results, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

    if type(limit) == "number" and limit > 0 and #results > limit then
        local trimmed = {}
        for i = 1, limit do
            trimmed[i] = results[i]
        end
        return trimmed
    end

    return results
end

return Logger