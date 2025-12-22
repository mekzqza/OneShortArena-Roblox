--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

local CombatService = {}

local trackedHumanoids: { [Humanoid]: Player } = {}

function CombatService:Init()
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            self:_trackCharacter(player, character)
        end)
    end)

    Players.PlayerRemoving:Connect(function(player)
        for humanoid, trackedPlayer in trackedHumanoids do
            if trackedPlayer == player then
                trackedHumanoids[humanoid] = nil
            end
        end
    end)
end

function CombatService:Start()
    print("[CombatService] Started")
end

function CombatService:_trackCharacter(player: Player, character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid

    for h, p in trackedHumanoids do
        if p == player then
            trackedHumanoids[h] = nil
        end
    end

    trackedHumanoids[humanoid] = player

    humanoid.Died:Connect(function()
        EventBus:Publish(Events.PLAYER_DIED, player)
    end)
end

return CombatService