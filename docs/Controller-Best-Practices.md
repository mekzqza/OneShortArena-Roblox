# 🎮 Controller Best Practices - Production Guide

## 📋 Overview

เอกสารนี้อธิบายวิธีการเขียน Controller ระดับ Production ที่:
- ✅ ไม่พึ่งพา file path
- ✅ ทำงานได้แม้ย้ายไฟล์
- ✅ Debug ง่าย
- ✅ Test ง่าย
- ✅ Maintainable

---

## ❌ วิธีที่ผิด (อย่าทำแบบนี้!)

### ❌ Bad Practice #1: Direct Path Require

```lua
-- filepath: AbilityController.luau

-- ❌ DON'T DO THIS!
local NetworkController = require(script.Parent.Parent.Core.NetworkController)
local InputHandler = require(script.Parent.Parent.Inputs.InputHandler)

-- ปัญหา:
-- 1. พึ่งพา folder structure
-- 2. ย้ายไฟล์แล้วพัง
-- 3. Refactor ยาก
-- 4. Test ยาก (ต้อง mock path)
```

---

### ❌ Bad Practice #2: ReplicatedStorage Path

```lua
-- ❌ DON'T DO THIS!
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Controllers = ReplicatedStorage.Controllers -- ❌ ไม่มี folder นี้!
```

---

## ✅ วิธีที่ถูกต้อง (Production Grade)

### ✅ Method 1: ControllersByCategory (แนะนำ)

```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\Gameplay\AbilityController.luau
--!strict

local Players = game:GetService("Players")

-- ✅ CORRECT: Use Controller Registry
local Controllers = _G.ControllersByCategory

-- ✅ Get dependencies by category
local NetworkController = Controllers.Core.NetworkController
local InputHandler = Controllers.Inputs.InputHandler

export type AbilityController = {
    Init: (self: AbilityController) -> (),
    Start: (self: AbilityController) -> (),
    CastAbility: (self: AbilityController, abilityName: string) -> (),
}

local AbilityController = {} :: AbilityController

function AbilityController:Init()
    print("[AbilityController] ✨ Initialized")
end

function AbilityController:Start()
    -- ✅ Dependencies are guaranteed to exist
    -- because Init.client loads in dependency order
    
    print("[AbilityController] 🚀 Started")
end

function AbilityController:CastAbility(abilityName: string)
    -- Use NetworkController to send to server
    NetworkController:Send("CastAbility", {
        ability = abilityName,
        timestamp = tick()
    })
end

return AbilityController
```

**ข้อดี:**
- ✅ ไม่สน path structure
- ✅ อ่านง่าย (รู้ทันทีว่าอยู่ category ไหน)
- ✅ Autocomplete ทำงาน (ถ้า type ถูกต้อง)
- ✅ Refactor-safe

---

### ✅ Method 2: Flat Qualified Keys (Debug-Friendly)

```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\UI\LobbyGuiController.luau
--!strict

-- ✅ CORRECT: Use flat qualified keys
local Controllers = _G.Controllers

local InputHandler = Controllers["Inputs.InputHandler"]
local NetworkController = Controllers["Core.NetworkController"]

-- ...controller code...
```

**ข้อดี:**
- ✅ Debug ง่าย (ใช้ใน console ได้)
- ✅ Grep ง่าย (search "Core.NetworkController")
- ✅ Tool-friendly

---

## 🎯 Complete Example: LobbyGuiController

```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\UI\LobbyGuiController.luau
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ✅ Get shared modules (Events, EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)

-- ✅ Get controllers via Registry (NOT via path!)
local Controllers = _G.ControllersByCategory

export type LobbyGuiController = {
    Init: (self: LobbyGuiController) -> (),
    Start: (self: LobbyGuiController) -> (),
}

local LobbyGuiController = {} :: LobbyGuiController

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local lobbyGui: ScreenGui? = nil
local playButton: TextButton? = nil
local cancelButton: TextButton? = nil

local buttonCooldowns = {} :: {[TextButton]: boolean}

local function connectButton(button: TextButton, actionName: string, cooldownTime: number?)
    cooldownTime = cooldownTime or 1.0
    
    button.MouseButton1Click:Connect(function()
        if buttonCooldowns[button] then
            warn(`[LobbyGuiController] ⏱️ {actionName} on cooldown (ignored)`)
            return
        end
        
        print(`[LobbyGuiController] 🖼️ Button clicked: {actionName}`)
        
        buttonCooldowns[button] = true
        
        -- ✅ Emit event via EventBus (not NetworkController!)
        -- InputHandler will pick it up and send to server
        EventBus:Emit(Events.INPUT_ACTION, actionName)
        
        local originalColor = button.BackgroundColor3
        local originalText = button.Text
        button.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
        button.Text = "..."
        
        task.delay(cooldownTime, function()
            buttonCooldowns[button] = false
            button.BackgroundColor3 = originalColor
            button.Text = originalText
        end)
    end)
end

function LobbyGuiController:Init()
    lobbyGui = playerGui:WaitForChild("LobbyGui") :: ScreenGui
    playButton = lobbyGui:WaitForChild("PlayButton") :: TextButton
    
    local cancelBtn = lobbyGui:FindFirstChild("CancelButton")
    if cancelBtn and cancelBtn:IsA("TextButton") then
        cancelButton = cancelBtn
    end
    
    print("[LobbyGuiController] 🎨 Initialized")
end

function LobbyGuiController:Start()
    connectButton(playButton, "PLAY", 1.0)
    
    if cancelButton then
        connectButton(cancelButton, "CANCEL", 0.5)
    end
    
    print("[LobbyGuiController] 🚀 Started - Buttons connected")
end

return LobbyGuiController
```

---

## 🔧 How to Access Controllers

### In Studio Console (F9)

```lua
-- List all controllers
for key, controller in _G.Controllers do
    print(key)
end

-- Output:
-- Core.NetworkController
-- Inputs.InputController
-- Inputs.InputHandler
-- UI.LobbyGuiController
-- Gameplay.AbilityController

-- Access specific controller
_G.Controllers["Core.NetworkController"]
_G.ControllersByCategory.Core.NetworkController

-- Call methods
_G.Controllers["Core.NetworkController"]:Send("Test", {})
```

---

## 📊 Dependency Rules

### ✅ Allowed Dependencies

```
┌─────────────────────────────────────────────────────────────┐
│           Controller Dependency Rules                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ✅ Controllers → Shared Modules (Events, EventBus)        │
│  ✅ Controllers → Other Controllers (via Registry)         │
│  ✅ Controllers → Services (ReplicatedStorage)             │
│                                                             │
│  ❌ Controllers → Direct Path Requires                     │
│  ❌ Controllers → _G pollution (except read)               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎓 Best Practices

### ✅ DO

```lua
-- ✅ Use Registry
local Controllers = _G.ControllersByCategory

-- ✅ Get shared modules normally
local Events = require(ReplicatedStorage.Shared.Events)

-- ✅ Document dependencies clearly
-- Dependencies:
--   - NetworkController (Core)
--   - InputHandler (Inputs)

-- ✅ Check existence (optional, for safety)
local NetworkController = Controllers.Core.NetworkController
assert(NetworkController, "NetworkController not found!")
```

---

### ❌ DON'T

```lua
-- ❌ Direct path require
local NetworkController = require(script.Parent.Parent.Core.NetworkController)

-- ❌ Pollute _G
_G.MyController = MyController

-- ❌ Circular dependencies
-- AbilityController → InputHandler → AbilityController (loop!)
```

---

## 🧪 Testing

### Test with Mock Registry

```lua
-- Test file
local function createMockControllers()
    return {
        Core = {
            NetworkController = {
                Send = function(self, event, data)
                    print("Mock send:", event, data)
                end
            }
        },
        Inputs = {
            InputHandler = {
                HandleInput = function(self, action)
                    print("Mock input:", action)
                end
            }
        }
    }
end

-- Inject mock
_G.ControllersByCategory = createMockControllers()

-- Now test your controller
local AbilityController = require(...)
AbilityController:Init()
AbilityController:Start()
```

---

## 📝 Migration Guide

### From Old (Direct Require)

```lua
-- ❌ Old
local NetworkController = require(script.Parent.Parent.Core.NetworkController)
```

### To New (Registry)

```lua
-- ✅ New
local Controllers = _G.ControllersByCategory
local NetworkController = Controllers.Core.NetworkController
```

---

## 🎯 Summary

| Aspect | Old Way | New Way |
|--------|---------|---------|
| **Dependency** | `require(path)` | `_G.ControllersByCategory` |
| **Refactor-safe** | ❌ No | ✅ Yes |
| **Test-friendly** | ❌ No | ✅ Yes |
| **Debug-friendly** | ❌ No | ✅ Yes |
| **Path-agnostic** | ❌ No | ✅ Yes |

---

**Version:** 1.0  
**Author:** OneShortArena Team  
**Purpose:** Production Controller Best Practices
