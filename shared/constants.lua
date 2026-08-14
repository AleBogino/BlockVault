-- source of truths for ENUMS
local M = {}

M.PROTOCOL_VERSION = 1

-- how long we remember nonces
M.NONCE_TTL_MS = 30000
-- how much clock skew between peers we tolerate
M.CLOCK_SKEW_MS = 30000
-- how long we wait for the player to enter the code in chat
M.LOGIN_CHAT_TIMEOUT_MS = 30000
-- login code length
M.LOGIN_CODE_LENGTH = 4
-- how long before an inactive session is evicted (ms)
M.SESSION_TIMEOUT_MS = 120000

M.PACKET = {
    -- handshake and auth
    HELLO = "HELLO",
    CHALLENGE = "CHALLENGE",
    AUTH = "AUTH",
    AUTH_OK = "AUTH_OK",
    AUTH_FAIL = "AUTH_FAIL",

    -- crud
    CREATE_ACCOUNT = "CREATE_ACCOUNT",
    DELETE_ACCOUNT = "DELETE_ACCOUNT",
    UPDATE_ACCOUNT = "UPDATE_ACCOUNT",
    GET_ACCOUNT = "GET_ACCOUNT",

    -- Transactions
    TRANSFER = "TRANSFER",
    DEPOSIT = "DEPOSIT",
    WITHDRAW = "WITHDRAW",
    BALANCE = "BALANCE",
    HISTORY = "HISTORY",

    -- System
    PING = "PING",
    PONG = "PONG",
    ERROR = "ERROR",
    DISCONNECT = "DISCONNECT",

    -- login via chat
    LOGIN_REQUEST     = "LOGIN_REQUEST",
    LOGIN_AWAIT_CHAT  = "LOGIN_AWAIT_CHAT",
    LOGIN_OK          = "LOGIN_OK",
    LOGIN_FAIL        = "LOGIN_FAIL",
    LOGIN_TIMEOUT     = "LOGIN_TIMEOUT",

    -- Online players (server-side)
    GET_ONLINE_PLAYERS     = "GET_ONLINE_PLAYERS",
    GET_ONLINE_PLAYERS_OK  = "GET_ONLINE_PLAYERS_OK",
}

-- what do we tolerate before a session is established
M.HANDSHAKE_PACKETS = {
    [M.PACKET.HELLO] = true,
    [M.PACKET.CHALLENGE] = true,
    [M.PACKET.AUTH] = true,
    [M.PACKET.AUTH_OK] = true,
    [M.PACKET.AUTH_FAIL] = true,
    [M.PACKET.ERROR] = true,
    [M.PACKET.LOGIN_REQUEST]    = true,
    [M.PACKET.LOGIN_AWAIT_CHAT] = true,
    [M.PACKET.LOGIN_OK]         = true,
    [M.PACKET.LOGIN_FAIL]       = true,
    [M.PACKET.LOGIN_TIMEOUT]    = true,
}

-- perms
M.PERMISSION = {
    USER = "USER",
    ADMIN = "ADMIN",
    SYSTEM = "SYSTEM",
}

M.PERMISSION_RANK = {
    USER = 1,
    ADMIN = 2,
    SYSTEM = 3,
}

-- Coin values
M.COIN_VALUES = {
    ["createdeco:zinc_coin"]            = 1,
    ["createdeco:copper_coin"]          = 9,
    ["createdeco:iron_coin"]            = 81,
    ["createdeco:industrial_iron_coin"] = 729,
    ["createdeco:brass_coin"]           = 6561,
    ["createdeco:gold_coin"]            = 59049,
    ["createdeco:netherite_coin"]       = 531441,
}
-- import order
M.COIN_ORDER = {
    "createdeco:netherite_coin",
    "createdeco:gold_coin",
    "createdeco:brass_coin",
    "createdeco:industrial_iron_coin",
    "createdeco:iron_coin",
    "createdeco:copper_coin",
    "createdeco:zinc_coin",
}

-- error codes
M.ERROR = {
    INVALID_SIGNATURE = "INVALID_SIGNATURE",
    INVALID_NONCE = "INVALID_NONCE",
    INVALID_TIMESTAMP = "INVALID_TIMESTAMP",
    INVALID_VERSION = "INVALID_VERSION",
    AUTH_FAILED = "AUTH_FAILED",
    ACCOUNT_NOT_FOUND = "ACCOUNT_NOT_FOUND",
    PERMISSION_DENIED = "PERMISSION_DENIED",
    INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS",
    SERVER_ERROR = "SERVER_ERROR",
    INVALID_PACKET = "INVALID_PACKET",
    PLAYER_NOT_FOUND = "PLAYER_NOT_FOUND",
    PLAYER_TOO_FAR = "PLAYER_TOO_FAR",
    LOGIN_TIMEOUT = "LOGIN_TIMEOUT",
    ALREADY_PENDING = "ALREADY_PENDING",
    NO_ME_BRIDGE = "NO_ME_BRIDGE",
    ME_NOT_CONNECTED = "ME_NOT_CONNECTED",
    ME_IMPORT_FAILED = "ME_IMPORT_FAILED",
    COINS_NOT_FOUND = "COINS_NOT_FOUND",
    NO_INVENTORY = "NO_INVENTORY",
}

-- payload schema
M.PAYLOAD_SCHEMA = {
    HELLO = {"clientId", "clientPublicKey", "clientDhPublicKey"},
    CHALLENGE = { "challenge", "serverDhPublicKey" },
    AUTH = { "challengeResponse" },
    AUTH_OK = {},
    AUTH_FAIL = { "reason" },

    CREATE_ACCOUNT = { "username", "initialBalance" },
    CREATE_ACCOUNT_OK = {},
    DELETE_ACCOUNT = { "username" },
    DELETE_ACCOUNT_OK = {},
    UPDATE_ACCOUNT = { "username" },
    UPDATE_ACCOUNT_OK = {},
    GET_ACCOUNT = { "username" },
    GET_ACCOUNT_OK = {},
 
    TRANSFER = { "from", "to", "amount" },
    TRANSFER_OK = {},
    DEPOSIT = { "username", "amount" },
    DEPOSIT_OK = {},
    WITHDRAW = { "username", "amount" },
    WITHDRAW_OK = {},
    BALANCE = { "username" },
    BALANCE_OK = {},
    HISTORY = { "username" },
    HISTORY_OK = {},
 
    PING = {},
    PONG = {},
    ERROR = { "code" },
    DISCONNECT = {},

    LOGIN_REQUEST    = { "clientId" },
    LOGIN_AWAIT_CHAT = { "code" },
    LOGIN_OK         = { "username", "balance", "permission", "createdAt" },
    LOGIN_FAIL       = { "reason" },
    LOGIN_TIMEOUT    = {},

    GET_ONLINE_PLAYERS     = {},
    GET_ONLINE_PLAYERS_OK  = {},
}

return M
