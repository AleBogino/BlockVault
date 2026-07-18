-- defines packet shape
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local constants = require("shared.constants")
local utils = require("shared.utils")

local M = {}

--- Validate envelope fields
--- @return boolean ok
--- @return string | nil err constants.ERROR code if not ok
local function validateEnvelopeFields(packet)
    if type(packet) ~= "table" then
        return false, constants.ERROR.INVALID_PACKET
    end

    if packet.version ~= constants.PROTOCOL_VERSION then
        return false, constants.ERROR.INVALID_VERSION
    end

    if type(packet.type) ~= "string" or not constants.PAYLOAD_SCHEMA[packet.type] then
        return false, constants.ERROR.INVALID_PACKET
    end

    if type(packet.sender) ~= "number" then
        return false, constants.ERROR.INVALID_PACKET
    end

    if type(packet.timestamp) ~= "number" then
        return false, constants.ERROR.INVALID_PACKET
    end

    if not utils.isNonEmptyString(packet.signature) then
        return false, constants.ERROR.INVALID_PACKET
    end
    return true, nil
end

--- Validate a payload table against the required fields
--- @return boolean ok
--- @return string | nil err
function M.validatePayload(packetType, payload)
    local schema = constants.PAYLOAD_SCHEMA[packetType]
    if not schema then
        return false, constants.ERROR.INVALID_PACKET
    end
    if type(payload) ~= "table" then
        return false, constants.ERROR.INVALID_PACKET
    end
        if not utils.hasFields(payload, schema) then
        return false, constants.ERROR.INVALID_PACKET
    end
    return true, nil
end

--- Full shape validation of a packet
--- @return boolean ok
--- @return string | nil err
function M.validate(packet)
    local ok, err = validateEnvelopeFields(packet)
    if not ok then return false, err end
 
    if constants.HANDSHAKE_PACKETS[packet.type] then
        return M.validatePayload(packet.type, packet.payload)
    end

    -- packet isnt a handshake, packet must be encrypted
    if type(packet.payload) ~= "table"
        or not utils.isNonEmptyString(packet.payload.ciphertext)
        or not utils.isNonEmptyString(packet.payload.tag)
    then
        return false, constants.ERROR.INVALID_PACKET
    end
    return true, nil
end

--- Builds a new envelope table
function M.new(packetType, sender, nonce, timestamp, payload)
    return {
        version = constants.PROTOCOL_VERSION,
        type = packetType,
        sender = sender,
        nonce = nonce,
        timestamp = timestamp,
        payload = payload,
        signature = "", -- filled by the caller :3
    }
end

return M