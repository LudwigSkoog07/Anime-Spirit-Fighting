-- Fiber Sever Slash (Scissor Blade): heavy overhead slash with guard break
local AbilityUtil = require(script.Parent:WaitForChild("AbilityUtil"))

local Ability = {}

local HITBOX_SIZE = Vector3.new(7, 5, 8)
local HITBOX_FORWARD_OFFSET = 5
local DAMAGE = 18
local STUN_DURATION = 0.7
local DEFENSE_DISABLE = 1.8
local DOT_FOV = 0.25

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
		CombatService:ApplyAbilityDamage(player, t.humanoid, DAMAGE, "fiber_sever_slash")
		AbilityUtil.applyMovementScale(t.humanoid, "fiber_sever_slash", 0, 0, STUN_DURATION)
		if t.player and t.player.Character then
			t.player.Character:SetAttribute("DefenseDisabled", true)
			task.delay(DEFENSE_DISABLE, function()
				if t.player and t.player.Character then
					t.player.Character:SetAttribute("DefenseDisabled", false)
				end
			end)
		end
	end

	if EV_FX then
		EV_FX:FireAllClients({
			caster = player.UserId,
			fx = { type = "fiber_slash", position = root.Position }
		})
	end

	return true, { fx = { type = "fiber_slash", position = root.Position } }
end

return Ability
