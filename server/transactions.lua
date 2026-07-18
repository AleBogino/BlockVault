if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local db = require "server.database"
local constants = require "shared.constants"
local utils = require "shared.utils"
local Auth = require "server.auth"

local Transactions = {}

--- Build a transaction log entry
local function makeTxRecord(txType, fromUser, toUser, amount, balances)
    return {
        type = txType,
        from = fromUser,
        to = toUser,
        amount = amount,
        balances = balances
    }
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

--- Deposit money into an account
--- ADMIN/SYSTEM only
--- @param payload table {username, amount}
function Transactions.deposit(payload, authResult)
    local resolved, rerr = Auth.requirePermission(authResult, constants.PERMISSION.ADMIN)
    if not resolved then
        return false, rerr
    end

    if not utils.isNonEmptyString(payload.username) then
        return false, constants.ERROR.INVALID_PACKET
    end
    if not utils.isNonNegativeNumber(payload.amount) or payload.amount <= 0 then
        return false, constants.ERROR.INVALID_PACKET
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
        [payload.username] = acct.balance
    })
    db.appendTransaction(tx)

    return true, {
        balance = acct.balance
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
    if resolved.permission == constants.PERMISSION.USER
       and payload.username ~= resolved.account.username then
        return false, constants.ERROR.PERMISSION_DENIED
    end

    local acct = db.getAccount(payload.username)
    if not acct then
        return false, constants.ERROR.ACCOUNT_NOT_FOUND
    end

    return true, { username = acct.username, balance = acct.balance }
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

    if resolved.permission == constants.PERMISSION.USER
       and payload.username ~= resolved.account.username then
        return false, constants.ERROR.PERMISSION_DENIED
    end

    local limit = nil
    if type(payload.limit) == "number" and payload.limit > 0 then
        limit = payload.limit
    end

    local txs = db.getTransactions(payload.username, limit)
    return true, { transactions = txs }
end

return Transactions