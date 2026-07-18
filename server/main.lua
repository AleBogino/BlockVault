-- Server entry point
-- Prerequisites: tools/install-ccryptolib.lua has been run, and a wireless modem is attached

if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local crypto = require "shared.crypto"
local identity = require "shared.identity"
local ccutil = require "ccryptolib.util"
local ServerProtocol = require "server.protocol"
local network = require "server.network"

crypto.initRandom()

local sk, pk = identity.loadOrCreate("/data/identity.key")

print("=== BlockVault Server ===")
print("Computer ID: " .. os.getComputerID())
print("Public key (hex), give this to every client you set up:")
print(ccutil.toHex(pk))
print()

local ok, err = network.open()
if not ok then
    error("network.open() failed: " .. tostring(err))
end
print("Modem open. Listening for connections...")

local server = ServerProtocol.new({
    myId = os.getComputerID(),
    mySk = sk,
    myPk = pk,
})
 
network.serveForever(server)
