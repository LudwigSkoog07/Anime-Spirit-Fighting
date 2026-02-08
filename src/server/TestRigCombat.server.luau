-- Test rig combat driver:
-- - Punch rig repeatedly performs forward fist M1 (facing direction only).
-- - Block rig keeps blocking with posture and a looped block animation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

if not RunService:IsStudio() then
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
if not Shared then
	warn("[TestRigCombat] Shared modules missing.")
	return
end

local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

local ROLE_ATTRIBUTE = "AFS_AutoCombatRole" -- "puncher" | "blocker"
local BLOCK_ANIMATION_ATTRIBUTE = "AFS_BlockAnimationId"
local PUNCH_RIG_NAMES = {
	"AFS_PunchRig",
	"AFS_AutoCombatRole = puncher",
	"AFS_AutoCombatRole=puncher",
}
local BLOCK_RIG_NAMES = {
	"AFS_BlockRig",
	"AFS_AutoCombatRole = blocker",
	"AFS_AutoCombatRole=blocker",
}

local BLOCKING_STATE_ATTRIBUTE = "AFS_IsBlocking"
local BLOCK_POSTURE_ATTRIBUTE = "AFS_BlockPosture"
local BLOCK_POSTURE_MAX_ATTRIBUTE = "AFS_BlockPostureMax"
local GUARD_BROKEN_UNTIL_ATTRIBUTE = "AFS_GuardBrokenUntil"
local STUNNED_UNTIL_ATTRIBUTE = "AFS_StunnedUntil"
local BLOCK_DEFENSE_DISABLED_ATTRIBUTE = "DefenseDisabled"
local STUN_BASE_WALKSPEED_ATTRIBUTE = "AFS_StunBaseWalkSpeed"
local STUN_BASE_JUMPPOWER_ATTRIBUTE = "AFS_StunBaseJumpPower"

local GUARD_BREAK_DURATION = 1.2
local BLOCK_BREAK_STUN_DURATION = 2.0
local DEFAULT_ATTACK_INTERVAL = 0.3
local MIN_ATTACK_INTERVAL = 0.05
local MELEE_HITBOX_SIZE = Vector3.new(6, 5, 8)
local MELEE_FORWARD_OFFSET = 4
local MELEE_DOT_MIN = 0.2
local MELEE_MAX_DISTANCE = 12
local DEFAULT_POSTURE_MAX = 50
local HITBOX_DEBUG_LIFETIME = 0.15
local HITBOX_DEBUG_COLOR = Color3.fromRGB(255, 130, 60)

local ANIMATION_ID_PREFIX = "rbxassetid://"
local SOUND_ID_PREFIX = "rbxassetid://"
local SOUND_MAX_DISTANCE = 120

local DEFAULT_BLOCK_LOOP_ANIMATION_ID = "124944234769911"
local BLOCK_BREAK_ANIMATION_ID = "102128029055200"
local BLOCK_HIT_SOUND_ID = "80809123525734"
local BLOCK_BREAK_SOUND_ID = "113917217579668"

local fistsStats = ItemConfig.GetWeaponStats("fists")
local FIST_DAMAGE = math.max(1, math.floor((fistsStats and fistsStats.baseDamage) or 5))
local FIST_ATTACK_ANIMATION_ID = tostring((fistsStats and fistsStats.attackAnimationId) or "112489316768198")
local FIST_ATTACK_ANIMATION_SPEED = 1

local animationById: { [string]: Animation } = {}
local fistTrackByHumanoid = setmetatable({}, { __mode = "k" })
local blockLoopTrackStateByHumanoid = setmetatable({}, { __mode = "k" })
local blockBreakTrackByHumanoid = setmetatable({}, { __mode = "k" })

local function getRoot(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart
		or model.PrimaryPart
		or model:FindFirstChild("UpperTorso") :: BasePart
		or model:FindFirstChild("Torso") :: BasePart
end

local function getHumanoid(model: Model): Humanoid?
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

local function isRigModel(model: Model?): boolean
	if not model or not model:IsA("Model") then
		return false
	end
	if Players:GetPlayerFromCharacter(model) then
		return false
	end
	return model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function normalizeAnimationId(animIdRaw: any): string?
	if animIdRaw == nil then
		return nil
	end
	local animId = tostring(animIdRaw)
	if animId == "" then
		return nil
	end
	if animId:sub(1, #ANIMATION_ID_PREFIX) ~= ANIMATION_ID_PREFIX then
		animId = ANIMATION_ID_PREFIX .. animId
	end
	return animId
end

local function normalizeSoundId(soundIdRaw: any): string?
	if soundIdRaw == nil then
		return nil
	end
	local soundId = tostring(soundIdRaw)
	if soundId == "" then
		return nil
	end
	if soundId:sub(1, #SOUND_ID_PREFIX) ~= SOUND_ID_PREFIX then
		soundId = SOUND_ID_PREFIX .. soundId
	end
	return soundId
end

local function getAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function isTrackUsable(track: AnimationTrack?): boolean
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

local function stopAndDestroyTrack(track: AnimationTrack?, fadeTime: number?)
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

local function getOrCreateAnimation(animationId: string): Animation
	local anim = animationById[animationId]
	if anim then
		return anim
	end
	anim = Instance.new("Animation")
	anim.AnimationId = animationId
	animationById[animationId] = anim
	return anim
end

local function playOneShotSoundAtRoot(rootPart: BasePart?, soundIdRaw: any)
	local soundId = normalizeSoundId(soundIdRaw)
	if not rootPart or not soundId then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "AFS_RigCombatSfx"
	sound.SoundId = soundId
	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = SOUND_MAX_DISTANCE
	sound.Parent = rootPart
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function drawMeleeHitbox(cframe: CFrame, size: Vector3)
	local part = Instance.new("Part")
	part.Name = "AFS_RigMeleeHitbox"
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 0.72
	part.Material = Enum.Material.ForceField
	part.Color = HITBOX_DEBUG_COLOR
	part.Parent = Workspace
	Debris:AddItem(part, HITBOX_DEBUG_LIFETIME)
end

local function getFistTrack(humanoid: Humanoid): AnimationTrack?
	local cached = fistTrackByHumanoid[humanoid]
	if isTrackUsable(cached) then
		return cached
	end

	local animator = getAnimator(humanoid)
	local attackAnimId = normalizeAnimationId(FIST_ATTACK_ANIMATION_ID)
	if not attackAnimId then
		return nil
	end
	local attackAnim = getOrCreateAnimation(attackAnimId)
	local ok, track = pcall(function()
		return animator:LoadAnimation(attackAnim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		fistTrackByHumanoid[humanoid] = track
		return track
	end
	return nil
end

local function getBlockLoopTrack(humanoid: Humanoid, animationId: string): AnimationTrack?
	local state = blockLoopTrackStateByHumanoid[humanoid]
	if state and state.animationId == animationId and isTrackUsable(state.track) then
		return state.track
	end
	if state and state.track then
		stopAndDestroyTrack(state.track, 0.05)
	end
	blockLoopTrackStateByHumanoid[humanoid] = nil

	local animator = getAnimator(humanoid)
	local anim = getOrCreateAnimation(animationId)
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

local function syncBlockLoopAnimation(rig: Model, humanoid: Humanoid, enabled: boolean)
	local desired = normalizeAnimationId(rig:GetAttribute(BLOCK_ANIMATION_ATTRIBUTE))
		or normalizeAnimationId(DEFAULT_BLOCK_LOOP_ANIMATION_ID)
	local state = blockLoopTrackStateByHumanoid[humanoid]

	if not enabled or not desired then
		if state and state.track and state.track.IsPlaying then
			state.track:Stop(0.1)
		end
		return
	end

	if state and state.animationId ~= desired and state.track and state.track.IsPlaying then
		state.track:Stop(0.1)
	end

	local track = getBlockLoopTrack(humanoid, desired)
	if track and not track.IsPlaying then
		track:Play(0.1, 1, 1)
	end
end

local function getBlockBreakTrack(humanoid: Humanoid): AnimationTrack?
	local cached = blockBreakTrackByHumanoid[humanoid]
	if isTrackUsable(cached) then
		return cached
	end

	local animId = normalizeAnimationId(BLOCK_BREAK_ANIMATION_ID)
	if not animId then
		return nil
	end
	local anim = getOrCreateAnimation(animId)
	local animator = getAnimator(humanoid)
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

local function playBlockBreakEffects(targetModel: Model, targetHumanoid: Humanoid?)
	local root = getRoot(targetModel)
	playOneShotSoundAtRoot(root, BLOCK_BREAK_SOUND_ID)

	local humanoid = targetHumanoid or getHumanoid(targetModel)
	if not humanoid then
		return
	end

	local track = getBlockBreakTrack(humanoid)
	if track then
		if track.IsPlaying then
			track:Stop(0.05)
		end
		track:Play(0.05, 1, 1)
	end
end

local function playBlockHitSound(targetModel: Model)
	playOneShotSoundAtRoot(getRoot(targetModel), BLOCK_HIT_SOUND_ID)
end

local function findRigByRole(role: string, fallbackNames: { string }): Model?
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("Model") and descendant:GetAttribute(ROLE_ATTRIBUTE) == role and isRigModel(descendant) then
			return descendant
		end
	end

	for _, fallbackName in ipairs(fallbackNames) do
		local named = Workspace:FindFirstChild(fallbackName, true)
		if named and named:IsA("Model") and isRigModel(named) then
			return named
		end
	end

	return nil
end

local function listRigCandidates(): { Model }
	local rigs = {}
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("Model") and isRigModel(descendant) then
			table.insert(rigs, descendant)
		end
	end
	return rigs
end

local function resolvePunchRig(): Model?
	local punchRig = findRigByRole("puncher", PUNCH_RIG_NAMES)
	if punchRig then
		return punchRig
	end
	local rigs = listRigCandidates()
	return rigs[1]
end

local function resolveBlockRig(exclude: Model?): Model?
	local blockRig = findRigByRole("blocker", BLOCK_RIG_NAMES)
	if blockRig and blockRig ~= exclude then
		return blockRig
	end
	local rigs = listRigCandidates()
	for _, rig in ipairs(rigs) do
		if rig ~= exclude then
			return rig
		end
	end
	return nil
end

local function getPostureData(targetModel: Model): (number, number)
	local maxPosture = targetModel:GetAttribute(BLOCK_POSTURE_MAX_ATTRIBUTE)
	if type(maxPosture) ~= "number" or maxPosture <= 0 then
		maxPosture = DEFAULT_POSTURE_MAX
	end
	maxPosture = math.max(1, math.floor(maxPosture))
	targetModel:SetAttribute(BLOCK_POSTURE_MAX_ATTRIBUTE, maxPosture)

	local posture = targetModel:GetAttribute(BLOCK_POSTURE_ATTRIBUTE)
	if type(posture) ~= "number" then
		posture = maxPosture
	else
		posture = math.clamp(math.floor(posture), 0, maxPosture)
	end
	targetModel:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, posture)

	return posture, maxPosture
end

local function clearModelStun(targetModel: Model, humanoid: Humanoid?)
	targetModel:SetAttribute(STUNNED_UNTIL_ATTRIBUTE, nil)
	if not humanoid then
		return
	end
	local baseWalk = targetModel:GetAttribute(STUN_BASE_WALKSPEED_ATTRIBUTE)
	local baseJump = targetModel:GetAttribute(STUN_BASE_JUMPPOWER_ATTRIBUTE)
	if type(baseWalk) == "number" then
		humanoid.WalkSpeed = baseWalk
	end
	if type(baseJump) == "number" then
		humanoid.JumpPower = baseJump
	end
	targetModel:SetAttribute(STUN_BASE_WALKSPEED_ATTRIBUTE, nil)
	targetModel:SetAttribute(STUN_BASE_JUMPPOWER_ATTRIBUTE, nil)
end

local function isModelStunned(targetModel: Model, humanoid: Humanoid?): boolean
	local stunnedUntil = targetModel:GetAttribute(STUNNED_UNTIL_ATTRIBUTE)
	if type(stunnedUntil) ~= "number" then
		return false
	end
	if tick() >= stunnedUntil then
		clearModelStun(targetModel, humanoid)
		return false
	end
	return true
end

local function applyModelStun(targetModel: Model, humanoid: Humanoid?, duration: number)
	if not humanoid then
		return
	end
	local stunDuration = math.max(0, tonumber(duration) or 0)
	if stunDuration <= 0 then
		return
	end
	if targetModel:GetAttribute(STUN_BASE_WALKSPEED_ATTRIBUTE) == nil then
		targetModel:SetAttribute(STUN_BASE_WALKSPEED_ATTRIBUTE, humanoid.WalkSpeed)
	end
	if targetModel:GetAttribute(STUN_BASE_JUMPPOWER_ATTRIBUTE) == nil then
		targetModel:SetAttribute(STUN_BASE_JUMPPOWER_ATTRIBUTE, humanoid.JumpPower)
	end

	local untilTime = tick() + stunDuration
	targetModel:SetAttribute(STUNNED_UNTIL_ATTRIBUTE, untilTime)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	targetModel:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
	syncBlockLoopAnimation(targetModel, humanoid, false)

	task.delay(stunDuration, function()
		if not targetModel or not targetModel.Parent then
			return
		end
		local currentUntil = targetModel:GetAttribute(STUNNED_UNTIL_ATTRIBUTE)
		if currentUntil ~= untilTime then
			return
		end
		clearModelStun(targetModel, humanoid)
	end)
end

local function isGuardBroken(targetModel: Model): boolean
	local brokenUntil = targetModel:GetAttribute(GUARD_BROKEN_UNTIL_ATTRIBUTE)
	if type(brokenUntil) ~= "number" then
		return false
	end
	if tick() >= brokenUntil then
		targetModel:SetAttribute(GUARD_BROKEN_UNTIL_ATTRIBUTE, nil)
		return false
	end
	return true
end

local function applyGuardBreak(targetModel: Model, targetHumanoid: Humanoid?, maxPosture: number)
	local untilTime = tick() + GUARD_BREAK_DURATION
	targetModel:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
	targetModel:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, 0)
	targetModel:SetAttribute(GUARD_BROKEN_UNTIL_ATTRIBUTE, untilTime)

	if targetHumanoid then
		syncBlockLoopAnimation(targetModel, targetHumanoid, false)
	end
	playBlockBreakEffects(targetModel, targetHumanoid)
	applyModelStun(targetModel, targetHumanoid, BLOCK_BREAK_STUN_DURATION)

	task.delay(GUARD_BREAK_DURATION, function()
		if not targetModel or not targetModel.Parent then
			return
		end
		if targetModel:GetAttribute(GUARD_BROKEN_UNTIL_ATTRIBUTE) ~= untilTime then
			return
		end
		targetModel:SetAttribute(GUARD_BROKEN_UNTIL_ATTRIBUTE, nil)
		targetModel:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, math.max(1, math.floor(maxPosture or DEFAULT_POSTURE_MAX)))
	end)
end

local function ensureBlockRigState(blockRig: Model)
	local blockHumanoid = getHumanoid(blockRig)
	if not blockHumanoid then
		return
	end

	local posture, maxPosture = getPostureData(blockRig)
	if isModelStunned(blockRig, blockHumanoid) then
		blockRig:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
		syncBlockLoopAnimation(blockRig, blockHumanoid, false)
		return
	end
	if isGuardBroken(blockRig) then
		blockRig:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
		syncBlockLoopAnimation(blockRig, blockHumanoid, false)
		return
	end

	if posture <= 0 then
		posture = maxPosture
		blockRig:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, posture)
	end
	blockRig:SetAttribute(BLOCKING_STATE_ATTRIBUTE, true)
	syncBlockLoopAnimation(blockRig, blockHumanoid, true)
end

local function tryConsumeBlockPosture(targetModel: Model, targetHumanoid: Humanoid, damage: number): boolean
	if targetModel:GetAttribute(BLOCKING_STATE_ATTRIBUTE) ~= true then
		return false
	end
	if targetModel:GetAttribute(BLOCK_DEFENSE_DISABLED_ATTRIBUTE) == true then
		targetModel:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
		return false
	end
	if isGuardBroken(targetModel) then
		targetModel:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
		return false
	end

	local posture, maxPosture = getPostureData(targetModel)
	if posture <= 0 then
		targetModel:SetAttribute(BLOCKING_STATE_ATTRIBUTE, nil)
		return false
	end

	local nextPosture = math.max(0, posture - math.max(0, math.floor(damage or 0)))
	targetModel:SetAttribute(BLOCK_POSTURE_ATTRIBUTE, nextPosture)
	playBlockHitSound(targetModel)

	if nextPosture <= 0 then
		applyGuardBreak(targetModel, targetHumanoid, maxPosture)
	end
	return true
end

local function clearForceFields(targetModel: Model)
	for _, child in ipairs(targetModel:GetChildren()) do
		if child:IsA("ForceField") then
			child:Destroy()
		end
	end
end

local function applyForwardM1Damage(targetModel: Model, targetHumanoid: Humanoid, damage: number)
	clearForceFields(targetModel)
	if tryConsumeBlockPosture(targetModel, targetHumanoid, damage) then
		return
	end
	targetHumanoid:TakeDamage(damage)
end

local function getMeleeHitbox(attackerRoot: BasePart): (CFrame, Vector3)
	local forward = attackerRoot.CFrame.LookVector
	local center = attackerRoot.Position + (forward * MELEE_FORWARD_OFFSET)
	local cframe = CFrame.lookAt(center, center + forward)
	return cframe, MELEE_HITBOX_SIZE
end

local function isPointInsideHitbox(hitboxCFrame: CFrame, hitboxSize: Vector3, point: Vector3): boolean
	local localPos = hitboxCFrame:PointToObjectSpace(point)
	local half = hitboxSize * 0.5
	return
		math.abs(localPos.X) <= half.X and
		math.abs(localPos.Y) <= half.Y and
		math.abs(localPos.Z) <= half.Z
end

local function findForwardMeleeTarget(attackerRig: Model): { model: Model, humanoid: Humanoid, root: BasePart }?
	local attackerRoot = getRoot(attackerRig)
	if not attackerRoot then
		return nil
	end

	local hitboxCFrame, hitboxSize = getMeleeHitbox(attackerRoot)
	drawMeleeHitbox(hitboxCFrame, hitboxSize)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { attackerRig }

	local forward = attackerRoot.CFrame.LookVector
	local seen = {}
	local best = nil

	local function tryCandidate(model: Model)
		if not model or seen[model] or model == attackerRig then
			return
		end
		seen[model] = true

		local asPlayer = Players:GetPlayerFromCharacter(model)
		if not asPlayer and not isRigModel(model) then
			return
		end

		local targetHumanoid = getHumanoid(model)
		local targetRoot = getRoot(model)
		if not targetHumanoid or not targetRoot then
			return
		end

		local delta = targetRoot.Position - attackerRoot.Position
		local distance = delta.Magnitude
		if distance <= 0.05 then
			return
		end
		if distance > MELEE_MAX_DISTANCE then
			return
		end
		local dot = forward:Dot(delta.Unit)
		if dot < MELEE_DOT_MIN then
			return
		end

		local score = (dot * 100) - distance
		if not best or score > best.score then
			best = {
				model = model,
				humanoid = targetHumanoid,
				root = targetRoot,
				score = score,
			}
		end
	end

	for _, part in ipairs(Workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlap)) do
		local model = part and part:FindFirstAncestorOfClass("Model")
		if model then
			tryCandidate(model)
		end
	end

	-- Fallback for non-queryable parts.
	if not best then
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and getRoot(character)
			if character and root and isPointInsideHitbox(hitboxCFrame, hitboxSize, root.Position) then
				tryCandidate(character)
			end
		end
		for _, rig in ipairs(listRigCandidates()) do
			local root = getRoot(rig)
			if root and isPointInsideHitbox(hitboxCFrame, hitboxSize, root.Position) then
				tryCandidate(rig)
			end
		end
	end

	return best
end

local function performForwardM1(punchRig: Model): number
	local attackInterval = DEFAULT_ATTACK_INTERVAL
	local punchHumanoid = getHumanoid(punchRig)
	if not punchHumanoid then
		return attackInterval
	end
	if isModelStunned(punchRig, punchHumanoid) then
		return attackInterval
	end

	local attackTrack = getFistTrack(punchHumanoid)
	if attackTrack then
		if attackTrack.IsPlaying then
			attackTrack:Stop(0.02)
		end
		attackTrack:Play(0.05, 1, FIST_ATTACK_ANIMATION_SPEED)
		local length = attackTrack.Length
		if type(length) == "number" and length > 0 then
			attackInterval = math.max(MIN_ATTACK_INTERVAL, length / FIST_ATTACK_ANIMATION_SPEED)
		end
	end

	local hit = findForwardMeleeTarget(punchRig)
	if not hit then
		return attackInterval
	end

	applyForwardM1Damage(hit.model, hit.humanoid, FIST_DAMAGE)
	return attackInterval
end

task.spawn(function()
	local warnedMissing = false
	while true do
		local punchRig = resolvePunchRig()
		local blockRig = resolveBlockRig(punchRig)

		if not punchRig and not blockRig then
			if not warnedMissing then
				warn(string.format(
					"[TestRigCombat] Need at least one non-player rig. Preferred names: \"%s\" and \"%s\". Or set %s=\"puncher\" / \"blocker\".",
					PUNCH_RIG_NAMES[1],
					BLOCK_RIG_NAMES[1],
					ROLE_ATTRIBUTE
				))
				warnedMissing = true
			end
			task.wait(1)
			continue
		end

		warnedMissing = false
		local attackInterval = DEFAULT_ATTACK_INTERVAL
		if blockRig then
			ensureBlockRigState(blockRig)
		end
		if punchRig then
			attackInterval = performForwardM1(punchRig)
		end

		task.wait(attackInterval)
	end
end)
