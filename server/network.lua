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
    while true do
        local ok, err = pcall(function()
            while true do
                local event = {os.pullEvent()}
                local eventName = event[1]

                if eventName == "rednet_message" then
                    handleRednetMessage(protocolInstance, event[2], event[3], event[4])

                elseif eventName == "chat" then
                    handleChatEvent(protocolInstance, event[2], event[3])
                end
            end
        end)
        if not ok then
            print("[NET] Event loop error: " .. tostring(err))
            print("[NET] Restarting in 5 seconds...")
            sleep(5)
        end
    end
end

return M
