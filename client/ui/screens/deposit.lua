local Router = require "client.ui.router"
local Net = require "client.ui.net"
local constants = require "shared.constants"
local ME = require "shared.me"
local TextWrap = require "client.ui.textwrap"
local Draw = require "client.ui.draw"

local MainMenu = require "client.ui.screens.main_menu"

local Deposit = {}
local PHASE = {
    INSERT = "insert",
    CONFIRM = "confirm"
}

local function drawInsert(state, acct, message)
    local mon = state.monitor
    local lay = state.layout

    Draw.clear(mon)

    Draw.header(mon, lay, "Deposit")

    mon.setTextColor(colors.white)
    local y = lay.headerRow + 1
    y = TextWrap.write(mon, "Insert your coins into the barrel now.", 3, y)

    if message then
        Draw.banner(mon, message, 2, y + 1)
    end

    local continueCb = function()
        local inv = state.inventoryMgr
        if not inv then
            Deposit.draw(state, acct, PHASE.INSERT, "No barrel configured on this terminal.")
            return
        end
        local total, breakdown, scanErr = inv:scan()
        if scanErr then
            print("[CLI][DEPOSIT] scan error: " .. tostring(scanErr))
            Deposit.draw(state, acct, PHASE.INSERT, scanErr)
            return
        end
        print(("[CLI][DEPOSIT] scan total=%d breakdown=%s"):format(total, textutils.serialize(breakdown or {})))
        Deposit.draw(state, acct, PHASE.CONFIRM, nil, breakdown, total)
    end

    Draw.confirmCancelRow(mon, lay, continueCb, function()
        Router.switch(MainMenu, acct)
    end, "  Continue  ", "  Back  ")
end

local function drawConfirm(state, acct, breakdown, total)
    local mon = state.monitor
    local lay = state.layout

    Draw.clear(mon)

    Draw.header(mon, lay, "Deposit Review")

    local y = lay.headerRow + 1
    mon.setTextColor(colors.white)

    if total <= 0 then
        mon.setTextColor(colors.yellow)
        y = TextWrap.write(mon, "No recognized coins found in the barrel.", 3, y)
    else
        mon.setCursorPos(3, y)
        mon.write("Coins found:")
        y = y + 1

        for _, coinId in ipairs(constants.COIN_ORDER) do
            local n = breakdown and breakdown[coinId]
            if n and n > 0 then
                local value = constants.COIN_VALUES[coinId] or 0
                local line = ("%d x %s = %d units"):format(n, Draw.shortCoinName(coinId), n * value)
                y = TextWrap.write(mon, line, 3, y)
            end
        end

        mon.setTextColor(colors.lime)
        y = TextWrap.write(mon, ("Total: %d"):format(total), 2, y)
    end

    mon.setTextColor(colors.white)
    y = TextWrap.write(mon, ("Balance: %d"):format(acct.balance or 0), 2, y)
    y = TextWrap.write(mon, ("After: %d"):format((acct.balance or 0) + total), 2, y)

    local available = state.inventoryMgr ~= nil and state.meBridge ~= nil
    if not available then
        mon.setTextColor(colors.red)
        TextWrap.write(mon, "Physical deposits unavailable on this terminal.", 3, y)
    end

    local confirmCb = nil
    if available and total > 0 then
        confirmCb = function()
            local inv = state.inventoryMgr
            local me = state.meBridge

                -- 1) Import coins from the barrel (adjacent to the ME Bridge on state.meSide)
                local imported, importedValue, importErrs = ME.importCoins(me, state.meSide, breakdown)
                print(("[CLI][DEPOSIT] import result: value=%d imported=%s errors=%s"):format(importedValue or 0,
                    textutils.serialize(imported or {}), textutils.serialize(importErrs or {})))

                if importedValue <= 0 then
                    local why = "No coins were imported."
                    if importErrs and next(importErrs) then
                        local firstCoin = next(importErrs)
                        why = "ME import failed: " .. tostring(importErrs[firstCoin])
                    end
                    print("[CLI][DEPOSIT] import failed: " .. why)
                    Deposit.draw(state, acct, PHASE.INSERT, why)
                    return
                end

                -- 2) Tell the server what was actually imported
                local payload, err = Net.sendAndReceive(state, constants.PACKET.DEPOSIT, {
                    username = acct.username,
                    amount = importedValue,
                    coinBreakdown = imported
                })

                if not payload then
                    -- Rollback: return coins to the barrel
                    ME.exportCoins(me, state.meSide, imported)
                    print("[CLI][DEPOSIT] network error - rollback: " .. tostring(err))
                    Deposit.draw(state, acct, PHASE.INSERT, "Network error - coins returned.")
                    return
                end

                if not payload.success then
                    -- Rollback: return coins to the barrel
                    ME.exportCoins(me, state.meSide, imported)
                    local code = payload.code or "UNKNOWN"
                    print("[CLI][DEPOSIT] server rejected: " .. code)
                    Deposit.draw(state, acct, PHASE.INSERT, "Deposit rejected (" .. code .. ") - coins returned.")
                    return
                end

                -- 3) Success
                local newBalance = payload.data and payload.data.balance or acct.balance
                acct.balance = newBalance
                Router.switch(MainMenu, acct, ("Deposited %d units. New balance: %d"):format(importedValue, newBalance))
        end
    end

    -- confirm / cancel buttons
    Draw.confirmCancelRow(mon, lay, confirmCb, function()
        Deposit.draw(state, acct, PHASE.INSERT)
    end, "  Confirm  ", "  Cancel  ")
end

--- @param state table shared state (needs .inventoryMgr and .meBridge)
--- @param acct table current account
--- @param phase? string PHASE.INSERT | PHASE.CONFIRM (defaults to INSERT)
--- @param message? string banner text (INSERT phase)
--- @param breakdown? table { [coinId] = count } (CONFIRM phase)
--- @param total? number total value (CONFIRM phase)
function Deposit.draw(state, acct, phase, message, breakdown, total)
    phase = phase or PHASE.INSERT
    if phase == PHASE.CONFIRM then
        drawConfirm(state, acct, breakdown, total)
    else
        drawInsert(state, acct, message)
    end
end

return Deposit
