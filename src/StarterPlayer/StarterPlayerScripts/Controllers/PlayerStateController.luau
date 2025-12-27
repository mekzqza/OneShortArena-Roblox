--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkController = require(script.Parent.NetworkController)
local Types = require(ReplicatedStorage.Shared.Types)

export type PlayerStateController = Types.Controller & {
    RequestJoinArena: (self: PlayerStateController) -> (),
    RequestReturnToLobby: (self: PlayerStateController) -> (),
    RequestSpectate: (self: PlayerStateController) -> (),
    GetCurrentState: (self: PlayerStateController) -> string?,
}

local PlayerStateController = {} :: PlayerStateController

local currentState: string? = nil

function PlayerStateController:Init()
    print("[PlayerStateController] 🎮 Initialized")
end

function PlayerStateController:Start()
    -- Listen for state changes from server
    EventBus:On(Events.PLAYER_STATE_CHANGED, function(data: any)
        if data.success then
            currentState = data.state
            print(string.format("[PlayerStateController] ✅ State changed to: %s", data.state))
        else
            warn(string.format("[PlayerStateController] ❌ State change failed: %s", data.reason or "Unknown"))
        end
    end)
    
    print("[PlayerStateController] 🚀 Started")
end

function PlayerStateController:RequestJoinArena()
    print("[PlayerStateController] 📤 Requesting to join Arena...")
    NetworkController:Send(Events.PLAYER_REQUEST_TO_ARENA, {
        timestamp = tick()
    })
end

function PlayerStateController:RequestReturnToLobby()
    print("[PlayerStateController] 📤 Requesting to return to Lobby...")
    NetworkController:Send(Events.PLAYER_REQUEST_TO_LOBBY, {
        timestamp = tick()
    })
end

function PlayerStateController:RequestSpectate()
    print("[PlayerStateController] 📤 Requesting to spectate...")
    NetworkController:Send(Events.PLAYER_REQUEST_TO_SPECTATE, {
        timestamp = tick()
    })
end

function PlayerStateController:GetCurrentState(): string?
    return currentState
end

return PlayerStateController
