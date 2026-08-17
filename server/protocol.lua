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
local Toast = require "server.toast"

-- Generate a random numeric login code
local function generateLoginCode()
    local digits = {}
    for i = 1, constants.LOGIN_CODE_LENGTH do
        digits[i] = tostring(math.random(0, 9))
    end
    return table.concat(digits)
end

local ServerProtocol = {}
ServerProtocol.__index = ServerProtocol

local HANDSHAKE_TTL_MS = 30000

-- Session inactivity timeout (ms)
local SESSION_TIMEOUT_MS = 120000

--- @param opts table { myId, mySk, myPk, nonceStore?}
function ServerProtocol.new(opts)
    assert(opts.myId and opts.mySk and opts.myPk, "serverProtocol: myId, mySk and myPk are required")
    return setmetatable({
        myId = opts.myId,
        mySk = opts.mySk,
        myPk = opts.myPk,
        nonceStore = opts.nonceStore or replay.new(constants.NONCE_TTL_MS),
        pending = {},
        pendingLogins = {},
        sessions = {},
        playerDetector = opts.playerDetector
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
        elseif pkt.type == constants.PACKET.LOGIN_REQUEST then
            self:_handleLoginRequest(senderId, pkt, send)
        else
            send(senderId, self:_errorPacket(constants.ERROR.INVALID_PACKET))
        end
        return
    end

    local session = self.sessions[senderId]
    if not session then
        print("[SRV] No session for " .. tostring(senderId) .. " - sending AUTH_FAILED")
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
    -- expired logins go bye bye on every packet 
    self:_evictExpiredLogins()

    -- activity timestamp for session timeout
    if session then
        session.lastActivity = utils.now()
    end

    local targetUsername = payload.username or payload.from
    local authResult, authErr = Auth.resolve(session, targetUsername)

    -- CREATE_ACCOUNT, PING, and GET_ONLINE_PLAYERS don't require an existing account
    local isCreateAccount = (packetType == constants.PACKET.CREATE_ACCOUNT)
    local isPing = (packetType == constants.PACKET.PING)
    local isGetOnlinePlayers = (packetType == constants.PACKET.GET_ONLINE_PLAYERS)
    if not authResult and not isCreateAccount and not isPing and not isGetOnlinePlayers then
        local errCode = authErr or constants.ERROR.AUTH_FAILED
        self:_replyError(senderId, session, send, errCode)
        Logger.log(false, packetType, senderId, nil, errCode)
        return
    end
    if isCreateAccount and not authResult then
        -- authResult is nil, handled by createAccount
    end

    local username = authResult and authResult.account.username or targetUsername

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
    elseif packetType == constants.PACKET.WITHDRAW_REQUEST then
        ok, result = Transactions.withdrawRequest(payload, authResult, senderId)
    elseif packetType == constants.PACKET.WITHDRAW_CONFIRM then
        ok, result = Transactions.withdrawConfirm(payload, authResult, senderId)
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
    elseif packetType == constants.PACKET.GET_ONLINE_PLAYERS then
        ok, result = self:_handleGetOnlinePlayers()
    else
        ok, result = false, constants.ERROR.INVALID_PACKET
    end

    -- Reply
    if ok then
        -- PING - PONG
        local replyType = (packetType == constants.PACKET.PING) and constants.PACKET.PONG or (packetType .. "_OK")
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
        code = code
    })
    send(senderId, reply)
end

--- handle chat login requests
--- @param senderId number
--- @param pkt table
--- @param send function
function ServerProtocol:_handleLoginRequest(senderId, pkt, send)
    print("[SRV] LOGIN_REQUEST from " .. tostring(senderId))

    -- already pending login?
    for code, entry in pairs(self.pendingLogins) do
        if entry.senderId == senderId then
            -- Reuse the existing code
            local reply = packet.new(constants.PACKET.LOGIN_AWAIT_CHAT, self.myId, crypto.randomBytes(12), utils.now(),
                {
                    code = code
                })
            reply.signature = signing.sign(self.mySk, self.myPk, reply)
            send(senderId, reply)
            return
        end
    end

    -- otherwise generate a unique code
    local code
    repeat
        code = generateLoginCode()
    until not self.pendingLogins[code]

    self.pendingLogins[code] = {
        senderId = senderId,
        createdAt = utils.now()
    }

    local reply = packet.new(constants.PACKET.LOGIN_AWAIT_CHAT, self.myId, crypto.randomBytes(12), utils.now(), {
        code = code
    })
    reply.signature = signing.sign(self.mySk, self.myPk, reply)
    send(senderId, reply)
    print("[SRV] Login code " .. code .. " issued to client " .. tostring(senderId))
end

--- called on "$bank login <code>"
--- @param username string the player who sent the chat
--- @param code string the login code from the chat message
function ServerProtocol:onChatLogin(username, code)
    print("[SRV] Chat login attempt: user=" .. tostring(username) .. " code=" .. tostring(code))

    local entry = self.pendingLogins[code]
    if not entry then
        -- code not found or expired
        print("[SRV] Login code " .. tostring(code) .. " not found in pending logins")
        Toast.error(username, "Invalid or expired login code.")
        return
    end

    local senderId = entry.senderId
    self.pendingLogins[code] = nil

    local session = self.sessions[senderId]
    if not session then
        print("[SRV] No active session for client " .. tostring(senderId))
        Toast.error(username, "Login session expired. Please start login again.")
        return
    end

    -- Look up the account
    local db = require "server.database"
    local acct = db.getAccount(username)

    if acct then
        -- Existing account: return account data
        local reply = session:send(constants.PACKET.LOGIN_OK, self.myId, self.mySk, self.myPk, {
            username = acct.username,
            balance = acct.balance,
            permission = acct.permission,
            createdAt = acct.createdAt,
            id = acct.id
        })
        -- Send via rednet
        rednet.send(senderId, reply, "ccbank")
        print("[SRV] LOGIN_OK sent to " .. tostring(senderId) .. " for user " .. username)
        Toast.success(username, "Welcome back, " .. username .. "!")
    else
        -- No account yet: tell user they're a dumb one
        local reply = session:send(constants.PACKET.LOGIN_OK, self.myId, self.mySk, self.myPk, {
            username = username,
            balance = 0,
            permission = constants.PERMISSION.USER,
            createdAt = nil,
            id = nil,
            newAccount = true
        })
        rednet.send(senderId, reply, "ccbank")
        print("[SRV] LOGIN_OK (new) sent to " .. tostring(senderId) .. " for user " .. username)
        Toast.success(username, "Account ready. Welcome, " .. username .. "!")
    end
end

--- Handle "$bank help" - show all chat commands
--- @param username string the player who sent the chat
function ServerProtocol:onChatHelp(username)
    print("[SRV][CHAT] help requested by " .. tostring(username))
    Toast.sendMessage(username, table.concat({
        "bank help - show this list",
        "bank login <code> - link a computer",
        "bank balance - your balance",
        "bank transfer <player> <amount> - send money",
        "bank list - top 10 accounts",
    }, "\n"))
end

--- Handle "$bank transfer <to> <amount>" - send money from the sender's account
--- @param username string the player who sent the chat
--- @param args     string raw args "<to> <amount>"
function ServerProtocol:onChatTransfer(username, args)
    if not utils.isNonEmptyString(args) then
        Toast.sendMessage(username, "Usage: bank transfer <player> <amount>")
        return
    end

    local to, amountStr = args:match("^%s*(%S+)%s+(%S+)%s*$")
    local amount = amountStr and tonumber(amountStr)
    if not to or not amount or amount <= 0 then
        Toast.sendMessage(username, "Usage: bank transfer <player> <amount>")
        return
    end

    local db = require "server.database"
    local acct = db.getAccount(username)
    if not acct then
        Toast.sendMessage(username, "You don't have a BlockBank account yet.")
        print("[SRV][CHAT] transfer refused for " .. tostring(username) .. ": no account")
        return
    end

    local authResult = {
        account = acct,
        permission = acct.permission or constants.PERMISSION.USER,
    }

    local ok, result = Transactions.transfer({
        from = username,
        to = to,
        amount = amount,
    }, authResult)

    if not ok then
        local code = result
        local friendly
        if code == constants.ERROR.INSUFFICIENT_FUNDS then
            friendly = "Insufficient funds for that transfer."
        elseif code == constants.ERROR.DESTINATION_NO_ACCOUNT then
            friendly = "'" .. tostring(to) .. "' does not have a BlockBank account."
        elseif code == constants.ERROR.ACCOUNT_NOT_FOUND then
            friendly = "Your account was not found."
        elseif code == constants.ERROR.INVALID_PACKET then
            friendly = "Invalid transfer. Usage: bank transfer <player> <amount>"
        else
            friendly = "Transfer failed: " .. tostring(code)
        end
        Toast.sendMessage(username, friendly)
        print(("[SRV][CHAT] transfer failed for %s -> %s amount=%s: %s"):format(
            tostring(username), tostring(to), tostring(amount), tostring(code)))
        return
    end

    print(("[SRV][CHAT] transfer %s -> %s amount=%s ok (fromBalance=%s)"):format(
        tostring(username), tostring(to), tostring(amount),
        tostring(result and result.fromBalance or "?")))
    -- Success toasts (recipient + sender) and chat receipts are sent inside Transactions.transfer
end

--- Handle "$bank list" - show the top 10 accounts by balance
--- @param username string the player who sent the chat
function ServerProtocol:onChatList(username)
    local db = require "server.database"
    local accounts = db.listAccounts()
    table.sort(accounts, function(a, b)
        return (a.balance or 0) > (b.balance or 0)
    end)

    local topN = math.min(10, #accounts)
    print(("[SRV][CHAT] list requested by %s (accounts=%d)"):format(tostring(username), #accounts))

    if topN == 0 then
        Toast.sendMessage(username, "No accounts yet.")
        return
    end

    local lines = {}
    for i = 1, topN do
        local acct = accounts[i]
        lines[#lines + 1] = ("%d. %s - $%.2f"):format(i, tostring(acct.username), acct.balance or 0)
    end

    Toast.sendMessage(username, table.concat(lines, "\n"))
end

--- Handle "$bank balance" - show the sender's balance in chat
--- @param username string the player who sent the chat
function ServerProtocol:onChatBalance(username)
    local db = require "server.database"
    local acct = db.getAccount(username)
    if not acct then
        Toast.sendMessage(username, "You don't have a BlockBank account yet.")
        print("[SRV][CHAT] balance refused for " .. tostring(username) .. ": no account")
        return
    end

    Toast.sendMessage(username, ("Your balance is $%.2f"):format(acct.balance or 0))
    print(("[SRV][CHAT] balance for %s = %s"):format(tostring(username), tostring(acct.balance or 0)))
end

--- Evict expired pending logins
function ServerProtocol:_evictExpiredLogins()
    local cutoff = utils.now() - constants.LOGIN_CHAT_TIMEOUT_MS
    for code, entry in pairs(self.pendingLogins) do
        if entry.createdAt < cutoff then
            -- Notify timeout to the client
            local session = self.sessions[entry.senderId]
            if session then
                local timeoutPkt = session:send(constants.PACKET.LOGIN_TIMEOUT, self.myId, self.mySk, self.myPk, {})
                rednet.send(entry.senderId, timeoutPkt, "ccbank")
                print("[SRV] Login timeout for client " .. tostring(entry.senderId))
            end
            self.pendingLogins[code] = nil
        end
    end
end

--- Evict sessions that have been inactive too long
function ServerProtocol:_evictStaleSessions()
    local cutoff = utils.now() - constants.SESSION_TIMEOUT_MS
    for id, session in pairs(self.sessions) do
        if session.lastActivity and session.lastActivity < cutoff then
            print("[SRV] Evicting stale session for client " .. tostring(id))
            self.sessions[id] = nil
        end
    end
end

--- Query the server's playerDetector for online players
--- @return boolean ok
--- @return table|string result list of player names or error code
function ServerProtocol:_handleGetOnlinePlayers()
    if not self.playerDetector then
        return false, constants.ERROR.SERVER_ERROR
    end
    local players = {}
    local ok, list = pcall(function()
        return self.playerDetector.getOnlinePlayers()
    end)
    if ok and type(list) == "table" then
        for _, name in ipairs(list) do
            table.insert(players, name)
        end
    end
    return true, {
        players = players
    }
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
    session.lastActivity = utils.now()

    self.sessions[senderId] = session
    self.pending[senderId] = nil

    print("[SRV] Handshake COMPLETE with " .. tostring(senderId) .. " - session established")
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
