-- Maps a session to an account + permission

if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local db        = require "server.database"
local constants = require "shared.constants"
local utils     = require "shared.utils"

local Auth = {}

--- @class AuthResult
--- @field account    table   the full account record from accounts.db
--- @field permission string  "USER" | "ADMIN" | "SYSTEM"

--- Map a session to an account
--- @param session  table|nil  Session object from protocol
--- @param username string|nil The detected player username
--- @return AuthResult|nil result
--- @return string|nil error (from constants.ERROR codes)
function Auth.resolve(session, username)
    if not session then
        return nil, constants.ERROR.AUTH_FAILED
    end

    if not utils.isNonEmptyString(username) then
        return nil, constants.ERROR.PLAYER_NOT_FOUND
    end

    local acct = db.getAccount(username)
    if not acct then
        return nil, constants.ERROR.ACCOUNT_NOT_FOUND
    end

    return {
        account = acct,
        permission = acct.permission or constants.PERMISSION.USER,
    }
end

--- @return AuthResult|nil
--- @return string|nil       error
function Auth.requirePermission(authResult, minPermission)
    if not authResult then
        return nil, constants.ERROR.PERMISSION_DENIED
    end
    local required = constants.PERMISSION_RANK[minPermission] or 0
    local actual   = constants.PERMISSION_RANK[authResult.permission] or 0
    if actual < required then
        return nil, constants.ERROR.PERMISSION_DENIED
    end
    return authResult
end

return Auth