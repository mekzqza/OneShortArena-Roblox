--!strict

local ServerScriptService = game:GetService("ServerScriptService")
-- local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ═══════════════════════════════════════════════════════════════
-- LOAD PROMISE LIBRARY
-- ═══════════════════════════════════════════════════════════════

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Promise = require(Packages.Promise)

-- ═══════════════════════════════════════════════════════════════
-- IDEMPOTENT GUARD
-- ═══════════════════════════════════════════════════════════════

if _G.__SERVER_INITIALIZED then
	warn("[Init.server] ⚠️ Server already initialized! Skipping re-initialization.")
	return
end

local bootStartTime = os.clock()

print("🔌 Server Init: Starting Services...")
print(`⏱️  Boot started at: {os.date("%X", os.time())}`)

-- ═══════════════════════════════════════════════════════════════
-- ✅ TIMEOUTS - ต้องอยู่ที่นี่! ก่อน HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local TIMEOUTS = {
	ServiceInit = 15,     -- Max 15s per service Init
	ServiceStart = 15,    -- Max 15s per service Start
	LayerInit = 45,       -- Max 45s per layer Init
	LayerStart = 45,      -- Max 45s per layer Start
}

-- ═══════════════════════════════════════════════════════════════
-- GET FOLDERS
-- ═══════════════════════════════════════════════════════════════

local Services = ServerScriptService:WaitForChild("Services")
local Utils = ServerScriptService:WaitForChild("Utils")

-- ✅ NEW: Services subfolders
local Core = Services:WaitForChild("Core")
local Gameplay = Services:WaitForChild("Gameplay")
local Player = Services:WaitForChild("Player")
local Data = Services:WaitForChild("Data")
local Cloud = Services:WaitForChild("Cloud")

-- -- ✅ Preload NetworkConfig
-- local Configs = ServerStorage:WaitForChild("Configs")
-- local NetworkConfig = require(Configs.NetworkConfig)



-- ═══════════════════════════════════════════════════════════════
-- LOAD SERVICES
-- ═══════════════════════════════════════════════════════════════

-- Core Services
print("[Init] Loading Core services...")
local NetworkHandler = require(Core.NetworkHandler)
local CmdrService = require(Core.CmdrService)  -- ✅ เพิ่มบรรทัดนี้

-- Gameplay Services
print("[Init] Loading Gameplay services...")
local ArenaService = require(Gameplay.ArenaService)
local CombatService = require(Gameplay.CombatService)    -- ✅ NEW
local CooldownService = require(Gameplay.CooldownService)
local DeathService = require(Gameplay.DeathService)
local DownedService = require(Gameplay.DownedService)
local GameService = require(Gameplay.GameService)
local LobbyService = require(Gameplay.LobbyService)
local MatchService = require(Gameplay.MatchService)
local RespawnService = require(Gameplay.RespawnService)  -- ✅ NEW

-- Player Services
print("[Init] Loading Player services...")
local PlayerStateService = require(Player.PlayerStateService)

-- Data Services (NEW)
print("[Init] Loading Data services...")
local PlayerDataService = require(Data.PlayerDataService)

-- Cloud Services (NEW)
print("[Init] Loading Cloud services...")
local PocketBaseService = require(Cloud.PocketBaseService)

local TestService = require(Services.TestService)

-- Utils
print("[Init] Loading Utils...")
local IdempotentGuard = require(Utils.IdempotentGuard)
local ServiceLocator = require(Utils.ServiceLocator)
local DataMapper = require(Utils.DataMapper)
local IdempotencyKey = require(Utils.IdempotencyKey)

-- ═══════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS (NOW TIMEOUTS IS AVAILABLE!)
-- ═══════════════════════════════════════════════════════════════

--[[]
    Initialize a single service with error handling + timeout
    @param service table - Service instance
    @param name string - Service name for logging
    @param timeout number? - Timeout in seconds
    @return Promise<boolean>
]]
local function initService(service: any, name: string, timeout: number?): any
	timeout = timeout or TIMEOUTS.ServiceInit  -- ✅ ตอนนี้ TIMEOUTS มีค่าแล้ว!
	
	return Promise.new(function(resolve, reject)
		local success, err = pcall(function()
			if service and type(service.Init) == "function" then
				service:Init()
			end
		end)
		
		if success then
			print(`[Init] ✅ {name} initialized`)
			resolve(true)
		else
			reject(`{name} failed: {err}`)
		end
	end)
		:timeout(timeout)
		:catch(function(err)
			if Promise.Error.isKind(err, Promise.Error.Kind.TimedOut) then
				error(`[Init] ⏱️ TIMEOUT: {name} Init exceeded {timeout}s`)
			else
				error(`[Init] ❌ ERROR: {name} Init failed: {err}`)
			end
		end)
end

--[[]
    Start a single service with error handling + timeout
    @param service table - Service instance
    @param name string - Service name for logging
    @param timeout number? - Timeout in seconds
    @return Promise<boolean>
]]
local function startService(service: any, name: string, timeout: number?): any
	timeout = timeout or TIMEOUTS.ServiceStart  -- ✅ ตอนนี้ TIMEOUTS มีค่าแล้ว!
	
	return Promise.new(function(resolve, reject)
		local success, err = pcall(function()
			if service and type(service.Start) == "function" then
				service:Start()
			end
		end)
		
		if success then
			print(`[Init] ✅ {name} started`)
			resolve(true)
		else
			reject(`{name} failed: {err}`)
		end
	end)
		:timeout(timeout)
		:catch(function(err)
			if Promise.Error.isKind(err, Promise.Error.Kind.TimedOut) then
				error(`[Init] ⏱️ TIMEOUT: {name} Start exceeded {timeout}s`)
			else
				error(`[Init] ❌ ERROR: {name} Start failed: {err}`)
			end
		end)
end

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZE SERVICES (WITH TIMEOUTS)
-- ═══════════════════════════════════════════════════════════════

print("\n[Init] 🔧 Initializing services...")
print("═════════════════════════════════════════════════════════")

local layerTimes: {[string]: number} = {}

Promise.resolve()

	-- ═══════════════════════════════════════════════════════════
	-- 0️⃣ REGISTER SERVICES IN LOCATOR
	-- ═══════════════════════════════════════════════════════════
	
	:andThen(function()
		print("\n[Init] 📋 Registering services in ServiceLocator...")
		
		ServiceLocator:Register("NetworkHandler", NetworkHandler)
		ServiceLocator:Register("CmdrService", CmdrService)  -- ✅ เพิ่มบรรทัดนี้
		ServiceLocator:Register("PocketBaseService", PocketBaseService)
		ServiceLocator:Register("PlayerDataService", PlayerDataService)
		ServiceLocator:Register("PlayerStateService", PlayerStateService)
		ServiceLocator:Register("LobbyService", LobbyService)
		ServiceLocator:Register("ArenaService", ArenaService)
		ServiceLocator:Register("CombatService", CombatService)
		ServiceLocator:Register("DeathService", DeathService)
		ServiceLocator:Register("DownedService", DownedService)
		ServiceLocator:Register("RespawnService", RespawnService)
		ServiceLocator:Register("MatchService", MatchService)
		ServiceLocator:Register("CooldownService", CooldownService)
		ServiceLocator:Register("GameService", GameService)
		
		print("[Init] ✅ All services registered")
	end)
	-- 1️⃣ Core Layer
	:andThen(function()
		print("[Init] 1️⃣ Core Layer...")
		local startTime = os.clock()
		
		return Promise.all({
			initService(NetworkHandler, "NetworkHandler"),
			initService(CmdrService, "CmdrService"),  -- ✅ เพิ่มบรรทัดนี้
		})
			:andThen(function()
				layerTimes["Core"] = os.clock() - startTime
			end)
			:timeout(TIMEOUTS.LayerInit)
	end)	
	-- 2️⃣ Cloud Layer
	:andThen(function()
		print("[Init] 2️⃣ Cloud Layer...")
		local startTime = os.clock()
		
		return initService(PocketBaseService, "PocketBaseService")
			:andThen(function()
				layerTimes["Cloud"] = os.clock() - startTime
			end)
			:timeout(TIMEOUTS.LayerInit)
	end)
	
	-- 3️⃣ Data Layer
	:andThen(function()
		print("[Init] 3️⃣ Data Layer...")
		local startTime = os.clock()
		
		return initService(PlayerDataService, "PlayerDataService")
			:andThen(function()
				layerTimes["Data"] = os.clock() - startTime
			end)
			:timeout(TIMEOUTS.LayerInit)
	end)
	
	-- 4️⃣ Player Layer
	:andThen(function()
		print("[Init] 4️⃣ Player Layer...")
		local startTime = os.clock()
		
		return initService(PlayerStateService, "PlayerStateService")
			:andThen(function()
				layerTimes["Player"] = os.clock() - startTime
			end)
			:timeout(TIMEOUTS.LayerInit)
	end)
	
	-- 5️⃣ Gameplay Layer (PARALLEL)
	:andThen(function()
		print("[Init] 5️⃣ Gameplay Layer (Parallel)...")
		local startTime = os.clock()
		
		return Promise.all({
			initService(LobbyService, "LobbyService"),
			initService(ArenaService, "ArenaService"),
			initService(CombatService, "CombatService"),
			initService(DeathService, "DeathService"),
			initService(DownedService, "DownedService"),
			initService(RespawnService, "RespawnService"),
			initService(MatchService, "MatchService"),
			initService(CooldownService, "CooldownService"),
			initService(GameService, "GameService"),
		})
			:andThen(function()
				layerTimes["Gameplay"] = os.clock() - startTime
				print(`[Init] ⚡ Gameplay Layer completed in {string.format("%.3f", layerTimes["Gameplay"])}s (Parallel)`)
			end)
			:timeout(TIMEOUTS.LayerInit)
	end)
	
	-- 6️⃣ Test Layer (optional)
	:andThen(function()
		print("[Init] 6️⃣ Test Layer...")
		local startTime = os.clock()
		
		return initService(TestService, "TestService")
			:andThen(function()
				layerTimes["Test"] = os.clock() - startTime
			end)
			:timeout(TIMEOUTS.LayerInit)
			:catch(function(err)
				warn(`[Init] ⚠️ Test Layer failed: {err}`)
				return Promise.resolve()
			end)
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- START SERVICES (WITH TIMEOUTS)
	-- ═══════════════════════════════════════════════════════════
	
	:andThen(function()
		print("\n[Init] ▶️ Starting services...")
		print("═════════════════════════════════════════════════════════")
		return Promise.resolve()
	end)
	
	:andThen(function()
		return Promise.all({
			startService(NetworkHandler, "NetworkHandler"),
			startService(CmdrService, "CmdrService"),  -- ✅ เพิ่มบรรทัดนี้
		}):timeout(TIMEOUTS.LayerStart)
	end)
	
	:andThen(function()
		return Promise.all({
			startService(PocketBaseService, "PocketBaseService"),
			startService(PlayerDataService, "PlayerDataService"),
		}):timeout(TIMEOUTS.LayerStart)
	end)
	
	:andThen(function()
		return startService(PlayerStateService, "PlayerStateService")
			:timeout(TIMEOUTS.LayerStart)
	end)
	
	:andThen(function()
		return Promise.all({
			startService(LobbyService, "LobbyService"),
			startService(ArenaService, "ArenaService"),
			startService(CombatService, "CombatService"),
			startService(DeathService, "DeathService"),
			startService(DownedService, "DownedService"),
			startService(RespawnService, "RespawnService"),
			startService(MatchService, "MatchService"),
			startService(CooldownService, "CooldownService"),
			startService(GameService, "GameService"),
		}):timeout(TIMEOUTS.LayerStart)
	end)
	
	:andThen(function()
		return startService(TestService, "TestService")
			:timeout(TIMEOUTS.LayerStart)
			:catch(function(err)
				warn(`[Init] ⚠️ TestService start failed: {err}`)
				return Promise.resolve()
			end)
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- FINALIZE
	-- ═══════════════════════════════════════════════════════════
	
	:andThen(function()
		_G.__SERVER_INITIALIZED = true
		_G.__SERVER_INIT_TIME = bootStartTime
		
		local bootTime = os.clock() - bootStartTime
		
		print("\n═════════════════════════════════════════════════════════")
		print("✅ All services initialized and started successfully.")
		print(string.format("⏱️ Total boot time: %.3fs", bootTime))
		print("═════════════════════════════════════════════════════════")
		
		-- Print layer breakdown
		print("\n📊 Layer Timing Breakdown:")
		print("─────────────────────────────────────────────────────────")
		for layer, time in pairs(layerTimes) do
			local percentage = (time / bootTime) * 100
			print(string.format("  %s: %.3fs (%.1f%%)", layer, time, percentage))
		end
		print("─────────────────────────────────────────────────────────\n")
		
		-- Print summaries
		if IdempotentGuard and IdempotentGuard.printSummary then
			IdempotentGuard.printSummary()
		end
		
		ServiceLocator:PrintRegistry()
		DataMapper.PrintSchemas()
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- ERROR HANDLING
	-- ═══════════════════════════════════════════════════════════
	
	:catch(function(err)
		error(`[Init] ❌ CRITICAL ERROR during boot: {err}`)
		
		-- Optionally: Attempt graceful shutdown
		-- for _, player in ipairs(Players:GetPlayers()) do
		-- 	player:Kick("Server failed to start. Please rejoin.")
		-- end
	end)
	
	-- ═══════════════════════════════════════════════════════════
	-- FINALLY (always runs)
	-- ═══════════════════════════════════════════════════════════
	
	:finally(function()
		print(`\n⏱️  Boot completed at: {os.date("%X", os.time())}`)
		
		-- Expose for debugging (only in Studio)
		if game:GetService("RunService"):IsStudio() then
			_G.Services = {
				NetworkHandler = NetworkHandler,
				CmdrService = CmdrService,  -- ✅ เพิ่มบรรทัดนี้
				
				-- Data
				PlayerDataService = PlayerDataService,
				
				-- Player
				PlayerStateService = PlayerStateService,
				
				-- Gameplay
				ArenaService = ArenaService,
				CombatService = CombatService,
				CooldownService = CooldownService,
				DeathService = DeathService,
				DownedService = DownedService,
				GameService = GameService,
				LobbyService = LobbyService,
				MatchService = MatchService,
				RespawnService = RespawnService,
				
				-- Cloud
				PocketBaseService = PocketBaseService,
				
				-- Test
				TestService = TestService,
			}
			
			-- ✅ Add new utilities
			_G.ServiceLocator = ServiceLocator
			_G.DataMapper = DataMapper
			_G.IdempotencyKey = IdempotencyKey
			_G.Promise = Promise
			
			if IdempotentGuard then
				_G.IdempotentGuard = IdempotentGuard
			end
			
			print("[Init] 🔍 Debug mode: _G.Services exposed")
		end
	end)