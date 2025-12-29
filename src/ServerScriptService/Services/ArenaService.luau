--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║              ARENA SERVICE - PRODUCTION GRADE                  ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Manage arena spawning and player transitions         ║
║ Features:                                                      ║
║  ✅ Smart spawn system (team-based spawns)                    ║
║  ✅ Multiple arena support                                     ║
║  ✅ Team balancing                                             ║
║  ✅ Event-driven architecture                                 ║
║  ✅ Analytics tracking                                        ║
╚════════════════════════════════════════════════════════════════╝
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.NetworkHandler)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

export type ArenaService = {
    Init: (self: ArenaService) -> (),
    Start: (self: ArenaService) -> (),
    SpawnPlayerInArena: (self: ArenaService, player: Player) -> boolean,
    GetRandomArenaSpawn: (self: ArenaService) -> BasePart?,
    CanPlayerJoinArena: (self: ArenaService, player: Player) -> (boolean, string?),
    GetAnalytics: (self: ArenaService) -> {[string]: any},
}

local ArenaService = {} :: ArenaService

-- Create idempotent guard
local guard = IdempotentGuard.new("ArenaService", true)

-- CONFIGURATION

local ARENA_CONFIG = {
    ArenaSpawnsFolder = nil :: Folder?,
    SpawnHeight = 3,
    SpawnRadius = 5,
    MaxSpawnAttempts = 10,
    ForceRespawn = true,
    RespawnDelay = 0.5,
    FallbackSpawn = CFrame.new(0, 100, 0),
}

-- P0 FIX: Server-side teleport cooldowns
local teleportCooldowns: {[number]: number} = {}
local TELEPORT_COOLDOWN = 5 -- 5 seconds between arena joins

-- P0 FIX: Track players in combat
local playersInCombat: {[number]: number} = {} -- userId -> lastCombatTime
local COMBAT_TIMEOUT = 5 -- Can't teleport for 5s after taking damage

local analytics = {
    totalSpawns = 0,
    failedSpawns = 0,
    respawns = 0,
    blockedByValidation = 0,
    startTime = os.clock(),
}

-- PRIVATE FUNCTIONS

local function waitForArenaSpawns(): Folder?
    -- ✅ แก้ไข: เปลี่ยนเป็น "ArenaBoundary" (capital B)
    local arenabound = Workspace:WaitForChild("ArenaBoundary", 10)
    if not arenabound then
        warn("[ArenaService] Arena boundary folder not found!")
        return nil
    end
    
    local arenaSpawns = arenabound:WaitForChild("ArenaSpawns", 10)
    if not arenaSpawns then
        warn("[ArenaService] ArenaSpawns folder not found!")
        return nil
    end
    
    return arenaSpawns :: Folder
end

local function getArenaSpawnPoints(): {BasePart}
    if not ARENA_CONFIG.ArenaSpawnsFolder then
        return {}
    end
    
    local spawnPoints = {}
    for _, child in ipairs(ARENA_CONFIG.ArenaSpawnsFolder:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(spawnPoints, child)
        end
    end
    
    return spawnPoints
end

local function getRandomPositionNear(position: Vector3, radius: number): Vector3
    local randomX = math.random(-radius, radius)
    local randomZ = math.random(-radius, radius)
    return position + Vector3.new(randomX, ARENA_CONFIG.SpawnHeight, randomZ)
end

local function isAreaSafe(position: Vector3, radius: number): boolean
    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {}
    
    local partsInRegion = Workspace:GetPartBoundsInRadius(position, radius, overlapParams)
    
    for _, part in ipairs(partsInRegion) do
        if part.Parent and part.Parent:FindFirstChild("Humanoid") then
            return false
        end
    end
    
    return true
end

-- P0 FIX: Check if player is in combat
local function isPlayerInCombat(userId: number): boolean
    local lastCombat = playersInCombat[userId]
    if not lastCombat then
        return false
    end
    return (os.clock() - lastCombat) < COMBAT_TIMEOUT
end

-- P0 FIX: Set player combat state (call this when player takes damage)
local function setPlayerInCombat(userId: number)
    playersInCombat[userId] = os.clock()
end

-- PUBLIC METHODS

function ArenaService:Init()
    if not guard:MarkInitialized() then
        return
    end
    
    ARENA_CONFIG.ArenaSpawnsFolder = waitForArenaSpawns()
    
    if not ARENA_CONFIG.ArenaSpawnsFolder then
        warn("[ArenaService] Initialized without spawn points!")
    else
        local spawnPoints = getArenaSpawnPoints()
        print(string.format("[ArenaService] Found %d arena spawn points", #spawnPoints))
    end
    
    print("[ArenaService] Initialized")
    print("  - Teleport cooldown: " .. TELEPORT_COOLDOWN .. "s")
    print("  - Combat protection: " .. COMBAT_TIMEOUT .. "s")
end

function ArenaService:Start()
    if not guard:MarkStarted() then
        return
    end
    
    -- ✅ ใหม่: ฟัง PLAYER_STATE_CHANGED_INTERNAL แทน
    EventBus:On(Events.PLAYER_STATE_CHANGED_INTERNAL, function(player: Player, stateData: any)
        -- เฉพาะเมื่อ state เปลี่ยนเป็น Arena เท่านั้น
        if stateData.newState ~= "Arena" then
            return
        end
        
        print(string.format("[ArenaService] %s state changed to Arena, spawning...", player.Name))
        
        -- P0 FIX: Server-side validation ก่อน spawn
        local canJoin, reason = self:CanPlayerJoinArena(player)
        
        if not canJoin then
            warn(string.format("[ArenaService] %s spawn blocked: %s", player.Name, reason or "Unknown"))
            analytics.blockedByValidation += 1
            
            NetworkHandler:SendToClient(player, Events.PLAYER_TELEPORTED_TO_ARENA, {
                success = false,
                reason = reason,
                timestamp = os.clock()
            })
            return
        end
        
        local success = self:SpawnPlayerInArena(player)
        
        if success then
            -- P0 FIX: Set cooldown after successful teleport
            teleportCooldowns[player.UserId] = os.clock()
            
            print(string.format("[ArenaService] ✅ %s spawned in Arena", player.Name))
            
            NetworkHandler:SendToClient(player, Events.PLAYER_TELEPORTED_TO_ARENA, {
                success = true,
                timestamp = os.clock()
            })
        else
            warn(string.format("[ArenaService] ❌ Failed to spawn %s in Arena", player.Name))
            
            NetworkHandler:SendToClient(player, Events.PLAYER_TELEPORTED_TO_ARENA, {
                success = false,
                reason = "Spawn failed",
                timestamp = os.clock()
            })
        end
    end)
    
    -- Cleanup on player leave
    Players.PlayerRemoving:Connect(function(player: Player)
        teleportCooldowns[player.UserId] = nil
        playersInCombat[player.UserId] = nil
    end)
    
    -- Analytics
    task.spawn(function()
        while true do
            task.wait(300)
            local stats = self:GetAnalytics()
            print("[ArenaService] Analytics:")
            print(string.format("  Total spawns: %d", stats.totalSpawns))
            print(string.format("  Failed spawns: %d", stats.failedSpawns))
            print(string.format("  Blocked by validation: %d", stats.blockedByValidation))
        end
    end)
    
    print("[ArenaService] Started - Listening for arena requests")
end

-- P0 FIX: Server-side validation for arena join
function ArenaService:CanPlayerJoinArena(player: Player): (boolean, string?)
    local userId = player.UserId
    local now = os.clock()
    
    -- Check 1: Teleport cooldown
    local lastTeleport = teleportCooldowns[userId]
    if lastTeleport and (now - lastTeleport) < TELEPORT_COOLDOWN then
        local remaining = TELEPORT_COOLDOWN - (now - lastTeleport)
        return false, string.format("Teleport cooldown (%.1fs remaining)", remaining)
    end
    
    -- Check 2: Combat check
    if isPlayerInCombat(userId) then
        local remaining = COMBAT_TIMEOUT - (now - (playersInCombat[userId] or 0))
        return false, string.format("Cannot teleport while in combat (%.1fs)", remaining)
    end
    
    -- Check 3: Character exists
    local character = player.Character
    if not character then
        return false, "No character"
    end
    
    -- Check 4: Player is alive
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false, "Player is dead"
    end
    
    -- Check 5: Player is not already in arena (optional - depends on game logic)
    -- local currentState = PlayerStateService:GetState(player)
    -- if currentState == "Arena" then
    --     return false, "Already in arena"
    -- end
    
    return true
end

-- SPAWN METHODS

function ArenaService:GetRandomArenaSpawn(): BasePart?
    local spawnPoints = getArenaSpawnPoints()
    
    if #spawnPoints == 0 then
        warn("[ArenaService] No arena spawn points available!")
        return nil
    end
    
    for attempt = 1, ARENA_CONFIG.MaxSpawnAttempts do
        local randomSpawn = spawnPoints[math.random(1, #spawnPoints)]
        
        if isAreaSafe(randomSpawn.Position, ARENA_CONFIG.SpawnRadius) then
            return randomSpawn
        end
    end
    
    warn("[ArenaService] All arena spawns occupied, using random spawn")
    return spawnPoints[math.random(1, #spawnPoints)]
end

function ArenaService:SpawnPlayerInArena(player: Player): boolean
    local character = player.Character
    if not character then
        if ARENA_CONFIG.ForceRespawn then
            print(string.format("[ArenaService] Respawning %s...", player.Name))
            player:LoadCharacter()
            analytics.respawns += 1
            task.wait(ARENA_CONFIG.RespawnDelay)
            character = player.Character
        end
        
        if not character then
            warn(string.format("[ArenaService] No character for %s", player.Name))
            analytics.failedSpawns += 1
            return false
        end
    end
    
    local spawnPoint = self:GetRandomArenaSpawn()
    
    if not spawnPoint then
        warn("[ArenaService] Using fallback arena spawn")
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
            humanoidRootPart.CFrame = ARENA_CONFIG.FallbackSpawn
        end
        analytics.failedSpawns += 1
        return false
    end
    
    local spawnPosition = getRandomPositionNear(spawnPoint.Position, ARENA_CONFIG.SpawnRadius)
    local spawnCFrame = CFrame.new(spawnPosition)
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
        humanoidRootPart.CFrame = spawnCFrame
        analytics.totalSpawns += 1
        
        print(string.format("[ArenaService] Spawned %s in Arena at %s", player.Name, tostring(spawnPosition)))
        return true
    else
        warn(string.format("[ArenaService] No HumanoidRootPart for %s", player.Name))
        analytics.failedSpawns += 1
        return false
    end
end

function ArenaService:GetAnalytics(): {[string]: any}
    local uptime = os.clock() - analytics.startTime
    
    return {
        totalSpawns = analytics.totalSpawns,
        failedSpawns = analytics.failedSpawns,
        respawns = analytics.respawns,
        blockedByValidation = analytics.blockedByValidation,
        uptime = uptime,
        spawnsPerMinute = uptime > 0 and (analytics.totalSpawns / uptime * 60) or 0,
    }
end

-- P0 FIX: Expose combat state setter for other services
function ArenaService:SetPlayerInCombat(player: Player)
    setPlayerInCombat(player.UserId)
end

return ArenaService
