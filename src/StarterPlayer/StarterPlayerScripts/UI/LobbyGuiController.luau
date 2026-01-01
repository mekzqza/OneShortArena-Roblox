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

local buttonCooldowns = {} :: {[TextButton]: boolean}

-- ✅ NEW: Track if player is Downed
local isPlayerDowned = false

-- ✅ NEW: Dependencies storage
local Dependencies: {
	NetworkController: any?,
	PlayerStateController: any?,
} = {}

local function connectButton(button: TextButton, actionName: string, cooldownTime: number?)
	cooldownTime = cooldownTime or 1.0
	
	button.MouseButton1Click:Connect(function()
		-- ✅ NEW: Check if Downed
		if isPlayerDowned and actionName ~= "CANCEL" then
			warn(`[LobbyGuiController] 🚫 {actionName} blocked: Player is Downed`)
			
			-- Visual feedback
			local originalColor = button.BackgroundColor3
			button.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
			task.delay(0.3, function()
				button.BackgroundColor3 = originalColor
			end)
			
			return
		end
		
		if buttonCooldowns[button] then
			warn(`[LobbyGuiController] ⏱️ {actionName} on cooldown (ignored)`)
			return
		end
		
		print(`[LobbyGuiController] 🖼️ Button clicked: {actionName}`)
		
		buttonCooldowns[button] = true
		
		EventBus:Emit(Events.INPUT_ACTION, actionName)
		
		local originalColor = button.BackgroundColor3
		local originalText = button.Text
		button.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		button.Text = "..."
		
		task.delay(cooldownTime, function()
			buttonCooldowns[button] = false
			button.BackgroundColor3 = originalColor
			button.Text = originalText
		end)
	end)
end

-- ✅ NEW: SetDependencies (called by Init.client before Init)
function LobbyGuiController:SetDependencies(locator: any)
	-- Safe dependency resolution
	Dependencies.NetworkController = locator:Get("NetworkController")
	Dependencies.PlayerStateController = locator:Get("PlayerStateController")
	
	-- Validate critical dependencies
	if not Dependencies.NetworkController then
		warn("[LobbyGuiController] ⚠️ NetworkController not found!")
	end
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

	-- Now you can use dependencies safely
	if Dependencies.NetworkController then
		print("[LobbyGuiController] ✅ NetworkController available")
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
	
	-- ✅ NEW: Listen for Downed state
	EventBus:On(Events.PLAYER_DOWNED, function(data: any)
		print("[LobbyGuiController] 🦵 Player is DOWNED - disabling Play button")
		isPlayerDowned = true
		
		if playButton then
			playButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
			playButton.Text = "❌ Downed"
		end
	end)
	
	EventBus:On(Events.PLAYER_REVIVED, function(data: any)
		print("[LobbyGuiController] 💚 Player REVIVED - enabling Play button")
		isPlayerDowned = false
		
		if playButton then
			playButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
			playButton.Text = "▶ Play"
		end
	end)
	
	EventBus:On(Events.PLAYER_DIED, function(data: any)
		print("[LobbyGuiController] 💀 Player DIED - disabling Play button")
		isPlayerDowned = false
		
		if playButton then
			playButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
			playButton.Text = "☠️ Died"
		end
	end)
	
	-- Use dependencies in Start
	if Dependencies.PlayerStateController then
		-- Do something
	end
end

return LobbyGuiController