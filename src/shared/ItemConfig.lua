-- Data-driven item config for Anime Fighting Spirit
local ItemConfig = {}

ItemConfig.Items = {
    -- Weapons
    {
        id = "nichirin_katana",
        name = "Nichirin Katana",
        type = "Weapon",
        cost = 100,
        model = "Nichirin Katana",
        -- Default equipped carry position.
        equipMount = "waist",
        -- Fine-tune how the sword sits at the right waist (degrees).
        waistOffset = {
            pos = { 0.92, -0.95, -0.12 },
            rot = { 90, -90, 80 },
        },
        gripOffset = {
            pos = { 0, 0, 0 },
            rot = { -9.244, -87.431, -9.625 },
        },
    },
    {
        id = "scissor_blade",
        name = "Scissor Blade",
        type = "Weapon",
        cost = 300,
        model = "Scissor Blade",
        -- TEMP tuning mode: keep weapon in hand during idle so grip is easy to calibrate.
        equipMount = "back",
        backOffset = {
            pos = { 0, 0, 0.4 },
            rot = { 205, -90, 45 },
        },
        gripOffset = {
            -- Same grip-offset style as katana baseline.
            pos = { -0.227, -0.452, -5 },
            rot = { 0, 180, 180 },
        },
        shopDisabled = false,
    },
    {
        id = "zangetsu_bankai",
        name = "Zangetsu (Bankai)",
        type = "Weapon",
        cost = 700,
        model = "Zangetsu (Bankai)",
        equipMount = "waist",
        waistOffset = {
            pos = { 1, -0.95, 0 },
            rot = { -15, -90, 80 },
        },
        -- Start from katana grip baseline, then fine-tune if needed.
        gripOffset = {
            pos = { 0, -0.8, -0 },
            rot = { -45, 0, 180 },
        },
        shopDisabled = false,
    },
    {
        id = "dragon_slayer",
        name = "Dragon Slayer",
        type = "Weapon",
        cost = 1500,
        model = "Dragon Slayer",
        equipMount = "grip",
        gripOffset = {
            pos = { 0, -0.5, 0 },
            rot = { 0, -60, 180 },
        },
        shopDisabled = false,
        -- Idle animation to play when equipped (asset id)
        idleAnimationId = "86004141593078",
    },

    -- Weapon abilities removed: weapons only scale damage now

    -- Powers
    {
        id = "kaioken",
        name = "Kaioken 10x",
        type = "Power",
        cost = 200,
        blocksOtherAbilities = false,
        duration = 12,
        cooldown = 20,
    },
    {
        id = "black_flame",
        name = "Black Flame Barrage",
        type = "Power",
        cost = 500,
        cooldown = 12,
    },
    {
        id = "time_skip",
        name = "Time Skip Strike",
        type = "Power",
        cost = 1000,
        cooldown = 20,
    },
    {
        id = "flash_step",
        name = "Flash Step",
        type = "Power",
        cost = 1500,
        cooldown = 5,
    },
    {
        id = "reality_break",
        name = "Sandevistan",
        type = "Power",
        cost = 3000,
        duration = 6,
        cooldown = 40,
    },

    -- Health upgrades (type Upgrade)
    {
        id = "hp_plus_5",
        name = "+5 HP",
        type = "Upgrade",
        cost = 150,
        hpBonus = 5,
    },
    {
        id = "hp_plus_15",
        name = "+15 HP",
        type = "Upgrade",
        cost = 500,
        hpBonus = 15,
    },
    {
        id = "hp_plus_50",
        name = "+50 HP",
        type = "Upgrade",
        cost = 1250,
        hpBonus = 50,
    },
    {
        id = "hp_plus_100",
        name = "+100 HP",
        type = "Upgrade",
        cost = 2500,
        hpBonus = 100,
    },
    {
        id = "hp_plus_150",
        name = "+150 HP",
        type = "Upgrade",
        cost = 5000,
        hpBonus = 150,
    },
}

-- Weapon stats (damage + attack animation list)
-- Fill in attackAnimationId with your animation asset ids.
ItemConfig.WeaponStats = {
    fists = { baseDamage = 5, attackAnimationId = "112489316768198" },
    nichirin_katana = { baseDamage = 7, attackAnimationId = "79192833678057" },
    scissor_blade = { baseDamage = 9, attackAnimationId = "76819893508181" },
    zangetsu_bankai = { baseDamage = 13, attackAnimationId = "126062948549765" },
    dragon_slayer = { baseDamage = 17, attackAnimationId = "128291095081709" },
}

local lookup = {}
for _, it in ipairs(ItemConfig.Items) do
    lookup[it.id] = it
end

local weaponAbilityByWeapon = {}
for _, it in ipairs(ItemConfig.Items) do
    if it.type == "WeaponAbility" and it.requiresWeapon then
        weaponAbilityByWeapon[it.requiresWeapon] = it.id
    end
end

function ItemConfig.Get(itemId)
    return lookup[itemId]
end

function ItemConfig.GetAll()
    return ItemConfig.Items
end

function ItemConfig.GetByType(t)
    local res = {}
    for _, it in ipairs(ItemConfig.Items) do
        if it.type == t then table.insert(res, it) end
    end
    return res
end

function ItemConfig.GetWeaponStats(weaponId)
    if weaponId and ItemConfig.WeaponStats[weaponId] then
        return ItemConfig.WeaponStats[weaponId]
    end
    return ItemConfig.WeaponStats.fists
end

function ItemConfig.GetWeaponAbilityId(weaponId)
    return weaponAbilityByWeapon[weaponId]
end

function ItemConfig.GetWeaponAbility(weaponId)
    local id = weaponAbilityByWeapon[weaponId]
    if id then
        return lookup[id]
    end
    return nil
end

function ItemConfig.IsShopEnabled(itemOrId)
    local item = nil
    if type(itemOrId) == "table" then
        item = itemOrId
    else
        item = lookup[itemOrId]
    end

    if not item then
        return false
    end

    return item.shopDisabled ~= true
end

return ItemConfig
