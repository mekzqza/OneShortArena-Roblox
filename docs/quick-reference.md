# 🚀 Quick Reference Guide

## 📌 Most Important Files

| File | Purpose | When to Edit |
|------|---------|--------------|
| `Events.luau` | Event name registry | Adding new events |
| `Init.server.luau` | Server startup | Adding new services |
| `Init.client.luau` | Client startup | Adding new controllers |
| `NetworkHandler.luau` | Network security | Changing security rules |

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

## 🔍 Debug Checklist

### ❌ Client can't connect to server

- [ ] Check server console: Did NetworkHandler create RemoteEvent?
- [ ] Check client console: Did it find Network/NetworkBridge?
- [ ] Wait 30+ seconds (WaitForChild timeout)

### ❌ Event not firing

- [ ] Is event name in Events.luau?
- [ ] Is event allowed in NetworkHandler whitelist?
- [ ] Is EventBus:On() listener set up?
- [ ] Check console for rate limit warnings

### ❌ Data not received

- [ ] Is event in SERVER_TO_CLIENT_ALLOW or CLIENT_TO_SERVER_ALLOW?
- [ ] Is payload safe? (no functions, instances, circular refs)
- [ ] Check NetworkHandler logs (set DEBUG = true)

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

-- Check network status
print(game.ReplicatedStorage.SystemsShared.Network.NetworkBridge)

-- Count players
print(#game.Players:GetPlayers())
```

---

*Quick Reference v1.0*
