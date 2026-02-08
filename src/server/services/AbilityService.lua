-- AbilityService: central handler for abilities
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
if not Shared then warn("Shared modules missing (AbilityService)") end
local Constants = require(Shared:WaitForChild("Constants"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local CooldownService = require(Shared:WaitForChild("CooldownService"))

local ShopService
local CombatService
pcall(function() ShopService = require(script.Parent.ShopService) end)
pcall(function() CombatService = require(script.Parent.CombatService) end)

local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not remotes then warn("Remotes folder missing (AbilityService)") end
local REQ_ABILITY = remotes:WaitForChild(Constants.RemoteNames.AbilityRequest, 5)
local EV_FX = remotes:WaitForChild(Constants.RemoteNames.AbilityFx, 5)

local AbilityService = {}

-- dynamic ability registry (moduleName -> module)
local abilityModules = {}
local activeAbilityLockByUserId = {} -- userId -> { abilityId = string, expiresAt = number? }
local TEST_MODE_ATTRIBUTE = "AFS_TestMode"
local TEST_MODE_LEGACY_ATTRIBUTE = "AFS_IgnoreRoundRules"
local STUNNED_UNTIL_ATTRIBUTE = "AFS_StunnedUntil"
local SANDEVISTAN_DEFER_COUNT_ATTR = "AFS_SandevistanDeferCount"

local function isTestModeEnabled()
    local v = Workspace:GetAttribute(TEST_MODE_ATTRIBUTE)
    if v ~= nil then
        return v == true
    end
    return Workspace:GetAttribute(TEST_MODE_LEGACY_ATTRIBUTE) == true
end

local function debugEnabled()
    local override = Workspace:GetAttribute("AFS_DebugLogs")
    if override ~= nil then
        return override == true
    end
    return RunService:IsStudio()
end

local function debugPrint(msg)
    if debugEnabled() then
        print(msg)
    end
end

local function isPlayerStunned(player)
    local character = player and player.Character
    if not character then
        return false
    end
    local stunnedUntil = character:GetAttribute(STUNNED_UNTIL_ATTRIBUTE)
    if type(stunnedUntil) ~= "number" then
        return false
    end
    if tick() >= stunnedUntil then
        character:SetAttribute(STUNNED_UNTIL_ATTRIBUTE, nil)
        return false
    end
    return true
end

local function isPlayerSandevistanFrozen(player)
    local character = player and player.Character
    if not character then
        return false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end
    local activeCount = humanoid:GetAttribute(SANDEVISTAN_DEFER_COUNT_ATTR)
    return type(activeCount) == "number" and activeCount > 0
end

local function clearActiveAbilityLock(userId)
    activeAbilityLockByUserId[userId] = nil
end

local function doesAbilityBlockOthers(abilityId, abilityDef)
    local def = abilityDef
    if not def and type(abilityId) == "string" and abilityId ~= "" then
        def = ItemConfig.Get(abilityId)
    end

    if def and def.blocksOtherAbilities == false then
        return false
    end
    return true
end

local function isActiveAbilityLockBlockingRequestedAbility(activeAbilityId, requestedAbilityId)
    if not doesAbilityBlockOthers(activeAbilityId) then
        return false
    end

    -- Allow Black Flame Barrage while Sandevistan is active.
    if activeAbilityId == "reality_break" and requestedAbilityId == "black_flame" then
        return false
    end

    return true
end

local function getActiveAbilityLock(player)
    if not player then
        return nil
    end

    local userId = player.UserId
    local lockState = activeAbilityLockByUserId[userId]
    if not lockState then
        return nil
    end

    if type(lockState.expiresAt) == "number" and tick() >= lockState.expiresAt then
        clearActiveAbilityLock(userId)
        return nil
    end

    local character = player.Character
    if not character then
        clearActiveAbilityLock(userId)
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        clearActiveAbilityLock(userId)
        return nil
    end

    local lockedAbilityId = lockState.abilityId
    local lockedAbilityModule = lockedAbilityId and abilityModules[lockedAbilityId]
    if lockedAbilityModule and lockedAbilityModule.IsActive then
        local ok, isActive = pcall(function()
            return lockedAbilityModule.IsActive(player)
        end)
        if not ok or isActive ~= true then
            clearActiveAbilityLock(userId)
            return nil
        end
    elseif not lockState.expiresAt then
        -- If the lock has no expiry and no runtime active check, clear it to avoid stuck states.
        clearActiveAbilityLock(userId)
        return nil
    end

    return lockState
end

local function trackActiveAbility(player, abilityId, abilityDef, abilityModule, executeResult)
    if not player or type(abilityId) ~= "string" or abilityId == "" then
        return
    end

    if not doesAbilityBlockOthers(abilityId, abilityDef) then
        local current = activeAbilityLockByUserId[player.UserId]
        if current and current.abilityId == abilityId then
            clearActiveAbilityLock(player.UserId)
        end
        return
    end

    local isActiveNow = false
    if abilityModule and abilityModule.IsActive then
        local ok, active = pcall(function()
            return abilityModule.IsActive(player)
        end)
        isActiveNow = ok and active == true
    end

    local lockDuration = nil
    if type(executeResult) == "table" and type(executeResult.activeDuration) == "number" and executeResult.activeDuration > 0 then
        lockDuration = executeResult.activeDuration
    elseif type(abilityDef.duration) == "number" and abilityDef.duration > 0 then
        lockDuration = abilityDef.duration
    end

    if not isActiveNow and not lockDuration then
        local current = activeAbilityLockByUserId[player.UserId]
        if current and current.abilityId == abilityId then
            clearActiveAbilityLock(player.UserId)
        end
        return
    end

    activeAbilityLockByUserId[player.UserId] = {
        abilityId = abilityId,
        expiresAt = lockDuration and (tick() + lockDuration) or nil,
    }
end

local function loadAbilityModule(id, modulePath)
    local ok, mod = pcall(function() return require(modulePath) end)
    if ok and mod then
        abilityModules[id] = mod
    end
end

-- Preload known ability modules
pcall(function()
    loadAbilityModule("water_striking_tide", script.Parent.Parent:WaitForChild("Abilities"):WaitForChild("WaterStrikingTide"))
    loadAbilityModule("fiber_sever_slash", script.Parent.Parent:WaitForChild("Abilities"):WaitForChild("FiberSeverSlash"))
    loadAbilityModule("spirit_surge", script.Parent.Parent:WaitForChild("Abilities"):WaitForChild("SpiritSurge"))
    loadAbilityModule("getsuga_tensho", script.Parent.Parent:WaitForChild("Abilities"):WaitForChild("GetsugaTensho"))
    loadAbilityModule("chidori_stream", script.Parent.Parent:WaitForChild("Abilities"):WaitForChild("ChidoriStream"))

    loadAbilityModule("kaioken", script.Parent.Parent:WaitForChild("Abilities"):WaitForChild("Kaioken"))
    loadAbilityModule("black_flame", script.Parent.Parent:WaitForChild("Abilities"):WaitForChild("BlackFlameBarrage"))
    loadAbilityModule("time_skip", script.Parent.Parent:WaitForChild("Abilities"):WaitForChild("TimeSkipStrike"))
    loadAbilityModule("flash_step", script.Parent.Parent:WaitForChild("Abilities"):WaitForChild("FlashStep"))
    loadAbilityModule("reality_break", script.Parent.Parent:WaitForChild("Abilities"):WaitForChild("RealityBreak"))
end)

local function validateAbilityUse(player, abilityDef)
    if not player or not abilityDef then return false, "invalid" end
    if abilityDef.requiresWeapon and ShopService then
        local profile = ShopService:GetLoadout(player)
        if not profile or profile.equippedWeapon ~= abilityDef.requiresWeapon then
            return false, "requires-weapon"
        end
    end
    if abilityDef.type == "Power" and ShopService then
        local profile = ShopService:GetLoadout(player)
        if not profile or not profile.owned[abilityDef.id] then
            return false, "not-owned"
        end
        local slot1 = profile.equippedPowers and profile.equippedPowers[1]
        local slot2 = profile.equippedPowers and profile.equippedPowers[2]
        local slot3 = profile.equippedPowers and profile.equippedPowers[3]
        if abilityDef.id ~= slot1 and abilityDef.id ~= slot2 and abilityDef.id ~= slot3 then
            return false, "not-equipped"
        end
    end
    -- cooldown check (server-side)
    if abilityDef.cooldown and not CooldownService:CanUse(player, abilityDef.id) then
        return false, "cooldown"
    end
    -- alive check
    if player.Character and player.Character:FindFirstChild("Humanoid") then
        if player.Character.Humanoid.Health <= 0 then return false, "dead" end
    end
    if isPlayerStunned(player) then
        return false, "stunned"
    end
    if isPlayerSandevistanFrozen(player) then
        return false, "frozen"
    end
    -- optional InMatch attribute: if set, ensure true
    local attr = player:GetAttribute("InMatch")
    if not isTestModeEnabled() and attr ~= nil and not attr then
        return false, "not-inmatch"
    end
    return true
end

function AbilityService:UseAbility(player, abilityId, payload)
    local abilityDef = ItemConfig.Get(abilityId)
    if not abilityDef then return false, "no-such-ability" end
    if isPlayerStunned(player) then
        return false, "stunned"
    end
    if isPlayerSandevistanFrozen(player) then
        return false, "frozen"
    end

    -- route to ability module
    local mod = abilityModules[abilityId]
    if not mod or not mod.Execute then return false, "ability-not-implemented" end

    local inputAction = (type(payload) == "table" and type(payload.action) == "string") and payload.action or nil
    local function dispatchAbilityInput(inputPayload)
        if not mod or not mod.HandleInput then
            return false, "ability-input-not-supported"
        end
        local success, handled, result = pcall(function()
            return mod.HandleInput(player, inputPayload, { CombatService = CombatService, EV_FX = EV_FX })
        end)
        if not success then
            return false, "ability-input-error"
        end
        if handled ~= true then
            return false, (type(result) == "string" and result) or "ability-input-failed"
        end
        return true, result
    end

    -- Optional input events (e.g. key release) bypass normal cooldown validation.
    if inputAction then
        local activeLock = getActiveAbilityLock(player)
        if activeLock
            and activeLock.abilityId ~= abilityId
            and isActiveAbilityLockBlockingRequestedAbility(activeLock.abilityId, abilityId)
        then
            return false, "ability-already-active"
        end
        local ok, result = dispatchAbilityInput(payload)
        if ok then
            getActiveAbilityLock(player)
        end
        return ok, result
    end

    -- Toggle-off path: if ability is already active and supports input handling,
    -- pressing its key again deactivates it without re-validating cooldown.
    if mod.IsActive and mod.HandleInput then
        local activeOk, isActive = pcall(function()
            return mod.IsActive(player)
        end)
        if activeOk and isActive == true then
            local ok, result = dispatchAbilityInput({ action = "release" })
            if ok then
                getActiveAbilityLock(player)
            end
            return ok, result
        end
    end

    local activeLock = getActiveAbilityLock(player)
    if activeLock
        and activeLock.abilityId ~= abilityId
        and isActiveAbilityLockBlockingRequestedAbility(activeLock.abilityId, abilityId)
    then
        return false, "ability-already-active"
    end

    -- attach id for cooldown use
    abilityDef.id = abilityId
    local ok, reason = validateAbilityUse(player, abilityDef)
    if not ok then return false, reason end

    -- execute ability (module should apply damage via CombatService)
    local success, executed, result = pcall(function()
        return mod.Execute(player, payload, { CombatService = CombatService, EV_FX = EV_FX })
    end)

    if not success then
        return false, "ability-error"
    end
    if executed ~= true then
        return false, (type(result) == "string" and result) or "ability-failed"
    end

    trackActiveAbility(player, abilityId, abilityDef, mod, result)

    local skipCooldown = type(result) == "table" and result.noCooldown == true

    -- start cooldown server-side only after successful execution
    if abilityDef.cooldown and not skipCooldown then
        CooldownService:StartCooldown(player, abilityId, abilityDef.cooldown)
    end

    local abilityName = abilityDef.name or abilityId
    debugPrint(string.format("[Ability] %s used \"%s\"", player.Name, abilityName))

    -- inform clients to play FX and start local cooldown display
    if EV_FX then
        EV_FX:FireAllClients({
            caster = player.UserId,
            fx = result and result.fx or nil,
            abilityId = abilityId,
            cooldown = skipCooldown and nil or abilityDef.cooldown,
        })
    end

    return true, result
end

Players.PlayerRemoving:Connect(function(player)
    clearActiveAbilityLock(player.UserId)
end)

-- Remote handler
REQ_ABILITY.OnServerEvent:Connect(function(player, abilityId, payload)
    pcall(function()
        local ok, reason = AbilityService:UseAbility(player, abilityId, payload)
        if not ok and debugEnabled() then
            debugPrint(string.format("[Ability] %s failed \"%s\": %s", player.Name, tostring(abilityId), tostring(reason)))
        end
    end)
end)

return AbilityService
