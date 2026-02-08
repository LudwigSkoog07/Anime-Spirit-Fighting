-- UIController.client: pixel-neon HUD
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- require shared modules from ReplicatedStorage
local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
if not Shared then warn("Shared modules not found in ReplicatedStorage (UIController)") return end
local Constants = require(Shared:WaitForChild("Constants"))
local CooldownService = require(Shared:WaitForChild("CooldownService"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

local BLOCKED_HIGHLIGHT_NAME = "AFS_BlockedHighlight"
local BLOCKED_MARKER_NAME = "AFS_BlockedMarker"

local Theme = {
    panel = Color3.fromRGB(17, 13, 37),
    panelMid = Color3.fromRGB(24, 18, 52),
    panelDeep = Color3.fromRGB(7, 5, 18),
    stroke = Color3.fromRGB(86, 210, 255),
    accent = Color3.fromRGB(94, 246, 255),
    accentAlt = Color3.fromRGB(200, 122, 255),
    accentHot = Color3.fromRGB(255, 102, 236),
    text = Color3.fromRGB(240, 245, 255),
    textDim = Color3.fromRGB(194, 208, 242),
    health = Color3.fromRGB(109, 246, 188),
}

local function applyPixelText(label, strokeTransparency)
    label.Font = Enum.Font.Arcade
    label.TextStrokeColor3 = Theme.panelDeep
    label.TextStrokeTransparency = strokeTransparency or 0.62
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

-- Build or reuse HUD ScreenGui
local screen = PlayerGui:FindFirstChild("AFS_HUD")
if not screen then
    screen = Instance.new("ScreenGui")
    screen.Name = "AFS_HUD"
    screen.ResetOnSpawn = false
    screen.Parent = PlayerGui
end
screen.IgnoreGuiInset = true

-- Local-only damage popups (attacker only)
local damageFolder = PlayerGui:FindFirstChild("AFS_DamagePopups")
if not damageFolder then
    damageFolder = Instance.new("Folder")
    damageFolder.Name = "AFS_DamagePopups"
    damageFolder.Parent = PlayerGui
end

-- Top-left spirit card
local hud = screen:FindFirstChild("GlassHud") or Instance.new("Frame")
hud.Name = "GlassHud"
hud.AnchorPoint = Vector2.new(0,0)
hud.Position = UDim2.new(0, 20, 0, 66)
hud.Size = UDim2.new(0, 290, 0, 128)
hud.BackgroundTransparency = 0.02
hud.BackgroundColor3 = Theme.panel
hud.BorderSizePixel = 0
hud.Parent = screen

local hudCorner = hud:FindFirstChild("Corner") or Instance.new("UICorner")
hudCorner.CornerRadius = UDim.new(0,0)
hudCorner.Name = "Corner"
hudCorner.Parent = hud

local hudStroke = hud:FindFirstChild("Stroke") or Instance.new("UIStroke")
hudStroke.Color = Theme.stroke
hudStroke.Transparency = 0.2
hudStroke.Thickness = 2
hudStroke.LineJoinMode = Enum.LineJoinMode.Miter
hudStroke.Parent = hud

local hudGrad = hud:FindFirstChild("Grad") or Instance.new("UIGradient")
applyPanelGradient(hudGrad, Theme.panel, Theme.panelDeep)
hudGrad.Parent = hud
ensureScanlines(hud)

local uiScale = hud:FindFirstChild("UIScale") or Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = hud

local hudAccent = hud:FindFirstChild("Accent")
if hudAccent then
    hudAccent:Destroy()
    hudAccent = nil
end

-- Money label
local moneyLabel = hud:FindFirstChild("MoneyLabel") or Instance.new("TextLabel")
moneyLabel.Name = "MoneyLabel"
moneyLabel.BackgroundTransparency = 1
moneyLabel.Position = UDim2.new(0.04, 0, 0.18, 0)
moneyLabel.Size = UDim2.new(1, -12, 0, 40)
moneyLabel.Font = Enum.Font.Arcade
moneyLabel.TextSize = 30
moneyLabel.TextColor3 = Theme.accent
moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
moneyLabel.Text = "$0"
moneyLabel.Parent = hud
applyPixelText(moneyLabel, 0.6)

local titleLabel = hud:FindFirstChild("TitleLabel") or Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0.04, 0, 0.02, 0)
titleLabel.Size = UDim2.new(1, -12, 0, 18)
titleLabel.Font = Enum.Font.Arcade
titleLabel.TextSize = 12
titleLabel.TextColor3 = Theme.text
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "SPIRIT ARENA"
titleLabel.Parent = hud
applyPixelText(titleLabel, 0.86)

local moneyScale = moneyLabel:FindFirstChild("UIScale") or Instance.new("UIScale")
moneyScale.Name = "UIScale"
moneyScale.Scale = 1
moneyScale.Parent = moneyLabel

-- Streak and role
local streakLabel = hud:FindFirstChild("StreakLabel") or Instance.new("TextLabel")
streakLabel.Name = "StreakLabel"
streakLabel.BackgroundTransparency = 1
streakLabel.Position = UDim2.new(0.04, 0, 0.62, 0)
streakLabel.Size = UDim2.new(0.6, 0, 0, 18)
streakLabel.Font = Enum.Font.Arcade
streakLabel.TextSize = 14
streakLabel.TextColor3 = Theme.text
streakLabel.TextXAlignment = Enum.TextXAlignment.Left
streakLabel.Text = "Streak: 0"
streakLabel.Parent = hud
applyPixelText(streakLabel, 0.86)

local roleBadge = hud:FindFirstChild("RoleBadge") or Instance.new("TextLabel")
roleBadge.Name = "RoleBadge"
roleBadge.AnchorPoint = Vector2.new(1,0)
roleBadge.Position = UDim2.new(0.98, 0, 0.58, 0)
roleBadge.BackgroundTransparency = 0
roleBadge.BackgroundColor3 = Theme.panelDeep
roleBadge.Size = UDim2.new(0.38, -10, 0, 22)
roleBadge.Font = Enum.Font.Arcade
roleBadge.TextSize = 14
roleBadge.TextColor3 = Theme.text
roleBadge.TextXAlignment = Enum.TextXAlignment.Center
roleBadge.Text = "Spectator"
roleBadge.Parent = hud
local roleCorner = Instance.new("UICorner") roleCorner.CornerRadius = UDim.new(0,0) roleCorner.Parent = roleBadge
local roleStroke = Instance.new("UIStroke") roleStroke.Color = Theme.stroke roleStroke.Transparency = 0.2 roleStroke.Thickness = 2 roleStroke.Parent = roleBadge
applyPixelText(roleBadge, 0.8)

-- Top-center role banner
local roleBanner = screen:FindFirstChild("AFS_RoleBanner") or Instance.new("Frame")
roleBanner.Name = "AFS_RoleBanner"
roleBanner.AnchorPoint = Vector2.new(0.5, 0)
roleBanner.Position = UDim2.new(0.5, 0, 0, 12)
roleBanner.Size = UDim2.new(0, 420, 0, 54)
roleBanner.BackgroundColor3 = Theme.panel
roleBanner.BackgroundTransparency = 0.02
roleBanner.Visible = false
roleBanner.Parent = screen
local roleBannerCorner = Instance.new("UICorner") roleBannerCorner.CornerRadius = UDim.new(0, 0) roleBannerCorner.Parent = roleBanner
local roleBannerStroke = Instance.new("UIStroke") roleBannerStroke.Color = Theme.stroke roleBannerStroke.Transparency = 0.2 roleBannerStroke.Thickness = 2 roleBannerStroke.Parent = roleBanner
local roleBannerGrad = Instance.new("UIGradient") applyPanelGradient(roleBannerGrad, Theme.panel, Theme.panelDeep) roleBannerGrad.Parent = roleBanner
ensureScanlines(roleBanner)

local roleTitle = roleBanner:FindFirstChild("Title") or Instance.new("TextLabel")
roleTitle.Name = "Title"
roleTitle.BackgroundTransparency = 1
roleTitle.Position = UDim2.new(0, 12, 0, 4)
roleTitle.Size = UDim2.new(1, -24, 0, 24)
roleTitle.Font = Enum.Font.Arcade
roleTitle.TextSize = 20
roleTitle.TextColor3 = Theme.text
roleTitle.TextXAlignment = Enum.TextXAlignment.Center
roleTitle.Text = ""
roleTitle.Parent = roleBanner
applyPixelText(roleTitle, 0.78)

local roleSub = roleBanner:FindFirstChild("Sub") or Instance.new("TextLabel")
roleSub.Name = "Sub"
roleSub.BackgroundTransparency = 1
roleSub.Position = UDim2.new(0, 12, 0, 28)
roleSub.Size = UDim2.new(1, -24, 0, 18)
roleSub.Font = Enum.Font.Arcade
roleSub.TextSize = 12
roleSub.TextColor3 = Theme.text
roleSub.TextXAlignment = Enum.TextXAlignment.Center
roleSub.Text = ""
roleSub.Parent = roleBanner
applyPixelText(roleSub, 0.88)

-- =========================
-- Bottom HUD (SEPARATE FRAMES, NO BIG BAR)
-- =========================

-- Utility: destroy old hintBar if it exists from previous version
local oldHintBar = screen:FindFirstChild("AFS_Hints")
if oldHintBar then oldHintBar:Destroy() end

-- SHOP PANEL (bottom-left)
local shopPanel = screen:FindFirstChild("AFS_ShopPanel") or Instance.new("Frame")
shopPanel.Name = "AFS_ShopPanel"
shopPanel.AnchorPoint = Vector2.new(0, 1)
shopPanel.Position = UDim2.new(0, 20, 1, -20)
shopPanel.Size = UDim2.new(0, 300, 0, 36)
shopPanel.BackgroundColor3 = Theme.panel
shopPanel.BackgroundTransparency = 0.02
shopPanel.BorderSizePixel = 0
shopPanel.Parent = screen
local shopCorner = shopPanel:FindFirstChild("Corner") or Instance.new("UICorner") shopCorner.Name="Corner" shopCorner.CornerRadius = UDim.new(0,0) shopCorner.Parent = shopPanel
local shopStroke = shopPanel:FindFirstChild("Stroke") or Instance.new("UIStroke") shopStroke.Name="Stroke" shopStroke.Color = Theme.stroke shopStroke.Transparency = 0.2 shopStroke.Thickness = 2 shopStroke.Parent = shopPanel
local shopGrad = shopPanel:FindFirstChild("Grad") or Instance.new("UIGradient") shopGrad.Name="Grad" applyPanelGradient(shopGrad, Theme.panel, Theme.panelDeep) shopGrad.Parent = shopPanel
ensureScanlines(shopPanel)

local hintLabel = shopPanel:FindFirstChild("AFS_HintLabel") or Instance.new("TextLabel")
hintLabel.Name = "AFS_HintLabel"
hintLabel.BackgroundTransparency = 1
hintLabel.Size = UDim2.new(1, -24, 1, 0)
hintLabel.Position = UDim2.new(0, 12, 0, 0)
hintLabel.Font = Enum.Font.Arcade
hintLabel.TextSize = 14
hintLabel.TextColor3 = Theme.text
hintLabel.Text = "B - Shop"
hintLabel.TextXAlignment = Enum.TextXAlignment.Left
hintLabel.Parent = shopPanel
applyPixelText(hintLabel, 0.86)

-- HEALTH CLUSTER (bottom-center) holds posture + HP
local healthCluster = screen:FindFirstChild("AFS_HealthCluster") or Instance.new("Frame")
healthCluster.Name = "AFS_HealthCluster"
healthCluster.AnchorPoint = Vector2.new(0.5, 1)
healthCluster.Position = UDim2.new(0.5, 0, 1, -20)
healthCluster.Size = UDim2.new(0, 190, 0, 46)
healthCluster.BackgroundTransparency = 1
healthCluster.BorderSizePixel = 0
healthCluster.Parent = screen

-- Posture bar (top, thin)
local postureFrame = healthCluster:FindFirstChild("PostureBar") or Instance.new("Frame")
postureFrame.Name = "PostureBar"
postureFrame.Position = UDim2.new(0, 10, 0, 0)
postureFrame.Size = UDim2.new(1, -20, 0, 10)
postureFrame.BackgroundColor3 = Theme.panelDeep
postureFrame.BackgroundTransparency = 0.04
postureFrame.BorderSizePixel = 0
postureFrame.Parent = healthCluster
local postureCorner = postureFrame:FindFirstChild("Corner") or Instance.new("UICorner")
postureCorner.Name = "Corner"
postureCorner.CornerRadius = UDim.new(0,0)
postureCorner.Parent = postureFrame
local postureStroke = postureFrame:FindFirstChild("Stroke") or Instance.new("UIStroke")
postureStroke.Name = "Stroke"
postureStroke.Color = Theme.stroke
postureStroke.Transparency = 0.25
postureStroke.Thickness = 2
postureStroke.Parent = postureFrame
local postureFill = postureFrame:FindFirstChild("Fill") or Instance.new("Frame")
postureFill.Name = "Fill"
postureFill.Size = UDim2.new(1, 0, 1, 0)
postureFill.BackgroundColor3 = Theme.accentAlt
postureFill.BorderSizePixel = 0
postureFill.Parent = postureFrame

-- Health bar (bottom, bigger)
local healthFrame = healthCluster:FindFirstChild("HealthBar") or Instance.new("Frame")
healthFrame.Name = "HealthBar"
healthFrame.Position = UDim2.new(0, 10, 0, 14)
healthFrame.Size = UDim2.new(1, -20, 0, 30)
healthFrame.BackgroundColor3 = Theme.panelDeep
healthFrame.BackgroundTransparency = 0.04
healthFrame.ClipsDescendants = true
healthFrame.BorderSizePixel = 0
healthFrame.Parent = healthCluster
local healthCorner = healthFrame:FindFirstChild("Corner") or Instance.new("UICorner")
healthCorner.Name = "Corner"
healthCorner.CornerRadius = UDim.new(0,0)
healthCorner.Parent = healthFrame
local healthStroke = healthFrame:FindFirstChild("Stroke") or Instance.new("UIStroke")
healthStroke.Name = "Stroke"
healthStroke.Color = Theme.stroke
healthStroke.Transparency = 0.25
healthStroke.Thickness = 2
healthStroke.Parent = healthFrame

local healthFill = healthFrame:FindFirstChild("Fill") or Instance.new("Frame")
healthFill.Name = "Fill"
healthFill.Size = UDim2.new(1, 0, 1, 0)
healthFill.BackgroundColor3 = Theme.health
healthFill.BorderSizePixel = 0
healthFill.Parent = healthFrame
local healthFillCorner = healthFill:FindFirstChild("Corner") or Instance.new("UICorner")
healthFillCorner.Name = "Corner"
healthFillCorner.CornerRadius = UDim.new(0,0)
healthFillCorner.Parent = healthFill

local healthText = healthFrame:FindFirstChild("Text") or Instance.new("TextLabel")
healthText.Name = "Text"
healthText.BackgroundTransparency = 1
healthText.Size = UDim2.new(1, 0, 1, 0)
healthText.Font = Enum.Font.Arcade
healthText.TextSize = 14
healthText.TextColor3 = Theme.text
healthText.TextXAlignment = Enum.TextXAlignment.Center
healthText.Text = "HP 100/100"
healthText.Parent = healthFrame
applyPixelText(healthText, 0.86)

-- ABILITY PANEL (bottom-right)
local abilityPanel = screen:FindFirstChild("AFS_AbilityPanel") or Instance.new("Frame")
abilityPanel.Name = "AFS_AbilityPanel"
abilityPanel.AnchorPoint = Vector2.new(1, 1)
abilityPanel.Position = UDim2.new(1, -20, 1, -20)
abilityPanel.Size = UDim2.new(0, 320, 0, 36)
abilityPanel.BackgroundColor3 = Theme.panel
abilityPanel.BackgroundTransparency = 0.02
abilityPanel.BorderSizePixel = 0
abilityPanel.Parent = screen
local abilityCorner = abilityPanel:FindFirstChild("Corner") or Instance.new("UICorner") abilityCorner.Name="Corner" abilityCorner.CornerRadius = UDim.new(0,0) abilityCorner.Parent = abilityPanel
local abilityStroke = abilityPanel:FindFirstChild("Stroke") or Instance.new("UIStroke") abilityStroke.Name="Stroke" abilityStroke.Color = Theme.stroke abilityStroke.Transparency = 0.2 abilityStroke.Thickness = 2 abilityStroke.Parent = abilityPanel
local abilityGrad = abilityPanel:FindFirstChild("Grad") or Instance.new("UIGradient") abilityGrad.Name="Grad" applyPanelGradient(abilityGrad, Theme.panel, Theme.panelDeep) abilityGrad.Parent = abilityPanel
ensureScanlines(abilityPanel)

local abilitySlots = abilityPanel:FindFirstChild("AbilitySlots") or Instance.new("Frame")
abilitySlots.Name = "AbilitySlots"
abilitySlots.BackgroundTransparency = 1
abilitySlots.Size = UDim2.new(1, -12, 1, -8)
abilitySlots.Position = UDim2.new(0, 6, 0, 4)
abilitySlots.Parent = abilityPanel

local slotLayout = abilitySlots:FindFirstChild("Layout") or Instance.new("UIListLayout")
slotLayout.Name = "Layout"
slotLayout.FillDirection = Enum.FillDirection.Horizontal
slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotLayout.Padding = UDim.new(0, 8)
slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
slotLayout.Parent = abilitySlots

local function ensureAbilitySlot(name, order, keyText)
    local slot = abilitySlots:FindFirstChild(name) or Instance.new("Frame")
    slot.Name = name
    slot.LayoutOrder = order
    slot.Size = UDim2.new(0, 96, 0, 28)
    slot.BackgroundColor3 = Theme.panelDeep
    slot.BackgroundTransparency = 0.04
    slot.BorderSizePixel = 0
    slot.ClipsDescendants = true
    slot.Parent = abilitySlots

    local corner = slot:FindFirstChild("Corner") or Instance.new("UICorner")
    corner.Name = "Corner"
    corner.CornerRadius = UDim.new(0,0)
    corner.Parent = slot

    local stroke = slot:FindFirstChild("Stroke") or Instance.new("UIStroke")
    stroke.Name = "Stroke"
    stroke.Color = Theme.stroke
    stroke.Transparency = 0.25
    stroke.Thickness = 2
    stroke.LineJoinMode = Enum.LineJoinMode.Miter
    stroke.Parent = slot

    local scale = slot:FindFirstChild("UIScale") or Instance.new("UIScale")
    scale.Name = "UIScale"
    scale.Scale = 1
    scale.Parent = slot

    local cooldownFill = slot:FindFirstChild("CooldownFill") or Instance.new("Frame")
    cooldownFill.Name = "CooldownFill"
    cooldownFill.AnchorPoint = Vector2.new(0, 1)
    cooldownFill.Position = UDim2.new(0, 0, 1, 0)
    cooldownFill.Size = UDim2.new(1, 0, 0, 0)
    cooldownFill.BackgroundColor3 = Theme.accentHot
    cooldownFill.BackgroundTransparency = 0.55
    cooldownFill.BorderSizePixel = 0
    cooldownFill.ZIndex = 1
    cooldownFill.Visible = false
    cooldownFill.Parent = slot
    local cooldownFillCorner = cooldownFill:FindFirstChild("Corner") or Instance.new("UICorner")
    cooldownFillCorner.Name = "Corner"
    cooldownFillCorner.CornerRadius = UDim.new(0, 0)
    cooldownFillCorner.Parent = cooldownFill

    local key = slot:FindFirstChild("Key") or Instance.new("TextLabel")
    key.Name = "Key"
    key.BackgroundTransparency = 1
    key.Position = UDim2.new(0, 6, 0, 2)
    key.Size = UDim2.new(0, 16, 1, -4)
    key.Font = Enum.Font.Arcade
    key.TextSize = 14
    key.TextColor3 = Theme.accent
    key.TextXAlignment = Enum.TextXAlignment.Left
    key.Text = keyText
    key.ZIndex = 3
    key.Parent = slot
    applyPixelText(key, 0.88)

    local nameLabel = slot:FindFirstChild("Name") or Instance.new("TextLabel")
    nameLabel.Name = "Name"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Position = UDim2.new(0, 26, 0, 3)
    nameLabel.Size = UDim2.new(1, -30, 0, 12)
    nameLabel.Font = Enum.Font.Arcade
    nameLabel.TextSize = 11
    nameLabel.TextColor3 = Theme.text
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextYAlignment = Enum.TextYAlignment.Top
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Text = "-"
    nameLabel.ZIndex = 3
    nameLabel.Parent = slot
    applyPixelText(nameLabel, 0.88)

    local cooldownLabel = slot:FindFirstChild("CooldownLabel") or Instance.new("TextLabel")
    cooldownLabel.Name = "CooldownLabel"
    cooldownLabel.BackgroundTransparency = 1
    cooldownLabel.Position = UDim2.new(0, 26, 0, 15)
    cooldownLabel.Size = UDim2.new(1, -30, 0, 11)
    cooldownLabel.Font = Enum.Font.Arcade
    cooldownLabel.TextSize = 11
    cooldownLabel.TextColor3 = Theme.accent
    cooldownLabel.TextXAlignment = Enum.TextXAlignment.Left
    cooldownLabel.TextYAlignment = Enum.TextYAlignment.Bottom
    cooldownLabel.Text = ""
    cooldownLabel.ZIndex = 3
    cooldownLabel.Parent = slot
    applyPixelText(cooldownLabel, 0.88)

    return {
        frame = slot,
        scale = scale,
        stroke = stroke,
        keyLabel = key,
        nameLabel = nameLabel,
        cooldownFill = cooldownFill,
        cooldownLabel = cooldownLabel,
    }
end

-- Recreate ability slot refs (same variable names your script uses later)
abilitySlotE = ensureAbilitySlot("SlotE", 1, "E")
abilitySlotR = ensureAbilitySlot("SlotR", 2, "R")
abilitySlotT = ensureAbilitySlot("SlotT", 3, "T")


local hintLabel = shopPanel:FindFirstChild("AFS_HintLabel") or Instance.new("TextLabel")
hintLabel.Name = "AFS_HintLabel"
hintLabel.BackgroundTransparency = 1
hintLabel.Size = UDim2.new(1, -24, 1, 0)
hintLabel.Position = UDim2.new(0, 12, 0, 0)
hintLabel.Font = Enum.Font.Arcade
hintLabel.TextSize = 14
hintLabel.TextColor3 = Theme.text
hintLabel.Text = "B - Shop"
hintLabel.TextXAlignment = Enum.TextXAlignment.Left
hintLabel.Parent = shopPanel
applyPixelText(hintLabel, 0.86)

-- Ability cooldown label (small, bottom-left)
local cooldownLabel = screen:FindFirstChild("AFS_Cooldown") or Instance.new("TextLabel")
cooldownLabel.Name = "AFS_Cooldown"
cooldownLabel.AnchorPoint = Vector2.new(0.5, 1)
cooldownLabel.Position = UDim2.new(0.5, 0, 1, -70)
cooldownLabel.Size = UDim2.new(0, 280, 0, 22)
cooldownLabel.BackgroundTransparency = 1
cooldownLabel.Font = Enum.Font.Arcade
cooldownLabel.TextSize = 14
cooldownLabel.TextColor3 = Theme.text
cooldownLabel.Text = ""
cooldownLabel.Parent = screen
applyPixelText(cooldownLabel, 0.9)

local abilityPopup = screen:FindFirstChild("AFS_AbilityPopup") or Instance.new("TextLabel")
abilityPopup.Name = "AFS_AbilityPopup"
abilityPopup.AnchorPoint = Vector2.new(0.5, 0)
abilityPopup.Position = UDim2.new(0.5, 0, 0, 88)
abilityPopup.Size = UDim2.new(0, 360, 0, 34)
abilityPopup.BackgroundColor3 = Theme.panel
abilityPopup.BackgroundTransparency = 0.03
abilityPopup.BorderSizePixel = 0
abilityPopup.Font = Enum.Font.Arcade
abilityPopup.TextSize = 18
abilityPopup.TextColor3 = Theme.accentHot
abilityPopup.TextStrokeTransparency = 0.72
abilityPopup.Text = ""
abilityPopup.Visible = false
abilityPopup.Parent = screen
local abilityPopupCorner = abilityPopup:FindFirstChild("Corner") or Instance.new("UICorner")
abilityPopupCorner.Name = "Corner"
abilityPopupCorner.CornerRadius = UDim.new(0, 0)
abilityPopupCorner.Parent = abilityPopup
local abilityPopupStroke = abilityPopup:FindFirstChild("Stroke") or Instance.new("UIStroke")
abilityPopupStroke.Name = "Stroke"
abilityPopupStroke.Color = Theme.stroke
abilityPopupStroke.Transparency = 0.2
abilityPopupStroke.Thickness = 2
abilityPopupStroke.Parent = abilityPopup
ensureScanlines(abilityPopup)
applyPixelText(abilityPopup, 0.7)

local timeSkipOverlay = screen:FindFirstChild("AFS_TimeSkipOverlay") or Instance.new("Frame")
timeSkipOverlay.Name = "AFS_TimeSkipOverlay"
timeSkipOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
timeSkipOverlay.Position = UDim2.new(0.5, 0, 0.5, 0)
timeSkipOverlay.Size = UDim2.new(1, 0, 1, 0)
timeSkipOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
timeSkipOverlay.BackgroundTransparency = 1
timeSkipOverlay.BorderSizePixel = 0
timeSkipOverlay.Visible = false
timeSkipOverlay.ZIndex = 8
timeSkipOverlay.Parent = screen

local sandevistanOverlay = screen:FindFirstChild("AFS_SandevistanOverlay") or Instance.new("Frame")
sandevistanOverlay.Name = "AFS_SandevistanOverlay"
sandevistanOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
sandevistanOverlay.Position = UDim2.new(0.5, 0, 0.5, 0)
sandevistanOverlay.Size = UDim2.new(1, 0, 1, 0)
sandevistanOverlay.BackgroundColor3 = Color3.fromRGB(6, 255, 155)
sandevistanOverlay.BackgroundTransparency = 1
sandevistanOverlay.BorderSizePixel = 0
sandevistanOverlay.Visible = false
sandevistanOverlay.ZIndex = 7
sandevistanOverlay.Parent = screen

-- remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotes then warn("Remotes folder not found (UIController)") return end
local EV_ABILITY_FX = remotes:WaitForChild(Constants.RemoteNames.AbilityFx, 10)
local EV_SHOP = remotes:WaitForChild(Constants.RemoteNames.ShopUpdate, 10)
local EV_ECONOMY = remotes:WaitForChild(Constants.RemoteNames.EconomyUpdate, 10)
local EV_STATE_UPDATE = remotes:WaitForChild(Constants.RemoteNames.MatchStateUpdate, 10)
local EV_DAMAGE_POPUP = remotes:WaitForChild(Constants.RemoteNames.DamagePopup, 10)

-- local profile cache
local localProfile = {}
local currentBlocked = {}
local currentState = nil
local isSpiritLocal = false
local currentSpiritUserId = nil
local waitingForPlayers = false
local trackedCooldowns = {}
local lastActivatedAbilityId = nil

local SPIRIT_HIGHLIGHT_NAME = "AFS_SpiritHighlight"
local TIME_SKIP_CC_NAME = "AFS_TimeSkipColorCorrection"
local TIME_SKIP_BLUR_NAME = "AFS_TimeSkipBlur"
local TIME_SKIP_SOUND_NAME = "AFS_TimeSkipSfx"
local TIME_SKIP_SOUND_ID = "rbxassetid://123891403807633"
local SANDEVISTAN_FX_FOLDER_NAME = "AFS_SandevistanFx"
local timeSkipFxToken = 0
local timeSkipFxTweens = {}
local sandevistanFxTokenByCaster = {}

local function titleCase(text)
    return (text:gsub("(%w)(%w*)", function(a, b) return a:upper() .. b:lower() end))
end

local function getAbilityName(id)
    local it = ItemConfig.Get(id)
    if it and it.name then return it.name end
    return titleCase((id or ""):gsub("_", " "))
end

local function getEquippedAbility(profile, slotIndex)
    return profile and profile.equippedPowers and profile.equippedPowers[slotIndex] or nil
end

local function getAbilityCooldownTotal(abilityId)
    if not abilityId then return 0 end
    if trackedCooldowns[abilityId] then
        return trackedCooldowns[abilityId]
    end
    local item = ItemConfig.Get(abilityId)
    if item and type(item.cooldown) == "number" then
        return item.cooldown
    end
    return 0
end

local function getPopupColorForAbility(abilityId)
    if abilityId == "kaioken" then
        return Color3.fromRGB(255, 120, 105)
    elseif abilityId == "flash_step" then
        return Color3.fromRGB(90, 220, 255)
    elseif abilityId == "reality_break" then
        return Color3.fromRGB(90, 235, 255)
    end
    return Theme.accent
end

local function pulseAbilitySlot(slotInfo, color)
    if not slotInfo then return end
    slotInfo.stroke.Color = color or Theme.accent
    slotInfo.stroke.Transparency = 0.18
    local grow = TweenService:Create(slotInfo.scale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.08 })
    local shrink = TweenService:Create(slotInfo.scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 })
    task.spawn(function()
        grow:Play()
        grow.Completed:Wait()
        shrink:Play()
    end)
end

local function cancelTimeSkipTweens()
    for _, tween in ipairs(timeSkipFxTweens) do
        if tween then
            pcall(function()
                tween:Cancel()
            end)
        end
    end
    table.clear(timeSkipFxTweens)
end

local function ensureTimeSkipColorCorrection()
    local fx = Lighting:FindFirstChild(TIME_SKIP_CC_NAME)
    if fx and fx:IsA("ColorCorrectionEffect") then
        return fx
    end
    if fx then
        fx:Destroy()
    end
    local cc = Instance.new("ColorCorrectionEffect")
    cc.Name = TIME_SKIP_CC_NAME
    cc.Enabled = false
    cc.Brightness = 0
    cc.Contrast = 0
    cc.Saturation = 0
    cc.TintColor = Color3.fromRGB(255, 255, 255)
    cc.Parent = Lighting
    return cc
end

local function ensureTimeSkipBlur()
    local fx = Lighting:FindFirstChild(TIME_SKIP_BLUR_NAME)
    if fx and fx:IsA("BlurEffect") then
        return fx
    end
    if fx then
        fx:Destroy()
    end
    local blur = Instance.new("BlurEffect")
    blur.Name = TIME_SKIP_BLUR_NAME
    blur.Enabled = false
    blur.Size = 0
    blur.Parent = Lighting
    return blur
end

local function playTimeSkipVisual(freezeDuration, isLocalCaster, isLocalTarget)
    timeSkipFxToken += 1
    local token = timeSkipFxToken
    cancelTimeSkipTweens()

    local duration = math.clamp(tonumber(freezeDuration) or 0.3, 0.12, 0.8)
    local peakDark = 0.3
    local peakBlur = 10
    local peakContrast = 0.28
    if isLocalCaster then
        peakDark = 0.35
        peakBlur = 13
        peakContrast = 0.34
    elseif isLocalTarget then
        peakDark = 0.42
        peakBlur = 16
        peakContrast = 0.4
    end

    local cc = ensureTimeSkipColorCorrection()
    local blur = ensureTimeSkipBlur()
    cc.Enabled = true
    cc.Brightness = 0
    cc.Contrast = 0
    cc.Saturation = 0
    cc.TintColor = Color3.fromRGB(255, 255, 255)
    blur.Enabled = true
    blur.Size = 0
    timeSkipOverlay.Visible = true
    timeSkipOverlay.BackgroundTransparency = 1

    local inTweenInfo = TweenInfo.new(math.max(0.05, duration * 0.35), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local overlayIn = TweenService:Create(timeSkipOverlay, inTweenInfo, { BackgroundTransparency = 1 - peakDark })
    local colorIn = TweenService:Create(cc, inTweenInfo, {
        Saturation = -1,
        Contrast = peakContrast,
        Brightness = -0.06,
        TintColor = Color3.fromRGB(178, 178, 178),
    })
    local blurIn = TweenService:Create(blur, inTweenInfo, { Size = peakBlur })
    table.insert(timeSkipFxTweens, overlayIn)
    table.insert(timeSkipFxTweens, colorIn)
    table.insert(timeSkipFxTweens, blurIn)
    overlayIn:Play()
    colorIn:Play()
    blurIn:Play()

    task.delay(duration, function()
        if token ~= timeSkipFxToken then
            return
        end

        local outTweenInfo = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        local overlayOut = TweenService:Create(timeSkipOverlay, outTweenInfo, { BackgroundTransparency = 1 })
        local colorOut = TweenService:Create(cc, outTweenInfo, {
            Saturation = 0,
            Contrast = 0,
            Brightness = 0,
            TintColor = Color3.fromRGB(255, 255, 255),
        })
        local blurOut = TweenService:Create(blur, outTweenInfo, { Size = 0 })
        table.insert(timeSkipFxTweens, overlayOut)
        table.insert(timeSkipFxTweens, colorOut)
        table.insert(timeSkipFxTweens, blurOut)

        overlayOut:Play()
        colorOut:Play()
        blurOut:Play()
        overlayOut.Completed:Connect(function()
            if token ~= timeSkipFxToken then
                return
            end
            timeSkipOverlay.Visible = false
            cc.Enabled = false
            blur.Enabled = false
            table.clear(timeSkipFxTweens)
        end)
    end)
end

local function playTimeSkipSound()
    local sound = SoundService:FindFirstChild(TIME_SKIP_SOUND_NAME)
    if sound and not sound:IsA("Sound") then
        sound:Destroy()
        sound = nil
    end

    if not sound then
        sound = Instance.new("Sound")
        sound.Name = TIME_SKIP_SOUND_NAME
        sound.SoundId = TIME_SKIP_SOUND_ID
        sound.Volume = 1
        sound.RollOffMode = Enum.RollOffMode.InverseTapered
        sound.Parent = SoundService
    else
        sound.SoundId = TIME_SKIP_SOUND_ID
    end

    sound.TimePosition = 0
    sound:Play()
end

local function getOrCreateFxFolder(name)
    local folder = Workspace:FindFirstChild(name)
    if folder and folder:IsA("Folder") then
        return folder
    end
    if folder then
        folder:Destroy()
    end
    folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = Workspace
    return folder
end

local SANDEVISTAN_MAX_CLONES = 15
local SANDEVISTAN_SNAPSHOT_INTERVAL = 0.06
local SANDEVISTAN_CLONE_LIFETIME = 1.55
local SANDEVISTAN_TRAIL_OFFSET = 0.48
local SANDEVISTAN_CLONE_START_TRANSP = 0.35
local SANDEVISTAN_CLONE_END_TRANSP = 0.98
local SANDEVISTAN_OUTLINE_COLOR = Color3.fromRGB(255, 220, 255)
local SANDEVISTAN_FOV_TARGET = 102
local SANDEVISTAN_FOV_IN_TIME = 0.08
local SANDEVISTAN_FOV_OUT_TIME = 0.18
local SANDEVISTAN_FOV_JITTER_AMPL = 0.18
local SANDEVISTAN_FOV_JITTER_FREQ = 5
local SANDEVISTAN_OVERLAY_ALPHA = 0.28
local SANDEVISTAN_OVERLAY_IN_TIME = 0.12
local SANDEVISTAN_OVERLAY_OUT_TIME = 0.14
local SANDEVISTAN_DUPLICATE_WINDOW = 0.12
local SANDEVISTAN_SFX_ACTIVATE_ID = "rbxassetid://71484187008173"
local SANDEVISTAN_SFX_DEACTIVATE_ID = "rbxassetid://105347748753186"
local SANDEVISTAN_SFX_VOLUME = 0.9
local SANDEVISTAN_SFX_MAX_DISTANCE = 120

local SANDEVISTAN_PALETTE = {
    Color3.fromRGB(255, 255, 0),
    Color3.fromRGB(255, 165, 0),
    Color3.fromRGB(255, 0, 0),
    Color3.fromRGB(255, 40, 160),
    Color3.fromRGB(150, 0, 255),
    Color3.fromRGB(0, 0, 255),
    Color3.fromRGB(0, 255, 255),
    Color3.fromRGB(0, 255, 0),
}
local SANDEVISTAN_CYCLE_SECONDS = 8.0
local SANDEVISTAN_STEP_TIME = 0.03

local sandevistanStateByCaster = {}
local sandevistanCameraConn = nil
local sandevistanCameraToken = 0
local sandevistanCameraBaseFov = nil
local sandevistanOverlayActiveCount = 0
local sandevistanOverlayTween = nil
local sandevistanLastEventAtByCaster = {}

local function easeOutCubic(t)
    return 1 - (1 - t) ^ 3
end

local function paletteColorAt(t)
    local n = #SANDEVISTAN_PALETTE
    if n <= 0 then
        return Color3.new(1, 1, 1)
    end
    local x = (t % 1) * n
    local i = math.clamp(math.floor(x) + 1, 1, n)
    local j = (i % n) + 1
    local a = x - math.floor(x)
    return SANDEVISTAN_PALETTE[i]:Lerp(SANDEVISTAN_PALETTE[j], a)
end

local function trailColorForIndex(index, count, nowTime)
    local timePhase = ((nowTime / SANDEVISTAN_CYCLE_SECONDS) % 1)
    local stackFrac = (index - 1) / math.max(1, count - 1)
    local phase = (timePhase + (1 - stackFrac) * 0.15) % 1
    return paletteColorAt(phase)
end

local function setSandevistanOverlayActive(active)
    if active then
        sandevistanOverlayActiveCount += 1
    else
        if sandevistanOverlayActiveCount > 0 then
            sandevistanOverlayActiveCount -= 1
        end
    end

    if sandevistanOverlayTween then
        pcall(function()
            sandevistanOverlayTween:Cancel()
        end)
        sandevistanOverlayTween = nil
    end

    if sandevistanOverlayActiveCount > 0 then
        sandevistanOverlay.Visible = true
        sandevistanOverlayTween = TweenService:Create(
            sandevistanOverlay,
            TweenInfo.new(SANDEVISTAN_OVERLAY_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 1 - SANDEVISTAN_OVERLAY_ALPHA }
        )
        sandevistanOverlayTween:Play()
    else
        sandevistanOverlayActiveCount = 0
        sandevistanOverlayTween = TweenService:Create(
            sandevistanOverlay,
            TweenInfo.new(SANDEVISTAN_OVERLAY_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { BackgroundTransparency = 1 }
        )
        sandevistanOverlayTween:Play()
        sandevistanOverlayTween.Completed:Connect(function()
            if sandevistanOverlayActiveCount <= 0 then
                sandevistanOverlay.Visible = false
            end
        end)
    end
end

local function getModelRoot(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("LowerTorso")
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function getLiveCharacterParts(character)
    local parts = {}
    if not character then
        return parts
    end
    for _, inst in ipairs(character:GetDescendants()) do
        if inst:IsA("BasePart") then
            table.insert(parts, inst)
        end
    end
    return parts
end

local function forceNoCollide(part)
    if not part or not part:IsA("BasePart") then
        return
    end
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Massless = true
    part.CastShadow = false
end

local function playSandevistanSoundAtCharacter(character, soundId, name)
    local root = character and getModelRoot(character)
    if not root or not soundId or soundId == "" then
        return
    end

    local sound = Instance.new("Sound")
    sound.Name = name
    sound.SoundId = soundId
    sound.Volume = SANDEVISTAN_SFX_VOLUME
    sound.RollOffMode = Enum.RollOffMode.InverseTapered
    sound.RollOffMaxDistance = SANDEVISTAN_SFX_MAX_DISTANCE
    sound.Parent = root
    sound:Play()
    Debris:AddItem(sound, 4)
end

local function sanitizeSandevistanClone(model, sourceCharacter)
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("Script")
            or inst:IsA("LocalScript")
            or inst:IsA("ModuleScript")
            or inst:IsA("Tool")
        then
            inst:Destroy()
        elseif inst:IsA("BasePart") then
            forceNoCollide(inst)
            inst.Transparency = SANDEVISTAN_CLONE_START_TRANSP
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            inst.Transparency = SANDEVISTAN_CLONE_START_TRANSP
        end
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then
            animator:Destroy()
        end
        hum.AutoRotate = false
        hum.PlatformStand = true
        hum.BreakJointsOnDeath = false
        hum.Health = 0

        local cloneRoot = model:FindFirstChild("HumanoidRootPart")
        if cloneRoot and cloneRoot:IsA("BasePart") then
            cloneRoot.Anchored = true
        end
    end

    local hl = model:FindFirstChild("CloneTint")
    if not hl or not hl:IsA("Highlight") then
        hl = Instance.new("Highlight")
        hl.Name = "CloneTint"
        hl.Adornee = model
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillColor = Color3.new(1, 0, 1)
        hl.OutlineColor = SANDEVISTAN_OUTLINE_COLOR
        hl.FillTransparency = 0.25
        hl.OutlineTransparency = 0.25
        hl.Parent = model
    end

    local liveParts = getLiveCharacterParts(sourceCharacter)
    if #liveParts > 0 then
        for _, inst in ipairs(model:GetDescendants()) do
            if inst:IsA("BasePart") then
                for _, lp in ipairs(liveParts) do
                    if lp ~= inst and lp.Parent then
                        local ncc = Instance.new("NoCollisionConstraint")
                        ncc.Part0 = inst
                        ncc.Part1 = lp
                        ncc.Parent = inst
                    end
                end
            end
        end
    end
end

local function buildSandevistanClone(character, root, folder)
    if not character or not root or not root.Parent or not folder then
        return nil
    end

    local oldArchivable = character.Archivable
    character.Archivable = true
    local ok, clone = pcall(function()
        return character:Clone()
    end)
    if character and character.Parent then
        character.Archivable = oldArchivable
    end

    if not ok or not clone then
        return nil
    end

    clone.Name = "AFS_SandevistanAfterimage"
    clone.Parent = folder
    clone:PivotTo(root.CFrame * CFrame.new(0, 0, -SANDEVISTAN_TRAIL_OFFSET))
    sanitizeSandevistanClone(clone, character)
    return clone
end

local function snapshotSandevistanClone(state, character, root, folder)
    local clone = buildSandevistanClone(character, root, folder)
    if not clone then
        return
    end

    table.insert(state.clones, {
        model = clone,
        born = os.clock(),
    })

    if #state.clones > SANDEVISTAN_MAX_CLONES then
        local old = table.remove(state.clones, 1)
        if old and old.model and old.model.Parent then
            old.model:Destroy()
        end
    end
end

local function updateSandevistanClones(state)
    local now = os.clock()
    local i = 1
    while i <= #state.clones do
        local rec = state.clones[i]
        local model = rec and rec.model
        if not model or not model.Parent then
            table.remove(state.clones, i)
        else
            local t = math.clamp((now - rec.born) / SANDEVISTAN_CLONE_LIFETIME, 0, 1)
            local eased = easeOutCubic(t)
            local alpha = SANDEVISTAN_CLONE_START_TRANSP + (SANDEVISTAN_CLONE_END_TRANSP - SANDEVISTAN_CLONE_START_TRANSP) * eased
            local tint = trailColorForIndex(i, #state.clones, now)
            for _, inst in ipairs(model:GetDescendants()) do
                if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
                    inst.Transparency = alpha
                elseif inst:IsA("Highlight") and inst.Name == "CloneTint" then
                    inst.FillColor = tint
                    inst.OutlineColor = SANDEVISTAN_OUTLINE_COLOR
                    inst.FillTransparency = 0.25 + (1 - 0.25) * eased
                    inst.OutlineTransparency = 0.25 + (1 - 0.25) * eased
                end
            end
            if t >= 1 then
                model:Destroy()
                table.remove(state.clones, i)
            else
                i += 1
            end
        end
    end
end

local function clearSandevistanClones(state)
    if not state or not state.clones then
        return
    end
    for i = #state.clones, 1, -1 do
        local rec = state.clones[i]
        if rec and rec.model and rec.model.Parent then
            rec.model:Destroy()
        end
        table.remove(state.clones, i)
    end
    state.timeSinceClone = 0
end

local function stopSandevistanLocalCamera(token)
    if token and sandevistanCameraToken ~= token then
        return
    end

    if sandevistanCameraConn then
        sandevistanCameraConn:Disconnect()
        sandevistanCameraConn = nil
    end

    local camera = Workspace.CurrentCamera
    if camera and type(sandevistanCameraBaseFov) == "number" then
        TweenService:Create(camera, TweenInfo.new(SANDEVISTAN_FOV_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            FieldOfView = sandevistanCameraBaseFov,
        }):Play()
    end
    sandevistanCameraBaseFov = nil
    sandevistanCameraToken = 0
end

local function startSandevistanLocalCamera(token, duration, fovTarget)
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    stopSandevistanLocalCamera()
    sandevistanCameraToken = token
    sandevistanCameraBaseFov = camera.FieldOfView
    local targetFov = math.clamp(tonumber(fovTarget) or SANDEVISTAN_FOV_TARGET, 80, 130)

    TweenService:Create(camera, TweenInfo.new(SANDEVISTAN_FOV_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        FieldOfView = targetFov,
    }):Play()

    local startedAt = os.clock()
    sandevistanCameraConn = RunService.RenderStepped:Connect(function()
        if sandevistanCameraToken ~= token then
            return
        end
        local elapsed = os.clock() - startedAt
        if elapsed >= duration then
            return
        end
        local wobble = math.sin(elapsed * math.pi * 2 * SANDEVISTAN_FOV_JITTER_FREQ) * SANDEVISTAN_FOV_JITTER_AMPL
        camera.FieldOfView = targetFov + wobble
    end)
end

local function playSandevistanVisual(fx, casterUserId)
    if type(fx) ~= "table" then return end
    if type(casterUserId) ~= "number" then return end

    local caster = Players:GetPlayerByUserId(casterUserId)
    if not caster then return end
    local now = os.clock()
    local lastEventAt = sandevistanLastEventAtByCaster[casterUserId]
    if lastEventAt and (now - lastEventAt) <= SANDEVISTAN_DUPLICATE_WINDOW then
        return
    end
    sandevistanLastEventAtByCaster[casterUserId] = now

    local duration = math.clamp(tonumber(fx.duration) or 4, 0.2, 6)
    local token = (sandevistanFxTokenByCaster[casterUserId] or 0) + 1
    sandevistanFxTokenByCaster[casterUserId] = token
    local state = {
        token = token,
        clones = {},
        timeSinceClone = 0,
    }
    sandevistanStateByCaster[casterUserId] = state

    playSandevistanSoundAtCharacter(caster.Character, SANDEVISTAN_SFX_ACTIVATE_ID, "AFS_SandevistanActivate")
    setSandevistanOverlayActive(true)

    if caster == Player then
        startSandevistanLocalCamera(token, duration, fx.fovTarget)
    end

    task.spawn(function()
        local folder = getOrCreateFxFolder(SANDEVISTAN_FX_FOLDER_NAME)

        local startedAt = os.clock()
        local lastStep = startedAt
        local interrupted = false
        while os.clock() - startedAt < duration do
            if sandevistanFxTokenByCaster[casterUserId] ~= token then
                interrupted = true
                break
            end

            local now = os.clock()
            local dt = math.max(0, now - lastStep)
            lastStep = now

            updateSandevistanClones(state)

            local currentCharacter = caster.Character
            local root = currentCharacter and getModelRoot(currentCharacter)
            if currentCharacter and root then
                local speed = root.AssemblyLinearVelocity.Magnitude
                local snapshotInterval = SANDEVISTAN_SNAPSHOT_INTERVAL
                if speed < 4 then
                    snapshotInterval = SANDEVISTAN_SNAPSHOT_INTERVAL * 1.7
                elseif speed > 22 then
                    snapshotInterval = SANDEVISTAN_SNAPSHOT_INTERVAL * 0.8
                end

                state.timeSinceClone += dt
                if speed > 1 and state.timeSinceClone >= snapshotInterval then
                    state.timeSinceClone = 0
                    snapshotSandevistanClone(state, currentCharacter, root, folder)
                end
            end

            task.wait(SANDEVISTAN_STEP_TIME)
        end

        if not interrupted and sandevistanFxTokenByCaster[casterUserId] == token then
            playSandevistanSoundAtCharacter(caster.Character, SANDEVISTAN_SFX_DEACTIVATE_ID, "AFS_SandevistanDeactivate")
        end
        setSandevistanOverlayActive(false)

        if caster == Player then
            stopSandevistanLocalCamera(token)
        end

        local fadeDeadline = os.clock() + SANDEVISTAN_CLONE_LIFETIME + 0.1
        while #state.clones > 0 and os.clock() < fadeDeadline do
            updateSandevistanClones(state)
            task.wait(SANDEVISTAN_STEP_TIME)
        end

        clearSandevistanClones(state)
        if sandevistanStateByCaster[casterUserId] == state then
            sandevistanStateByCaster[casterUserId] = nil
        end
    end)
end

local function setSlotReadyVisual(slotInfo, hasAbility)
    slotInfo.cooldownFill.Visible = false
    slotInfo.cooldownFill.Size = UDim2.new(1, 0, 0, 0)
    slotInfo.cooldownLabel.Text = hasAbility and "READY" or ""
    slotInfo.cooldownLabel.TextColor3 = hasAbility and Theme.accent or Theme.textDim
    slotInfo.nameLabel.TextColor3 = hasAbility and Theme.text or Theme.textDim
    slotInfo.keyLabel.TextColor3 = hasAbility and Theme.accent or Theme.textDim
    slotInfo.stroke.Color = hasAbility and Theme.stroke or Theme.textDim
    slotInfo.stroke.Transparency = hasAbility and 0.3 or 0.55
end

local function setSlotCooldownVisual(slotInfo, remaining, total)
    local safeTotal = math.max(0.05, total)
    local ratio = math.clamp(remaining / safeTotal, 0, 1)
    slotInfo.cooldownFill.Visible = true
    slotInfo.cooldownFill.Size = UDim2.new(1, 0, ratio, 0)
    slotInfo.cooldownLabel.Text = string.format("%.1fs", remaining)
    slotInfo.cooldownLabel.TextColor3 = Theme.accentHot
    slotInfo.nameLabel.TextColor3 = Theme.text
    slotInfo.keyLabel.TextColor3 = Theme.text
    slotInfo.stroke.Color = Theme.accentHot
    slotInfo.stroke.Transparency = 0.2
end

local function updateMoveCooldownVisuals(profile)
    local p = profile or localProfile
    local eAbility = getEquippedAbility(p, 1)
    local rAbility = getEquippedAbility(p, 2)
    local tAbility = getEquippedAbility(p, 3)

    local eRemaining = eAbility and CooldownService:GetRemaining(Player, eAbility) or 0
    local rRemaining = rAbility and CooldownService:GetRemaining(Player, rAbility) or 0
    local tRemaining = tAbility and CooldownService:GetRemaining(Player, tAbility) or 0

    if eAbility and eRemaining > 0 then
        setSlotCooldownVisual(abilitySlotE, eRemaining, getAbilityCooldownTotal(eAbility))
    else
        setSlotReadyVisual(abilitySlotE, eAbility ~= nil)
    end

    if rAbility and rRemaining > 0 then
        setSlotCooldownVisual(abilitySlotR, rRemaining, getAbilityCooldownTotal(rAbility))
    else
        setSlotReadyVisual(abilitySlotR, rAbility ~= nil)
    end

    if tAbility and tRemaining > 0 then
        setSlotCooldownVisual(abilitySlotT, tRemaining, getAbilityCooldownTotal(tAbility))
    else
        setSlotReadyVisual(abilitySlotT, tAbility ~= nil)
    end

    local labelAbility = lastActivatedAbilityId
    if labelAbility and CooldownService:GetRemaining(Player, labelAbility) <= 0 then
        labelAbility = nil
        lastActivatedAbilityId = nil
    end
    if not labelAbility then
        if eAbility and eRemaining > 0 then
            labelAbility = eAbility
        elseif rAbility and rRemaining > 0 then
            labelAbility = rAbility
        elseif tAbility and tRemaining > 0 then
            labelAbility = tAbility
        end
    end

    if labelAbility then
        local rem = CooldownService:GetRemaining(Player, labelAbility)
        cooldownLabel.Text = rem > 0 and string.format("%s: %.1fs", getAbilityName(labelAbility), rem) or ""
    else
        cooldownLabel.Text = ""
    end
end

local function updateAbilitySlots(profile)
    local a1 = getEquippedAbility(profile, 1)
    local a2 = getEquippedAbility(profile, 2)
    local a3 = getEquippedAbility(profile, 3)
    abilitySlotE.nameLabel.Text = a1 and getAbilityName(a1) or "-"
    abilitySlotR.nameLabel.Text = a2 and getAbilityName(a2) or "-"
    abilitySlotT.nameLabel.Text = a3 and getAbilityName(a3) or "-"
    updateMoveCooldownVisuals(profile)
end

local function updateHints(profile)
    updateAbilitySlots(profile)
    if waitingForPlayers then return end
    hintLabel.TextSize = 14
    hintLabel.Text = "B - Shop"
end

task.spawn(function()
    while screen.Parent do
        updateMoveCooldownVisuals(localProfile)
        task.wait(0.1)
    end
end)

local function pulseRoleBanner(color)
    roleBannerStroke.Color = color
    roleTitle.TextColor3 = color
    local tween1 = TweenService:Create(roleBanner, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Size = UDim2.new(0, 440, 0, 56) })
    local tween2 = TweenService:Create(roleBanner, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Size = UDim2.new(0, 420, 0, 54) })
    task.spawn(function()
        tween1:Play()
        tween1.Completed:Wait()
        tween2:Play()
    end)
end

local function updateRoleBanner(isSpirit, isChallenger, isAlly, state, playerCount, minPlayers)
    local waiting = state == Constants.RoundState.WaitingForPlayers
        or (playerCount and minPlayers and playerCount < minPlayers)
    if waiting then
        roleBanner.Visible = true
        roleTitle.Text = "WAITING FOR PLAYERS"
        if playerCount and minPlayers then
            local needed = math.max(0, minPlayers - playerCount)
            if needed > 0 then
                roleSub.Text = string.format("Need %d more player%s to start", needed, needed == 1 and "" or "s")
            else
                roleSub.Text = "Preparing match..."
            end
        else
            roleSub.Text = "Need more players to start"
        end
        pulseRoleBanner(Theme.textDim)
        return
    end

    if isSpirit then
        roleBanner.Visible = true
        roleTitle.Text = "YOU ARE THE SPIRIT"
        roleSub.Text = (state == Constants.RoundState.ChoosingOpponent) and "Pick a seat or click a player to challenge" or "Prepare for the fight"
        pulseRoleBanner(Theme.accent)
    elseif isChallenger then
        roleBanner.Visible = true
        roleTitle.Text = "YOU ARE THE CHALLENGER"
        roleSub.Text = "Defeat the Spirit"
        pulseRoleBanner(Theme.accentAlt)
    elseif isAlly then
        roleBanner.Visible = true
        roleTitle.Text = "YOU ARE THE ALLY"
        roleSub.Text = "Assist the Spirit"
        pulseRoleBanner(Color3.fromRGB(255, 220, 100))
    else
        roleBanner.Visible = false
    end
end

local function updateWaitingHint(playerCount, minPlayers)
    if playerCount and minPlayers then
        hintLabel.Text = string.format("Waiting for players: %d/%d", playerCount, minPlayers)
    else
        hintLabel.Text = "Waiting for players"
    end
    hintLabel.TextSize = 12
    updateAbilitySlots(localProfile)
end

local function setBlockedHighlight(character, enabled)
    if not character then return end
    local h = character:FindFirstChild(BLOCKED_HIGHLIGHT_NAME)
    if enabled then
        if not h then
            h = Instance.new("Highlight")
            h.Name = BLOCKED_HIGHLIGHT_NAME
            h.FillColor = Color3.fromRGB(255, 70, 70)
            h.OutlineColor = Color3.fromRGB(255, 30, 30)
            h.FillTransparency = 0.45
            h.OutlineTransparency = 0.2
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = character
        end
    else
        if h then h:Destroy() end
    end
end

local function setBlockedMarker(character, enabled)
    if not character then return end
    local marker = character:FindFirstChild(BLOCKED_MARKER_NAME)
    if enabled then
        local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
        if not head then return end
        if not marker then
            marker = Instance.new("BillboardGui")
            marker.Name = BLOCKED_MARKER_NAME
            marker.Size = UDim2.new(0, 160, 0, 28)
            marker.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
            marker.AlwaysOnTop = true
            marker.MaxDistance = 130
            marker.Parent = character

            local label = Instance.new("TextLabel")
            label.Name = "Label"
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundColor3 = Color3.fromRGB(60, 16, 16)
            label.BackgroundTransparency = 0.15
            label.BorderSizePixel = 0
            label.Font = Enum.Font.Arcade
            label.TextSize = 12
            label.TextColor3 = Color3.fromRGB(255, 130, 130)
            label.TextStrokeTransparency = 0.45
            label.Text = "UNAVAILABLE"
            label.Parent = marker

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 0)
            corner.Parent = label

            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(255, 80, 80)
            stroke.Transparency = 0.35
            stroke.Parent = label
        end
        marker.Adornee = head
    else
        if marker then marker:Destroy() end
    end
end

local function setSpiritHighlight(character, enabled)
    if not character then return end
    local h = character:FindFirstChild(SPIRIT_HIGHLIGHT_NAME)
    if enabled then
        if not h then
            h = Instance.new("Highlight")
            h.Name = SPIRIT_HIGHLIGHT_NAME
            h.FillColor = Theme.accent
            h.OutlineColor = Theme.accentAlt
            h.FillTransparency = 0.65
            h.OutlineTransparency = 0.1
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = character
        end
    else
        if h then h:Destroy() end
    end
end

local seatHighlights = {}
local function clearSeatHighlights()
    for _, h in pairs(seatHighlights) do
        if h then h:Destroy() end
    end
    seatHighlights = {}
end

local function rebuildSeatHighlights()
    clearSeatHighlights()
    local map = Workspace:FindFirstChild("Map")
    local lobby = map and map:FindFirstChild("Lobby")
    local seats = lobby and lobby:FindFirstChild("Seats")
    if not seats then return end
    for _, seat in ipairs(seats:GetChildren()) do
        if seat:IsA("BasePart") then
            local occupantId = seat:GetAttribute("OccupantUserId")
            if occupantId then
                local blocked = currentBlocked and currentBlocked[occupantId] == true
                local h = Instance.new("Highlight")
                h.Name = "AFS_SeatHighlight"
                if blocked then
                    h.FillColor = Color3.fromRGB(220, 60, 60)
                    h.OutlineColor = Color3.fromRGB(255, 80, 80)
                else
                    h.FillColor = Theme.accent
                    h.OutlineColor = Theme.accentAlt
                end
                h.FillTransparency = 0.85
                h.OutlineTransparency = 0.35
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = seat
                seatHighlights[seat] = h
            end
        end
    end
end

local function setSeatHighlights(enabled)
    if enabled then
        rebuildSeatHighlights()
    else
        clearSeatHighlights()
    end
end

local function applyBlockedForPlayer(p)
    if not p then return end
    local blocked = currentBlocked and currentBlocked[p.UserId] == true
    if p.Character then
        setBlockedHighlight(p.Character, blocked)
        setBlockedMarker(p.Character, blocked)
    end
end

local function refreshBlockedHighlights()
    for _, p in ipairs(Players:GetPlayers()) do
        applyBlockedForPlayer(p)
    end
end

local function hookPlayer(p)
    if not p then return end
    p.CharacterAdded:Connect(function()
        task.wait(0.1)
        applyBlockedForPlayer(p)
        if p == Player then
            setSpiritHighlight(p.Character, isSpiritLocal)
        end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    hookPlayer(p)
end
Players.PlayerAdded:Connect(hookPlayer)

-- Local health bar
local function setHealthBar(health, maxHealth)
    local maxVal = math.max(1, maxHealth or 1)
    local hp = math.clamp(health or 0, 0, maxVal)
    local ratio = hp / maxVal
    healthFill.Size = UDim2.new(ratio, 0, 1, 0)
    healthText.Text = string.format("HP %d/%d", math.floor(hp), math.floor(maxVal))
    if ratio <= 0.3 then
        healthFill.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
    else
        healthFill.BackgroundColor3 = Theme.health
    end
end

local function hookHealth(character)
    if not character then return end
    local hum = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 3)
    if not hum then return end
    local function update()
        setHealthBar(hum.Health, hum.MaxHealth)
    end
    update()
    hum.HealthChanged:Connect(update)
    hum:GetPropertyChangedSignal("MaxHealth"):Connect(update)
end

if Player.Character then
    hookHealth(Player.Character)
end
Player.CharacterAdded:Connect(hookHealth)

-- Posture bar updates (block posture)
local BLOCK_POSTURE_ATTRIBUTE = "AFS_BlockPosture"
local BLOCK_POSTURE_MAX_ATTRIBUTE = "AFS_BlockPostureMax"
local BLOCK_POSTURE_REGEN_RATE = 8 -- passive regeneration rate
local lastPostureValue = 50 -- start at max

local function setPostureBar(posture, maxPosture)
    local maxVal = math.max(1, maxPosture or 1)
    local p = math.clamp(posture or 0, 0, maxVal)
    local ratio = p / maxVal
    
    lastPostureValue = p
    
    -- Smooth tween the fill
    local currentRatio = postureFill.Size.X.Scale
    if math.abs(currentRatio - ratio) > 0.01 then
        local tweenTime = 0.15 -- smooth transition
        local tInfo = TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tween = TweenService:Create(postureFill, tInfo, { Size = UDim2.new(ratio, 0, 1, 0) })
        tween:Play()
    else
        postureFill.Size = UDim2.new(ratio, 0, 1, 0)
    end
end

local function hookPosture(character)
    if not character then return end
    local function update()
        local maxP = character:GetAttribute(BLOCK_POSTURE_MAX_ATTRIBUTE)
        if type(maxP) ~= "number" or maxP <= 0 then maxP = 50 end
        local p = character:GetAttribute(BLOCK_POSTURE_ATTRIBUTE)
        if type(p) ~= "number" then p = maxP end
        setPostureBar(p, maxP)
    end
    update()
    if character.GetAttributeChangedSignal then
        character:GetAttributeChangedSignal(BLOCK_POSTURE_ATTRIBUTE):Connect(update)
        character:GetAttributeChangedSignal(BLOCK_POSTURE_MAX_ATTRIBUTE):Connect(update)
    end
end

if Player.Character then
    hookPosture(Player.Character)
end
Player.CharacterAdded:Connect(hookPosture)

-- Helper: tween money pulse
local function moneyPulse()
    local tInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
    local t1 = TweenService:Create(moneyScale, tInfo, { Scale = 1.12 })
    local t2 = TweenService:Create(moneyScale, tInfo, { Scale = 1 })
    t1:Play() t1.Completed:Wait() t2:Play()
end

local abilityPopupToken = 0
local function showAbilityActivatedPopup(text, color)
    abilityPopupToken = abilityPopupToken + 1
    local token = abilityPopupToken
    abilityPopup.Text = text
    abilityPopup.TextColor3 = color or Theme.accentAlt
    abilityPopup.Visible = true
    abilityPopup.Position = UDim2.new(0.5, 0, 0, 96)
    abilityPopup.TextTransparency = 0
    abilityPopup.TextStrokeTransparency = 0.72
    abilityPopup.BackgroundTransparency = 0.08

    TweenService:Create(abilityPopup, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0, 88),
    }):Play()

    task.delay(1.25, function()
        if token ~= abilityPopupToken then return end
        local fade = TweenService:Create(abilityPopup, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            TextTransparency = 1,
            TextStrokeTransparency = 1,
            BackgroundTransparency = 1,
        })
        fade:Play()
        fade.Completed:Connect(function()
            if token ~= abilityPopupToken then return end
            abilityPopup.Visible = false
            abilityPopup.Text = ""
        end)
    end)
end

local function showDamagePopup(targetUserId, amount)
    if not amount or amount <= 0 then return end
    local target = Players:GetPlayerByUserId(targetUserId)
    if not target or not target.Character then return end
    local head = target.Character:FindFirstChild("Head") or target.Character:FindFirstChild("HumanoidRootPart")
    if not head then return end

    local gui = Instance.new("BillboardGui")
    gui.Name = "AFS_DamagePopup"
    gui.Adornee = head
    gui.AlwaysOnTop = true
    gui.Size = UDim2.new(0, 90, 0, 30)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
    gui.MaxDistance = 90
    gui.Parent = damageFolder

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.Arcade
    label.TextSize = 20
    label.TextColor3 = Theme.accentAlt
    label.TextStrokeTransparency = 0.3
    label.Text = tostring(math.floor(amount))
    label.Parent = gui

    local drift = gui.StudsOffsetWorldSpace + Vector3.new(0, 1.4, 0)
    local tweenInfo = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(gui, tweenInfo, { StudsOffsetWorldSpace = drift }):Play()
    TweenService:Create(label, tweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
    task.delay(0.6, function()
        if gui then gui:Destroy() end
    end)
end

EV_ECONOMY.OnClientEvent:Connect(function(payload)
    if not payload or payload.userId ~= Player.UserId then return end
    moneyLabel.Text = "$" .. tostring(payload.money or 0)
    moneyPulse()
    streakLabel.Text = "Streak: " .. tostring(payload.streak or 0)
end)

-- Damage popup (attacker-only)
if EV_DAMAGE_POPUP then
    EV_DAMAGE_POPUP.OnClientEvent:Connect(function(payload)
        if not payload then return end
        if type(payload.targetUserId) ~= "number" or type(payload.damage) ~= "number" then return end
        showDamagePopup(payload.targetUserId, payload.damage)
    end)
end

-- round state updates (role badge color changes)
EV_STATE_UPDATE.OnClientEvent:Connect(function(payload)
    if not payload then return end
    if payload.state then currentState = payload.state end
    waitingForPlayers = currentState == Constants.RoundState.WaitingForPlayers
        or (payload.minPlayers and payload.playerCount and payload.playerCount < payload.minPlayers)
    local role = "Spectator"
    local color = Color3.fromRGB(180,180,180)
    local isSpirit = payload.spiritUserId == Player.UserId
    local isChallenger = payload.challengerUserId == Player.UserId
    local isAlly = payload.allyUserId == Player.UserId
    if waitingForPlayers then
        role = "Waiting"
        color = Theme.textDim
    elseif isSpirit then
        role = "Spirit"
        color = Theme.accent
    elseif isChallenger then
        role = "Challenger"
        color = Theme.accentAlt
    elseif isAlly then
        role = "Ally"
        color = Color3.fromRGB(255, 220, 100)
    else
        if payload.blocked and payload.blocked[Player.UserId] then
            role = "Blocked"
            color = Color3.fromRGB(200,100,100)
        end
    end
    roleBadge.Text = role
    pcall(function()
        local tween = TweenService:Create(roleBadge, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { BackgroundColor3 = color })
        tween:Play()
    end)
    if payload.streaks and payload.streaks[Player.UserId] ~= nil then
        streakLabel.Text = "Streak: " .. tostring(payload.streaks[Player.UserId])
    end

    if payload.blocked then
        currentBlocked = payload.blocked
    else
        currentBlocked = {}
    end
    refreshBlockedHighlights()

    isSpiritLocal = isSpirit
    updateRoleBanner(isSpirit, isChallenger, isAlly, currentState, payload.playerCount, payload.minPlayers)
    setSeatHighlights(isSpirit and currentState == Constants.RoundState.ChoosingOpponent)
    if Player.Character then
        setSpiritHighlight(Player.Character, isSpirit)
    end

    if waitingForPlayers then
        updateWaitingHint(payload.playerCount, payload.minPlayers)
    else
        updateHints(localProfile)
    end
end)

-- Shop updates to track equipped weapon
if EV_SHOP then
    EV_SHOP.OnClientEvent:Connect(function(profile)
        if not profile then return end
        localProfile = profile
        updateHints(profile)
    end)
end

-- Ability FX: start cooldown and mirror
if EV_ABILITY_FX then
    EV_ABILITY_FX.OnClientEvent:Connect(function(data)
        if not data then return end
        if data.fx and data.fx.type == "time_skip" then
            playTimeSkipVisual(data.fx.freezeDuration, data.caster == Player.UserId, data.fx.target == Player.UserId)
            playTimeSkipSound()
        elseif data.fx and (data.fx.type == "sandevistan" or data.fx.type == "reality_break") then
            playSandevistanVisual(data.fx, data.caster)
        end

        local isLocalCaster = data.caster == Player.UserId
        if not isLocalCaster or not data.abilityId then return end
        local suppressPopup = data.fx and data.fx.type == "flash_step_end"

        local popupColor = getPopupColorForAbility(data.abilityId)
        if not suppressPopup then
            if data.abilityId == "kaioken" then
                showAbilityActivatedPopup("KAIOKEN ACTIVATED!", popupColor)
            else
                showAbilityActivatedPopup(string.upper(getAbilityName(data.abilityId)) .. "!", popupColor)
            end
        end

        if data.cooldown then
            trackedCooldowns[data.abilityId] = data.cooldown
            CooldownService:StartCooldown(Player, data.abilityId, data.cooldown)
            lastActivatedAbilityId = data.abilityId
        end

        local eAbility = getEquippedAbility(localProfile, 1)
        local rAbility = getEquippedAbility(localProfile, 2)
        local tAbility = getEquippedAbility(localProfile, 3)
        if eAbility == data.abilityId then
            pulseAbilitySlot(abilitySlotE, popupColor)
        elseif rAbility == data.abilityId then
            pulseAbilitySlot(abilitySlotR, popupColor)
        elseif tAbility == data.abilityId then
            pulseAbilitySlot(abilitySlotT, popupColor)
        end
        updateMoveCooldownVisuals(localProfile)
    end)
end

updateHints(localProfile)
