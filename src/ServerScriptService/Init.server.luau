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

-- Get Services folder
local Services = ServerScriptService:WaitForChild("Services")
local utils = ServerScriptService:WaitForChild("Utils")

-- ✅ Preload NetworkConfig
local Configs = ServerStorage:WaitForChild("Configs")
local NetworkConfig = require(Configs.NetworkConfig)

print("[Init] 📡 Loaded NetworkConfig")
NetworkConfig.PrintSummary()

-- Load core services in dependency order
local NetworkHandler = require(Services.NetworkHandler)
local LobbyService = require(Services.LobbyService)
local ArenaService = require(Services.ArenaService)
local PlayerStateService = require(Services.PlayerStateService)
local DeathService = require(Services.DeathService)
local MatchService = require(Services.MatchService)  -- ✅ เพิ่ม
local GameService = require(Services.GameService)
local TestService = require(Services.TestService)

--load utils for idempotent guard service
local IdempotentGuard  = require(utils.IdempotentGuard)


-- Initialize core services
print("[Init] Initializing NetworkHandler...")
NetworkHandler:Init()

print("[Init] Initializing LobbyService...")
LobbyService:Init()

print("[Init] Initializing ArenaService...")  -- ✅ เพิ่ม
ArenaService:Init()

print("[Init] Initializing PlayerStateService...")
PlayerStateService:Init()

print("[Init] Initializing DeathService...")  -- ✅ เพิ่ม
DeathService:Init()

print("[Init] Initializing MatchService...")  -- ✅ เพิ่ม
MatchService:Init()

print("[Init] Initializing GameService...")
GameService:Init()

print("[Init] Initializing TestService...")
TestService:Init()

-- Start services (runtime phase)
print("[Init] Starting services...")
NetworkHandler:Start()
LobbyService:Start()
ArenaService:Start()  -- ✅ เพิ่ม
PlayerStateService:Start()
DeathService:Start()  -- ✅ เพิ่ม
MatchService:Start()  -- ✅ เพิ่ม
GameService:Start()
TestService:Start()

-- ═══════════════════════════════════════════════════════════════
-- FINALIZE
-- ═══════════════════════════════════════════════════════════════

_G.__SERVER_INITIALIZED = true
_G.__SERVER_INIT_TIME = os.clock()

print("✅ All services initialized and started successfully.")

-- ✅ Print IdempotentGuard summary (if available)
if IdempotentGuard and IdempotentGuard.printSummary then
    IdempotentGuard.printSummary()
end

-- Expose for debugging (only in Studio)
if game:GetService("RunService"):IsStudio() then
    if IdempotentGuard then
        _G.IdempotentGuard = IdempotentGuard
    end
end