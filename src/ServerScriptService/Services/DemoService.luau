--!strict

--[[
	DemoService - Network Communication Demo
	
	สาธิตวิธีการใช้งาน NetworkHandler:
	1. รับคำขอจาก Client (Client → Server)
	2. ส่งข้อมูลกลับไปที่ Client (Server → Client)
	3. Broadcast ข้อมูลไปยัง Client ทั้งหมด (Server → All Clients)
--]]

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

-- Server-side data
local serverCounter = 0
local playerData: {[number]: {clicks: number, lastPing: number}} = {}

function DemoService:Init()
	-- Allow demo events in NetworkHandler
	NetworkHandler:AllowClientEvent(Events.DEMO_PING)
	NetworkHandler:AllowClientEvent(Events.DEMO_REQUEST_DATA)
	NetworkHandler:AllowClientEvent(Events.DEMO_CHAT_MESSAGE)
	NetworkHandler:AllowClientEvent(Events.DEMO_BUTTON_CLICKED)
	
	NetworkHandler:AllowServerEvent(Events.DEMO_PONG)
	NetworkHandler:AllowServerEvent(Events.DEMO_SEND_DATA)
	NetworkHandler:AllowServerEvent(Events.DEMO_BROADCAST_MESSAGE)
	NetworkHandler:AllowServerEvent(Events.DEMO_UPDATE_COUNTER)
	
	-- Register custom validators (optional)
	NetworkHandler:RegisterValidator(Events.DEMO_CHAT_MESSAGE, function(player, args)
		local message = args[1]
		if typeof(message) ~= "string" then
			return false, "Message must be a string"
		end
		if #message > 100 then
			return false, "Message too long"
		end
		if #message == 0 then
			return false, "Message cannot be empty"
		end
		return true
	end)
	
	print("[DemoService] 🎮 Demo service initialized")
end

function DemoService:Start()
	-- Example 1: Simple Ping-Pong
	-- Client sends DEMO_PING → Server responds with DEMO_PONG
	EventBus:On(Events.DEMO_PING, function(player: Player, timestamp: number)
		print(`[DemoService] 📨 Received PING from {player.Name} at {timestamp}`)
		
		-- Track player data
		if not playerData[player.UserId] then
			playerData[player.UserId] = {clicks = 0, lastPing = 0}
		end
		playerData[player.UserId].lastPing = os.clock()
		
		-- Send PONG back to the specific player
		local serverTime = os.clock()
		local latency = serverTime - timestamp
		
		NetworkHandler:SendToClient(player, Events.DEMO_PONG, {
			serverTime = serverTime,
			latency = latency,
			message = "Pong! 🏓"
		})
		
		print(`[DemoService] ✅ Sent PONG to {player.Name} (latency: {math.floor(latency * 1000)}ms)`)
	end)
	
	-- Example 2: Data Request
	-- Client requests data → Server sends personalized data
	EventBus:On(Events.DEMO_REQUEST_DATA, function(player: Player, dataType: string)
		print(`[DemoService] 📊 {player.Name} requested data: {dataType}`)
		
		local data = {}
		
		if dataType == "stats" then
			data = {
				playerName = player.Name,
				userId = player.UserId,
				clicks = playerData[player.UserId]?.clicks or 0,
				serverCounter = serverCounter,
				accountAge = player.AccountAge,
			}
		elseif dataType == "server" then
			data = {
				totalPlayers = #Players:GetPlayers(),
				serverCounter = serverCounter,
				uptime = os.clock(),
			}
		else
			data = {error = "Unknown data type"}
		end
		
		NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, data)
		print(`[DemoService] 📤 Sent {dataType} data to {player.Name}`)
	end)
	
	-- Example 3: Chat Message (Broadcast to all)
	-- Client sends message → Server broadcasts to everyone
	EventBus:On(Events.DEMO_CHAT_MESSAGE, function(player: Player, message: string)
		print(`[DemoService] 💬 {player.Name}: {message}`)
		
		-- Broadcast to ALL clients (including sender)
		NetworkHandler:Broadcast(Events.DEMO_BROADCAST_MESSAGE, {
			playerName = player.Name,
			userId = player.UserId,
			message = message,
			timestamp = os.clock(),
		})
		
		print("[DemoService] 📢 Broadcasted message to all clients")
	end)
	
	-- Example 4: Button Click Counter
	-- Client clicks button → Server updates counter → Broadcast to all
	EventBus:On(Events.DEMO_BUTTON_CLICKED, function(player: Player, buttonName: string)
		print(`[DemoService] 🖱️ {player.Name} clicked: {buttonName}`)
		
		-- Update server counter
		serverCounter += 1
		
		-- Update player data
		if not playerData[player.UserId] then
			playerData[player.UserId] = {clicks = 0, lastPing = 0}
		end
		playerData[player.UserId].clicks += 1
		
		-- Broadcast updated counter to all clients
		NetworkHandler:Broadcast(Events.DEMO_UPDATE_COUNTER, {
			totalClicks = serverCounter,
			lastClicker = player.Name,
			playerClicks = playerData[player.UserId].clicks,
		})
		
		print(`[DemoService] 📊 Counter updated: {serverCounter}`)
	end)
	
	-- Example 5: Auto-broadcast every 10 seconds
	task.spawn(function()
		while true do
			task.wait(10)
			
			NetworkHandler:Broadcast(Events.DEMO_BROADCAST_MESSAGE, {
				playerName = "Server",
				userId = 0,
				message = `Server heartbeat - Total clicks: {serverCounter}`,
				timestamp = os.clock(),
			})
			
			print("[DemoService] 💓 Sent heartbeat broadcast")
		end
	end)
	
	-- Cleanup on player leave
	Players.PlayerRemoving:Connect(function(player)
		playerData[player.UserId] = nil
		print(`[DemoService] 🚪 {player.Name} left - cleaned up data`)
	end)
	
	print("[DemoService] 🚀 Demo service started")
	print("[DemoService] 📋 Available commands:")
	print("  • DEMO_PING - Test ping-pong")
	print("  • DEMO_REQUEST_DATA - Request server data")
	print("  • DEMO_CHAT_MESSAGE - Send chat message")
	print("  • DEMO_BUTTON_CLICKED - Increment counter")
end

-- Public methods for testing via server console
function DemoService:GetPlayerData(player: Player)
	return playerData[player.UserId]
end

function DemoService:GetServerCounter(): number
	return serverCounter
end

function DemoService:ResetCounter()
	serverCounter = 0
	NetworkHandler:Broadcast(Events.DEMO_UPDATE_COUNTER, {
		totalClicks = 0,
		lastClicker = "Server",
		playerClicks = 0,
	})
	print("[DemoService] 🔄 Counter reset")
end

return DemoService
