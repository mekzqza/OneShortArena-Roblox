# 🗄️ Data System Guide - Complete Documentation

## 📋 Overview

เอกสารนี้อธิบายระบบ **Data Management** ของ OneShortArena แบบละเอียด รวมถึงวิธีใช้งาน ความเสี่ยง และวิธีแก้ไข

---

## 🎯 Version Info

| Component | Version | Status |
|-----------|---------|--------|
| **PlayerDataService** | 1.0 | ✅ Production |
| **PocketBaseService** | 1.0 | ✅ Production |
| **ProfileService** | External | ✅ Integrated |
| **ServiceLocator** | 1.0 | ✅ Production |
| **DataMapper** | 1.0 | ✅ Production |
| **IdempotencyKey** | 1.0 | ✅ Production |

---

## 🖼️ ภาพรวมระบบ

```
┌─────────────────────────────────────────────────────────────────┐
│               HYBRID DATA SYNC ARCHITECTURE                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  🎮 Game Logic                                                  │
│       │                                                        │
│       ▼                                                        │
│  ┌─────────────────────────────────────────────────────┐      │
│  │           PlayerDataService (Primary API)            │      │
│  │  ┌─────────────────┐     ┌─────────────────┐        │      │
│  │  │ ProfileService  │     │ PocketBase      │        │      │
│  │  │  (DataStore)    │ ←──►│  Service        │        │      │
│  │  │   PRIMARY       │     │  SECONDARY      │        │      │
│  │  └─────────────────┘     └─────────────────┘        │      │
│  └─────────────────────────────────────────────────────┘      │
│                              │                                  │
│                              │ HTTPS + DataMapper               │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────┐      │
│  │         🌐 VPS (DigitalOcean)                        │      │
│  │                                                      │      │
│  │  ┌──────────┐    ┌──────────────┐    ┌─────────┐   │      │
│  │  │  Caddy   │───►│  PocketBase  │───►│  Redis  │   │      │
│  │  │(Reverse  │    │  (Database)  │    │ (Cache) │   │      │
│  │  │  Proxy)  │    │              │    │         │   │      │
│  │  └──────────┘    └──────────────┘    └─────────┘   │      │
│  │                                                      │      │
│  │  Domain: https://roblox-api.sukpat.dev              │      │
│  └─────────────────────────────────────────────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🧩 Components ทั้งหมด

### 1️⃣ PlayerDataService - API หลักสำหรับจัดการข้อมูล

```
┌─────────────────────────────────────────────────────────────────┐
│  🗄️ PLAYER DATA SERVICE                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  หน้าที่:                                                       │
│  ────────                                                       │
│  1. Load / Release profile จาก ProfileService                  │
│  2. ผูก profile กับ Player                                     │
│  3. ป้องกัน double-load                                        │
│  4. Cleanup ตอน Player ออก                                     │
│  5. Read / Write API พร้อม Validation                          │
│  6. Sync ไป PocketBase (Secondary)                             │
│                                                                 │
│  ไม่ทำ:                                                         │
│  ──────                                                         │
│  ❌ เชื่อมต่อ VPS โดยตรง (PocketBaseService ทำ)                │
│  ❌ แปลงข้อมูล (DataMapper ทำ)                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2️⃣ PocketBaseService - Sync ข้อมูลไป VPS

```
┌─────────────────────────────────────────────────────────────────┐
│  ☁️ POCKETBASE SERVICE                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  หน้าที่:                                                       │
│  ────────                                                       │
│  1. เชื่อมต่อ HTTPS ไป VPS                                     │
│  2. Auto-authenticate กับ PocketBase                           │
│  3. Sync ข้อมูลแบบ async                                       │
│  4. Retry logic + exponential backoff                          │
│  5. Queue สำหรับ offline/failed syncs                          │
│  6. ใช้ IdempotencyKey ป้องกัน duplicate sync                  │
│                                                                 │
│  ไม่ทำ:                                                         │
│  ──────                                                         │
│  ❌ เก็บ credentials โดยตรง (ใช้ Secret Config)                │
│  ❌ จัดการ DataStore (PlayerDataService ทำ)                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3️⃣ ServiceLocator - แก้ Circular Dependency

```
┌─────────────────────────────────────────────────────────────────┐
│  🔗 SERVICE LOCATOR                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  หน้าที่:                                                       │
│  ────────                                                       │
│  1. Centralized registry สำหรับ Services                       │
│  2. Lazy loading - โหลดเมื่อต้องการ                            │
│  3. ป้องกัน circular dependency                                │
│  4. Async get พร้อม callback                                   │
│                                                                 │
│  วิธีใช้:                                                       │
│  ────────                                                       │
│  • ServiceLocator:Register("Name", Service)                    │
│  • local svc = ServiceLocator:Get("Name")                      │
│  • ServiceLocator:GetAsync("Name", callback)                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 4️⃣ DataMapper - แปลงข้อมูลระหว่าง Roblox ↔ PocketBase

```
┌─────────────────────────────────────────────────────────────────┐
│  🗺️ DATA MAPPER                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  หน้าที่:                                                       │
│  ────────                                                       │
│  1. Explicit field mapping (ไม่มี magic/auto)                  │
│  2. Type coercion - แปลง type อย่างปลอดภัย                     │
│  3. Validation - ตรวจสอบข้อมูล                                  │
│  4. Default values - จัดการ missing fields                     │
│  5. Schema versioning - รองรับ migration                       │
│                                                                 │
│  Mapping Example:                                               │
│  ─────────────────                                              │
│                                                                 │
│  Roblox (PascalCase)    →    PocketBase (snake_case)           │
│  ────────────────────        ────────────────────               │
│  Coins                  →    coins                              │
│  Level                  →    level                              │
│  Kills                  →    kills                              │
│  _version               →    data_version                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5️⃣ IdempotencyKey - ป้องกัน Duplicate Operations

```
┌─────────────────────────────────────────────────────────────────┐
│  🔑 IDEMPOTENCY KEY                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  หน้าที่:                                                       │
│  ────────                                                       │
│  1. Generate unique keys สำหรับ operations                     │
│  2. Track operation status (Processing/Complete/Failed)        │
│  3. TTL support - auto-expire old keys                         │
│  4. Result caching - คืนค่าเดิมสำหรับ duplicates              │
│  5. LRU eviction - จำกัดจำนวน keys                             │
│                                                                 │
│  Use Cases:                                                     │
│  ───────────                                                    │
│  • ป้องกัน sync ซ้ำซ้อน                                        │
│  • ป้องกัน purchase ซ้ำ                                        │
│  • ป้องกัน API call ซ้ำ                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📊 Data Schema

### PlayerData Structure

```lua
export type PlayerData = {
    -- Version (for migration)
    _version: number,           -- Current: 1
    
    -- Currency
    Coins: number,              -- 0 - 999,999,999
    Gems: number,               -- 0 - 999,999,999
    
    -- Stats
    Level: number,              -- 1 - 100
    Experience: number,         -- 0 - 999,999,999
    
    -- Combat stats
    Kills: number,              -- 0 - 999,999,999
    Deaths: number,             -- 0 - 999,999,999
    Wins: number,               -- 0 - 999,999,999
    Losses: number,             -- 0 - 999,999,999
    
    -- Inventory
    OwnedItems: {string},       -- List of item IDs
    EquippedItems: {[string]: string?}, -- slot -> itemId
    
    -- Settings
    Settings: {
        MusicVolume: number,    -- 0.0 - 1.0
        SFXVolume: number,      -- 0.0 - 1.0
        ShowDamageNumbers: boolean,
    },
}
```

### PocketBase Collection (player_stats)

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | PocketBase auto-generated |
| `roblox_id` | text | Player's UserId |
| `coins` | number | Currency |
| `gems` | number | Premium currency |
| `level` | number | Player level |
| `experience` | number | XP points |
| `kills` | number | Total kills |
| `deaths` | number | Total deaths |
| `wins` | number | Match wins |
| `losses` | number | Match losses |
| `data_version` | number | Schema version |
| `last_sync` | number | Unix timestamp |

---

## 📖 วิธีใช้งาน (API Reference)

### 1️⃣ PlayerDataService - การอ่าน/เขียนข้อมูล

#### รอข้อมูล Load เสร็จ

```lua
local PlayerDataService = ServiceLocator:Get("PlayerDataService")

-- วิธีที่ 1: WaitForData (blocking)
if PlayerDataService:WaitForData(player, 10) then -- timeout 10s
    print("Data ready!")
else
    print("Data load failed or timeout")
end

-- วิธีที่ 2: เช็ค IsDataLoaded
if PlayerDataService:IsDataLoaded(player) then
    -- ข้อมูลพร้อมแล้ว
end
```

#### อ่านข้อมูล (Read)

```lua
-- อ่านค่าเดียว
local coins = PlayerDataService:Get(player, "Coins")
local level = PlayerDataService:Get(player, "Level")

-- อ่าน nested value (ใช้ dot notation)
local musicVol = PlayerDataService:Get(player, "Settings.MusicVolume")

-- อ่านทั้งหมด (ได้ copy)
local allData = PlayerDataService:GetAll(player)
print(allData.Coins, allData.Level)
```

#### เขียนข้อมูล (Write)

```lua
-- Set ค่าเดียว
local success = PlayerDataService:Set(player, "Coins", 500)
if success then
    print("Saved!")
end

-- Set nested value
PlayerDataService:Set(player, "Settings.MusicVolume", 0.8)

-- Increment (สำหรับ number)
local success, newValue = PlayerDataService:Increment(player, "Kills", 1)
print("New kills:", newValue) -- e.g., 11

-- Decrement
PlayerDataService:Increment(player, "Coins", -100) -- ลบ 100
```

#### Inventory API

```lua
-- เช็คว่ามี item หรือไม่
if PlayerDataService:HasItem(player, "Sword_001") then
    print("Player owns this sword")
end

-- เพิ่ม item
local success = PlayerDataService:AddItem(player, "Shield_002")
if not success then
    print("Already owned or error")
end

-- ลบ item (+ auto-unequip)
PlayerDataService:RemoveItem(player, "Sword_001")

-- Equip item
PlayerDataService:EquipItem(player, "Weapon", "Sword_001")

-- Unequip (set nil)
PlayerDataService:EquipItem(player, "Weapon", nil)
```

#### Settings API

```lua
-- อ่าน setting
local musicVol = PlayerDataService:GetSetting(player, "MusicVolume")

-- เขียน setting
PlayerDataService:SetSetting(player, "MusicVolume", 0.5)
PlayerDataService:SetSetting(player, "ShowDamageNumbers", false)
```

---

### 2️⃣ PocketBaseService - Sync ไป VPS

#### Manual Sync

```lua
local PocketBaseService = ServiceLocator:Get("PocketBaseService")
local data = PlayerDataService:GetAll(player)

-- Async sync (fire and forget)
PocketBaseService:SyncPlayer(player.UserId, data)

-- Sync with result
local success = PocketBaseService:SyncPlayerAsync(player.UserId, data)
if success then
    print("Synced to VPS!")
end
```

#### Fetch จาก VPS

```lua
-- ดึงข้อมูลจาก PocketBase
local remoteData = PocketBaseService:FetchPlayer(player.UserId)
if remoteData then
    print("Level from VPS:", remoteData.Level)
end
```

#### Batch Operations

```lua
-- Sync ผู้เล่นทุกคน
PocketBaseService:SyncAll()

-- Process pending queue
PocketBaseService:ProcessQueue()
```

#### Status Check

```lua
-- เช็คสถานะ online
if PocketBaseService:IsOnline() then
    print("Connected to VPS")
end

-- เช็ค sync status ของ user
local status = PocketBaseService:GetSyncStatus(player.UserId)
-- Returns: "Pending" | "Syncing" | "Success" | "Failed" | "Offline" | nil
```

---

### 3️⃣ ServiceLocator - แก้ Circular Dependency

#### Register Service (Init.server.luau)

```lua
-- หลัง load services แล้ว
ServiceLocator:Register("PlayerDataService", PlayerDataService)
ServiceLocator:Register("PocketBaseService", PocketBaseService)
ServiceLocator:Register("MyService", MyService)
```

#### Get Service (ในโค้ดอื่นๆ)

```lua
-- แบบ sync (ถ้า nil = ยังไม่ register)
local PDS = ServiceLocator:Get("PlayerDataService")
if PDS then
    PDS:DoSomething()
end

-- แบบ async (รอจน register)
ServiceLocator:GetAsync("PlayerDataService", function(service)
    service:DoSomething()
end, 10) -- timeout 10s

-- แบบ blocking wait
local PDS = ServiceLocator:WaitFor("PlayerDataService", 10)

-- เช็คว่ามีหรือยัง
if ServiceLocator:Has("PlayerDataService") then
    -- มีแล้ว
end
```

---

### 4️⃣ DataMapper - แปลงข้อมูล

#### Roblox → PocketBase

```lua
local DataMapper = require(ServerScriptService.Utils.DataMapper)

local playerData = PlayerDataService:GetAll(player)
local remoteData = DataMapper.ToRemote("PlayerData", playerData, player.UserId)

-- remoteData = {
--     roblox_id = "12345",
--     coins = 100,
--     level = 5,
--     kills = 10,
--     last_sync = 1234567890,
--     ...
-- }
```

#### PocketBase → Roblox

```lua
local pocketBaseRecord = {
    coins = 100,
    level = 5,
    kills = 10,
}

local robloxData = DataMapper.FromRemote("PlayerData", pocketBaseRecord)

-- robloxData = {
--     Coins = 100,
--     Level = 5,
--     Kills = 10,
--     ...
-- }
```

#### Validate Data

```lua
local valid, errors = DataMapper.Validate("PlayerData", playerData)
if not valid then
    for _, err in ipairs(errors) do
        warn("Validation error:", err)
    end
end
```

#### Custom Schema

```lua
local mySchema = {
    version = 1,
    name = "MyCustomData",
    fields = {
        {
            robloxKey = "Score",
            remoteKey = "score",
            robloxType = "number",
            remoteType = "number",
            default = 0,
            required = true,
        },
    },
}

DataMapper.RegisterSchema(mySchema)
```

---

### 5️⃣ IdempotencyKey - ป้องกัน Duplicates

#### Generate Key

```lua
local IdempotencyKey = require(ServerScriptService.Utils.IdempotencyKey)

-- Unique key (มี timestamp)
local key = IdempotencyKey.Generate("sync", player.UserId)
-- "sync:12345:1234567890:abc12345"

-- Deterministic key (same inputs = same key)
local key = IdempotencyKey.GenerateDeterministic("sync", player.UserId)
-- "sync:12345"
```

#### Execute with Idempotency

```lua
-- วิธีที่ 1: Execute helper (recommended)
local success, result = IdempotencyKey:Execute(key, "MyOperation", function()
    -- Do expensive operation
    return doSomething()
end, 300) -- TTL 5 minutes

if success then
    print("Result:", result)
else
    print("Failed or duplicate")
end

-- วิธีที่ 2: Manual control
if IdempotencyKey:WasProcessed(key) then
    -- Already done, return cached result
    return IdempotencyKey:GetResult(key)
end

IdempotencyKey:MarkProcessing(key, "MyOperation", 300)

local result = doSomething()

IdempotencyKey:MarkComplete(key, result)
-- or
IdempotencyKey:MarkFailed(key, "Error message")
```

#### Status Check

```lua
-- เช็ค status
local status = IdempotencyKey:GetStatus(key)
-- "Processing" | "Complete" | "Failed" | "Expired" | nil

-- เช็คว่ากำลังทำงานอยู่
if IdempotencyKey:IsProcessing(key) then
    print("Operation in progress")
end

-- ดึง cached result
local result = IdempotencyKey:GetResult(key)
```

---

## 📊 Data Flow Diagrams

### Write Operation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  WRITE OPERATION FLOW                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Game Logic calls:                                          │
│     PlayerDataService:Set(player, "Coins", 100)                │
│                                                                 │
│  2. PlayerDataService:                                         │
│     ├─ ❓ Profile loaded?                                       │
│     │   └─ ❌ No → Return false                                │
│     │                                                          │
│     ├─ ❓ Profile active?                                       │
│     │   └─ ❌ No → Return false                                │
│     │                                                          │
│     ├─ 🔍 Validate value                                       │
│     │   ├─ Type check (number?)                                │
│     │   ├─ Range check (0-999999999?)                          │
│     │   └─ Clamp if needed                                     │
│     │                                                          │
│     ├─ 💾 Write to ProfileService (DataStore)                  │
│     │                                                          │
│     ├─ 📢 Emit PLAYER_DATA_CHANGED event                       │
│     │                                                          │
│     └─ ❓ Should sync to cloud?                                 │
│         ├─ EnableCloudSync = true?                             │
│         ├─ Debounce passed? (5s)                               │
│         └─ Is critical key? (bypass debounce)                  │
│                                                                 │
│  3. PocketBaseService (if sync triggered):                     │
│     ├─ Generate IdempotencyKey                                 │
│     ├─ Check for duplicate                                     │
│     ├─ DataMapper.ToRemote()                                   │
│     ├─ HTTP POST/PATCH to VPS                                  │
│     └─ Queue on failure                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Player Join/Leave Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  PLAYER LIFECYCLE FLOW                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  📥 Player Joins:                                               │
│  ─────────────────                                              │
│  1. PlayerAdded event fires                                    │
│  2. Check LoadingPlayers[userId] (prevent double-load)         │
│  3. ProfileStore:LoadProfileAsync("Player_{userId}")           │
│  4. profile:AddUserId(userId) (GDPR)                           │
│  5. profile:Reconcile() (fill missing fields)                  │
│  6. Check data version, migrate if needed                      │
│  7. profile:ListenToRelease() (handle kick)                    │
│  8. Store in Profiles[userId]                                  │
│  9. Emit PLAYER_DATA_LOADED event                              │
│                                                                 │
│  📤 Player Leaves:                                              │
│  ──────────────────                                             │
│  1. PlayerRemoving event fires                                 │
│  2. Get profile from Profiles[userId]                          │
│  3. Final sync to PocketBase (synchronous!)                    │
│  4. profile:Release() (saves to DataStore)                     │
│  5. Cleanup: LoadingPlayers, lastCloudSync, Profiles           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## ⚠️ ความเสี่ยงและวิธีแก้ไข

### 🔴 P0 - Critical Risks

| Risk | Description | Mitigation | Status |
|------|-------------|------------|--------|
| **Double-load Profile** | โหลด profile ซ้ำทำให้ data corrupt | `LoadingPlayers` lock + check | ✅ Fixed |
| **Race Condition (Write)** | เขียนพร้อมกันหลาย thread | Profile active check + atomic ops | ✅ Fixed |
| **Duplicate Sync** | Sync ไป VPS ซ้ำหลายครั้ง | IdempotencyKey + debounce | ✅ Fixed |
| **Data Loss on Leave** | ผู้เล่นออกก่อน save | Synchronous final sync | ✅ Fixed |
| **Credentials Leak** | รหัส database หลุด | Secret Config + .gitignore | ✅ Fixed |

### 🟡 P1 - High Risks

| Risk | Description | Mitigation | Status |
|------|-------------|------------|--------|
| **Circular Dependency** | Services require กัน วนลูป | ServiceLocator pattern | ✅ Fixed |
| **Type Mismatch** | ข้อมูล type ผิดทำให้ error | Validation + type coercion | ✅ Fixed |
| **Value Overflow** | ค่าเกิน limit | Clamp + max bounds | ✅ Fixed |
| **Network Failure** | VPS offline | Queue + retry + exponential backoff | ✅ Fixed |
| **Auth Token Expire** | Token หมดอายุ | Auto-refresh (1 hour) | ✅ Fixed |

### 🟢 P2 - Medium Risks

| Risk | Description | Mitigation | Status |
|------|-------------|------------|--------|
| **Schema Mismatch** | Roblox/PocketBase schema ต่างกัน | DataMapper explicit mapping | ✅ Fixed |
| **Memory Leak** | ไม่ cleanup data | PlayerRemoving cleanup | ✅ Fixed |
| **Queue Overflow** | Failed syncs สะสมมาก | MaxQueueSize + LRU eviction | ✅ Fixed |
| **Idempotency Key Bloat** | Keys สะสมมาก | TTL + cleanup interval | ✅ Fixed |

---

## 🔒 Security Best Practices

### 1️⃣ Secret Configuration

```lua
-- ❌ WRONG: Hardcode credentials
local CONFIG = {
    ADMIN_EMAIL = "admin@example.com",  -- EXPOSED!
    ADMIN_PASS = "password123",          -- EXPOSED!
}

-- ✅ CORRECT: Use Secret Config (not committed)
local SECRET_CONFIG = nil
pcall(function()
    local Secrets = ServerStorage:FindFirstChild("Secrets")
    if Secrets then
        SECRET_CONFIG = require(Secrets.PocketBaseSecret)
    end
end)

if not SECRET_CONFIG then
    warn("No secret config - service disabled")
end
```

### 2️⃣ Input Validation

```lua
-- ❌ WRONG: Trust client input
function SetCoins(player, amount)
    profile.Data.Coins = amount  -- Can be negative or huge!
end

-- ✅ CORRECT: Validate and clamp
function SetCoins(player, amount)
    local validation = validateValue("Coins", amount)
    if not validation.valid then
        return false
    end
    
    local finalValue = validation.clampedValue or amount
    profile.Data.Coins = finalValue
    return true
end
```

### 3️⃣ Server-Authoritative

```lua
-- ❌ WRONG: Client decides final value
RemoteEvent.OnServerEvent:Connect(function(player, newCoins)
    PlayerDataService:Set(player, "Coins", newCoins)
end)

-- ✅ CORRECT: Server calculates and validates
RemoteEvent.OnServerEvent:Connect(function(player, purchaseId)
    local price = SHOP_ITEMS[purchaseId].price
    local currentCoins = PlayerDataService:Get(player, "Coins")
    
    if currentCoins >= price then
        PlayerDataService:Increment(player, "Coins", -price)
        PlayerDataService:AddItem(player, purchaseId)
    end
end)
```

---

## 🧪 Debug Commands (F9)

```lua
-- ═══════════════════════════════════════════════════════════════
-- PLAYER DATA SERVICE
-- ═══════════════════════════════════════════════════════════════

-- Get player data
local player = game.Players:GetPlayers()[1]
local data = _G.Services.PlayerDataService:GetAll(player)
print(data.Coins, data.Level)

-- Set data
_G.Services.PlayerDataService:Set(player, "Coins", 1000)

-- Check if loaded
print(_G.Services.PlayerDataService:IsDataLoaded(player))

-- Get analytics
print(_G.Services.PlayerDataService:GetAnalytics())

-- ═══════════════════════════════════════════════════════════════
-- POCKETBASE SERVICE
-- ═══════════════════════════════════════════════════════════════

-- Check online status
print(_G.Services.PocketBaseService:IsOnline())

-- Manual sync
local data = _G.Services.PlayerDataService:GetAll(player)
_G.Services.PocketBaseService:SyncPlayer(player.UserId, data)

-- Get analytics
print(_G.Services.PocketBaseService:GetAnalytics())

-- Process queue
_G.Services.PocketBaseService:ProcessQueue()

-- ═══════════════════════════════════════════════════════════════
-- SERVICE LOCATOR
-- ═══════════════════════════════════════════════════════════════

-- List all services
_G.ServiceLocator:PrintRegistry()

-- Get service
local PDS = _G.ServiceLocator:Get("PlayerDataService")

-- ═══════════════════════════════════════════════════════════════
-- DATA MAPPER
-- ═══════════════════════════════════════════════════════════════

-- Print schemas
_G.DataMapper.PrintSchemas()

-- Convert data
local remoteData = _G.DataMapper.ToRemote("PlayerData", data, 12345)

-- ═══════════════════════════════════════════════════════════════
-- IDEMPOTENCY KEY
-- ═══════════════════════════════════════════════════════════════

-- Print summary
_G.IdempotencyKey:PrintSummary()

-- Get analytics
print(_G.IdempotencyKey:GetAnalytics())
```

---

## 📚 Related Documents

| Document | Description |
|----------|-------------|
| [deps.md](./deps.md) | Architecture overview |
| [Combat-Downed-Respawn-Guide.md](./Combat-Downed-Respawn-Guide.md) | Combat system |
| [NetworkConfig-Guide.md](./NetworkConfig-Guide.md) | Rate limiting |
| [Risk-Assessment.md](./Risk-Assessment.md) | Security audit |

---

## 🎯 Quick Reference Card

```
╔════════════════════════════════════════════════════════════════╗
║  📋 QUICK REFERENCE - DATA SYSTEM                              ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  📖 READ DATA:                                                 ║
║  ─────────────────────────────────────────────────────────────║
║  PlayerDataService:Get(player, "Coins")           → 100       ║
║  PlayerDataService:Get(player, "Settings.Music")  → 0.5       ║
║  PlayerDataService:GetAll(player)                 → {table}   ║
║  PlayerDataService:HasItem(player, "Sword_001")   → true      ║
║                                                                ║
║  ✏️ WRITE DATA:                                                ║
║  ─────────────────────────────────────────────────────────────║
║  PlayerDataService:Set(player, "Coins", 500)      → true      ║
║  PlayerDataService:Increment(player, "Kills", 1)  → true, 11  ║
║  PlayerDataService:AddItem(player, "Shield_001")  → true      ║
║  PlayerDataService:EquipItem(player, "Weapon", "Sword_001")   ║
║                                                                ║
║  ☁️ CLOUD SYNC:                                                ║
║  ─────────────────────────────────────────────────────────────║
║  PocketBaseService:SyncPlayer(userId, data)       → async     ║
║  PocketBaseService:SyncPlayerAsync(userId, data)  → boolean   ║
║  PocketBaseService:FetchPlayer(userId)            → {table}?  ║
║  PocketBaseService:IsOnline()                     → boolean   ║
║                                                                ║
║  🔗 SERVICE LOCATOR:                                           ║
║  ─────────────────────────────────────────────────────────────║
║  ServiceLocator:Register("Name", service)                      ║
║  ServiceLocator:Get("Name")                       → service?  ║
║  ServiceLocator:WaitFor("Name", 10)               → service?  ║
║                                                                ║
║  🗺️ DATA MAPPER:                                               ║
║  ─────────────────────────────────────────────────────────────║
║  DataMapper.ToRemote("PlayerData", data, userId)  → {remote}  ║
║  DataMapper.FromRemote("PlayerData", remote)      → {roblox}  ║
║  DataMapper.Validate("PlayerData", data)          → bool, err ║
║                                                                ║
║  🔑 IDEMPOTENCY:                                               ║
║  ─────────────────────────────────────────────────────────────║
║  IdempotencyKey.Generate("op", userId)            → "key..."  ║
║  IdempotencyKey:Execute(key, "op", fn, ttl)       → bool, any ║
║  IdempotencyKey:WasProcessed(key)                 → boolean   ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
```

---

**Version:** 1.0  
**Author:** OneShortArena Team  
**Last Updated:** 2024  
**Status:** ✅ Production Ready
