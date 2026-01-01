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
| **สถาปัตยกรรม** | 3.2 | ✅ พร้อมใช้งานจริง |
| **Data System** | 1.0 | ✅ Production ✨NEW |
| **CombatService** | 1.0 | ✅ Production |
| **DownedService** | 2.0 | ✅ Production |
| **RespawnService** | 1.0 | ✅ Production |
| **Utilities** | 1.0 | ✅ Production ✨NEW |
| **ความปลอดภัย** | P0 Fixed | ✅ แก้ไขแล้ว |

---

## 🖼️ ภาพรวมระบบ

```
┌─────────────────────────────────────────────────────────────────┐
│                     🎮 OneShortArena v3.1                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐        ┌──────────────────┐              │
│  │                  │        │                  │              │
│  │   📱 CLIENT      │◄──────►│   🖥️ SERVER      │              │
│  │   (ผู้เล่น)       │ Network │   (เจ้าของเกม)   │              │
│  │                  │        │                  │              │
│  └──────────────────┘        └──────────────────┘              │
│                                                                 │
│  Client ทำอะไร?              Server ทำอะไร?                     │
│  ─────────────               ────────────────                   │
│  • กดปุ่ม                    • ตรวจสอบโกง                       │
│  • แสดงผล                    • ย้ายผู้เล่น                       │
│  • ส่งคำสั่ง                  • จัดการ Combat                    │
│  • Block input (Downed)      • จัดการ Downed                    │
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
│   │   │
│   │   ├── 📂 Core/
│   │   │   └── 📡 NetworkController     → "ส่งข้อความไป Server"
│   │   │
│   │   ├── 📂 Inputs/
│   │   │   ├── 🎮 InputController       → "รับปุ่มที่กด"
│   │   │   └── 🧠 InputHandler          → "ตัดสินใจ + Block Downed"
│   │   │
│   │   ├── 📂 Gameplay/
│   │   │   └── 📍 PlayerStateController → "Sync state กับ Server"
│   │   │
│   │   ├── 📂 UI/
│   │   │   └── 🖼️ LobbyGuiController    → "ปุ่ม Play + Downed visual"
│   │   │
│   │   └── 📂 Dev/
│   │       └── 🧪 TestHandler           → "Debug tools"
│   │
│   ├── 📂 Server (ServerScriptService) 🖥️
│   │   │
│   │   ├── 📂 Core/
│   │   │   └── 🔒 NetworkHandler        → "ตรวจสอบโกง"
│   │   │
│   │   ├── 📂 Data/                                                  ✨NEW
│   │   │   └── 🗄️ PlayerDataService    → "จัดการข้อมูลผู้เล่น (Primary)"
│   │   │
│   │   ├── 📂 Cloud/                                                 ✨NEW
│   │   │   └── ☁️ PocketBaseService    → "Sync ข้อมูลไป VPS (Secondary)"
│   │   │
│   │   ├── 📂 Player/
│   │   │   └── 📍 PlayerStateService    → "ผู้เล่นอยู่ไหน?"
│   │   │
│   │   └── 📂 Gameplay/
│   │       ├── 🏟️ ArenaService          → "ย้ายไป Arena"
│   │       ├── ⚔️ CombatService         → "ตรวจจับ Damage"    ✨NEW
│   │       ├── ⏱️ CooldownService       → "จัดการ Cooldown"
│   │       ├── 💀 DeathService          → "ตรวจจับการตาย"
│   │       ├── 🦵 DownedService         → "จัดการ Downed"     ✨NEW
│   │       ├── 🎮 GameService           → "ควบคุมเกม"
│   │       ├── 🏠 LobbyService          → "ย้ายไป Lobby"
│   │       ├── 🎯 MatchService          → "จัดการแมตช์"
│   │       └── 🔄 RespawnService        → "จัดการ Respawn"    ✨NEW
│   │
│   └── 📂 Shared (ReplicatedStorage) 🤝
│       ├── 📋 Events.luau               → "รายชื่อเหตุการณ์"
│       └── 📡 EventBus.luau             → "ส่งข่าวสาร"
│
└── 📂 docs/ 📚
    ├── deps.md                          → "คุณกำลังอ่านอยู่!"
    ├── Combat-Downed-Respawn-Guide.md   → "ระบบ Combat"       ✨NEW
    └── ...
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
│  ⚔️ CombatService                                               │
│     │ • รับ PLAYER_DAMAGED                                     │
│     │ • คำนวณ HP                                                │
│     │ • เช็ค HP <= 0? (Fatal Hit)                              │
│     │                                                          │
│     ▼                                                          │
│  📢 Emit: PLAYER_FATAL_HIT                                      │
│     │                                                          │
│     ▼                                                          │
│  🦵 DownedService                                               │
│     │ • State = "Downed"                                       │
│     │ • HP = 1%                                                │
│     │ • Ragdoll (PlatformStand)                                │
│     │ • เริ่มนับถอยหลัง 15 วินาที                               │
│     │ • Block inputs (Play, Attack)                            │
│     │                                                          │
│     ├─► Revived? → กลับ Arena! (HP = 30-50%)                   │
│     │                                                          │
│     └─► Timeout/Finished?                                       │
│         │                                                      │
│         ▼                                                      │
│  📢 Emit: PLAYER_DOWNED_TIMEOUT / PLAYER_FINISHED               │
│     │                                                          │
│     ▼                                                          │
│  🔄 RespawnService                                              │
│     │ • รอ 3-5 วินาที                                          │
│     │                                                          │
│     ▼                                                          │
│  📢 Emit: PLAYER_RESPAWN_REQUESTED                              │
│     │                                                          │
│     ▼                                                          │
│  🏠 LobbyService                                                │
│     │ • Spawn ผู้เล่นที่ Lobby                                  │
│     │ • State = "Lobby"                                        │
│     │ • Enable inputs                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🧩 Services ทั้งหมด

```
┌─────────────────────────────────────────────────────────────────┐
│  🏢 SERVER SERVICES                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  📂 Core/                                                       │
│  ─────────                                                      │
│  🔒 NetworkHandler        → "ยามหน้าประตู - ตรวจคนเข้าออก"      │
│                                                                 │
│  📂 Data/                                                  ✨NEW │
│  ──────────                                                     │
│  🗄️ PlayerDataService    → "จัดการข้อมูลผู้เล่น (Primary)"      │
│                                                                 │
│  📂 Cloud/                                                 ✨NEW │
│  ───────────                                                    │
│  ☁️ PocketBaseService    → "Sync ข้อมูลไป VPS (Secondary)"      │
│                                                                 │
│  📂 Player/                                                     │
│  ──────────                                                     │
│  📍 PlayerStateService    → "บอกว่าผู้เล่นอยู่ไหน"              │
│                                                                 │
│  📂 Gameplay/                                                   │
│  ─────────────                                                  │
│  🏟️ ArenaService          → "พาผู้เล่นไป Arena"                 │
│  ⚔️ CombatService         → "ตรวจจับ Damage, Fatal Hit"         │
│  ⏱️ CooldownService       → "จัดการ Cooldown"                   │
│  💀 DeathService          → "ตรวจจับการตาย"                     │
│  🦵 DownedService         → "จัดการ Downed state"               │
│  🎮 GameService           → "ควบคุมเกมทั้งหมด"                  │
│  🏠 LobbyService          → "พาผู้เล่นไป Lobby"                 │
│  🎯 MatchService          → "นับแต้ม, จัดการแมตช์"              │
│  🔄 RespawnService        → "จัดการ Respawn delay"              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────┐
│  🛠️ UTILITIES                                              ✨NEW │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  🔗 ServiceLocator        → "แก้ Circular dependency"           │
│  🗺️ DataMapper            → "แปลงข้อมูล Roblox ↔ PocketBase"   │
│  🔑 IdempotencyKey        → "ป้องกัน duplicate operations"      │
│  🛡️ ExecutionGuard        → "RunOnce + Lock management"         │
│  ✅ IdempotentGuard       → "ป้องกัน double init/start"         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📡 Events ที่ใช้

```
┌─────────────────────────────────────────────────────────────────┐
│  📋 รายการ Events                                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  🎮 Player Events:                                              │
│  ─────────────────                                              │
│  • PLAYER_REQUEST_TO_ARENA   → "ขอไป Arena"                     │
│  • PLAYER_REQUEST_TO_LOBBY   → "ขอกลับ Lobby"                   │
│  • PLAYER_STATE_CHANGED      → "State เปลี่ยนแล้ว"              │
│  • PLAYER_DIED               → "ตายแล้ว"                        │
│  • PLAYER_DAMAGED            → "โดนตี"                          │
│                                                                 │
│  ⚔️ Combat Events:                                         ✨NEW │
│  ─────────────────                                              │
│  • PLAYER_FATAL_HIT          → "HP <= 0 (Lethal)"              │
│  • PLAYER_DAMAGE_APPLIED     → "Non-lethal damage"             │
│                                                                 │
│  🦵 Downed Events:                                         ✨NEW │
│  ─────────────────                                              │
│  • PLAYER_DOWNED             → "เข้า Downed state"             │
│  • PLAYER_DOWNED_COUNTDOWN   → "Countdown tick"                │
│  • PLAYER_REVIVED            → "ถูก Revive"                    │
│  • PLAYER_FINISHED           → "ถูก Finish"                    │
│  • PLAYER_DOWNED_TIMEOUT     → "หมดเวลา Downed"                │
│                                                                 │
│  🔄 Respawn Events:                                        ✨NEW │
│  ──────────────────                                             │
│  • PLAYER_RESPAWN_REQUESTED  → "ขอ Respawn"                    │
│  • PLAYER_RESPAWNED          → "Respawn แล้ว"                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔒 ความปลอดภัย (7+1 ชั้น)

```
┌─────────────────────────────────────────────────────────────────┐
│  🛡️ 7+1 ชั้นป้องกัน                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ชั้น 1: 🖼️ UI Cooldown (1s)                                    │
│  ชั้น 2: 📡 Per-Event Rate Limit (1-10/5s)                      │
│  ชั้น 3: 🔢 Global Rate Limit (10/5s)                           │
│  ชั้น 4: 🔐 Transition Lock (atomic)                            │
│  ชั้น 5: ⏱️ Transition Cooldown (2s)                            │
│  ชั้น 6: 🚀 Teleport Cooldown (5s)                              │
│  ชั้น 7: ⚔️ Combat Check (5s)                                   │
│                                                                 │
│  ✨NEW                                                          │
│  ชั้น 8: 🦵 Downed Input Blocking                               │
│          └─ Block Play/Attack ขณะ Downed                       │
│          └─ Visual feedback (ปุ่มเทา)                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📊 Boot Order

```
┌─────────────────────────────────────────────────────────────────┐
│  🖥️ SERVER BOOT                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1️⃣  📡 NetworkConfig         → "โหลดตั้งค่า"                    │
│  2️⃣  🔒 NetworkHandler        → "เปิดประตู"                      │
│  3️⃣  ☁️ PocketBaseService     → "เชื่อมต่อ VPS"            ✨NEW │
│  4️⃣  🗄️ PlayerDataService     → "เตรียมระบบ Data"          ✨NEW │
│  5️⃣  📍 PlayerStateService    → "เตรียมระบบ State"               │
│  6️⃣  🏠 LobbyService          → "เตรียม Lobby"                   │
│  7️⃣  🏟️ ArenaService          → "เตรียม Arena"                   │
│  8️⃣  ⚔️ CombatService         → "เตรียมระบบ Combat"              │
│  9️⃣  💀 DeathService          → "เตรียมตรวจจับการตาย"            │
│  🔟 🦵 DownedService         → "เตรียมระบบ Downed"              │
│  1️⃣1️⃣ 🔄 RespawnService        → "เตรียมระบบ Respawn"             │
│  1️⃣2️⃣ 🎯 MatchService          → "เตรียมระบบแมตช์"                │
│  1️⃣3️⃣ 🎮 GameService           → "เตรียมเกม"                     │
│                                                                 │
│  ✅ Server พร้อม!                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🎓 สรุป

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  🎮 OneShortArena v3.2 =                                         │
│                                                                 │
│  "ผู้เล่นกดปุ่ม → Server ตรวจสอบ → ย้ายไป Arena →              │
│   สู้กัน → Downed (15 วิ) → ตาย → Respawn (3-5 วิ) → วนใหม่!"  │
│                                                                 │
│  ✨ NEW in v3.2:                                                │
│  • PlayerDataService - ProfileService + PocketBase hybrid      │
│  • PocketBaseService - VPS sync พร้อม retry logic             │
│  • ServiceLocator    - แก้ circular dependencies               │
│  • DataMapper        - แปลงข้อมูล Roblox ↔ PocketBase          │
│  • IdempotencyKey    - ป้องกัน duplicate operations            │
│  • ExecutionGuard    - RunOnce + Lock management               │
│  • Dictionary OwnedItems - O(1) lookup (500x เร็วขึ้น!)        │
│                                                                 │
│  Previous (v3.1):                                              │
│  • CombatService  - ตรวจจับ Damage & Fatal Hit                 │
│  • DownedService  - Revive window ก่อนตาย                      │
│  • RespawnService - Configurable respawn delay                 │
│  • Input Blocking - Block inputs ขณะ Downed                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📚 อ่านเพิ่มเติม

| เอกสาร | เกี่ยวกับ |
|--------|----------|
| [Data-System-Guide](./Data-System-Guide.md) | ระบบ Data ✨NEW |
| [Combat-Downed-Respawn-Guide](./Combat-Downed-Respawn-Guide.md) | ระบบ Combat |
| [Lobby-to-Arena-Guide](./Lobby-to-Arena-Guide.md) | วิธีย้ายไป Arena |
| [NetworkConfig-Guide](./NetworkConfig-Guide.md) | ตั้งค่าความปลอดภัย |
| [Risk-Assessment](./Risk-Assessment.md) | ความปลอดภัย |

---

**Version:** 3.2 - Production Ready  
**อัปเดตล่าสุด:** 2024  
**สถานะ:** ✅ พร้อมใช้งานจริง  
**ทีมพัฒนา:** OneShortArena Team