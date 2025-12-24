# 🧪 Demo: Network Communication Tutorial

## ⚠️ เอกสารนี้สำหรับ Demo Layer เท่านั้น

**Demo Components** ใช้เพื่อทดสอบการส่งข้อมูล Client ↔ Server เท่านั้น

**ไม่ควรใช้เป็น Production architecture!**

---

## 📚 สารบัญ

1. [Client → Server](#1-client--server)
2. [Server → Client (Single Player)](#2-server--client-single-player)
3. [Server → All Clients (Broadcast)](#3-server--all-clients-broadcast)
4. [Complete Examples](#4-complete-examples)

---

## 1. Client → Server

### 📤 วิธีส่งข้อมูลจาก Client ไปยัง Server

```
┌─────────────┐                    ┌─────────────┐
│   CLIENT    │ ─── Send Data ───► │   SERVER    │
│ DemoController                    │ DemoService │
└─────────────┘                    └─────────────┘
```

### ขั้นตอนการส่ง

#### Step 1: เพิ่ม Event ใน Events.luau

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ReplicatedStorage\Shared\Events.luau
// ...existing code...

-- Demo Events (🧪 Testing Only)
DEMO_HELLO = "DemoHello",  -- ใหม่: ทดสอบส่งข้อความ
```

#### Step 2: Client - ส่งข้อมูล (DemoController.luau)

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\Controllers\DemoController.luau
// ...existing code...

-- ฟังก์ชันใหม่: ส่งข้อความไปยัง Server
function DemoController:SendHello()
    print("[DemoController] 📤 Sending Hello to server...")
    
    -- ส่งข้อมูลไปยัง Server
    NetworkController:Send(Events.DEMO_HELLO, {
        message = "สวัสดี Server!",
        playerName = player.Name,
        timestamp = tick(),
    })
end

// ...existing code...
```

#### Step 3: Server - รับข้อมูล (DemoService.luau)

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\Services\DemoService.luau
// ...existing code...

function DemoService:Init()
    // ...existing code...
    
    -- อนุญาตให้ Client ส่ง event นี้ได้
    NetworkHandler:AllowClientEvent(Events.DEMO_HELLO)
end

function DemoService:Start()
    // ...existing code...
    
    -- รับข้อมูลจาก Client
    EventBus:On(Events.DEMO_HELLO, function(player: Player, data: any)
        print(`[DemoService] 📨 Received from {player.Name}:`)
        print(`  Message: {data.message}`)
        print(`  Timestamp: {data.timestamp}`)
        
        -- ทำอะไรกับข้อมูลที่ได้รับ (เช่น บันทึก, ประมวลผล)
    end)
end

// ...existing code...
```

#### Step 4: ทดสอบ

```lua
-- ใน Command Bar (F9)
_G.DemoController:SendHello()

-- Console Output (Client):
-- [DemoController] 📤 Sending Hello to server...

-- Console Output (Server):
-- [DemoService] 📨 Received from Player1:
--   Message: สวัสดี Server!
--   Timestamp: 1234.56
```

---

## 2. Server → Client (Single Player)

### 📥 วิธีส่งข้อมูลจาก Server ไปยัง Client คนเดียว

```
┌─────────────┐                    ┌─────────────┐
│   SERVER    │ ◄── Send Data ──── │   CLIENT    │
│ DemoService │                    │ DemoController
└─────────────┘                    └─────────────┘
```

### ขั้นตอนการส่ง

#### Step 1: เพิ่ม Event

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ReplicatedStorage\Shared\Events.luau
// ...existing code...

DEMO_HELLO_RESPONSE = "DemoHelloResponse",  -- ใหม่: Server ตอบกลับ
```

#### Step 2: Server - ส่งข้อมูลกลับ

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\Services\DemoService.luau
// ...existing code...

function DemoService:Init()
    // ...existing code...
    NetworkHandler:AllowServerEvent(Events.DEMO_HELLO_RESPONSE)
end

function DemoService:Start()
    // ...existing code...
    
    EventBus:On(Events.DEMO_HELLO, function(player: Player, data: any)
        print(`[DemoService] 📨 Received from {player.Name}: {data.message}`)
        
        -- ส่งข้อมูลกลับไปยัง Client ที่ส่งมา
        NetworkHandler:SendToClient(player, Events.DEMO_HELLO_RESPONSE, {
            serverMessage = "สวัสดี " .. player.Name .. "!",
            receivedAt = os.clock(),
            yourMessage = data.message,
        })
    end)
end

// ...existing code...
```

#### Step 3: Client - รับข้อมูล

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\Controllers\DemoController.luau
// ...existing code...

function DemoController:Start()
    -- รอรับ INPUT_ACTION จาก InputController
    EventBus:On(Events.INPUT_ACTION, function(actionName: string)
        self:OnInputAction(actionName)
    end)
    
    -- รับข้อมูลจาก Server
    EventBus:On(Events.DEMO_HELLO_RESPONSE, function(data: any)
        print("[DemoController] 📬 Received response from server:")
        print(`  Server says: {data.serverMessage}`)
        print(`  Received at: {data.receivedAt}`)
        print(`  Echo: {data.yourMessage}`)
    end)
end

-- ฟังก์ชันหลักที่จัดการ input
function DemoController:OnInputAction(actionName: string)
    print(`[DemoController -client] 🎮 Input detected: {actionName}`)
    
    -- แปลงเป็นตัวพิมพ์ใหญ่ทั้งหมดเพื่อให้ case-insensitive
    local action = string.upper(actionName)
    
    if action == "ATTACK" then
        self:SendAttack()
        
    elseif action == "DEFEND" then
        self:SendDefend()
        
    elseif action == "SPECIAL" then
        self:SendSpecial()
        
    elseif action == "PING" then
        self:SendPing()
        
    elseif action == "TESTBUTTON1" then
        self:SendTestButton(1)
        
    elseif action == "TESTBUTTON2" then
        self:SendTestButton(2)
        
    elseif action == "TESTBUTTON3" then
        self:SendTestButton(3)
        
    elseif action == "TESTCLICK" then
        self:SendTestEventToServer()
        
    else
        -- Actions อื่นๆ ที่ไม่ต้องส่งไปยัง server
        print(`[DemoController] ℹ️ Action '{actionName}' handled locally`)
    end
end

-- ส่ง Attack ไปยัง Server
function DemoController:SendAttack()
    print("[DemoController] ⚔️ Sending Attack to server...")
    
    NetworkController:Send(Events.PLAYER_ATTACK, {
        timestamp = tick(),
        position = player.Character and player.Character.PrimaryPart.Position or Vector3.zero,
    })
end

-- ส่ง Defend ไปยัง Server
function DemoController:SendDefend()
    print("[DemoController] 🛡️ Sending Defend to server...")
    
    NetworkController:Send(Events.PLAYER_DEFEND, {
        timestamp = tick(),
        isBlocking = true,
    })
end

-- ส่ง Special ไปยัง Server
function DemoController:SendSpecial()
    print("[DemoController] ✨ Sending Special to server...")
    
    NetworkController:Send(Events.PLAYER_SPECIAL, {
        timestamp = tick(),
        skillType = "Ultimate",
    })
end

-- ส่ง Ping (Demo)
function DemoController:SendPing()
    print("[DemoController] 📡 Sending Ping to server...")
    
    NetworkController:Send(Events.DEMO_PING, tick())
end

-- ส่ง Test Button
function DemoController:SendTestButton(buttonNumber: number)
    print(`[DemoController] 🔘 Sending TestButton{buttonNumber} to server...`)
    
    NetworkController:Send(Events.TEST_BUTTON_PRESSED, {
        buttonId = buttonNumber,
        playerName = player.Name,
        timestamp = tick(),
    })
end

-- สามารถเรียกจาก Console ได้
function DemoController:SendTestEventToServer()
    local buttonCounter = 1
    NetworkController:Send(Events.TEST_CLIENT_BUTTON_CLICK,"buttonCounter")
    print(`[DemoController-client] 📨 Sent TestClientButtonClick with counter {buttonCounter} to server`)
end

return DemoController
```

#### Step 4: ทดสอบ

```lua
-- Client sends
_G.DemoController:SendHello()

-- Console Output (All Clients):
-- [DemoController] 📢 Announcement:
--   Player1 ส่งทักทายมา!
--   From: Player1
```

---

## 3. Server → All Clients (Broadcast)

### 📢 วิธีส่งข้อมูลจาก Server ไปยัง Client ทุกคน

```
┌─────────────┐
│   SERVER    │
│ DemoService │
└─────────────┘
       │
       ├──► Client 1
       ├──► Client 2
       └──► Client 3
```

### ขั้นตอนการ Broadcast

#### Step 1: เพิ่ม Event

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ReplicatedStorage\Shared\Events.luau
// ...existing code...

DEMO_ANNOUNCEMENT = "DemoAnnouncement",  -- ใหม่: ประกาศทั่วไป
```

#### Step 2: Server - Broadcast ไปยังทุกคน

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\Services\DemoService.luau
// ...existing code...

function DemoService:Init()
    // ...existing code...
    NetworkHandler:AllowServerEvent(Events.DEMO_ANNOUNCEMENT)
end

function DemoService:Start()
    // ...existing code...
    
    EventBus:On(Events.DEMO_HELLO, function(player: Player, data: any)
        print(`[DemoService] 📨 Received from {player.Name}: {data.message}`)
        
        -- Broadcast ไปยัง Client ทุกคน
        NetworkHandler:Broadcast(Events.DEMO_ANNOUNCEMENT, {
            message = `{player.Name} ส่งทักทายมา!`,
            from = player.Name,
            timestamp = os.clock(),
        })
    end)
end

// ...existing code...
```

#### Step 3: Client - รับการ Broadcast

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\Controllers\DemoController.luau
// ...existing code...

function DemoController:Start()
    -- รอรับ INPUT_ACTION จาก InputController
    EventBus:On(Events.INPUT_ACTION, function(actionName: string)
        self:OnInputAction(actionName)
    end)
    
    -- รับการประกาศจาก Server
    EventBus:On(Events.DEMO_ANNOUNCEMENT, function(data: any)
        print("[DemoController] 📢 Announcement:")
        print(`  {data.message}`)
        print(`  From: {data.from}`)
    end)
end

-- ฟังก์ชันหลักที่จัดการ input
function DemoController:OnInputAction(actionName: string)
    print(`[DemoController -client] 🎮 Input detected: {actionName}`)
    
    -- แปลงเป็นตัวพิมพ์ใหญ่ทั้งหมดเพื่อให้ case-insensitive
    local action = string.upper(actionName)
    
    if action == "ATTACK" then
        self:SendAttack()
        
    elseif action == "DEFEND" then
        self:SendDefend()
        
    elseif action == "SPECIAL" then
        self:SendSpecial()
        
    elseif action == "PING" then
        self:SendPing()
        
    elseif action == "TESTBUTTON1" then
        self:SendTestButton(1)
        
    elseif action == "TESTBUTTON2" then
        self:SendTestButton(2)
        
    elseif action == "TESTBUTTON3" then
        self:SendTestButton(3)
        
    elseif action == "TESTCLICK" then
        self:SendTestEventToServer()
        
    else
        -- Actions อื่นๆ ที่ไม่ต้องส่งไปยัง server
        print(`[DemoController] ℹ️ Action '{actionName}' handled locally`)
    end
end

-- ส่ง Attack ไปยัง Server
function DemoController:SendAttack()
    print("[DemoController] ⚔️ Sending Attack to server...")
    
    NetworkController:Send(Events.PLAYER_ATTACK, {
        timestamp = tick(),
        position = player.Character and player.Character.PrimaryPart.Position or Vector3.zero,
    })
end

-- ส่ง Defend ไปยัง Server
function DemoController:SendDefend()
    print("[DemoController] 🛡️ Sending Defend to server...")
    
    NetworkController:Send(Events.PLAYER_DEFEND, {
        timestamp = tick(),
        isBlocking = true,
    })
end

-- ส่ง Special ไปยัง Server
function DemoController:SendSpecial()
    print("[DemoController] ✨ Sending Special to server...")
    
    NetworkController:Send(Events.PLAYER_SPECIAL, {
        timestamp = tick(),
        skillType = "Ultimate",
    })
end

-- ส่ง Ping (Demo)
function DemoController:SendPing()
    print("[DemoController] 📡 Sending Ping to server...")
    
    NetworkController:Send(Events.DEMO_PING, tick())
end

-- ส่ง Test Button
function DemoController:SendTestButton(buttonNumber: number)
    print(`[DemoController] 🔘 Sending TestButton{buttonNumber} to server...`)
    
    NetworkController:Send(Events.TEST_BUTTON_PRESSED, {
        buttonId = buttonNumber,
        playerName = player.Name,
        timestamp = tick(),
    })
end

-- สามารถเรียกจาก Console ได้
function DemoController:SendTestEventToServer()
    local buttonCounter = 1
    NetworkController:Send(Events.TEST_CLIENT_BUTTON_CLICK,"buttonCounter")
    print(`[DemoController-client] 📨 Sent TestClientButtonClick with counter {buttonCounter} to server`)
end

return DemoController
```

#### Step 4: ทดสอบ

```lua
-- Player1 sends
_G.DemoController:SendHello()

-- Console Output (All Clients):
-- [DemoController] 📢 Announcement:
--   Player1 ส่งทักทายมา!
--   From: Player1
```

---

## 4. Complete Examples

### ตัวอย่างที่ 1: ระบบ Chat

#### Client ส่งข้อความ

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\Controllers\DemoController.luau
// ...existing code...

function DemoController:SendChatMessage(message: string)
    if #message == 0 or #message > 100 then
        warn("[DemoController] Message too long or empty")
        return
    end
    
    print(`[DemoController] 💬 Sending chat: {message}`)
    
    NetworkController:Send(Events.DEMO_CHAT_MESSAGE, {
        message = message,
        timestamp = tick(),
    })
end

-- ...existing code...
```

#### Server ประมวลผลและ Broadcast

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\Services\DemoService.luau
// ...existing code...

function DemoService:Init()
    // ...existing code...
    NetworkHandler:AllowClientEvent(Events.DEMO_CHAT_MESSAGE)
    NetworkHandler:AllowServerEvent(Events.DEMO_BROADCAST_MESSAGE)
    
    -- Validator สำหรับ Chat
    NetworkHandler:RegisterValidator(Events.DEMO_CHAT_MESSAGE, function(player, args)
        local message = args[1].message
        
        -- Validate
        if typeof(message) ~= "string" then
            return false, "Message must be string"
        end
        if #message > 100 then
            return false, "Message too long"
        end
        if #message == 0 then
            return false, "Message empty"
        end
        
        return true
    end)
end

function DemoService:Start()
    // ...existing code...
    
    EventBus:On(Events.DEMO_CHAT_MESSAGE, function(player: Player, data: any)
        print(`[DemoService] 💬 Chat from {player.Name}: {data.message}`)
        
        -- Filter bad words (ตัวอย่าง)
        local filtered = data.message:gsub("badword", "***")
        
        -- Broadcast to everyone
        NetworkHandler:Broadcast(Events.DEMO_BROADCAST_MESSAGE, {
            playerName = player.Name,
            userId = player.UserId,
            message = filtered,
            timestamp = os.clock(),
        })
    end)
end

// ...existing code...
```

#### Client แสดงข้อความ

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\Controllers\DemoController.luau
// ...existing code...

function DemoController:Start()
    -- รอรับ INPUT_ACTION จาก InputController
    EventBus:On(Events.INPUT_ACTION, function(actionName: string)
        self:OnInputAction(actionName)
    end)
    
    EventBus:On(Events.DEMO_BROADCAST_MESSAGE, function(data: any)
        print(`[CHAT] {data.playerName}: {data.message}`)
        
        -- แสดงใน UI (ถ้ามี)
        -- local chatUI = player.PlayerGui.ChatFrame
        -- chatUI:AddMessage(data.playerName, data.message)
    end)
end

-- ฟังก์ชันหลักที่จัดการ input
function DemoController:OnInputAction(actionName: string)
    print(`[DemoController -client] 🎮 Input detected: {actionName}`)
    
    -- แปลงเป็นตัวพิมพ์ใหญ่ทั้งหมดเพื่อให้ case-insensitive
    local action = string.upper(actionName)
    
    if action == "ATTACK" then
        self:SendAttack()
        
    elseif action == "DEFEND" then
        self:SendDefend()
        
    elseif action == "SPECIAL" then
        self:SendSpecial()
        
    elseif action == "PING" then
        self:SendPing()
        
    elseif action == "TESTBUTTON1" then
        self:SendTestButton(1)
        
    elseif action == "TESTBUTTON2" then
        self:SendTestButton(2)
        
    elseif action == "TESTBUTTON3" then
        self:SendTestButton(3)
        
    elseif action == "TESTCLICK" then
        self:SendTestEventToServer()
        
    else
        -- Actions อื่นๆ ที่ไม่ต้องส่งไปยัง server
        print(`[DemoController] ℹ️ Action '{actionName}' handled locally`)
    end
end

-- ส่ง Attack ไปยัง Server
function DemoController:SendAttack()
    print("[DemoController] ⚔️ Sending Attack to server...")
    
    NetworkController:Send(Events.PLAYER_ATTACK, {
        timestamp = tick(),
        position = player.Character and player.Character.PrimaryPart.Position or Vector3.zero,
    })
end

-- ส่ง Defend ไปยัง Server
function DemoController:SendDefend()
    print("[DemoController] 🛡️ Sending Defend to server...")
    
    NetworkController:Send(Events.PLAYER_DEFEND, {
        timestamp = tick(),
        isBlocking = true,
    })
end

-- ส่ง Special ไปยัง Server
function DemoController:SendSpecial()
    print("[DemoController] ✨ Sending Special to server...")
    
    NetworkController:Send(Events.PLAYER_SPECIAL, {
        timestamp = tick(),
        skillType = "Ultimate",
    })
end

-- ส่ง Ping (Demo)
function DemoController:SendPing()
    print("[DemoController] 📡 Sending Ping to server...")
    
    NetworkController:Send(Events.DEMO_PING, tick())
end

-- ส่ง Test Button
function DemoController:SendTestButton(buttonNumber: number)
    print(`[DemoController] 🔘 Sending TestButton{buttonNumber} to server...`)
    
    NetworkController:Send(Events.TEST_BUTTON_PRESSED, {
        buttonId = buttonNumber,
        playerName = player.Name,
        timestamp = tick(),
    })
end

-- สามารถเรียกจาก Console ได้
function DemoController:SendTestEventToServer()
    local buttonCounter = 1
    NetworkController:Send(Events.TEST_CLIENT_BUTTON_CLICK,"buttonCounter")
    print(`[DemoController-client] 📨 Sent TestClientButtonClick with counter {buttonCounter} to server`)
end

return DemoController
```

#### ทดสอบ Chat

```lua
-- Player1
_G.DemoController:SendChatMessage("Hello everyone!")

-- Player2
_G.DemoController:SendChatMessage("Hi Player1!")

-- Output (All Clients):
-- [CHAT] Player1: Hello everyone!
-- [CHAT] Player2: Hi Player1!
```

---

### ตัวอย่างที่ 2: ระบบ Request/Response

#### Client Request ข้อมูล

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\Controllers\DemoController.luau
// ...existing code...

function DemoController:RequestPlayerStats()
    print("[DemoController] 📊 Requesting player stats...")
    
    NetworkController:Send(Events.DEMO_REQUEST_DATA, {
        dataType = "stats",
    })
end

function DemoController:RequestServerInfo()
    print("[DemoController] 🖥️ Requesting server info...")
    
    NetworkController:Send(Events.DEMO_REQUEST_DATA, {
        dataType = "server",
    })
end

-- ...existing code...
```

#### Server Response ข้อมูล

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\Services\DemoService.luau
// ...existing code...

function DemoService:Init()
    // ...existing code...
    NetworkHandler:AllowClientEvent(Events.DEMO_REQUEST_DATA)
    NetworkHandler:AllowServerEvent(Events.DEMO_SEND_DATA)
end

function DemoService:Start()
    // ...existing code...
    
    EventBus:On(Events.DEMO_REQUEST_DATA, function(player: Player, data: any)
        local dataType = data.dataType
        print(`[DemoService] 📊 {player.Name} requested: {dataType}`)
        
        local response = {}
        
        if dataType == "stats" then
            -- ส่งข้อมูลผู้เล่น
            response = {
                playerName = player.Name,
                userId = player.UserId,
                accountAge = player.AccountAge,
                health = player.Character and player.Character.Humanoid.Health or 0,
            }
            
        elseif dataType == "server" then
            -- ส่งข้อมูล Server
            local players = game:GetService("Players")
            response = {
                totalPlayers = #players:GetPlayers(),
                uptime = os.clock(),
                maxPlayers = players.MaxPlayers,
            }
            
        else
            response = {
                error = "Unknown data type: " .. tostring(dataType)
            }
        end
        
        -- ส่งกลับไปยัง Client
        NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, response)
    end)
end

// ...existing code...
```

#### Client รับข้อมูล

```lua
// filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\StarterPlayer\StarterPlayerScripts\Controllers\DemoController.luau
// ...existing code...

function DemoController:Start()
    -- รอรับ INPUT_ACTION จาก InputController
    EventBus:On(Events.INPUT_ACTION, function(actionName: string)
        self:OnInputAction(actionName)
    end)
    
    EventBus:On(Events.DEMO_SEND_DATA, function(data: any)
        if data.error then
            warn(`[DemoController] ❌ Error: {data.error}`)
            return
        end
        
        print("[DemoController] 📊 Received data:")
        for key, value in pairs(data) do
            print(`  {key}: {value}`)
        end
    end)
end

-- ฟังก์ชันหลักที่จัดการ input
function DemoController:OnInputAction(actionName: string)
    print(`[DemoController -client] 🎮 Input detected: {actionName}`)
    
    -- แปลงเป็นตัวพิมพ์ใหญ่ทั้งหมดเพื่อให้ case-insensitive
    local action = string.upper(actionName)
    
    if action == "ATTACK" then
        self:SendAttack()
        
    elseif action == "DEFEND" then
        self:SendDefend()
        
    elseif action == "SPECIAL" then
        self:SendSpecial()
        
    elseif action == "PING" then
        self:SendPing()
        
    elseif action == "TESTBUTTON1" then
        self:SendTestButton(1)
        
    elseif action == "TESTBUTTON2" then
        self:SendTestButton(2)
        
    elseif action == "TESTBUTTON3" then
        self:SendTestButton(3)
        
    elseif action == "TESTCLICK" then
        self:SendTestEventToServer()
        
    else
        -- Actions อื่นๆ ที่ไม่ต้องส่งไปยัง server
        print(`[DemoController] ℹ️ Action '{actionName}' handled locally`)
    end
end

-- ส่ง Attack ไปยัง Server
function DemoController:SendAttack()
    print("[DemoController] ⚔️ Sending Attack to server...")
    
    NetworkController:Send(Events.PLAYER_ATTACK, {
        timestamp = tick(),
        position = player.Character and player.Character.PrimaryPart.Position or Vector3.zero,
    })
end

-- ส่ง Defend ไปยัง Server
function DemoController:SendDefend()
    print("[DemoController] 🛡️ Sending Defend to server...")
    
    NetworkController:Send(Events.PLAYER_DEFEND, {
        timestamp = tick(),
        isBlocking = true,
    })
end

-- ส่ง Special ไปยัง Server
function DemoController:SendSpecial()
    print("[DemoController] ✨ Sending Special to server...")
    
    NetworkController:Send(Events.PLAYER_SPECIAL, {
        timestamp = tick(),
        skillType = "Ultimate",
    })
end

-- ส่ง Ping (Demo)
function DemoController:SendPing()
    print("[DemoController] 📡 Sending Ping to server...")
    
    NetworkController:Send(Events.DEMO_PING, tick())
end

-- ส่ง Test Button
function DemoController:SendTestButton(buttonNumber: number)
    print(`[DemoController] 🔘 Sending TestButton{buttonNumber} to server...`)
    
    NetworkController:Send(Events.TEST_BUTTON_PRESSED, {
        buttonId = buttonNumber,
        playerName = player.Name,
        timestamp = tick(),
    })
end

-- สามารถเรียกจาก Console ได้
function DemoController:SendTestEventToServer()
    local buttonCounter = 1
    NetworkController:Send(Events.TEST_CLIENT_BUTTON_CLICK,"buttonCounter")
    print(`[DemoController-client] 📨 Sent TestClientButtonClick with counter {buttonCounter} to server`)
end

return DemoController
```

#### ทดสอบ Request/Response

```lua
-- Request player stats
_G.DemoController:RequestPlayerStats()

-- Output (Client):
-- [DemoController] 📊 Requesting player stats...
-- [DemoController] 📊 Received data:
--   playerName: Player1
--   userId: 123456
--   accountAge: 1000
--   health: 100

-- Request server info
_G.DemoController:RequestServerInfo()

-- Output (Client):
-- [DemoController] 🖥️ Requesting server info...
-- [DemoController] 📊 Received data:
--   totalPlayers: 2
--   uptime: 345.67
--   maxPlayers: 50
```

---

## 5. Data Types ที่ส่งได้

### ✅ Types ที่ปลอดภัย (Safe)

```lua
-- String
NetworkController:Send(Events.DEMO_TEST, {
    text = "Hello World"
})

-- Number
NetworkController:Send(Events.DEMO_TEST, {
    score = 100,
    health = 75.5
})

-- Boolean
NetworkController:Send(Events.DEMO_TEST, {
    isAlive = true,
    hasItem = false
})

-- Table (simple)
NetworkController:Send(Events.DEMO_TEST, {
    items = {"Sword", "Shield", "Potion"},
    stats = {hp = 100, mp = 50}
})

-- Vector3
NetworkController:Send(Events.DEMO_TEST, {
    position = Vector3.new(10, 5, 20)
})

-- Color3
NetworkController:Send(Events.DEMO_TEST, {
    color = Color3.fromRGB(255, 0, 0)
})
```

### ❌ Types ที่ห้ามส่ง (Unsafe)

```lua
-- ❌ Function
NetworkController:Send(Events.DEMO_TEST, {
    callback = function() end  -- NetworkHandler จะ reject!
})

-- ❌ Instance
NetworkController:Send(Events.DEMO_TEST, {
    part = workspace.Part  -- NetworkHandler จะ reject!
})

-- ❌ Circular reference
local t = {}
t.self = t
NetworkController:Send(Events.DEMO_TEST, t)  -- NetworkHandler จะ reject!

-- ❌ Table ที่ลึกเกินไป (> 3 levels)
NetworkController:Send(Events.DEMO_TEST, {
    a = { b = { c = { d = "too deep!" } } }  -- NetworkHandler จะ reject!
})
```

---

## 6. Best Practices (Demo Layer)

### ✅ DO's

1. **ใช้เพื่อทดสอบเท่านั้น**
   ```lua
   // ✅ GOOD - Testing network
   _G.DemoController:SendHello()
   ```

2. **Validate ข้อมูลก่อนส่ง**
   ```lua
   // ✅ GOOD
   if #message > 0 and #message <= 100 then
       NetworkController:Send(Events.DEMO_CHAT, {message = message})
   end
   ```

3. **Log ทุก action**
   ```lua
   // ✅ GOOD
   print(`[Demo] Sending {eventName}`)
   ```

### ❌ DON'Ts

1. **ห้ามใช้ใน Production**
   ```lua
   // ❌ BAD
   function GameController:Attack()
       DemoController:SendAttack()  -- ใช้ InputHandler แทน!
   end
   ```

2. **ห้ามส่งข้อมูลที่ไม่ validate**
   ```lua
   // ❌ BAD
   NetworkController:Send(Events.DEMO_TEST, userInput)  -- อาจมี exploit!
   ```

3. **ห้าม spam**
   ```lua
   // ❌ BAD
   for i = 1, 1000 do
       NetworkController:Send(Events.DEMO_TEST, {i = i})  -- Rate limit จะ block!
   end
   ```

---

## 7. Common Issues

### Issue 1: Server ไม่ได้รับข้อมูล

**อาการ:** Client ส่งแล้วแต่ Server ไม่มี log

**แก้ไข:**
```lua
// Check 1: Event allowed?
NetworkHandler:AllowClientEvent(Events.YOUR_EVENT)  // ต้องมี!

// Check 2: EventBus listener?
EventBus:On(Events.YOUR_EVENT, function(player, data)
    print("Received!")  // ต้องมี!
end)

// Check 3: Rate limit?
// ดู console - ถ้ามี warning แสดงว่าส่งเร็วเกินไป
```

---

### Issue 2: Client ไม่ได้รับข้อมูล

**อาการ:** Server ส่งแล้วแต่ Client ไม่มี log

**แก้ไข:**
```lua
// Check 1: Event allowed?
NetworkHandler:AllowServerEvent(Events.YOUR_EVENT)  // ต้องมี!

// Check 2: EventBus listener?
EventBus:On(Events.YOUR_EVENT, function(data)
    print("Received!")  // ต้องมี!
end)

// Check 3: Sent to correct player?
NetworkHandler:SendToClient(correctPlayer, ...)  // ตรวจสอบ player object
```

---

### Issue 3: Data เปลี่ยนไป

**อาการ:** ส่ง `{value = 10}` แต่ได้ `nil`

**แก้ไข:**
```lua
// Payload unsafe!
NetworkHandler จะ reject:
- Functions
- Instances
- Circular references
- Tables > depth 3
- Strings > 500 chars

// ดู server console จะมี warning
```

---

## 8. Testing Checklist

- [ ] Client สามารถส่งข้อมูลไปยัง Server
- [ ] Server รับข้อมูลและ log ได้
- [ ] Server สามารถส่งข้อมูลกลับไปยัง Client ที่ส่งมา
- [ ] Server สามารถ Broadcast ไปยัง Client ทั้งหมด
- [ ] Client ทุกคนได้รับข้อมูลจาก Broadcast
- [ ] NetworkHandler reject ข้อมูลที่ unsafe
- [ ] Rate limiting ทำงาน (ส่งเร็ว 10+ ครั้ง จะถูก block)

---

## 9. Migration to Production

เมื่อพร้อมใช้งานจริง:

```lua
// ❌ ลบ Demo
-- DemoController:SendHello()

// ✅ ใช้ Production
-- InputHandler:HandleAttack()
```

**อ่านเพิ่มเติม:** [Production Features](production-features.md)

---

*Demo Network Tutorial v1.0*
*For Testing Only - Not Production ⚠️*