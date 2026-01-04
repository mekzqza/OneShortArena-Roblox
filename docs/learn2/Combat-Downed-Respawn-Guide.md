# ⚔️ Combat, Downed & Respawn System - Complete Guide

## 📋 Overview

เอกสารนี้อธิบายระบบ **Combat → Downed → Respawn** แบบละเอียด รวมถึงความเสี่ยงและวิธีแก้ไข

---

## 🎯 Version Info

| Service | Version | Status | Last Updated |
|---------|---------|--------|--------------|
| **CombatService** | 1.0 | ✅ Production | 2024 |
| **DownedService** | 2.0 | ✅ Production | 2024 |
| **RespawnService** | 1.0 | ✅ Production | 2024 |
| **DeathService** | 2.1 | ✅ Production | 2024 |

---

## 🖼️ ภาพรวมระบบ

```
┌─────────────────────────────────────────────────────────────────┐
│                  COMBAT → DOWNED → RESPAWN FLOW                  │
└─────────────────────────────────────────────────────────────────┘

  ผู้เล่นโดนโจมตี
       │
       ▼
┌──────────────┐
│ CombatService │  ← 1. ตรวจจับ Damage
│   ⚔️          │  ← 2. คำนวณ HP
└──────────────┘  ← 3. เช็ค Fatal Hit
       │
       │ HP <= 0?
       ▼
┌──────────────┐
│ DownedService │  ← 4. เข้าสถานะ Downed
│   🦵          │  ← 5. เริ่มนับถอยหลัง 15s
└──────────────┘  ← 6. รอ Revive / Timeout
       │
       │ Timeout หรือ Finished?
       ▼
┌──────────────┐
│RespawnService │  ← 7. กำหนด Respawn Delay
│   🔄          │  ← 8. เลือก Location
└──────────────┘  ← 9. Emit Respawn Request
       │
       ▼
┌──────────────┐
│ LobbyService  │  ← 10. Spawn ผู้เล่น
│   🏠          │
└──────────────┘
```

---

## 1️⃣ CombatService - ระบบต่อสู้

### 📖 หน้าที่หลัก

```
┌─────────────────────────────────────────────────────────────────┐
│  ⚔️ COMBAT SERVICE - ระบบต่อสู้                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  หน้าที่:                                                       │
│  ────────                                                       │
│  1. รับ PLAYER_DAMAGED event                                    │
│  2. คำนวณ damage (shield, armor ในอนาคต)                        │
│  3. ตรวจจับ Fatal Hit (HP จะ <= 0)                              │
│  4. Emit PLAYER_FATAL_HIT สำหรับ DownedService                  │
│                                                                 │
│  ไม่ทำ:                                                         │
│  ──────                                                         │
│  ❌ ตัดสินใจว่าจะ Downed หรือ Die                               │
│  ❌ จัดการ Respawn                                              │
│  ❌ นับ Kill/Death stats                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 🔧 Configuration

```lua
local COMBAT_CONFIG = {
    CombatTimeout = 5,           -- ถือว่า "อยู่ในการต่อสู้" 5 วินาทีหลังโดนตี
    FatalHitThreshold = 0,       -- HP <= 0 = Fatal
    PreventInstantDeath = true,  -- ตั้ง HP = 1 แทนการตายทันที
}
```

### 📊 Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  CombatService Flow                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. EventBus:On(PLAYER_DAMAGED)                                │
│     │                                                          │
│     ▼                                                          │
│  2. ProcessDamage(info)                                        │
│     │                                                          │
│     ├─ ❓ Player alive?                                        │
│     │   └─ ❌ No → Return                                      │
│     │                                                          │
│     ├─ ❓ Already Downed?                                      │
│     │   └─ ✅ Yes → Skip damage                                │
│     │                                                          │
│     ├─ ❓ In Arena?                                            │
│     │   └─ ❌ No → Apply damage normally                       │
│     │                                                          │
│     ▼                                                          │
│  3. Calculate resulting HP                                     │
│     │                                                          │
│     ├─ HP > 0?                                                 │
│     │   └─ ✅ Apply damage, emit PLAYER_DAMAGE_APPLIED         │
│     │                                                          │
│     └─ HP <= 0? (FATAL HIT!)                                   │
│         │                                                      │
│         ├─ Set HP = 1 (prevent death)                          │
│         └─ Emit PLAYER_FATAL_HIT                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 🔒 Security Features

| Feature | Description | Status |
|---------|-------------|--------|
| **Processing Lock** | ป้องกัน damage ซ้ำซ้อน | ✅ |
| **Fatal Hit Cooldown** | ป้องกัน fatal hit spam | ✅ |
| **State Check** | ตรวจสอบว่าอยู่ใน Arena | ✅ |
| **IsDowned Check** | ไม่ damage ถ้า Downed แล้ว | ✅ |

### ⚠️ ความเสี่ยง (Risks)

| Risk | Severity | Mitigation | Status |
|------|----------|------------|--------|
| **Damage Spam** | 🔴 High | Processing lock + cooldown | ✅ Fixed |
| **Race Condition** | 🔴 High | Atomic lock per player | ✅ Fixed |
| **HP Manipulation** | 🟡 Medium | Server-authoritative | ✅ Fixed |
| **Bypass Downed** | 🟡 Medium | IsDowned attribute check | ✅ Fixed |

---

## 2️⃣ DownedService - ระบบ Downed State

### 📖 หน้าที่หลัก

```
┌─────────────────────────────────────────────────────────────────┐
│  🦵 DOWNED SERVICE - ระบบ Downed State                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  หน้าที่:                                                       │
│  ────────                                                       │
│  1. รับ PLAYER_FATAL_HIT → Down ผู้เล่น                         │
│  2. สร้าง Snapshot (บันทึกสถานะก่อน Down)                       │
│  3. เริ่มนับถอยหลัง 15 วินาที                                  │
│  4. แสดง Visual Effects (Ragdoll, Highlight)                   │
│  5. จัดการ Revive (Self, Teammate, Item, Robux)                │
│  6. จัดการ Finish (ถูกฆ่าขณะ Downed)                           │
│  7. Emit PLAYER_DOWNED_TIMEOUT เมื่อหมดเวลา                    │
│                                                                 │
│  ไม่ทำ:                                                         │
│  ──────                                                         │
│  ❌ คำนวณ Damage (CombatService)                               │
│  ❌ จัดการ Respawn (RespawnService)                            │
│  ❌ เปลี่ยน State โดยตรง (PlayerStateService)                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 🔧 Configuration

```lua
local DOWNED_CONFIG = {
    DefaultCountdown = 15,           -- 15 วินาที
    CountdownTickInterval = 1,       -- อัปเดตทุก 1 วินาที
    MaxReviveAttempts = 3,           -- Self-revive ได้ 3 ครั้ง
    SelfReviveCooldown = 60,         -- Cooldown 60 วินาที
    TeammateReviveTime = 5,          -- Teammate ช่วยใช้เวลา 5 วินาที
    CanBeFinished = true,            -- สามารถถูก Finish ได้
    DownedHealthPercent = 0.01,      -- HP = 1% ขณะ Downed
    CanMoveWhileDowned = false,      -- เคลื่อนที่ไม่ได้
}
```

### 📊 State Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  Downed State Transitions                                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    PLAYER_FATAL_HIT                             │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────┐                   │
│  │                                         │                   │
│  │              🦵 DOWNED                  │                   │
│  │                                         │                   │
│  │  • HP = 1%                              │                   │
│  │  • WalkSpeed = 0                        │                   │
│  │  • PlatformStand = true (Ragdoll)       │                   │
│  │  • Countdown: 15...0                    │                   │
│  │                                         │                   │
│  └─────────────────────────────────────────┘                   │
│       │              │              │                           │
│       │ Revive       │ Timeout      │ Finish                   │
│       ▼              ▼              ▼                           │
│  ┌─────────┐   ┌──────────┐   ┌──────────┐                     │
│  │ ARENA   │   │  DIED    │   │  DIED    │                     │
│  │ (alive) │   │ (timeout)│   │(finished)│                     │
│  └─────────┘   └──────────┘   └──────────┘                     │
│       │              │              │                           │
│       │              └──────────────┤                           │
│       │                             │                           │
│       ▼                             ▼                           │
│  Continue                    PLAYER_DOWNED_TIMEOUT              │
│  Fighting                    PLAYER_FINISHED                    │
│                                     │                           │
│                                     ▼                           │
│                              RespawnService                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 📸 Snapshot System

```lua
export type DownedSnapshot = {
    userId: number,
    playerName: string,
    -- Combat state
    health: number,
    maxHealth: number,
    position: Vector3,
    rotation: CFrame,
    -- Timing
    downedAt: number,
    downedBy: Player?,      -- ใครทำให้ Down
    downedCause: string?,   -- "Combat", "Environmental"
}
```

### 🎨 Visual Effects

```
┌─────────────────────────────────────────────────────────────────┐
│  Downed Visual Effects                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  เมื่อ Downed:                                                  │
│  ────────────                                                   │
│  1. PlatformStand = true       → ล้ม (Ragdoll)                 │
│  2. WalkSpeed = 0              → เคลื่อนที่ไม่ได้               │
│  3. JumpPower = 0              → กระโดดไม่ได้                   │
│  4. AutoRotate = false         → ไม่หมุนตาม Camera             │
│  5. CanCollide = false         → ทะลุผ่านได้                    │
│  6. Highlight (Red)            → เรืองแสงสีแดง                  │
│                                                                 │
│  เมื่อ Revive:                                                  │
│  ─────────────                                                  │
│  1. PlatformStand = false      → ลุกขึ้น                        │
│  2. WalkSpeed = 16             → เดินได้ปกติ                    │
│  3. JumpPower = 50             → กระโดดได้                      │
│  4. AutoRotate = true          → หมุนตาม Camera                 │
│  5. CanCollide = true          → ชนได้                          │
│  6. Highlight removed          → ไม่มีแสง                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 🔒 P0 Security - Atomic Locks

```lua
-- ✅ P0 FIX: Atomic locks for downed operations
local downedLocks: {[number]: boolean} = {}

local function acquireDownedLock(userId: number): boolean
    if downedLocks[userId] then
        analytics.blockedByLock += 1
        return false  -- ❌ ไม่อนุญาต
    end
    downedLocks[userId] = true
    return true  -- ✅ อนุญาต
end

local function releaseDownedLock(userId: number)
    downedLocks[userId] = nil
end
```

### ⚠️ ความเสี่ยง (Risks)

| Risk | Severity | Mitigation | Status |
|------|----------|------------|--------|
| **Race Condition (Down)** | 🔴 High | Atomic downedLocks | ✅ Fixed |
| **Double Downed** | 🔴 High | IsPlayerDowned check | ✅ Fixed |
| **Countdown Overlap** | 🟡 Medium | Cancel existing task | ✅ Fixed |
| **Revive Spam** | 🟡 Medium | Max attempts + cooldown | ✅ Fixed |
| **Finish Exploit** | 🟡 Medium | CanBeFinished config | ✅ Fixed |
| **Memory Leak** | 🟡 Medium | PlayerRemoving cleanup | ✅ Fixed |

---

## 3️⃣ RespawnService - ระบบ Respawn

### 📖 หน้าที่หลัก

```
┌─────────────────────────────────────────────────────────────────┐
│  🔄 RESPAWN SERVICE - ระบบ Respawn                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  หน้าที่:                                                       │
│  ────────                                                       │
│  1. รับ PLAYER_DOWNED_TIMEOUT / PLAYER_FINISHED                │
│  2. กำหนด Respawn Delay ตาม Death Reason                       │
│  3. กำหนด Respawn Location                                     │
│  4. Schedule Respawn                                           │
│  5. Emit PLAYER_RESPAWN_REQUESTED                              │
│                                                                 │
│  ไม่ทำ:                                                         │
│  ──────                                                         │
│  ❌ Spawn ผู้เล่นเอง (LobbyService/ArenaService)               │
│  ❌ เปลี่ยน State (PlayerStateService)                         │
│  ❌ จัดการ Downed (DownedService)                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 🔧 Configuration

```lua
local RESPAWN_CONFIG = {
    DefaultDelay = 3,          -- 3 วินาที default
    DefaultLocation = "Lobby",
    
    -- Delay ตาม reason
    DelayByReason = {
        ["DownedTimeout"] = 3,
        ["Finished"] = 5,
        ["Environmental"] = 2,
        ["Combat"] = 3,
        ["Unknown"] = 3,
    },
    
    -- Location ตาม reason
    LocationByReason = {
        ["DownedTimeout"] = "Lobby",
        ["Finished"] = "Lobby",
        ["Environmental"] = "Lobby",
        ["Combat"] = "Lobby",
        ["Unknown"] = "Lobby",
    },
}
```

### 📊 Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  RespawnService Flow                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Listen for death events:                                   │
│     │                                                          │
│     ├─ PLAYER_DOWNED_TIMEOUT                                   │
│     ├─ PLAYER_FINISHED                                         │
│     └─ PLAYER_DIED (with bypassedDowned=true)                  │
│                                                                 │
│  2. GetRespawnConfig(reason)                                   │
│     │                                                          │
│     ├─ Delay: 3-5 seconds                                      │
│     └─ Location: "Lobby"                                       │
│                                                                 │
│  3. ScheduleRespawn(player, config)                            │
│     │                                                          │
│     ├─ Cancel existing respawn (if any)                        │
│     └─ task.delay(config.delay, ...)                           │
│                                                                 │
│  4. After delay:                                               │
│     │                                                          │
│     ├─ Check player still exists                               │
│     ├─ Check state still "Died"                                │
│     └─ Emit PLAYER_RESPAWN_REQUESTED                           │
│                                                                 │
│  5. PlayerStateService receives PLAYER_RESPAWN_REQUESTED       │
│     │                                                          │
│     └─ SetState(player, "Lobby")                               │
│                                                                 │
│  6. LobbyService receives STATE_CHANGED_INTERNAL               │
│     │                                                          │
│     └─ SpawnPlayerInLobby(player)                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### ⚠️ ความเสี่ยง (Risks)

| Risk | Severity | Mitigation | Status |
|------|----------|------------|--------|
| **Double Respawn** | 🟡 Medium | Cancel existing + check | ✅ Fixed |
| **State Mismatch** | 🟡 Medium | Check state before emit | ✅ Fixed |
| **Player Leave** | 🟢 Low | Check player.Parent | ✅ Fixed |
| **Memory Leak** | 🟢 Low | CancelRespawn on leave | ✅ Fixed |

---

## 📊 Event Flow Summary

```
┌─────────────────────────────────────────────────────────────────┐
│  📡 EVENT FLOW - Complete Journey                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. PLAYER_DAMAGED                                             │
│     └─► CombatService.ProcessDamage()                          │
│                                                                 │
│  2. PLAYER_FATAL_HIT                                           │
│     └─► DownedService.DownPlayer()                             │
│                                                                 │
│  3. PLAYER_DOWNED (to Client)                                  │
│     └─► Show Downed UI                                         │
│                                                                 │
│  4. PLAYER_DOWNED_COUNTDOWN (every 1s)                         │
│     └─► Update countdown UI                                    │
│                                                                 │
│  5a. PLAYER_REVIVED (if revived)                               │
│      └─► DownedService.RevivePlayer()                          │
│          └─► Back to Arena!                                    │
│                                                                 │
│  5b. PLAYER_DOWNED_TIMEOUT (if timeout)                        │
│      └─► RespawnService.ScheduleRespawn()                      │
│                                                                 │
│  5c. PLAYER_FINISHED (if killed while downed)                  │
│      └─► RespawnService.ScheduleRespawn()                      │
│                                                                 │
│  6. PLAYER_RESPAWN_REQUESTED                                   │
│     └─► PlayerStateService.SetState("Lobby")                   │
│                                                                 │
│  7. PLAYER_STATE_CHANGED_INTERNAL                              │
│     └─► LobbyService.SpawnPlayerInLobby()                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔒 Security Summary

### P0 Issues - ALL FIXED ✅

```
┌─────────────────────────────────────────────────────────────────┐
│  🛡️ SECURITY FIXES SUMMARY                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CombatService:                                                │
│  ──────────────                                                 │
│  ✅ processingLocks       → ป้องกัน damage race condition      │
│  ✅ fatalHitProcessed     → ป้องกัน fatal hit spam             │
│  ✅ IsDowned check        → ไม่ damage ถ้า downed แล้ว         │
│                                                                 │
│  DownedService:                                                │
│  ─────────────                                                  │
│  ✅ downedLocks           → ป้องกัน race condition              │
│  ✅ IsPlayerDowned()      → ป้องกัน double downed              │
│  ✅ IsDowned attribute    → สำรองเช็ค                          │
│  ✅ task.cancel()         → ป้องกัน countdown overlap          │
│  ✅ PlayerRemoving        → cleanup memory                     │
│                                                                 │
│  RespawnService:                                               │
│  ──────────────                                                 │
│  ✅ CancelRespawn()       → ป้องกัน double respawn             │
│  ✅ State check           → เช็คก่อน emit                       │
│  ✅ Player exists check   → ป้องกัน nil player                 │
│                                                                 │
│  DeathService:                                                 │
│  ─────────────                                                  │
│  ✅ processingDeaths      → ป้องกัน re-entrancy                │
│  ✅ deathConnections      → disconnect HealthChanged           │
│  ✅ IsPlayerDowned()      → skip ถ้า downed แล้ว               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## ⚠️ Known Issues & Future Improvements

### 🟡 P1: Known Issues

| Issue | Impact | Workaround | Priority |
|-------|--------|------------|----------|
| **Ragdoll inconsistent** | Visual glitch | PlatformStand | P1 |
| **Countdown desync** | UI mismatch | Server tick | P1 |
| **Teammate revive distance** | No check | TODO | P2 |

### 🟢 P2: Future Improvements

```
┌─────────────────────────────────────────────────────────────────┐
│  🚀 FUTURE IMPROVEMENTS                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Teammate Revive System                                     │
│     └─ Proximity check                                         │
│     └─ Progress bar                                            │
│     └─ Interrupt on damage                                     │
│                                                                 │
│  2. Robux Revive                                               │
│     └─ MarketplaceService integration                          │
│     └─ Receipt validation                                      │
│                                                                 │
│  3. Item Revive                                                │
│     └─ Inventory check                                         │
│     └─ Item consumption                                        │
│                                                                 │
│  4. Custom Ragdoll System                                      │
│     └─ Better physics                                          │
│     └─ Animation support                                       │
│                                                                 │
│  5. Spectate While Downed                                      │
│     └─ Camera switch                                           │
│     └─ Teammate view                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🧪 Testing Checklist

### Combat Tests

| Test | Expected | Status |
|------|----------|--------|
| Normal damage | HP reduced | ✅ |
| Fatal damage | Enter Downed | ✅ |
| Damage spam | Blocked by lock | ✅ |
| Damage while Downed | Ignored | ✅ |

### Downed Tests

| Test | Expected | Status |
|------|----------|--------|
| Enter Downed | Ragdoll + countdown | ✅ |
| Self revive | HP restored, back to Arena | ✅ |
| Timeout (15s) | Enter Died, schedule respawn | ✅ |
| Finish | Enter Died, schedule respawn | ✅ |
| Double down | Blocked | ✅ |

### Respawn Tests

| Test | Expected | Status |
|------|----------|--------|
| Timeout respawn | Respawn after 3s delay | ✅ |
| Finished respawn | Respawn after 5s delay | ✅ |
| Cancel on revive | No respawn | ✅ |
| Player leave | Cleanup | ✅ |

---

## 📚 Related Documents

| Document | Description |
|----------|-------------|
| [deps.md](./deps.md) | Architecture overview |
| [Lobby-to-Arena-Guide.md](./Lobby-to-Arena-Guide.md) | Teleport system |
| [Risk-Assessment.md](./Risk-Assessment.md) | Security audit |
| [NetworkConfig-Guide.md](./NetworkConfig-Guide.md) | Rate limiting |

---

## 🎓 Quick Reference

### เมื่อต้องการแก้ไข Combat:

```lua
-- แก้ไข CombatService
-- src/ServerScriptService/Services/Gameplay/CombatService.luau
```

### เมื่อต้องการแก้ไข Downed:

```lua
-- แก้ไข DownedService
-- src/ServerScriptService/Services/Gameplay/DownedService.luau
```

### เมื่อต้องการแก้ไข Respawn:

```lua
-- แก้ไข RespawnService
-- src/ServerScriptService/Services/Gameplay/RespawnService.luau
```

### Debug Commands (F9):

```lua
-- Check player downed status
_G.Services.DownedService:IsPlayerDowned(player)

-- Get downed data
_G.Services.DownedService:GetDownedData(player)

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

**Version:** 1.0  
**Author:** OneShortArena Team  
**Last Updated:** 2024  
**Status:** ✅ Production Ready
