# 🛡️ ExecutionGuard - Production Guide

## 📋 Overview

**ExecutionGuard** เป็น utility สำหรับควบคุมการ execute ฟังก์ชันให้รันเพียงครั้งเดียว พร้อมจัดการ:
- **RunOnce** - รันฟังก์ชันครั้งเดียวต่อ key
- **Lock Management** - ป้องกัน concurrent execution
- **Result Cache** - เก็บผลลัพธ์ไว้ใช้ซ้ำ
- **Timeout Protection** - จัดการ timeout อัตโนมัติ

---

## 🎯 Use Cases in TestService

### 1. Data Loading (RunOnce)

```lua
local guard = ExecutionGuard.new(true)

function TestService:LoadTestData()
    local success, data = guard:RunOnce("loadTestData", function()
        -- This runs only once, even if called multiple times
        return HttpService:GetAsync("https://api.example.com/data")
    end, {
        timeout = 10,
        cacheResult = true,  -- Cache result for reuse
    })
    
    if success then
        print("Data loaded:", data)
    else
        warn("Data load failed or already running")
    end
end

-- Subsequent calls return cached result
TestService:LoadTestData()  -- Loads from API
TestService:LoadTestData()  -- Returns cached result ✅
```

---

### 2. Initialization Protection

```lua
function TestService:Init()
    local success = guard:RunOnce("init", function()
        -- Run initialization logic
        self:SetupTestEnvironment()
        self:LoadConfigurations()
        return true
    end, {
        allowRerun = false,  -- Prevent re-initialization
    })
    
    if not success then
        warn("TestService already initialized!")
    end
end
```

---

### 3. Lock Management (Prevent Concurrent Tests)

```lua
function TestService:RunTest(testName)
    -- Try to acquire lock
    if not guard:AcquireLock(testName, 30) then
        warn(`Test '{testName}' is already running!`)
        return false
    end
    
    -- Run test (protected by lock)
    local success = pcall(function()
        -- ... test logic ...
    end)
    
    -- Always release lock
    guard:ReleaseLock(testName)
    
    return success
end
```

---

### 4. Execution Status Tracking

```lua
function TestService:GetTestStatus(testName)
    local status = guard:GetStatus(testName)
    -- Returns: "Idle" | "Running" | "Completed" | "TimedOut" | "Failed"
    
    if status == "Running" then
        print("Test is currently running...")
    elseif status == "Completed" then
        local result = guard:GetResult(testName)
        print("Test completed with result:", result)
    elseif status == "TimedOut" then
        warn("Test timed out!")
    end
end
```

---

### 5. Complete TestService Example

```lua
-- filepath: TestService.luau

local ExecutionGuard = require(script.Parent.Parent.Utils.ExecutionGuard)

local TestService = {}
local guard = ExecutionGuard.new(true)  -- Debug mode

function TestService:Init()
    guard:RunOnce("init", function()
        print("[TestService] Initializing...")
        self:LoadTestSuite()
    end)
end

function TestService:RunAllTests()
    local testNames = {"Test1", "Test2", "Test3"}
    
    for _, testName in testNames do
        guard:RunOnce(testName, function()
            print(`Running {testName}...`)
            
            -- Simulate test
            task.wait(1)
            
            return {success = true, duration = 1.0}
        end, {
            timeout = 5,
            cacheResult = true,
            onTimeout = function()
                warn(`{testName} timed out!`)
            end
        })
    end
end

function TestService:GetTestResults()
    local results = {}
    local records = guard:GetAllRecords()
    
    for key, record in records do
        results[key] = {
            status = record.status,
            result = record.result,
            executionCount = record.executionCount,
        }
    end
    
    return results
end

function TestService:PrintAnalytics()
    ExecutionGuard.printSummary(guard)
end

return TestService
```

---

## 📊 ExecutionStatus Values

| Status | Description | Next Action |
|--------|-------------|-------------|
| `Idle` | Not started | Can execute |
| `Running` | Currently executing | Wait or block |
| `Completed` | Finished successfully | Can get result |
| `TimedOut` | Exceeded timeout | Can retry |
| `Failed` | Execution failed | Check error |

---

## 🔧 API Reference

### Constructor
```lua
local guard = ExecutionGuard.new(debug: boolean?)
```

### Core Methods
```lua
guard:RunOnce(key, fn, options) -> (success, result)
guard:AcquireLock(key, timeout) -> boolean
guard:ReleaseLock(key)
guard:IsLocked(key) -> boolean
```

### Result Management
```lua
guard:GetResult(key) -> any?
guard:HasResult(key) -> boolean
guard:ClearResult(key)
```

### Status Queries
```lua
guard:GetStatus(key) -> ExecutionStatus
guard:GetRecord(key) -> ExecutionRecord?
```

### Utilities
```lua
guard:Reset(key)
guard:ResetAll()
guard:GetAnalytics() -> table
ExecutionGuard.printSummary(guard)
```

---

**Version:** 1.0  
**Author:** OneShortArena Team
