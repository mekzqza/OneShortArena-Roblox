--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║           SERVICE LOCATOR - CIRCULAR DEPENDENCY FIX            ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Centralized service registry to prevent circular deps ║
║ Features:                                                      ║
║  ✅ Lazy loading - Services loaded on first access             ║
║  ✅ Circular dep prevention - No direct require between svcs   ║
║  ✅ Type-safe access - Get services by name                    ║
║  ✅ Debug support - List all registered services               ║
╚════════════════════════════════════════════════════════════════╝

USAGE:
  -- Register (in Init.server.luau after loading)
  ServiceLocator:Register("PlayerDataService", PlayerDataService)
  
  -- Get (anywhere in code)
  local PDS = ServiceLocator:Get("PlayerDataService")
  
  -- Or lazy get with callback
  ServiceLocator:GetAsync("PlayerDataService", function(service)
      service:DoSomething()
  end)
]]

local ServiceLocator = {}

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type ServiceLocator = {
	Register: (self: ServiceLocator, name: string, service: any) -> (),
	Get: (self: ServiceLocator, name: string) -> any?,
	GetAsync: (self: ServiceLocator, name: string, callback: (service: any) -> (), timeout: number?) -> (),
	Has: (self: ServiceLocator, name: string) -> boolean,
	WaitFor: (self: ServiceLocator, name: string, timeout: number?) -> any?,
	GetAll: (self: ServiceLocator) -> {[string]: any},
	PrintRegistry: (self: ServiceLocator) -> (),
}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local registry: {[string]: any} = {}
local pendingCallbacks: {[string]: {(service: any) -> ()}} = {}

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

--[[
    Register a service in the locator
    @param name string - Unique service name
    @param service any - Service instance
]]
function ServiceLocator:Register(name: string, service: any)
	if registry[name] then
		warn(`[ServiceLocator] ⚠️ Service '{name}' already registered, overwriting`)
	end
	
	registry[name] = service
	print(`[ServiceLocator] ✅ Registered: {name}`)
	
	-- Fire pending callbacks
	if pendingCallbacks[name] then
		for _, callback in ipairs(pendingCallbacks[name]) do
			task.spawn(callback, service)
		end
		pendingCallbacks[name] = nil
	end
end

--[[
    Get a service by name (returns nil if not found)
    @param name string - Service name
    @return any? - Service instance or nil
]]
function ServiceLocator:Get(name: string): any?
	return registry[name]
end

--[[
    Get a service asynchronously (waits if not registered yet)
    @param name string - Service name
    @param callback function - Called when service is available
    @param timeout number? - Max wait time (default 10s)
]]
function ServiceLocator:GetAsync(name: string, callback: (service: any) -> (), timeout: number?)
	-- Already registered
	if registry[name] then
		task.spawn(callback, registry[name])
		return
	end
	
	-- Add to pending
	if not pendingCallbacks[name] then
		pendingCallbacks[name] = {}
	end
	table.insert(pendingCallbacks[name], callback)
	
	-- Timeout handler
	timeout = timeout or 10
	task.delay(timeout, function()
		if not registry[name] then
			warn(`[ServiceLocator] ⏱️ Timeout waiting for '{name}' ({timeout}s)`)
			-- Remove callback
			if pendingCallbacks[name] then
				local index = table.find(pendingCallbacks[name], callback)
				if index then
					table.remove(pendingCallbacks[name], index)
				end
			end
		end
	end)
end

--[[
    Check if a service is registered
    @param name string - Service name
    @return boolean
]]
function ServiceLocator:Has(name: string): boolean
	return registry[name] ~= nil
end

--[[
    Wait for a service to be registered (blocking)
    @param name string - Service name
    @param timeout number? - Max wait time (default 10s)
    @return any? - Service instance or nil
]]
function ServiceLocator:WaitFor(name: string, timeout: number?): any?
	timeout = timeout or 10
	local startTime = os.clock()
	
	while not registry[name] do
		if (os.clock() - startTime) > timeout then
			warn(`[ServiceLocator] ⏱️ Timeout waiting for '{name}'`)
			return nil
		end
		task.wait(0.1)
	end
	
	return registry[name]
end

--[[
    Get all registered services
    @return {[string]: any}
]]
function ServiceLocator:GetAll(): {[string]: any}
	return registry
end

--[[
    Print all registered services
]]
function ServiceLocator:PrintRegistry()
	print("╔════════════════════════════════════════════════════════════════╗")
	print("║              SERVICE LOCATOR REGISTRY                          ║")
	print("╠════════════════════════════════════════════════════════════════╣")
	
	local count = 0
	for name, _ in pairs(registry) do
		count += 1
		print(`║ ✅ {name}`)
	end
	
	print("╠════════════════════════════════════════════════════════════════╣")
	print(`║ Total Services: {count}`)
	print("╚════════════════════════════════════════════════════════════════╝")
end

return ServiceLocator
