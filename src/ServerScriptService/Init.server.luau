--!strict

local ServerScriptService = game:GetService("ServerScriptService")

print("🔌 Server Init: Starting Services...")

-- Get Services folder
local Services = ServerScriptService:WaitForChild("Services")

-- Production mode flag
local IS_PRODUCTION = true -- เปลี่ยนเป็น true เมื่อ deploy

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

-- Load demo service only in development
local DemoService
if not IS_PRODUCTION then
    DemoService = require(Services.DemoService)
    print("[Init] Initializing DemoService...")
    DemoService:Init()
end

-- Start services (runtime phase)
print("[Init] Starting services...")
NetworkHandler:Start()
GameService:Start()
ArenaService:Start()

if DemoService then
    DemoService:Start()
    print("🎮 Demo Mode: Use DemoController methods to test")
end

print("✅ All services initialized and started successfully.")