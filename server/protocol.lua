-- server side handshake
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local crypto = require "shared.crypto"
local signing = require "shared.signing"
local packet = require "shared.packet"
local constants = require "shared.constants"
local utils = require "shared.utils"
local replay = require "shared.replay"
local Session = require "shared.session"
local ccutil = require "ccryptolib.util"

local Auth = require "server.auth"
local Accounts = require "server.accounts"
local Transactions = require "server.transactions"
local Logger = require "server.logger"

local ServerProtocol = {}
ServerProtocol.__index = ServerProtocol

local HANDSHAKE_TTL_MS = 30000

--- @param opts table { myId, mySk, myPk, nonceStore?}
function ServerProtocol.new(opts)
    assert(opts.myId and opts.mySk and opts.myPk, "serverProtocol: myId, mySk and myPk are required")
    return setmetatable({
        myId = opts.myId,
        mySk = opts.mySk,
        myPk = opts.myPk,
        nonceStore = opts.nonceStore or replay.new(constants.NONCE_TTL_MS),
        pending = {},
        sessions = {}
    }, ServerProtocol)
end

--- KILL EXPIRED PENDINGS (those mfs am i right)
function ServerProtocol:evictExpiredPending()
    local cutoff = utils.now() - HANDSHAKE_TTL_MS
    for id, p in pairs(self.pending) do
        if p.createdAt < cutoff then
            self.pending[id] = nil
        end
    end
end

--- Main entry point.
--- Assumes the packet has already been validated
function ServerProtocol:handlePacket(senderId, pkt, send)

    if tonumber(pkt.sender) ~= tonumber(senderId) then
        send(senderId, self:_errorPacket(constants.ERROR.INVALID_PACKET))
        return
    end

    if constants.HANDSHAKE_PACKETS[pkt.type] then
        if not self.nonceStore:check(pkt.sender, pkt.nonce, pkt.timestamp) then
            send(senderId, self:_errorPacket(constants.ERROR.INVALID_NONCE))
            return
        end
        if pkt.type == constants.PACKET.HELLO then
            self:_handleHello(senderId, pkt, send)
        elseif pkt.type == constants.PACKET.AUTH then
            self:_handleAuth(senderId, pkt, send)
        else
            send(senderId, self:_errorPacket(constants.ERROR.INVALID_PACKET))
        end
        return
    end

    local session = self.sessions[senderId]
    if not session then
        print("[SRV] No session for " .. tostring(senderId) .. " — sending AUTH_FAILED")
        send(senderId, self:_errorPacket(constants.ERROR.AUTH_FAILED))
        return
    end
    local payload, rerr = session:receive(pkt)
    if not payload then
        print("[SRV] Decrypt/verify failed for " .. tostring(senderId) .. ": " .. tostring(rerr))
        send(senderId, self:_errorPacket(rerr))
        return
    end
    print("[SRV] Operational packet from " .. tostring(senderId) .. " type=" .. tostring(pkt.type))
    self:onOperational(senderId, pkt.type, payload, session, send)
end

--- The operations handler 8)
--- @param senderId number rednet computer ID
--- @param packetType string "TRANSFER", etc
--- @param payload table decrypted payload
--- @param session Session authenticated session
--- @param send function reply function (recipientId, packet)
function ServerProtocol:onOperational(senderId, packetType, payload, session, send)
    local authResult, authErr = Auth.resolve(session)

    -- CREATE_ACCOUNT and PING don't require an existing account
    local isCreateAccount = (packetType == constants.PACKET.CREATE_ACCOUNT)
    local isPing = (packetType == constants.PACKET.PING)
    if not authResult and not isCreateAccount and not isPing then
        local errCode = authErr or constants.ERROR.AUTH_FAILED
        self:_replyError(senderId, session, send, errCode)
        Logger.log(false, packetType, senderId, nil, errCode)
        return
    end
    if isCreateAccount and not authResult then
        -- authResult is nil, handled by createAccount
    end
    local username = authResult and authResult.account.username or nil

    -- go forth, children
    local ok, result

    if packetType == constants.PACKET.CREATE_ACCOUNT then
        ok, result = Accounts.createAccount(payload, authResult, session)
    elseif packetType == constants.PACKET.GET_ACCOUNT then
        ok, result = Accounts.getAccount(payload, authResult)
    elseif packetType == constants.PACKET.UPDATE_ACCOUNT then
        ok, result = Accounts.updateAccount(payload, authResult)
    elseif packetType == constants.PACKET.DELETE_ACCOUNT then
        ok, result = Accounts.deleteAccount(payload, authResult)
    elseif packetType == constants.PACKET.DEPOSIT then
        ok, result = Transactions.deposit(payload, authResult)
    elseif packetType == constants.PACKET.WITHDRAW then
        ok, result = Transactions.withdraw(payload, authResult)
    elseif packetType == constants.PACKET.TRANSFER then
        ok, result = Transactions.transfer(payload, authResult)
    elseif packetType == constants.PACKET.BALANCE then
        ok, result = Transactions.balance(payload, authResult)
    elseif packetType == constants.PACKET.HISTORY then
        ok, result = Transactions.history(payload, authResult)
    elseif packetType == constants.PACKET.PING then
        ok, result = true, {
            echo = payload
        }
    else
        ok, result = false, constants.ERROR.INVALID_PACKET
    end


    -- Reply
    if ok then
        -- PING - PONG
        local replyType = (packetType == constants.PACKET.PING)
            and constants.PACKET.PONG
            or (packetType .. "_OK")
        local reply = session:send(replyType, self.myId, self.mySk, self.myPk, {
            success = true,
            data = result
        })
        send(senderId, reply)
        Logger.log(true, packetType, senderId, username, "ok")
    else
        local errCode = type(result) == "string" and result or constants.ERROR.SERVER_ERROR
        self:_replyError(senderId, session, send, errCode)
        Logger.log(false, packetType, senderId, username, errCode)
    end
end

--- Send an ERROR back
function ServerProtocol:_replyError(senderId, session, send, code)
    local reply = session:send(constants.PACKET.ERROR, self.myId, self.mySk, self.myPk, {
        success = false,
        code    = code,
    })
    send(senderId, reply)
end


function ServerProtocol:_handleHello(senderId, pkt, send)
    print("[SRV] HELLO from " .. tostring(senderId))
    self:evictExpiredPending()

    local serverDhSk, serverDhPk = crypto.newDHKeypair()
    local challenge = crypto.randomBytes(32)

    self.pending[senderId] = {
        serverDhSk = serverDhSk,
        serverDhPk = serverDhPk,
        challenge = challenge,
        clientPk = pkt.payload.clientPublicKey,
        clientDhPk = pkt.payload.clientDhPublicKey,
        createdAt = utils.now()
    }

    local resp = packet.new(constants.PACKET.CHALLENGE, self.myId, crypto.randomBytes(12), utils.now(), {
        challenge = challenge,
        serverDhPublicKey = serverDhPk
    })
    resp.signature = signing.sign(self.mySk, self.myPk, resp)
    send(senderId, resp)
end

function ServerProtocol:_handleAuth(senderId, pkt, send)
    print("[SRV] AUTH from " .. tostring(senderId))
    local p = self.pending[senderId]
    if not p then
        send(senderId, self:_authFail("no pending handshake"))
        return
    end

    if not signing.verify(p.clientPk, pkt) then
        self.pending[senderId] = nil
        send(senderId, self:_authFail("bad signature"))
        return
    end
    if not ccutil.compare(pkt.payload.challengeResponse, p.challenge) then
        self.pending[senderId] = nil
        send(senderId, self:_authFail("challenge mismatch"))
        return
    end

    -- server receives on c2s, sends on s2c
    local c2s = crypto.deriveSessionKey(p.serverDhSk, p.clientDhPk, "blockvault-c2s-v1")
    local s2c = crypto.deriveSessionKey(p.serverDhSk, p.clientDhPk, "blockvault-s2c-v1")
    local session = Session.new(senderId, p.clientPk, s2c, c2s, function()
        return crypto.randomBytes(12)
    end)

    self.sessions[senderId] = session
    self.pending[senderId] = nil

    print("[SRV] Handshake COMPLETE with " .. tostring(senderId) .. " — session established")
    local ok = packet.new(constants.PACKET.AUTH_OK, self.myId, crypto.randomBytes(12), utils.now(), {})
    ok.signature = signing.sign(self.mySk, self.myPk, ok)
    send(senderId, ok)
end

function ServerProtocol:_authFail(reason)
    local fail = packet.new(constants.PACKET.AUTH_FAIL, self.myId, crypto.randomBytes(12), utils.now(), {
        reason = reason
    })
    fail.signature = signing.sign(self.mySk, self.myPk, fail)
    return fail
end

function ServerProtocol:_errorPacket(code)
    local e = packet.new(constants.PACKET.ERROR, self.myId, crypto.randomBytes(12), utils.now(), {
        code = code or constants.ERROR.SERVER_ERROR
    })
    e.signature = signing.sign(self.mySk, self.myPk, e)
    return e
end

return ServerProtocol
