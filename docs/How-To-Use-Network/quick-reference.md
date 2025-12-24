# 🚀 Quick Reference Guide (Production)

## ⚠️ Production Only

เอกสารนี้ครอบคลุม **Production components เท่านั้น**

**🧪 Demo components** (DemoController, DemoService) ดูที่ `demo-testing.md`

---

## 📌 Most Important Files (Production)

| File | Purpose | When to Edit | Status |
|------|---------|--------------|--------|
| `Events.luau` | Event name registry | Adding new events | ✅ Production |
| `Init.server.luau` | Server startup | Adding services | ✅ Production |
| `Init.client.luau` | Client startup | Adding controllers | ✅ Production |
| `NetworkHandler.luau` | Network security | Security rules | ✅ Production |
| `CooldownService.luau` | Cooldown tracking | Cooldown config | ✅ Production |
| ~~`DemoService.luau`~~ | ~~Testing~~ | ~~N/A~~ | 🧪 Demo (ลบได้) |

---

## 🎯 Common Tasks (Production)

### Task 1: Add New Event

**1. Add to Events.luau:**
```lua
MY_NEW_EVENT = "MyNewEvent",
```

**2. Allow in NetworkHandler:**
```lua
// For client→server events
NetworkHandler:AllowClientEvent(Events.MY_NEW_EVENT)
```

**3. Listen in Service (Production):**
```lua
// ✅ Production Service
EventBus:On(Events.MY_NEW_EVENT, function(player, data)
    -- Validate first
    if not validateAction(player, data) then return end
    
    -- Process
    local result = processAction(player, data)
    
    -- Respond
    NetworkHandler:SendToClient(player, Events.ACTION_SUCCESS, result)
end)
```

**❌ อย่าใช้:**
```lua
// ❌ Demo Service (ลบได้)
EventBus:On(Events.DEMO_*, ...)
```

---

### Task 2: Send Data to Client (Production)

**From Production Service:**
```lua
// ✅ GOOD - Production
-- CombatService.luau
NetworkHandler:SendToClient(player, Events.COMBAT_RESULT, {
    damage = 10,
    success = true,
})

-- Broadcast to all
NetworkHandler:Broadcast(Events.GAME_STARTED, {round = 1})
```

**❌ อย่าใช้:**
```lua
// ❌ BAD - Demo events
NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, ...)
```

---

### Task 3: Handle Input (Production)

**Production Flow:**
```lua
// ✅ Production: InputController → InputHandler → Server

// InputHandler.luau
if actionName == "Attack" then
    self:HandleAttack() // Production method
end
```

**❌ อย่าใช้:**
```lua
// ❌ Demo
DemoController:SendTestEventToServer()
```

---

### Task 4: Create New Service (Production)

**1. Create file:** `Services/MyService.luau`

**2. Use Production template:**
```lua
--!strict
-- ✅ Production Service Template

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local NetworkHandler = require(ServerScriptService.Services.NetworkHandler)
local CooldownService = require(ServerScriptService.Services.CooldownService)

export type MyService = {
    Init: (self: MyService) -> (),
    Start: (self: MyService) -> (),
}

local MyService: MyService = {}

function MyService:Init()
    // Allow events
    NetworkHandler:AllowClientEvent(Events.MY_ACTION)
    print("[MyService] Initialized")
end

function MyService:Start()
    EventBus:On(Events.MY_ACTION, function(player, data)
        // 1. Validate
        if not self:Validate(player, data) then return end
        
        // 2. Check cooldown
        if CooldownService:IsOnCooldown(player, "MyAction") then
            return
        end
        
        // 3. Process
        local result = self:Process(player, data)
        
        // 4. Set cooldown
        CooldownService:SetCooldown(player, "MyAction")
        
        // 5. Respond
        NetworkHandler:SendToClient(player, Events.ACTION_SUCCESS, result)
    end)
end

function MyService:Validate(player: Player, data: any): boolean
    if not player.Character then return false end
    return true
end

function MyService:Process(player: Player, data: any)
    return {success = true}
end

return MyService
```

**3. Add to Init.server.luau:**
```lua
local MyService = require(Services.MyService)
// ...
MyService:Init()
// ...
MyService:Start()
```

---

## ⚡ Production Features

### Input Types Quick Reference

| Input Type | Component | Event Name | Status |
|------------|-----------|------------|--------|
| **Tap** | InputController ✅ | `"Attack"` | Production |
| **Hold** | InputController ✅ | `"AttackHold"` | Production |
| **Release** | InputController ✅ | `"AttackRelease"` | Production |
| **Double Tap** | InputController ✅ | `"AttackDoubleTap"` | Production |
| **Combo** | InputController ✅ | `"ComboTripleStrike"` | Production |

### Cooldown System (Production)

```lua
// ✅ Production: CooldownService

// Server: Check cooldown
if CooldownService:IsOnCooldown(player, "Attack") then
    return
end

// Server: Set cooldown
CooldownService:SetCooldown(player, "Attack")

// Server: Get remaining
local remaining = CooldownService:GetRemaining(player, "Attack")
```

---

## 🔍 Debug Checklist (Production)

### ❌ Event not firing

- [ ] Is event in `Events.luau`?
- [ ] Is event allowed in NetworkHandler whitelist?
- [ ] Is EventBus:On() listener in **Production Service** (not Demo)?
- [ ] Check console for rate limit warnings

### ❌ Cooldown not working

- [ ] Is CooldownService:SetCooldown() called on server?
- [ ] Is check before or after action?
- [ ] Check server console logs

### ❌ Input not detected

- [ ] Is key in InputSettings.Bindings?
- [ ] Is InputController initialized?
- [ ] Is InputHandler listening to INPUT_ACTION?

---

## 🎮 Testing Shortcuts (Production)

```lua
// In Command Bar (F9)

// ✅ Production testing
-- Check input state
print(_G.InputController:GetInputState())

-- Check handler state
print(_G.InputHandler:GetState())

// ❌ อย่าใช้ Demo
-- print(_G.DemoController) // ลบได้
```

---

## 📊 Component Status

### ✅ Production Ready
- InputController
- InputHandler  
- NetworkController
- NetworkHandler
- CooldownService
- CombatService
- GameService
- ArenaService

### 🧪 Demo (ลบได้)
- ~~DemoController~~
- ~~DemoService~~

### 🔨 TODO
- UIController
- ProfileService
- GameConfigs

---

*Quick Reference v2.0*
*Production Only - Demo Separated ✅*
