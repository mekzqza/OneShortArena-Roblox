--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(script.Parent.Parent.Core.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

local CombatService = {}

local trackedHumanoids: { [Humanoid]: Player } = {}

function CombatService:Init()
	-- Track all player humanoids
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			self:_trackCharacter(player, character)
		end)
	end)

	-- Clean up on player leave
	Players.PlayerRemoving:Connect(function(player)
		for humanoid, trackedPlayer in trackedHumanoids do
			if trackedPlayer == player then
				trackedHumanoids[humanoid] = nil
			end
		end
	end)
end

function CombatService:_trackCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- Clean up old tracking
	for h, p in trackedHumanoids do
		if p == player then
			trackedHumanoids[h] = nil
		end
	end

	trackedHumanoids[humanoid] = player

	-- Listen for death
	humanoid.Died:Connect(function()
		self:_handleDeath(player, humanoid)
	end)

	-- Listen for damage (one-shot implementation)
	humanoid.HealthChanged:Connect(function(health)
		if health < humanoid.MaxHealth and health > 0 then
			-- Get GameService state
			local GameService = require(script.Parent.GameService)
			local state = GameService:GetPlayerState(player)
			
			-- Only one-shot in arena
			if state == "ARENA_ALIVE" then
				humanoid.Health = 0 -- One shot = instant death
			end
		end
	end)
end

function CombatService:_handleDeath(player: Player, humanoid: Humanoid)
	-- Import GameService to check state
	local GameService = require(script.Parent.GameService)
	local state = GameService:GetPlayerState(player)

	-- Only process arena deaths
	if state ~= "ARENA_ALIVE" then
		return
	end

	-- Publish death event
	EventBus:Publish(Events.PLAYER_DIED, player)
end

return CombatService
