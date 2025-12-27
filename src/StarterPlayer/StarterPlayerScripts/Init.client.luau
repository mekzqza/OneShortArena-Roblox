--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local controllersFolder = script.Parent:WaitForChild("Controllers") -- โฟลเดอร์แม่

print("🔌 Client Init: Starting Controllers...")

local controllers = {}

-- Production mode: Skip demo/test controllers
local SKIP_IN_PRODUCTION = {
    ["DemoController"] = true,
    ["TestController"] = true,
}

local IS_PRODUCTION = false -- เปลี่ยนเป็น true เมื่อ deploy

-- Step 1: Load and Init all controllers
print("[Client Init] Step 1: Initializing controllers...")
for _, moduleScript in ipairs(controllersFolder:GetChildren()) do
    if moduleScript:IsA("ModuleScript") then
        -- Skip demo/test controllers in production
        if IS_PRODUCTION and SKIP_IN_PRODUCTION[moduleScript.Name] then
            print(`[Client Init] ⏭️ Skipped {moduleScript.Name} (Production mode)`)
            continue
        end
        
        local success, result = pcall(function()
            return require(moduleScript)
        end)
        
        if success then
            controllers[moduleScript.Name] = result
            print(`[Client Init] ✅ Loaded {moduleScript.Name}`)
            
            -- Init phase
            if type(result.Init) == "function" then
                local initSuccess, initErr = pcall(function()
                    result:Init()
                end)
                
                if not initSuccess then
                    warn(`❌ Failed to init {moduleScript.Name}: {initErr}`)
                end
            end
        else
            warn(`❌ Failed to load {moduleScript.Name}: {result}`)
        end
    end
end

-- Step 2: Start all controllers
print("[Client Init] Step 2: Starting controllers...")
for name, controller in pairs(controllers) do
    if type(controller.Start) == "function" then
        task.spawn(function()
            local success, err = pcall(function()
                controller:Start()
            end)
            
            if success then
                print(`[Client Init] ✅ Started {name}`)
            else
                warn(`❌ Failed to start {name}: {err}`)
            end
        end)
    end
end

print("✅ All controllers initialized and started.")

-- Expose for debugging (only in development)
if not IS_PRODUCTION then
    _G.Controllers = controllers
    _G.DemoController = controllers.DemoController
    _G.TestController = controllers.TestController
end



