local ReplicatedStorage = game:GetService("ReplicatedStorage")
local controllersFolder = script.Parent:WaitForChild("Controllers") -- โฟลเดอร์แม่

print("🔌 Client Init: Starting Controllers...")

-- แก้ชื่อตัวแปรในลูปจาก controllersFolder เป็น moduleScript
for _, moduleScript in ipairs(controllersFolder:GetChildren()) do
    if moduleScript:IsA("ModuleScript") then
        task.spawn(function()
            -- require ตัวสคริปต์ลูก
            local controller = require(moduleScript) 
            
            if type(controller.Init) == "function" then
                local success, err = pcall(function()
                    controller:Init() 
                end)
                
                if not success then
                    -- เวลา Error จะได้รู้ว่าตัวไหนพัง
                    warn("❌ Failed to init " .. moduleScript.Name .. ": " .. err) 
                end
            end
        end)
    end
end

print("✅ Controllers initialized.")

local NetworkController = require(controllersFolder:WaitForChild("NetworkController"))
local DemoController = require(controllersFolder:WaitForChild("DemoController")) -- Add demo

-- Initialize
print("[Init] Initializing NetworkController...")
NetworkController:Init()

print("[Init] Initializing DemoController...")
DemoController:Init()

-- Start
print("[Init] Starting controllers...")
NetworkController:Start()
DemoController:Start()

print("✅ Client initialized successfully.")
print("🎮 Demo Mode: Press F9 and use DemoController methods")

-- Make DemoController globally accessible for testing
_G.DemoController = DemoController