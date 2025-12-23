# 🚀 Quick Reference Guide

## 📌 Most Important Files

| File | Purpose | When to Edit |
|------|---------|--------------|
| `Events.luau` | Event name registry | Adding new events |
| `Init.server.luau` | Server startup | Adding new services |
| `Init.client.luau` | Client startup | Adding new controllers |
| `NetworkHandler.luau` | Network security | Changing security rules |

---

## 🎮 Input System Quick Reference

### Add New Input Action

**1. Add to InputSettings.luau:**
```lua
Bindings = {
    MyAction = { Enum.KeyCode.F },
},
MobileButtonNames = {
    MyAction = "🎯 My Action",
},
```

**2. Add to Events.luau:**
```lua
PLAYER_MY_ACTION = "PlayerMyAction",
```

**3. Handle in DemoController:**
```lua
elseif actionName == "MyAction" then
    self:SendMyAction()

function DemoController:SendMyAction()
    NetworkController:Send(Events.PLAYER_MY_ACTION, {data = "value"})
end
```

**4. Process in DemoService:**
```lua
-- Init
NetworkHandler:AllowClientEvent(Events.PLAYER_MY_ACTION)

-- Start
EventBus:On(Events.PLAYER_MY_ACTION, function(player, data)
    -- Process action
end)
```

---

### Input Flow Cheat Sheet

| Want to... | Use | Example |
|------------|-----|---------|
| Add keyboard key | InputSettings.Bindings | `MyAction = { Enum.KeyCode.F }` |
| Add mobile button | InputSettings.MobileButtonNames | `MyAction = "🎯 Do Something"` |
| Send to server | NetworkController:Send() | `NetworkController:Send(Events.MY_ACTION, data)` |
| Receive on server | EventBus:On() | `EventBus:On(Events.MY_ACTION, handler)` |
| Validate action | DemoService | Check cooldown, resources, state |

---

### Common Input Patterns

**Pattern 1: Simple Button Press**
```lua
-- Client
function DemoController:OnInputAction(actionName)
    if actionName == "Jump" then
        NetworkController:Send(Events.PLAYER_JUMP)
    end
end

-- Server
EventBus:On(Events.PLAYER_JUMP, function(player)
    if canJump(player) then
        applyJumpForce(player)
    end
end)
```

**Pattern 2: Action with Data**
```lua
-- Client
function DemoController:SendAttack()
    NetworkController:Send(Events.PLAYER_ATTACK, {
        timestamp = tick(),
        targetPosition = getMouseHit(),
    })
end

-- Server
EventBus:On(Events.PLAYER_ATTACK, function(player, data)
    if validateAttack(player, data) then
        dealDamage(player, data.targetPosition)
    end
end)
```

**Pattern 3: Cooldown Check**
```lua
-- Server
local lastActionTime = {}
local COOLDOWN = 1.0

EventBus:On(Events.PLAYER_SKILL, function(player, data)
    local userId = player.UserId
    local now = tick()
    
    if (now - (lastActionTime[userId] or 0)) < COOLDOWN then
        NetworkHandler:SendToClient(player, Events.ACTION_FAILED, "On cooldown")
        return
    end
    
    lastActionTime[userId] = now
    -- Process skill
end)
```

---

### Testing Input System

```lua
-- Command Bar (F9)

-- Check if InputController is loaded
print(game.StarterPlayer.StarterPlayerScripts.Controllers.InputController)

-- Manually trigger action
_G.DemoController:SendAttack()

-- Check bindings
local InputSettings = require(game.ReplicatedStorage.Shared.InputSettings)
for action, keys in pairs(InputSettings.Bindings) do
    print(action, keys)
end
```

---

### Input Debugging Checklist

**❌ Key press not detected:**
- [ ] InputSettings.luau has the key binding
- [ ] InputController:BindAllActions() was called
- [ ] Check F9 console for errors
- [ ] Try different key (some are reserved)

**❌ Action not sent to server:**
- [ ] DemoController has handler for that action
- [ ] NetworkController is initialized
- [ ] Event exists in Events.luau
- [ ] Check network console logs

**❌ Server not responding:**
- [ ] Event is in AllowClientEvent whitelist
- [ ] DemoService has EventBus:On() listener
- [ ] Rate limit not exceeded (max 10 in 5 sec)
- [ ] Check server console for errors

---

## 🎯 Common Tasks

### Task 1: Add New Event

**1. Add to Events.luau:**
```lua
MY_NEW_EVENT = "MyNewEvent",
```

**2. Allow in NetworkHandler (if client→server):**
```lua
NetworkHandler:AllowClientEvent(Events.MY_NEW_EVENT)
```

**3. Listen in Service:**
```lua
EventBus:On(Events.MY_NEW_EVENT, function(player, data)
    -- Handle event
end)
```

---

### Task 2: Send Data to Client

**From any Service:**
```lua
-- Send to specific player
NetworkHandler:SendToClient(player, Events.UPDATE_UI, {score = 100})

-- Broadcast to all players
NetworkHandler:Broadcast(Events.GAME_STARTED, {round = 1})
```

---

### Task 3: Send Data to Server

**From any Controller:**
```lua
NetworkController:Send(Events.BUTTON_CLICKED, {buttonId = "Play"})
```

---

### Task 4: Create New Service

**1. Create file:** `Services/MyService.luau`

**2. Use template:**
```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local NetworkHandler = require(ServerScriptService.Services.NetworkHandler)

export type MyService = {
    Init: (self: MyService) -> (),
    Start: (self: MyService) -> (),
}

local MyService: MyService = {}

function MyService:Init()
    print("[MyService] Initialized")
end

function MyService:Start()
    EventBus:On(Events.MY_EVENT, function(player, data)
        -- Handle event
    end)
    print("[MyService] Started")
end

return MyService
```

**3. Add to Init.server.luau:**
```lua
local MyService = require(Services.MyService)
-- ...
MyService:Init()
-- ...
MyService:Start()
```

---

### Task 5: Add Input Action

**1. Define in InputSettings.luau:**
```lua
return {
    Bindings = {
        MyNewAction = { Enum.KeyCode.G, Enum.KeyCode.ButtonX },
    },
    MobileButtonNames = {
        MyNewAction = "⚡ New Action",
    },
}
```

**2. Add event to Events.luau:**
```lua
PLAYER_NEW_ACTION = "PlayerNewAction",
```

**3. Handle in DemoController.luau:**
```lua
function DemoController:OnInputAction(actionName: string)
    -- ...existing code...
    elseif actionName == "MyNewAction" then
        self:SendNewAction()
end

function DemoController:SendNewAction()
    NetworkController:Send(Events.PLAYER_NEW_ACTION, {
        customData = "value",
    })
end
```

**4. Process in DemoService.luau:**
```lua
-- In Init()
NetworkHandler:AllowClientEvent(Events.PLAYER_NEW_ACTION)

-- In Start()
EventBus:On(Events.PLAYER_NEW_ACTION, function(player, data)
    print(`[DemoService] {player.Name} used new action!`)
    -- Process logic here
end)
```

---

## 📊 Event Cheat Sheet

| I want to... | Use Event Direction | Method |
|--------------|---------------------|--------|
| Send player action | C→S | `NetworkController:Send()` |
| Update single player UI | S→C | `NetworkHandler:SendToClient()` |
| Update all players | S→C | `NetworkHandler:Broadcast()` |
| Internal server communication | - | `EventBus:Emit()` |

---

## 🎮 Testing Shortcuts

```lua
-- In Command Bar (F9)

-- Access demo
_G.DemoController:SendPing()
_G.DemoController:SendAttack()
_G.DemoController:RunTests()

-- Check network status
print(game.ReplicatedStorage.SystemsShared.Network.NetworkBridge)

-- Count players
print(#game.Players:GetPlayers())

-- List all input bindings
local InputSettings = require(game.ReplicatedStorage.Shared.InputSettings)
for action, keys in pairs(InputSettings.Bindings) do
    print(action, "→", table.concat(keys, ", "))
end

-- Check if controller exists
print(game.StarterPlayer.StarterPlayerScripts.Controllers:GetChildren())
```

---

*Quick Reference v1.1*
*Added Input System Reference*
