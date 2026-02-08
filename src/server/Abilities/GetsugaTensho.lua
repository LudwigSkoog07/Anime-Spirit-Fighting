-- Getsuga Tensho (Zangetsu Bankai): black energy slash projectile
local AbilityUtil = require(script.Parent:WaitForChild("AbilityUtil"))

local Ability = {}

local HITBOX_SIZE = Vector3.new(6, 6, 26)
local HITBOX_FORWARD_OFFSET = 14
local DAMAGE = 24
local DOT_FOV = 0.1

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
		CombatService:ApplyAbilityDamage(player, t.humanoid, DAMAGE, "getsuga_tensho")
	end

	if EV_FX then
		EV_FX:FireAllClients({
			caster = player.UserId,
			fx = { type = "getsuga", position = root.Position }
		})
	end

	return true, { fx = { type = "getsuga", position = root.Position } }
end

return Ability
