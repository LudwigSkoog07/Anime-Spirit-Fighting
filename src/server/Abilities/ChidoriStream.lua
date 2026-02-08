-- Chidori Stream (Kusanagi Blade): lightning burst that stuns nearby enemies
local AbilityUtil = require(script.Parent:WaitForChild("AbilityUtil"))

local Ability = {}

local RADIUS = 8
local DAMAGE = 12
local SLOW_DURATION = 1.0

function Ability.Execute(player: Player, payload, ctx)
	local CombatService = ctx and ctx.CombatService
	local EV_FX = ctx and ctx.EV_FX
	if not player or not CombatService then
		return false
	end

	local character = player.Character
	if not character then return false end
	local hum = AbilityUtil.getHumanoid(character)
	local root = AbilityUtil.getRoot(character)
	if not hum or not root then return false end
	if not AbilityUtil.isInMatch(player) then return false end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }

	local targets = AbilityUtil.getTargetsInRadius(player, root.Position, RADIUS, overlap, CombatService)
	for _, t in ipairs(targets) do
		CombatService:ApplyAbilityDamage(player, t.humanoid, DAMAGE, "chidori_stream")
		AbilityUtil.applyMovementScale(t.humanoid, "chidori_stream", 0.35, 0.35, SLOW_DURATION)
	end

	if EV_FX then
		EV_FX:FireAllClients({
			caster = player.UserId,
			fx = { type = "chidori_stream", position = root.Position }
		})
	end

	return true, { fx = { type = "chidori_stream", position = root.Position } }
end

return Ability
