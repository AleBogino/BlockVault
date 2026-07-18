-- load this pc's long-term ed25519 keypair from disk
-- generates and persists a new one on first run
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local crypto = require "shared.crypto"
local serialization = require "shared.serialization"
local ccutil = require "ccryptolib.util"

local M = {}

--- @param path string
--- @return string sk, string pk
function M.loadOrCreate(path)
    if fs.exists(path) then
        local f = fs.open(path, "r")
        local raw = f.readAll()
        f.close()
        local decoded, err = serialization.decode(raw)
        if not decoded or not decoded.skHex or not decoded.pkHex then
            error("identity.lua: corrupt or unreadable identity file at "
                .. path .. (err and (": " .. err) or ""))
        end
        return ccutil.fromHex(decoded.skHex), ccutil.fromHex(decoded.pkHex)
    end
 
    local sk, pk = crypto.newIdentity()
    local encoded, err = serialization.encode({
        skHex = ccutil.toHex(sk),
        pkHex = ccutil.toHex(pk),
 })
    if not encoded then
        error("identity.lua: failed to encode new identity: " .. tostring(err))
    end
    local dir = path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local f = fs.open(path, "w")
    f.write(encoded)
    f.close()
    return sk, pk
end
 
return M
