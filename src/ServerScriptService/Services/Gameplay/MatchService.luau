--!strict

--[[
	MATCH SERVICE - PRODUCTION GRADE v1.0
	
	Purpose: Manage match lifecycle, tracking, and statistics
	
	Features:
	  - Match registration & lifecycle
	  - Multi-arena support
	  - Ranked/Casual/Tournament modes
	  - Match-scoped death statistics
	  - Kill streak tracking per match
	  - Respawn delay by match type
	  - Match analytics
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.Core.NetworkHandler)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type MatchType = "Casual" | "Ranked" | "Custom" | "Tournament"
export type MatchStatus = "Pending" | "Active" | "Ended" | "Cancelled"

export type MatchContext = {
	matchId: string,
	matchType: MatchType,
	status: MatchStatus,
	arenaId: string?,
	startTime: number,
	endTime: number?,
	players: {number},
}

export type MatchDeathStats = {
	matchId: string,
	matchType: MatchType,
	arenaId: string?,
	totalDeaths: number,
	deathsByPlayer: {[number]: number},
	killsByPlayer: {[number]: number},
	killStreaks: {[number]: number},
	deathsByCause: {[string]: number},
	startTime: number,
	endTime: number?,
}

export type MatchService = {
	Init: (self: MatchService) -> (),
	Start: (self: MatchService) -> (),
	-- Match lifecycle
	CreateMatch: (self: MatchService, matchType: MatchType, arenaId: string?, players: {Player}) -> string,
	StartMatch: (self: MatchService, matchId: string) -> boolean,
	EndMatch: (self: MatchService, matchId: string, reason: string?) -> MatchDeathStats?,
	CancelMatch: (self: MatchService, matchId: string, reason: string?) -> (),
	-- Player management
	AddPlayerToMatch: (self: MatchService, matchId: string, player: Player) -> boolean,
	RemovePlayerFromMatch: (self: MatchService, matchId: string, player: Player) -> boolean,
	GetPlayerMatch: (self: MatchService, player: Player) -> MatchContext?,
	GetPlayerMatchId: (self: MatchService, player: Player) -> string?,
	-- Match queries
	GetMatch: (self: MatchService, matchId: string) -> MatchContext?,
	GetMatchStats: (self: MatchService, matchId: string) -> MatchDeathStats?,
	GetActiveMatches: (self: MatchService) -> {[string]: MatchContext},
	GetRespawnDelay: (self: MatchService, matchType: MatchType?) -> number,
	-- Analytics
	GetAnalytics: (self: MatchService) -> {[string]: any},
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local MatchService = {} :: MatchService

local guard = IdempotentGuard.new("MatchService", true)

local MATCH_CONFIG = {
	-- Respawn delays by match type
	RespawnDelayByMatchType = {
		Casual = 3,
		Ranked = 5,
		Custom = 3,
		Tournament = 10,
	},
	
	-- Match settings
	DefaultMatchType = "Casual" :: MatchType,
	MaxPlayersPerMatch = 20,
	MinPlayersToStart = 2,
	MatchTimeout = 1800, -- 30 minutes
	
	-- Death causes to track
	DeathCauses = {"Combat", "Environmental", "Timeout", "Script", "Unknown"},
}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local activeMatches: {[string]: MatchContext} = {}
local matchDeathStats: {[string]: MatchDeathStats} = {}
local playerToMatch: {[number]: string} = {}
local matchCounter = 0

local analytics = {
	totalMatches = 0,
	matchesByType = {} :: {[MatchType]: number},
	matchesByStatus = {} :: {[MatchStatus]: number},
	totalDeaths = 0,
	totalKills = 0,
	startTime = os.clock(),
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function generateMatchId(): string
	matchCounter += 1
	return string.format("MATCH_%d_%d", os.time(), matchCounter)
end

local function initializeMatchStats(matchId: string, matchType: MatchType, arenaId: string?): MatchDeathStats
	local stats: MatchDeathStats = {
		matchId = matchId,
		matchType = matchType,
		arenaId = arenaId,
		totalDeaths = 0,
		deathsByPlayer = {},
		killsByPlayer = {},
		killStreaks = {},
		deathsByCause = {},
		startTime = os.clock(),
		endTime = nil,
	}
	
	for _, cause in ipairs(MATCH_CONFIG.DeathCauses) do
		stats.deathsByCause[cause] = 0
	end
	
	return stats
end

local function updateAnalytics(matchType: MatchType, status: MatchStatus, delta: number)
	analytics.matchesByType[matchType] = (analytics.matchesByType[matchType] or 0) + delta
	analytics.matchesByStatus[status] = (analytics.matchesByStatus[status] or 0) + delta
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function MatchService:Init()
	if not guard:MarkInitialized() then
		return
	end
	
	-- Initialize analytics
	for matchType in pairs(MATCH_CONFIG.RespawnDelayByMatchType) do
		analytics.matchesByType[matchType] = 0
	end
	
	analytics.matchesByStatus = {
		Pending = 0,
		Active = 0,
		Ended = 0,
		Cancelled = 0,
	}
	
	print("[MatchService] 🎮 Initialized v1.0")
	print("  ✅ Match types: Casual, Ranked, Custom, Tournament")
	print("  ✅ Multi-arena support: ENABLED")
end

function MatchService:Start()
	if not guard:MarkStarted() then
		return
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- LISTEN TO DEATH EVENTS
	-- ═══════════════════════════════════════════════════════════
	
	EventBus:On(Events.PLAYER_DIED, function(player: Player, deathData: any)
		local matchId = self:GetPlayerMatchId(player)
		if not matchId then
			return
		end
		
		local stats = matchDeathStats[matchId]
		if not stats then
			return
		end
		
		local userId = player.UserId
		
		-- Update death stats
		stats.totalDeaths += 1
		stats.deathsByPlayer[userId] = (stats.deathsByPlayer[userId] or 0) + 1
		
		local cause = deathData.cause or "Unknown"
		stats.deathsByCause[cause] = (stats.deathsByCause[cause] or 0) + 1
		
		-- Update kill stats
		local killer = deathData.killer
		if killer and typeof(killer) == "Instance" and killer:IsA("Player") then
			local killerUserId = killer.UserId
			stats.killsByPlayer[killerUserId] = (stats.killsByPlayer[killerUserId] or 0) + 1
			stats.killStreaks[killerUserId] = (stats.killStreaks[killerUserId] or 0) + 1
			stats.killStreaks[userId] = 0 -- Reset victim's streak
			
			analytics.totalKills += 1
		end
		
		analytics.totalDeaths += 1
		
		print(`[MatchService] 📊 Death recorded in match {matchId}: {player.Name}`)
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- PLAYER CLEANUP
	-- ═══════════════════════════════════════════════════════════
	
	Players.PlayerRemoving:Connect(function(player: Player)
		local matchId = playerToMatch[player.UserId]
		if matchId then
			self:RemovePlayerFromMatch(matchId, player)
		end
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- MATCH TIMEOUT
	-- ═══════════════════════════════════════════════════════════
	
	task.spawn(function()
		while true do
			task.wait(60) -- Check every minute
			
			local now = os.clock()
			for matchId, match in pairs(activeMatches) do
				if match.status == "Active" then
					local duration = now - match.startTime
					if duration > MATCH_CONFIG.MatchTimeout then
						warn(`[MatchService] ⏱️ Match {matchId} timed out after {duration}s`)
						self:EndMatch(matchId, "Timeout")
					end
				end
			end
		end
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- ANALYTICS REPORTING
	-- ═══════════════════════════════════════════════════════════
	
	task.spawn(function()
		while true do
			task.wait(300) -- Every 5 minutes
			local stats = self:GetAnalytics()
			print("[MatchService] 📊 Analytics:")
			print(string.format("  Total matches: %d | Active: %d", stats.totalMatches, stats.activeMatches))
			print(string.format("  Total deaths: %d | Total kills: %d", stats.totalDeaths, stats.totalKills))
		end
	end)
	
	print("[MatchService] 🚀 Started - Match management enabled")
end

-- ═══════════════════════════════════════════════════════════════
-- MATCH LIFECYCLE
-- ═══════════════════════════════════════════════════════════════

function MatchService:CreateMatch(matchType: MatchType, arenaId: string?, players: {Player}): string
	local matchId = generateMatchId()
	
	local playerIds = {}
	for _, player in ipairs(players) do
		table.insert(playerIds, player.UserId)
		playerToMatch[player.UserId] = matchId
	end
	
	local match: MatchContext = {
		matchId = matchId,
		matchType = matchType,
		status = "Pending",
		arenaId = arenaId,
		startTime = os.clock(),
		endTime = nil,
		players = playerIds,
	}
	
	activeMatches[matchId] = match
	matchDeathStats[matchId] = initializeMatchStats(matchId, matchType, arenaId)
	
	analytics.totalMatches += 1
	updateAnalytics(matchType, "Pending", 1)
	
	print(`[MatchService] 🎮 Match created: {matchId} ({matchType}) with {#players} players`)
	
	EventBus:Emit(Events.MATCH_REGISTERED, matchId, match)
	
	return matchId
end

function MatchService:StartMatch(matchId: string): boolean
	local match = activeMatches[matchId]
	if not match then
		warn(`[MatchService] Match {matchId} not found!`)
		return false
	end
	
	if match.status ~= "Pending" then
		warn(`[MatchService] Match {matchId} cannot start (status: {match.status})`)
		return false
	end
	
	if #match.players < MATCH_CONFIG.MinPlayersToStart then
		warn(`[MatchService] Match {matchId} needs at least {MATCH_CONFIG.MinPlayersToStart} players`)
		return false
	end
	
	updateAnalytics(match.matchType, "Pending", -1)
	match.status = "Active"
	match.startTime = os.clock()
	updateAnalytics(match.matchType, "Active", 1)
	
	print(`[MatchService] ▶️ Match started: {matchId}`)
	
	EventBus:Emit(Events.MATCH_STARTED, matchId, match)
	
	return true
end

function MatchService:EndMatch(matchId: string, reason: string?): MatchDeathStats?
	local match = activeMatches[matchId]
	if not match then
		warn(`[MatchService] Match {matchId} not found!`)
		return nil
	end
	
	-- Remove players from tracking
	for _, userId in ipairs(match.players) do
		if playerToMatch[userId] == matchId then
			playerToMatch[userId] = nil
		end
	end
	
	-- Finalize stats
	local stats = matchDeathStats[matchId]
	if stats then
		stats.endTime = os.clock()
	end
	
	-- Update status
	updateAnalytics(match.matchType, match.status, -1)
	match.status = "Ended"
	match.endTime = os.clock()
	updateAnalytics(match.matchType, "Ended", 1)
	
	-- Remove from active
	activeMatches[matchId] = nil
	
	print(`[MatchService] 🏁 Match ended: {matchId} (reason: {reason or "Normal"})`)
	
	EventBus:Emit(Events.MATCH_ENDED, matchId, stats)
	
	return stats
end

function MatchService:CancelMatch(matchId: string, reason: string?)
	local match = activeMatches[matchId]
	if not match then
		return
	end
	
	-- Remove players from tracking
	for _, userId in ipairs(match.players) do
		if playerToMatch[userId] == matchId then
			playerToMatch[userId] = nil
		end
	end
	
	updateAnalytics(match.matchType, match.status, -1)
	match.status = "Cancelled"
	match.endTime = os.clock()
	updateAnalytics(match.matchType, "Cancelled", 1)
	
	activeMatches[matchId] = nil
	
	print(`[MatchService] ❌ Match cancelled: {matchId} (reason: {reason or "Unknown"})`)
	
	EventBus:Emit(Events.MATCH_CANCELLED, matchId, reason)
end

-- ═══════════════════════════════════════════════════════════════
-- PLAYER MANAGEMENT
-- ═══════════════════════════════════════════════════════════════

function MatchService:AddPlayerToMatch(matchId: string, player: Player): boolean
	local match = activeMatches[matchId]
	if not match then
		return false
	end
	
	if #match.players >= MATCH_CONFIG.MaxPlayersPerMatch then
		warn(`[MatchService] Match {matchId} is full!`)
		return false
	end
	
	local userId = player.UserId
	
	-- Check if already in a match
	if playerToMatch[userId] then
		warn(`[MatchService] {player.Name} is already in match {playerToMatch[userId]}`)
		return false
	end
	
	table.insert(match.players, userId)
	playerToMatch[userId] = matchId
	
	print(`[MatchService] ➕ {player.Name} joined match {matchId}`)
	
	EventBus:Emit(Events.MATCH_PLAYER_JOINED, matchId, player)
	
	return true
end

function MatchService:RemovePlayerFromMatch(matchId: string, player: Player): boolean
	local match = activeMatches[matchId]
	if not match then
		return false
	end
	
	local userId = player.UserId
	
	-- Remove from players list
	local newPlayers = {}
	local found = false
	for _, pId in ipairs(match.players) do
		if pId ~= userId then
			table.insert(newPlayers, pId)
		else
			found = true
		end
	end
	
	if not found then
		return false
	end
	
	match.players = newPlayers
	playerToMatch[userId] = nil
	
	print(`[MatchService] ➖ {player.Name} left match {matchId}`)
	
	EventBus:Emit(Events.MATCH_PLAYER_LEFT, matchId, player)
	
	-- End match if no players left
	if #match.players == 0 then
		self:EndMatch(matchId, "All players left")
	end
	
	return true
end

function MatchService:GetPlayerMatch(player: Player): MatchContext?
	local matchId = playerToMatch[player.UserId]
	if matchId then
		return activeMatches[matchId]
	end
	return nil
end

function MatchService:GetPlayerMatchId(player: Player): string?
	return playerToMatch[player.UserId]
end

-- ═══════════════════════════════════════════════════════════════
-- MATCH QUERIES
-- ═══════════════════════════════════════════════════════════════

function MatchService:GetMatch(matchId: string): MatchContext?
	return activeMatches[matchId]
end

function MatchService:GetMatchStats(matchId: string): MatchDeathStats?
	return matchDeathStats[matchId]
end

function MatchService:GetActiveMatches(): {[string]: MatchContext}
	return activeMatches
end

function MatchService:GetRespawnDelay(matchType: MatchType?): number
	if matchType and MATCH_CONFIG.RespawnDelayByMatchType[matchType] then
		return MATCH_CONFIG.RespawnDelayByMatchType[matchType]
	end
	return MATCH_CONFIG.RespawnDelayByMatchType.Casual
end

-- ═══════════════════════════════════════════════════════════════
-- ANALYTICS
-- ═══════════════════════════════════════════════════════════════

function MatchService:GetAnalytics(): {[string]: any}
	local uptime = os.clock() - analytics.startTime
	local activeCount = 0
	for _ in pairs(activeMatches) do
		activeCount += 1
	end
	
	return {
		totalMatches = analytics.totalMatches,
		activeMatches = activeCount,
		matchesByType = analytics.matchesByType,
		matchesByStatus = analytics.matchesByStatus,
		totalDeaths = analytics.totalDeaths,
		totalKills = analytics.totalKills,
		uptime = uptime,
	}
end

return MatchService
