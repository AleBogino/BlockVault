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
local ServerME = require "server.me"
local Toast = require "server.toast"
local Peripheral = require "shared.peripheral"

crypto.initRandom()

local sk, pk = identity.loadOrCreate("/data/identity.key")
local pkHex = ccutil.toHex(pk)

print("=== BlockVault Server ===")
print("Computer ID: " .. os.getComputerID())
print("Public key (hex), give this to every client you set up:")
print(pkHex)
print()

--- Copy the server's public key onto a disk drive's disk, if one is available
--- @param pkHex string hex-encoded public key
local function exportPublicKeyToDisk(pkHex)
    local cat = Peripheral.scan()
    local driveName = Peripheral.pickDrive(cat)
    if not driveName then
        print("[KEY] No disk drive found on wired network - skipping key export")
        return
    end

    local drive = peripheral.wrap(driveName)
    if not drive then
        print("[KEY] Could not wrap disk drive " .. tostring(driveName) .. " - skipping key export")
        return
    end

    local okData, hasData = pcall(function() return drive.hasData() end)
    if not okData or not hasData then
        print("[KEY] Disk drive " .. tostring(driveName) .. " has no data disk - skipping key export")
        return
    end

    local okPath, mountPath = pcall(function() return drive.getMountPath() end)
    if not okPath or not mountPath then
        print("[KEY] Could not get mount path for " .. tostring(driveName) .. " - skipping key export")
        return
    end

    local f = fs.open(mountPath .. "/server_public_key.txt", "w")
    if not f then
        print("[KEY] Could not open " .. mountPath .. "/server_public_key.txt - skipping key export")
        return
    end
    f.write(pkHex)
    f.close()
    print("[KEY] Public key written to " .. mountPath .. "/server_public_key.txt on " .. tostring(driveName))
end

exportPublicKeyToDisk(pkHex)

local ok, err = network.open()
if not ok then
    error("network.open() failed: " .. tostring(err))
end
print("Modem open. Listening for connections...")
Toast.init(network.chatBox)
if network.chatBox then
    print("Chat box detected. Chat login active. Players use: $bank login <code>")
else
    print("WARNING: No chat box attached - chat login will not work.")
end

-- Detect playerDetector for online player listing
local playerDetector = nil
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "playerDetector" then
        playerDetector = peripheral.wrap(name)
        print("Player detector found: " .. name)
        break
    end
end
if not playerDetector then
    print("WARNING: No playerDetector peripheral found! Online player list will be empty.")
end

local server = ServerProtocol.new({
    myId = os.getComputerID(),
    mySk = sk,
    myPk = pk,
    playerDetector = playerDetector
})

ServerME.init()

network.serveForever(server)
