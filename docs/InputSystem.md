# 🎮 Input System Documentation

## 🎯 Overview

ระบบ Input แบบ **2-Layer Architecture** ที่แยก Low-level Detection ออกจาก Game Logic:

- **InputController** - ตรวจจับ input จากฮาร์ดแวร์
- **InputHandler** - แปลเป็น game commands และส่งไป server

---

## 📖 Table of Contents

1. [Architecture](#architecture)
2. [InputController (Detection Layer)](#inputcontroller)
3. [InputHandler (Logic Layer)](#inputhandler)
4. [Input Patterns](#input-patterns)
5. [Configuration](#configuration)
6. [Examples](#examples)

---

## Architecture

### Layer Separation

```
Player กดปุ่ม "E"
    ↓
┌─────────────────────────────────────┐
│  InputController (Low-level)        │
│  - Detect hardware input            │
│  - Pattern detection:               │
│    • Tap, Hold, DoubleTap          │
│    • Combo buffering               │
│  - Debounce protection             │
└──────────────┬──────────────────────┘
               │ Emit: INPUT_ACTION("ATTACK")
               ↓
┌─────────────────────────────────────┐
│  InputHandler (Game Logic)          │
│  - Convert to game command          │
│  - Check cooldown (client)          │
│  - Validate player state            │
│  - Queue action                     │
└──────────────┬──────────────────────┘
               │ Send to server
               ↓
┌─────────────────────────────────────┐
│  NetworkController                  │
│  - Send via RemoteEvent             │
│  - Reliable send option             │
└──────────────┬──────────────────────┘
               │
               ↓ Server validates & processes
```

### Why 2 Layers?

| Concern | InputController | InputHandler |
|---------|----------------|--------------|
| **Responsibility** | "ปุ่มไหนถูกกด?" | "ต้องทำอะไร?" |
| **Output** | "ATTACK", "ATTACKHold" | PLAYER_ATTACK event |
| **Reusable** | ✅ ใช้ได้กับทุกเกม | ❌ เฉพาะ OneShortArena |
| **Dependencies** | None (pure input) | Game logic, Network |

---

## InputController

### Features

- ✅ **Tap Detection** - คลิกเดี่ยว
- ✅ **Hold Detection** - กดค้าง (0.3s threshold)
- ✅ **DoubleTap Detection** - กด 2 ครั้งเร็วๆ (0.3s window)
- ✅ **Combo Buffering** - เก็บ input history สำหรับ combo
- ✅ **Debounce Protection** - ป้องกันกดซ้ำเร็วเกินไป (0.1s)
- ✅ **Cross-platform** - PC, Mobile, Gamepad

### Input Flow

```lua
-- 1. Player presses "E"
ContextActionService triggers "ATTACK" action

-- 2. InputController processes
function onInput(actionName, state, inputObject)
    if state == Begin then
        -- Start hold timer (0.3s)
        -- Check for double tap
        -- Emit tap event
        EventBus:Emit(INPUT_ACTION, "ATTACK")
    elseif state == End then
        -- Cancel hold timer
        -- Emit release if was holding
    end
end
```

### Detection Logic

**Hold Detection (Timer-based):**
```lua
-- กดปุ่ม
holdTimer = task.delay(0.3, function()
    if stillHolding then
        EventBus:Emit(INPUT_ACTION, "ATTACKHold")
    end
end)

-- ปล่อยปุ่ม
task.cancel(holdTimer)
```

**DoubleTap Detection:**
```lua
local now = tick()
local lastTap = lastTapTime["ATTACK"] or 0

if (now - lastTap) < 0.3 then
    tapCount += 1
    if tapCount >= 2 then
        EventBus:Emit(INPUT_ACTION, "ATTACKDoubleTap")
    end
else
    tapCount = 1
end
```

### Configuration

```lua
-- StarterPlayerScripts/Controllers/InputController.luau

local DEBOUNCE_TIME = 0.1      -- ห้ามกดซ้ำภายใน 0.1s
local HOLD_THRESHOLD = 0.3     -- กดค้าง 0.3s = Hold
local DOUBLE_TAP_WINDOW = 0.3  -- กด 2 ครั้งภายใน 0.3s = DoubleTap
```

### Methods

```lua
-- Enable/Disable input
InputController:EnableInput(false)  -- ปิด input (เช่นตอนอยู่ใน menu)
InputController:EnableInput(true)   -- เปิด input

-- Get state (for debugging)
local state = InputController:GetInputState()
print(state.enabled)        -- true/false
print(state.holding)        -- {ATTACK = true}
print(state.bufferSize)     -- 3
print(state.buffer)         -- {{action="ATTACK", time=123}, ...}

-- Unbind all (cleanup)
InputController:UnbindAll()
```

### Key Bindings

```lua
-- ReplicatedStorage/Shared/InputSettings.luau

Bindings = {
    ATTACK = { Enum.KeyCode.E },                    -- PC: E key
    DEFEND = { Enum.KeyCode.Q },                    -- PC: Q key
    SPECIAL = { Enum.KeyCode.R },                   -- PC: R key
    TOGGLEMENU = { Enum.KeyCode.Tab },              -- PC: Tab
    PING = { Enum.KeyCode.P },                      -- Debug
}

-- Mobile button names
MobileButtonNames = {
    ATTACK = "⚔️",
    DEFEND = "🛡️",
    SPECIAL = "✨",
}
```

---

## InputHandler

### Features

- ✅ **Action Routing** - แยก handler ตามประเภท action
- ✅ **Client Cooldown** - เช็คฝั่ง client (visual feedback)
- ✅ **State Validation** - ตรวจสอบว่า player มีชีวิต, ไม่อยู่ใน menu
- ✅ **Action Queue** - จัดเก็บ action สำหรับ lag compensation
- ✅ **Multiple Attack Types** - Normal, Charged, Dash

### Input → Command Mapping

```lua
INPUT_ACTION event          →  Game Command
─────────────────────────────────────────────
"ATTACK"                   →  Normal Attack
"ATTACKHold"               →  Charged Attack
"ATTACKDoubleTap"          →  Dash Attack
"DEFEND"                   →  Block
"DEFENDHold"               →  Parry
"SPECIAL"                  →  Ultimate
"ComboTripleStrike"        →  Combo Attack
```

### Action Processing

```lua
function InputHandler:OnInputAction(actionName: string)
    -- Route to appropriate handler
    if actionName == "ATTACK" then
        self:HandleAttack()
    elseif actionName == "ATTACKHold" then
        self:HandleChargedAttack()
    elseif actionName == "ATTACKDoubleTap" then
        self:HandleDashAttack()
    -- ...
    end
end
```

### Attack Handler Example

```lua
function InputHandler:HandleAttack()
    -- 1. Check cooldown (client-side)
    if not self:CheckCooldown("Attack") then
        return  -- Still on cooldown
    end
    
    -- 2. Validate state
    if not self:CanPerformCombatAction() then
        return  -- Dead, in menu, etc.
    end
    
    -- 3. Gather data
    local position = self:GetPlayerPosition()
    local direction = self:GetPlayerLookDirection()
    
    -- 4. Queue action (for lag compensation)
    self:QueueAction(Events.PLAYER_ATTACK, {
        timestamp = tick(),
        position = position,
        direction = direction,
        attackType = "Normal",
    })
    
    -- 5. Set client cooldown (visual)
    self:SetCooldown("Attack")
    
    print("[InputHandler] ⚔️ Attack queued")
end
```

### Cooldown System

```lua
-- Client-side cooldowns (for UI feedback)
local cooldowns = {
    Attack = 0.5,   -- 0.5 seconds
    Defend = 1.0,   -- 1 second
    Special = 3.0,  -- 3 seconds
}

function InputHandler:CheckCooldown(actionName: string): boolean
    local lastTime = lastActionTime[actionName] or 0
    local cooldown = cooldowns[actionName] or 0
    local now = tick()
    
    if (now - lastTime) < cooldown then
        local remaining = cooldown - (now - lastTime)
        warn(`⏱️ On cooldown ({remaining:.2f}s remaining)`)
        return false
    end
    
    return true
end
```

### Action Queue

```lua
-- Queue for lag compensation
local actionQueue = {} :: {{
    action: string,
    data: any,
    time: number
}}

-- Add to queue
function InputHandler:QueueAction(eventName: string, data: any)
    if #actionQueue >= MAX_QUEUE_SIZE then
        table.remove(actionQueue, 1)  -- Remove oldest
    end
    
    table.insert(actionQueue, {
        action = eventName,
        data = data,
        time = tick(),
    })
end

-- Process queue (30 FPS)
task.spawn(function()
    while true do
        task.wait(0.033)
        
        for _, action in actionQueue do
            NetworkController:Send(action.action, action.data)
        end
        
        table.clear(actionQueue)
    end
end)
```

---

## Input Patterns

### 1. Tap (Single Click)

```lua
-- Player: กด E
-- InputController: Emit "ATTACK"
-- InputHandler: HandleAttack() → Normal attack
```

### 2. Hold (Press and Hold)

```lua
-- Player: กด E ค้างไว้ 0.3+ วินาที
-- InputController: Emit "ATTACKHold"
-- InputHandler: HandleChargedAttack() → Charged attack (1.5x damage)
```

### 3. DoubleTap (Rapid Double Press)

```lua
-- Player: กด E 2 ครั้งเร็วๆ (< 0.3s)
-- InputController: Emit "ATTACKDoubleTap"
-- InputHandler: HandleDashAttack() → Dash attack with knockback
```

### 4. Combo (Sequence)

```lua
-- Player: Attack → Attack → Special (ภายใน 0.5s)
-- InputController: Buffer = ["ATTACK", "ATTACK", "SPECIAL"]
-- InputController: Detect pattern → Emit "ComboTripleStrike"
-- InputHandler: HandleCombo("TripleStrike")
```

### Adding Custom Combos

```lua
-- In InputController:CheckComboPatterns()

if pattern == "Attack-Attack-Special" then
    EventBus:Emit(INPUT_ACTION, "ComboTripleStrike")
elseif pattern == "Defend-Attack-Attack" then
    EventBus:Emit(INPUT_ACTION, "ComboCounterRush")
elseif pattern == "Special-Defend-Special" then
    EventBus:Emit(INPUT_ACTION, "ComboUltimateDefense")
end
```

---

## Configuration

### Input Settings

```lua
-- ReplicatedStorage/Shared/InputSettings.luau

return {
    Bindings = {
        ATTACK = { Enum.KeyCode.E },
        DEFEND = { Enum.KeyCode.Q },
        SPECIAL = { Enum.KeyCode.R },
        -- Add more...
    },
    
    MobileButtonNames = {
        ATTACK = "⚔️ Attack",
        DEFEND = "🛡️ Defend",
        SPECIAL = "✨ Special",
    },
    
    -- Thresholds (optional)
    HoldThreshold = 0.3,
    DoubleTapWindow = 0.3,
    DebounceTime = 0.1,
}
```

### Controller Configuration

```lua
-- In InputController.luau
local DEBOUNCE_TIME = InputSettings.DebounceTime or 0.1
local HOLD_THRESHOLD = InputSettings.HoldThreshold or 0.3
local DOUBLE_TAP_WINDOW = InputSettings.DoubleTapWindow or 0.3
```

---

## Examples

### Example 1: Simple Attack

```lua
-- Player presses "E"

-- InputController:
EventBus:Emit(INPUT_ACTION, "ATTACK")

-- InputHandler:
function InputHandler:OnInputAction("ATTACK")
    self:HandleAttack()
end

function InputHandler:HandleAttack()
    -- Check cooldown
    if not self:CheckCooldown("Attack") then return end
    
    -- Queue action
    self:QueueAction(Events.PLAYER_ATTACK, {
        attackType = "Normal",
        timestamp = tick()
    })
    
    -- Set cooldown
    self:SetCooldown("Attack")
end

-- NetworkController sends to server
```

### Example 2: Charged Attack

```lua
-- Player holds "E" for 0.3+ seconds

-- InputController:
task.delay(0.3, function()
    EventBus:Emit(INPUT_ACTION, "ATTACKHold")
end)

-- InputHandler:
function InputHandler:OnInputAction("ATTACKHold")
    self:HandleChargedAttack()
end

function InputHandler:HandleChargedAttack()
    self:QueueAction(Events.PLAYER_ATTACK, {
        attackType = "Charged",
        damageMultiplier = 1.5,  -- 50% more damage
        timestamp = tick()
    })
end
```

### Example 3: Custom Ability

```lua
-- 1. Add key binding
-- InputSettings.luau
Bindings.TELEPORT = { Enum.KeyCode.T }

-- 2. Handle in InputHandler
function InputHandler:OnInputAction(actionName)
    if actionName == "TELEPORT" then
        self:HandleTeleport()
    end
end

function InputHandler:HandleTeleport()
    if not self:CheckCooldown("Teleport") then return end
    
    local mousePosition = getMouse3DPosition()
    
    self:QueueAction(Events.PLAYER_TELEPORT, {
        targetPosition = mousePosition,
        timestamp = tick()
    })
    
    self:SetCooldown("Teleport")
end

-- 3. Register cooldown
-- In InputHandler
local cooldowns = {
    Attack = 0.5,
    Defend = 1.0,
    Special = 3.0,
    Teleport = 5.0,  -- 5 second cooldown
}
```

### Example 4: Disable Input During Cutscene

```lua
-- Start cutscene
InputController:EnableInput(false)
playAnimationCutscene()

-- End cutscene
task.wait(5)
InputController:EnableInput(true)
```

---

## Debugging

### Enable Debug Logs

```lua
-- In InputController.luau
local DEBUG = true

-- In InputHandler.luau
local DEBUG = true
```

### Check Input State

```lua
-- F9 Console
local state = _G.Controllers.InputController:GetInputState()
print("Enabled:", state.enabled)
print("Holding:", state.holding)
print("Buffer:", state.buffer)
```

### Monitor Events

```lua
-- Listen to all INPUT_ACTION events
EventBus:On(Events.INPUT_ACTION, function(actionName)
    print(`[DEBUG] INPUT_ACTION: {actionName}`)
end)
```

---

## Performance Tips

### 1. Debounce Aggressive Inputs

```lua
-- Prevent spam (already implemented)
local DEBOUNCE_TIME = 0.1  -- Minimum 0.1s between inputs
```

### 2. Clean Up Listeners

```lua
-- When controller is destroyed
InputController:UnbindAll()
```

### 3. Limit Buffer Size

```lua
-- Combo buffer
local maxBufferSize = 5  -- Only keep last 5 inputs
```

### 4. Use Task.defer for Non-urgent

```lua
-- Non-urgent operations
task.defer(function()
    updateUI()
end)
```

---

## Common Issues

### Input not detected?

```lua
-- 1. Check if enabled
local state = InputController:GetInputState()
print(state.enabled)  -- Should be true

-- 2. Check key binding
print(InputSettings.Bindings.ATTACK)  -- Should have keys

-- 3. Check listeners
-- Make sure InputHandler:Start() was called
```

### Cooldown not working?

```lua
-- Client cooldown is visual only
-- Server validates the real cooldown
-- Check server logs for validation
```

### DoubleTap not triggering?

```lua
-- Timing must be < 0.3 seconds
-- Try adjusting DOUBLE_TAP_WINDOW
local DOUBLE_TAP_WINDOW = 0.5  -- More forgiving
```

---

## Advanced: Custom Input Patterns

### Adding Triple Tap

```lua
-- In InputController

local tapCount = {}

if action == "ATTACK" then
    tapCount.ATTACK = (tapCount.ATTACK or 0) + 1
    
    if tapCount.ATTACK >= 3 then
        EventBus:Emit(INPUT_ACTION, "ATTACKTripleTap")
        tapCount.ATTACK = 0
    end
    
    -- Reset after window
    task.delay(0.5, function()
        tapCount.ATTACK = 0
    end)
end
```

### Adding Directional Input

```lua
-- Detect direction + action
local direction = getInputDirection()  -- "UP", "DOWN", "LEFT", "RIGHT"

if action == "ATTACK" then
    if direction == "UP" then
        EventBus:Emit(INPUT_ACTION, "ATTACKUp")  -- Uppercut
    elseif direction == "DOWN" then
        EventBus:Emit(INPUT_ACTION, "ATTACKDown")  -- Slam
    end
end
```

---

## Summary

| Component | Purpose | Output |
|-----------|---------|--------|
| **InputController** | Detect hardware input | INPUT_ACTION events |
| **InputHandler** | Game command logic | Network events |
| **NetworkController** | Send to server | RemoteEvent |

**Flow:**
```
Hardware → InputController → EventBus → InputHandler → NetworkController → Server
```

**Key Features:**
- ✅ 2-layer separation
- ✅ Pattern detection (Hold, DoubleTap, Combo)
- ✅ Debounce protection
- ✅ Client-side cooldown (visual)
- ✅ Action queue (lag compensation)

---

**Version:** 2.0 - Production Grade  
**Last Updated:** 2024  
**Author:** OneShortArena Team
