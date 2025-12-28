# 🏟️ Lobby to Arena Teleport System - Production Guide

## 📋 Table of Contents

- [Overview](#overview)
- [System Architecture](#system-architecture)
- [Flow Diagram](#flow-diagram)
- [Setup Guide](#setup-guide)
- [Creating UI Buttons](#creating-ui-buttons)
- [Service Integration](#service-integration)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## 🎯 Overview

**Lobby to Arena Teleport System** เป็นระบบ Production-grade สำหรับจัดการการเคลื่อนย้ายผู้เล่นระหว่าง Lobby และ Arena

### ✨ Features:

- ✅ **UI Button Integration** - ปุ่มกดเข้า Arena
- ✅ **Event-Driven** - ใช้ EventBus สื่อสาร
- ✅ **State Management** - PlayerStateService ติดตาม state
- ✅ **Smart Spawning** - เลือก spawn point แบบสุ่ม + collision avoidance
- ✅ **Network Security** - Rate limiting, validation
- ✅ **Analytics** - ติดตามสถิติการใช้งาน
- ✅ **Error Handling** - Fallback spawns, timeout handling

---

## 🏗️ System Architecture

### Services Involved:

| Service | Responsibility |
|---------|---------------|
| **LobbyGuiController** | UI button → EventBus |
| **InputHandler** | EventBus → Network request |
| **NetworkController** | Send request to server |
| **NetworkHandler** | Security validation |
| **PlayerStateService** | State: Lobby → Arena |
| **ArenaService** | Spawn player in arena |
| **LobbyService** | Return to lobby |

---

## 📊 Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│              LOBBY TO ARENA TELEPORT FLOW                    │
└─────────────────────────────────────────────────────────────┘

1. Player กดปุ่ม "Play" (UI)
   │
   │  📱 UI Layer
   ▼
2. LobbyGuiController
   ├─> Detect: MouseButton1Click
   ├─> Validate: Cooldown check
   └─> Emit: EventBus:Emit(INPUT_ACTION, "PLAY")
   │
   │  🎮 Input Layer
   ▼
3. InputHandler
   ├─> Listen: EventBus:On(INPUT_ACTION)
   ├─> Route to: HandlePlay()
   ├─> Validate: Player alive? Not in menu?
   └─> Send: NetworkController:Send(PLAYER_REQUEST_TO_ARENA)
   │
   │  🌐 Network Layer
   ▼
4. Server: NetworkHandler
   ├─> Receive: OnServerEvent(PLAYER_REQUEST_TO_ARENA)
   ├─> Security: Rate limit (10 req/5s)
   ├─> Validate: Payload sanitization
   ├─> Check: Event allowlist
   └─> Emit: EventBus:Emit(PLAYER_REQUEST_TO_ARENA, player, data)
   │
   │  🎯 State Management
   ▼
5. Server: PlayerStateService
   ├─> Listen: EventBus:On(PLAYER_REQUEST_TO_ARENA)
   ├─> Validate: CanTransition(player, "Arena")?
   ├─> Update: SetState(player, "Arena")
   ├─> Track: Transition history
   └─> Emit: EventBus:Emit(PLAYER_STATE_CHANGED_INTERNAL)
   │
   │  🏟️ Arena Management
   ▼
6. Server: ArenaService
   ├─> Listen: EventBus:On(PLAYER_REQUEST_TO_ARENA)
   ├─> Get Spawn: GetRandomArenaSpawn()
   │   ├─> Find: Empty spawn point
   │   ├─> Check: isAreaSafe()
   │   └─> Fallback: If all occupied
   ├─> Teleport: character.HumanoidRootPart.CFrame
   ├─> Track: Analytics (totalSpawns++)
   └─> Send: NetworkHandler:SendToClient(PLAYER_TELEPORTED_TO_ARENA)
   │
   │  ✅ Response
   ▼
7. Client: NetworkController
   ├─> Receive: OnClientEvent(PLAYER_TELEPORTED_TO_ARENA)
   ├─> Parse: {success = true, timestamp = ...}
   ├─> Emit: EventBus:Emit(PLAYER_TELEPORTED_TO_ARENA)
   └─> UI: Update button state, show notification
```

---

## 🛠️ Setup Guide

### Step 1: Create Workspace Structure

ใน Roblox Studio, สร้างโครงสร้างดังนี้:

```
Workspace/
├── LobbySpawns/ (Model/Folder)
│   └── LobbySpawns/ (Folder)
│       ├── SpawnLocation_1 (Part)
│       ├── SpawnLocation_2 (Part)
│       └── SpawnLocation_3 (Part)
│
└── ArenaBoundary/ (Model/Folder)
    └── ArenaSpawns/ (Folder)
        ├── SpawnLocation_1 (Part)
        ├── SpawnLocation_2 (Part)
        └── SpawnLocation_3 (Part)
```

**Properties สำหรับ Spawn Parts:**

```lua
-- Lobby Spawns
Size = Vector3.new(4, 1, 4)
Transparency = 1
CanCollide = false
Anchored = true
Color = Color3.fromRGB(0, 255, 0)  -- Green

-- Arena Spawns
Size = Vector3.new(4, 1, 4)
Transparency = 1
CanCollide = false
Anchored = true
Color = Color3.fromRGB(255, 0, 0)  -- Red
```

---

### Step 2: Create UI Buttons

#### A. สร้าง ScreenGui

1. ใน **StarterGui**, สร้าง **ScreenGui** ชื่อ `LobbyGui`
2. Properties:
   - `ResetOnSpawn = false`
   - `ZIndexBehavior = Sibling`

#### B. สร้าง Play Button

1. ใน **LobbyGui**, Insert **TextButton** ชื่อ `PlayButton`
2. Properties:

```lua
-- Position & Size
Size = UDim2.new(0, 200, 0, 60)
Position = UDim2.new(0.5, -100, 0.7, -30)
AnchorPoint = Vector2.new(0.5, 0.5)

-- Appearance
Text = "▶ Play"
TextScaled = true
Font = Enum.Font.GothamBold
TextColor3 = Color3.fromRGB(255, 255, 255)
BackgroundColor3 = Color3.fromRGB(0, 170, 0)
BorderSizePixel = 0

-- Corner Radius (Optional)
-- Add UICorner with CornerRadius = UDim.new(0, 12)
```

#### C. สร้าง Cancel Button (Optional)

```lua
Size = UDim2.new(0, 200, 0, 60)
Position = UDim2.new(0.5, -100, 0.7, 40)
AnchorPoint = Vector2.new(0.5, 0.5)

Text = "◀ Back to Lobby"
BackgroundColor3 = Color3.fromRGB(170, 0, 0)
```

---

### Step 3: Create LobbyGuiController

````lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\Controllers\LobbyGuiController.luau
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)

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
            warn(`[LobbyGuiController] ⏱️ {actionName} on cooldown`)
            return
        end
        
        print(`[LobbyGuiController] 🖱️ Button clicked: {actionName}`)
        EventBus:Emit(Events.INPUT_ACTION, actionName)
        
        -- Visual feedback
        local originalColor = button.BackgroundColor3
        button.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
        button.Text = "..."
        
        buttonCooldowns[button] = true
        
        task.delay(cooldownTime, function()
            buttonCooldowns[button] = false
            button.BackgroundColor3 = originalColor
            button.Text = actionName == "PLAY" and "▶ Play" or "◀ Back to Lobby"
        end)
    end)
    
    -- Hover effects
    button.MouseEnter:Connect(function()
        if not buttonCooldowns[button] then
            button.BackgroundColor3 = button.BackgroundColor3:Lerp(Color3.new(1, 1, 1), 0.3)
        end
    end)
    
    button.MouseLeave:Connect(function()
        if not buttonCooldowns[button] then
            button.BackgroundColor3 = actionName == "PLAY" 
                and Color3.fromRGB(0, 170, 0) 
                or Color3.fromRGB(170, 0, 0)
        end
    end)
end

function LobbyGuiController:Init()
    lobbyGui = playerGui:WaitForChild("LobbyGui") :: ScreenGui
    playButton = lobbyGui:WaitForChild("PlayButton") :: TextButton
    
    -- Cancel button is optional
    local cancelBtn = lobbyGui:FindFirstChild("CancelButton")
    if cancelBtn and cancelBtn:IsA("TextButton") then
        cancelButton = cancelBtn
    end
    
    print("[LobbyGuiController] 🎨 Initialized")
end

function LobbyGuiController:Start()
    -- Connect buttons to EventBus
    connectButton(playButton, "PLAY", 1.0)
    
    if cancelButton then
        connectButton(cancelButton, "CANCEL", 0.5)
    end
    
    print("[LobbyGuiController] 🚀 Started - Buttons connected")
end

return LobbyGuiController
````

---

### Step 4: Update InputSettings

Add PLAY and CANCEL actions:

````lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ReplicatedStorage\Shared\InputSettings.luau
--!strict

return {
    Bindings = {
        -- ...existing bindings...
        
        -- UI Actions (Keyboard fallback)
        PLAY = {Enum.KeyCode.Return},    -- Enter key
        CANCEL = {Enum.KeyCode.Escape},  -- Escape key
    },
    
    MobileButtonNames = {
        -- ...existing mobile buttons...
        -- UI buttons don't need mobile buttons (use GUI instead)
    },
}
````

---

### Step 5: Update InputHandler

Add handlers for PLAY and CANCEL:

````lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\Controllers\InputHandler.luau

-- ...existing code...

function InputHandler:Start()
    EventBus:On(Events.INPUT_ACTION, function(actionName: string)
        -- ...existing handlers...
        
        if actionName == "PLAY" then
            self:HandlePlay()
        elseif actionName == "CANCEL" then
            self:HandleCancel()
        end
    end)
    
    print("[InputHandler] Started")
end

function InputHandler:HandlePlay()
    print("[InputHandler] ▶️ Play button pressed")
    NetworkController:Send(Events.PLAYER_REQUEST_TO_ARENA, {
        action = "join",
        timestamp = tick()
    })
end

function InputHandler:HandleCancel()
    print("[InputHandler] ⏸️ Cancel button pressed")
    NetworkController:Send(Events.PLAYER_REQUEST_TO_LOBBY, {
        action = "cancel",
        timestamp = tick()
    })
end

-- ...existing code...
````

---

### Step 6: Update Events.luau

Add missing events:

````lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ReplicatedStorage\Shared\Events.luau
--!strict

return {
    -- ...existing events...
    
    -- Player State Events
    PLAYER_REQUEST_TO_ARENA = "PlayerRequestToArena",
    PLAYER_REQUEST_TO_LOBBY = "PlayerRequestToLobby",
    PLAYER_REQUEST_TO_SPECTATE = "PlayerRequestToSpectate",
    PLAYER_STATE_CHANGED = "PlayerStateChanged",
    PLAYER_STATE_CHANGED_INTERNAL = "PlayerStateChangedInternal",
    
    -- Arena Events
    PLAYER_TELEPORTED_TO_ARENA = "PlayerTeleportedToArena",
    PLAYER_TELEPORTED_TO_LOBBY = "PlayerTeleportedToLobby",
    
    -- ...existing events...
}
````

---

## 🧪 Testing

### Test Checklist:

#### 1. **Visual Test**
```
✅ ปุ่ม "Play" แสดงผลถูกต้อง
✅ ปุ่ม hover ได้ (สีเปลี่ยน)
✅ ปุ่ม click ได้ (cooldown ทำงาน)
```

#### 2. **Client Console (F9)**
```
Expected Output:
[LobbyGuiController] 🖱️ Button clicked: PLAY
[InputHandler] ▶️ Play button pressed
[NetworkController] 📤 Sending: PLAYER_REQUEST_TO_ARENA
```

#### 3. **Server Console**
```
Expected Output:
[NetworkHandler] 📨 Received: PLAYER_REQUEST_TO_ARENA from sukpatzqza
[PlayerStateService] ✅ sukpatzqza joined Arena
[ArenaService] ✅ Spawned sukpatzqza in Arena at 50, 103, 30
```

#### 4. **In-Game Test**
```
✅ กดปุ่ม → ตัวละครถูก teleport ไป Arena
✅ Spawn point สุ่มได้ (ไม่ spawn ที่เดิมทุกครั้ง)
✅ ไม่ spawn ซ้อนกับผู้เล่นอื่น
✅ กลับ Lobby ได้ (ถ้ามีปุ่ม Cancel)
```

---

## 🐛 Troubleshooting

### Problem 1: Button Not Clicking

**Symptoms:**
```
- กดปุ่มแล้วไม่มี response
- Console ไม่มี log
```

**Solutions:**
```lua
-- Check 1: Button properties
button.Active = true
button.Interactable = true

-- Check 2: ZIndex
lobbyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
button.ZIndex = 10  -- Higher than other UI

-- Check 3: Parent order
-- LobbyGui must be in PlayerGui, not StarterGui
```

---

### Problem 2: "Arena boundary folder not found"

**Symptoms:**
```
[ArenaService] ❌ Arena boundary folder not found!
```

**Solutions:**
```lua
-- Fix 1: Check folder name (case-sensitive)
-- Must be: "ArenaBoundary" (capital B)

-- Fix 2: Check hierarchy
Workspace/
└── ArenaBoundary/
    └── ArenaSpawns/

-- Fix 3: Wait time
-- Increase timeout in ArenaService:
local arenabound = Workspace:WaitForChild("ArenaBoundary", 20)  -- 20s
```

---

### Problem 3: Player Not Spawning

**Symptoms:**
```
[ArenaService] ❌ No HumanoidRootPart for sukpatzqza
```

**Solutions:**
```lua
-- Check character exists
if not player.Character then
    player:LoadCharacter()  -- Force respawn
end

-- Check HumanoidRootPart
local hrp = character:FindFirstChild("HumanoidRootPart")
if not hrp then
    warn("Character malformed!")
end
```

---

## 📝 Best Practices

### ✅ DO (ควรทำ)

```lua
-- 1. ใช้ cooldown ป้องกัน spam
connectButton(playButton, "PLAY", 1.0)  -- 1 วินาที

-- 2. Visual feedback
button.BackgroundColor3 = Color3.fromRGB(100, 100, 100)  -- Gray during cooldown

-- 3. Error handling
if not success then
    warn("Failed to join arena!")
    -- Show notification to user
end

-- 4. Analytics
analytics.buttonClicks += 1
analytics.lastClickTime = os.clock()
```

### ❌ DON'T (ไม่ควรทำ)

```lua
-- 1. อย่าลืม cooldown
button.MouseButton1Click:Connect(function()
    EventBus:Emit(Events.INPUT_ACTION, "PLAY")  -- ❌ Spammable!
end)

-- 2. อย่าใช้ string literal
EventBus:Emit("PlayerRequestToArena", data)  -- ❌ Typo-prone
EventBus:Emit(Events.PLAYER_REQUEST_TO_ARENA, data)  -- ✅ Type-safe

-- 3. อย่า teleport โดยตรง (bypass validation)
player.Character.HumanoidRootPart.CFrame = arenaSpawn.CFrame  -- ❌
ArenaService:SpawnPlayerInArena(player)  -- ✅ Use service
```

---

## 🎯 Summary

### Complete Flow:

```
UI Button → EventBus → InputHandler → Network → Server Validation 
→ State Change → Arena Spawn → Response → Client Update
```

### Key Components:

| Component | File | Purpose |
|-----------|------|---------|
| **UI** | StarterGui/LobbyGui | Player clicks button |
| **Controller** | LobbyGuiController.luau | Button → EventBus |
| **Handler** | InputHandler.luau | EventBus → Network |
| **Network** | NetworkController.luau | Client-Server comm |
| **Security** | NetworkHandler.luau | Validation |
| **State** | PlayerStateService.luau | Lobby → Arena |
| **Spawn** | ArenaService.luau | Teleport player |

### Files Created/Modified:

```
✅ StarterGui/LobbyGui (UI)
✅ LobbyGuiController.luau (New)
✅ InputHandler.luau (Modified)
✅ InputSettings.luau (Modified)
✅ Events.luau (Modified)
✅ ArenaService.luau (New)
✅ PlayerStateService.luau (Existing)
```

---

## 📚 Related Documentation

- [Architecture Overview](./deps.md)
- [EventBus Guide](./EventBus-Guide.md)
- [PlayerStateService Guide](./PlayerStateService-Guide.md)
- [Network Security](./Network-Security.md)

---

**Version:** 1.0  
**Last Updated:** 2024  
**Status:** Production Ready ✅  
**Author:** OneShortArena Team