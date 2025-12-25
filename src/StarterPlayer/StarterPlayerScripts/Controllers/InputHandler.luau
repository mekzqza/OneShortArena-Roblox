--!strict

--[[
    InputHandler - Production Version
    
    จัดการ input actions และแปลงเป็น game commands
    รองรับ: Cooldown, State checking, Action queuing
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkController = require(script.Parent.NetworkController)

export type InputHandler = {
    Init: (self: InputHandler) -> (),
    Start: (self: InputHandler) -> (),
    [string]: any,
}

local InputHandler = {} :: InputHandler

local player = Players.LocalPlayer

-- Client-side state
local playerState = {
    canAttack = true,
    canDefend = true,
    canUseSkill = true,
    isInCombat = false,
    isInMenu = false,
}

-- Client-side cooldowns (visual feedback only, server validates)
local cooldowns = {
    Attack = 0.5,
    Defend = 1.0,
    Special = 3.0,
}

local lastActionTime = {} :: {[string]: number}

-- Action queue (for lag compensation)
local actionQueue = {} :: {{action: string, data: any, time: number}}
local MAX_QUEUE_SIZE = 3

function InputHandler:Init()
    print("[InputHandler] 🎯 Initialized")
end

function InputHandler:Start()
    -- Listen for all input actions
    EventBus:On(Events.INPUT_ACTION, function(actionName: string)
        self:OnInputAction(actionName)
    end)
    
    -- Listen for game state changes
    EventBus:On(Events.GAME_STATE_UPDATE, function(state: any)
        self:OnGameStateUpdate(state)
    end)
    
    --[[ Listen for server cooldown updates
    EventBus:On(Events.COOLDOWN_UPDATE, function(data: any)
        self:OnCooldownUpdate(data)
    end)]]
    
    -- Process action queue
    task.spawn(function()
        while true do
            task.wait(0.033) -- ~30 FPS
            self:ProcessActionQueue()
        end
    end)
    
    print("[InputHandler] 🚀 Started")
    self:PrintKeyBindings()
end

function InputHandler:OnInputAction(actionName: string)
    print(`[InputHandler] 🎮 Input: {actionName}`)
    
    -- Check if in menu
    if playerState.isInMenu then
        if actionName == "ToggleMenu" then
            self:HandleToggleMenu()
        end
        return -- Ignore other inputs in menu
    end
    
    -- Route to appropriate handler
    if actionName == "ATTACK" then
        self:HandleAttack()
        
    elseif actionName == "ATTACKHOLD" then
        self:HandleChargedAttack()
        
    elseif actionName == "ATTACKDOUBLETAP" then
        self:HandleDashAttack()
        
    elseif actionName == "DEFEND" then
        self:HandleDefend()
        
    elseif actionName == "DEFENDHOLD" then
        self:HandleParry()
        
    elseif actionName == "SPECIAL" then
        self:HandleSpecial()
        
    elseif actionName == "COMBOTRIPLESTRIKE" then
        self:HandleCombo("TripleStrike")
        
    elseif actionName == "TOGGLEMENU" then
        self:HandleToggleMenu()
    else
        -- Unknown action
        print(`[InputHandler] ⚠️ Unhandled action: {actionName}`)
    end
end

-- === COMBAT ACTIONS ===

function InputHandler:HandleAttack()
    if not self:CheckCooldown("Attack") then return end
    if not self:CanPerformCombatAction() then return end
    
    local position = self:GetPlayerPosition()
    local direction = self:GetPlayerLookDirection()
    
    self:QueueAction(Events.PLAYER_ATTACK, {
        timestamp = tick(),
        position = position,
        direction = direction,
        attackType = "Normal",
    })
    
    self:SetCooldown("Attack")
    print("[InputHandler] ⚔️ Attack queued")
end

function InputHandler:HandleChargedAttack()
    if not self:CheckCooldown("Attack") then return end
    if not self:CanPerformCombatAction() then return end
    
    self:QueueAction(Events.PLAYER_ATTACK, {
        timestamp = tick(),
        position = self:GetPlayerPosition(),
        direction = self:GetPlayerLookDirection(),
        attackType = "Charged",
        damageMultiplier = 1.5,
    })
    
    self:SetCooldown("Attack")
    print("[InputHandler] ⚡ Charged attack queued")
end

function InputHandler:HandleDashAttack()
    if not self:CheckCooldown("Attack") then return end
    if not self:CanPerformCombatAction() then return end
    
    self:QueueAction(Events.PLAYER_ATTACK, {
        timestamp = tick(),
        position = self:GetPlayerPosition(),
        direction = self:GetPlayerLookDirection(),
        attackType = "Dash",
        damageMultiplier = 1.2,
        knockback = true,
    })
    
    self:SetCooldown("Attack")
    print("[InputHandler] 💨 Dash attack queued")
end

function InputHandler:HandleDefend()
    if not self:CheckCooldown("Defend") then return end
    if not self:CanPerformCombatAction() then return end
    
    self:QueueAction(Events.PLAYER_DEFEND, {
        timestamp = tick(),
        defendType = "Block",
    })
    
    self:SetCooldown("Defend")
    print("[InputHandler] 🛡️ Defend queued")
end

function InputHandler:HandleParry()
    if not self:CheckCooldown("Defend") then return end
    if not self:CanPerformCombatAction() then return end
    
    self:QueueAction(Events.PLAYER_DEFEND, {
        timestamp = tick(),
        defendType = "Parry",
        counterAttack = true,
    })
    
    self:SetCooldown("Defend")
    print("[InputHandler] ⚡🛡️ Parry queued")
end

function InputHandler:HandleSpecial()
    if not self:CheckCooldown("Special") then return end
    if not self:CanPerformCombatAction() then return end
    
    self:QueueAction(Events.PLAYER_SPECIAL, {
        timestamp = tick(),
        position = self:GetPlayerPosition(),
        skillType = "Ultimate",
    })
    
    self:SetCooldown("Special")
    print("[InputHandler] ✨ Special queued")
end
--[[
function InputHandler:HandleCombo(comboName: string)
    print(`[InputHandler] 🔥 Combo: {comboName}`)
    
    self:QueueAction(Events.PLAYER_COMBO, {
        timestamp = tick(),
        comboName = comboName,
        position = self:GetPlayerPosition(),
    })
end
]]

-- === UI ACTIONS ===

function InputHandler:HandleToggleMenu()
    playerState.isInMenu = not playerState.isInMenu
    EventBus:Emit(Events.TOGGLE_UI, playerState.isInMenu)
    print(`[InputHandler] 📋 Menu: {playerState.isInMenu and "OPEN" or "CLOSED"}`)
end

-- === STATE MANAGEMENT ===

function InputHandler:CheckCooldown(actionName: string): boolean
    local lastTime = lastActionTime[actionName] or 0
    local cooldown = cooldowns[actionName] or 0
    local now = tick()
    
    if (now - lastTime) < cooldown then
        local remaining = cooldown - (now - lastTime)
        warn(string.format("[InputHandler] ⏱️ Action '%s' on cooldown (%.2f seconds left)", actionName, remaining))
        return false
    end
    
    return true
end

function InputHandler:SetCooldown(actionName: string)
    lastActionTime[actionName] = tick()
end

function InputHandler:CanPerformCombatAction(): boolean
    -- Check if player is alive
    if not player.Character or not player.Character:FindFirstChild("Humanoid") then
        warn("[InputHandler] ❌ Player not alive")
        return false
    end
    
    local humanoid = player.Character.Humanoid
    if humanoid.Health <= 0 then
        warn("[InputHandler] ❌ Player is dead")
        return false
    end
    
    -- Check if in combat state
    if not playerState.isInCombat and not playerState.canAttack then
        warn("[InputHandler] ❌ Not in combat state")
        return false
    end
    
    return true
end

-- === ACTION QUEUE (for lag compensation) ===

function InputHandler:QueueAction(eventName: string, data: any)
    if #actionQueue >= MAX_QUEUE_SIZE then
        warn("[InputHandler] ⚠️ Action queue full, dropping oldest")
        table.remove(actionQueue, 1)
    end
    
    table.insert(actionQueue, {
        action = eventName,
        data = data,
        time = tick(),
    })
end

function InputHandler:ProcessActionQueue()
    if #actionQueue == 0 then return end
    
    -- Send queued actions to server
    for _, queuedAction in ipairs(actionQueue) do
        NetworkController:Send(queuedAction.action, queuedAction.data)
    end 
    
    -- Clear queue
    table.clear(actionQueue)
end

-- === SERVER STATE UPDATES ===

function InputHandler:OnGameStateUpdate(state: any)
    if state.isInCombat ~= nil then
        playerState.isInCombat = state.isInCombat
    end
    
    print(`[InputHandler] 🔄 State updated: Combat={playerState.isInCombat}`)
end

function InputHandler:OnCooldownUpdate(data: any)
    if data.action and data.remaining then
        print(`[InputHandler] ⏱️ Server cooldown: {data.action} = {data.remaining}s`)
        -- Could update UI here
    end
end

-- === HELPERS ===

function InputHandler:GetPlayerPosition(): Vector3
    if player.Character and player.Character.PrimaryPart then
        return player.Character.PrimaryPart.Position
    end
    return Vector3.zero
end

function InputHandler:GetPlayerLookDirection(): Vector3
    if player.Character and player.Character.PrimaryPart then
        return player.Character.PrimaryPart.CFrame.LookVector
    end
    return Vector3.new(0, 0, -1)
end

function InputHandler:PrintKeyBindings()
    print("[InputHandler] ⌨️ Key Bindings:")
    print("  • E = Attack")
    print("  • Hold E = Charged Attack")
    print("  • Double E = Dash Attack")
    print("  • Q = Defend")
    print("  • Hold Q = Parry")
    print("  • R = Special")
    print("  • Tab = Toggle Menu")
    print("  • P = Ping Server")
end

-- Debug
function InputHandler:GetState()
    return {
        playerState = playerState,
        cooldowns = lastActionTime,
        queueSize = #actionQueue,
    }
end

return InputHandler
