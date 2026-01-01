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

local player = Players.LocalPlayer

-- ✅ NEW: Track if player is Downed
local isPlayerDowned = false

-- ✅ NEW: Helper function to check if input should be blocked
local function shouldBlockInput(): boolean
	-- Check if downed
	if isPlayerDowned then
		warn("[InputHandler] ⚠️ Input blocked: Player is Downed")
		return true
	end
	
	-- ✅ Check IsDowned attribute (backup check)
	local character = player.Character
	if character and character:GetAttribute("IsDowned") then
		warn("[InputHandler] ⚠️ Input blocked: IsDowned attribute = true")
		return true
	end
	
	return false
end

function InputHandler:Init()
	print("[InputHandler] 🧠 Initialized")
end

function InputHandler:Start()
	-- ✅ NEW: Listen for Downed state changes
	EventBus:On(Events.PLAYER_DOWNED, function(data: any)
		print("[InputHandler] 🦵 Player is now DOWNED - blocking inputs")
		isPlayerDowned = true
	end)
	
	EventBus:On(Events.PLAYER_REVIVED, function(data: any)
		print("[InputHandler] 💚 Player REVIVED - enabling inputs")
		isPlayerDowned = false
	end)
	
	EventBus:On(Events.PLAYER_DIED, function(data: any)
		print("[InputHandler] 💀 Player DIED - blocking inputs")
		isPlayerDowned = false -- Died is different from Downed
	end)
	
	EventBus:On(Events.PLAYER_STATE_CHANGED, function(data: any)
		if data.state == "Downed" then
			isPlayerDowned = true
		elseif data.state == "Arena" or data.state == "Lobby" then
			isPlayerDowned = false
		end
	end)
	
	EventBus:On(Events.INPUT_ACTION, function(actionName: string)
		-- ✅ NEW: Block all inputs if Downed
		if shouldBlockInput() then
			print(`[InputHandler] 🚫 Action blocked: {actionName} (Downed)`)
			return
		end
		
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
	-- ✅ NEW: Double-check before sending
	if shouldBlockInput() then
		warn("[InputHandler] 🚫 Play blocked: Player is Downed")
		return
	end
	
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
	-- ✅ NEW: Allow Cancel even while Downed (to give up)
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
	-- ✅ NEW: Block attack if Downed
	if shouldBlockInput() then
		warn("[InputHandler] 🚫 Attack blocked: Player is Downed")
		return
	end
	
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
