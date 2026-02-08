-- ProfileService: persistent player combat stats + leaderstats syncing
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ProfileService = {}
ProfileService._profiles = {} -- userId -> profile table
ProfileService._dirty = {} -- userId -> true
ProfileService._loaded = {} -- userId -> true
ProfileService._initialized = false

local DATASTORE_NAME = "AFS_PlayerStats_v1"
local DATASTORE_ENABLE_ATTRIBUTE = "AFS_EnableDataStore"
local AUTOSAVE_INTERVAL = 120
local MAX_SAVE_RETRIES = 2
local MAX_STAT_VALUE = 1000000000

local STAT_KEYS = {
    kills = true,
    deaths = true,
    wins = true,
    losses = true,
    matches = true,
}

local LEADERSTAT_FIELDS = {
    { key = "wins", name = "Wins" },
    { key = "kills", name = "Kills" },
    { key = "deaths", name = "Deaths" },
    { key = "losses", name = "Losses" },
}

local function makeDefaultProfile()
    return {
        kills = 0,
        deaths = 0,
        wins = 0,
        losses = 0,
        matches = 0,
    }
end

local function isDataStoreEnabled()
    local override = Workspace:GetAttribute(DATASTORE_ENABLE_ATTRIBUTE)
    if override ~= nil then
        return override == true
    end
    return not RunService:IsStudio()
end

local PROFILE_STORE = nil
if isDataStoreEnabled() then
    local okStore, store = pcall(function()
        return DataStoreService:GetDataStore(DATASTORE_NAME)
    end)
    if okStore then
        PROFILE_STORE = store
    else
        warn("[ProfileService] Failed to acquire DataStore:", tostring(store))
    end
end

local function getPlayerKey(player)
    return "u_" .. tostring(player.UserId)
end

local function clampInt(value, fallback)
    if type(value) ~= "number" then
        return fallback
    end
    local n = math.floor(value + 0.5)
    if n < 0 then
        n = 0
    end
    if n > MAX_STAT_VALUE then
        n = MAX_STAT_VALUE
    end
    return n
end

local function sanitizeLoadedProfile(data)
    local profile = makeDefaultProfile()
    if type(data) ~= "table" then
        return profile
    end

    profile.kills = clampInt(data.kills, 0)
    profile.deaths = clampInt(data.deaths, 0)
    profile.wins = clampInt(data.wins, 0)
    profile.losses = clampInt(data.losses, 0)
    profile.matches = clampInt(data.matches, 0)
    return profile
end

local function serializeProfile(profile)
    return {
        kills = clampInt(profile.kills, 0),
        deaths = clampInt(profile.deaths, 0),
        wins = clampInt(profile.wins, 0),
        losses = clampInt(profile.losses, 0),
        matches = clampInt(profile.matches, 0),
        updatedAt = os.time(),
    }
end

local function getOrCreateLeaderstats(player)
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then
        leaderstats = Instance.new("Folder")
        leaderstats.Name = "leaderstats"
        leaderstats.Parent = player
    end

    for _, field in ipairs(LEADERSTAT_FIELDS) do
        local value = leaderstats:FindFirstChild(field.name)
        if not value or not value:IsA("IntValue") then
            if value then
                value:Destroy()
            end
            value = Instance.new("IntValue")
            value.Name = field.name
            value.Parent = leaderstats
        end
    end

    return leaderstats
end

local function syncLeaderstats(player)
    if not player then
        return
    end

    local profile = ProfileService._profiles[player.UserId]
    if not profile then
        return
    end

    local leaderstats = getOrCreateLeaderstats(player)
    for _, field in ipairs(LEADERSTAT_FIELDS) do
        local statValue = leaderstats:FindFirstChild(field.name)
        if statValue and statValue:IsA("IntValue") then
            statValue.Value = clampInt(profile[field.key], 0)
        end
    end
end

local function ensureProfile(player)
    if not player then
        return nil
    end

    local userId = player.UserId
    local profile = ProfileService._profiles[userId]
    if not profile then
        profile = makeDefaultProfile()
        ProfileService._profiles[userId] = profile
    end
    return profile
end

local function markDirty(player)
    if not player then
        return
    end
    ProfileService._dirty[player.UserId] = true
end

local function savePlayerProfile(player, force)
    if not player then
        return false
    end
    if not PROFILE_STORE then
        return true
    end

    local userId = player.UserId
    if not force and ProfileService._dirty[userId] ~= true then
        return true
    end

    local profile = ensureProfile(player)
    if not profile then
        return false
    end

    local payload = serializeProfile(profile)
    local success = false
    local errMessage = nil
    for attempt = 1, MAX_SAVE_RETRIES do
        local okSave, result = pcall(function()
            PROFILE_STORE:UpdateAsync(getPlayerKey(player), function(oldValue)
                local out = type(oldValue) == "table" and oldValue or {}
                out.kills = payload.kills
                out.deaths = payload.deaths
                out.wins = payload.wins
                out.losses = payload.losses
                out.matches = payload.matches
                out.updatedAt = payload.updatedAt
                return out
            end)
        end)
        if okSave then
            success = true
            break
        end
        errMessage = result
        task.wait(0.2 * attempt)
    end

    if success then
        ProfileService._dirty[userId] = nil
    else
        warn("[ProfileService] Failed saving player", userId, tostring(errMessage))
    end
    return success
end

local function loadPlayerProfile(player)
    if not player then
        return
    end

    local userId = player.UserId
    ProfileService._loaded[userId] = false
    local profile = makeDefaultProfile()

    if PROFILE_STORE then
        local loaded = nil
        local loadedOk = false
        local loadErr = nil
        for attempt = 1, MAX_SAVE_RETRIES do
            local okLoad, result = pcall(function()
                return PROFILE_STORE:GetAsync(getPlayerKey(player))
            end)
            if okLoad then
                loaded = result
                loadedOk = true
                break
            end
            loadErr = result
            task.wait(0.2 * attempt)
        end

        if loadedOk and type(loaded) == "table" then
            profile = sanitizeLoadedProfile(loaded)
        elseif not loadedOk then
            warn("[ProfileService] Failed loading player", userId, tostring(loadErr))
        end
    end

    ProfileService._profiles[userId] = profile
    ProfileService._dirty[userId] = nil
    ProfileService._loaded[userId] = true
    syncLeaderstats(player)
end

function ProfileService:Init()
    if self._initialized then
        return
    end
    self._initialized = true

    for _, player in ipairs(Players:GetPlayers()) do
        loadPlayerProfile(player)
    end

    Players.PlayerAdded:Connect(function(player)
        loadPlayerProfile(player)
    end)
    Players.PlayerRemoving:Connect(function(player)
        savePlayerProfile(player, true)
        self._profiles[player.UserId] = nil
        self._dirty[player.UserId] = nil
        self._loaded[player.UserId] = nil
    end)

    game:BindToClose(function()
        for _, player in ipairs(Players:GetPlayers()) do
            savePlayerProfile(player, true)
        end
    end)

    task.spawn(function()
        while self._initialized do
            task.wait(AUTOSAVE_INTERVAL)
            for _, player in ipairs(Players:GetPlayers()) do
                savePlayerProfile(player, false)
            end
        end
    end)
end

function ProfileService:GetProfile(player)
    local profile = ensureProfile(player)
    if not profile then
        return nil
    end
    return {
        kills = profile.kills,
        deaths = profile.deaths,
        wins = profile.wins,
        losses = profile.losses,
        matches = profile.matches,
    }
end

function ProfileService:GetStat(player, key)
    if not player or STAT_KEYS[key] ~= true then
        return 0
    end
    if PROFILE_STORE and self._loaded[player.UserId] ~= true then
        return 0
    end
    local profile = ensureProfile(player)
    return clampInt(profile[key], 0)
end

function ProfileService:AddStat(player, key, amount)
    if not player or STAT_KEYS[key] ~= true then
        return false
    end
    if type(amount) ~= "number" or amount == 0 then
        return false
    end

    local profile = ensureProfile(player)
    if not profile then
        return false
    end

    profile[key] = clampInt((profile[key] or 0) + amount, 0)
    markDirty(player)
    syncLeaderstats(player)
    return true
end

function ProfileService:RecordElimination(victimPlayer, killers)
    if victimPlayer then
        self:AddStat(victimPlayer, "deaths", 1)
    end

    if type(killers) ~= "table" then
        return
    end

    local awarded = {}
    for _, killer in ipairs(killers) do
        if killer and killer.UserId and killer ~= victimPlayer and not awarded[killer.UserId] then
            awarded[killer.UserId] = true
            self:AddStat(killer, "kills", 1)
        end
    end
end

function ProfileService:RecordRoundResult(winners, losers, isDraw)
    local matched = {}

    local function addMatches(players)
        if type(players) ~= "table" then
            return
        end
        for _, player in ipairs(players) do
            if player and player.UserId and not matched[player.UserId] then
                matched[player.UserId] = true
                self:AddStat(player, "matches", 1)
            end
        end
    end

    addMatches(winners)
    addMatches(losers)

    if isDraw then
        return
    end

    if type(winners) == "table" then
        for _, player in ipairs(winners) do
            if player then
                self:AddStat(player, "wins", 1)
            end
        end
    end

    if type(losers) == "table" then
        for _, player in ipairs(losers) do
            if player then
                self:AddStat(player, "losses", 1)
            end
        end
    end
end

return ProfileService
