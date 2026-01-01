--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

-- ═══════════════════════════════════════════════════════════════
-- IDEMPOTENT GUARD
-- ═══════════════════════════════════════════════════════════════

if _G.__SERVER_INITIALIZED then
	warn("[Init.server] ⚠️ Server already initialized! Skipping re-initialization.")
	return
end

print("🔌 Server Init: Starting Services...")

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

-- ✅ Preload NetworkConfig
local Configs = ServerStorage:WaitForChild("Configs")
local NetworkConfig = require(Configs.NetworkConfig)

print("[Init] 📡 Loaded NetworkConfig")
NetworkConfig.PrintSummary()

-- ═══════════════════════════════════════════════════════════════
-- LOAD SERVICES
-- ═══════════════════════════════════════════════════════════════

-- Core Services
print("[Init] Loading Core services...")
local NetworkHandler = require(Core.NetworkHandler)

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
-- INITIALIZE SERVICES (DEPENDENCY ORDER)
-- ═══════════════════════════════════════════════════════════════

print("\n[Init] 🔧 Initializing services...")
print("═════════════════════════════════════════════════════════")

-- 1. Core Services (no dependencies)
print("[Init] 1️⃣ Core Layer...")
NetworkHandler:Init()

-- 2. Cloud Services (depend on Core, before Data)
print("[Init] 2️⃣ Cloud Layer...")
PocketBaseService:Init()

-- 3. Data Services (depend on Cloud)
print("[Init] 3️⃣ Data Layer...")
PlayerDataService:Init()

-- 4. Player Services (depend on Data)
print("[Init] 4️⃣ Player Layer...")
PlayerStateService:Init()


-- 5. Gameplay Services (depend on Player)
print("[Init] 5️⃣ Gameplay Layer...")
LobbyService:Init()
ArenaService:Init()
CombatService:Init()
DeathService:Init()
DownedService:Init()
RespawnService:Init()
MatchService:Init()
CooldownService:Init()
GameService:Init()

-- 6. Test/Debug Services (optional, last)
print("[Init] 6️⃣ Test Layer...")
TestService:Init()

-- ═══════════════════════════════════════════════════════════════
-- REGISTER SERVICES IN LOCATOR (after Init, before Start)
-- ═══════════════════════════════════════════════════════════════

print("\n[Init] 📋 Registering services in ServiceLocator...")

ServiceLocator:Register("NetworkHandler", NetworkHandler)
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

-- ═══════════════════════════════════════════════════════════════
-- START SERVICES (RUNTIME PHASE)
-- ═══════════════════════════════════════════════════════════════

print("\n[Init] ▶️ Starting services...")
print("═════════════════════════════════════════════════════════")

-- Start in same order as Init
NetworkHandler:Start()

PocketBaseService:Start()
PlayerDataService:Start()
PlayerStateService:Start()


LobbyService:Start()
ArenaService:Start()
CombatService:Start()   -- ✅ NEW
DeathService:Start()
DownedService:Start()
RespawnService:Start()  -- ✅ NEW
MatchService:Start()
CooldownService:Start()
GameService:Start()

TestService:Start()

-- ═══════════════════════════════════════════════════════════════
-- FINALIZE
-- ═══════════════════════════════════════════════════════════════

_G.__SERVER_INITIALIZED = true
_G.__SERVER_INIT_TIME = os.clock()

print("\n═════════════════════════════════════════════════════════")
print("✅ All services initialized and started successfully.")
print(string.format("⏱️ Total time: %.3fs", os.clock() - (_G.__SERVER_INIT_TIME or 0)))
print("═════════════════════════════════════════════════════════\n")

-- ✅ Print summaries
if IdempotentGuard and IdempotentGuard.printSummary then
	IdempotentGuard.printSummary()
end

ServiceLocator:PrintRegistry()
DataMapper.PrintSchemas()

-- Expose for debugging (only in Studio)
if game:GetService("RunService"):IsStudio() then
	_G.Services = {
		-- Core
		NetworkHandler = NetworkHandler,
		
		-- Data
		PlayerDataService = PlayerDataService,  -- ✅ NEW
		
		-- Player
		PlayerStateService = PlayerStateService,
		
		-- Gameplay
		ArenaService = ArenaService,
		CombatService = CombatService,     -- ✅ NEW
		CooldownService = CooldownService,
		DeathService = DeathService,
		DownedService = DownedService,
		GameService = GameService,
		LobbyService = LobbyService,
		MatchService = MatchService,
		RespawnService = RespawnService,   -- ✅ NEW
		
		-- Cloud
		PocketBaseService = PocketBaseService,  -- ✅ NEW
		
		-- Test
		TestService = TestService,
	}
	
	-- ✅ Add new utilities
	_G.ServiceLocator = ServiceLocator
	_G.DataMapper = DataMapper
	_G.IdempotencyKey = IdempotencyKey
	
	if IdempotentGuard then
		_G.IdempotentGuard = IdempotentGuard
	end
	
	print("[Init] 🔍 Debug mode: _G.Services exposed")
end