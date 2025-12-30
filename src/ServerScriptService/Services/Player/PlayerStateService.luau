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
local NetworkHandler = require(ServerScriptService.Services.Core.NetworkHandler)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type PlayerState = "Lobby" | "Arena" | "Downed" | "Died" | "Spectating"

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
	Downed = true,  -- ✅ NEW
	Died = true,
	Spectating = true,
}

-- State transition rules (from -> to)
local ALLOWED_TRANSITIONS: {[PlayerState]: {[PlayerState]: true}} = {
	Lobby = {
		Arena = true,
		Spectating = true,
	},
	Arena = {
		Downed = true,     -- ✅ NEW: แพ้แล้วเข้า Downed
		Died = true,       -- ตายตรงๆ (ตก void, etc.)
		Lobby = true,
		Spectating = true,
	},
	Downed = {             -- ✅ NEW: Downed state transitions
		Died = true,       -- timeout หรือถูก finish
		Arena = true,      -- ถูก revive กลับมาสู้ต่อ
		Spectating = true, -- เลือก spectate (ยอมแพ้)
	},
	Died = {
		Lobby = true,
		Spectating = true,
	},
	Spectating = {
		Lobby = true,
		Arena = true,
	},
}

-- Default state for new players
local DEFAULT_STATE: PlayerState = "Lobby"

-- State storage: userId -> PlayerStateData
local playerStates: {[number]: PlayerStateData} = {}

-- P0 FIX: Transition locks to prevent race conditions
local transitionLocks: {[number]: boolean} = {}

-- P0 FIX: Per-player cooldowns for state transitions
local transitionCooldowns: {[number]: number} = {}
local TRANSITION_COOLDOWN = 2 -- 2 seconds between transitions

-- Analytics
local analytics = {
	totalTransitions = 0,
	transitionCounts = {} :: {[string]: number}, -- "Lobby->Arena" -> count
	currentStateCounts = {} :: {[PlayerState]: number},
	blockedByLock = 0,
	blockedByCooldown = 0,
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

-- P0 FIX: Acquire transition lock (atomic operation)
local function acquireTransitionLock(userId: number): boolean
	if transitionLocks[userId] then
		analytics.blockedByLock += 1
		return false
	end
	transitionLocks[userId] = true
	return true
end

-- P0 FIX: Release transition lock
local function releaseTransitionLock(userId: number)
	transitionLocks[userId] = nil
end

-- P0 FIX: Check cooldown
local function isOnCooldown(userId: number): boolean
	local lastTransition = transitionCooldowns[userId]
	if not lastTransition then
		return false
	end
	return (os.clock() - lastTransition) < TRANSITION_COOLDOWN
end

-- P0 FIX: Set cooldown
local function setCooldown(userId: number)
	transitionCooldowns[userId] = os.clock()
end

-- P0 FIX: แยก validation logic (ไม่เช็ค lock)
local function validateTransition(userId: number, currentState: PlayerState, targetState: PlayerState): (boolean, string?)
	-- ✅ NEW: ห้าม transition จาก Downed (ยกเว้นไป Died, Arena, Spectating)
	if currentState == "Downed" then
		if targetState ~= "Died" and targetState ~= "Arena" and targetState ~= "Spectating" then
			return false, `Cannot transition from Downed to {targetState} (only Died/Arena/Spectating allowed)`
		end
	end
	
	-- Check transition rules
	local allowedTargets = ALLOWED_TRANSITIONS[currentState]
	if not allowedTargets or not allowedTargets[targetState] then
		return false, string.format("Cannot transition from %s to %s", currentState, targetState)
	end
	
	return true
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
	print("  - Transition locks: ENABLED")
	print("  - Cooldown protection: ENABLED (" .. TRANSITION_COOLDOWN .. "s)")
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
		
		-- P0 FIX: Cleanup locks and cooldowns
		playerStates[userId] = nil
		transitionLocks[userId] = nil
		transitionCooldowns[userId] = nil
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- CLIENT REQUEST EVENTS
	-- ═══════════════════════════════════════════════════════════
	
	-- Request to join Arena
	EventBus:On(Events.PLAYER_REQUEST_TO_ARENA, function(player: Player, data: any)
		-- ✅ NEW: เช็คว่าไม่ได้อยู่ใน Downed state
		local currentState = self:GetState(player)
		
		if currentState == "Downed" then
			warn(`[PlayerStateService] ❌ {player.Name} is Downed, cannot join Arena`)
			
			NetworkHandler:SendToClient(player, Events.PLAYER_STATE_CHANGED, {
				state = "Arena",
				success = false,
				reason = "You are Downed! Wait for revive or timeout.",
				timestamp = os.clock()
			})
			return
		end
		
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
				warn(string.format("[PlayerStateService] ❌ Failed to move %s to Arena (locked)", player.Name))
				
				-- Notify client of failure
				NetworkHandler:SendToClient(player, Events.PLAYER_STATE_CHANGED, {
					state = "Arena",
					success = false,
					reason = "Transition in progress",
					timestamp = os.clock()
				})
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
		local canTransition, reason = self:CanTransition(player, "Lobby")
		
		if canTransition then
			local success = self:SetState(player, "Lobby", "Player request")
			
			if success then
				print(string.format("[PlayerStateService] ✅ %s returned to Lobby", player.Name))
				
				NetworkHandler:SendToClient(player, Events.PLAYER_STATE_CHANGED, {
					state = "Lobby",
					success = true,
					timestamp = os.clock()
				})
			end
		else
			NetworkHandler:SendToClient(player, Events.PLAYER_STATE_CHANGED, {
				state = "Lobby",
				success = false,
				reason = reason,
				timestamp = os.clock()
			})
		end
	end)
	
	-- Request to spectate
	EventBus:On(Events.PLAYER_REQUEST_TO_SPECTATE, function(player: Player, data: any)
		local canTransition, reason = self:CanTransition(player, "Spectating")
		
		if canTransition then
			local success = self:SetState(player, "Spectating", "Player request")
			
			if success then
				print(string.format("[PlayerStateService] ✅ %s is now spectating", player.Name))
				
				NetworkHandler:SendToClient(player, Events.PLAYER_STATE_CHANGED, {
					state = "Spectating",
					success = true,
					timestamp = os.clock()
				})
			end
		end
	end)
	
	-- ✅ Listen for death event from DeathService
	EventBus:On(Events.PLAYER_DIED, function(player: Player, deathData: any)
		local success = self:SetState(player, "Died", `Death: {deathData.cause}`)
		
		if success then
			print(string.format("[PlayerStateService] ✅ %s marked as Died", player.Name))
			
			NetworkHandler:SendToClient(player, Events.PLAYER_STATE_CHANGED, {
				state = "Died",
				success = true,
				deathData = deathData,
				timestamp = os.clock()
			})
		end
	end)
	
	-- ✅ NEW: Listen for respawn request
	EventBus:On(Events.PLAYER_RESPAWN_REQUESTED, function(player: Player, respawnData: any)
		local location = respawnData.location or "Lobby"
		local targetState = location == "Arena" and "Arena" or "Lobby"
		
		print(`[PlayerStateService] 🔄 Respawn requested for {player.Name} to {targetState}`)
		
		-- ✅ Force transition from Died to Lobby (bypass normal rules)
		local currentState = self:GetState(player)
		
		if currentState == "Died" then
			local success = self:SetState(player, targetState, `Respawn: {respawnData.reason or "Normal"}`)
			
			if success then
				print(`[PlayerStateService] ✅ {player.Name} respawned to {targetState}`)
			else
				warn(`[PlayerStateService] ❌ Failed to respawn {player.Name}`)
			end
		else
			warn(`[PlayerStateService] ⚠️ {player.Name} not in Died state (current: {currentState})`)
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
			print(string.format("  Blocked by lock: %d", stats.blockedByLock))
			print(string.format("  Blocked by cooldown: %d", stats.blockedByCooldown))
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

-- P0 FIX: Enhanced CanTransition with cooldown check
function PlayerStateService:CanTransition(player: Player | number, targetState: PlayerState): (boolean, string?)
    if not VALID_STATES[targetState] then
        return false, string.format("Invalid state: %s", tostring(targetState))
    end
    
    local userId = getUserId(player)
    
    -- P0 FIX: Check cooldown first
    if isOnCooldown(userId) then
        local remaining = TRANSITION_COOLDOWN - (os.clock() - (transitionCooldowns[userId] or 0))
        analytics.blockedByCooldown += 1
        return false, string.format("Cooldown active (%.1fs remaining)", remaining)
    end
    
    -- P0 FIX: Check if transition is already in progress
    if transitionLocks[userId] then
        return false, "Transition already in progress"
    end
    
    local stateData = playerStates[userId]
    
    if not stateData then
        return true
    end
    
    local currentState = stateData.currentState
    
    -- Idempotent: Already in target state = success (no-op)
    if currentState == targetState then
        return true, "Already in target state"
    end
    
    -- ✅ ใช้ validateTransition แทน
    return validateTransition(userId, currentState, targetState)
end

-- P0 FIX: Thread-safe SetState with lock
function PlayerStateService:SetState(player: Player | number, newState: PlayerState, reason: string?): boolean
    local userId = getUserId(player)
    
    -- Validate state
    if not VALID_STATES[newState] then
        warn(string.format("[PlayerStateService] Invalid state: %s", tostring(newState)))
        return false
    end
    
    -- P0 FIX: Acquire lock (atomic)ไ
    if not acquireTransitionLock(userId) then
        warn(string.format("[PlayerStateService] Transition blocked by lock for user %d", userId))
        return false
    end
    
    -- ✅ Everything below is protected by the lock
    local success = false
    
    -- ✅ Wrap in pcall to ensure lock is always released
    local pcallSuccess, pcallError = pcall(function()
        local stateData = playerStates[userId]
        if not stateData then
            stateData = initializePlayerState(userId)
        end
        
        local oldState = stateData.currentState
        
        -- Idempotent: Already in target state
        if oldState == newState then
            print(string.format("[PlayerStateService] %d already in %s (idempotent)", userId, newState))
            success = true
            return
        end
        
        -- ✅ Validate transition (without checking lock!)
        local canTransition, transitionReason = validateTransition(userId, oldState, newState)
        if not canTransition then
            warn(string.format("[PlayerStateService] Transition blocked: %s", transitionReason or "Unknown"))
            success = false
            return
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
        
        -- P0 FIX: Set cooldown
        setCooldown(userId)
        
        -- Update analytics
        updateAnalytics(oldState, newState)
        
        -- Emit internal event
        local playerInstance = getPlayer(userId)
        if playerInstance then
            EventBus:Emit(Events.PLAYER_STATE_CHANGED_INTERNAL, playerInstance, {
                oldState = oldState,
                newState = newState,
                reason = reason,
                timestamp = transition.timestamp
            })
        end
        
        success = true
    end)
    
    -- ✅ ALWAYS release lock (even if error)
    releaseTransitionLock(userId)
    
    if not pcallSuccess then
        warn(string.format("[PlayerStateService] ❌ SetState error: %s", tostring(pcallError)))
        return false
    end
    
    return success
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
		blockedByLock = analytics.blockedByLock,
		blockedByCooldown = analytics.blockedByCooldown,
		uptime = uptime,
		transitionsPerMinute = uptime > 0 and (analytics.totalTransitions / uptime * 60) or 0,
	}
end

return PlayerStateService
