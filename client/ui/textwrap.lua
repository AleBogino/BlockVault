-- Text wrapping helpers for monitor output.

local TextWrap = {}

local DEFAULT_MAX = 15

--- Split text into lines of at most maxWidth characters each.
--- Words are kept whole when possible; words longer than maxWidth are hard-broken.
--- Explicit newlines are preserved.
--- @param text string
--- @param maxWidth? number (default 15)
--- @return table list of line strings
function TextWrap.wrap(text, maxWidth)
    maxWidth = maxWidth or DEFAULT_MAX
    if maxWidth < 1 then maxWidth = 1 end
    text = tostring(text)

    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local current = ""
        for word in line:gmatch("%S+") do
            if #word > maxWidth then
                if current ~= "" then
                    table.insert(lines, current)
                    current = ""
                end
                local rest = word
                while #rest > maxWidth do
                    table.insert(lines, rest:sub(1, maxWidth))
                    rest = rest:sub(maxWidth + 1)
                end
                current = rest
            elseif current == "" then
                current = word
            elseif #current + 1 + #word <= maxWidth then
                current = current .. " " .. word
            else
                table.insert(lines, current)
                current = word
            end
        end
        table.insert(lines, current)
    end

    -- Drop trailing blank lines produced by the terminator newline.
    while #lines > 0 and lines[#lines] == "" do
        table.remove(lines)
    end

    if #lines == 0 then
        return { "" }
    end
    return lines
end

--- Smallest width that fits the monitor column
--- @param mon table wrapped monitor
--- @param x number starting column (1-based)
--- @param maxWidth? number requested max (default 15)
--- @return number
local function availableWidth(mon, x, maxWidth)
    maxWidth = maxWidth or DEFAULT_MAX
    local w = mon.getSize()
    local avail = w - x + 1
    if avail < 1 then avail = 1 end
    return math.max(1, math.min(maxWidth, avail))
end

--- Write text at (x, y), wrapping into multiple lines
--- @param mon table wrapped monitor
--- @param text string
--- @param x number starting column
--- @param y number starting row
--- @param maxWidth? number max chars per line (default 15)
--- @return number the row immediately after the last written line
function TextWrap.write(mon, text, x, y, maxWidth)
    local width = availableWidth(mon, x, maxWidth)
    local lines = TextWrap.wrap(text, width)
    for i, line in ipairs(lines) do
        mon.setCursorPos(x, y + i - 1)
        mon.write(line)
    end
    return y + #lines
end

--- Write text centred horizontally at row y
--- @param mon table wrapped monitor
--- @param text string
--- @param y number starting row
--- @param maxWidth? number max chars per line (default 15)
--- @return number the row immediately after the last written line
function TextWrap.writeCentered(mon, text, y, maxWidth)
    local w = mon.getSize()
    local width = math.max(1, math.min(maxWidth or DEFAULT_MAX, w))
    local lines = TextWrap.wrap(text, width)
    for i, line in ipairs(lines) do
        local col = math.max(1, math.floor((w - #line) / 2) + 1)
        mon.setCursorPos(col, y + i - 1)
        mon.write(line)
    end
    return y + #lines
end

return TextWrap
