-- Toast notification handler for the Advanced Peripherals Chat Box.

if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local Peripheral = require "shared.peripheral"

local M = {}

M.box = nil
M.warned = false

-- Chat Box cooldown (default 1 second)
local COOLDOWN_MS = 1000

M.queue = {}
M.lastSentAt = 0
M.timer = nil

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

--- Cancel any pending queue timer.
local function clearTimer()
    if M.timer then
        os.cancelTimer(M.timer)
        M.timer = nil
    end
end

--- Schedule the queue to be pumped when the cooldown expires
local function armTimer(seconds)
    clearTimer()
    if seconds <= 0 then seconds = 0.05 end
    M.timer = os.startTimer(seconds)
end

--- peripheral call for a plain toast
local function dispatch(player, title, message, options)
    if not M.box then
        return nil, "no chat_box peripheral attached"
    end

    M.lastSentAt = os.epoch("utc")

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

--- peripheral call for a formatted toast.
local function dispatchFormatted(player, titleJson, messageJson, options)
    if not M.box then
        return nil, "no chat_box peripheral attached"
    end

    M.lastSentAt = os.epoch("utc")

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

--- peripheral call for a plain chat message (optionally private to a player)
--- @param player  string|nil player name/uuid, nil broadcasts to everyone
--- @param message string  chat message
--- @param options table { prefix=, brackets=, bracketColor=, utf8= }
local function dispatchChat(player, message, options)
    if not M.box then
        return nil, "no chat_box peripheral attached"
    end

    M.lastSentAt = os.epoch("utc")

    local opts = {
        utf8         = options.utf8,
        prefix       = options.prefix or DEFAULTS.prefix,
        brackets     = options.brackets or DEFAULTS.brackets,
        bracketColor = options.bracketColor,
    }
    if player and player ~= "" then
        opts.player = player
    end

    local called, result, callErr = pcall(M.box.sendMessage, message, opts)
    if not called then
        print("[TOAST] chat send error for " .. tostring(player) .. ": " .. tostring(result))
        return nil, tostring(result)
    end
    if result == true then
        return true
    end
    local errMsg = tostring(callErr or result or "chat send failed")
    print("[TOAST] chat send failed for " .. tostring(player) .. ": " .. errMsg)
    return nil, errMsg
end

--- peripheral call for a formatted chat message (optionally private to a player)
--- @param player      string|nil player name/uuid, nil broadcasts to everyone
--- @param messageJson string|nil  JSON text component
--- @param options     table { prefix=, brackets=, bracketColor=, utf8= }
local function dispatchChatFormatted(player, messageJson, options)
    if not M.box then
        return nil, "no chat_box peripheral attached"
    end

    M.lastSentAt = os.epoch("utc")

    local opts = {
        utf8         = options.utf8,
        prefix       = options.prefix or DEFAULTS.prefix,
        brackets     = options.brackets or DEFAULTS.brackets,
        bracketColor = options.bracketColor,
    }
    if player and player ~= "" then
        opts.player = player
    end

    local called, result, callErr = pcall(M.box.sendFormattedMessage, messageJson, opts)
    if not called then
        print("[TOAST] formatted chat send error for " .. tostring(player) .. ": " .. tostring(result))
        return nil, tostring(result)
    end
    if result == true then
        return true
    end
    local errMsg = tostring(callErr or result or "formatted chat send failed")
    print("[TOAST] formatted chat send failed for " .. tostring(player) .. ": " .. errMsg)
    return nil, errMsg
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

    -- Respect the chat box cooldown
    local now = os.epoch("utc")
    if now - M.lastSentAt < COOLDOWN_MS then
        M.queue[#M.queue + 1] = {
            player = player,
            title = title,
            message = message,
            options = options,
            formatted = false,
        }
        armTimer((M.lastSentAt + COOLDOWN_MS - now) / 1000)
        return true
    end

    return dispatch(player, title, message, options)
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

    local now = os.epoch("utc")
    if now - M.lastSentAt < COOLDOWN_MS then
        M.queue[#M.queue + 1] = {
            player = player,
            titleJson = titleJson,
            messageJson = messageJson,
            options = options,
            formatted = true,
        }
        armTimer((M.lastSentAt + COOLDOWN_MS - now) / 1000)
        return true
    end

    return dispatchFormatted(player, titleJson, messageJson, options)
end

--- Send a plain chat message
--- @param player  string|nil  player name/uuid to privately message, or nil to broadcast
--- @param message string        chat message
--- @param options table|nil { prefix=, brackets=, bracketColor=, utf8= }
--- @return boolean|nil ok
--- @return string|nil err
function M.sendMessage(player, message, options)
    local ok, err = M.ready()
    if not ok then
        return nil, err
    end
    if type(message) ~= "string" or message == "" then
        return nil, "message required"
    end

    options = options or {}

    local now = os.epoch("utc")
    if now - M.lastSentAt < COOLDOWN_MS then
        M.queue[#M.queue + 1] = {
            player = player,
            message = message,
            options = options,
            chat = true,
        }
        armTimer((M.lastSentAt + COOLDOWN_MS - now) / 1000)
        return true
    end

    return dispatchChat(player, message, options)
end

--- Send a formatted chat message
--- @param player  string|nil  player name/uuid to privately message, or nil to broadcast
--- @param message string|table  JSON string or component table
--- @param options table|nil { prefix=, brackets=, bracketColor=, utf8= }
--- @return boolean|nil ok
--- @return string|nil err
function M.sendFormattedMessage(player, message, options)
    local ok, err = M.ready()
    if not ok then
        return nil, err
    end

    options = options or {}
    local messageJson = toJson(message)

    local now = os.epoch("utc")
    if now - M.lastSentAt < COOLDOWN_MS then
        M.queue[#M.queue + 1] = {
            player = player,
            messageJson = messageJson,
            options = options,
            chat = true,
            formatted = true,
        }
        armTimer((M.lastSentAt + COOLDOWN_MS - now) / 1000)
        return true
    end

    return dispatchChatFormatted(player, messageJson, options)
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

--- Process the queued toasts
function M.pump()
    if #M.queue == 0 then
        clearTimer()
        return
    end

    local now = os.epoch("utc")
    if now - M.lastSentAt < COOLDOWN_MS then
        armTimer((M.lastSentAt + COOLDOWN_MS - now) / 1000)
        return
    end

    local item = table.remove(M.queue, 1)
    if item.chat then
        if item.formatted then
            dispatchChatFormatted(item.player, item.messageJson, item.options)
        else
            dispatchChat(item.player, item.message, item.options)
        end
    elseif item.formatted then
        dispatchFormatted(item.player, item.titleJson, item.messageJson, item.options)
    else
        dispatch(item.player, item.title, item.message, item.options)
    end

    if #M.queue > 0 then
        local remaining = M.lastSentAt + COOLDOWN_MS - os.epoch("utc")
        armTimer(math.max(0, remaining) / 1000)
    else
        clearTimer()
    end
end

return M
