--!strict

-- NetworkController (Client)
-- Bridges RemoteEvent -> EventBus on the client and provides Send helper

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function getRemote(): RemoteEvent
	local systemsShared = ReplicatedStorage:WaitForChild("SystemsShared")
	local folder = systemsShared:WaitForChild(REMOTE_FOLDER_NAME)
	return folder:WaitForChild(REMOTE_EVENT_NAME) :: RemoteEvent
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
	-- No-op
end

function Module:Send(eventName: string, ...: any)
	remoteEvent:FireServer(eventName, ...)
end

return Module
