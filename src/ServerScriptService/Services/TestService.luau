--!strict

-- ไฟล์นี้ใช้สำหรับทดสอบ server-side services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.Core.NetworkHandler)

-- ✅ แก้ไข: ใช้ IdempotentGuard สำหรับ Init/Start protection
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- ✅ ExecutionGuard ใช้แยกสำหรับ demos
local ExecutionGuard = require(ServerScriptService.Utils.ExecutionGuard)

export type TestService = {
    Init: (self: TestService) -> (),
    Start: (self: TestService) -> (),
    [string]: any,
}

local TestService = {} :: TestService

-- ✅ แก้ไข: ใช้ IdempotentGuard สำหรับ service lifecycle
local guard = IdempotentGuard.new("TestService", true)

-- ✅ ExecutionGuard สำหรับ demos
local execGuard = ExecutionGuard.new(true)


-- ═══════════════════════════════════════════════════════════════
-- DEMO FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

--[[]
    DEMO 1: RunOnce - Load Player Data
    
    ✅ Use Case: Load player data from DataStore only once
    ✅ Feature: Cached result, subsequent calls return cached data
]]
local function loadPlayerData(userId: number): any?
    local key = `player_data_{userId}`
    
    -- ✅ ใช้ execGuard แทน guard
    local success, result = execGuard:RunOnce(key, function()
        print(`[TestService] 💾 Loading data for user {userId}...`)
        
        -- Simulate expensive operation
        task.wait(2)
        
        return {
            userId = userId,
            coins = 1000,
            level = 5,
            loadedAt = os.clock()
        }
    end, {
        timeout = 10,           -- 10 second timeout
        cacheResult = true,     -- Cache the result
        allowRerun = false,     -- Don't allow re-execution
    })
    
    return result
end

--[[]
    DEMO 2: RunOnce with Timeout
    
    ✅ Use Case: API call that might hang
    ✅ Feature: Auto-timeout after X seconds
]]
local function fetchExternalData(apiUrl: string): any?
    local key = `api_fetch_{apiUrl}`
    
    local success, result = execGuard:RunOnce(key, function()
        print(`[TestService] 🌐 Fetching from {apiUrl}...`)
        
        -- Simulate slow API
        task.wait(5)
        
        return {
            data = "API response",
            timestamp = os.clock()
        }
    end, {
        timeout = 3,  -- ⏱️ Timeout after 3 seconds (will fail!)
        onTimeout = function()
            warn(`[TestService] ⚠️ API call to {apiUrl} timed out!`)
        end
    })
    
    return result
end

--[[]
    DEMO 3: Prevent Concurrent Execution
    
    ✅ Use Case: Process order only once, even if multiple requests
    ✅ Feature: In-progress lock
]]
local function processOrder(orderId: number): boolean
    local key = `order_{orderId}`
    
    local success, result = execGuard:RunOnce(key, function()
        print(`[TestService] 📦 Processing order {orderId}...`)
        
        -- Simulate order processing
        task.wait(3)
        
        return {
            orderId = orderId,
            status = "completed",
            processedAt = os.clock()
        }
    end, {
        timeout = 10,
        cacheResult = false,  -- Don't cache (one-time operation)
    })
    
    return success
end

--[[]
    DEMO 4: Manual Lock Management
    
    ✅ Use Case: Complex operation with manual control
]]
local function complexOperation(taskId: string)
    if not execGuard:AcquireLock(taskId, 5) then
        warn(`[TestService] 🔒 Failed to acquire lock for {taskId}`)
        return false
    end
    
    print(`[TestService] 🔓 Lock acquired for {taskId}`)
    
    -- Do work
    task.wait(2)
    print(`[TestService] ✅ Work completed for {taskId}`)
    
    -- Release lock
    execGuard:ReleaseLock(taskId)
    
    return true
end

-- ═══════════════════════════════════════════════════════════════
-- SERVICE IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════

function TestService:Init()
    -- ✅ ถูกต้องแล้ว: ใช้ IdempotentGuard
    if not guard:MarkInitialized() then
        return
    end
    
    -- ✅ แก้ไข: เปลี่ยนจาก AllowServerEvent → AllowClientEvent
    NetworkHandler:AllowClientEvent(Events.TEST_PING)
    
    print("[TestService] 🧪 Initialized")
end

function TestService:Start()
    -- ✅ ถูกต้องแล้ว: ใช้ IdempotentGuard
    if not guard:MarkStarted() then
        return
    end
    
    -- Listen for TEST_PING from client
    EventBus:On(Events.TEST_PING, function(player: Player, payload: any)
        print(string.format("[TestService-Server] 📨 Received from %s", player.Name))
        
        if type(payload) ~= "table" then
            warn("[TestService-Server] ❌ Payload is not a table!")
            return
        end
        
        -- ✅ DEMO: Use ExecutionGuard to load player data
        print("\n🎯 DEMO 1: Loading Player Data (RunOnce)")
        print("─────────────────────────────────────────")
        
        local data1 = loadPlayerData(player.UserId)
        print("First call result:", data1)
        
        task.wait(0.5)
        
        local data2 = loadPlayerData(player.UserId)
        print("Second call result (cached):", data2)
        print("Same object?", data1 == data2)  -- Should be true
        
        -- ✅ DEMO: Test timeout
        print("\n🎯 DEMO 2: Timeout Test")
        print("─────────────────────────────────────────")
        
        local apiResult = fetchExternalData("https://api.example.com")
        print("API result:", apiResult)  -- Should be nil (timed out)
        
        -- ✅ DEMO: Concurrent execution prevention
        print("\n🎯 DEMO 3: Concurrent Execution Prevention")
        print("─────────────────────────────────────────")
        
        -- Simulate two simultaneous requests
        task.spawn(function()
            local success = processOrder(12345)
            print("Thread 1 result:", success)
        end)
        
        task.wait(0.1)
        
        task.spawn(function()
            local success = processOrder(12345)  -- Same order!
            print("Thread 2 result:", success)  -- Should be false (blocked)
        end)
        
        task.wait(4)
        
        -- ✅ DEMO: Get execution status
        print("\n🎯 DEMO 4: Query Status")
        print("─────────────────────────────────────────")
        
        -- ✅ แก้ไข: ใช้ execGuard ในการ query
        local status = execGuard:GetStatus(`player_data_{player.UserId}`)
        print("Player data status:", status)
        
        local hasResult = execGuard:HasResult(`player_data_{player.UserId}`)
        print("Has cached result?", hasResult)
        
        -- ✅ DEMO: Manual lock
        print("\n🎯 DEMO 5: Manual Lock Management")
        print("─────────────────────────────────────────")
        
        complexOperation("task_001")
        
        -- ✅ แก้ไข: Print summary ของ execGuard
        print("\n📊 ExecutionGuard Summary:")
        print("═════════════════════════════════════════")
        ExecutionGuard.printSummary(execGuard)
        
        -- ✅ Send response
        NetworkHandler:SendToClient(player, Events.TEST_PONG, {
            success = true,
            message = "ExecutionGuard demos completed!",
            serverTime = os.clock()
        })
    end)
    
    -- ═══════════════════════════════════════════════════════════
    -- PERIODIC ANALYTICS
    -- ═══════════════════════════════════════════════════════════
    
    -- task.spawn(function()
    --     while true do
    --         task.wait(60)  -- Every minute
            
    --         local analytics = guard:GetAnalytics()
            
    --         print("\n📊 [TestService] ExecutionGuard Analytics:")
    --         print(string.format("  Total Executions: %d", analytics.global.totalExecutions))
    --         print(string.format("  Blocked: %d", analytics.global.blockedExecutions))
    --         print(string.format("  Cached Results: %d", analytics.global.cachedResults))
    --         print(string.format("  Timed Out: %d", analytics.global.timedOutExecutions))
    --         print(string.format("  Failed: %d", analytics.global.failedExecutions))
    --     end
    -- end)
    
    print("[TestService-Server] 🚀 Started - Listening for TEST_PING")
end

return TestService

--[[]
╔════════════════════════════════════════════════════════════════╗
║              📚 TEST SERVICE - สรุปการใช้งาน DEMO              ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║ 🎯 PURPOSE (จุดประสงค์):                                       ║
║    สาธิตการใช้งาน ExecutionGuard ในทุกรูปแบบ                  ║
║    ทดสอบ Network, EventBus, และ ExecutionGuard                ║
║                                                                ║
║ 🧪 DEMOS INCLUDED (การสาธิตที่มี):                            ║
║                                                                ║
║    DEMO 1: RunOnce - Load Player Data                        ║
║    ├─ แสดงการ cache ผลลัพธ์                                   ║
║    ├─ การเรียกครั้งที่ 2 ได้ผลทันที (cached)                 ║
║    └─ Use Case: DataStore operations                         ║
║                                                                ║
║    DEMO 2: Timeout Test                                       ║
║    ├─ แสดงการทำงานของ timeout                                 ║
║    ├─ onTimeout callback ถูกเรียก                             ║
║    └─ Use Case: External API calls                           ║
║                                                                ║
║    DEMO 3: Concurrent Execution Prevention                    ║
║    ├─ แสดง in-progress lock                                   ║
║    ├─ Thread 2 ถูก block เพราะ Thread 1 กำลังทำงาน          ║
║    └─ Use Case: Payment processing, Order processing         ║
║                                                                ║
║    DEMO 4: Query Status                                       ║
║    ├─ แสดงการเช็คสถานะ                                         ║
║    ├─ การตรวจสอบว่ามี cached result หรือไม่                   ║
║    └─ Use Case: Status monitoring                            ║
║                                                                ║
║    DEMO 5: Manual Lock Management                            ║
║    ├─ แสดงการใช้ AcquireLock/ReleaseLock                      ║
║    ├─ ควบคุม lock ด้วยตัวเอง                                  ║
║    └─ Use Case: Complex multi-step operations                ║
║                                                                ║
║ 📖 HOW TO TEST (วิธีทดสอบ):                                    ║
║                                                                ║
║    1. เปิดเกมใน Roblox Studio                                 ║
║    2. กด F9 เปิด Console                                      ║
║    3. กด P (หรือ key ที่ bind TESTPING)                       ║
║    4. ดู console output                                       ║
║                                                                ║
║ 🎓 WHAT YOU'LL SEE (สิ่งที่จะเห็น):                           ║
║                                                                ║
║    [TestService] 💾 Loading data for user 123...             ║
║    First call result: {userId=123, coins=1000, ...}          ║
║    Second call result (cached): {userId=123, ...}            ║
║    Same object? true                                          ║
║                                                                ║
║    [TestService] ⚠️ API call timed out!                       ║
║    API result: nil                                            ║
║                                                                ║
║    Thread 1 result: true                                      ║
║    Thread 2 result: false  (blocked)                          ║
║                                                                ║
║    Player data status: Completed                              ║
║    Has cached result? true                                    ║
║                                                                ║
║    ╔════════════════════════════════════════╗                 ║
║    ║    EXECUTION GUARD SUMMARY             ║                 ║
║    ╠════════════════════════════════════════╣                 ║
║    ║ Total Records: 3                       ║                 ║
║    ║ Total Executions: 4                    ║                 ║
║    ║ Blocked: 1 | Cached: 1                 ║                 ║
║    ║ Timed Out: 1 | Failed: 0               ║                 ║
║    ╚════════════════════════════════════════╝                 ║
║                                                                ║
║ 💡 LEARNING POINTS (จุดเรียนรู้):                              ║
║                                                                ║
║    ✅ RunOnce จะ cache ผลลัพธ์ → การเรียกซ้ำได้ผลทันที      ║
║    ✅ Timeout จะปล่อย lock อัตโนมัติ → ป้องกัน deadlock      ║
║    ✅ In-progress lock → ป้องกัน concurrent execution        ║
║    ✅ Status query → ตรวจสอบสถานะได้ตลอดเวลา                 ║
║    ✅ Manual lock → ควบคุมได้ละเอียด                          ║
║                                                                ║
║ 🔧 CUSTOMIZATION (ปรับแต่ง):                                  ║
║                                                                ║
║    แก้ timeout:                                               ║
║    timeout = 10  -- เปลี่ยนเป็น 5, 15, 30, etc.             ║
║                                                                ║
║    ปิด cache:                                                 ║
║    cacheResult = false  -- ไม่เก็บผลลัพธ์                    ║
║                                                                ║
║    อนุญาตรันซ้ำ:                                               ║
║    allowRerun = true  -- รันได้หลายครั้ง                     ║
║                                                                ║
║ 📊 PERIODIC ANALYTICS (สถิติแบบ Real-time):                   ║
║                                                                ║
║    Service จะแสดงสถิติทุก 60 วินาที:                          ║
║    • Total Executions                                         ║
║    • Blocked Executions                                       ║
║    • Cached Results                                           ║
║    • Timed Out                                                ║
║    • Failed                                                   ║
║                                                                ║
║ 🎯 USE THIS AS TEMPLATE (ใช้เป็นแม่แบบ):                      ║
║                                                                ║
║    คัดลอก pattern จาก demo functions:                         ║
║    • loadPlayerData()     → DataStore operations             ║
║    • fetchExternalData()  → API calls                        ║
║    • processOrder()       → Transactions                     ║
║    • complexOperation()   → Multi-step tasks                 ║
║                                                                ║
║ ⚠️ IMPORTANT (ข้อสำคัญ):                                       ║
║                                                                ║
║    • นี่คือ TEST SERVICE สำหรับเรียนรู้เท่านั้น              ║
║    • Production ใช้ pattern แต่ลบ demo code                  ║
║    • Debug mode = true → เห็น log ทุกอย่าง                   ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

TLDR (สรุปสั้นๆ):
─────────────────────────────────────────────────────────────────
TestService = สาธิตการใช้ ExecutionGuard ครบทุกรูปแบบ

วิธีใช้:
1. กด P ในเกม
2. ดู Console
3. เรียนรู้จาก output

Demos:
• Load Data (cache demo)
• Timeout (timeout demo)
• Concurrent (lock demo)
• Status (query demo)
• Manual Lock (advanced demo)

เหมาะสำหรับ: เรียนรู้ ExecutionGuard pattern
─────────────────────────────────────────────────────────────────

Version: Demo 1.0
Author: OneShortArena Team
Last Updated: 2024
]]