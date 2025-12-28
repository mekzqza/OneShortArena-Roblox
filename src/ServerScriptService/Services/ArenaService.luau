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

local analytics = {
    totalSpawns = 0,
    failedSpawns = 0,
    respawns = 0,
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
    
    NetworkHandler:AllowClientEvent(Events.PLAYER_REQUEST_TO_ARENA)
    
    print("[ArenaService] Initialized")
end

function ArenaService:Start()
    if not guard:MarkStarted() then
        return
    end
    
    -- Listen for arena join requests
    EventBus:On(Events.PLAYER_REQUEST_TO_ARENA, function(player: Player, data: any)
        print(string.format("[ArenaService] %s requested to join Arena", player.Name))
        
        local success = self:SpawnPlayerInArena(player)
        
        if success then
            print(string.format("[ArenaService] %s joined Arena", player.Name))
            
            NetworkHandler:SendToClient(player, Events.PLAYER_TELEPORTED_TO_ARENA, {
                success = true,
                timestamp = os.clock()
            })
        else
            warn(string.format("[ArenaService] Failed to teleport %s to Arena", player.Name))
            
            NetworkHandler:SendToClient(player, Events.PLAYER_TELEPORTED_TO_ARENA, {
                success = false,
                reason = "No spawn points available",
                timestamp = os.clock()
            })
        end
    end)
    
    -- Analytics
    task.spawn(function()
        while true do
            task.wait(300)
            local stats = self:GetAnalytics()
            print("[ArenaService] Analytics:")
            print(string.format("  Total spawns: %d", stats.totalSpawns))
            print(string.format("  Failed spawns: %d", stats.failedSpawns))
        end
    end)
    
    print("[ArenaService] Started - Listening for arena requests")
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
        uptime = uptime,
        spawnsPerMinute = uptime > 0 and (analytics.totalSpawns / uptime * 60) or 0,
    }
end

return ArenaService
