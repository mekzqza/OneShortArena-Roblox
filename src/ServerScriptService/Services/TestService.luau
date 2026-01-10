--!strict

-- ไฟล์นี้ใช้สำหรับทดสอบ server-side services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Events = require(ReplicatedStorage.Shared.Events)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

export type TestService = {
    Init: (self: TestService) -> (),
    Start: (self: TestService) -> (),
    [string]: any,
}

local TestService = {} :: TestService

local guard = IdempotentGuard.new("TestService", true)

function TestService:Init()
	if not guard:MarkInitialized() then
		return
	end
	
	print("[TestService] 🔧 Initializing...")
	print("[TestService] ✅ Initialized")
end

function TestService:Start()
	if not guard:MarkStarted() then
		return
	end
	
	print("[TestService] 🚀 Starting...")
	
	-- Get NetworkHandler
	local NetworkHandler = ServiceLocator:Get("NetworkHandler")
	
	if NetworkHandler then
		-- ✅ FIX: Return (success: boolean, response: any?)
		NetworkHandler:RegisterRequestHandler(Events.TEST_PING, function(player: Player, data: any)
			print(`[TestService-server] ✅ Received TEST_PING from {player.Name} with data:`, data)
			
			-- ✅ Return tuple: (true, data)
			return true, {
				message = "PONG from server!",
				receivedData = data,
			}
		end)
		
		print("[TestService] 📡 Registered TEST_PING handler")
	else
		warn("[TestService] ⚠️ NetworkHandler not available!")
	end
	
	print("[TestService] ✅ Started")
end

return TestService

