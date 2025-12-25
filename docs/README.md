# 📚 OneShortArena - Technical Documentation

## 🎯 Overview

**OneShortArena** เป็นเกม Roblox แนว Combat Arena ที่ใช้สถาปัตยกรรม **Production-Grade** พร้อมระบบ:
- ✅ Client-Server Architecture แบบแยกชั้น
- ✅ Event-Driven System
- ✅ Network Security & Anti-Cheat
- ✅ Modular Design Pattern

---

## 📖 Table of Contents

1. [Project Structure](#project-structure)
2. [Architecture Overview](#architecture-overview)
3. [Core Systems](#core-systems)
4. [Getting Started](#getting-started)
5. [Development Guide](#development-guide)

---

## Project Structure

```
OneShortArena-Roblox/
├── src/
│   ├── ReplicatedStorage/
│   │   ├── Shared/              # Shared modules (Client & Server)
│   │   │   ├── Events.luau      # Event constants
│   │   │   └── InputSettings.luau
│   │   └── SystemsShared/       # Shared systems
│   │       ├── EventBus.luau    # Event bus system
│   │       └── Network/         # Network remotes
│   │
│   ├── ServerScriptService/
│   │   ├── Init.server.luau     # Server entry point
│   │   └── Services/            # Server-side services
│   │       ├── NetworkHandler.luau    # Network security
│   │       ├── GameService.luau       # Game logic
│   │       ├── ArenaService.luau      # Arena management
│   │       ├── CooldownService.luau   # Cooldown system
│   │       └── DemoService.luau       # (Dev only)
│   │
│   └── StarterPlayer/
│       └── StarterPlayerScripts/
│           ├── Init.client.luau      # Client entry point
│           └── Controllers/          # Client-side controllers
│               ├── NetworkController.luau  # Network client
│               ├── InputController.luau    # Input detection
│               ├── InputHandler.luau       # Input logic
│               ├── AbilityController.luau  # Abilities
│               ├── DemoController.luau     # (Dev only)
│               └── TestController.luau     # (Dev only)
│
└── docs/                         # Documentation
    ├── README.md                 # This file
    ├── Architecture.md           # System architecture
    ├── NetworkSystem.md          # Network documentation
    ├── InputSystem.md            # Input system
    └── DevelopmentGuide.md       # Dev guide
```

---

## Architecture Overview

### 🏗️ Layer Architecture

```
┌─────────────────────────────────────────┐
│         Player Input (Hardware)          │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│      InputController (Detection)         │  ◄─── Low-level
│  - Detect Tap, Hold, DoubleTap          │
│  - Input buffering for combos           │
└──────────────┬──────────────────────────┘
               │ INPUT_ACTION event
┌──────────────▼──────────────────────────┐
│       InputHandler (Game Logic)          │  ◄─── Game-specific
│  - Convert to game commands              │
│  - Cooldown check                        │
│  - State validation                      │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│     NetworkController (Client Net)       │  ◄─── Network layer
│  - Send to server                        │
│  - Reliable send with ACK                │
│  - Auto-retry system                     │
└──────────────┬──────────────────────────┘
               │ RemoteEvent
┌──────────────▼──────────────────────────┐
│     NetworkHandler (Server Net)          │  ◄─── Server layer
│  - Security validation                   │
│  - Rate limiting                         │
│  - Anti-replay protection                │
└──────────────┬──────────────────────────┘
               │ EventBus
┌──────────────▼──────────────────────────┐
│        Game Services (Business)          │  ◄─── Business logic
│  - GameService, ArenaService             │
│  - Process game logic                    │
└───────────────────────────────────────────┘
```

### 🔄 Event Flow

**Normal Action:**
```
Player Input → InputController → EventBus (INPUT_ACTION)
    → InputHandler → NetworkController → Server
    → NetworkHandler → GameService → Process
```

**Reliable Action (Important):**
```
Player Input → InputController → EventBus
    → InputHandler → NetworkController.SendReliable()
    → Server receives + validates
    → Server sends ACK back
    → Client confirms delivery
    (If no ACK: Auto-retry up to 3 times)
```

---

## Core Systems

### 1. 📡 Network System
- **Production-grade** security
- Message acknowledgment (ACK)
- Auto-retry mechanism
- Anti-replay protection
- Analytics tracking

📄 [Full Documentation →](./NetworkSystem.md)

### 2. 🎮 Input System
- **2-layer architecture**: Detection + Logic
- Advanced pattern detection (Hold, DoubleTap, Combo)
- Cross-platform support (PC, Mobile, Console)
- Debounce protection

📄 [Full Documentation →](./InputSystem.md)

### 3. 🎯 Event Bus System
- Decoupled event communication
- Type-safe events
- Debugging support

📄 [Full Documentation →](./Architecture.md#event-bus)

### 4. 🛡️ Security System
- Rate limiting (per-player & global)
- Event validation
- Suspicious activity tracking
- Auto-kick system

📄 [Full Documentation →](./NetworkSystem.md#security)

---

## Getting Started

### Prerequisites
- Roblox Studio (latest version)
- Rojo (optional, for VS Code sync)
- Basic Luau knowledge

### Installation

1. **Clone Repository**
   ```bash
   git clone [repository-url]
   cd OneShortArena-Roblox
   ```

2. **Open in Roblox Studio**
   - Open `OneShortArena.rbxl`
   - Or use Rojo: `rojo serve`

3. **Configure Production Mode**
   ```lua
   -- ServerScriptService/Init.server.luau
   local IS_PRODUCTION = false  -- Dev mode
   
   -- StarterPlayerScripts/Init.client.luau
   local IS_PRODUCTION = false  -- Dev mode
   ```

4. **Test**
   - Press F5 to test locally
   - Check console for initialization logs

---

## Development Guide

### Adding New Event

1. **Define event in Events.luau**
   ```lua
   -- ReplicatedStorage/Shared/Events.luau
   Events.YOUR_NEW_EVENT = "YourNewEvent"
   ```

2. **Allow event (Server)**
   ```lua
   -- ServerScriptService/Services/NetworkHandler.luau
   NetworkHandler:AllowClientEvent(Events.YOUR_NEW_EVENT)
   ```

3. **Send from Client**
   ```lua
   -- Client controller
   NetworkController:Send(Events.YOUR_NEW_EVENT, {
       data = "example"
   })
   ```

4. **Handle on Server**
   ```lua
   -- Server service
   EventBus:On(Events.YOUR_NEW_EVENT, function(player, data)
       print(`Received from {player.Name}:`, data)
   end)
   ```

### Adding New Ability

📄 See: [Development Guide →](./DevelopmentGuide.md#adding-abilities)

### Production Deployment

1. **Enable Production Mode**
   ```lua
   local IS_PRODUCTION = true
   ```

2. **Remove Debug Code**
   - DemoController, TestController auto-skipped
   - DemoService auto-skipped

3. **Verify Security**
   ```lua
   -- Check rate limits
   NetworkHandler:Configure({
       maxPerWindow = 10,  -- Adjust as needed
       debug = false
   })
   ```

4. **Test in Private Server**
   - Test all critical paths
   - Monitor Analytics dashboard
   - Check for suspicious activity

5. **Publish**
   - File → Publish to Roblox
   - Update game description
   - Monitor logs

---

## Architecture Principles

### ✅ DO

1. **Use Event-Driven Communication**
   ```lua
   EventBus:Emit(Events.SOMETHING_HAPPENED, data)
   ```

2. **Validate on Server**
   ```lua
   -- Server always validates
   if not isValid(data) then return end
   ```

3. **Separate Concerns**
   - InputController = Hardware detection
   - InputHandler = Game logic
   - NetworkController = Network transport

4. **Use Reliable Send for Important Data**
   ```lua
   NetworkController:SendReliable(Events.PURCHASE, data)
   ```

### ❌ DON'T

1. **Don't Trust Client**
   ```lua
   -- ❌ BAD
   player.Coins = player.Coins + 100  -- Client can modify
   
   -- ✅ GOOD
   ServerData:AddCoins(player, 100)   -- Server validates
   ```

2. **Don't Skip Validation**
   ```lua
   -- Always validate
   NetworkHandler:RegisterValidator(eventName, validator)
   ```

3. **Don't Spam Events**
   ```lua
   -- ❌ BAD: 100 events per second
   -- ✅ GOOD: Batch or throttle
   ```

---

## Performance Guidelines

### Client

- ✅ Batch UI updates (max 30 FPS)
- ✅ Use object pooling for VFX
- ✅ Debounce input (0.1s minimum)
- ✅ Clean up listeners on destroy

### Server

- ✅ Use DataStore cache
- ✅ Limit event processing (rate limiting enabled)
- ✅ Profile critical paths
- ✅ Monitor Analytics dashboard

### Network

- ✅ Send only necessary data
- ✅ Use Reliable Send sparingly
- ✅ Compress large payloads
- ✅ Monitor EPS (Events Per Second)

---

## Debugging

### Enable Debug Mode

```lua
-- Server
NetworkHandler:Configure({ debug = true })

-- Client
local DEBUG = true
```

### Common Issues

**Event not reaching server?**
```lua
-- 1. Check allowlist
NetworkHandler:AllowClientEvent(Events.YOUR_EVENT)

-- 2. Check rate limit
local stats = NetworkController:GetStats()
print(stats.pendingMessages)  -- Should be 0

-- 3. Retry
NetworkController:RetryAllPending()
```

**Performance issues?**
```lua
-- Check Analytics
local analytics = NetworkHandler:GetAnalytics()
print("EPS:", analytics.eventsPerSecond)  -- Should be < 50

-- Check Health
local health = NetworkHandler:GetNetworkHealth()
print("Status:", health.status)  -- Should be "Healthy"
```

---

## Testing

### Unit Tests (Future)
```lua
-- tests/InputController.spec.luau
```

### Integration Tests
```lua
-- Manual testing checklist:
-- ✅ Input detection works
-- ✅ Network sends/receives
-- ✅ Security blocks exploits
-- ✅ Analytics tracking works
```

---

## Contributing

1. Fork repository
2. Create feature branch
3. Follow code style (strict mode)
4. Add documentation
5. Test thoroughly
6. Submit pull request

---

## Resources

- 📄 [Network System](./NetworkSystem.md)
- 📄 [Input System](./InputSystem.md)
- 📄 [Architecture Deep Dive](./Architecture.md)
- 📄 [Development Guide](./DevelopmentGuide.md)
- 🎮 [Roblox API Reference](https://create.roblox.com/docs)

---

## License

[Your License Here]

---

## Support

- 💬 Discord: [Your Discord]
- 📧 Email: [Your Email]
- 🐛 Issues: [GitHub Issues]

---

**Version:** 2.0 - Production Grade  
**Last Updated:** 2024  
**Maintained by:** OneShortArena Team
