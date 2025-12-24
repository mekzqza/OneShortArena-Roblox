local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Events =require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.NetworkHandler)
local CooldownService = require(ServerScriptService.Services.CooldownService)
export type DemoService ={
	Init: (self: DemoService) ->(),
	Start: (self: DemoService) ->(),
	[string]: any,
}

local DemoService: DemoService = {}

function DemoService:Start()

	-- Listen for Attack input
	EventBus:On(Events.PLAYER_ATTACK, function(player: Player, data: any)
		print(`[DemoService] ⚔️ {player.Name} attacked at {data.position}`)
		
		-- ✅ Server-side cooldown check
		if CooldownService:IsOnCooldown(player, "Attack") then
			local remaining = CooldownService:GetRemaining(player, "Attack")
			NetworkHandler:SendToClient(player, Events.ACTION_FAILED, {
				reason = "On cooldown",
				remaining = remaining,
			})
			warn(string.format("[DemoService] ⚔️ %s tried to attack but is on cooldown (%.2f seconds left)", player.Name, remaining))
			return
		end
		
		-- ✅ Validate player state
		if not player.Character or not player.Character:FindFirstChild("Humanoid") then
			return
		end
		
		local humanoid = player.Character.Humanoid
		if humanoid.Health <= 0 then
			return
		end
		
		-- Process attack
		local damage = 10
		
		-- Send response back to client
		NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, {
			action = "Attack",
			damage = damage,
			success = true,
			message = "Attack executed!",
		})
		
		-- Broadcast to other players
		NetworkHandler:Broadcast(Events.DEMO_BROADCAST_MESSAGE, {
			playerName = player.Name,
			userId = player.UserId,
			message = `{player.Name} performed an attack! (Damage: {damage})`,
			timestamp = os.clock(),
		})
	end)
	
	-- Listen for Defend input
	EventBus:On(Events.PLAYER_DEFEND, function(player: Player, data: any)
		print(`[DemoService] 🛡️ {player.Name} is defending`)
		
		NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, {
			action = "Defend",
			isBlocking = data.isBlocking,
			success = true,
			message = "Defense activated!",
		})
	end)
	
	-- Listen for Special input
	EventBus:On(Events.PLAYER_SPECIAL, function(player: Player, data: any)
		print(`[DemoService] ✨ {player.Name} used special: {data.skillType}`)
		
		NetworkHandler:Broadcast(Events.DEMO_BROADCAST_MESSAGE, {
			playerName = player.Name,
			userId = player.UserId,
			message = `{player.Name} used {data.skillType}! ✨`,
			timestamp = os.clock(),
		})
	end)
	
	-- Listen for manual test
	EventBus:On(Events.TEST_CLIENT_BUTTON_CLICK, function(player: Player, message: number)
		print(`[DemoService] 📨 Manual test from {player.Name}: {message}`)
		
		NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, {
			action = "ManualTest",
			echo = message,
			serverResponse = "Server received your message!",
		})
	end)
end

function DemoService:Init()

	NetworkHandler:AllowClientEvent(Events.TEST_CLIENT_BUTTON_CLICK)
	NetworkHandler:AllowServerEvent(Events.TEST_SERVER_RESPONSE)
	
	-- Allow input events
	NetworkHandler:AllowClientEvent(Events.PLAYER_ATTACK)
	NetworkHandler:AllowClientEvent(Events.PLAYER_DEFEND)
	NetworkHandler:AllowClientEvent(Events.PLAYER_SPECIAL)
end

return DemoService
