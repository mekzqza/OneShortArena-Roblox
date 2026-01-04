# 💀 DeathService Guide v2.1 - Simplified Architecture

## 📋 Overview

**DeathService v2.1** เป็น simplified service ที่มีหน้าที่เพียง:
1. **Detect** - ตรวจจับการตาย (server-authoritative)
2. **Classify** - จำแนกสาเหตุ (Combat, Environmental, etc.)
3. **Emit** - ส่ง event ให้ services อื่นจัดการต่อ

---

## 🎯 Philosophy: Single Responsibility

```
❌ Before (v2.0):
DeathService → Detect, Track Damage, Match Stats, Respawn, Kill Streaks

✅ After (v2.1):
DeathService → Detect, Classify, Emit
MatchService → Match Stats, Kill Streaks, Respawn Delays
```

---

## 🔄 Death Detection Flow

```
1. Humanoid.Died fires
   │
   ▼
2. shouldProcessDeath()
   ├─> OnlyTrackArenaDeaths = true
   └─> PlayerStateService:GetState() == "Arena" ?
   
3. handleDeath()
   ├─> acquireDeathLock() (P0 protection)
   ├─> analyzeDeath() → DeathCause
   ├─> getKillerInfo() → (killer, weapon)
   └─> Emit PLAYER_DIED event
   
4. Other services listen:
   ├─> MatchService → Track kills
   ├─> PlayerStateService → SetState("Died")
   └─> Custom logic (leaderboards, etc.)
```

---

## 📊 Death Causes

| Cause | Detection Logic |
|-------|----------------|
| **Combat** | Damage within 5s window |
| **Environmental** | `humanoid:GetAttribute("DeathByEnvironment")` |
| **Timeout** | Game-specific logic |
| **Script** | Manual death trigger |
| **Unknown** | No matching criteria |

---

## 🔧 API Reference

### Core Methods

```lua
-- Register damage (for combat death detection)
DeathService:RegisterDamage(victim, attacker, damage, weapon)

-- Query last killer
local killer = DeathService:GetLastKiller(player)

-- Get analytics
local stats = DeathService:GetAnalytics()
-- Returns:
-- {
--   totalDeaths = 42,
--   deathsByCause = {Combat = 30, Environmental = 8, ...},
--   blockedDuplicateDeaths = 3,
--   ignoredNonArenaDeaths = 12,
-- }
```

---

## 🎮 Integration Example

### Listen to Death Events

```lua
-- In any service
EventBus:On(Events.PLAYER_DIED, function(player, deathData)
    print("Player died:", player.Name)
    print("Cause:", deathData.cause)
    print("Killer:", deathData.killer)
    print("Weapon:", deathData.weapon)
    
    -- Your custom logic here
end)
```

### Register Damage (Combat System)

```lua
-- In your combat system
function CombatSystem:DealDamage(attacker, victim, damage)
    victim.Character.Humanoid.Health -= damage
    
    -- ✅ Register damage for death tracking
    DeathService:RegisterDamage(victim, attacker, damage, "Sword")
end
```

---

## ⚙️ Configuration

```lua
-- DeathService.luau
local DEATH_CONFIG = {
    CombatWindow = 5,              -- Consider combat death if damaged within 5s
    OnlyTrackArenaDeaths = true,   -- Ignore deaths outside Arena
}
```

---

## 🔐 P0 Security Features

### 1. Death Lock (Prevent Duplicate Processing)

```lua
-- Scenario: Humanoid.Died fires twice
Thread 1: acquireDeathLock() → ✅ Acquired
Thread 2: acquireDeathLock() → ❌ Blocked (lock exists)

Thread 1: Process death → releaseDeathLock()
```

### 2. Arena-Only Filtering

```lua
-- Deaths in Lobby are ignored
if currentState ~= "Arena" then
    analytics.ignoredNonArenaDeaths += 1
    return
end
```

---

## 📈 Analytics

```lua
local stats = DeathService:GetAnalytics()

print("Total deaths:", stats.totalDeaths)
print("Blocked duplicates:", stats.blockedDuplicateDeaths)
print("Ignored non-Arena:", stats.ignoredNonArenaDeaths)

for cause, count in pairs(stats.deathsByCause) do
    print(cause, "deaths:", count)
end
```

---

## 🔄 Migration from v2.0

| v2.0 (Old) | v2.1 (New) | Notes |
|------------|------------|-------|
| `RegisterMatch()` | ❌ Removed | Use MatchService |
| `EndMatch()` | ❌ Removed | Use MatchService |
| `GetMatchStats()` | ❌ Removed | Use MatchService |
| `RegisterDamage()` | ✅ Kept | Still needed for combat detection |
| `GetLastKiller()` | ✅ Kept | Useful for UI |

---

**Version:** 2.1 - Simplified  
**Philosophy:** Do One Thing Well  
**Author:** OneShortArena Team
