--!strict

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(script.Parent.Parent.Core.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

local ArenaService = {}

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
        rootPart.CFrame = ARENA_SPAWN.CFrame + Vector3.new(0, 5, 0)
        character:SetAttribute("Invincible", false)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
        humanoid.Health = humanoid.MaxHealth
    else
        rootPart.CFrame = LOBBY_SPAWN.CFrame + Vector3.new(0, 5, 0)
        character:SetAttribute("Invincible", true)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
        humanoid.Health = humanoid.MaxHealth
    end
end

return ArenaService