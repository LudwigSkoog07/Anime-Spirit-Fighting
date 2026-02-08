-- CooldownService: shared cooldown tracking (server & client friendly)
local CooldownService = {}
CooldownService._cooldowns = {} -- map userId -> abilityId -> expiryTime

function CooldownService:CanUse(player, abilityId)
    if not player then return false end
    local userId = player.UserId
    local now = tick()
    if not self._cooldowns[userId] then return true end
    local expiry = self._cooldowns[userId][abilityId]
    if not expiry then return true end
    return now >= expiry
end

function CooldownService:StartCooldown(player, abilityId, seconds)
    if not player then return end
    self._cooldowns[player.UserId] = self._cooldowns[player.UserId] or {}
    self._cooldowns[player.UserId][abilityId] = tick() + seconds
end

function CooldownService:GetRemaining(player, abilityId)
    if not player then return 0 end
    local t = self._cooldowns[player.UserId]
    if not t or not t[abilityId] then return 0 end
    return math.max(0, t[abilityId] - tick())
end

function CooldownService:ClearCooldown(player, abilityId)
    if not player or type(abilityId) ~= "string" or abilityId == "" then
        return
    end
    local t = self._cooldowns[player.UserId]
    if not t then
        return
    end
    t[abilityId] = nil
    if next(t) == nil then
        self._cooldowns[player.UserId] = nil
    end
end

function CooldownService:ClearAll(player)
    if not player then
        return
    end
    self._cooldowns[player.UserId] = nil
end

return CooldownService
