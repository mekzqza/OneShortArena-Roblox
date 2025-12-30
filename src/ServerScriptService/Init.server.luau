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

-- ✅ Preload NetworkConfig
local Configs = ServerStorage:WaitForChild("Configs")
local NetworkConfig = require(Configs.NetworkConfig)

print("[Init] 📡 Loaded NetworkConfig")
NetworkConfig.PrintSummary()

-- ═══════════════════════════════════════════════════════════════
-- LOAD SERVICES (NEW STRUCTURE)
-- ═══════════════════════════════════════════════════════════════

-- Core Services
print("[Init] Loading Core services...")
local NetworkHandler = require(Core.NetworkHandler)

-- Gameplay Services
print("[Init] Loading Gameplay services...")
local ArenaService = require(Gameplay.ArenaService)
local CooldownService = require(Gameplay.CooldownService)
local DeathService = require(Gameplay.DeathService)
local GameService = require(Gameplay.GameService)
local LobbyService = require(Gameplay.LobbyService)
local MatchService = require(Gameplay.MatchService)

-- Player Services
print("[Init] Loading Player services...")
local PlayerStateService = require(Player.PlayerStateService)

local TestService = require(Services.TestService)

-- Utils
print("[Init] Loading Utils...")
local IdempotentGuard = require(Utils.IdempotentGuard)

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZE SERVICES (DEPENDENCY ORDER)
-- ═══════════════════════════════════════════════════════════════

print("\n[Init] 🔧 Initializing services...")
print("═════════════════════════════════════════════════════════")

-- 1. Core Services (no dependencies)
print("[Init] 1️⃣ Core Layer...")
NetworkHandler:Init()

-- 2. Player Services (depend on Core)
print("[Init] 2️⃣ Player Layer...")
PlayerStateService:Init()


-- 3. Gameplay Services (depend on Player)
print("[Init] 3️⃣ Gameplay Layer...")
LobbyService:Init()
ArenaService:Init()
DeathService:Init()
MatchService:Init()
CooldownService:Init()
GameService:Init()

-- 4. Test/Debug Services (optional, last)
print("[Init] 4️⃣ Test Layer...")
TestService:Init()

-- ═══════════════════════════════════════════════════════════════
-- START SERVICES (RUNTIME PHASE)
-- ═══════════════════════════════════════════════════════════════

print("\n[Init] ▶️ Starting services...")
print("═════════════════════════════════════════════════════════")

-- Start in same order as Init
NetworkHandler:Start()

PlayerStateService:Start()


LobbyService:Start()
ArenaService:Start()
DeathService:Start()
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

-- ✅ Print IdempotentGuard summary (if available)
if IdempotentGuard and IdempotentGuard.printSummary then
	IdempotentGuard.printSummary()
end

-- Expose for debugging (only in Studio)
if game:GetService("RunService"):IsStudio() then
	_G.Services = {
		-- Core
		NetworkHandler = NetworkHandler,
		
		-- Player
		PlayerStateService = PlayerStateService,
		
		-- Gameplay
		ArenaService = ArenaService,
		CooldownService = CooldownService,
		DeathService = DeathService,
		GameService = GameService,
		LobbyService = LobbyService,
		MatchService = MatchService,
		
		-- Test
		TestService = TestService,
	}
	
	if IdempotentGuard then
		_G.IdempotentGuard = IdempotentGuard
	end
	
	print("[Init] 🔍 Debug mode: _G.Services exposed")
end