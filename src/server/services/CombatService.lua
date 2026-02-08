-- CombatService: server-authoritative attacks, hit validation, kill attribution
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
if not Shared then warn("Shared modules missing (CombatService)") end
local Constants = require(Shared:WaitForChild("Constants"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local ShopService
pcall(function() ShopService = require(script.Parent.ShopService) end)
local WeaponService
pcall(function() WeaponService = require(script.Parent.WeaponService) end)
local AbilityUtil
do
    local serverRoot = script.Parent and script.Parent.Parent
    local abilitiesFolder = serverRoot and serverRoot:FindFirstChild("Abilities")
    local utilModule = abilitiesFolder and abilitiesFolder:FindFirstChild("AbilityUtil")
    if utilModule then
        local okUtil, modUtil = pcall(require, utilModule)
        if okUtil and modUtil then
            AbilityUtil = modUtil
        end
    end
end

local CombatService = {}
CombatService._active = false
CombatService._players = {} -- userId -> player
CombatService._participants = {} -- array
CombatService._team = {} -- userId -> "spirit" | "challenger"
CombatService._lastAttack = {} -- userId -> {time=}
CombatService._lastDash = {} -- userId -> time
CombatService._m1RecoverUntil = {} -- userId -> timestamp
CombatService._lastDamagers = {} -- victimUserId -> { attackerUserId -> lastHitTime }
CombatService._connections = {}
CombatService._deferredDamageByHumanoid = setmetatable({}, { __mode = "k" }) -- humanoid -> queued damage state
CombatService.KILL_WINDOW = 6 -- seconds

local ANIM_ID_PREFIX = "rbxassetid://"
local attackAnimCache = {} -- animId -> Animation
local attackAnimDurationCache = {} -- animId -> seconds
local activeAttackTracks = {} -- userId -> { track = AnimationTrack, animId = string, humanoid = Humanoid, stoppedConn = RBXScriptConnection? }
local attackPlayToken = {} -- userId -> number
local blockBreakTrackByHumanoid = setmetatable({}, { __mode = "k" })
local blockLoopTrackStateByHumanoid = setmetatable({}, { __mode = "k" })
local dashTrackStateByHumanoid = setmetatable({}, { __mode = "k" })
local dashMoveTokenByCharacter = setmetatable({}, { __mode = "k" })

local MELEE_HITBOX_SIZE = Vector3.new(6, 5, 8)
local MELEE_FORWARD_OFFSET = 4
local MELEE_DOT_MIN = 0.2
local MELEE_PREFERRED_MAX_DISTANCE = 12
local MELEE_VERTICAL_TOLERANCE = 8
local HITBOX_DEBUG_LIFETIME = 0.15
local HITBOX_DEBUG_COLOR = Color3.fromRGB(255, 90, 90)
local DAMAGE_MULT_PREFIX = "DamageMult_"
local DEFAULT_ATTACK_COOLDOWN = 0.3
local MIN_ATTACK_COOLDOWN = 0.05
local ATTACK_ANIM_SPEED = 1
local TEST_MODE_ATTRIBUTE = "AFS_TestMode"
local TEST_MODE_LEGACY_ATTRIBUTE = "AFS_IgnoreRoundRules"
local ALLOW_DUMMY_DAMAGE_ATTRIBUTE = "AFS_AllowDummyDamage"
local SOUND_ID_PREFIX = "rbxassetid://"
local DEFAULT_SWORD_M1_SWING_SOUND_ID = "139595755396613"
local M1_HIT_SOUND_ID = "140139514810063"
local FIST_M1_SWING_SOUND_ID = "140139514810063"
local FIST_M1_MISS_SOUND_ID = "80018460671417"
local M1_HIT_MARKER = "Hit"
local M1_HIT_MARKER_ALT = "hit"
local M1_HIT_MARKER_FALLBACK_DELAY = 0.45
local M1_POST_HIT_RECOVERY = 0.2
local M1_SOUND_MAX_DISTANCE = 120
local FLASH_STEP_ACTIVE_ATTRIBUTE = "FlashStepActive"
local BLOCKING_STATE_ATTRIBUTE = "AFS_IsBlocking"
local BLOCK_POSTURE_ATTRIBUTE = "AFS_BlockPosture"
local BLOCK_POSTURE_MAX_ATTRIBUTE = "AFS_BlockPostureMax"
local BLOCK_GUARD_BROKEN_UNTIL_ATTRIBUTE = "AFS_GuardBrokenUntil"
local STUNNED_UNTIL_ATTRIBUTE = "AFS_StunnedUntil"
local BLOCK_DEFENSE_DISABLED_ATTRIBUTE = "DefenseDisabled"
local BLOCK_LOOP_ANIMATION_ATTRIBUTE = "AFS_BlockAnimationId"
local BLOCK_POSTURE_MAX = 50
local BLOCK_GUARD_BREAK_DURATION = 1.2
local BLOCK_BREAK_STUN_DURATION = 2.0
local BLOCK_BREAK_STUN_MOVEMENT_ID = "GuardBreakStun"
local BLOCK_MOVEMENT_ID = "Block"
local BLOCK_MOVE_SCALE = 0.72
local DEFAULT_BLOCK_LOOP_ANIMATION_ID = "124944234769911"
local BLOCK_HIT_SOUND_ID = "80809123525734"
local BLOCK_BREAK_SOUND_ID = "113917217579668"
local BLOCK_BREAK_ANIMATION_ID = "102128029055200"
local BLOCK_POSTURE_REGEN_RATE = 8 -- posture per second (passive)
local BLOCK_POSTURE_REGEN_TICK_INTERVAL = 0.1 -- update interval in seconds
local DASH_COOLDOWN = 1
local DASH_DISTANCE = 9
local DASH_BACKOFF = 1
local DASH_MIN_INPUT_MAGNITUDE = 0.05
local DASH_GLIDE_SPEED = 62
local DASH_GLIDE_MIN_DURATION = 0.12
local DASH_GLIDE_MAX_DURATION = 0.24
local DASH_ANIMATION_ID = ""
local DASH_SOUND_ID = "137431264282253"
local DASH_SOUND_VOLUME = 0.85
local SANDEVISTAN_DEFER_COUNT_ATTR = "AFS_SandevistanDeferCount"
local SANDEVISTAN_DEFER_TOTAL_ATTR = "AFS_SandevistanDeferTotal"
local SANDEVISTAN_DEFER_BY_PREFIX = "AFS_SandevistanDeferBy_"
local FISTS_WEAPON_ID = "fists"
local MARKER_TIMED_SWORD_WEAPON_IDS = {
    nichirin_katana = true,
    scissor_blade = true,
    zangetsu_bankai = true,
    dragon_slayer = true,
}
local SWORD_WEAPON_IDS = {
    nichirin_katana = true,
    scissor_blade = true,
    spirit_sword = true,
    zangetsu_bankai = true,
    kusanagi_blade = true,
    dragon_slayer = true,
}
local SWORD_SWING_SOUND_BY_WEAPON = {
    nichirin_katana = "83608346371642",
    scissor_blade = "83608346371642",
    dragon_slayer = "97151139235328",
}

local WEAPON_MODEL_NAME = (WeaponService and WeaponService.WeaponModelName) or "AFS_WeaponModel"
local WEAPON_ATTRIBUTE = (WeaponService and WeaponService.WeaponAttribute) or "AFS_Weapon"
local WEAPON_ID_ATTRIBUTE = (WeaponService and WeaponService.WeaponIdAttribute) or "AFS_WeaponId"

local function normalizeAnimId(id)
    if not id or id == "" then return nil end
    id = tostring(id)
    if id:sub(1, #ANIM_ID_PREFIX) ~= ANIM_ID_PREFIX then
        id = ANIM_ID_PREFIX .. id
    end
    return id
end

local function getRootPart(character)
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

local function normalizeSoundId(id)
    if not id or id == "" then return nil end
    id = tostring(id)
    if id:sub(1, #SOUND_ID_PREFIX) ~= SOUND_ID_PREFIX then
        id = SOUND_ID_PREFIX .. id
    end
    return id
end

local function isSwordWeaponId(weaponId)
    if type(weaponId) ~= "string" or weaponId == "" then
        return false
    end
    return SWORD_WEAPON_IDS[weaponId] == true
end

local function isFistsWeaponId(weaponId)
    return weaponId == FISTS_WEAPON_ID
end

local function getSwordSwingSoundId(weaponId)
    if type(weaponId) ~= "string" or weaponId == "" then
        return DEFAULT_SWORD_M1_SWING_SOUND_ID
    end
    return SWORD_SWING_SOUND_BY_WEAPON[weaponId] or DEFAULT_SWORD_M1_SWING_SOUND_ID
end

local function playOneShotSoundAtRoot(rootPart, soundId, volume, maxDistance)
    local resolved = normalizeSoundId(soundId)
    if not rootPart or not resolved then return end
    local sound = Instance.new("Sound")
    sound.Name = "AFS_M1Sfx"
    sound.SoundId = resolved
    sound.Volume = volume or 1
    sound.RollOffMode = Enum.RollOffMode.InverseTapered
    sound.RollOffMaxDistance = maxDistance or M1_SOUND_MAX_DISTANCE
    sound.Parent = rootPart
    sound:Play()
    Debris:AddItem(sound, 3)
end

local function isDebugHitboxEnabled()
    local override = Workspace:GetAttribute("AFS_ShowHitboxes")
    if override ~= nil then
        return override == true
    end
    return RunService:IsStudio()
end

local function isDamageDebugEnabled()
    local override = Workspace:GetAttribute("AFS_DebugDamage")
    if override ~= nil then
        return override == true
    end

    local logs = Workspace:GetAttribute("AFS_DebugLogs")
    if logs ~= nil then
        return logs == true
    end

    return RunService:IsStudio()
end

local function getDebugFolder()
    local folder = Workspace:FindFirstChild("AFS_DebugHitboxes")
    if folder and folder:IsA("Folder") then
        return folder
    end
    folder = Instance.new("Folder")
    folder.Name = "AFS_DebugHitboxes"
    folder.Parent = Workspace
    return folder
end

local function drawMeleeHitbox(cframe, size)
    if not isDebugHitboxEnabled() then return end
    local part = Instance.new("Part")
    part.Name = "AFS_MeleeHitbox"
    part.Size = size
    part.CFrame = cframe
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Transparency = 0.7
    part.Material = Enum.Material.ForceField
    part.Color = HITBOX_DEBUG_COLOR
    part.Parent = getDebugFolder()
    task.delay(HITBOX_DEBUG_LIFETIME, function()
        if part then
            part:Destroy()
        end
    end)
end

local function getAnimator(humanoid)
    if not humanoid then return nil end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end
    return animator
end

local function isTrackUsable(track)
    if not track then
        return false
    end
    local ok = pcall(function()
        local _ = track.IsPlaying
        local __ = track.Length
        return _ ~= nil and __ ~= nil
    end)
    return ok
end

local function stopAndDestroyTrack(track, fadeTime)
    if not isTrackUsable(track) then
        return
    end
    pcall(function()
        if track.IsPlaying then
            track:Stop(fadeTime or 0)
        end
    end)
    pcall(function()
        track:Destroy()
    end)
end

local function clearAttackTrackState(userId, fadeTime)
    local state = activeAttackTracks[userId]
    if not state then
        return
    end
    if state.stoppedConn and state.stoppedConn.Disconnect then
        state.stoppedConn:Disconnect()
        state.stoppedConn = nil
    end
    stopAndDestroyTrack(state.track, fadeTime or 0)
    activeAttackTracks[userId] = nil
end

local function getValidAttackTrackState(userId)
    local state = activeAttackTracks[userId]
    if not state then
        return nil
    end
    if not isTrackUsable(state.track) then
        clearAttackTrackState(userId, 0)
        return nil
    end
    return state
end

local function getDashTrack(humanoid)
    if not humanoid then
        return nil
    end
    local animId = normalizeAnimId(DASH_ANIMATION_ID)
    if not animId then
        return nil
    end

    local state = dashTrackStateByHumanoid[humanoid]
    if state and state.animId == animId and isTrackUsable(state.track) then
        return state.track
    end
    if state and state.track then
        stopAndDestroyTrack(state.track, 0)
    end
    dashTrackStateByHumanoid[humanoid] = nil

    local animator = getAnimator(humanoid)
    if not animator then
        return nil
    end

    local anim = attackAnimCache[animId]
    if not anim then
        anim = Instance.new("Animation")
        anim.AnimationId = animId
        attackAnimCache[animId] = anim
    end

    local ok, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    if not ok or not track then
        return nil
    end
    track.Priority = Enum.AnimationPriority.Action4
    track.Looped = false
    dashTrackStateByHumanoid[humanoid] = {
        animId = animId,
        track = track,
    }
    return track
end

local function playDashAnimation(humanoid)
    local track = getDashTrack(humanoid)
    if not track then
        return
    end
    if track.IsPlaying then
        track:Stop(0.03)
    end
    track:Play(0.03, 1, 1)
end

local function getBlockBreakTrack(humanoid)
    if not humanoid then return nil end
    local cached = blockBreakTrackByHumanoid[humanoid]
    if isTrackUsable(cached) then
        return cached
    end

    local animator = getAnimator(humanoid)
    if not animator then
        return nil
    end

    local animId = normalizeAnimId(BLOCK_BREAK_ANIMATION_ID)
    if not animId then
        return nil
    end

    local anim = attackAnimCache[animId]
    if not anim then
        anim = Instance.new("Animation")
        anim.AnimationId = animId
        attackAnimCache[animId] = anim
    end

    local ok, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    if not ok or not track then
        return nil
    end

    track.Priority = Enum.AnimationPriority.Action4
    track.Looped = false
    blockBreakTrackByHumanoid[humanoid] = track
    return track
end

local function getBlockLoopTrack(humanoid, animationId)
    if not humanoid or type(animationId) ~= "string" or animationId == "" then
        return nil
    end

    local state = blockLoopTrackStateByHumanoid[humanoid]
    if state and state.animationId == animationId and isTrackUsable(state.track) then
        return state.track
    end

    if state and state.track then
        stopAndDestroyTrack(state.track, 0.05)
    end
    blockLoopTrackStateByHumanoid[humanoid] = nil

    local animator = getAnimator(humanoid)
    if not animator then
        return nil
    end

    local anim = attackAnimCache[animationId]
    if not anim then
        anim = Instance.new("Animation")
        anim.AnimationId = animationId
        attackAnimCache[animationId] = anim
    end

    local ok, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    if not ok or not track then
        return nil
    end

    track.Priority = Enum.AnimationPriority.Action
    track.Looped = true
    blockLoopTrackStateByHumanoid[humanoid] = {
        animationId = animationId,
        track = track,
    }
    return track
end

local function syncCharacterBlockLoopAnimation(character, enabled)
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local desiredAnimId = normalizeAnimId(character:GetAttribute(BLOCK_LOOP_ANIMATION_ATTRIBUTE))
        or normalizeAnimId(DEFAULT_BLOCK_LOOP_ANIMATION_ID)
    local state = blockLoopTrackStateByHumanoid[humanoid]

    if not enabled or not desiredAnimId then
        if state and state.track and state.track.IsPlaying then
            state.track:Stop(0.1)
        end
        return
    end

    local track = getBlockLoopTrack(humanoid, desiredAnimId)
    if track and not track.IsPlaying then
        track:Play(0.1, 1, 1)
    end
end

local function recomputeHumanoidMovement(humanoid)
    if not humanoid then
        return
    end
    if humanoid:GetAttribute("BaseWalkSpeed") == nil then
        humanoid:SetAttribute("BaseWalkSpeed", humanoid.WalkSpeed)
    end
    if humanoid:GetAttribute("BaseJumpPower") == nil then
        humanoid:SetAttribute("BaseJumpPower", humanoid.JumpPower)
    end

    if AbilityUtil and AbilityUtil.recomputeMovement then
        AbilityUtil.recomputeMovement(humanoid)
        return
    end

    local baseWalk = humanoid:GetAttribute("BaseWalkSpeed") or humanoid.WalkSpeed
    local baseJump = humanoid:GetAttribute("BaseJumpPower") or humanoid.JumpPower
    local moveScale = 1
    local jumpScale = 1
    local attrs = humanoid:GetAttributes()
    for key, value in pairs(attrs) do
        if type(value) == "number" then
            if key:sub(1, 10) == "MoveScale_" then
                moveScale = math.min(moveScale, value)
            elseif key:sub(1, 10) == "JumpScale_" then
                jumpScale = math.min(jumpScale, value)
            end
        end
    end
    humanoid.WalkSpeed = baseWalk * moveScale
    humanoid.JumpPower = baseJump * jumpScale
end

local function setBlockMovementSlow(humanoid, enabled)
    if not humanoid then
        return
    end
    local moveAttr = "MoveScale_" .. BLOCK_MOVEMENT_ID
    if enabled then
        humanoid:SetAttribute(moveAttr, BLOCK_MOVE_SCALE)
    else
        humanoid:SetAttribute(moveAttr, nil)
    end
    recomputeHumanoidMovement(humanoid)
end

local function setStunMovementLock(humanoid, enabled)
    if not humanoid then
        return
    end
    local moveAttr = "MoveScale_" .. BLOCK_BREAK_STUN_MOVEMENT_ID
    local jumpAttr = "JumpScale_" .. BLOCK_BREAK_STUN_MOVEMENT_ID
    if enabled then
        humanoid:SetAttribute(moveAttr, 0)
        humanoid:SetAttribute(jumpAttr, 0)
    else
        humanoid:SetAttribute(moveAttr, nil)
        humanoid:SetAttribute(jumpAttr, nil)
    end
    recomputeHumanoidMovement(humanoid)
end

local function clearCharacterStun(character)
    if not character then
        return
    end
    character:SetAttribute(STUNNED_UNTIL_ATTRIBUTE, nil)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        setStunMovementLock(humanoid, false)
    end
end

local function isCharacterStunned(character)
    if not character then
        return false
    end
    local stunnedUntil = character:GetAttribute(STUNNED_UNTIL_ATTRIBUTE)
    if type(stunnedUntil) ~= "number" then
        return false
    end
    if tick() >= stunnedUntil then
        clearCharacterStun(character)
        return false
    end
    return true
end

local function applyCharacterStun(character, duration)
    if not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return
    end

    local stunDuration = math.max(0, tonumber(duration) or 0)
    if stunDuration <= 0 then
        return
    end

    local untilTime = tick() + stunDuration
    character:SetAttribute(STUNNED_UNTIL_ATTRIBUTE, untilTime)
    character:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
    syncCharacterBlockLoopAnimation(character, false)
    setStunMovementLock(humanoid, true)

    task.delay(stunDuration, function()
        if not character or not character.Parent then
            return
        end
        local currentUntil = character:GetAttribute(STUNNED_UNTIL_ATTRIBUTE)
        if currentUntil ~= untilTime then
            return
        end
        if tick() < untilTime then
            return
        end
        clearCharacterStun(character)
    end)
end

local function playBlockHitEffects(character)
    local root = getRootPart(character)
    playOneShotSoundAtRoot(root, BLOCK_HIT_SOUND_ID, 1, M1_SOUND_MAX_DISTANCE)
end

local function playBlockBreakEffects(character)
    local root = getRootPart(character)
    playOneShotSoundAtRoot(root, BLOCK_BREAK_SOUND_ID, 1, M1_SOUND_MAX_DISTANCE)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local track = getBlockBreakTrack(humanoid)
    if track then
        if track.IsPlaying then
            track:Stop(0.05)
        end
        track:Play(0.05, 1, 1)
    end
end

local function isTestModeEnabled()
    local v = Workspace:GetAttribute(TEST_MODE_ATTRIBUTE)
    if v ~= nil then
        return v == true
    end
    return Workspace:GetAttribute(TEST_MODE_LEGACY_ATTRIBUTE) == true
end

local function canDamageDummyRigs()
    local override = Workspace:GetAttribute(ALLOW_DUMMY_DAMAGE_ATTRIBUTE)
    if override ~= nil then
        return override == true
    end
    return isTestModeEnabled() or RunService:IsStudio()
end

local function getEquippedWeaponId(player)
    if player and player.Character then
        local character = player.Character
        local weaponModel = character:FindFirstChild(WEAPON_MODEL_NAME)
        if not weaponModel then
            for _, child in ipairs(character:GetChildren()) do
                if child:GetAttribute(WEAPON_ATTRIBUTE) == true then
                    weaponModel = child
                    break
                end
            end
        end

        if weaponModel then
            local weaponIdAttr = weaponModel:GetAttribute(WEAPON_ID_ATTRIBUTE)
            if type(weaponIdAttr) == "string" and weaponIdAttr ~= "" then
                return weaponIdAttr
            end
        end
    end

    if player and ShopService and ShopService.GetLoadout then
        local profile = ShopService:GetLoadout(player)
        if profile and type(profile.equippedWeapon) == "string" and profile.equippedWeapon ~= "" then
            return profile.equippedWeapon
        end
    end

    return "fists"
end

local function getWeaponAnimId(player)
    local weaponId = getEquippedWeaponId(player)
    local stats = ItemConfig.GetWeaponStats(weaponId)
    local animId = stats and stats.attackAnimationId
    if not animId or animId == "" then
        local fallback = ItemConfig.GetWeaponStats("fists")
        animId = fallback and fallback.attackAnimationId
    end
    return normalizeAnimId(animId)
end

local function playAttackAnimation(player)
    local fallbackCooldown = DEFAULT_ATTACK_COOLDOWN
    if not player or not player.Character then return fallbackCooldown end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return fallbackCooldown end
    local userId = player.UserId
    local token = (attackPlayToken[userId] or 0) + 1
    attackPlayToken[userId] = token

    if WeaponService and WeaponService.Unsheathe then
        WeaponService:Unsheathe(player)
    end

    local animId = getWeaponAnimId(player)
    local attackDuration = fallbackCooldown
    if not animId then
        if WeaponService and WeaponService.Sheathe and attackPlayToken[userId] == token then
            WeaponService:Sheathe(player)
        end
        return attackDuration
    end

    attackDuration = attackAnimDurationCache[animId] or attackDuration

    local animator = getAnimator(hum)
    if not animator then return attackDuration end

    local anim = attackAnimCache[animId]
    if not anim then
        anim = Instance.new("Animation")
        anim.AnimationId = animId
        attackAnimCache[animId] = anim
    end

    local state = getValidAttackTrackState(userId)
    if state and (state.humanoid ~= hum or state.animId ~= animId) then
        clearAttackTrackState(userId, 0.05)
        state = nil
    end

    if not state then
        local ok, trackOrErr = pcall(function()
            return animator:LoadAnimation(anim)
        end)
        if not ok or not trackOrErr then
            if WeaponService and WeaponService.Sheathe and attackPlayToken[userId] == token then
                WeaponService:Sheathe(player)
            end
            return attackDuration
        end
        state = {
            track = trackOrErr,
            animId = animId,
            humanoid = hum,
            stoppedConn = nil,
        }
        activeAttackTracks[userId] = state
    end

    local track = state.track
    track.Priority = Enum.AnimationPriority.Action

    if state.stoppedConn and state.stoppedConn.Disconnect then
        state.stoppedConn:Disconnect()
        state.stoppedConn = nil
    end
    if track.IsPlaying then
        track:Stop(0.05)
    end

    local length = track.Length
    if type(length) == "number" and length > 0 then
        attackDuration = math.max(MIN_ATTACK_COOLDOWN, length / ATTACK_ANIM_SPEED)
        attackAnimDurationCache[animId] = attackDuration
    end

    state.stoppedConn = track.Stopped:Connect(function()
        if attackPlayToken[userId] ~= token then
            return
        end
        if WeaponService and WeaponService.Sheathe then
            WeaponService:Sheathe(player)
        end
    end)

    track:Play(0.05, 1, ATTACK_ANIM_SPEED)
    return attackDuration, track
end

local function getDamageMultiplier(player)
    local mult = 1.0
    if not player then return mult end
    local attrs = player:GetAttributes()
    for k, v in pairs(attrs) do
        if type(v) == "number" and k:sub(1, #DAMAGE_MULT_PREFIX) == DAMAGE_MULT_PREFIX then
            mult = mult * v
        end
    end
    return mult
end

local function formatDamageLog(damage: number, mult: number): string
    if mult > 1.001 or mult < 0.999 then
        local multText = string.format("%.2f", mult):gsub("%.?0+$", "")
        return string.format("dmg: %d (%sx)", damage, multText)
    end
    return string.format("dmg: %d", damage)
end

local function debugDamage(attacker: Player?, victimLabel: string, damage: number, mult: number, source: string?)
    if not isDamageDebugEnabled() then return end
    local attackerName = attacker and attacker.Name or "Unknown"
    local src = source and (" | " .. source) or ""
    print(string.format("[Damage] %s -> %s | %s%s", attackerName, victimLabel, formatDamageLog(damage, mult), src))
end

local function getLifesteal(player)
    local ls = 0
    if not player then return ls end
    local attrs = player:GetAttributes()
    for k, v in pairs(attrs) do
        if type(v) == "number" and k:sub(1, 10) == "Lifesteal_" then
            ls = ls + v
        end
    end
    if ls < 0 then ls = 0 end
    if ls > 1 then ls = 1 end
    return ls
end

local function applyLifesteal(attacker, amount)
    if not attacker or amount <= 0 then return end
    local ls = getLifesteal(attacker)
    if ls <= 0 then return end
    local char = attacker.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    hum.Health = math.min(hum.MaxHealth, hum.Health + (amount * ls))
end

-- Events
local PlayerDiedEvent = Instance.new("BindableEvent")
CombatService.PlayerDied = PlayerDiedEvent

-- Remote
local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not remotes then warn("Remotes folder missing (CombatService)") end
local REQ_ATTACK = remotes:WaitForChild(Constants.RemoteNames.AttackRequest, 5)
local REQ_BLOCK = remotes:WaitForChild(Constants.RemoteNames.BlockRequest, 5)
local REQ_DASH = remotes:WaitForChild(Constants.RemoteNames.DashRequest, 5)
local EV_DAMAGE_POPUP = remotes:WaitForChild(Constants.RemoteNames.DamagePopup, 5)

local function getWeaponBaseDamage(player)
    local weaponId = getEquippedWeaponId(player)
    local stats = ItemConfig.GetWeaponStats(weaponId)
    return (stats and stats.baseDamage) or 5
end

local function fireDamagePopup(attacker, victimPlayer, damage)
    if not EV_DAMAGE_POPUP or not attacker or not victimPlayer then return end
    if damage <= 0 then return end
    EV_DAMAGE_POPUP:FireClient(attacker, {
        targetUserId = victimPlayer.UserId,
        damage = damage,
    })
end

local function getCharacterBlockPosture(character)
    if not character then
        return 0, BLOCK_POSTURE_MAX
    end

    local maxPosture = character:GetAttribute(BLOCK_POSTURE_MAX_ATTRIBUTE)
    if type(maxPosture) ~= "number" or maxPosture <= 0 then
        maxPosture = BLOCK_POSTURE_MAX
        character:SetAttribute(BLOCK_POSTURE_MAX_ATTRIBUTE, maxPosture)
    else
        maxPosture = math.max(1, math.floor(maxPosture))
    end

    local posture = character:GetAttribute(BLOCK_POSTURE_ATTRIBUTE)
    if type(posture) ~= "number" then
        posture = maxPosture
    else
        posture = math.floor(posture)
        posture = math.clamp(posture, 0, maxPosture)
    end
    character:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, posture)
    return posture, maxPosture
end

local function resetCharacterBlockState(character, resetPosture)
    if not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    character:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
    syncCharacterBlockLoopAnimation(character, false)
    setBlockMovementSlow(humanoid, false)
    character:SetAttribute(BLOCK_GUARD_BROKEN_UNTIL_ATTRIBUTE, nil)
    clearCharacterStun(character)
    local _, maxPosture = getCharacterBlockPosture(character)
    if resetPosture then
        character:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, maxPosture)
    end
end

local function isGuardBroken(character)
    if not character then
        return false
    end
    local guardBrokenUntil = character:GetAttribute(BLOCK_GUARD_BROKEN_UNTIL_ATTRIBUTE)
    if type(guardBrokenUntil) ~= "number" then
        return false
    end
    if tick() >= guardBrokenUntil then
        character:SetAttribute(BLOCK_GUARD_BROKEN_UNTIL_ATTRIBUTE, nil)
        return false
    end
    return true
end

local function applyGuardBreak(character, postureRecovery)
    if not character then
        return
    end

    local untilTime = tick() + BLOCK_GUARD_BREAK_DURATION
    character:SetAttribute(BLOCK_GUARD_BROKEN_UNTIL_ATTRIBUTE, untilTime)
    character:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
    syncCharacterBlockLoopAnimation(character, false)
    character:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, 0)
    playBlockBreakEffects(character)
    applyCharacterStun(character, BLOCK_BREAK_STUN_DURATION)

    task.delay(BLOCK_GUARD_BREAK_DURATION, function()
        if not character or not character.Parent then
            return
        end
        if character:GetAttribute(BLOCK_GUARD_BROKEN_UNTIL_ATTRIBUTE) ~= untilTime then
            return
        end
        character:SetAttribute(BLOCK_GUARD_BROKEN_UNTIL_ATTRIBUTE, nil)
        character:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, math.max(1, math.floor(postureRecovery or BLOCK_POSTURE_MAX)))
    end)
end

local function clearDeferredDamageAttributes(victimHumanoid)
    if not victimHumanoid then
        return
    end
    victimHumanoid:SetAttribute(SANDEVISTAN_DEFER_COUNT_ATTR, nil)
    victimHumanoid:SetAttribute(SANDEVISTAN_DEFER_TOTAL_ATTR, nil)

    local attrs = victimHumanoid:GetAttributes()
    for attrName, _ in pairs(attrs) do
        if type(attrName) == "string" and attrName:sub(1, #SANDEVISTAN_DEFER_BY_PREFIX) == SANDEVISTAN_DEFER_BY_PREFIX then
            victimHumanoid:SetAttribute(attrName, nil)
        end
    end
end

local function getVictimContext(victimHumanoid)
    local victimCharacter = victimHumanoid and victimHumanoid.Parent
    local victimPlayer = nil
    local victimLabel = "DummyRig"

    if victimCharacter and victimCharacter:IsA("Model") then
        victimPlayer = Players:GetPlayerFromCharacter(victimCharacter)
        if victimPlayer then
            victimLabel = victimPlayer.Name
        elseif victimCharacter.Name ~= "" then
            victimLabel = victimCharacter.Name
        end
    end

    return victimCharacter, victimPlayer, victimLabel
end

local function getDeferredDamageState(victimHumanoid, createIfMissing)
    local state = CombatService._deferredDamageByHumanoid[victimHumanoid]
    if state or not createIfMissing then
        return state
    end

    state = {
        effects = {},
        totalDamage = 0,
        byAttacker = {},
    }
    CombatService._deferredDamageByHumanoid[victimHumanoid] = state
    return state
end

local function hasActiveDeferredEffects(state)
    return state and next(state.effects) ~= nil
end

local function isDeferredDamageActive(victimHumanoid)
    local activeCount = victimHumanoid and victimHumanoid:GetAttribute(SANDEVISTAN_DEFER_COUNT_ATTR)
    if type(activeCount) == "number" and activeCount > 0 then
        return true
    end
    local state = getDeferredDamageState(victimHumanoid, false)
    return hasActiveDeferredEffects(state)
end

local function queueDeferredDamage(attacker, victimHumanoid, damage, source, explicitVictimLabel)
    if not attacker or not victimHumanoid then return end
    local state = getDeferredDamageState(victimHumanoid, true)
    if not state then return end

    state.totalDamage = (state.totalDamage or 0) + damage
    state.byAttacker[attacker.UserId] = (state.byAttacker[attacker.UserId] or 0) + damage

    local totalAttr = victimHumanoid:GetAttribute(SANDEVISTAN_DEFER_TOTAL_ATTR)
    local queuedTotal = (type(totalAttr) == "number" and totalAttr or 0) + damage
    victimHumanoid:SetAttribute(SANDEVISTAN_DEFER_TOTAL_ATTR, queuedTotal)

    local byAttackerAttrName = SANDEVISTAN_DEFER_BY_PREFIX .. tostring(attacker.UserId)
    local byAttackerAttr = victimHumanoid:GetAttribute(byAttackerAttrName)
    local queuedByAttacker = (type(byAttackerAttr) == "number" and byAttackerAttr or 0) + damage
    victimHumanoid:SetAttribute(byAttackerAttrName, queuedByAttacker)

    local _, _, resolvedVictimLabel = getVictimContext(victimHumanoid)
    local victimLabel = explicitVictimLabel or resolvedVictimLabel
    local taggedSource = source and ("queued:" .. source) or "queued:sandevistan"
    debugDamage(attacker, victimLabel, damage, getDamageMultiplier(attacker), taggedSource)
end

local function queueDeferredGuardBreak(victimHumanoid, victimCharacter, postureRecovery)
    if not victimHumanoid then
        return false
    end

    local state = getDeferredDamageState(victimHumanoid, true)
    if not state then
        return false
    end

    state.pendingGuardBreak = true
    state.pendingGuardBreakCharacter = victimCharacter
    state.pendingGuardBreakPostureRecovery = math.max(1, math.floor(postureRecovery or BLOCK_POSTURE_MAX))
    return true
end

local function releaseDeferredGuardBreak(victimHumanoid, state)
    if not state or state.pendingGuardBreak ~= true then
        return
    end

    local victimCharacter = state.pendingGuardBreakCharacter
    if not victimCharacter or not victimCharacter.Parent then
        local parent = victimHumanoid and victimHumanoid.Parent
        if parent and parent:IsA("Model") then
            victimCharacter = parent
        else
            victimCharacter = nil
        end
    end

    if victimCharacter then
        applyGuardBreak(victimCharacter, state.pendingGuardBreakPostureRecovery)
    end

    state.pendingGuardBreak = nil
    state.pendingGuardBreakCharacter = nil
    state.pendingGuardBreakPostureRecovery = nil
end

local function triggerGuardBreak(victimCharacter, postureRecovery)
    if not victimCharacter then
        return
    end

    local recovery = math.max(1, math.floor(postureRecovery or BLOCK_POSTURE_MAX))
    local victimHumanoid = victimCharacter:FindFirstChildOfClass("Humanoid")
    if victimHumanoid and isDeferredDamageActive(victimHumanoid) then
        victimCharacter:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
        syncCharacterBlockLoopAnimation(victimCharacter, false)
        victimCharacter:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, 0)
        if queueDeferredGuardBreak(victimHumanoid, victimCharacter, recovery) then
            return
        end
    end

    applyGuardBreak(victimCharacter, recovery)
end

local function flushDeferredDamage(victimHumanoid, state)
    if not victimHumanoid then
        return
    end

    CombatService._deferredDamageByHumanoid[victimHumanoid] = nil

    local queuedTotalAttr = victimHumanoid:GetAttribute(SANDEVISTAN_DEFER_TOTAL_ATTR)
    local queuedTotal = math.max(
        0,
        math.floor(math.max(
            type(queuedTotalAttr) == "number" and queuedTotalAttr or 0,
            (state and state.totalDamage) or 0
        ))
    )
    victimHumanoid:SetAttribute(SANDEVISTAN_DEFER_TOTAL_ATTR, nil)

    local contributions = {}
    local hasAttributeContributions = false
    local attrs = victimHumanoid:GetAttributes()
    for attrName, attrValue in pairs(attrs) do
        if type(attrName) == "string" and attrName:sub(1, #SANDEVISTAN_DEFER_BY_PREFIX) == SANDEVISTAN_DEFER_BY_PREFIX then
            local attackerUserId = tonumber(attrName:sub(#SANDEVISTAN_DEFER_BY_PREFIX + 1))
            if attackerUserId and type(attrValue) == "number" and attrValue > 0 then
                contributions[attackerUserId] = (contributions[attackerUserId] or 0) + attrValue
                hasAttributeContributions = true
            end
            victimHumanoid:SetAttribute(attrName, nil)
        end
    end

    if not hasAttributeContributions and state and state.byAttacker then
        for attackerUserId, contribution in pairs(state.byAttacker) do
            contributions[attackerUserId] = (contributions[attackerUserId] or 0) + (contribution or 0)
        end
    end

    if queuedTotal <= 0 then
        return
    end
    if not victimHumanoid.Parent or victimHumanoid.Health <= 0 then
        return
    end

    local victimCharacter, victimPlayer, victimLabel = getVictimContext(victimHumanoid)
    if not victimCharacter then
        return
    end

    for _, child in ipairs(victimCharacter:GetChildren()) do
        if child:IsA("ForceField") then
            child:Destroy()
        end
    end

    if victimPlayer then
        local now = tick()
        CombatService._lastDamagers[victimPlayer.UserId] = CombatService._lastDamagers[victimPlayer.UserId] or {}
        for attackerUserId, contribution in pairs(contributions) do
            if math.floor(contribution or 0) > 0 then
                CombatService._lastDamagers[victimPlayer.UserId][attackerUserId] = now
            end
        end
    end

    victimHumanoid:TakeDamage(queuedTotal)

    for attackerUserId, contribution in pairs(contributions) do
        local damagePortion = math.max(0, math.floor(contribution or 0))
        if damagePortion > 0 then
            local attacker = Players:GetPlayerByUserId(attackerUserId)
            if attacker then
                applyLifesteal(attacker, damagePortion)
                if victimPlayer then
                    fireDamagePopup(attacker, victimPlayer, damagePortion)
                end
                debugDamage(attacker, victimLabel, damagePortion, getDamageMultiplier(attacker), "sandevistan-release")
            end
        end
    end
end

-- Helper
local function isParticipant(player)
    return CombatService._players[player.UserId] ~= nil
end

local function allowDamageOutsideActiveMatch()
    local override = Workspace:GetAttribute("AFS_AllowLobbyDamage")
    if override ~= nil then
        return override == true
    end
    -- Public server default: keep lobby/non-match combat disabled unless explicitly enabled.
    return false
end

local function canUseCombatInput(player)
    if not player then
        return false
    end
    if isTestModeEnabled() or RunService:IsStudio() then
        return true
    end
    if CombatService._active then
        return isParticipant(player)
    end
    if allowDamageOutsideActiveMatch() then
        return true
    end
    return player:GetAttribute("InMatch") == true
end

local function isCharacterSandevistanFrozen(character)
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

local function canAttack(attacker)
    if not attacker then return false end
    local recoverUntil = CombatService._m1RecoverUntil[attacker.UserId]
    if type(recoverUntil) == "number" and tick() < recoverUntil then
        return false
    end
    if attacker:GetAttribute(FLASH_STEP_ACTIVE_ATTRIBUTE) == true then
        return false
    end
    local character = attacker.Character
    if character and isCharacterSandevistanFrozen(character) then
        return false
    end
    if character and isCharacterStunned(character) then
        return false
    end
    if character and character:GetAttribute(BLOCKING_STATE_ATTRIBUTE) == true then
        return false
    end
    return canUseCombatInput(attacker)
end

local function getHorizontalDashDirection(v)
    if typeof(v) ~= "Vector3" then
        return nil
    end
    local flat = Vector3.new(v.X, 0, v.Z)
    local mag = flat.Magnitude
    if mag <= DASH_MIN_INPUT_MAGNITUDE then
        return nil
    end
    return flat / mag
end

local function canDash(player)
    if not player then
        return false
    end
    if player:GetAttribute(FLASH_STEP_ACTIVE_ATTRIBUTE) == true then
        return false
    end
    local character = player.Character
    if not character then
        return false
    end
    if isCharacterSandevistanFrozen(character) then
        return false
    end
    if isCharacterStunned(character) then
        return false
    end
    if isGuardBroken(character) then
        return false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false
    end
    return canUseCombatInput(player)
end

local function performDash(player, payload)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = getRootPart(character)
    if not character or not humanoid or humanoid.Health <= 0 or not root then
        return false
    end

    if character:GetAttribute(BLOCKING_STATE_ATTRIBUTE) == true then
        character:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
        syncCharacterBlockLoopAnimation(character, false)
        setBlockMovementSlow(humanoid, false)
    end

    local moveDirection = nil
    if type(payload) == "table" then
        moveDirection = getHorizontalDashDirection(payload.move)
    end

    local dashDirection = moveDirection or getHorizontalDashDirection(-root.CFrame.LookVector)
    if not dashDirection then
        dashDirection = Vector3.new(0, 0, 1)
    end

    local origin = root.Position
    local rayDirection = dashDirection * DASH_DISTANCE
    local desired = origin + rayDirection

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { character }
    rayParams.IgnoreWater = true

    local result = Workspace:Raycast(origin, rayDirection, rayParams)
    if result and result.Position then
        desired = result.Position - (dashDirection * DASH_BACKOFF)
    end

    desired = Vector3.new(desired.X, origin.Y, desired.Z)
    local dashDelta = desired - origin
    local dashDistance = dashDelta.Magnitude
    if dashDistance <= 0.05 then
        return false
    end

    local travelDirection = dashDelta.Unit
    local lookDirection = getHorizontalDashDirection(root.CFrame.LookVector) or travelDirection
    root.CFrame = CFrame.new(root.Position, root.Position + lookDirection)

    local dashDuration = math.clamp(dashDistance / DASH_GLIDE_SPEED, DASH_GLIDE_MIN_DURATION, DASH_GLIDE_MAX_DURATION)
    local dashSpeed = dashDistance / dashDuration

    local token = (dashMoveTokenByCharacter[character] or 0) + 1
    dashMoveTokenByCharacter[character] = token

    local mover = Instance.new("BodyVelocity")
    mover.Name = "AFS_DashVelocity"
    mover.MaxForce = Vector3.new(1e9, 0, 1e9)
    mover.P = 60000
    mover.Velocity = travelDirection * dashSpeed
    mover.Parent = root
    Debris:AddItem(mover, dashDuration + 0.08)

    playDashAnimation(humanoid)
    playOneShotSoundAtRoot(root, DASH_SOUND_ID, DASH_SOUND_VOLUME, M1_SOUND_MAX_DISTANCE)

    task.delay(dashDuration, function()
        if dashMoveTokenByCharacter[character] ~= token then
            return
        end
        if not root or not root.Parent then
            return
        end
        local v = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
    end)

    return true
end

local function setPlayerBlocking(player, shouldBlock)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not humanoid or humanoid.Health <= 0 then
        return
    end

    local function clearBlocking()
        character:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
        syncCharacterBlockLoopAnimation(character, false)
        setBlockMovementSlow(humanoid, false)
    end

    getCharacterBlockPosture(character)

    if shouldBlock ~= true then
        clearBlocking()
        return
    end

    if isCharacterStunned(character) then
        clearBlocking()
        return
    end

    if not canUseCombatInput(player) then
        clearBlocking()
        return
    end
    if player:GetAttribute(FLASH_STEP_ACTIVE_ATTRIBUTE) == true then
        clearBlocking()
        return
    end
    if character:GetAttribute(BLOCK_DEFENSE_DISABLED_ATTRIBUTE) == true then
        clearBlocking()
        return
    end
    if isGuardBroken(character) then
        clearBlocking()
        return
    end
    local posture = getCharacterBlockPosture(character)
    if posture <= 0 then
        clearBlocking()
        return
    end
    character:SetAttribute(BLOCKING_STATE_ATTRIBUTE, true)
    syncCharacterBlockLoopAnimation(character, true)
    setBlockMovementSlow(humanoid, true)
end

local function tryConsumeBlockPostureDamage(attacker, victimCharacter, victimPlayer, damage, source)
    if not attacker or not victimCharacter then
        return false
    end
    if victimCharacter:GetAttribute(BLOCKING_STATE_ATTRIBUTE) ~= true then
        return false
    end
    if victimCharacter:GetAttribute(BLOCK_DEFENSE_DISABLED_ATTRIBUTE) == true then
        victimCharacter:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
        syncCharacterBlockLoopAnimation(victimCharacter, false)
        return false
    end
    if isGuardBroken(victimCharacter) then
        victimCharacter:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
        syncCharacterBlockLoopAnimation(victimCharacter, false)
        return false
    end
    if victimPlayer and not canUseCombatInput(victimPlayer) then
        victimCharacter:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
        syncCharacterBlockLoopAnimation(victimCharacter, false)
        return false
    end

    local posture, maxPosture = getCharacterBlockPosture(victimCharacter)
    if posture <= 0 then
        victimCharacter:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
        syncCharacterBlockLoopAnimation(victimCharacter, false)
        return false
    end

    local nextPosture = math.max(0, posture - math.max(0, math.floor(damage or 0)))
    victimCharacter:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, nextPosture)
    playBlockHitEffects(victimCharacter)
    local victimLabel = (victimPlayer and victimPlayer.Name) or (victimCharacter.Name ~= "" and victimCharacter.Name or "DummyRig")
    debugDamage(attacker, victimLabel, damage, getDamageMultiplier(attacker), (source or "melee") .. ":blocked")

    if nextPosture <= 0 then
        triggerGuardBreak(victimCharacter, maxPosture)
    end
    return true
end

local function canDamageTarget(attacker, target)
    if not attacker or not target or attacker == target then return false end

    if CombatService._active then
        if not isParticipant(target) then return false end
        local ta = CombatService._team[attacker.UserId]
        local tb = CombatService._team[target.UserId]
        if ta and tb and ta == tb then
            return false
        end
        return true
    end

    if allowDamageOutsideActiveMatch() then
        return true
    end

    if attacker:GetAttribute("InMatch") ~= true then return false end
    if target:GetAttribute("InMatch") ~= true then return false end
    return true
end

local function applyDamageAndRecord(attacker, victimPlayer, victimHumanoid, damage, now, source)
    if not attacker or not victimPlayer or not victimHumanoid then return end
    damage = math.floor(damage or 0)
    if damage <= 0 then return end
    if victimHumanoid.Health <= 0 then return end

    if isDeferredDamageActive(victimHumanoid) then
        queueDeferredDamage(attacker, victimHumanoid, damage, source, victimPlayer.Name)
        return
    end

    local victimCharacter = victimPlayer.Character
    if victimCharacter then
        for _, child in ipairs(victimCharacter:GetChildren()) do
            if child:IsA("ForceField") then
                child:Destroy()
            end
        end
    end

    victimHumanoid:TakeDamage(damage)
    applyLifesteal(attacker, damage)
    debugDamage(attacker, victimPlayer.Name, damage, getDamageMultiplier(attacker), source)

    CombatService._lastDamagers[victimPlayer.UserId] = CombatService._lastDamagers[victimPlayer.UserId] or {}
    CombatService._lastDamagers[victimPlayer.UserId][attacker.UserId] = now or tick()
    fireDamagePopup(attacker, victimPlayer, damage)
end

local function getMeleeHitbox(attackerRoot)
    local forward = attackerRoot.CFrame.LookVector
    local center = attackerRoot.Position + (forward * MELEE_FORWARD_OFFSET)
    local cframe = CFrame.lookAt(center, center + forward)
    return cframe, MELEE_HITBOX_SIZE
end

local function resolveMeleeTarget(attacker, preferredTarget)
    if not attacker or not attacker.Character then return nil end
    local attackerRoot = getRootPart(attacker.Character)
    if not attackerRoot then return nil end

    local hitboxCFrame, hitboxSize = getMeleeHitbox(attackerRoot)
    drawMeleeHitbox(hitboxCFrame, hitboxSize)

    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances = { attacker.Character }

    local autoHit = attacker:GetAttribute("AutoHit") == true
    local forward = attackerRoot.CFrame.LookVector
    local seen = {}
    local best = nil
    local preferred = nil

    local parts = Workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlap)
    local function tryCandidate(target, model)
        if not model then
            return
        end

        local targetRoot = getRootPart(model)
        local targetHumanoid = model:FindFirstChildOfClass("Humanoid")
        if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
            return
        end

        if target then
            if seen[target] or not canDamageTarget(attacker, target) then
                return
            end
            seen[target] = true
        else
            if not canDamageDummyRigs() then
                return
            end
            if model == attacker.Character then
                return
            end
            if Players:GetPlayerFromCharacter(model) then
                return
            end
            if seen[model] then
                return
            end
            seen[model] = true
        end

        local dir = targetRoot.Position - attackerRoot.Position
        local dist = dir.Magnitude
        if dist > 0.05 then
            local dot = forward:Dot(dir.Unit)
            if autoHit or dot >= MELEE_DOT_MIN then
                local candidate = {
                    player = target,
                    humanoid = targetHumanoid,
                    score = (dot * 100) - dist,
                }
                if preferredTarget and target and target == preferredTarget then
                    preferred = candidate
                end
                if not best or candidate.score > best.score then
                    best = candidate
                end
            end
        end
    end

    for _, part in ipairs(parts) do
        local model = part and part:FindFirstAncestorOfClass("Model")
        local target = model and Players:GetPlayerFromCharacter(model)
        if model then
            tryCandidate(target, model)
        end
    end

    -- Fallback for cases where target parts are non-queryable.
    if not preferred and not best then
        for _, target in ipairs(Players:GetPlayers()) do
            if target ~= attacker and target.Character then
                local targetRoot = getRootPart(target.Character)
                if targetRoot then
                    local localPos = hitboxCFrame:PointToObjectSpace(targetRoot.Position)
                    local half = hitboxSize * 0.5
                    local inside =
                        math.abs(localPos.X) <= half.X and
                        math.abs(localPos.Y) <= half.Y and
                        math.abs(localPos.Z) <= half.Z
                    if inside then
                        tryCandidate(target, target.Character)
                    end
                end
            end
        end
    end

    -- Test-mode fallback for non-player humanoid rigs.
    if canDamageDummyRigs() and not preferred and not best then
        local half = hitboxSize * 0.5
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("Model") and inst ~= attacker.Character and not Players:GetPlayerFromCharacter(inst) then
                local targetHumanoid = inst:FindFirstChildOfClass("Humanoid")
                local targetRoot = getRootPart(inst)
                if targetHumanoid and targetHumanoid.Health > 0 and targetRoot then
                    local localPos = hitboxCFrame:PointToObjectSpace(targetRoot.Position)
                    local inside =
                        math.abs(localPos.X) <= half.X and
                        math.abs(localPos.Y) <= half.Y and
                        math.abs(localPos.Z) <= half.Z
                    if inside then
                        tryCandidate(nil, inst)
                    end
                end
            end
        end
    end

    if preferredTarget and not preferred and preferredTarget.Character and canDamageTarget(attacker, preferredTarget) then
        local targetRoot = getRootPart(preferredTarget.Character)
        local targetHumanoid = preferredTarget.Character:FindFirstChildOfClass("Humanoid")
        if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
            local delta = targetRoot.Position - attackerRoot.Position
            local horizontal = Vector3.new(delta.X, 0, delta.Z)
            local distance = horizontal.Magnitude
            local vertical = math.abs(delta.Y)
            if distance <= MELEE_PREFERRED_MAX_DISTANCE and vertical <= MELEE_VERTICAL_TOLERANCE then
                local dot = 1
                if distance > 0.05 then
                    dot = forward:Dot(horizontal.Unit)
                end
                if autoHit or dot >= (MELEE_DOT_MIN - 0.15) then
                    preferred = {
                        player = preferredTarget,
                        humanoid = targetHumanoid,
                        score = (dot * 100) - distance,
                    }
                end
            end
        end
    end

    return preferred or best
end

local function clearDiedConnections()
    for _, conn in ipairs(CombatService._connections) do
        if conn and conn.Disconnect then
            conn:Disconnect()
        end
    end
    CombatService._connections = {}
end

function CombatService:SetActiveMatch(playersArray)
    -- playersArray: ordered array {spirit, challenger, ally?}
    CombatService:ClearActiveMatch()
    CombatService._active = true
    CombatService._participants = playersArray
    for i, p in ipairs(playersArray) do
        CombatService._players[p.UserId] = p
        if i == 1 or i == 3 then
            CombatService._team[p.UserId] = "spirit"
        else
            CombatService._team[p.UserId] = "challenger"
        end
        if p.Character then
            resetCharacterBlockState(p.Character, true)
        end
        -- hook Died for each participant
        if p.Character then
            local humanoid = p.Character:FindFirstChild("Humanoid")
            if humanoid then
                local conn = humanoid.Died:Connect(function()
                    -- determine killers using lastDamagers
                    local victim = p
                    local killers = CombatService:GetKillers(victim)
                    -- fire server-side event
                    PlayerDiedEvent:Fire(victim, killers)
                end)
                table.insert(CombatService._connections, conn)
            end
        end
    end
end

function CombatService:ClearActiveMatch()
    CombatService._active = false
    CombatService._players = {}
    CombatService._participants = {}
    CombatService._team = {}
    CombatService._lastAttack = {}
    CombatService._lastDash = {}
    CombatService._m1RecoverUntil = {}
    CombatService._lastDamagers = {}
    CombatService._deferredDamageByHumanoid = setmetatable({}, { __mode = "k" })
    for userId, _ in pairs(activeAttackTracks) do
        clearAttackTrackState(userId, 0)
    end
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player and player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if character then
            resetCharacterBlockState(character, true)
        end
        if humanoid then
            clearDeferredDamageAttributes(humanoid)
        end
    end
    clearDiedConnections()
end

function CombatService:GetKillers(victimPlayer)
    local res = {}
    local now = tick()
    local victimId = victimPlayer.UserId
    local t = CombatService._lastDamagers[victimId]
    if not t then return res end
    for attackerId, atime in pairs(t) do
        if now - atime <= CombatService.KILL_WINDOW then
            local p = Players:GetPlayerByUserId(attackerId)
            if p then table.insert(res, p) end
        end
    end
    return res
end

function CombatService:GetTeam(player)
    if not player then return nil end
    return CombatService._team[player.UserId]
end

function CombatService:IsEnemy(a, b)
    if not a or not b then return false end
    local ta = CombatService._team[a.UserId]
    local tb = CombatService._team[b.UserId]
    if not ta or not tb then return false end
    return ta ~= tb
end

function CombatService:BeginSandevistanDeferredDamage(victimHumanoid, effectId)
    if not victimHumanoid or typeof(victimHumanoid) ~= "Instance" or not victimHumanoid:IsA("Humanoid") then
        return
    end
    if type(effectId) ~= "string" or effectId == "" then
        return
    end

    local state = getDeferredDamageState(victimHumanoid, true)
    if not state then
        return
    end
    state.effects[effectId] = true

    local activeCount = victimHumanoid:GetAttribute(SANDEVISTAN_DEFER_COUNT_ATTR)
    local nextCount = (type(activeCount) == "number" and activeCount or 0) + 1
    if nextCount == 1 then
        clearDeferredDamageAttributes(victimHumanoid)
    end
    victimHumanoid:SetAttribute(SANDEVISTAN_DEFER_COUNT_ATTR, nextCount)
end

function CombatService:EndSandevistanDeferredDamage(victimHumanoid, effectId)
    if not victimHumanoid or typeof(victimHumanoid) ~= "Instance" or not victimHumanoid:IsA("Humanoid") then
        return
    end

    local state = getDeferredDamageState(victimHumanoid, false)
    if state then
        if type(effectId) == "string" and effectId ~= "" then
            state.effects[effectId] = nil
        else
            state.effects = {}
        end
    end

    local activeCount = victimHumanoid:GetAttribute(SANDEVISTAN_DEFER_COUNT_ATTR)
    local nextCount = (type(activeCount) == "number" and activeCount or 0) - 1
    if nextCount > 0 then
        victimHumanoid:SetAttribute(SANDEVISTAN_DEFER_COUNT_ATTR, nextCount)
        return
    end
    victimHumanoid:SetAttribute(SANDEVISTAN_DEFER_COUNT_ATTR, nil)

    if state and hasActiveDeferredEffects(state) then
        return
    end

    releaseDeferredGuardBreak(victimHumanoid, state)
    flushDeferredDamage(victimHumanoid, state)
end

function CombatService:ApplyAbilityDamage(attacker, victimHumanoid, amount, abilityId)
    if not attacker or not victimHumanoid then return end
    if typeof(victimHumanoid) ~= "Instance" or not victimHumanoid:IsA("Humanoid") then return end
    -- apply damage
    local now = tick()
    local mult = getDamageMultiplier(attacker)
    local dmg = math.max(0, math.floor(amount * mult))
    local isTimeSkip = abilityId == "time_skip"
    local sourceTag = "ability:" .. tostring(abilityId or "unknown")
    local sourceDummyTag = "ability-dummy:" .. tostring(abilityId or "unknown")

    -- find victim player by character
    local char = victimHumanoid.Parent
    if char and char:IsA("Model") then
        local victimPlayer = Players:GetPlayerFromCharacter(char)
        if victimPlayer then
            if isTimeSkip and char:GetAttribute(BLOCKING_STATE_ATTRIBUTE) == true then
                local _, maxPosture = getCharacterBlockPosture(char)
                triggerGuardBreak(char, maxPosture)
            elseif tryConsumeBlockPostureDamage(attacker, char, victimPlayer, dmg, sourceTag) then
                return
            end

            applyDamageAndRecord(attacker, victimPlayer, victimHumanoid, dmg, now, sourceTag)
        elseif canDamageDummyRigs() then
            if isTimeSkip and char:GetAttribute(BLOCKING_STATE_ATTRIBUTE) == true then
                local _, maxPosture = getCharacterBlockPosture(char)
                triggerGuardBreak(char, maxPosture)
            elseif tryConsumeBlockPostureDamage(attacker, char, nil, dmg, sourceDummyTag) then
                return
            end

            for _, child in ipairs(char:GetChildren()) do
                if child:IsA("ForceField") then
                    child:Destroy()
                end
            end
            if dmg > 0 and victimHumanoid.Health > 0 then
                local victimLabel = char.Name ~= "" and char.Name or "DummyRig"
                if isDeferredDamageActive(victimHumanoid) then
                    queueDeferredDamage(attacker, victimHumanoid, dmg, sourceDummyTag, victimLabel)
                else
                    victimHumanoid:TakeDamage(dmg)
                    applyLifesteal(attacker, dmg)
                    debugDamage(attacker, victimLabel, dmg, mult, sourceDummyTag)
                end
            end
        end
    end
end

local function bindPlayerBlockState(player)
    if not player then
        return
    end

    local function onCharacterAdded(character)
        resetCharacterBlockState(character, true)
        character:GetAttributeChangedSignal(BLOCKING_STATE_ATTRIBUTE):Connect(function()
            if not character or not character.Parent then
                return
            end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local isBlockingNow = character:GetAttribute(BLOCKING_STATE_ATTRIBUTE) == true
            if isCharacterStunned(character) then
                syncCharacterBlockLoopAnimation(character, false)
                setBlockMovementSlow(humanoid, false)
                return
            end
            syncCharacterBlockLoopAnimation(character, isBlockingNow)
            setBlockMovementSlow(humanoid, isBlockingNow)
        end)
        character:GetAttributeChangedSignal(STUNNED_UNTIL_ATTRIBUTE):Connect(function()
            if not character or not character.Parent then
                return
            end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if isCharacterStunned(character) then
                syncCharacterBlockLoopAnimation(character, false)
                setBlockMovementSlow(humanoid, false)
            else
                local isBlockingNow = character:GetAttribute(BLOCKING_STATE_ATTRIBUTE) == true
                syncCharacterBlockLoopAnimation(character, isBlockingNow)
                setBlockMovementSlow(humanoid, isBlockingNow)
            end
        end)
    end

    player.CharacterAdded:Connect(onCharacterAdded)
    player.CharacterRemoving:Connect(function(character)
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            character:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
            setBlockMovementSlow(humanoid, false)
            clearCharacterStun(character)
        end
    end)

    if player.Character then
        onCharacterAdded(player.Character)
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    bindPlayerBlockState(player)
end

Players.PlayerAdded:Connect(function(player)
    bindPlayerBlockState(player)
end)

Players.PlayerRemoving:Connect(function(player)
    local userId = player.UserId
    if userId then
        clearAttackTrackState(userId, 0)
        attackPlayToken[userId] = nil
        CombatService._m1RecoverUntil[userId] = nil
    end
    CombatService._lastAttack[player.UserId] = nil
    CombatService._lastDash[player.UserId] = nil
end)

local function updateBlockPostureRegeneration()
    -- Regenerate for all players
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if not character then
            continue
        end
        
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            continue
        end
        
        -- Don't regenerate if blocking or guard is broken
        if character:GetAttribute(BLOCKING_STATE_ATTRIBUTE) == true then
            continue
        end
        
        if isGuardBroken(character) then
            continue
        end
        
        local posture, maxPosture = getCharacterBlockPosture(character)
        if posture >= maxPosture then
            continue -- Already at max
        end
        
        -- Passively regenerate posture
        local regenAmount = BLOCK_POSTURE_REGEN_RATE * BLOCK_POSTURE_REGEN_TICK_INTERVAL
        local newPosture = math.min(posture + regenAmount, maxPosture)
        character:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, math.floor(newPosture))
    end
    
    -- Also regenerate for test rigs and dummy characters in Workspace
    for _, model in ipairs(Workspace:GetChildren()) do
        if not model:IsA("Model") or not model:FindFirstChildOfClass("Humanoid") then
            continue
        end
        
        -- Skip if it's a player character (already handled above)
        if Players:GetPlayerFromCharacter(model) then
            continue
        end
        
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            continue
        end
        
        -- Don't regenerate if blocking or guard is broken
        if model:GetAttribute(BLOCKING_STATE_ATTRIBUTE) == true then
            continue
        end
        
        if isGuardBroken(model) then
            continue
        end
        
        local posture, maxPosture = getCharacterBlockPosture(model)
        if posture >= maxPosture then
            continue -- Already at max
        end
        
        -- Passively regenerate posture
        local regenAmount = BLOCK_POSTURE_REGEN_RATE * BLOCK_POSTURE_REGEN_TICK_INTERVAL
        local newPosture = math.min(posture + regenAmount, maxPosture)
        model:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, math.floor(newPosture))
    end
end

RunService.Heartbeat:Connect(function()
    -- Update block posture regeneration every tick interval
    local now = tick()
    if not CombatService._lastRegenTick then
        CombatService._lastRegenTick = now
    end
    
    if now - CombatService._lastRegenTick >= BLOCK_POSTURE_REGEN_TICK_INTERVAL then
        updateBlockPostureRegeneration()
        CombatService._lastRegenTick = now
    end
end)

REQ_BLOCK.OnServerEvent:Connect(function(player, isBlocking)
    if type(isBlocking) ~= "boolean" then
        return
    end
    setPlayerBlocking(player, isBlocking)
end)

REQ_DASH.OnServerEvent:Connect(function(player, payload)
    if not canDash(player) then
        return
    end
    if payload ~= nil and type(payload) ~= "table" then
        return
    end

    local now = tick()
    local lastDash = CombatService._lastDash[player.UserId]
    if lastDash and (now - lastDash) < DASH_COOLDOWN then
        return
    end

    if performDash(player, payload) then
        CombatService._lastDash[player.UserId] = now
    end
end)

local function resolveAndApplyMeleeAttack(attacker, preferredTarget, weaponId, isSwordM1, isFistM1)
    if not attacker or not attacker.Character then return end
    local attackerHumanoid = attacker.Character:FindFirstChildOfClass("Humanoid")
    if not attackerHumanoid or attackerHumanoid.Health <= 0 then return end

    local attackerRoot = getRootPart(attacker.Character)
    if isSwordM1 then
        playOneShotSoundAtRoot(attackerRoot, getSwordSwingSoundId(weaponId), 1, M1_SOUND_MAX_DISTANCE)
    elseif isFistM1 then
        playOneShotSoundAtRoot(attackerRoot, FIST_M1_SWING_SOUND_ID, 1, M1_SOUND_MAX_DISTANCE)
    end

    local hit = resolveMeleeTarget(attacker, preferredTarget)
    if not hit then
        if isFistM1 then
            playOneShotSoundAtRoot(attackerRoot, FIST_M1_MISS_SOUND_ID, 1, M1_SOUND_MAX_DISTANCE)
        end
        return
    end

    if isSwordM1 or isFistM1 then
        local hitRoot = nil
        if hit.player and hit.player.Character then
            hitRoot = getRootPart(hit.player.Character)
        elseif hit.humanoid and hit.humanoid.Parent then
            hitRoot = getRootPart(hit.humanoid.Parent)
        end
        playOneShotSoundAtRoot(hitRoot or attackerRoot, M1_HIT_SOUND_ID, 1, M1_SOUND_MAX_DISTANCE)
    end

    local baseDmg = getWeaponBaseDamage(attacker)
    local mult = getDamageMultiplier(attacker)
    local dmg = math.floor(baseDmg * mult)
    local now = tick()
    if hit.player then
        local victimCharacter = hit.player.Character
        if victimCharacter and tryConsumeBlockPostureDamage(attacker, victimCharacter, hit.player, dmg, "melee") then
            return
        end
        applyDamageAndRecord(attacker, hit.player, hit.humanoid, dmg, now, "melee")
    elseif hit.humanoid and canDamageDummyRigs() then
        local victimCharacter = hit.humanoid.Parent
        if victimCharacter then
            for _, child in ipairs(victimCharacter:GetChildren()) do
                if child:IsA("ForceField") then
                    child:Destroy()
                end
            end
        end
        if dmg > 0 and hit.humanoid.Health > 0 then
            local victimLabel = (victimCharacter and victimCharacter.Name) or "DummyRig"
            if victimCharacter and tryConsumeBlockPostureDamage(attacker, victimCharacter, nil, dmg, "melee-dummy") then
                return
            end
            if isDeferredDamageActive(hit.humanoid) then
                queueDeferredDamage(attacker, hit.humanoid, dmg, "melee-dummy", victimLabel)
            else
                hit.humanoid:TakeDamage(dmg)
                applyLifesteal(attacker, dmg)
                debugDamage(attacker, victimLabel, dmg, mult, "melee-dummy")
            end
        end
    end
end

-- Validate attack
REQ_ATTACK.OnServerEvent:Connect(function(player, targetUserId, attackIndex, clientTime)
    -- basic checks
    if not canAttack(player) then return end

    if not player.Character then return end
    local hp = player.Character:FindFirstChild("Humanoid")
    if not hp or hp.Health <= 0 then return end
    local weaponId = getEquippedWeaponId(player)
    local isSwordM1 = isSwordWeaponId(weaponId)
    local isFistM1 = isFistsWeaponId(weaponId)
    local hasMarkerTimedSword = isSwordM1 and MARKER_TIMED_SWORD_WEAPON_IDS[weaponId] == true

    -- rate limit (single attack pattern)
    local now = tick()
    local last = CombatService._lastAttack[player.UserId]
    local lastCooldown = (last and last.cooldown) or DEFAULT_ATTACK_COOLDOWN
    if last and now - (last.time or 0) < lastCooldown then
        return -- too fast
    end

    -- Play attack animation (server-authoritative, replicates to all)
    local attackCooldown, attackTrack = playAttackAnimation(player)
    local attackToken = attackPlayToken[player.UserId]
    CombatService._lastAttack[player.UserId] = {
        time = now,
        cooldown = math.max(MIN_ATTACK_COOLDOWN, attackCooldown or DEFAULT_ATTACK_COOLDOWN),
    }

    local preferredTarget = nil
    if type(targetUserId) == "number" and targetUserId > 0 then
        preferredTarget = Players:GetPlayerByUserId(targetUserId)
    end

    local useHitMarkerTiming = attackTrack and (isFistM1 or hasMarkerTimedSword)
    local resolved = false
    local markerConnections = {}
    local function disconnectMarkerConnections()
        for _, conn in ipairs(markerConnections) do
            if conn and conn.Disconnect then
                conn:Disconnect()
            end
        end
        table.clear(markerConnections)
    end
    local function resolveHitOnce()
        if resolved then
            return
        end
        if useHitMarkerTiming and attackPlayToken[player.UserId] ~= attackToken then
            resolved = true
            disconnectMarkerConnections()
            return
        end
        if not canAttack(player) then
            resolved = true
            disconnectMarkerConnections()
            return
        end
        resolved = true
        disconnectMarkerConnections()
        CombatService._m1RecoverUntil[player.UserId] = tick() + M1_POST_HIT_RECOVERY
        resolveAndApplyMeleeAttack(player, preferredTarget, weaponId, isSwordM1, isFistM1)
    end

    if useHitMarkerTiming then
        -- Marker-timed damage/sfx so contact matches the animation frame.
        table.insert(markerConnections, attackTrack:GetMarkerReachedSignal(M1_HIT_MARKER):Connect(function()
            resolveHitOnce()
        end))
        if M1_HIT_MARKER_ALT ~= M1_HIT_MARKER then
            table.insert(markerConnections, attackTrack:GetMarkerReachedSignal(M1_HIT_MARKER_ALT):Connect(function()
                resolveHitOnce()
            end))
        end

        local cooldownWindow = attackCooldown or DEFAULT_ATTACK_COOLDOWN
        local fallbackDelay = math.clamp(cooldownWindow * 0.7, MIN_ATTACK_COOLDOWN, M1_HIT_MARKER_FALLBACK_DELAY)
        task.delay(fallbackDelay, function()
            resolveHitOnce()
        end)
    else
        resolveHitOnce()
    end
end)

return CombatService
