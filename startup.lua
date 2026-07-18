function downloadFile(url, path)
    local remoteStream = nil
    local attempts = 0
    local maxAttempts = 5

    while remoteStream == nil and attempts < maxAttempts do
        attempts = attempts + 1
        remoteStream = http.get(url)
        if remoteStream == nil then
            print("Failed to download " .. url .. ". Attempt " .. attempts .. " of " .. maxAttempts .. ". Retrying..")
            sleep(2)
        end
    end

    if remoteStream == nil then
        print("ERROR: Failed to download " .. path .. " after " .. attempts .. " attempts.")
        return
    end

    local remoteFile = remoteStream.readAll()
    local localFileWrite = fs.open(path, "w")
    if not fs.exists(path) then
        localFileWrite.write(remoteFile)
        print(path, " downloaded")
    else
        local localFileRead = fs.open(path, "r")
        if remoteFile ~= localFileRead.readAll() then
            localFileWrite.write(remoteFile)
            print(path, " updated")
        end
        localFileRead.close()
    end
    localFileWrite.close()
end

-- ------------------------ CONFIG (SERVER OR CLIENT SETTING) ----------------------- --
local NODE_TYPE = "client"

downloadFile("https://raw.githubusercontent.com/alebogino/BlockVault/refs/heads/main/files.lua", "files")

os.loadAPI("files")

-- Download shared files (needed by both client and server)
for _, file in pairs(files.shared) do
    downloadFile(file.url, file.path)
end

-- Download node-specific files
local nodeFiles = nil
if NODE_TYPE == "server" then
    nodeFiles = files.server
elseif NODE_TYPE == "client" then
    nodeFiles = files.client
else
    print("ERROR: Unknown NODE_TYPE '" .. NODE_TYPE .. "'. Set to 'client' or 'server'.")
    return
end

for _, file in pairs(nodeFiles) do
    downloadFile(file.url, file.path)
end

print("Finished downloading " .. NODE_TYPE .. " files.")
print("Starting " .. NODE_TYPE .. " program...")

shell.run(NODE_TYPE .. "/main")