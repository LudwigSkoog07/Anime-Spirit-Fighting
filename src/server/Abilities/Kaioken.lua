-- Kaioken 10x: temporary health and damage boost
local Debris = game:GetService("Debris")
local AbilityUtil = require(script.Parent:WaitForChild("AbilityUtil"))

local Ability = {}

local DAMAGE_MULT = 1.5
local HEALTH_MULT = 1.5
local DURATION = 12
local FX_FOLDER_NAME = "AFS_KaiokenFx"
local FX_HIGHLIGHT_NAME = "Aura"
local FX_ATTACHMENT_NAME = "AFS_KaiokenAuraAttachment"
local ACTIVATION_SOUND_ID = "rbxassetid://110665865527958"

local function clearKaiokenFx(character: Model)
	if not character then return end

	local root = AbilityUtil.getRoot(character)
	if root then
		local attachment = root:FindFirstChild(FX_ATTACHMENT_NAME)
		if attachment then
			attachment:Destroy()
		end
	end

	local fx = character:FindFirstChild(FX_FOLDER_NAME)
	if fx then
		fx:Destroy()
	end
end

local function applyKaiokenFx(character: Model)
	if not character then return end
	local root = AbilityUtil.getRoot(character)
	if not root then return end

	clearKaiokenFx(character)

	local fxFolder = Instance.new("Folder")
	fxFolder.Name = FX_FOLDER_NAME
	fxFolder.Parent = character

	local highlight = Instance.new("Highlight")
	highlight.Name = FX_HIGHLIGHT_NAME
	highlight.Adornee = character
	highlight.FillColor = Color3.fromRGB(255, 85, 85)
	highlight.OutlineColor = Color3.fromRGB(255, 160, 95)
	highlight.FillTransparency = 0.72
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = fxFolder

	local attachment = Instance.new("Attachment")
	attachment.Name = FX_ATTACHMENT_NAME
	attachment.Parent = root

	local aura = Instance.new("ParticleEmitter")
	aura.Name = "AuraMist"
	aura.Parent = attachment
	aura.Enabled = true
	aura.Rate = 50
	aura.Lifetime = NumberRange.new(0.35, 0.6)
	aura.Speed = NumberRange.new(0.3, 2.2)
	aura.SpreadAngle = Vector2.new(360, 360)
	aura.RotSpeed = NumberRange.new(-120, 120)
	aura.LightEmission = 0.8
	aura.Drag = 4
	aura.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(0.65, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	aura.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	aura.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 135, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 65, 65)),
	})

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "AuraSparks"
	sparks.Parent = attachment
	sparks.Enabled = true
	sparks.Rate = 22
	sparks.Lifetime = NumberRange.new(0.2, 0.35)
	sparks.Speed = NumberRange.new(7, 14)
	sparks.SpreadAngle = Vector2.new(360, 360)
	sparks.Acceleration = Vector3.new(0, 16, 0)
	sparks.LightEmission = 1
	sparks.Drag = 7
	sparks.Size = NumberSequence.new(0.2)
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 175, 120)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 95, 95)),
	})

	local light = Instance.new("PointLight")
	light.Name = "AuraLight"
	light.Parent = attachment
	light.Color = Color3.fromRGB(255, 90, 90)
	light.Brightness = 2.2
	light.Range = 15
	light.Shadows = false

	aura:Emit(36)
	sparks:Emit(22)
end

local function playKaiokenActivationSound(character: Model)
	if not character then return end
	local root = AbilityUtil.getRoot(character)
	if not root then return end

	local sound = Instance.new("Sound")
	sound.Name = "AFS_KaiokenActivateSfx"
	sound.SoundId = ACTIVATION_SOUND_ID
	sound.Volume = 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 120
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, 4)
end

local function applyHealthBoost(humanoid: Humanoid)
	if not humanoid then return end
	if humanoid:GetAttribute("BaseMaxHealth") == nil then
		humanoid:SetAttribute("BaseMaxHealth", humanoid.MaxHealth)
	end
	local base = humanoid:GetAttribute("BaseMaxHealth") or humanoid.MaxHealth
	local newMax = math.floor(base * HEALTH_MULT)
	local ratio = 1
	if humanoid.MaxHealth > 0 then
		ratio = humanoid.Health / humanoid.MaxHealth
	end
	humanoid.MaxHealth = newMax
	humanoid.Health = math.min(newMax, newMax * ratio)
end

local function removeHealthBoost(humanoid: Humanoid)
	if not humanoid then return end
	local base = humanoid:GetAttribute("BaseMaxHealth")
	if base then
		local ratio = 1
		if humanoid.MaxHealth > 0 then
			ratio = humanoid.Health / humanoid.MaxHealth
		end
		humanoid.MaxHealth = base
		humanoid.Health = math.min(base, base * ratio)
		humanoid:SetAttribute("BaseMaxHealth", nil)
	end
end

function Ability.Execute(player: Player, payload, ctx)
	if not player then return false end
	if not AbilityUtil.isInMatch(player) then return false end
	if player:GetAttribute("KaiokenActive") then return false end

	local character = player.Character
	if not character then return false end
	local hum = AbilityUtil.getHumanoid(character)
	if not hum then return false end

	player:SetAttribute("KaiokenActive", true)
	player:SetAttribute("DamageMult_Kaioken", DAMAGE_MULT)

	applyHealthBoost(hum)
	applyKaiokenFx(character)
	playKaiokenActivationSound(character)

	task.delay(DURATION, function()
		if player and player.Parent then
			player:SetAttribute("DamageMult_Kaioken", nil)
			player:SetAttribute("KaiokenActive", nil)
		end
		if hum and hum.Parent then
			removeHealthBoost(hum)
		end
		if character then
			clearKaiokenFx(character)
		end
	end)

	local EV_FX = ctx and ctx.EV_FX
	if EV_FX then
		EV_FX:FireAllClients({
			caster = player.UserId,
			fx = { type = "kaioken", duration = DURATION }
		})
	end

	return true, { fx = { type = "kaioken", duration = DURATION } }
end

return Ability
