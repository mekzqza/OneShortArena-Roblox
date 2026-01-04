# 🎨 GUI Communication Guide - Complete Server ↔ Client Guide

## 📋 Overview

คู่มือนี้อธิบายวิธีการสื่อสารระหว่าง **Server** และ **GUI (Client)** แบบ Production-Grade

```
┌─────────────────────────────────────────────────────────────────┐
│  🔄 COMMUNICATION FLOW                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  📱 GUI (Client)          🌐 Network          🖥️ Server          │
│  ─────────────            ─────────────       ────────────      │
│                                                                 │
│  User clicks button                                            │
│       │                                                         │
│       ▼                                                         │
│  GUIController                                                  │
│       │                                                         │
│       ├──► NetworkController                                    │
│       │        │                                                │
│       │        └──► RemoteEvent ──────────────► NetworkHandler │
│       │                                              │          │
│       │                                              ▼          │
│       │                                         Validate       │
│       │                                              │          │
│       │                                              ▼          │
│       │                                         GameService    │
│       │                                              │          │
│       │                                              ▼          │
│       │                              Event: STATE_CHANGED      │
│       │                                              │          │
│       ◄────────────────────── EventBus ◄─────────────┘          │
│       │                                                         │
│       ▼                                                         │
│  Update UI                                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🎯 Part 1: GUI → Server (Client to Server)

### 📝 Use Case: ปุ่ม "Play" ส่งคำขอไป Server

---

### Step 1: สร้าง GUI ใน Roblox Studio

```
StarterGui/
└── GameGui (ScreenGui)
    └── PlayFrame (Frame)
        └── PlayButton (TextButton)
            └── Text = "🎮 Play"
```

---

### Step 2: สร้าง GUI Controller (Client)

````lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\UI\PlayGuiController.luau
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

local PlayGuiController = {}

-- ═══════════════════════════════════════════════════════════════
-- DEPENDENCIES
-- ═══════════════════════════════════════════════════════════════

local Dependencies: {
	NetworkController: any?,
	PlayerStateController: any?,
} = {}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local player = Players.LocalPlayer
local playerGui: PlayerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local gui: ScreenGui? = nil
local playButton: TextButton? = nil

local isProcessing = false
local lastClickTime = 0
local CLICK_COOLDOWN = 1

local connections: {RBXScriptConnection} = {}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function setButtonEnabled(enabled: boolean)
	if not playButton then return end
	
	playButton.Interactable = enabled
	playButton.BackgroundColor3 = enabled 
		and Color3.fromRGB(0, 170, 0) 
		or Color3.fromRGB(100, 100, 100)
	playButton.Text = enabled and "🎮 Play" or "⏳ Loading..."
end

--[[]
    ✅ STEP 2A: Handle button click
]]
local function onPlayButtonClick()
	-- 1. Check cooldown
	local now = os.clock()
	if (now - lastClickTime) < CLICK_COOLDOWN then
		warn("[PlayGuiController] ⏱️ Click too fast!")
		return
	end
	
	-- 2. Check if already processing
	if isProcessing then
		warn("[PlayGuiController] ⚠️ Already processing...")
		return
	end
	
	lastClickTime = now
	isProcessing = true
	setButtonEnabled(false)
	
	-- 3. ✅ Send to server via NetworkController
	print("[PlayGuiController] 📤 Sending PLAYER_REQUEST_TO_ARENA to server...")
	
	if Dependencies.NetworkController then
		-- ✅ Method 1: Via NetworkController (Recommended)
		Dependencies.NetworkController:Send("RequestToArena", {
			timestamp = os.time()
		})
	else
		-- ✅ Method 2: Direct EventBus (Fallback)
		EventBus:Emit(Events.PLAYER_REQUEST_TO_ARENA, player)
	end
	
	-- 4. Re-enable after cooldown
	task.delay(CLICK_COOLDOWN, function()
		isProcessing = false
		setButtonEnabled(true)
	end)
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function PlayGuiController:SetDependencies(locator: any)
	Dependencies.NetworkController = locator:Get("NetworkController")
	Dependencies.PlayerStateController = locator:Get("PlayerStateController")
end

function PlayGuiController:Init()
	print("[PlayGuiController] 🔧 Initializing...")
	
	-- Cache GUI
	gui = playerGui:WaitForChild("GameGui") :: ScreenGui
	local playFrame = gui:WaitForChild("PlayFrame") :: Frame
	playButton = playFrame:WaitForChild("PlayButton") :: TextButton
	
	-- Initially show
	gui.Enabled = true
	setButtonEnabled(true)
	
	print("[PlayGuiController] ✅ Initialized")
end

function PlayGuiController:Start()
	print("[PlayGuiController] 🚀 Starting...")
	
	-- ═══════════════════════════════════════════════════════════
	-- CONNECT BUTTON EVENTS
	-- ═══════════════════════════════════════════════════════════
	
	if playButton then
		-- Click event
		table.insert(connections, playButton.MouseButton1Click:Connect(onPlayButtonClick))
		
		-- Hover effects
		table.insert(connections, playButton.MouseEnter:Connect(function()
			if not isProcessing then
				playButton.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
			end
		end))
		
		table.insert(connections, playButton.MouseLeave:Connect(function()
			if not isProcessing then
				playButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
			end
		end))
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- LISTEN TO STATE CHANGES FROM SERVER
	-- ═══════════════════════════════════════════════════════════
	
	table.insert(connections, EventBus:On(Events.PLAYER_STATE_CHANGED, function(changedPlayer: Player, eventData: any)
		if changedPlayer ~= player then return end
		
		local newState = eventData.newState
		
		-- Hide GUI when in Arena/Playing
		if newState == "Playing" or newState == "Downed" then
			if gui then
				gui.Enabled = false
			end
		elseif newState == "Lobby" then
			if gui then
				gui.Enabled = true
			end
			setButtonEnabled(true)
		end
	end))
	
	print("[PlayGuiController] ✅ Started")
end

return PlayGuiController
````

---

### Step 3: Server รับและประมวลผล

````lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\Services\Core\NetworkHandler.luau

-- ...existing code...

-- ✅ STEP 3A: Register event handler
function NetworkHandler:Init()
	-- ...existing code...
	
	-- Register "RequestToArena" handler
	self:RegisterEvent("RequestToArena", function(player: Player, data: {[string]: any})
		print(`[NetworkHandler] 📥 Received RequestToArena from {player.Name}`)
		
		-- 1. Validate player
		if not player or not player.Parent then
			return
		end
		
		-- 2. Rate limiting (already handled by NetworkHandler)
		
		-- 3. Forward to ArenaService
		local ArenaService = ServiceLocator:Get("ArenaService")
		if ArenaService then
			ArenaService:TeleportToArena(player)
		end
	end)
end

-- ...existing code...
````

---

## 🎯 Part 2: Server → GUI (Server to Client)

### 📝 Use Case: Server ส่งข้อมูล Coins ให้ GUI แสดงผล

---

### Step 1: สร้าง GUI แสดงผล Coins

```
StarterGui/
└── HUD (ScreenGui)
    └── CoinsFrame (Frame)
        ├── CoinsIcon (ImageLabel)
        └── CoinsLabel (TextLabel)
            └── Text = "0"
```

---

### Step 2: สร้าง GUI Controller รับข้อมูล

````lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\UI\HudController.luau
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

local HudController = {}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local player = Players.LocalPlayer
local playerGui: PlayerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local gui: ScreenGui? = nil
local coinsLabel: TextLabel? = nil

local currentCoins = 0
local connections: {RBXScriptConnection} = {}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

--[[]
    ✅ STEP 2A: Update coins display with animation
]]
local function updateCoins(newCoins: number)
	if not coinsLabel then return end
	
	local oldCoins = currentCoins
	currentCoins = newCoins
	
	-- Animate number counting up
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local steps = 20
	local increment = (newCoins - oldCoins) / steps
	
	for i = 1, steps do
		task.wait(0.5 / steps)
		local value = math.floor(oldCoins + (increment * i))
		coinsLabel.Text = `💰 {value}`
	end
	
	coinsLabel.Text = `💰 {newCoins}`
	
	-- Scale animation
	local scaleTween = TweenService:Create(coinsLabel, 
		TweenInfo.new(0.2, Enum.EasingStyle.Back), 
		{ TextSize = 24 }
	)
	scaleTween:Play()
	scaleTween.Completed:Wait()
	
	local scaleTweenBack = TweenService:Create(coinsLabel, 
		TweenInfo.new(0.2, Enum.EasingStyle.Back), 
		{ TextSize = 20 }
	)
	scaleTweenBack:Play()
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function HudController:Init()
	print("[HudController] 🔧 Initializing...")
	
	-- Cache GUI
	gui = playerGui:WaitForChild("HUD") :: ScreenGui
	local coinsFrame = gui:WaitForChild("CoinsFrame") :: Frame
	coinsLabel = coinsFrame:WaitForChild("CoinsLabel") :: TextLabel
	
	-- Initially show
	gui.Enabled = true
	setButtonEnabled(true)
	
	print("[HudController] ✅ Initialized")
end

function HudController:Start()
	print("[HudController] 🚀 Starting...")
	
	-- ═══════════════════════════════════════════════════════════
	-- ✅ STEP 2B: LISTEN TO DATA CHANGES FROM SERVER
	-- ═══════════════════════════════════════════════════════════
	
	-- Method 1: Listen to specific field change
	table.insert(connections, EventBus:On(Events.PLAYER_DATA_CHANGED, function(changedPlayer: Player, eventData: any)
		if changedPlayer ~= player then return end
		
		-- Check if Coins changed
		if eventData.key == "Coins" then
			print(`[HudController] 💰 Coins changed: {eventData.oldValue} → {eventData.newValue}`)
			updateCoins(eventData.newValue)
		end
	end))
	
	-- Method 2: Listen to full data load (initial)
	table.insert(connections, EventBus:On(Events.PLAYER_DATA_LOADED, function(loadedPlayer: Player, eventData: any)
		if loadedPlayer ~= player then return end
		
		print("[HudController] 📊 Data loaded")
		local data = eventData.data
		
		if data.Coins then
			updateCoins(data.Coins)
		end
	end))
	
	print("[HudController] ✅ Started")
end

return HudController
````

---

### Step 3: Server ส่งข้อมูล

````lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\Services\Data\PlayerDataService.luau

-- ...existing code...

function PlayerDataService:Set(player: Player, key: string, value: any): boolean
	-- ...existing validation...
	
	-- Update data
	profile.Data[key] = finalValue
	analytics.totalWrites += 1
	
	-- ✅ STEP 3A: Emit event to clients
	EventBus:Emit(Events.PLAYER_DATA_CHANGED, player, { 
		key = key, 
		newValue = finalValue,
		oldValue = currentValue 
	})
	
	return true
end

-- ...existing code...
````

---

## 🔄 Complete Flow Examples

### Example 1: Buy Item Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  🛒 BUY ITEM FLOW                                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1️⃣ GUI: User clicks "Buy Sword" (100 Coins)                    │
│     │                                                           │
│     ├─► ShopGuiController:OnBuyClick()                          │
│     │   └─► NetworkController:Send("BuyItem", {...})            │
│     │                                                           │
│  2️⃣ Server: NetworkHandler receives                             │
│     │                                                           │
│     ├─► Validate player                                         │
│     ├─► Rate limit check                                        │
│     ├─► ShopService:ProcessPurchase(player, itemId)            │
│     │   │                                                       │
│     │   ├─► Check if enough coins                              │
│     │   ├─► PlayerDataService:Get(player, "Coins")             │
│     │   │                                                       │
│     │   ├─► Deduct coins                                        │
│     │   ├─► PlayerDataService:Increment(player, "Coins", -100)  │
│     │   │   └─► Emit: PLAYER_DATA_CHANGED (Coins)              │
│     │   │                                                       │
│     │   └─► Give item                                           │
│     │       └─► PlayerDataService:AddItem(player, itemId)       │
│     │           └─► Emit: PLAYER_ITEM_ADDED                    │
│     │                                                           │
│  3️⃣ Client: GUI updates automatically                           │
│     │                                                           │
│     ├─► HudController hears PLAYER_DATA_CHANGED (Coins)        │
│     │   └─► updateCoins(900)                                    │
│     │                                                           │
│     └─► ShopGuiController hears PLAYER_ITEM_ADDED              │
│         └─► showPurchaseSuccess()                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Implementation:

````lua
-- Client: ShopGuiController.luau
local function onBuyButtonClick(itemId: string, price: number)
	if Dependencies.NetworkController then
		Dependencies.NetworkController:Send("BuyItem", {
			itemId = itemId,
			price = price,
			timestamp = os.time()
		})
	end
end

-- Server: ShopService.luau
function ShopService:ProcessPurchase(player: Player, itemId: string, price: number): boolean
	local PlayerDataService = ServiceLocator:Get("PlayerDataService")
	
	-- 1. Check coins
	local coins = PlayerDataService:Get(player, "Coins")
	if coins < price then
		warn(`[ShopService] ❌ {player.Name} not enough coins`)
		return false
	end
	
	-- 2. Deduct coins
	local success = PlayerDataService:Increment(player, "Coins", -price)
	if not success then return false end
	
	-- 3. Give item
	PlayerDataService:AddItem(player, itemId)
	
	print(`[ShopService] ✅ {player.Name} bought {itemId} for {price} coins`)
	return true
end
````

---

### Example 2: Leaderboard Update Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  🏆 LEADERBOARD UPDATE FLOW                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1️⃣ Server: Player kills enemy                                  │
│     │                                                           │
│     ├─► CombatService detects kill                              │
│     ├─► PlayerDataService:Increment(player, "Kills", 1)        │
│     │   └─► Emit: PLAYER_DATA_CHANGED (Kills)                  │
│     │                                                           │
│  2️⃣ Server: Broadcast to all clients                            │
│     │                                                           │
│     └─► EventBus:EmitToAll(Events.LEADERBOARD_UPDATED, {...})  │
│                                                                 │
│  3️⃣ Client: All players' GUIs update                            │
│     │                                                           │
│     └─► LeaderboardController hears LEADERBOARD_UPDATED        │
│         └─► refreshLeaderboard()                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📚 Best Practices Checklist

```
✅ GUI → Server:

□ ใช้ NetworkController (ไม่ใช้ RemoteEvent ตรง)
□ ใส่ Cooldown ป้องกัน spam click
□ ใช้ isProcessing flag
□ Disable button ขณะ processing
□ ส่ง timestamp เพื่อตรวจสอบ
□ Validate ข้อมูลก่อนส่ง
□ แสดง Loading state

✅ Server → GUI:

□ ใช้ EventBus (ไม่ใช้ RemoteEvent ตรง)
□ Emit event เมื่อข้อมูลเปลี่ยน
□ ส่งเฉพาะข้อมูลที่จำเป็น
□ ใช้ specific events (ไม่ generic)
□ Filter recipient ถ้าไม่ต้องการ broadcast
□ Log events สำหรับ debug

✅ GUI Controller:

□ Cache GUI elements ใน Init()
□ ใช้ SetDependencies() pattern
□ Cleanup connections ใน Destroy()
□ แยก UI logic จาก business logic
□ ใช้ TweenService สำหรับ animations
□ Handle edge cases (player leaving, etc.)

✅ Security:

□ ตรวจสอบทุกอย่างฝั่ง Server
□ ไม่เชื่อข้อมูลจาก Client
□ Rate limiting ทุก event
□ Validate input ก่อนประมวลผล
□ Log suspicious activities
```