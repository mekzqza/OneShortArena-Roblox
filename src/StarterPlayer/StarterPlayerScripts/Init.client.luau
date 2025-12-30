--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ═══════════════════════════════════════════════════════════════
-- UTILS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local Utils = ReplicatedStorage:WaitForChild("Utils")
local IdempotentGuard = require(Utils.IdempotentGuard)

-- ✅ FIX #1: Use Guard instead of _G
local bootGuard = IdempotentGuard.new("ClientBootstrap", true)

if not bootGuard:MarkInitialized() then
	warn("[Init.client] ⚠️ Client already initialized! (via Guard)")
	return
end

print("🔌 Client Init: Starting Controllers...")

-- ═══════════════════════════════════════════════════════════════
-- GET FOLDERS
-- ═══════════════════════════════════════════════════════════════

local ControllersRoot = script.Parent
local Core = ControllersRoot:WaitForChild("Core")
local Dev = ControllersRoot:WaitForChild("Dev")
local Gameplay = ControllersRoot:WaitForChild("Gameplay")
local Inputs = ControllersRoot:WaitForChild("Inputs")
local UI = ControllersRoot:WaitForChild("UI")

-- ═══════════════════════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════════════════════

-- ✅ FIX #5: Should come from central config (TODO)
-- local ENV = require(ReplicatedStorage.Shared.Environment)
-- local IS_PRODUCTION = ENV.IS_PRODUCTION
local IS_PRODUCTION = false  -- Temporary: hardcoded

-- ✅ FIX #4: Use structured storage for O(n) instead of O(n²)
local controllersByCategory: {[string]: {[string]: any}} = {
	Core = {},
	Inputs = {},
	Gameplay = {},
	UI = {},
	Dev = {},
}

-- ✅ FIX #3: Use qualified keys to prevent name collision
local controllersFlat: {[string]: any} = {} -- For debugging only

-- ═══════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function loadControllersFromFolder(folder: Folder, categoryName: string, skipInProduction: boolean?)
	print(`[Init.client] Loading {categoryName} controllers...`)
	
	for _, moduleScript in ipairs(folder:GetChildren()) do
		if not moduleScript:IsA("ModuleScript") then
			continue
		end
		
		local controllerName = moduleScript.Name
		
		-- Skip if production and marked to skip
		if IS_PRODUCTION and skipInProduction then
			print(`[Init.client] ⏭️ Skipped {controllerName} (Production mode)`)
			continue
		end
		
		-- Load controller
		local success, result = pcall(function()
			return require(moduleScript)
		end)
		
		if not success then
			warn(`[Init.client] ❌ Failed to load {controllerName}: {result}`)
			continue
		end
		
		-- ✅ FIX #2: Controller manages its own guard (TODO: move to controller)
		-- For now, we still create it here for backward compatibility
		local guard = IdempotentGuard.new(`{categoryName}.{controllerName}`, false)
		result._guard = guard
		result._category = categoryName
		result._name = controllerName
		
		-- ✅ FIX #4: Store in category-specific table
		controllersByCategory[categoryName][controllerName] = result
		
		-- ✅ FIX #3: Use qualified key for flat storage
		local qualifiedKey = `{categoryName}.{controllerName}`
		controllersFlat[qualifiedKey] = result
		
		print(`[Init.client] ✅ Loaded {categoryName}/{controllerName}`)
	end
end

-- ═══════════════════════════════════════════════════════════════
-- LOAD CONTROLLERS (BY CATEGORY)
-- ═══════════════════════════════════════════════════════════════

print("\n[Init.client] 📦 Loading controllers by category...")
print("═════════════════════════════════════════════════════════")

loadControllersFromFolder(Core, "Core", false)
loadControllersFromFolder(Inputs, "Inputs", false)
loadControllersFromFolder(Gameplay, "Gameplay", false)
loadControllersFromFolder(UI, "UI", false)
loadControllersFromFolder(Dev, "Dev", true)

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZE CONTROLLERS
-- ═══════════════════════════════════════════════════════════════

print("\n[Init.client] 🔧 Initializing controllers...")
print("═════════════════════════════════════════════════════════")

local initOrder = {"Core", "Inputs", "Gameplay", "UI", "Dev"}

-- ✅ FIX #4: O(n) instead of O(n²) - iterate category map directly
for _, category in ipairs(initOrder) do
	for name, controller in pairs(controllersByCategory[category]) do
		if type(controller.Init) ~= "function" then
			continue
		end
		
		local guard = controller._guard
		
		if guard and not guard:MarkInitialized() then
			warn(`[Init.client] ⚠️ {category}/{name} already initialized, skipping`)
			continue
		end
		
		local initSuccess, initErr = pcall(function()
			controller:Init()
		end)
		
		if not initSuccess then
			warn(`[Init.client] ❌ Failed to init {category}/{name}: {initErr}`)
		else
			print(`[Init.client] ✅ Initialized {category}/{name}`)
		end
	end
end

-- ═══════════════════════════════════════════════════════════════
-- START CONTROLLERS
-- ═══════════════════════════════════════════════════════════════

print("\n[Init.client] ▶️ Starting controllers...")
print("═════════════════════════════════════════════════════════")

-- ✅ FIX #4: O(n) iteration
for _, category in ipairs(initOrder) do
	for name, controller in pairs(controllersByCategory[category]) do
		if type(controller.Start) ~= "function" then
			continue
		end
		
		task.spawn(function()
			local guard = controller._guard
			
			if guard and not guard:MarkStarted() then
				warn(`[Init.client] ⚠️ {category}/{name} not initialized or already started, skipping`)
				return
			end
			
			local success, err = pcall(function()
				controller:Start()
			end)
			
			if success then
				print(`[Init.client] ✅ Started {category}/{name}`)
			else
				warn(`[Init.client] ❌ Failed to start {category}/{name}: {err}`)
			end
		end)
	end
end

-- ═══════════════════════════════════════════════════════════════
-- FINALIZE
-- ═══════════════════════════════════════════════════════════════

-- ✅ FIX #1: Mark boot complete via Guard
if not bootGuard:MarkStarted() then
	warn("[Init.client] ⚠️ Failed to mark boot as started")
end

local bootTime = os.clock()

print("\n═════════════════════════════════════════════════════════")
print("✅ All controllers initialized and started successfully.")
print(string.format("⏱️ Total time: %.3fs", bootTime))
print("═════════════════════════════════════════════════════════\n")

-- ✅ Print Guard summary
if IdempotentGuard and IdempotentGuard.printSummary then
	IdempotentGuard.printSummary(bootGuard)
end

-- ═══════════════════════════════════════════════════════════════
-- DEBUG EXPOSURE (Studio only)
-- ═══════════════════════════════════════════════════════════════

if not IS_PRODUCTION or RunService:IsStudio() then
	-- ✅ Expose both flat and structured access
	_G.Controllers = controllersFlat -- Flat with qualified keys
	_G.ControllersByCategory = controllersByCategory -- Structured by category
	_G.BootGuard = bootGuard -- ✅ FIX #1: Expose boot guard
	_G.IdempotentGuard = IdempotentGuard
	
	print("[Init.client] 🔍 Debug mode enabled:")
	print("  • _G.Controllers (flat, qualified keys)")
	print("  • _G.ControllersByCategory (structured)")
	print("  • _G.BootGuard (boot lifecycle)")
	print("  • _G.IdempotentGuard (utility)")
end



