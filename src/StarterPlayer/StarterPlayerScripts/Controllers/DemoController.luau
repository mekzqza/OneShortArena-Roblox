--!strict

--[[
	--🧪 DemoController - Network Testing Demo
	
	--⚠️ FOR TESTING ONLY - NOT PRODUCTION
	
	--Purpose:
	-- Demonstrate Client → Server communication
	-- Demonstrate Server → Client communication
	-- Test NetworkController functionality
	
	--Can be deleted when Production is ready.
	
	--Examples:
	-- SendHello() - Simple message to server
	-- SendChatMessage() - Chat with broadcast
	-- RequestPlayerStats() - Request/Response pattern
	-- SendTestButton() - Button click event
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkController = require(script.Parent.NetworkController)

export type DemoController = {
	Init: (self: DemoController) -> (),
	Start: (self: DemoController) -> (),
	-- Client → Server methods
	SendHello: (self: DemoController) -> (),
	SendChatMessage: (self: DemoController, message: string) -> (),
	RequestPlayerStats: (self: DemoController) -> (),
	RequestServerInfo: (self: DemoController) -> (),
	SendTestButton: (self: DemoController, buttonNumber: number) -> (),
	SendTestEventToServer: (self: DemoController) -> (),
	-- Legacy methods (for compatibility)
	SendAttack: (self: DemoController) -> (),
	SendDefend: (self: DemoController) -> (),
	SendSpecial: (self: DemoController) -> (),
	SendPing: (self: DemoController) -> (),
	[string]: any,
}

local DemoController = {} :: DemoController

local player = Players.LocalPlayer

function DemoController:Init()
	print("[DemoController] 🧪 Initializing Demo Layer...")
	print("⚠️  This is for TESTING only - not Production")
	warn("[DemoController] ✅ Init() CALLED") -- เพิ่ม debug
end

function DemoController:Start()
	warn("[DemoController] ✅ Start() CALLED") -- เพิ่ม debug
	
	-- Listen for responses from Server
	self:SetupServerListeners()
	
	-- Legacy: รับ INPUT_ACTION จาก InputController
	print("[DemoController] 📡 Setting up INPUT_ACTION listener...")
	EventBus:On(Events.INPUT_ACTION, function(actionName: string)
		print("[DemoController] 🎯 Received INPUT_ACTION:", actionName)
		self:OnInputAction(actionName)
	end)
	
	print("[DemoController] 🚀 Started - Demo ready")
	print("📋 Available commands:")
	print("  _G.DemoController:SendHello()")
	print("  _G.DemoController:SendChatMessage('text')")
	print("  _G.DemoController:RequestPlayerStats()")
	print("  _G.DemoController:RequestServerInfo()")
end

--[[
	Setup listeners for Server → Client events
]]
function DemoController:SetupServerListeners()
	-- Response to Hello
	
	
	-- Broadcast messages (Chat)
	EventBus:On(Events.DEMO_BROADCAST_MESSAGE, function(data: any)
		print(`[CHAT] {data.playerName}: {data.message}`)
	end)
	
	-- Data responses
	EventBus:On(Events.DEMO_SEND_DATA, function(data: any)
		if data.error then
			warn(`[DemoController] ❌ Error: {data.error}`)
			return
		end
		
		print("[DemoController] 📊 Received data:")
		for key, value in pairs(data) do
			print(`  {key}: {value}`)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- CLIENT → SERVER EXAMPLES
-- ═══════════════════════════════════════════════════════════



--[[
	Example 2: Send chat message (will be broadcasted to all)
	
	Usage: _G.DemoController:SendChatMessage("Hello everyone!")
]]
function DemoController:SendChatMessage(message: string)
	if #message == 0 then
		warn("[DemoController] ❌ Message cannot be empty")
		return
	end
	
	if #message > 100 then
		warn("[DemoController] ❌ Message too long (max 100 chars)")
		return
	end
	
	print(`[DemoController] 💬 Sending chat: {message}`)
	
	NetworkController:SendToServer(Events.DEMO_CHAT_MESSAGE, {
		message = message,
		timestamp = tick(),
	})
end

--[[
	Example 3: Request player stats from Server
	
	Usage: _G.DemoController:RequestPlayerStats()
]]
function DemoController:RequestPlayerStats()
	print("[DemoController] 📊 Requesting player stats...")
	
	NetworkController:SendToServer(Events.DEMO_REQUEST_DATA, {
		dataType = "stats",
	})
end

--[[
	Example 4: Request server info
	
	Usage: _G.DemoController:RequestServerInfo()
]]
function DemoController:RequestServerInfo()
	print("[DemoController] 🖥️ Requesting server info...")
	
	NetworkController:SendToServer(Events.DEMO_REQUEST_DATA, {
		dataType = "server",
	})
end

--[[
	Example 5: Send button click event
	
	Usage: _G.DemoController:SendTestButton(1)
]]


--[[
	Legacy: Manual test event
]]
function DemoController:SendTestEventToServer()
	print("[DemoController] 📨 Sending manual test event...")
	
	NetworkController:SendToServer(Events.TEST_CLIENT_BUTTON_CLICK, {
		counter = 1,
		timestamp = tick(),
	})
end

-- ═══════════════════════════════════════════════════════════
-- LEGACY METHODS (for backward compatibility)
-- ═══════════════════════════════════════════════════════════

function DemoController:OnInputAction(actionName: string)
	print(`[DemoController] 🎮 Input: {actionName}`)
	
	local action = string.upper(actionName)
	
	if action == "ATTACK" then
		self:SendAttack()
	elseif action == "DEFEND" then
		self:SendDefend()
	elseif action == "SPECIAL" then
		self:SendSpecial()
	elseif action == "PING" then
		self:SendPing()
	elseif action == "TESTBUTTON1" then
		self:SendTestButton(1)
	elseif action == "TESTBUTTON2" then
		self:SendTestButton(2)
	elseif action == "TESTBUTTON3" then
		self:SendTestButton(3)
	elseif action == "TESTCLICK" then
		self:SendTestEventToServer()
	else
		print(`[DemoController] ℹ️ Action '{actionName}' handled locally`)
	end
end

function DemoController:SendAttack()
	print("[DemoController] ⚔️ Sending Attack...")
	
	NetworkController:Send(Events.PLAYER_ATTACK, {
		timestamp = tick(),
		position = player.Character and player.Character.PrimaryPart.Position or Vector3.zero,
	})
end

function DemoController:SendDefend()
	print("[DemoController] 🛡️ Sending Defend...")
	
	NetworkController:SendToServer(Events.PLAYER_DEFEND, {
		timestamp = tick(),
		isBlocking = true,
	})
end

function DemoController:SendSpecial()
	print("[DemoController] ✨ Sending Special...")
	
	NetworkController:SendToServer(Events.PLAYER_SPECIAL, {
		timestamp = tick(),
		skillType = "Ultimate",
	})
end

function DemoController:SendPing()
	print("[DemoController] 📡 Sending Ping...")
	
	NetworkController:SendToServer(Events.DEMO_PING, tick())
end

return DemoController