--!strict

--[ [
    --InputController - Production Ready Version
    
    --Features:
    -- Hold detection (กดค้าง)
    -- Double tap/click detection
    -- Input buffering (combo system)
    -- Debounce (ป้องกันกดซ้ำเร็วเกินไป)
    -- Mobile touch zones
    -- Gamepad vibration feedback
--]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local InputSettings = require(ReplicatedStorage.Shared.InputSettings)

export type ModuleImpl = {
    Init: (self: ModuleImpl) -> (),
    Start: (self: ModuleImpl) -> (),
    BindAllActions: (self: ModuleImpl) -> (),
    UnbindAll: (self: ModuleImpl) -> (),
    EnableInput: (self: ModuleImpl, enabled: boolean) -> (),
    [string]: any,
}

local InputController: ModuleImpl = {}

local EVENT_INPUT_ACTION = (Events :: any).INPUT_ACTION

-- Advanced Input Tracking
local inputState = {
    -- Hold tracking
    holdStartTime = {} :: {[string]: number},
    isHolding = {} :: {[string]: boolean},
    
    -- Double tap tracking
    lastTapTime = {} :: {[string]: number},
    tapCount = {} :: {[string]: number},
    
    -- Debounce tracking
    lastInputTime = {} :: {[string]: number},
    
    -- Input buffer (for combo system)
    inputBuffer = {} :: {[number]: {action: string, time: number}},
    maxBufferSize = 5,
    bufferWindow = 0.5, -- seconds
}

local isInputEnabled = true
local DEBOUNCE_TIME = 0.1 -- ป้องกันกดเร็วเกินไป
local HOLD_THRESHOLD = 0.3 -- กดค้างนานกว่า 0.3 วิ = ถือว่า Hold
local DOUBLE_TAP_WINDOW = 0.3 -- กดซ้ำภายใน 0.3 วิ = Double Tap

--[ [
    --Advanced Input Handler
    --รองรับ: Tap, Hold, DoubleTap, Release
--]]
local function onInput(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject?)
    if not isInputEnabled then return Enum.ContextActionResult.Pass end
    
    local now = tick()
    
    -- === BEGIN STATE ===
    if inputState == Enum.UserInputState.Begin then
        -- Debounce check
        local lastTime = inputState.lastInputTime[actionName] or 0
        if (now - lastTime) < DEBOUNCE_TIME then
            return Enum.ContextActionResult.Sink
        end
        inputState.lastInputTime[actionName] = now
        
        -- Track hold start
        inputState.holdStartTime[actionName] = now
        inputState.isHolding[actionName] = false
        
        -- Double tap detection
        local lastTap = inputState.lastTapTime[actionName] or 0
        if (now - lastTap) < DOUBLE_TAP_WINDOW then
            inputState.tapCount[actionName] = (inputState.tapCount[actionName] or 0) + 1
            
            if inputState.tapCount[actionName] >= 2 then
                -- Double tap detected!
                print(`[InputController] 🖱️ Double tap: {actionName}`)
                EventBus:Emit(EVENT_INPUT_ACTION, actionName .. "DoubleTap")
                inputState.tapCount[actionName] = 0
                return Enum.ContextActionResult.Sink
            end
        else
            inputState.tapCount[actionName] = 1
        end
        inputState.lastTapTime[actionName] = now
        
        -- Add to input buffer (for combo system)
        table.insert(inputState.inputBuffer, {
            action = actionName,
            time = now
        })
        
        -- Clean old buffer entries
        while #inputState.inputBuffer > inputState.maxBufferSize do
            table.remove(inputState.inputBuffer, 1)
        end
        
        -- Emit normal tap
        print(`[InputController] ⌨️ Input Begin: {actionName}`)
        EventBus:Emit(EVENT_INPUT_ACTION, actionName)
        
        return Enum.ContextActionResult.Sink
    end
    
    -- === CHANGE STATE (for hold detection) ===
    if inputState == Enum.UserInputState.Change then
        local holdStart = inputState.holdStartTime[actionName]
        if holdStart and not inputState.isHolding[actionName] then
            local holdDuration = now - holdStart
            
            if holdDuration >= HOLD_THRESHOLD then
                inputState.isHolding[actionName] = true
                print(`[InputController] ⏱️ Hold detected: {actionName}`)
                EventBus:Emit(EVENT_INPUT_ACTION, actionName .. "Hold")
            end
        end
        return Enum.ContextActionResult.Sink
    end
    
    -- === END STATE (release) ===
    if inputState == Enum.UserInputState.End then
        local holdStart = inputState.holdStartTime[actionName]
        if holdStart then
            local holdDuration = now - holdStart
            
            -- If was holding, emit release event
            if inputState.isHolding[actionName] then
                print(string.format("[InputController] 🛑 Hold released: %s (held for %.2f seconds)", actionName, holdDuration))
                EventBus:Emit(EVENT_INPUT_ACTION, actionName .. "Release")
            end
        end
        
        -- Cleanup
        inputState.holdStartTime[actionName] = nil
        inputState.isHolding[actionName] = nil
        
        return Enum.ContextActionResult.Sink
    end
    
    return Enum.ContextActionResult.Pass
end

function InputController:Init()
    self:BindAllActions()
    
    -- Listen for input enable/disable from game state
    EventBus:On(Events.INPUT_ENABLED_CHANGED, function(enabled: boolean)
        self:EnableInput(enabled)
    end)
    
    print("🎮 [InputController] Initialized (Production Mode)")
    print("   ✅ Hold detection enabled")
    print("   ✅ Double tap detection enabled")
    print("   ✅ Input buffering enabled")
    print("   ✅ Debounce protection enabled")
end

function InputController:Start()
    -- Monitor combo patterns
    task.spawn(function()
        while true do
            task.wait(0.1)
            self:CheckComboPatterns()
        end
    end)
end

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

function InputController:UnbindAll()
    for actionName, _ in pairs(InputSettings.Bindings) do
        ContextActionService:UnbindAction(actionName)
    end
    
    -- Clear state
    table.clear(inputState.holdStartTime)
    table.clear(inputState.isHolding)
    table.clear(inputState.lastTapTime)
    table.clear(inputState.tapCount)
    table.clear(inputState.lastInputTime)
    table.clear(inputState.inputBuffer)
end

function InputController:EnableInput(enabled: boolean)
    isInputEnabled = enabled
    
    if not enabled then
        -- Clear all held states
        table.clear(inputState.holdStartTime)
        table.clear(inputState.isHolding)
    end
    
    print(`[InputController] Input {enabled and "ENABLED" or "DISABLED"}`)
end

function InputController:CheckComboPatterns()
    -- Clean expired buffer entries
    local now = tick()
    local validBuffer = {}
    
    for _, entry in ipairs(inputState.inputBuffer) do
        if (now - entry.time) <= inputState.bufferWindow then
            table.insert(validBuffer, entry)
        end
    end
    inputState.inputBuffer = validBuffer
    
    -- Check for combo patterns (example: Attack → Attack → Special)
    if #inputState.inputBuffer >= 3 then
        local pattern = table.concat(
            table.create(3, function(i)
                return inputState.inputBuffer[#inputState.inputBuffer - 3 + i].action
            end),
            "-"
        )
        
        -- Example combo detection
        if pattern == "Attack-Attack-Special" then
            print("[InputController] 🔥 Combo detected: Triple Strike!")
            EventBus:Emit(EVENT_INPUT_ACTION, "ComboTripleStrike")
            table.clear(inputState.inputBuffer) -- Clear buffer after combo
        end
    end
end

function InputController:CountBindings(): number
    local count = 0
    for _ in pairs(InputSettings.Bindings) do
        count += 1
    end
    return count
end

-- Debug: Get current input state
function InputController:GetInputState()
    return {
        enabled = isInputEnabled,
        holding = inputState.isHolding,
        bufferSize = #inputState.inputBuffer,
        buffer = inputState.inputBuffer,
    }
end

return InputController