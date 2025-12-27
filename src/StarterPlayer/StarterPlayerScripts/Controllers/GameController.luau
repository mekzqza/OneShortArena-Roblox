local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SrverScriptService = game:GetService("ServerScriptService")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)



export type GameController = {
	Init: (self: GameController) -> (),
	Start: (self: GameController) -> (),
	[string]: any,
}
local GameController = {} :: GameController


function GameController:Init()
	print("[GameController-Client] Initialized")
end

function GameController:Start()


end

return GameController