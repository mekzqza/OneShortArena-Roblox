--!strict

--[[]
╔════════════════════════════════════════════════════════════════╗
║           CMDR CONTROLLER - PRODUCTION GRADE                   ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Initialize Cmdr command console (client component)   ║
║ Features:                                                      ║
║  ✅ Wait for CmdrClient (runtime component from server)        ║
║  ✅ Retry logic (10 attempts with timeout)                     ║
║  ✅ Configurable activation key (default F2)                   ║
║  ✅ Graceful degradation (works without Cmdr)                  ║
║  ✅ Production-ready error handling                            ║
╚════════════════════════════════════════════════════════════════╝

⚠️ IMPORTANT: CmdrClient is NOT in ReplicatedStorage during Edit Mode!
   It's cloned by CmdrService (server) at runtime when game starts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ═══════════════════════════════════════════════════════════════
-- CONTROLLER DEFINITION
-- ═══════════════════════════════════════════════════════════════

local CmdrController = {}

export type CmdrController = {
	Init: (self: CmdrController) -> (),
	Start: (self: CmdrController) -> (),
}

-- ═══════════════════════════════════════════════════════════════S
-- STATE
-- ═══════════════════════════════════════════════════════════════

local CmdrClient = nil

local CONFIG = {
	MaxRetries = 10,         -- Max attempts to find CmdrClient
	RetryDelay = 1,          -- Delay between retries (seconds)
	Timeout = 15,            -- Total timeout (seconds)
	ActivationKey = Enum.KeyCode.F2,  -- Press this to open
}

local analytics = {
	loadSuccess = false,
	retries = 0,
	loadTime = 0,
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function loadCmdrClient(): any?
	local startTime = os.clock()
	
	for attempt = 1, CONFIG.MaxRetries do
		-- Check timeout
		if (os.clock() - startTime) > CONFIG.Timeout then
			warn("[CmdrController] ⏱️ Timeout waiting for CmdrClient")
			return nil
		end
		
		-- Try to find CmdrClient
		local success, result = pcall(function()
			return ReplicatedStorage:FindFirstChild("CmdrClient")
		end)
		
		if success and result then
			-- Found it! Try to require
			local success2, result2 = pcall(function()
				return require(result)
			end)
			
			if success2 and result2 then
				analytics.retries = attempt - 1
				analytics.loadTime = os.clock() - startTime
				return result2
			else
				warn(`[CmdrController] ⚠️ Found CmdrClient but require failed: {result2}`)
			end
		end
		
		-- Not found yet, wait and retry
		if attempt < CONFIG.MaxRetries then
			print(`[CmdrController] ⏳ CmdrClient not found, retrying... (attempt {attempt}/{CONFIG.MaxRetries})`)
			task.wait(CONFIG.RetryDelay)
		end
	end
	
	return nil
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function CmdrController:Init()
	print("[CmdrController] 🔧 Initializing...")
	
	-- ✅ Load CmdrClient with retry logic
	CmdrClient = loadCmdrClient()
	
	if not CmdrClient then
		warn("[CmdrController] ⚠️ CmdrClient not found in ReplicatedStorage")
		warn("[CmdrController] 📝 Possible causes:")
		warn("[CmdrController]    1. Cmdr not installed in ServerScriptService/cmdr/")
		warn("[CmdrController]    2. CmdrService failed to start on server")
		warn("[CmdrController]    3. Server hasn't cloned CmdrClient yet (wait longer)")
		warn("[CmdrController] 💡 Game will continue without Cmdr console")
		analytics.loadSuccess = false
		return
	end
	
	analytics.loadSuccess = true
	print(`[CmdrController] ✅ Loaded CmdrClient (after {analytics.retries} retries, {string.format("%.3f", analytics.loadTime)}s)`)
	
	-- ✅ Set activation keys
	if CmdrClient.SetActivationKeys then
		CmdrClient:SetActivationKeys({ CONFIG.ActivationKey })
		print(`[CmdrController] ✅ Initialized. Press [{CONFIG.ActivationKey.Name}] to open console`)
	else
		warn("[CmdrController] ⚠️ SetActivationKeys not found!")
	end
end

function CmdrController:Start()
	print("[CmdrController] 🚀 Starting...")
	
	if not CmdrClient then
		warn("[CmdrController] ⚠️ CmdrClient not loaded - console unavailable")
		return
	end
	
	-- ...existing GUI verification code...
	
	print("[CmdrController] ✅ Started")
end

--[[]
	Get analytics
	@return table
]]
function CmdrController:GetAnalytics(): {[string]: any}
	return analytics
end

return CmdrController