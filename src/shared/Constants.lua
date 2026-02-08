-- Shared constants for Anime Fighting Spirit
local Constants = {}

Constants.RoundState = {
    WaitingForPlayers = "WaitingForPlayers",
    ChoosingOpponent = "ChoosingOpponent",
    InMatch = "InMatch",
    MatchEnd = "MatchEnd",
}

Constants.RemoteNames = {
    Round_RequestChallenge = "Round_RequestChallenge",
    Round_StateUpdate = "Round_StateUpdate",
    Round_RequestSit = "Round_RequestSit",
    Round_RoundStarted = "Round_RoundStarted",
    Round_RoundEnded = "Round_RoundEnded",
    Effects_Highlight = "Effects_Highlight",

    -- Combat / economy
    AttackRequest = "AttackRequest",
    BlockRequest = "BlockRequest",
    DashRequest = "DashRequest",
    EconomyUpdate = "EconomyUpdate",
    MatchStateUpdate = "MatchStateUpdate",
    -- Abilities
    AbilityRequest = "AbilityRequest",
    AbilityFx = "AbilityFx",
    -- UI Toasts
    Toast = "Toast",
    -- Combat UI
    DamagePopup = "DamagePopup",

    -- Shop remotes (canonical flat names)
    ShopPurchaseRequest = "ShopPurchaseRequest",
    ShopEquipRequest = "ShopEquipRequest",
    ShopUpdate = "ShopUpdate",
}

Constants.GamePasses = {
    -- Set this to your Roblox gamepass id for unlocking the 3rd power slot.
    UnlockThirdSlot = 1703234872,
}

-- Shop / economy constants (used later)
Constants.Shop = {
    -- Weapon placeholders
    Weapons = {
        { id = "nichirin", name = "Nichirin Katana", cost = 100 },
        { id = "scissor", name = "Scissor Blade", cost = 300 },
        { id = "spirit_sword", name = "Spirit Sword", cost = 1000 },
        { id = "zangetsu", name = "Zangetsu (Bankai)", cost = 1500 },
        { id = "kusanagi", name = "Kusanagi Blade", cost = 2500 },
    },

    Powers = {
        { id = "kaioken", name = "Kaioken 10x", cost = 200, cooldown = 20 },
        { id = "black_flame", name = "Black Flame Barrage", cost = 500, cooldown = 12 },
        { id = "time_skip", name = "Time Skip Strike", cost = 1000, cooldown = 20 },
        { id = "flash_step", name = "Flash Step", cost = 1500, cooldown = 5 },
        { id = "reality_break", name = "Sandevistan", cost = 3000, cooldown = 40 },
    },

    HealthUpgrades = {
        { hp = 5, cost = 150 },
        { hp = 15, cost = 500 },
        { hp = 50, cost = 1250 },
        { hp = 100, cost = 2500 },
        { hp = 150, cost = 5000 },
    }
}

return Constants
