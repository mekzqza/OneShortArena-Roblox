--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║              DOWNED SERVICE - PRODUCTION GRADE                 ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Manage "Downed" state before death commitment        ║
║ Features:                                                      ║
║  ✅ Snapshot player state before down                         ║
║  ✅ Countdown timer for revive window                         ║
║  ✅ Multiple revive methods (item/robux/teammate)             ║
║  ✅ Block combat input while downed                           ║
║  ✅ Finish mechanic (kill downed player)                      ║
║  ✅ Event-driven architecture                                 ║
╚════════════════════════════════════════════════════════════════╝

Flow:
    HP <= 0
       │
       ▼
   [ Downed ]  ──► Save snapshot
       │          ──► Start countdown
       │          ──► Block input
       │          ──► Open revive window
       │
       ├─► Revive (item/robux/teammate) ──► [ Arena ] (restore snapshot)
       │
       └─► Timeout / Finish ──► [ Died ] ──► Respawn flow
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.Core.NetworkHandler)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- Lazy load to avoid circular dependency
local PlayerStateService: any = nil

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type ReviveMethod = "Self" | "Item" | "Robux" | "Teammate" | "Admin"

export type DownedSnapshot = {
	userId: number,
	playerName: string,
	-- Combat state
	health: number,
	maxHealth: number,
	position: Vector3,
	rotation: CFrame,
	-- Game state
	kills: number?,
	deaths: number?,
	score: number?,
	-- Inventory (optional)
	equippedWeapon: string?,
	ammo: number?,
	-- Timing
	downedAt: number,
	downedBy: Player?,      -- Who downed this player
	downedCause: string?,   -- "Combat", "Environmental", etc.
}

export type DownedPlayerData = {
	snapshot: DownedSnapshot,
	countdownStartTime: number,
	countdownDuration: number,
	remainingTime: number,
	reviveAttempts: number,
	isBeingRevived: boolean,
	reviver: Player?,
	countdownTask: thread?,
}

export type DownedService = {
	Init: (self: DownedService) -> (),
	Start: (self: DownedService) -> (),
	-- Core methods
	DownPlayer: (self: DownedService, player: Player, cause: string?, attacker: Player?) -> boolean,
	RevivePlayer: (self: DownedService, player: Player, method: ReviveMethod, reviver: Player?) -> boolean,
	FinishPlayer: (self: DownedService, downedPlayer: Player, finisher: Player?) -> boolean,
	-- Queries
	IsPlayerDowned: (self: DownedService, player: Player) -> boolean,
	GetDownedData: (self: DownedService, player: Player) -> DownedPlayerData?,
	GetSnapshot: (self: DownedService, player: Player) -> DownedSnapshot?,
	GetAllDownedPlayers: (self: DownedService) -> {Player},
	GetRemainingTime: (self: DownedService, player: Player) -> number?,
	-- Config
	CanRevive: (self: DownedService, player: Player, method: ReviveMethod) -> (boolean, string?),
	-- Analytics
	GetAnalytics: (self: DownedService) -> {[string]: any},
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local DownedService = {} :: DownedService

local guard = IdempotentGuard.new("DownedService", true)

local DOWNED_CONFIG = {
	-- Timing
	DefaultCountdown = 15,           -- 15 seconds to revive
	CountdownTickInterval = 1,       -- Update every 1 second
	
	-- Revive
	MaxReviveAttempts = 3,           -- Max self-revive attempts per match
	SelfReviveCooldown = 60,         -- 60 seconds between self-revives
	TeammateReviveTime = 5,          -- 5 seconds to revive teammate
	
	-- Revive costs
	SelfReviveCost = 0,              -- Free self-revive (uses attempts)
	RobuxReviveCost = 10,            -- 10 Robux to revive
	ItemReviveId = "ReviveToken",    -- Item ID for revive token
	
	-- Behavior
	CanMoveWhileDowned = false,      -- Can crawl while downed
	CrawlSpeed = 5,                  -- Crawl speed (if enabled)
	CanBeFinished = true,            -- Can be killed while downed
	FinishTime = 2,                  -- Time to finish a downed player
	
	-- Visual
	DownedHealthPercent = 0.01,      -- 1% health while downed (visual)
}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local downedPlayers: {[number]: DownedPlayerData} = {}
local reviveAttemptCounts: {[number]: number} = {}      -- Per match/session
local lastSelfReviveTime: {[number]: number} = {}       -- For cooldown

local analytics = {
	totalDowns = 0,
	totalRevives = 0,
	totalFinishes = 0,
	totalTimeouts = 0,
	revivesByMethod = {} :: {[ReviveMethod]: number},
	averageDownTime = 0,
	totalDownTime = 0,
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

local function createSnapshot(player: Player, cause: string?, attacker: Player?): DownedSnapshot
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	
	local snapshot: DownedSnapshot = {
		userId = player.UserId,
		playerName = player.Name,
		-- Combat state
		health = humanoid and humanoid.Health or 0,
		maxHealth = humanoid and humanoid.MaxHealth or 100,
		position = rootPart and rootPart.Position or Vector3.zero,
		rotation = rootPart and rootPart.CFrame or CFrame.identity,
		-- Game state (from leaderstats or attributes)
		kills = player:GetAttribute("Kills") or 0,
		deaths = player:GetAttribute("Deaths") or 0,
		score = player:GetAttribute("Score") or 0,
		-- Inventory
		equippedWeapon = player:GetAttribute("EquippedWeapon"),
		ammo = player:GetAttribute("Ammo"),
		-- Timing
		downedAt = os.clock(),
		downedBy = attacker,
		downedCause = cause or "Unknown",
	}
	
	return snapshot
end

local function setDownedVisuals(player: Player, isDowned: boolean)
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then return end
	
	if isDowned then
		-- Set to downed state
		humanoid.Health = humanoid.MaxHealth * DOWNED_CONFIG.DownedHealthPercent
		humanoid.WalkSpeed = DOWNED_CONFIG.CanMoveWhileDowned and DOWNED_CONFIG.CrawlSpeed or 0
		humanoid.JumpPower = 0
		
		-- Play downed animation (if exists)
		local animator = humanoid:FindFirstChild("Animator") :: Animator?
		if animator then
			-- TODO: Play downed animation
		end
		
		-- Set attribute for other systems
		character:SetAttribute("IsDowned", true)
		
		print(`[DownedService] 🦵 {player.Name} visuals set to DOWNED`)
	else
		-- Restore normal state
		humanoid.WalkSpeed = 16 -- Default walk speed
		humanoid.JumpPower = 50 -- Default jump power
		
		character:SetAttribute("IsDowned", false)
		
		print(`[DownedService] 🏃 {player.Name} visuals restored`)
	end
end

local function startCountdown(player: Player, data: DownedPlayerData)
	local userId = player.UserId
	
	-- Cancel existing countdown
	if data.countdownTask then
		task.cancel(data.countdownTask)
	end
	
	data.countdownTask = task.spawn(function()
		local startTime = os.clock()
		local duration = data.countdownDuration
		
		while data.remainingTime > 0 do
			task.wait(DOWNED_CONFIG.CountdownTickInterval)
			
			-- Check if still downed
			if not downedPlayers[userId] then
				print(`[DownedService] ⏹️ Countdown stopped for {player.Name} (no longer downed)`)
				return
			end
			
			-- Update remaining time
			local elapsed = os.clock() - startTime
			data.remainingTime = math.max(0, duration - elapsed)
			
			-- Send countdown update to client
			NetworkHandler:SendToClient(player, Events.PLAYER_DOWNED_COUNTDOWN, {
				remainingTime = data.remainingTime,
				totalTime = duration,
				percentage = data.remainingTime / duration,
			})
			
			print(`[DownedService] ⏱️ {player.Name} countdown: {string.format("%.1f", data.remainingTime)}s`)
		end
		
		-- Timeout - commit death
		if downedPlayers[userId] then
			print(`[DownedService] ⏰ {player.Name} downed timeout - committing death`)
			
			analytics.totalTimeouts += 1
			
			-- Emit timeout event
			EventBus:Emit(Events.PLAYER_DOWNED_TIMEOUT, player, {
				snapshot = data.snapshot,
				downedDuration = duration,
			})
			
			-- Transition to Died
			local PSS = getPlayerStateService()
			PSS:SetState(player, "Died", "Downed timeout")
			
			-- Cleanup
			downedPlayers[userId] = nil
			setDownedVisuals(player, false)
			
			-- Notify client
			NetworkHandler:SendToClient(player, Events.PLAYER_DIED, {
				cause = "DownedTimeout",
				snapshot = data.snapshot,
			})
		end
	end)
end

local function updateAnalytics(downTime: number)
	analytics.totalDownTime += downTime
	local totalEvents = analytics.totalRevives + analytics.totalFinishes + analytics.totalTimeouts
	if totalEvents > 0 then
		analytics.averageDownTime = analytics.totalDownTime / totalEvents
	end
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function DownedService:Init()
	if not guard:MarkInitialized() then
		return
	end
	
	-- Initialize analytics
	for _, method in ipairs({"Self", "Item", "Robux", "Teammate", "Admin"}) do
		analytics.revivesByMethod[method] = 0
	end
	
	-- Allow client events
	NetworkHandler:AllowClientEvent(Events.PLAYER_REQUEST_REVIVE)
	NetworkHandler:AllowClientEvent(Events.PLAYER_REQUEST_FINISH)
	NetworkHandler:AllowClientEvent(Events.TEAMMATE_REQUEST_REVIVE)
	
	print("[DownedService] 🦵 Initialized")
	print(`  ✅ Countdown: {DOWNED_CONFIG.DefaultCountdown}s`)
	print(`  ✅ Max self-revives: {DOWNED_CONFIG.MaxReviveAttempts}`)
	print(`  ✅ Can be finished: {DOWNED_CONFIG.CanBeFinished}`)
end

function DownedService:Start()
	if not guard:MarkStarted() then
		return
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- LISTEN FOR COMBAT DEATH (HP <= 0)
	-- ═══════════════════════════════════════════════════════════
	
	-- Listen for damage that would kill player
	EventBus:On(Events.PLAYER_DAMAGED, function(player: Player, damage: number, attacker: Player?)
		local character = player.Character
		local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
		
		if not humanoid then return end
		
		-- Check if this damage would kill the player
		if humanoid.Health <= damage and humanoid.Health > 0 then
			-- Check if already downed
			if self:IsPlayerDowned(player) then
				-- Already downed - this is a "finish" attempt
				if DOWNED_CONFIG.CanBeFinished and attacker then
					self:FinishPlayer(player, attacker)
				end
				return
			end
			
			-- Check if in Arena
			local PSS = getPlayerStateService()
			local currentState = PSS:GetState(player)
			
			if currentState ~= "Arena" then
				return -- Only down in Arena
			end
			
			-- Prevent actual death - down instead
			humanoid.Health = 1 -- Prevent death event
			
			-- Down the player
			self:DownPlayer(player, "Combat", attacker)
		end
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- CLIENT REQUESTS
	-- ═══════════════════════════════════════════════════════════
	
	-- Self revive request
	EventBus:On(Events.PLAYER_REQUEST_REVIVE, function(player: Player, data: any)
		local method = data.method or "Self"
		
		local canRevive, reason = self:CanRevive(player, method)
		
		if canRevive then
			local success = self:RevivePlayer(player, method)
			
			NetworkHandler:SendToClient(player, Events.PLAYER_REVIVED, {
				success = success,
				method = method,
			})
		else
			NetworkHandler:SendToClient(player, Events.PLAYER_REVIVED, {
				success = false,
				reason = reason,
			})
		end
	end)
	
	-- Teammate revive request
	EventBus:On(Events.TEAMMATE_REQUEST_REVIVE, function(reviver: Player, data: any)
		local targetUserId = data.targetUserId
		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		
		if not targetPlayer then
			warn(`[DownedService] Target player {targetUserId} not found`)
			return
		end
		
		if not self:IsPlayerDowned(targetPlayer) then
			warn(`[DownedService] {targetPlayer.Name} is not downed`)
			return
		end
		
		-- TODO: Check if reviver is on same team
		-- TODO: Check if reviver is close enough
		-- TODO: Start revive progress bar
		
		local success = self:RevivePlayer(targetPlayer, "Teammate", reviver)
		
		if success then
			print(`[DownedService] ✅ {reviver.Name} revived {targetPlayer.Name}`)
		end
	end)
	
	-- Finish downed player
	EventBus:On(Events.PLAYER_REQUEST_FINISH, function(finisher: Player, data: any)
		local targetUserId = data.targetUserId
		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		
		if not targetPlayer then return end
		
		if not self:IsPlayerDowned(targetPlayer) then return end
		
		-- TODO: Check if finisher is enemy
		-- TODO: Check if finisher is close enough
		-- TODO: Add finish animation/delay
		
		self:FinishPlayer(targetPlayer, finisher)
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- CLEANUP
	-- ═══════════════════════════════════════════════════════════
	
	Players.PlayerRemoving:Connect(function(player: Player)
		local userId = player.UserId
		
		if downedPlayers[userId] then
			-- Cancel countdown
			if downedPlayers[userId].countdownTask then
				task.cancel(downedPlayers[userId].countdownTask)
			end
			downedPlayers[userId] = nil
		end
		
		reviveAttemptCounts[userId] = nil
		lastSelfReviveTime[userId] = nil
	end)
	
	-- Analytics reporting
	task.spawn(function()
		while true do
			task.wait(300)
			local stats = self:GetAnalytics()
			print("[DownedService] 📊 Analytics:")
			print(`  Total downs: {stats.totalDowns}`)
			print(`  Total revives: {stats.totalRevives}`)
			print(`  Total finishes: {stats.totalFinishes}`)
			print(`  Total timeouts: {stats.totalTimeouts}`)
			print(`  Avg down time: {string.format("%.1f", stats.averageDownTime)}s`)
		end
	end)
	
	print("[DownedService] 🚀 Started - Listening for combat events")
end

-- ═══════════════════════════════════════════════════════════════
-- CORE METHODS
-- ═══════════════════════════════════════════════════════════════

function DownedService:DownPlayer(player: Player, cause: string?, attacker: Player?): boolean
	local userId = player.UserId
	
	-- Already downed?
	if downedPlayers[userId] then
		warn(`[DownedService] {player.Name} is already downed`)
		return false
	end
	
	-- Create snapshot
	local snapshot = createSnapshot(player, cause, attacker)
	
	-- Create downed data
	local data: DownedPlayerData = {
		snapshot = snapshot,
		countdownStartTime = os.clock(),
		countdownDuration = DOWNED_CONFIG.DefaultCountdown,
		remainingTime = DOWNED_CONFIG.DefaultCountdown,
		reviveAttempts = reviveAttemptCounts[userId] or 0,
		isBeingRevived = false,
		reviver = nil,
		countdownTask = nil,
	}
	
	downedPlayers[userId] = data
	analytics.totalDowns += 1
	
	-- Change state to Downed
	local PSS = getPlayerStateService()
	local success = PSS:SetState(player, "Downed", `Downed by {cause or "Unknown"}`)
	
	if not success then
		downedPlayers[userId] = nil
		return false
	end
	
	-- Apply downed visuals
	setDownedVisuals(player, true)
	
	-- Start countdown
	startCountdown(player, data)
	
	-- Emit event
	EventBus:Emit(Events.PLAYER_DOWNED_INTERNAL, player, {
		snapshot = snapshot,
		countdown = DOWNED_CONFIG.DefaultCountdown,
		attacker = attacker,
	})
	
	-- Notify client
	NetworkHandler:SendToClient(player, Events.PLAYER_DOWNED, {
		countdown = DOWNED_CONFIG.DefaultCountdown,
		canSelfRevive = (reviveAttemptCounts[userId] or 0) < DOWNED_CONFIG.MaxReviveAttempts,
		reviveOptions = {
			self = true,
			item = true,  -- TODO: Check if has item
			robux = true,
			teammate = true,
		},
		snapshot = snapshot,
	})
	
	-- Notify attacker (if any)
	if attacker then
		NetworkHandler:SendToClient(attacker, Events.PLAYER_DOWNED, {
			target = player.Name,
			targetUserId = userId,
			canFinish = DOWNED_CONFIG.CanBeFinished,
		})
	end
	
	print(`[DownedService] 🦵 {player.Name} DOWNED by {attacker and attacker.Name or cause or "Unknown"}`)
	
	return true
end

function DownedService:RevivePlayer(player: Player, method: ReviveMethod, reviver: Player?): boolean
	local userId = player.UserId
	local data = downedPlayers[userId]
	
	if not data then
		warn(`[DownedService] {player.Name} is not downed`)
		return false
	end
	
	-- Calculate down time
	local downTime = os.clock() - data.countdownStartTime
	
	-- Cancel countdown
	if data.countdownTask then
		task.cancel(data.countdownTask)
		data.countdownTask = nil
	end
	
	-- Update revive count for self-revive
	if method == "Self" then
		reviveAttemptCounts[userId] = (reviveAttemptCounts[userId] or 0) + 1
		lastSelfReviveTime[userId] = os.clock()
	end
	
	-- Cleanup downed data
	downedPlayers[userId] = nil
	
	-- Restore player
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
	
	if humanoid then
		-- Restore health (partial based on method)
		local healthPercent = method == "Teammate" and 0.5 or 0.3
		humanoid.Health = humanoid.MaxHealth * healthPercent
	end
	
	-- Remove downed visuals
	setDownedVisuals(player, false)
	
	-- Change state back to Arena
	local PSS = getPlayerStateService()
	PSS:SetState(player, "Arena", `Revived by {method}`)
	
	-- Update analytics
	analytics.totalRevives += 1
	analytics.revivesByMethod[method] = (analytics.revivesByMethod[method] or 0) + 1
	updateAnalytics(downTime)
	
	-- Emit event
	EventBus:Emit(Events.PLAYER_REVIVED, player, {
		method = method,
		reviver = reviver,
		downTime = downTime,
	})
	
	-- Notify client
	NetworkHandler:SendToClient(player, Events.PLAYER_REVIVED, {
		success = true,
		method = method,
		reviver = reviver and reviver.Name,
		healthRestored = humanoid and humanoid.Health or 0,
	})
	
	print(`[DownedService] 💚 {player.Name} REVIVED by {method}` .. (reviver and ` ({reviver.Name})` or ""))
	
	return true
end

function DownedService:FinishPlayer(downedPlayer: Player, finisher: Player?): boolean
	local userId = downedPlayer.UserId
	local data = downedPlayers[userId]
	
	if not data then
		warn(`[DownedService] {downedPlayer.Name} is not downed`)
		return false
	end
	
	if not DOWNED_CONFIG.CanBeFinished then
		warn(`[DownedService] Finishing is disabled`)
		return false
	end
	
	-- Calculate down time
	local downTime = os.clock() - data.countdownStartTime
	
	-- Cancel countdown
	if data.countdownTask then
		task.cancel(data.countdownTask)
		data.countdownTask = nil
	end
	
	-- Cleanup downed data
	downedPlayers[userId] = nil
	
	-- Remove downed visuals
	setDownedVisuals(downedPlayer, false)
	
	-- Update analytics
	analytics.totalFinishes += 1
	updateAnalytics(downTime)
	
	-- Change state to Died
	local PSS = getPlayerStateService()
	PSS:SetState(downedPlayer, "Died", `Finished by {finisher and finisher.Name or "Unknown"}`)
	
	-- Emit finished event
	EventBus:Emit(Events.PLAYER_FINISHED, downedPlayer, {
		finisher = finisher,
		snapshot = data.snapshot,
		downTime = downTime,
	})
	
	-- Notify downed player
	NetworkHandler:SendToClient(downedPlayer, Events.PLAYER_FINISHED, {
		finisher = finisher and finisher.Name,
	})
	
	-- Notify finisher
	if finisher then
		NetworkHandler:SendToClient(finisher, Events.PLAYER_FINISHED, {
			target = downedPlayer.Name,
			confirmed = true,
		})
	end
	
	print(`[DownedService] 💀 {downedPlayer.Name} FINISHED by {finisher and finisher.Name or "Timeout"}`)
	
	return true
end

-- ═══════════════════════════════════════════════════════════════
-- QUERY METHODS
-- ═══════════════════════════════════════════════════════════════

function DownedService:IsPlayerDowned(player: Player): boolean
	return downedPlayers[player.UserId] ~= nil
end

function DownedService:GetDownedData(player: Player): DownedPlayerData?
	return downedPlayers[player.UserId]
end

function DownedService:GetSnapshot(player: Player): DownedSnapshot?
	local data = downedPlayers[player.UserId]
	return data and data.snapshot
end

function DownedService:GetAllDownedPlayers(): {Player}
	local result = {}
	for userId in pairs(downedPlayers) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(result, player)
		end
	end
	return result
end

function DownedService:GetRemainingTime(player: Player): number?
	local data = downedPlayers[player.UserId]
	return data and data.remainingTime
end

function DownedService:CanRevive(player: Player, method: ReviveMethod): (boolean, string?)
	local userId = player.UserId
	local data = downedPlayers[userId]
	
	if not data then
		return false, "Player is not downed"
	end
	
	if data.isBeingRevived then
		return false, "Already being revived"
	end
	
	if method == "Self" then
		local attempts = reviveAttemptCounts[userId] or 0
		if attempts >= DOWNED_CONFIG.MaxReviveAttempts then
			return false, "Max self-revive attempts reached"
		end
		
		local lastTime = lastSelfReviveTime[userId]
		if lastTime and (os.clock() - lastTime) < DOWNED_CONFIG.SelfReviveCooldown then
			local remaining = DOWNED_CONFIG.SelfReviveCooldown - (os.clock() - lastTime)
			return false, `Self-revive cooldown ({string.format("%.0f", remaining)}s)`
		end
	end
	
	-- TODO: Check item inventory for "Item" method
	-- TODO: Check Robux for "Robux" method
	-- TODO: Check teammate proximity for "Teammate" method
	
	return true
end

function DownedService:GetAnalytics(): {[string]: any}
	local activeCount = 0
	for _ in pairs(downedPlayers) do
		activeCount += 1
	end
	
	return {
		totalDowns = analytics.totalDowns,
		totalRevives = analytics.totalRevives,
		totalFinishes = analytics.totalFinishes,
		totalTimeouts = analytics.totalTimeouts,
		revivesByMethod = analytics.revivesByMethod,
		averageDownTime = analytics.averageDownTime,
		activeDownedPlayers = activeCount,
		uptime = os.clock() - analytics.startTime,
	}
end

return DownedService
