-- Client entrypoint
-- Run client/setup.lua first.
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local crypto = require "shared.crypto"
local identity = require "shared.identity"
local config = require "client.config"
local ClientProtocol = require "client.protocol"
local network = require "client.network"
local constants = require "shared.constants"
local ui = require "client.ui"
local Peripheral = require "shared.peripheral"
local Inventory = require "client.inventory"
local ME = require "shared.me"
local FatalError = require "client.ui.screens.fatal_error"
local activeMonitor = nil

--- Show the fatal error state on the ATM screen and the computer's terminal.
--- @param err any the original error (optional)
local function showFatalError(err)
    print("Fatal error")
    print("Contact maintenance")
    if err then
        print("Details: " .. tostring(err))
    end

    if activeMonitor then
        pcall(FatalError.draw, { monitor = activeMonitor })
    end
end

local function detectMonitor()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            local candidate = peripheral.wrap(name)
            if candidate.isColor and candidate.isColor() then
                print("Advanced monitor found: " .. name)
                return candidate
            end
        end
    end
    return nil
end

--- Everything that can stop the client with an error
local function run()
    crypto.initRandom()

    local serverInfo = config.load()
    if not serverInfo then
        error("No server.cfg found -- run client/setup.lua first.")
    end

    local sk, pk = identity.loadOrCreate("/data/identity.key")

    local ok, err = network.open()
    if not ok then
        error("network.open() failed: " .. tostring(err))
    end

    local myId = os.getComputerID()
    local clientProtocol = ClientProtocol.new({
        myId = myId,
        mySk = sk,
        myPk = pk,
        serverId = serverInfo.serverId,
        serverPk = serverInfo.serverPk
    })

    local monitor = detectMonitor()
    if not monitor then
        error("No Monitor found! An Advanced Monitor is required for the ATM UI.")
    end
    activeMonitor = monitor

    monitor.setTextScale(0.5)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local cat = Peripheral.scan()

    -- barrel 4 da coins
    local inventoryMgr = nil
    local barrelName = Peripheral.first(cat.inventories)
    if barrelName then
        local inv, invErr = Inventory.new(barrelName)
        if inv then
            inventoryMgr = inv
            print("Deposit barrel: " .. tostring(barrelName))
        else
            print("WARNING: " .. tostring(invErr))
        end
    else
        print("WARNING: No inventory peripheral found - physical deposits disabled.")
    end

    -- ME bridge
    local meBridge = nil
    local meName = Peripheral.first(cat.meBridges)
    if meName then
        meBridge = ME.wrap(meName)
        if meBridge and ME.isConnected(meBridge) then
            print("ME Bridge ready: " .. tostring(meName))
        else
            print("WARNING: ME Bridge not connected to an AE2 network: " .. tostring(meName))
            meBridge = nil
        end
    else
        print("WARNING: No ME Bridge found: physical deposits disabled.")
    end

    local function connect()
        print("Connecting to BlockVault server " .. serverInfo.serverId .. "...")
        local connected, hsErr = network.handshake(clientProtocol, 10)
        if not connected then
            return false, hsErr
        end
        sleep(0.5)
        print("Connected. Session established with BlockVault.")
        return true, nil
    end

    local function main()
        local connected, hsErr = connect()
        if not connected then
            print("Handshake failed: " .. tostring(hsErr))
            print("Retry? (y/n)")
            if read():lower() == "y" then
                return main()
            end
            return
        end

        ui.run({
            clientProtocol = clientProtocol,
            network = network,
            myId = myId,
            sk = sk,
            pk = pk,
            serverId = serverInfo.serverId,
            serverPk = serverInfo.serverPk,
            connect = connect,
            monitor = monitor,
            inventoryMgr = inventoryMgr,
            meBridge = meBridge,
            meSide = constants.ME_BARREL_SIDE
        })
    end
    main()
end

-- Any code-stopping error shows the fatal error screen.
local ok, err = xpcall(run, debug.traceback)
if not ok then
    showFatalError(err)
end
