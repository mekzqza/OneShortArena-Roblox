--!strict

--[ [
    -- InputController - Production Version
    
    -- Part of: OneShortArena Production Architecture
    -- Layer: Client-Side Input Detection
    
    -- Responsibilities:
    -- Detect hardware input (Keyboard, Mobile, Gamepad)
    -- Support 5 input types: Tap, Hold, DoubleTap, Release, Combo
    -- Emit INPUT_ACTION events via EventBus
    -- Does NOT send to server directly (handled by InputHandler)
    
    -- Architecture Flow:
    -- Player Input → InputController → EventBus → InputHandler → Server
    
    -- Features:
    -- ✅ Hold detection (Timer-based, 0.3s threshold)
    -- ✅ Double tap detection (0.3s window)
    -- ✅ Input buffering for combo system
    -- ✅ Debounce protection (0.1s)
    -- ✅ Mobile touch button support
    -- ✅ Configurable thresholds
    
    -- @version 2.0 - Production Ready
    -- @author OneShortArena Team
--]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local InputSettings = require(ReplicatedStorage.Shared.InputSettings)

-- Type Definitions
export type InputController = {
    Init: (self: InputController) -> (),
    Start: (self: InputController) -> (),
    BindAllActions: (self: InputController) -> (),
    UnbindAll: (self: InputController) -> (),
    EnableInput: (self: InputController, enabled: boolean) -> (),
    GetInputState: (self: InputController) -> InputState,
    CountBindings: (self: InputController) -> number,
    [string]: any,
}

export type InputState = {
    enabled: boolean,
    holding: {[string]: boolean},
    bufferSize: number,
    buffer: {{action: string, time: number}},
}

local InputController: InputController = {} :: InputController

-- Constants
local EVENT_INPUT_ACTION = (Events :: any).INPUT_ACTION
local DEBOUNCE_TIME = 0.1 -- Prevent rapid duplicate inputs
local HOLD_THRESHOLD = 0.3 -- Time to detect hold
local DOUBLE_TAP_WINDOW = 0.3 -- Time window for double tap

-- State Tracking
local inputTracking = {
    holdStartTime = {} :: {[string]: number},
    isHolding = {} :: {[string]: boolean},
    lastTapTime = {} :: {[string]: number},
    tapCount = {} :: {[string]: number},
    lastInputTime = {} :: {[string]: number},
    inputBuffer = {} :: {{action: string, time: number}},
    maxBufferSize = 5,
    bufferWindow = 0.5,
    hasEmittedTap = {} :: {[string]: boolean}, -- ป้องกันส่งซ้ำ
}

local holdTimers = {} :: {[string]: thread?}
local isInputEnabled = true

--[ [
    -- Advanced Input Handler
    
    -- Handles all input states: Begin, End
    -- Detects: Tap, Hold, DoubleTap, Release, Combo
    
    -- @param actionName string - Action identifier from InputSettings
    -- @param state Enum.UserInputState - Input state (Begin/End)
    -- @param inputObject InputObject? - Raw input data
    -- @return Enum.ContextActionResult - Sink (handled) or Pass (ignored)
--]]
local function onInput(actionName: string, state: Enum.UserInputState, inputObject: InputObject?): Enum.ContextActionResult
    if not isInputEnabled then 
        return Enum.ContextActionResult.Pass 
    end
    
    local now = tick()
    
    -- === BEGIN STATE: Button Pressed ===
    if state == Enum.UserInputState.Begin then
        -- Debounce: Ignore rapid duplicate inputs
        local lastTime = inputTracking.lastInputTime[actionName] or 0
        if (now - lastTime) < DEBOUNCE_TIME then
            return Enum.ContextActionResult.Sink
        end
        inputTracking.lastInputTime[actionName] = now
        
        -- Reset emission flag
        inputTracking.hasEmittedTap[actionName] = false
        
        -- Track hold state
        inputTracking.holdStartTime[actionName] = now
        inputTracking.isHolding[actionName] = false
        
        -- Start hold timer (Timer-based detection)
        if holdTimers[actionName] then
            task.cancel(holdTimers[actionName])
        end
        
        holdTimers[actionName] = task.delay(HOLD_THRESHOLD, function()
            if inputTracking.holdStartTime[actionName] and not inputTracking.hasEmittedTap[actionName] then
                inputTracking.isHolding[actionName] = true
                inputTracking.hasEmittedTap[actionName] = true
                print(`[InputController] ⏱️ Hold detected: {actionName}`)
                EventBus:Emit(EVENT_INPUT_ACTION, actionName .. "Hold")
            end
        end)
        
        -- Double tap detection (CHECK FIRST before emitting tap)
        local lastTap = inputTracking.lastTapTime[actionName] or 0
        local isWithinDoubleTapWindow = (now - lastTap) < DOUBLE_TAP_WINDOW
        
        if isWithinDoubleTapWindow then
            inputTracking.tapCount[actionName] = (inputTracking.tapCount[actionName] or 0) + 1
            
            if inputTracking.tapCount[actionName] >= 2 then
                print(`[InputController] 🖱️ Double tap: {actionName}`)
                
                -- Cancel hold timer on double tap
                if holdTimers[actionName] then
                    task.cancel(holdTimers[actionName])
                    holdTimers[actionName] = nil
                end
                
                inputTracking.hasEmittedTap[actionName] = true
                EventBus:Emit(EVENT_INPUT_ACTION, actionName .. "DoubleTap")
                inputTracking.tapCount[actionName] = 0
                
                -- DON'T emit normal tap for double tap
                return Enum.ContextActionResult.Sink
            end
        else
            inputTracking.tapCount[actionName] = 1
        end
        inputTracking.lastTapTime[actionName] = now
        
        -- Add to input buffer (for combo detection)
        table.insert(inputTracking.inputBuffer, {
            action = actionName,
            time = now
        })
        
        -- Limit buffer size
        while #inputTracking.inputBuffer > inputTracking.maxBufferSize do
            table.remove(inputTracking.inputBuffer, 1)
        end
        
        -- Emit normal tap event (only if not already emitted)
        if not inputTracking.hasEmittedTap[actionName] then
            -- Delay tap emission slightly to detect double tap
            task.delay(DOUBLE_TAP_WINDOW, function()
                if not inputTracking.hasEmittedTap[actionName] then
                    inputTracking.hasEmittedTap[actionName] = true
                    print(`[InputController] ⌨️ Input Begin: {actionName}`)
                    EventBus:Emit(EVENT_INPUT_ACTION, actionName)
                end
            end)
        end
        
        return Enum.ContextActionResult.Sink
    end
    
    -- === END STATE: Button Released ===
    if state == Enum.UserInputState.End then
        -- Cancel hold timer
        if holdTimers[actionName] then
            task.cancel(holdTimers[actionName])
            holdTimers[actionName] = nil
        end
        
        local holdStart = inputTracking.holdStartTime[actionName]
        if holdStart then
            local holdDuration = now - holdStart
            
            -- Emit release event if was holding
            if inputTracking.isHolding[actionName] then
                print(string.format("[InputController] 📤 Hold released: %s (duration: %.2fs)", actionName, holdDuration))
                EventBus:Emit(EVENT_INPUT_ACTION, actionName .. "Release")
            end
        end
        
        -- Cleanup
        inputTracking.holdStartTime[actionName] = nil
        inputTracking.isHolding[actionName] = nil
        inputTracking.hasEmittedTap[actionName] = nil
        
        return Enum.ContextActionResult.Sink
    end
    
    return Enum.ContextActionResult.Pass
end

--[ [
    -- Initialize InputController
    
    -- - Bind all actions from InputSettings
    -- - Setup EventBus listeners for input enable/disable
    -- - Print initialization status
--]]
function InputController:Init()
    self:BindAllActions()
    
    -- Listen for game state changes
    EventBus:On(Events.INPUT_ENABLED_CHANGED, function(enabled: boolean)
        self:EnableInput(enabled)
    end)
    
    print("🎮 [InputController] Initialized (Production Mode)")
    print("   ✅ Hold detection enabled (Timer-based)")
    print("   ✅ Double tap detection enabled")
    print("   ✅ Input buffering enabled (Combo system)")
    print("   ✅ Debounce protection enabled")
end

--[ [
    -- Start InputController
    
    -- - Begin combo pattern monitoring
    -- - Run cleanup loop for expired buffer entries
--]]
function InputController:Start()
    -- Monitor combo patterns in background
    task.spawn(function()
        while true do
            task.wait(0.1) -- Check every 100ms
            self:CheckComboPatterns()
        end
    end)
    
    print("[InputController] Started - Combo monitoring active")
end

--[ [
    -- Bind all actions from InputSettings
    
    -- Registers all key bindings with ContextActionService
    -- Sets mobile button titles if defined
--]]
function InputController:BindAllActions()
    for actionName, keys in pairs(InputSettings.Bindings) do
        ContextActionService:BindAction(actionName, onInput, true, table.unpack(keys))

        local title = InputSettings.MobileButtonNames[actionName]
        if title then
            ContextActionService:SetTitle(actionName, title)
        end
    end
    
    print(`[InputController] Bound {self:CountBindings()} actions`)
end

--[ [
    -- Unbind all actions and cleanup
    
    -- - Unbind all ContextActionService bindings
    -- - Cancel all hold timers
    -- - Clear all tracking state
--]]
function InputController:UnbindAll()
    -- Unbind all actions
    for actionName, _ in pairs(InputSettings.Bindings) do
        ContextActionService:UnbindAction(actionName)
    end
    
    -- Cancel all hold timers
    for actionName, timer in pairs(holdTimers) do
        if timer then
            task.cancel(timer)
        end
    end
    table.clear(holdTimers)
    
    -- Clear all tracking state
    table.clear(inputTracking.holdStartTime)
    table.clear(inputTracking.isHolding)
    table.clear(inputTracking.lastTapTime)
    table.clear(inputTracking.tapCount)
    table.clear(inputTracking.lastInputTime)
    table.clear(inputTracking.inputBuffer)
    table.clear(inputTracking.hasEmittedTap)
    
    print("[InputController] Unbound all actions and cleaned up state")
end

--[ [
    -- Enable or disable input processing
    
    -- @param enabled boolean - True to enable, false to disable
--]]
function InputController:EnableInput(enabled: boolean)
    isInputEnabled = enabled
    
    if not enabled then
        -- Cancel all active hold timers
        for actionName, timer in pairs(holdTimers) do
            if timer then
                task.cancel(timer)
            end
        end
        table.clear(holdTimers)
        
        -- Clear hold state
        table.clear(inputTracking.holdStartTime)
        table.clear(inputTracking.isHolding)
    end
    
    print(`[InputController] Input {enabled and "ENABLED" or "DISABLED"}`)
end

--[ [
    -- Check for combo patterns in input buffer
    
    -- Detects predefined sequences like "Attack-Attack-Special"
    -- Emits combo events when patterns match
--]]
function InputController:CheckComboPatterns()
    local now = tick()
    local validBuffer = {}
    
    -- Clean expired entries
    for _, entry in ipairs(inputTracking.inputBuffer) do
        if (now - entry.time) <= inputTracking.bufferWindow then
            table.insert(validBuffer, entry)
        end
    end
    inputTracking.inputBuffer = validBuffer
    
    -- Check for combo patterns
    if #inputTracking.inputBuffer >= 3 then
        local actions = {}
        for i = #inputTracking.inputBuffer - 2, #inputTracking.inputBuffer do
            table.insert(actions, inputTracking.inputBuffer[i].action)
        end
        local pattern = table.concat(actions, "-")
        
        -- Example: Triple Strike combo
        if pattern == "Attack-Attack-Special" then
            print("[InputController] 🔥 Combo detected: Triple Strike!")
            EventBus:Emit(EVENT_INPUT_ACTION, "ComboTripleStrike")
            table.clear(inputTracking.inputBuffer)
        end
        
        -- Add more combo patterns here
    end
end

--[ [
    -- Count number of bound actions
    
    -- @return number - Count of bindings
--]]
function InputController:CountBindings(): number
    local count = 0
    for _ in pairs(InputSettings.Bindings) do
        count += 1
    end
    return count
end

--[ [
    -- Get current input state (Debug)
    
    -- @return InputState - Current state snapshot
--]]
function InputController:GetInputState(): InputState
    return {
        enabled = isInputEnabled,
        holding = inputTracking.isHolding,
        bufferSize = #inputTracking.inputBuffer,
        buffer = inputTracking.inputBuffer,
    }
end

return InputController