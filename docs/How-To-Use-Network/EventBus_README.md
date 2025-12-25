# EventBus - ระบบสื่อสารภายในของเกม

## 📖 คำอธิบาย

EventBus เป็นระบบสื่อสารภายใน (Internal Communication System) ที่ใช้สำหรับการส่งข้อมูลระหว่าง:
- **Client-Client**: ระหว่าง Controllers ด้วยกันบน Client
- **Server-Server**: ระหว่าง Services ด้วยกันบน Server

> ⚠️ **หมายเหตุสำคัญ**: EventBus **ไม่สามารถ** ใช้สื่อสารข้ามระหว่าง Client-Server ได้ ต้องใช้ RemoteEvent/RemoteFunction แทน

## 🔧 API Reference

### EventBus:On(eventName, callback)
สมัครรับฟังอีเวนต์ (Subscribe to event)

**Parameters:**
- `eventName: string` - ชื่ออีเวนต์ที่ต้องการฟัง
- `callback: function` - ฟังก์ชันที่จะถูกเรียกเมื่ออีเวนต์เกิดขึ้น

**Returns:**
- `RBXScriptConnection` - connection object สำหรับ disconnect ภายหลัง

**ตัวอย่าง:**
```lua
local connection = EventBus:On("PlayerDied", function(playerName, cause)
    print(playerName .. " died from " .. cause)
end)

-- ถอนการสมัครเมื่อไม่ใช้แล้ว
connection:Disconnect()
```

---

### EventBus:Once(eventName, callback)
สมัครรับฟังอีเวนต์แค่ครั้งเดียว (Subscribe to event once)

**Parameters:**
- `eventName: string` - ชื่อของ event ที่ต้องการฟัง
- `callback: function` - ฟังก์ชันที่จะถูกเรียกเมื่อ event เกิดขึ้น

**Returns:**
- `RBXScriptConnection` - connection object (ถ้าต้องการยกเลิกก่อนที่จะถูกเรียก)

**ตัวอย่าง:**
```lua
EventBus:Once("GameInitialized", function()
    print("Game initialized! This will only print once.")
end)
```

---

### EventBus:Emit(eventName, ...)
ส่งอีเวนต์พร้อมข้อมูล (Emit/Fire event with data)

**Parameters:**
- `eventName: string` - ชื่อของ event ที่ต้องการส่ง
- `...: any` - ข้อมูลที่ต้องการส่งไปยัง callbacks (สามารถส่งหลาย arguments)

**ตัวอย่าง:**
```lua
-- ส่งข้อมูลเดียว
EventBus:Emit("GameStarted")

-- ส่งหลายข้อมูล
EventBus:Emit("PlayerJoined", "John", 5, true)
```

---

### EventBus:Off(eventName)
ถอนการสมัครรับฟังอีเวนต์ทั้งหมด (Unsubscribe all listeners for an event)

**Parameters:**
- `eventName: string` - ชื่อของ event ที่ต้องการถอนการสมัคร

**ตัวอย่าง:**
```lua
-- ลบ listeners ทั้งหมดของ event นี้
EventBus:Off("PlayerJoined")
```

---

### EventBus:Clear()
ลบอีเวนต์ทั้งหมดและทำความสะอาด memory (Clear all events and cleanup)

> ⚠️ **คำเตือน**: จะลบ event listeners ทั้งหมดในระบบ!

**ตัวอย่าง:**
```lua
-- ลบทุก event ในระบบ (ใช้ระวัง!)
EventBus:Clear()
```

---

### EventBus:GetEventNames()
ดูรายชื่ออีเวนต์ทั้งหมดที่มีในระบบ (Get all registered event names)

**Returns:**
- `{string}` - ตารางที่เก็บชื่อ events ทั้งหมด

**ตัวอย่าง:**
```lua
local events = EventBus:GetEventNames()
for _, eventName in ipairs(events) do
    print("Event:", eventName)
end
```

---

## 💡 Best Practices (แนวทางปฏิบัติที่ดี)

### 1. ตั้งชื่อ Event ให้มีความหมายชัด
```lua
-- ✅ ดี - ชื่อชัดเจน มีความหมาย
EventBus:Emit("Player_Died", playerName)
EventBus:Emit("UI_Opened", "MainMenu")
EventBus:Emit("Game_Started", gameMode)

-- ❌ ไม่ดี - ชื่อไม่ชัด
EventBus:Emit("event1")
EventBus:Emit("update")
EventBus:Emit("do_something")
```

### 2. ใช้ Prefix จัดกลุ่ม Events
```lua
-- UI Events
EventBus:On("UI_Opened", ...)
EventBus:On("UI_Closed", ...)

-- Player Events
EventBus:On("Player_Joined", ...)
EventBus:On("Player_Died", ...)

-- Game Events
EventBus:On("Game_Started", ...)
EventBus:On("Game_Ended", ...)
```

### 3. ใช้ Once สำหรับ Events ที่เกิดครั้งเดียว
```lua
-- ✅ ดี - ใช้ Once เพื่อป้องกัน memory leak
EventBus:Once("GameInitialized", function()
    print("Initialized!")
end)

-- ❌ ไม่ดี - ใช้ On กับ event ที่เกิดครั้งเดียว
EventBus:On("GameInitialized", function()
    print("Initialized!")
    -- connection ยังคงอยู่แม้จะไม่ถูกเรียกอีก = memory leak
end)
```

### 4. เก็บ Connections และทำ Cleanup
```lua
-- ✅ ดี - เก็บ connection และ disconnect เมื่อไม่ใช้
local MyController = {}
MyController.connections = {}

function MyController:Init()
    local conn = EventBus:On("SomeEvent", function()
        -- do something
    end)
    table.insert(self.connections, conn)
end

function MyController:Cleanup()
    for _, connection in ipairs(self.connections) do
        connection:Disconnect()
    end
    self.connections = {}
end

-- ❌ ไม่ดี - ไม่เก็บ connection, ไม่สามารถ disconnect ได้
EventBus:On("SomeEvent", function()
    -- do something
end)
```

### 5. ใช้ pcall เมื่อเรียก Events ที่อาจมี Error
```lua
-- EventBus มี built-in error handling แล้ว
-- แต่ถ้าต้องการจัดการ error เพิ่มเติมในฝั่งรับ:

EventBus:On("RiskyEvent", function(data)
    local success, result = pcall(function()
        -- โค้ดที่อาจจะเกิด error
        return processData(data)
    end)
    
    if not success then
        warn("Error processing RiskyEvent:", result)
    end
end)
```

---

## 📚 ตัวอย่างการใช้งาน

### ตัวอย่างที่ 1: การสื่อสารระหว่าง Controllers (Client-Client)

```lua
-- UIController.luau
local UIController = {}

function UIController:Init()
    -- ฟังอีเวนต์จาก Controller อื่น
    EventBus:On("ShowNotification", function(message, duration)
        self:DisplayNotification(message, duration)
    end)
end

-- GameController.luau
local GameController = {}

function GameController:OnPlayerScored(points)
    -- ส่งอีเวนต์ให้ UIController แสดงการแจ้งเตือน
    EventBus:Emit("ShowNotification", "You scored " .. points .. " points!", 3)
end
```

### ตัวอย่างที่ 2: Event Chain (เชื่อมโยง Events)

```lua
-- Service A: ฟังและส่งต่อ
EventBus:On("Player_Damaged", function(playerName, damage)
    print(playerName .. " took " .. damage .. " damage")
    
    -- ตรวจสอบว่าตายหรือยัง
    local health = getPlayerHealth(playerName)
    if health <= 0 then
        EventBus:Emit("Player_Died", playerName, "combat")
    end
end)

-- Service B: ฟังผลลัพธ์
EventBus:On("Player_Died", function(playerName, cause)
    print(playerName .. " died from " .. cause)
    -- จัดการเมื่อผู้เล่นตาย
end)
```

### ตัวอย่างที่ 3: Dynamic Events (Events แบบไดนามิก)

```lua
-- สร้าง event เฉพาะสำหรับแต่ละผู้เล่น
local function setupPlayerEvents(player)
    local userId = player.UserId
    
    -- Event เฉพาะผู้เล่นคนนี้
    EventBus:On("Player_" .. userId .. "_LevelUp", function(newLevel)
        print(player.Name .. " leveled up to " .. newLevel)
    end)
end

-- ส่ง event เฉพาะผู้เล่น
EventBus:Emit("Player_12345_LevelUp", 10)
```

### ตัวอย่างที่ 4: Debugging และ Development

```lua
-- แสดง events ทั้งหมดในระบบ
local function debugEventBus()
    local events = EventBus:GetEventNames()
    print("=== EventBus Debug Info ===")
    print("Total events:", #events)
    for i, eventName in ipairs(events) do
        print(i .. ".", eventName)
    end
    print("========================")
end

-- เรียกใช้เมื่อต้องการ debug
debugEventBus()
```

---

## ⚠️ ข้อควรระวัง

### 1. Memory Leaks
```lua
-- ❌ อันตราย: สร้าง connections ในลูปโดยไม่ cleanup
for i = 1, 100 do
    EventBus:On("SomeEvent", function()
        -- ทุกครั้งที่ลูปทำงาน จะสร้าง connection ใหม่
        -- connections เก่าจะยังอยู่ = memory leak!
    end)
end

-- ✅ ปลอดภัย: ใช้ Once หรือเก็บ connection เพื่อ cleanup
local connection = EventBus:On("SomeEvent", function() end)
-- เมื่อไม่ใช้แล้ว
connection:Disconnect()
```

### 2. Circular Dependencies
```lua
-- ❌ อันตราย: Event A เรียก Event B, Event B เรียก Event A
EventBus:On("EventA", function()
    EventBus:Emit("EventB")
end)

EventBus:On("EventB", function()
    EventBus:Emit("EventA")
end)
-- = Infinite loop!

-- ✅ ปลอดภัย: ใช้ flags หรือ conditions
local isProcessing = false

EventBus:On("EventA", function()
    if not isProcessing then
        isProcessing = true
        EventBus:Emit("EventB")
        isProcessing = false
    end
end)
```

### 3. Event Names Typos
```lua
-- ❌ อันตราย: สะกดผิด
EventBus:On("PlayerJoined", function() end)
EventBus:Emit("PlayerJoind") -- สะกดผิด! จะไม่ทำงาน

-- ✅ ปลอดภัย: ใช้ constants
local EVENTS = {
    PLAYER_JOINED = "Player_Joined",
    PLAYER_LEFT = "Player_Left",
}

EventBus:On(EVENTS.PLAYER_JOINED, function() end)
EventBus:Emit(EVENTS.PLAYER_JOINED)
```

---

## 🆚 เมื่อไหร่ควรใช้ EventBus vs RemoteEvent

### ใช้ EventBus เมื่อ:
- ✅ สื่อสารภายใน Client (Controller ↔ Controller)
- ✅ สื่อสารภายใน Server (Service ↔ Service)
- ✅ ต้องการ loose coupling ระหว่าง modules
- ✅ ต้องการให้หลาย modules รับฟังอีเวนต์เดียวกัน

### ใช้ RemoteEvent/RemoteFunction เมื่อ:
- ✅ สื่อสารข้ามระหว่าง Client ↔ Server
- ✅ ต้องการ security และ validation
- ✅ ต้องการ replication ข้อมูล

---

## 🎯 สรุป

EventBus เป็นเครื่องมือที่ทรงพลังสำหรับการสื่อสารภายในระบบ ช่วยให้โค้ดมีความเป็น modular มากขึ้น และลด coupling ระหว่าง modules

**สิ่งสำคัญที่ต้องจำ:**
1. ใช้ชื่อ events ที่มีความหมายชัด
2. ทำ cleanup connections เมื่อไม่ใช้งาน
3. ใช้ Once สำหรับ events ที่เกิดครั้งเดียว
4. ระวัง memory leaks และ circular dependencies
5. EventBus **ไม่ได้** ใช้สื่อสาร Client-Server

---

**เขียนโดย:** Game Development Team  
**อัปเดตล่าสุด:** 2024  
**เวอร์ชัน:** 1.0.0
