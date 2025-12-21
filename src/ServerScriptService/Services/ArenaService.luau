--!strict

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(script.Parent.Parent.Core.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

local ArenaService = {}

-- Spawn points (adjust paths to your workspace structure)
local LOBBY_SPAWN = Workspace:WaitForChild("LobbySpawn") :: BasePart
local ARENA_SPAWN = Workspace:WaitForChild("ArenaSpawn") :: BasePart

function ArenaService:Init()
	EventBus:Subscribe(Events.PLAYER_ENTER_ARENA, function(player: Player, isArena: boolean)
		self:_teleportPlayer(player, isArena)
	end)
end

function ArenaService:_teleportPlayer(player: Player, isArena: boolean)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not humanoid or not rootPart then return end

	if isArena then
		-- Teleport to ARENA
		rootPart.CFrame = ARENA_SPAWN.CFrame + Vector3.new(0, 5, 0)
		
		-- Make vulnerable
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = true
			end
		end
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
		
		-- Reset health
		humanoid.Health = humanoid.MaxHealth
	else
		-- Teleport to LOBBY
		rootPart.CFrame = LOBBY_SPAWN.CFrame + Vector3.new(0, 5, 0)
		
		-- Make invincible (prevent damage)
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		
		-- Reset health
		humanoid.Health = humanoid.MaxHealth
	end
end

return ArenaService
