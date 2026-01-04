--!strict

local players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)


local AssetUI = ReplicatedStorage:WaitForChild("Assets")
local UiFolder = AssetUI:FindFirstChild("UI")
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UiLoader = {}
UiLoader.LoadedScreens = {}

function UiLoader:LoadScreen(screenName: string)
    if screenName == nil or screenName == "" then
        warn("Screen name is required")
        return nil
    end

    if self.LoadedScreens[screenName] then
        warn("Screen "..screenName.." is already loaded.")
        return
    end

    local originalScreen = UiFolder:FindFirstChild(screenName)
    if not originalScreen then
        warn("Screen "..screenName.." does not exist in AssetUI.")
        return
    end

    --load screen 1
    local newScreen = originalScreen:Clone()

    --เก็บไว้ใน PlayerGui 2
    newScreen.Parent = playerGui

    --เก็บไว้ในตาราง LoadedScreens 3
    self.LoadedScreens[screenName] = newScreen

    --แสดงผลใน Output ว่าโหลด UI แล้ว 4
    print(" UI Loaded :"..screenName)

    return newScreen
end

function UiLoader:Init()
    
    -- ตัวอย่างการโหลดหน้าจอ UI
    local SkillBarGui = self:LoadScreen("SkillBarGui")

    if SkillBarGui then
        print("SkillBarGui screen loaded successfully.")
    else
        warn("Failed to load SkillBarGui screen.")
    end

    EventBus:On(Events.TOGGLE_UI, function(uiName: string, isVisible: boolean)
        local screen = self.LoadedScreens[uiName] or self:LoadScreen(uiName)
        if screen then
            screen.Enabled = isVisible
            print("Toggled UI "..uiName.." to "..tostring(isVisible))
        else
            warn("UI "..uiName.." not found to toggle.")
        end
    end)

    print("UiLoader initialized.")


end

function UiLoader:Start()
    -- No-op for now
end

return UiLoader