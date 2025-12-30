--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║              RESPAWN SERVICE - PRODUCTION GRADE                ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Handle all respawn logic after death                 ║
║ Features:                                                      ║
║  ✅ Auto-respawn after Died state                             ║
║  ✅ Respawn delay configuration                               ║
║  ✅ Respawn location selection                                ║
║  ✅ Event-driven architecture                                 ║
╚════════════════════════════════════════════════════════════════╝

Responsibility:
  - Listen for PLAYER_DIED / PLAYER_DOWNED_TIMEOUT
  - Decide respawn delay
  - Decide respawn location
  - Emit PLAYER_RESPAWN_REQUESTED
  - Does NOT handle state transitions (PlayerStateService does)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type RespawnConfig = {
	delay: number,
	location: string,  -- "Lobby" | "Arena" | "Spectate"
	reason: string,
}

export type RespawnService = {
	Init: (self: RespawnService) -> (),
	Start: (self: RespawnService) -> (),
	ScheduleRespawn: (self: RespawnService, player: Player, config: RespawnConfig?) -> (),
	CancelRespawn: (self: RespawnService, player: Player) -> (),
	GetRespawnConfig: (self: RespawnService, deathReason: string) -> RespawnConfig,
	GetAnalytics: (self: RespawnService) -> {[string]: any},
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local RespawnService = {} :: RespawnService

local guard = IdempotentGuard.new("RespawnService", true)

local RESPAWN_CONFIG = {
	DefaultDelay = 3,          -- 3 seconds default
	DefaultLocation = "Lobby",
	
	-- By death reason
	DelayByReason = {
		["DownedTimeout"] = 3,
		["Finished"] = 5,
		["Environmental"] = 2,
		["Combat"] = 3,
		["Unknown"] = 3,
	},
	
	-- Location by reason
	LocationByReason = {
		["DownedTimeout"] = "Lobby",
		["Finished"] = "Lobby",
		["Environmental"] = "Lobby",
		["Combat"] = "Lobby",
		["Unknown"] = "Lobby",
	},
}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local pendingRespawns: {[number]: thread} = {}

local analytics = {
	totalRespawns = 0,
	cancelledRespawns = 0,
	respawnsByLocation = {} :: {[string]: number},
	startTime = os.clock(),
}

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function RespawnService:Init()
	if not guard:MarkInitialized() then
		return
	end
	
	-- Initialize analytics
	analytics.respawnsByLocation["Lobby"] = 0
	analytics.respawnsByLocation["Arena"] = 0
	
	print("[RespawnService] 🔄 Initialized")
	print(`  ✅ Default delay: {RESPAWN_CONFIG.DefaultDelay}s`)
	print(`  ✅ Default location: {RESPAWN_CONFIG.DefaultLocation}`)
end

function RespawnService:Start()
	if not guard:MarkStarted() then
		return
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- LISTEN FOR DEATH EVENTS
	-- ═══════════════════════════════════════════════════════════
	
	-- Listen for Downed timeout
	EventBus:On(Events.PLAYER_DOWNED_TIMEOUT, function(player: Player, data: any)
		local config = self:GetRespawnConfig("DownedTimeout")
		print(`[RespawnService] 📥 Downed timeout for {player.Name}, scheduling respawn in {config.delay}s`)
		self:ScheduleRespawn(player, config)
	end)
	
	-- Listen for Finished (killed while downed)
	EventBus:On(Events.PLAYER_FINISHED, function(player: Player, data: any)
		local config = self:GetRespawnConfig("Finished")
		print(`[RespawnService] 📥 {player.Name} was finished, scheduling respawn in {config.delay}s`)
		self:ScheduleRespawn(player, config)
	end)
	
	-- Listen for direct deaths (bypass Downed)
	EventBus:On(Events.PLAYER_DIED, function(player: Player, data: any)
		-- Only handle if bypassedDowned = true
		if data.bypassedDowned then
			local reason = data.cause or "Unknown"
			local config = self:GetRespawnConfig(reason)
			print(`[RespawnService] 📥 {player.Name} died directly ({reason}), scheduling respawn in {config.delay}s`)
			self:ScheduleRespawn(player, config)
		end
	end)
	
	-- Cleanup on player leave
	Players.PlayerRemoving:Connect(function(player: Player)
		self:CancelRespawn(player)
	end)
	
	print("[RespawnService] 🚀 Started - Listening for death events")
end

function RespawnService:ScheduleRespawn(player: Player, config: RespawnConfig?)
	local userId = player.UserId
	
	-- Cancel existing respawn
	self:CancelRespawn(player)
	
	-- Use provided config or default
	local respawnConfig = config or {
		delay = RESPAWN_CONFIG.DefaultDelay,
		location = RESPAWN_CONFIG.DefaultLocation,
		reason = "Manual",
	}
	
	print(`[RespawnService] ⏳ {player.Name} will respawn to {respawnConfig.location} in {respawnConfig.delay}s`)
	
	-- Schedule respawn
	pendingRespawns[userId] = task.delay(respawnConfig.delay, function()
		-- Check if player still exists
		if not player or not player.Parent then
			return
		end
		
		-- Check if still pending
		if not pendingRespawns[userId] then
			return
		end
		
		pendingRespawns[userId] = nil
		
		-- Update analytics
		analytics.totalRespawns += 1
		analytics.respawnsByLocation[respawnConfig.location] = 
			(analytics.respawnsByLocation[respawnConfig.location] or 0) + 1
		
		print(`[RespawnService] 🔄 Respawning {player.Name} to {respawnConfig.location}`)
		
		-- Emit respawn request
		EventBus:Emit(Events.PLAYER_RESPAWN_REQUESTED, player, {
			location = respawnConfig.location,
			reason = respawnConfig.reason,
		})
	end)
end

function RespawnService:CancelRespawn(player: Player)
	local userId = player.UserId
	
	if pendingRespawns[userId] then
		task.cancel(pendingRespawns[userId])
		pendingRespawns[userId] = nil
		analytics.cancelledRespawns += 1
		print(`[RespawnService] ❌ Cancelled respawn for {player.Name}`)
	end
end

function RespawnService:GetRespawnConfig(deathReason: string): RespawnConfig
	local delay = RESPAWN_CONFIG.DelayByReason[deathReason] or RESPAWN_CONFIG.DefaultDelay
	local location = RESPAWN_CONFIG.LocationByReason[deathReason] or RESPAWN_CONFIG.DefaultLocation
	
	return {
		delay = delay,
		location = location,
		reason = deathReason,
	}
end

function RespawnService:GetAnalytics(): {[string]: any}
	local pending = 0
	for _ in pairs(pendingRespawns) do
		pending += 1
	end
	
	return {
		totalRespawns = analytics.totalRespawns,
		cancelledRespawns = analytics.cancelledRespawns,
		pendingRespawns = pending,
		respawnsByLocation = analytics.respawnsByLocation,
		uptime = os.clock() - analytics.startTime,
	}
end

return RespawnService
