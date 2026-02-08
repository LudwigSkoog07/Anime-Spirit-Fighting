-- WeaponService: attaches weapon models to characters based on equipped weapon
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
if not Shared then warn("Shared modules missing (WeaponService)") end
local ItemConfig = Shared and require(Shared:WaitForChild("ItemConfig"))

local WeaponService = {}

WeaponService.WeaponAttribute = "AFS_Weapon"
WeaponService.WeaponModelName = "AFS_WeaponModel"
WeaponService.WeaponIdAttribute = "AFS_WeaponId"
WeaponService.WeaponMountAttribute = "AFS_WeaponMount"

local ANIM_ID_PREFIX = "rbxassetid://"
local idleTrackByHumanoid = setmetatable({}, { __mode = "k" })

local function normalizeAnimId(id)
    if not id or id == "" then return nil end
    id = tostring(id)
    if id:sub(1, #ANIM_ID_PREFIX) ~= ANIM_ID_PREFIX then
        id = ANIM_ID_PREFIX .. id
    end
    return id
end

local function getAnimator(humanoid)
    if not humanoid then return nil end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end
    return animator
end

local function stopIdleTrackForCharacter(character)
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local track = idleTrackByHumanoid[humanoid]
    if track then
        pcall(function()
            if track.IsPlaying then track:Stop(0.05) end
            track:Destroy()
        end)
        idleTrackByHumanoid[humanoid] = nil
    end
end

local function playIdleForItem(character, item)
    if not character or not item then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local animId = normalizeAnimId(item.idleAnimationId or item.idleAnim or item.idleAnimation)
    if not animId then return end
    stopIdleTrackForCharacter(character)
    local animator = getAnimator(humanoid)
    if not animator then return end
    local anim = Instance.new("Animation")
    anim.AnimationId = animId
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    if not ok or not track then return end
    track.Priority = Enum.AnimationPriority.Idle
    track.Looped = true
    track:Play(0.1, 1, 1)
    idleTrackByHumanoid[humanoid] = track
end

local function getWeaponsFolder()
    local folder = ServerStorage:FindFirstChild("Weapons")
    if not folder then
        folder = ReplicatedStorage:FindFirstChild("Weapons")
    end
    return folder
end

local function getRightHand(character: Model): BasePart?
    local rightHand = character:FindFirstChild("RightHand")
    if rightHand and rightHand:IsA("BasePart") then
        return rightHand
    end

    local rightArm = character:FindFirstChild("Right Arm")
    if rightArm and rightArm:IsA("BasePart") then
        return rightArm
    end

    return nil
end

local function getWaistPart(character: Model): BasePart?
    local lowerTorso = character:FindFirstChild("LowerTorso")
    if lowerTorso and lowerTorso:IsA("BasePart") then
        return lowerTorso
    end

    local torso = character:FindFirstChild("Torso")
    if torso and torso:IsA("BasePart") then
        return torso
    end

    local upperTorso = character:FindFirstChild("UpperTorso")
    if upperTorso and upperTorso:IsA("BasePart") then
        return upperTorso
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart and rootPart:IsA("BasePart") then
        return rootPart
    end

    return nil
end

local function getBackPart(character: Model): BasePart?
    local upperTorso = character:FindFirstChild("UpperTorso")
    if upperTorso and upperTorso:IsA("BasePart") then
        return upperTorso
    end

    local torso = character:FindFirstChild("Torso")
    if torso and torso:IsA("BasePart") then
        return torso
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart and rootPart:IsA("BasePart") then
        return rootPart
    end

    local lowerTorso = character:FindFirstChild("LowerTorso")
    if lowerTorso and lowerTorso:IsA("BasePart") then
        return lowerTorso
    end

    return nil
end

local function findHandle(model: Instance): BasePart?
    if model:IsA("Model") and model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart
    end

    local handle = model:FindFirstChild("Handle", true)
    if handle and handle:IsA("BasePart") then
        if model:IsA("Model") then
            model.PrimaryPart = handle
        end
        return handle
    end

    local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
    if firstPart then
        if model:IsA("Model") then
            model.PrimaryPart = firstPart
        end
        return firstPart
    end

    return nil
end

local function setNonCollide(model: Instance)
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.Massless = true
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end
    end
end

local function clearExistingWeapon(character: Model)
    -- stop any weapon-specific idle animation
    stopIdleTrackForCharacter(character)
    for _, child in ipairs(character:GetChildren()) do
        if child:GetAttribute(WeaponService.WeaponAttribute) == true or child.Name == WeaponService.WeaponModelName then
            child:Destroy()
        end
    end
end

local function getCharacterWeaponModel(character: Model): Instance?
    if not character then return nil end
    local direct = character:FindFirstChild(WeaponService.WeaponModelName)
    if direct then
        return direct
    end
    for _, child in ipairs(character:GetChildren()) do
        if child:GetAttribute(WeaponService.WeaponAttribute) == true then
            return child
        end
    end
    return nil
end

local function getOffsetCFrame(offsetData)
    if type(offsetData) ~= "table" then return nil end
    local o = offsetData
    local pos = o.pos or o.position or o.p or {}
    local rot = o.rot or o.rotation or o.r or {}
    local px = pos.x or pos[1] or 0
    local py = pos.y or pos[2] or 0
    local pz = pos.z or pos[3] or 0
    local rx = rot.x or rot[1] or 0
    local ry = rot.y or rot[2] or 0
    local rz = rot.z or rot[3] or 0
    return CFrame.new(px, py, pz) * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
end

local function alignHandleToHand(hand: BasePart, handle: BasePart, offset: CFrame?)
    local handAttachment = hand:FindFirstChild("RightGripAttachment") or hand:FindFirstChild("RightGrip")
    local gripAttachment = handle:FindFirstChild("Grip") or handle:FindFirstChild("RightGripAttachment") or handle:FindFirstChild("GripAttachment")

    if handAttachment and handAttachment:IsA("Attachment") and gripAttachment and gripAttachment:IsA("Attachment") then
        handle.CFrame = handAttachment.WorldCFrame * gripAttachment.CFrame:Inverse()
        if offset then
            handle.CFrame = handle.CFrame * offset
        end
        return
    end

    -- Fallback alignment (tweak in Studio if needed by adding a Grip attachment)
    handle.CFrame = hand.CFrame * CFrame.new(0, -1, -0.6) * CFrame.Angles(math.rad(-90), 0, 0)
    if offset then
        handle.CFrame = handle.CFrame * offset
    end
end

local function alignHandleToPart(part: BasePart, handle: BasePart, offset: CFrame?)
    handle.CFrame = part.CFrame
    if offset then
        handle.CFrame = handle.CFrame * offset
    end
end

local function clearCharacterHandleJoints(character: Model, weaponModel: Instance, handle: BasePart)
    for _, inst in ipairs(character:GetDescendants()) do
        if inst:IsA("Motor6D") then
            if inst.Part1 == handle then
                inst:Destroy()
            end
        elseif inst:IsA("WeldConstraint") then
            if inst.Part1 == handle and (inst.Name == "AFS_WeaponWeld" or not inst:IsDescendantOf(weaponModel)) then
                inst:Destroy()
            end
        elseif inst:IsA("Weld") then
            if inst.Part1 == handle and not inst:IsDescendantOf(weaponModel) then
                inst:Destroy()
            end
        end
    end
end

local function getMountOffsetCFrame(item, mountMode: string)
    if mountMode == "waist" then
        return getOffsetCFrame(item and item.waistOffset)
            or (CFrame.new(0.85, -0.95, 0.2) * CFrame.Angles(math.rad(0), math.rad(90), math.rad(100)))
    elseif mountMode == "back" then
        return getOffsetCFrame(item and item.backOffset)
            or (CFrame.new(0.7, -0.25, 0.75) * CFrame.Angles(math.rad(25), math.rad(-90), math.rad(80)))
    end
    return getOffsetCFrame(item and item.gripOffset)
end

local function applyMount(character: Model, clone: Instance, handle: BasePart, item, mountMode: string): boolean
    local mountPart: BasePart? = nil
    if mountMode == "waist" then
        mountPart = getWaistPart(character)
    elseif mountMode == "back" then
        mountPart = getBackPart(character)
    else
        mountPart = getRightHand(character)
    end

    if not mountPart then
        return false
    end

    -- Detach first, then reposition; moving while welded can shove/fling the character.
    clearCharacterHandleJoints(character, clone, handle)
    setNonCollide(clone)

    local offset = getMountOffsetCFrame(item, mountMode)
    if mountMode == "waist" or mountMode == "back" then
        alignHandleToPart(mountPart, handle, offset)
    else
        alignHandleToHand(mountPart, handle, offset)
    end

    handle.AssemblyLinearVelocity = Vector3.zero
    handle.AssemblyAngularVelocity = Vector3.zero

    local weld = Instance.new("WeldConstraint")
    weld.Name = "AFS_WeaponWeld"
    weld.Part0 = mountPart
    weld.Part1 = handle
    weld.Parent = handle

    clone:SetAttribute(WeaponService.WeaponMountAttribute, mountMode)
    return true
end

local function getRequestedMount(item, mode: string?): string
    if mode == "waist" or mode == "back" or mode == "hand" then
        return mode
    end
    local defaultMount = item and item.equipMount
    if defaultMount == "back" then
        return "back"
    end
    if defaultMount == "waist" then
        return "waist"
    end
    return "hand"
end

function WeaponService:SetWeaponMount(player: Player, mode: string?): boolean
    if not player or not player.Character then return false end
    local character = player.Character
    local weaponModel = getCharacterWeaponModel(character)
    if not weaponModel then return false end

    local weaponId = weaponModel:GetAttribute(WeaponService.WeaponIdAttribute)
    if type(weaponId) ~= "string" or weaponId == "" then
        return false
    end

    local item = ItemConfig and ItemConfig.Get and ItemConfig.Get(weaponId) or nil
    if not item then return false end

    local requestedMount = getRequestedMount(item, mode)
    local currentMount = weaponModel:GetAttribute(WeaponService.WeaponMountAttribute)
    if currentMount == requestedMount then
        return true
    end

    local handle = findHandle(weaponModel)
    if not handle then
        return false
    end

    return applyMount(character, weaponModel, handle, item, requestedMount)
end

function WeaponService:Unsheathe(player: Player): boolean
    return self:SetWeaponMount(player, "hand")
end

function WeaponService:Sheathe(player: Player): boolean
    return self:SetWeaponMount(player, "default")
end

function WeaponService:ApplyWeapon(player: Player, weaponId: string?)
    if not player then return end
    local character = player.Character
    if not character then return end

    clearExistingWeapon(character)

    if not weaponId or weaponId == "fists" then
        return
    end

    local item = ItemConfig and ItemConfig.Get and ItemConfig.Get(weaponId) or nil
    local modelName = item and (item.model or item.modelName) or nil
    if not modelName then
        warn("[WeaponService] No model configured for weapon:", weaponId)
        return
    end

    local weaponsFolder = getWeaponsFolder()
    if not weaponsFolder then
        warn("[WeaponService] Weapons folder missing. Create ServerStorage/Weapons or ReplicatedStorage/Weapons")
        return
    end

    local source = weaponsFolder:FindFirstChild(modelName)
    if not source then
        warn("[WeaponService] Weapon model not found:", modelName)
        return
    end

    local clone = source:Clone()
    clone.Name = WeaponService.WeaponModelName
    clone:SetAttribute(WeaponService.WeaponAttribute, true)
    clone:SetAttribute(WeaponService.WeaponIdAttribute, weaponId)
    clone.Parent = character

    local handle = findHandle(clone)
    if not handle then
        warn("[WeaponService] Weapon model has no BasePart:", modelName)
        clone:Destroy()
        return
    end

    setNonCollide(clone)
    local mountMode = getRequestedMount(item, nil)
    local ok = applyMount(character, clone, handle, item, mountMode)
    if not ok then
        warn("[WeaponService] Could not mount weapon for:", player.Name, "mode:", mountMode)
        clone:Destroy()
    end
    -- play idle animation for this weapon if configured
    pcall(function()
        playIdleForItem(character, item)
    end)
end

return WeaponService
