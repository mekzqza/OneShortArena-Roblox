# 🏗️ System Architecture - Deep Dive

## 📋 Table of Contents

1. [Overview](#overview)
2. [Layer Architecture](#layer-architecture)
3. [Core Systems](#core-systems)
4. [Data Flow](#data-flow)
5. [Design Patterns](#design-patterns)

---

## Overview

OneShortArena ใช้สถาปัตยกรรมแบบ **Layered Architecture** ที่แยกความรับผิดชอบชัดเจน:

- **Presentation Layer** - UI, Input, Visual Effects
- **Application Layer** - Controllers, Input Handlers
- **Domain Layer** - Game Logic, Business Rules
- **Infrastructure Layer** - Network, Data Storage

---

## Layer Architecture

### Client-Side Layers

```
┌────────────────────────────────────────┐
│   Presentation Layer (UI/UX)           │
│   - Screen GUI                         │
│   - Visual Effects                     │
│   - Sounds                             │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│   Application Layer (Controllers)      │
│   - InputController (Low-level)        │
│   - InputHandler (Game-specific)       │
│   - AbilityController                  │
│   - UIController                       │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│   Infrastructure Layer (Network)       │
│   - NetworkController                  │
│   - RemoteEvent Communication          │
└─────────────┬──────────────────────────┘
              │ Network
┌─────────────▼──────────────────────────┐
│           SERVER                       │
└────────────────────────────────────────┘
```

### Server-Side Layers

```
┌────────────────────────────────────────┐
│   Infrastructure Layer (Network)       │
│   - NetworkHandler                     │
│   - Security & Validation              │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│   Application Layer (Services)         │
│   - GameService                        │
│   - ArenaService                       │
│   - CooldownService                    │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│   Domain Layer (Business Logic)        │
│   - Game Rules                         │
│   - Combat System                      │
│   - Matchmaking                        │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│   Data Layer (Storage)                 │
│   - DataStore                          │
│   - Cache System                       │
└────────────────────────────────────────┘
```

---

## Core Systems

### 1. Event Bus System

**Purpose:** Decoupled event communication

```lua
-- ReplicatedStorage/SystemsShared/EventBus.luau
local EventBus = {
    _listeners = {}  -- event -> {callbacks}
}

function EventBus:On(eventName: string, callback: (...any) -> ())
    -- Register listener
end

function EventBus:Emit(eventName: string, ...: any)
    -- Call all listeners
end
```

**Benefits:**
- ✅ Loose coupling between modules
- ✅ Easy to add/remove features
- ✅ Centralized event management

**Example:**
```lua
-- Publisher
EventBus:Emit(Events.PLAYER_ATTACKED, player, damage)

-- Subscriber
EventBus:On(Events.PLAYER_ATTACKED, function(player, damage)
    print(`{player.Name} dealt {damage} damage`)
end)
```

---

### 2. Service Pattern (Server)

**Structure:**
```lua
export type ServiceName = {
    Init: (self: ServiceName) -> (),
    Start: (self: ServiceName) -> (),
    -- Service methods...
}

local ServiceName = {} :: ServiceName

function ServiceName:Init()
    -- Setup phase (load resources, register events)
end

function ServiceName:Start()
    -- Runtime phase (start loops, connect listeners)
end

return ServiceName
```

**Lifecycle:**
```
Init.server.luau
    → Load all services
    → Call Init() on each  (dependency setup)
    → Call Start() on each (begin runtime)
```

**Example Services:**
- `NetworkHandler` - Network security
- `GameService` - Game loop, state management
- `ArenaService` - Arena spawning, management
- `CooldownService` - Ability cooldowns

---

### 3. Controller Pattern (Client)

**Structure:**
```lua
export type ControllerName = {
    Init: (self: ControllerName) -> (),
    Start: (self: ControllerName) -> (),
    -- Controller methods...
}

local ControllerName = {} :: ControllerName

function ControllerName:Init()
    -- Setup (bind events, create UI)
end

function ControllerName:Start()
    -- Runtime (start listening)
end

return ControllerName
```

**Example Controllers:**
- `InputController` - Hardware input detection
- `InputHandler` - Game command logic
- `NetworkController` - Network transport
- `AbilityController` - Ability VFX, client-side logic

---

### 4. Network Security System

**Components:**

1. **Rate Limiting**
   ```lua
   -- Per-player: 10 events / 5 seconds
   -- Global: 100 events / second
   -- Burst: 3 events / 0.5 seconds
   ```

2. **Event Validation**
   ```lua
   NetworkHandler:RegisterValidator(eventName, function(player, args)
       -- Validate args
       return true/false, "reason"
   end)
   ```

3. **Anti-Replay**
   ```lua
   -- Each message has unique ID
   -- Duplicate IDs rejected
   -- IDs expire after 60s
   ```

4. **Suspicious Activity Tracking**
   ```lua
   -- 3 strikes system
   -- Strike 1-2: Warning
   -- Strike 3+: Rate limit increase
   -- Strike 5: Auto-kick
   ```

---

## Data Flow

### Combat Action Flow

```
1. Player presses attack button
   └─> InputController detects "E" key

2. InputController emits INPUT_ACTION
   └─> EventBus:Emit("INPUT_ACTION", "ATTACK")

3. InputHandler receives event
   ├─> Check cooldown (client-side)
   ├─> Check player state (alive?)
   └─> Queue action

4. InputHandler sends to server
   └─> NetworkController:SendReliable(PLAYER_ATTACK, data)

5. NetworkController adds messageId
   └─> Send via RemoteEvent + wait for ACK

6. Server NetworkHandler receives
   ├─> Validate rate limit
   ├─> Check anti-replay (messageId)
   ├─> Sanitize payload
   └─> Emit to EventBus

7. GameService processes attack
   ├─> Validate on server (cooldown, range, etc.)
   ├─> Apply damage
   ├─> Update game state
   └─> Send ACK back to client

8. Client receives ACK
   └─> Remove from retry queue
   └─> Update UI (cooldown animation)
```

### Reliable Send with Retry

```
Client:
  1. Generate messageId (GUID)
  2. Send data + messageId
  3. Add to retry queue
  4. Wait 5 seconds for ACK
  5. If no ACK → retry (max 3 times)
  6. If ACK received → remove from queue

Server:
  1. Receive data + messageId
  2. Check if messageId already seen
  3. If duplicate → reject (anti-replay)
  4. Process data
  5. Send ACK with messageId back
```

---

## Design Patterns

### 1. Observer Pattern (EventBus)

```lua
-- Subject
EventBus:Emit("EVENT", data)

-- Observers
EventBus:On("EVENT", callback1)
EventBus:On("EVENT", callback2)
EventBus:On("EVENT", callback3)
```

### 2. Singleton Pattern (Services)

```lua
-- Only one instance per service
local GameService = {}
return GameService
```

### 3. Strategy Pattern (Input Actions)

```lua
-- Different strategies for different inputs
if action == "ATTACK" then
    handleAttack()
elseif action == "DEFEND" then
    handleDefend()
elseif action == "SPECIAL" then
    handleSpecial()
end
```

### 4. Command Pattern (Action Queue)

```lua
-- Queue commands for later execution
actionQueue:Add({
    type = "ATTACK",
    data = attackData,
    timestamp = tick()
})

-- Process queue
for _, command in actionQueue do
    executeCommand(command)
end
```

### 5. Factory Pattern (Future: Ability System)

```lua
-- Create abilities from configuration
local ability = AbilityFactory:Create("Fireball", {
    damage = 50,
    cooldown = 3,
    range = 30
})
```

---

## Module Dependencies

```
ReplicatedStorage/
├── Shared/
│   ├── Events.luau          (No dependencies)
│   └── InputSettings.luau   (No dependencies)
│
└── SystemsShared/
    └── EventBus.luau         (No dependencies)

Server/
├── NetworkHandler           (→ EventBus, Events)
├── GameService              (→ NetworkHandler, EventBus)
├── ArenaService             (→ NetworkHandler, EventBus)
└── CooldownService          (No dependencies)

Client/
├── NetworkController        (→ EventBus, Events)
├── InputController          (→ EventBus, Events, InputSettings)
├── InputHandler             (→ NetworkController, EventBus, Events)
└── AbilityController        (→ NetworkController, EventBus, Events)
```

**Dependency Rules:**
- ✅ Lower layers can depend on higher layers
- ✅ Same layer can depend on each other (avoid circular)
- ❌ Higher layers cannot depend on lower layers

---

## State Management

### Server State

```lua
-- GameService
local gameState = {
    status = "Waiting",  -- "Waiting" | "Starting" | "Playing" | "Ended"
    players = {},
    roundNumber = 0,
    timeRemaining = 0
}
```

### Client State

```lua
-- InputHandler
local playerState = {
    canAttack = true,
    canDefend = true,
    isInCombat = false,
    isInMenu = false
}
```

**State Sync:**
- Server = source of truth
- Client = optimistic updates
- Server validates & corrects

---

## Error Handling

### Client

```lua
pcall(function()
    -- Risky operation
    controller:SomeMethod()
end)

-- Network failures
EventBus:On("NETWORK_SEND_FAILED", function(eventName)
    -- Show UI notification
    UIController:ShowError("Connection issue")
end)
```

### Server

```lua
-- Graceful degradation
local success, err = pcall(function()
    -- Process request
end)

if not success then
    warn(`[Service] Error: {err}`)
    -- Don't crash server
end
```

---

## Performance Considerations

### Memory

- ✅ Clean up listeners when objects destroyed
- ✅ Use object pooling for frequent spawns
- ✅ Limit event history size (max 100 errors)

### Network

- ✅ Batch events when possible
- ✅ Use priority queue (important events first)
- ✅ Rate limiting prevents spam

### CPU

- ✅ Debounce rapid inputs
- ✅ Use task.defer() for non-urgent code
- ✅ Profile critical paths

---

## Security Architecture

### Defense in Depth

```
Layer 1: Client Validation
  └─> Basic checks (cooldown, state)

Layer 2: Network Security
  ├─> Rate limiting
  ├─> Event allowlist
  └─> Payload sanitization

Layer 3: Server Validation
  ├─> Re-check cooldowns
  ├─> Validate game state
  ├─> Check permissions
  └─> Verify data integrity

Layer 4: Anti-Cheat
  ├─> Suspicious activity tracking
  ├─> Pattern detection
  └─> Auto-kick system
```

---

## Scalability

### Horizontal Scaling (Future)

```lua
-- Reserved servers for high player count
if #Players:GetPlayers() > 30 then
    -- Spawn new server
    TeleportService:TeleportToPrivateServer(...)
end
```

### Vertical Optimization

```lua
-- Cache frequently accessed data
local cache = {}
function getData(key)
    if cache[key] then return cache[key] end
    cache[key] = expensiveOperation(key)
    return cache[key]
end
```

---

## Future Enhancements

1. **State Machine** for game states
2. **Ability System** with data-driven config
3. **Replay System** for match recordings
4. **Leaderboard System** with pagination
5. **Chat System** with filters
6. **Friend System** integration
7. **Clan/Guild System**

---

**Version:** 2.0  
**Last Updated:** 2024  
**Author:** OneShortArena Team
