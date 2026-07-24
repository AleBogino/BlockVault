-- Start screen 

local Button = require "client.ui.button"
local ScreenManager = require "client.ui.screen_manager"
local Router = require "client.ui.router"
local Net = require "client.ui.net"
local constants = require "shared.constants"
local playerDetector = require "shared.player_detector"

local MainMenu = require "client.ui.screens.main_menu"

local Rest = {}

--- Draw da screen
--- @param state table shared state
--- @param message? string optional status/error message to display
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

    -- Status?
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
            Rest.draw(state, "Scanning for player...")

            local detectedUsername = playerDetector.detectOrRetry(
                state.playerDetector,
                constants.PLAYER_DETECT_RANGE
            )
            if not detectedUsername then
                Rest.draw(state, "No player detected. Tap Start to try again.")
                return
            end

            local payload, err = Net.sendAndReceive(state, constants.PACKET.GET_ACCOUNT, {
                username = detectedUsername
            })

            if not payload then
                Rest.draw(state, "Network error: " .. tostring(err))
                return
            end

            if not payload.success then
                local code = payload.code or "UNKNOWN"
                if code == constants.ERROR.ACCOUNT_NOT_FOUND then
                    Rest.drawCreateAccountPrompt(state, detectedUsername)
                elseif code == constants.ERROR.PERMISSION_DENIED then
                    Rest.draw(state, "Account belongs to a different user.")
                else
                    Rest.draw(state, "Server error: " .. code)
                end
                return
            end

            local acct = payload.data
            Router.switch(MainMenu, acct)
        end,
        { bg = colors.blue, fg = colors.white }
    )):draw(mon)
end

--- Create an account?
--- @param state table shared state
--- @param username string detected player name
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
                    Rest.draw(state, "You already have an account — logging in...")
                    -- Retry GET_ACCOUNT
                    local p2, e2 = Net.sendAndReceive(state, constants.PACKET.GET_ACCOUNT, { username = username })
                    if p2 and p2.success then
                        Router.switch(MainMenu, p2.data)
                    else
                        Rest.draw(state, "Login failed: " .. tostring(e2 or p2.code))
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