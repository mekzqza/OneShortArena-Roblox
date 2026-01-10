--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║           NETWORK CONFIGURATION - PRODUCTION GRADE             ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Centralized network security and performance config  ║
║ Features:                                                      ║
║  ✅ Rate limiting configuration                               ║
║  ✅ Per-event rate limits                                     ║
║  ✅ Security thresholds                                       ║
║  ✅ Network performance tuning                                ║
║  ✅ Anti-spam protection                                      ║
╚════════════════════════════════════════════════════════════════╝
]]

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type NetworkConfig = {

	-- Global rate limits
	GlobalRateLimit: number,
	GlobalRateWindow: number,
	BurstLimit: number,
	BurstWindow: number,

	-- Per-event rate limits
	EventRateLimits: { [string]: { rate: number, window: number } },
	DefaultEventRateLimit: { rate: number, window: number },

	-- Security settings
	MaxStrikes: number,
	MessageIdTTL: number,
	MaxPayloadSize: number,
	MaxStringLength: number,
	MaxTableDepth: number,

	-- Retry & reliability
	DefaultMaxRetries: number,
	RetryDelay: number,
	AckTimeout: number,

	-- Performance
	BatchSize: number,
	BatchInterval: number,

	-- Monitoring
	AnalyticsInterval: number,
	LogLevel: "None" | "Error" | "Warn" | "Info" | "Debug",
}

-- ═══════════════════════════════════════════════════════════════
-- PRODUCTION CONFIGURATION
-- ═══════════════════════════════════════════════════════════════

local NetworkConfig: NetworkConfig = {
	-- ═══════════════════════════════════════════════════════════
	-- GLOBAL RATE LIMITS
	-- ═══════════════════════════════════════════════════════════

	-- Maximum events per player per window
	GlobalRateLimit = 10,
	GlobalRateWindow = 5, -- seconds

	-- Burst protection (rapid consecutive events)
	BurstLimit = 3,
	BurstWindow = 0.5, -- seconds

	-- ═══════════════════════════════════════════════════════════
	-- PER-EVENT RATE LIMITS
	-- ═══════════════════════════════════════════════════════════

	EventRateLimits = {
		-- ─────────────────────────────────────────────────────
		-- ARENA & LOBBY (Very Strict)
		-- ─────────────────────────────────────────────────────
		["PlayerRequestToArena"] = { rate = 1, window = 5 },
		["PlayerRequestToLobby"] = { rate = 1, window = 5 },
		["PlayerRequestToSpectate"] = { rate = 1, window = 5 },

		-- ─────────────────────────────────────────────────────
		-- COMBAT ACTIONS (Moderate)
		-- ─────────────────────────────────────────────────────
		["PlayerAttack"] = { rate = 10, window = 5 },
		["PlayerDefend"] = { rate = 10, window = 5 },
		["PlayerSpecial"] = { rate = 5, window = 5 },
		["PlayerUltimate"] = { rate = 1, window = 10 },
		["PlayerDash"] = { rate = 5, window = 5 },
		["PlayerBlock"] = { rate = 8, window = 5 },

		-- ─────────────────────────────────────────────────────
		-- MOVEMENT (Lenient)
		-- ─────────────────────────────────────────────────────
		["PlayerMove"] = { rate = 30, window = 5 },
		["PlayerJump"] = { rate = 20, window = 5 },
		["PlayerSprint"] = { rate = 15, window = 5 },
		["PlayerCrouch"] = { rate = 10, window = 5 },

		-- ─────────────────────────────────────────────────────
		-- UI & SETTINGS (Moderate)
		-- ─────────────────────────────────────────────────────
		["SettingsChanged"] = { rate = 5, window = 5 },
		["ToggleUI"] = { rate = 10, window = 5 },
		["MenuOpen"] = { rate = 5, window = 5 },
		["MenuClose"] = { rate = 5, window = 5 },

		-- ─────────────────────────────────────────────────────
		-- INVENTORY & SHOP (Strict)
		-- ─────────────────────────────────────────────────────
		["InventoryOpen"] = { rate = 3, window = 5 },
		["ItemPurchase"] = { rate = 1, window = 2 },
		["ItemEquip"] = { rate = 5, window = 5 },
		["ItemDrop"] = { rate = 3, window = 5 },

		-- ─────────────────────────────────────────────────────
		-- SOCIAL (Moderate)
		-- ─────────────────────────────────────────────────────
		["ChatMessage"] = { rate = 5, window = 5 },
		["EmotePlay"] = { rate = 3, window = 5 },
		["FriendRequest"] = { rate = 2, window = 10 },
		["PartyInvite"] = { rate = 2, window = 10 },

		-- ─────────────────────────────────────────────────────
		-- TESTING (Lenient - for development)
		-- ─────────────────────────────────────────────────────
		["TestPing"] = { rate = 20, window = 5 },
		["TestClientButtonClick"] = { rate = 15, window = 5 },
		["DemoPing"] = { rate = 20, window = 5 },

		-- ─────────────────────────────────────────────────────
		-- MATCHMAKING (Strict)
		-- ─────────────────────────────────────────────────────
		["MatchmakingJoin"] = { rate = 1, window = 3 },
		["MatchmakingLeave"] = { rate = 2, window = 5 },
		["MatchmakingReady"] = { rate = 5, window = 5 },
	},

	-- Default for events not in the list
	DefaultEventRateLimit = { rate = 10, window = 5 },

	-- ═══════════════════════════════════════════════════════════
	-- SECURITY SETTINGS
	-- ═══════════════════════════════════════════════════════════

	-- Strike system (kick after X violations)
	MaxStrikes = 5,

	-- Anti-replay protection
	MessageIdTTL = 60, -- seconds (how long to track message IDs)

	-- Payload size limits
	MaxPayloadSize = 10000, -- bytes (10 KB)
	MaxStringLength = 1000, -- characters
	MaxTableDepth = 5, -- nested tables

	-- ═══════════════════════════════════════════════════════════
	-- RETRY & RELIABILITY
	-- ═══════════════════════════════════════════════════════════

	-- Reliable send configuration
	DefaultMaxRetries = 3,
	RetryDelay = 2, -- seconds between retries
	AckTimeout = 5, -- seconds to wait for ACK

	-- ═══════════════════════════════════════════════════════════
	-- PERFORMANCE TUNING
	-- ═══════════════════════════════════════════════════════════

	-- Batch processing (for high-frequency events)
	BatchSize = 10, -- max events per batch
	BatchInterval = 0.033, -- 30 FPS (seconds)

	-- ═══════════════════════════════════════════════════════════
	-- MONITORING & ANALYTICS
	-- ═══════════════════════════════════════════════════════════

	-- How often to print analytics
	AnalyticsInterval = 60, -- seconds

	-- Logging level
	-- "None"  - No logs
	-- "Error" - Only errors
	-- "Warn"  - Errors + warnings
	-- "Info"  - Errors + warnings + info
	-- "Debug" - Everything (use in development only)
	LogLevel = "Warn",
}

-- ═══════════════════════════════════════════════════════════════
-- DEVELOPMENT OVERRIDES (Auto-detect Studio)
-- ═══════════════════════════════════════════════════════════════

local RunService = game:GetService("RunService")

if RunService:IsStudio() then
	-- More lenient in Studio for testing
	NetworkConfig.LogLevel = "Info"
	NetworkConfig.MaxStrikes = 10 -- More forgiving
	NetworkConfig.AnalyticsInterval = 30 -- More frequent

	print("[NetworkConfig] 🛠️ Development mode detected")
	print("  - LogLevel: Info")
	print("  - MaxStrikes: 10")
	print("  - AnalyticsInterval: 30s")
end

-- ═══════════════════════════════════════════════════════════════
-- VALIDATION
-- ═══════════════════════════════════════════════════════════════

local function validateConfig()
	assert(NetworkConfig.GlobalRateLimit > 0, "GlobalRateLimit must be > 0")
	assert(NetworkConfig.GlobalRateWindow > 0, "GlobalRateWindow must be > 0")
	assert(NetworkConfig.MaxStrikes > 0, "MaxStrikes must be > 0")
	assert(NetworkConfig.MessageIdTTL > 0, "MessageIdTTL must be > 0")

	-- Validate each event rate limit
	for eventName, config in pairs(NetworkConfig.EventRateLimits) do
		assert(config.rate > 0, `EventRateLimit for '{eventName}': rate must be > 0`)
		assert(config.window > 0, `EventRateLimit for '{eventName}': window must be > 0`)
	end

	print("[NetworkConfig] ✅ Configuration validated")
end

validateConfig()

-- ═══════════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

function NetworkConfig.GetEventRateLimit(eventName: string): { rate: number, window: number }
	return NetworkConfig.EventRateLimits[eventName] or NetworkConfig.DefaultEventRateLimit
end

function NetworkConfig.SetEventRateLimit(eventName: string, rate: number, window: number)
	NetworkConfig.EventRateLimits[eventName] = { rate = rate, window = window }
	print(`[NetworkConfig] ✅ Set rate limit for '{eventName}': {rate} per {window}s`)
end

function NetworkConfig.PrintSummary()
	print(
		"╔════════════════════════════════════════════════════════════════╗"
	)
	print("║              NETWORK CONFIGURATION SUMMARY                     ║")
	print(
		"╠════════════════════════════════════════════════════════════════╣"
	)
	print(
		string.format(
			"║ Global Rate Limit: %d events / %ds",
			NetworkConfig.GlobalRateLimit,
			NetworkConfig.GlobalRateWindow
		)
	)
	print(string.format("║ Burst Protection: %d events / %.1fs", NetworkConfig.BurstLimit, NetworkConfig.BurstWindow))
	print(string.format("║ Max Strikes: %d", NetworkConfig.MaxStrikes))
	print(string.format("║ Message TTL: %ds", NetworkConfig.MessageIdTTL))
	print(string.format("║ Log Level: %s", NetworkConfig.LogLevel))
	print(
		"╠════════════════════════════════════════════════════════════════╣"
	)
	print(string.format("║ Event Rate Limits: %d configured", #NetworkConfig.EventRateLimits))
	print(
		"╚════════════════════════════════════════════════════════════════╝"
	)
end

-- ═══════════════════════════════════════════════════════════════
-- EXPORT
-- ═══════════════════════════════════════════════════════════════

return table.freeze(NetworkConfig)
