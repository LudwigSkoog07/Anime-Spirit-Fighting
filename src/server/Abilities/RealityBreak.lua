-- Sandevistan (legacy reality_break id): freeze nearby enemies and play speed FX.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AbilityUtil = require(script.Parent:WaitForChild("AbilityUtil"))

local Ability = {}

local DURATION = 6
local FREEZE_SCALE = 0
local FREEZE_RELEASE_BUFFER = 0.15
local CASTER_SPEED_MULT = 2.5
local CASTER_JUMP_MULT = 1.12
local CASTER_BASE_WALKSPEED_ATTR = "AFS_SandevistanBaseWalkSpeed"
local CASTER_BASE_JUMPPOWER_ATTR = "AFS_SandevistanBaseJumpPower"
local SANDEVISTAN_ACTIVE_COUNT_ATTR = "AFS_SandevistanActiveCount"

local function debugLogsEnabled()
	local override = Workspace:GetAttribute("AFS_DebugLogs")
	if override ~= nil then
		return override == true
	end
	return RunService:IsStudio()
end

local function incrementSandevistanActiveCount()
	local current = Workspace:GetAttribute(SANDEVISTAN_ACTIVE_COUNT_ATTR)
	local count = type(current) == "number" and current or 0
	Workspace:SetAttribute(SANDEVISTAN_ACTIVE_COUNT_ATTR, count + 1)
end

local function decrementSandevistanActiveCount()
	local current = Workspace:GetAttribute(SANDEVISTAN_ACTIVE_COUNT_ATTR)
	local count = type(current) == "number" and current or 0
	local nextCount = count - 1
	if nextCount > 0 then
		Workspace:SetAttribute(SANDEVISTAN_ACTIVE_COUNT_ATTR, nextCount)
	else
		Workspace:SetAttribute(SANDEVISTAN_ACTIVE_COUNT_ATTR, nil)
	end
end

local function captureServerTargets(caster: Player)
	local captured = {}
	local labels = {}
	local seenCharacters = {}

	local function addTarget(targetPlayer: Player?, targetCharacter: Model, targetHumanoid: Humanoid, targetRoot: BasePart, labelPrefix: string)
		if seenCharacters[targetCharacter] then
			return
		end
		seenCharacters[targetCharacter] = true

		local labelName = targetPlayer and targetPlayer.Name or targetCharacter.Name
		table.insert(labels, string.format("%s:%s", labelPrefix, labelName))
		table.insert(captured, {
			player = targetPlayer,
			character = targetCharacter,
			humanoid = targetHumanoid,
			root = targetRoot,
		})
	end

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= caster then
			local targetCharacter = targetPlayer.Character
			local humanoid = targetCharacter and AbilityUtil.getHumanoid(targetCharacter)
			local root = targetCharacter and AbilityUtil.getRoot(targetCharacter)
			if humanoid and root then
				addTarget(targetPlayer, targetCharacter, humanoid, root, "Player")
			end
		end
	end

	if AbilityUtil.canDamageDummyRigs() then
		for _, descendant in ipairs(Workspace:GetDescendants()) do
			if descendant:IsA("Humanoid") then
				local targetCharacter = descendant.Parent
				if targetCharacter and targetCharacter:IsA("Model") and targetCharacter ~= caster.Character then
					local dummyOwner = Players:GetPlayerFromCharacter(targetCharacter)
					if not dummyOwner then
						local humanoid = AbilityUtil.getHumanoid(targetCharacter)
						local root = AbilityUtil.getRoot(targetCharacter)
						if humanoid and root then
							addTarget(nil, targetCharacter, humanoid, root, "Dummy")
						end
					end
				end
			end
		end
	end

	if debugLogsEnabled() then
		if #labels > 0 then
			print(string.format("[Sandevistan] Frozen %d target(s): %s", #labels, table.concat(labels, ", ")))
		else
			print("[Sandevistan] Frozen 0 target(s).")
		end
	end

	return captured
end

local function applyCasterSpeedBoost(humanoid: Humanoid?)
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if humanoid:GetAttribute(CASTER_BASE_WALKSPEED_ATTR) == nil then
		humanoid:SetAttribute(CASTER_BASE_WALKSPEED_ATTR, humanoid.WalkSpeed)
	end
	local baseWalkSpeed = humanoid:GetAttribute(CASTER_BASE_WALKSPEED_ATTR)
	if type(baseWalkSpeed) == "number" and baseWalkSpeed > 0 then
		humanoid.WalkSpeed = baseWalkSpeed * CASTER_SPEED_MULT
	end

	if humanoid.UseJumpPower ~= false then
		if humanoid:GetAttribute(CASTER_BASE_JUMPPOWER_ATTR) == nil then
			humanoid:SetAttribute(CASTER_BASE_JUMPPOWER_ATTR, humanoid.JumpPower)
		end
		local baseJumpPower = humanoid:GetAttribute(CASTER_BASE_JUMPPOWER_ATTR)
		if type(baseJumpPower) == "number" and baseJumpPower > 0 then
			humanoid.JumpPower = baseJumpPower * CASTER_JUMP_MULT
		end
	end
end

local function restoreCasterSpeedBoost(humanoid: Humanoid?)
	if not humanoid or not humanoid.Parent then
		return
	end

	local baseWalkSpeed = humanoid:GetAttribute(CASTER_BASE_WALKSPEED_ATTR)
	if type(baseWalkSpeed) == "number" and baseWalkSpeed > 0 then
		humanoid.WalkSpeed = baseWalkSpeed
	end
	humanoid:SetAttribute(CASTER_BASE_WALKSPEED_ATTR, nil)

	if humanoid.UseJumpPower ~= false then
		local baseJumpPower = humanoid:GetAttribute(CASTER_BASE_JUMPPOWER_ATTR)
		if type(baseJumpPower) == "number" and baseJumpPower > 0 then
			humanoid.JumpPower = baseJumpPower
		end
	end
	humanoid:SetAttribute(CASTER_BASE_JUMPPOWER_ATTR, nil)
end

function Ability.Execute(player: Player, payload, ctx)
	local EV_FX = ctx and ctx.EV_FX
	local CombatService = ctx and ctx.CombatService
	if not CombatService then
		local servicesFolder = script.Parent.Parent and script.Parent.Parent:FindFirstChild("services")
		local combatModule = servicesFolder and servicesFolder:FindFirstChild("CombatService")
		if combatModule then
			local ok, mod = pcall(require, combatModule)
			if ok and mod then
				CombatService = mod
			end
		end
	end
	if not player then
		return false
	end
	if not AbilityUtil.isInMatch(player) then return false end

	local character = player.Character
	if not character then return false end
	local root = AbilityUtil.getRoot(character)
	if not root then return false end
	local casterHumanoid = AbilityUtil.getHumanoid(character)
	local capturedTargets = captureServerTargets(player)
	applyCasterSpeedBoost(casterHumanoid)
	incrementSandevistanActiveCount()

	local freezeId = string.format("sandevistan_%d_%d", player.UserId, math.floor(os.clock() * 1000))
	for index, t in ipairs(capturedTargets) do
		local targetHumanoid = t.humanoid
		local targetFreezeId = freezeId .. "_" .. tostring(index)
		if targetHumanoid and targetHumanoid.Parent and targetHumanoid.Health > 0 then
			AbilityUtil.applyMovementScale(targetHumanoid, targetFreezeId, FREEZE_SCALE, FREEZE_SCALE, DURATION + FREEZE_RELEASE_BUFFER)
			if CombatService and CombatService.BeginSandevistanDeferredDamage then
				CombatService:BeginSandevistanDeferredDamage(targetHumanoid, targetFreezeId)
			end
		end

		local targetRoot = t.root
		if targetRoot and targetRoot.Parent then
			t.wasAnchored = targetRoot.Anchored
			targetRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			targetRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
			targetRoot.Anchored = true
		end
	end

	task.delay(DURATION, function()
		decrementSandevistanActiveCount()
		restoreCasterSpeedBoost(casterHumanoid)
		for index, t in ipairs(capturedTargets) do
			local targetFreezeId = freezeId .. "_" .. tostring(index)
			local targetRoot = t.root
			if targetRoot and targetRoot.Parent and t.wasAnchored ~= nil then
				targetRoot.Anchored = t.wasAnchored
				t.wasAnchored = nil
			end

			local targetHumanoid = t.humanoid
			if CombatService and CombatService.EndSandevistanDeferredDamage and targetHumanoid then
				CombatService:EndSandevistanDeferredDamage(targetHumanoid, targetFreezeId)
			end
		end
	end)

	if EV_FX then
		EV_FX:FireAllClients({
			caster = player.UserId,
			fx = { type = "sandevistan", duration = DURATION, fovTarget = 102 }
		})
	end

	return true, {
		fx = { type = "sandevistan", duration = DURATION, fovTarget = 102 },
		activeDuration = DURATION,
	}
end

return Ability
