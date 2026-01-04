--!strict

-- NetworkController (Client)
-- Bridges RemoteEvent -> EventBus on the client and provides Send helper

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Promise = require(ReplicatedStorage.Packages.Promise)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

export type ModuleImpl = {
	Init: (self: ModuleImpl) -> (),
	Start: (self: ModuleImpl) -> (),
	Send: (self: ModuleImpl, eventName: string, ...any) -> (),
	SendReliable: (self: ModuleImpl, eventName: string, data: any, maxRetries: number?) -> (),
	[string]: any,
}

local Module: ModuleImpl = {}

local REMOTE_FOLDER_NAME = "Network"
local REMOTE_EVENT_NAME = "NetworkBridge"

local remoteEvent: RemoteEvent

-- NEW: Track sent messages for retry
local sentMessages = {} :: {{
	messageId: string,
	eventName: string,
	data: any,
	timestamp: number,
	retries: number
}}

local MAX_RETRIES = 3
local RETRY_DELAY = 2

-- ═══════════════════════════════════════════════════════════════
-- ✨ NEW: REQUEST-RESPONSE SYSTEM
-- ═══════════════════════════════════════════════════════════════

-- Track pending requests
local pendingRequests: {[string]: {
	promise: any,
	eventName: string,
	sentAt: number,
	timeoutThread: thread?,
}} = {}

-- Config
local REQUEST_TIMEOUT = 10 -- seconds
local MAX_PENDING_REQUESTS = 100

-- Analytics
local requestAnalytics = {
	totalRequests = 0,
	successfulResponses = 0,
	timedOutRequests = 0,
	failedRequests = 0,
}

local function getRemote(): RemoteEvent
	local systemsShared = ReplicatedStorage:WaitForChild("SystemsShared", 30)
	if not systemsShared then
		error("[NetworkController] SystemsShared not found in ReplicatedStorage")
	end
	
	local folder = systemsShared:WaitForChild(REMOTE_FOLDER_NAME, 30)
	if not folder then
		error(`[NetworkController] {REMOTE_FOLDER_NAME} folder not found. Server may not be initialized.`)
	end
	
	local remote = folder:WaitForChild(REMOTE_EVENT_NAME, 30)
	if not remote then
		error(`[NetworkController] {REMOTE_EVENT_NAME} RemoteEvent not found`)
	end
	
	return remote :: RemoteEvent
end

function Module:Init()
	remoteEvent = getRemote()

	-- ✅ FIX: Listen for server events
	remoteEvent.OnClientEvent:Connect(function(payload: any)
		-- Check if it's a response to a request
		if payload and type(payload) == "table" and payload._isResponse then
			self:_HandleResponse(payload)
			return
		end
		
		-- ✅ FIX: Handle regular events from server
		-- Server sends either:
		-- 1. Simple string event name: "EventName"
		-- 2. Structured payload: { _eventName = "EventName", _data = {...} }
		
		if type(payload) == "string" then
			-- Simple event with no data
			EventBus:Emit(payload)
		elseif type(payload) == "table" and payload._eventName then
			-- Structured event with data
			local eventName = payload._eventName
			local eventData = payload._data
			
			if eventData ~= nil then
				EventBus:Emit(eventName, eventData)
			else
				EventBus:Emit(eventName)
			end
		else
			warn("[NetworkController] ⚠️ Unknown payload format:", payload)
		end
	end)

	-- Announce controller readiness
	EventBus:Emit(Events.CONTROLLER_READY, "NetworkController")
end

function Module:Start()
	-- Listen for ACK
	EventBus:On("__ACK", function(data: any)
		local messageId = data.messageId
		
		for i, msg in ipairs(sentMessages) do
			if msg.messageId == messageId then
				table.remove(sentMessages, i)
				print(`[NetworkController] ACK received for {msg.eventName}`)
				break
			end
		end
	end)
	
	-- ✨ NEW: Periodic cleanup of timed-out requests
	task.spawn(function()
		while true do
			task.wait(5) -- Check every 5 seconds
			self:_CleanupTimedOutRequests()
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════
-- ✨ NEW: INVOKE (Request-Response)
-- ═══════════════════════════════════════════════════════════════

--[[]
	Invoke a server function and wait for response
	
	@param eventName string - Name of the server function to call
	@param data any? - Data to send
	@param timeout number? - Timeout in seconds (default 10s)
	@return Promise<any> - Promise that resolves with server response
	
	Example:
		NetworkController:Invoke("GetPlayerData", { userId = 123 })
			:andThen(function(data)
				print("Received:", data)
			end)
			:catch(function(err)
				warn("Error:", err)
			end)
]]
function Module:Invoke(eventName: string, data: any?, timeout: number?): any
	timeout = timeout or REQUEST_TIMEOUT
	
	-- Check limit
	local pendingCount = 0
	for _ in pairs(pendingRequests) do
		pendingCount += 1
	end
	
	if pendingCount >= MAX_PENDING_REQUESTS then
		return Promise.reject("Too many pending requests")
	end
	
	-- Generate unique request ID
	local reqId = HttpService:GenerateGUID(false)
	
	requestAnalytics.totalRequests += 1
	
	-- Create promise
	return Promise.new(function(resolve, reject)
		-- Prepare payload
		local payload = {
			_isRequest = true,
			_reqId = reqId,
			_eventName = eventName,
			_data = data,
			_sentAt = os.time(),
		}
		
		-- Store pending request
		pendingRequests[reqId] = {
			promise = {
				resolve = resolve,
				reject = reject,
			},
			eventName = eventName,
			sentAt = os.clock(),
			timeoutThread = nil,
		}
		
		-- Setup timeout
		pendingRequests[reqId].timeoutThread = task.delay(timeout, function()
			if pendingRequests[reqId] then
				requestAnalytics.timedOutRequests += 1
				reject(`Request '{eventName}' timed out after {timeout}s`)
				pendingRequests[reqId] = nil
			end
		end)
		
		-- Send to server
		remoteEvent:FireServer(payload)
		
		print(`[NetworkController] 📤 Request sent: {eventName} (reqId: {reqId:sub(1, 8)}...)`)
	end)
end

-- ═══════════════════════════════════════════════════════════════
-- ✨ NEW: HANDLE RESPONSE (Internal)
-- ═══════════════════════════════════════════════════════════════

function Module:_HandleResponse(response: any)
	local reqId = response._reqId
	
	if not reqId then
		warn("[NetworkController] ⚠️ Received response without reqId")
		return
	end
	
	local pending = pendingRequests[reqId]
	
	if not pending then
		warn(`[NetworkController] ⚠️ No pending request found for reqId: {reqId:sub(1, 8)}...`)
		return
	end
	
	-- Cancel timeout
	if pending.timeoutThread then
		task.cancel(pending.timeoutThread)
	end
	
	-- Calculate duration
	local duration = os.clock() - pending.sentAt
	
	print(`[NetworkController] 📥 Response received: {pending.eventName} ({string.format("%.3f", duration)}s)`)
	
	-- Resolve/Reject promise
	if response._success then
		requestAnalytics.successfulResponses += 1
		pending.promise.resolve(response._result)
	else
		requestAnalytics.failedRequests += 1
		pending.promise.reject(response._error or "Unknown error")
	end
	
	-- Cleanup
	pendingRequests[reqId] = nil
end

-- ═══════════════════════════════════════════════════════════════
-- ✨ NEW: CLEANUP TIMED-OUT REQUESTS
-- ═══════════════════════════════════════════════════════════════

function Module:_CleanupTimedOutRequests()
	local now = os.clock()
	local cleaned = 0
	
	for reqId, pending in pairs(pendingRequests) do
		local age = now - pending.sentAt
		
		if age > REQUEST_TIMEOUT then
			if pending.timeoutThread then
				task.cancel(pending.timeoutThread)
			end
			
			pending.promise.reject(`Request timed out (age: {string.format("%.1f", age)}s)`)
			pendingRequests[reqId] = nil
			cleaned += 1
		end
	end
	
	if cleaned > 0 then
		print(`[NetworkController] 🧹 Cleaned up {cleaned} timed-out requests`)
	end
end

-- ═══════════════════════════════════════════════════════════════
-- ✨ NEW: GET ANALYTICS
-- ═══════════════════════════════════════════════════════════════

function Module:GetAnalytics(): {[string]: any}
	local pendingCount = 0
	for _ in pairs(pendingRequests) do
		pendingCount += 1
	end
	
	return {
		totalRequests = requestAnalytics.totalRequests,
		successfulResponses = requestAnalytics.successfulResponses,
		timedOutRequests = requestAnalytics.timedOutRequests,
		failedRequests = requestAnalytics.failedRequests,
		pendingRequests = pendingCount,
		successRate = requestAnalytics.totalRequests > 0 
			and (requestAnalytics.successfulResponses / requestAnalytics.totalRequests * 100) 
			or 0,
	}
end

-- NEW: Send with automatic retry
function Module:SendReliable(eventName: string, data: any, maxRetries: number?)
	maxRetries = maxRetries or MAX_RETRIES
	
	local messageId = HttpService:GenerateGUID(false)
	data._msgId = messageId

	table.insert(sentMessages, {
		messageId = messageId,
		eventName = eventName,
		data = data,
		timestamp = tick(),
		retries = 0,
	})

	self:Send(eventName, data)

	-- Auto-retry if no ACK
	task.delay(RETRY_DELAY, function()
		self:CheckRetry(messageId, maxRetries)
	end)
end

-- NEW: Check if need retry
function Module:CheckRetry(messageId: string, maxRetries: number)
	for i, msg in ipairs(sentMessages) do
		if msg.messageId == messageId then
			if msg.retries < maxRetries then
				msg.retries += 1
				warn(`[NetworkController] Retrying {msg.eventName} (attempt {msg.retries})`)
				self:Send(msg.eventName, msg.data)
				
				task.delay(RETRY_DELAY, function()
					self:CheckRetry(messageId, maxRetries)
				end)
			else
				warn(`[NetworkController] Max retries reached for {msg.eventName}`)
				table.remove(sentMessages, i)
			end
			return
		end
	end
end

-- ✅ FIX: Send method
function Module:Send(eventName: string, ...: any)
	local args = {...}
	
	if #args == 0 then
		-- Simple event (no data)
		remoteEvent:FireServer(eventName)
	elseif #args == 1 then
		-- Event with single data payload
		remoteEvent:FireServer({
			_eventName = eventName,
			_data = args[1]
		})
	else
		-- Event with multiple args (pack into array)
		remoteEvent:FireServer({
			_eventName = eventName,
			_data = args
		})
	end
end

return Module
