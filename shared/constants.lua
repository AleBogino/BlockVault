-- source of truths for ENUMS
local M = {}

M.PROTOCOL_VERSION = 1

-- how long we remember nonces
M.NONCE_TTL_MS = 30000
-- how much clock skew between peers we tolerate
M.CLOCK_SKEW_MS = 30000
-- how far we detect the players
M.PLAYER_DETECT_RANGE = 2

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
}

-- what do we tolerate before a session is established
M.HANDSHAKE_PACKETS = {
    [M.PACKET.HELLO] = true,
    [M.PACKET.CHALLENGE] = true,
    [M.PACKET.AUTH] = true,
    [M.PACKET.AUTH_OK] = true,
    [M.PACKET.AUTH_FAIL] = true,
    [M.PACKET.ERROR] = true,
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
    PLAYER_TOO_FAR = "PLAYER_TOO_FAR"
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
}

return M
