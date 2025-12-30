--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║              COMBAT SERVICE - PRODUCTION GRADE                 ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Handle all combat-related logic                      ║
║ Features:                                                      ║
║  ✅ Damage detection                                          ║
║  ✅ Fatal hit detection                                       ║
║  ✅ Shield/Armor support (future)                             ║
║  ✅ Event emission (PLAYER_FATAL_HIT)                         ║
╚════════════════════════════════════════════════════════════════╝

Responsibility:
  - Detect damage
  - Apply damage modifiers (shield, armor, etc.)
  - Detect fatal hits (HP would go <= 0)
  - Emit PLAYER_FATAL_HIT for DownedService
  - Does NOT decide what happens after fatal hit
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- Lazy load
local PlayerStateService: any = nil

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type DamageInfo = {
	victim: Player,
	attacker: Player?,
	damage: number,
	damageType: string,  -- "Physical", "Magic", "Environmental", etc.
	weapon: string?,
	isCritical: boolean?,
	timestamp: number,
}

export type CombatService = {
	Init: (self: CombatService) -> (),
	Start: (self: CombatService) -> (),
	-- Core methods
	ProcessDamage: (self: CombatService, info: DamageInfo) -> boolean,
	RegisterDamage: (self: CombatService, victim: Player, attacker: Player?, damage: number, weapon: string?) -> (),
	-- Queries
	GetLastDamageInfo: (self: CombatService, player: Player) -> DamageInfo?,
	IsPlayerInCombat: (self: CombatService, player: Player) -> boolean,
	-- Analytics
	GetAnalytics: (self: CombatService) -> {[string]: any},
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local CombatService = {} :: CombatService

local guard = IdempotentGuard.new("CombatService", true)

local COMBAT_CONFIG = {
	CombatTimeout = 5,           -- Player is "in combat" for 5s after damage
	FatalHitThreshold = 0,       -- HP <= this = fatal
	PreventInstantDeath = true,  -- Set HP to 1 instead of 0 for Downed system
}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local lastDamageInfo: {[number]: DamageInfo} = {}
local combatTimestamps: {[number]: number} = {}
local processingLocks: {[number]: boolean} = {}

-- ✅ NEW: Track players who already received fatal hit (prevent duplicate)
local fatalHitProcessed: {[number]: number} = {}
local FATAL_HIT_COOLDOWN = 5 -- 5 seconds between fatal hits

local analytics = {
	totalDamageEvents = 0,
	totalFatalHits = 0,
	blockedByLock = 0,
	blockedByFatalCooldown = 0,
	startTime = os.clock(),
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function getPlayerStateService()
	if not PlayerStateService then
		PlayerStateService = require(ServerScriptService.Services.Player.PlayerStateService)
	end
	return PlayerStateService
end

-- P0: Acquire processing lock
local function acquireProcessingLock(userId: number): boolean
	if processingLocks[userId] then
		analytics.blockedByLock += 1
		return false
	end
	processingLocks[userId] = true
	return true
end

-- P0: Release processing lock
local function releaseProcessingLock(userId: number)
	processingLocks[userId] = nil
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function CombatService:Init()
	if not guard:MarkInitialized() then
		return
	end
	
	print("[CombatService] ⚔️ Initialized")
	print(`  ✅ Combat timeout: {COMBAT_CONFIG.CombatTimeout}s`)
	print(`  ✅ Prevent instant death: {COMBAT_CONFIG.PreventInstantDeath}`)
end

function CombatService:Start()
	if not guard:MarkStarted() then
		return
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- LISTEN FOR DAMAGE EVENTS
	-- ═══════════════════════════════════════════════════════════
	
	EventBus:On(Events.PLAYER_DAMAGED, function(victim: Player, damage: number, attacker: Player?, weapon: string?)
		local info: DamageInfo = {
			victim = victim,
			attacker = attacker,
			damage = damage,
			damageType = attacker and "Physical" or "Environmental",
			weapon = weapon,
			isCritical = false,
			timestamp = os.clock(),
		}
		
		self:ProcessDamage(info)
	end)
	
	-- Cleanup on player leave
	Players.PlayerRemoving:Connect(function(player: Player)
		local userId = player.UserId
		lastDamageInfo[userId] = nil
		combatTimestamps[userId] = nil
		processingLocks[userId] = nil
		fatalHitProcessed[userId] = nil  -- ✅ NEW: Cleanup
	end)
	
	print("[CombatService] 🚀 Started - Listening for damage events")
end

function CombatService:ProcessDamage(info: DamageInfo): boolean
	local victim = info.victim
	local userId = victim.UserId
	
	-- P0: Acquire lock
	if not acquireProcessingLock(userId) then
		warn(`[CombatService] ⚠️ {victim.Name} damage already processing`)
		return false
	end
	
	local success = false
	
	pcall(function()
		local character = victim.Character
		local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
		
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		
		-- ✅ NEW: Check if player is already Downed
		if character:GetAttribute("IsDowned") then
			print(`[CombatService] ⏭️ {victim.Name} is Downed, skipping damage`)
			return
		end
		
		-- Store damage info
		lastDamageInfo[userId] = info
		combatTimestamps[userId] = info.timestamp
		analytics.totalDamageEvents += 1
		
		-- Check if in Arena
		local PSS = getPlayerStateService()
		local currentState = PSS:GetState(victim)
		
		if currentState ~= "Arena" then
			-- Not in Arena, apply damage normally (no Downed system)
			humanoid.Health = math.max(0, humanoid.Health - info.damage)
			success = true
			return
		end
		
		-- Calculate resulting HP
		local resultingHP = humanoid.Health - info.damage
		
		-- Check for fatal hit
		if resultingHP <= COMBAT_CONFIG.FatalHitThreshold then
			-- ✅ NEW: Check fatal hit cooldown (prevent duplicate fatal hits)
			local lastFatal = fatalHitProcessed[userId]
			if lastFatal and (os.clock() - lastFatal) < FATAL_HIT_COOLDOWN then
				analytics.blockedByFatalCooldown += 1
				print(`[CombatService] ⏭️ {victim.Name} fatal hit already processed`)
				return
			end
			
			-- ✅ Mark as processed BEFORE emitting event
			fatalHitProcessed[userId] = os.clock()
			analytics.totalFatalHits += 1
			
			print(`[CombatService] ⚠️ FATAL HIT detected for {victim.Name}`)
			
			if COMBAT_CONFIG.PreventInstantDeath then
				-- ✅ Set health to 1 (prevent death event)
				humanoid.Health = 1
				
				-- ✅ Emit PLAYER_FATAL_HIT for DownedService (once only!)
				EventBus:Emit(Events.PLAYER_FATAL_HIT, victim, {
					attacker = info.attacker,
					damage = info.damage,
					damageType = info.damageType,
					weapon = info.weapon,
					timestamp = info.timestamp,
				})
			else
				humanoid.Health = 0
			end
		else
			-- Non-fatal damage
			humanoid.Health = math.max(0, resultingHP)
			
			EventBus:Emit(Events.PLAYER_DAMAGE_APPLIED, victim, {
				damage = info.damage,
				remainingHP = humanoid.Health,
				attacker = info.attacker,
			})
		end
		
		success = true
	end)
	
	-- P0: Always release lock
	releaseProcessingLock(userId)
	
	return success
end

function CombatService:RegisterDamage(victim: Player, attacker: Player?, damage: number, weapon: string?)
	local info: DamageInfo = {
		victim = victim,
		attacker = attacker,
		damage = damage,
		damageType = attacker and "Physical" or "Environmental",
		weapon = weapon,
		isCritical = false,
		timestamp = os.clock(),
	}
	
	lastDamageInfo[victim.UserId] = info
	combatTimestamps[victim.UserId] = info.timestamp
end

function CombatService:GetLastDamageInfo(player: Player): DamageInfo?
	return lastDamageInfo[player.UserId]
end

function CombatService:IsPlayerInCombat(player: Player): boolean
	local lastCombat = combatTimestamps[player.UserId]
	if not lastCombat then
		return false
	end
	return (os.clock() - lastCombat) < COMBAT_CONFIG.CombatTimeout
end

function CombatService:GetAnalytics(): {[string]: any}
	return {
		totalDamageEvents = analytics.totalDamageEvents,
		totalFatalHits = analytics.totalFatalHits,
		blockedByLock = analytics.blockedByLock,
		uptime = os.clock() - analytics.startTime,
	}
end

return CombatService
