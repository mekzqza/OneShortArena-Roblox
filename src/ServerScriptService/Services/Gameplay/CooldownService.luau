--!strict

--[[
    CooldownService - Production Ready
    
    จัดการ cooldown ของ skills, attacks, items
    - Server-authoritative (client ห้ามเชื่อ)
    - Per-player tracking
    - Configurable cooldowns
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local NetworkHandler = require(ServerScriptService.Services.Core.NetworkHandler)

export type CooldownService = {
    Init: (self: CooldownService) -> (),
    Start: (self: CooldownService) -> (),
    IsOnCooldown: (self: CooldownService, player: Player, actionName: string) -> boolean,
    SetCooldown: (self: CooldownService, player: Player, actionName: string, duration: number?) -> (),
    GetRemaining: (self: CooldownService, player: Player, actionName: string) -> number,
    [string]: any,
}

local CooldownService: CooldownService = {}

-- Cooldown configs (in seconds)
local COOLDOWN_CONFIG = {
    Attack = 0.5,
    ChargedAttack = 1.0,
    DashAttack = 0.8,
    Defend = 1.0,
    Parry = 2.0,
    Special = 5.0,
    Combo = 3.0,
}

-- Track cooldowns: {[userId] = {[actionName] = expiryTime}}
local playerCooldowns: {[number]: {[string]: number}} = {}

function CooldownService:Init()
    print("[CooldownService] Initialized")
end

function CooldownService:Start()
    -- Cleanup on player leave
    Players.PlayerRemoving:Connect(function(player)
        playerCooldowns[player.UserId] = nil
    end)
    
    print("[CooldownService] Started")
end

function CooldownService:IsOnCooldown(player: Player, actionName: string): boolean
    local userId = player.UserId
    local cooldownData = playerCooldowns[userId]
    
    if not cooldownData then return false end
    
    local expiryTime = cooldownData[actionName]
    if not expiryTime then return false end
    
    local now = os.clock()
    return now < expiryTime
end

function CooldownService:SetCooldown(player: Player, actionName: string, duration: number?)
    local userId = player.UserId
    
    if not playerCooldowns[userId] then
        playerCooldowns[userId] = {}
    end
    
    local cooldownDuration = duration or COOLDOWN_CONFIG[actionName] or 1.0
    local expiryTime = os.clock() + cooldownDuration
    
    playerCooldowns[userId][actionName] = expiryTime
    
    -- Notify client (for UI feedback)
    NetworkHandler:SendToClient(player, Events.COOLDOWN_UPDATE, {
        action = actionName,
        remaining = cooldownDuration,
    })
    
    print(`[CooldownService] {player.Name}: {actionName} cooldown = {cooldownDuration}s`)
end

function CooldownService:GetRemaining(player: Player, actionName: string): number
    local userId = player.UserId
    local cooldownData = playerCooldowns[userId]
    
    if not cooldownData then return 0 end
    
    local expiryTime = cooldownData[actionName]
    if not expiryTime then return 0 end
    
    local remaining = math.max(0, expiryTime - os.clock())
    return remaining
end

function CooldownService:ClearCooldown(player: Player, actionName: string)
    local userId = player.UserId
    if playerCooldowns[userId] then
        playerCooldowns[userId][actionName] = nil
    end
end

function CooldownService:ClearAllCooldowns(player: Player)
    playerCooldowns[player.UserId] = {}
end

return CooldownService
