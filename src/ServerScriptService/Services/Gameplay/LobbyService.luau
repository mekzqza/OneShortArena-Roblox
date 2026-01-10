--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║              LOBBY SERVICE - PRODUCTION GRADE                  ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Manage lobby spawning and player transitions         ║
║ Features:                                                      ║
║  ✅ Smart spawn system (random spawn points)                  ║
║  ✅ Collision prevention                                       ║
║  ✅ Character respawn handling                                ║
║  ✅ Event-driven architecture                                 ║
║  ✅ Analytics tracking                                        ║
╚════════════════════════════════════════════════════════════════╝
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
-- local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.Core.NetworkHandler)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)


export type SpawnPoint = BasePart
export type LobbyService = {
	Init: (self: LobbyService) -> (),
	Start: (self: LobbyService) -> (),
	SpawnPlayerInLobby: (self: LobbyService, player: Player) -> boolean,
	GetRandomSpawnPoint: (self: LobbyService) -> SpawnPoint,
	IsSpawnPointOccupied: (self: LobbyService, spawnPoint: SpawnPoint, radius: number?) -> boolean,
	TeleportPlayerToLobby: (self: LobbyService, player: Player) -> boolean,
	GetAnalytics: (self: LobbyService) -> {[string]: any},
	GetRandomSpawnPoint: (self: LobbyService) -> SpawnPoint?,
}

local LobbyService = {} :: LobbyService

-- ✅ Create idempotent guard
local guard = IdempotentGuard.new("LobbyService", true)

-- ═══════════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════════

local SPAWN_CONFIG = {
	-- Spawn location
	LobbySpawnsFolder = nil :: Folder?,
	
	-- Spawn settings
	SpawnHeight = 3, -- Height above spawn point
	SpawnRadius = 5, -- Random offset radius
	OccupiedCheckRadius = 5, -- Radius to check for other players
	MaxSpawnAttempts = 10, -- Max attempts to find empty spawn
	
	-- Character settings
	ForceRespawn = true, -- Respawn character if doesn't exist
	RespawnDelay = 0.5, -- Wait before respawning
	
	-- Safety
	FallbackSpawn = CFrame.new(0, 50, 0), -- If no spawns available
}

-- Analytics
local analytics = {
	totalSpawns = 0,
	failedSpawns = 0,
	respawns = 0,
	averageAttempts = 0,
	startTime = os.clock(),
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

-- Wait for lobby spawns folder
local function waitForLobbySpawns(): Folder?
	local lobbySpawns = Workspace:WaitForChild("LobbySpawns", 10)
    --warn("[LobbyService] LobbySpawns found in Workspace!")
	if not lobbySpawns then
		warn("[LobbyService] ❌ LobbySpawns folder not found in Workspace!")
		return nil
	end
	
	local spawnsFolder = lobbySpawns:WaitForChild("LobbySpawns", 10)
	if not spawnsFolder then
		warn("[LobbyService] ❌ LobbySpawns/LobbySpawns folder not found!")
		return nil
	end
	
	return spawnsFolder :: Folder
end

-- Get all spawn points
local function getSpawnPoints(): {SpawnPoint}
	if not SPAWN_CONFIG.LobbySpawnsFolder then
		return {}
	end
	
	local spawnPoints = {}
	for _, child in ipairs(SPAWN_CONFIG.LobbySpawnsFolder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(spawnPoints, child)
		end
	end
	
	return spawnPoints
end

-- Calculate random position near spawn point
local function getRandomPositionNear(position: Vector3, radius: number): Vector3
	local randomX = math.random(-radius, radius)
	local randomZ = math.random(-radius, radius)
	return position + Vector3.new(randomX, SPAWN_CONFIG.SpawnHeight, randomZ)
end

-- Check if area is safe to spawn
local function isAreaSafe(position: Vector3, radius: number): boolean
	-- ✅ แก้ไข: ใช้ OverlapParams แทน Region3 (deprecated)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {}
	
	-- Check for other characters in sphere
	local partsInRegion = Workspace:GetPartBoundsInRadius(position, radius, overlapParams)
	
	for _, part in ipairs(partsInRegion) do
		-- Check if part belongs to a character
		if part.Parent and part.Parent:FindFirstChild("Humanoid") then
			return false -- Another player nearby
		end
	end
	
	return true
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function LobbyService:Init()
	-- ✅ Guard: Prevent double init
	if not guard:MarkInitialized() then
		return
	end
	
	-- Wait for lobby spawns
	SPAWN_CONFIG.LobbySpawnsFolder = waitForLobbySpawns()
	
	if not SPAWN_CONFIG.LobbySpawnsFolder then
		warn("[LobbyService] ⚠️ Initialized without spawn points!")
	else
		local spawnPoints = getSpawnPoints()
		print(string.format("[LobbyService] ✅ Found %d spawn points", #spawnPoints))
	end
	
	print("[LobbyService] 🏠 Initialized")
end

function LobbyService:Start()
	if not guard:MarkStarted() then
		return
	end
	
	-- Listen for state changes
	EventBus:On(Events.PLAYER_STATE_CHANGED_INTERNAL, function(player: Player, stateData: any)
		-- Only spawn when state is Lobby
		if stateData.newState ~= "Lobby" then
			return
		end
		
		-- ✅ NEW: Check if player is Downed (should not spawn!)
		local character = player.Character
		if character and character:GetAttribute("IsDowned") then
			warn(`[LobbyService] ⚠️ {player.Name} is Downed, not spawning to Lobby`)
			return
		end
		
		-- ✅ FIX: เพิ่ม "Downed" เข้าไปใน validPreviousStates
		local validPreviousStates = {
			["Arena"] = true,
			["Died"] = true,
			["Downed"] = true,      -- ✅ เพิ่มบรรทัดนี้!
			["Spectating"] = true,
		}
		
		if stateData.oldState and not validPreviousStates[stateData.oldState] then
			print(`[LobbyService] ⏭️ {player.Name} state: {stateData.oldState} → Lobby (not spawning)`)
			return
		end
		
		print(`[LobbyService] {player.Name} state changed to Lobby, spawning...`)
		
		local success = self:SpawnPlayerInLobby(player)
		
		if success then
			print(`[LobbyService] ✅ Spawned {player.Name} in Lobby`)
		else
			warn(`[LobbyService] ❌ Failed to spawn {player.Name}`)
		end
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- EVENT LISTENERS
	-- ═══════════════════════════════════════════════════════════
	
	-- Listen for return to lobby requests
	EventBus:On(Events.PLAYER_STATE_CHANGED_INTERNAL, function(player: Player, stateData: any)
        -- เฉพาะเมื่อ state เปลี่ยนเป็น Lobby
        if stateData.newState ~= "Lobby" then
            return
        end
        
        print(string.format("[LobbyService] %s state changed to Lobby, spawning...", player.Name))
        
        local success = self:TeleportPlayerToLobby(player)
        
        if success then
            print(string.format("[LobbyService] ✅ %s teleported to Lobby", player.Name))
            
            NetworkHandler:SendToClient(player, Events.PLAYER_TELEPORTED_TO_LOBBY, {
                success = true,
                timestamp = os.clock()
            })
        else
            warn(string.format("[LobbyService] ❌ Failed to teleport %s to Lobby", player.Name))
            
            NetworkHandler:SendToClient(player, Events.PLAYER_TELEPORTED_TO_LOBBY, {
                success = false,
                reason = "No spawn points available",
                timestamp = os.clock()
            })
        end
    end)
	
	-- ═══════════════════════════════════════════════════════════
	-- ANALYTICS
	-- ═══════════════════════════════════════════════════════════
	
	task.spawn(function()
		while true do
			task.wait(300) -- Every 5 minutes
			local stats = self:GetAnalytics()
			print("[LobbyService] 📊 Analytics:")
			print(string.format("  Total spawns: %d", stats.totalSpawns))
			print(string.format("  Failed spawns: %d", stats.failedSpawns))
			print(string.format("  Avg attempts: %.2f", stats.averageAttempts))
		end
	end)
	
	print("[LobbyService] 🚀 Started - Listening for lobby requests")
end

-- ═══════════════════════════════════════════════════════════════
-- SPAWN METHODS
-- ═══════════════════════════════════════════════════════════════

-- Get random unoccupied spawn point
function LobbyService:GetRandomSpawnPoint(): SpawnPoint?
	local spawnPoints = getSpawnPoints()
	
	if #spawnPoints == 0 then
		warn("[LobbyService] ❌ No spawn points available!")
		return nil
	end
	
	-- Try to find empty spawn point
	for attempt = 1, SPAWN_CONFIG.MaxSpawnAttempts do
		local randomSpawn = spawnPoints[math.random(1, #spawnPoints)]
		
		if not self:IsSpawnPointOccupied(randomSpawn) then
			return randomSpawn
		end
	end
	
	-- All spawns occupied, return random one anyway
	warn("[LobbyService] ⚠️ All spawns occupied, using random spawn")
	return spawnPoints[math.random(1, #spawnPoints)]
end

-- Check if spawn point is occupied
function LobbyService:IsSpawnPointOccupied(spawnPoint: SpawnPoint, radius: number?): boolean
	radius = radius or SPAWN_CONFIG.OccupiedCheckRadius
	return not isAreaSafe(spawnPoint.Position, radius)
end

-- Spawn player in lobby
function LobbyService:SpawnPlayerInLobby(player: Player): boolean
	-- Get character
	local character = player.Character
	if not character then
		if SPAWN_CONFIG.ForceRespawn then
			print(string.format("[LobbyService] 🔄 Respawning %s...", player.Name))
			player:LoadCharacter()
			analytics.respawns += 1
			task.wait(SPAWN_CONFIG.RespawnDelay)
			character = player.Character
		end
		
		if not character then
			warn(string.format("[LobbyService] ❌ No character for %s", player.Name))
			analytics.failedSpawns += 1
			return false
		end
	end
	
	-- Get spawn point
	local spawnPoint = self:GetRandomSpawnPoint()
	
	if not spawnPoint then
		-- Use fallback spawn
		warn("[LobbyService] ⚠️ Using fallback spawn position")
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			humanoidRootPart.CFrame = SPAWN_CONFIG.FallbackSpawn
		end
		analytics.failedSpawns += 1
		return false
	end
	
	-- Calculate spawn position
	local spawnPosition = getRandomPositionNear(spawnPoint.Position, SPAWN_CONFIG.SpawnRadius)
	local spawnCFrame = CFrame.new(spawnPosition)
	
	-- Teleport character
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		humanoidRootPart.CFrame = spawnCFrame
		analytics.totalSpawns += 1
		
		print(string.format("[LobbyService] ✅ Spawned %s at %s", player.Name, tostring(spawnPosition)))
		return true
	else
		warn(string.format("[LobbyService] ❌ No HumanoidRootPart for %s", player.Name))
		analytics.failedSpawns += 1
		return false
	end
end

-- Teleport existing player to lobby
function LobbyService:TeleportPlayerToLobby(player: Player): boolean
	return self:SpawnPlayerInLobby(player)
end

-- Get analytics
function LobbyService:GetAnalytics(): {[string]: any}
	local uptime = os.clock() - analytics.startTime
	
	return {
		totalSpawns = analytics.totalSpawns,
		failedSpawns = analytics.failedSpawns,
		respawns = analytics.respawns,
		averageAttempts = analytics.totalSpawns > 0 and analytics.totalSpawns / (analytics.totalSpawns + analytics.failedSpawns) or 0,
		uptime = uptime,
		spawnsPerMinute = uptime > 0 and (analytics.totalSpawns / uptime * 60) or 0,
	}
end

return LobbyService
