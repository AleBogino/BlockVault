local BASE = "https://raw.githubusercontent.com/migeyel/ccryptolib/v1.2.2/ccryptolib/"
 
local FILES = {
    "random.lua",
    "ed25519.lua",
    "x25519.lua",
    "sha256.lua",
    "aead.lua",
    "blake3.lua",
    "chacha20.lua",
    "poly1305.lua",
    "util.lua",
    "internal/curve25519.lua",
    "internal/edwards25519.lua",
    "internal/fp.lua",
    "internal/fq.lua",
    "internal/mp.lua",
    "internal/packing.lua",
    "internal/sha512.lua",
    "internal/util.lua",
}
 
if not http then
    error("HTTP API is disabled on this server; enable it (and allow " ..
        "raw.githubusercontent.com) in the CC:Tweaked server config to " ..
        "install ccryptolib.")
end
 
local installed, failed = 0, {}
 
for _, path in ipairs(FILES) do
    local dest = "/ccryptolib/" .. path
    local dir = dest:match("^(.*)/[^/]+$")
    if dir and not fs.exists(dir) then
        fs.makeDir(dir)
    end
 
    if fs.exists(dest) then
        print("skip (exists): " .. dest)
        installed = installed + 1
    else
        local resp = http.get(BASE .. path)
        if resp then
            local f = fs.open(dest, "w")
            f.write(resp.readAll())
            f.close()
            resp.close()
            print("installed: " .. dest)
            installed = installed + 1
        else
            print("FAILED: " .. path)
            table.insert(failed, path)
        end
    end
end
 
print(("\n%d/%d files installed."):format(installed, #FILES))
if #failed > 0 then
    print("Failed files (retry, or check network settings):")
    for _, f in ipairs(failed) do print("  " .. f) end
end
