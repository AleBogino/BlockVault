if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local db = require "server.database"
local constants = require "shared.constants"
local utils = require "shared.utils"
local Auth = require "server.auth"
local ServerME = require "server.me"

local Transactions = {}

local pendingWithdraws = {}
local PENDING_WITHDRAW_TTL_MS = 60000

-- forward declaration: withdrawConfirm is defined before makeTxRecord
--- Build a transaction log entry
local makeTxRecord = function(txType, fromUser, toUser, amount, balances)
    return {
        type = txType,
        from = fromUser,
        to = toUser,
        amount = amount,
        balances = balances
    }
end

--- Drop pending withdraws and reserved coins
local function dropPending(senderId)
    local entry = pendingWithdraws[senderId]
    if entry then
        ServerME.release(entry.breakdown)
        pendingWithdraws[senderId] = nil
        -- recover staged coins
        ServerME.sweepBuffer()
    end
    return entry
end

function Transactions.evictExpiredWithdraws()
    local cutoff = utils.now() - PENDING_WITHDRAW_TTL_MS
    for senderId, entry in pairs(pendingWithdraws) do
        if entry.expiresAt < cutoff then
            dropPending(senderId)
            print(("[SRV][WITHDRAW] evicted expired pending withdraw for %s (client %d)"):format(
                tostring(entry.username), senderId))
        end
    end
end

--- check funds + coin availability and register withdrawal
--- @param payload table {username, amount}
--- @param authResult table Auth.resolve result
--- @param senderId number client computer ID
--- @return boolean ok
--- @return table|string result {breakdown = {[coinId]=count}} or error code
function Transactions.withdrawRequest(payload, authResult, senderId)
    local resolved, rerr = Auth.requirePermission(authResult, constants.PERMISSION.USER)
    if not resolved then
        return false, rerr
    end
    if not utils.isNonEmptyString(payload.username) then
        return false, constants.ERROR.INVALID_PACKET
    end
    if not utils.isNonNegativeNumber(payload.amount) or payload.amount <= 0 then
        return false, constants.ERROR.INVALID_PACKET
    end

    -- USER can only extract from their own account
    if resolved.permission == constants.PERMISSION.USER and payload.username ~= resolved.account.username then
        return false, constants.ERROR.PERMISSION_DENIED
    end

    local acct = db.getAccount(payload.username)
    if not acct then
        return false, constants.ERROR.ACCOUNT_NOT_FOUND
    end

    if acct.balance < payload.amount then
        return false, constants.ERROR.INSUFFICIENT_FUNDS
    end

    -- Free expired reservations
    Transactions.evictExpiredWithdraws()
    dropPending(senderId)

    -- TODO if coinBreakdown returns COINS_NOT_FOUND, attempt to craft em once

    local breakdown, berr = ServerME.coinBreakdown(payload.amount)
    if not breakdown then
        return false, berr or constants.ERROR.COINS_NOT_FOUND
    end

    -- Reserve the approved coins
    ServerME.reserve(breakdown)

    if not ServerME.stageWithdrawal(breakdown) then
        ServerME.release(breakdown)
        return false, constants.ERROR.ME_EXPORT_FAILED
    end

    pendingWithdraws[senderId] = {
        username = payload.username,
        amount = payload.amount,
        breakdown = breakdown,
        expiresAt = utils.now() + PENDING_WITHDRAW_TTL_MS
    }

    print(("[SRV][WITHDRAW] request approved for %s amount=%d (pending, reserved, no debit yet)"):format(
        payload.username, payload.amount))

    return true, {
        breakdown = breakdown
    }
end

--- Export coins, debit account and record transaction.
--- @param payload table {username, amount, [coinBreakdown]}
--- @param authResult table Auth.resolve result
--- @param senderId number client computer ID
--- @return boolean ok
--- @return table|string result {balance} or error code
function Transactions.withdrawConfirm(payload, authResult, senderId)
    local resolved, rerr = Auth.requirePermission(authResult, constants.PERMISSION.USER)
    if not resolved then
        return false, rerr
    end

    if not utils.isNonEmptyString(payload.username) then
        return false, constants.ERROR.INVALID_PACKET
    end
    if not utils.isNonNegativeNumber(payload.amount) or payload.amount <= 0 then
        return false, constants.ERROR.INVALID_PACKET
    end

    local pending = pendingWithdraws[senderId]
    if not pending then
        return false, constants.ERROR.INVALID_PACKET   -- no matching request
    end
    if pending.expiresAt < utils.now() then
        dropPending(senderId)
        return false, constants.ERROR.INVALID_PACKET   -- request expired
    end
    if pending.username ~= payload.username or pending.amount ~= payload.amount then
        dropPending(senderId)
        return false, constants.ERROR.INVALID_PACKET
    end

    -- USER can only extract from their own account
    if resolved.permission == constants.PERMISSION.USER and payload.username ~= resolved.account.username then
        dropPending(senderId)
        return false, constants.ERROR.PERMISSION_DENIED
    end

    local acct = db.getAccount(payload.username)
    if not acct then
        dropPending(senderId)
        return false, constants.ERROR.ACCOUNT_NOT_FOUND
    end
    if acct.balance < payload.amount then
        dropPending(senderId)
        return false, constants.ERROR.INSUFFICIENT_FUNDS
    end

    -- Drop the pending request BEFORE persisting
    dropPending(senderId)

    acct.balance = acct.balance - payload.amount

    local ok, err = db.saveAccount(acct)
    if not ok then
        return false, constants.ERROR.SERVER_ERROR
    end

    local tx = makeTxRecord("WITHDRAW", payload.username, nil, payload.amount, {
        [payload.username] = acct.balance,
        coinBreakdown = payload.coinBreakdown or pending.breakdown,
    })
    db.appendTransaction(tx)

    return true, { balance = acct.balance }
end


--- persist two acounts + transaction log
--- @return boolean ok
--- @return string|nil error
local function atomicPersist(acctA, acctB, txRecord)
    local ok, err = db.saveTwoAccounts(acctA, acctB)
    if not ok then
        return false, "saveTwoAccounts failed: " .. tostring(err)
    end

    ok, err = db.appendTransaction(txRecord)
    if not ok then
        -- money was already transfered, so we return an error but dont roll back
        return false, "appendTransaction failed: " .. tostring(err)
    end

    return true, nil
end

-- ---------------------------------- CRUD ---------------------------------- --

--- Deposit money into an account.
--- USER: self-only physical coin deposit
--- ADMIN/SYSTEM: numeric deposit
--- @param payload table {username, amount, [coinBreakdown]}
function Transactions.deposit(payload, authResult)
    local resolved, rerr = Auth.requirePermission(authResult, constants.PERMISSION.USER)
    if not resolved then
        return false, rerr
    end

    -- USER can only deposit into their own account
    if resolved.permission == constants.PERMISSION.USER and payload.username ~= resolved.account.username then
        return false, constants.ERROR.PERMISSION_DENIED
    end

    if not utils.isNonEmptyString(payload.username) then
        return false, constants.ERROR.INVALID_PACKET
    end
    if not utils.isNonNegativeNumber(payload.amount) or payload.amount <= 0 then
        return false, constants.ERROR.INVALID_PACKET
    end

    -- USER coins must be already on the network
    if resolved.permission == constants.PERMISSION.USER then
        local verified, verr = ServerME.verifyDeposit(payload.coinBreakdown)
        if not verified then
            print("[SRV][DEPOSIT] verifyDeposit failed for " .. tostring(payload.username) .. ": " .. tostring(verr))
            return false, verr
        end
        -- The reported amount must be exactly backed
        if verified < payload.amount then
            print(("[SRV][DEPOSIT] verified=%d < amount=%d for %s"):format(verified, payload.amount,
                tostring(payload.username)))
            return false, constants.ERROR.COINS_NOT_FOUND
        end
    end

    -- Read
    local acct = db.getAccount(payload.username)
    if not acct then
        return false, constants.ERROR.ACCOUNT_NOT_FOUND
    end

    acct.balance = acct.balance + payload.amount

    -- Persist
    local ok, err = db.saveAccount(acct)
    if not ok then
        return false, constants.ERROR.SERVER_ERROR
    end

    local tx = makeTxRecord("DEPOSIT", nil, payload.username, payload.amount, {
        [payload.username] = acct.balance,
        coinBreakdown = payload.coinBreakdown
    })
    db.appendTransaction(tx)
    ServerME.sweepBuffer()

    return true, {
        balance = acct.balance,
        deposited = payload.amount
    }
end

--- Withdraw money from an account
--- @param payload table {username, amount}
function Transactions.withdraw(payload, authResult)
    local resolved, rerr = Auth.requirePermission(authResult, constants.PERMISSION.USER)
    if not resolved then
        return false, rerr
    end

    if not utils.isNonEmptyString(payload.username) then
        return false, constants.ERROR.INVALID_PACKET
    end
    if not utils.isNonNegativeNumber(payload.amount) or payload.amount <= 0 then
        return false, constants.ERROR.INVALID_PACKET
    end

    -- USER can only withdraw from their own account
    if resolved.permission == constants.PERMISSION.USER and payload.username ~= resolved.account.username then
        return false, constants.ERROR.PERMISSION_DENIED
    end

    -- Read
    local acct = db.getAccount(payload.username)
    if not acct then
        return false, constants.ERROR.ACCOUNT_NOT_FOUND
    end

    -- Validate
    if acct.balance < payload.amount then
        return false, constants.ERROR.INSUFFICIENT_FUNDS
    end

    -- Apply
    acct.balance = acct.balance - payload.amount

    -- Persist
    local ok, err = db.saveAccount(acct)
    if not ok then
        return false, constants.ERROR.SERVER_ERROR
    end

    local tx = makeTxRecord("WITHDRAW", payload.username, nil, payload.amount, {
        [payload.username] = acct.balance
    })
    db.appendTransaction(tx)

    return true, {
        balance = acct.balance
    }
end

--- Transfer money from one account to another
--- @param payload table {from, to, amount}
function Transactions.transfer(payload, authResult)
    local resolved, rerr = Auth.requirePermission(authResult, constants.PERMISSION.USER)
    if not resolved then
        return false, rerr
    end

    if not utils.isNonEmptyString(payload.from) then
        return false, constants.ERROR.INVALID_PACKET
    end
    if not utils.isNonEmptyString(payload.to) then
        return false, constants.ERROR.INVALID_PACKET
    end
    if payload.from == payload.to then
        return false, constants.ERROR.INVALID_PACKET
    end
    if not utils.isNonNegativeNumber(payload.amount) or payload.amount <= 0 then
        return false, constants.ERROR.INVALID_PACKET
    end

    -- USER can only transfer from their own account
    if resolved.permission == constants.PERMISSION.USER and payload.from ~= resolved.account.username then
        return false, constants.ERROR.PERMISSION_DENIED
    end

    -- Validate
    local fromAcct = db.getAccount(payload.from)
    if not fromAcct then
        return false, constants.ERROR.ACCOUNT_NOT_FOUND
    end

    local toAcct = db.getAccount(payload.to)
    if not toAcct then
        return false, constants.ERROR.ACCOUNT_NOT_FOUND
    end

    if fromAcct.balance < payload.amount then
        return false, constants.ERROR.INSUFFICIENT_FUNDS
    end

    -- Apply
    fromAcct.balance = fromAcct.balance - payload.amount
    toAcct.balance = toAcct.balance + payload.amount

    -- Persist
    local tx = makeTxRecord("TRANSFER", payload.from, payload.to, payload.amount, {
        [payload.from] = fromAcct.balance,
        [payload.to] = toAcct.balance
    })

    local ok, err = atomicPersist(fromAcct, toAcct, tx)
    if not ok then
        return false, constants.ERROR.SERVER_ERROR
    end

    return true, {
        fromBalance = fromAcct.balance,
        toBalance = toAcct.balance
    }
end

--- Get the balance of an account
--- @param payload table {username}
--- @param authResult table|nil AuthResult from Auth.resolve(session) {account, permission}
function Transactions.balance(payload, authResult)
    local resolved, rerr = Auth.requirePermission(authResult, constants.PERMISSION.USER)
    if not resolved then
        return false, rerr
    end

    if not utils.isNonEmptyString(payload.username) then
        return false, constants.ERROR.INVALID_PACKET
    end

    -- user can only check their own balance
    if resolved.permission == constants.PERMISSION.USER and payload.username ~= resolved.account.username then
        return false, constants.ERROR.PERMISSION_DENIED
    end

    local acct = db.getAccount(payload.username)
    if not acct then
        return false, constants.ERROR.ACCOUNT_NOT_FOUND
    end

    return true, {
        username = acct.username,
        balance = acct.balance
    }
end

--- Get the transaction history of an account
--- @param payload table {username, [limit]}
function Transactions.history(payload, authResult)
    local resolved, rerr = Auth.requirePermission(authResult, constants.PERMISSION.USER)
    if not resolved then
        return false, rerr
    end

    if not utils.isNonEmptyString(payload.username) then
        return false, constants.ERROR.INVALID_PACKET
    end

    if resolved.permission == constants.PERMISSION.USER and payload.username ~= resolved.account.username then
        return false, constants.ERROR.PERMISSION_DENIED
    end

    local limit = nil
    if type(payload.limit) == "number" and payload.limit > 0 then
        limit = payload.limit
    end

    local txs = db.getTransactions(payload.username, limit)
    return true, {
        transactions = txs
    }
end

return Transactions
