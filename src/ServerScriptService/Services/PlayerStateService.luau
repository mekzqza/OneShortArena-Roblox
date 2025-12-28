--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║           PLAYER STATE SERVICE - PRODUCTION GRADE              ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Manage player states (Lobby, Arena, Died)            ║
║ Features:                                                      ║
║  ✅ Type-safe state management                                ║
║  ✅ State transition validation                               ║
║  ✅ Event-driven architecture                                 ║
║  ✅ Analytics tracking                                        ║
║  ✅ Automatic cleanup on player leave                         ║
╚════════════════════════════════════════════════════════════════╝
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.NetworkHandler)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type PlayerState = "Lobby" | "Arena" | "Died" | "Spectating"

export type StateTransition = {
	from: PlayerState,
	to: PlayerState,
	timestamp: number,
	reason: string?,
}

export type PlayerStateData = {
	currentState: PlayerState,
	previousState: PlayerState?,
	transitionHistory: {StateTransition},
	lastTransitionTime: number,
}

export type PlayerStateService = {
	GetState: (self: PlayerStateService, player: Player | number) -> PlayerState?,
	SetState: (self: PlayerStateService, player: Player | number, newState: PlayerState, reason: string?) -> boolean,
	CanTransition: (self: PlayerStateService, player: Player | number, targetState: PlayerState) -> (boolean, string?),
	GetStateData: (self: PlayerStateService, player: Player | number) -> PlayerStateData?,
	GetPlayersInState: (self: PlayerStateService, state: PlayerState) -> {Player},
	GetAnalytics: (self: PlayerStateService) -> {[string]: any},
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local PlayerStateService = {} :: PlayerStateService

-- ✅ Create idempotent guard
local guard = IdempotentGuard.new("PlayerStateService", true)

-- Valid states
local VALID_STATES: {[PlayerState]: true} = {
	Lobby = true,
	Arena = true,
	Died = true,
	Spectating = true,
}

-- State transition rules (from -> to)
local ALLOWED_TRANSITIONS: {[PlayerState]: {[PlayerState]: true}} = {
	Lobby = {
		Arena = true,      -- Can join arena from lobby
		Spectating = true, -- Can spectate from lobby
	},
	Arena = {
		Died = true,       -- Can die in arena
		Lobby = true,      -- Can return to lobby
		Spectating = true, -- Can switch to spectating
	},
	Died = {
		Lobby = true,      -- Can respawn to lobby
		Spectating = true, -- Can spectate after death
	},
	Spectating = {
		Lobby = true,      -- Can return to lobby
		Arena = true,      -- Can join arena from spectating
	},
}

-- Default state for new players
local DEFAULT_STATE: PlayerState = "Lobby"

-- State storage: userId -> PlayerStateData
local playerStates: {[number]: PlayerStateData} = {}

-- Analytics
local analytics = {
	totalTransitions = 0,
	transitionCounts = {} :: {[string]: number}, -- "Lobby->Arena" -> count
	currentStateCounts = {} :: {[PlayerState]: number},
	startTime = os.clock(),
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

-- Get userId from Player or number
local function getUserId(player: Player | number): number
	if type(player) == "number" then
		return player
	end
	return player.UserId
end

-- Get Player from userId
local function getPlayer(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

-- Initialize state data for new player
local function initializePlayerState(userId: number): PlayerStateData
	local stateData: PlayerStateData = {
		currentState = DEFAULT_STATE,
		previousState = nil,
		transitionHistory = {},
		lastTransitionTime = os.clock(),
	}
	
	playerStates[userId] = stateData
	
	-- Update analytics
	analytics.currentStateCounts[DEFAULT_STATE] = (analytics.currentStateCounts[DEFAULT_STATE] or 0) + 1
	
	return stateData
end

-- Update analytics on state change
local function updateAnalytics(from: PlayerState, to: PlayerState)
	analytics.totalTransitions += 1
	
	local transitionKey = string.format("%s->%s", from, to)
	analytics.transitionCounts[transitionKey] = (analytics.transitionCounts[transitionKey] or 0) + 1
	
	analytics.currentStateCounts[from] = math.max(0, (analytics.currentStateCounts[from] or 0) - 1)
	analytics.currentStateCounts[to] = (analytics.currentStateCounts[to] or 0) + 1
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function PlayerStateService:Init()
	-- ✅ Guard: Prevent double init
	if not guard:MarkInitialized() then
		return
	end
	
	-- Allow client events
	NetworkHandler:AllowClientEvent(Events.PLAYER_REQUEST_TO_ARENA)
	NetworkHandler:AllowClientEvent(Events.PLAYER_REQUEST_TO_LOBBY)
	NetworkHandler:AllowClientEvent(Events.PLAYER_REQUEST_TO_SPECTATE)
	
	-- Initialize analytics counts
	for state in pairs(VALID_STATES) do
		analytics.currentStateCounts[state] = 0
	end
	
	print("[PlayerStateService] 🎮 Initialized")
	print("  ✅ Valid states:", table.concat({"Lobby", "Arena", "Died", "Spectating"}, ", "))
	print("  ✅ Transition rules configured")
end

function PlayerStateService:Start()
	-- ✅ Guard: Prevent double start & require init
	if not guard:MarkStarted() then
		return
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- PLAYER LIFECYCLE EVENTS
	-- ═══════════════════════════════════════════════════════════
	
	-- Initialize state when player joins
	Players.PlayerAdded:Connect(function(player: Player)
		local stateData = initializePlayerState(player.UserId)
		print(string.format("[PlayerStateService] 👤 %s joined → %s", player.Name, stateData.currentState))
		
		-- Notify client
		NetworkHandler:SendToClient(player, Events.PLAYER_STATE_CHANGED, {
			state = stateData.currentState,
			timestamp = os.clock()
		})
	end)
	
	-- Cleanup when player leaves
	Players.PlayerRemoving:Connect(function(player: Player)
		local userId = player.UserId
		local stateData = playerStates[userId]
		
		if stateData then
			-- Update analytics
			analytics.currentStateCounts[stateData.currentState] = 
				math.max(0, (analytics.currentStateCounts[stateData.currentState] or 0) - 1)
			
			print(string.format("[PlayerStateService] 👋 %s left (was in %s)", player.Name, stateData.currentState))
		end
		
		playerStates[userId] = nil
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- CLIENT REQUEST EVENTS
	-- ═══════════════════════════════════════════════════════════
	
	-- Request to join Arena
	EventBus:On(Events.PLAYER_REQUEST_TO_ARENA, function(player: Player, data: any)
		local canTransition, reason = self:CanTransition(player, "Arena")
		
		if canTransition then
			local success = self:SetState(player, "Arena", "Player request")
			
			if success then
				print(string.format("[PlayerStateService] ✅ %s joined Arena", player.Name))
				
				-- Notify client
				NetworkHandler:SendToClient(player, Events.PLAYER_STATE_CHANGED, {
					state = "Arena",
					success = true,
					timestamp = os.clock()
				})
			else
				warn(string.format("[PlayerStateService] ❌ Failed to move %s to Arena", player.Name))
			end
		else
			warn(string.format("[PlayerStateService] ❌ %s cannot join Arena: %s", player.Name, reason or "Unknown"))
			
			-- Notify client of failure
			NetworkHandler:SendToClient(player, Events.PLAYER_STATE_CHANGED, {
				state = "Arena",
				success = false,
				reason = reason,
				timestamp = os.clock()
			})
		end
	end)
	
	-- Request to return to Lobby
	EventBus:On(Events.PLAYER_REQUEST_TO_LOBBY, function(player: Player, data: any)
		local success = self:SetState(player, "Lobby", "Player request")
		
		if success then
			print(string.format("[PlayerStateService] ✅ %s returned to Lobby", player.Name))
			
			NetworkHandler:SendToClient(player, Events.PLAYER_STATE_CHANGED, {
				state = "Lobby",
				success = true,
				timestamp = os.clock()
			})
		end
	end)
	
	-- Request to spectate
	EventBus:On(Events.PLAYER_REQUEST_TO_SPECTATE, function(player: Player, data: any)
		local success = self:SetState(player, "Spectating", "Player request")
		
		if success then
			print(string.format("[PlayerStateService] ✅ %s is now spectating", player.Name))
			
			NetworkHandler:SendToClient(player, Events.PLAYER_STATE_CHANGED, {
				state = "Spectating",
				success = true,
				timestamp = os.clock()
			})
		end
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- ANALYTICS REPORTING
	-- ═══════════════════════════════════════════════════════════
	
	task.spawn(function()
		while true do
			task.wait(60) -- Every minute
			local stats = self:GetAnalytics()
			print("[PlayerStateService] 📊 Analytics:")
			print(string.format("  Total transitions: %d", stats.totalTransitions))
			for state, count in pairs(stats.currentStateCounts) do
				print(string.format("  %s: %d players", state, count))
			end
		end
	end)
	
	print("[PlayerStateService] 🚀 Started - Listening for state requests")
end

-- ═══════════════════════════════════════════════════════════════
-- STATE MANAGEMENT METHODS
-- ═══════════════════════════════════════════════════════════════

-- Get current state of player
function PlayerStateService:GetState(player: Player | number): PlayerState?
	local userId = getUserId(player)
	local stateData = playerStates[userId]
	
	if not stateData then
		-- Initialize if not exists
		stateData = initializePlayerState(userId)
	end
	
	return stateData.currentState
end

-- Check if state transition is allowed
function PlayerStateService:CanTransition(player: Player | number, targetState: PlayerState): (boolean, string?)
	-- Validate target state
	if not VALID_STATES[targetState] then
		return false, string.format("Invalid state: %s", tostring(targetState))
	end
	
	local userId = getUserId(player)
	local stateData = playerStates[userId]
	
	if not stateData then
		-- If no state, can go to any state
		return true
	end
	
	local currentState = stateData.currentState
	
	-- ✅ แก้ไข: ถ้า state เดียวกัน ให้ return true (idempotent)
	if currentState == targetState then
		return true, "Already in target state (idempotent)"  -- ✅ Changed from false to true
	end
	
	-- Check transition rules
	local allowedTargets = ALLOWED_TRANSITIONS[currentState]
	if not allowedTargets or not allowedTargets[targetState] then
		return false, string.format("Cannot transition from %s to %s", currentState, targetState)
	end
	
	return true
end

-- Set player state with validation
function PlayerStateService:SetState(player: Player | number, newState: PlayerState, reason: string?): boolean
	local userId = getUserId(player)
	
	-- Validate state
	if not VALID_STATES[newState] then
		warn(string.format("[PlayerStateService] Invalid state: %s", tostring(newState)))
		return false
	end
	
	-- Get or create state data
	local stateData = playerStates[userId]
	if not stateData then
		stateData = initializePlayerState(userId)
	end
	
	local oldState = stateData.currentState
	
	-- Check if transition is allowed
	if oldState ~= newState then
		local canTransition, transitionReason = self:CanTransition(userId, newState)
		if not canTransition then
			warn(string.format("[PlayerStateService] Transition blocked: %s", transitionReason or "Unknown"))
			return false
		end
	end
	
	-- Perform transition
	local transition: StateTransition = {
		from = oldState,
		to = newState,
		timestamp = os.clock(),
		reason = reason,
	}
	
	stateData.previousState = oldState
	stateData.currentState = newState
	stateData.lastTransitionTime = transition.timestamp
	table.insert(stateData.transitionHistory, transition)
	
	-- Update analytics
	updateAnalytics(oldState, newState)
	
	-- Emit event
	local playerInstance = getPlayer(userId)
	if playerInstance then
		EventBus:Emit(Events.PLAYER_STATE_CHANGED_INTERNAL, playerInstance, {
			oldState = oldState,
			newState = newState,
			reason = reason,
			timestamp = transition.timestamp
		})
	end
	
	return true
end

-- Get full state data
function PlayerStateService:GetStateData(player: Player | number): PlayerStateData?
	local userId = getUserId(player)
	return playerStates[userId]
end

-- Get all players in specific state
function PlayerStateService:GetPlayersInState(state: PlayerState): {Player}
	local result = {}
	
	for userId, stateData in pairs(playerStates) do
		if stateData.currentState == state then
			local player = getPlayer(userId)
			if player then
				table.insert(result, player)
			end
		end
	end
	
	return result
end

-- Get analytics
function PlayerStateService:GetAnalytics(): {[string]: any}
	local uptime = os.clock() - analytics.startTime
	
	return {
		totalTransitions = analytics.totalTransitions,
		transitionCounts = analytics.transitionCounts,
		currentStateCounts = analytics.currentStateCounts,
		uptime = uptime,
		transitionsPerMinute = uptime > 0 and (analytics.totalTransitions / uptime * 60) or 0,
	}
end

return PlayerStateService
