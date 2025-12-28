--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║         EVENTBUS MODULE - PRODUCTION GRADE (Signal-Based)      ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Type-safe event communication system                 ║
║ Features:                                                      ║
║  ✅ Uses Signal library (Production-grade)                    ║
║  ✅ Type-safe event handling                                  ║
║  ✅ Memory-efficient cleanup                                  ║
║  ✅ Enhanced error messages                                   ║
║  ✅ Analytics tracking                                        ║
║  ✅ Connection management                                     ║
╚════════════════════════════════════════════════════════════════╝

📖 ตัวอย่างการใช้งาน:

-- การสมัครรับฟังอีเวนต์
local connection = EventBus:On("PlayerJoined", function(playerName, level)
	print(playerName .. " joined with level " .. level)
end)

-- การส่งอีเวนต์
EventBus:Emit("PlayerJoined", "John", 5)

-- การสมัครรับฟังแค่ครั้งเดียว
EventBus:Once("GameStarted", function()
	print("Game has started!")
end)

-- การถอนการสมัคร
connection:Disconnect()

-- การถอนการสมัครทั้งหมดของอีเวนต์
EventBus:Off("PlayerJoined")

💡 Best Practices:
- ตั้งชื่ออีเวนต์ให้มีความหมายชัด
- ใช้ Once สำหรับอีเวนต์ที่เกิดครั้งเดียว
- ทำ cleanup ด้วย Disconnect() หรือ Off()
- ใช้ GetEventNames() เพื่อ debug
]]

-- ═══════════════════════════════════════════════════════════════
-- DEPENDENCIES
-- ═══════════════════════════════════════════════════════════════

local Signal = require(game.ReplicatedStorage.Packages.Signal)

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

type EventCallback = (...any) -> ()
type SignalConnection = typeof(Signal.new():Connect(function() end))

export type EventBus = {
	-- Core methods
	On: (self: EventBus, eventName: string, callback: EventCallback) -> SignalConnection,
	Once: (self: EventBus, eventName: string, callback: EventCallback) -> SignalConnection,
	Emit: (self: EventBus, eventName: string, ...any) -> (),
	Off: (self: EventBus, eventName: string) -> (),
	
	-- Utilities
	Clear: (self: EventBus) -> (),
	GetEventNames: (self: EventBus) -> {string},
	GetListenerCount: (self: EventBus, eventName: string) -> number,
	GetAnalytics: (self: EventBus) -> {[string]: any},
	
	-- Internal
	_signals: {[string]: any},
	_analytics: {[string]: any},
}

local EventBus = {} :: EventBus
EventBus._signals = {}

-- ═══════════════════════════════════════════════════════════════
-- ANALYTICS
-- ═══════════════════════════════════════════════════════════════

EventBus._analytics = {
	totalEvents = 0,
	totalEmits = 0,
	eventCounts = {} :: {[string]: {subscribes: number, emits: number}},
	errors = {} :: {{timestamp: number, event: string, error: string}},
	startTime = os.clock(),
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function getSignal(eventName: string)
	if not EventBus._signals[eventName] then
		EventBus._signals[eventName] = Signal.new()
		EventBus._analytics.totalEvents += 1
		
		-- Track event creation
		if not EventBus._analytics.eventCounts[eventName] then
			EventBus._analytics.eventCounts[eventName] = {
				subscribes = 0,
				emits = 0,
			}
		end
	end
	return EventBus._signals[eventName]
end

local function validateEventName(eventName: any, functionName: string)
	if type(eventName) ~= "string" then
		-- Enhanced error message
		warn("╔════════════════════════════════════════════════════════════════╗")
		warn(`║          ❌ EventBus:{functionName}() - Invalid Event Name        ║`)
		warn("╠════════════════════════════════════════════════════════════════╣")
		warn(string.format("║ Expected: string                                               ║"))
		warn(string.format("║ Got:      %-55s ║", type(eventName)))
		warn(string.format("║ Value:    %-55s ║", tostring(eventName)))
		warn("╠════════════════════════════════════════════════════════════════╣")
		warn("║ 💡 Common Issues:                                              ║")
		warn("║   • Event not defined in Events.luau                           ║")
		warn("║   • Typo in event name (e.g., Events.GAEM_START)              ║")
		warn("║   • Using nil or undefined variable                            ║")
		warn("╠════════════════════════════════════════════════════════════════╣")
		warn("║ 📍 Stack Trace:                                                ║")
		
		local stack = debug.traceback("", 3)
		for line in stack:gmatch("[^\r\n]+") do
			warn("║ " .. line)
		end
		
		warn("╚════════════════════════════════════════════════════════════════╝")
		
		error(string.format(
			"EventBus:%s() - eventName must be a string, got %s (value: %s)",
			functionName,
			type(eventName),
			tostring(eventName)
		), 3)
	end
end

local function trackError(eventName: string, errorMsg: string)
	table.insert(EventBus._analytics.errors, {
		timestamp = os.clock(),
		event = eventName,
		error = errorMsg,
	})
	
	-- Keep only last 100 errors
	if #EventBus._analytics.errors > 100 then
		table.remove(EventBus._analytics.errors, 1)
	end
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

--[[
	On: Subscribe to event
	
	@param eventName string - Event name to listen to
	@param callback function - Function to call when event fires
	@return SignalConnection - Connection object (call :Disconnect() to unsubscribe)
	
	Example:
		local conn = EventBus:On("PlayerDied", function(playerName)
			print(playerName .. " died")
		end)
		
		-- Later: conn:Disconnect()
]]
function EventBus:On(eventName: string, callback: EventCallback): SignalConnection
	validateEventName(eventName, "On")
	assert(type(callback) == "function", "callback must be a function")
	
	local signal = getSignal(eventName)
	
	-- Track subscription
	EventBus._analytics.eventCounts[eventName].subscribes += 1
	
	-- Connect with error handling
	local connection
	connection = signal:Connect(function(...)
		local success, err = pcall(callback, ...)
		if not success then
			trackError(eventName, tostring(err))
			warn(string.format(
				"[EventBus] ❌ Error in listener for '%s': %s",
				eventName,
				tostring(err)
			))
		end
	end)
	
	return connection
end

--[[
	Once: Subscribe to event (fires only once)
	
	@param eventName string - Event name
	@param callback function - Function to call
	@return SignalConnection - Connection (auto-disconnects after first fire)
	
	Example:
		EventBus:Once("GameStarted", function()
			print("Game started!")
		end)
]]
function EventBus:Once(eventName: string, callback: EventCallback): SignalConnection
	validateEventName(eventName, "Once")
	assert(type(callback) == "function", "callback must be a function")
	
	local signal = getSignal(eventName)
	
	-- Track subscription
	EventBus._analytics.eventCounts[eventName].subscribes += 1
	
	-- Use Signal's Once method
	local connection
	connection = signal:Once(function(...)
		local success, err = pcall(callback, ...)
		if not success then
			trackError(eventName, tostring(err))
			warn(string.format(
				"[EventBus] ❌ Error in Once listener for '%s': %s",
				eventName,
				tostring(err)
			))
		end
	end)
	
	return connection
end

--[[
	Emit: Fire event with data
	
	@param eventName string - Event name
	@param ... any - Arguments to pass to listeners
	
	Example:
		EventBus:Emit("PlayerJoined", "John", 5, true)
]]
function EventBus:Emit(eventName: string, ...: any)
	validateEventName(eventName, "Emit")
	
	local signal = EventBus._signals[eventName]
	if signal then
		-- Track emit
		EventBus._analytics.totalEmits += 1
		EventBus._analytics.eventCounts[eventName].emits += 1
		
		-- Fire signal (Signal library handles errors internally)
		signal:Fire(...)
	end
	-- If no signal exists, no listeners are registered (silent ignore)
end

--[[
	Off: Disconnect all listeners for event
	
	@param eventName string - Event name
	
	Example:
		EventBus:Off("PlayerJoined")
]]
function EventBus:Off(eventName: string)
	validateEventName(eventName, "Off")
	
	local signal = EventBus._signals[eventName]
	if signal then
		-- Destroy signal (disconnects all connections)
		signal:Destroy()
		EventBus._signals[eventName] = nil
		
		-- Keep analytics data
		EventBus._analytics.totalEvents -= 1
	end
end

--[[
	Clear: Disconnect all events
	
	⚠️ Warning: Removes ALL event listeners!
	
	Example:
		EventBus:Clear()
]]
function EventBus:Clear()
	for eventName, signal in pairs(EventBus._signals) do
		if signal then
			signal:Destroy()
		end
		EventBus._signals[eventName] = nil
	end
	
	-- Reset analytics
	EventBus._analytics.totalEvents = 0
end

--[[
	GetEventNames: Get list of all registered events
	
	@return {string} - Array of event names
	
	Example:
		local events = EventBus:GetEventNames()
		for _, name in ipairs(events) do
			print("Event:", name)
		end
]]
function EventBus:GetEventNames(): {string}
	local names = {}
	for eventName, _ in pairs(EventBus._signals) do
		table.insert(names, eventName)
	end
	return names
end

--[[
	GetListenerCount: Get number of listeners for event
	
	@param eventName string - Event name
	@return number - Number of active listeners
	
	Example:
		local count = EventBus:GetListenerCount("PlayerJoined")
		print("Listeners:", count)
]]
function EventBus:GetListenerCount(eventName: string): number
	validateEventName(eventName, "GetListenerCount")
	
	local signal = EventBus._signals[eventName]
	if signal and signal.GetConnectionCount then
		return signal:GetConnectionCount()
	end
	return 0
end

--[[
	GetAnalytics: Get analytics data
	
	@return table - Analytics data
	
	Example:
		local analytics = EventBus:GetAnalytics()
		print("Total events:", analytics.totalEvents)
		print("Total emits:", analytics.totalEmits)
]]
function EventBus:GetAnalytics(): {[string]: any}
	local uptime = os.clock() - EventBus._analytics.startTime
	
	return {
		totalEvents = EventBus._analytics.totalEvents,
		totalEmits = EventBus._analytics.totalEmits,
		eventCounts = EventBus._analytics.eventCounts,
		errors = EventBus._analytics.errors,
		uptime = uptime,
		emitsPerSecond = uptime > 0 and EventBus._analytics.totalEmits / uptime or 0,
	}
end

-- ═══════════════════════════════════════════════════════════════
-- DEBUG UTILITIES
-- ═══════════════════════════════════════════════════════════════

--[[
	PrintSummary: Print summary of all events (debug)
]]
function EventBus:PrintSummary()
	print("╔════════════════════════════════════════════════════════════════╗")
	print("║                    EVENTBUS SUMMARY                            ║")
	print("╠════════════════════════════════════════════════════════════════╣")
	
	local analytics = self:GetAnalytics()
	print(string.format("║ Total Events: %d", analytics.totalEvents))
	print(string.format("║ Total Emits: %d", analytics.totalEmits))
	print(string.format("║ Emits/sec: %.2f", analytics.emitsPerSecond))
	print(string.format("║ Uptime: %.2fs", analytics.uptime))
	print("╠════════════════════════════════════════════════════════════════╣")
	
	if analytics.totalEvents > 0 then
		print("║ Events:")
		for eventName, stats in pairs(analytics.eventCounts) do
			local listeners = self:GetListenerCount(eventName)
			print(string.format(
				"║   %-30s Listeners: %d, Emits: %d",
				eventName,
				listeners,
				stats.emits
			))
		end
	end
	
	if #analytics.errors > 0 then
		print("╠════════════════════════════════════════════════════════════════╣")
		print(string.format("║ Recent Errors: %d", #analytics.errors))
		for i = math.max(1, #analytics.errors - 5), #analytics.errors do
			local err = analytics.errors[i]
			print(string.format("║   [%.2fs] %s: %s", err.timestamp, err.event, err.error:sub(1, 40)))
		end
	end
	
	print("╚════════════════════════════════════════════════════════════════╝")
end

return EventBus