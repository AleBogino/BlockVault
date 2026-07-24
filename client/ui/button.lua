-- rectangle u can touch :)

local Button = {}
Button.__index = Button

--- Create a new button object
--- @param x1 number left column
--- @param y1 number top row
--- @param x2 number right column
--- @param y2 number bottom row
--- @param label string text drawn (centered)
--- @param onClick function callback
--- @param opts? table { bg = color, fg = color}
function Button.new(x1, y1, x2, y2, label, onClick, opts)
    opts = opts or {}
    return setmetatable({
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        label = label,
        onClick = onClick,
        bg = opts.bg or colors.gray,
        fg = opts.fg or colors.white
    }, Button)
end

--- did u just touch it?
--- @param x number column
--- @param y number row
--- @return boolean
function Button:contains(x, y)
    return x >= self.x1 and x <= self.x2 and y >= self.y1 and y <= self.y2
end

--- Draw button
--- @param mon table wrapped monitor
function Button:draw(mon)
    mon.setBackgroundColor(self.bg)
    mon.setTextColor(self.fg)
    -- rectangle
    local fill = string.rep(" ", self.x2 - self.x1 + 1)
    for row = self.y1, self.y2 do
        mon.setCursorPos(self.x1, row)
        mon.write(fill)
    end
    -- text
    local midRow = math.floor((self.y1 + self.y2) / 2)
    local midCol = self.x1 + math.floor(((self.x2 - self.x1 + 1) - #self.label) / 2)
    mon.setCursorPos(midCol, midRow)
    mon.write(self.label)
end

return Button