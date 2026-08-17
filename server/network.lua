--- rednet stuffs for the server
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end
local Chat = require "server.chat"
local packet = require "shared.packet"
local Peripheral = require "shared.peripheral"
local constants = require "shared.constants"
local ServerME = require "server.me"
local Toast = require "server.toast"

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
    Chat.handleChat(message, username)
    return true
end

--- Find and wrap the chat box peripheral
--- @return table|nil chatBox the wrapped peripheral
--- @return string|nil side
local function findChatBox()
    local cat = Peripheral.scan()
    local name = Peripheral.first(cat.chatBoxes)
    if name then
        return peripheral.wrap(name), name
    end
    return nil, nil
end

--- OPEN THE GATES (the modem)
--- @return boolean ok, string | nil err
function M.open()
    if not rednet.isOpen() then
        local cat = Peripheral.scan()
        local modemSide = Peripheral.pickModem(cat)
        if not modemSide then
            return false, "no wireless modem attached to this computer"
        end
        print("[NET] Opening wireless modem on " .. tostring(modemSide))
        rednet.open(modemSide)
    end

    -- Detect the chat box used for chat-based login.
    M.chatBox, M.chatBoxSide = findChatBox()
    if M.chatBox then
        print("[NET] Chat box found: " .. tostring(M.chatBoxSide))
    else
        print("[NET] WARNING: no chat box attached - $bank login will not work")
    end

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
    local maintenanceTimer = os.startTimer(constants.MAINTENANCE_INTERVAL_MS / 1000)
    while true do
        local event = {os.pullEventRaw()}
        local eventName = event[1]

        if eventName == "rednet_message" then
            handleRednetMessage(protocolInstance, event[2], event[3], event[4])

        elseif eventName == "chat" then
            -- Advanced Peripherals chat event: "chat", username, message, uuid, isHidden, messageUtf8
            handleChatEvent(protocolInstance, event[3], event[2])

        elseif eventName == "timer" then
            if event[2] == maintenanceTimer then
                ServerME.maintainStock()
                maintenanceTimer = os.startTimer(constants.MAINTENANCE_INTERVAL_MS / 1000)
            end
            Toast.pump()

        elseif eventName == "terminate" then
            print("[NET] Terminate event received. Shutting down.")
            break
        end
    end
end

return M
