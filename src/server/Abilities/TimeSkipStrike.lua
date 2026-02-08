-- Time Skip Strike: brief time freeze, then blink strike critical hit
local AbilityUtil = require(script.Parent:WaitForChild("AbilityUtil"))

local Ability = {}

local RANGE = 24
local DOT_MIN = 0.2
local CRITICAL_DAMAGE = 42
local FREEZE_DURATION = 0.3
local DASH_BACK_OFFSET = 2

local function isEnemy(caster: Player, target: Player, combatService)
	if not caster or not target or caster == target then
		return false
	end
	if combatService and combatService.IsEnemy then
		return combatService:IsEnemy(caster, target)
	end
	return true
end

local function freezeTarget(targetInfo, duration: number, freezeKey: string)
	local frozenUserIds = {}
	if not targetInfo then
		return frozenUserIds
	end

	local targetPlayer = targetInfo.player
	local targetCharacter = targetInfo.character
	local targetHumanoid = targetInfo.humanoid or (targetCharacter and AbilityUtil.getHumanoid(targetCharacter))
	local targetRoot = targetInfo.root or (targetCharacter and AbilityUtil.getRoot(targetCharacter))
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return frozenUserIds
	end

	AbilityUtil.applyMovementScale(targetHumanoid, freezeKey .. "_target", 0, 0, duration)

	if targetRoot and targetRoot.Parent then
		local wasAnchored = targetRoot.Anchored
		targetRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		targetRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		targetRoot.Anchored = true
		task.delay(duration, function()
			if targetRoot and targetRoot.Parent then
				targetRoot.Anchored = wasAnchored
			end
		end)
	end

	if targetPlayer then
		table.insert(frozenUserIds, targetPlayer.UserId)
	end

	return frozenUserIds
end

function Ability.Execute(player: Player, payload, ctx)
	local CombatService = ctx and ctx.CombatService
	if not player or not CombatService then
		return false, "missing-context"
	end
	if not AbilityUtil.isInMatch(player) then return false, "not-in-match" end

	local character = player.Character
	if not character then return false, "no-character" end
	local root = AbilityUtil.getRoot(character)
	if not root then return false, "no-root" end

	local targetInfo = AbilityUtil.findTargetInCone(player, RANGE, DOT_MIN, CombatService)
	if not targetInfo then return false, "no-target-in-cone" end
	local target = targetInfo.player
	local targetCharacter = targetInfo.character
	local tHum = targetInfo.humanoid or (targetCharacter and AbilityUtil.getHumanoid(targetCharacter))
	if not tHum or tHum.Health <= 0 then return false, "target-invalid" end
	if target and not isEnemy(player, target, CombatService) then return false, "target-not-enemy" end

	local freezeKey = string.format("time_skip_%d_%d", player.UserId, math.floor(os.clock() * 1000))
	local frozenTargets = freezeTarget(targetInfo, FREEZE_DURATION, freezeKey)

	task.spawn(function()
		task.wait(FREEZE_DURATION)
		if not player or not player.Parent or not AbilityUtil.isInMatch(player) then
			return
		end

		local currentCharacter = player.Character
		local currentRoot = currentCharacter and AbilityUtil.getRoot(currentCharacter)
		if not currentRoot then return end

		local refreshedTargetCharacter = target and target.Character or targetCharacter
		local targetHumanoid = refreshedTargetCharacter and AbilityUtil.getHumanoid(refreshedTargetCharacter)
		local targetRoot = refreshedTargetCharacter and AbilityUtil.getRoot(refreshedTargetCharacter)
		if not targetHumanoid or not targetRoot or targetHumanoid.Health <= 0 then
			return
		end
		if target and (not AbilityUtil.isInMatch(target) or not isEnemy(player, target, CombatService)) then
			return
		end

		local behindPos = targetRoot.Position - (targetRoot.CFrame.LookVector * DASH_BACK_OFFSET)
		currentRoot.CFrame = CFrame.lookAt(behindPos, targetRoot.Position)
		CombatService:ApplyAbilityDamage(player, targetHumanoid, CRITICAL_DAMAGE, "time_skip")
	end)

	return true, {
		fx = {
			type = "time_skip",
			target = target and target.UserId or nil,
			targetModel = targetCharacter and targetCharacter.Name or nil,
			freezeDuration = FREEZE_DURATION,
			frozenTargets = frozenTargets,
		}
	}
end

return Ability
