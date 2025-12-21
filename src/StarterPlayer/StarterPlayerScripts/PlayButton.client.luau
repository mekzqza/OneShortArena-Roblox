--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Events = require(ReplicatedStorage.Shared.Events)
local NetworkHandler = require(ReplicatedStorage.Client.NetworkHandler)

-- Press 'P' to request play
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.P then
		NetworkHandler:SendToServer(Events.PLAYER_REQUEST_PLAY)
		print("Requested to play!")
	end
end)
