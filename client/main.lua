-- Client entrypoint
-- Run client/setup.lua first.

if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local crypto         = require "shared.crypto"
local identity       = require "shared.identity"
local config         = require "client.config"
local ClientProtocol = require "client.protocol"
local network        = require "client.network"
local constants      = require "shared.constants"
local ui             = require "client.ui"
 
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
    myId     = myId,
    mySk     = sk,
    myPk     = pk,
    serverId = serverInfo.serverId,
    serverPk = serverInfo.serverPk,
})

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

    local ok, runErr = pcall(ui.run, {
        clientProtocol = clientProtocol,
        network        = network,
        myId           = myId,
        sk             = sk,
        pk             = pk,
        serverId       = serverInfo.serverId,
        serverPk       = serverInfo.serverPk,
        connect        = connect,
    })
    if not ok then
        print("Unexpected error: " .. tostring(runErr))
        print("Press Enter to exit.")
        read()
    end
end
main()