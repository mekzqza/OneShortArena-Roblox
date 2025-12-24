--!strict

--[[
	🧪 DemoService - Network Testing Demo (Server)
	
	⚠️ FOR TESTING ONLY - NOT PRODUCTION
	
	-Purpose:
	-Demonstrate Server → Client communication
	- Respond to Client requests
	- Broadcast to all clients
	
	-Can be deleted when Production is ready.
	
	-Examples:
	- Handle DEMO_HELLO - Simple response
	- Handle DEMO_CHAT_MESSAGE - Broadcast chat
	- Handle DEMO_REQUEST_DATA - Send data to client
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.NetworkHandler)
local CooldownService = require(ServerScriptService.Services.CooldownService)

export type DemoService = {
	Init: (self: DemoService) -> (),
	Start: (self: DemoService) -> (),
	[string]: any,
}

local DemoService  = {} :: DemoService

function DemoService:Init()
	print("[DemoService] 🧪 Initializing Demo Layer...")
	
	-- Allow Client → Server events
	
	NetworkHandler:AllowClientEvent(Events.DEMO_CHAT_MESSAGE)
	NetworkHandler:AllowClientEvent(Events.DEMO_REQUEST_DATA)
	NetworkHandler:AllowClientEvent(Events.TEST_CLIENT_BUTTON_CLICK)
	
	
	-- Legacy events
	NetworkHandler:AllowClientEvent(Events.PLAYER_ATTACK)
	NetworkHandler:AllowClientEvent(Events.PLAYER_DEFEND)
	NetworkHandler:AllowClientEvent(Events.PLAYER_SPECIAL)
	NetworkHandler:AllowClientEvent(Events.DEMO_PING)
	
	-- Allow Server → Client events

	NetworkHandler:AllowServerEvent(Events.DEMO_SEND_DATA)
	NetworkHandler:AllowServerEvent(Events.DEMO_BROADCAST_MESSAGE)
	NetworkHandler:AllowServerEvent(Events.TEST_SERVER_RESPONSE)
	
	-- Register validators
	self:RegisterValidators()
	
	print("⚠️  This is for TESTING only - not Production")
end

function DemoService:RegisterValidators()
	-- Chat message validator
	NetworkHandler:RegisterValidator(Events.DEMO_CHAT_MESSAGE, function(player, args)
		local message = args[1].message
		
		if typeof(message) ~= "string" then
			return false, "Message must be string"
		end
		if #message > 100 then
			return false, "Message too long (max 100)"
		end
		if #message == 0 then
			return false, "Message cannot be empty"
		end
		
		return true, ""
	end)
end

function DemoService:Start()
	print("[DemoService] 🚀 Started - Demo ready")
	
	-- ═══════════════════════════════════════════════════════════
	-- SERVER → CLIENT EXAMPLES
	-- ═══════════════════════════════════════════════════════════
	
	--[[
		--Example 1: Simple Request/Response
		--Client sends DEMO_HELLO → Server responds with DEMO_HELLO_RESPONSE
	
	EventBus:On(Events.DEMO_HELLO, function(player: Player, data: any)
		print(`[DemoService] 📨 Hello from {player.Name}: {data.message}`)
		
		-- Send response back to client
		NetworkHandler:SendToClient(player, Events.DEMO_HELLO_RESPONSE, {
			serverMessage = "สวัสดี " .. player.Name .. "!",
			receivedAt = os.clock(),
			yourMessage = data.message,
		})
		
		-- Broadcast announcement
		NetworkHandler:Broadcast(Events.DEMO_ANNOUNCEMENT, {
			message = `{player.Name} ส่งทักทายมา!`,
			from = player.Name,
			timestamp = os.clock(),
		})
	end)
	--]]

	--[[ 
		--Example 2: Chat with Broadcast
		--Client sends chat → Server broadcasts to all
	--]]
	EventBus:On(Events.DEMO_CHAT_MESSAGE, function(player: Player, data: any)
		print(`[DemoService] 💬 Chat from {player.Name}: {data.message}`)
		
		-- Filter bad words (example)
		local filtered = data.message:gsub("badword", "***")
		
		-- Broadcast to everyone
		NetworkHandler:Broadcast(Events.DEMO_BROADCAST_MESSAGE, {
			playerName = player.Name,
			userId = player.UserId,
			message = filtered,
			timestamp = os.clock(),
		})
	end)
	
	--[ [
		--Example 3: Data Request/Response
		--Client requests data → Server sends specific data back
	--]]
	EventBus:On(Events.DEMO_REQUEST_DATA, function(player: Player, data: any)
		local dataType = data.dataType
		print(`[DemoService] 📊 {player.Name} requested: {dataType}`)
		
		local response = {}
		
		if dataType == "stats" then
			-- Player stats
			response = {
				playerName = player.Name,
				userId = player.UserId,
				accountAge = player.AccountAge,
				health = player.Character and player.Character:FindFirstChild("Humanoid") and (player.Character:FindFirstChild("Humanoid") :: Humanoid).Health or 0,
				maxHealth = player.Character and player.Character:FindFirstChild("Humanoid") and (player.Character:FindFirstChild("Humanoid") :: Humanoid).MaxHealth or 100,
				
				--[[health = player.Character and player.Character.Humanoid.Health or 0,
				maxHealth = player.Character and player.Character.Humanoid.MaxHealth or 100,]]
			}
			
		elseif dataType == "server" then
			-- Server info
			response = {
				totalPlayers = #Players:GetPlayers(),
				uptime = os.clock(),
				maxPlayers = Players.MaxPlayers,
			}
			
		else
			response = {
				error = "Unknown data type: " .. tostring(dataType)
			}
		end
		
		-- Send back to client
		NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, response)
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- LEGACY HANDLERS
	-- ═══════════════════════════════════════════════════════════
	
	-- Attack with cooldown
	EventBus:On(Events.PLAYER_ATTACK, function(player: Player, data: any)
		print(`[DemoService] ⚔️ {player.Name} attacked`)
		
		-- Check cooldown
		if CooldownService:IsOnCooldown(player, "Attack") then
			local remaining = CooldownService:GetRemaining(player, "Attack")
			NetworkHandler:SendToClient(player, Events.ACTION_FAILED, {
				reason = "On cooldown",
				remaining = remaining,
			})
			warn(string.format("[DemoService] ⏱️ %s on cooldown (%.2fs left)", player.Name, remaining))
			return
		end
		
		-- Validate state
		if not player.Character or not player.Character:FindFirstChild("Humanoid") then
			return
		end
		
		if player.Character and player.Character:FindFirstChild("Humanoid") and (player.Character:FindFirstChild("Humanoid") :: Humanoid).MaxHealth <= 0 then
			return
		end
		
		-- Process
		local damage = 10
		
		-- Set cooldown
		CooldownService:SetCooldown(player, "Attack")
		
		-- Response
		NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, {
			action = "Attack",
			damage = damage,
			success = true,
		})
		
		-- Broadcast
		NetworkHandler:Broadcast(Events.DEMO_BROADCAST_MESSAGE, {
			playerName = player.Name,
			userId = player.UserId,
			message = `{player.Name} attacked! (Damage: {damage})`,
			timestamp = os.clock(),
		})
	end)
	
	-- Defend
	EventBus:On(Events.PLAYER_DEFEND, function(player: Player, data: any)
		print(`[DemoService] 🛡️ {player.Name} defending`)
		
		NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, {
			action = "Defend",
			isBlocking = data.isBlocking,
			success = true,
		})
	end)
	
	-- Special
	EventBus:On(Events.PLAYER_SPECIAL, function(player: Player, data: any)
		print(`[DemoService] ✨ {player.Name} used special`)
		
		NetworkHandler:Broadcast(Events.DEMO_BROADCAST_MESSAGE, {
			playerName = player.Name,
			userId = player.UserId,
			message = `{player.Name} used {data.skillType}! ✨`,
			timestamp = os.clock(),
		})
	end)
	-- Ping
	EventBus:On(Events.DEMO_PING, function(player: Player, clientTime: number)
		local serverTime = tick()
		local latency = serverTime - clientTime
		
		print(string.format("[DemoService] 📡 Ping from %s (latency: %.0fms)", player.Name, latency * 1000))
		
		NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, {
			action = "Pong",
			latency = latency,
			serverTime = serverTime,
		})
	end)
	
	--[[ Test button
	EventBus:On(Events.TEST_BUTTON_PRESSED, function(player: Player, data: any)
		print(`[DemoService] 🔘 {player.Name} pressed button {data.buttonId}`)
		
		NetworkHandler:SendToClient(player, Events.TEST_SERVER_RESPONSE, {
			buttonId = data.buttonId,
			receivedAt = os.clock(),
		})
	end)
	]]
	
	-- Test click
	EventBus:On(Events.TEST_CLIENT_BUTTON_CLICK, function(player: Player, data: any)
		print(`[DemoService] 🖱️ Test click from {player.Name}`)
		
		NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, {
			action = "TestClick",
			echo = data,
			serverResponse = "Received!",
		})
	end)
end
return DemoService 


