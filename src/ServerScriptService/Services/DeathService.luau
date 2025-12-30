--!strict

--[[
	DEATH SERVICE - PRODUCTION GRADE
	
	Purpose: Detect, interpret, and handle player deaths
	
	Features:
	  - Server-authoritative death detection
	  - Death cause classification (Combat, Fall, Timeout, etc.)
	  - Killer tracking & weapon identification
	  - PlayerStateService integration
	  - Death analytics & tracking
	  - Configurable respawn behavior
	  - P0: Idempotent death processing (locks)
	  - P0: Arena-only death filtering
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.NetworkHandler)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- ✅ P1: Import PlayerStateService for state checking
local PlayerStateService: any = nil  -- Lazy load to avoid circular dependency

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

export type DeathRecord = {
	deathId: string,
	context: DeathContext,
	respawnTime: number?,
	respawnLocation: "Lobby" | "Arena" | "LastPosition"?,
}

export type DeathService = {
	Init: (self: DeathService) -> (),
	Start: (self: DeathService) -> (),
	HandleDeath: (self: DeathService, context: DeathContext) -> (),
	RegisterDamage: (self: DeathService, victim: Player, attacker: Player?, damage: number, weapon: string?) -> (),
	GetLastKiller: (self: DeathService, victim: Player) -> Player?,
	GetDeathHistory: (self: DeathService, player: Player) -> {DeathRecord},
	GetAnalytics: (self: DeathService) -> {[string]: any},
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local DeathService = {} :: DeathService

local guard = IdempotentGuard.new("DeathService", true)

-- Death detection config
local DEATH_CONFIG = {
	-- Combat tracking
	CombatWindow = 5,
	
	-- Respawn behavior
	RespawnDelay = 3,
	DefaultRespawnLocation = "Lobby",
	
	-- ✅ P0: Death filtering
	OnlyTrackArenaDeaths = true,  -- Only process deaths in Arena state
	
	-- Death cause priority (higher = more important)
	CausePriority = {
		Combat = 3,
		Environmental = 2,
		Timeout = 1,
		Script = 1,
		Unknown = 0,
	},
}

-- State tracking
local playerDamageHistory: {[number]: {
	attacker: Player?,
	damage: number,
	weapon: string?,
	timestamp: number,
}} = {}

-- ✅ P2: Multi-attacker damage tracking
local playerAllDamageHistory: {[number]: {{
	attacker: Player?,
	damage: number,
	weapon: string?,
	timestamp: number,
}}} = {}

local deathRecords: {[number]: {DeathRecord}} = {}

local recentDeaths: {[number]: number} = {}

-- ✅ P0 FIX: Death processing locks
local deathProcessingLocks: {[number]: boolean} = {}
local DEATH_PROCESSING_TIMEOUT = 5

-- Analytics
local analytics = {
	totalDeaths = 0,
	deathsByCause = {} :: {[DeathCause]: number},
	playerDeathCounts = {} :: {[number]: number},
	killStreaks = {} :: {[number]: number},
	longestKillStreak = 0,
	blockedDuplicateDeaths = 0,
	ignoredNonArenaDeaths = 0,  -- ✅ P0: Track filtered deaths
	startTime = os.clock(),
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

-- ✅ P0 FIX: Acquire death processing lock
local function acquireDeathLock(userId: number): boolean
	if deathProcessingLocks[userId] then
		analytics.blockedDuplicateDeaths += 1
		return false
	end
	
	deathProcessingLocks[userId] = true
	
	-- Auto-release after timeout (safety)
	task.delay(DEATH_PROCESSING_TIMEOUT, function()
		if deathProcessingLocks[userId] then
			warn(`[DeathService] ⏱️ Death lock auto-released for user {userId} after {DEATH_PROCESSING_TIMEOUT}s`)
			deathProcessingLocks[userId] = nil
		end
	end)
	
	return true
end

-- ✅ P0 FIX: Release death processing lock
local function releaseDeathLock(userId: number)
	deathProcessingLocks[userId] = nil
end

local function generateDeathId(): string
	return tostring(os.clock()) .. "_" .. tostring(math.random(1000, 9999))
end

local function analyzeDeath(character: Model, humanoid: Humanoid): DeathCause
	local player = Players:GetPlayerFromCharacter(character)
	local userId = player and player.UserId
	
	if not userId then
		return "Unknown"
	end
	
	local now = os.clock()
	local damageHistory = playerDamageHistory[userId]
	
	-- Check combat death (damaged recently)
	if damageHistory and (now - damageHistory.timestamp) <= DEATH_CONFIG.CombatWindow then
		return "Combat"
	end
	
	-- Check environmental
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

local function updateKillStreak(killer: Player, victim: Player)
	local killerUserId = killer.UserId
	local victimUserId = victim.UserId
	
	analytics.killStreaks[killerUserId] = (analytics.killStreaks[killerUserId] or 0) + 1
	analytics.killStreaks[victimUserId] = 0
	
	if analytics.killStreaks[killerUserId] > analytics.longestKillStreak then
		analytics.longestKillStreak = analytics.killStreaks[killerUserId]
	end
	
	EventBus:Emit(Events.PLAYER_KILL_STREAK, killer, analytics.killStreaks[killerUserId])
end

local function determineRespawnLocation(context: DeathContext): "Lobby" | "Arena" | "LastPosition"
	-- Always respawn in Lobby for now
	return "Lobby"
end

local function cleanupOldRecords(userId: number)
	local records = deathRecords[userId]
	if not records then
		return
	end
	
	while #records > 10 do
		table.remove(records, 1)
	end
end

-- ✅ P0: Check if player is in Arena (should process death)
local function shouldProcessDeath(player: Player): boolean
	if not DEATH_CONFIG.OnlyTrackArenaDeaths then
		return true  -- Process all deaths
	end
	
	-- Lazy load PlayerStateService
	if not PlayerStateService then
		local success, service = pcall(function()
			return require(ServerScriptService.Services.PlayerStateService)
		end)
		
		if success then
			PlayerStateService = service
		else
			warn("[DeathService] Failed to load PlayerStateService, allowing death")
			return true
		end
	end
	
	if not PlayerStateService then
		return true
	end
	
	local currentState = PlayerStateService:GetState(player)
	return currentState == "Arena"
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function DeathService:Init()
	if not guard:MarkInitialized() then
		return
	end
	
	for cause in pairs(DEATH_CONFIG.CausePriority) do
		analytics.deathsByCause[cause] = 0
	end
	
	print("[DeathService] 💀 Initialized")
	print("  ✅ Combat window:", DEATH_CONFIG.CombatWindow, "s")
	print("  ✅ Respawn delay:", DEATH_CONFIG.RespawnDelay, "s")
	print("  ✅ Arena-only tracking:", DEATH_CONFIG.OnlyTrackArenaDeaths)
end

function DeathService:Start()
	if not guard:MarkStarted() then
		return
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- PLAYER LIFECYCLE
	-- ═══════════════════════════════════════════════════════════
	
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			local humanoid = character:WaitForChild("Humanoid", 5)
			
			if not humanoid or not humanoid:IsA("Humanoid") then
				return
			end
			
			-- ✅ Server-authoritative death detection
			humanoid.Died:Connect(function()
				-- ✅ P0: Filter non-Arena deaths BEFORE acquiring lock
				if not shouldProcessDeath(player) then
					analytics.ignoredNonArenaDeaths += 1
					print(`[DeathService] ⏭️ {player.Name} died outside Arena (ignored)`)
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
					lastDamageTime = playerDamageHistory[player.UserId] and playerDamageHistory[player.UserId].timestamp,
					lastDamageAmount = playerDamageHistory[player.UserId] and playerDamageHistory[player.UserId].damage,
				}
				
				self:HandleDeath(context)
			end)
			
			-- Track health changes
			humanoid.HealthChanged:Connect(function(health)
				if health < humanoid.MaxHealth and health > 0 then
					local lastHealth = humanoid:GetAttribute("LastHealth") or humanoid.MaxHealth
					local damage = lastHealth - health
					
					humanoid:SetAttribute("LastHealth", health)
					
					EventBus:Emit(Events.PLAYER_DAMAGED, player, damage)
				end
			end)
			
			humanoid:SetAttribute("LastHealth", humanoid.Health)
		end)
	end)
	
	Players.PlayerRemoving:Connect(function(player: Player)
		local userId = player.UserId
		
		playerDamageHistory[userId] = nil
		playerAllDamageHistory[userId] = nil
		recentDeaths[userId] = nil
		deathProcessingLocks[userId] = nil
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- DAMAGE TRACKING
	-- ═══════════════════════════════════════════════════════════
	
	EventBus:On(Events.PLAYER_ATTACKED, function(attacker: Player, victim: Player, damage: number, weapon: string?)
		self:RegisterDamage(victim, attacker, damage, weapon)
	end)
	
	-- ✅ P1: Listen for respawn completion from PlayerStateService
	EventBus:On(Events.PLAYER_STATE_CHANGED_INTERNAL, function(player: Player, stateData: any)
		if stateData.newState == "Lobby" and stateData.oldState == "Died" then
			-- Player successfully respawned to Lobby
			print(`[DeathService] ✅ {player.Name} respawned to Lobby`)
			
			-- Clear death-related data
			local userId = player.UserId
			playerAllDamageHistory[userId] = {}
			analytics.killStreaks[userId] = 0
		end
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- ANALYTICS
	-- ═══════════════════════════════════════════════════════════
	
	task.spawn(function()
		while true do
			task.wait(300)
			local stats = self:GetAnalytics()
			print("[DeathService] 📊 Analytics:")
			print(string.format("  Total deaths: %d", stats.totalDeaths))
			print(string.format("  Blocked duplicates: %d", stats.blockedDuplicateDeaths))
			print(string.format("  Ignored non-Arena: %d", stats.ignoredNonArenaDeaths))
			print(string.format("  Longest kill streak: %d", stats.longestKillStreak))
			
			for cause, count in pairs(stats.deathsByCause) do
				if count > 0 then
					print(string.format("    %s: %d", cause, count))
				end
			end
		end
	end)
	
	print("[DeathService] 🚀 Started - Monitoring player deaths")
end

-- ═══════════════════════════════════════════════════════════════
-- DEATH HANDLING (P0 PROTECTED)
-- ═══════════════════════════════════════════════════════════════

function DeathService:HandleDeath(context: DeathContext)
	local victim = context.victim
	local userId = victim.UserId
	
	-- ✅ P0 FIX: Acquire lock FIRST (atomic death processing)
	if not acquireDeathLock(userId) then
		warn(string.format(
			"[DeathService] ⚠️ %s death already being processed (duplicate blocked)",
			victim.Name
		))
		return
	end
	
	-- ✅ Wrap in pcall to ensure lock is ALWAYS released
	local success = pcall(function()
		print(string.format(
			"[DeathService] 💀 %s died (%s)%s",
			victim.Name,
			context.cause,
			context.killer and (" by " .. context.killer.Name) or ""
		))
		
		-- Update analytics
		analytics.totalDeaths += 1
		analytics.deathsByCause[context.cause] = (analytics.deathsByCause[context.cause] or 0) + 1
		analytics.playerDeathCounts[userId] = (analytics.playerDeathCounts[userId] or 0) + 1
		
		recentDeaths[userId] = os.clock()
		
		if context.killer then
			updateKillStreak(context.killer, victim)
		end
		
		local respawnLocation = determineRespawnLocation(context)
		
		local record: DeathRecord = {
			deathId = generateDeathId(),
			context = context,
			respawnTime = os.clock() + DEATH_CONFIG.RespawnDelay,
			respawnLocation = respawnLocation,
		}
		
		if not deathRecords[userId] then
			deathRecords[userId] = {}
		end
		table.insert(deathRecords[userId], record)
		cleanupOldRecords(userId)
		
		-- ✅ P1: Signal PlayerStateService to change state to "Died"
		EventBus:Emit(Events.PLAYER_DIED, victim, {
			cause = context.cause,
			killer = context.killer,
			weapon = context.weapon,
			respawnDelay = DEATH_CONFIG.RespawnDelay,
			respawnLocation = respawnLocation,
		})
		
		-- Notify clients
		NetworkHandler:Broadcast(Events.PLAYER_DEATH_ANNOUNCED, {
			victimName = victim.Name,
			victimUserId = userId,
			cause = context.cause,
			killerName = context.killer and context.killer.Name,
			killerUserId = context.killer and context.killer.UserId,
			weapon = context.weapon,
			timestamp = context.timestamp,
		})
		
		-- Schedule respawn
		task.delay(DEATH_CONFIG.RespawnDelay, function()
			if not Players:GetPlayerByUserId(userId) then
				return
			end
			
			-- ✅ P1: Signal respawn (PlayerStateService will handle state transition)
			EventBus:Emit(Events.PLAYER_RESPAWN_REQUESTED, victim, {
				location = respawnLocation,
				deathId = record.deathId,
			})
		end)
	end)
	
	-- ✅ P0 FIX: ALWAYS release lock
	releaseDeathLock(userId)
	
	if not success then
		warn(`[DeathService] ❌ Error in HandleDeath: {tostring(success)}`)
	end
end

-- ═══════════════════════════════════════════════════════════════
-- DAMAGE TRACKING
-- ═══════════════════════════════════════════════════════════════

function DeathService:RegisterDamage(victim: Player, attacker: Player?, damage: number, weapon: string?)
	local userId = victim.UserId
	
	-- Update primary damage history (last attacker)
	playerDamageHistory[userId] = {
		attacker = attacker,
		damage = damage,
		weapon = weapon,
		timestamp = os.clock(),
	}
	
	-- ✅ P2: Track all damage for multi-attacker analysis
	if not playerAllDamageHistory[userId] then
		playerAllDamageHistory[userId] = {}
	end
	
	table.insert(playerAllDamageHistory[userId], {
		attacker = attacker,
		damage = damage,
		weapon = weapon,
		timestamp = os.clock(),
	})
	
	-- Keep only recent damage (within combat window)
	local now = os.clock()
	local recentDamage = {}
	for _, damageRecord in ipairs(playerAllDamageHistory[userId]) do
		if (now - damageRecord.timestamp) <= DEATH_CONFIG.CombatWindow then
			table.insert(recentDamage, damageRecord)
		end
	end
	playerAllDamageHistory[userId] = recentDamage
	
	print(string.format(
		"[DeathService] 💥 %s took %.1f damage%s%s",
		victim.Name,
		damage,
		attacker and (" from " .. attacker.Name) or "",
		weapon and (" with " .. weapon) or ""
	))
end

-- ═══════════════════════════════════════════════════════════════
-- QUERY METHODS
-- ═══════════════════════════════════════════════════════════════

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

function DeathService:GetDeathHistory(player: Player): {DeathRecord}
	return deathRecords[player.UserId] or {}
end

-- ✅ P2: Get all attackers that contributed to damage
function DeathService:GetAllAttackers(victim: Player): {{attacker: Player?, damage: number, weapon: string?}}
	return playerAllDamageHistory[victim.UserId] or {}
end

function DeathService:GetAnalytics(): {[string]: any}
	local uptime = os.clock() - analytics.startTime
	
	return {
		totalDeaths = analytics.totalDeaths,
		deathsByCause = analytics.deathsByCause,
		playerDeathCounts = analytics.playerDeathCounts,
		killStreaks = analytics.killStreaks,
		longestKillStreak = analytics.longestKillStreak,
		blockedDuplicateDeaths = analytics.blockedDuplicateDeaths,
		ignoredNonArenaDeaths = analytics.ignoredNonArenaDeaths,
		uptime = uptime,
		deathsPerMinute = uptime > 0 and (analytics.totalDeaths / uptime * 60) or 0,
	}
end

return DeathService