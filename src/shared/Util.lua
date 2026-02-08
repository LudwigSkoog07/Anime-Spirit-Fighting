local Util = {}

function Util.shallowCopy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

function Util.randomChoice(t)
    if not t or #t == 0 then return nil end
    return t[math.random(1, #t)]
end

-- Safe get player by userId
local Players = game:GetService("Players")
function Util.getPlayerByUserId(id)
    return Players:GetPlayerByUserId(id)
end

return Util
