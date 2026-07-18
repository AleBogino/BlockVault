-- An authenticated, encrypted session with one peer.
-- We use two separate keys for sending and receiving (see protocol.lua)
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local crypto = require "shared.crypto"
local signing = require "shared.signing"
local cannonical = require "shared.cannonical"
local packet = require "shared.packet"
local serialization = require "shared.serialization"
local constants = require "shared.constants"
local utils = require "shared.utils"

local Session = {}
Session.__index = Session

function Session.new(peerId, peerPk, sendKey, recvKey, randomNonceFn)
    return setmetatable({
        peerId = peerId,
        peerPk = peerPk,
        sendKey = sendKey,
        recvKey = recvKey,
        randomNonceFn = randomNonceFn,
        sendSeq = 0,
        lastRecvSeq = 0
    }, Session)
end

--- Builds and signs a packet to send
function Session:send(packetType, myId, mySk, myPk, payloadTable)
    self.sendSeq = self.sendSeq + 1
    local seq = self.sendSeq

    local aeadNonce = crypto.makeNonce(seq)
    local plaintext = assert(serialization.encode(payloadTable))
    local envNonce = self.randomNonceFn()
    local timestamp = utils.now()

    -- bind the cipher to the metadata
    -- so u cant swap it without breaking decryption
    local aad = table.concat({tostring(constants.PROTOCOL_VERSION), packetType, tostring(myId), envNonce, tostring(timestamp),
                              tostring(seq)}, "\30")

    local ciphertext, tag = crypto.encrypt(self.sendKey, aeadNonce, plaintext, aad)
    local pkt = packet.new(packetType, myId, envNonce, timestamp, {
        ciphertext = ciphertext,
        tag = tag
    })
    pkt.seq = seq
    pkt.signature = signing.sign(mySk, myPk, pkt)
    return pkt
end

--- Verifies and decrypts an incoming packet
function Session:receive(pkt)
    if tonumber(pkt.sender) ~= tonumber(self.peerId) then
        return nil, constants.ERROR.INVALID_PACKET
    end

    if pkt.seq == nil then
        return nil, constants.ERROR.INVALID_PACKET
    end

    if pkt.seq <= self.lastRecvSeq then
        return nil, constants.ERROR.INVALID_PACKET
    end

    if not signing.verify(self.peerPk, pkt) then
        return nil, constants.ERROR.INVALID_PACKET
    end

    local aeadNonce = crypto.makeNonce(pkt.seq)
    local aad = table.concat( {
        tostring(pkt.version), pkt.type, tostring(pkt.sender), pkt.nonce, tostring(pkt.timestamp), tostring(pkt.seq)
    }, "\30")

    local plaintext = crypto.decrypt(self.recvKey, aeadNonce, pkt.payload.tag, pkt.payload.ciphertext, aad)
    if not plaintext then
        return nil, constants.ERROR.INVALID_SIGNATURE
    end

    local payloadTable, decErr = serialization.decode(plaintext)
    if not payloadTable then
        return nil, constants.ERROR.INVALID_PACKET
    end

    -- only count it when everything succeded
    self.lastRecvSeq = pkt.seq
    return payloadTable, nil
end

return Session

