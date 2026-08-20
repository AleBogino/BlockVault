-- client side handshake
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end


local crypto = require "shared.crypto"
local signing = require "shared.signing"
local packet = require "shared.packet"
local constants = require "shared.constants"
local utils = require "shared.utils"
local Session = require "shared.session"

local ClientProtocol = {}
ClientProtocol.__index = ClientProtocol

--- @param opts table { myId, mySk, myPk, serverId, serverPk }
function ClientProtocol.new(opts)
    assert(opts.myId and opts.mySk and opts.myPk and opts.serverId and opts.serverPk,
        "ClientProtocol: myId, mySk, myPk, serverId, and serverPk are required")
    return setmetatable({
        myId = opts.myId,
        mySk = opts.mySk,
        myPk = opts.myPk,
        serverId = opts.serverId,
        serverPk = opts.serverPk,
        state = "IDLE",
        session = nil,
        loginState = nil,
    }, ClientProtocol)
end

--- Begin a handshake attempt
--- @return table helloPacket
function ClientProtocol:start()
    self.dhSk, self.dhPk = crypto.newDHKeypair()
    self.state = "WAIT_CHALLENGE"
    local hello = packet.new(constants.PACKET.HELLO, self.myId, crypto.randomBytes(12), utils.now(), {
        clientId = self.myId,
        clientPublicKey = self.myPk,
        clientDhPublicKey = self.dhPk
    })
    hello.signature = signing.sign(self.mySk, self.myPk, hello)
    return hello
end

--- FEED THE PACKET 
--- @return table | nil replyPacket (a packet to send back, or nil)
--- @return string | nil result "CONNECTED" or "FAILED" after the handshake is done; 'nil' in progress
function ClientProtocol:handlePacket(pkt)
    if tonumber(pkt.sender) ~= tonumber(self.serverId) then
        return nil, nil -- not my server, eat shit
    end

    if pkt.type == constants.PACKET.CHALLENGE and self.state == "WAIT_CHALLENGE" then
        if not signing.verify(self.serverPk, pkt) then
            self.state = "FAILED"
            return nil, "FAILED"
        end

        -- to send
        local c2s = crypto.deriveSessionKey(self.dhSk, pkt.payload.serverDhPublicKey, "blockvault-c2s-v1")
        -- to receive
        local s2c = crypto.deriveSessionKey(self.dhSk, pkt.payload.serverDhPublicKey, "blockvault-s2c-v1")
        self.pendingKeys = {
            sendKey = c2s,
            recvKey = s2c
        }

        local auth = packet.new(constants.PACKET.AUTH, self.myId, crypto.randomBytes(12), utils.now(), {
            challengeResponse = pkt.payload.challenge
        })
        auth.signature = signing.sign(self.mySk, self.myPk, auth)
        self.state = "WAIT_AUTH_OK"
        return auth, nil
        
    elseif pkt.type == constants.PACKET.AUTH_OK and self.state == "WAIT_AUTH_OK" then
        if not signing.verify(self.serverPk, pkt) then
            self.state = "FAILED"
            return nil, "FAILED"
        end
        self.session = Session.new(self.serverId, self.serverPk, self.pendingKeys.sendKey, self.pendingKeys.recvKey, function() return crypto.randomBytes(12) end)
        self.pendingKeys = nil
        self.state = "CONNECTED"
        return nil, "CONNECTED"

    elseif pkt.type == constants.PACKET.AUTH_FAIL or pkt.type == constants.PACKET.ERROR then
        self.state = "FAILED"
        return nil, "FAILED"

    else
    end
    return nil, nil
end

--- Send a login request to start the chat login
--- @return table loginRequestPacket
function ClientProtocol:sendLoginRequest()
    if not self.session then
        error("Cannot request login: no active session")
    end
    local pkt = self.session:send(
        constants.PACKET.LOGIN_REQUEST,
        self.myId, self.mySk, self.myPk,
        { clientId = self.myId }
    )
    self.loginState = "WAIT_LOGIN_CODE"
    return pkt
end

--- Process a packet during the login (post-handshake).
--- @param pkt table the received packet
--- @return table|nil replyPacket to send back
--- @return string|nil loginCode if LOGIN_AWAIT_CHAT
--- @return string|nil result   "LOGGED_IN", "LOGIN_FAIL", "LOGIN_TIMEOUT", "AUTH_FAILED", or nil (in progress)
--- @return table|nil accountData if LOGGED_IN
function ClientProtocol:handleLoginPacket(pkt)
    if tonumber(pkt.sender) ~= tonumber(self.serverId) then
        return nil, nil, nil, nil
    end

    -- LOGIN_AWAIT_CHAT is sent as a plain signed packet
    if pkt.type == constants.PACKET.LOGIN_AWAIT_CHAT and self.loginState == "WAIT_LOGIN_CODE" then
        if not signing.verify(self.serverPk, pkt) then
            self.loginState = nil
            return nil, nil, "LOGIN_FAIL", nil
        end
        self.loginState = "WAIT_LOGIN_OK"
        return nil, pkt.payload.code, nil, nil
    end

    -- Drop the stale session so the caller can reconnect.
    if pkt.type == constants.PACKET.AUTH_FAIL or pkt.type == constants.PACKET.ERROR then
        self.session = nil
        self.loginState = nil
        return nil, nil, "AUTH_FAILED", nil
    end

    -- All other login packets are encrypted
    if not self.session then
        self.loginState = nil
        return nil, nil, "AUTH_FAILED", nil
    end
    local payload, rerr = self.session:receive(pkt)
    if not payload then
        return nil, nil, "LOGIN_FAIL", nil
    end

    if pkt.type == constants.PACKET.LOGIN_OK and self.loginState == "WAIT_LOGIN_OK" then
        self.loginState = "LOGGED_IN"
        return nil, nil, "LOGGED_IN", payload

    elseif pkt.type == constants.PACKET.LOGIN_FAIL then
        self.loginState = nil
        return nil, nil, "LOGIN_FAIL", payload

    elseif pkt.type == constants.PACKET.LOGIN_TIMEOUT then
        self.loginState = nil
        return nil, nil, "LOGIN_TIMEOUT", nil

    elseif pkt.type == constants.PACKET.ERROR then
        self.loginState = nil
        return nil, nil, "LOGIN_FAIL", payload
    end

    return nil, nil, nil, nil
end

return ClientProtocol
