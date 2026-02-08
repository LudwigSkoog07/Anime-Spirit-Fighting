-- MapService: ensures a larger workspace map exists (dev-friendly placeholder creation)
local Workspace = game:GetService("Workspace")

local MapService = {}
local AUTO_SEAT_COUNT = 16
local AUTO_SEAT_RADIUS = 56
local AUTO_SEAT_BASE_Y = 1.5
local AUTO_SEAT_ALT_Y_OFFSET = -0.6
local AUTO_RING_CENTER_Z = 0
local AUTO_RING_SPAWN_OFFSET = 22

local function makePart(parent, name, size, cframe)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size or Vector3.new(4,1,4)
    p.Anchored = true
    p.CanCollide = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p:SetAttribute("AFS_AutoCreated", true)
    if cframe then p.CFrame = cframe end
    p.Parent = parent
    return p
end

local function makeFolder(parent, name)
    local f = parent:FindFirstChild(name)
    if f and f:IsA("Folder") then return f end
    f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

local function repositionAutoPart(part, position)
    if not part or not part:IsA("BasePart") then
        return
    end
    if part:GetAttribute("AFS_AutoCreated") ~= true then
        return
    end
    part.CFrame = CFrame.new(position)
end

function MapService:GetOrCreateMap()
    local created = false
    -- Top-level container
    local mapRoot = Workspace:FindFirstChild("Map")
    if not mapRoot then
        mapRoot = Instance.new("Folder")
        mapRoot.Name = "Map"
        mapRoot:SetAttribute("AFS_AutoCreated", true)
        mapRoot.Parent = Workspace
        created = true
    end

    -- Lobby area
    local lobby = makeFolder(mapRoot, "Lobby")
    local seatsFolder = makeFolder(lobby, "Seats")
    -- Seat prompts folder (for easy replacement)
    local seatPromptsFolder = makeFolder(lobby, "SeatPrompts")

    -- Lobby platform: delete auto-generated grey plate if present (do not recreate)
    local lobbyPlatform = lobby:FindFirstChild("Platform")
    if lobbyPlatform and lobbyPlatform:IsA("BasePart") then
        local isAuto = lobbyPlatform:GetAttribute("AFS_AutoCreated") == true
            or (lobbyPlatform.Size == Vector3.new(260, 2, 260) and lobbyPlatform.BrickColor == BrickColor.new("Medium stone grey"))
        if isAuto then
            lobbyPlatform:Destroy()
            lobbyPlatform = nil
            created = true
        end
    end

    -- Seats: use custom seats if provided, otherwise create 16 around a circle
    local seats = {}
    local existingSeats = seatsFolder:GetChildren()
    local function ensureSeatPrompt(seat)
        if not seat:FindFirstChildOfClass("ProximityPrompt") then
            local pp = Instance.new("ProximityPrompt")
            pp.ObjectText = "Seat"
            pp.ActionText = "Challenge"
            pp.HoldDuration = 0
            pp.MaxActivationDistance = 16
            pp.Parent = seat
        end
        if not seat:FindFirstChild("SeatAttachment") then
            local att = Instance.new("Attachment") att.Name = "SeatAttachment" att.Parent = seat
        end
    end

    local index = 0
    for _, seat in ipairs(existingSeats) do
        if seat:IsA("BasePart") then
            index = index + 1
            if seat:GetAttribute("SeatIndex") == nil then
                seat:SetAttribute("SeatIndex", index)
            end
            ensureSeatPrompt(seat)
            local isAuto = seat:GetAttribute("AFS_AutoCreated") == true
                or (seat.Size == Vector3.new(10, 1.5, 10) and seat.BrickColor == BrickColor.new("Really black"))
            local seatIndex = seat:GetAttribute("SeatIndex")
            if isAuto and seatIndex then
                local angle = (seatIndex - 1) * (2 * math.pi / AUTO_SEAT_COUNT)
                local x = math.cos(angle) * AUTO_SEAT_RADIUS
                local z = math.sin(angle) * AUTO_SEAT_RADIUS
                local y = AUTO_SEAT_BASE_Y
                if seatIndex % 2 == 0 then
                    y = y + AUTO_SEAT_ALT_Y_OFFSET
                end
                seat.CFrame = CFrame.new(x, y, z)
                seat:SetAttribute("AFS_AltSeatOffsetApplied", true)
                seat:SetAttribute("AFS_CompactLayoutV2", true)
            end
            table.insert(seats, seat)
        end
    end

    if #seats == 0 then
        local seatCount = AUTO_SEAT_COUNT
        local radius = AUTO_SEAT_RADIUS
        for i=1,seatCount do
            local seatName = string.format("Seat%02d", i)
            local seat = seatsFolder:FindFirstChild(seatName)
            if not seat then
                local angle = (i-1) * (2*math.pi / seatCount)
                local x = math.cos(angle) * radius
                local z = math.sin(angle) * radius
                local y = AUTO_SEAT_BASE_Y
                if i % 2 == 0 then
                    y = y + AUTO_SEAT_ALT_Y_OFFSET
                end
                local cf = CFrame.new(x, y, z)
                seat = makePart(seatsFolder, seatName, Vector3.new(10,1.5,10), cf)
                seat.BrickColor = BrickColor.new("Really black")
                seat.Transparency = 0.05
                seat:SetAttribute("SeatIndex", i)
                seat:SetAttribute("AFS_AltSeatOffsetApplied", true)
                created = true
            end
            ensureSeatPrompt(seat)
            table.insert(seats, seat)
        end
    end

    -- Arena area (placed in the middle of the lobby seats)
    local arenaRoot = makeFolder(mapRoot, "Arena")
    local arenaPlatform = arenaRoot:FindFirstChild("Platform")
    if arenaPlatform and arenaPlatform:IsA("BasePart") then
        local isAuto = arenaPlatform:GetAttribute("AFS_AutoCreated") == true
            or (arenaPlatform.Size == Vector3.new(220, 2, 220) and arenaPlatform.BrickColor == BrickColor.new("Dark stone grey"))
        if isAuto then
            arenaPlatform:Destroy()
            arenaPlatform = nil
            created = true
        end
    end

    local ringFolder = makeFolder(arenaRoot, "Ring")
    local ringSpawns = makeFolder(ringFolder, "RingSpawns")

    local centerZ = AUTO_RING_CENTER_Z
    local spiritSpawn = ringSpawns:FindFirstChild("SpiritSpawn")
    if not spiritSpawn then
        spiritSpawn = makePart(ringSpawns, "SpiritSpawn", Vector3.new(6,1,6), CFrame.new(0, 2, centerZ - AUTO_RING_SPAWN_OFFSET)) -- near one edge
        spiritSpawn.BrickColor = BrickColor.new("Bright blue")
        spiritSpawn:SetAttribute("SpawnType", "Spirit")
        created = true
    end
    repositionAutoPart(spiritSpawn, Vector3.new(0, 2, centerZ - AUTO_RING_SPAWN_OFFSET))

    local challengerSpawn = ringSpawns:FindFirstChild("ChallengerSpawn")
    if not challengerSpawn then
        challengerSpawn = makePart(ringSpawns, "ChallengerSpawn", Vector3.new(6,1,6), CFrame.new(0, 2, centerZ + AUTO_RING_SPAWN_OFFSET))
        challengerSpawn.BrickColor = BrickColor.new("Bright red")
        challengerSpawn:SetAttribute("SpawnType", "Challenger")
        created = true
    end
    repositionAutoPart(challengerSpawn, Vector3.new(0, 2, centerZ + AUTO_RING_SPAWN_OFFSET))

    local allySpawn = ringSpawns:FindFirstChild("AllySpawn")
    if not allySpawn then
        allySpawn = makePart(ringSpawns, "AllySpawn", Vector3.new(6,1,6), CFrame.new(AUTO_RING_SPAWN_OFFSET, 2, centerZ + AUTO_RING_SPAWN_OFFSET))
        allySpawn.BrickColor = BrickColor.new("Bright yellow")
        allySpawn:SetAttribute("SpawnType", "Ally")
        created = true
    end
    repositionAutoPart(allySpawn, Vector3.new(AUTO_RING_SPAWN_OFFSET, 2, centerZ + AUTO_RING_SPAWN_OFFSET))

    -- ring center marker
    local ringCenter = ringFolder:FindFirstChild("Center")
    if not ringCenter then
        ringCenter = makePart(ringFolder, "Center", Vector3.new(1,1,1), CFrame.new(0,2,centerZ))
        ringCenter.BrickColor = BrickColor.new("Lime green")
        ringCenter.Transparency = 0.5
        created = true
    end
    repositionAutoPart(ringCenter, Vector3.new(0, 2, centerZ))

    if created then
        warn("[MapService] Missing map parts were auto-created for dev. Consider adding a proper map in Studio.")
    end

    return {
        MapRoot = mapRoot,
        Lobby = lobby,
        SeatsFolder = seatsFolder,
        Seats = seats,
        SeatPromptsFolder = seatPromptsFolder,
        Arena = arenaRoot,
        RingFolder = ringFolder,
        RingSpawns = ringSpawns,
        SpiritSpawn = spiritSpawn,
        ChallengerSpawn = challengerSpawn,
        AllySpawn = allySpawn,
        RingCenter = ringCenter,
        LobbyPlatform = lobbyPlatform,
        ArenaPlatform = arenaPlatform,
    }
end

return MapService
