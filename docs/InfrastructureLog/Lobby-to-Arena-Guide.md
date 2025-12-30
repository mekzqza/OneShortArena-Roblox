# 🏟️ Lobby to Arena Teleport System - Production Guide

## 📋 Version Info

| Component | Version | Status |
|-----------|---------|--------|
| System | 2.0 | ✅ Production Ready |
| Security | P0 Fixed | ✅ Hardened |
| NetworkConfig | 1.0 | ✅ Centralized |

---

## 🎯 Overview

**Lobby to Arena Teleport System** เป็นระบบ Production-grade สำหรับจัดการการเคลื่อนย้ายผู้เล่นระหว่าง Lobby และ Arena

### ✨ Features:

- ✅ **UI Button Integration** - ปุ่มกดเข้า Arena พร้อม cooldown protection
- ✅ **Event-Driven** - ใช้ EventBus สื่อสาร
- ✅ **State Management** - PlayerStateService ติดตาม state พร้อม transition locks
- ✅ **Smart Spawning** - เลือก spawn point แบบสุ่ม + collision avoidance
- ✅ **Network Security** - Rate limiting, validation, anti-spam
- ✅ **P0 Security Fixes** - Race condition protection, exploit prevention
- ✅ **Analytics** - ติดตามสถิติการใช้งาน
- ✅ **Error Handling** - Fallback spawns, timeout handling

---

## 🏗️ System Architecture

### Services Involved:

| Service | Responsibility | Config |
|---------|---------------|--------|
| **LobbyGuiController** | UI button → EventBus | 1s cooldown |
| **InputHandler** | EventBus → Network | Validation |
| **NetworkController** | Send to server | Retry/ACK |
| **NetworkHandler** | Security validation | NetworkConfig |
| **PlayerStateService** | State management | 2s cooldown |
| **ArenaService** | Arena spawning | 5s cooldown |
| **LobbyService** | Lobby spawning | State-based |

### Rate Limits (from NetworkConfig):

```lua
EventRateLimits = {
    PlayerRequestToArena = {rate = 1, window = 5},
    PlayerRequestToLobby = {rate = 1, window = 5},
}
```

---

## 📊 Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│         LOBBY TO ARENA TELEPORT FLOW (P0 SECURED)            │
└─────────────────────────────────────────────────────────────┘

1. Player กดปุ่ม "Play" (UI)
   │
   │  📱 UI Layer (P0: Cooldown Protection)
   ▼
2. LobbyGuiController
   ├─> Detect: MouseButton1Click
   ├─> ✅ P0 Check: Button cooldown (1s)
   │   └─> if on cooldown → block, don't emit
   ├─> Set cooldown flag
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
   │  🌐 Network Layer (P0: Rate Limiting)
   ▼
4. Server: NetworkHandler
   ├─> Receive: OnServerEvent(PLAYER_REQUEST_TO_ARENA)
   ├─> ✅ P0 Security:
   │   ├─> Rate limit check (10 req/5s per player)
   │   ├─> Anti-replay (message ID tracking)
   │   ├─> Payload sanitization
   │   └─> Event allowlist validation
   └─> Emit: EventBus:Emit(PLAYER_REQUEST_TO_ARENA, player, data)
   │
   │  🎯 State Management (P0: Lock Protection)
   ▼
5. Server: PlayerStateService
   ├─> Listen: EventBus:On(PLAYER_REQUEST_TO_ARENA)
   ├─> ✅ P0 Validations:
   │   ├─> Check cooldown (2s server-side)
   │   ├─> Check transition lock (prevent race condition)
   │   └─> Validate state transition (Lobby → Arena allowed?)
   ├─> Acquire transition lock (atomic)
   ├─> Update: SetState(player, "Arena")
   │   ├─> Validate transition rules
   │   ├─> Set cooldown (2s)
   │   └─> Update analytics
   ├─> Release transition lock
   └─> Emit: EventBus:Emit(PLAYER_STATE_CHANGED_INTERNAL)
   │
   │  🏟️ Arena Management (P0: Spawn Validation)
   ▼
6. Server: ArenaService
   ├─> Listen: EventBus:On(PLAYER_STATE_CHANGED_INTERNAL)
   ├─> ✅ Only if newState == "Arena"
   ├─> ✅ P0 Validations:
   │   ├─> Teleport cooldown (5s)
   │   ├─> Combat check (can't teleport while in combat)
   │   ├─> Character exists
   │   └─> Player is alive
   ├─> Get Spawn: GetRandomArenaSpawn()
   │   ├─> Find: Empty spawn point
   │   ├─> Check: isAreaSafe()
   │   └─> Fallback: If all occupied
   ├─> Teleport: character.HumanoidRootPart.CFrame
   ├─> Set teleport cooldown
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

## 🔐 Security Layers

```
Layer 1: UI Cooldown (1s)
    └── LobbyGuiController.buttonCooldowns

Layer 2: Per-Event Rate Limit
    └── NetworkConfig.EventRateLimits["PlayerRequestToArena"]
    └── 1 request per 5 seconds

Layer 3: Global Rate Limit
    └── NetworkConfig.GlobalRateLimit = 10 per 5s

Layer 4: Transition Lock
    └── PlayerStateService.transitionLocks[userId]

Layer 5: Transition Cooldown (2s)
    └── PlayerStateService.transitionCooldowns[userId]

Layer 6: Teleport Cooldown (5s)
    └── ArenaService.teleportCooldowns[userId]

Layer 7: Combat Check (5s)
    └── ArenaService.playersInCombat[userId]
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

-- ✅ P0: Cooldown tracking
local buttonCooldowns = {} :: {[TextButton]: boolean}

local function connectButton(button: TextButton, actionName: string, cooldownTime: number?)
    cooldownTime = cooldownTime or 1.0
    
    button.MouseButton1Click:Connect(function()
        -- ✅ P0 FIX: Check cooldown BEFORE emitting event
        if buttonCooldowns[button] then
            warn(`[LobbyGuiController] ⏱️ {actionName} on cooldown (ignored)`)
            return  -- Don't emit event!
        end
        
        print(`[LobbyGuiController] 🖱️ Button clicked: {actionName}`)
        
        -- ✅ P0: Set cooldown BEFORE emit
        buttonCooldowns[button] = true
        
        -- Emit event AFTER cooldown check
        EventBus:Emit(Events.INPUT_ACTION, actionName)
        
        -- Visual feedback
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
    -- ✅ P0: Cooldown protections
    connectButton(playButton, "PLAY", 1.0)  -- 1 second cooldown
    
    if cancelButton then
        connectButton(cancelButton, "CANCEL", 0.5)
    end
    
    print("[LobbyGuiController] 🚀 Started - Buttons connected with cooldown protection")
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
        
        -- ✅ P0: Handle PLAY and CANCEL
        if actionName == "PLAY" then
            self:HandlePlay()
        elseif actionName == "CANCEL" then
            self:HandleCancel()
        else
            warn(`[InputHandler] ⚠️ Unhandled action: {actionName}`)
        end
    end)
    
    print("[InputHandler] ✅ Started")
end

-- ✅ P0: PLAY handler
function InputHandler:HandlePlay()
    print("[InputHandler] ▶️ Play button pressed")
    
    -- Validate before sending
    local player = Players.LocalPlayer
    if not player.Character or player.Character.Humanoid.Health <= 0 then
        warn("[InputHandler] Cannot join arena: Player is dead")
        return
    end
    
    -- Send to server
    NetworkController:Send(Events.PLAYER_REQUEST_TO_ARENA, {
        action = "join",
        timestamp = tick()
    })
end

-- ✅ P0: CANCEL handler
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

### Test Scenarios with P0 Validation:

#### ✅ Scenario 1: Normal Click (Expected: Success)

**Actions:**
```
1. Player กดปุ่ม "Play"
2. รอ 2 วินาที
3. ตัวละครถูก teleport ไป Arena
```

**Expected Output:**
```
[LobbyGuiController] 🖱️ Button clicked: PLAY
[InputHandler] ▶️ Play button pressed
[NetworkController] 📤 Sending: PLAYER_REQUEST_TO_ARENA
[PlayerStateService] ✅ sukpatzqza joined Arena
[ArenaService] sukpatzqza state changed to Arena, spawning...
[ArenaService] ✅ sukpatzqza spawned in Arena at -880, 24.5, 30
```

---

#### ✅ Scenario 2: Spam Click (Expected: Blocked by Cooldown)

**Actions:**
```
1. กด "Play" ครั้งที่ 1
2. กด "Play" ครั้งที่ 2 ทันที (0.1s later)
3. กด "Play" ครั้งที่ 3 ทันที (0.2s later)
```

**Expected Output:**
```
Click 1:
[LobbyGuiController] 🖱️ Button clicked: PLAY
[InputHandler] ▶️ Play button pressed
[NetworkController] 📤 Sending...

Click 2 (0.1s later):
[LobbyGuiController] ⏱️ PLAY on cooldown (ignored)
(ไม่ส่ง event! ✅)

Click 3 (0.2s later):
[LobbyGuiController] ⏱️ PLAY on cooldown (ignored)
(ไม่ส่ง event! ✅)
```

---

## 📚 Related Documentation

- [deps.md](./deps.md) - Architecture overview
- [Risk-Assessment.md](./Risk-Assessment.md) - Security audit
- [NetworkConfig-Guide.md](./NetworkConfig-Guide.md) - Rate limits

---

**Version:** 2.0 - P0 Security Fixes Applied  
**Last Updated:** 2024  
**Status:** Production Ready ✅  
**Author:** OneShortArena Team