-- Services startup
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local DATASTORE_ENABLE_ATTRIBUTE = "AFS_EnableDataStore"

print("[init] bootstrap start")

local function enforceProductionDefaults()
    -- Enable DataStores by default in every environment unless explicitly disabled.
    if Workspace:GetAttribute(DATASTORE_ENABLE_ATTRIBUTE) == nil then
        Workspace:SetAttribute(DATASTORE_ENABLE_ATTRIBUTE, true)
    end

    if RunService:IsStudio() then
        return
    end

    -- Clear common test/debug toggles on live servers unless deliberately re-enabled.
    local clearAttrs = {
        "AFS_TestMode",
        "AFS_IgnoreRoundRules",
        "AFS_AllowDummyDamage",
        "AFS_ShowHitboxes",
        "AFS_DebugLogs",
        "AFS_DebugDamage",
        "AFS_AllowLobbyDamage",
    }
    for _, attr in ipairs(clearAttrs) do
        if Workspace:GetAttribute(attr) ~= nil then
            Workspace:SetAttribute(attr, nil)
        end
    end

end

local function getOrCreateFolder(parent, name)
    local folder = parent:FindFirstChild(name)
    if folder and folder:IsA("Folder") then
        return folder
    end
    folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local function getOrCreateRemoteEvent(parent, name)
    local remote = parent:FindFirstChild(name)
    if remote and remote:IsA("RemoteEvent") then
        return remote
    end
    remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = parent
    return remote
end

local function ensureFallbackRemotes()
    local remotesFolder = getOrCreateFolder(ReplicatedStorage, "Remotes")
    local names = {
        "AttackRequest",
        "BlockRequest",
        "DashRequest",
        "DamagePopup",
        "EconomyUpdate",
        "MatchStateUpdate",
        "ShopPurchaseRequest",
        "ShopEquipRequest",
        "ShopUpdate",
        "Round_RequestChallenge",
        "Round_RequestSit",
        "Round_RoundStarted",
        "Round_RoundEnded",
        "AbilityRequest",
        "AbilityFx",
        "Toast",
        "Effects_Highlight",
    }
    for _, remoteName in ipairs(names) do
        getOrCreateRemoteEvent(remotesFolder, remoteName)
    end
end

local function findModule(name)
    local parent = script.Parent
    if parent then
        local inParent = parent:FindFirstChild(name, true)
        if inParent and inParent:IsA("ModuleScript") then
            return inParent
        end
    end
    local inServerScriptService = ServerScriptService:FindFirstChild(name, true)
    if inServerScriptService and inServerScriptService:IsA("ModuleScript") then
        return inServerScriptService
    end
    return nil
end

local function safeRequire(name)
    local moduleScript = findModule(name)
    if not moduleScript then
        warn("[init] module missing: " .. name)
        return nil
    end
    local ok, mod = pcall(require, moduleScript)
    if not ok then
        warn("[init] failed requiring " .. name .. ": " .. tostring(mod))
        return nil
    end
    return mod
end

-- Create canonical remotes immediately so clients can bind even if later requires fail.
ensureFallbackRemotes()
enforceProductionDefaults()
if RunService:IsStudio() and Workspace:GetAttribute(DATASTORE_ENABLE_ATTRIBUTE) == true then
    print("[init] DataStore is enabled. For Studio persistence, turn on Game Settings > Security > Enable Studio Access to API Services.")
end

local RemotesInit = safeRequire("RemotesInit")
if RemotesInit and RemotesInit.Init then
    pcall(function() RemotesInit.Init() end)
end

local SanityCheck = safeRequire("SanityCheckService")
if SanityCheck and SanityCheck.Run then
    pcall(function() SanityCheck:Run() end)
end

local MapService = safeRequire("MapService")
if MapService and MapService.GetOrCreateMap then
    pcall(function() MapService:GetOrCreateMap() end)
end

local RoundService = safeRequire("RoundService")
if RoundService and RoundService.Init then
    RoundService:Init()
end

local EconomyService = safeRequire("EconomyService")
if EconomyService and EconomyService.Init then
    EconomyService:Init()
end

local ProfileService = safeRequire("ProfileService")
if ProfileService and ProfileService.Init then
    ProfileService:Init()
end

safeRequire("AbilityService")
safeRequire("CombatService")
local ShopService = safeRequire("ShopService")
if ShopService and ShopService.Init then
    ShopService:Init()
end
