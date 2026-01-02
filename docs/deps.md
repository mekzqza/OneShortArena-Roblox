# 🏗️ OneShortArena - สถาปัตยกรรมระบบ v3.2

## 🎯 เข้าใจง่ายใน 1 นาที

```
🎮 เกมนี้ทำงานยังไง?

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   👦 ผู้เล่น กดปุ่ม "Play"                                     ║
║      │                                                        ║
║      ▼                                                        ║
║   📱 Client ส่งข้อความไป Server                               ║
║      │                                                        ║
║      ▼                                                        ║
║   🔒 Server ตรวจสอบ "ส่งบ่อยไปมั้ย? โกงมั้ย?"                 ║
║      │                                                        ║
║      ▼                                                        ║
║   ✅ OK! ย้ายผู้เล่นไป Arena!                                  ║
║      │                                                        ║
║      ▼                                                        ║
║   ⚔️ สู้กัน! → 🦵 Downed! → 💀 ตาย! → 🔄 Respawn!             ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

---

## 📊 Version Info

| ส่วน | เวอร์ชัน | สถานะ |
|------|---------|-------|
| สถาปัตยกรรม | 3.2 | ✅ พร้อมใช้งานจริง |
| Data System | 1.0 | ✅ Production |
| CombatService | 1.0 | ✅ Production |
| DownedService | 2.0 | ✅ Production |
| RespawnService | 1.0 | ✅ Production |
| Utilities | 1.0 | ✅ Production |
| ความปลอดภัย | P0 Fixed | ✅ แก้ไขแล้ว |

---

## 🖼️ ภาพรวมระบบ

```
┌─────────────────────────────────────────────────────────────────┐
│                     🎮 OneShortArena v3.2                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐        ┌──────────────────┐              │
│  │   📱 CLIENT      │◄──────►│   🖥️ SERVER      │              │
│  │   (ผู้เล่น)       │ Network │   (เจ้าของเกม)   │              │
│  └──────────────────┘        └──────────────────┘              │
│                                                                 │
│  Client ทำอะไร?              Server ทำอะไร?                     │
│  • กดปุ่ม                    • ตรวจสอบโกง                       │
│  • แสดงผล                    • ย้ายผู้เล่น                       │
│  • ส่งคำสั่ง                  • จัดการ Combat                    │
│  • Block input               • จัดการ Downed                    │
│                              • จัดการ Respawn                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🏠 โครงสร้างไฟล์

```
📂 OneShortArena-Roblox/
│
├── 📂 src/
│   │
│   ├── 📂 Client (StarterPlayerScripts) 📱
│   │   ├── 📂 Core/
│   │   │   └── 📡 NetworkController
│   │   ├── 📂 Inputs/
│   │   │   ├── 🎮 InputController
│   │   │   └── 🧠 InputHandler
│   │   ├── 📂 Gameplay/
│   │   │   └── 📍 PlayerStateController
│   │   ├── 📂 UI/
│   │   │   └── 🖼️ LobbyGuiController
│   │   └── 📂 Dev/
│   │       └── 🧪 TestHandler
│   │
│   ├── 📂 Server (ServerScriptService) 🖥️
│   │   ├── 📂 Core/
│   │   │   └── 🔒 NetworkHandler
│   │   ├── 📂 Data/
│   │   │   └── 🗄️ PlayerDataService
│   │   ├── 📂 Cloud/
│   │   │   └── ☁️ PocketBaseService
│   │   ├── 📂 Player/
│   │   │   └── 📍 PlayerStateService
│   │   └── 📂 Gameplay/
│   │       ├── 🏟️ ArenaService
│   │       ├── ⚔️ CombatService
│   │       ├── 🦵 DownedService
│   │       ├── 🔄 RespawnService
│   │       └── ... (other services)
│   │
│   └── 📂 Shared (ReplicatedStorage) 🤝
│       ├── 📋 Events.luau
│       └── 📡 EventBus.luau
│
└── 📂 docs/ 📚
```

---

## 🎬 Combat → Downed → Respawn Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  ⚔️ COMBAT → DOWNED → RESPAWN FLOW                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. ผู้เล่นโดนโจมตี                                              │
│     │                                                          │
│     ▼                                                          │
│  ⚔️ CombatService (รับ PLAYER_DAMAGED)                          │
│     │                                                          │
│     ▼                                                          │
│  📢 Emit: PLAYER_FATAL_HIT (ถ้า HP <= 0)                        │
│     │                                                          │
│     ▼                                                          │
│  🦵 DownedService                                               │
│     • State = "Downed"                                         │
│     • HP = 1%                                                  │
│     • Ragdoll + Countdown 15s                                  │
│     │                                                          │
│     ▼                                                          │
│  📢 Emit: PLAYER_DOWNED_TIMEOUT                                 │
│     │                                                          │
│     ▼                                                          │
│  🔄 RespawnService (รอ 3-5 วินาที)                              │
│     │                                                          │
│     ▼                                                          │
│  🏠 LobbyService (Spawn ที่ Lobby)                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🧩 Services ทั้งหมด

| Category | Service | Purpose |
|----------|---------|---------|
| Core | NetworkHandler | ยามหน้าประตู - ตรวจคนเข้าออก |
| Data | PlayerDataService | จัดการข้อมูลผู้เล่น (Primary) |
| Cloud | PocketBaseService | Sync ข้อมูลไป VPS (Secondary) |
| Player | PlayerStateService | บอกว่าผู้เล่นอยู่ไหน |
| Gameplay | ArenaService | พาผู้เล่นไป Arena |
| Gameplay | CombatService | ตรวจจับ Damage, Fatal Hit |
| Gameplay | DownedService | จัดการ Downed state |
| Gameplay | RespawnService | จัดการ Respawn delay |
| Gameplay | LobbyService | พาผู้เล่นไป Lobby |

---

## 🛠️ Utilities

| Utility | Purpose |
|---------|---------|
| ServiceLocator | แก้ Circular dependency |
| DataMapper | แปลงข้อมูล Roblox ↔ PocketBase |
| IdempotencyKey | ป้องกัน duplicate operations |
| ExecutionGuard | RunOnce + Lock management |
| IdempotentGuard | ป้องกัน double init/start |

---

## 🔒 ความปลอดภัย (7+1 ชั้น)

1. 🖼️ UI Cooldown (1s)
2. 📡 Per-Event Rate Limit (1-10/5s)
3. 🔢 Global Rate Limit (10/5s)
4. 🔐 Transition Lock (atomic)
5. ⏱️ Transition Cooldown (2s)
6. 🚀 Teleport Cooldown (5s)
7. ⚔️ Combat Check (5s)
8. 🦵 Downed Input Blocking

---

## 📚 อ่านเพิ่มเติม

| เอกสาร | เกี่ยวกับ |
|--------|----------|
| [Data-System-Guide](./Data-System-Guide.md) | ระบบ Data |
| [Combat-Downed-Respawn-Guide](./Combat-Downed-Respawn-Guide.md) | ระบบ Combat |
| [Init-System-Guide](./Init-System-Guide.md) | ระบบ Boot |
| [GUI-Communication-Guide](./GUI-Communication-Guide.md) | GUI ↔ Server |

---

**Version:** 3.2 - Production Ready  
**Status:** ✅ พร้อมใช้งานจริง
