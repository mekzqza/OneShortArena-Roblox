--!strict

-- NetworkHandler - Enhanced Security Version
-- Added protections against common exploits

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

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

-- Enhanced rate limiting
local DEBUG = false
local RATE_LIMIT_WINDOW = 5 -- Increased from 2
local MAX_EVENTS_PER_WINDOW = 10
local MAX_BURST_EVENTS = 3 -- New: max events in 0.5 seconds
local GLOBAL_RATE_LIMIT = 100 -- New: max events per second from all players
local MAX_STRING_LENGTH = 500
local MAX_TABLE_SIZE = 32
local MAX_DEPTH = 3

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
		addSuspiciousStrike(player, "Rate limit exceeded")
		return false, "Rate limit exceeded"
	end

	return true
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

	warn(string.format("[NetworkHandler] Suspicious activity from %s: %s (Strike %d)", 
		player.Name, reason, record.strikes))

	-- Auto-kick after too many strikes
	if record.strikes >= 5 then
		player:Kick("Suspicious network activity detected")
	end
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
	local systemsShared = ReplicatedStorage:WaitForChild("SystemsShared")
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
			remoteEvent:FireClient(first, eventName, table.unpack(args, 1, #args))
		end
	else
		local ok, args = sanitizeArgs(table.unpack(packed, 1, packed.n))
		if ok then
			log("-> FireAllClients", eventName)
			remoteEvent:FireAllClients(eventName, table.unpack(args, 1, #args))
		end
	end
end

local function handleClientEvent(player: Player, eventName: string, ...: any)
	-- Basic validation
	if typeof(eventName) ~= "string" then
		addSuspiciousStrike(player, "Invalid event name type")
		return
	end

	-- Check allowlist
	if not CLIENT_TO_SERVER_ALLOW[eventName] then
		addSuspiciousStrike(player, string.format("Blocked disallowed event '%s'", eventName))
		return
	end

	-- Check rate limit (enhanced)
	local rateLimitOk, rateLimitReason = checkRateLimit(player)
	if not rateLimitOk then
		warn(string.format("[NetworkHandler] %s: %s", player.Name, rateLimitReason))
		return
	end

	-- Check event sequence
	local sequenceOk, sequenceReason = checkEventSequence(player, eventName)
	if not sequenceOk then
		addSuspiciousStrike(player, string.format("Invalid sequence: %s", sequenceReason))
		return
	end

	-- Sanitize payload
	local ok, args = sanitizeArgs(...)
	if not ok then
		addSuspiciousStrike(player, string.format("Blocked unsafe payload for '%s'", eventName))
		return
	end

	-- Per-event validator (optional)
	local validator = validators[eventName]
	if validator then
		local passed, reason = validator(player, args)
		if not passed then
			addSuspiciousStrike(player, string.format("Validator rejected '%s': %s", eventName, tostring(reason)))
			return
		end
	end

	-- Track successful event
	trackEvent(player, eventName)

	log("<- From", player.Name, eventName)
	EventBus:Emit(eventName, player, table.unpack(args, 1, #args))
end

function NetworkHandler:Init()
	remoteEvent = ensureRemoteEvent()

	remoteEvent.OnServerEvent:Connect(function(player, eventName, ...)
		handleClientEvent(player, eventName, ...)
	end)

	for eventName in pairs(SERVER_TO_CLIENT_ALLOW) do
		EventBus:On(eventName, function(...)
			forwardToClients(eventName, ...)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		clientRate[userId] = nil
		eventSequence[userId] = nil
		suspiciousPlayers[userId] = nil
	end)
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