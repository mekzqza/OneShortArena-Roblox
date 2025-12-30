--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║              DOWNED SERVICE - PRODUCTION GRADE v2.0            ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Manage "Downed" state lifecycle ONLY                 ║
╚════════════════════════════════════════════════════════════════╝
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

export type ReviveMethod = "Self" | "Item" | "Robux" | "Teammate" | "Admin"

export type DownedSnapshot = {
	userId: number,
	playerName: string,
	health: number,
	maxHealth: number,
	position: Vector3,
	rotation: CFrame,
	downedAt: number,
	downedBy: Player?,
	downedCause: string?,
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
	DownPlayer: (self: DownedService, player: Player, cause: string?, attacker: Player?) -> boolean,
	RevivePlayer: (self: DownedService, player: Player, method: ReviveMethod, reviver: Player?) -> boolean,
	FinishPlayer: (self: DownedService, downedPlayer: Player, finisher: Player?) -> boolean,
	IsPlayerDowned: (self: DownedService, player: Player) -> boolean,
	GetDownedData: (self: DownedService, player: Player) -> DownedPlayerData?,
	GetSnapshot: (self: DownedService, player: Player) -> DownedSnapshot?,
	GetAllDownedPlayers: (self: DownedService) -> {Player},
	GetRemainingTime: (self: DownedService, player: Player) -> number?,
	CanRevive: (self: DownedService, player: Player, method: ReviveMethod) -> (boolean, string?),
	GetAnalytics: (self: DownedService) -> {[string]: any},
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local DownedService = {} :: DownedService

local guard = IdempotentGuard.new("DownedService", true)

local DOWNED_CONFIG = {
	DefaultCountdown = 15,
	CountdownTickInterval = 1,
	MaxReviveAttempts = 3,
	SelfReviveCooldown = 60,
	TeammateReviveTime = 5,
	CanBeFinished = true,
	DownedHealthPercent = 0.01,
	CanMoveWhileDowned = false,
	CrawlSpeed = 5,
}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local downedPlayers: {[number]: DownedPlayerData} = {}
local reviveAttemptCounts: {[number]: number} = {}
local lastSelfReviveTime: {[number]: number} = {}
local downedLocks: {[number]: boolean} = {}

local analytics = {
	totalDowns = 0,
	totalRevives = 0,
	totalFinishes = 0,
	totalTimeouts = 0,
	blockedByLock = 0,
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

local function acquireDownedLock(userId: number): boolean
	if downedLocks[userId] then
		analytics.blockedByLock += 1
		return false
	end
	downedLocks[userId] = true
	return true
end

local function releaseDownedLock(userId: number)
	downedLocks[userId] = nil
end

local function createSnapshot(player: Player, cause: string?, attacker: Player?): DownedSnapshot
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	
	return {
		userId = player.UserId,
		playerName = player.Name,
		health = humanoid and humanoid.Health or 0,
		maxHealth = humanoid and humanoid.MaxHealth or 100,
		position = rootPart and rootPart.Position or Vector3.zero,
		rotation = rootPart and rootPart.CFrame or CFrame.identity,
		downedAt = os.clock(),
		downedBy = attacker,
		downedCause = cause or "Unknown",
	}
end

local function setDownedVisuals(player: Player, isDowned: boolean)
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	
	if not humanoid then return end
	
	if isDowned then
		-- ✅ Make player ragdoll
		humanoid.PlatformStand = true
		humanoid.Health = humanoid.MaxHealth * DOWNED_CONFIG.DownedHealthPercent
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
		
		character:SetAttribute("IsDowned", true)
		
		-- Disable collision
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
		
		-- Visual effect
		if rootPart then
			local highlight = Instance.new("Highlight")
			highlight.Name = "DownedHighlight"
			highlight.FillColor = Color3.fromRGB(255, 0, 0)
			highlight.FillTransparency = 0.5
			highlight.OutlineColor = Color3.fromRGB(255, 100, 100)
			highlight.OutlineTransparency = 0
			highlight.Parent = character
		end
		
		print(`[DownedService] 🦵 {player.Name} visuals set to DOWNED (ragdolled)`)
	else
		-- Restore
		humanoid.PlatformStand = false
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		humanoid.JumpHeight = 7.2
		humanoid.AutoRotate = true
		
		character:SetAttribute("IsDowned", false)
		
		-- Restore collision
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = true
			end
		end
		
		-- Remove highlight
		local highlight = character:FindFirstChild("DownedHighlight")
		if highlight then
			highlight:Destroy()
		end
		
		print(`[DownedService] 🏃 {player.Name} visuals restored`)
	end
end

local function startCountdown(player: Player, data: DownedPlayerData)
	local userId = player.UserId
	
	if data.countdownTask then
		task.cancel(data.countdownTask)
	end
	
	data.countdownTask = task.spawn(function()
		local startTime = os.clock()
		local duration = data.countdownDuration
		
		-- Countdown loop
		while data.remainingTime > 0 do
			task.wait(DOWNED_CONFIG.CountdownTickInterval)
			
			if not downedPlayers[userId] then
				return
			end
			
			local elapsed = os.clock() - startTime
			data.remainingTime = math.max(0, duration - elapsed)
			
			NetworkHandler:SendToClient(player, Events.PLAYER_DOWNED_COUNTDOWN, {
				remainingTime = data.remainingTime,
				totalTime = duration,
				percentage = data.remainingTime / duration,
			})
			
			print(`[DownedService] ⏱️ {player.Name} countdown: {string.format("%.1f", data.remainingTime)}s`)
		end
		
		-- Countdown finished
		if not downedPlayers[userId] then
			return
		end
		
		if not acquireDownedLock(userId) then
			warn(`[DownedService] ⚠️ Timeout blocked by lock for {player.Name}`)
			return
		end
		
		if not downedPlayers[userId] then
			releaseDownedLock(userId)
			return
		end
		
		print(`[DownedService] ⏰ {player.Name} downed timeout (countdown finished!)`)
		
		analytics.totalTimeouts += 1
		local downTime = os.clock() - data.countdownStartTime
		analytics.totalDownTime += downTime
		
		local snapshot = data.snapshot
		
		downedPlayers[userId] = nil
		setDownedVisuals(player, false)
		
		local PSS = getPlayerStateService()
		PSS:SetState(player, "Died", "Downed timeout")
		
		NetworkHandler:SendToClient(player, Events.PLAYER_DIED, {
			cause = "DownedTimeout",
			snapshot = snapshot,
		})
		
		EventBus:Emit(Events.PLAYER_DOWNED_TIMEOUT, player, {
			snapshot = snapshot,
			downedDuration = duration,
		})
		
		releaseDownedLock(userId)
	end)
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function DownedService:Init()
	if not guard:MarkInitialized() then
		return
	end
	
	for _, method in ipairs({"Self", "Item", "Robux", "Teammate", "Admin"}) do
		analytics.revivesByMethod[method] = 0
	end
	
	NetworkHandler:AllowClientEvent(Events.PLAYER_REQUEST_REVIVE)
	NetworkHandler:AllowClientEvent(Events.PLAYER_REQUEST_FINISH)
	NetworkHandler:AllowClientEvent(Events.TEAMMATE_REQUEST_REVIVE)
	
	print("[DownedService] 🦵 Initialized v2.0")
	print(`  ✅ Countdown: {DOWNED_CONFIG.DefaultCountdown}s`)
	print(`  ✅ P0 Downed Lock: ENABLED`)
end

function DownedService:Start()
	if not guard:MarkStarted() then
		return
	end
	
	EventBus:On(Events.PLAYER_FATAL_HIT, function(player: Player, data: any)
		if self:IsPlayerDowned(player) then
			print(`[DownedService] ⏭️ {player.Name} is already downed, ignoring fatal hit`)
			return
		end
		
		local character = player.Character
		if character and character:GetAttribute("IsDowned") then
			print(`[DownedService] ⏭️ {player.Name} has IsDowned attribute, ignoring`)
			return
		end
		
		print(`[DownedService] 📥 Fatal hit received for {player.Name}`)
		self:DownPlayer(player, data.damageType or "Combat", data.attacker)
	end)
	
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
	
	EventBus:On(Events.TEAMMATE_REQUEST_REVIVE, function(reviver: Player, data: any)
		local targetUserId = data.targetUserId
		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		
		if not targetPlayer then return end
		if not self:IsPlayerDowned(targetPlayer) then return end
		
		self:RevivePlayer(targetPlayer, "Teammate", reviver)
	end)
	
	EventBus:On(Events.PLAYER_REQUEST_FINISH, function(finisher: Player, data: any)
		local targetUserId = data.targetUserId
		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		
		if not targetPlayer then return end
		if not self:IsPlayerDowned(targetPlayer) then return end
		
		self:FinishPlayer(targetPlayer, finisher)
	end)
	
	Players.PlayerRemoving:Connect(function(player: Player)
		local userId = player.UserId
		
		if downedPlayers[userId] then
			if downedPlayers[userId].countdownTask then
				task.cancel(downedPlayers[userId].countdownTask)
			end
			downedPlayers[userId] = nil
		end
		
		downedLocks[userId] = nil
		reviveAttemptCounts[userId] = nil
		lastSelfReviveTime[userId] = nil
	end)
	
	print("[DownedService] 🚀 Started - Listening for PLAYER_FATAL_HIT")
end

function DownedService:DownPlayer(player: Player, cause: string?, attacker: Player?): boolean
	local userId = player.UserId
	
	if not acquireDownedLock(userId) then
		warn(`[DownedService] ⚠️ DownPlayer blocked by lock for {player.Name}`)
		return false
	end
	
	local success = false
	
	pcall(function()
		if downedPlayers[userId] then
			warn(`[DownedService] {player.Name} is already downed`)
			return
		end
		
		local snapshot = createSnapshot(player, cause, attacker)
		
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
		
		local PSS = getPlayerStateService()
		local stateSuccess = PSS:SetState(player, "Downed", `Downed by {cause or "Unknown"}`)
		
		if not stateSuccess then
			downedPlayers[userId] = nil
			return
		end
		
		setDownedVisuals(player, true)
		startCountdown(player, data)
		
		EventBus:Emit(Events.PLAYER_DOWNED_INTERNAL, player, {
			snapshot = snapshot,
			countdown = DOWNED_CONFIG.DefaultCountdown,
			attacker = attacker,
		})
		
		NetworkHandler:SendToClient(player, Events.PLAYER_DOWNED, {
			countdown = DOWNED_CONFIG.DefaultCountdown,
			canSelfRevive = (reviveAttemptCounts[userId] or 0) < DOWNED_CONFIG.MaxReviveAttempts,
			reviveOptions = {self = true, item = true, robux = true, teammate = true},
			snapshot = snapshot,
		})
		
		if attacker then
			NetworkHandler:SendToClient(attacker, Events.PLAYER_DOWNED, {
				target = player.Name,
				targetUserId = userId,
				canFinish = DOWNED_CONFIG.CanBeFinished,
			})
		end
		
		print(`[DownedService] 🦵 {player.Name} DOWNED by {attacker and attacker.Name or cause or "Unknown"}`)
		success = true
	end)
	
	releaseDownedLock(userId)
	
	return success
end

function DownedService:RevivePlayer(player: Player, method: ReviveMethod, reviver: Player?): boolean
	local userId = player.UserId
	
	if not acquireDownedLock(userId) then
		warn(`[DownedService] ⚠️ RevivePlayer blocked by lock for {player.Name}`)
		return false
	end
	
	local success = false
	
	pcall(function()
		local data = downedPlayers[userId]
		
		if not data then
			warn(`[DownedService] {player.Name} is not downed`)
			return
		end
		
		local downTime = os.clock() - data.countdownStartTime
		
		if data.countdownTask then
			task.cancel(data.countdownTask)
			data.countdownTask = nil
		end
		
		if method == "Self" then
			reviveAttemptCounts[userId] = (reviveAttemptCounts[userId] or 0) + 1
			lastSelfReviveTime[userId] = os.clock()
		end
		
		downedPlayers[userId] = nil
		
		local character = player.Character
		local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
		
		if humanoid then
			local healthPercent = method == "Teammate" and 0.5 or 0.3
			humanoid.Health = humanoid.MaxHealth * healthPercent
		end
		
		setDownedVisuals(player, false)
		
		local PSS = getPlayerStateService()
		PSS:SetState(player, "Arena", `Revived by {method}`)
		
		analytics.totalRevives += 1
		analytics.revivesByMethod[method] = (analytics.revivesByMethod[method] or 0) + 1
		analytics.totalDownTime += downTime
		
		EventBus:Emit(Events.PLAYER_REVIVED, player, {
			method = method,
			reviver = reviver,
			downTime = downTime,
		})
		
		NetworkHandler:SendToClient(player, Events.PLAYER_REVIVED, {
			success = true,
			method = method,
			reviver = reviver and reviver.Name,
			healthRestored = humanoid and humanoid.Health or 0,
		})
		
		print(`[DownedService] 💚 {player.Name} REVIVED by {method}`)
		success = true
	end)
	
	releaseDownedLock(userId)
	
	return success
end

function DownedService:FinishPlayer(downedPlayer: Player, finisher: Player?): boolean
	local userId = downedPlayer.UserId
	
	if not acquireDownedLock(userId) then
		warn(`[DownedService] ⚠️ FinishPlayer blocked by lock for {downedPlayer.Name}`)
		return false
	end
	
	local success = false
	
	pcall(function()
		local data = downedPlayers[userId]
		
		if not data then
			warn(`[DownedService] {downedPlayer.Name} is not downed`)
			return
		end
		
		if not DOWNED_CONFIG.CanBeFinished then
			warn(`[DownedService] Finishing is disabled`)
			return
		end
		
		local downTime = os.clock() - data.countdownStartTime
		local snapshot = data.snapshot
		
		if data.countdownTask then
			task.cancel(data.countdownTask)
			data.countdownTask = nil
		end
		
		downedPlayers[userId] = nil
		setDownedVisuals(downedPlayer, false)
		
		analytics.totalFinishes += 1
		analytics.totalDownTime += downTime
		
		local PSS = getPlayerStateService()
		PSS:SetState(downedPlayer, "Died", `Finished by {finisher and finisher.Name or "Unknown"}`)
		
		EventBus:Emit(Events.PLAYER_FINISHED, downedPlayer, {
			finisher = finisher,
			snapshot = snapshot,
			downTime = downTime,
		})
		
		NetworkHandler:SendToClient(downedPlayer, Events.PLAYER_FINISHED, {
			finisher = finisher and finisher.Name,
		})
		
		if finisher then
			NetworkHandler:SendToClient(finisher, Events.PLAYER_FINISHED, {
				target = downedPlayer.Name,
				confirmed = true,
			})
		end
		
		print(`[DownedService] 💀 {downedPlayer.Name} FINISHED by {finisher and finisher.Name or "Unknown"}`)
		success = true
	end)
	
	releaseDownedLock(userId)
	
	return success
end

-- ═══════════════════════════════════════════════════════════════
-- QUERY METHODS (unchanged)
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
	
	return true
end

function DownedService:GetAnalytics(): {[string]: any}
	local activeCount = 0
	for _ in pairs(downedPlayers) do
		activeCount += 1
	end
	
	local totalEvents = analytics.totalRevives + analytics.totalFinishes + analytics.totalTimeouts
	local avgDownTime = totalEvents > 0 and (analytics.totalDownTime / totalEvents) or 0
	
	return {
		totalDowns = analytics.totalDowns,
		totalRevives = analytics.totalRevives,
		totalFinishes = analytics.totalFinishes,
		totalTimeouts = analytics.totalTimeouts,
		blockedByLock = analytics.blockedByLock,
		revivesByMethod = analytics.revivesByMethod,
		averageDownTime = avgDownTime,
		activeDownedPlayers = activeCount,
		uptime = os.clock() - analytics.startTime,
	}
end

return DownedService
