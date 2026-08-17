if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local M = {}

function M.parse(message)
    if type(message) ~= "string" then return nil end
    local trimmed = message:match("^%s*(.-)%s*$")
    if not trimmed then return nil end

    -- match bank
    local cmd, args = trimmed:match("^bank%s+(%S+)%s*(.*)$")
    if not cmd then return nil end

    cmd = cmd:lower()
    if cmd == "login" then
        -- args is the login code (may be empty)
        local code = args:match("^%s*(%S+)%s*$")
        return "login", code or ""
    end

    return nil
end

function M.handleChatEvent(message, username, onLogin)
    local cmd, args = M.parse(message)
    if cmd == "login" then
        if onLogin then
            onLogin(username, args)
        end
    end
end

return M