--- rednet stuffs for the server
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local packet = require "shared.packet"

local PROTOCOL = "ccbank"

local M = {}

--- OPEN THE GATES (the modem)
--- @return boolean ok, string | nil err
function M.open()
    if rednet.isOpen() then
        return true
    end
    local modemSide = nil
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "modem" then
            modemSide = side
            break
        end
    end
    if not modemSide then
        return false, "no modem attached to this computer"
    end
    rednet.open(modemSide)
    return true
end


--- Blocks until a packet arrives (or timeout)
--- @return boolean handledSomething  false on timeout
function M.pumpOnce(protocolInstance, timeout)
    local senderId, pkt, proto = rednet.receive(PROTOCOL, timeout)
    if senderId == nil then
        return false -- timed out
    end
 
    print("[NET] Received packet from " .. tostring(senderId) .. " type=" .. tostring(pkt and pkt.type or "?"))
    
    local ok, err = packet.validate(pkt)
    if not ok then
        print("[NET] Packet validation FAILED: " .. tostring(err))
        return true
    end
 
    protocolInstance:handlePacket(senderId, pkt, function(recipientId, replyPkt)
        print("[NET] Sending reply to " .. tostring(recipientId) .. " type=" .. tostring(replyPkt.type))
        rednet.send(recipientId, replyPkt, PROTOCOL)
    end)
    return true
end
 

function M.serveForever(protocolInstance)
    while true do
        M.pumpOnce(protocolInstance, nil) 
    end
end
 
return M
