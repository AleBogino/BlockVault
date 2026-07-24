-- stuff to make each module send and receive data
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local constants = require "shared.constants"

local Net = {}
local REQUEST_TIMEOUT = 10

--- Send an encrypted request and return the decrypted response
--- @param state        table  { clientProtocol, network, myId, sk, pk, serverId, ... }
--- @param packetType   string from constants.PACKET
--- @param payloadTable table  unencrypted payload to send
--- @return table|nil replyPayload { success = bool, data = ..., code = ... }
--- @return string|nil errorMessage
function Net.sendAndReceive(state, packetType, payloadTable)
    local session = state.clientProtocol.session
    if not session then
        return nil, "No active session. Please restart the client."
    end

    local pkt = session:send(packetType, state.myId, state.sk, state.pk, payloadTable)
    state.network.send(state.serverId, pkt)

    local reply = state.network.receiveOnce(REQUEST_TIMEOUT)
    if not reply then
        return nil, "Request timed out. Server may be offline or unreachable."
    end

    local payload, decErr = session:receive(reply)
    if not payload then
        return nil, "Failed to decrypt/verify server response: " .. tostring(decErr)
    end

    return payload, nil
end

return Net