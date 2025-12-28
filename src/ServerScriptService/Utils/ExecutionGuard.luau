--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║           EXECUTION GUARD UTILITY - PRODUCTION GRADE           ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Advanced execution control & deduplication           ║
║ Features:                                                      ║
║  ✅ RunOnce - Execute function only once per key              ║
║  ✅ In-progress lock - Prevent concurrent execution           ║
║  ✅ Result reuse - Cache and return previous results          ║
║  ✅ Timeout support - Auto-release locks after timeout        ║
║  ✅ Thread-safe - Handle race conditions                      ║
╚════════════════════════════════════════════════════════════════╝
]]

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type ExecutionStatus = "Idle" | "Running" | "Completed" | "TimedOut" | "Failed"

export type ExecutionRecord = {
	key: string,
	status: ExecutionStatus,
	startTime: number?,
	endTime: number?,
	result: any?,
	error: string?,
	executionCount: number,
	lastExecutionTime: number?,
}

export type ExecutionOptions = {
	timeout: number?, -- Seconds to wait before considering execution timed out
	allowRerun: boolean?, -- Allow re-execution even if completed
	cacheResult: boolean?, -- Cache result for reuse
	onTimeout: (() -> ())?, -- Callback on timeout
}

export type ExecutionGuard = {
	-- RunOnce execution
	RunOnce: (self: ExecutionGuard, key: string, fn: () -> any, options: ExecutionOptions?) -> (boolean, any?),
	
	-- Lock management
	AcquireLock: (self: ExecutionGuard, key: string, timeout: number?) -> boolean,
	ReleaseLock: (self: ExecutionGuard, key: string) -> (),
	IsLocked: (self: ExecutionGuard, key: string) -> boolean,
	
	-- Result management
	GetResult: (self: ExecutionGuard, key: string) -> any?,
	HasResult: (self: ExecutionGuard, key: string) -> boolean,
	ClearResult: (self: ExecutionGuard, key: string) -> (),
	
	-- Status queries
	GetStatus: (self: ExecutionGuard, key: string) -> ExecutionStatus,
	GetRecord: (self: ExecutionGuard, key: string) -> ExecutionRecord?,
	
	-- Utilities
	Reset: (self: ExecutionGuard, key: string) -> (),
	ResetAll: (self: ExecutionGuard) -> (),
	GetAllRecords: (self: ExecutionGuard) -> {[string]: ExecutionRecord},
	GetAnalytics: (self: ExecutionGuard) -> {[string]: any},
	
	-- Internal
	_records: {[string]: ExecutionRecord},
	_locks: {[string]: number}, -- key -> lock timestamp
	_timeouts: {[string]: thread?}, -- key -> timeout thread
	_debug: boolean,
}

local ExecutionGuard = {}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════

local DEFAULT_TIMEOUT = 30 -- Default timeout in seconds
local LOCK_CHECK_INTERVAL = 0.1 -- Check lock status every 0.1s

-- ═══════════════════════════════════════════════════════════════
-- GLOBAL ANALYTICS
-- ═══════════════════════════════════════════════════════════════

local globalStats = {
	totalExecutions = 0,
	blockedExecutions = 0, -- Blocked because already running
	cachedResults = 0, -- Returned cached results
	timedOutExecutions = 0,
	failedExecutions = 0,
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function log(guard: ExecutionGuard, level: "Info" | "Warn" | "Error", message: string)
	if not guard._debug and level == "Info" then
		return
	end
	
	local prefix = "[ExecutionGuard]"
	
	if level == "Error" then
		error(prefix .. " " .. message)
	elseif level == "Warn" then
		warn(prefix .. " " .. message)
	else
		print(prefix .. " " .. message)
	end
end

-- ═══════════════════════════════════════════════════════════════
-- CONSTRUCTOR
-- ═══════════════════════════════════════════════════════════════

function ExecutionGuard.new(debug: boolean?): ExecutionGuard
	local self = {} :: ExecutionGuard
	
	self._records = {}
	self._locks = {}
	self._timeouts = {}
	self._debug = debug or false
	
	-- ═══════════════════════════════════════════════════════════
	-- RUNONCE EXECUTION
	-- ═══════════════════════════════════════════════════════════
	
	--[[
		Execute function only once per key with advanced controls
		
		@param key string - Unique identifier for this execution
		@param fn function - Function to execute
		@param options ExecutionOptions? - Execution options
		@return (success: boolean, result: any?)
		
		Example:
			local success, result = guard:RunOnce("loadData", function()
				return loadPlayerData()
			end, { timeout = 10, cacheResult = true })
	]]
	function self:RunOnce(key: string, fn: () -> any, options: ExecutionOptions?): (boolean, any?)
		options = options or {}
		local timeout = options.timeout or DEFAULT_TIMEOUT
		local allowRerun = options.allowRerun or false
		local cacheResult = options.cacheResult ~= false -- Default true
		
		-- Get or create record
		local record = self._records[key]
		if not record then
			record = {
				key = key,
				status = "Idle",
				startTime = nil,
				endTime = nil,
				result = nil,
				error = nil,
				executionCount = 0,
				lastExecutionTime = nil,
			}
			self._records[key] = record
		end
		
		-- Check if already completed
		if record.status == "Completed" then
			if allowRerun then
				log(self, "Info", `🔄 Re-running '{key}' (allowRerun=true)`)
			else
				if cacheResult and record.result ~= nil then
					log(self, "Info", `♻️ Returning cached result for '{key}'`)
					globalStats.cachedResults += 1
					return true, record.result
				end
				
				log(self, "Warn", `⚠️ '{key}' already completed`)
				globalStats.blockedExecutions += 1
				return false, nil
			end
		end
		
		-- Check if currently running
		if record.status == "Running" then
			log(self, "Warn", `⚠️ '{key}' is already running (blocked)`)
			globalStats.blockedExecutions += 1
			return false, nil
		end
		
		-- Try to acquire lock
		if not self:AcquireLock(key, timeout) then
			log(self, "Warn", `🔒 Failed to acquire lock for '{key}'`)
			globalStats.blockedExecutions += 1
			return false, nil
		end
		
		-- Update record
		record.status = "Running"
		record.startTime = os.clock()
		record.executionCount += 1
		globalStats.totalExecutions += 1
		
		log(self, "Info", `▶️ Executing '{key}' (attempt #{record.executionCount})`)
		
		-- Setup timeout
		local timedOut = false
		if timeout > 0 then
			self._timeouts[key] = task.delay(timeout, function()
				if record.status == "Running" then
					timedOut = true
					record.status = "TimedOut"
					record.endTime = os.clock()
					self:ReleaseLock(key)
					
					globalStats.timedOutExecutions += 1
					log(self, "Warn", `⏱️ '{key}' timed out after {timeout}s`)
					
					if options.onTimeout then
						options.onTimeout()
					end
				end
			end)
		end
		
		-- Execute function
		local success, result = pcall(fn)
		
		-- Cancel timeout
		if self._timeouts[key] then
			task.cancel(self._timeouts[key])
			self._timeouts[key] = nil
		end
		
		-- Don't update if already timed out
		if timedOut then
			return false, nil
		end
		
		-- Update record
		record.endTime = os.clock()
		record.lastExecutionTime = record.endTime
		
		if success then
			record.status = "Completed"
			if cacheResult then
				record.result = result
			end
			record.error = nil
			
			local duration = record.endTime - (record.startTime or record.endTime)
			log(self, "Info", `✅ '{key}' completed in {string.format("%.3f", duration)}s`)
		else
			record.status = "Failed"
			record.error = tostring(result)
			
			globalStats.failedExecutions += 1
			log(self, "Error", `❌ '{key}' failed: {result}`)
		end
		
		-- Release lock
		self:ReleaseLock(key)
		
		return success, result
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- LOCK MANAGEMENT
	-- ═══════════════════════════════════════════════════════════
	
	function self:AcquireLock(key: string, timeout: number?): boolean
		timeout = timeout or DEFAULT_TIMEOUT
		local startTime = os.clock()
		
		-- Wait for lock with timeout
		while self._locks[key] do
			if (os.clock() - startTime) > timeout then
				log(self, "Warn", `🔒 Lock acquisition timed out for '{key}'`)
				return false
			end
			task.wait(LOCK_CHECK_INTERVAL)
		end
		
		-- Acquire lock
		self._locks[key] = os.clock()
		log(self, "Info", `🔓 Lock acquired for '{key}'`)
		return true
	end
	
	function self:ReleaseLock(key: string)
		if self._locks[key] then
			self._locks[key] = nil
			log(self, "Info", `🔓 Lock released for '{key}'`)
		end
	end
	
	function self:IsLocked(key: string): boolean
		return self._locks[key] ~= nil
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- RESULT MANAGEMENT
	-- ═══════════════════════════════════════════════════════════
	
	function self:GetResult(key: string): any?
		local record = self._records[key]
		return record and record.result
	end
	
	function self:HasResult(key: string): boolean
		local record = self._records[key]
		return record ~= nil and record.result ~= nil
	end
	
	function self:ClearResult(key: string)
		local record = self._records[key]
		if record then
			record.result = nil
			log(self, "Info", `🧹 Cleared result for '{key}'`)
		end
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- STATUS QUERIES
	-- ═══════════════════════════════════════════════════════════
	
	function self:GetStatus(key: string): ExecutionStatus
		local record = self._records[key]
		return record and record.status or "Idle"
	end
	
	function self:GetRecord(key: string): ExecutionRecord?
		return self._records[key]
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- UTILITIES
	-- ═══════════════════════════════════════════════════════════
	
	function self:Reset(key: string)
		local record = self._records[key]
		if record then
			record.status = "Idle"
			record.result = nil
			record.error = nil
			record.startTime = nil
			record.endTime = nil
			
			log(self, "Info", `🔄 Reset '{key}'`)
		end
		
		self:ReleaseLock(key)
		
		if self._timeouts[key] then
			task.cancel(self._timeouts[key])
			self._timeouts[key] = nil
		end
	end
	
	function self:ResetAll()
		for key in pairs(self._records) do
			self:Reset(key)
		end
		
		log(self, "Info", "🔄 Reset all records")
	end
	
	function self:GetAllRecords(): {[string]: ExecutionRecord}
		return self._records
	end
	
	function self:GetAnalytics(): {[string]: any}
		local records = 0
		local byStatus = {
			Idle = 0,
			Running = 0,
			Completed = 0,
			TimedOut = 0,
			Failed = 0,
		}
		
		for _, record in pairs(self._records) do
			records += 1
			byStatus[record.status] = (byStatus[record.status] or 0) + 1
		end
		
		return {
			totalRecords = records,
			byStatus = byStatus,
			global = globalStats,
		}
	end
	
	log(self, "Info", `🛡️ ExecutionGuard created (Debug: {self._debug})`)
	
	return self
end

-- ═══════════════════════════════════════════════════════════════
-- GLOBAL UTILITIES
-- ═══════════════════════════════════════════════════════════════

function ExecutionGuard.getGlobalStats(): {[string]: any}
	return globalStats
end

function ExecutionGuard.printSummary(guard: ExecutionGuard)
	print("╔════════════════════════════════════════════════════════════════╗")
	print("║              EXECUTION GUARD SUMMARY                           ║")
	print("╠════════════════════════════════════════════════════════════════╣")
	
	local analytics = guard:GetAnalytics()
	print(string.format("║ Total Records: %d", analytics.totalRecords))
	print(string.format("║ Total Executions: %d", analytics.global.totalExecutions))
	print(string.format("║ Blocked: %d | Cached: %d", analytics.global.blockedExecutions, analytics.global.cachedResults))
	print(string.format("║ Timed Out: %d | Failed: %d", analytics.global.timedOutExecutions, analytics.global.failedExecutions))
	print("╠════════════════════════════════════════════════════════════════╣")
	print("║ Status Distribution:")
	
	for status, count in pairs(analytics.byStatus) do
		if count > 0 then
			local symbol = status == "Completed" and "✅" 
				or status == "Running" and "▶️"
				or status == "Failed" and "❌"
				or status == "TimedOut" and "⏱️"
				or "⚪"
			
			print(string.format("║ %s %-20s %d", symbol, status, count))
		end
	end
	
	print("╚════════════════════════════════════════════════════════════════╝")
end

return ExecutionGuard

--[[]
╔════════════════════════════════════════════════════════════════╗
║                    📚 EXECUTION GUARD - สรุปการใช้งาน          ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║ 🎯 PURPOSE (จุดประสงค์):                                       ║
║    ควบคุมการทำงานของฟังก์ชันให้รันเพียงครั้งเดียว            ║
║    ป้องกันการ execute ซ้ำซ้อน และจัดการ concurrent execution  ║
║                                                                ║
║ ✨ FEATURES (ฟีเจอร์หลัก):                                      ║
║    1. RunOnce      - รันฟังก์ชันครั้งเดียวต่อ key             ║
║    2. Lock         - ป้องกันการรันพร้อมกัน (race condition)   ║
║    3. Cache        - เก็บผลลัพธ์ไว้ใช้ซ้ำ                      ║
║    4. Timeout      - จัดการ timeout อัตโนมัติ                  ║
║    5. Thread-safe  - ทำงานได้ปลอดภัยแม้มีหลาย thread          ║
║                                                                ║
║ 📖 BASIC USAGE (วิธีใช้พื้นฐาน):                               ║
║                                                                ║
║    -- สร้าง instance                                          ║
║    local guard = ExecutionGuard.new(true)                     ║
║                                                                ║
║    -- รันฟังก์ชันครั้งเดียว                                   ║
║    local success, result = guard:RunOnce("loadData", function()║
║        return loadPlayerDataFromAPI()                          ║
║    end, {                                                      ║
║        timeout = 10,         -- Timeout 10 วินาที             ║
║        cacheResult = true,   -- เก็บผลลัพธ์ไว้                ║
║        allowRerun = false    -- ห้ามรันซ้ำ                    ║
║    })                                                          ║
║                                                                ║
║ 🎓 ADVANCED USAGE (ใช้งานขั้นสูง):                             ║
║                                                                ║
║    -- จัดการ lock ด้วยตัวเอง                                   ║
║    if guard:AcquireLock("myTask", 5) then                     ║
║        -- Do work                                             ║
║        guard:ReleaseLock("myTask")                            ║
║    end                                                         ║
║                                                                ║
║    -- เช็คสถานะ                                                ║
║    local status = guard:GetStatus("myKey")                    ║
║    -- Returns: "Idle" | "Running" | "Completed" | "TimedOut"  ║
║                                                                ║
║    -- ดึงผลลัพธ์ที่เก็บไว้                                     ║
║    local cachedResult = guard:GetResult("myKey")              ║
║                                                                ║
║ 💡 USE CASES (กรณีใช้งาน):                                     ║
║                                                                ║
║    ✅ โหลดข้อมูล Player จาก DataStore ครั้งเดียว             ║
║    ✅ เรียก API ภายนอก (ป้องกัน duplicate calls)             ║
║    ✅ ประมวลผล Order/Transaction (ป้องกันซ้ำซ้อน)            ║
║    ✅ Initialize Server/Game (รันครั้งเดียว)                  ║
║    ✅ Rate-limited operations (จำกัดการเรียก)                 ║
║                                                                ║
║ ⚠️ IMPORTANT NOTES (ข้อควรระวัง):                             ║
║                                                                ║
║    • ใช้ key ที่ unique สำหรับแต่ละงาน                         ║
║    • ตั้ง timeout ให้เหมาะสมกับงาน                            ║
║    • ใช้ cacheResult=false สำหรับงานที่ไม่ควร cache          ║
║    • Reset() เฉพาะเมื่อจำเป็น (ระวัง race condition)         ║
║                                                                ║
║ 📊 ANALYTICS (การติดตามสถิติ):                                ║
║                                                                ║
║    local analytics = guard:GetAnalytics()                     ║
║    print("Total Executions:", analytics.global.totalExecutions)║
║    print("Blocked:", analytics.global.blockedExecutions)      ║
║    print("Cached:", analytics.global.cachedResults)           ║
║                                                                ║
║    -- แสดงสรุปแบบละเอียด                                       ║
║    ExecutionGuard.printSummary(guard)                         ║
║                                                                ║
║ 🔄 LIFECYCLE (วงจรการทำงาน):                                  ║
║                                                                ║
║    1. Idle      → ยังไม่เริ่มทำงาน                            ║
║    2. Running   → กำลังทำงาน (มี lock)                        ║
║    3. Completed → ทำงานเสร็จแล้ว (มี result)                  ║
║    4. TimedOut  → Timeout (lock ถูกปล่อยอัตโนมัติ)            ║
║    5. Failed    → ทำงานล้มเหลว (error stored)                ║
║                                                                ║
║ 🎯 REAL-WORLD EXAMPLES (ตัวอย่างจริง):                        ║
║                                                                ║
║    -- Example 1: Load player data                             ║
║    function loadPlayerData(userId)                            ║
║        return guard:RunOnce(`player_{userId}`, function()     ║
║            return DataStore:GetAsync(userId)                  ║
║        end, { timeout = 10, cacheResult = true })             ║
║    end                                                         ║
║                                                                ║
║    -- Example 2: Process purchase                             ║
║    function processPurchase(player, itemId)                   ║
║        local key = `purchase_{player.UserId}_{itemId}`        ║
║        return guard:RunOnce(key, function()                   ║
║            -- Deduct currency, give item                      ║
║            return {success = true}                            ║
║        end, { timeout = 5, cacheResult = false })             ║
║    end                                                         ║
║                                                                ║
║    -- Example 3: API call with retry                          ║
║    function fetchFromAPI(endpoint)                            ║
║        return guard:RunOnce(`api_{endpoint}`, function()      ║
║            return HttpService:GetAsync(endpoint)              ║
║        end, {                                                  ║
║            timeout = 10,                                       ║
║            onTimeout = function()                             ║
║                warn("API timeout!")                           ║
║            end                                                 ║
║        })                                                      ║
║    end                                                         ║
║                                                                ║
║ 🐛 DEBUGGING (การ Debug):                                     ║
║                                                                ║
║    -- เปิด debug mode                                         ║
║    local guard = ExecutionGuard.new(true)                     ║
║                                                                ║
║    -- ดู record ทั้งหมด                                        ║
║    local records = guard:GetAllRecords()                      ║
║    for key, record in records do                              ║
║        print(key, record.status, record.executionCount)       ║
║    end                                                         ║
║                                                                ║
║    -- เช็คว่ามี lock อยู่ไหม                                   ║
║    if guard:IsLocked("myKey") then                            ║
║        print("Still running!")                                ║
║    end                                                         ║
║                                                                ║
║ 📚 API REFERENCE (รายละเอียด API):                            ║
║                                                                ║
║    Core Methods:                                              ║
║    • RunOnce(key, fn, options) -> (success, result)          ║
║    • AcquireLock(key, timeout) -> boolean                    ║
║    • ReleaseLock(key)                                         ║
║    • IsLocked(key) -> boolean                                ║
║                                                                ║
║    Result Management:                                         ║
║    • GetResult(key) -> any?                                   ║
║    • HasResult(key) -> boolean                                ║
║    • ClearResult(key)                                         ║
║                                                                ║
║    Status Queries:                                            ║
║    • GetStatus(key) -> ExecutionStatus                        ║
║    • GetRecord(key) -> ExecutionRecord?                       ║
║                                                                ║
║    Utilities:                                                 ║
║    • Reset(key)                                               ║
║    • ResetAll()                                               ║
║    • GetAllRecords() -> {[string]: ExecutionRecord}          ║
║    • GetAnalytics() -> table                                  ║
║                                                                ║
║    Global:                                                    ║
║    • ExecutionGuard.getGlobalStats() -> table                ║
║    • ExecutionGuard.printSummary(guard)                      ║
║                                                                ║
║ 📝 BEST PRACTICES (แนวทางที่ดี):                              ║
║                                                                ║
║    ✅ ใช้ key ที่มีความหมายชัดเจน                             ║
║    ✅ ตั้ง timeout ให้เหมาะสมกับงาน                           ║
║    ✅ ใช้ cacheResult=true สำหรับข้อมูลที่ไม่เปลี่ยน         ║
║    ✅ Handle error cases (success = false)                    ║
║    ✅ Monitor analytics ใน production                         ║
║                                                                ║
║    ❌ อย่าใช้ key ซ้ำกันสำหรับงานที่ต่างกัน                  ║
║    ❌ อย่าตั้ง timeout สั้นเกินไป                             ║
║    ❌ อย่า cache sensitive data                               ║
║    ❌ อย่า Reset() บ่อยเกินไป                                 ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

TLDR (สรุปสั้นๆ):
─────────────────────────────────────────────────────────────────
ExecutionGuard = ตัวจัดการที่ทำให้ฟังก์ชันรันเพียงครั้งเดียว
                พร้อม cache ผลลัพธ์, timeout, และ lock

การใช้งาน 3 ขั้นตอน:
1. สร้าง:     local guard = ExecutionGuard.new(true)
2. รัน:       local ok, result = guard:RunOnce(key, fn, options)
3. ตรวจสอบ:   local status = guard:GetStatus(key)

เหมาะสำหรับ:
• โหลดข้อมูล DataStore
• เรียก API ภายนอก
• ประมวลผล Transaction
• Initialize ระบบ
─────────────────────────────────────────────────────────────────

Version: 1.0.0
Author: OneShortArena Team
Last Updated: 2024
]]
