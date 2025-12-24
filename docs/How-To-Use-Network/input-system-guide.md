# 🎮 Input System Guide

## 📖 Overview

ระบบ Input ของ OneShortArena ประกอบด้วย 3 ส่วนหลัก:

```
┌─────────────────────────────────────────────────────────┐
│                    INPUT SYSTEM                          │
└─────────────────────────────────────────────────────────┘

Player Input (Keyboard/Mobile)
         │
         ▼
┌─────────────────────┐
│  InputController    │  ← จับ input จาก hardware
│  (Client)           │
└─────────────────────┘
         │
         │ EventBus:Emit(INPUT_ACTION)
         ▼
┌─────────────────────┐
│  DemoController     │  ← แปลง input เป็น game actions
│  (Client)           │
└─────────────────────┘
         │
         │ NetworkController:Send()
         ▼
┌─────────────────────┐
│  NetworkHandler     │  ← Validate & Security
│  (Server)           │
└─────────────────────┘
         │
         │ EventBus:Emit()
         ▼
┌─────────────────────┐
│  DemoService        │  ← ประมวลผล game logic
│  (Server)           │
└─────────────────────┘
```

---

## 🏗️ Architecture

### 1. InputController (Client)

**ไฟล์:** `src/StarterPlayer/StarterPlayerScripts/Controllers/InputController.luau`

**หน้าที่:**
- จับ keyboard/mobile input ผ่าน `ContextActionService`
- แปลง hardware input เป็น action names
- ส่งต่อผ่าน EventBus (ไม่ส่งไปยัง server โดยตรง)

**ไม่รับผิดชอบ:**
- ❌ การส่งข้อมูลไปยัง Server
- ❌ Game logic หรือ validation
- ❌ UI feedback

**Example Usage:**
```lua
-- InputController จับปุ่ม E และส่ง event
EventBus:Emit(Events.INPUT_ACTION, "Attack")
```

---

### 2. DemoController (Client)

**ไฟล์:** `src/StarterPlayer/StarterPlayerScripts/Controllers/DemoController.luau`

**หน้าที่:**
- รับ INPUT_ACTION events จาก InputController
- แปลงเป็น game-specific actions พร้อม metadata
- ส่งไปยัง Server ผ่าน NetworkController
- รับและแสดง response จาก Server

**Example:**
```lua
-- รับ "Attack" input และส่งไปยัง Server พร้อม metadata
function DemoController:SendAttack()
    NetworkController:Send(Events.PLAYER_ATTACK, {
        timestamp = tick(),
        position = player.Character.PrimaryPart.Position,
    })
end
```

---

### 3. DemoService (Server)

**ไฟล์:** `src/ServerScriptService/Services/DemoService.luau`

**หน้าที่:**
- รับ player actions จาก NetworkHandler
- Validate ข้อมูล (cooldown, resources, state)
- ประมวลผล game logic
- ส่ง response กลับไปยัง Client

**Example:**
```lua
EventBus:On(Events.PLAYER_ATTACK, function(player: Player, data: any)
    -- Validate
    if not canAttack(player) then return end
    
    -- Process
    local damage = calculateDamage(player)
    
    -- Respond
    NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, {
        damage = damage,
        success = true,
    })
end)
```

---

## 📋 Input Configuration

### InputSettings.luau

**ไฟล์:** `src/ReplicatedStorage/Shared/InputSettings.luau`

กำหนด key bindings และชื่อปุ่มบนมือถือ:

```lua
return {
    Bindings = {
        Attack = { Enum.KeyCode.E, Enum.KeyCode.ButtonR1 },
        Defend = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL1 },
        Special = { Enum.KeyCode.R, Enum.KeyCode.ButtonY },
        Ping = { Enum.KeyCode.P },
    },
    
    MobileButtonNames = {
        Attack = "⚔️ Attack",
        Defend = "🛡️ Defend",
        Special = "✨ Special",
        Ping = "📡 Ping",
    },
}
```

**การเพิ่มปุ่มใหม่:**
1. เพิ่มใน `Bindings` (สามารถผูกหลายปุ่มได้)
2. เพิ่มใน `MobileButtonNames` (ถ้าต้องการแสดงบนมือถือ)

---

## 🔄 Data Flow Examples

### Example 1: Simple Action (Ping)

```
1. Player กดปุ่ม "P"
   │
   ▼
2. InputController:
   ContextActionService จับ input
   │
   ▼
3. InputController:
   EventBus:Emit(INPUT_ACTION, "Ping")
   │
   ▼
4. DemoController:
   รับ event และเรียก SendPing()
   │
   ▼
5. DemoController:
   NetworkController:Send(DEMO_PING, tick())
   │
   ▼
6. NetworkHandler (Server):
   - Rate limit check ✅
   - Whitelist check ✅
   - Payload validation ✅
   │
   ▼
7. DemoService (Server):
   คำนวณ latency และส่งกลับ
   │
   ▼
8. DemoController (Client):
   แสดงผลลัพธ์ใน console
```

---

### Example 2: Complex Action (Attack)

```
1. Player กดปุ่ม "E"
   │
   ▼
2. InputController:
   EventBus:Emit(INPUT_ACTION, "Attack")
   │
   ▼
3. DemoController:
   สร้าง attack data packet:
   {
       timestamp = tick(),
       position = Vector3,
   }
   │
   ▼
4. NetworkController:
   RemoteEvent:FireServer(PLAYER_ATTACK, data)
   │
   ▼
5. NetworkHandler (Server):
   Security validation layers
   │
   ▼
6. DemoService (Server):
   - Check cooldown ⏰
   - Validate position 📍
   - Calculate damage 🎲
   - Update game state 💾
   - Broadcast to other players 📢
   │
   ▼
7. NetworkHandler → Client:
   Send response back
   │
   ▼
8. DemoController (Client):
   Update UI / Play effects
```

---

## 🎯 Common Use Cases

### Use Case 1: เพิ่ม Action ใหม่

**Scenario:** ต้องการเพิ่มปุ่ม "Dodge" (กด Spacebar)

**ขั้นตอน:**

**1. เพิ่มใน InputSettings.luau:**
```lua
Bindings = {
    -- ...existing code...
    Dodge = { Enum.KeyCode.Space },
},

MobileButtonNames = {
    -- ...existing code...
    Dodge = "🏃 Dodge",
},
```

**2. เพิ่ม Event ใน Events.luau:**
```lua
-- Input Events
PLAYER_DODGE = "PlayerDodge",
```

**3. เพิ่มใน DemoController.luau:**
```lua
function DemoController:OnInputAction(actionName: string)
    -- ...existing code...
    elseif actionName == "Dodge" then
        self:SendDodge()
end

function DemoController:SendDodge()
    print("[DemoController] 🏃 Sending Dodge to server...")
    NetworkController:Send(Events.PLAYER_DODGE, {
        timestamp = tick(),
        direction = getMovementDirection(),
    })
end
```

**4. เพิ่มใน DemoService.luau:**
```lua
function DemoService:Init()
    -- ...existing code...
    NetworkHandler:AllowClientEvent(Events.PLAYER_DODGE)
end

function DemoService:Start()
    -- ...existing code...
    EventBus:On(Events.PLAYER_DODGE, function(player: Player, data: any)
        print(`[DemoService] 🏃 {player.Name} dodged`)
        
        -- Process dodge logic
        local success = performDodge(player, data.direction)
        
        NetworkHandler:SendToClient(player, Events.DEMO_SEND_DATA, {
            action = "Dodge",
            success = success,
        })
    end)
end
```

---

### Use Case 2: Mobile-Only Button

**Scenario:** ต้องการปุ่มพิเศษสำหรับมือถือเท่านั้น

**InputSettings.luau:**
```lua
Bindings = {
    -- ไม่มี keyboard binding
    MobileSpecial = {},
},

MobileButtonNames = {
    MobileSpecial = "📱 Mobile Only",
},
```

**Note:** ปุ่มนี้จะแสดงแค่บนมือถือ และต้องเรียกใช้ผ่าน UI button

---

### Use Case 3: Combo/Hold Actions

**Scenario:** ต้องการจับ "กดค้าง" หรือ "combo"

**InputController.luau:**
```lua
local holdStartTime = {}

local function onInputAdvanced(actionName: string, inputState: Enum.UserInputState)
    local userId = Players.LocalPlayer.UserId
    
    if inputState == Enum.UserInputState.Begin then
        holdStartTime[actionName] = tick()
        EventBus:Emit(Events.INPUT_ACTION, actionName)
        
    elseif inputState == Enum.UserInputState.End then
        local holdDuration = tick() - (holdStartTime[actionName] or 0)
        
        if holdDuration > 1.0 then
            -- Held for 1+ seconds
            EventBus:Emit(Events.INPUT_ACTION, actionName .. "Hold")
        end
        
        holdStartTime[actionName] = nil
    end
end
```

---

## 🔐 Security Considerations

### ✅ DO's

1. **Server-side validation:**
   ```lua
   -- Always validate on server
   if not player.Character or not player.Character:FindFirstChild("Humanoid") then
       return -- Don't process
   end
   ```

2. **Cooldown enforcement:**
   ```lua
   local lastAttackTime = {}
   
   if (tick() - (lastAttackTime[player.UserId] or 0)) < ATTACK_COOLDOWN then
       return -- Too soon
   end
   ```

3. **Resource checks:**
   ```lua
   local profile = ProfileService:GetProfile(player)
   if profile.Data.Stamina < ATTACK_COST then
       return -- Not enough stamina
   end
   ```

### ❌ DON'Ts

1. **ห้ามเชื่อ Client timestamp:**
   ```lua
   -- ❌ BAD
   local clientTime = data.timestamp
   if tick() - clientTime > 1 then
       -- Client can fake this!
   end
   
   -- ✅ GOOD
   local serverTime = tick()
   if serverTime - lastActionTime[player.UserId] < COOLDOWN then
       return
   end
   ```

2. **ห้ามส่ง sensitive data:**
   ```lua
   -- ❌ BAD - sending enemy HP to client
   NetworkHandler:SendToClient(player, Events.ENEMY_DATA, {
       enemyHP = enemy.Humanoid.Health,
       enemyPosition = enemy.PrimaryPart.Position,
   })
   
   -- ✅ GOOD - only send what player needs to see
   NetworkHandler:SendToClient(player, Events.ENEMY_DATA, {
       isAlive = enemy.Humanoid.Health > 0,
       lastKnownPosition = enemy.PrimaryPart.Position,
   })
   ```

---

## 🧪 Testing Guide

### Manual Testing

**1. Open Developer Console (F9)**

**2. Test each action:**
| Key | Expected Output (Client) | Expected Output (Server) |
|-----|--------------------------|--------------------------|
| E | `🎮 Input detected: Attack` | `⚔️ Player1 attacked` |
| Q | `🎮 Input detected: Defend` | `🛡️ Player1 is defending` |
| R | `🎮 Input detected: Special` | `✨ Player1 used special` |
| P | `🎮 Input detected: Ping` | `📨 Received PING from Player1` |

**3. Check for spam protection:**
```
กด E 20 ครั้งติดกัน
→ ควรเห็น rate limit warning หลังจาก 10 ครั้ง
```

---

### Automated Testing (Future)

```lua
-- Example test case
local function testAttackAction()
    local mockPlayer = createMockPlayer()
    
    -- Simulate attack input
    DemoService:HandleAttack(mockPlayer, {
        timestamp = tick(),
        position = Vector3.new(0, 5, 0),
    })
    
    -- Assert
    assert(mockPlayer.ReceivedEvents[1].eventName == Events.DEMO_SEND_DATA)
    assert(mockPlayer.ReceivedEvents[1].data.success == true)
end
```

---

## 📊 Performance Tips

### 1. Debounce Rapid Inputs

```lua
-- In InputController
local lastInputTime = {}
local DEBOUNCE_TIME = 0.1

local function onInputDebounced(actionName: string, inputState: Enum.UserInputState)
    if inputState == Enum.UserInputState.Begin then
        local now = tick()
        if (now - (lastInputTime[actionName] or 0)) < DEBOUNCE_TIME then
            return -- Ignore rapid inputs
        end
        lastInputTime[actionName] = now
        EventBus:Emit(Events.INPUT_ACTION, actionName)
    end
end
```

---

### 2. Batch Multiple Actions

```lua
-- Instead of sending each action immediately
local actionQueue = {}

task.spawn(function()
    while true do
        task.wait(0.1) -- Send batch every 100ms
        if #actionQueue > 0 then
            NetworkController:Send(Events.BATCH_ACTIONS, actionQueue)
            actionQueue = {}
        end
    end
end)
```

---

## 🐛 Common Issues & Solutions

### Issue 1: Input ไม่ทำงาน

**อาการ:** กดปุ่มแล้วไม่มีอะไรเกิดขึ้น

**แก้ไข:**
1. ✅ Check InputController ถูก Start แล้ว
2. ✅ Check Events.luau มี INPUT_ACTION
3. ✅ Check DemoController มี EventBus:On(INPUT_ACTION)
4. ✅ Check console ดูว่ามี error

**Debug Command:**
```lua
-- In Command Bar
print(game.StarterPlayer.StarterPlayerScripts.Controllers.InputController)
```

---

### Issue 2: Server ไม่ได้รับ Event

**อาการ:** Client log แสดง "Sending to server" แต่ Server ไม่มี log

**แก้ไข:**
1. ✅ Check NetworkHandler:AllowClientEvent(Events.PLAYER_ATTACK)
2. ✅ Check DemoService มี EventBus:On(Events.PLAYER_ATTACK)
3. ✅ Check rate limit (กดปุ่มเร็วเกินไป)

---

### Issue 3: Mobile Button ไม่แสดง

**อาการ:** ปุ่มไม่ปรากฏบน mobile device

**แก้ไข:**
1. ✅ เพิ่มชื่อใน MobileButtonNames
2. ✅ เช็คว่า ContextActionService:SetTitle() ถูกเรียก
3. ✅ ทดสอบบน mobile emulator

---

## 📚 Additional Resources

- [Roblox ContextActionService Docs](https://create.roblox.com/docs/reference/engine/classes/ContextActionService)
- [Input Best Practices](https://create.roblox.com/docs/input)
- Backend Agent: `.github/agents/gameplay-backend.md`
- Quick Reference: `docs/quick-reference.md`

---

## 🔄 Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024 | Initial input system |

---

*Input System Guide v1.0*
*Last Updated: 2024*