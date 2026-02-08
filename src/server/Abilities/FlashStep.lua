-- Flash Step: toggle mode.
-- Press once to activate speed/invisibility, press again to deactivate.
-- While active, the player leaves dark afterimages at wider spacing.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AbilityUtil = require(script.Parent:WaitForChild("AbilityUtil"))
local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
local ItemConfig = Shared and require(Shared:WaitForChild("ItemConfig"))
local CooldownService = Shared and require(Shared:WaitForChild("CooldownService"))

local Ability = {}

local ACTIVE_DURATION = 5
local SPEED_MULT = 2.35
local ECHO_CHECK_INTERVAL = 0.08
local MIN_AFTERIMAGE_DISTANCE = 8.0

local FX_FOLDER_NAME = "AFS_FlashStepFx"
local AFTERIMAGE_BASE_TRANSPARENCY = 0.52
local AFTERIMAGE_DARKEN_ALPHA = 0.78
local AFTERIMAGE_LIFETIME = 1.0
local AFTERIMAGE_Y_OFFSET = -2.0

local SOUND_ID = "rbxassetid://89663981846729"
local SOUND_VOLUME = 0.52
local SOUND_MAX_DISTANCE = 120
local ABILITY_ID = "flash_step"
local FLASH_STEP_ACTIVE_ATTR = "FlashStepActive"

local activeStateByUserId = {}

local function setFlashStepActive(player: Player?, isActive: boolean)
	if not player or not player.Parent then
		return
	end
	player:SetAttribute(FLASH_STEP_ACTIVE_ATTR, isActive and true or nil)
end

local function getCooldownSeconds()
	local it = ItemConfig and ItemConfig.Get and ItemConfig.Get(ABILITY_ID)
	if it and type(it.cooldown) == "number" then
		return it.cooldown
	end
	return 5
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

local function getModelRoot(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
		or model:FindFirstChild("UpperTorso")
		or model:FindFirstChild("Torso")
		or model:FindFirstChild("LowerTorso")
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function prepareAfterimageTemplate(character: Model): Model?
	local wasArchivable = character.Archivable
	if not wasArchivable then
		character.Archivable = true
	end

	local ok, template = pcall(function()
		return character:Clone()
	end)

	if character and character.Parent then
		character.Archivable = wasArchivable
	end

	if not ok or not template then
		return nil
	end

	local templateRoot = getModelRoot(template)
	if not templateRoot then
		template:Destroy()
		return nil
	end
	template.Name = "AFS_FlashStepAfterimageTemplate"
	template.PrimaryPart = templateRoot

	for _, inst in ipairs(template:GetDescendants()) do
		if inst:IsA("Humanoid")
			or inst:IsA("Animator")
			or inst:IsA("AnimationController")
			or inst:IsA("Script")
			or inst:IsA("LocalScript")
			or inst:IsA("ModuleScript")
			or inst:IsA("Sound")
			or inst:IsA("ParticleEmitter")
			or inst:IsA("Trail")
			or inst:IsA("Beam")
			or inst:IsA("Smoke")
			or inst:IsA("Fire")
			or inst:IsA("Sparkles")
			or inst:IsA("Highlight")
			or inst:IsA("SurfaceAppearance")
		then
			inst:Destroy()
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			inst.Transparency = 1
		elseif inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
			inst.Massless = true
			inst.Color = inst.Color:Lerp(Color3.new(0, 0, 0), AFTERIMAGE_DARKEN_ALPHA)
			inst.Transparency = AFTERIMAGE_BASE_TRANSPARENCY
		end
	end

	return template
end

local function spawnAfterimage(character: Model, template: Model)
	if not character or not template then
		return false
	end
	local pivot = character:GetPivot() * CFrame.new(0, AFTERIMAGE_Y_OFFSET, 0)

	local ghost = template:Clone()
	ghost.Name = "AFS_FlashStepAfterimage"
	local ghostRoot = getModelRoot(ghost)
	if not ghostRoot then
		ghost:Destroy()
		return false
	end
	ghost.PrimaryPart = ghostRoot
	ghost:PivotTo(pivot)
	ghost.Parent = getFxFolder()

	local fadeInfo = TweenInfo.new(AFTERIMAGE_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, inst in ipairs(ghost:GetDescendants()) do
		if inst:IsA("BasePart") then
			TweenService:Create(inst, fadeInfo, { Transparency = 1 }):Play()
		end
	end

	local sound = Instance.new("Sound")
	sound.Name = "AFS_FlashStepSfx"
	sound.SoundId = SOUND_ID
	sound.Volume = SOUND_VOLUME
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = SOUND_MAX_DISTANCE
	sound.Parent = ghostRoot
	sound:Play()

	Debris:AddItem(ghost, AFTERIMAGE_LIFETIME + 0.1)
	return true
end

local function applyInvisibility(character: Model, state)
	state.partTransparency = {}
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") then
			state.partTransparency[inst] = inst.Transparency
			inst.Transparency = 1
		end
	end
end

local function restoreInvisibility(state)
	if not state or not state.partTransparency then return end
	for part, oldTransparency in pairs(state.partTransparency) do
		if part and part.Parent then
			part.Transparency = oldTransparency
		end
	end
	state.partTransparency = nil
end

local function applySpeedBoost(humanoid: Humanoid, state)
	state.baseWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = state.baseWalkSpeed * SPEED_MULT
end

local function restoreSpeed(state)
	if not state then return end
	local humanoid = state.humanoid
	if humanoid and humanoid.Parent and type(state.baseWalkSpeed) == "number" then
		humanoid.WalkSpeed = state.baseWalkSpeed
	end
	state.baseWalkSpeed = nil
end

local function deactivateState(userId: number, reason: string?)
	local state = activeStateByUserId[userId]
	if not state then return end

	state.released = true
	restoreInvisibility(state)
	restoreSpeed(state)

	if state.template then
		state.template:Destroy()
		state.template = nil
	end

	activeStateByUserId[userId] = nil

	local player = state.player
	setFlashStepActive(player, false)
	if player and player.Parent then
		local cooldown = getCooldownSeconds()
		if CooldownService and CooldownService.StartCooldown then
			CooldownService:StartCooldown(player, ABILITY_ID, cooldown)
		end
		if state.evFx then
			state.evFx:FireAllClients({
				caster = player.UserId,
				abilityId = ABILITY_ID,
				cooldown = cooldown,
				fx = {
					type = "flash_step_end",
					reason = reason or "release",
				},
			})
		end
	end
end

local function runActiveLoop(player: Player, userId: number, token: number)
	local state = activeStateByUserId[userId]
	if not state or state.token ~= token then
		return
	end

	local startedAt = os.clock()
	local lastPos = nil

	while os.clock() - startedAt < ACTIVE_DURATION do
		local current = activeStateByUserId[userId]
		if not current or current.token ~= token or current.released then
			break
		end
		if not player or not player.Parent then
			break
		end

		local character = player.Character
		local root = character and AbilityUtil.getRoot(character)
		local humanoid = character and AbilityUtil.getHumanoid(character)
		if not character or not root or not humanoid then
			break
		end

		if not current.template then
			current.template = prepareAfterimageTemplate(character)
		end

		local pos = root.Position
		if not lastPos then
			lastPos = pos
		elseif (pos - lastPos).Magnitude >= MIN_AFTERIMAGE_DISTANCE then
			if current.template then
				spawnAfterimage(character, current.template)
			end
			lastPos = pos
		end

		task.wait(ECHO_CHECK_INTERVAL)
	end

	local final = activeStateByUserId[userId]
	if final and final.token == token then
		deactivateState(userId, "expired")
	end
end

function Ability.IsActive(player: Player): boolean
	if not player then return false end
	local state = activeStateByUserId[player.UserId]
	return state ~= nil and state.released ~= true
end

function Ability.HandleInput(player: Player, payload, _ctx)
	if not player then return false, "no-player" end
	if type(payload) ~= "table" or payload.action ~= "release" then
		return false, "unsupported-input"
	end

	local userId = player.UserId
	if not activeStateByUserId[userId] then
		return false, "not-active"
	end
	deactivateState(userId, "manual-release")
	return true, { released = true, noCooldown = true, fx = { type = "flash_step_end" } }
end

function Ability.Execute(player: Player, payload, ctx)
	if not player then return false end
	if not AbilityUtil.isInMatch(player) then return false end

	local character = player.Character
	if not character then return false end
	local humanoid = AbilityUtil.getHumanoid(character)
	local root = AbilityUtil.getRoot(character)
	if not humanoid or not root then return false end

	local userId = player.UserId
	if activeStateByUserId[userId] then
		deactivateState(userId, "toggle-off")
		return true, { noCooldown = true, fx = { type = "flash_step_end" } }
	end

	local state = {
		token = math.floor(os.clock() * 1000),
		released = false,
		humanoid = humanoid,
		baseWalkSpeed = nil,
		partTransparency = nil,
		template = nil,
		player = player,
		evFx = ctx and ctx.EV_FX or nil,
	}
	activeStateByUserId[userId] = state
	setFlashStepActive(player, true)

	applyInvisibility(character, state)
	applySpeedBoost(humanoid, state)

	task.spawn(function()
		runActiveLoop(player, userId, state.token)
	end)

	return true, {
		noCooldown = true,
		fx = {
			type = "flash_step",
			activeDuration = ACTIVE_DURATION,
		}
	}
end

return Ability
