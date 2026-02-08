-- Test rig walker: moves a named rig left/right for ability testing.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RIG_NAME = "AFS_TestRig"
local DEFAULT_PATROL_DISTANCE = 24
local PAUSE_BETWEEN_POINTS = 0.2
local MOVE_TIMEOUT = 8

if not RunService:IsStudio() then
	return
end

local function getRoot(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart
		or model.PrimaryPart
		or model:FindFirstChild("UpperTorso") :: BasePart
		or model:FindFirstChild("Torso") :: BasePart
end

local function getHumanoid(model: Model): Humanoid?
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

local function findRig(): Model?
	local rig = Workspace:FindFirstChild(RIG_NAME, true)
	if rig and rig:IsA("Model") then
		return rig
	end
	return nil
end

local function waitForRig(): Model
	local rig = findRig()
	while not rig do
		task.wait(0.5)
		rig = findRig()
	end
	return rig
end

local function patrolRig(rig: Model)
	local humanoid = getHumanoid(rig)
	local root = getRoot(rig)
	if not humanoid or not root then
		return
	end

	if root.Anchored then
		root.Anchored = false
	end

	local patrolDistance = tonumber(rig:GetAttribute("PatrolDistance")) or DEFAULT_PATROL_DISTANCE
	local halfDistance = math.max(2, patrolDistance * 0.5)
	local center = root.Position
	local leftPos = center + Vector3.new(-halfDistance, 0, 0)
	local rightPos = center + Vector3.new(halfDistance, 0, 0)

	print(string.format("[TestRigWalker] %s patrol started. Left=%s Right=%s", rig.Name, tostring(leftPos), tostring(rightPos)))

	local function waitForMoveFinished()
		local finished = false
		local conn = humanoid.MoveToFinished:Connect(function()
			finished = true
		end)
		local startedAt = os.clock()
		while not finished and humanoid.Parent and humanoid.Health > 0 and (os.clock() - startedAt) < MOVE_TIMEOUT do
			task.wait(0.05)
		end
		conn:Disconnect()
	end

	while rig.Parent and humanoid.Parent and humanoid.Health > 0 do
		humanoid:MoveTo(rightPos)
		waitForMoveFinished()
		task.wait(PAUSE_BETWEEN_POINTS)

		if not rig.Parent or humanoid.Health <= 0 then
			break
		end

		humanoid:MoveTo(leftPos)
		waitForMoveFinished()
		task.wait(PAUSE_BETWEEN_POINTS)
	end
end

task.spawn(function()
	print(string.format("[TestRigWalker] Waiting for rig named \"%s\".", RIG_NAME))
	while true do
		local rig = waitForRig()
		patrolRig(rig)
		task.wait(0.5)
	end
end)
