-- persistent storage for the server
-- idea for this one is atomicity, first we create a temp db file
-- then replace the old one with the new one
local M = {}

local DATA_DIR = "data"
local ACCOUNTS_FILE = "data/accounts.db"
local TRANSACTIONS_FILE = "data/transactions.db"
local KEYS_FILE = "data/keys.db"

-- --------------------------------- Helpers -------------------------------- --
local function ensureDataDir()
    if not fs.exists(DATA_DIR) then
        fs.makeDir(DATA_DIR)
    end
end

local function cleanupTmpFiles()
    local tmpFiles = {ACCOUNTS_FILE .. ".tmp", TRANSACTIONS_FILE .. ".tmp", KEYS_FILE .. ".tmp"}
    for _, tmpPath in ipairs(tmpFiles) do
        if fs.exists(tmpPath) then
            fs.delete(tmpPath)
        end
    end
end

--- Read table
--- @param path string
--- @return table
local function readTable(path)
    if not fs.exists(path) then
        return {} -- first time will return empty
    end
    local f = fs.open(path, "r")
    local raw = f.readAll()
    f.close()
    if raw == nil or raw == "" then
        return {} -- also empty if file is empty :)
    end
    local ok, result = pcall(textutils.unserialize, raw)
    if not ok or type(result) ~= "table" then
        return {}
    end
    return result
end

--- Write table
--- @param path string destination file
--- @param data table the table to write
--- @return boolean ok
--- @return string|nil error
local function writeTable(path, data)
    ensureDataDir()
    local tmpPath = path .. ".tmp"

    -- Serialize and write temp
    local serialized
    local ok, serResult = pcall(textutils.serialize, data, {
        compact = true
    })
    if not ok then
        return false, "Serialize failed: " .. tostring(serResult)
    end
    serialized = serResult

    local f, openErr = fs.open(tmpPath, "w")
    if not f then
        return false, "Open tmp file failed: " .. tostring(openErr)
    end

    f.write(serialized)
    f.close()

    -- remove old file
    if fs.exists(path) then
        fs.delete(path)
    end

    -- rename tmp to original
    local moveOk, moveErr = pcall(fs.move, tmpPath, path)
    if not moveOk then
        -- fallback: copy + delete
        local src = fs.open(tmpPath, "r")
        if src then
            local content = src.readAll()
            src.close()
            local dst = fs.open(path, "w")
            if dst then
                dst.write(content)
                dst.close()
                fs.delete(tmpPath)
                return true
            end
        end
        return false, "Move tmp to original failed: " .. tostring(moveErr)
    end
    return true
end

--- Generate unique transaction id
--- @return string
local function generateTxId()
    return "tx_" .. tostring(os.epoch("utc")) .. "_" .. tostring(math.random(10000, 99999))
end

--- Generate unique account ID (incremental casero)
--- @param accounts table
--- @return string
local function generateAccountId(accounts)
    local maxId = 0

    for _, account in pairs(accounts) do
        local numId = tonumber(account.id)
        if numId and numId > maxId then
            maxId = numId
        end
    end

    return tostring(maxId + 1)
end

-- -------------------------------- Accounts -------------------------------- --
---Retrieve an account record by username
--- @param username string
--- @return table|nil account record, nil if not found
function M.getAccount(username)
    if type(username) ~= "string" or username == "" then
        return nil
    end
    local accounts = readTable(ACCOUNTS_FILE)
    return accounts[username]
end

--- Retrieve an account by its ID
--- @param accountId string
--- @return table|nil
function M.getAccountById(accountId)
    if type(accountId) ~= "string" or accountId == "" then
        return nil
    end
    local accounts = readTable(ACCOUNTS_FILE)
    for _, acct in pairs(accounts) do
        if acct.id == accountId then
            return acct
        end
    end
    return nil
end

--- List all accounts
--- @return table array of account records
function M.listAccounts()
    local accounts = readTable(ACCOUNTS_FILE)
    local result = {}
    for _, acct in pairs(accounts) do
        result[#result + 1] = acct
    end
    return result
end

--- Create or update an account. If the username already exists record is overwritten
--- @param record table {username, balance, permission, publicKey, ... }
--- @return boolean ok
--- @return string|nil error
function M.saveAccount(record)
    if type(record) ~= "table" then
        return false, "record must be a table"
    end
    if type(record.username) ~= "string" or record.username == "" then
        return false, "username must be a non-empty string"
    end

    local accounts = readTable(ACCOUNTS_FILE)

    if not record.id then
        record.id = generateAccountId(accounts)
    end

    local now = os.epoch("utc")
    if not record.createdAt then
        record.createdAt = now
    end
    record.updatedAt = now

    if not record.permission then
        record.permission = "USER"
    end

    accounts[record.username] = record

    return writeTable(ACCOUNTS_FILE, accounts)
end

--- Delete an account by username
--- @param username string
--- @return boolean ok
--- @return string|nil error
function M.deleteAccount(username)
    if type(username) ~= "string" or username == "" then
        return false, "username is required"
    end

    local accounts = readTable(ACCOUNTS_FILE)
    if not accounts[username] then
        return false, "account not found"
    end

    accounts[username] = nil
    return writeTable(ACCOUNTS_FILE, accounts)
end

--- Save two records at a time (used for transactions)
--- @param recordA table first account record
--- @param recordB table second account record
--- @return boolean ok
--- @return string|nil error
function M.saveTwoAccounts(recordA, recordB)
    if type(recordA) ~= "table" or type(recordB) ~= "table" then
        return false, "both records must be tables"
    end

    local accounts = readTable(ACCOUNTS_FILE)

    local now = os.epoch("utc")
    recordA.updatedAt = now
    recordB.updatedAt = now

    accounts[recordA.username] = recordA
    accounts[recordB.username] = recordB

    return writeTable(ACCOUNTS_FILE, accounts)
end

-- ---------------------------------- Keys ---------------------------------- --
--- Get the publicKey for a username
--- @param username string
--- @return string|nil publicKey hex or nil
function M.getKey(username)
    if type(username) ~= "string" or username == "" then
        return nil
    end
    local keys = readTable(KEYS_FILE)
    return keys[username]
end

--- Store a publicKey for a username
--- @param username string
--- @param publicKey string hex
--- @return boolean ok
--- @return string|nil error
function M.saveKey(username, publicKey)
    if type(username) ~= "string" or username == "" then
        return false, "username is required"
    end
    if type(publicKey) ~= "string" or publicKey == "" then
        return false, "publicKey is required"
    end

    local keys = readTable(KEYS_FILE)
    keys[username] = publicKey
    return writeTable(KEYS_FILE, keys)
end

--- Remove a stored key
--- @param username string
--- @return boolean ok
--- @return string|nil error
function M.deleteKey(username)
    if type(username) ~= "string" or username == "" then
        return false, "username is required"
    end

    local keys = readTable(KEYS_FILE)
    if not keys[username] then
        return false, "key not found"
    end
    keys[username] = nil
    return writeTable(KEYS_FILE, keys)
end

-- ------------------------------ Transactions ------------------------------ --
--- Add transaction record to log
--- @param tx table {type, from, to, amount, [description], [balances]}
--- @return boolean ok
--- @return string|nil error
function M.appendTransaction(tx)
    if type(tx) ~= "table" then
        return false, "Transaction must be a table"
    end
    if type(tx.type) ~= "string" or tx.type == "" then
        return false, "Transaction type is required"
    end
    if tx.amount == nil then
        return false, "tx.amount is required"
    end

    ensureDataDir()

    if not tx.id then
        tx.id = generateTxId()
    end
    if not tx.timestamp then
        tx.timestamp = os.epoch("utc")
    end

    local ok, line = pcall(textutils.serialize, tx, { compact = true})
    if not ok then
        return false, "Serialize failed: " .. tostring(line)
    end

    -- append
    local f, openErr = fs.open(TRANSACTIONS_FILE, "a")
    if not f then
        return false, "Open transactions file failed: " .. tostring(openErr)
    end
    f.write(line .. "\n")
    f.close()

    return true
end

--- Retrieve transactions for account
--- @param username string
--- @param limit number|nil number of records to return
--- @return table array of transaction records
function M.getTransactions(username, limit)
    if type(username) ~= "string" or username == "" then
        return {}
    end
    if not fs.exists(TRANSACTIONS_FILE) then
        return {}
    end

    local f = fs.open(TRANSACTIONS_FILE, "r")
    local results = {}

    local line = f.readLine()
    while line ~= nil do
        if line ~= "" then
            local ok, tx = pcall(textutils.unserialize, line)
            if ok and type(tx) == "table" then
                if tx.from == username or tx.to == username then
                    results[#results + 1] = tx
                end
            end
        end
        line = f.readLine()
    end
    f.close()

    table.sort(results, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)

    -- limit
    if type(limit) == "number" and limit > 0 and #results > limit then
        local trimmed = {}
        for i = 1, limit do
            trimmed[i] = results[i]
        end
        return trimmed
    end

    return results
end

--- Retrieve ALL transactions logs
--- @param limit number|nil
--- @return table array of transaction records
function M.getAllTransactions(limit)
    if not fs.exists(TRANSACTIONS_FILE) then
        return {}
    end

    local f = fs.open(TRANSACTIONS_FILE, "r")
    local results = {}

    local line = f.readLine()
    while line ~= nil do
        if line ~= "" then
            local ok, tx = pcall(textutils.unserialize, line)
            if ok and type(tx) == "table" then
                results[#results + 1] = tx
            end
        end
        line = f.readLine()
    end
    f.close()

    table.sort(results, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)

    if type(limit) == "number" and limit > 0 and #results > limit then
        local trimmed = {}
        for i = 1, limit do
            trimmed[i] = results[i]
        end
        return trimmed
    end

    return results
end

-- ---------------------------------- Loop ---------------------------------- --
--- cleans up leftover tmp files
function M.init()
    ensureDataDir()
    cleanupTmpFiles()
end

M.init()
return M