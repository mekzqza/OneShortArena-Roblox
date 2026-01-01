--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ═══════════════════════════════════════════════════════════════
-- LOAD PROMISE LIBRARY
-- ═══════════════════════════════════════════════════════════════

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Promise = require(Packages.Promise)

-- ═══════════════════════════════════════════════════════════════
-- UTILS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local Utils = ReplicatedStorage:WaitForChild("Utils")
local IdempotentGuard = require(Utils.IdempotentGuard)

-- ✅ Use Guard instead of _G
local bootGuard = IdempotentGuard.new("ClientBootstrap", true)

if not bootGuard:MarkInitialized() then
	warn("[Init.client] ⚠️ Client already initialized! (via Guard)")
	return
end

local bootStartTime = os.clock()

print("🔌 Client Init: Starting Controllers...")
print(`⏱️  Boot started at: {os.date("%X", os.time())}`)

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

local IS_PRODUCTION = false

-- ✅ TIMEOUTS ต้องอยู่ที่นี่ - ก่อนใช้งาน!
local TIMEOUTS = {
	ControllerInit = 10,     -- Max 10s per controller Init
	ControllerStart = 10,    -- Max 10s per controller Start
	LayerInit = 30,          -- Max 30s per layer Init
	LayerStart = 30,         -- Max 30s per layer Start
}

-- ✅ Structured storage for O(n) access
local controllersByCategory: {[string]: {[string]: any}} = {
	Core = {},
	Inputs = {},
	Gameplay = {},
	UI = {},
	Dev = {},
}

local controllersFlat: {[string]: any} = {} -- For debugging

-- 📊 Track timing per category
local categoryTimes: {[string]: number} = {}

-- ✅ NEW: Controller Locator (for dependency injection)
local ControllerLocator = {
	_registry = {} :: {[string]: any},
}

function ControllerLocator:Register(name: string, controller: any)
	self._registry[name] = controller
end

function ControllerLocator:Get(name: string): any?
	return self._registry[name]
end

function ControllerLocator:GetAll(): {[string]: any}
	return self._registry
end

-- ═══════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS (NOW TIMEOUTS IS AVAILABLE!)
-- ═══════════════════════════════════════════════════════════════

local function loadControllersFromFolder(folder: Folder, categoryName: string, skipInProduction: boolean?): {any}
	print(`[Init.client] Loading {categoryName} controllers...`)
	
	local controllers: {any} = {}
	
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
		
		-- Setup controller metadata
		local guard = IdempotentGuard.new(`{categoryName}.{controllerName}`, false)
		result._guard = guard
		result._category = categoryName
		result._name = controllerName
		
		-- Store in category-specific table
		controllersByCategory[categoryName][controllerName] = result
		
		-- Use qualified key for flat storage
		local qualifiedKey = `{categoryName}.{controllerName}`
		controllersFlat[qualifiedKey] = result
		
		table.insert(controllers, result)
		
		print(`[Init.client] ✅ Loaded {categoryName}/{controllerName}`)
	end
	
	return controllers
end

--[[]
    Initialize a single controller with timeout protection
    @param controller table - Controller instance
    @param timeout number? - Timeout in seconds (default 10s)
    @return Promise<boolean>
]]
local function initController(controller: any, timeout: number?): any
	timeout = timeout or TIMEOUTS.ControllerInit  -- ✅ NOW THIS WORKS!
	
	return Promise.new(function(resolve, reject)
		local category = controller._category
		local name = controller._name
		
		if type(controller.Init) ~= "function" then
			resolve(true)
			return
		end
		
		local guard = controller._guard
		
		if guard and not guard:MarkInitialized() then
			warn(`[Init.client] ⚠️ {category}/{name} already initialized, skipping`)
			reject(`{category}/{name} already initialized`)
			return
		end
		
		-- ✅ INJECT DEPENDENCIES: Pass ControllerLocator to controller
		if controller.SetDependencies and type(controller.SetDependencies) == "function" then
			controller:SetDependencies(ControllerLocator)
		end
		
		local success, err = pcall(function()
			controller:Init()
		end)
		
		if success then
			print(`[Init.client] ✅ Initialized {category}/{name}`)
			resolve(true)
		else
			reject(`{category}/{name} failed: {err}`)
		end
	end)
		:timeout(timeout)
		:catch(function(err)
			-- Handle both regular errors and timeouts
			if Promise.Error.isKind(err, Promise.Error.Kind.TimedOut) then
				error(`[Init.client] ⏱️ TIMEOUT: {controller._category}/{controller._name} Init exceeded {timeout}s`)
			else
				error(`[Init.client] ❌ ERROR: {controller._category}/{controller._name} Init failed: {err}`)
			end
		end)
end

--[[]
    Start a single controller with timeout protection
    @param controller table - Controller instance
    @param timeout number? - Timeout in seconds (default 10s)
    @return Promise<boolean>
]]
local function startController(controller: any, timeout: number?): any
	timeout = timeout or TIMEOUTS.ControllerStart  -- ✅ NOW THIS WORKS!
	
	return Promise.new(function(resolve, reject)
		local category = controller._category
		local name = controller._name
		
		if type(controller.Start) ~= "function" then
			resolve(true)
			return
		end
		
		local guard = controller._guard
		
		if guard and not guard:MarkStarted() then
			warn(`[Init.client] ⚠️ {category}/{name} not initialized or already started`)
			reject(`{category}/{name} not initialized`)
			return
		end
		
		local success, err = pcall(function()
			controller:Start()
		end)
		
		if success then
			print(`[Init.client] ✅ Started {category}/{name}`)
			resolve(true)
		else
			reject(`{category}/{name} failed: {err}`)
		end
	end)
		:timeout(timeout)
		:catch(function(err)
			if Promise.Error.isKind(err, Promise.Error.Kind.TimedOut) then
				error(`[Init.client] ⏱️ TIMEOUT: {controller._category}/{controller._name} Start exceeded {timeout}s`)
			else
				error(`[Init.client] ❌ ERROR: {controller._category}/{controller._name} Start failed: {err}`)
			end
		end)
end

-- ═══════════════════════════════════════════════════════════════
-- LOAD CONTROLLERS (BY CATEGORY) + REGISTER IN LOCATOR
-- ═══════════════════════════════════════════════════════════════

print("\n[Init.client] 📦 Loading controllers by category...")
print("═════════════════════════════════════════════════════════")

-- Load all controllers first (synchronous)
loadControllersFromFolder(Core, "Core", false)
loadControllersFromFolder(Inputs, "Inputs", false)
loadControllersFromFolder(Gameplay, "Gameplay", false)
loadControllersFromFolder(UI, "UI", false)
loadControllersFromFolder(Dev, "Dev", true)

-- ✅ NEW: Register all loaded controllers in ControllerLocator
print("\n[Init.client] 📋 Registering controllers in ControllerLocator...")
for qualifiedKey, controller in pairs(controllersFlat) do
	ControllerLocator:Register(qualifiedKey, controller)
	-- Also register by short name for convenience
	ControllerLocator:Register(controller._name, controller)
end
print(`[Init.client] ✅ Registered {#controllersFlat} controllers`)

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZE CONTROLLERS (WITH TIMEOUTS)
-- ═══════════════════════════════════════════════════════════════

print("\n[Init.client] 🔧 Initializing controllers...")
print("═════════════════════════════════════════════════════════")

Promise.resolve()
	-- 1️⃣ Core Layer
	:andThen(function()
		print("[Init.client] 1️⃣ Core Layer...")
		local startTime = os.clock()
		
		local promises = {}
		for _, controller in pairs(controllersByCategory.Core) do
			table.insert(promises, initController(controller))
		end
		
		return Promise.all(promises)
			:andThen(function()
				categoryTimes["Core"] = os.clock() - startTime
			end)
			:timeout(TIMEOUTS.LayerInit)
	end)
	
	-- 2️⃣ Inputs Layer
	:andThen(function()
		print("[Init.client] 2️⃣ Inputs Layer...")
		local startTime = os.clock()
		
		local promises = {}
		for _, controller in pairs(controllersByCategory.Inputs) do
			table.insert(promises, initController(controller))
		end
		
		return Promise.all(promises)
			:andThen(function()
				categoryTimes["Inputs"] = os.clock() - startTime
			end)
			:timeout(TIMEOUTS.LayerInit)
	end)
	
	-- 3️⃣ Gameplay + UI Layers (PARALLEL)
	:andThen(function()
		print("[Init.client] 3️⃣ Gameplay & UI Layers (Parallel)...")
		local startTime = os.clock()
		
		local promises = {}
		
		for _, controller in pairs(controllersByCategory.Gameplay) do
			table.insert(promises, initController(controller))
		end
		
		for _, controller in pairs(controllersByCategory.UI) do
			table.insert(promises, initController(controller))
		end
		
		return Promise.all(promises)
			:andThen(function()
				categoryTimes["Gameplay+UI"] = os.clock() - startTime
				print(`[Init.client] ⚡ Gameplay & UI completed in {string.format("%.3f", categoryTimes["Gameplay+UI"])}s (Parallel)`)
			end)
			:timeout(TIMEOUTS.LayerInit)
	end)
	
	-- 4️⃣ Dev Layer (optional)
	:andThen(function()
		if IS_PRODUCTION then
			return Promise.resolve()
		end
		
		print("[Init.client] 4️⃣ Dev Layer...")
		local startTime = os.clock()
		
		local promises = {}
		for _, controller in pairs(controllersByCategory.Dev) do
			table.insert(promises, initController(controller))
		end
		
		return Promise.all(promises)
			:andThen(function()
				categoryTimes["Dev"] = os.clock() - startTime
			end)
			:timeout(TIMEOUTS.LayerInit)
			:catch(function(err)
				warn(`[Init.client] ⚠️ Dev Layer failed: {err}`)
				return Promise.resolve()
			end)
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- START CONTROLLERS (WITH TIMEOUTS)
	-- ═══════════════════════════════════════════════════════════
	
	:andThen(function()
		print("\n[Init.client] ▶️ Starting controllers...")
		print("═════════════════════════════════════════════════════════")
		return Promise.resolve()
	end)
	
	-- Start Core
	:andThen(function()
		local promises = {}
		for _, controller in pairs(controllersByCategory.Core) do
			table.insert(promises, startController(controller))
		end
		return Promise.all(promises):timeout(TIMEOUTS.LayerStart)
	end)
	
	-- Start Inputs
	:andThen(function()
		local promises = {}
		for _, controller in pairs(controllersByCategory.Inputs) do
			table.insert(promises, startController(controller))
		end
		return Promise.all(promises):timeout(TIMEOUTS.LayerStart)
	end)
	
	-- Start Gameplay + UI (PARALLEL)
	:andThen(function()
		local promises = {}
		
		for _, controller in pairs(controllersByCategory.Gameplay) do
			table.insert(promises, startController(controller))
		end
		
		for _, controller in pairs(controllersByCategory.UI) do
			table.insert(promises, startController(controller))
		end
		
		return Promise.all(promises):timeout(TIMEOUTS.LayerStart)
	end)
	
	-- Start Dev (optional)
	:andThen(function()
		if IS_PRODUCTION then
			return Promise.resolve()
		end
		
		local promises = {}
		for _, controller in pairs(controllersByCategory.Dev) do
			table.insert(promises, startController(controller))
		end
		
		return Promise.all(promises)
			:timeout(TIMEOUTS.LayerStart)
			:catch(function(err)
				warn(`[Init.client] ⚠️ Dev controllers start failed: {err}`)
				return Promise.resolve()
			end)
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- FINALIZE
	-- ═══════════════════════════════════════════════════════════
	
	:andThen(function()
		if not bootGuard:MarkStarted() then
			warn("[Init.client] ⚠️ Failed to mark boot as started")
		end
		
		local bootTime = os.clock() - bootStartTime
		
		print("\n═════════════════════════════════════════════════════════")
		print("✅ All controllers initialized and started successfully.")
		print(string.format("⏱️ Total boot time: %.3fs", bootTime))
		print("═════════════════════════════════════════════════════════")
		
		-- Print category breakdown
		print("\n📊 Category Timing Breakdown:")
		print("─────────────────────────────────────────────────────────")
		for category, time in pairs(categoryTimes) do
			local percentage = (time / bootTime) * 100
			print(string.format("  %s: %.3fs (%.1f%%)", category, time, percentage))
		end
		print("─────────────────────────────────────────────────────────\n")
		
		-- Print Guard summary
		if IdempotentGuard and IdempotentGuard.printSummary then
			IdempotentGuard.printSummary(bootGuard)
		end
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- ERROR HANDLING
	-- ═══════════════════════════════════════════════════════════
	
	:catch(function(err)
		error(`[Init.client] ❌ CRITICAL ERROR during boot: {err}`)
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- FINALLY (always runs)
	-- ═══════════════════════════════════════════════════════════
	
	:finally(function()
		print(`\n⏱️  Boot completed at: {os.date("%X", os.time())}`)
		
		if not IS_PRODUCTION or RunService:IsStudio() then
			_G.Controllers = controllersFlat
			_G.ControllersByCategory = controllersByCategory
			_G.ControllerLocator = ControllerLocator  -- ✅ NEW
			_G.BootGuard = bootGuard
			_G.IdempotentGuard = IdempotentGuard
			_G.Promise = Promise
			
			print("[Init.client] 🔍 Debug mode enabled:")
			print("  • _G.Controllers (flat, qualified keys)")
			print("  • _G.ControllersByCategory (structured)")
			print("  • _G.ControllerLocator (dependency injection)")  -- ✅ NEW
			print("  • _G.BootGuard (boot lifecycle)")
			print("  • _G.IdempotentGuard (utility)")
			print("  • _G.Promise (for testing)")
		end
	end)



