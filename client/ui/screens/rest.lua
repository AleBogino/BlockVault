if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local ScreenManager = require "client.ui.screen_manager"
local Router = require "client.ui.router"
local Layout = require "client.ui.layout"
local Net = require "client.ui.net"
local constants = require "shared.constants"
local packet = require "shared.packet"
local Draw = require "client.ui.draw"

local MainMenu = require "client.ui.screens.main_menu"

local Rest = {}

-- How long to wait for LOGIN_OK after receiving the code (seconds)
local LOGIN_TIMEOUT = 30
local LOGIN_REDRAW_INTERVAL = 2

--- Draw da screen
--- @param state table shared state
--- @param message? string optional status/error message
function Rest.draw(state, message)
    local mon = state.monitor
    local lay = state.layout

    ScreenManager.reset()
    Draw.clear(mon)

    -- Title
    local title = "BlockBank ATM"
    mon.setTextColor(colors.cyan)
    mon.setCursorPos(Draw.centerCol(lay, title), 4)
    mon.write(title)

    -- Tagline
    local tagline
    if lay.width >= 32 then
        tagline = "Give us your money, we'll keep it."
    else
        tagline = "Coin banking"
    end
    mon.setTextColor(colors.lightGray)
    Draw.writeCentered(mon, lay, tagline, 6)

    -- Status message
    if message then
        mon.setTextColor(colors.yellow)
        Draw.writeCentered(mon, lay, message, 9)
    end

    -- Start button
    Draw.centeredButton(mon, lay, "  Start  ", 14, 11, 3, function()
        Rest.startLogin(state)
    end, { bg = colors.blue, fg = colors.white })
end

--- Draw the "wait for chat login" screen
--- @param state table shared state
--- @param loginCode string the code the player must type in chat
--- @param flags table { cancelled = boolean } shared with the login loop
local function drawLoginWait(state, loginCode, flags)
    local mon = state.monitor
    local lay = state.layout

    Draw.clear(mon)

    mon.setTextColor(colors.cyan)
    local title = "BlockBank ATM"
    mon.setCursorPos(Draw.centerCol(lay, title), 3)
    mon.write(title)

    mon.setTextColor(colors.white)
    local instruction = "Type in chat:"
    mon.setCursorPos(Draw.centerCol(lay, instruction), 5)
    mon.write(instruction)

    -- Split the command so the 4-char code is never clipped on narrow screens
    local cmdPrefix = "$.bvault login"
    mon.setTextColor(colors.green)
    mon.setBackgroundColor(colors.white)
    mon.setCursorPos(Draw.centerCol(lay, cmdPrefix), 7)
    mon.write(cmdPrefix)

    mon.setCursorPos(Draw.centerCol(lay, loginCode), 8)
    mon.write(loginCode)
    mon.setBackgroundColor(colors.black)

    mon.setTextColor(colors.lightGray)
    Draw.writeCentered(mon, lay, "Waiting for chat", 10)

    ScreenManager.reset()
    Draw.centeredButton(mon, lay, "  Cancel  ", 15, 9, 3, function()
        flags.cancelled = true
    end, { bg = colors.gray, fg = colors.white })
end

--- Initiate the chat-based login flow
--- @param state table shared state
function Rest.startLogin(state)
    -- Step 1: Send LOGIN_REQUEST
    Rest.draw(state, "Connecting to server...")

    local session = state.clientProtocol.session
    if not session then
        -- No session, need to reconnect first
        local connected, err = state.connect()
        if not connected then
            Rest.draw(state, "Connection failed: " .. tostring(err))
            return
        end
        session = state.clientProtocol.session
    end

    local loginPkt = state.clientProtocol:sendLoginRequest()
    state.network.send(state.serverId, loginPkt)

    -- Step 2: Wait for LOGIN_AWAIT_CHAT with the code
    local reply = state.network.receiveOnce(10)
    if not reply then
        Rest.draw(state, "No response from server. Try again.")
        return
    end

    local _, loginCode, loginResult, accountData =
        state.clientProtocol:handleLoginPacket(reply)

    if not loginCode then
        Rest.draw(state, "Login error. Please try again.")
        return
    end

    -- Step 3: Display the code and wait for user to type it in chat
    local flags = { cancelled = false }
    drawLoginWait(state, loginCode, flags)

    -- Step 4: Wait for LOGIN_OK / LOGIN_FAIL / LOGIN_TIMEOUT, or a tap on Cancel.
    local loginTimer = os.startTimer(LOGIN_TIMEOUT)
    local redrawTimer = os.startTimer(LOGIN_REDRAW_INTERVAL)
    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" then
            ScreenManager.dispatch(p2, p3)
            if flags.cancelled then
                break
            end

        elseif event == "rednet_message" then
            -- p1 = senderId, p2 = message, p3 = protocol
            if p3 == state.network.PROTOCOL and packet.validate(p2) then
                local _, _, result, data = state.clientProtocol:handleLoginPacket(p2)
                if result == "LOGGED_IN" then
                    if data and not data.newAccount then
                        Router.switch(MainMenu, data)
                    elseif data and data.newAccount then
                        Rest.drawCreateAccountPrompt(state, data.username)
                    else
                        Rest.draw(state, "Invalid account data received.")
                    end
                    return
                elseif result == "LOGIN_FAIL" then
                    local reason = data and data.reason or "Unknown error"
                    Rest.draw(state, "Login failed: " .. reason)
                    return
                elseif result == "LOGIN_TIMEOUT" then
                    Rest.draw(state, "Timed out. Try again.")
                    return
                end
            end

        elseif event == "timer" and p1 == loginTimer then
            Rest.draw(state, "Timed out. Try again.")
            return

        elseif event == "timer" and p1 == redrawTimer then
            local m = state.refreshMonitor and state.refreshMonitor() or state.monitor
            if m then
                state.monitor = m
                local okLay, newLay = pcall(Layout.compute, m)
                if okLay then state.layout = newLay end
                drawLoginWait(state, loginCode, flags)
            end
            redrawTimer = os.startTimer(LOGIN_REDRAW_INTERVAL)
        end
    end

    Rest.draw(state, "Login cancelled.")
end

--- Prompt to create a new account
--- @param state table shared state
--- @param username string detected player name from chat
function Rest.drawCreateAccountPrompt(state, username)
    local mon = state.monitor
    local lay = state.layout

    Draw.clear(mon)

    mon.setTextColor(colors.yellow)
    Draw.writeCentered(mon, lay, "No account for " .. username, 4)

    local msg2 = "Create one?"
    mon.setCursorPos(Draw.centerCol(lay, msg2), 6)
    mon.write(msg2)

    -- Create Account button
    local btnW = math.min(16, lay.width)
    ScreenManager.reset()
    Draw.centeredButton(mon, lay, "Create Account", 9, btnW, 2, function()
            local payload, err = Net.sendAndReceive(state, constants.PACKET.CREATE_ACCOUNT, {
                username = username,
                initialBalance = 100,
            })
            if not payload then
                Rest.draw(state, "Error: " .. tostring(err))
            elseif not payload.success then
                local code = payload.code or "UNKNOWN"
                if code == "USERNAME_TAKEN" then
                    Rest.draw(state, "Username '" .. username .. "' is already taken.")
                elseif code == "ALREADY_HAS_ACCOUNT" then
                    Rest.draw(state, "You already have an account.")
                    local p2, e2 = Net.sendAndReceive(state, constants.PACKET.GET_ACCOUNT, { username = username })
                    if p2 and p2.success then
                        Router.switch(MainMenu, p2.data)
                    else
                        Rest.draw(state, "Login failed: " .. tostring(e2 or (p2 and p2.code)))
                    end
                else
                    Rest.draw(state, "Server error: " .. code)
                end
            else
                Rest.draw(state, "Account created! Tap Start to log in.")
            end
        end, { bg = colors.green, fg = colors.white })

    -- Back button
    Draw.centeredButton(mon, lay, "     Back     ", 12, btnW, 2, function()
        Rest.draw(state)
    end, { bg = colors.gray, fg = colors.white })
end

return Rest