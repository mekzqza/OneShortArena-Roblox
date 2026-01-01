--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║           POCKETBASE SERVICE - PRODUCTION GRADE                ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Sync player data to external PocketBase VPS          ║
║ Features:                                                      ║
║  ✅ HTTPS connection to VPS                                   ║
║  ✅ Auto-authentication with token refresh                    ║
║  ✅ Hybrid sync with PlayerDataService                        ║
║  ✅ Retry logic with exponential backoff                      ║
║  ✅ Queue system for offline handling                         ║
║  ✅ Analytics integration                                     ║
╚════════════════════════════════════════════════════════════════╝

-- Note: Requires ServerStorage/Secrets/PocketBaseSecret.luau
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)
local DataMapper = require(ServerScriptService.Utils.DataMapper)
local IdempotencyKey = require(ServerScriptService.Utils.IdempotencyKey)
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type SyncStatus = "Pending" | "Syncing" | "Success" | "Failed" | "Offline"

export type SyncRecord = {
	userId: number,
	data: {[string]: any},
	timestamp: number,
	attempts: number,
	status: SyncStatus,
	lastError: string?,
}

export type PocketBaseService = {
	Init: (self: PocketBaseService) -> (),
	Start: (self: PocketBaseService) -> (),
    -- Sync methods
	SyncPlayer: (self: PocketBaseService, userId: number, data: {[string]: any}) -> (),
	SyncPlayerAsync: (self: PocketBaseService, userId: number, data: {[string]: any}) -> boolean,
	FetchPlayer: (self: PocketBaseService, userId: number) -> {[string]: any}?,
	-- Batch operations
	SyncAll: (self: PocketBaseService) -> (),
	ProcessQueue: (self: PocketBaseService) -> (),
	-- Status
	IsOnline: (self: PocketBaseService) -> boolean,
	GetSyncStatus: (self: PocketBaseService, userId: number) -> SyncStatus?,
	GetAnalytics: (self: PocketBaseService) -> {[string]: any},
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local PocketBaseService = {} :: PocketBaseService

local guard = IdempotentGuard.new("PocketBaseService", true)

-- ✅ Load secret config (not committed to git!)
local SECRET_CONFIG: {
	URL: string,
	COLLECTION: string,
	ADMIN_EMAIL: string,
	ADMIN_PASS: string,
}? = nil

local function loadSecretConfig()
	local success = pcall(function()
		local Secrets = ServerStorage:FindFirstChild("Secrets")
		if Secrets then
			local SecretModule = Secrets:FindFirstChild("PocketBaseSecret")
			if SecretModule then
				SECRET_CONFIG = require(SecretModule)
			end
		end
	end)
	
	return success and SECRET_CONFIG ~= nil
end

-- Default config (used when secrets not available)
local DEFAULT_CONFIG = {
	URL = "https://example.com",
	COLLECTION = "player_stats",
	ADMIN_EMAIL = "admin@example.com",
	ADMIN_PASS = "password",
}

-- Runtime config
local CONFIG = {
	-- Sync settings
	SyncOnLeave = true,
	SyncOnChange = true,
	SyncDebounce = 5,           -- 5 seconds between syncs per player
	
	-- Retry settings
	MaxRetries = 3,
	RetryDelayBase = 2,         -- 2^attempt seconds
	
	-- Queue settings
	QueueProcessInterval = 30,  -- Process queue every 30s
	MaxQueueSize = 100,
	
	-- Auth settings
	TokenRefreshInterval = 3600, -- 1 hour
}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local authToken: string? = nil
local tokenExpiry: number = 0
local isOnline: boolean = false
local lastSyncTime: {[number]: number} = {} -- userId -> timestamp

-- Sync queue for offline/failed syncs
local syncQueue: {SyncRecord} = {}

-- Analytics
local analytics = {
	totalSyncs = 0,
	successfulSyncs = 0,
	failedSyncs = 0,
	retries = 0,
	queuedSyncs = 0,
	authFailures = 0,
	startTime = os.clock(),
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function getConfig(): {URL: string, COLLECTION: string, ADMIN_EMAIL: string, ADMIN_PASS: string}
	return SECRET_CONFIG or DEFAULT_CONFIG
end

-- ✅ Authenticate with PocketBase
local function authenticate(): boolean
	local config = getConfig()
	
	if not SECRET_CONFIG then
		warn("[PocketBaseService] ⚠️ No secret config - using dummy (will fail)")
		return false
	end
	
	-- Check if token still valid
	if authToken and os.time() < tokenExpiry then
		return true
	end
	
	print("[PocketBaseService] 🔐 Authenticating...")
	
	-- ✅ เรียงตาม priority (ลองใหม่ก่อน)
	local authEndpoints = {
		"/api/collections/_superusers/auth-with-password", -- ✅ PocketBase v0.23+ (ลองอันนี้ก่อน!)
		"/api/admins/auth-with-password",                   -- PocketBase v0.8-v0.22
		"/api/collections/users/auth-with-password",        -- Alternative
	}
	
	for _, endpoint in ipairs(authEndpoints) do
		print(`[PocketBaseService] 🔍 Trying endpoint: {endpoint}`)
		
		local success, response = pcall(function()
			return HttpService:RequestAsync({
				Url = config.URL .. endpoint,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode({
					identity = config.ADMIN_EMAIL,
					password = config.ADMIN_PASS
				})
			})
		end)
		
		if success and response.StatusCode == 200 then
			local data = HttpService:JSONDecode(response.Body)
			authToken = data.token
			tokenExpiry = os.time() + CONFIG.TokenRefreshInterval
			isOnline = true
			
			print(`[PocketBaseService] ✅ Authenticated via {endpoint}`)
			print(`[PocketBaseService] 🔑 Token: {authToken:sub(1, 20)}...`)
			return true
		elseif success then
			warn(`[PocketBaseService] ⚠️ Endpoint {endpoint} returned {response.StatusCode}`)
			if response.Body then
				warn(`[PocketBaseService] 📄 Response: {response.Body}`)
			end
		else
			warn(`[PocketBaseService] ❌ Request failed: {response}`)
		end
	end
	
	analytics.authFailures += 1
	isOnline = false
	
	error("[PocketBaseService] ❌ All auth endpoints failed! Check VPS logs.")
	return false
end

-- ✅ Find existing record by roblox_id
local function findRecord(userId: number): string?
	local config = getConfig()
	
	if not authToken then
		return nil
	end
	
	local searchUrl = `{config.URL}/api/collections/{config.COLLECTION}/records?filter=(roblox_id='{userId}')`
	
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = searchUrl,
			Method = "GET",
			Headers = { ["Authorization"] = authToken }
		})
	end)
	
	if success and response.StatusCode == 200 then
		local result = HttpService:JSONDecode(response.Body)
		if result.items and #result.items > 0 then
			return result.items[1].id
		end
	end
	
	return nil
end

-- ✅ Perform actual sync to PocketBase
local function performSync(userId: number, data: {[string]: any}): (boolean, string?)
	if not authenticate() then
		return false, "Authentication failed"
	end
	
	local config = getConfig()
	
	-- Find existing record
	local recordId = findRecord(userId)
	
	-- Prepare payload
	local payload = {
		roblox_id = tostring(userId),
		-- Core stats
		coins = data.Coins or 0,
		gems = data.Gems or 0,
		level = data.Level or 1,
		experience = data.Experience or 0,
		-- Combat stats
		kills = data.Kills or 0,
		deaths = data.Deaths or 0,
		wins = data.Wins or 0,
		losses = data.Losses or 0,
		-- Metadata
		last_sync = os.time(),
		data_version = data._version or 1,
	}
	
	-- Determine method and URL
	local method = recordId and "PATCH" or "POST"
	local url = `{config.URL}/api/collections/{config.COLLECTION}/records`
	if recordId then
		url = `{url}/{recordId}`
	end
	
	-- Send request
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = method,
			Headers = {
				["Content-Type"] = "application/json",
				["Authorization"] = authToken
			},
			Body = HttpService:JSONEncode(payload)
		})
	end)
	
	if success and (response.StatusCode == 200 or response.StatusCode == 201) then
		return true, nil
	else
		local errorMsg = response and `Status {response.StatusCode}` or "Network error"
		return false, errorMsg
	end
end

-- ✅ Add to sync queue
local function queueSync(userId: number, data: {[string]: any})
	-- Check queue size
	if #syncQueue >= CONFIG.MaxQueueSize then
		warn("[PocketBaseService] ⚠️ Queue full, dropping oldest entry")
		table.remove(syncQueue, 1)
	end
	
	-- Check if already in queue
	for _, record in ipairs(syncQueue) do
		if record.userId == userId then
			-- Update existing
			record.data = data
			record.timestamp = os.time()
			return
		end
	end
	
	-- Add new
	local record: SyncRecord = {
		userId = userId,
		data = data,
		timestamp = os.time(),
		attempts = 0,
		status = "Pending",
		lastError = nil,
	}
	
	table.insert(syncQueue, record)
	analytics.queuedSyncs += 1
	
	print(`[PocketBaseService] 📥 Queued sync for user {userId}`)
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function PocketBaseService:Init()
	if not guard:MarkInitialized() then
		return
	end
	
	-- Load secret config
	local hasSecrets = loadSecretConfig()
	
	if hasSecrets then
		print("[PocketBaseService] 🔐 Secret config loaded")
		print(`  ✅ URL: {SECRET_CONFIG and SECRET_CONFIG.URL or "N/A"}`)
		print(`  ✅ Collection: {SECRET_CONFIG and SECRET_CONFIG.COLLECTION or "N/A"}`)
	else
		warn("[PocketBaseService] ⚠️ No secret config found!")
		warn("[PocketBaseService] ⚠️ Sync to VPS will NOT work!")
		warn("[PocketBaseService] 📝 Create: ServerStorage/Secrets/PocketBaseSecret.luau")
	end
	
	print("[PocketBaseService] 🚀 Initialized")
end

function PocketBaseService:Start()
	if not guard:MarkStarted() then
		return
	end
	
	-- ❌ REMOVE THIS LINE - Already registered in Init.server.luau
	-- ServiceLocator:Register("PocketBaseService", self)
	
	-- Initial auth attempt
	task.spawn(function()
		authenticate()
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- LISTEN FOR PLAYER DATA EVENTS
	-- ═══════════════════════════════════════════════════════════
	
	-- Sync when player data is loaded
	EventBus:On(Events.PLAYER_DATA_LOADED, function(player: Player, eventData: any)
		if not CONFIG.SyncOnChange then return end
		
		print(`[PocketBaseService] 📊 Player data loaded for {player.Name}`)
		-- Optional: Fetch from VPS to compare versions
	end)
	
	-- Sync when player data changes
	EventBus:On(Events.PLAYER_DATA_CHANGED, function(player: Player, eventData: any)
		if not CONFIG.SyncOnChange then return end
		
		local userId = player.UserId
		local now = os.time()
		
		-- Debounce
		if lastSyncTime[userId] and (now - lastSyncTime[userId]) < CONFIG.SyncDebounce then
			return
		end
		
		-- Get full data from PlayerDataService
		local PlayerDataService = require(ServerScriptService.Services.Data.PlayerDataService)
		local data = PlayerDataService:GetAll(player)
		
		if data then
			self:SyncPlayer(userId, data)
		end
	end)
	
	-- Sync when player leaves
	Players.PlayerRemoving:Connect(function(player: Player)
		if not CONFIG.SyncOnLeave then return end
		
		local userId = player.UserId
		
		-- Get data from PlayerDataService
		local PlayerDataService = require(ServerScriptService.Services.Data.PlayerDataService)
		local data = PlayerDataService:GetAll(player)
		
		if data then
			-- Sync synchronously on leave (important!)
			local success = self:SyncPlayerAsync(userId, data)
			
			if success then
				print(`[PocketBaseService] ✅ Final sync for {player.Name}`)
			else
				print(`[PocketBaseService] ⚠️ Final sync failed for {player.Name} (queued)`)
			end
		end
		
		-- Cleanup
		lastSyncTime[userId] = nil
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- QUEUE PROCESSOR
	-- ═══════════════════════════════════════════════════════════
	
	task.spawn(function()
		while true do
			task.wait(CONFIG.QueueProcessInterval)
			self:ProcessQueue()
		end
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- ANALYTICS REPORTER
	-- ═══════════════════════════════════════════════════════════
	
	task.spawn(function()
		while true do
			task.wait(600) -- Every 10 minutes
			local stats = self:GetAnalytics()
			print("[PocketBaseService] 📊 Analytics:")
			print(`  Total: {stats.totalSyncs} | Success: {stats.successfulSyncs} | Failed: {stats.failedSyncs}`)
			print(`  Queue: {stats.queueSize} | Online: {stats.isOnline}`)
		end
	end)
	
	print("[PocketBaseService] 🚀 Started")
end

-- ═══════════════════════════════════════════════════════════════
-- SYNC METHODS (UPDATED with DataMapper & IdempotencyKey)
-- ═══════════════════════════════════════════════════════════════

-- ✅ Sync with idempotency guarantee
function PocketBaseService:SyncPlayerAsync(userId: number, data: {[string]: any}): boolean
	-- Generate deterministic key for this sync operation
	local idempotencyKey = IdempotencyKey.GenerateDeterministic("sync", userId, os.time() // 5) -- 5 second window
	
	-- Execute with idempotency
	local success, result = IdempotencyKey:Execute(idempotencyKey, "PlayerSync", function()
		analytics.totalSyncs += 1
		lastSyncTime[userId] = os.time()
		
		-- ✅ Use DataMapper for explicit field mapping
		local remoteData = DataMapper.ToRemote("PlayerData", data, userId)
		
		-- Try sync with retries
		for attempt = 1, CONFIG.MaxRetries do
			local syncSuccess, err = performSync(userId, remoteData)
			
			if syncSuccess then
				analytics.successfulSyncs += 1
				print(`[PocketBaseService] 💾 Synced user {userId}`)
				return true
			end
			
			analytics.retries += 1
			
			if attempt < CONFIG.MaxRetries then
				local delay = CONFIG.RetryDelayBase ^ attempt
				task.wait(delay)
			else
				analytics.failedSyncs += 1
				queueSync(userId, data)
				return false
			end
		end
		
		return false
	end, 300) -- 5 minute TTL
	
	return success and result == true
end

-- ✅ Fetch with DataMapper conversion
function PocketBaseService:FetchPlayer(userId: number): {[string]: any}?
	if not authenticate() then
		return nil
	end
	
	local config = getConfig()
	local searchUrl = `{config.URL}/api/collections/{config.COLLECTION}/records?filter=(roblox_id='{userId}')`
	
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = searchUrl,
			Method = "GET",
			Headers = { ["Authorization"] = authToken }
		})
	end)
	
	if success and response.StatusCode == 200 then
		local result = HttpService:JSONDecode(response.Body)
		if result.items and #result.items > 0 then
			-- ✅ Convert from remote format to Roblox format
			return DataMapper.FromRemote("PlayerData", result.items[1])
		end
	end
	
	return nil
end

-- ═══════════════════════════════════════════════════════════════
-- BATCH OPERATIONS
-- ═══════════════════════════════════════════════════════════════

function PocketBaseService:SyncAll()
	local PlayerDataService = require(ServerScriptService.Services.Data.PlayerDataService)
	
	for _, player in ipairs(Players:GetPlayers()) do
		local data = PlayerDataService:GetAll(player)
		if data then
			self:SyncPlayer(player.UserId, data)
		end
	end
end

function PocketBaseService:ProcessQueue()
	if #syncQueue == 0 then
		return
	end
	
	print(`[PocketBaseService] 🔄 Processing queue ({#syncQueue} items)...`)
	
	local processed = 0
	local remaining: {SyncRecord} = {}
	
	for _, record in ipairs(syncQueue) do
		if record.attempts >= CONFIG.MaxRetries then
			-- Give up
			warn(`[PocketBaseService] ❌ Dropping sync for user {record.userId} (max retries)`)
			continue
		end
		
		record.attempts += 1
		record.status = "Syncing"
		
		local success, err = performSync(record.userId, record.data)
		
		if success then
			record.status = "Success"
			processed += 1
		else
			record.status = "Failed"
			record.lastError = err
			table.insert(remaining, record)
		end
	end
	
	syncQueue = remaining
	
	print(`[PocketBaseService] ✅ Processed {processed}, remaining {#remaining}`)
end

-- ═══════════════════════════════════════════════════════════════
-- STATUS METHODS
-- ═══════════════════════════════════════════════════════════════

function PocketBaseService:IsOnline(): boolean
	return isOnline
end

function PocketBaseService:GetSyncStatus(userId: number): SyncStatus?
	for _, record in ipairs(syncQueue) do
		if record.userId == userId then
			return record.status
		end
	end
	return nil
end

function PocketBaseService:GetAnalytics(): {[string]: any}
	return {
		totalSyncs = analytics.totalSyncs,
		successfulSyncs = analytics.successfulSyncs,
		failedSyncs = analytics.failedSyncs,
		retries = analytics.retries,
		queueSize = #syncQueue,
		authFailures = analytics.authFailures,
		isOnline = isOnline,
		hasSecrets = SECRET_CONFIG ~= nil,
		uptime = os.clock() - analytics.startTime,
	}
end

return PocketBaseService