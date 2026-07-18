--- Loads the config file for the client
--- what server to trust and whatnot

if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local serialization = require "shared.serialization"
local ccutil = require "ccryptolib.util"
 
local M = {}
local CONFIG_PATH = "/data/server.cfg"

--- @return table|nil { serverId, serverPk } or nil if not configured yet
function M.load()
    if not fs.exists(CONFIG_PATH) then
        return nil
    end
    local f = fs.open(CONFIG_PATH, "r")
    local raw = f.readAll()
    f.close()
    local decoded, err = serialization.decode(raw)
    if not decoded or not decoded.serverId or not decoded.serverPkHex then
        error("client/config.lua: corrupt server.cfg" .. (err and (": " .. err) or ""))
    end
    return {
        serverId = tonumber(decoded.serverId),
        serverPk = ccutil.fromHex(decoded.serverPkHex),
    }
end

--- @param serverId string|number
--- @param serverPkHex string  the hex string printed by server/main.lua
function M.save(serverId, serverPkHex)
    local dir = CONFIG_PATH:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local encoded = assert(serialization.encode({
        serverId = tonumber(serverId),
        serverPkHex = serverPkHex,
    }))
    local f = fs.open(CONFIG_PATH, "w")
    f.write(encoded)
    f.close()
end
 
return M
