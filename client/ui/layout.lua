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
        inputFieldRow = h - 9,
        keypadOriginX = math.floor(w / 2) - 6,
        keypadOriginY = h - 7,
        confirmButtonRow = h - 1,
    }
end

return Layout