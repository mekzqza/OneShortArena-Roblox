# 🧪 Demo & Testing Guide

## ⚠️ Demo Components Only

เอกสารนี้ครอบคลุม **Demo/Testing components** ที่ **สามารถลบได้ในอนาคต**

**สำหรับ Production**, ดู `production-features.md`

---

## 🎯 Purpose of Demo Layer

```
┌─────────────────────────────────────────┐
│         WHY WE HAVE DEMO LAYER          │
├─────────────────────────────────────────┤
│                                         │
│  ✅ Test network communication         │
│  ✅ Verify RemoteEvent setup           │
│  ✅ Test EventBus integration          │
│  ✅ Quick prototyping                  │
│                                         │
│  ❌ NOT for production gameplay        │
│  ❌ NOT for final architecture         │
│  ❌ NO business logic                  │
│                                         │
└─────────────────────────────────────────┘
```

---

## 📁 Demo Components

### Client Side

**DemoController.luau** 🧪
```
Location: src/StarterPlayerScripts/Controllers/DemoController.luau
Status: ลบได้
Purpose: ทดสอบ network communication
```

**Features:**
- SendPing() - Test latency
- RequestData() - Test data requests
- SendChatMessage() - Test broadcasts
- ClickButton() - Test button events

### Server Side

**DemoService.luau** 🧪
```
Location: src/ServerScriptService/Services/DemoService.luau
Status: ลบได้
Purpose: Respond to demo requests
```

**Features:**
- Handle DEMO_PING
- Handle DEMO_REQUEST_DATA
- Handle DEMO_CHAT_MESSAGE
- Handle DEMO_BUTTON_CLICKED

---

## 🧪 Demo Events

### Events List (All Demo - ลบได้)

```lua
-- In Events.luau
DEMO_PING = "DemoPing",                           
DEMO_PONG = "DemoPong",                           
DEMO_REQUEST_DATA = "DemoRequestData",            
DEMO_SEND_DATA = "DemoSendData",                  
DEMO_BROADCAST_MESSAGE = "DemoBroadcastMessage",  
DEMO_CHAT_MESSAGE = "DemoChatMessage",            
DEMO_UPDATE_COUNTER = "DemoUpdateCounter",        
DEMO_BUTTON_CLICKED = "DemoButtonClicked",        
TEST_CLIENT_BUTTON_CLICK = "TestClientButtonClick",
TEST_SERVER_RESPONSE = "TestServerResponse",
```

**⚠️ ทั้งหมดนี้ลบได้เมื่อ Production พร้อม**

---

## 🎮 วิธีใช้ Demo

### Testing Network

```lua
-- In Command Bar (F9)

-- Test 1: Ping-Pong
_G.DemoController:SendPing()
→ Client: 📤 Sending PING
→ Server: 📨 Received PING
→ Client: 🏓 Received PONG (15ms)

-- Test 2: Request Data
_G.DemoController:RequestData("stats")
→ Client: 📤 Requesting data
→ Server: 📊 Sending stats
→ Client: 📊 Received data

-- Test 3: Chat
_G.DemoController:SendChatMessage("Hello!")
→ Server: 💬 Broadcasting
→ All Clients: 📢 "Hello!"

-- Test 4: Button
_G.DemoController:ClickButton("Test")
→ Server: 🖱️ Button clicked
→ All Clients: 🔢 Counter updated
```

---

## 🔄 Migration to Production

### When to Delete Demo

```
✅ Delete when:
- InputHandler fully working
- CombatService fully working
- All network tests passing
- Production components stable

❌ Keep if:
- Still prototyping
- Need quick network tests
- Production not ready
```

### How to Delete Demo

**Step 1: Remove Files**
```bash
# Delete these files:
rm Controllers/DemoController.luau
rm Services/DemoService.luau
```

**Step 2: Remove from Init files**
```lua
// Init.client.luau
-- ❌ Remove this:
-- local DemoController = require(Controllers.DemoController)
-- DemoController:Init()
-- DemoController:Start()

// Init.server.luau
-- ❌ Remove this:
-- local DemoService = require(Services.DemoService)
-- DemoService:Init()
-- DemoService:Start()
```

**Step 3: Remove Demo Events**
```lua
// Events.luau
-- ❌ Remove all DEMO_* events
```

**Step 4: Clean NetworkHandler**
```lua
// NetworkHandler.luau
-- ❌ Remove:
-- NetworkHandler:AllowClientEvent(Events.DEMO_*)
```

---

## 📊 Demo vs Production

| Aspect | Demo | Production |
|--------|------|------------|
| **Files** | DemoController, DemoService | InputHandler, CombatService |
| **Events** | DEMO_* | PLAYER_* |
| **Validation** | ❌ Minimal | ✅ Full |
| **Cooldown** | ❌ None | ✅ CooldownService |
| **Security** | ⚠️ Basic | ✅ Complete |
| **Delete?** | ✅ Yes | ❌ No |
| **Use in Game?** | ❌ No | ✅ Yes |

---

## ⚠️ Important Warnings

### ❌ DO NOT

1. **Use Demo in Production**
   ```lua
   // ❌ BAD
   if player then
       DemoController:SendTestEvent() // Demo!
   end
   ```

2. **Add Business Logic to Demo**
   ```lua
   // ❌ BAD - Demo should be simple
   function DemoService:HandleComplexGameplay(...)
       // Complex logic here
   end
   ```

3. **Depend on Demo**
   ```lua
   // ❌ BAD
   local DemoService = require(...)
   local myData = DemoService:GetData() // Don't depend on Demo
   ```

### ✅ DO

1. **Use for Quick Tests**
   ```lua
   // ✅ GOOD
   _G.DemoController:SendPing() // Quick network test
   ```

2. **Keep Simple**
   ```lua
   // ✅ GOOD - Demo stays simple
   function DemoService:HandlePing(player)
       NetworkHandler:SendToClient(player, Events.DEMO_PONG)
   end
   ```

---

## 🔗 Related Documentation

- [Production Features](production-features.md) - Production architecture
- [Quick Reference](quick-reference.md) - Production quick guide
- [Dependencies](deps.md) - System architecture

---

*Demo Testing Guide v1.0*
*For Testing Only - Not Production ⚠️*
