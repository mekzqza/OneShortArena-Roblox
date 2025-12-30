--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ✅ Get shared modules
local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)

export type PlayerStateController = {
	Init: (self: PlayerStateController) -> (),
	Start: (self: PlayerStateController) -> (),
}

local PlayerStateController = {} :: PlayerStateController

local player = Players.LocalPlayer
local currentState = "Lobby" -- Default state

function PlayerStateController:Init()
	print("[PlayerStateController] 📍 Initialized")
end

function PlayerStateController:Start()
	-- Listen for state changes from server
	EventBus:On(Events.PLAYER_STATE_CHANGED, function(newState: string)
		local oldState = currentState
		currentState = newState
		
		print(`[PlayerStateController] ✅ State changed: {oldState} → {newState}`)
		
		-- Emit for other controllers to listen
		EventBus:Emit(Events.PLAYER_STATE_CHANGED_INTERNAL, {
			oldState = oldState,
			newState = newState,
		})
	end)
	
	print("[PlayerStateController] ✅ Started")
end

return PlayerStateController
