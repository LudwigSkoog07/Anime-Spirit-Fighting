-- Black Flame Barrage: fires a dark flame projectile that applies sticky DoT.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local AbilityUtil = require(script.Parent:WaitForChild("AbilityUtil"))

local Ability = {}

local PROJECTILE_SPEED = 90
local PROJECTILE_RANGE = 80
local PROJECTILE_RADIUS = 3.25
local PROJECTILE_MAX_LIFETIME = 2.5
local CAST_ANIMATION_DURATION = 1.0
local CAST_WINDUP = 0.12
local BURST_WAVES = 10
local BURST_INTERVAL = math.max(0.03, (CAST_ANIMATION_DURATION - CAST_WINDUP) / math.max(1, BURST_WAVES - 1))
local BURST_SPREAD_DEGREES = 7

local DOT_DURATION = 4
local DOT_INTERVAL = 0.5
local DOT_TICKS = math.floor((DOT_DURATION / DOT_INTERVAL) + 0.5)
local DOT_DAMAGE_PER_TICK = 3
local CAST_ANIMATION_ID = "82642912365523"
local FIREBALL_SHOT_SOUND_ID = "rbxassetid://77133369409638"
local ANIM_ID_PREFIX = "rbxassetid://"

local FX_FOLDER_NAME = "AFS_BlackFlameFx"
local TARGET_FX_NAME = "AFS_BlackFlameTargetFx"
local TARGET_ATTR_NAME = "BlackFlameActive"
local TEST_MODE_ATTRIBUTE = "AFS_TestMode"
local TEST_MODE_LEGACY_ATTRIBUTE = "AFS_IgnoreRoundRules"
local DUMMY_DAMAGE_ATTRIBUTE = "AFS_AllowDummyDamage"
local SANDEVISTAN_ACTIVE_COUNT_ATTR = "AFS_SandevistanActiveCount"

local activeBurnTokenByHumanoid = {} -- Humanoid -> number
local castAnimationObject = nil
local rng = Random.new()

local function isTestModeEnabled()
	local v = Workspace:GetAttribute(TEST_MODE_ATTRIBUTE)
	if v ~= nil then
		return v == true
	end
	return Workspace:GetAttribute(TEST_MODE_LEGACY_ATTRIBUTE) == true
end

local function canDamageDummyRigs()
	local override = Workspace:GetAttribute(DUMMY_DAMAGE_ATTRIBUTE)
	if override ~= nil then
		return override == true
	end
	return isTestModeEnabled()
end

local function isGlobalSandevistanFreezeActive()
	local activeCount = Workspace:GetAttribute(SANDEVISTAN_ACTIVE_COUNT_ATTR)
	return type(activeCount) == "number" and activeCount > 0
end

local function normalizeAnimId(id: string?): string?
	if not id or id == "" then return nil end
	id = tostring(id)
	if id:sub(1, #ANIM_ID_PREFIX) ~= ANIM_ID_PREFIX then
		id = ANIM_ID_PREFIX .. id
	end
	return id
end

local function playCastAnimation(player: Player)
	if not player or not player.Character then return end
	local hum = AbilityUtil.getHumanoid(player.Character)
	if not hum then return end

	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local animId = normalizeAnimId(CAST_ANIMATION_ID)
	if not animId then return end

	if not castAnimationObject then
		castAnimationObject = Instance.new("Animation")
		castAnimationObject.AnimationId = animId
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(castAnimationObject)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action4
		track:Play(0.05, 1, 1)
	end
end

local function applyDirectionSpread(baseDirection: Vector3): Vector3
	local yaw = math.rad(rng:NextNumber(-BURST_SPREAD_DEGREES, BURST_SPREAD_DEGREES))
	local pitch = math.rad(rng:NextNumber(-BURST_SPREAD_DEGREES, BURST_SPREAD_DEGREES))
	local cf = CFrame.lookAt(Vector3.zero, baseDirection) * CFrame.Angles(pitch, yaw, 0)
	return cf.LookVector
end

local function getHandPart(character: Model, rightSide: boolean): BasePart?
	local primaryName = rightSide and "RightHand" or "LeftHand"
	local fallbackName = rightSide and "Right Arm" or "Left Arm"

	local limb = character:FindFirstChild(primaryName)
	if limb and limb:IsA("BasePart") then
		return limb
	end

	limb = character:FindFirstChild(fallbackName)
	if limb and limb:IsA("BasePart") then
		return limb
	end

	return nil
end

local function getMuzzleOrigin(character: Model, root: BasePart, rightSide: boolean, direction: Vector3): Vector3
	local hand = getHandPart(character, rightSide)
	if hand then
		return hand.Position + (direction * 1.0)
	end
	local sideOffset = rightSide and 0.7 or -0.7
	return root.Position + Vector3.new(sideOffset, 1.2, 0) + (direction * 2.2)
end

local function isEnemyPlayer(caster: Player, target: Player, combatService)
	if not caster or not target or caster == target then
		return false
	end
	if combatService and combatService.IsEnemy then
		local casterTeam = combatService.GetTeam and combatService:GetTeam(caster) or nil
		local targetTeam = combatService.GetTeam and combatService:GetTeam(target) or nil
		if casterTeam and targetTeam then
			return combatService:IsEnemy(caster, target)
		end
	end
	return AbilityUtil.isInMatch(target)
end

local function getFxFolder()
	local folder = Workspace:FindFirstChild(FX_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = FX_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function clearTargetFx(targetCharacter: Model)
	if not targetCharacter then return end
	local fx = targetCharacter:FindFirstChild(TARGET_FX_NAME)
	if fx then
		fx:Destroy()
	end
end

local function createTargetFx(targetCharacter: Model)
	if not targetCharacter then return nil end
	local root = AbilityUtil.getRoot(targetCharacter)
	if not root then return nil end

	clearTargetFx(targetCharacter)

	local fxFolder = Instance.new("Folder")
	fxFolder.Name = TARGET_FX_NAME
	fxFolder.Parent = targetCharacter

	local attachment = Instance.new("Attachment")
	attachment.Name = "Root"
	attachment.Parent = root

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Parent = attachment
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 20, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 0, 0)),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 2.2),
	})
	smoke.LightEmission = 0.5
	smoke.Speed = NumberRange.new(0.5, 2.2)
	smoke.Drag = 3
	smoke.Lifetime = NumberRange.new(0.35, 0.8)
	smoke.Rate = 65
	smoke.SpreadAngle = Vector2.new(360, 360)

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Parent = attachment
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 75)),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Size = NumberSequence.new(0.16)
	embers.LightEmission = 1
	embers.Speed = NumberRange.new(3.5, 8)
	embers.Acceleration = Vector3.new(0, 9, 0)
	embers.Drag = 6
	embers.Lifetime = NumberRange.new(0.2, 0.4)
	embers.Rate = 22
	embers.SpreadAngle = Vector2.new(360, 360)

	local light = Instance.new("PointLight")
	light.Name = "Aura"
	light.Parent = attachment
	light.Color = Color3.fromRGB(255, 70, 50)
	light.Brightness = 2
	light.Range = 12

	return fxFolder
end

local function createProjectile(origin: Vector3, direction: Vector3, playLaunchSound: boolean)
	local projectile = Instance.new("Part")
	projectile.Name = "AFS_BlackFlameProjectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(1.4, 1.4, 1.4)
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.fromRGB(28, 28, 28)
	projectile.Transparency = 0.1
	projectile.CFrame = CFrame.lookAt(origin, origin + direction)
	projectile.Parent = getFxFolder()

	local core = Instance.new("Attachment")
	core.Name = "Core"
	core.Parent = projectile

	local back = Instance.new("Attachment")
	back.Name = "Back"
	back.Position = Vector3.new(0, 0, 1.8)
	back.Parent = projectile

	local trail = Instance.new("Trail")
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 18, 18)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 20, 20)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.22
	trail.LightEmission = 0.55
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	trail.Attachment0 = core
	trail.Attachment1 = back
	trail.Parent = projectile

	local cloud = Instance.new("ParticleEmitter")
	cloud.Name = "Cloud"
	cloud.Parent = core
	cloud.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 16, 16)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 20, 20)),
	})
	cloud.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	cloud.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1.2),
	})
	cloud.Lifetime = NumberRange.new(0.12, 0.3)
	cloud.Speed = NumberRange.new(0, 0.4)
	cloud.Drag = 4
	cloud.Rate = 90
	cloud.SpreadAngle = Vector2.new(360, 360)

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Parent = core
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 85)),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Size = NumberSequence.new(0.12)
	sparks.Lifetime = NumberRange.new(0.12, 0.2)
	sparks.Speed = NumberRange.new(3, 6)
	sparks.Acceleration = Vector3.new(0, 4, 0)
	sparks.Rate = 50
	sparks.SpreadAngle = Vector2.new(360, 360)

	if playLaunchSound then
		local sound = Instance.new("Sound")
		sound.Name = "ShotSfx"
		sound.SoundId = FIREBALL_SHOT_SOUND_ID
		sound.Volume = 1
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMaxDistance = 110
		sound.Parent = projectile
		sound:Play()
	end

	-- Keep a generous fallback cleanup because projectile lifetime is paused during Sandevistan freeze.
	Debris:AddItem(projectile, PROJECTILE_MAX_LIFETIME + 30)
	return projectile
end

local function findHitModel(
	caster: Player,
	casterCharacter: Model,
	position: Vector3,
	radius: number,
	combatService
)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { casterCharacter }

	local parts = Workspace:GetPartBoundsInRadius(position, radius, overlap)
	local seen = {}
	for _, part in ipairs(parts) do
		local model = part and part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local targetPlayer = Players:GetPlayerFromCharacter(model)
				if targetPlayer then
					if isEnemyPlayer(caster, targetPlayer, combatService) then
						return model, humanoid, targetPlayer
					end
				elseif canDamageDummyRigs() then
					return model, humanoid, nil
				end
			end
		end
	end
	return nil, nil, nil
end

local function applyBlackFlameDot(caster: Player, targetModel: Model, targetHumanoid: Humanoid, targetPlayer: Player?, combatService)
	if not caster or not targetHumanoid then return end
	local token = (activeBurnTokenByHumanoid[targetHumanoid] or 0) + 1
	activeBurnTokenByHumanoid[targetHumanoid] = token

	if targetPlayer then
		targetPlayer:SetAttribute(TARGET_ATTR_NAME, true)
	end
	createTargetFx(targetModel)

	task.spawn(function()
		for tickIndex = 1, DOT_TICKS do
			if activeBurnTokenByHumanoid[targetHumanoid] ~= token then
				return
			end
			if not targetHumanoid.Parent or targetHumanoid.Health <= 0 then
				break
			end

			if combatService then
				combatService:ApplyAbilityDamage(caster, targetHumanoid, DOT_DAMAGE_PER_TICK, "black_flame")
			elseif canDamageDummyRigs() then
				targetHumanoid:TakeDamage(DOT_DAMAGE_PER_TICK)
			end

			if tickIndex < DOT_TICKS then
				task.wait(DOT_INTERVAL)
			end
		end

		if activeBurnTokenByHumanoid[targetHumanoid] == token then
			activeBurnTokenByHumanoid[targetHumanoid] = nil
			if targetPlayer and targetPlayer.Parent then
				targetPlayer:SetAttribute(TARGET_ATTR_NAME, nil)
			end
			if targetModel and targetModel.Parent then
				clearTargetFx(targetModel)
			end
		end
	end)
end

local function launchProjectile(
	caster: Player,
	casterCharacter: Model,
	origin: Vector3,
	direction: Vector3,
	combatService,
	playLaunchSound: boolean
)
	local projectile = createProjectile(origin, direction, playLaunchSound == true)
	local elapsed = 0
	local traveled = 0
	local currentPos = origin

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not projectile.Parent then
			if connection then connection:Disconnect() end
			return
		end

		if isGlobalSandevistanFreezeActive() then
			projectile.CFrame = CFrame.lookAt(currentPos, currentPos + direction)
			return
		end

		local step = PROJECTILE_SPEED * dt
		elapsed += dt
		traveled += step
		currentPos = currentPos + (direction * step)
		projectile.CFrame = CFrame.lookAt(currentPos, currentPos + direction)

		local targetModel, targetHumanoid, targetPlayer = findHitModel(caster, casterCharacter, currentPos, PROJECTILE_RADIUS, combatService)
		if targetHumanoid then
			if connection then connection:Disconnect() end
			projectile:Destroy()
			applyBlackFlameDot(caster, targetModel, targetHumanoid, targetPlayer, combatService)
			return
		end

		if traveled >= PROJECTILE_RANGE or elapsed >= PROJECTILE_MAX_LIFETIME then
			if connection then connection:Disconnect() end
			projectile:Destroy()
		end
	end)
end

function Ability.Execute(player: Player, payload, ctx)
	local CombatService = ctx and ctx.CombatService
	if not player or not CombatService then
		return false
	end
	if not AbilityUtil.isInMatch(player) then return false end

	local character = player.Character
	if not character then return false end
	local root = AbilityUtil.getRoot(character)
	local hum = AbilityUtil.getHumanoid(character)
	if not root or not hum then return false end

	playCastAnimation(player)

	local look = payload and payload.look
	local baseDirection = (typeof(look) == "Vector3" and look.Magnitude > 0.05) and look.Unit or root.CFrame.LookVector

	task.spawn(function()
		task.wait(CAST_WINDUP)
		local projectileCount = 0
		for wave = 1, BURST_WAVES do
			if not player or not player.Parent then
				break
			end
			local currentCharacter = player.Character
			local currentRoot = currentCharacter and AbilityUtil.getRoot(currentCharacter)
			if not currentCharacter or not currentRoot then
				break
			end

			local castDirection = baseDirection
			if castDirection.Magnitude <= 0.05 then
				castDirection = currentRoot.CFrame.LookVector
			end
			castDirection = castDirection.Unit

			local rightOrigin = getMuzzleOrigin(currentCharacter, currentRoot, true, castDirection)
			local leftOrigin = getMuzzleOrigin(currentCharacter, currentRoot, false, castDirection)

			local rightDir = applyDirectionSpread(castDirection)
			local leftDir = applyDirectionSpread(castDirection)

			projectileCount += 1
			launchProjectile(player, currentCharacter, rightOrigin, rightDir, CombatService, projectileCount % 2 == 0)
			projectileCount += 1
			launchProjectile(player, currentCharacter, leftOrigin, leftDir, CombatService, projectileCount % 2 == 0)

			if wave < BURST_WAVES then
				task.wait(BURST_INTERVAL)
			end
		end
	end)

	-- Return FX payload so AbilityService broadcasts cooldown/UI sync.
	return true, { fx = { type = "black_flame", duration = DOT_DURATION } }
end

return Ability
