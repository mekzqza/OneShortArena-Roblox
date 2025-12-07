--!strict

-- NetworkHandler - Bridge between Client and Server using EventBus
-- Responsibilities:
-- 1) Create a single RemoteEvent bridge for client requests
-- 2) Validate + rate-limit inbound client events before emitting to EventBus
-- 3) Forward selected server events (from EventBus) to clients

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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

-- Runtime config (can be tuned via :Configure)
local DEBUG = false
local RATE_LIMIT_WINDOW = 2 -- seconds
local MAX_EVENTS_PER_WINDOW = 10 -- per player per window
local MAX_STRING_LENGTH = 500
local MAX_TABLE_SIZE = 32
local MAX_DEPTH = 3

local clientRate: {[number]: {t: number, count: number}} = {}
local remoteEvent: RemoteEvent
local validators: {[string]: (Player, {any}) -> (boolean, string?)} = {}

-- Allowlists to control what can traverse the bridge
local CLIENT_TO_SERVER_ALLOW = {
	[Events.TOGGLE_UI] = true,
	[Events.GAME_START_REQUESTED] = true,
	[Events.SETTINGS_CHANGED] = true,
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

local function isPayloadSafe(value: any, depth: number): boolean
	if depth > MAX_DEPTH then
		return false
	end

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
		local count = 0
		for k, v in pairs(value) do
			count += 1
			if count > MAX_TABLE_SIZE then
				return false
			end
			if not isPayloadSafe(k, depth + 1) or not isPayloadSafe(v, depth + 1) then
				return false
			end
		end
		return true
	else
		return true
	end
end

local function checkRateLimit(player: Player): boolean
	local now = os.clock()
	local record = clientRate[player.UserId]
	if record == nil or (now - record.t) > RATE_LIMIT_WINDOW then
		record = { t = now, count = 0 }
		clientRate[player.UserId] = record
	end

	record.count += 1
	if record.count > MAX_EVENTS_PER_WINDOW then
		warn(string.format("[NetworkHandler] Rate limit exceeded by %s", player.Name))
		return false
	end

	return true
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
		if not isPayloadSafe(packed[i], 1) then
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
	if typeof(eventName) ~= "string" then
		return
	end
	if not CLIENT_TO_SERVER_ALLOW[eventName] then
		warn(string.format("[NetworkHandler] Blocked disallowed event '%s' from %s", eventName, player.Name))
		return
	end
	if not checkRateLimit(player) then
		return
	end

	local ok, args = sanitizeArgs(...)
	if not ok then
		warn(string.format("[NetworkHandler] Blocked unsafe payload for '%s' from %s", eventName, player.Name))
		return
	end

	-- Per-event validator (optional)
	local validator = validators[eventName]
	if validator then
		local passed, reason = validator(player, args)
		if not passed then
			warn(string.format("[NetworkHandler] Validator rejected '%s' from %s: %s", eventName, player.Name, tostring(reason)))
			return
		end
	end

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
		clientRate[player.UserId] = nil
	end)
end

function NetworkHandler:Start()
	-- Optionally announce readiness to other services
	EventBus:Emit(Events.SERVICE_READY, "NetworkHandler")
end

function NetworkHandler:SendToClient(player: Player, eventName: string, ...: any)
	forwardToClients(eventName, player, ...)
end

function NetworkHandler:Broadcast(eventName: string, ...: any)
	forwardToClients(eventName, ...)
end

-- Configure runtime settings
function NetworkHandler:Configure(opts: {rateWindow: number?, maxPerWindow: number?, debug: boolean?})
	if opts.rateWindow ~= nil then RATE_LIMIT_WINDOW = opts.rateWindow end
	if opts.maxPerWindow ~= nil then MAX_EVENTS_PER_WINDOW = opts.maxPerWindow end
	if opts.debug ~= nil then DEBUG = opts.debug end
end

-- Register per-event validator for client->server events
function NetworkHandler:RegisterValidator(eventName: string, fn: (Player, {any}) -> (boolean, string?))
	if CLIENT_TO_SERVER_ALLOW[eventName] then
		validators[eventName] = fn
	else
		warn(string.format("[NetworkHandler] Cannot register validator for disallowed event '%s'", eventName))
	end
end

-- Dynamically allow additional events (use cautiously; prefer editing allowlist)
function NetworkHandler:AllowClientEvent(eventName: string)
	CLIENT_TO_SERVER_ALLOW[eventName] = true
end

function NetworkHandler:AllowServerEvent(eventName: string)
	SERVER_TO_CLIENT_ALLOW[eventName] = true
end

return NetworkHandler
