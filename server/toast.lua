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
    title = title or DEFAULTS.prefix
    message = message or ""

    local called, result, callErr
    if M.box.sendToast then
        -- sendToast({ player, title, message, ... })
        called, result, callErr = pcall(M.box.sendToast, {
            player       = player,
            title        = title,
            message      = message,
            utf8         = options.utf8,
            prefix       = options.prefix or DEFAULTS.prefix,
            brackets     = options.brackets or DEFAULTS.brackets,
            bracketColor = options.bracketColor,
        })
    elseif M.box.sendToastToPlayer then
        -- sendToastToPlayer(message, title, username, prefix, brackets, bracketColor)
        called, result, callErr = pcall(M.box.sendToastToPlayer,
            message,
            title,
            player,
            options.prefix or DEFAULTS.prefix,
            options.brackets or DEFAULTS.brackets,
            options.bracketColor)
    else
        print("[TOAST] ERROR: chat box does not support sendToast")
        return nil, "chat box does not support sendToast"
    end

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
    local titleJson = toJson(title)
    local messageJson = toJson(message)

    local called, result, callErr
    if M.box.sendFormattedToast then
        -- sendFormattedToast({ player, title, message, ... })
        called, result, callErr = pcall(M.box.sendFormattedToast, {
            player       = player,
            title        = titleJson,
            message      = messageJson,
            utf8         = options.utf8,
            prefix       = options.prefix or DEFAULTS.prefix,
            brackets     = options.brackets or DEFAULTS.brackets,
            bracketColor = options.bracketColor,
        })
    elseif M.box.sendFormattedToastToPlayer then
        -- sendFormattedToastToPlayer(messageJson, titleJson, username, prefix, brackets, bracketColor)
        called, result, callErr = pcall(M.box.sendFormattedToastToPlayer,
            messageJson,
            titleJson,
            player,
            options.prefix or DEFAULTS.prefix,
            options.brackets or DEFAULTS.brackets,
            options.bracketColor)
    else
        print("[TOAST] ERROR: chat box does not support sendFormattedToast")
        return nil, "chat box does not support sendFormattedToast"
    end

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
