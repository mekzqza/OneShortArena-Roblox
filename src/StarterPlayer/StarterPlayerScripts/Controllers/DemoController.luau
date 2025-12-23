--client side script for demoing network communication
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkController = require(script.Parent.NetworkController)

export type DemoController ={
	Init: (self: DemoController) ->(),
	Start: (self: DemoController) ->(),
	[string]: any,
}

local DemoController: DemoController = {}

function DemoController:Init()
	print("[DemoController] Initialized")
	self:Start()
	
end
function DemoController:Start()
	print("[DemoController] Started")
	self:SendDemoPing()

	EventBus:On(Events.DEMO_PONG, function(playload: any)
		if playload then
			print("[DemoController] Received from server massage:",playload)
		else
			print("No payload received from server.")	
		end
		
	end)

end

function DemoController:SendDemoPing()
	task.spawn(function()
		local count = 1
		while true do
			task.wait(5)
			NetworkController:Send(Events.DEMO_PING,("Ping from client! Count: %d"):format(count))
			count = count + 1
		end
	end)
	
end

return DemoController