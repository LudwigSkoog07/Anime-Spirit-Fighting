-- RemotesInit.luau (safe replacement)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemotesInit = {}

local function getOrCreateFolder(parent: Instance, name: string)
    local f = parent:FindFirstChild(name)
    if f and f:IsA("Folder") then return f end
    f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

local function getOrCreateRemoteEvent(parent: Instance, name: string)
    local r = parent:FindFirstChild(name)
    if r and r:IsA("RemoteEvent") then return r end
    r = Instance.new("RemoteEvent")
    r.Name = name
    r.Parent = parent
    return r
end

function RemotesInit.Init()
    local remotesFolder = getOrCreateFolder(ReplicatedStorage, "Remotes")

    -- Combat
    getOrCreateRemoteEvent(remotesFolder, "AttackRequest")
    getOrCreateRemoteEvent(remotesFolder, "BlockRequest")
    getOrCreateRemoteEvent(remotesFolder, "DashRequest")
    getOrCreateRemoteEvent(remotesFolder, "DamagePopup")

    -- Economy / HUD
    getOrCreateRemoteEvent(remotesFolder, "EconomyUpdate")
    getOrCreateRemoteEvent(remotesFolder, "MatchStateUpdate")

    -- Shop
    getOrCreateRemoteEvent(remotesFolder, "ShopPurchaseRequest")
    getOrCreateRemoteEvent(remotesFolder, "ShopEquipRequest")
    getOrCreateRemoteEvent(remotesFolder, "ShopUpdate")

    -- Round / Match
    getOrCreateRemoteEvent(remotesFolder, "Round_RequestChallenge")
    getOrCreateRemoteEvent(remotesFolder, "Round_RequestSit")
    getOrCreateRemoteEvent(remotesFolder, "Round_RoundStarted")
    getOrCreateRemoteEvent(remotesFolder, "Round_RoundEnded")

    -- Abilities
    getOrCreateRemoteEvent(remotesFolder, "AbilityRequest")
    getOrCreateRemoteEvent(remotesFolder, "AbilityFx")

    -- UI: Toast notifications
    getOrCreateRemoteEvent(remotesFolder, "Toast")

    -- Misc effects
    getOrCreateRemoteEvent(remotesFolder, "Effects_Highlight")

    print("[RemotesInit] ready")
end

return RemotesInit
