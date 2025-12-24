--!strict

-- NetworkController (Client)
-- Bridges RemoteEvent -> EventBus on the client and provides Send helper

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

export type ModuleImpl = {
	Init: (self: ModuleImpl) -> (),
	Start: (self: ModuleImpl) -> (),
	Send: (self: ModuleImpl, eventName: string, ...any) -> (),
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

	remoteEvent.OnClientEvent:Connect(function(eventName: string, ...)
		-- Only forward known events from server
		-- Client trusts allowlist server-side; here we just forward to EventBus
		EventBus:Emit(eventName, ...)
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
	
	-- Connection health monitoring
	task.spawn(function()
		while true do
			task.wait(10)
			local ping = self:GetPing()
			if ping > 500 then
				warn(`[NetworkController] High latency detected: {ping}ms`)
			end
		end
	end)
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

-- NEW: Get network stats
function Module:GetStats(): {ping: number, pendingMessages: number}
	return {
		ping = self:GetPing(),
		pendingMessages = #sentMessages,
	}
end

function Module:Start()
	-- No-op
end

function Module:Send(eventName: string, ...: any)
	remoteEvent:FireServer(eventName, ...)
end

return Module
