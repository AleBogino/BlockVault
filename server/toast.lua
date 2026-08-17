-- Toast notification handler for the Advanced Peripherals Chat Box.

if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local Peripheral = require "shared.peripheral"

local M = {}

M.box = nil
M.warned = false

local DEFAULTS = {
    prefix   = "Bank",
    brackets = "[]",
}

--- Serialise a table into a JSON
local function toJson(value)
    if type(value) ~= "table" then
        return value
    end
    if textutils and textutils.serialiseJSON then
        local ok, json = pcall(textutils.serialiseJSON, value)
        if ok then return json end
    end
    if textutils and textutils.serializeJSON then
        local ok, json = pcall(textutils.serializeJSON, value)
        if ok then return json end
    end
    return nil
end

--- Register chatbox
--- @param chatBox table|nil
--- @return boolean ok
function M.init(chatBox)
    M.box = chatBox
    return M.box ~= nil
end

--- Find and wrap chatbox
--- @return table|nil box
--- @return string|nil side
function M.find()
    local cat = Peripheral.scan()
    local name = Peripheral.first(cat.chatBoxes)
    if name then
        return peripheral.wrap(name), name
    end
    return nil, nil
end

--- Make sure a chatbox is available
--- @return boolean ok
--- @return string|nil err
function M.ready()
    if M.box then
        return true
    end
    M.box = M.find()
    if not M.box then
        if not M.warned then
            print("[TOAST] WARNING: no chat_box peripheral found - toasts disabled")
            M.warned = true
        end
        return false, "no chat_box peripheral attached"
    end
    return true
end

--- Send a plain toast notification.
--- @param player  string  player name or uuid (required)
--- @param title   string  toast title (required)
--- @param message string  toast message (required)
--- @param options table|nil { prefix=, brackets=, bracketColor=, utf8= }
--- @return boolean ok
--- @return string|nil err
function M.send(player, title, message, options)
    local ok, err = M.ready()
    if not ok then
        return nil, err
    end
    if type(player) ~= "string" or player == "" then
        return nil, "player name required"
    end

    options = options or {}
    local payload = {
        player       = player,
        title        = title or DEFAULTS.prefix,
        message      = message or "",
        utf8         = options.utf8,
        prefix       = options.prefix or DEFAULTS.prefix,
        brackets     = options.brackets or DEFAULTS.brackets,
        bracketColor = options.bracketColor,
    }
    local method = M.box.sendToast or M.box.sendToastToPlayer
    if not method then
        print("[TOAST] ERROR: chat box does not support sendToast")
        return nil, "chat box does not support sendToast"
    end

    local called, result, callErr = pcall(method, M.box, payload)
    if not called then
        print("[TOAST] send error for " .. tostring(player) .. ": " .. tostring(result))
        return nil, tostring(result)
    end
    if result == true then
        return true
    end
    local errMsg = tostring(callErr or result or "toast send failed")
    print("[TOAST] send failed for " .. tostring(player) .. ": " .. errMsg)
    return nil, errMsg
end

--- Send a toast with title and message
--- @param player  string
--- @param title   string|table  JSON string or component table
--- @param message string|table  JSON string or component table
--- @param options table|nil { prefix=, brackets=, bracketColor=, utf8= }
--- @return boolean ok
--- @return string|nil err
function M.sendFormatted(player, title, message, options)
    local ok, err = M.ready()
    if not ok then
        return nil, err
    end
    if type(player) ~= "string" or player == "" then
        return nil, "player name required"
    end

    options = options or {}
    local payload = {
        player       = player,
        title        = toJson(title),
        message      = toJson(message),
        utf8         = options.utf8,
        prefix       = options.prefix or DEFAULTS.prefix,
        brackets     = options.brackets or DEFAULTS.brackets,
        bracketColor = options.bracketColor,
    }

    local method = M.box.sendFormattedToast or M.box.sendFormattedToastToPlayer
    if not method then
        return nil, "chat box does not support sendFormattedToast"
    end

    local called, result, callErr = pcall(method, M.box, payload)
    if not called then
        print("[TOAST] formatted send error for " .. tostring(player) .. ": " .. tostring(result))
        return nil, tostring(result)
    end
    if result == true then
        return true
    end
    local errMsg = tostring(callErr or result or "formatted toast send failed")
    print("[TOAST] formatted send failed for " .. tostring(player) .. ": " .. errMsg)
    return nil, errMsg
end

-- ---------------------------- convenience wrappers ---------------------------- --

--- Quick toast with the default "Bank" title.
function M.notify(player, message, options)
    return M.send(player, DEFAULTS.prefix, message, options)
end

function M.info(player, message, options)
    return M.send(player, "Info", message, options)
end

function M.success(player, message, options)
    return M.send(player, "Success", message, options)
end

function M.warn(player, message, options)
    return M.send(player, "Warning", message, options)
end

function M.error(player, message, options)
    return M.send(player, "Error", message, options)
end

return M
