-- Transfer screen in two-steps: first select the recipient, then amount.
local Button = require "client.ui.button"
local ScreenManager = require "client.ui.screen_manager"
local Router = require "client.ui.router"
local Net = require "client.ui.net"
local Keypad = require "client.ui.keypad"
local constants = require "shared.constants"
local TextWrap = require "client.ui.textwrap"
local Draw = require "client.ui.draw"

local MainMenu = require "client.ui.screens.main_menu"

local Transfer = {}

local MAX_PLAYERS_PER_PAGE = 6

local drawConfirmStage

--- Draw the amount entry step
--- @param state     table shared state
--- @param acct      table current user account
--- @param recipient string target username
--- @param message?  string optional error banner
local function drawAmountStage(state, acct, recipient, message)
    local mon = state.monitor
    local lay = state.layout

    Draw.clear(mon)

    -- header
    Draw.header(mon, lay, "Transfer")

    mon.setTextColor(colors.white)
    local y = lay.headerRow + 1
    y = TextWrap.write(mon, "To: " .. recipient, 3, y)

    -- message
    if message then
        Draw.banner(mon, message, 2, y + 1)
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

            drawConfirmStage(state, acct, recipient, amount)
        end,
        onCancel = function()
            -- Go back to recipient
            Transfer.draw(state, acct)
        end
    })
end

--- Draw the confirmation step
--- @param state     table shared state
--- @param acct      table current user account
--- @param recipient string target username
--- @param amount    number amount to send
drawConfirmStage = function(state, acct, recipient, amount)
    local mon = state.monitor
    local lay = state.layout

    Draw.clear(mon)

    Draw.header(mon, lay, "Confirm Transfer")

    local y = lay.headerRow + 1
    mon.setTextColor(colors.white)
    y = TextWrap.write(mon, "Send to: " .. recipient, 3, y)
    y = TextWrap.write(mon, "Amount: $" .. string.format("%.2f", amount), 3, y)

    mon.setTextColor(colors.lime)
    y = TextWrap.write(mon, "Balance after: $" .. string.format("%.2f", (acct.balance or 0) - amount), 3, y)

    local confirmCb = function()
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
            elseif code == constants.ERROR.DESTINATION_NO_ACCOUNT then
                friendly = "Recipient '" .. recipient .. "' does not have a BlockBank account."
            elseif code == constants.ERROR.ACCOUNT_NOT_FOUND then
                friendly = "Your account was not found."
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
    end

    Draw.confirmCancelRow(mon, lay, confirmCb, function()
        -- Go back to the amount entry
        drawAmountStage(state, acct, recipient)
    end, "  Confirm  ", "  Cancel  ")
end

--- u know it, draw it!
--- @param state    table shared state
--- @param acct     table current user account
--- @param players  table list of online player usernames
--- @param page     number current page index
--- @param message? string optional error banner
local function drawRecipientStage(state, acct, players, page, message)
    local mon = state.monitor
    local lay = state.layout

    Draw.clear(mon)

    -- header
    Draw.header(mon, lay, "Pick Recipient")

    mon.setTextColor(colors.white)
    local y = lay.headerRow + 1
    y = TextWrap.write(mon, "From: " .. acct.username, 3, y)

    -- message
    if message then
        Draw.banner(mon, message, 2, y + 1)
    end

    -- Player list
    local listY = lay.headerRow + 3
    local listBottom = lay.confirmButtonRow - 3
    local playersPerPage = math.max(1, math.min(MAX_PLAYERS_PER_PAGE, math.floor((listBottom - listY + 1) / 2)))
    local startPage = (page - 1) * playersPerPage + 1
    local endPage = math.min(page * playersPerPage, #players)

    if #players == 0 then
        mon.setTextColor(colors.red)
        TextWrap.write(mon, "No other players online.", 4, listY)
    else
        local row = listY
        for i = startPage, endPage do
            local name = players[i]
            if name == acct.username then
                -- Skip self
                goto continue
            end
            local label = Draw.truncate(" " .. name, lay.width - 4)
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
            Draw.fillLine(mon, row + 1, math.min(20, lay.width - 5), { x = 4, bg = colors.gray })
            mon.setBackgroundColor(colors.black)

            row = row + 2
            if row + 1 > listBottom then
                break
            end
            ::continue::
        end
    end

    -- Pagination
    local totalPages = math.ceil(#players / playersPerPage)
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
        mon.setCursorPos(Draw.centerCol(lay, pageStr), lay.confirmButtonRow)
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


--- Entry point
--- @param state    table shared state
--- @param acct     table current user account
--- @param message? string optional error banner
function Transfer.draw(state, acct, message)
    local players = {}
    local payload, err = Net.sendAndReceive(state, constants.PACKET.GET_ONLINE_PLAYERS, {})
    if payload and payload.success and payload.data and payload.data.players then
        for _, name in ipairs(payload.data.players) do
            table.insert(players, name)
        end
    else
        -- empty list
    end

    drawRecipientStage(state, acct, players, 1, message)
end

return Transfer