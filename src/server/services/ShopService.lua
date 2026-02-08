-- ShopService: handles purchases, equips, and applying upgrades
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
if not Shared then warn("Shared modules missing (ShopService)") end
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local Constants = require(Shared:WaitForChild("Constants"))

local EconomyService
pcall(function() EconomyService = require(script.Parent.EconomyService) end)
local WeaponService
pcall(function() WeaponService = require(script.Parent.WeaponService) end)

local ShopService = {}
ShopService._profiles = {} -- userId -> profile
ShopService._dirty = {} -- userId -> true
ShopService._charConnections = {} -- userId -> RBXScriptConnection
ShopService._initialized = false
ShopService._thirdSlotUnlockedByUserId = {} -- userId -> bool

local DATASTORE_NAME = "AFS_ShopProfiles_v1"
local DATASTORE_ENABLE_ATTRIBUTE = "AFS_EnableDataStore"
local AUTOSAVE_INTERVAL = 120
local MAX_SAVE_RETRIES = 2
local BASE_POWER_SLOT_COUNT = 2
local MAX_POWER_SLOT_COUNT = 3
local THIRD_POWER_SLOT_INDEX = 3
local THIRD_SLOT_GAMEPASS_ATTRIBUTE = "AFS_ThirdSlotGamePassId"
local DEFAULT_THIRD_SLOT_GAMEPASS_ID = math.max(
    0,
    math.floor(tonumber((Constants.GamePasses and Constants.GamePasses.UnlockThirdSlot) or 0) or 0)
)

local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not remotes then warn("Remotes folder missing (ShopService)") end
local REQ_PURCHASE = remotes:WaitForChild(Constants.RemoteNames.ShopPurchaseRequest, 5)
local REQ_EQUIP = remotes:WaitForChild(Constants.RemoteNames.ShopEquipRequest, 5)
local EV_UPDATE = remotes:WaitForChild(Constants.RemoteNames.ShopUpdate, 5)

local function isDataStoreEnabled()
    local override = Workspace:GetAttribute(DATASTORE_ENABLE_ATTRIBUTE)
    if override ~= nil then
        return override == true
    end
    return not RunService:IsStudio()
end

local SHOP_STORE = nil
if isDataStoreEnabled() then
    local okStore, store = pcall(function()
        return DataStoreService:GetDataStore(DATASTORE_NAME)
    end)
    if okStore then
        SHOP_STORE = store
    else
        warn("[ShopService] Failed to acquire DataStore:", tostring(store))
    end
end

local function makeDefaultProfile()
    return {
        owned = {},
        equippedWeapon = "fists",
        equippedPowers = {},
        hpBonus = 0,
        thirdSlotUnlocked = false,
        thirdSlotGamePassId = 0,
    }
end

local function getPlayerKey(player)
    return "u_" .. tostring(player.UserId)
end

local function toPositiveInteger(value)
    local n = tonumber(value)
    if not n then
        return nil
    end
    n = math.floor(n)
    if n <= 0 then
        return nil
    end
    return n
end

local function getThirdSlotGamePassId()
    local attrId = toPositiveInteger(Workspace:GetAttribute(THIRD_SLOT_GAMEPASS_ATTRIBUTE))
    if attrId then
        return attrId
    end
    return DEFAULT_THIRD_SLOT_GAMEPASS_ID
end

local function hasThirdSlotGamePass(player, forceRefresh)
    if not player then
        return false
    end

    local userId = player.UserId
    if not forceRefresh then
        local cached = ShopService._thirdSlotUnlockedByUserId[userId]
        if cached ~= nil then
            return cached == true
        end
    end

    local gamePassId = getThirdSlotGamePassId()
    if gamePassId <= 0 then
        ShopService._thirdSlotUnlockedByUserId[userId] = false
        return false
    end

    local okOwns, owns = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(userId, gamePassId)
    end)
    if not okOwns then
        warn("[ShopService] Failed checking gamepass ownership", userId, tostring(owns))
        owns = false
    end

    owns = owns == true
    ShopService._thirdSlotUnlockedByUserId[userId] = owns
    return owns
end

local function computeProfileHpBonus(profile)
    local total = 0
    if not profile or type(profile.owned) ~= "table" then
        return total
    end
    for itemId, owned in pairs(profile.owned) do
        if owned == true then
            local item = ItemConfig.Get(itemId)
            if item and item.type == "Upgrade" and type(item.hpBonus) == "number" and item.hpBonus > 0 then
                total = total + math.floor(item.hpBonus + 0.5)
            end
        end
    end
    return math.max(0, total)
end

local function sanitizeLoadedProfile(data, thirdSlotUnlocked)
    local profile = makeDefaultProfile()
    if type(data) ~= "table" then
        profile.thirdSlotUnlocked = thirdSlotUnlocked == true
        profile.thirdSlotGamePassId = getThirdSlotGamePassId()
        return profile
    end

    if type(data.owned) == "table" then
        for itemId, owned in pairs(data.owned) do
            if owned == true and type(itemId) == "string" and itemId ~= "" then
                local item = ItemConfig.Get(itemId)
                if item then
                    profile.owned[itemId] = true
                end
            end
        end
    end

    local equippedWeapon = type(data.equippedWeapon) == "string" and data.equippedWeapon or "fists"
    if equippedWeapon ~= "fists" then
        local weaponItem = ItemConfig.Get(equippedWeapon)
        if not weaponItem or weaponItem.type ~= "Weapon" or profile.owned[equippedWeapon] ~= true then
            equippedWeapon = "fists"
        end
    end
    profile.equippedWeapon = equippedWeapon

    local maxPowerSlots = (thirdSlotUnlocked == true) and MAX_POWER_SLOT_COUNT or BASE_POWER_SLOT_COUNT
    local seenPower = {}
    if type(data.equippedPowers) == "table" then
        for slot = 1, MAX_POWER_SLOT_COUNT do
            local powerId = data.equippedPowers[slot]
            if slot <= maxPowerSlots and type(powerId) == "string" and profile.owned[powerId] == true and not seenPower[powerId] then
                local powerItem = ItemConfig.Get(powerId)
                if powerItem and powerItem.type == "Power" then
                    profile.equippedPowers[slot] = powerId
                    seenPower[powerId] = true
                end
            end
        end
    end

    profile.hpBonus = computeProfileHpBonus(profile)
    profile.thirdSlotUnlocked = thirdSlotUnlocked == true
    profile.thirdSlotGamePassId = getThirdSlotGamePassId()
    return profile
end

local function serializeProfile(profile)
    local out = {
        owned = {},
        equippedWeapon = "fists",
        equippedPowers = {},
        hpBonus = 0,
        updatedAt = os.time(),
    }

    if type(profile) ~= "table" then
        return out
    end

    if type(profile.owned) == "table" then
        for itemId, owned in pairs(profile.owned) do
            if owned == true and type(itemId) == "string" and itemId ~= "" then
                out.owned[itemId] = true
            end
        end
    end

    if type(profile.equippedWeapon) == "string" and profile.equippedWeapon ~= "" then
        out.equippedWeapon = profile.equippedWeapon
    end

    if type(profile.equippedPowers) == "table" then
        if type(profile.equippedPowers[1]) == "string" then
            out.equippedPowers[1] = profile.equippedPowers[1]
        end
        if type(profile.equippedPowers[2]) == "string" then
            out.equippedPowers[2] = profile.equippedPowers[2]
        end
        if type(profile.equippedPowers[3]) == "string" then
            out.equippedPowers[3] = profile.equippedPowers[3]
        end
    end

    out.hpBonus = computeProfileHpBonus(profile)
    return out
end

local function sendProfileUpdate(player)
    if not EV_UPDATE then return end
    local profile = ShopService._profiles[player.UserId]
    if not profile then return end
    profile.equippedPowers = profile.equippedPowers or {}
    local thirdSlotUnlocked = hasThirdSlotGamePass(player, false)
    profile.thirdSlotUnlocked = thirdSlotUnlocked
    profile.thirdSlotGamePassId = getThirdSlotGamePassId()
    if not thirdSlotUnlocked then
        profile.equippedPowers[THIRD_POWER_SLOT_INDEX] = nil
    end
    EV_UPDATE:FireClient(player, profile)
end

local function applyEquippedWeapon(player)
    if not WeaponService or not WeaponService.ApplyWeapon then return end
    local profile = ShopService._profiles[player.UserId]
    if not profile then return end
    WeaponService:ApplyWeapon(player, profile.equippedWeapon)
end

local function markDirty(player)
    if not player then return end
    ShopService._dirty[player.UserId] = true
end

local function savePlayerProfile(player, force)
    if not player then
        return false
    end
    if not SHOP_STORE then
        return true
    end

    local userId = player.UserId
    if not force and ShopService._dirty[userId] ~= true then
        return true
    end

    local profile = ShopService._profiles[userId]
    if not profile then
        return true
    end

    local payload = serializeProfile(profile)
    local success = false
    local errMessage = nil
    for attempt = 1, MAX_SAVE_RETRIES do
        local okSave, result = pcall(function()
            SHOP_STORE:UpdateAsync(getPlayerKey(player), function(_oldValue)
                return payload
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
        ShopService._dirty[userId] = nil
    else
        warn("[ShopService] Failed saving player", userId, tostring(errMessage))
    end
    return success
end

local function loadPlayerProfile(player)
    local profile = makeDefaultProfile()
    local thirdSlotUnlocked = hasThirdSlotGamePass(player, false)
    if not SHOP_STORE then
        profile.thirdSlotUnlocked = thirdSlotUnlocked
        profile.thirdSlotGamePassId = getThirdSlotGamePassId()
        if not thirdSlotUnlocked then
            profile.equippedPowers[THIRD_POWER_SLOT_INDEX] = nil
        end
        ShopService._profiles[player.UserId] = profile
        ShopService._dirty[player.UserId] = nil
        return profile
    end

    local loaded = nil
    local loadedOk = false
    local loadErr = nil
    for attempt = 1, MAX_SAVE_RETRIES do
        local okLoad, result = pcall(function()
            return SHOP_STORE:GetAsync(getPlayerKey(player))
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
        profile = sanitizeLoadedProfile(loaded, thirdSlotUnlocked)
    elseif not loadedOk then
        warn("[ShopService] Failed loading player", player.UserId, tostring(loadErr))
    end

    profile.thirdSlotUnlocked = thirdSlotUnlocked
    profile.thirdSlotGamePassId = getThirdSlotGamePassId()
    if not thirdSlotUnlocked then
        profile.equippedPowers[THIRD_POWER_SLOT_INDEX] = nil
    end

    ShopService._profiles[player.UserId] = profile
    ShopService._dirty[player.UserId] = nil
    return profile
end

local function applyProfileToCharacter(player, char)
    if not player or not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    local profile = ShopService._profiles[player.UserId]
    if profile and humanoid then
        profile.hpBonus = computeProfileHpBonus(profile)
        humanoid.MaxHealth = 100 + (profile.hpBonus or 0)
        humanoid.Health = humanoid.MaxHealth
    end
    task.defer(function()
        applyEquippedWeapon(player)
    end)
end

local function bindCharacter(player)
    local userId = player.UserId
    local existing = ShopService._charConnections[userId]
    if existing and existing.Disconnect then
        existing:Disconnect()
    end

    ShopService._charConnections[userId] = player.CharacterAdded:Connect(function(char)
        applyProfileToCharacter(player, char)
    end)

    if player.Character then
        applyProfileToCharacter(player, player.Character)
    end
end

local function initPlayer(player)
    hasThirdSlotGamePass(player, true)
    loadPlayerProfile(player)
    bindCharacter(player)
    sendProfileUpdate(player)
end

local function canUseShop(player)
    return player and player:GetAttribute("InMatch") ~= true
end

function ShopService:Init()
    if self._initialized then
        return
    end
    self._initialized = true

    for _, player in ipairs(Players:GetPlayers()) do
        initPlayer(player)
    end

    Players.PlayerAdded:Connect(function(player)
        initPlayer(player)
    end)
    Players.PlayerRemoving:Connect(function(player)
        savePlayerProfile(player, true)
        ShopService._profiles[player.UserId] = nil
        ShopService._dirty[player.UserId] = nil
        ShopService._thirdSlotUnlockedByUserId[player.UserId] = nil
        local conn = ShopService._charConnections[player.UserId]
        if conn and conn.Disconnect then
            conn:Disconnect()
        end
        ShopService._charConnections[player.UserId] = nil
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

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
        if not player or player.Parent ~= Players then
            return
        end
        if gamePassId ~= getThirdSlotGamePassId() then
            return
        end

        local thirdUnlocked = wasPurchased == true
        if not thirdUnlocked then
            thirdUnlocked = hasThirdSlotGamePass(player, true)
        else
            ShopService._thirdSlotUnlockedByUserId[player.UserId] = true
        end

        local profile = ShopService._profiles[player.UserId]
        if profile then
            profile.thirdSlotUnlocked = thirdUnlocked
            profile.thirdSlotGamePassId = gamePassId
            if not thirdUnlocked then
                profile.equippedPowers[THIRD_POWER_SLOT_INDEX] = nil
            end
            sendProfileUpdate(player)
        end
    end)

    -- Remote handlers
    if REQ_PURCHASE then
        REQ_PURCHASE.OnServerEvent:Connect(function(player, itemId)
            pcall(function()
                ShopService:Purchase(player, itemId)
            end)
        end)
    end
    if REQ_EQUIP then
        REQ_EQUIP.OnServerEvent:Connect(function(player, itemId, slotIndex)
            pcall(function()
                -- equip weapon or power
                local it = ItemConfig.Get(itemId)
                if not it then return end
                if it.type == "Weapon" then
                    ShopService:EquipWeapon(player, itemId)
                elseif it.type == "Power" then
                    ShopService:EquipPower(player, itemId, slotIndex)
                end
            end)
        end)
    end
end

function ShopService:GetLoadout(player)
    local profile = ShopService._profiles[player.UserId]
    local thirdSlotUnlocked = hasThirdSlotGamePass(player, false)
    if not profile then
        profile = makeDefaultProfile()
        profile.hpBonus = computeProfileHpBonus(profile)
        ShopService._profiles[player.UserId] = profile
    end
    profile.thirdSlotUnlocked = thirdSlotUnlocked
    profile.thirdSlotGamePassId = getThirdSlotGamePassId()
    profile.equippedPowers = profile.equippedPowers or {}
    if not thirdSlotUnlocked then
        profile.equippedPowers[THIRD_POWER_SLOT_INDEX] = nil
    end
    return profile
end

function ShopService:Purchase(player, itemId)
    if not player then return false, "no-player" end
    if not canUseShop(player) then return false, "in-match" end
    local it = ItemConfig.Get(itemId)
    if not it then return false, "invalid-item" end
    if ItemConfig.IsShopEnabled and not ItemConfig.IsShopEnabled(it) then
        return false, "item-disabled"
    end
    local profile = ShopService:GetLoadout(player)

    -- upgrades cannot be bought twice (for non-stackable items)
    if it.type == "Upgrade" then
        -- Allow stacking for health upgrades by design, so do not block; but prevent duplicate exact purchase? requirement: Player cannot buy same upgrade twice -> interpret as same exact tier not repeat
        if profile.owned[itemId] then return false, "already-owned" end
    else
        if profile.owned[itemId] then return false, "already-owned" end
    end

    if not EconomyService then return false, "no-economy" end
    if not EconomyService:CanAfford(player, it.cost) then return false, "no-funds" end

    local ok = EconomyService:Spend(player, it.cost)
    if not ok then return false, "spend-failed" end

    -- grant item
    profile.owned[itemId] = true
    if it.type == "Upgrade" and it.hpBonus then
        profile.hpBonus = computeProfileHpBonus(profile)
        -- apply to current humanoid if present
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            local humanoid = player.Character.Humanoid
            humanoid.MaxHealth = 100 + profile.hpBonus
            humanoid.Health = humanoid.MaxHealth
        end
    end

    -- send update
    markDirty(player)
    sendProfileUpdate(player)
    return true
end

function ShopService:EquipWeapon(player, weaponId)
    if not player then return false end
    if not canUseShop(player) then return false, "in-match" end
    local profile = ShopService:GetLoadout(player)
    if weaponId ~= "fists" and not profile.owned[weaponId] then return false, "not-owned" end
    profile.equippedWeapon = weaponId
    applyEquippedWeapon(player)
    markDirty(player)
    sendProfileUpdate(player)
    return true
end

function ShopService:EquipPower(player, powerId, slotIndex)
    if not player then return false end
    if not canUseShop(player) then return false, "in-match" end
    local profile = ShopService:GetLoadout(player)
    if not profile.owned[powerId] then return false, "not-owned" end
    profile.equippedPowers = profile.equippedPowers or {}

    local thirdSlotUnlocked = hasThirdSlotGamePass(player, false)
    if slotIndex == THIRD_POWER_SLOT_INDEX and not thirdSlotUnlocked then
        thirdSlotUnlocked = hasThirdSlotGamePass(player, true)
    end
    local maxPowerSlots = thirdSlotUnlocked and MAX_POWER_SLOT_COUNT or BASE_POWER_SLOT_COUNT
    profile.thirdSlotUnlocked = thirdSlotUnlocked
    profile.thirdSlotGamePassId = getThirdSlotGamePassId()

    if slotIndex ~= 1 and slotIndex ~= 2 and slotIndex ~= THIRD_POWER_SLOT_INDEX then
        for i = 1, maxPowerSlots do
            if not profile.equippedPowers[i] then
                slotIndex = i
                break
            end
        end
        if slotIndex ~= 1 and slotIndex ~= 2 and slotIndex ~= THIRD_POWER_SLOT_INDEX then
            slotIndex = 1
        end
    end

    if slotIndex == THIRD_POWER_SLOT_INDEX and not thirdSlotUnlocked then
        profile.equippedPowers[THIRD_POWER_SLOT_INDEX] = nil
        sendProfileUpdate(player)
        return false, "third-slot-locked"
    end

    if not thirdSlotUnlocked then
        profile.equippedPowers[THIRD_POWER_SLOT_INDEX] = nil
    end

    -- if same power exists in any other active slot, clear it first
    for i = 1, maxPowerSlots do
        if i ~= slotIndex and profile.equippedPowers[i] == powerId then
            profile.equippedPowers[i] = nil
        end
    end

    -- toggle off if selecting the same slot
    if profile.equippedPowers[slotIndex] == powerId then
        profile.equippedPowers[slotIndex] = nil
    else
        profile.equippedPowers[slotIndex] = powerId
    end
    markDirty(player)
    sendProfileUpdate(player)
    return true
end

return ShopService
