-- Fatal error screen
-- Static state

local TextWrap = require "client.ui.textwrap"
local Draw = require "client.ui.draw"

local FatalError = {}

--- Draw the fatal error state.
--- @param state table shared state (uses state.monitor)
function FatalError.draw(state)
    local mon = state and state.monitor
    if not mon then
        return
    end

    local ok = pcall(function()
        local w, h = mon.getSize()
        local lay = { width = w, height = h }

        Draw.clear(mon)

        local mid = math.max(2, math.floor(h / 2))

        -- Red band.
        Draw.fillLine(mon, mid - 1, w, { bg = colors.red })

        -- Title on the band.
        local title = "Fatal error"
        mon.setTextColor(colors.white)
        mon.setCursorPos(Draw.centerCol(lay, title), mid - 1)
        mon.write(title)

        -- Subtitle below the band.
        local subtitle = "Contact maintenance"
        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
        local subtitleLines = TextWrap.wrap(subtitle, 15)
        for i, line in ipairs(subtitleLines) do
            mon.setCursorPos(Draw.centerCol(lay, line), math.min(h, mid + i))
            mon.write(line)
        end
    end)

    return ok
end

return FatalError
