-- Transfer screen in two-steps: first select the recipient, then amount.
local Button = require "client.ui.button"
local ScreenManager = require "client.ui.screen_manager"
local Router = require "client.ui.router"
local Net = require "client.ui.net"
local Keypad = require "client.ui.keypad"
local constants = require "shared.constants"

local MainMenu = require "client.ui.screens.main_menu"

local Transfer = {}

local PLAYERS_PER_PAGE = 6

--- u know it, draw it!
--- @param state    table shared state
--- @param acct     table current user account
--- @param players  table list of online player usernames
--- @param page     number current page index
--- @param message? string optional error banner
local function drawRecipientStage(state, acct, players, page, message)
    local mon = state.monitor
    local lay = state.layout

    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- header
    mon.setTextColor(colors.cyan)
    mon.setCursorPos(3, lay.headerRow)
    mon.write("Transfer — Select Recipient")

    mon.setTextColor(colors.white)
    mon.setCursorPos(3, lay.headerRow + 1)
    mon.write("From: " .. acct.username)

    -- message
    if message then
        mon.setTextColor(colors.yellow)
        mon.setCursorPos(2, lay.headerRow + 2)
        mon.write(message:sub(1, lay.width - 2))
    end

    -- Player list
    local startPage = (page - 1) * PLAYERS_PER_PAGE + 1
    local endPage = math.min(page * PLAYERS_PER_PAGE, #players)
    local listY = lay.keypadOriginY - 1

    if #players == 0 then
        mon.setTextColor(colors.red)
        mon.setCursorPos(4, listY)
        mon.write("No other players online.")
    else
        local row = listY
        for i = startPage, endPage do
            local name = players[i]
            if name == acct.username then
                -- Skip self
                goto continue
            end
            local label = " " .. name .. string.rep(" ", 20 - #name)
            mon.setTextColor(colors.white)
            mon.setCursorPos(4, row)
            mon.write(label)

            -- Invisible button over the name row
            local btn = Button.new(4, row, lay.width - 3, row, "", function()
                -- Advance
                drawAmountStage(state, acct, name)
            end, {
                bg = colors.black,
                fg = colors.white
            })
            ScreenManager.register(btn)
            -- Draw underline
            mon.setBackgroundColor(colors.gray)
            mon.setCursorPos(4, row + 1)
            mon.write(string.rep(" ", math.min(20, lay.width - 5)))
            mon.setBackgroundColor(colors.black)

            row = row + 2
            if row > lay.keypadOriginY + 8 then
                break
            end
            ::continue::
        end
    end

    -- Pagination
    local totalPages = math.ceil(#players / PLAYERS_PER_PAGE)
    if totalPages > 1 then
        -- Prev page
        if page > 1 then
            ScreenManager.register(Button.new(2, lay.confirmButtonRow, 9, lay.confirmButtonRow, " < Prev  ", function()
                drawRecipientStage(state, acct, players, page - 1)
            end, {
                bg = colors.lightGray,
                fg = colors.black
            })):draw(mon)
        end

        -- Page indicator
        mon.setTextColor(colors.white)
        local pageStr = "Page " .. tostring(page) .. "/" .. tostring(totalPages)
        local pc = math.floor((lay.width - #pageStr) / 2) + 1
        mon.setCursorPos(pc, lay.confirmButtonRow)
        mon.write(pageStr)

        -- Next page
        if page < totalPages then
            ScreenManager.register(Button.new(lay.width - 10, lay.confirmButtonRow, lay.width - 2, lay.confirmButtonRow,
                " Next >  ", function()
                    drawRecipientStage(state, acct, players, page + 1)
                end, {
                    bg = colors.lightGray,
                    fg = colors.black
                })):draw(mon)
        end
    end

    -- cancel
    ScreenManager.register(Button.new(2, lay.confirmButtonRow - 2, 9, lay.confirmButtonRow - 2, " Cancel  ", function()
        Router.switch(MainMenu, acct)
    end, {
        bg = colors.red,
        fg = colors.white
    })):draw(mon)
end

--- Draw the amount entry step
--- @param state     table shared state
--- @param acct      table current user account
--- @param recipient string target username
--- @param message?  string optional error banner
local function drawAmountStage(state, acct, recipient, message)
    local mon = state.monitor
    local lay = state.layout

    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- header
    mon.setTextColor(colors.cyan)
    mon.setCursorPos(3, lay.headerRow)
    mon.write("Transfer")

    mon.setTextColor(colors.white)
    mon.setCursorPos(3, lay.headerRow + 1)
    mon.write("To: " .. recipient)

    -- message
    if message then
        mon.setTextColor(colors.yellow)
        mon.setCursorPos(2, lay.headerRow + 2)
        mon.write(message:sub(1, lay.width - 2))
    end

    state.inputBuffer = ""

    -- keypad
    Keypad.draw(mon, lay, state, {
        fieldLabel = "Amount",
        onConfirm = function()
            local amount = tonumber(state.inputBuffer)
            if not amount or amount <= 0 then
                drawAmountStage(state, acct, recipient, "Invalid amount. Enter a positive number.")
                return
            end

            local payload, err = Net.sendAndReceive(state, constants.PACKET.TRANSFER, {
                from = acct.username,
                to = recipient,
                amount = amount
            })

            if not payload then
                drawAmountStage(state, acct, recipient, "Network error: " .. tostring(err))
                return
            end

            if not payload.success then
                local code = payload.code or "UNKNOWN"
                local friendly
                if code == constants.ERROR.INSUFFICIENT_FUNDS then
                    friendly = "Insufficient funds."
                elseif code == constants.ERROR.ACCOUNT_NOT_FOUND then
                    friendly = "Recipient '" .. recipient .. "' does not have a BlockBank account."
                elseif code == constants.ERROR.PERMISSION_DENIED then
                    friendly = "You can only transfer from your own account."
                else
                    friendly = "Error: " .. code
                end
                drawAmountStage(state, acct, recipient, friendly)
                return
            end

            -- Success
            acct.balance = payload.data.fromBalance
            local successMsg = "Sent $" .. tostring(amount) .. " to " .. recipient .. ". New balance: $" ..
                                   tostring(payload.data.fromBalance)
            Router.switch(MainMenu, acct, successMsg)
        end,
        onCancel = function()
            -- Go back to recipient selection
            Transfer.draw(state, acct)
        end
    })
end


--- Entry point
--- @param state    table shared state
--- @param acct     table current user account
--- @param message? string optional error banner
function Transfer.draw(state, acct, message)
    local players = {}
    if state.playerDetector then
        local ok, list = pcall(function()
            return state.playerDetector.getOnlinePlayers()
        end)
        if ok and type(list) == "table" then
            for _, name in ipairs(list) do
                table.insert(players, name)
            end
        end
    end

    drawRecipientStage(state, acct, players, 1, message)
end

return Transfer