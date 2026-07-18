-- Account CRUD stuffs
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local db = require "server.database"
local constants = require "shared.constants"
local utils = require "shared.utils"
local Auth = require "server.auth"

local Accounts = {}

local function sanitiseAccount(acct)
    return {
        username = acct.username,
        id = acct.id,
        balance = acct.balance,
        permission = acct.permission,
        createdAt = acct.createdAt
    }
end

-- --------------------------------- CREATE --------------------------------- --

---Create a new account
---@param payload table {username, initialBalance, publicKey}
---@param authResult table|nil AuthResult from Auth.resolve(session) {account, permission}
---@param session table|nil Session object from protocol
function Accounts.createAccount(payload, authResult, session)
    if not utils.isNonEmptyString(payload.username) then
        return false, constants.ERROR.INVALID_PACKET
    end
    if not utils.isNonNegativeNumber(payload.initialBalance) then
        return false, constants.ERROR.INVALID_PACKET
    end
    if not utils.isNonEmptyString(payload.publicKey) then
        return false, constants.ERROR.INVALID_PACKET
    end
    if not session then
        return false, constants.ERROR.AUTH_FAILED
    end

    if authResult then
        return false, constants.ERROR.PERMISSION_DENIED
    end
    local existing = db.getAccount(payload.username)
    if existing then
        return false, "USERNAME_TAKEN"
    end

    local record = {
        username = payload.username,
        balance = payload.initialBalance,
        permission = constants.PERMISSION.USER,
        publicKey = payload.publicKey
    }

    local ok, err = db.saveAccount(record)
    if not ok then
        return false, constants.ERROR.SERVER_ERROR
    end
    db.saveKey(payload.username, payload.publicKey)
    return true, sanitiseAccount(db.getAccount(payload.username))
end

-- ----------------------------------- GET ---------------------------------- --

--- Get an account by username
--- @param payload table {username}
--- @param authResult table|nil AuthResult from Auth.resolve(session) {account, permission}
function Accounts.getAccount(payload, authResult)
    local resolved, rerr = Auth.requirePermission(authResult, constants.PERMISSION.USER)
    if not resolved then
        return false, rerr
    end

    if not utils.isNonEmptyString(payload.username) then
        return false, constants.ERROR.INVALID_PACKET
    end

    -- users can only get their own
    if resolved.permission == constants.PERMISSION.USER and payload.username ~= resolved.account.username then
        return false, constants.ERROR.PERMISSION_DENIED
    end

    local acct = db.getAccount(payload.username)
    if not acct then
        return false, constants.ERROR.ACCOUNT_NOT_FOUND
    end

    return true, sanitiseAccount(acct)
end

-- --------------------------------- UPDATE --------------------------------- --

--- Update account details (not balance)
--- almost exclusively used to transfer accounts or change permissions
--- @param payload table {username, [newUsername], [permission]}
function Accounts.updateAccount(payload, authResult)
    local resolved, rerr = Auth.requirePermission(authResult, constants.PERMISSION.USER)
    if not resolved then
        return false, rerr
    end

    if not utils.isNonEmptyString(payload.username) then
        return false, constants.ERROR.INVALID_PACKET
    end

    local acct = db.getAccount(payload.username)
    if not acct then
        return false, constants.ERROR.ACCOUNT_NOT_FOUND
    end

    -- users can only update their own (same stuff)
    if resolved.permission == constants.PERMISSION.USER then
        if payload.username ~= resolved.account.username then
            return false, constants.ERROR.PERMISSION_DENIED
        end
        -- and ofc they cant change their permissions
        if payload.permission ~= nil then
            return false, constants.ERROR.PERMISSION_DENIED
        end
    end

    -- apply (only allowed changes)
    if payload.newUsername and utils.isNonEmptyString(payload.newUsername) then
        if payload.newUsername ~= payload.username then
            local existing = db.getAccount(payload.newUsername)
            if existing then
                return false, "USERNAME_TAKEN"
            end
        end
        acct.username = payload.newUsername
    end

    -- ADMINS can rock the boat, but not the system
    if payload.permission ~= nil and resolved.permission ~= constants.PERMISSION.USER then
        if payload.permission == constants.PERMISSION.SYSTEM and resolved.permission ~= constants.PERMISSION.SYSTEM then
            return false, constants.ERROR.PERMISSION_DENIED
        end
        acct.permission = payload.permission
    end

    local ok, err = db.saveAccount(acct)
    if not ok then
        return false, constants.ERROR.SERVER_ERROR
    end
    return true, sanitiseAccount(db.getAccount(acct.username))
end

-- --------------------------------- DELETE --------------------------------- --

--- Delete an account
--- @param payload table {username}
--- @param authResult table|nil AuthResult from Auth.resolve(session) {account, permission}
function Accounts.deleteAccount(payload, authResult)
    local resolved, rerr = Auth.requirePermission(authResult, constants.PERMISSION.ADMIN)
    if not resolved then
        return false, rerr
    end

    if not utils.isNonEmptyString(payload.username) then
        return false, constants.ERROR.INVALID_PACKET
    end

    local acct = db.getAccount(payload.username)
    if not acct then
        return false, constants.ERROR.ACCOUNT_NOT_FOUND
    end

    -- u cant delete the system, u crazy?
    if acct.permission == constants.PERMISSION.SYSTEM and resolved.permission ~= constants.PERMISSION.SYSTEM then
        return false, constants.ERROR.PERMISSION_DENIED
    end

    -- u cant delete your own, ask an admin
    if payload.username == resolved.account.username then
        return false, constants.ERROR.PERMISSION_DENIED
    end

    local ok, err = db.deleteAccount(payload.username)
    if not ok then
        return false, constants.ERROR.SERVER_ERROR
    end

    db.deleteKey(payload.username)

    return true, {
        deleted = payload.username
    }
end

return Accounts
