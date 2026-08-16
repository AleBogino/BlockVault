--- Shared positions constants for a monitor
local Layout = {}

--- Computer, get this monitor constants
--- @param mon table wrapped monitor
--- @return table { width, height, headerRow, inputFieldRow, keypadOriginX, keypadOriginY, confirmButtonRow}
function Layout.compute(mon)
    local w, h = mon.getSize()
    return {
        width  = w,
        height = h,
        headerRow = 2,
        inputFieldRow = math.max(2, h - 9),
        keypadOriginX = math.max(1, math.floor(w / 2) - 6),
        keypadOriginY = math.max(4, h - 7),
        confirmButtonRow = math.max(2, h - 2),
    }
end

return Layout