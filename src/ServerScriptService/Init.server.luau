--!strict

local ServerScriptService = game:GetService("ServerScriptService")

print("🔌 Server Init: Starting Services...")

-- Get Services folder
local Services = ServerScriptService:WaitForChild("Services")

-- Load core services
local GameService = require(Services.GameService)
local ArenaService = require(Services.ArenaService)
local CombatService = require(Services.CombatService)
local NetworkHandler = require(Services.NetworkHandler)

-- Initialize in dependency order
NetworkHandler:Init()
GameService:Init()
ArenaService:Init()
CombatService:Init()

print("✅ Services initialized.")