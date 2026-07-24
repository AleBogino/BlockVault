-- registry of buttons for a ScreenManager
local ScreenManager = {
    buttons = {}
}

--- Clear all buttons
function ScreenManager.reset()
    ScreenManager.buttons = {}
end

--- Register a button for this screen
--- @param btn table a Button object
--- @return btn table the same button
function ScreenManager.register(btn)
    table.insert(ScreenManager.buttons, btn)
    return btn
end

--- Touch event!
--- @param x number column
--- @param y number row
--- @return boolean true if handleed
function ScreenManager.dispatch(x, y)
    for i = #ScreenManager.buttons, 1, -1 do
        local btn = ScreenManager.buttons[i]
        if btn:contains(x, y) then
            btn.onClick()
            return true
        end
    end
    return false
end

return ScreenManager
