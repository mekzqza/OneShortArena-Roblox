# 👨‍💻 Development Guide

## 🎯 Quick Start

### Prerequisites

- Roblox Studio (latest)
- VS Code (optional, with Rojo)
- Git
- Basic Luau knowledge

### Setup Development Environment

```bash
# 1. Clone repository
git clone [repo-url]
cd OneShortArena-Roblox

# 2. Install Rojo (optional)
npm install -g rojo

# 3. Start Rojo server (optional)
rojo serve
```

### Enable Development Mode

```lua
-- ServerScriptService/Init.server.luau
local IS_PRODUCTION = false  -- Development mode

-- StarterPlayerScripts/Init.client.luau
local IS_PRODUCTION = false  -- Development mode
```

---

## 📋 Development Workflow

### 1. Adding New Event

**Step 1: Define Event**
```lua
-- ReplicatedStorage/Shared/Events.luau
return {
    -- ...existing code...
    YOUR_NEW_EVENT = "YourNewEvent",
}
```

**Step 2: Allow Event (Server)**
```lua
-- ServerScriptService/Services/YourService.luau
function YourService:Init()
    NetworkHandler:AllowClientEvent(Events.YOUR_NEW_EVENT)
end
```

**Step 3: Send from Client**
```lua
-- Client Controller
NetworkController:Send(Events.YOUR_NEW_EVENT, {
    data = "example"
})

-- Or use Reliable Send for important events
NetworkController:SendReliable(Events.YOUR_NEW_EVENT, {
    data = "important"
})
```

**Step 4: Handle on Server**
```lua
-- Server Service
function YourService:Start()
    EventBus:On(Events.YOUR_NEW_EVENT, function(player: Player, data: any)
        print(`Received from {player.Name}:`, data)
        -- Process...
    end)
end
```

---

### 2. Adding New Ability

**Step 1: Add Key Binding**
```lua
-- ReplicatedStorage/Shared/InputSettings.luau
Bindings = {
    -- ...existing code...
    FIREBALL = { Enum.KeyCode.F },
}

MobileButtonNames = {
    -- ...existing code...
    FIREBALL = "🔥 Fireball",
}
```

**Step 2: Handle Input**
```lua
-- StarterPlayerScripts/Controllers/InputHandler.luau
function InputHandler:OnInputAction(actionName: string)
    -- ...existing code...
    
    if actionName == "FIREBALL" then
        self:HandleFireball()
    end
end

function InputHandler:HandleFireball()
    if not self:CheckCooldown("Fireball") then return end
    if not self:CanPerformCombatAction() then return end
    
    local targetPosition = self:GetMouseWorldPosition()
    
    self:QueueAction(Events.PLAYER_ABILITY, {
        abilityName = "Fireball",
        targetPosition = targetPosition,
        timestamp = tick()
    })
    
    self:SetCooldown("Fireball")
end
```

**Step 3: Add Cooldown**
```lua
-- In InputHandler
local cooldowns = {
    -- ...existing code...
    Fireball = 2.0,  -- 2 second cooldown
}
```

**Step 4: Server Processing**
```lua
-- ServerScriptService/Services/AbilityService.luau (create if needed)
function AbilityService:Start()
    EventBus:On(Events.PLAYER_ABILITY, function(player: Player, data: any)
        if data.abilityName == "Fireball" then
            self:CastFireball(player, data)
        end
    end)
end

function AbilityService:CastFireball(player: Player, data: any)
    -- Validate cooldown (server-side)
    if CooldownService:IsOnCooldown(player, "Fireball") then
        return
    end
    
    -- Create projectile
    local fireball = createFireballProjectile(data.targetPosition)
    
    -- Apply effects
    fireball.Touched:Connect(function(hit)
        local enemy = getPlayerFromHit(hit)
        if enemy and enemy ~= player then
            applyDamage(enemy, 50)
        end
    end)
    
    -- Set server cooldown
    CooldownService:SetCooldown(player, "Fireball")
end
```

---

### 3. Adding New Service

**Create Service File**
```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\Services\YourService.luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)

export type YourService = {
    Init: (self: YourService) -> (),
    Start: (self: YourService) -> (),
    [string]: any,
}

local YourService = {} :: YourService

function YourService:Init()
    print("[YourService] Initializing...")
    -- Setup phase (register events, load resources)
end

function YourService:Start()
    print("[YourService] Started")
    -- Runtime phase (start loops, listeners)
    
    EventBus:On(Events.SOME_EVENT, function(player, data)
        -- Handle event
    end)
end

return YourService
```

**Load in Init.server.luau**
```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\Init.server.luau
-- ...existing code...

local YourService = require(Services.YourService)

-- ...existing code...

print("[Init] Initializing YourService...")
YourService:Init()

-- ...existing code...

YourService:Start()
```

---

### 4. Adding New Controller

**Create Controller File**
```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\Controllers\YourController.luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)

export type YourController = {
    Init: (self: YourController) -> (),
    Start: (self: YourController) -> (),
    [string]: any,
}

local YourController = {} :: YourController

function YourController:Init()
    print("[YourController] Initializing...")
end

function YourController:Start()
    print("[YourController] Started")
    
    EventBus:On(Events.SOME_EVENT, function(data)
        -- Handle event
    end)
end

return YourController
```

**Auto-loaded by Init.client.luau** ✅

---

## 🧪 Testing

### Local Testing

```lua
-- F9 Console Commands

-- Test network
_G.NetworkController:Send(Events.TEST, {test = true})

-- Test reliable send
_G.NetworkController:SendReliable(Events.TEST, {important = true})

-- Check stats
local stats = _G.NetworkController:GetStats()
print(stats)

-- Force retry
_G.NetworkController:RetryAllPending()
```

### Server Testing

```lua
-- F9 Console (Server)

-- Check network health
local health = NetworkHandler:GetNetworkHealth()
print(health)

-- Get analytics
local analytics = NetworkHandler:GetAnalytics()
print("Total events:", analytics.totalEvents)
print("EPS:", analytics.eventsPerSecond)

-- Check suspicious players
local suspicious = NetworkHandler:GetSuspiciousPlayers()
for userId, data in pairs(suspicious) do
    print(`User {userId}: {data.strikes} strikes`)
end
```

---

## 🐛 Debugging

### Enable Debug Mode

```lua
-- NetworkHandler
NetworkHandler:Configure({ debug = true })

-- InputController
local DEBUG = true

-- InputHandler
local DEBUG = true
```

### Common Debug Commands

```lua
-- Check if event is allowed
print(CLIENT_TO_SERVER_ALLOW[Events.YOUR_EVENT])

-- Monitor all events
EventBus:On(Events.INPUT_ACTION, function(action)
    print("[DEBUG]", action)
end)

-- Check controller state
print(_G.Controllers)
```

---

## 📊 Performance Optimization

### Client

```lua
-- ✅ Batch updates
local updates = {}
for i = 1, 10 do
    table.insert(updates, data[i])
end
NetworkController:Send(Events.BATCH_UPDATE, {items = updates})

-- ❌ Don't spam
for i = 1, 10 do
    NetworkController:Send(Events.UPDATE, data[i])  -- BAD
end
```

### Server

```lua
-- ✅ Use caching
local cache = {}
function getData(key)
    if cache[key] then return cache[key] end
    cache[key] = expensiveQuery(key)
    return cache[key]
end

-- ✅ Profile critical paths
local start = os.clock()
performOperation()
print("Operation took:", os.clock() - start)
```

---

## 🔒 Security Best Practices

### Server Validation

```lua
-- ✅ Always validate on server
EventBus:On(Events.PURCHASE_ITEM, function(player, data)
    -- Validate price
    local actualPrice = getItemPrice(data.itemId)
    if data.price ~= actualPrice then
        warn(`Price mismatch from {player.Name}`)
        return
    end
    
    -- Validate currency
    if getPlayerCoins(player) < actualPrice then
        warn(`Insufficient funds from {player.Name}`)
        return
    end
    
    -- Process
    deductCoins(player, actualPrice)
    giveItem(player, data.itemId)
end)
```

### Register Validators

```lua
-- Custom validation
NetworkHandler:RegisterValidator(Events.PURCHASE_ITEM, function(player, args)
    local data = args[1]
    
    -- Validate structure
    if type(data.itemId) ~= "string" then
        return false, "Invalid itemId type"
    end
    
    if type(data.price) ~= "number" or data.price < 0 then
        return false, "Invalid price"
    end
    
    return true
end)
```

---

## 📝 Code Style

### Naming Conventions

```lua
-- Variables: camelCase
local playerName = "John"
local attackDamage = 50

-- Constants: UPPER_CASE
local MAX_PLAYERS = 16
local COOLDOWN_TIME = 3.0

-- Types: PascalCase
export type PlayerData = {
    name: string,
    coins: number
}

-- Private functions: _camelCase (optional)
local function _helperFunction()
end

-- Public functions: PascalCase (methods)
function Service:PublicMethod()
end
```

### File Headers

```lua
--!strict

--[[]
    ServiceName - Brief description
    
    Purpose:
    - What this service does
    
    Dependencies:
    - EventBus
    - NetworkHandler
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- ...
```

### Comments

```lua
-- ✅ Good: Explain WHY
-- Rate limit prevents spam attacks
if not checkRateLimit(player) then return end

-- ❌ Bad: Explain WHAT (code is self-explanatory)
-- Check if player exists
if player then
```