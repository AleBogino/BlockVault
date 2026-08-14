if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local Button = require "client.ui.button"
local ScreenManager = require "client.ui.screen_manager"
local Router = require "client.ui.router"
local Net = require "client.ui.net"
local constants = require "shared.constants"

local MainMenu = require "client.ui.screens.main_menu"

local Rest = {}

-- How long to wait for LOGIN_OK after receiving the code (seconds)
local LOGIN_TIMEOUT = 30

--- Draw da screen
--- @param state table shared state
--- @param message? string optional status/error message
function Rest.draw(state, message)
    local mon = state.monitor
    local lay = state.layout

    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Title
    local title = "BlockBank ATM"
    mon.setTextColor(colors.cyan)
    local titleCol = math.floor((lay.width - #title) / 2) + 1
    mon.setCursorPos(titleCol, 4)
    mon.write(title)

    -- Tagline
    local tagline = "Give us your money, we'll keep it."
    mon.setTextColor(colors.lightGray)
    local tagCol = math.floor((lay.width - #tagline) / 2) + 1
    mon.setCursorPos(tagCol, 6)
    mon.write(tagline)

    -- Status message
    if message then
        mon.setTextColor(colors.yellow)
        local msgCol = math.floor((lay.width - #message) / 2) + 1
        mon.setCursorPos(msgCol, 9)
        mon.write(message)
    end

    -- Start button
    local btnW = 9
    local btnX = math.floor((lay.width - btnW) / 2) + 1
    local btnY = 12
    ScreenManager.register(Button.new(
        btnX, btnY, btnX + btnW - 1, btnY + 1,
        "  Start  ",
        function()
            Rest.startLogin(state)
        end,
        { bg = colors.blue, fg = colors.white }
    )):draw(mon)
end

--- Initiate the chat-based login flow
--- @param state table shared state
function Rest.startLogin(state)
    local mon = state.monitor
    local lay = state.layout

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
    local instruction = "Type in chat:"
    local command = ".bvault login " .. loginCode

    mon.setBackgroundColor(colors.black)
    mon.clear()

    mon.setTextColor(colors.cyan)
    local title = "BlockBank ATM"
    local titleCol = math.floor((lay.width - #title) / 2) + 1
    mon.setCursorPos(titleCol, 3)
    mon.write(title)

    mon.setTextColor(colors.white)
    local instrCol = math.floor((lay.width - #instruction) / 2) + 1
    mon.setCursorPos(instrCol, 5)
    mon.write(instruction)

    -- Display the command prominently
    mon.setTextColor(colors.green)
    mon.setBackgroundColor(colors.gray)
    local cmdCol = math.floor((lay.width - #command) / 2) + 1
    mon.setCursorPos(cmdCol, 7)
    mon.write(command)
    mon.setBackgroundColor(colors.black)

    mon.setTextColor(colors.lightGray)
    local hint = "Waiting for chat command..."
    local hintCol = math.floor((lay.width - #hint) / 2) + 1
    mon.setCursorPos(hintCol, 9)
    mon.write(hint)

    -- Cancel button
    local btnW = 9
    local btnX = math.floor((lay.width - btnW) / 2) + 1
    ScreenManager.reset()
    ScreenManager.register(Button.new(
        btnX, 12, btnX + btnW - 1, 13,
        "  Cancel  ",
        function()
            Rest.draw(state, "Login cancelled.")
        end,
        { bg = colors.gray, fg = colors.white }
    )):draw(mon)

    -- Step 4: Wait for LOGIN_OK / LOGIN_FAIL / LOGIN_TIMEOUT
    -- We use a timer-based wait loop
    local deadline = os.epoch("utc") + LOGIN_TIMEOUT * 1000
    while os.epoch("utc") < deadline do
        local remaining = math.max(0, math.ceil((deadline - os.epoch("utc")) / 1000))
        local pkt = state.network.receiveOnce(remaining)
        if pkt then
            local _, code, result, data = state.clientProtocol:handleLoginPacket(pkt)
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
                Rest.draw(state, "Login timed out. Please try again.")
                return
            end
        end
    end

    -- If we get here, the client-side timeout fired
    Rest.draw(state, "Login timed out. Please try again.")
end

--- Prompt to create a new account
--- @param state table shared state
--- @param username string detected player name from chat
function Rest.drawCreateAccountPrompt(state, username)
    local mon = state.monitor
    local lay = state.layout

    mon.setBackgroundColor(colors.black)
    mon.clear()

    mon.setTextColor(colors.yellow)
    local msg = "No account found for " .. username
    local col = math.floor((lay.width - #msg) / 2) + 1
    mon.setCursorPos(col, 4)
    mon.write(msg)

    local msg2 = "Create one?"
    col = math.floor((lay.width - #msg2) / 2) + 1
    mon.setCursorPos(col, 6)
    mon.write(msg2)

    -- Create Account button
    local btnW = 16
    local btnX = math.floor((lay.width - btnW) / 2) + 1
    ScreenManager.reset()
    ScreenManager.register(Button.new(
        btnX, 9, btnX + btnW - 1, 10,
        "Create Account",
        function()
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
        end,
        { bg = colors.green, fg = colors.white }
    )):draw(mon)

    -- Back button
    ScreenManager.register(Button.new(
        btnX, 12, btnX + btnW - 1, 13,
        "     Back     ",
        function()
            Rest.draw(state)
        end,
        { bg = colors.gray, fg = colors.white }
    )):draw(mon)
end

return Rest