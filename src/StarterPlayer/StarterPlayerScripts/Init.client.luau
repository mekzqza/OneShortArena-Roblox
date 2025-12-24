--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local controllersFolder = script.Parent:WaitForChild("Controllers") -- โฟลเดอร์แม่

print("🔌 Client Init: Starting Controllers...")

local controllers = {}

-- Step 1: Load and Init all controllers
print("[Client Init] Step 1: Initializing controllers...")
for _, moduleScript in ipairs(controllersFolder:GetChildren()) do
    if moduleScript:IsA("ModuleScript") then
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



