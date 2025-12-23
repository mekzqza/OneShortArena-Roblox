--Server side service for demo purposes
--Handles demo-related network events
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local NetworkHandler = require(ServerScriptService.Services.NetworkHandler)

export type DemoService = {
	Init: (self: DemoService) -> (),
	Start: (self: DemoService) -> (),
	[string]: any,
}

local DemoService: DemoService = {}

function DemoService:Init()

	NetworkHandler:AllowClientEvent(Events.DEMO_PING)
	NetworkHandler:AllowServerEvent(Events.DEMO_PONG)


	print("[DemoService] Initialized")
end

function DemoService:Start()
	EventBus:On(Events.DEMO_PING,function(player: Player,playload: any)
		if playload then
			print("[DemosService] Received from client:", player.Name,"massage:",playload)
		else
			print("No payload received from client.")
		end

		--ตอบกลับไปหาคลายเอนต์
		NetworkHandler:SendToClient(
			player,
			Events.DEMO_PONG,
			"Pong from server!"--ส่งกลับไปหาคลายเอนต์ -->DemoController
		)
	end)

	print("[DemoService] Started")

end

return DemoService