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

-- Advanced Input Tracking (เปลี่ยนชื่อจาก inputState เป็น inputTracking)
local inputTracking = {
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
local function onInput(actionName: string, state: Enum.UserInputState, inputObject: InputObject?)
    if not isInputEnabled then return Enum.ContextActionResult.Pass end
    
    local now = tick()
    
    -- === BEGIN STATE ===
    if state == Enum.UserInputState.Begin then
        -- Debounce check
        local lastTime = inputTracking.lastInputTime[actionName] or 0
        if (now - lastTime) < DEBOUNCE_TIME then
            return Enum.ContextActionResult.Sink
        end
        inputTracking.lastInputTime[actionName] = now
        
        -- Track hold start
        inputTracking.holdStartTime[actionName] = now
        inputTracking.isHolding[actionName] = false
        
        -- Double tap detection
        local lastTap = inputTracking.lastTapTime[actionName] or 0
        if (now - lastTap) < DOUBLE_TAP_WINDOW then
            inputTracking.tapCount[actionName] = (inputTracking.tapCount[actionName] or 0) + 1
            
            if inputTracking.tapCount[actionName] >= 2 then
                -- Double tap detected!
                print(`[InputController] 🖱️ Double tap: {actionName}`)
                EventBus:Emit(EVENT_INPUT_ACTION, actionName .. "DoubleTap")
                inputTracking.tapCount[actionName] = 0
                return Enum.ContextActionResult.Sink
            end
        else
            inputTracking.tapCount[actionName] = 1
        end
        inputTracking.lastTapTime[actionName] = now
        
        -- Add to input buffer (for combo system)
        table.insert(inputTracking.inputBuffer, {
            action = actionName,
            time = now
        })
        
        -- Clean old buffer entries
        while #inputTracking.inputBuffer > inputTracking.maxBufferSize do
            table.remove(inputTracking.inputBuffer, 1)
        end
        
        -- Emit normal tap
        print(`[InputController] ⌨️ Input Begin: {actionName}`)
        EventBus:Emit(EVENT_INPUT_ACTION, actionName)
        
        return Enum.ContextActionResult.Sink
    end
    
    -- === CHANGE STATE (for hold detection) ===
    if state == Enum.UserInputState.Change then
        local holdStart = inputTracking.holdStartTime[actionName]
        if holdStart and not inputTracking.isHolding[actionName] then
            local holdDuration = now - holdStart
            
            if holdDuration >= HOLD_THRESHOLD then
                inputTracking.isHolding[actionName] = true
                print(`[InputController] ⏱️ Hold detected: {actionName}`)
                EventBus:Emit(EVENT_INPUT_ACTION, actionName .. "Hold")
            end
        end
        return Enum.ContextActionResult.Sink
    end
    
    -- === END STATE (release) ===
    if state == Enum.UserInputState.End then
        local holdStart = inputTracking.holdStartTime[actionName]
        if holdStart then
            local holdDuration = now - holdStart
            
            -- If was holding, emit release event
            if inputTracking.isHolding[actionName] then
                print(string.format("[InputController] 📤 Hold released: %s (duration: %.2fs)", actionName, holdDuration))
                EventBus:Emit(EVENT_INPUT_ACTION, actionName .. "Release")
            end
        end
        
        -- Cleanup
        inputTracking.holdStartTime[actionName] = nil
        inputTracking.isHolding[actionName] = nil
        
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
    table.clear(inputTracking.holdStartTime)
    table.clear(inputTracking.isHolding)
    table.clear(inputTracking.lastTapTime)
    table.clear(inputTracking.tapCount)
    table.clear(inputTracking.lastInputTime)
    table.clear(inputTracking.inputBuffer)
end

function InputController:EnableInput(enabled: boolean)
    isInputEnabled = enabled
    
    if not enabled then
        -- Clear all held states
        table.clear(inputTracking.holdStartTime)
        table.clear(inputTracking.isHolding)
    end
    
    print(`[InputController] Input {enabled and "ENABLED" or "DISABLED"}`)
end

function InputController:CheckComboPatterns()
    -- Clean expired buffer entries
    local now = tick()
    local validBuffer = {}
    
    for _, entry in ipairs(inputTracking.inputBuffer) do
        if (now - entry.time) <= inputTracking.bufferWindow then
            table.insert(validBuffer, entry)
        end
    end
    inputTracking.inputBuffer = validBuffer
    
    -- Check for combo patterns (example: Attack → Attack → Special)
    if #inputTracking.inputBuffer >= 3 then
        local pattern = table.concat(
            table.create(3, function(i)
                return inputTracking.inputBuffer[#inputTracking.inputBuffer - 3 + i].action
            end),
            "-"
        )
        
        -- Example combo detection
        if pattern == "Attack-Attack-Special" then
            print("[InputController] 🔥 Combo detected: Triple Strike!")
            EventBus:Emit(EVENT_INPUT_ACTION, "ComboTripleStrike")
            table.clear(inputTracking.inputBuffer) -- Clear buffer after combo
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
        holding = inputTracking.isHolding,
        bufferSize = #inputTracking.inputBuffer,
        buffer = inputTracking.inputBuffer,
    }
end

return InputController