-- Shared drawing helpers for monitor screens.

local TextWrap = require "client.ui.textwrap"
local Button = require "client.ui.button"
local ScreenManager = require "client.ui.screen_manager"

local Draw = {}

--- Clear the monitor to black.
--- @param mon table wrapped monitor
function Draw.clear(mon)
    mon.setBackgroundColor(colors.black)
    mon.clear()
end

--- Clamp text to at most `width` characters.
--- @param text any (coerced to string)
--- @param width number
--- @return string
function Draw.truncate(text, width)
    if width < 1 then width = 1 end
    text = tostring(text)
    if #text > width then
        return text:sub(1, width)
    end
    return text
end

--- Centered column for `text` using a layout table (uses lay.width)<
--- @param lay table { width = number }
--- @param text string
--- @return number 1-based column
function Draw.centerCol(lay, text)
    return math.max(1, math.floor((lay.width - #tostring(text)) / 2) + 1)
end

--- Paint a whole (or partial) row with a background color.
--- Does not reset the background afterwards.
--- @param mon table wrapped monitor
--- @param y number row
--- @param width number number of columns to paint
--- @param opts? table { x = 1, bg = colors.black }
function Draw.fillLine(mon, y, width, opts)
    opts = opts or {}
    local x = opts.x or 1
    local bg = opts.bg or colors.black
    if width < 1 then width = 1 end
    mon.setBackgroundColor(bg)
    mon.setCursorPos(x, y)
    mon.write(string.rep(" ", width))
end

--- Paint a full-width bar and optionally center text on top of it.
--- @param mon table wrapped monitor
--- @param lay table layout
--- @param y number row
--- @param bg number background color
--- @param text? string optional centered text
--- @param fg? number text color (default colors.white)
function Draw.fullWidthBar(mon, lay, y, bg, text, fg)
    Draw.fillLine(mon, y, lay.width, { bg = bg })
    if text then
        mon.setTextColor(fg or colors.white)
        local t = Draw.truncate(text, lay.width)
        mon.setCursorPos(Draw.centerCol(lay, t), y)
        mon.write(t)
    end
end

--- Draw a horizontal rule of repeated chars, center label optional
--- @param mon table wrapped monitor
--- @param y number row
--- @param width number rule length
--- @param opts? table { x = 1, char = "-", fg = colors.gray, bg = colors.black, label = nil }
function Draw.textDivider(mon, y, width, opts)
    opts = opts or {}
    local x = opts.x or 1
    local char = opts.char or "-"
    local fg = opts.fg or colors.gray
    local bg = opts.bg or colors.black
    local label = opts.label

    local line
    if label then
        local t = tostring(label)
        local side = width - #t - 2
        if side < 0 then
            line = Draw.truncate(t, width)
        else
            local left = math.floor(side / 2)
            line = string.rep(char, left) .. " " .. t .. " " .. string.rep(char, side - left)
        end
    else
        line = string.rep(char, width)
    end

    mon.setBackgroundColor(bg)
    mon.setTextColor(fg)
    mon.setCursorPos(x, y)
    mon.write(line)
end

--- Draw the standard cyan screen title at the header row.
--- @param mon table wrapped monitor
--- @param lay table layout
--- @param title string
--- @param color? number (default colors.cyan)
function Draw.header(mon, lay, title, color)
    mon.setTextColor(color or colors.cyan)
    mon.setCursorPos(3, lay.headerRow)
    mon.write(title)
end

--- Write a yellow status/error banner starting at (x, y)
--- @param mon table wrapped monitor
--- @param message string
--- @param x number starting column
--- @param y number starting row
--- @return number the row immediately after the last written line
function Draw.banner(mon, message, x, y)
    mon.setTextColor(colors.yellow)
    return TextWrap.write(mon, message, x, y)
end

--- Write text centered using layout.width
--- @param mon table wrapped monitor
--- @param lay table layout
--- @param text string
--- @param y number starting row
--- @param maxWidth? number (default lay.width)
--- @return number the row immediately after the last written line
function Draw.writeCentered(mon, lay, text, y, maxWidth)
    local width = math.max(1, math.min(maxWidth or lay.width, lay.width))
    local lines = TextWrap.wrap(text, width)
    for i, line in ipairs(lines) do
        mon.setCursorPos(Draw.centerCol(lay, line), y + i - 1)
        mon.write(line)
    end
    return y + #lines
end

--- Draw a button horizontally centered on the screen.
--- @param mon table wrapped monitor
--- @param lay table layout
--- @param label string button text
--- @param y number top row
--- @param w number button width
--- @param h number button height
--- @param cb function onClick
--- @param opts? table { bg = color, fg = color }
--- @return table the button
function Draw.centeredButton(mon, lay, label, y, w, h, cb, opts)
    local x = math.max(1, math.floor((lay.width - w) / 2) + 1)
    local btn = Button.new(x, y, x + w - 1, y + h - 1, label, cb, opts)
    ScreenManager.register(btn):draw(mon)
    return btn
end

--- Standard confirm/cancel pair
--- @param mon table wrapped monitor
--- @param lay table layout
--- @param onConfirm? function (green button at confirmButtonRow - 2)
--- @param onCancel? function (gray button at confirmButtonRow)
--- @param confirmLabel? string (default "  Confirm  ")
--- @param cancelLabel? string (default "  Cancel  ")
function Draw.confirmCancelRow(mon, lay, onConfirm, onCancel, confirmLabel, cancelLabel)
    if onConfirm then
        Draw.centeredButton(mon, lay, confirmLabel or "  Confirm  ", lay.confirmButtonRow - 2, 14, 1, onConfirm, {
            bg = colors.green,
            fg = colors.white
        })
    end
    if onCancel then
        Draw.centeredButton(mon, lay, cancelLabel or "  Cancel  ", lay.confirmButtonRow, 14, 1, onCancel, {
            bg = colors.gray,
            fg = colors.white
        })
    end
end

--- Short display name for a coin id like "minecraft:iron_nugget".
--- @param coinId string
--- @return string
function Draw.shortCoinName(coinId)
    return coinId:match(":([^:]+)$") or coinId
end

return Draw
