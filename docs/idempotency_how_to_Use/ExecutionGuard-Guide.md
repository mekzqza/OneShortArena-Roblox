# 🛡️ ExecutionGuard Usage Guide - Production Grade

## 📋 Overview

**ExecutionGuard** เป็น Utility สำหรับควบคุมการทำงานของฟังก์ชัน ป้องกันการรันซ้ำซ้อน และจัดการ concurrent execution

### 🎯 Use Cases:

1. **RunOnce** - รัน function เพียงครั้งเดียว
2. **In-progress Lock** - ป้องกันการรันพร้อมกัน
3. **Result Reuse** - เก็บผลลัพธ์ไว้ใช้ซ้ำ
4. **Timeout Support** - จัดการ timeout อัตโนมัติ

---

## 🚀 Quick Start

### Basic RunOnce

```lua
local ExecutionGuard = require(ServerScriptService.Utils.ExecutionGuard)
local guard = ExecutionGuard.new(true) -- debug mode

-- Execute once
local success, result = guard:RunOnce("loadData", function()
    print("Loading data...")
    task.wait(2)
    return {data = "loaded"}
end)

-- Try again (will be blocked)
local success2, result2 = guard:RunOnce("loadData", function()
    print("This won't run")
end)
-- success2 = false (already completed)
-- result2 = {data = "loaded"} (cached result)
```

---

## 📚 Features

### 1️⃣ RunOnce - Execute Only Once

#### Problem: Duplicate API Calls

```lua
-- ❌ Without Guard: API called multiple times
function loadPlayerData(userId)
    local data = HttpService:GetAsync(`/api/player/{userId}`)
    return data
end

-- Called 3 times!
loadPlayerData(123)
loadPlayerData(123)  -- Duplicate!
loadPlayerData(123)  -- Duplicate!
```

#### Solution: RunOnce

```lua
-- ✅ With Guard: API called once, results cached
local guard = ExecutionGuard.new()

function loadPlayerData(userId)
    local key = `player_data_{userId}`
    
    local success, data = guard:RunOnce(key, function()
        return HttpService:GetAsync(`/api/player/{userId}`)
    end, { cacheResult = true })
    
    return data
end

-- Only first call hits API
local data1 = loadPlayerData(123)  -- API call
local data2 = loadPlayerData(123)  -- Cached ✅
local data3 = loadPlayerData(123)  -- Cached ✅
```

---

### 2️⃣ In-Progress Lock - Prevent Concurrent Execution

#### Problem: Race Condition

```lua
-- ❌ Without Lock: Both threads process order
task.spawn(function()
    processOrder(orderId)  -- Thread 1
end)

task.spawn(function()
    processOrder(orderId)  -- Thread 2 (duplicate!)
end)
```

#### Solution: Auto Locking

```lua
-- ✅ With Guard: Only one thread processes
local guard = ExecutionGuard.new()

function processOrder(orderId)
    local key = `order_{orderId}`
    
    return guard:RunOnce(key, function()
        print("Processing order", orderId)
        task.wait(5) -- Simulate processing
        return {status = "completed"}
    end)
end

-- Thread 1: Acquires lock, processes
-- Thread 2: Blocked (already running)
task.spawn(function()
    processOrder(123)  -- ✅ Runs
end)

task.spawn(function()
    processOrder(123)  -- ❌ Blocked
end)
```

---

### 3️⃣ Result Reuse - Cache Results

```lua
local guard = ExecutionGuard.new()

-- Heavy computation
local success, result = guard:RunOnce("calculate", function()
    local sum = 0
    for i = 1, 1000000 do
        sum = sum + i
    end
    return sum
end, { cacheResult = true })

print("First call:", result)  -- Computes: 500000500000

-- Get cached result
local cached = guard:GetResult("calculate")
print("Cached:", cached)  -- Returns instantly: 500000500000
```

---

### 4️⃣ Timeout Support - Auto Release

#### Problem: Stuck Execution

```lua
-- ❌ Without Timeout: Hangs forever
function fetchData()
    while true do
        task.wait(1)  -- Never completes!
    end
end

fetchData()  -- Stuck forever
```

#### Solution: Timeout

```lua
-- ✅ With Timeout: Auto-release after 10s
local guard = ExecutionGuard.new()

local success, result = guard:RunOnce("fetch", function()
    while true do
        task.wait(1)
    end
end, { 
    timeout = 10,
    onTimeout = function()
        warn("Fetch timed out!")
    end
})

-- After 10s:
-- "Fetch timed out!"
-- Lock auto-released
-- Can retry
```

---

## 📖 API Reference

### Constructor

#### `ExecutionGuard.new(debug: boolean?): ExecutionGuard`

Create new ExecutionGuard instance

```lua
local guard = ExecutionGuard.new(true)  -- With debug logs
```

---

### RunOnce

#### `guard:RunOnce(key: string, fn: () -> any, options?: ExecutionOptions): (boolean, any?)`

Execute function only once per key

**Parameters:**
- `key` - Unique identifier
- `fn` - Function to execute
- `options` - Optional configuration

**Options:**
```lua
{
    timeout = 30,          -- Timeout in seconds (default: 30)
    allowRerun = false,    -- Allow re-execution (default: false)
    cacheResult = true,    -- Cache result (default: true)
    onTimeout = function() -- Timeout callback
        warn("Timed out!")
    end
}
```

**Returns:**
- `success` - true if executed, false if blocked/failed
- `result` - Function result or cached result

---

### Lock Management

#### `guard:AcquireLock(key: string, timeout: number?): boolean`

Manually acquire execution lock

```lua
if guard:AcquireLock("myKey", 10) then
    -- Do work
    guard:ReleaseLock("myKey")
end
```

#### `guard:IsLocked(key: string): boolean`

Check if key is locked

```lua
if guard:IsLocked("myKey") then
    print("Still running")
end
```

---

### Result Management

#### `guard:GetResult(key: string): any?`

Get cached result

```lua
local result = guard:GetResult("myKey")
```

#### `guard:HasResult(key: string): boolean`

Check if has cached result

```lua
if guard:HasResult("myKey") then
    print("Result available")
end
```

#### `guard:ClearResult(key: string)`

Clear cached result

```lua
guard:ClearResult("myKey")
```

---

### Status

#### `guard:GetStatus(key: string): ExecutionStatus`

Get current status

**Returns:** `"Idle"` | `"Running"` | `"Completed"` | `"TimedOut"` | `"Failed"`

```lua
local status = guard:GetStatus("myKey")
if status == "Completed" then
    print("Done!")
end
```

---

## 💡 Real-World Examples

### Example 1: Player Data Loading

```lua
local guard = ExecutionGuard.new()

function PlayerDataService:LoadData(player: Player)
    local key = `player_data_{player.UserId}`
    
    local success, data = guard:RunOnce(key, function()
        print(`Loading data for {player.Name}...`)
        
        local success, result = pcall(function()
            return DataStore:GetAsync(player.UserId)
        end)
        
        if not success then
            error("Failed to load data")
        end
        
        return result or {
            coins = 0,
            level = 1
        }
    end, {
        timeout = 10,
        cacheResult = true,
        onTimeout = function()
            warn(`Data load timeout for {player.Name}`)
            player:Kick("Data load failed")
        end
    })
    
    return data
end
```

### Example 2: Server Initialization

```lua
local guard = ExecutionGuard.new()

function GameService:InitializeArena()
    return guard:RunOnce("arena_init", function()
        print("Initializing arena...")
        
        -- Load assets
        task.wait(2)
        
        -- Setup spawns
        task.wait(1)
        
        -- Configure lighting
        task.wait(0.5)
        
        return {initialized = true}
    end, {
        timeout = 30,
        allowRerun = false
    })
end
```

### Example 3: Daily Reward

```lua
local guard = ExecutionGuard.new()

function RewardService:ClaimDailyReward(player: Player)
    local today = os.date("%Y-%m-%d")
    local key = `daily_reward_{player.UserId}_{today}`
    
    return guard:RunOnce(key, function()
        -- Give reward
        player.leaderstats.Coins.Value += 100
        
        return {claimed = true, amount = 100}
    end, {
        allowRerun = false,  -- Once per day!
        cacheResult = true
    })
end
```

---

## 🎓 Best Practices  --how to ues Execution Guard

### ✅ DO

```lua
-- 1. Use descriptive keys
guard:RunOnce("player_data_123", fn)  -- ✅ Clear
guard:RunOnce("pd123", fn)            -- ❌ Unclear

-- 2. Set appropriate timeouts
guard:RunOnce("key", fn, {timeout = 5})  -- ✅ Short for quick ops

-- 3. Handle timeout callbacks
guard:RunOnce("key", fn, {
    timeout = 10,
    onTimeout = function()
        -- Cleanup
    end
})
```

### ❌ DON'T

```lua
-- 1. Don't use same key for different operations
guard:RunOnce("data", loadPlayerData)
guard:RunOnce("data", loadGameData)  -- ❌ Conflict!

-- 2. Don't forget to set timeout for long operations
guard:RunOnce("longTask", function()
    task.wait(100)  -- ❌ Will timeout!
end)  -- Should set {timeout = 120}

-- 3. Don't cache sensitive data
guard:RunOnce("password", fn, {
    cacheResult = true  -- ❌ Security risk!
})
```

---

## 📊 Comparison: IdempotentGuard vs ExecutionGuard

| Feature | IdempotentGuard | ExecutionGuard |
|---------|-----------------|----------------|
| **Purpose** | Init/Start lifecycle | Function execution control |
| **Scope** | Per-module (Service/Controller) | Per-operation (any function) |
| **Lock** | State-based (Created→Started) | Execution-based (acquire/release) |
| **Cache** | ❌ No result caching | ✅ Result caching |
| **Timeout** | ❌ No timeout | ✅ Auto timeout |
| **Use Case** | Prevent double Init() | Prevent duplicate API calls |

---

## 🔧 Debugging

```lua
-- F9 Console

-- Get all records
local records = guard:GetAllRecords()
for key, record in pairs(records) do
    print(key, record.status, record.executionCount)
end

-- Print summary
ExecutionGuard.printSummary(guard)

-- Check specific key
local status = guard:GetStatus("myKey")
print("Status:", status)

-- Get analytics
local analytics = guard:GetAnalytics()
print("Total:", analytics.global.totalExecutions)
print("Blocked:", analytics.global.blockedExecutions)
```

---

**Version:** 1.0  
**Last Updated:** 2024  
**Author:** OneShortArena Team
