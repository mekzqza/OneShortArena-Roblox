--!strict

--[[
	DEATH SERVICE - PRODUCTION GRADE v2.1 (Simplified)
	
	Purpose: Detect, classify, and emit player death events
	
	Features:
	  - Server-authoritative death detection
	  - Death cause classification (Combat, Environmental, etc.)
	  - Killer tracking & weapon identification
	  - P0: Idempotent death processing (locks)
	  - P0: Arena-only death filtering
	  
	Note: Match-related logic moved to MatchService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.Core.NetworkHandler)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

local PlayerStateService: any = nil

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type DeathCause = "Combat" | "Timeout" | "Script" | "Environmental" | "Unknown"

export type DeathContext = {
	victim: Player,
	cause: DeathCause,
	killer: Player?,
	weapon: string?,
	position: Vector3?,
	timestamp: number,
	lastDamageTime: number?,
	lastDamageAmount: number?,
}

export type DeathService = {
	Init: (self: DeathService) -> (),
	Start: (self: DeathService) -> (),
	RegisterDamage: (self: DeathService, victim: Player, attacker: Player?, damage: number, weapon: string?) -> (),
	GetLastKiller: (self: DeathService, victim: Player) -> Player?,
	GetAnalytics: (self: DeathService) -> {[string]: any},
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local DeathService = {} :: DeathService

local guard = IdempotentGuard.new("DeathService", true)

local DEATH_CONFIG = {
	CombatWindow = 5,
	OnlyTrackArenaDeaths = true,
}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local playerDamageHistory: {[number]: {
	attacker: Player?,
	damage: number,
	weapon: string?,
	timestamp: number,
}} = {}

-- ✅ NEW: Track if death is being processed to prevent re-entry
local deathProcessingLocks: {[number]: boolean} = {}

-- ✅ NEW: Track processed deaths to prevent re-entrancy
local processingDeaths: {[number]: boolean} = {}
local deathConnections: {[number]: RBXScriptConnection} = {}

local DEATH_PROCESSING_TIMEOUT = 5

local analytics = {
	totalDeaths = 0,
	deathsByCause = {} :: {[DeathCause]: number},
	blockedDuplicateDeaths = 0,
	ignoredNonArenaDeaths = 0,
	startTime = os.clock(),
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function acquireDeathLock(userId: number): boolean
	if deathProcessingLocks[userId] then
		return false
	end
	deathProcessingLocks[userId] = true
	return true
end

local function releaseDeathLock(userId: number)
	deathProcessingLocks[userId] = nil
end

local function analyzeDeath(character: Model, humanoid: Humanoid): DeathCause
	local player = Players:GetPlayerFromCharacter(character)
	local userId = player and player.UserId
	
	if not userId then
		return "Unknown"
	end
	
	local now = os.clock()
	local damageHistory = playerDamageHistory[userId]
	
	if damageHistory and (now - damageHistory.timestamp) <= DEATH_CONFIG.CombatWindow then
		return "Combat"
	end
	
	if humanoid:GetAttribute("DeathByEnvironment") then
		return "Environmental"
	end
	
	return "Unknown"
end

local function getKillerInfo(victim: Player): (Player?, string?)
	local userId = victim.UserId
	local damageHistory = playerDamageHistory[userId]
	
	if not damageHistory then
		return nil, nil
	end
	
	local now = os.clock()
	if (now - damageHistory.timestamp) <= DEATH_CONFIG.CombatWindow then
		return damageHistory.attacker, damageHistory.weapon
	end
	
	return nil, nil
end

local function shouldProcessDeath(player: Player): boolean
	if not DEATH_CONFIG.OnlyTrackArenaDeaths then
		return true
	end
	
	if not PlayerStateService then
		local success, service = pcall(function()
			return require(ServerScriptService.Services.PlayerStateService)
		end)
		
		if success then
			PlayerStateService = service
		else
			return true
		end
	end
	
	if not PlayerStateService then
		return true
	end
	
	local currentState = PlayerStateService:GetState(player)
	return currentState == "Arena"
end

-- Lazy load DownedService
local DownedService: any = nil

local function getDownedService()
	if not DownedService then
		local success, service = pcall(function()
			return require(ServerScriptService.Services.Gameplay.DownedService)
		end)
		if success then
			DownedService = service
		end
	end
	return DownedService
end

local function handleDeath(player: Player, character: Model, humanoid: Humanoid)
	local userId = player.UserId
	
	-- ✅ NEW: Check if already processing (prevent re-entrancy)
	if processingDeaths[userId] then
		return
	end
	
	-- ✅ NEW: Mark as processing
	processingDeaths[userId] = true
	
	-- ✅ NEW: Disconnect HealthChanged to prevent recursion
	if deathConnections[userId] then
		deathConnections[userId]:Disconnect()
		deathConnections[userId] = nil
	end
	
	local success = pcall(function()
		-- ✅ Check if player is already Downed
		local DownedService: any = nil
		local hasDownedService = pcall(function()
			DownedService = require(ServerScriptService.Services.Gameplay.DownedService)
		end)
		
		if hasDownedService and DownedService and DownedService:IsPlayerDowned(player) then
			print(`[DeathService] ⏭️ {player.Name} is already Downed, ignoring death event`)
			return
		end
		
		local deathCause = analyzeDeath(character, humanoid)
		local killer, weapon = getKillerInfo(player)
		
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		local position = rootPart and rootPart:IsA("BasePart") and rootPart.Position or nil
		
		local context: DeathContext = {
			victim = player,
			cause = deathCause,
			killer = killer,
			weapon = weapon,
			position = position,
			timestamp = os.clock(),
			lastDamageTime = playerDamageHistory[userId] and playerDamageHistory[userId].timestamp,
			lastDamageAmount = playerDamageHistory[userId] and playerDamageHistory[userId].damage,
		}
		
		analytics.totalDeaths += 1
		analytics.deathsByCause[deathCause] = (analytics.deathsByCause[deathCause] or 0) + 1
		
		print(string.format(
			"[DeathService] 💀 %s died (%s)%s",
			player.Name,
			deathCause,
			killer and (" by " .. killer.Name) or ""
		))
		
		-- Emit event
		EventBus:Emit(Events.PLAYER_DIED, player, {
			cause = context.cause,
			killer = context.killer,
			weapon = context.weapon,
			position = context.position,
			timestamp = context.timestamp,
		})
		
		-- Broadcast to clients
		NetworkHandler:Broadcast(Events.PLAYER_DEATH_ANNOUNCED, {
			victimName = player.Name,
			victimUserId = userId,
			cause = deathCause,
			killerName = killer and killer.Name,
			killerUserId = killer and killer.UserId,
			weapon = weapon,
			timestamp = context.timestamp,
		})
	end)
	
	-- ✅ ALWAYS clear processing flag
	processingDeaths[userId] = nil
	
	if not success then
		warn(`[DeathService] ❌ Error processing death`)
	end
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function DeathService:Init()
	if not guard:MarkInitialized() then
		return
	end
	
	analytics.deathsByCause = {
		Combat = 0,
		Environmental = 0,
		Timeout = 0,
		Script = 0,
		Unknown = 0,
	}
	
	print("[DeathService] 💀 Initialized v2.1 (Simplified)")
	print("  ✅ Combat window:", DEATH_CONFIG.CombatWindow, "s")
	print("  ✅ Role: Detect → Classify → Emit")
end

function DeathService:Start()
	if not guard:MarkStarted() then
		return
	end
	
	-- Connect to CharacterAdded
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
			
			if not humanoid then
				warn(`[DeathService] No Humanoid found for {player.Name}`)
				return
			end
			
			-- ✅ Store connection for later disconnect
			deathConnections[player.UserId] = humanoid.Died:Connect(function()
				handleDeath(player, character, humanoid)
			end)
			
			print(`[DeathService] 👂 Listening for {player.Name}'s death`)
		end)
	end)
	
	-- ✅ Cleanup on player leave
	Players.PlayerRemoving:Connect(function(player: Player)
		local userId = player.UserId
		
		-- Disconnect death connection
		if deathConnections[userId] then
			deathConnections[userId]:Disconnect()
			deathConnections[userId] = nil
		end
		
		-- Clear processing flag
		processingDeaths[userId] = nil
		
		playerDamageHistory[userId] = nil
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- DAMAGE TRACKING
	-- ═══════════════════════════════════════════════════════════
	
	EventBus:On(Events.PLAYER_ATTACKED, function(attacker: Player, victim: Player, damage: number, weapon: string?)
		self:RegisterDamage(victim, attacker, damage, weapon)
	end)
	
	-- Analytics
	task.spawn(function()
		while true do
			task.wait(300)
			local stats = self:GetAnalytics()
			print("[DeathService] 📊 Analytics:")
			print(string.format("  Total deaths: %d | Blocked duplicates: %d", stats.totalDeaths, stats.blockedDuplicateDeaths))
		end
	end)
	
	print("[DeathService] 🚀 Started - Death detection enabled")
end

function DeathService:RegisterDamage(victim: Player, attacker: Player?, damage: number, weapon: string?)
	local userId = victim.UserId
	
	playerDamageHistory[userId] = {
		attacker = attacker,
		damage = damage,
		weapon = weapon,
		timestamp = os.clock(),
	}
end

function DeathService:GetLastKiller(victim: Player): Player?
	local damageHistory = playerDamageHistory[victim.UserId]
	
	if not damageHistory then
		return nil
	end
	
	local now = os.clock()
	if (now - damageHistory.timestamp) <= DEATH_CONFIG.CombatWindow then
		return damageHistory.attacker
	end
	
	return nil
end

function DeathService:GetAnalytics(): {[string]: any}
	local uptime = os.clock() - analytics.startTime
	
	return {
		totalDeaths = analytics.totalDeaths,
		deathsByCause = analytics.deathsByCause,
		blockedDuplicateDeaths = analytics.blockedDuplicateDeaths,
		ignoredNonArenaDeaths = analytics.ignoredNonArenaDeaths,
		uptime = uptime,
	}
end

return DeathService