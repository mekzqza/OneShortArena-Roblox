--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkController = require(script.Parent.NetworkController)

export type LobbyController = {
    RequestReturnToLobby: (self: LobbyController) -> (),
}

local LobbyController = {} :: LobbyController

function LobbyController:Init()
    print("[LobbyController] 🏠 Initialized")
end

function LobbyController:Start()
    -- Listen for teleport responses
    EventBus:On(Events.PLAYER_TELEPORTED_TO_LOBBY, function(data: any)
        if data.success then
            print("[LobbyController] ✅ Teleported to Lobby")
        else
            warn(string.format("[LobbyController] ❌ Failed to teleport: %s", data.reason or "Unknown"))
        end
    end)
    
    print("[LobbyController] 🚀 Started")
end

function LobbyController:RequestReturnToLobby()
    print("[LobbyController] 📤 Requesting return to Lobby...")
    NetworkController:Send(Events.PLAYER_REQUEST_TO_LOBBY, {
        timestamp = tick()
    })
end

return LobbyController
