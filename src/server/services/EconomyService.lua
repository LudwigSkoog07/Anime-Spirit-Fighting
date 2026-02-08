-- EconomyService: money, streaks, payouts
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
if not Shared then warn("Shared modules missing (EconomyService)") end
local Constants = require(Shared:WaitForChild("Constants"))

local EconomyService = {}
EconomyService._balances = {}
EconomyService._streaks = {}
EconomyService._initialized = false
EconomyService._dirty = {}
EconomyService._loaded = {}

local START_MONEY = 500
local DATASTORE_NAME = "AFS_Economy_v1"
local DATASTORE_ENABLE_ATTRIBUTE = "AFS_EnableDataStore"
local AUTOSAVE_INTERVAL = 120
local MAX_SAVE_RETRIES = 2
local ROUND_WIN_REWARD = 350
local ROUND_LOSS_REWARD = 150
local ROUND_DRAW_REWARD = 150

local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not remotes then warn("Remotes folder missing (EconomyService)") end
local EV_ECONOMY = remotes:WaitForChild(Constants.RemoteNames.EconomyUpdate, 5)

local function isDataStoreEnabled()
    local override = Workspace:GetAttribute(DATASTORE_ENABLE_ATTRIBUTE)
    if override ~= nil then
        return override == true
    end
    return not RunService:IsStudio()
end

local ECONOMY_STORE = nil
if isDataStoreEnabled() then
    local okStore, store = pcall(function()
        return DataStoreService:GetDataStore(DATASTORE_NAME)
    end)
    if okStore then
        ECONOMY_STORE = store
    else
        warn("[EconomyService] Failed to acquire DataStore:", tostring(store))
    end
end

local function sendUpdate(player)
    -- sends the player's updated money and streak to all clients
    local payload = {
        userId = player.UserId,
        money = EconomyService._balances[player.UserId] or 0,
        streak = EconomyService._streaks[player.UserId] or 0,
    }
    EV_ECONOMY:FireAllClients(payload)
end

local function getPlayerKey(player)
    return "u_" .. tostring(player.UserId)
end

local function clampNumber(value, fallback, minValue, maxValue)
    if type(value) ~= "number" then
        return fallback
    end
    local n = math.floor(value + 0.5)
    if minValue and n < minValue then
        n = minValue
    end
    if maxValue and n > maxValue then
        n = maxValue
    end
    return n
end

local function markDirty(player)
    if not player then return end
    EconomyService._dirty[player.UserId] = true
end

local function savePlayerEconomy(player, force)
    if not player then
        return false
    end
    if not ECONOMY_STORE then
        return true
    end

    local userId = player.UserId
    if not force and EconomyService._dirty[userId] ~= true then
        return true
    end

    local payload = {
        money = clampNumber(EconomyService._balances[userId], START_MONEY, 0, 1000000000),
        streak = clampNumber(EconomyService._streaks[userId], 0, 0, 1000000),
        updatedAt = os.time(),
    }

    local success = false
    local errMessage = nil
    for attempt = 1, MAX_SAVE_RETRIES do
        local okSave, result = pcall(function()
            ECONOMY_STORE:UpdateAsync(getPlayerKey(player), function(oldValue)
                local out = type(oldValue) == "table" and oldValue or {}
                out.money = payload.money
                out.streak = payload.streak
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
        EconomyService._dirty[userId] = nil
    else
        warn("[EconomyService] Failed saving player", player.UserId, tostring(errMessage))
    end
    return success
end

local function initPlayerEconomy(player)
    if not player then return end
    local userId = player.UserId
    EconomyService._loaded[userId] = false
    EconomyService._balances[userId] = START_MONEY
    EconomyService._streaks[userId] = 0

    if ECONOMY_STORE then
        local loaded = nil
        local loadedOk = false
        local loadErr = nil
        for attempt = 1, MAX_SAVE_RETRIES do
            local okLoad, result = pcall(function()
                return ECONOMY_STORE:GetAsync(getPlayerKey(player))
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
            EconomyService._balances[userId] = clampNumber(loaded.money, START_MONEY, 0, 1000000000)
            EconomyService._streaks[userId] = clampNumber(loaded.streak, 0, 0, 1000000)
        elseif not loadedOk then
            warn("[EconomyService] Failed loading player", player.UserId, tostring(loadErr))
        end
    end

    EconomyService._dirty[userId] = nil
    EconomyService._loaded[userId] = true
    sendUpdate(player)
end

function EconomyService:Init()
    if self._initialized then
        return
    end
    self._initialized = true

    for _, player in ipairs(Players:GetPlayers()) do
        initPlayerEconomy(player)
    end

    Players.PlayerAdded:Connect(function(player)
        initPlayerEconomy(player)
    end)
    Players.PlayerRemoving:Connect(function(player)
        savePlayerEconomy(player, true)
        self._balances[player.UserId] = nil
        self._streaks[player.UserId] = nil
        self._dirty[player.UserId] = nil
        self._loaded[player.UserId] = nil
    end)

    game:BindToClose(function()
        for _, player in ipairs(Players:GetPlayers()) do
            savePlayerEconomy(player, true)
        end
    end)

    task.spawn(function()
        while self._initialized do
            task.wait(AUTOSAVE_INTERVAL)
            for _, player in ipairs(Players:GetPlayers()) do
                savePlayerEconomy(player, false)
            end
        end
    end)
end

function EconomyService:CanAfford(player, amount)
    if not player then return false end
    if ECONOMY_STORE and self._loaded[player.UserId] ~= true then
        return false
    end
    return (self._balances[player.UserId] or 0) >= amount
end

function EconomyService:Spend(player, amount)
    if not player or amount <= 0 then return false end
    if not self:CanAfford(player, amount) then return false end
    self._balances[player.UserId] = (self._balances[player.UserId] or 0) - amount
    markDirty(player)
    sendUpdate(player)
    return true
end

function EconomyService:AddMoney(player, amount, reason)
    if not player or amount == 0 then return end
    self._balances[player.UserId] = (self._balances[player.UserId] or 0) + amount
    markDirty(player)
    sendUpdate(player)
end

function EconomyService:GetMoney(player)
    if not player then return 0 end
    if ECONOMY_STORE and self._loaded[player.UserId] ~= true then
        return 0
    end
    return self._balances[player.UserId] or 0
end

function EconomyService:SetStreak(player, streak)
    if not player then return end
    self._streaks[player.UserId] = clampNumber(streak, 0, 0, 1000000)
    markDirty(player)
    sendUpdate(player)
end

function EconomyService:GetStreak(player)
    if not player then return 0 end
    if ECONOMY_STORE and self._loaded[player.UserId] ~= true then
        return 0
    end
    return self._streaks[player.UserId] or 0
end

-- Payout rules when a player dies; 'killers' is an array of Player objects (1 or more)
function EconomyService:PayKillBounty(victimPlayer, killers)
    if not victimPlayer or not killers then return end
    local victimStreak = self:GetStreak(victimPlayer)
    local payout = 0
    if victimStreak >= 15 then
        payout = 1000
    elseif victimStreak >= 10 then
        payout = 600
    elseif victimStreak >= 5 then
        payout = 200
    elseif victimStreak >= 2 then
        payout = 100
    else
        payout = 0
    end

    if payout <= 0 or #killers == 0 then return end

    if #killers == 1 then
        local k = killers[1]
        self:AddMoney(k, payout, "kill bounty")
    else
        local base = math.floor(payout / #killers)
        local remainder = payout - (base * #killers)
        for i, k in ipairs(killers) do
            local amount = base
            if i == 1 and remainder > 0 then amount = amount + remainder end
            self:AddMoney(k, amount, "kill bounty")
        end
    end
end

-- Payout rules when a round ends.
-- winners/losers are arrays of Player objects. Draws pay participants a flat reward.
function EconomyService:PayRoundResult(winners, losers, isDraw)
    local awarded = {}

    local function payGroup(players, amount, reason)
        if amount <= 0 or type(players) ~= "table" then
            return
        end
        for _, player in ipairs(players) do
            if player and player.UserId and not awarded[player.UserId] then
                awarded[player.UserId] = true
                self:AddMoney(player, amount, reason)
            end
        end
    end

    if isDraw then
        payGroup(winners, ROUND_DRAW_REWARD, "round draw")
        payGroup(losers, ROUND_DRAW_REWARD, "round draw")
        return
    end

    payGroup(winners, ROUND_WIN_REWARD, "round win")
    payGroup(losers, ROUND_LOSS_REWARD, "round loss")
end

return EconomyService
