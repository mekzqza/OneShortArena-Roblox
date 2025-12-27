--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.NetworkHandler)

export type MatchService = {
    Init: (self: MatchService) -> (),
    Start: (self: MatchService) -> (),
}

local MatchService = {} :: MatchService



function MatchService:Init()

end

function MatchService:Start()

end
return MatchService
