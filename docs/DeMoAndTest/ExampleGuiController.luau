--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║           EXAMPLE GUI CONTROLLER - PRODUCTION GRADE            ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Manage ExampleGui interactions                       ║
║ Features:                                                      ║
║  ✅ Clean state management                                     ║
║  ✅ Proper cleanup on destroy                                  ║
║  ✅ Dependency injection via SetDependencies                   ║
║  ✅ Error handling                                             ║
║  ✅ Debouncing/Cooldowns                                       ║
╚════════════════════════════════════════════════════════════════╝
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

-- ═══════════════════════════════════════════════════════════════
-- CONTROLLER DEFINITION
-- ═══════════════════════════════════════════════════════════════

local ExampleGuiController = {}

-- ═══════════════════════════════════════════════════════════════
-- DEPENDENCIES (Injected via Init.client)
-- ═══════════════════════════════════════════════════════════════

local Dependencies: {
	NetworkController: any?,
	PlayerStateController: any?,
} = {}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local player: Player = Players.LocalPlayer
local playerGui: PlayerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- GUI References
local gui: ScreenGui? = nil
local mainFrame: Frame? = nil
local playButton: TextButton? = nil
local titleLabel: TextLabel? = nil
local inputBox: TextBox? = nil

-- Controller State
local isVisible: boolean = false
local isProcessing: boolean = false
local lastClickTime: number = 0

-- Connections (for cleanup)
local connections: {RBXScriptConnection} = {}

-- Constants
local CLICK_COOLDOWN = 1 -- seconds
local TWEEN_TIME = 0.3

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

--[[
    Find and cache GUI elements
]]
local function cacheGuiElements(): boolean
	-- Find GUI (retry up to 5 times)
	for i = 1, 5 do
		gui = playerGui:FindFirstChild("ExampleGui") :: ScreenGui?
		if gui then break end
		task.wait(0.5)
	end
	
	if not gui then
		warn("[ExampleGuiController] ❌ Could not find ExampleGui!")
		return false
	end
	
	-- Cache elements
	mainFrame = gui:FindFirstChild("MainFrame") :: Frame?
	playButton = mainFrame and mainFrame:FindFirstChild("PlayButton") :: TextButton?
	titleLabel = mainFrame and mainFrame:FindFirstChild("TitleLabel") :: TextLabel?
	inputBox = mainFrame and mainFrame:FindFirstChild("InputBox") :: TextBox?
	
	-- Validate required elements
	if not mainFrame or not playButton then
		warn("[ExampleGuiController] ❌ Missing required GUI elements!")
		return false
	end
	
	print("[ExampleGuiController] ✅ GUI elements cached")
	return true
end

--[[
    Show GUI with animation
]]
local function showGui()
	if not mainFrame or isVisible then return end
	
	gui.Enabled = true
	isVisible = true
	
	-- Tween animation
	mainFrame.Size = UDim2.new(0, 0, 0, 0)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	
	local tween = TweenService:Create(mainFrame, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Back), {
		Size = UDim2.new(0, 400, 0, 300)
	})
	
	tween:Play()
end

--[[
    Hide GUI with animation
]]
local function hideGui()
	if not mainFrame or not isVisible then return end
	
	local tween = TweenService:Create(mainFrame, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Back), {
		Size = UDim2.new(0, 0, 0, 0)
	})
	
	tween:Play()
	tween.Completed:Wait()
	
	gui.Enabled = false
	isVisible = false
end

--[[
    Update UI state
]]
local function updateUiState(state: string)
	if not titleLabel then return end
	
	if state == "Playing" then
		titleLabel.Text = "🎮 In Game"
		titleLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
	elseif state == "Lobby" then
		titleLabel.Text = "🏠 Lobby"
		titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	elseif state == "Downed" then
		titleLabel.Text = "🦵 Downed"
		titleLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
	end
end

--[[
    Set button enabled/disabled
]]
local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Interactable = enabled
	button.BackgroundColor3 = enabled 
		and Color3.fromRGB(0, 170, 0) 
		or Color3.fromRGB(100, 100, 100)
end

--[[
    Handle button click with cooldown
]]
local function onPlayButtonClick()
	-- Check cooldown
	local now = os.clock()
	if (now - lastClickTime) < CLICK_COOLDOWN then
		warn("[ExampleGuiController] ⏱️ Click too fast! Please wait...")
		return
	end
	
	-- Check if processing
	if isProcessing then
		warn("[ExampleGuiController] ⚠️ Already processing...")
		return
	end
	
	lastClickTime = now
	isProcessing = true
	setButtonEnabled(playButton, false)
	
	-- Get input value (if exists)
	local inputValue = inputBox and inputBox.Text or ""
	
	-- Send to server via NetworkController
	if Dependencies.NetworkController then
		Dependencies.NetworkController:Send("ExampleAction", {
			action = "play",
			input = inputValue
		})
	else
		-- Fallback: direct event
		EventBus:Emit(Events.PLAYER_REQUEST_TO_ARENA, player)
	end
	
	-- Re-enable after cooldown
	task.delay(CLICK_COOLDOWN, function()
		isProcessing = false
		setButtonEnabled(playButton, true)
	end)
end

--[[
    Cleanup all connections
]]
local function cleanup()
	print("[ExampleGuiController] 🧹 Cleaning up...")
	
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	
	table.clear(connections)
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS (Called by Init.client)
-- ═══════════════════════════════════════════════════════════════

--[[
    Set dependencies (called before Init)
]]
function ExampleGuiController:SetDependencies(locator: any)
	Dependencies.NetworkController = locator:Get("NetworkController")
	Dependencies.PlayerStateController = locator:Get("PlayerStateController")
	
	if not Dependencies.NetworkController then
		warn("[ExampleGuiController] ⚠️ NetworkController not found!")
	end
end

--[[
    Initialize controller (cache elements, setup)
]]
function ExampleGuiController:Init()
	print("[ExampleGuiController] 🔧 Initializing...")
	
	-- Cache GUI elements
	if not cacheGuiElements() then
		error("[ExampleGuiController] ❌ Failed to cache GUI elements!")
		return
	end
	
	-- Initially hide
	if gui then
		gui.Enabled = false
	end
	
	print("[ExampleGuiController] ✅ Initialized")
end

--[[
    Start controller (connect events)
]]
function ExampleGuiController:Start()
	print("[ExampleGuiController] 🚀 Starting...")
	
	-- ═══════════════════════════════════════════════════════════
	-- CONNECT BUTTON EVENTS
	-- ═══════════════════════════════════════════════════════════
	
	if playButton then
		table.insert(connections, playButton.MouseButton1Click:Connect(onPlayButtonClick))
		
		-- Hover effects
		table.insert(connections, playButton.MouseEnter:Connect(function()
			if not isProcessing then
				playButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
			end
		end))
		
		table.insert(connections, playButton.MouseLeave:Connect(function()
			if not isProcessing then
				playButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
			end
		end))
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- LISTEN TO GAME EVENTS
	-- ═══════════════════════════════════════════════════════════
	
	-- Show GUI in Lobby
	table.insert(connections, EventBus:On(Events.PLAYER_STATE_CHANGED, function(changedPlayer: Player, eventData: any)
		if changedPlayer ~= player then return end
		
		local newState = eventData.newState
		
		if newState == "Lobby" then
			showGui()
		elseif newState == "Playing" or newState == "Downed" then
			hideGui()
		end
		
		updateUiState(newState)
	end))
	
	-- ═══════════════════════════════════════════════════════════
	-- CLEANUP ON PLAYER LEAVING
	-- ═══════════════════════════════════════════════════════════
	
	table.insert(connections, player.AncestryChanged:Connect(function()
		if not player:IsDescendantOf(game) then
			cleanup()
		end
	end))
	
	print("[ExampleGuiController] ✅ Started")
end

--[[
    Public: Show GUI manually
]]
function ExampleGuiController:Show()
	showGui()
end

--[[
    Public: Hide GUI manually
]]
function ExampleGuiController:Hide()
	hideGui()
end

--[[
    Public: Toggle GUI
]]
function ExampleGuiController:Toggle()
	if isVisible then
		hideGui()
	else
		showGui()
	end
end

--[[
    Public: Set button text
]]
function ExampleGuiController:SetButtonText(text: string)
	if playButton then
		playButton.Text = text
	end
end

--[[
    Public: Get input value
]]
function ExampleGuiController:GetInput(): string
	return inputBox and inputBox.Text or ""
end

--[[
    Public: Destroy controller
]]
function ExampleGuiController:Destroy()
	cleanup()
	
	if gui then
		gui:Destroy()
	end
	
	print("[ExampleGuiController] 🗑️ Destroyed")
end

return ExampleGuiController
