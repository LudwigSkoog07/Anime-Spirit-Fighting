-- ShopController.client: pixel-neon shop modal
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
if not Shared then warn("Shared modules not found in ReplicatedStorage (ShopController)") return end
local Constants = require(Shared:WaitForChild("Constants"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

local Theme = {
    panel = Color3.fromRGB(17, 13, 37),
    panelMid = Color3.fromRGB(24, 18, 52),
    panelDeep = Color3.fromRGB(7, 5, 18),
    accent = Color3.fromRGB(94, 246, 255),
    accentAlt = Color3.fromRGB(200, 122, 255),
    accentHot = Color3.fromRGB(255, 102, 236),
    text = Color3.fromRGB(240, 245, 255),
    textDim = Color3.fromRGB(194, 208, 242),
    stroke = Color3.fromRGB(86, 210, 255),
}

local function applyPixelText(label, strokeTransparency)
    label.Font = Enum.Font.Arcade
    label.TextStrokeColor3 = Theme.panelDeep
    label.TextStrokeTransparency = strokeTransparency or 0.6
end

local function applyPanelGradient(gradient, topColor, bottomColor)
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, topColor or Theme.panel),
        ColorSequenceKeypoint.new(0.48, topColor or Theme.panel),
        ColorSequenceKeypoint.new(0.52, bottomColor or Theme.panelMid),
        ColorSequenceKeypoint.new(1, bottomColor or Theme.panelDeep),
    })
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.02),
        NumberSequenceKeypoint.new(0.6, 0.08),
        NumberSequenceKeypoint.new(1, 0.14),
    })
end

local function ensureScanlines(frame)
    local scan = frame:FindFirstChild("Scanlines") or Instance.new("Frame")
    scan.Name = "Scanlines"
    scan.BackgroundColor3 = Color3.fromRGB(195, 220, 255)
    scan.BackgroundTransparency = 0
    scan.BorderSizePixel = 0
    scan.Size = UDim2.new(1, 0, 1, 0)
    scan.Position = UDim2.new(0, 0, 0, 0)
    scan.ZIndex = 0
    scan.Active = false
    scan.Parent = frame

    local grad = scan:FindFirstChild("Gradient") or Instance.new("UIGradient")
    grad.Name = "Gradient"
    grad.Rotation = 90
    grad.Color = ColorSequence.new(
        Color3.fromRGB(255, 255, 255),
        Color3.fromRGB(200, 215, 255)
    )
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.975),
        NumberSequenceKeypoint.new(0.12, 0.945),
        NumberSequenceKeypoint.new(0.24, 0.975),
        NumberSequenceKeypoint.new(0.36, 0.945),
        NumberSequenceKeypoint.new(0.48, 0.975),
        NumberSequenceKeypoint.new(0.6, 0.945),
        NumberSequenceKeypoint.new(0.72, 0.975),
        NumberSequenceKeypoint.new(0.84, 0.945),
        NumberSequenceKeypoint.new(1, 0.975),
    })
    grad.Parent = scan
end

local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotes then warn("Remotes folder not found (ShopController)") return end
local REQ_PURCHASE = remotes:WaitForChild(Constants.RemoteNames.ShopPurchaseRequest, 10)
local REQ_EQUIP = remotes:WaitForChild(Constants.RemoteNames.ShopEquipRequest, 10)
local EV_UPDATE = remotes:WaitForChild(Constants.RemoteNames.ShopUpdate, 10)
if not (REQ_PURCHASE and EV_UPDATE) then warn("Shop remotes missing events") end
local DEFAULT_THIRD_SLOT_GAMEPASS_ID = math.max(
    0,
    math.floor(tonumber((Constants.GamePasses and Constants.GamePasses.UnlockThirdSlot) or 0) or 0)
)
local THIRD_SLOT_INDEX = 3

-- Create ScreenGui
local screen = PlayerGui:FindFirstChild("ShopGui") or Instance.new("ScreenGui")
screen.Name = "ShopGui"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = PlayerGui

local backdrop = screen:FindFirstChild("ShopBackdrop") or Instance.new("Frame")
backdrop.Name = "ShopBackdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.Position = UDim2.new(0, 0, 0, 0)
backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
backdrop.BackgroundTransparency = 0.4
backdrop.Visible = false
backdrop.ZIndex = 1
backdrop.Parent = screen

-- Modal frame (center)
local modal = screen:FindFirstChild("ShopModal") or Instance.new("Frame")
modal.Name = "ShopModal"
modal.Size = UDim2.new(0,540,0,440)
modal.Position = UDim2.new(0.5, -270, 0.5, -220)
modal.BackgroundColor3 = Theme.panel
modal.BackgroundTransparency = 0
modal.Visible = false
modal.Parent = screen
modal.ZIndex = 2
local modalCorner = Instance.new("UICorner") modalCorner.CornerRadius = UDim.new(0,0) modalCorner.Parent = modal
local modalStroke = Instance.new("UIStroke") modalStroke.Color = Theme.stroke modalStroke.Transparency = 0.2 modalStroke.Thickness = 2 modalStroke.LineJoinMode = Enum.LineJoinMode.Miter modalStroke.Parent = modal
local modalGrad = modal:FindFirstChild("Grad") or Instance.new("UIGradient")
modalGrad.Name = "Grad"
applyPanelGradient(modalGrad, Theme.panel, Theme.panelDeep)
modalGrad.Parent = modal
local modalScale = modal:FindFirstChild("UIScale") or Instance.new("UIScale") modalScale.Scale = 1 modalScale.Parent = modal
ensureScanlines(modal)

-- Power slot prompt
local slotPrompt = modal:FindFirstChild("PowerSlotPrompt") or Instance.new("Frame")
slotPrompt.Name = "PowerSlotPrompt"
slotPrompt.Size = UDim2.new(0, 472, 0, 150)
slotPrompt.Position = UDim2.new(0.5, -236, 0.5, -75)
slotPrompt.BackgroundColor3 = Theme.panelDeep
slotPrompt.BackgroundTransparency = 0.02
slotPrompt.Visible = false
slotPrompt.ZIndex = 5
slotPrompt.Parent = modal
local slotCorner = slotPrompt:FindFirstChild("Corner") or Instance.new("UICorner")
slotCorner.Name = "Corner"
slotCorner.CornerRadius = UDim.new(0, 0)
slotCorner.Parent = slotPrompt
local slotStroke = slotPrompt:FindFirstChild("Stroke") or Instance.new("UIStroke")
slotStroke.Name = "Stroke"
slotStroke.Color = Theme.stroke
slotStroke.Transparency = 0.25
slotStroke.Thickness = 2
slotStroke.Parent = slotPrompt
ensureScanlines(slotPrompt)

local promptTitle = slotPrompt:FindFirstChild("Title") or Instance.new("TextLabel")
promptTitle.Name = "Title"
promptTitle.BackgroundTransparency = 1
promptTitle.Position = UDim2.new(0, 12, 0, 8)
promptTitle.Size = UDim2.new(1, -24, 0, 22)
promptTitle.Font = Enum.Font.Arcade
promptTitle.TextSize = 16
promptTitle.TextColor3 = Theme.text
promptTitle.TextXAlignment = Enum.TextXAlignment.Left
promptTitle.Text = "Equip Ability"
promptTitle.ZIndex = 6
promptTitle.Parent = slotPrompt
applyPixelText(promptTitle, 0.82)

local function makeSlotButton(name, x)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Size = UDim2.new(0, 140, 0, 48)
    b.Position = UDim2.new(0, x, 0, 44)
    b.BackgroundColor3 = Theme.panel
    b.BackgroundTransparency = 0.02
    if name == "SlotE" then
        b.Text = "Slot E"
    elseif name == "SlotR" then
        b.Text = "Slot R"
    else
        b.Text = "Slot T"
    end
    b.Font = Enum.Font.Arcade
    b.TextSize = 14
    b.TextColor3 = Theme.text
    b.AutoButtonColor = false
    b.ZIndex = 6
    b.Parent = slotPrompt
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0,0) c.Parent = b
    local s = Instance.new("UIStroke") s.Color = Theme.stroke s.Transparency = 0.25 s.Thickness = 2 s.LineJoinMode = Enum.LineJoinMode.Miter s.Parent = b
    local info = Instance.new("TextLabel")
    info.Name = "Info"
    info.BackgroundTransparency = 1
    info.Position = UDim2.new(0, 8, 0, 22)
    info.Size = UDim2.new(1, -16, 0, 20)
    info.Font = Enum.Font.Arcade
    info.TextSize = 12
    info.TextColor3 = Theme.textDim
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.Text = "Empty"
    info.ZIndex = 7
    info.Parent = b
    applyPixelText(b, 0.86)
    applyPixelText(info, 0.9)
    return b
end

local slotBtnE = slotPrompt:FindFirstChild("SlotE") or makeSlotButton("SlotE", 14)
local slotBtnR = slotPrompt:FindFirstChild("SlotR") or makeSlotButton("SlotR", 166)
local slotBtnT = slotPrompt:FindFirstChild("SlotT") or makeSlotButton("SlotT", 318)

local cancelBtn = slotPrompt:FindFirstChild("Cancel") or Instance.new("TextButton")
cancelBtn.Name = "Cancel"
cancelBtn.Size = UDim2.new(0, 96, 0, 28)
cancelBtn.Position = UDim2.new(1, -108, 1, -36)
cancelBtn.BackgroundColor3 = Theme.panel
cancelBtn.BackgroundTransparency = 0.02
cancelBtn.Text = "Cancel"
cancelBtn.Font = Enum.Font.Arcade
cancelBtn.TextSize = 14
cancelBtn.TextColor3 = Theme.text
cancelBtn.AutoButtonColor = false
cancelBtn.ZIndex = 6
cancelBtn.Parent = slotPrompt
local cancelCorner = cancelBtn:FindFirstChild("Corner") or Instance.new("UICorner")
cancelCorner.Name = "Corner"
cancelCorner.CornerRadius = UDim.new(0,0)
cancelCorner.Parent = cancelBtn
local cancelStroke = cancelBtn:FindFirstChild("Stroke") or Instance.new("UIStroke")
cancelStroke.Name = "Stroke"
cancelStroke.Color = Theme.stroke
cancelStroke.Transparency = 0.25
cancelStroke.Thickness = 2
cancelStroke.Parent = cancelBtn
applyPixelText(cancelBtn, 0.88)

-- Title bar and close
local title = Instance.new("TextLabel") title.Size = UDim2.new(1, -46, 0, 46) title.Position = UDim2.new(0, 16, 0, 6) title.BackgroundTransparency = 1 title.Font = Enum.Font.Arcade title.TextSize = 22 title.TextColor3 = Theme.text title.Text = "SPIRIT PIXEL ARMORY" title.Parent = modal
local closeBtn = Instance.new("TextButton") closeBtn.Name = "Close" closeBtn.Size = UDim2.new(0,34,0,34) closeBtn.Position = UDim2.new(1, -46, 0, 8) closeBtn.Text = "X" closeBtn.Font = Enum.Font.Arcade closeBtn.TextSize = 18 closeBtn.BackgroundTransparency = 0.02 closeBtn.BackgroundColor3 = Theme.panelDeep closeBtn.TextColor3 = Theme.text closeBtn.Parent = modal
local closeCorner = Instance.new("UICorner") closeCorner.CornerRadius = UDim.new(0,0) closeCorner.Parent = closeBtn
local closeStroke = Instance.new("UIStroke") closeStroke.Color = Theme.stroke closeStroke.Transparency = 0.25 closeStroke.Thickness = 2 closeStroke.Parent = closeBtn
applyPixelText(title, 0.74)
applyPixelText(closeBtn, 0.8)
-- Tabs
local tabs = Instance.new("Frame") tabs.Name = "Tabs" tabs.Size = UDim2.new(1, -24, 0, 36) tabs.Position = UDim2.new(0, 12, 0, 58) tabs.BackgroundTransparency = 1 tabs.Parent = modal
local function makeTab(text, x)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 160, 1, 0)
    b.Position = UDim2.new(0, x, 0, 0)
    b.Font = Enum.Font.Arcade
    b.TextSize = 15
    b.Text = text
    b.BackgroundTransparency = 0.15
    b.BackgroundColor3 = Theme.panelDeep
    b.TextColor3 = Theme.text
    b.Parent = tabs
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0,0) c.Parent = b
    local s = Instance.new("UIStroke") s.Color = Theme.stroke s.Transparency = 0.25 s.Thickness = 2 s.Parent = b
    applyPixelText(b, 0.88)
    return b
end
local tabWeapons = makeTab("Weapons", 0)
local tabPowers = makeTab("Powers", 170)
local tabUpgrades = makeTab("Upgrades", 340)

-- Content list
local content = Instance.new("ScrollingFrame") content.Position = UDim2.new(0, 12, 0, 104) content.Size = UDim2.new(1, -24, 1, -118) content.BackgroundTransparency = 1 content.CanvasSize = UDim2.new(0,0) content.ScrollBarThickness = 6 content.ScrollBarImageColor3 = Theme.accent content.BorderSizePixel = 0 content.Parent = modal

local lastProfile = nil
local pendingPowerId = nil
local SHOP_LOCKED_MESSAGE = "Shop unavailable while fighting"
local showToast
local canAccessShop

local function getAbilityName(id)
    local it = ItemConfig.Get(id)
    return (it and it.name) or "-"
end

local function getThirdSlotGamePassId(profile)
    local profilePassId = profile and tonumber(profile.thirdSlotGamePassId)
    if profilePassId then
        profilePassId = math.floor(profilePassId)
        if profilePassId > 0 then
            return profilePassId
        end
    end
    return DEFAULT_THIRD_SLOT_GAMEPASS_ID
end

local function isThirdSlotUnlocked(profile)
    return profile and profile.thirdSlotUnlocked == true
end

local function getItemDisplayName(item)
    if not item then return "Unknown Item" end
    if type(item.name) == "string" and item.name ~= "" then
        return item.name
    end
    if item.type == "Upgrade" and type(item.hpBonus) == "number" then
        return string.format("+%d HP", item.hpBonus)
    end
    return tostring(item.id or "Unknown Item")
end

local function isEquippedPower(profile, id)
    if not profile or not profile.equippedPowers then return false end
    return profile.equippedPowers[1] == id or profile.equippedPowers[2] == id or profile.equippedPowers[THIRD_SLOT_INDEX] == id
end

local function updateSlotPromptInfo()
    local slot1 = lastProfile and lastProfile.equippedPowers and lastProfile.equippedPowers[1]
    local slot2 = lastProfile and lastProfile.equippedPowers and lastProfile.equippedPowers[2]
    local slot3 = lastProfile and lastProfile.equippedPowers and lastProfile.equippedPowers[THIRD_SLOT_INDEX]
    local thirdSlotUnlocked = isThirdSlotUnlocked(lastProfile)
    local infoE = slotBtnE:FindFirstChild("Info")
    local infoR = slotBtnR:FindFirstChild("Info")
    local infoT = slotBtnT:FindFirstChild("Info")
    if infoE then infoE.Text = slot1 and getAbilityName(slot1) or "Empty" end
    if infoR then infoR.Text = slot2 and getAbilityName(slot2) or "Empty" end
    if infoT then
        if thirdSlotUnlocked then
            infoT.Text = slot3 and getAbilityName(slot3) or "Empty"
            infoT.TextColor3 = Theme.textDim
        else
            infoT.Text = "Locked (Gamepass)"
            infoT.TextColor3 = Theme.accentAlt
        end
    end
    if thirdSlotUnlocked then
        slotBtnT.Text = "Slot T"
        slotBtnT.BackgroundColor3 = Theme.panel
        slotBtnT.TextColor3 = Theme.text
    else
        slotBtnT.Text = "Unlock Slot T"
        slotBtnT.BackgroundColor3 = Theme.accentHot
        slotBtnT.TextColor3 = Theme.panelDeep
    end
end

local function openSlotPrompt(item)
    pendingPowerId = item.id
    promptTitle.Text = "Equip " .. tostring(item.name or "Ability")
    updateSlotPromptInfo()
    slotPrompt.Visible = true
end

local function closeSlotPrompt()
    slotPrompt.Visible = false
    pendingPowerId = nil
end

local function makeRow(item, y, profile)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,64)
    row.Position = UDim2.new(0,0,0,y)
    row.BackgroundTransparency = 0.01
    row.BackgroundColor3 = Theme.panelMid
    row.Parent = content
    local corner = Instance.new("UICorner") corner.CornerRadius = UDim.new(0,0) corner.Parent = row
    local stroke = Instance.new("UIStroke") stroke.Color = Theme.stroke stroke.Transparency = 0.25 stroke.Thickness = 2 stroke.LineJoinMode = Enum.LineJoinMode.Miter stroke.Parent = row

    local name = Instance.new("TextLabel") name.Size = UDim2.new(0.6, -12, 1, 0) name.Position = UDim2.new(0,12,0,0) name.BackgroundTransparency = 1 name.Text = getItemDisplayName(item) name.Font = Enum.Font.Arcade name.TextSize = 18 name.TextColor3 = Theme.text name.Parent = row
    local cost = Instance.new("TextLabel") cost.Size = UDim2.new(0.2, -8, 1, 0) cost.Position = UDim2.new(0.6, 10, 0, 0) cost.BackgroundTransparency = 1 cost.Text = "$" .. tostring(item.cost) cost.Font = Enum.Font.Arcade cost.TextSize = 16 cost.TextColor3 = Theme.text cost.Parent = row

    local btn = Instance.new("TextButton") btn.Size = UDim2.new(0.18, -12, 0.6, -10) btn.Position = UDim2.new(0.82, 0, 0.2, 0) btn.Text = "Buy" btn.Font = Enum.Font.Arcade btn.TextSize = 15 btn.AutoButtonColor = false btn.BackgroundColor3 = Theme.accent btn.TextColor3 = Theme.panelDeep btn.Parent = row
    local btnCorner = Instance.new("UICorner") btnCorner.CornerRadius = UDim.new(0,0) btnCorner.Parent = btn
    local btnStroke = Instance.new("UIStroke") btnStroke.Color = Theme.stroke btnStroke.Transparency = 0.25 btnStroke.Thickness = 2 btnStroke.LineJoinMode = Enum.LineJoinMode.Miter btnStroke.Parent = btn
    applyPixelText(name, 0.84)
    applyPixelText(cost, 0.84)
    applyPixelText(btn, 1)

    local action = "buy"
    local canBuyFromShop = ItemConfig.IsShopEnabled and ItemConfig.IsShopEnabled(item)
    if profile and profile.owned and profile.owned[item.id] then
        if item.type == "Weapon" then
            if profile.equippedWeapon == item.id then
                action = "none"
                btn.Text = "Equipped"
                btn.BackgroundColor3 = Theme.panel
                btn.TextColor3 = Theme.textDim
            else
                action = "equip"
                btn.Text = "Equip"
                btn.BackgroundColor3 = Theme.accentAlt
                btn.TextColor3 = Theme.panelDeep
            end
        elseif item.type == "Power" then
            action = "equip"
            if isEquippedPower(profile, item.id) then
                btn.Text = "Equipped"
                btn.BackgroundColor3 = Theme.accentAlt
                btn.TextColor3 = Theme.panelDeep
            else
                btn.Text = "Equip"
                btn.BackgroundColor3 = Theme.accent
                btn.TextColor3 = Theme.panelDeep
            end
        elseif item.type == "Upgrade" then
            action = "none"
            btn.Text = "Owned"
            btn.BackgroundColor3 = Theme.panel
            btn.TextColor3 = Theme.textDim
        else
            action = "none"
        end
    else
        if canBuyFromShop then
            btn.Text = "Buy"
            btn.BackgroundColor3 = Theme.accent
            btn.TextColor3 = Theme.panelDeep
        else
            action = "none"
            btn.Text = "Soon"
            btn.BackgroundColor3 = Theme.panel
            btn.TextColor3 = Theme.textDim
        end
    end
    btn:SetAttribute("Action", action)

    -- hover effect
    row.MouseEnter:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
    end)
    row.MouseLeave:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.12), { BackgroundTransparency = 0.01 }):Play()
    end)

    btn.MouseButton1Click:Connect(function()
        if not canAccessShop() then return end
        local act = btn:GetAttribute("Action")
        if act == "buy" then
            REQ_PURCHASE:FireServer(item.id)
        elseif act == "equip" then
            if item.type == "Power" then
                openSlotPrompt(item)
            else
                REQ_EQUIP:FireServer(item.id)
            end
        end
    end)

    return row
end

slotBtnE.MouseButton1Click:Connect(function()
    if not canAccessShop() then
        closeSlotPrompt()
        return
    end
    if pendingPowerId then
        REQ_EQUIP:FireServer(pendingPowerId, 1)
    end
    closeSlotPrompt()
end)

slotBtnR.MouseButton1Click:Connect(function()
    if not canAccessShop() then
        closeSlotPrompt()
        return
    end
    if pendingPowerId then
        REQ_EQUIP:FireServer(pendingPowerId, 2)
    end
    closeSlotPrompt()
end)

slotBtnT.MouseButton1Click:Connect(function()
    if not canAccessShop() then
        closeSlotPrompt()
        return
    end

    if isThirdSlotUnlocked(lastProfile) then
        if pendingPowerId then
            REQ_EQUIP:FireServer(pendingPowerId, THIRD_SLOT_INDEX)
        end
        closeSlotPrompt()
        return
    end

    local gamePassId = getThirdSlotGamePassId(lastProfile)
    if gamePassId <= 0 then
        if showToast then
            showToast("Third slot gamepass ID is not configured")
        end
        return
    end
    MarketplaceService:PromptGamePassPurchase(Player, gamePassId)
end)

cancelBtn.MouseButton1Click:Connect(function()
    closeSlotPrompt()
end)

-- Rebuild function with type filtering
local currentTab = "Weapon"
local tabsMap = {
    Weapon = tabWeapons,
    Power = tabPowers,
    Upgrade = tabUpgrades,
}

local function rebuild(profile)
    if profile then lastProfile = profile end
    for _, c in ipairs(content:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local list = ItemConfig.GetByType(currentTab == "Weapon" and "Weapon" or currentTab == "Power" and "Power" or "Upgrade")
    local y = 0
    for _, it in ipairs(list) do
        local row = makeRow(it, y, lastProfile)
        y = y + 70
    end
    content.CanvasSize = UDim2.new(0,0,0,y)
end

local function setActiveTab(tabName)
    currentTab = tabName
    for name, btn in pairs(tabsMap) do
        local active = name == tabName
        btn.BackgroundTransparency = active and 0.02 or 0.2
        btn.BackgroundColor3 = active and Theme.accent or Theme.panelMid
        btn.TextColor3 = active and Theme.panelDeep or Theme.text
    end
    rebuild(lastProfile)
end

-- Tab clicks
tabWeapons.MouseButton1Click:Connect(function() setActiveTab("Weapon") end)
tabPowers.MouseButton1Click:Connect(function() setActiveTab("Power") end)
tabUpgrades.MouseButton1Click:Connect(function() setActiveTab("Upgrade") end)

-- Toast helper
local toast = screen:FindFirstChild("ShopToast")
local toastToken = 0
showToast = function(text)
    if not toast then
        toast = Instance.new("TextLabel") toast.Name = "ShopToast" toast.Size = UDim2.new(0, 360, 0, 40) toast.Position = UDim2.new(0.5, -180, 0.12, 0) toast.BackgroundTransparency = 0.02 toast.BackgroundColor3 = Theme.panel toast.Font = Enum.Font.Arcade toast.TextSize = 16 toast.TextColor3 = Theme.text toast.Parent = screen toast.ZIndex = 3
        local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0,0) c.Parent = toast
        local s = Instance.new("UIStroke") s.Color = Theme.stroke s.Transparency = 0.2 s.Thickness = 2 s.Parent = toast
        applyPixelText(toast, 0.84)
        ensureScanlines(toast)
    end
    toastToken += 1
    local token = toastToken
    toast.Text = text
    toast.Visible = true
    toast.BackgroundTransparency = 0.02
    task.delay(1.8, function()
        if token ~= toastToken then return end
        toast.Visible = false
    end)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(playerOrUserId, gamePassId, wasPurchased)
    local purchaserUserId = Player.UserId
    if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
        purchaserUserId = playerOrUserId.UserId
    elseif type(playerOrUserId) == "number" then
        purchaserUserId = playerOrUserId
    end
    if purchaserUserId ~= Player.UserId then
        return
    end
    if gamePassId ~= getThirdSlotGamePassId(lastProfile) then
        return
    end

    if wasPurchased then
        showToast("Third slot unlocked")
        if pendingPowerId then
            REQ_EQUIP:FireServer(pendingPowerId, THIRD_SLOT_INDEX)
        end
    end
end)

canAccessShop = function()
    if Player:GetAttribute("InMatch") == true then
        showToast(SHOP_LOCKED_MESSAGE)
        return false
    end
    return true
end

-- Handle server updates
EV_UPDATE.OnClientEvent:Connect(function(profile)
    if not profile then return end
    rebuild(profile)
    if slotPrompt.Visible then
        updateSlotPromptInfo()
    end
end)

local shopOpen = false
local function openShop()
    if shopOpen then return end
    if not canAccessShop() then return end
    shopOpen = true
    backdrop.Visible = true
    backdrop.BackgroundTransparency = 1
    modal.Visible = true
    modalScale.Scale = 0.95
    modal.BackgroundTransparency = 0.1
    TweenService:Create(backdrop, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.42 }):Play()
    TweenService:Create(modalScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
    TweenService:Create(modal, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0 }):Play()
end

local function closeShop()
    if not shopOpen then return end
    shopOpen = false
    closeSlotPrompt()
    TweenService:Create(backdrop, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
    TweenService:Create(modalScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.95 }):Play()
    TweenService:Create(modal, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 0.2 }):Play()
    task.delay(0.16, function()
        if not shopOpen then
            modal.Visible = false
            backdrop.Visible = false
        end
    end)
end

-- Toggle
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.B then
        if shopOpen then
            closeShop()
        else
            openShop()
        end
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    closeShop()
end)

Player:GetAttributeChangedSignal("InMatch"):Connect(function()
    if Player:GetAttribute("InMatch") == true and shopOpen then
        closeShop()
        showToast(SHOP_LOCKED_MESSAGE)
    end
end)

-- initial build
setActiveTab("Weapon")
