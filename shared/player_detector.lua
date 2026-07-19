if not package.path:find("^/%?%.lua;", 1) then
    package.path = "/?.lua;/?/init.lua;" .. package.path
end

local M = {}

local DEFAULT_RANGE = 2

--- Find da player detecter
--- @return table|nil wrapped peripheral, or nil if none found
function M.findDetector()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "playerDetector" then
            return peripheral.wrap(name)
        end
    end
    return nil
end

--- Detect nearest player
--- @param detector table  wrapped playerDetector peripheral
--- @param range number|nil max block distance (default 2)
--- @return string|nil closest player username, or nil if none found
function M.detectClosest(detector, range)
    if not detector then
        return nil
    end
    range = range or DEFAULT_RANGE

    local ok, players = pcall(function()
        return detector.getPlayersInRange(range)
    end)
    if not ok or type(players) ~= "table" or #players == 0 then
        return nil
    end

    if #players == 1 then
        return players[1]
    end

    local closest, closestDist = nil, math.huge
    for _, username in ipairs(players) do
        local posOk, pos = pcall(function()
            return detector.getPlayerPos(username)
        end)
        if posOk and type(pos) == "table" then
            local dist = math.sqrt((pos.x or 0) ^ 2 + (pos.y or 0) ^ 2 + (pos.z or 0) ^ 2)
            if dist < closestDist then
                closest, closestDist = username, dist
            end
        end
    end

    return closest
end

--- keep tryin until a player is detected or user gives upvalue
--- @param detector table  wrapped playerDetector peripheral
--- @param range number|nil
--- @return string|nil username or nil if user quits
function M.detectOrRetry(detector, range)
    range = range or DEFAULT_RANGE
    while true do
        local name = M.detectClosest(detector, range)
        if name then
            print("Detected player: " .. name)
            return name
        end
        print("No player detected within " .. tostring(range) .. " blocks.")
        print("Stand closer to the terminal and press Enter to retry,")
        print("or type 'quit' to exit.")
        local input = read()
        if not input or input == "" then
        elseif input:lower() == "quit" then
            return nil
        end
    end
end

return M