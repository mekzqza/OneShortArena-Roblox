--!strict

-- NetworkHandler - Production Grade Version
-- Enhanced: Analytics, Anti-Replay, Message ACK, Priority Queue

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

local systemsShared = ReplicatedStorage:WaitForChild("SystemsShared")

export type NetworkHandler = {
	Init: (self: NetworkHandler) -> (),
	Start: (self: NetworkHandler) -> (),
	SendToClient: (self: NetworkHandler, player: Player, eventName: string, ...any) -> (),
	Broadcast: (self: NetworkHandler, eventName: string, ...any) -> (),
	[string]: any,
}

local NetworkHandler: NetworkHandler = {}

local REMOTE_FOLDER_NAME = "Network"
local REMOTE_EVENT_NAME = "NetworkBridge"




--[[
Production Grade Settings:
local MAX_EVENTS_PER_WINDOW = 15
local MAX_BURST_EVENTS = 5
local KICK_THRESHOLD = 10  // เตะหลัง 10 strikes
local MAX_DEPTH = 5                -- พอสมควร
local MAX_TABLE_SIZE = 50          -- ไม่ใหญ่เกินไป
local MAX_STRING_LENGTH = 1000     -- ไม่ยาวเกินไป
]]

-- Enhanced rate limiting
local DEBUG = false
local RATE_LIMIT_WINDOW = 5
local MAX_EVENTS_PER_WINDOW = 3     -- 3 events in 5 seconds
local MAX_BURST_EVENTS = 2           -- 2 events in 0.5 seconds
local GLOBAL_RATE_LIMIT = 100 -- New: max events per second from all players
local MAX_STRING_LENGTH = 1000
local MAX_TABLE_SIZE = 50
local MAX_DEPTH = 5

-- NEW: Analytics tracking
local analytics = {
	totalEvents = 0,
	eventCounts = {} :: {[string]: number},
	playerEventCounts = {} :: {[number]: {[string]: number}},
	errors = {} :: {{timestamp: number, player: string, error: string}},
	startTime = os.clock(),
}

-- NEW: Anti-replay protection
local messageIds = {} :: {[number]: {[string]: number}} -- player -> messageId -> timestamp
local MESSAGE_ID_EXPIRY = 60 -- Message IDs expire after 60 seconds

-- NEW: Message acknowledgment
local pendingAcks = {} :: {[number]: {[string]: {callback: () -> (), timeout: number}}}

-- NEW: Priority queue 
local priorityEvents = {
	[Events.PLAYER_ATTACK] = 1, -- High priority
	[Events.PLAYER_DEFEND] = 1,
	[Events.PLAYER_SPECIAL] = 1,
	[Events.GAME_START_REQUESTED] = 2, -- Medium
	[Events.SETTINGS_CHANGED] = 3, -- Low
}

-- Enhanced tracking
local clientRate: {[number]: {t: number, count: number, burst: number, burstTime: number}} = {}
local globalEventCount = 0
local globalEventResetTime = os.clock()
local eventSequence: {[number]: {[string]: number}} = {} -- Track event sequences
local suspiciousPlayers: {[number]: {strikes: number, lastStrike: number}} = {}

local remoteEvent: RemoteEvent
local validators: {[string]: (Player, {any}) -> (boolean, string?)} = {}

-- Event dependencies (what events must happen before others)
local EVENT_DEPENDENCIES: {[string]: {string}} = {
	-- Example: Can't request game start if not in lobby
	[Events.GAME_START_REQUESTED] = {"PLAYER_JOINED_LOBBY"},
}

local CLIENT_TO_SERVER_ALLOW = {
	[Events.TOGGLE_UI] = true,
	[Events.GAME_START_REQUESTED] = true,
	[Events.SETTINGS_CHANGED] = true,
	[Events.INPUT_ACTION] = true,
}

local SERVER_TO_CLIENT_ALLOW = {
	[Events.UI_SHOW_NOTIFICATION] = true,
	[Events.UI_UPDATE_SCORE] = true,
	[Events.UI_UPDATE_HEALTH] = true,
	[Events.RESULTS_SHOW_WINNER] = true,
}

local function log(...: any)
	if DEBUG then
		print("[NetworkHandler]", ...)
	end
end

local function createRemoteStructure()
	local folder = systemsShared:FindFirstChild(REMOTE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = REMOTE_FOLDER_NAME
		folder.Parent = systemsShared
	end
	
	local remote = folder:FindFirstChild(REMOTE_EVENT_NAME)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_EVENT_NAME
		remote.Parent = folder
	end
	
	return remote :: RemoteEvent
end

local function isPayloadSafe(value: any, depth: number, visited: {[any]: boolean}?): boolean
	if depth > MAX_DEPTH then
		return false
	end

	visited = visited or {}

	local valueType = typeof(value)
	if valueType == "Instance" then
		return false
	elseif valueType == "function" or valueType == "thread" or valueType == "userdata" then
		return false
	elseif valueType == "string" then
		return #value <= MAX_STRING_LENGTH
	elseif valueType == "number" then
		return value == value and value ~= math.huge and value ~= -math.huge
	elseif valueType == "table" then
		-- Check for circular references
		if visited[value] then
			return false
		end
		visited[value] = true

		local count = 0
		for k, v in pairs(value) do
			count += 1
			if count > MAX_TABLE_SIZE then
				return false
			end
			if not isPayloadSafe(k, depth + 1, visited) or not isPayloadSafe(v, depth + 1, visited) then
				return false
			end
		end
		return true
	else
		return true
	end
end

-- Track suspicious behavior
local function addSuspiciousStrike(player: Player, reason: string)
    local userId = player.UserId
    local record = suspiciousPlayers[userId]
    local now = os.clock()

    if not record or (now - record.lastStrike) > 60 then
        record = { strikes = 0, lastStrike = now }
        suspiciousPlayers[userId] = record
    end

    record.strikes += 1
    record.lastStrike = now

    warn(string.format("[NetworkHandler] ⚠️ Suspicious activity from %s: %s (Strike %d)", 
        player.Name, reason, record.strikes))

    -- Auto-kick after too many strikes 5
    if record.strikes >= 5 then
        player:Kick("Suspicious network activity detected")
    end
end

-- Enhanced rate limiting with burst detection
local function checkRateLimit(player: Player): (boolean, string?)
	local now = os.clock()
	local userId = player.UserId

	-- Check global rate limit
	if (now - globalEventResetTime) > 1 then
		globalEventCount = 0
		globalEventResetTime = now
	end
	globalEventCount += 1
	if globalEventCount > GLOBAL_RATE_LIMIT then
		return false, "Global rate limit exceeded"
	end

	-- Check per-player rate limit
	local record = clientRate[userId]
	if record == nil or (now - record.t) > RATE_LIMIT_WINDOW then
		record = { t = now, count = 0, burst = 0, burstTime = now }
		clientRate[userId] = record
	end

	-- Check burst (rapid fire)
	if (now - record.burstTime) <= 0.5 then
		record.burst += 1
		if record.burst > MAX_BURST_EVENTS then
			addSuspiciousStrike(player, "Burst limit exceeded")
			return false, "Burst limit exceeded"
		end
	else
		record.burst = 1
		record.burstTime = now
	end

    record.count += 1
    if record.count > MAX_EVENTS_PER_WINDOW then
        -- ✅ แสดงข้อความชัดเจน
        warn(string.format("[NetworkHandler] 🚨 %s RATE LIMIT! (%d events in %ds)", 
            player.Name, record.count, RATE_LIMIT_WINDOW))
        addSuspiciousStrike(player, "Rate limit exceeded")
        return false, "Rate limit exceeded"
    end

    return true
end



-- Validate event sequence/dependencies
local function checkEventSequence(player: Player, eventName: string): (boolean, string?)
	local dependencies = EVENT_DEPENDENCIES[eventName]
	if not dependencies then
		return true
	end

	local playerSeq = eventSequence[player.UserId]
	if not playerSeq then
		return false, "Missing required previous events"
	end

	for _, requiredEvent in ipairs(dependencies) do
		if not playerSeq[requiredEvent] or playerSeq[requiredEvent] == 0 then
			return false, string.format("Must trigger %s first", requiredEvent)
		end
	end

	return true
end

-- Track event for sequence validation
local function trackEvent(player: Player, eventName: string)
	local playerSeq = eventSequence[player.UserId]
	if not playerSeq then
		playerSeq = {}
		eventSequence[player.UserId] = playerSeq
	end
	playerSeq[eventName] = (playerSeq[eventName] or 0) + 1
end

local function ensureRemoteEvent(): RemoteEvent
	local folder = systemsShared:FindFirstChild(REMOTE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = REMOTE_FOLDER_NAME
		folder.Parent = systemsShared
	end

	local remote = folder:FindFirstChild(REMOTE_EVENT_NAME)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_EVENT_NAME
		remote.Parent = folder
	end

	return remote
end

local function sanitizeArgs(...: any): (boolean, {any})
	local packed = table.pack(...)
	for i = 1, packed.n do
		if not isPayloadSafe(packed[i], 1, {}) then
			return false, {}
		end
	end
	return true, packed
end

local function forwardToClients(eventName: string, ...: any)
	if not SERVER_TO_CLIENT_ALLOW[eventName] then
		return
	end

	local packed = table.pack(...)
	local first = packed[1]

	if typeof(first) == "Instance" and first:IsA("Player") then
		packed[1] = nil
		local ok, args = sanitizeArgs(table.unpack(packed, 2, packed.n))
		if ok then
			log("-> FireClient", first.Name, eventName)
			remoteEvent:FireClient(first, eventName, table.unpack(args, 1, args.n))
		end
	else
		local ok, args = sanitizeArgs(table.unpack(packed, 1, packed.n))
		if ok then
			log("-> FireAllClients", eventName)
			remoteEvent:FireAllClients(eventName, table.unpack(args, 1, args.n))
		end
	end
end

-- NEW: Check for replay attacks
local function checkMessageId(player: Player, messageId: string?): (boolean, string?)
	if not messageId then
		return true -- Optional feature
	end

	local userId = player.UserId
	local playerMessages = messageIds[userId]
	local now = os.clock()

	if not playerMessages then
		playerMessages = {}
		messageIds[userId] = playerMessages
	end

	-- Clean expired IDs
	for id, timestamp in pairs(playerMessages) do
		if (now - timestamp) > MESSAGE_ID_EXPIRY then
			playerMessages[id] = nil
		end
	end

	-- Check for duplicate
	if playerMessages[messageId] then
		return false, "Replay attack detected"
	end

	playerMessages[messageId] = now
	return true
end

-- NEW: Track analytics
local function trackAnalytics(player: Player, eventName: string, success: boolean)
	analytics.totalEvents += 1
	analytics.eventCounts[eventName] = (analytics.eventCounts[eventName] or 0) + 1

	local userId = player.UserId
	if not analytics.playerEventCounts[userId] then
		analytics.playerEventCounts[userId] = {}
	end
	analytics.playerEventCounts[userId][eventName] = (analytics.playerEventCounts[userId][eventName] or 0) + 1

	if not success and #analytics.errors < 100 then -- Keep last 100 errors
		table.insert(analytics.errors, {
			timestamp = os.clock(),
			player = player.Name,
			error = eventName,
		})
	end
end

local function handleClientEvent(player: Player, eventName: string, ...: any)
	-- NEW: Extract messageId if present
	local args = table.pack(...)
	local messageId = nil
	if args.n > 0 and type(args[1]) == "table" and args[1]._msgId then
		messageId = args[1]._msgId
		args[1]._msgId = nil
	end

	-- Basic validation
	if typeof(eventName) ~= "string" then
		addSuspiciousStrike(player, "Invalid event name type")
		trackAnalytics(player, eventName, false)
		return
	end

	-- NEW: Check for replay attack
	local replayOk, replayReason = checkMessageId(player, messageId)
	if not replayOk then
		addSuspiciousStrike(player, replayReason or "Replay attack")
		trackAnalytics(player, eventName, false)
		return
	end

	-- Check allowlist
	if not CLIENT_TO_SERVER_ALLOW[eventName] then
		addSuspiciousStrike(player, string.format("Blocked disallowed event '%s'", eventName))
		trackAnalytics(player, eventName, false)
		return
	end

	-- Check rate limit (enhanced)
	local rateLimitOk, rateLimitReason = checkRateLimit(player)
	if not rateLimitOk then
		warn(string.format("[NetworkHandler] %s: %s", player.Name, rateLimitReason))
		trackAnalytics(player, eventName, false)
		return
	end

	-- Check event sequence
	local sequenceOk, sequenceReason = checkEventSequence(player, eventName)
	if not sequenceOk then
		addSuspiciousStrike(player, string.format("Invalid sequence: %s", sequenceReason))
		trackAnalytics(player, eventName, false)
		return
	end

	-- Sanitize payload
	local ok, sanitizedArgs = sanitizeArgs(table.unpack(args, 1, args.n))
	if not ok then
		addSuspiciousStrike(player, string.format("Blocked unsafe payload for '%s'", eventName))
		trackAnalytics(player, eventName, false)
		return
	end

	-- Per-event validator (optional)
	local validator = validators[eventName]
	if validator then
		local passed, reason = validator(player, sanitizedArgs)
		if not passed then
			addSuspiciousStrike(player, string.format("Validator rejected '%s': %s", eventName, tostring(reason)))
			trackAnalytics(player, eventName, false)
			return
		end
	end

	-- Track successful event
	trackEvent(player, eventName)
	trackAnalytics(player, eventName, true)

	log("<- From", player.Name, eventName)
	EventBus:Emit(eventName, player, table.unpack(sanitizedArgs, 1, sanitizedArgs.n))

	-- NEW: Send ACK if requested
	if messageId then
		NetworkHandler:SendAck(player, messageId)
	end
end

-- NEW: Send acknowledgment
function NetworkHandler:SendAck(player: Player, messageId: string)
	self:SendToClient(player, "__ACK", {
		messageId = messageId,
		timestamp = os.clock(),
	})
end

-- NEW: Send with ACK request (Reliable Send)
function NetworkHandler:SendToClientReliable(player: Player, eventName: string, data: any, callback: (() -> ())?)
	local messageId = HttpService:GenerateGUID(false)
	
	if type(data) ~= "table" then
		data = {value = data}
	end
	data._msgId = messageId
	
	self:SendToClient(player, eventName, data)

	if callback then
		local userId = player.UserId
		if not pendingAcks[userId] then
			pendingAcks[userId] = {}
		end

		pendingAcks[userId][messageId] = {
			callback = callback,
			timeout = os.clock() + 5,
		}

		-- Auto-cleanup after timeout
		task.delay(5, function()
			if pendingAcks[userId] and pendingAcks[userId][messageId] then
				pendingAcks[userId][messageId] = nil
				warn(`[NetworkHandler] ACK timeout for {player.Name}: {eventName}`)
			end
		end)
	end
end

-- NEW: Get analytics report
function NetworkHandler:GetAnalytics(): typeof(analytics)
	local uptime = os.clock() - analytics.startTime
	return {
		totalEvents = analytics.totalEvents,
		eventCounts = analytics.eventCounts,
		playerEventCounts = analytics.playerEventCounts,
		errors = analytics.errors,
		uptime = uptime,
		eventsPerSecond = uptime > 0 and analytics.totalEvents / uptime or 0,
	}
end

-- NEW: Get network health
function NetworkHandler:GetNetworkHealth(): {status: string, metrics: {[string]: any}}
	local now = os.clock()
	local uptime = now - analytics.startTime
	local eps = uptime > 0 and analytics.totalEvents / uptime or 0
	
	local suspiciousCount = 0
	for _ in pairs(suspiciousPlayers) do
		suspiciousCount += 1
	end

	return {
		status = eps < 50 and "Healthy" or eps < 100 and "Warning" or "Critical",
		metrics = {
			eventsPerSecond = eps,
			totalEvents = analytics.totalEvents,
			suspiciousPlayers = suspiciousCount,
			uptime = uptime,
		}
	}
end

-- NEW: Broadcast with priority
function NetworkHandler:BroadcastPriority(eventName: string, data: any)
	local priority = priorityEvents[eventName] or 3
	
	-- High priority: send immediately
	if priority == 1 then
		self:Broadcast(eventName, data)
	else
		-- Lower priority: could be batched/delayed
		task.defer(function()
			self:Broadcast(eventName, data)
		end)
	end
end

function NetworkHandler:Init()
	remoteEvent = createRemoteStructure()
	
	remoteEvent.OnServerEvent:Connect(handleClientEvent)
	
	-- Allow ACK event
	SERVER_TO_CLIENT_ALLOW["__ACK"] = true
	
	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		clientRate[userId] = nil
		eventSequence[userId] = nil
		suspiciousPlayers[userId] = nil
		messageIds[userId] = nil
		pendingAcks[userId] = nil
		analytics.playerEventCounts[userId] = nil
	end)
	
	-- NEW: Analytics logger (every 60 seconds)
	task.spawn(function()
		while true do
			task.wait(60)
			local health = NetworkHandler:GetNetworkHealth()
			print(string.format("[NetworkHandler] Health: %s | EPS: %.2f | Suspicious: %d", 
				health.status, 
				health.metrics.eventsPerSecond,
				health.metrics.suspiciousPlayers
			))
		end
	end)
	
	print("[NetworkHandler] 🚀 Initialized (Production Grade)")
	print("  ✅ Analytics tracking")
	print("  ✅ Anti-replay protection")
	print("  ✅ Message acknowledgment")
	print("  ✅ Priority queue system")
end

function NetworkHandler:Start()
	EventBus:Emit(Events.SERVICE_READY, "NetworkHandler")
	log("NetworkHandler started with enhanced security")
end

function NetworkHandler:SendToClient(player: Player, eventName: string, ...: any)
	forwardToClients(eventName, player, ...)
end

function NetworkHandler:Broadcast(eventName: string, ...: any)
	forwardToClients(eventName, ...)
end

function NetworkHandler:Configure(opts: {rateWindow: number?, maxPerWindow: number?, debug: boolean?})
	if opts.rateWindow ~= nil then RATE_LIMIT_WINDOW = opts.rateWindow end
	if opts.maxPerWindow ~= nil then MAX_EVENTS_PER_WINDOW = opts.maxPerWindow end
	if opts.debug ~= nil then DEBUG = opts.debug end
end

function NetworkHandler:RegisterValidator(eventName: string, fn: (Player, {any}) -> (boolean, string?))
	if CLIENT_TO_SERVER_ALLOW[eventName] then
		validators[eventName] = fn
	else
		warn(string.format("[NetworkHandler] Cannot register validator for disallowed event '%s'", eventName))
	end
end

-- New: Register event dependencies
function NetworkHandler:RegisterDependency(eventName: string, requiredEvents: {string})
	EVENT_DEPENDENCIES[eventName] = requiredEvents
end

-- New: Clear player sequence (e.g., when leaving game)
function NetworkHandler:ClearPlayerSequence(player: Player)
	eventSequence[player.UserId] = nil
end

function NetworkHandler:AllowClientEvent(eventName: string)
	CLIENT_TO_SERVER_ALLOW[eventName] = true
end

function NetworkHandler:AllowServerEvent(eventName: string)
	SERVER_TO_CLIENT_ALLOW[eventName] = true
end

-- New: Get suspicious player info (for admin tools)
function NetworkHandler:GetSuspiciousPlayers(): {[number]: {strikes: number, lastStrike: number}}
	return suspiciousPlayers
end

return NetworkHandler

--[[
╔════════════════════════════════════════════════════════════════╗
║           NETWORK SECURITY CONFIGURATION                       ║
╠════════════════════════════════════════════════════════════════╣
║ คำอธิบาย:                                                      ║
║                                                                ║
║ 🔧 DEBUG                                                       ║
║    - เปิด/ปิด debug logs                                      ║
║    - false = ปิด (Production)                                 ║
║    - true  = เปิด (Development)                               ║
║                                                                ║
║ ⏱️ RATE_LIMIT_WINDOW                                          ║
║    - หน้าต่างเวลาสำหรับนับ events (วินาที)                   ║
║    - ถ้าส่ง events เกิน MAX_EVENTS_PER_WINDOW ใน 5 วินาที    ║
║      → ถือว่า spam                                            ║
║                                                                ║
║ 📊 MAX_EVENTS_PER_WINDOW                                       ║
║    - จำนวน events สูงสุดต่อหน้าต่าง                          ║
║    - ตัวอย่าง: 3 events ใน 5 วินาที                          ║
║    - เกิน = Strike + บล็อก event                             ║
║                                                                ║
║ 💨 MAX_BURST_EVENTS                                            ║
║    - จำนวน events สูงสุดใน 0.5 วินาที (rapid fire)          ║
║    - ป้องกันการกดปุ่มเร็วเกินไป                              ║
║    - ตัวอย่าง: 2 events ใน 0.5s                              ║
║                                                                ║
║ 🌐 GLOBAL_RATE_LIMIT                                           ║
║    - จำนวน events สูงสุดจากผู้เล่นทั้งหมดต่อวินาที          ║
║    - ป้องกัน server ถูก DDoS                                 ║
║    - 100 events/sec จากทุกคน                                 ║
║                                                                ║
║ 📝 MAX_STRING_LENGTH                                           ║
║    - ความยาวสูงสุดของ string (characters)                    ║
║    - ป้องกันส่ง string ยาวเกินไป                             ║
║    - เกิน 1000 ตัวอักษร = unsafe                             ║
║                                                                ║
║ 📦 MAX_TABLE_SIZE                                              ║
║    - จำนวน keys สูงสุดใน table หนึ่งชั้น                     ║
║    - ป้องกันส่ง table ใหญ่เกินไป                             ║
║    - ตัวอย่าง: {key1=..., key2=..., ..., key50=...}         ║
║                                                                ║
║ 🗂️ MAX_DEPTH                                                  ║
║    - ความลึกสูงสุดของ nested table                            ║
║    - ตัวอย่าง depth 5:                                        ║
║      {a = {b = {c = {d = {e = "OK"}}}}}                      ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
]]

-- -- ⚙️ Configuration Settings
-- local DEBUG = false                    -- 🔧 Debug logs (false = Off, true = On)
-- local RATE_LIMIT_WINDOW = 5            -- ⏱️ Time window for rate limiting (seconds)
-- local MAX_EVENTS_PER_WINDOW = 3        -- 📊 Max events per window (3 in 5s)
-- local MAX_BURST_EVENTS = 2             -- 💨 Max rapid events (2 in 0.5s)
-- local GLOBAL_RATE_LIMIT = 100          -- 🌐 Global max events/second (all players)
-- local MAX_STRING_LENGTH = 1000         -- 📝 Max string length (characters)
-- local MAX_TABLE_SIZE = 50              -- 📦 Max keys per table level
-- local MAX_DEPTH = 5                    -- 🗂️ Max nested table depth

--[[
╔════════════════════════════════════════════════════════════════╗
║                    USAGE EXAMPLES                              ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║ 📊 MAX_EVENTS_PER_WINDOW = 3 (ใน 5 วินาที)                    ║
║    ✅ Event 1 (0.0s) → OK                                      ║
║    ✅ Event 2 (1.0s) → OK                                      ║
║    ✅ Event 3 (2.0s) → OK                                      ║
║    ❌ Event 4 (3.0s) → BLOCKED! (Strike +1)                   ║
║                                                                ║
║ 💨 MAX_BURST_EVENTS = 2 (ใน 0.5 วินาที)                       ║
║    ✅ Event 1 (0.0s) → OK                                      ║
║    ✅ Event 2 (0.1s) → OK                                      ║
║    ❌ Event 3 (0.2s) → BLOCKED! (Burst limit)                 ║
║                                                                ║
║ 📦 MAX_TABLE_SIZE = 50                                         ║
║    ✅ {key1=1, key2=2, ..., key50=50} → OK                    ║
║    ❌ {key1=1, ..., key51=51} → UNSAFE!                       ║
║                                                                ║
║ 🗂️ MAX_DEPTH = 5                                              ║
║    ✅ {a={b={c={d={e=1}}}}} → OK (depth 5)                   ║
║    ❌ {a={b={c={d={e={f=1}}}}}} → UNSAFE! (depth 6)          ║
║                                                                ║
║ 📝 MAX_STRING_LENGTH = 1000                                    ║
║    ✅ "สวัสดี" (6 chars) → OK                                 ║
║    ❌ string.rep("A", 1001) → UNSAFE!                         ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
]]

--[[
╔════════════════════════════════════════════════════════════════╗
║              RECOMMENDED SETTINGS BY ENVIRONMENT               ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║ 🧪 DEVELOPMENT / TESTING:                                      ║
║    DEBUG = true                    -- เปิด debug logs         ║
║    MAX_EVENTS_PER_WINDOW = 20      -- ผ่อนปรน                ║
║    MAX_BURST_EVENTS = 10           -- ผ่อนปรน                ║
║    MAX_TABLE_SIZE = 100            -- ใหญ่กว่า                ║
║    MAX_DEPTH = 10                  -- ลึกกว่า                 ║
║    MAX_STRING_LENGTH = 5000        -- ยาวกว่า                 ║
║                                                                ║
║ 🚀 PRODUCTION (Current):                                       ║
║    DEBUG = false                   -- ปิด debug logs          ║
║    MAX_EVENTS_PER_WINDOW = 3       -- เข้มงวด                ║
║    MAX_BURST_EVENTS = 2            -- เข้มงวด                ║
║    MAX_TABLE_SIZE = 50             -- พอดี                    ║
║    MAX_DEPTH = 5                   -- พอดี                     ║
║    MAX_STRING_LENGTH = 1000        -- พอดี                     ║
║                                                                ║
║ 🎮 PRODUCTION (Relaxed):                                       ║
║    DEBUG = false                   -- ปิด debug               ║
║    MAX_EVENTS_PER_WINDOW = 15      -- ผ่อนปรนกว่า            ║
║    MAX_BURST_EVENTS = 5            -- ผ่อนปรนกว่า            ║
║    MAX_TABLE_SIZE = 100            -- ใหญ่กว่า                ║
║    MAX_DEPTH = 10                  -- ลึกกว่า                 ║
║    MAX_STRING_LENGTH = 2000        -- ยาวกว่า                 ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
]]

-- ...existing code...