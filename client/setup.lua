-- Run once per client, before main.lua, to record which server to trust
if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end


local config = require "client.config"
 
print("=== BlockVault Client Setup ===")
print("Enter the server's computer ID (shown on the server's screen):")
local serverId = read()
 
print("Enter the server's public key (hex, shown on the server's screen):")
local serverPkHex = read()
 
config.save(serverId, serverPkHex)
print("Saved. Run client/main.lua to connect.")
 
