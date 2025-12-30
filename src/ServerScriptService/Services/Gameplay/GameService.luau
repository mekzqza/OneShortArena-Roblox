--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local NetworkHandler = require(ServerScriptService.Services.Core.NetworkHandler)

export type GameService = {
	Init: (self: GameService) -> (),
	Start: (self: GameService) -> (),
	[string]: any,
}

local GameService = {} :: GameService

local gameState = {
	isRunning = false,
	currentRound = 0,
	playersInGame = {},
}

function GameService:Init()
	-- Initialize game state

	NetworkHandler:AllowClientEvent(Events.PLAYER_ATTACK)

	gameState.isRunning = false
	gameState.currentRound = 0
	gameState.playersInGame = {}
	
	print("[GameService] Initialized")
end

function GameService:Start()
	-- Listen for game events
	EventBus:On(Events.GAME_START_REQUESTED, function(player)
		self:HandleGameStartRequest(player)
	end)
	
	EventBus:On(Events.PLAYER_REQUEST_PLAY, function(player)
		self:HandlePlayerJoinRequest(player)
	end)
	
	-- Handle player connections
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerJoined(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerLeft(player)
	end)
	
	print("[GameService] Started")
end

function GameService:HandleGameStartRequest(player: Player)
	-- Validate: Is player authorized to start game?
	if gameState.isRunning then
		NetworkHandler:SendToClient(player, Events.GAME_START_FAILED, "Game already running")
		return
	end
	
	-- Validate: Minimum players
	if #gameState.playersInGame < 2 then
		NetworkHandler:SendToClient(player, Events.GAME_START_FAILED, "Need at least 2 players")
		return
	end
	
	-- Start game
	self:StartGame()
end

function GameService:StartGame()
	gameState.isRunning = true
	gameState.currentRound += 1
	
	print(`[GameService] Starting game - Round {gameState.currentRound}`)
	
	-- Broadcast to all players
	NetworkHandler:Broadcast(Events.GAME_STARTED, {
		round = gameState.currentRound,
		players = gameState.playersInGame,
	})
	
	-- Emit internal event for other services
	EventBus:Emit(Events.GAME_STARTED, gameState.currentRound)
end

function GameService:HandlePlayerJoinRequest(player: Player)
	-- Validate: Player not already in game
	if table.find(gameState.playersInGame, player.UserId) then
		NetworkHandler:SendToClient(player, Events.JOIN_FAILED, "Already in game")
		return
	end
	
	-- Validate: Game not full
	local MAX_PLAYERS = 10
	if #gameState.playersInGame >= MAX_PLAYERS then
		NetworkHandler:SendToClient(player, Events.JOIN_FAILED, "Game is full")
		return
	end
	
	-- Add player to game
	table.insert(gameState.playersInGame, player.UserId)
	
	NetworkHandler:SendToClient(player, Events.JOIN_SUCCESS, {
		playersInGame = #gameState.playersInGame,
	})
	
	print(`[GameService] Player {player.Name} joined game`)
end

function GameService:OnPlayerJoined(player: Player)
	print(`[GameService] Player {player.Name} connected to server`)
	
	-- Send initial game state to player
	NetworkHandler:SendToClient(player, Events.GAME_STATE_UPDATE, {
		isRunning = gameState.isRunning,
		currentRound = gameState.currentRound,
		playersInGame = #gameState.playersInGame,
	})
end

function GameService:OnPlayerLeft(player: Player)
	-- Remove from active game
	local index = table.find(gameState.playersInGame, player.UserId)
	if index then
		table.remove(gameState.playersInGame, index)
		print(`[GameService] Player {player.Name} left game`)
		
		-- Check if game should end
		if gameState.isRunning and #gameState.playersInGame < 2 then
			self:EndGame("Not enough players")
		end
	end
end

function GameService:EndGame(reason: string)
	gameState.isRunning = false
	
	print(`[GameService] Game ended - Reason: {reason}`)
	
	NetworkHandler:Broadcast(Events.GAME_ENDED, {
		reason = reason,
		round = gameState.currentRound,
	})
	
	-- Clear player list
	gameState.playersInGame = {}
end

function GameService:GetGameState()
	return gameState
end

return GameService