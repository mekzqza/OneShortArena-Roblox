# 🔄 Request-Response System Guide

## 📋 Overview

ระบบ Request-Response เป็นการสื่อสารแบบ **2-way** ระหว่าง Client และ Server ที่รอ**ผลลัพธ์กลับมา**

```
┌─────────────────────────────────────────────────────────────────┐
│  🔄 REQUEST-RESPONSE vs FIRE-AND-FORGET                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ❌ BEFORE (Fire-and-Forget):                                   │
│  ────────────────────────────                                   │
│  Client ──► Send("BuyItem")  ──► Server                         │
│                                    │                            │
│  ❓ ซื้อสำเร็จหรือไม่?             ▼                            │
│  ❓ เหลือเงินเท่าไร?           Process...                       │
│  ❓ มี error อะไรไหม?              │                            │
│                                    ▼                            │
│  ⏰ (รอ Event กลับมาแยก)       Emit Event (optional)            │
│                                                                 │
│  ✅ AFTER (Request-Response):                                   │
│  ──────────────────────────                                     │
│  Client ──► Invoke("BuyItem") ──► Server                        │
│       ↑                               │                         │
│       │                               ▼                         │
│       │                          Process...                     │
│       │                               │                         │
│       │                               ▼                         │
│       └────── Response ◄──────── Return result                  │
│                                                                 │
│  ✅ ได้คำตอบทันที!                                              │
│  ✅ รู้ว่าสำเร็จหรือล้มเหลว                                     │
│  ✅ ได้ข้อมูลกลับมาทันที                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🆚 เปรียบเทียบ: Fire-and-Forget vs Request-Response

### ❌ แบบเก่า (Fire-and-Forget)

```lua
-- Client
NetworkController:Send("BuyItem", { itemId = "Sword_001", price = 100 })

-- ❓ ไม่รู้ว่าสำเร็จหรือไม่
-- ❓ ต้องรอ Event แยกมาบอก

-- Server
EventBus:On("BuyItem", function(player, data)
    -- Process purchase
    if success then
        -- ต้องส่ง Event กลับไป
        NetworkHandler:SendToClient(player, "PurchaseSuccess", {...})
    else
        NetworkHandler:SendToClient(player, "PurchaseFailure", {...})
    end
end)

-- Client ต้อง listen แยก
EventBus:On("PurchaseSuccess", function(data)
    -- Update UI
end)

EventBus:On("PurchaseFailure", function(data)
    -- Show error
end)
```

**ปัญหา:**
- ❌ ต้องจัดการ 3 ที่: Send, Success listener, Failure listener
- ❌ ไม่รู้ว่าการส่งสำเร็จหรือไม่
- ❌ ต้องเก็บ state เพื่อรอผลลัพธ์
- ❌ Code กระจัดกระจาย

---

### ✅ แบบใหม่ (Request-Response)

```lua
-- Client - ทำทุกอย่างในที่เดียว!
NetworkController:Invoke("BuyItem", { itemId = "Sword_001", price = 100 })
    :andThen(function(result)
        -- ✅ สำเร็จ!
        print("Purchased:", result.itemId)
        print("New balance:", result.newBalance)
        updateUI(result)
    end)
    :catch(function(error)
        -- ❌ ล้มเหลว!
        warn("Purchase failed:", error)
        showErrorPopup(error)
    end)

-- Server - Return ผลลัพธ์ได้เลย!
NetworkHandler:RegisterRequestHandler("BuyItem", function(player, data)
    local itemId = data.itemId
    local price = data.price
    
    -- Check coins
    local coins = PlayerDataService:Get(player, "Coins")
    if coins < price then
        return false, "Not enough coins" -- ❌ Error
    end
    
    -- Process purchase
    PlayerDataService:Increment(player, "Coins", -price)
    PlayerDataService:AddItem(player, itemId)
    
    -- ✅ Success
    return true, {
        purchased = true,
        itemId = itemId,
        newBalance = PlayerDataService:Get(player, "Coins")
    }
end)
```  

**ข้อดี:**
- ✅ Code อยู่ในที่เดียว (Promise chain)
- ✅ รู้ผลลัพธ์ทันที
- ✅ Type-safe (รู้ว่าได้อะไรกลับมา)
- ✅ Error handling ง่าย

---

## 📖 วิธีใช้งาน

### 1️⃣ Server: Register Handler

```lua
-- ใน Service ใดก็ได้ (เช่น PlayerDataService:Start())
local NetworkHandler = ServiceLocator:Get("NetworkHandler")

NetworkHandler:RegisterRequestHandler("RequestName", function(player, data)
    -- ✅ ทำงาน...
    -- ✅ Return (success, result/error)
    
    if success then
        return true, result -- Success
    else
        return false, "Error message" -- Failure
    end
end)
```

### 2️⃣ Client: Call Request

```lua
-- ใน Controller ใดก็ได้
local NetworkController = Dependencies.NetworkController

NetworkController:Invoke("RequestName", { key = "value" })
    :andThen(function(result)
        -- ✅ Success - ทำอะไรก็ได้กับ result
        print("Success:", result)
    end)
    :catch(function(error)
        -- ❌ Failure - แสดง error
        warn("Failed:", error)
    end)
```

---

## 🎯 ตัวอย่างการใช้งานจริง

### Example 1: Get Player Data

**Server (PlayerDataService.luau):**

```lua
function PlayerDataService:Start()
    // ...existing code...
    
    local NetworkHandler = ServiceLocator:Get("NetworkHandler")
    
    -- ✅ Register handler
    NetworkHandler:RegisterRequestHandler("GetPlayerData", function(player: Player, data: any)
        local playerData = self:GetAll(player)
        
        if playerData then
            return true, playerData -- ✅ Success
        else
            return false, "Data not loaded" -- ❌ Error
        end
    end)
end
```

**Client (HudController.luau):**

```lua
function HudController:Start()
    -- ✅ Request data
    Dependencies.NetworkController:Invoke("GetPlayerData")
        :andThen(function(data)
            -- ✅ Got data!
            print("Coins:", data.Coins)
            print("Level:", data.Level)
            updateCoinsDisplay(data.Coins)
        end)
        :catch(function(err)
            warn("Failed to load data:", err)
        end)
end
```

---

### Example 2: Buy Item

**Server (ShopService.luau หรือ PlayerDataService.luau):**

```lua
NetworkHandler:RegisterRequestHandler("BuyItem", function(player: Player, data: any)
    local itemId = data.itemId
    local price = data.price
    
    -- Get dependencies
    local PlayerDataService = ServiceLocator:Get("PlayerDataService")
    
    -- 1. Check coins
    local coins = PlayerDataService:Get(player, "Coins")
    if coins < price then
        return false, "Not enough coins" -- ❌
    end
    
    -- 2. Check if already owned
    if PlayerDataService:HasItem(player, itemId) then
        return false, "Already owned" -- ❌
    end
    
    -- 3. Deduct coins
    PlayerDataService:Increment(player, "Coins", -price)
    
    -- 4. Give item
    PlayerDataService:AddItem(player, itemId)
    
    -- 5. Return success
    return true, {
        purchased = true,
        itemId = itemId,
        newBalance = PlayerDataService:Get(player, "Coins"),
        timestamp = os.time()
    } -- ✅
end)
```

**Client (ShopGuiController.luau):**

```lua
local function onBuyButtonClick(itemId: string, price: number)
    -- Disable button
    buyButton.Interactable = false
    
    -- Request purchase
    Dependencies.NetworkController:Invoke("BuyItem", {
        itemId = itemId,
        price = price
    })
        :andThen(function(result)
            -- ✅ Success!
            print("Purchased:", result.itemId)
            print("New balance:", result.newBalance)
            
            -- Update UI
            updateCoinsDisplay(result.newBalance)
            showSuccessPopup(`Purchased {itemId}!`)
            
            -- Re-enable button
            buyButton.Interactable = true
        end)
        :catch(function(error)
            -- ❌ Failed!
            warn("Purchase failed:", error)
            
            -- Show error
            showErrorPopup(error)
            
            -- Re-enable button
            buyButton.Interactable = true
        end)
end
```

---

### Example 3: Equip Item

**Server:**

```lua
NetworkHandler:RegisterRequestHandler("EquipItem", function(player, data)
    local itemId = data.itemId
    local slot = data.slot
    
    local PDS = ServiceLocator:Get("PlayerDataService")
    
    -- Check if owned
    if not PDS:HasItem(player, itemId) then
        return false, "Item not owned"
    end
    
    -- Equip
    local profile = PDS:GetProfile(player)
    if not profile then
        return false, "Profile not loaded"
    end
    
    profile.Data.EquippedItems[slot] = itemId
    
    -- Broadcast to other players
    local NetworkHandler = ServiceLocator:Get("NetworkHandler")
    NetworkHandler:Broadcast("PlayerEquippedItem", {
        userId = player.UserId,
        itemId = itemId,
        slot = slot
    })
    
    return true, {
        equipped = true,
        slot = slot,
        itemId = itemId
    }
end)
```

**Client:**

```lua
local function equipItem(itemId, slot)
    NetworkController:Invoke("EquipItem", {
        itemId = itemId,
        slot = slot
    })
        :andThen(function(result)
            print(`Equipped {result.itemId} in {result.slot}`)
            updateEquipmentUI()
        end)
        :catch(function(err)
            warn("Equip failed:", err)
        end)
end
```

---

### Example 4: Get Leaderboard

**Server:**

```lua
NetworkHandler:RegisterRequestHandler("GetLeaderboard", function(player, data)
    local category = data.category or "Kills"
    local limit = data.limit or 10
    
    -- ตัวอย่าง: Query จาก PocketBase
    local PocketBaseService = ServiceLocator:Get("PocketBaseService")
    
    -- ใน production จริงๆ ควรมี LeaderboardService
    local leaderboard = {
        { name = "Player1", score = 100 },
        { name = "Player2", score = 90 },
        { name = "Player3", score = 80 },
    }
    
    return true, {
        category = category,
        data = leaderboard,
        timestamp = os.time()
    }
end)
```

**Client:**

```lua
function LeaderboardController:RefreshLeaderboard()
    NetworkController:Invoke("GetLeaderboard", {
        category = "Kills",
        limit = 10
    })
        :andThen(function(result)
            local leaderboard = result.data
            
            -- Update UI
            for i, entry in ipairs(leaderboard) do
                updateLeaderboardEntry(i, entry.name, entry.score)
            end
        end)
        :catch(function(err)
            warn("Failed to load leaderboard:", err)
        end)
end
```

---

## ⚙️ Advanced Features

### 1️⃣ Timeout

```lua
-- Default timeout: 10 seconds
NetworkController:Invoke("SlowOperation", data, 20) -- 20s timeout
    :andThen(function(result)
        print("Success:", result)
    end)
    :catch(function(err)
        -- err might be timeout error
        warn("Error:", err)
    end)
```

### 2️⃣ Chaining Requests

```lua
-- Request 1
NetworkController:Invoke("GetPlayerData")
    :andThen(function(data)
        print("Got data:", data.Coins)
        
        -- Request 2 (depends on Request 1)
        return NetworkController:Invoke("BuyItem", {
            itemId = "Sword",
            price = 100
        })
    end)
    :andThen(function(result)
        print("Purchased:", result.itemId)
    end)
    :catch(function(err)
        warn("Failed:", err)
    end)
```

### 3️⃣ Parallel Requests

```lua
local Promise = require(ReplicatedStorage.Packages.Promise)

-- Request หลายอย่างพร้อมกัน
Promise.all({
    NetworkController:Invoke("GetPlayerData"),
    NetworkController:Invoke("GetLeaderboard"),
    NetworkController:Invoke("GetShopItems"),
})
    :andThen(function(results)
        local playerData = results[1]
        local leaderboard = results[2]
        local shopItems = results[3]
        
        print("All data loaded!")
    end)
    :catch(function(err)
        warn("One failed:", err)
    end)
```

---

## 🐛 Debug Commands

```lua
-- F9 Console (Server)

-- List registered handlers
print(_G.Services.NetworkHandler:GetRegisteredHandlers())

-- Get request analytics
print(_G.Services.NetworkHandler:GetRequestAnalytics())

-- F9 Console (Client)

-- Test request
_G.ControllerLocator:Get("NetworkController"):Invoke("GetPlayerData")
    :andThen(print)
    :catch(warn)

-- Check analytics
print(_G.ControllerLocator:Get("NetworkController"):GetAnalytics())
```

---

## ✅ Best Practices

### Server

```lua
✅ DO:
• Validate input data
• Check player permissions
• Return meaningful error messages
• Use pcall for external operations
• Keep handlers fast (<1s)

❌ DON'T:
• Trust client data blindly
• Return sensitive information
• Block for too long (use timeout)
• Forget error handling
```

### Client

```lua
✅ DO:
• Handle both success and error
• Show loading state
• Disable buttons during request
• Use timeout for slow operations
• Chain requests when needed

❌ DON'T:
• Spam requests
• Ignore errors
• Assume success
• Forget to re-enable UI
```