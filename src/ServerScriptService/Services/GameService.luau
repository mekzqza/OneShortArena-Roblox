--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(script.Parent.Parent.Core.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

local GameService = {}

export type PlayerState = "LOBBY" | "ARENA_ALIVE" | "ARENA_DEAD"

type PlayerData = {
    State: PlayerState,
    Character: Model?,
}

local playerStates: { [Player]: PlayerData } = {}

function GameService:Init()
    Players.PlayerAdded:Connect(function(player)
        self:_onPlayerAdded(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:_onPlayerRemoving(player)
    end)

    EventBus:Subscribe(Events.PLAYER_REQUEST_PLAY, function(player: Player)
        self:_handlePlayRequest(player)
    end)

    EventBus:Subscribe(Events.PLAYER_DIED, function(player: Player)
        self:_handlePlayerDeath(player)
    end)
end

function GameService:_onPlayerAdded(player: Player)
    playerStates[player] = {
        State = "LOBBY",
        Character = nil,
    }

    player.CharacterAdded:Connect(function(character)
        playerStates[player].Character = character
        
        if playerStates[player].State == "LOBBY" then
            EventBus:Publish(Events.PLAYER_ENTER_ARENA, player, false)
        end
    end)
end

function GameService:_onPlayerRemoving(player: Player)
    playerStates[player] = nil
end

function GameService:_handlePlayRequest(player: Player)
    local data = playerStates[player]
    if not data then return end

    if data.State ~= "LOBBY" then
        warn(`Player {player.Name} tried to play from state {data.State}`)
        return
    end

    data.State = "ARENA_ALIVE"
    EventBus:Publish(Events.PLAYER_ENTER_ARENA, player, true)
end

function GameService:_handlePlayerDeath(player: Player)
    local data = playerStates[player]
    if not data then return end

    if data.State ~= "ARENA_ALIVE" then
        return
    end

    data.State = "LOBBY"
    EventBus:Publish(Events.PLAYER_ENTER_ARENA, player, false)
end

function GameService:GetPlayerState(player: Player): PlayerState?
    local data = playerStates[player]
    return if data then data.State else nil
end

return GameService