--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Events = require(ReplicatedStorage.Shared.Events)
local EventsBus = require(ReplicatedStorage.SystemsShared.EventsBus)
local NetworkHandler = require(ServerScriptService.Services.NetworkHandler)

export type ArenaService = {
    Init: (self: ArenaService) -> (),
    Start: (self: ArenaService) -> (),
}

local ArenaService = {}

function ArenaService:Init()
    
end

function ArenaService:Start()
    
end




return ArenaService
