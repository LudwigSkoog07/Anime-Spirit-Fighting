-- RoundService: Manages Spirit selection loop, matches, blocked list, streaks and state machine
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
if not Shared then error("Shared modules missing (RoundService)") end
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local CooldownService = require(Shared:WaitForChild("CooldownService"))

local MIN_PLAYERS = 3
local TEST_MODE_ATTRIBUTE = "AFS_TestMode"
local TEST_MODE_LEGACY_ATTRIBUTE = "AFS_IgnoreRoundRules"

local function isTestModeEnabled()
    local v = Workspace:GetAttribute(TEST_MODE_ATTRIBUTE)
    if v ~= nil then
        return v == true
    end
    return Workspace:GetAttribute(TEST_MODE_LEGACY_ATTRIBUTE) == true
end

local AbilityUtil
do
    local serverRoot = script.Parent and script.Parent.Parent
    local abilitiesFolder = serverRoot and serverRoot:FindFirstChild("Abilities")
    local utilModule = abilitiesFolder and abilitiesFolder:FindFirstChild("AbilityUtil")
    if utilModule then
        local okUtil, modUtil = pcall(require, utilModule)
        if okUtil and modUtil then
            AbilityUtil = modUtil
        end
    end
end

-- Try to require an EconomyService stub if present
local EconomyService
local ok, mod = pcall(function() return require(script.Parent.EconomyService) end)
if ok and mod then EconomyService = mod end

local ProfileService
local okProfile, modProfile = pcall(function() return require(script.Parent.ProfileService) end)
if okProfile and modProfile then ProfileService = modProfile end

local RoundService = {}
RoundService.State = Constants.RoundState.WaitingForPlayers
RoundService.currentSpirit = nil -- Player
RoundService.blocked = {} -- map userId -> true
RoundService.streaks = {} -- map userId -> streak number
RoundService.participants = {} -- players in current match
RoundService.currentAlly = nil -- Player
RoundService._connections = {}

local function clearRoundConnections()
    for i = #RoundService._connections, 1, -1 do
        local conn = RoundService._connections[i]
        if conn and conn.Disconnect then
            conn:Disconnect()
        end
        RoundService._connections[i] = nil
    end
end

-- Remote events (flat Remotes folder expected in ReplicatedStorage)
local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not remotes then error("Remotes folder missing (RoundService)") end
local REQ_CHALLENGE = remotes:WaitForChild(Constants.RemoteNames.Round_RequestChallenge, 5)
local EV_STATE_UPDATE = remotes:WaitForChild(Constants.RemoteNames.MatchStateUpdate, 5)
local REQ_SIT = remotes:WaitForChild(Constants.RemoteNames.Round_RequestSit, 5)
local EV_ROUND_STARTED = remotes:WaitForChild(Constants.RemoteNames.Round_RoundStarted, 5)
local EV_ROUND_ENDED = remotes:WaitForChild(Constants.RemoteNames.Round_RoundEnded, 5)
local EV_TOAST = remotes:WaitForChild(Constants.RemoteNames.Toast, 5)

-- Map / workspace helpers: safely require MapService and fetch map (guarded)
local MapService
local msModule = script.Parent:FindFirstChild("MapService") or script:FindFirstChild("MapService")
if msModule then
    local ok, mod = pcall(function() return require(msModule) end)
    if ok and mod then MapService = mod end
else
    local ok, mod = pcall(function() return require(script.Parent:WaitForChild("MapService", 5)) end)
    if ok and mod then MapService = mod end
end
if not MapService then
    warn("[RoundService] MapService module missing; using fallback map to avoid blocking")
    MapService = { GetOrCreateMap = function()
        return { Seats = {}, SeatsFolder = nil, Arena = nil, SpiritSpawn = nil, ChallengerSpawn = nil, AllySpawn = nil }
    end }
end

local ok, map = pcall(function() return MapService:GetOrCreateMap() end)
if not ok or not map then
    warn("[RoundService] MapService:GetOrCreateMap() failed; using empty fallbacks")
    map = map or { Seats = {}, SeatsFolder = nil, Arena = nil, SpiritSpawn = nil, ChallengerSpawn = nil, AllySpawn = nil }
end
local LobbyChairsFolder = map.SeatsFolder or map.ChairsFolder
local Seats = map.Seats or {}
local SpawnSpirit = map.SpiritSpawn
local SpawnChallenger = map.ChallengerSpawn
local SpawnAlly = map.AllySpawn

if not LobbyChairsFolder then
    warn("[RoundService] Lobby/Seats missing and MapService failed to provide them")
end

-- Basic seated bookkeeping: player.UserId -> chairPart (Part)
RoundService.seated = {}

local function getSeatOccupantUserId(seat)
    if not seat then return nil end
    local occId = seat:GetAttribute("OccupantUserId")
    if type(occId) == "number" and RoundService.seated[occId] == seat then
        return occId
    end
    for userId, chair in pairs(RoundService.seated) do
        if chair == seat then
            return userId
        end
    end
    return nil
end

local function isSeatAvailableForPlayer(seat, player)
    if not seat or not player then return false end
    local occId = getSeatOccupantUserId(seat)
    return occId == nil or occId == player.UserId
end

local function pickOpenSeat(chairs, player)
    local available = {}
    for _, seat in ipairs(chairs or {}) do
        if seat and seat:IsA("BasePart") and isSeatAvailableForPlayer(seat, player) then
            table.insert(available, seat)
        end
    end
    if #available > 0 then
        return Util.randomChoice(available)
    end
    return nil
end

local function getPlayerCount(excludeUserId)
    local count = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if not excludeUserId or p.UserId ~= excludeUserId then
            count = count + 1
        end
    end
    return count
end

local function hasMinPlayers(excludeUserId)
    if isTestModeEnabled() then
        return true
    end
    return getPlayerCount(excludeUserId) >= MIN_PLAYERS
end

local function broadcastState(extra)
    local minPlayers = isTestModeEnabled() and 1 or MIN_PLAYERS
    local payload = {
        state = RoundService.State,
        spiritUserId = RoundService.currentSpirit and RoundService.currentSpirit.UserId or nil,
        challengerUserId = RoundService.currentChallenger and RoundService.currentChallenger.UserId or nil,
        allyUserId = RoundService.currentAlly and RoundService.currentAlly.UserId or nil,
        blocked = RoundService.blocked,
        streaks = RoundService.streaks,
        playerCount = getPlayerCount(),
        minPlayers = minPlayers,
    }
    if extra then
        for k, v in pairs(extra) do
            payload[k] = v
        end
    end
    EV_STATE_UPDATE:FireAllClients(payload)
end

local function clearBlocked()
    RoundService.blocked = {}
end

local function addBlocked(userId)
    RoundService.blocked[userId] = true
end

local function setBlockedPlayers(players)
    clearBlocked()
    if not players then return end
    for _, p in ipairs(players) do
        if p and p.UserId then
            addBlocked(p.UserId)
        end
    end
end

local function setSeated(player, seat)
    if not player then return end
    local oldSeat = RoundService.seated[player.UserId]
    if oldSeat and oldSeat ~= seat and oldSeat.SetAttribute then
        local oldOccId = oldSeat:GetAttribute("OccupantUserId")
        if oldOccId == player.UserId then
            oldSeat:SetAttribute("OccupantUserId", nil)
        end
    end

    if seat then
        local currentOccId = getSeatOccupantUserId(seat)
        if currentOccId and currentOccId ~= player.UserId then
            RoundService.seated[currentOccId] = nil
        end
    end

    RoundService.seated[player.UserId] = seat
    if seat and seat.SetAttribute then
        seat:SetAttribute("OccupantUserId", player.UserId)
    end
end

local function setRole(player, role)
    if player and player.SetAttribute then
        player:SetAttribute("Role", role)
    end
end

local function getHumanoidFromPlayer(player)
    local character = player and player.Character
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
end

local function resetRoundFighterState(player)
    if not player then
        return
    end

    local humanoid = getHumanoidFromPlayer(player)
    if humanoid and humanoid.Health <= 0 then
        pcall(function()
            player:LoadCharacter()
        end)
    elseif humanoid then
        humanoid.Health = humanoid.MaxHealth
    end

    task.spawn(function()
        for _ = 1, 20 do
            local refreshed = getHumanoidFromPlayer(player)
            if refreshed then
                refreshed.Health = refreshed.MaxHealth
                break
            end
            task.wait(0.05)
        end
    end)

    if CooldownService and CooldownService.ClearAll then
        CooldownService:ClearAll(player)
    end
end

local function resetRoundParticipantsState(participants)
    if type(participants) ~= "table" then
        return
    end
    for _, participant in ipairs(participants) do
        resetRoundFighterState(participant)
    end
end

local function setMovementLock(player, locked)
    local hum = getHumanoidFromPlayer(player)
    if not hum then return end

    if AbilityUtil and AbilityUtil.applyMovementScale and AbilityUtil.recomputeMovement then
        if locked then
            AbilityUtil.applyMovementScale(hum, "RoundLock", 0, 0, 0)
        else
            if hum:GetAttribute("MoveScale_RoundLock") ~= nil or hum:GetAttribute("JumpScale_RoundLock") ~= nil then
                hum:SetAttribute("MoveScale_RoundLock", nil)
                hum:SetAttribute("JumpScale_RoundLock", nil)
                AbilityUtil.recomputeMovement(hum)
            end
        end
    else
        if hum:GetAttribute("BaseWalkSpeed") == nil then
            hum:SetAttribute("BaseWalkSpeed", hum.WalkSpeed)
        end
        if hum:GetAttribute("BaseJumpPower") == nil then
            hum:SetAttribute("BaseJumpPower", hum.JumpPower)
        end

        if locked then
            hum.WalkSpeed = 0
            hum.JumpPower = 0
        else
            hum.WalkSpeed = hum:GetAttribute("BaseWalkSpeed") or hum.WalkSpeed
            hum.JumpPower = hum:GetAttribute("BaseJumpPower") or hum.JumpPower
        end
    end
end

local function applyMovementLocks()
    if isTestModeEnabled() then
        for _, p in ipairs(Players:GetPlayers()) do
            setMovementLock(p, false)
        end
        return
    end

    local allow = {}
    if RoundService.State == Constants.RoundState.InMatch then
        for _, p in ipairs(RoundService.participants or {}) do
            if p then allow[p] = true end
        end
    elseif RoundService.State == Constants.RoundState.ChoosingOpponent and RoundService.currentSpirit then
        allow[RoundService.currentSpirit] = true
    end

    for _, p in ipairs(Players:GetPlayers()) do
        setMovementLock(p, not allow[p])
    end
end

local function setSpectatorForAll(exclude)
    for _, p in ipairs(Players:GetPlayers()) do
        if not exclude[p] then
            setRole(p, "Spectator")
        end
    end
end

local function setAllPromptsEnabled(enabled)
    for _, s in ipairs(Seats or {}) do
        for _, c in ipairs(s:GetChildren()) do
            if c:IsA("ProximityPrompt") then
                c.Enabled = enabled
            end
        end
    end
end

local setWaitingForPlayers

local function setSpirit(player)
    if not hasMinPlayers() then
        setWaitingForPlayers()
        return
    end
    RoundService.currentSpirit = player
    RoundService.currentAlly = nil
    local streak = RoundService.streaks[player.UserId]
    if streak == nil and EconomyService and EconomyService.GetStreak then
        streak = EconomyService:GetStreak(player)
    end
    RoundService.streaks[player.UserId] = math.max(0, math.floor(tonumber(streak) or 0))
    clearBlocked()
    setRole(player, "Spirit")
    setSpectatorForAll({ [player] = true })
    -- ensure EconomyService has same streak record when available
    if EconomyService and EconomyService.SetStreak then
        EconomyService:SetStreak(player, RoundService.streaks[player.UserId])
    end
    RoundService.State = Constants.RoundState.ChoosingOpponent
    broadcastState()
    applyMovementLocks()

    if EV_TOAST then
        pcall(function() EV_TOAST:FireClient(player, "You are the Spirit. Pick a seat to challenge.", "info") end)
    end
end

local function getSeatedPlayersExcluding(excludeSet)
    local res = {}
    for userId, chair in pairs(RoundService.seated) do
        if not excludeSet[userId] then
            local player = Players:GetPlayerByUserId(userId)
            if player and player.Character and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0 then
                table.insert(res, player)
            end
        end
    end
    return res
end

local function teleportTo(part, character)
    if not part or not character or not character.PrimaryPart then return end
    character:SetPrimaryPartCFrame(part.CFrame + Vector3.new(0,3,0))
end

local function anchorCharacter(character, anchored)
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = anchored
        end
    end
end

setWaitingForPlayers = function(playerCountOverride)
    RoundService.State = Constants.RoundState.WaitingForPlayers
    RoundService.currentSpirit = nil
    RoundService.currentChallenger = nil
    RoundService.currentAlly = nil
    RoundService.participants = {}
    RoundService._matchEnding = false
    clearBlocked()
    clearRoundConnections()

    local combatModule = script.Parent:FindFirstChild("CombatService")
    if combatModule then
        local okCombat, combatSvc = pcall(require, combatModule)
        if okCombat and combatSvc and combatSvc.ClearActiveMatch then
            pcall(function() combatSvc:ClearActiveMatch() end)
        end
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p and p.SetAttribute then
            p:SetAttribute("InMatch", false)
            p:SetAttribute("Role", "Spectator")
        end
        anchorCharacter(p.Character, false)
    end

    setAllPromptsEnabled(true)
    if playerCountOverride then
        broadcastState({ playerCount = playerCountOverride })
    else
        broadcastState()
    end
    applyMovementLocks()
end

local function startMatch(spirit, target, ally)
    RoundService.State = Constants.RoundState.InMatch
    RoundService.participants = { spirit, target }
    RoundService.currentChallenger = target
    RoundService.currentAlly = ally
    if ally then table.insert(RoundService.participants, ally) end

    setRole(spirit, "Spirit")
    setRole(target, "Challenger")
    if ally then setRole(ally, "Ally") end
    local exclude = { [spirit] = true, [target] = true }
    if ally then exclude[ally] = true end
    setSpectatorForAll(exclude)
    applyMovementLocks()
    broadcastState()

    -- Teleport
    if spirit.Character and spirit.Character.PrimaryPart then
        teleportTo(SpawnSpirit, spirit.Character)
    end
    if target.Character and target.Character.PrimaryPart then
        teleportTo(SpawnChallenger, target.Character)
    end
    if ally and ally.Character and ally.Character.PrimaryPart then
        teleportTo(SpawnAlly, ally.Character)
    end

    -- Anchor briefly
    for _, p in ipairs(RoundService.participants) do
        anchorCharacter(p.Character, true)
    end

    EV_ROUND_STARTED:FireAllClients({ participants = table.create(#RoundService.participants, nil) })

    -- Unanchor and enable combat after countdown
    -- Anchor period already elapsed; here we will do the countdown then unanchor and activate combat
    for _, p in ipairs(RoundService.participants) do
        if p and p.SetAttribute then p:SetAttribute("InMatch", true) end
    end

    -- disable all seat prompts while match active
    setAllPromptsEnabled(false)

    -- countdown 3..2..1..FIGHT (send both state update and toast)
    for i=3,1,-1 do
        EV_STATE_UPDATE:FireAllClients({ countdown = i })
        if EV_TOAST then pcall(function() EV_TOAST:FireAllClients(tostring(i), "info") end) end
        task.wait(1)
    end
    EV_STATE_UPDATE:FireAllClients({ countdown = "FIGHT" })
    if EV_TOAST then pcall(function() EV_TOAST:FireAllClients("FIGHT", "info") end) end

    -- unanchor participants and then enable combat
    for _, p in ipairs(RoundService.participants) do
        anchorCharacter(p.Character, false)
    end

    -- Now activate CombatService
    local CombatService = require(script.Parent:WaitForChild("CombatService"))
    CombatService:SetActiveMatch(RoundService.participants)

    -- Listen for deaths from CombatService
    local deathConn
    deathConn = CombatService.PlayerDied.Event:Connect(function(victim, killers)
        task.delay(0.1, function()
            if RoundService.State ~= Constants.RoundState.InMatch then return end

            -- prevent re-entrance
            if RoundService._matchEnding then return end
            RoundService._matchEnding = true

            if ProfileService and ProfileService.RecordElimination then
                ProfileService:RecordElimination(victim, killers)
            end

            -- find which team still has alive players
            local aliveByTeam = { spirit = 0, challenger = 0 }
            for _, q in ipairs(RoundService.participants) do
                if q.Character and q.Character:FindFirstChild("Humanoid") and q.Character.Humanoid.Health > 0 then
                    if q == spirit or (ally and q == ally) then
                        aliveByTeam.spirit = aliveByTeam.spirit + 1
                    else
                        aliveByTeam.challenger = aliveByTeam.challenger + 1
                    end
                end
            end

            local spiritWins = aliveByTeam.spirit > 0 and aliveByTeam.challenger == 0
            local challengerWins = aliveByTeam.challenger > 0 and aliveByTeam.spirit == 0

                -- Round cleanup reward: all fighters get full HP and abilities off cooldown.
                resetRoundParticipantsState(RoundService.participants)

                if spiritWins then
                    -- Spirit victory
                    RoundService.streaks[spirit.UserId] = (RoundService.streaks[spirit.UserId] or 0) + 1
                    if EconomyService and EconomyService.SetStreak then
                        EconomyService:SetStreak(spirit, RoundService.streaks[spirit.UserId])
                    end
                    if EconomyService and killers then
                        EconomyService:PayKillBounty(victim, killers)
                    end
                    if EconomyService and EconomyService.PayRoundResult then
                        local winners = { spirit }
                        if ally then table.insert(winners, ally) end
                        EconomyService:PayRoundResult(winners, { target }, false)
                    end
                    if ProfileService and ProfileService.RecordRoundResult then
                        local winners = { spirit }
                        if ally then table.insert(winners, ally) end
                        ProfileService:RecordRoundResult(winners, { target }, false)
                    end

                    -- Block the last opponent so they can't be re-picked immediately
                    setBlockedPlayers({ target })

                    RoundService.State = Constants.RoundState.MatchEnd
                    broadcastState()
                    applyMovementLocks()
                    EV_ROUND_ENDED:FireAllClients({ winner = spirit.UserId, killers = (killers and table.create(#killers, nil)) })

                    -- Return players to chairs and reset states
                    task.delay(1, function()
                        for _, p in ipairs(RoundService.participants) do
                            local chair = RoundService.seated[p.UserId]
                            if chair and p.Character and p.Character.PrimaryPart then
                                teleportTo(chair, p.Character)
                                setSeated(p, chair)
                            end
                            if p and p.SetAttribute then
                                p:SetAttribute("InMatch", false)
                                p:SetAttribute("Role", "Spectator")
                            end
                        end

                        -- keep Spirit role for winner
                        setRole(spirit, "Spirit")
                        setSpectatorForAll({ [spirit] = true })

                        -- re-enable prompts
                        for _, s in ipairs(Seats or {}) do
                            for _, c in ipairs(s:GetChildren()) do
                                if c:IsA("ProximityPrompt") then c.Enabled = true end
                            end
                        end

                        if not hasMinPlayers() then
                            setWaitingForPlayers()
                            RoundService._matchEnding = false
                            return
                        end

                        RoundService.participants = {}
                        RoundService.currentChallenger = nil
                        RoundService.currentAlly = nil
                        RoundService.State = Constants.RoundState.ChoosingOpponent
                        broadcastState()
                        applyMovementLocks()
                        RoundService._matchEnding = false
                    end)

                elseif challengerWins then
                    -- Challenger becomes new Spirit, set streak to 1
                    RoundService.streaks[target.UserId] = 1
                    RoundService.streaks[spirit.UserId] = 0
                    if EconomyService and EconomyService.SetStreak then
                        EconomyService:SetStreak(target, 1)
                        EconomyService:SetStreak(spirit, 0)
                    end
                    if EconomyService and killers then
                        EconomyService:PayKillBounty(victim, killers)
                    end
                    if EconomyService and EconomyService.PayRoundResult then
                        local losers = { spirit }
                        if ally then table.insert(losers, ally) end
                        EconomyService:PayRoundResult({ target }, losers, false)
                    end
                    if ProfileService and ProfileService.RecordRoundResult then
                        local losers = { spirit }
                        if ally then table.insert(losers, ally) end
                        ProfileService:RecordRoundResult({ target }, losers, false)
                    end

                    -- Promote challenger to Spirit immediately
                    RoundService.currentSpirit = target
                    RoundService.currentChallenger = nil
                    setRole(target, "Spirit")

                    -- Block the last opponent(s) so they can't be re-picked immediately
                    if ally then
                        setBlockedPlayers({ spirit, ally })
                    else
                        setBlockedPlayers({ spirit })
                    end

                    RoundService.State = Constants.RoundState.MatchEnd
                    broadcastState()
                    applyMovementLocks()
                    EV_ROUND_ENDED:FireAllClients({ winner = target.UserId, killers = (killers and table.create(#killers, nil)) })

                    if EV_TOAST then
                        pcall(function() EV_TOAST:FireClient(target, "You are the Spirit. Pick a seat to challenge.", "info") end)
                    end

                    task.delay(1, function()
                        for _, p in ipairs(RoundService.participants) do
                            local chair = RoundService.seated[p.UserId]
                            if chair and p.Character and p.Character.PrimaryPart then
                                teleportTo(chair, p.Character)
                                setSeated(p, chair)
                            end
                            if p and p.SetAttribute then
                                p:SetAttribute("InMatch", false)
                                p:SetAttribute("Role", "Spectator")
                            end
                        end

                        -- keep Spirit role for new Spirit
                        setRole(target, "Spirit")
                        setSpectatorForAll({ [target] = true })

                        -- re-enable prompts
                        for _, s in ipairs(Seats or {}) do
                            for _, c in ipairs(s:GetChildren()) do
                                if c:IsA("ProximityPrompt") then c.Enabled = true end
                            end
                        end

                        if not hasMinPlayers() then
                            setWaitingForPlayers()
                            RoundService._matchEnding = false
                            return
                        end

                        RoundService.participants = {}
                        RoundService.currentChallenger = nil
                        RoundService.currentAlly = nil
                        RoundService.State = Constants.RoundState.ChoosingOpponent
                        broadcastState()
                        applyMovementLocks()
                        RoundService._matchEnding = false
                    end)

                else
                    if EconomyService and killers then
                        EconomyService:PayKillBounty(victim, killers)
                    end
                    if EconomyService and EconomyService.PayRoundResult then
                        EconomyService:PayRoundResult(nil, RoundService.participants, true)
                    end
                    if ProfileService and ProfileService.RecordRoundResult then
                        ProfileService:RecordRoundResult(nil, RoundService.participants, true)
                    end
                    RoundService.State = Constants.RoundState.MatchEnd
                    broadcastState({ draw = true })
                    applyMovementLocks()
                    EV_ROUND_ENDED:FireAllClients({ winner = nil, draw = true, killers = (killers and table.create(#killers, nil)) })

                    task.delay(1, function()
                        setWaitingForPlayers()
                        RoundService._matchEnding = false
                    end)
                end

                -- cleanup
                clearRoundConnections()
                CombatService:ClearActiveMatch()
            end)
        end)

        table.insert(RoundService._connections, deathConn)
    end

local function validateChallengeRequest(player, targetUserId)
    if RoundService.State ~= Constants.RoundState.ChoosingOpponent then return false, "not-choosing" end
    if not RoundService.currentSpirit then return false, "no-spirit" end
    if player ~= RoundService.currentSpirit then return false, "not-spirit" end
    local target = Players:GetPlayerByUserId(targetUserId)
    if not target then return false, "invalid-target" end
    if target == player then return false, "self-target" end
    if RoundService.blocked[targetUserId] then return false, "blocked" end
    if not RoundService.seated[targetUserId] then return false, "not-seated" end
    return true, "ok", target
end

local function pickAllyIfNeeded(spirit, target)
    local s = RoundService.streaks[spirit.UserId] or 0
    if s >= 10 then
        local exclude = {}
        exclude[spirit.UserId] = true
        exclude[target.UserId] = true
        for userId, _ in pairs(RoundService.blocked) do exclude[userId] = true end
        local candidates = getSeatedPlayersExcluding(exclude)
        if #candidates > 0 then
            return Util.randomChoice(candidates)
        end
    end
    return nil
end

local function getSeatOccupant(seat)
    if not seat then return nil end
    local occId = getSeatOccupantUserId(seat)
    if not occId then return nil end

    local p = Players:GetPlayerByUserId(occId)
    if p and p.Character and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
        return p
    end

    if seat.SetAttribute and seat:GetAttribute("OccupantUserId") == occId then
        seat:SetAttribute("OccupantUserId", nil)
    end
    RoundService.seated[occId] = nil
    return nil
end

local function handleSeatPrompt(player, seat)
    if not player or not seat then return end
    if RoundService.State == Constants.RoundState.InMatch then return end

    -- Spirit selecting a challenger
    if RoundService.State == Constants.RoundState.ChoosingOpponent and RoundService.currentSpirit == player then
        local target = getSeatOccupant(seat)
        if not target or target == player then return end
        if RoundService.blocked[target.UserId] then return end
        local ally = pickAllyIfNeeded(player, target)
        startMatch(player, target, ally)
        return
    end

    -- Non-spirit (or waiting) sits down
    if player.Character and player.Character.PrimaryPart then
        if not isSeatAvailableForPlayer(seat, player) then
            return
        end
        teleportTo(seat, player.Character)
        setSeated(player, seat)
        broadcastState()
        if not RoundService.currentSpirit then
            if hasMinPlayers() then
                setSpirit(player)
            else
                setWaitingForPlayers()
            end
        end
    end
end

local function bindSeatPrompt(seat)
    if not seat or not seat:IsA("BasePart") then return end
    if seat:GetAttribute("PromptBound") then return end
    local prompt = seat:FindFirstChildOfClass("ProximityPrompt") or seat:FindFirstChild("ProximityPrompt")
    if not prompt then return end
    seat:SetAttribute("PromptBound", true)
    prompt.Triggered:Connect(function(player)
        handleSeatPrompt(player, seat)
    end)
end

local function bindAllSeatPrompts()
    for _, seat in ipairs(Seats or {}) do
        bindSeatPrompt(seat)
    end
    if LobbyChairsFolder then
        LobbyChairsFolder.ChildAdded:Connect(function(child)
            if child:IsA("BasePart") then
                task.wait(0.1)
                bindSeatPrompt(child)
            end
        end)
    end
end

-- Remote handlers
REQ_CHALLENGE.OnServerEvent:Connect(function(player, targetUserId)
    local ok, msg, target = validateChallengeRequest(player, targetUserId)
    if not ok then
        -- Optionally send a rejection to player
        return
    end
    local ally = pickAllyIfNeeded(player, target)
    startMatch(player, target, ally)
end)

REQ_SIT.OnServerEvent:Connect(function(player, chairName)
    -- Simple sit handler: teleport player to chair and record seated map
    local chair = LobbyChairsFolder and LobbyChairsFolder:FindFirstChild(chairName)
    if not chair then return end
    if player.Character and player.Character.PrimaryPart then
        if not isSeatAvailableForPlayer(chair, player) then
            return
        end
        teleportTo(chair, player.Character)
        setSeated(player, chair)
        broadcastState()
    end
end)

-- Player join/leave
Players.PlayerAdded:Connect(function(player)
    if RoundService.streaks[player.UserId] == nil and EconomyService and EconomyService.GetStreak then
        RoundService.streaks[player.UserId] = math.max(0, math.floor(tonumber(EconomyService:GetStreak(player)) or 0))
    end

    -- If first player, make them Spirit after they load
    player.CharacterAdded:Connect(function(character)
        -- spawn them at a chair automatically (choose random chair)
        local chairs = Seats or (LobbyChairsFolder and LobbyChairsFolder:GetChildren()) or {}
        local seatCandidates = {}
        for _, chair in ipairs(chairs) do
            if chair and chair:IsA("BasePart") then
                table.insert(seatCandidates, chair)
            end
        end
        if #seatCandidates > 0 then
            local chair = pickOpenSeat(seatCandidates, player) or Util.randomChoice(seatCandidates)
            teleportTo(chair, character)
            setSeated(player, chair)
            broadcastState()
        end

        if not RoundService.currentSpirit then
            if hasMinPlayers() then
                setSpirit(player)
            else
                setWaitingForPlayers()
            end
        else
            applyMovementLocks()
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    -- Cleanup
    local seat = RoundService.seated[player.UserId]
    if seat and seat.SetAttribute and seat:GetAttribute("OccupantUserId") == player.UserId then
        seat:SetAttribute("OccupantUserId", nil)
    end
    RoundService.seated[player.UserId] = nil
    RoundService.blocked[player.UserId] = nil
    RoundService.streaks[player.UserId] = nil

    local countAfter = getPlayerCount(player.UserId)
    if (not isTestModeEnabled()) and countAfter < MIN_PLAYERS then
        setWaitingForPlayers(countAfter)
        return
    end

    if RoundService.currentSpirit == player then
        RoundService.currentSpirit = nil
        -- pick next player as spirit if any
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= player then
                setSpirit(p)
                return
            end
        end
    end

    broadcastState({ playerCount = countAfter })
    applyMovementLocks()
end)

function RoundService:Init()
    if EconomyService and EconomyService.Init then EconomyService:Init() end
    if ProfileService and ProfileService.Init then ProfileService:Init() end
    bindAllSeatPrompts()
    if not hasMinPlayers() then
        setWaitingForPlayers()
    else
        -- initial state broadcast
        broadcastState()
        applyMovementLocks()
    end
end

return RoundService
