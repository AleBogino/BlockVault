-- this file is a thin wrapper around ccryptolib
-- REQUIRES "ccryptolib" folder present along with all its stuff downloaded

local random = require "ccryptolib.random"
local ed25519 = require "ccryptolib.ed25519"
local x25519 = require "ccryptolib.x25519"
local sha256 = require "ccryptolib.sha256"
local aead = require "ccryptolib.aead"
local blake3 = require "ccryptolib.blake3"

local M = {}

-- entropy source
function M.initRandom()
    if random.isInit() then return end
    random.initWithTiming()
    -- pato si lees esto, teach me crypto ;)
end


--- generate a keypair (32-byte secret and public keys)
function M.newIdentity()
    local sk = random.random(32)
    local pk = ed25519.publicKey(sk)
    return sk, pk
end
 
-- ed25519: FOR SIGNING SHIT
-- looked into how it works, im too stupid to understand yet
function M.sign(sk, pk, msg)
    return ed25519.sign(sk, pk, msg)
end
 
function M.verify(pk, msg, sig)
    return ed25519.verify(pk, msg, sig)
end

-- X22519: TO EXCHANGE "DIFFIE-HELLMAN" KEYS :)
-- generate a keypair for one handshake, discarded as soon as the session is established
function M.newDHKeypair()
    local sk = random.random(32)
    local pk = x25519.publicKey(sk)
    return sk, pk
end


-- derive a session key
function M.deriveSessionKey(myDhSk, theirDhPk, context)
    local shared = x25519.exchange(myDhSk, theirDhPk)
    local kdf = blake3.deriveKey(context)
    return kdf(shared, 32)
end

-- encrypt using session key
function M.encrypt(sessionKey, nonce, plaintext, aad)
    return aead.encrypt(sessionKey, nonce, plaintext, aad or "")
end

-- decrypt using session key
-- nil if doesnt match
function M.decrypt(sessionKey, nonce, tag, ciphertext, aad)
    return aead.decrypt(sessionKey, nonce, tag, ciphertext, aad or "")
end

function M.hash(data)
    return sha256.digest(data)
end

function M.makeNonce(counter)
    local bytes = {}
    for i = 0, 11 do
        bytes[12 - i] = string.char(counter % 256)
        counter = math.floor(counter / 256)
    end
    return table.concat(bytes)
end

--- Generate n random bytes
function M.randomBytes(n)
    return random.random(n)
end

return M
