--- rednet stuffs for the server
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end
local chatHandler = require "server.chat_handler"
local packet = require "shared.packet"

local PROTOCOL = "ccbank"

local M = {}

-- helpers
local handleRednetMessage
local handleChatEvent
local packetCount = 0

--- Process a single rednet message event
--- @return boolean handledSomething
handleRednetMessage = function(protocolInstance, senderId, pkt, proto)
    if proto ~= PROTOCOL then
        return false
    end

    -- cleanup every ~10 packets
    packetCount = packetCount + 1
    if packetCount % 10 == 0 then
        protocolInstance:_evictStaleSessions()
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

--- Process a single chat event
--- @return boolean handledSomething
handleChatEvent = function(protocolInstance, message, username)
    if not message or not username then
        return false
    end
    chatHandler.handleChatEvent(message, username, function(playerName, code)
        protocolInstance:onChatLogin(playerName, code)
    end)
    return true
end

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
    return handleRednetMessage(protocolInstance, senderId, pkt, proto)
end

function M.serveForever(protocolInstance)
    print("[NET] serveForever: entering event loop. Rednet open=" .. tostring(rednet.isOpen()))
    local eventCount = 0
    while true do
        local event = {os.pullEventRaw()}
        local eventName = event[1]
        eventCount = eventCount + 1

        -- Log every ~50 events or any non-timer/monitor events
        if eventName ~= "timer" and eventName ~= "monitor_touch" then
            print("[NET] Event #" .. tostring(eventCount) .. ": " .. tostring(eventName))
        end

        if eventName == "rednet_message" then
            handleRednetMessage(protocolInstance, event[2], event[3], event[4])

        elseif eventName == "chat" then
            handleChatEvent(protocolInstance, event[2], event[3])

        elseif eventName == "terminate" then
            print("[NET] Terminate event received. Shutting down.")
            break
        end
    end
end

return M
