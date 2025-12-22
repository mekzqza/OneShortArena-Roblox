--!strict

--[[
	DemoController - Client-side Network Demo
	
	วิธีทดสอบ:
	กด F9 เปิด Console แล้วดูข้อมูลที่ส่ง/รับ
	หรือใช้คำสั่ง: _G.DemoController:SendPing()
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local NetworkController = require(script.Parent.NetworkController)

export type DemoController = {
	Init: (self: DemoController) -> (),
	Start: (self: DemoController) -> (),
	[string]: any,
}

local DemoController: DemoController = {}

local player = Players.LocalPlayer

local function showChatMessage(text: string, color: Color3)
	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = text,
			Color = color,
		})
	end)
end

function DemoController:Init()
	print("[DemoController] 🎮 Demo controller initialized")
end

function DemoController:Start()
	-- Example 1: Listen for PONG response
	EventBus:On(Events.DEMO_PONG, function(data: any)
		print("[DemoController] 🏓 Received PONG from server:")
		print(`  • Server Time: {data.serverTime}`)
		print(`  • Latency: {math.floor(data.latency * 1000)}ms`)
		print(`  • Message: {data.message}`)
		
		showChatMessage(
			`[PONG] {data.message} (Latency: {math.floor(data.latency * 1000)}ms)`,
			Color3.fromRGB(0, 255, 0)
		)
	end)
	
	-- Example 2: Listen for data response
	EventBus:On(Events.DEMO_SEND_DATA, function(data: any)
		print("[DemoController] 📊 Received data from server:")
		for key, value in pairs(data) do
			print(`  • {key}: {value}`)
		end
		
		if data.error then
			warn(`[DemoController] ❌ Error: {data.error}`)
		end
	end)
	
	-- Example 3: Listen for broadcasts (from any player)
	EventBus:On(Events.DEMO_BROADCAST_MESSAGE, function(data: any)
		print(`[DemoController] 📢 Broadcast: [{data.playerName}] {data.message}`)
		
		showChatMessage(
			`[{data.playerName}] {data.message}`,
			data.userId == player.UserId 
				and Color3.fromRGB(100, 200, 255) 
				or Color3.fromRGB(200, 200, 200)
		)
	end)
	
	-- Example 4: Listen for counter updates
	EventBus:On(Events.DEMO_UPDATE_COUNTER, function(data: any)
		print(`[DemoController] 🔢 Counter updated: {data.totalClicks} (Last: {data.lastClicker})`)
		
		showChatMessage(
			`🔢 Total: {data.totalClicks} | {data.lastClicker} clicked!`,
			Color3.fromRGB(255, 200, 0)
		)
	end)
	
	print("[DemoController] 🚀 Demo controller started")
	print("[DemoController] 📋 Available methods:")
	print("  • :SendPing() - Test ping-pong")
	print("  • :RequestData(type) - Request server data")
	print("  • :SendChatMessage(msg) - Send chat message")
	print("  • :ClickButton(name) - Simulate button click")
	
	-- Auto-send ping every 5 seconds for testing
	task.spawn(function()
		while true do
			task.wait(5)
			self:SendPing()
		end
	end)
end

-- Public methods (callable from console)

function DemoController:SendPing()
	print("[DemoController] 📤 Sending PING to server...")
	NetworkController:Send(Events.DEMO_PING, tick())
end

function DemoController:RequestData(dataType: string)
	dataType = dataType or "stats"
	print(`[DemoController] 📤 Requesting data: {dataType}`)
	NetworkController:Send(Events.DEMO_REQUEST_DATA, dataType)
end

function DemoController:SendChatMessage(message: string)
	message = message or "Hello from client!"
	print(`[DemoController] 📤 Sending chat message: {message}`)
	NetworkController:Send(Events.DEMO_CHAT_MESSAGE, message)
end

function DemoController:ClickButton(buttonName: string)
	buttonName = buttonName or "DemoButton"
	print(`[DemoController] 📤 Button clicked: {buttonName}`)
	NetworkController:Send(Events.DEMO_BUTTON_CLICKED, buttonName)
end

-- Example: Send multiple test requests
function DemoController:RunTests()
	print("[DemoController] 🧪 Running all tests...")
	
	task.wait(1)
	self:SendPing()
	
	task.wait(1)
	self:RequestData("stats")
	
	task.wait(1)
	self:RequestData("server")
	
	task.wait(1)
	self:SendChatMessage("Test message from client!")
	
	task.wait(1)
	self:ClickButton("TestButton1")
	
	task.wait(1)
	self:ClickButton("TestButton2")
	
	print("[DemoController] ✅ All tests completed")
end

return DemoController
