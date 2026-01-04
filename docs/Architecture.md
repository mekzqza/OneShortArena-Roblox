# 🏗️ System Architecture - Deep Dive v3.2

## 📋 Table of Contents

1. [Overview](#overview)
2. [Layer Architecture](#layer-architecture)
3. [Core Systems](#core-systems)
4. [Data Flow](#data-flow)
5. [Design Patterns](#design-patterns)
6. [Data System Architecture](#data-system-architecture) ✨NEW
7. [Init System Architecture](#init-system-architecture) ✨NEW
8. [Utility Systems](#utility-systems) ✨NEW

---

## Overview

OneShortArena ใช้สถาปัตยกรรมแบบ **Layered Architecture** ที่แยกความรับผิดชอบชัดเจน:

- **Presentation Layer** - UI, Input, Visual Effects
- **Application Layer** - Controllers, Input Handlers
- **Domain Layer** - Game Logic, Business Rules
- **Data Layer** - ProfileService + PocketBase (Hybrid) ✨NEW
- **Infrastructure Layer** - Network, Storage, Cloud Sync ✨NEW

**Version:** 3.2 - Production Ready  
**Major Features:**
- ✅ Combat → Downed → Respawn Flow
- ✅ Hybrid Data System (ProfileService + PocketBase)
- ✅ Promise-based Init with Parallel Execution
- ✅ Dependency Injection (ServiceLocator/ControllerLocator)
- ✅ Utilities (DataMapper, IdempotencyKey, ExecutionGuard)

---

## Layer Architecture

### Client-Side Layers

```
┌────────────────────────────────────────┐
│   Presentation Layer (UI/UX)           │
│   - Screen GUI                         │
│   - Visual Effects                     │
│   - Sounds                             │
│   - Downed State Visual    ✨NEW       │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│   Application Layer (Controllers)      │
│   - InputController (Low-level)        │
│   - InputHandler (+ Downed blocking)   │
│   - AbilityController                  │
│   - UIController                       │
│   - HudController          ✨NEW       │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│   Infrastructure Layer (Network)       │
│   - NetworkController                  │
│   - ControllerLocator      ✨NEW       │
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
│   - ServiceLocator         ✨NEW       │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│   Application Layer (Services)         │
│   - GameService                        │
│   - ArenaService                       │
│   - CombatService          ✨NEW       │
│   - DownedService          ✨NEW       │
│   - RespawnService         ✨NEW       │
│   - CooldownService                    │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│   Domain Layer (Business Logic)        │
│   - Game Rules                         │
│   - Combat System                      │
│   - Downed/Revive Logic    ✨NEW       │
│   - Matchmaking                        │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│   Data Layer (Hybrid Storage)  ✨NEW   │
│   ┌────────────────────────────────┐   │
│   │   PlayerDataService (API)      │   │
│   │   ┌────────────┐ ┌───────────┐ │   │
│   │   │ProfileSvc  │ │PocketBase │ │   │
│   │   │ PRIMARY    │ │ SECONDARY │ │   │
│   │   └────────────┘ └───────────┘ │   │
│   └────────────────────────────────┘   │
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

-- ✨NEW: Emit to specific player (Client)
function EventBus:EmitTo(player: Player, eventName: string, ...: any)
    -- Send to specific player's client
end
```

**Benefits:**
- ✅ Loose coupling between modules
- ✅ Easy to add/remove features
- ✅ Centralized event management
- ✅ **NEW:** Support for targeted emits

**Example:**
```lua
-- Publisher
EventBus:Emit(Events.PLAYER_FATAL_HIT, player, damage)

-- Subscriber
EventBus:On(Events.PLAYER_FATAL_HIT, function(player, damage)
    -- Enter Downed state
    DownedService:EnterDownedState(player)
end)
```

---

### 2. Service Pattern (Server) ✨UPDATED

**Structure:**
```lua
export type ServiceName = {
    Init: (self: ServiceName) -> (),
    Start: (self: ServiceName) -> (),
    -- Service methods...
}

local ServiceName = {} :: ServiceName

-- ✅ Use IdempotentGuard
local guard = IdempotentGuard.new("ServiceName", true)

function ServiceName:Init()
    if not guard:MarkInitialized() then return end
    -- Setup phase (load resources, register events)
end

function ServiceName:Start()
    if not guard:MarkStarted() then return end
    
    -- ✅ Get dependencies via ServiceLocator
    local PlayerDataService = ServiceLocator:Get("PlayerDataService")
    
    -- Runtime phase (start loops, connect listeners)
end

return ServiceName
```

**Lifecycle (Promise-based):**
```
Init.server.luau
    → Load all services
    → Promise chain:
      ├─ Init() Layer 1 (Core)
      ├─ Init() Layer 2 (Cloud)
      ├─ Init() Layer 3 (Data)
      ├─ Init() Layer 4 (Player)
      └─ Init() Layer 5 (Gameplay) ⚡ PARALLEL!
    → Register in ServiceLocator
    → Promise chain:
      └─ Start() all layers (with timeout)
```

**Example Services:**
- `NetworkHandler` - Network security
- `PlayerDataService` - Data management (PRIMARY) ✨NEW
- `PocketBaseService` - Cloud sync (SECONDARY) ✨NEW
- `CombatService` - Combat logic ✨NEW
- `DownedService` - Downed state ✨NEW
- `RespawnService` - Respawn scheduling ✨NEW

---

### 3. Controller Pattern (Client) ✨UPDATED

**Structure:**
```lua
export type ControllerName = {
    SetDependencies: (self: ControllerName, locator: any) -> (),  -- ✨NEW
    Init: (self: ControllerName) -> (),
    Start: (self: ControllerName) -> (),
}

local ControllerName = {} :: ControllerName

-- ✅ Dependencies storage
local Dependencies: {
    NetworkController: any?,
    PlayerStateController: any?,
} = {}

-- ✅ Dependency Injection (called before Init)
function ControllerName:SetDependencies(locator: any)
    Dependencies.NetworkController = locator:Get("NetworkController")
    Dependencies.PlayerStateController = locator:Get("PlayerStateController")
end

function ControllerName:Init()
    -- Setup (bind events, create UI)
    -- Can use Dependencies here
end

function ControllerName:Start()
    -- Runtime (start listening)
    -- Use Dependencies.NetworkController
end

return ControllerName
```

**Lifecycle (Promise-based):**
```
Init.client.luau
    → Load all controllers
    → Register in ControllerLocator
    → Promise chain:
      ├─ SetDependencies() + Init() Layer 1 (Core)
      ├─ Init() Layer 2 (Inputs)
      └─ Init() Layer 3 (Gameplay + UI) ⚡ PARALLEL!
    → Promise chain:
      └─ Start() all layers
```

**Example Controllers:**
- `InputController` - Hardware input detection
- `InputHandler` - Game command logic + Downed blocking ✨NEW
- `NetworkController` - Network transport
- `HudController` - Real-time UI updates ✨NEW

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

### Combat → Downed → Respawn Flow ✨NEW

```
1. Player takes damage
   └─> CombatService:ApplyDamage(player, damage)

2. Check if fatal (HP <= 0)
   └─> EventBus:Emit(PLAYER_FATAL_HIT, player)

3. DownedService enters Downed state
   ├─> Set HP to 1%
   ├─> PlatformStand (ragdoll)
   ├─> Start 15s countdown
   └─> EventBus:Emit(PLAYER_DOWNED, player)

4. Client blocks inputs
   └─> InputHandler detects Downed state
       └─> Block Play/Attack buttons

5. Countdown expires (or Finished)
   └─> EventBus:Emit(PLAYER_DOWNED_TIMEOUT, player)

6. RespawnService schedules respawn
   ├─> Wait 3-5 seconds
   └─> EventBus:Emit(PLAYER_RESPAWN_REQUESTED, player)

7. LobbyService spawns player
   └─> Teleport to Lobby SpawnLocation
```

### Data Sync Flow (Hybrid) ✨NEW

```
1. Player action changes data
   └─> GameService:IncrementKills(player)

2. Update ProfileService (PRIMARY)
   └─> PlayerDataService:Increment(player, "Kills", 1)
       ├─> Validate
       ├─> Update profile.Data
       └─> EventBus:Emit(PLAYER_DATA_CHANGED, player, data)

3. Sync to PocketBase (SECONDARY)
   └─> PocketBaseService:SyncPlayer(userId, data)
       ├─> Check debounce (5s)
       ├─> DataMapper.ToRemote() - Convert format
       ├─> IdempotencyKey - Prevent duplicates
       └─> HTTP POST to VPS

4. Client receives update
   └─> HudController hears PLAYER_DATA_CHANGED
       └─> Update coins/kills display with animation
```

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

### 3. Dependency Injection Pattern ✨NEW

```lua
-- Server (ServiceLocator)
ServiceLocator:Register("PlayerDataService", PlayerDataService)

-- Later, in any service
local PDS = ServiceLocator:Get("PlayerDataService")
PDS:Set(player, "Coins", 100)

-- Client (ControllerLocator)
function MyController:SetDependencies(locator)
    Dependencies.NetworkController = locator:Get("NetworkController")
end
```

**Benefits:**
- ✅ No circular dependencies
- ✅ Type-safe (with proper exports)
- ✅ Easy to test (can mock dependencies)
- ✅ Loose coupling

### 4. Strategy Pattern (Input Actions)

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

### 5. Command Pattern (Action Queue)

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

### 6. Hybrid Storage Pattern ✨NEW

```lua
-- Primary: ProfileService (Roblox DataStore)
-- Secondary: PocketBase (VPS)

-- Write
PlayerDataService:Set(player, "Coins", 100)
  ├─> ProfileService (instant)
  └─> PocketBaseService (async, debounced)

-- Read
PlayerDataService:Get(player, "Coins")
  └─> ProfileService only (fast)

-- On Leave
PlayerDataService:Release(player)
  ├─> ProfileService:Release()
  └─> PocketBaseService:SyncPlayerAsync() (wait for completion)
```

**Benefits:**
- ✅ Fast reads (local DataStore)
- ✅ Backup to VPS (data safety)
- ✅ Can restore from VPS if DataStore fails
- ✅ Web dashboard access via PocketBase

---

## Data System Architecture ✨NEW

### Hybrid Storage Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│  📊 HYBRID DATA ARCHITECTURE                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Game Logic                                                     │
│      │                                                          │
│      ▼                                                          │
│  ┌─────────────────────────────────────┐                       │
│  │  PlayerDataService (Unified API)    │                       │
│  │  ┌──────────┐      ┌──────────┐     │                       │
│  │  │ProfileSvc│◄────►│PocketBase│     │                       │
│  │  │ PRIMARY  │      │SECONDARY │     │                       │
│  │  │DataStore │      │   VPS    │     │                       │
│  │  └──────────┘      └────┬─────┘     │                       │
│  └──────────────────────────┼───────────┘                       │
│                             │                                   │
│                             │ HTTPS + DataMapper                │
│                             ▼                                   │
│  ┌─────────────────────────────────────┐                       │
│  │   VPS (roblox-api.sukpat.dev)       │                       │
│  │  ┌──────┐  ┌──────────┐  ┌──────┐   │                       │
│  │  │Caddy │─►│PocketBase│─►│Redis │   │                       │
│  │  └──────┘  └──────────┘  └──────┘   │                       │
│  └─────────────────────────────────────┘                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Components

**1. PlayerDataService (Unified API)**
- Single interface for all data operations
- Manages ProfileService (primary)
- Triggers PocketBase sync (secondary)
- Type-safe with `PlayerData` export type
- O(1) dictionary-based inventory

**2. ProfileService (Primary Storage)**
- Roblox DataStore wrapper
- Session locking
- Data reconciliation
- Version migration support

**3. PocketBaseService (Secondary Storage)**
- VPS backup
- Retry logic with exponential backoff
- Queue system for offline handling
- Idempotent operations via IdempotencyKey

**4. DataMapper (Format Converter)**
- Explicit field mapping
- Type coercion (number ↔ string)
- Dictionary ↔ Array conversion for inventory
- Validation

**5. IdempotencyKey (Duplicate Prevention)**
- Generate unique keys per operation
- Track execution status
- Cache results
- TTL-based cleanup

---

## Init System Architecture ✨NEW

### Promise-based Boot Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  🚀 INIT SYSTEM - PARALLEL EXECUTION                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Sequential Layers (must complete in order):                   │
│  ───────────────────────────────────────────                   │
│  1️⃣ Core Layer       (NetworkHandler)                          │
│       ↓                                                         │
│  2️⃣ Cloud Layer      (PocketBaseService)                       │
│       ↓                                                         │
│  3️⃣ Data Layer       (PlayerDataService)                       │
│       ↓                                                         │
│  4️⃣ Player Layer     (PlayerStateService)                      │
│       ↓                                                         │
│  5️⃣ Gameplay Layer   ⚡ PARALLEL EXECUTION                      │
│     ┌────────────────────────────────────┐                     │
│     │ LobbyService    │ ArenaService     │                     │
│     │ CombatService   │ DeathService     │                     │
│     │ DownedService   │ RespawnService   │                     │
│     │ MatchService    │ CooldownService  │                     │
│     │ GameService     │                  │                     │
│     └────────────────────────────────────┘                     │
│       ↓                                                         │
│  6️⃣ Test Layer       (TestService - optional)                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Key Features

**1. Parallel Execution**
```lua
Promise.all({
    initService(LobbyService, "LobbyService"),
    initService(ArenaService, "ArenaService"),
    // ... 9 services run simultaneously!
})
```
**Result:** 5-10x faster boot (1.05s → 0.27s)

**2. Timeout Protection**
```lua
local TIMEOUTS = {
    ServiceInit = 15,   -- Max per service
    LayerInit = 45,     -- Max per layer
}

initService(MyService, "MyService")
    :timeout(TIMEOUTS.ServiceInit)
    :catch(function(err)
        if Promise.Error.isKind(err, Promise.Error.Kind.TimedOut) then
            error("Service took too long!")
        end
    end)
```

**3. Error Handling**
```lua
Promise.resolve()
    :andThen(function() return initLayer1() end)
    :andThen(function() return initLayer2() end)
    :catch(function(err)
        error(`CRITICAL: {err}`)
        -- Optionally kick all players
    end)
    :finally(function()
        print("Boot completed")
    end)
```

**4. Boot Analytics**
```lua
📊 Layer Timing Breakdown:
─────────────────────────────
  Core: 0.051s (11.0%)
  Cloud: 0.030s (6.6%)
  Data: 0.040s (8.8%)
  Player: 0.025s (5.5%)
  Gameplay: 0.123s (27.0%)  ← Parallel!
  Test: 0.010s (2.2%)
─────────────────────────────
```

---

## Utility Systems ✨NEW

### 1. ServiceLocator

**Purpose:** Fix circular dependencies

```lua
-- Register (Init.server.luau)
ServiceLocator:Register("PlayerDataService", PlayerDataService)

-- Get (any service)
local PDS = ServiceLocator:Get("PlayerDataService")

-- Async get (wait for availability)
ServiceLocator:GetAsync("PlayerDataService", function(service)
    service:DoSomething()
end, 10) -- 10s timeout
```

### 2. DataMapper

**Purpose:** Convert data between Roblox ↔ PocketBase

```lua
-- To Remote (Roblox → PocketBase)
local remoteData = DataMapper.ToRemote("PlayerData", robloxData, userId)
-- { coins: 100, level: 5, roblox_id: "123456" }

-- From Remote (PocketBase → Roblox)
local robloxData = DataMapper.FromRemote("PlayerData", remoteData)
-- { Coins = 100, Level = 5, OwnedItems = {...} }

-- Validate
local valid, errors = DataMapper.Validate("PlayerData", data)
```

### 3. IdempotencyKey

**Purpose:** Prevent duplicate operations

```lua
-- Generate key
local key = IdempotencyKey.Generate("sync", userId)

-- Execute with idempotency
IdempotencyKey:Execute(key, "PlayerSync", function()
    -- This runs only once per key
    return syncData()
end, 300) -- 5 min TTL

-- Check status
local status = IdempotencyKey:GetStatus(key)
-- "Processing" | "Complete" | "Failed" | "Expired"
```

### 4. ExecutionGuard

**Purpose:** Run function only once + lock management

```lua
local guard = ExecutionGuard.new(true) -- debug mode

-- Run once
guard:RunOnce("loadData", function()
    return loadPlayerData()
end, {
    timeout = 10,
    cacheResult = true,
    allowRerun = false
})

-- Manual lock
if guard:AcquireLock("myTask", 5) then
    -- Do work
    guard:ReleaseLock("myTask")
end
```

---

## Module Dependencies ✨UPDATED

```
ReplicatedStorage/
├── Shared/
│   ├── Events.luau          (No dependencies)
│   └── InputSettings.luau   (No dependencies)
│
├── SystemsShared/
│   └── EventBus.luau         (No dependencies)
│
└── Packages/                 ✨NEW
    ├── Promise.lua           (External: evaera_promise)
    └── Signal.lua            (External: sleitnick_signal)

Server/
├── Utils/                    ✨NEW
│   ├── ServiceLocator       (No dependencies)
│   ├── DataMapper           (No dependencies)
│   ├── IdempotencyKey       (→ HttpService)
│   ├── ExecutionGuard       (No dependencies)
│   └── IdempotentGuard      (No dependencies)
│
├── Core/
│   └── NetworkHandler       (→ EventBus, Events, ServiceLocator)
│
├── Cloud/                    ✨NEW
│   └── PocketBaseService    (→ HttpService, DataMapper, IdempotencyKey)
│
├── Data/                     ✨NEW
│   └── PlayerDataService    (→ ProfileService, PocketBaseService)
│
├── Player/
│   └── PlayerStateService   (→ ServiceLocator)
│
└── Gameplay/
    ├── CombatService         (→ ServiceLocator)
    ├── DownedService         (→ ServiceLocator)
    ├── RespawnService        (→ ServiceLocator)
    └── ...

Client/
├── Utils/
│   └── ControllerLocator     ✨NEW
│
├── Core/
│   └── NetworkController    (→ EventBus, Events)
│
├── Inputs/
│   └── InputHandler         (→ ControllerLocator, EventBus)
│
└── UI/
    └── HudController         (→ ControllerLocator, EventBus)
```

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

## Performance Considerations ✨UPDATED

### Memory

- ✅ Clean up listeners when objects destroyed
- ✅ Use object pooling for frequent spawns
- ✅ Limit event history size (max 100 errors)
- ✅ **NEW:** IdempotencyKey auto-cleanup (max 10k keys)
- ✅ **NEW:** ExecutionGuard caches results with TTL

### Network

- ✅ Batch events when possible
- ✅ Use priority queue (important events first)
- ✅ Rate limiting prevents spam
- ✅ **NEW:** PocketBase debouncing (5s)
- ✅ **NEW:** Retry logic with exponential backoff

### CPU

- ✅ Debounce rapid inputs
- ✅ Use task.defer() for non-urgent code
- ✅ Profile critical paths
- ✅ **NEW:** Parallel service initialization (4x faster boot)

### Data

- ✅ **NEW:** Dictionary-based inventory (O(1) lookup)
- ✅ **NEW:** ProfileService session locking
- ✅ **NEW:** Hybrid storage (fast local + VPS backup)

---

## Security Architecture ✨UPDATED

### Defense in Depth

```
Layer 1: Client Validation
  └─> Basic checks (cooldown, state, Downed blocking)

Layer 2: Network Security
  ├─> Rate limiting (per-event + global)
  ├─> Event allowlist
  └─> Payload sanitization

Layer 3: Server Validation
  ├─> Re-check cooldowns
  ├─> Validate game state (Downed, Combat, etc.)
  ├─> Check permissions
  └─> Verify data integrity

Layer 4: Data Security        ✨NEW
  ├─> Idempotency (prevent duplicate writes)
  ├─> Validation rules (min/max values)
  ├─> Type coercion
  └─> Schema versioning

Layer 5: Anti-Cheat
  ├─> Suspicious activity tracking
  ├─> Pattern detection
  └─> Auto-kick system
```

---

## Scalability ✨UPDATED

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
-- ✅ Cache frequently accessed data
local cache = {}
function getData(key)
    if cache[key] then return cache[key] end
    cache[key] = expensiveOperation(key)
    return cache[key]
end

-- ✅ NEW: Use ServiceLocator (singleton pattern)
local PDS = ServiceLocator:Get("PlayerDataService")
-- No need to require multiple times

-- ✅ NEW: Dictionary inventory (O(1) lookup)
if PlayerDataService:HasItem(player, itemId) then
    -- Instant check!
end
```

---

## Future Enhancements

1. ✅ **State Machine** for game states (Lobby → Playing → Downed → Dead)
2. **Ability System** with data-driven config
3. **Replay System** for match recordings
4. **Leaderboard System** with pagination (using PocketBase)
5. **Chat System** with filters
6. **Friend System** integration
7. **Clan/Guild System** (stored in PocketBase)
8. **Achievement System** (local + cloud sync)
9. **Cosmetic System** (inventory management)
10. **Shop System** (currency transactions)

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| **3.2** | 2024 | ✨ Data System, Init System, Utilities |
| **3.1** | 2024 | Combat → Downed → Respawn |
| **3.0** | 2024 | P0 Security Fixes |
| **2.0** | 2024 | Event-driven Architecture |
| **1.0** | 2024 | Initial Release |

---

**Version:** 3.2 - Production Ready  
**Last Updated:** 2024  
**Author:** OneShortArena Team  
**Status:** ✅ Ready for Production

**Related Documents:**
- [Data System Guide](./Data-System-Guide.md)
- [Init System Guide](./Init-System-Guide.md)
- [GUI Communication Guide](./GUI-Communication-Guide.md)
- [Combat Guide](./Combat-Downed-Respawn-Guide.md)
