-- Nonce store for replaying handshake packets
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local utils = require "shared.utils"

local M = {}
M.__index = M

function M.new(ttlMs)
    return setmetatable({ ttlMs = ttlMs, seen = {}}, M)
end

--- kill older entries
function M:evictExpired()
    local cutoff = utils.now() - self.ttlMs
    for key, seenAt in pairs(self.seen) do
        if seenAt < cutoff then
            self.seen[key] = nil
        end
    end
end

--- checks a sender-nonce pair. returns true and records it
--- @return boolean freshlySeenOk
function M:check(sender, nonce, timestamp)
    self:evictExpired()
    if not utils.withinSkew(timestamp, self.ttlMs) then
        return false
    end
    local key = sender .. "\30" .. nonce
    if self.seen[key] then
        return false
    end
    self.seen[key] = utils.now()
    return true
end

return M