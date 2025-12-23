--!strict

local ServerScriptService = game:GetService("ServerScriptService")

print("🔌 Server Init: Starting Services...")

-- Get Services folder
local Services = ServerScriptService:WaitForChild("Services")

-- Load core services in dependency order
local NetworkHandler = require(Services.NetworkHandler)
local GameService = require(Services.GameService)
local ArenaService = require(Services.ArenaService)
local CombatService = require(Services.CombatService)


--เอาไว้ทดสอบระบบ
local DemoService = require(Services.DemoService) -- Add demo

-- Initialize services (setup phase)
print("[Init] Initializing NetworkHandler...")
NetworkHandler:Init()

print("[Init] Initializing GameService...")
GameService:Init()

print("[Init] Initializing ArenaService...")
ArenaService:Init()

print("[Init] Initializing CombatService...")
CombatService:Init()

print("[Init] Initializing DemoService...")
DemoService:Init()

-- Start services (runtime phase)
print("[Init] Starting services...")
NetworkHandler:Start()
GameService:Start()
ArenaService:Start()
CombatService:Start()
DemoService:Start()

print("✅ All services initialized and started successfully.")
print("🎮 Demo Mode: Use DemoController methods to test network communication")