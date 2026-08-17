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
    elseif cmd == "help" then
        return "help"
    elseif cmd == "transfer" then
        -- args is "<to> <amount>"
        return "transfer", args or ""
    elseif cmd == "list" then
        return "list"
    elseif cmd == "balance" then
        return "balance"
    end

    return nil
end

--- Handle chat command
--- @param message  string the (already $-stripped) chat message
--- @param username string the player who sent the message
--- @param handlers table { onLogin=, onHelp=, onTransfer=, onList=, onBalance= }
function M.handleChatEvent(message, username, handlers)
    handlers = handlers or {}
    local cmd, args = M.parse(message)
    if cmd == "login" then
        if handlers.onLogin then
            handlers.onLogin(username, args)
        end
    elseif cmd == "help" then
        if handlers.onHelp then
            handlers.onHelp(username)
        end
    elseif cmd == "transfer" then
        if handlers.onTransfer then
            handlers.onTransfer(username, args)
        end
    elseif cmd == "list" then
        if handlers.onList then
            handlers.onList(username)
        end
    elseif cmd == "balance" then
        if handlers.onBalance then
            handlers.onBalance(username)
        end
    end
end

return M