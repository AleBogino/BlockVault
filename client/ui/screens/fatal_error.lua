-- Fatal error screen
-- Static state

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

        mon.setBackgroundColor(colors.black)
        mon.clear()

        local mid = math.max(2, math.floor(h / 2))

        -- Red band.
        mon.setBackgroundColor(colors.red)
        mon.setCursorPos(1, mid - 1)
        mon.write(string.rep(" ", w))

        -- Title on the band.
        local title = "Fatal error"
        mon.setTextColor(colors.white)
        mon.setCursorPos(math.max(1, math.floor((w - #title) / 2) + 1), mid - 1)
        mon.write(title)

        -- Subtitle below the band.
        local subtitle = "Contact maintenance"
        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
        mon.setCursorPos(math.max(1, math.floor((w - #subtitle) / 2) + 1), math.min(h, mid + 1))
        mon.write(subtitle)
    end)

    return ok
end

return FatalError
