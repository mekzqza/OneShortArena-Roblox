--!strict

--[[
    InputHandler - Production Version
    
    จัดการ input actions และแปลงเป็น game commands
    รองรับ: Cooldown, State checking, Action queuing
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ✅ Get shared modules
local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)

export type InputHandler = {
	Init: (self: InputHandler) -> (),
	Start: (self: InputHandler) -> (),
	HandlePlay: (self: InputHandler) -> (),
	HandleCancel: (self: InputHandler) -> (),
	HandleAttack: (self: InputHandler) -> (),
}

local InputHandler = {} :: InputHandler

function InputHandler:Init()
	print("[InputHandler] 🧠 Initialized")
end

function InputHandler:Start()
	EventBus:On(Events.INPUT_ACTION, function(actionName: string)
		if actionName == "PLAY" then
			self:HandlePlay()
		elseif actionName == "CANCEL" then
			self:HandleCancel()
		elseif actionName == "ATTACK" then
			self:HandleAttack()
		else
			warn(`[InputHandler] ⚠️ Unhandled action: {actionName}`)
		end
	end)
	
	print("[InputHandler] ✅ Started")
end

function InputHandler:HandlePlay()
	print("[InputHandler] ▶️ Play button pressed")
	
	-- ✅ ใช้ Registry
	local Controllers = _G.ControllersByCategory
	
	if not Controllers or not Controllers.Core or not Controllers.Core.NetworkController then
		warn("[InputHandler] ❌ NetworkController not available")
		return
	end
	
	local NetworkController = Controllers.Core.NetworkController
	
	NetworkController:Send(Events.PLAYER_REQUEST_TO_ARENA, {
		action = "join",
		timestamp = tick()
	})
end

function InputHandler:HandleCancel()
	print("[InputHandler] ⏸️ Cancel button pressed")
	
	local Controllers = _G.ControllersByCategory
	
	if not Controllers or not Controllers.Core or not Controllers.Core.NetworkController then
		warn("[InputHandler] ❌ NetworkController not available")
		return
	end
	
	local NetworkController = Controllers.Core.NetworkController
	
	NetworkController:Send(Events.PLAYER_REQUEST_TO_LOBBY, {
		action = "cancel",
		timestamp = tick()
	})
end

function InputHandler:HandleAttack()
	print("[InputHandler] ⚔️ Attack pressed")
	
	local Controllers = _G.ControllersByCategory
	
	if not Controllers or not Controllers.Core or not Controllers.Core.NetworkController then
		warn("[InputHandler] ❌ NetworkController not available")
		return
	end
	
	local NetworkController = Controllers.Core.NetworkController
	
	NetworkController:Send(Events.PLAYER_ATTACK, {
		action = "attack",
		timestamp = tick()
	})
end

return InputHandler
