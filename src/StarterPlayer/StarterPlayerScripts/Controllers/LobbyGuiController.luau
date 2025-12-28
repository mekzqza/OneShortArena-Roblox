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
    cooldownTime = cooldownTime or 0.5
    
    button.MouseButton1Click:Connect(function()
        -- Check cooldown
        if buttonCooldowns[button] then
            warn(`[LobbyGuiController] ⏱️ {actionName} is on cooldown`)
            return
        end
        
        -- Emit to EventBus (InputController listens to this)
        print(`[LobbyGuiController] 🖱️ Button clicked: {actionName}`)
        EventBus:Emit(Events.INPUT_ACTION, actionName)
        
        -- Visual feedback
        button.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
        
        -- Apply cooldown
        buttonCooldowns[button] = true
        button.Text = "..."
        
        task.delay(cooldownTime, function()
            buttonCooldowns[button] = false
            button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            button.Text = actionName
        end)
    end)
    
    -- Hover effects
    button.MouseEnter:Connect(function()
        if not buttonCooldowns[button] then
            button.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
        end
    end)
    
    button.MouseLeave:Connect(function()
        if not buttonCooldowns[button] then
            button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        end
    end)
end

function LobbyGuiController:Init()
    -- Wait for GUI
    lobbyGui = playerGui:WaitForChild("LobbyGui") :: ScreenGui
    playButton = lobbyGui:WaitForChild("PlayButton") :: TextButton
    cancelButton = lobbyGui:WaitForChild("CancelButton") :: TextButton
    
    print("[LobbyGuiController] 🎨 Initialized")
end

function LobbyGuiController:Start()
    -- ✅ Connect buttons to InputController
    -- When clicked → Emit "PLAY" or "CANCEL" → InputController receives
    connectButton(playButton, "PLAY", 1.0)
    connectButton(cancelButton, "CANCEL", 0.5)
    
    print("[LobbyGuiController] 🚀 Started - Buttons connected to EventBus")
end

return LobbyGuiController
