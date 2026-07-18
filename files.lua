files = {}

files.shared = {
    { path = "shared/cannonical.lua",   url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/shared/cannonical.lua"   },
    { path = "shared/constants.lua",     url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/shared/constants.lua"     },
    { path = "shared/crypto.lua",        url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/shared/crypto.lua"        },
    { path = "shared/identity.lua",      url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/shared/identity.lua"      },
    { path = "shared/packet.lua",        url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/shared/packet.lua"        },
    { path = "shared/replay.lua",        url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/shared/replay.lua"        },
    { path = "shared/serialization.lua", url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/shared/serialization.lua" },
    { path = "shared/session.lua",       url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/shared/session.lua"       },
    { path = "shared/signing.lua",       url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/shared/signing.lua"       },
    { path = "shared/utils.lua",         url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/shared/utils.lua"         },
}

files.server = {
    { path = "server/accounts.lua",     url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/server/accounts.lua"     },
    { path = "server/auth.lua",         url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/server/auth.lua"         },
    { path = "server/database.lua",     url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/server/database.lua"     },
    { path = "server/logger.lua",       url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/server/logger.lua"       },
    { path = "server/main.lua",         url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/server/main.lua"         },
    { path = "server/network.lua",      url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/server/network.lua"      },
    { path = "server/protocol.lua",     url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/server/protocol.lua"     },
    { path = "server/transactions.lua", url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/server/transactions.lua" },
}

files.client = {
    { path = "client/config.lua",  url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/client/config.lua"  },
    { path = "client/main.lua",    url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/client/main.lua"    },
    { path = "client/network.lua", url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/client/network.lua" },
    { path = "client/protocol.lua",url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/client/protocol.lua"},
    { path = "client/setup.lua",   url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/client/setup.lua"   },
    { path = "client/ui.lua",      url = "https://raw.githubusercontent.com/alebogino/BlockVault/master/client/ui.lua"      },
}

return files