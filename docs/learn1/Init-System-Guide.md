# 🚀 Init System Guide - Complete Setup & Usage

## 📋 Overview

คู่มือนี้อธิบายวิธีการเพิ่ม Service/Controller ใหม่ในระบบ Init ที่ใช้ **Promise**, **Timeout Protection**, และ **Dependency Injection**

---

## 🎯 สิ่งที่ต้องรู้

```
┌─────────────────────────────────────────────────────────────────┐
│  🏗️ INIT SYSTEM ARCHITECTURE                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ⚡ Promise-based Boot                                          │
│  ├─ Parallel Execution (5-10x faster)                          │
│  ├─ Error Handling per layer                                   │
│  └─ Timing Analytics                                            │
│                                                                 │
│  ⏱️ Timeout Protection                                          │
│  ├─ Per-service/controller timeout (10-15s)                    │
│  ├─ Per-layer timeout (30-45s)                                 │
│  └─ Automatic failure detection                                │
│                                                                 │
│  💉 Dependency Injection                                        │
│  ├─ ServiceLocator (Server)                                    │
│  ├─ ControllerLocator (Client)                                 │
│  └─ No circular dependencies                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📂 File Structure

```
src/
├── ServerScriptService/
│   ├── Init.server.luau          ← Server boot script
│   ├── Services/
│   │   ├── Core/                 ← Layer 1 (Sequential)
│   │   ├── Data/                 ← Layer 2 (Sequential)
│   │   ├── Cloud/                ← Layer 3 (Sequential)
│   │   ├── Player/               ← Layer 4 (Sequential)
│   │   └── Gameplay/             ← Layer 5 (Parallel) ⚡
│   └── Utils/
│       └── ServiceLocator.luau   ← DI Container
│
└── StarterPlayer/
    └── StarterPlayerScripts/
        ├── Init.client.luau      ← Client boot script
        ├── Core/                 ← Layer 1 (Sequential)
        ├── Inputs/               ← Layer 2 (Sequential)
        ├── Gameplay/             ← Layer 3 (Parallel) ⚡
        ├── UI/                   ← Layer 3 (Parallel) ⚡
        └── Dev/                  ← Layer 4 (Optional)
```

---

## 🖥️ Server: How to Add a New Service

### 📝 Step 1: Create Service File

````lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\Services\Gameplay\MyNewService.luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- ✅ Use ServiceLocator for dependencies (fix circular deps)
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

local MyNewService = {}

local guard = IdempotentGuard.new("MyNewService", true)

-- ═══════════════════════════════════════════════════════════════
-- DEPENDENCIES (Injected via ServiceLocator)
-- ═══════════════════════════════════════════════════════════════

local PlayerDataService: any = nil
local PlayerStateService: any = nil

-- ═══════════════════════════════════════════════════════════════
-- INIT (Setup, no side effects)
-- ═══════════════════════════════════════════════════════════════

function MyNewService:Init()
	if not guard:MarkInitialized() then return end
	
	print("[MyNewService] 🔧 Initialized")
end

-- ═══════════════════════════════════════════════════════════════
-- START (Connect events, start loops)
-- ═══════════════════════════════════════════════════════════════

function MyNewService:Start()
	if not guard:MarkStarted() then return end
	
	-- ✅ Get dependencies from ServiceLocator
	PlayerDataService = ServiceLocator:Get("PlayerDataService")
	PlayerStateService = ServiceLocator:Get("PlayerStateService")
	
	if not PlayerDataService then
		warn("[MyNewService] ⚠️ PlayerDataService not found!")
	end
	
	-- Connect events
	EventBus:On(Events.SOME_EVENT, function(player, data)
		-- Use dependencies safely
		if PlayerDataService then
			local coins = PlayerDataService:Get(player, "Coins")
			print(`Player has {coins} coins`)
		end
	end)
	
	print("[MyNewService] 🚀 Started")
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function MyNewService:DoSomething(player: Player)
	-- Your logic here
end

return MyNewService
````

---

### 📝 Step 2: Add to Init.server.luau

````lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\Init.server.luau

-- ...existing code (after Gameplay Services section)...

-- Gameplay Services
print("[Init] Loading Gameplay services...")
-- ...existing services...
local MyNewService = require(Gameplay.MyNewService)  -- ✅ ADD THIS

-- ...existing code (in INITIALIZE SERVICES - Gameplay Layer)...

-- 5️⃣ Gameplay Layer (PARALLEL)
:andThen(function()
	print("[Init] 5️⃣ Gameplay Layer (Parallel)...")
	local startTime = os.clock()
	
	return Promise.all({
		-- ...existing services...
		initService(MyNewService, "MyNewService"),  -- ✅ ADD THIS
	})
		:andThen(function()
			layerTimes["Gameplay"] = os.clock() - startTime
			print(`[Init] ⚡ Gameplay Layer completed in {string.format("%.3f", layerTimes["Gameplay"])}s (Parallel)`)
		end)
		:timeout(TIMEOUTS.LayerInit)
end)

-- ...existing code (in REGISTER SERVICES IN LOCATOR)...

:andThen(function()
	print("\n[Init] 📋 Registering services in ServiceLocator...")
	
	-- ...existing registrations...
	ServiceLocator:Register("MyNewService", MyNewService)  -- ✅ ADD THIS
	
	print("[Init] ✅ All services registered")
end)

-- ...existing code (in START SERVICES - Gameplay Layer)...

:andThen(function()
	return Promise.all({
		-- ...existing services...
		startService(MyNewService, "MyNewService"),  -- ✅ ADD THIS
	}):timeout(TIMEOUTS.LayerStart)
end)

-- ...existing code (in FINALIZE - Debug exposure)...

if game:GetService("RunService"):IsStudio() then
	_G.Services = {
		-- ...existing services...
		MyNewService = MyNewService,  -- ✅ ADD THIS
	}
	-- ...existing code...
end
````

---

## 📱 Client: How to Add a New Controller

### 📝 Step 1: Create Controller File

````lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\UI\MyNewController.luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local IdempotentGuard = require(ReplicatedStorage.Utils.IdempotentGuard)

local MyNewController = {}

local guard = IdempotentGuard.new("MyNewController", true)

-- ═══════════════════════════════════════════════════════════════
-- DEPENDENCIES (Injected via ControllerLocator)
-- ═══════════════════════════════════════════════════════════════

local Dependencies: {
	NetworkController: any?,
	PlayerStateController: any?,
} = {}

-- ✅ SetDependencies (called by Init.client BEFORE Init)
function MyNewController:SetDependencies(locator: any)
	-- Get controllers from ControllerLocator
	Dependencies.NetworkController = locator:Get("NetworkController")
	Dependencies.PlayerStateController = locator:Get("PlayerStateController")
	
	-- Validate critical dependencies
	if not Dependencies.NetworkController then
		warn("[MyNewController] ⚠️ NetworkController not found!")
	end
end

-- ═══════════════════════════════════════════════════════════════
-- INIT (Setup UI, no connections)
-- ═══════════════════════════════════════════════════════════════

function MyNewController:Init()
	if not guard:MarkInitialized() then return end
	
	-- Now you can safely use dependencies
	if Dependencies.NetworkController then
		print("[MyNewController] ✅ NetworkController available")
	end
	
	print("[MyNewController] 🔧 Initialized")
end

-- ═══════════════════════════════════════════════════════════════
-- START (Connect events, show UI)
-- ═══════════════════════════════════════════════════════════════

function MyNewController:Start()
	if not guard:MarkStarted() then return end
	
	-- Use dependencies in Start
	if Dependencies.PlayerStateController then
		-- Do something with PlayerStateController
	end
	
	print("[MyNewController] 🚀 Started")
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function MyNewController:DoSomething()
	-- Your logic here
end

return MyNewController
````

---

### 📝 Step 2: Add to Init.client.luau

ไม่ต้องแก้ไข! Init.client.luau จะ **auto-load** ทุกไฟล์ในโฟลเดอร์ UI/ อัตโนมัติ

แค่ **วางไฟล์ใน UI/** เสร็จแล้ว! ✅

---

## 🎯 Boot Layers Explained

### 🖥️ Server Layers

```
Layer 1: Core         (Sequential)  ← NetworkHandler
         ↓
Layer 2: Cloud        (Sequential)  ← PocketBaseService
         ↓
Layer 3: Data         (Sequential)  ← PlayerDataService
         ↓
Layer 4: Player       (Sequential)  ← PlayerStateService
         ↓
Layer 5: Gameplay     (⚡ PARALLEL)  ← All Gameplay services run together!
         ↓
Layer 6: Test         (Optional)    ← TestService
```