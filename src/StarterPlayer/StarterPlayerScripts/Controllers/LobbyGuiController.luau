--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║              LOBBY GUI CONTROLLER - PRODUCTION GRADE           ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Connect UI buttons to InputController                ║
║ Features:                                                      ║
║  ✅ Button click → EventBus emission                          ║
║  ✅ Visual feedback (hover, click)                            ║
║  ✅ Cooldown visual (disable during cooldown)                 ║
║  ✅ Mobile-friendly touch events                              ║
╚════════════════════════════════════════════════════════════════╝
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
    Connect button to EventBus
    
    When button is clicked → Emit INPUT_ACTION event
    InputController will receive this and process it
]]
local function connectButton(button: TextButton, actionName: string, cooldownTime: number?)
    cooldownTime = cooldownTime or 1.0
    
    button.MouseButton1Click:Connect(function()
        -- ✅ FIX: เช็ค cooldown ก่อนส่ง event
        if buttonCooldowns[button] then
            warn(`[LobbyGuiController] ⏱️ {actionName} on cooldown (ignored)`)
            return  -- ✅ ไม่ส่ง event!
        end
        
        print(`[LobbyGuiController] 🖱️ Button clicked: {actionName}`)
        
        -- ✅ Apply cooldown BEFORE emit
        buttonCooldowns[button] = true
        
        -- ✅ Emit event AFTER cooldown check
        EventBus:Emit(Events.INPUT_ACTION, actionName)
        
        -- Visual feedback
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
    
    -- Hover effects
    button.MouseEnter:Connect(function()
        if not buttonCooldowns[button] then
            button.BackgroundColor3 = button.BackgroundColor3:Lerp(Color3.new(1, 1, 1), 0.3)
        end
    end)
    
    button.MouseLeave:Connect(function()
        if not buttonCooldowns[button] then
            button.BackgroundColor3 = actionName == "PLAY" 
                and Color3.fromRGB(0, 170, 0) 
                or Color3.fromRGB(170, 0, 0)
        end
    end)
end

function LobbyGuiController:Init()
    -- Wait for GUI
    lobbyGui = playerGui:WaitForChild("LobbyGui") :: ScreenGui
    playButton = lobbyGui:WaitForChild("PlayButton") :: TextButton
    
    local cancelBtn = lobbyGui:FindFirstChild("CancelButton")
    if cancelBtn and cancelBtn:IsA("TextButton") then
        cancelButton = cancelBtn
    end
    
    print("[LobbyGuiController] 🎨 Initialized")
end

function LobbyGuiController:Start()
    -- ✅ Connect buttons to InputController
    -- When clicked → Emit "PLAY" or "CANCEL" → InputController receives
    connectButton(playButton, "PLAY", 1.0)
    
    if cancelButton then
        connectButton(cancelButton, "CANCEL", 0.5)
    end
    
    print("[LobbyGuiController] 🚀 Started - Buttons connected")
end

return LobbyGuiController
