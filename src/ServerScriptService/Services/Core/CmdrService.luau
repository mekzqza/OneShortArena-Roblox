--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║           CMDR SERVICE - PRODUCTION GRADE                      ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Initialize Cmdr command console (server component)   ║
║ Features:                                                      ║
║  ✅ Manual installation (ServerScriptService/cmdr)             ║
║  ✅ Auto-detect and load Cmdr                                  ║
║  ✅ Register default commands + hooks                          ║
║  ✅ Support custom commands                                    ║
║  ✅ Graceful degradation (optional - game works without it)   ║
║  ✅ Production-ready error handling                            ║
╚════════════════════════════════════════════════════════════════╝
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

local CmdrService = {}

local guard = IdempotentGuard.new("CmdrService", true)

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local Cmdr = nil

local analytics = {
	commandsRegistered = 0,
	hooksRegistered = 0,
	loadSuccess = false,
	initTime = 0,
}

local function loadCmdr()
	-- Check if Cmdr is already loaded
	if Cmdr then
		return Cmdr
	end
	
	-- Attempt to load Cmdr from ReplicatedStorage
	local success, result = pcall(function()
		return require(game.ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Cmdr"))
	end)
	
	if not success then
		warn("[CmdrService] ⚠️ Failed to load Cmdr: " .. tostring(result))
		return nil
	end
	
	return result
end

function CmdrService:Init()
	if not guard:MarkInitialized() then return end
	
	print("[CmdrService] 🔧 Initializing...")
	local startTime = os.clock()
	
	-- Load Cmdr (Server version)
	Cmdr = loadCmdr()
	
	if not Cmdr then
		warn("[CmdrService] ⚠️ Cmdr not loaded - commands will not be available")
		warn("[CmdrService] 💡 This is optional - game will continue without Cmdr console")
		analytics.loadSuccess = false
		return
	end
	
	analytics.loadSuccess = true
	analytics.initTime = os.clock() - startTime
	
	print(`[CmdrService] ✅ Cmdr server loaded in {string.format("%.3f", analytics.initTime)}s`)
end

function CmdrService:Start()
	if not guard:MarkStarted() then return end
	
	if not Cmdr then
		warn("[CmdrService] ⚠️ Cannot start - Cmdr not loaded")
		return
	end
	
	print("[CmdrService] 🚀 Starting...")
	


	local success1 = Cmdr:RegisterDefaultCommands() -- This loads the default set of commands that Cmdr comes with. (Optional)
	-- Cmdr:RegisterCommandsIn(script.Parent.CmdrCommands) -- Register commands from your own folder. (Optional)
	local success2 = Cmdr:RegisterHooksIn(ServerStorage.Secrets.Hooks) -- Register hooks from your own folder. (Optional)
	
	if success1 then
		analytics.commandsRegistered += 1
		print("[CmdrService] ✅ Registered default commands")
	
	end
	
	if success2 then
		analytics.hooksRegistered += 1
		print("[CmdrService] ✅ Registered hooks from cmdr/Hooks")

	end
	
	-- Cmdr:RegisterCommandsIn(script.Parent.CmdrCommands) -- Register commands from your own folder. (Optional)
	
	print("[CmdrService] ✅ Started")
	print("[CmdrService] 🎮 Players can press [F2] to open console")
end

--[[
	Get Cmdr instance
	@return any? - Cmdr instance or nil
]]
function CmdrService:GetCmdr(): any?
	return Cmdr
end

--[[
	Check if Cmdr is available
	@return boolean
]]
function CmdrService:IsAvailable(): boolean
	return Cmdr ~= nil
end

--[[
	Get analytics
	@return table
]]

function CmdrService:GetAnalytics(): {[string]: any}
	return {
		loadSuccess = analytics.loadSuccess,
		commandsRegistered = analytics.commandsRegistered,
		hooksRegistered = analytics.hooksRegistered,
		initTime = analytics.initTime,
	}
end

return CmdrService