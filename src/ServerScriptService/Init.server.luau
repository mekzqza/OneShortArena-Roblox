--!strict

local ServerScriptService = game:GetService("ServerScriptService")

print("🔌 Server Init: Starting Services...")

-- Get Services folder
local Services = ServerScriptService:WaitForChild("Services")

-- Load core services in dependency order
local NetworkHandler = require(Services.NetworkHandler)
local GameService = require(Services.GameService)
local ArenaService = require(Services.ArenaService)

-- Initialize core services
print("[Init] Initializing NetworkHandler...")
NetworkHandler:Init()

print("[Init] Initializing GameService...")
GameService:Init()

print("[Init] Initializing ArenaService...")
ArenaService:Init()


-- Start services (runtime phase)
print("[Init] Starting services...")
NetworkHandler:Start()
GameService:Start()
ArenaService:Start()

print("✅ All services initialized and started successfully.")