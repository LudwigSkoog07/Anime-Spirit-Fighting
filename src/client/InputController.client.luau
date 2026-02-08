local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local mouse = localPlayer:GetMouse()

local function getRootPart(character)
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

local function getLookVector(character)
    local root = getRootPart(character)
    if root then
        return root.CFrame.LookVector
    end
    return nil
end

local function getMoveVector(character)
    if not character then return nil end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local move = hum.MoveDirection
    if move.Magnitude > 0.05 then
        return move.Unit
    end
    return nil
end

-- use Shared modules from ReplicatedStorage
local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
if not Shared then warn("Shared modules missing (InputController)") return end
local Constants = require(Shared:WaitForChild("Constants"))

local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotes then warn("Remotes folder not found (InputController)") return end
local REQ_ATTACK = remotes:WaitForChild(Constants.RemoteNames.AttackRequest, 10)
local REQ_BLOCK = remotes:WaitForChild(Constants.RemoteNames.BlockRequest, 10)
local REQ_DASH = remotes:WaitForChild(Constants.RemoteNames.DashRequest, 10)
local REQ_ABILITY = remotes:WaitForChild(Constants.RemoteNames.AbilityRequest, 10)
local REQ_CHALLENGE = remotes:WaitForChild(Constants.RemoteNames.Round_RequestChallenge, 10)
local EV_STATE_UPDATE = remotes:WaitForChild(Constants.RemoteNames.MatchStateUpdate, 10)

local ATTACK_COOLDOWN = 0.2
local DASH_COOLDOWN = 0.8
local lastAttackSent = 0
local lastDashSent = 0
local roundState = nil
local isSpirit = false
local FLASH_STEP_ACTIVE_ATTRIBUTE = "FlashStepActive"
local isBlockHeld = false

local function sendAttack(targetUserId, index)
    local now = tick()
    if now - lastAttackSent < ATTACK_COOLDOWN then return end
    lastAttackSent = now
    REQ_ATTACK:FireServer(targetUserId, index, now)
end

local function fireAbility(abilityId, extraPayload)
    if not abilityId then return end
    local payload = {
        look = getLookVector(localPlayer.Character),
        move = getMoveVector(localPlayer.Character),
    }
    if type(extraPayload) == "table" then
        for k, v in pairs(extraPayload) do
            payload[k] = v
        end
    end
    REQ_ABILITY:FireServer(abilityId, payload)
end

local function sendBlockState(isBlocking)
    if not REQ_BLOCK then return end
    REQ_BLOCK:FireServer(isBlocking == true)
end

local function releaseBlock()
    if not isBlockHeld then return end
    isBlockHeld = false
    sendBlockState(false)
end

local function sendDash()
    if not REQ_DASH then return end
    local now = tick()
    if now - lastDashSent < DASH_COOLDOWN then return end
    lastDashSent = now
    REQ_DASH:FireServer({
        move = getMoveVector(localPlayer.Character),
        look = getLookVector(localPlayer.Character),
        clientTime = now,
    })
end

local EV_SHOP = remotes:WaitForChild(Constants.RemoteNames.ShopUpdate, 10)
local localProfile = {}
if EV_SHOP then
    EV_SHOP.OnClientEvent:Connect(function(profile)
        if profile then localProfile = profile end
    end)
else
    warn("Shop update remote missing (InputController)")
end

if EV_STATE_UPDATE then
    EV_STATE_UPDATE.OnClientEvent:Connect(function(payload)
        if not payload then return end
        if payload.state then roundState = payload.state end
        if payload.spiritUserId then
            isSpirit = payload.spiritUserId == localPlayer.UserId
        end
    end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.F then
        if not isBlockHeld then
            isBlockHeld = true
            sendBlockState(true)
        end
    elseif input.KeyCode == Enum.KeyCode.E then
        local abilityId = localProfile and localProfile.equippedPowers and localProfile.equippedPowers[1]
        if abilityId then
            fireAbility(abilityId)
        end
    elseif input.KeyCode == Enum.KeyCode.R then
        local abilityId = localProfile and localProfile.equippedPowers and localProfile.equippedPowers[2]
        if abilityId then
            fireAbility(abilityId)
        end
    elseif input.KeyCode == Enum.KeyCode.T then
        local abilityId = localProfile and localProfile.equippedPowers and localProfile.equippedPowers[3]
        if abilityId then
            fireAbility(abilityId)
        end
    elseif input.KeyCode == Enum.KeyCode.Q then
        if isBlockHeld then
            releaseBlock()
        end
        sendDash()
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.F then
        releaseBlock()
    end
end)

localPlayer.CharacterRemoving:Connect(function()
    releaseBlock()
end)

mouse.Button1Down:Connect(function()
    local root = getRootPart(localPlayer.Character)
    if not localPlayer.Character or not root then return end
    if isSpirit and roundState == Constants.RoundState.ChoosingOpponent then
        local targetUserId = nil
        local target = mouse.Target
        if target and target.Parent then
            local humanoid = target.Parent:FindFirstChild("Humanoid")
            if humanoid then
                local plr = Players:GetPlayerFromCharacter(target.Parent)
                if plr and plr ~= localPlayer then targetUserId = plr.UserId end
            end
        end

        if not targetUserId then
            local closest, dist = nil, 1e9
            for _, p in ipairs(Players:GetPlayers()) do
                local pRoot = getRootPart(p.Character)
                if p ~= localPlayer and p.Character and pRoot and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
                    local d = (pRoot.Position - root.Position).Magnitude
                    if d <= 100 and d < dist then
                        closest = p
                        dist = d
                    end
                end
            end
            if closest then targetUserId = closest.UserId end
        end

        if targetUserId then
            REQ_CHALLENGE:FireServer(targetUserId)
            return
        end
    end

    if localPlayer:GetAttribute(FLASH_STEP_ACTIVE_ATTRIBUTE) == true then
        return
    end

    -- find target: prefer mouse.Target with humanoid, else nearest player within 7 studs
    local targetUserId = nil
    local target = mouse.Target
    if target and target.Parent then
        local humanoid = target.Parent:FindFirstChild("Humanoid")
        if humanoid then
            local plr = Players:GetPlayerFromCharacter(target.Parent)
            if plr then targetUserId = plr.UserId end
        end
    end

    if not targetUserId then
        -- fallback: find nearest player within 7 studs
        local closest, dist = nil, 1e9
        for _, p in ipairs(Players:GetPlayers()) do
            local pRoot = getRootPart(p.Character)
            if p ~= localPlayer and p.Character and pRoot and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
                local d = (pRoot.Position - root.Position).Magnitude
                if d <= 7 and d < dist then
                    closest = p
                    dist = d
                end
            end
        end
        if closest then targetUserId = closest.UserId end
    end

    sendAttack(targetUserId or 0, 1)
end)
