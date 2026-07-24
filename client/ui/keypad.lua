-- A touchable keypad!

local Button = require "client.ui.button"
local ScreenManager = require "client.ui.screen_manager"

local Keypad = {}
-- 3x4 grid
local LAYOUT = { "1 2 3", "4 5 6", "7 8 9", "C 0 <" }

--- Draw the keypad and register buttons
--- @param mon table wrapped monitor
--- @param layout table result of Layout.compute(mon)
--- @param state table shared state
--- @param opts? table {fieldLabel = string, onConfirm = fn, onCancel = fn}
function Keypad.draw(mon, layout, state, opts)
    opts = opts or {}
    local ox, oy = layout.keypadOriginX, layout.keypadOriginY

    -- input fieldLabel
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.setCursorPos(3, layout.inputFieldRow)
    local label = (opts.fieldLabel or "Amount") .. ": "
    local value = state.inputBuffer or ""
    local display = label .. value
    if #display > layout.width - 3 then
        display = display:sub(1, layout.width - 3)
    end
    mon.write(display)
    mon.write(string.rep(" ", math.max(0, layout.width - 3 - #display)))

    -- Numpad
    local keyW = 2
    for rowIdx, keysRow in ipairs(LAYOUT) do
        local col = ox
        for key in keysRow:gmatch("%S") do
            local btn = Button.new(
                col, oy + rowIdx - 1,
                col + 1, oy + rowIdx - 1,
                key,
                function()
                    if key == "C" then
                        state.inputBuffer = ""
                    elseif key == "<" then
                        state.inputBuffer = (state.inputBuffer or ""):sub(1, -2)
                    else
                        state.inputBuffer = (state.inputBuffer or "") .. key
                    end
                    Keypad.draw(mon, layout, state, opts)
                end,
                { bg = colors.lightGray, fg = colors.black }
            )
            ScreenManager.register(btn)
            btn:draw(mon)
            col = col + keyW
        end
    end

    -- Confirm / cancel row
    local confirmW = 6
    local cancelW  = 7
    local gap      = 2

    -- Confirm button
    if opts.onConfirm then
        ScreenManager.register(Button.new(
            ox, layout.confirmButtonRow,
            ox + confirmW - 1, layout.confirmButtonRow,
            "Confirm",
            opts.onConfirm,
            { bg = colors.green, fg = colors.white }
        )):draw(mon)
    end

    -- Cancel button
    if opts.onCancel then
        ScreenManager.register(Button.new(
            ox + confirmW + gap, layout.confirmButtonRow,
            ox + confirmW + gap + cancelW - 1, layout.confirmButtonRow,
            "Cancel",
            opts.onCancel,
            { bg = colors.red, fg = colors.white }
        )):draw(mon)
    end
end

return Keypad