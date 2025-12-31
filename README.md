# 🏟️ OneShortArena - Roblox Game

> **Production-grade multiplayer arena game built with modern Roblox architecture**

[![Roblox](https://img.shields.io/badge/Roblox-Ready-00A2FF?style=for-the-badge&logo=roblox)](https://www.roblox.com)
[![Luau](https://img.shields.io/badge/Luau-Strict-00A2FF?style=for-the-badge)](https://luau-lang.org/)
[![Architecture](https://img.shields.io/badge/Architecture-v3.1-success?style=for-the-badge)](./docs/deps.md)
[![Security](https://img.shields.io/badge/Security-P0_Fixed-success?style=for-the-badge)](./docs/Risk-Assessment.md)

---

## 📊 Project Status

| Component | Version | Status |
|-----------|---------|--------|
| **Core System** | 3.1 | ✅ Production Ready |
| **Combat System** | 1.0 | ✅ Production Ready |
| **Downed System** | 2.0 | ✅ Production Ready |
| **Respawn System** | 1.0 | ✅ Production Ready |
| **Security** | P0 Fixed | ✅ Hardened |
| **Documentation** | Complete | ✅ Full Coverage |

---

## 🎯 Features

### ✨ Core Gameplay
- 🏟️ **Lobby & Arena System** - Seamless player transitions
- ⚔️ **Combat System** - Damage detection & fatal hit handling
- 🦵 **Downed System** - Revive window before death
- 🔄 **Respawn System** - Configurable respawn delays
- 👥 **Multiplayer** - Support for multiple players
- 🎮 **Cross-Platform** - PC, Mobile, Console support

### 🔐 Security (P0 Fixed)
- ✅ **Multi-Layer Rate Limiting** - Global + Per-event
- ✅ **Race Condition Protection** - Atomic state transitions
- ✅ **Input Blocking** - Block inputs while Downed
- ✅ **Anti-Exploit** - Client authority removed
- ✅ **Memory Leak Prevention** - Automatic cleanup

### 🏗️ Architecture
- 📦 **Modular Services** - Separation of concerns
- 🔄 **Event-Driven** - EventBus pattern
- 🛡️ **Idempotent Guards** - Prevent double init/start
- 📡 **Centralized Config** - NetworkConfig.luau
- 📊 **Analytics** - Built-in tracking

---

## 📊 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    SYSTEM ARCHITECTURE v3.1                      │
└─────────────────────────────────────────────────────────────────┘

📱 Client Layer (StarterPlayerScripts)
├── Core/
│   └── NetworkController    - Network transport
├── Inputs/
│   ├── InputController      - Hardware input detection
│   └── InputHandler         - Game logic + Downed blocking
├── Gameplay/
│   └── PlayerStateController - State sync
├── UI/
│   └── LobbyGuiController   - UI buttons + Downed visual
└── Dev/
    └── TestHandler          - Debug tools

🖥️ Server Layer (ServerScriptService)
├── Core/
│   └── NetworkHandler       - Security & validation
├── Player/
│   └── PlayerStateService   - State management (Locks)
└── Gameplay/
    ├── ArenaService         - Arena spawning
    ├── CombatService        - Damage & fatal hit detection
    ├── CooldownService      - Cooldown management
    ├── DeathService         - Death detection & classification
    ├── DownedService        - Downed state lifecycle
    ├── GameService          - Game logic
    ├── LobbyService         - Lobby spawning
    ├── MatchService         - Match management
    └── RespawnService       - Respawn scheduling
```

[📚 Full Architecture Docs](./docs/deps.md)

---

## 🎮 Combat → Downed → Respawn Flow

```
  ผู้เล่นโดนโจมตี
       │
       ▼
┌──────────────┐
│ CombatService │  ← 1. ตรวจจับ Damage
└──────────────┘  ← 2. เช็ค Fatal Hit (HP <= 0)
       │
       │ HP <= 0?
       ▼
┌──────────────┐
│ DownedService │  ← 3. เข้าสถานะ Downed
│   🦵          │  ← 4. นับถอยหลัง 15s
└──────────────┘  ← 5. Block inputs
       │
       │ Timeout / Finished / Revived?
       ▼
┌──────────────┐
│RespawnService │  ← 6. Schedule Respawn (3-5s)
└──────────────┘  ← 7. Emit PLAYER_RESPAWN_REQUESTED
       │
       ▼
┌──────────────┐
│ LobbyService  │  ← 8. Spawn ผู้เล่นที่ Lobby
└──────────────┘
```

[📚 Full Combat Guide](./docs/Combat-Downed-Respawn-Guide.md)

---

## 🚀 Getting Started

### Prerequisites

- [Rojo](https://github.com/rojo-rbx/rojo) 7.6.1+
- [Roblox Studio](https://www.roblox.com/create)
- Git (for version control)

### Installation

```bash
# 1. Clone repository
git clone https://github.com/yourusername/OneShortArena-Roblox.git
cd OneShortArena-Roblox

# 2. Setup secret config (REQUIRED!)
cd src/ServerStorage/Secrets
cp PocketBaseSecret.template.luau PocketBaseSecret.luau

# 3. แก้ไข PocketBaseSecret.luau ให้ตรงกับ Database ของคุณ
# ⚠️ DO NOT COMMIT THIS FILE!

# 4. Build project
rojo build -o "OneShortArena.rbxlx"

# 5. Open in Roblox Studio
# File > Open > OneShortArena.rbxlx
```

### 🔐 Secret Configuration

ก่อนใช้งาน PocketBase Service, คุณต้อง:

1. สร้างโฟลเดอร์ `ServerStorage/Secrets/` (ไม่ถูก commit)
2. Copy `PocketBaseSecret.template.luau` → `PocketBaseSecret.luau`
3. แก้ไขข้อมูล:
   - `URL` - PocketBase API URL
   - `ADMIN_EMAIL` - Admin email
   - `ADMIN_PASS` - Admin password

⚠️ **IMPORTANT:** ไฟล์ `PocketBaseSecret.luau` จะ**ไม่ถูก commit** ตาม `.gitignore`

### Development Workflow

```bash
# Start Rojo live sync
rojo serve

# In Roblox Studio:
# Plugins > Rojo > Connect
```

---

## 📁 Project Structure

```
OneShortArena-Roblox/
├── 📁 src/
│   ├── ReplicatedStorage/
│   │   ├── Shared/                    # Shared constants
│   │   │   ├── Events.luau
│   │   │   └── InputSettings.luau
│   │   ├── SystemsShared/
│   │   │   └── EventBus.luau
│   │   └── Utils/
│   │       └── IdempotentGuard.luau
│   │
│   ├── ServerStorage/
│   │   └── Configs/
│   │       └── NetworkConfig.luau
│   │
│   ├── ServerScriptService/
│   │   ├── Init.server.luau
│   │   ├── Services/
│   │   │   ├── Core/
│   │   │   │   └── NetworkHandler.luau
│   │   │   ├── Player/
│   │   │   │   └── PlayerStateService.luau
│   │   │   └── Gameplay/
│   │   │       ├── ArenaService.luau
│   │   │       ├── CombatService.luau      # NEW
│   │   │       ├── CooldownService.luau
│   │   │       ├── DeathService.luau
│   │   │       ├── DownedService.luau      # NEW
│   │   │       ├── GameService.luau
│   │   │       ├── LobbyService.luau
│   │   │       ├── MatchService.luau
│   │   │       └── RespawnService.luau     # NEW
│   │   └── Utils/
│   │       ├── IdempotentGuard.luau
│   │       └── ExecutionGuard.luau
│   │
│   └── StarterPlayer/
│       └── StarterPlayerScripts/
│           ├── Init.client.luau
│           ├── Core/
│           │   └── NetworkController.luau
│           ├── Inputs/
│           │   ├── InputController.luau
│           │   └── InputHandler.luau       # + Downed blocking
│           ├── Gameplay/
│           │   └── PlayerStateController.luau
│           ├── UI/
│           │   └── LobbyGuiController.luau # + Downed visual
│           └── Dev/
│               └── TestHandler.luau
│
└── 📁 docs/
    ├── deps.md
    ├── Combat-Downed-Respawn-Guide.md      # NEW
    ├── Lobby-to-Arena-Guide.md
    ├── Risk-Assessment.md
    └── NetworkConfig-Guide.md
```

---

## 🔒 Security - 7 Layer Protection

```
┌─────────────────────────────────────────────────────────────────┐
│  🛡️ 7 LAYERS OF PROTECTION                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Layer 1: 🖼️ UI Cooldown (1s)                                   │
│  Layer 2: 📡 Per-Event Rate Limit (1/5s)                        │
│  Layer 3: 🔢 Global Rate Limit (10/5s)                          │
│  Layer 4: 🔐 Transition Lock (atomic)                           │
│  Layer 5: ⏱️ Transition Cooldown (2s)                           │
│  Layer 6: 🚀 Teleport Cooldown (5s)                             │
│  Layer 7: ⚔️ Combat Check (5s)                                  │
│                                                                 │
│  + 🦵 Downed Input Blocking (blocks Play/Attack while Downed)   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🧪 Debug Commands (F9 Console)

```lua
-- Check player state
_G.Services.PlayerStateService:GetState(player)

-- Check if downed
_G.Services.DownedService:IsPlayerDowned(player)

-- Get downed countdown
_G.Services.DownedService:GetRemainingTime(player)

-- Check combat status
_G.Services.CombatService:IsPlayerInCombat(player)

-- Cancel respawn
_G.Services.RespawnService:CancelRespawn(player)

-- Get analytics
_G.Services.DownedService:GetAnalytics()
_G.Services.CombatService:GetAnalytics()
_G.Services.RespawnService:GetAnalytics()
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [deps.md](./docs/deps.md) | Architecture & dependencies |
| [Combat-Downed-Respawn-Guide.md](./docs/Combat-Downed-Respawn-Guide.md) | **NEW** Combat system |
| [Lobby-to-Arena-Guide.md](./docs/Lobby-to-Arena-Guide.md) | Teleport system |
| [Risk-Assessment.md](./docs/Risk-Assessment.md) | Security audit |
| [NetworkConfig-Guide.md](./docs/NetworkConfig-Guide.md) | Rate limiting |

---

## 🔒 P0 Security Issues - ALL FIXED ✅

| Issue | Service | Status |
|-------|---------|--------|
| Race Condition | PlayerStateService | ✅ Transition locks |
| Teleport Exploit | ArenaService | ✅ Multi-layer cooldowns |
| Memory Leak | All Services | ✅ PlayerRemoving cleanup |
| Damage Spam | CombatService | ✅ Processing locks |
| Double Downed | DownedService | ✅ Atomic locks |
| Input During Downed | InputHandler | ✅ Input blocking |

---

## 📝 Changelog

### Version 3.1 (Current)
- ✅ **CombatService** - Damage & fatal hit detection
- ✅ **DownedService** - Revive window system
- ✅ **RespawnService** - Configurable respawn delays
- ✅ **Input Blocking** - Block inputs while Downed
- ✅ **Visual Feedback** - Downed button states

### Version 3.0
- ✅ P0 security fixes
- ✅ NetworkConfig centralization
- ✅ Per-event rate limiting

### Version 2.0
- Event-driven architecture
- PlayerStateService
- ArenaService & LobbyService

---

**Built with ❤️ using Roblox Studio & Modern Architecture**

[![Production](https://img.shields.io/badge/Status-Production_Ready-success?style=flat-square)](./docs/Risk-Assessment.md)
