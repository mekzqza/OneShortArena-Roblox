--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║              LOBBY GUI CONTROLLER - PRODUCTION GRADE           ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Connect UI buttons to InputController                ║
║ Features:                                                      ║
║  ✅ Button click → EventBus emission                          ║
║  ✅ Visual feedback (hover, click)                            ║
║  ✅ Cooldown visual (disable during cooldown)                 ║
╚════════════════════════════════════════════════════════════════╝
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ✅ Get shared modules
local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)

export type LobbyGuiController = {
	Init: (self: LobbyGuiController) -> (),
	Start: (self: LobbyGuiController) -> (),
}

local LobbyGuiController = {} :: LobbyGuiController

-- References
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local lobbyGui: ScreenGui? = nil
local playButton: TextButton? = nil
local cancelButton: TextButton? = nil

-- State
local buttonCooldowns = {} :: {[TextButton]: boolean}

--[[
    Helper Function: connectButton
    เชื่อมปุ่มเข้ากับระบบ EventBus พร้อมทำ Visual Feedback
]]
local function connectButton(button: TextButton, actionName: string, cooldownTime: number?)
	cooldownTime = cooldownTime or 1.0

	button.MouseButton1Click:Connect(function()
		-- 1. Check Cooldown
		if buttonCooldowns[button] then
			warn(`[LobbyGuiController] ⏱️ {actionName} on cooldown (ignored)`)
			return
		end

		print(`[LobbyGuiController] 🖼️ Button clicked: {actionName}`)

		-- 2. Activate Cooldown & Visuals
		buttonCooldowns[button] = true
		local originalText = button.Text
		
		-- Feedback: เปลี่ยนข้อความและสีชั่วคราว
		button.Text = "..." 
		-- (Optional: เปลี่ยนสีปุ่มตรงนี้ได้ถ้าต้องการ)

		-- 3. Emit Event
		EventBus:Emit(Events.INPUT_ACTION, actionName)

		-- 4. Reset after cooldown
		task.delay(cooldownTime, function()
			buttonCooldowns[button] = false
			button.Text = originalText
		end)
	end)
end

function LobbyGuiController:Init()
	print("[LobbyGuiController] 🔍 Initializing...")

	-- 1. รอ LobbyGui (สำคัญมาก ต้องใช้ WaitForChild)
	local gui = playerGui:WaitForChild("LobbyGui", 10)
	if not gui then
		warn("[LobbyGuiController] ❌ LobbyGui not found after 10s! Check StarterGui.")
		return
	end

	if not gui:IsA("ScreenGui") then
		warn(`[LobbyGuiController] ❌ LobbyGui is not a ScreenGui! (Found: {gui.ClassName})`)
		return
	end

	lobbyGui = gui :: ScreenGui
	print("[LobbyGuiController] ✅ Found LobbyGui")

	-- 2. รอ PlayButton (สำคัญ)
	local btn = lobbyGui:WaitForChild("PlayButton", 5)
	if not btn or not btn:IsA("TextButton") then
		warn("[LobbyGuiController] ❌ PlayButton not found or not a TextButton!")
		return
	end
	playButton = btn :: TextButton
	print("[LobbyGuiController] ✅ Found PlayButton")

	-- 3. หา CancelButton (Optional - อาจจะไม่มีก็ได้ ไม่ต้องรอ)
	local cancelBtn = lobbyGui:FindFirstChild("CancelButton")
	if cancelBtn and cancelBtn:IsA("TextButton") then
		cancelButton = cancelBtn :: TextButton
		print("[LobbyGuiController] ✅ Found CancelButton")
	else
		print("[LobbyGuiController] ℹ️ CancelButton not found (Optional)")
	end

	print("[LobbyGuiController] 🎨 Initialized successfully!")
end

function LobbyGuiController:Start()
	-- ตรวจสอบความพร้อมก่อนเริ่มทำงาน
	if not playButton then
		warn("[LobbyGuiController] ⚠️ Cannot start: PlayButton not initialized")
		return
	end

	print("[LobbyGuiController] 🚀 Starting logic...")

	-- เชื่อมต่อปุ่ม Play
	connectButton(playButton, "PLAY", 1.0)
	print("[LobbyGuiController] ✅ Connected PLAY action")

	-- เชื่อมต่อปุ่ม Cancel (ถ้ามี)
	if cancelButton then
		connectButton(cancelButton, "CANCEL", 0.5)
		print("[LobbyGuiController] ✅ Connected CANCEL action")
	end
end

return LobbyGuiController