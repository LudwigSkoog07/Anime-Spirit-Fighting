local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local AbilityUtil = {}

local DEBUG_DEFAULT = RunService:IsStudio()
local DEBUG_LIFETIME = 0.25
local DEBUG_COLOR_BOX = Color3.fromRGB(255, 90, 90)
local DEBUG_COLOR_RADIUS = Color3.fromRGB(90, 200, 255)
local TEST_MODE_ATTRIBUTE = "AFS_TestMode"
local TEST_MODE_LEGACY_ATTRIBUTE = "AFS_IgnoreRoundRules"
local ALLOW_DUMMY_DAMAGE_ATTRIBUTE = "AFS_AllowDummyDamage"

local function isTestModeEnabled()
	local v = Workspace:GetAttribute(TEST_MODE_ATTRIBUTE)
	if v ~= nil then
		return v == true
	end
	return Workspace:GetAttribute(TEST_MODE_LEGACY_ATTRIBUTE) == true
end

local function canDamageDummyRigs()
	local override = Workspace:GetAttribute(ALLOW_DUMMY_DAMAGE_ATTRIBUTE)
	if override ~= nil then
		return override == true
	end
	return isTestModeEnabled() or RunService:IsStudio()
end

local function debugEnabled()
	local override = Workspace:GetAttribute("AFS_ShowHitboxes")
	if override ~= nil then
		return override == true
	end
	return DEBUG_DEFAULT
end

local function getDebugFolder()
	local f = Workspace:FindFirstChild("AFS_DebugHitboxes")
	if not f then
		f = Instance.new("Folder")
		f.Name = "AFS_DebugHitboxes"
		f.Parent = Workspace
	end
	return f
end

function AbilityUtil.debugBox(boxCFrame: CFrame, boxSize: Vector3, color: Color3?, duration: number?)
	if not debugEnabled() then return end
	if not boxCFrame or not boxSize then return end
	local part = Instance.new("Part")
	part.Name = "AFS_HitboxDebug"
	part.Size = boxSize
	part.CFrame = boxCFrame
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 0.7
	part.Material = Enum.Material.ForceField
	part.Color = color or DEBUG_COLOR_BOX
	part.Parent = getDebugFolder()
	task.delay(duration or DEBUG_LIFETIME, function()
		if part then part:Destroy() end
	end)
end

function AbilityUtil.debugSphere(center: Vector3, radius: number, color: Color3?, duration: number?)
	if not debugEnabled() then return end
	if not center or not radius then return end
	local part = Instance.new("Part")
	part.Name = "AFS_HitboxDebug"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	part.CFrame = CFrame.new(center)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 0.7
	part.Material = Enum.Material.ForceField
	part.Color = color or DEBUG_COLOR_RADIUS
	part.Parent = getDebugFolder()
	task.delay(duration or DEBUG_LIFETIME, function()
		if part then part:Destroy() end
	end)
end

function AbilityUtil.getRoot(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart
		or character.PrimaryPart
		or character:FindFirstChild("UpperTorso") :: BasePart
		or character:FindFirstChild("Torso") :: BasePart
		or character:FindFirstChild("LowerTorso") :: BasePart
		or character:FindFirstChild("Head") :: BasePart
end

function AbilityUtil.getHumanoid(character: Model): Humanoid?
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

function AbilityUtil.getPlayerFromPart(part: BasePart): Player?
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then return nil end
	return Players:GetPlayerFromCharacter(model)
end

function AbilityUtil.isInMatch(player: Player): boolean
	if isTestModeEnabled() then
		return true
	end
	-- Allow free ability testing against dummy rigs outside active rounds.
	if canDamageDummyRigs() then
		return true
	end
	return player:GetAttribute("InMatch") == true
end

function AbilityUtil.canDamageDummyRigs(): boolean
	return canDamageDummyRigs()
end

function AbilityUtil.recomputeMovement(humanoid: Humanoid)
	if not humanoid then return end
	if humanoid:GetAttribute("BaseWalkSpeed") == nil then
		humanoid:SetAttribute("BaseWalkSpeed", humanoid.WalkSpeed)
	end
	if humanoid:GetAttribute("BaseJumpPower") == nil then
		humanoid:SetAttribute("BaseJumpPower", humanoid.JumpPower)
	end

	local baseWalk = humanoid:GetAttribute("BaseWalkSpeed") or humanoid.WalkSpeed
	local baseJump = humanoid:GetAttribute("BaseJumpPower") or humanoid.JumpPower
	local moveScale = 1
	local jumpScale = 1
	local attrs = humanoid:GetAttributes()
	for k, v in pairs(attrs) do
		if type(v) == "number" then
			if k:sub(1, 10) == "MoveScale_" then
				moveScale = math.min(moveScale, v)
			elseif k:sub(1, 10) == "JumpScale_" then
				jumpScale = math.min(jumpScale, v)
			end
		end
	end

	humanoid.WalkSpeed = baseWalk * moveScale
	humanoid.JumpPower = baseJump * jumpScale
end

function AbilityUtil.applyMovementScale(humanoid: Humanoid, id: string, moveScale: number, jumpScale: number, duration: number)
	if not humanoid then return end
	humanoid:SetAttribute("MoveScale_" .. id, moveScale)
	humanoid:SetAttribute("JumpScale_" .. id, jumpScale)
	AbilityUtil.recomputeMovement(humanoid)

	if duration and duration > 0 then
		task.spawn(function()
			task.wait(duration)
			if humanoid.Parent then
				humanoid:SetAttribute("MoveScale_" .. id, nil)
				humanoid:SetAttribute("JumpScale_" .. id, nil)
				AbilityUtil.recomputeMovement(humanoid)
			end
		end)
	end
end

function AbilityUtil.getTargetsInBox(caster: Player, boxCFrame: CFrame, boxSize: Vector3, overlapParams: OverlapParams, dotMin: number?, combatService, debugDraw: boolean?)
	if debugDraw ~= false then
		AbilityUtil.debugBox(boxCFrame, boxSize)
	end
	local parts = Workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlapParams)
	local res = {}
	local seenPlayers = {}
	local seenModels = {}
	local allowDummyDamage = AbilityUtil.canDamageDummyRigs()

	local casterChar = caster.Character
	local casterRoot = casterChar and AbilityUtil.getRoot(casterChar)
	local casterLook = casterRoot and casterRoot.CFrame.LookVector

	local function passesFov(targetRoot)
		if not dotMin or not casterRoot or not casterLook then
			return true
		end
		local dir = (targetRoot.Position - casterRoot.Position)
		if dir.Magnitude <= 0.001 then
			return true
		end
		dir = dir.Unit
		local dot = casterLook:Dot(dir)
		return dot >= dotMin
	end

	for _, part in ipairs(parts) do
		if part and part:IsA("BasePart") then
			local model = part:FindFirstAncestorOfClass("Model")
			if not model or model == casterChar or seenModels[model] then
				continue
			end

			local targetPlr = Players:GetPlayerFromCharacter(model)
			local tHum = AbilityUtil.getHumanoid(model)
			local tRoot = AbilityUtil.getRoot(model)
			if not tHum or not tRoot then
				continue
			end
			if not passesFov(tRoot) then
				continue
			end

			if targetPlr then
				if targetPlr == caster or seenPlayers[targetPlr.UserId] then
					continue
				end
				if not AbilityUtil.isInMatch(targetPlr) then
					continue
				end
				if combatService and combatService.IsEnemy and not combatService:IsEnemy(caster, targetPlr) then
					continue
				end
				seenPlayers[targetPlr.UserId] = true
				seenModels[model] = true
				table.insert(res, {
					player = targetPlr,
					character = model,
					humanoid = tHum,
					root = tRoot,
				})
			elseif allowDummyDamage then
				seenModels[model] = true
				table.insert(res, {
					player = nil,
					character = model,
					model = model,
					humanoid = tHum,
					root = tRoot,
				})
			end
		end
	end

	return res
end

function AbilityUtil.getTargetsInRadius(caster: Player, center: Vector3, radius: number, overlapParams: OverlapParams, combatService)
	local boxSize = Vector3.new(radius * 2, radius * 2, radius * 2)
	local boxCFrame = CFrame.new(center)
	AbilityUtil.debugSphere(center, radius)
	return AbilityUtil.getTargetsInBox(caster, boxCFrame, boxSize, overlapParams, nil, combatService, false)
end

function AbilityUtil.findTargetInCone(caster: Player, maxDist: number, dotMin: number, combatService)
	local casterChar = caster.Character
	local casterRoot = casterChar and AbilityUtil.getRoot(casterChar)
	if not casterRoot then return nil end
	local origin = casterRoot.Position
	local look = casterRoot.CFrame.LookVector

	local best
	local bestDist = maxDist + 1

	local function tryTarget(targetPlayer, targetCharacter, targetHumanoid, targetRoot)
		if not targetCharacter or not targetHumanoid or not targetRoot then
			return
		end
		local dir = (targetRoot.Position - origin)
		local dist = dir.Magnitude
		if dist > maxDist or dist <= 0.1 then
			return
		end
		local dot = look:Dot(dir.Unit)
		if dot < dotMin or dist >= bestDist then
			return
		end
		best = {
			player = targetPlayer,
			character = targetCharacter,
			humanoid = targetHumanoid,
			root = targetRoot,
			distance = dist,
		}
		bestDist = dist
	end

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= caster and AbilityUtil.isInMatch(p) and p.Character then
			if combatService and combatService.IsEnemy and not combatService:IsEnemy(caster, p) then
				continue
			end
			local tChar = p.Character
			local tHum = tChar and AbilityUtil.getHumanoid(tChar)
			local tRoot = tChar and AbilityUtil.getRoot(tChar)
			tryTarget(p, tChar, tHum, tRoot)
		end
	end

	if AbilityUtil.canDamageDummyRigs() then
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = casterChar and { casterChar } or {}
		local parts = Workspace:GetPartBoundsInRadius(origin, maxDist, overlap)
		local seenModels = {}
		for _, part in ipairs(parts) do
			if part and part:IsA("BasePart") then
				local model = part:FindFirstAncestorOfClass("Model")
				if model and model ~= casterChar and not seenModels[model] and not Players:GetPlayerFromCharacter(model) then
					seenModels[model] = true
					local tHum = AbilityUtil.getHumanoid(model)
					local tRoot = AbilityUtil.getRoot(model)
					tryTarget(nil, model, tHum, tRoot)
				end
			end
		end
	end

	return best
end

return AbilityUtil
