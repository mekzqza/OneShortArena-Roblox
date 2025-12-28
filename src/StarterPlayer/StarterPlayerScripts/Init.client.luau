--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")


local Utils = ReplicatedStorage:WaitForChild("Utils")

-- ═══════════════════════════════════════════════════════════════
-- IDEMPOTENT GUARD
-- ═══════════════════════════════════════════════════════════════

if _G.__CLIENT_INITIALIZED then
    warn("[Init.client] ⚠️ Client already initialized! Skipping re-initialization.")
    return
end

print("🔌 Client Init: Starting Controllers...")

-- ✅ Load IdempotentGuard from ReplicatedStorage
local IdempotentGuard =require(Utils.IdempotentGuard)



-- ═══════════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════════

local controllersFolder = script.Parent:WaitForChild("Controllers")
local controllers = {}

local SKIP_IN_PRODUCTION = {
    ["DemoController"] = true,
    ["TestController"] = true,
}

local IS_PRODUCTION = false

-- ═══════════════════════════════════════════════════════════════
-- LOAD CONTROLLERS
-- ═══════════════════════════════════════════════════════════════

print("[Client Init] Step 1: Loading controllers...")

for _, moduleScript in ipairs(controllersFolder:GetChildren()) do
    if not moduleScript:IsA("ModuleScript") then
        continue
    end
    
    local controllerName = moduleScript.Name
    
    -- Skip demo/test controllers in production
    if IS_PRODUCTION and SKIP_IN_PRODUCTION[controllerName] then
        print(`[Client Init] ⏭️ Skipped {controllerName} (Production mode)`)
        continue
    end
    
    -- ✅ Create guard for each controller
    local guard = IdempotentGuard and IdempotentGuard.new(controllerName, false)
    
    -- Load controller
    local success, result = pcall(function()
        return require(moduleScript)
    end)
    
    if success then
        controllers[controllerName] = result
        
        -- Store guard reference
        if guard then
            result._guard = guard
        end
        
        print(`[Client Init] ✅ Loaded {controllerName}`)
    else
        warn(`[Client Init] ❌ Failed to load {controllerName}: {result}`)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZE CONTROLLERS
-- ═══════════════════════════════════════════════════════════════

print("[Client Init] Step 2: Initializing controllers...")

for name, controller in pairs(controllers) do
    if type(controller.Init) == "function" then
        -- ✅ Use guard if available
        local guard = controller._guard
        
        if guard and not guard:MarkInitialized() then
            warn(`[Client Init] ⚠️ {name} already initialized, skipping`)
            continue
        end
        
        local initSuccess, initErr = pcall(function()
            controller:Init()
        end)
        
        if not initSuccess then
            warn(`[Client Init] ❌ Failed to init {name}: {initErr}`)
        else
            print(`[Client Init] ✅ Initialized {name}`)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- START CONTROLLERS
-- ═══════════════════════════════════════════════════════════════

print("[Client Init] Step 3: Starting controllers...")

for name, controller in pairs(controllers) do
    if type(controller.Start) == "function" then
        task.spawn(function()
            -- ✅ Use guard if available
            local guard = controller._guard
            
            if guard and not guard:MarkStarted() then
                warn(`[Client Init] ⚠️ {name} already started or not initialized, skipping`)
                return
            end
            
            local success, err = pcall(function()
                controller:Start()
            end)
            
            if success then
                print(`[Client Init] ✅ Started {name}`)
            else
                warn(`[Client Init] ❌ Failed to start {name}: {err}`)
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- FINALIZE
-- ═══════════════════════════════════════════════════════════════

_G.__CLIENT_INITIALIZED = true
_G.__CLIENT_INIT_TIME = os.clock()

print("✅ All controllers initialized and started.")

-- ✅ Print IdempotentGuard summary
if IdempotentGuard and IdempotentGuard.printSummary then
    IdempotentGuard.printSummary()
end

-- Expose for debugging (only in development)
if not IS_PRODUCTION or RunService:IsStudio() then
    _G.Controllers = controllers
    
    if IdempotentGuard then
        _G.IdempotentGuard = IdempotentGuard
    end
end



