-- SanityCheckService: validates presence of ReplicatedStorage.Shared and exact remotes
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sanity = {}

local requiredRemotes = {
    "AttackRequest",
    "BlockRequest",
    "DashRequest",
    "DamagePopup",
    "EconomyUpdate",
    "MatchStateUpdate",
    "ShopPurchaseRequest",
    "ShopEquipRequest",
    "ShopUpdate",
    "AbilityRequest",
    "AbilityFx",
    -- Round helpers
    "Round_RequestChallenge",
    "Round_RequestSit",
    "Round_RoundStarted",
    "Round_RoundEnded",
    -- Effects
    "Effects_Highlight",
    "Toast",
}

local requiredShared = {
    "Constants",
    "ItemConfig",
    "CooldownService",
    "Util",
}

function Sanity:Run()
    local ok = true
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if not shared then
        warn("[SanityCheck] ReplicatedStorage.Shared missing")
        ok = false
    else
        for _, name in ipairs(requiredShared) do
            if not shared:FindFirstChild(name) then
                warn("[SanityCheck] Shared module missing: " .. name)
                ok = false
            end
        end
    end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        warn("[SanityCheck] ReplicatedStorage.Remotes missing")
        ok = false
    else
        for _, r in ipairs(requiredRemotes) do
            if not remotes:FindFirstChild(r) then
                warn("[SanityCheck] Remote missing: " .. r)
                ok = false
            end
        end
    end

    if ok then
        print("[SanityCheck] all required shared modules and remotes present")
    else
        print("[SanityCheck] problems detected. See warnings above.")
    end
    return ok
end

return Sanity
