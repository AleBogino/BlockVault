-- rednet stuffs for the client
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end


local packet = require "shared.packet"
 
local PROTOCOL = "ccbank"
 
local M = {}
 
M.PROTOCOL = PROTOCOL
 
local Peripheral = require "shared.peripheral"

function M.open()
    if rednet.isOpen() then return true end
    local cat = Peripheral.scan()
    local modemSide = Peripheral.pickModem(cat)
    if not modemSide then
        return false, "no wireless modem attached to this computer"
    end
    print("[CLI-NET] Opening wireless modem on " .. tostring(modemSide))
    rednet.open(modemSide)
    return true
end
 
function M.send(recipientId, pkt)
    rednet.send(tonumber(recipientId), pkt, PROTOCOL)
end


--- Blocks for up to (timeout) seconds, discarding invalid packets,
--- and returns the first valid packet that passes validation.
--- @return table | nil pkt nil on timeout or if no valid packet arrives
function M.receiveOnce(timeout)
    local deadline = os.epoch("utc") + (timeout or 10) * 1000
    while true do
        local remaining = math.max(0, math.ceil((deadline - os.epoch("utc")) / 1000))
        if remaining <= 0 then
            return nil
        end
        local senderId, pkt = rednet.receive(PROTOCOL, remaining)
        if senderId == nil then
            return nil
        end
        local ok, err = packet.validate(pkt)
        if not ok then
            print("[CLI-NET] Dropped invalid packet from " .. tostring(senderId) .. " type=" .. tostring(pkt and pkt.type) .. " reason=" .. tostring(err))
            -- keep looping, discard noise
        else
            return pkt
        end
    end
end

--- Drives a ClientProtocol instance through a full handshake
--- blocking it until it reaches a terminal state
--- @return boolean ok, string | nil err
function M.handshake(clientProtocol, timeout)
    local t0 = os.epoch("utc")
    local hello = clientProtocol:start()
    M.send(clientProtocol.serverId, hello)
 
    while true do
        local pkt = M.receiveOnce(timeout or 10)
        if not pkt then
            return false, "timed out waiting for a handshake response"
        end
        local reply, result = clientProtocol:handlePacket(pkt)
        if reply then
            M.send(clientProtocol.serverId, reply)
        end
        if result == "CONNECTED" then
            local elapsed = os.epoch("utc") - t0
            return true, nil
        elseif result == "FAILED" then
            return false, "handshake failed (bad signature, challenge " ..
                "mismatch, or AUTH_FAIL/ERROR from server)"
        end
    end
end
 
return M
