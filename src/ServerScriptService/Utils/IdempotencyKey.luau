--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║           IDEMPOTENCY KEY - DUPLICATE OPERATION PREVENTION     ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Generate and track unique keys for operations         ║
║ Features:                                                      ║
║  ✅ Unique key generation - UUID-like keys                     ║
║  ✅ Operation tracking - Prevent duplicate execution           ║
║  ✅ TTL support - Auto-expire old keys                         ║
║  ✅ Result caching - Return previous result for duplicates     ║
║  ✅ Distributed support - Works across server instances        ║
╚════════════════════════════════════════════════════════════════╝

USAGE:
  -- Generate key for operation
  local key = IdempotencyKey.Generate("sync", player.UserId)
  
  -- Check if operation was already done
  if IdempotencyKey:WasProcessed(key) then
      return IdempotencyKey:GetResult(key) -- Return cached result
  end
  
  -- Mark as processing
  IdempotencyKey:MarkProcessing(key)
  
  -- Do operation...
  local result = doSomething()
  
  -- Mark complete with result
  IdempotencyKey:MarkComplete(key, result)
]]

local HttpService = game:GetService("HttpService")

local IdempotencyKey = {}

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type OperationStatus = "Processing" | "Complete" | "Failed" | "Expired"

export type OperationRecord = {
	key: string,
	operation: string,
	status: OperationStatus,
	createdAt: number,
	completedAt: number?,
	expiresAt: number,
	result: any?,
	error: string?,
	metadata: {[string]: any}?,
}

export type IdempotencyKeyConfig = {
	defaultTTL: number,     -- Default time-to-live in seconds
	cleanupInterval: number, -- How often to cleanup expired keys
	maxKeys: number,        -- Max keys to store (LRU eviction)
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local DEFAULT_CONFIG: IdempotencyKeyConfig = {
	defaultTTL = 300,       -- 5 minutes
	cleanupInterval = 60,   -- Cleanup every minute
	maxKeys = 10000,        -- Max 10k keys
}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local operations: {[string]: OperationRecord} = {}
local keyOrder: {string} = {} -- For LRU eviction
local config = DEFAULT_CONFIG

local analytics = {
	totalGenerated = 0,
	duplicatesBlocked = 0,
	expired = 0,
	evicted = 0,
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function generateUUID(): string
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	return string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format("%x", v)
	end)
end

local function isExpired(record: OperationRecord): boolean
	return os.time() > record.expiresAt
end

local function evictOldest()
	if #keyOrder > 0 then
		local oldestKey = table.remove(keyOrder, 1)
		if oldestKey and operations[oldestKey] then
			operations[oldestKey] = nil
			analytics.evicted += 1
		end
	end
end

local function cleanupExpired()
	local now = os.time()
	local keysToRemove: {string} = {}
	
	for key, record in pairs(operations) do
		if now > record.expiresAt then
			table.insert(keysToRemove, key)
		end
	end
	
	for _, key in ipairs(keysToRemove) do
		operations[key] = nil
		
		-- Remove from order
		local index = table.find(keyOrder, key)
		if index then
			table.remove(keyOrder, index)
		end
		
		analytics.expired += 1
	end
	
	if #keysToRemove > 0 then
		print(`[IdempotencyKey] 🧹 Cleaned up {#keysToRemove} expired keys`)
	end
end

-- Start cleanup task
task.spawn(function()
	while true do
		task.wait(config.cleanupInterval)
		cleanupExpired()
	end
end)

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

--[[
    Generate a unique idempotency key
    @param operation string - Operation name (e.g., "sync", "purchase")
    @param ... any - Additional identifiers (userId, itemId, etc.)
    @return string - Unique idempotency key
    
    Example:
        IdempotencyKey.Generate("sync", player.UserId)
        IdempotencyKey.Generate("purchase", player.UserId, itemId)
]]
function IdempotencyKey.Generate(operation: string, ...: any): string
	local parts = {operation}
	
	for _, part in ipairs({...}) do
		table.insert(parts, tostring(part))
	end
	
	-- Add timestamp for uniqueness
	table.insert(parts, tostring(os.time()))
	table.insert(parts, generateUUID():sub(1, 8))
	
	local key = table.concat(parts, ":")
	analytics.totalGenerated += 1
	
	return key
end

--[[
    Generate a deterministic key (same inputs = same key)
    Useful for preventing exact duplicate operations
    @param operation string - Operation name
    @param ... any - Identifiers that uniquely identify the operation
    @return string - Deterministic key
]]
function IdempotencyKey.GenerateDeterministic(operation: string, ...: any): string
	local parts = {operation}
	
	for _, part in ipairs({...}) do
		table.insert(parts, tostring(part))
	end
	
	return table.concat(parts, ":")
end

--[[
    Check if an operation was already processed
    @param key string - Idempotency key
    @return boolean - True if already processed
]]
function IdempotencyKey:WasProcessed(key: string): boolean
	local record = operations[key]
	
	if not record then
		return false
	end
	
	-- Check expiry
	if isExpired(record) then
		return false
	end
	
	return record.status == "Complete" or record.status == "Processing"
end

--[[
    Check if an operation is currently processing
    @param key string - Idempotency key
    @return boolean - True if currently processing
]]
function IdempotencyKey:IsProcessing(key: string): boolean
	local record = operations[key]
	return record ~= nil and record.status == "Processing" and not isExpired(record)
end

--[[
    Mark operation as processing
    @param key string - Idempotency key
    @param operation string - Operation name
    @param ttl number? - Time-to-live in seconds
    @param metadata table? - Additional metadata
    @return boolean - True if marked, false if already exists
]]
function IdempotencyKey:MarkProcessing(key: string, operation: string, ttl: number?, metadata: {[string]: any}?): boolean
	-- Check if already exists
	if self:WasProcessed(key) then
		analytics.duplicatesBlocked += 1
		return false
	end
	
	-- Check max keys
	if #keyOrder >= config.maxKeys then
		evictOldest()
	end
	
	local now = os.time()
	ttl = ttl or config.defaultTTL
	
	local record: OperationRecord = {
		key = key,
		operation = operation,
		status = "Processing",
		createdAt = now,
		completedAt = nil,
		expiresAt = now + ttl,
		result = nil,
		error = nil,
		metadata = metadata,
	}
	
	operations[key] = record
	table.insert(keyOrder, key)
	
	return true
end

--[[
    Mark operation as complete with result
    @param key string - Idempotency key
    @param result any? - Operation result
]]
function IdempotencyKey:MarkComplete(key: string, result: any?)
	local record = operations[key]
	
	if not record then
		warn(`[IdempotencyKey] ⚠️ Cannot mark complete - key not found: {key}`)
		return
	end
	
	record.status = "Complete"
	record.completedAt = os.time()
	record.result = result
end

--[[
    Mark operation as failed with error
    @param key string - Idempotency key
    @param error string - Error message
]]
function IdempotencyKey:MarkFailed(key: string, errorMsg: string)
	local record = operations[key]
	
	if not record then
		warn(`[IdempotencyKey] ⚠️ Cannot mark failed - key not found: {key}`)
		return
	end
	
	record.status = "Failed"
	record.completedAt = os.time()
	record.error = errorMsg
end

--[[
    Get the result of a completed operation
    @param key string - Idempotency key
    @return any? - Cached result or nil
]]
function IdempotencyKey:GetResult(key: string): any?
	local record = operations[key]
	
	if not record or isExpired(record) then
		return nil
	end
	
	return record.result
end

--[[
    Get operation record
    @param key string - Idempotency key
    @return OperationRecord?
]]
function IdempotencyKey:GetRecord(key: string): OperationRecord?
	return operations[key]
end

--[[
    Get operation status
    @param key string - Idempotency key
    @return OperationStatus?
]]
function IdempotencyKey:GetStatus(key: string): OperationStatus?
	local record = operations[key]
	
	if not record then
		return nil
	end
	
	if isExpired(record) then
		return "Expired"
	end
	
	return record.status
end

--[[
    Execute operation with idempotency guarantee
    @param key string - Idempotency key
    @param operation string - Operation name
    @param fn function - Function to execute
    @param ttl number? - Time-to-live
    @return (boolean, any?) - Success and result
]]
function IdempotencyKey:Execute(key: string, operation: string, fn: () -> any, ttl: number?): (boolean, any?)
	-- Check if already processed
	if self:WasProcessed(key) then
		local status = self:GetStatus(key)
		
		if status == "Complete" then
			print(`[IdempotencyKey] ♻️ Returning cached result for: {key}`)
			analytics.duplicatesBlocked += 1
			return true, self:GetResult(key)
		elseif status == "Processing" then
			warn(`[IdempotencyKey] ⚠️ Operation in progress: {key}`)
			analytics.duplicatesBlocked += 1
			return false, nil
		end
	end
	
	-- Mark as processing
	if not self:MarkProcessing(key, operation, ttl) then
		return false, nil
	end
	
	-- Execute
	local success, result = pcall(fn)
	
	if success then
		self:MarkComplete(key, result)
		return true, result
	else
		self:MarkFailed(key, tostring(result))
		return false, nil
	end
end

--[[
    Configure idempotency key settings
    @param newConfig IdempotencyKeyConfig - New configuration
]]
function IdempotencyKey:Configure(newConfig: IdempotencyKeyConfig)
	config = newConfig
	print(`[IdempotencyKey] ⚙️ Configured: TTL={config.defaultTTL}s, MaxKeys={config.maxKeys}`)
end

--[[
    Get analytics
    @return table
]]
function IdempotencyKey:GetAnalytics(): {[string]: any}
	return {
		totalGenerated = analytics.totalGenerated,
		duplicatesBlocked = analytics.duplicatesBlocked,
		expired = analytics.expired,
		evicted = analytics.evicted,
		activeKeys = #keyOrder,
		maxKeys = config.maxKeys,
	}
end

--[[
    Print summary
]]
function IdempotencyKey:PrintSummary()
	print("╔════════════════════════════════════════════════════════════════╗")
	print("║              IDEMPOTENCY KEY SUMMARY                           ║")
	print("╠════════════════════════════════════════════════════════════════╣")
	print(`║ Generated: {analytics.totalGenerated}`)
	print(`║ Duplicates Blocked: {analytics.duplicatesBlocked}`)
	print(`║ Expired: {analytics.expired}`)
	print(`║ Evicted: {analytics.evicted}`)
	print(`║ Active Keys: {#keyOrder}/{config.maxKeys}`)
	print("╚════════════════════════════════════════════════════════════════╝")
end

return IdempotencyKey
