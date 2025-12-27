# 📐 OneShortArena - System Architecture

## 🎯 Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    ROBLOX GAME ARCHITECTURE                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐         ┌─────────────┐         ┌───────────┐ │
│  │   CLIENT    │ ◄─────► │   NETWORK   │ ◄─────► │  SERVER   │ │
│  │  (Player)   │         │  (RemoteEvent)│        │ (Validate)│ │
│  └─────────────┘         └─────────────┘         └───────────┘ │
│        │                        │                       │        │
│        │                        │                       │        │
│        ▼                        ▼                       ▼        │
│  ┌─────────────┐         ┌─────────────┐         ┌───────────┐ │
│  │ Controllers │         │  EventBus   │         │ Services  │ │
│  └─────────────┘         └─────────────┘         └───────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📦 Component Structure

### 🔵 CLIENT SIDE (StarterPlayerScripts)

```
StarterPlayerScripts/
├── Init.client.luau              [ENTRY POINT]
└── Controllers/
    ├── NetworkController.luau    [✅ ACTIVE]
    ├── DemoController.luau       [✅ DEMO]
    ├── UIController.luau         [🔨 TODO]
    └── InputController.luau      [🔨 TODO]
```

**Controllers Status:**

| Controller | Status | Purpose | Dependencies |
|------------|--------|---------|--------------|
| **NetworkController** | ✅ Active | Client ↔ Server communication | EventBus, Events, RemoteEvent |
| **DemoController** | ✅ Demo | Network testing & examples | NetworkController, EventBus |
| **UIController** | 🔨 TODO | UI state management | EventBus |
| **InputController** | 🔨 TODO | Player input handling | NetworkController |

---

### 🔴 SERVER SIDE (ServerScriptService)

```
ServerScriptService/
├── Init.server.luau              [ENTRY POINT]
└── Services/
    ├── NetworkHandler.luau       [✅ ACTIVE] - Security Layer
    ├── GameService.luau          [✅ ACTIVE] - Game State
    ├── ArenaService.luau         [✅ ACTIVE] - Arena Management
    ├── CombatService.luau        [✅ ACTIVE] - Combat Validation
    ├── DemoService.luau          [✅ DEMO]   - Testing
    └── ProfileService.luau       [🔨 TODO]   - Data Persistence
```

**Services Status:**

| Service | Status | Purpose | Key Features |
|---------|--------|---------|--------------|
| **NetworkHandler** | ✅ Active | Network security & validation | Rate limiting, payload validation, event whitelist |
| **GameService** | ✅ Active | Game lifecycle management | Round control, player state |
| **ArenaService** | ✅ Active | Arena setup & cleanup | Map management |
| **CombatService** | ✅ Active | Combat logic validation | Damage calculation, hit detection |
| **DemoService** | ✅ Demo | Network testing service | Ping/Pong, data requests |
| **ProfileService** | 🔨 TODO | Player data persistence | Save/load, inventory |

---

### 🟠 SHARED SYSTEMS (ReplicatedStorage)

```
ReplicatedStorage/
├── SystemsShared/
│   ├── EventBus.luau            [✅ ACTIVE] - Event System
│   └── Network/
│       └── NetworkBridge        [✅ AUTO-CREATED] - RemoteEvent
│
└── Shared/
    ├── Events.luau              [✅ ACTIVE] - Event Constants
    └── Configs/                 [🔨 TODO]   - Game Configs
```

**Shared Components:**

| Component | Type | Purpose | Created By |
|-----------|------|---------|------------|
| **EventBus** | System | Internal event communication | Manual |
| **NetworkBridge** | RemoteEvent | Client ↔ Server RPC | NetworkHandler (runtime) |
| **Events** | Constants | Event name registry | Manual |

---

## 🔄 Data Flow Diagrams

### 📤 Client → Server Flow

```
[Player Action]
      │
      ▼
[InputController] ──┐
                    │
[UIController] ─────┤
                    │
                    ▼
         [NetworkController]
                    │
                    │ NetworkController:Send()
                    ▼
         ┌──────────────────┐
         │  NetworkBridge   │
         │  (RemoteEvent)   │
         └──────────────────┘
                    │
                    │ :FireServer()
                    ▼
         [NetworkHandler]
                    │
                    ├─► Rate Limit Check
                    ├─► Payload Validation
                    ├─► Event Whitelist
                    └─► Sequence Check
                    │
                    ▼
            [EventBus:Emit]
                    │
         ┌──────────┼──────────┐
         ▼          ▼          ▼
    [GameService] [Arena] [Combat]
```

### 📥 Server → Client Flow

```
[Server Event]
      │
      ▼
[GameService/ArenaService/CombatService]
      │
      │ NetworkHandler:SendToClient()
      │ NetworkHandler:Broadcast()
      ▼
[NetworkHandler]
      │
      ├─► Event Whitelist Check
      └─► Payload Sanitization
      │
      ▼
┌──────────────────┐
│  NetworkBridge   │
│  (RemoteEvent)   │
└──────────────────┘
      │
      │ :FireClient() / :FireAllClients()
      ▼
[NetworkController]
      │
      ▼
[EventBus:Emit]
      │
      ├─► UIController
      ├─► InputController
      └─► DemoController
```

---

## 🔐 Security Architecture

### NetworkHandler Protection Layers

```
┌─────────────────────────────────────────┐
│        CLIENT REQUEST ARRIVES           │
└─────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  Layer 1: Type Validation               │
│  • Is eventName a string?               │
└─────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  Layer 2: Event Whitelist               │
│  • Is this event allowed from client?   │
└─────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  Layer 3: Rate Limiting                 │
│  • Global: 100 events/sec               │
│  • Per-player: 10 events/5 sec          │
│  • Burst: max 3 in 0.5 sec              │
└─────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  Layer 4: Sequence Validation           │
│  • Did required events happen first?    │
└─────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  Layer 5: Payload Sanitization          │
│  • Max depth: 3                         │
│  • Max table size: 32                   │
│  • Max string: 500 chars                │
│  • No functions, Instances, etc.        │
└─────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  Layer 6: Custom Validators             │
│  • Event-specific business logic        │
└─────────────────────────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│         ✅ REQUEST ACCEPTED             │
│      Emit to EventBus → Services        │
└─────────────────────────────────────────┘
```

**Suspicious Activity Tracking:**
- 3+ violations → Warning logged
- 5+ violations → Auto-kick

---

## 📋 Event Registry

### Game Events (Events.luau)

| Category | Event Name | Direction | Purpose |
|----------|-----------|-----------|---------|
| **Game Lifecycle** | GAME_START_REQUESTED | C→S | Player requests game start |
| | GAME_STARTED | S→C | Server starts game |
| | GAME_ENDED | S→C | Server ends game |
| | GAME_STATE_UPDATE | S→C | Periodic state sync |
| **Player** | PLAYER_REQUEST_PLAY | C→S | Join game request |
| | JOIN_SUCCESS | S→C | Join confirmed |
| | JOIN_FAILED | S→C | Join rejected |
| **UI** | TOGGLE_UI | C→S | UI visibility request |
| | UI_SHOW_NOTIFICATION | S→C | Show notification |
| | UI_UPDATE_SCORE | S→C | Update score display |
| | UI_UPDATE_HEALTH | S→C | Update health display |
| **Combat** | INPUT_ACTION | C→S | Player combat input |
| **Demo** | DEMO_PING | C→S | Test latency |
| | DEMO_PONG | S→C | Ping response |
| | DEMO_REQUEST_DATA | C→S | Request server data |
| | DEMO_SEND_DATA | S→C | Send requested data |
| | DEMO_CHAT_MESSAGE | C→S | Send chat message |
| | DEMO_BROADCAST_MESSAGE | S→C | Broadcast chat |
| | DEMO_BUTTON_CLICKED | C→S | Button interaction |
| | DEMO_UPDATE_COUNTER | S→C | Counter update |

**Direction Legend:**
- `C→S` = Client to Server
- `S→C` = Server to Client (specific player)
- `S→*` = Server to All Clients (broadcast)

---

## 🚀 Initialization Sequence

### Server Startup

```
1. Init.server.luau starts
   │
   ├─► Load Services
   │   ├─► NetworkHandler
   │   ├─► GameService
   │   ├─► ArenaService
   │   ├─► CombatService
   │   └─► DemoService
   │
2. NetworkHandler:Init()
   │   └─► Create Network folder
   │       └─► Create NetworkBridge RemoteEvent
   │
3. All Services:Init()
   │   └─► Setup variables
   │       └─► Register validators
   │
4. All Services:Start()
   │   └─► Connect EventBus listeners
   │       └─► Start background tasks
   │
5. ✅ Server Ready
```

### Client Startup

```
1. Init.client.luau starts
   │
   ├─► Load Controllers
   │   ├─► NetworkController
   │   └─► DemoController
   │
2. NetworkController:Init()
   │   └─► Wait for Network/NetworkBridge (30s timeout)
   │       └─► Connect OnClientEvent
   │
3. DemoController:Init()
   │   └─► Setup variables
   │
4. All Controllers:Start()
   │   └─► Connect EventBus listeners
   │       └─► Start auto-ping (demo)
   │
5. ✅ Client Ready
```

---

## 🧪 Testing Commands

### Using DemoController

Open Developer Console (F9) and run:

```lua
-- Access demo controller
local demo = _G.DemoController

-- Test 1: Ping-Pong (latency test)
demo:SendPing()

-- Test 2: Request player stats
demo:RequestData("stats")

-- Test 3: Request server info
demo:RequestData("server")

-- Test 4: Send chat message
demo:SendChatMessage("Hello World!")

-- Test 5: Simulate button click
demo:ClickButton("TestButton")

-- Test 6: Run all tests
demo:RunTests()
```

### Expected Console Output

**Client:**
```
[DemoController] 📤 Sending PING to server...
[DemoController] 🏓 Received PONG from server:
  • Server Time: 123.456
  • Latency: 15ms
  • Message: Pong! 🏓
```

**Server:**
```
[DemoService] 📨 Received PING from Player1 at 123.441
[DemoService] ✅ Sent PONG to Player1 (latency: 15ms)
```

---

## 📊 Dependency Table

| Component | Depends On | Used By |
|-----------|-----------|---------|
| **Signal** (Package) | - | EventBus |
| **EventBus** | Signal | All Services, All Controllers |
| **Events** | - | All Services, All Controllers |
| **NetworkBridge** | - | NetworkHandler, NetworkController |
| **NetworkHandler** | EventBus, Events | All Services |
| **NetworkController** | EventBus, Events, NetworkBridge | All Controllers |
| **GameService** | EventBus, Events, NetworkHandler | - |
| **ArenaService** | EventBus, Events, NetworkHandler | - |
| **CombatService** | EventBus, Events, NetworkHandler | - |
| **DemoService** | EventBus, Events, NetworkHandler | - |
| **DemoController** | EventBus, Events, NetworkController | - |

---

## 📁 File Structure Summary

```
OneShortArena-Roblox/
│
├── src/
│   ├── ServerScriptService/
│   │   ├── Init.server.luau              ← Server Entry Point
│   │   └── Services/
│   │       ├── NetworkHandler.luau       ✅
│   │       ├── GameService.luau          ✅
│   │       ├── ArenaService.luau         ✅
│   │       ├── CombatService.luau        ✅
│   │       ├── DemoService.luau          ✅
│   │       └── ProfileService.luau       🔨
│   │
│   ├── StarterPlayer/
│   │   └── StarterPlayerScripts/
│   │       ├── Init.client.luau          ← Client Entry Point
│   │       └── Controllers/
│   │           ├── NetworkController.luau ✅
│   │           ├── DemoController.luau    ✅
│   │           ├── UIController.luau      🔨
│   │           └── InputController.luau   🔨
│   │
│   └── ReplicatedStorage/
│       ├── SystemsShared/
│       │   ├── EventBus.luau             ✅
│       │   └── Network/                  (Auto-created)
│       │       └── NetworkBridge         ✅ (RemoteEvent)
│       │
│       └── Shared/
│           ├── Events.luau               ✅
│           └── Configs/                  🔨
│
├── docs/
│   ├── deps.md                           ← This file
│   └── api-reference.md                  🔨
│
└── .github/
    └── agents/
        └── gameplay-backend.md           ← Backend Agent Instructions
```

**Legend:**
- ✅ = Implemented & Working
- 🔨 = Planned/TODO
- ← = Entry Point

---

## 🎓 Learning Resources

### For New Developers

1. **Start Here:**
   - Read `src/ServerScriptService/Services/DemoService.luau`
   - Read `src/StarterPlayerScripts/Controllers/DemoController.luau`
   - Run the demo commands in testing section

2. **Understand Data Flow:**
   - See "Data Flow Diagrams" section above
   - Trace a DEMO_PING from client to server and back

3. **Security:**
   - Read "Security Architecture" section
   - Study NetworkHandler validation layers

4. **Create New Service:**
   - Follow template in `.github/agents/gameplay-backend.md`
   - Add events to `Events.luau`
   - Register in `Init.server.luau`

---

## 📞 Support

- **Backend Issues:** See `.github/agents/gameplay-backend.md`
- **Network Issues:** Check NetworkHandler logs
- **Testing:** Use DemoService & DemoController

---

*Last Updated: 2024*
*Architecture Version: 1.0*