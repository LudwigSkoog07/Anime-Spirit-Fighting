-- WaterStrikingTide ability module (fixed)
-- Short forward dash + 3 oriented hit pulses (multi-target) in front of caster.

local Workspace = game:GetService("Workspace")
local AbilityUtil = require(script.Parent:WaitForChild("AbilityUtil"))

local Ability = {}

-- config
local DASH_DISTANCE = 5 -- studs
local DASH_BACKOFF = 1.0 -- how far to stay away from wall hit point
local PULSE_COUNT = 3
local PULSE_INTERVAL = 0.15

-- Oriented hitbox size (local to caster look direction)
local HITBOX_SIZE = Vector3.new(6, 4, 8) -- X width, Y height, Z forward length
local HITBOX_FORWARD_OFFSET = 4 -- studs in front of caster

local PULSE_DAMAGE = 10
local DOT_FOV = 0.35 -- dot threshold; ~0.35 is ~69 degrees cone

local function getRoot(character: Model): BasePart?
	return AbilityUtil.getRoot(character)
end

local function getHumanoid(character: Model): Humanoid?
	return AbilityUtil.getHumanoid(character)
end

local function getPlayerFromPart(part: BasePart): Player?
	return AbilityUtil.getPlayerFromPart(part)
end

local function isInMatch(player: Player): boolean
	return AbilityUtil.isInMatch(player)
end

function Ability.Execute(player: Player, payload, ctx)
	-- ctx should include CombatService and EV_FX
	local CombatService = ctx and ctx.CombatService
	local EV_FX = ctx and ctx.EV_FX
	if not player or not CombatService then
		return false
	end

	local character = player.Character
	if not character then return false end

	local hum = getHumanoid(character)
	local root = getRoot(character)
	if not hum or not root then return false end

	-- Optional match gate (recommended)
	if not isInMatch(player) then
		return false
	end

	-- ==== DASH (server-authoritative, clamped by raycast) ====
	local look = root.CFrame.LookVector
	local origin = root.Position
	local desired = origin + look * DASH_DISTANCE

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	rayParams.IgnoreWater = true

	local result = Workspace:Raycast(origin, look * DASH_DISTANCE, rayParams)
	if result and result.Position then
		desired = result.Position - look * DASH_BACKOFF
	end

	-- Preserve facing; only move position
	root.CFrame = CFrame.new(desired, desired + look)

	if EV_FX then
		EV_FX:FireAllClients({
			caster = player.UserId,
			fx = { type = "water_dash", position = root.Position }
		})
	end

	-- ==== HIT PULSES (oriented box + FOV) ====
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }

	local hitTargetsUserIds = {}
	local alreadyCounted = {} -- overall list (optional)

	for pulse = 1, PULSE_COUNT do
		if not character.Parent then break end
		if hum.Health <= 0 then break end

		local curRoot = getRoot(character)
		if not curRoot then break end

		local curLook = curRoot.CFrame.LookVector

		-- Oriented hitbox in front of caster
		local boxCFrame =
			curRoot.CFrame * CFrame.new(0, 0, -HITBOX_FORWARD_OFFSET) -- NOTE: Roblox forward is -Z in object space

		AbilityUtil.debugBox(boxCFrame, HITBOX_SIZE, Color3.fromRGB(80, 180, 255), PULSE_INTERVAL)

		local parts = Workspace:GetPartBoundsInBox(boxCFrame, HITBOX_SIZE, overlap)

		local hitThisPulse = {} -- de-dupe this pulse by userId

		for _, part in ipairs(parts) do
			if part and part:IsA("BasePart") then
				local targetPlr = getPlayerFromPart(part)
				if targetPlr and targetPlr ~= player and not hitThisPulse[targetPlr.UserId] then
					-- Optional match gate for targets too
					if isInMatch(targetPlr) then
						if CombatService and CombatService.IsEnemy and not CombatService:IsEnemy(player, targetPlr) then
							continue
						end
						local tChar = targetPlr.Character
						if tChar then
							local tHum = getHumanoid(tChar)
							local tRoot = getRoot(tChar)
							if tHum and tRoot then
								-- FOV check
								local dir = (tRoot.Position - curRoot.Position)
								if dir.Magnitude > 0.001 then
									dir = dir.Unit
									local dot = curLook:Dot(dir)
									if dot >= DOT_FOV then
										-- Apply damage via CombatService helper (keeps kill attribution)
										CombatService:ApplyAbilityDamage(player, tHum, PULSE_DAMAGE, "water_striking_tide")

										hitThisPulse[targetPlr.UserId] = true
										alreadyCounted[targetPlr.UserId] = true
									end
								end
							end
						end
					end
				end
			end
		end

		-- Optional FX per pulse
		if EV_FX then
			EV_FX:FireAllClients({
				caster = player.UserId,
				fx = { type = "water_pulse", position = root.Position, pulse = pulse }
			})
		end

		-- collect hit ids (unique overall)
		for userId in pairs(hitThisPulse) do
			table.insert(hitTargetsUserIds, userId)
		end

		task.wait(PULSE_INTERVAL)
	end

	return true, {
		fx = { type = "water_slash_end", position = root.Position },
		hits = hitTargetsUserIds
	}
end

return Ability
