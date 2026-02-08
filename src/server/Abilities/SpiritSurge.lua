-- Spirit Surge (Spirit Sword): long-range stab that pierces enemies in a line
local AbilityUtil = require(script.Parent:WaitForChild("AbilityUtil"))

local Ability = {}

local HITBOX_SIZE = Vector3.new(4, 4, 18)
local HITBOX_FORWARD_OFFSET = 10
local DAMAGE = 20
local DOT_FOV = 0.15

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

	local boxCFrame = root.CFrame * CFrame.new(0, 0, -HITBOX_FORWARD_OFFSET)
	local targets = AbilityUtil.getTargetsInBox(player, boxCFrame, HITBOX_SIZE, overlap, DOT_FOV, CombatService)
	for _, t in ipairs(targets) do
		CombatService:ApplyAbilityDamage(player, t.humanoid, DAMAGE, "spirit_surge")
	end

	if EV_FX then
		EV_FX:FireAllClients({
			caster = player.UserId,
			fx = { type = "spirit_surge", position = root.Position }
		})
	end

	return true, { fx = { type = "spirit_surge", position = root.Position } }
end

return Ability
