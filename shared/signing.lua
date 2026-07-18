-- Sign or verify a packet (everything but the signature itself)
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local crypto = require "shared.crypto"
local cannonical = require "shared.cannonical"

local M = {}

--- Build the string that gets signed for a packet
function M.cannonicalString(pkt)
    local parts = {
        tostring(pkt.version),
        pkt.type,
        pkt.sender,
        pkt.nonce,
        tostring(pkt.timestamp),
    }
    if pkt.seq ~= nil then
        parts[#parts + 1] = tostring(pkt.seq)
    end
    parts[#parts + 1] = cannonical.encode(pkt.payload)
    return table.concat(parts, "\30")
end

--- Signs a "pkt" with an ed25519 keypair
function M.sign(sk, pk, pkt)
    return crypto.sign(sk, pk, M.cannonicalString(pkt))
end

--- Verifies a "pkt" signature against an ed25519 public key
function M.verify(pk, pkt)
    if type(pkt.signature) ~= "string" or #pkt.signature == 0 then
        return false
    end
    return crypto.verify(pk, M.cannonicalString(pkt), pkt.signature)
end

return M