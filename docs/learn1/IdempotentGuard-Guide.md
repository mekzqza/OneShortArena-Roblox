# 🛡️ IdempotentGuard Usage Guide - Production Grade

## 📋 Table of Contents

- [Introduction](#introduction)
- [What is Idempotent?](#what-is-idempotent)
- [Why Use IdempotentGuard?](#why-use-idempotentguard)
- [Installation](#installation)
- [Basic Usage](#basic-usage)
- [Advanced Usage](#advanced-usage)
- [API Reference](#api-reference)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

---Mekzqza เรียนต่อ

## 🎯 Introduction

**IdempotentGuard** เป็น Utility Module ที่ช่วยป้องกันการเรียก `Init()` และ `Start()` ซ้ำซ้อนในระบบ Service/Controller

### ปัญหาที่แก้:

```lua
-- ❌ ปัญหา: ถ้า reload script หรือเรียก Init() 2 ครั้ง
MyService:Init()  -- ครั้งที่ 1: สร้าง RemoteEvent
MyService:Init()  -- ครั้งที่ 2: สร้าง RemoteEvent ซ้ำ! ❌
```

### วิธีแก้ด้วย IdempotentGuard:

```lua
-- ✅ ป้องกันด้วย Guard
local guard = IdempotentGuard.new("MyService")

function MyService:Init()
    if not guard:MarkInitialized() then
        return  -- ถ้า Init แล้ว ไม่ทำซ้ำ
    end
    -- ... init logic (รันครั้งเดียว)
end
```

---

## 🤔 What is Idempotent?

**Idempotent** = การทำซ้ำให้ผลลัพธ์เดียวกัน

### ตัวอย่าง:

```lua
-- ✅ Idempotent (ทำกี่ครั้งก็ได้ผลเหมือนกัน)
x = 5
x = 5  -- ผลเหมือนเดิม
x = 5  -- ผลเหมือนเดิม

-- ❌ Not Idempotent (ทำซ้ำ = ผลต่างกัน)
x = x + 1  -- x = 1
x = x + 1  -- x = 2 (ผลต่าง!)
x = x + 1  -- x = 3 (ผลต่าง!)
```

### ในบริบท Service/Controller:

```lua
-- ❌ Not Idempotent
function Service:Init()
    self.data = {}
    table.insert(self.data, "item")  -- เรียก 2 ครั้ง = มี 2 items!
end

-- ✅ Idempotent
function Service:Init()
    if guard:MarkInitialized() then
        self.data = {}
        table.insert(self.data, "item")  -- เรียกกี่ครั้งก็มี 1 item
    end
end
```

---

## 💡 Why Use IdempotentGuard?

### 1. **ป้องกัน Double Initialization**

```lua
-- ปัญหา: ใน Roblox Studio เมื่อ reload script
-- Init() อาจถูกเรียก 2 ครั้ง
NetworkHandler:Init()  -- สร้าง RemoteEvent
NetworkHandler:Init()  -- สร้างซ้ำ! Memory Leak!

-- วิธีแก้:
local guard = IdempotentGuard.new("NetworkHandler")

function NetworkHandler:Init()
    if not guard:MarkInitialized() then
        return  -- Skip ครั้งที่ 2
    end
    -- สร้าง RemoteEvent ครั้งเดียว
end
```

### 2. **Enforce Lifecycle Order** (Init → Start)

```lua
-- ปัญหา: เรียก Start() ก่อน Init()
MyService:Start()  -- ❌ Error: ยังไม่ได้ init!

-- วิธีแก้:
function MyService:Start()
    if not guard:MarkStarted() then
        return  -- จะ error ถ้ายังไม่ Init
    end
    -- Safe to start
end
```

### 3. **Debug และ Analytics**

```lua
-- ดูว่า Service ไหน Init แล้ว Start แล้ว
IdempotentGuard.printSummary()

-- Output:
-- ✅ NetworkHandler  - Started
-- 🔵 GameService     - Initialized
-- ⚪ ArenaService    - Created
```

### 4. **Thread-Safe State Tracking**

```lua
-- ป้องกัน race condition เมื่อมีหลาย thread
task.spawn(function()
    MyService:Init()  -- Thread 1
end)

task.spawn(function()
    MyService:Init()  -- Thread 2 (จะถูก block)
end)
```

---

## 📦 Installation

IdempotentGuard มี 2 เวอร์ชัน:

### 1. Server Version (สำหรับ Services)

```
ServerScriptService/
└── Utils/
    └── IdempotentGuard.luau
```

### 2. Client Version (สำหรับ Controllers)

```
ReplicatedStorage/
└── Utils/
    └── IdempotentGuard.luau
```

**Note:** โค้ดเหมือนกันทั้ง 2 ไฟล์ (copy ได้เลย)

---

## 🚀 Basic Usage

### Step 1: Import Module

```lua
-- Server
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- Client
local IdempotentGuard = require(ReplicatedStorage.Utils.IdempotentGuard)
```

### Step 2: Create Guard Instance

```lua
local MyService = {}

-- สร้าง guard (ทำ 1 ครั้งต่อ module)
local guard = IdempotentGuard.new("MyService", true)
--                                  ↑           ↑
--                              ชื่อ Service   Debug mode
```

### Step 3: Use in Init()

```lua
function MyService:Init()
    -- ✅ Guard: Prevent double init
    if not guard:MarkInitialized() then
        return
    end
    
    -- ... init logic (runs once)
    print("[MyService] Initialized")
end
```

### Step 4: Use in Start()

```lua
function MyService:Start()
    -- ✅ Guard: Prevent double start & require init
    if not guard:MarkStarted() then
        return
    end
    
    -- ... start logic (runs once)
    print("[MyService] Started")
end
```

---

## 🎓 Advanced Usage

### 1. **Require State Before Operation**

```lua
function MyService:DoSomethingCritical()
    -- ✅ ต้อง Init แล้วถึงจะทำได้
    guard:RequireInitialized()
    
    -- Safe to execute
    self.criticalData:Process()
end

function MyService:SendData()
    -- ✅ ต้อง Start แล้วถึงจะส่งได้
    guard:RequireStarted()
    
    -- Safe to send
    NetworkHandler:Send(data)
end
```

### 2. **Check State Manually**

```lua
if guard:IsInitialized() then
    print("Already initialized!")
end

if guard:IsStarted() then
    print("Service is running")
end

local state = guard:GetState()
-- "Created" | "Initialized" | "Started" | "Stopped"
```

### 3. **Get Analytics**

```lua
local stats = guard:GetAnalytics()
print("Init count:", stats.initCount)
print("Start count:", stats.startCount)
print("Uptime:", stats.uptime)
print("Time since init:", stats.timeSinceInit)
```

### 4. **Global Utilities**

```lua
-- ดู guard ทั้งหมด
local allGuards = IdempotentGuard.getAll()
for name, guardInstance in pairs(allGuards) do
    print(name, guardInstance:GetState())
end

-- ดูสถิติทั้งหมด
local globalStats = IdempotentGuard.getGlobalStats()
print("Total guards:", globalStats.totalGuardsCreated)
print("Blocked inits:", globalStats.blockedInits)

-- Print summary
IdempotentGuard.printSummary()
```

---

## 📖 API Reference

### Constructor

#### `IdempotentGuard.new(name: string, debug: boolean?): GuardInstance`

สร้าง guard instance ใหม่

**Parameters:**
- `name` - ชื่อของ Service/Controller
- `debug` - เปิด debug logs (optional, default = false)

**Returns:** GuardInstance

**Example:**
```lua
local guard = IdempotentGuard.new("MyService", true)
```

---

### State Queries

#### `guard:IsInitialized(): boolean`

เช็คว่า Init แล้วหรือยัง

**Returns:** `true` ถ้า state = Initialized, Started, หรือ Stopped

---

#### `guard:IsStarted(): boolean`

เช็คว่า Start แล้วหรือยัง

**Returns:** `true` ถ้า state = Started

---

#### `guard:IsStopped(): boolean`

เช็คว่า Stop แล้วหรือยัง

**Returns:** `true` ถ้า state = Stopped

---

#### `guard:GetState(): LifecycleState`

ดู state ปัจจุบัน

**Returns:** `"Created"` | `"Initialized"` | `"Started"` | `"Stopped"`

---

### State Transitions

#### `guard:MarkInitialized(): boolean`

ทำเครื่องหมายว่า Init แล้ว

**Returns:**
- `true` - ถ้าทำสำเร็จ (ครั้งแรก)
- `false` - ถ้า Init ไปแล้ว (block)

**Example:**
```lua
if guard:MarkInitialized() then
    -- Init logic here
end
```

---

#### `guard:MarkStarted(): boolean`

ทำเครื่องหมายว่า Start แล้ว

**Returns:**
- `true` - ถ้าทำสำเร็จ
- `false` - ถ้า Start แล้ว หรือยัง Init

**Note:** จะ error ถ้ายัง Init

---

#### `guard:MarkStopped(): boolean`

ทำเครื่องหมายว่า Stop แล้ว

**Returns:**
- `true` - ถ้าทำสำเร็จ
- `false` - ถ้า Stop แล้ว

---

### Validation

#### `guard:RequireInitialized()`

โยน error ถ้ายังไม่ได้ Init

**Throws:** Error ถ้า state ≠ Initialized/Started/Stopped

---

#### `guard:RequireNotInitialized()`

โยน error ถ้า Init แล้ว

**Throws:** Error ถ้า state = Initialized/Started/Stopped

---

#### `guard:RequireStarted()`

โยน error ถ้ายังไม่ได้ Start

**Throws:** Error ถ้า state ≠ Started

---

### Utilities

#### `guard:Reset()`

รีเซ็ต state กลับเป็น "Created"

**Warning:** ใช้เฉพาะ testing! Production ไม่ควรใช้

---

#### `guard:GetAnalytics(): table`

ดูสถิติของ guard นี้

**Returns:**
```lua
{
    name = "MyService",
    state = "Started",
    initCount = 1,
    startCount = 1,
    initTime = 123.456,
    startTime = 123.789,
    uptime = 10.5,
    timeSinceInit = 12.3
}
```

---

### Global Functions

#### `IdempotentGuard.get(name: string): GuardInstance?`

ดึง guard ที่มีอยู่แล้วตามชื่อ

---

#### `IdempotentGuard.getAll(): {[string]: GuardInstance}`

ดึง guard ทั้งหมดที่สร้างไว้

---

#### `IdempotentGuard.getGlobalStats(): table`

ดูสถิติทั้งระบบ

**Returns:**
```lua
{
    totalGuardsCreated = 5,
    totalInitAttempts = 7,
    totalStartAttempts = 6,
    blockedInits = 2,
    blockedStarts = 1,
    activeGuards = 5,
    states = {
        Created = 1,
        Initialized = 1,
        Started = 3,
        Stopped = 0
    }
}
```

---

#### `IdempotentGuard.printSummary()`

แสดงสรุปของ guard ทั้งหมด

**Output:**
```
╔════════════════════════════════════════════════════════════════╗
║              IDEMPOTENT GUARD SUMMARY                          ║
╠════════════════════════════════════════════════════════════════╣
║ Total Guards: 5
║ Init Attempts: 7 (Blocked: 2)
║ Start Attempts: 6 (Blocked: 1)
╠════════════════════════════════════════════════════════════════╣
║ ✅ NetworkHandler                 Started
║ ✅ LobbyService                   Started
║ ✅ PlayerStateService             Started
║ 🔵 GameService                    Initialized
║ ⚪ ArenaService                   Created
╚════════════════════════════════════════════════════════════════╝
```

---

## ✅ Best Practices

### 1. **Create Guard Once Per Module**

```lua
-- ✅ Good: Module-level variable
local guard = IdempotentGuard.new("MyService")

-- ❌ Bad: Create in function
function MyService:Init()
    local guard = IdempotentGuard.new("MyService")  -- New instance every call!
end
```

---

### 2. **Use Debug Mode in Development**

```lua
-- Development
local guard = IdempotentGuard.new("MyService", true)  -- ✅ Debug ON

-- Production
local guard = IdempotentGuard.new("MyService", false)  -- Debug OFF
```

---

### 3. **Always Check Return Value**

```lua
-- ✅ Good: Check return value
if not guard:MarkInitialized() then
    return  -- Skip if already initialized
end

-- ❌ Bad: Ignore return value
guard:MarkInitialized()
-- Logic runs even if already initialized!
```

---

### 4. **Use Require Methods for Critical Operations**

```lua
-- ✅ Good: Enforce state
function MyService:SendCriticalData()
    guard:RequireStarted()  -- Error if not started
    NetworkHandler:Send(data)
end

-- ❌ Bad: No validation
function MyService:SendCriticalData()
    NetworkHandler:Send(data)  -- Might fail silently
end
```

---

### 5. **Don't Reset in Production**

```lua
-- ✅ Good: Only in tests
if game:GetService("RunService"):IsStudio() then
    guard:Reset()  -- Test mode only
end

-- ❌ Bad: Reset in production
guard:Reset()  -- Defeats the purpose!
```

---

## 📝 Examples

### Example 1: Basic Service

```lua
-- filepath: Services/MyService.luau
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

local MyService = {}
local guard = IdempotentGuard.new("MyService", true)

function MyService:Init()
    if not guard:MarkInitialized() then
        return
    end
    
    self.data = {}
    print("[MyService] Initialized")
end

function MyService:Start()
    if not guard:MarkStarted() then
        return
    end
    
    print("[MyService] Started")
end

return MyService
```

---

### Example 2: With State Validation

```lua
local MyService = {}
local guard = IdempotentGuard.new("MyService")

function MyService:Init()
    if not guard:MarkInitialized() then
        return
    end
    
    self.connection = NetworkHandler:OnEvent(function()
        self:HandleEvent()
    end)
end

function MyService:HandleEvent()
    -- ✅ Require Started before handling
    guard:RequireStarted()
    
    print("Event handled!")
end

function MyService:Cleanup()
    -- ✅ Can only cleanup if initialized
    guard:RequireInitialized()
    
    if self.connection then
        self.connection:Disconnect()
    end
    
    guard:MarkStopped()
end

return MyService
```

---

### Example 3: Debugging in Console

```lua
-- F9 Console (Server)

-- ดูทุก guards
_G.IdempotentGuard.printSummary()

-- ดูสถิติ
local stats = _G.IdempotentGuard.getGlobalStats()
print(stats)

-- ดู guard เฉพาะ
local guard = _G.IdempotentGuard.get("NetworkHandler")
if guard then
    print(guard:GetState())
    print(guard:GetAnalytics())
end
```

---

## 🐛 Troubleshooting

### Problem 1: "Already initialized" Warning

**Symptom:**
```
[IdempotentGuard:MyService] ⚠️ Already initialized! (State: Initialized)
```

**Cause:** เรียก `Init()` 2 ครั้ง

**Solution:**
```lua
-- ตรวจสอบว่า Init() ถูกเรียกที่ไหนบ้าง
-- ลบการเรียก Init() ซ้ำ
```

---

### Problem 2: "Cannot start before Init()"

**Symptom:**
```
[IdempotentGuard:MyService] ❌ Cannot start before Init()!
```

**Cause:** เรียก `Start()` ก่อน `Init()`

**Solution:**
```lua
-- เรียก Init() ก่อน Start() เสมอ
MyService:Init()
MyService:Start()
```

---

### Problem 3: Guard Already Exists

**Symptom:**
```
[IdempotentGuard] ⚠️ Guard 'MyService' already exists!
```

**Cause:** สร้าง guard ชื่อซ้ำ

**Solution:**
```lua
-- ใช้ชื่อที่ unique หรือ reuse existing guard
local existingGuard = IdempotentGuard.get("MyService")
if existingGuard then
    guard = existingGuard
else
    guard = IdempotentGuard.new("MyService")
end
```

---

## 📊 Lifecycle States

```
Created
   ↓
Initialized (after MarkInitialized)
   ↓
Started (after MarkStarted)
   ↓
Stopped (after MarkStopped)
```

---

## 🎯 Summary

| Feature | Purpose |
|---------|---------|
| **Idempotent** | ทำซ้ำได้ผลเดิม |
| **MarkInitialized** | ป้องกัน double init |
| **MarkStarted** | ป้องกัน double start + enforce order |
| **RequireStarted** | Validate state ก่อนทำงาน |
| **Analytics** | ติดตามสถิติ |
| **Debug Mode** | แสดง logs ช่วย debug |

---

**Version:** 1.0  
**Last Updated:** 2024  
**Author:** OneShortArena Team

---

## 📚 Related Docs

- [Architecture Overview](./deps.md)
- [Service Pattern](./Service-Pattern.md)
- [Controller Pattern](./Controller-Pattern.md)
