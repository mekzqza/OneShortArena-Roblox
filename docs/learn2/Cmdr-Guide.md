# 🐛 Cmdr Console Guide - Production Manual Install

## 📋 Overview

Cmdr เป็น **Production-grade command console** สำหรับ Roblox ที่ติดตั้งแบบ **Manual** (ไม่ใช้ Wally)

**Installation Method:** Manual (recommended for stability)  
**Activation Key:** F2 (configurable)  
**Optional:** ✅ Game works without it

---

## 🚀 Quick Start

### เปิด Cmdr Console

**กด F2** ในเกม → Cmdr Console จะขึ้นมา

---

## 📁 Installation (Manual)

### 1️⃣ Download Cmdr

```bash
# Option 1: Download ZIP
https://github.com/evaera/Cmdr/archive/refs/heads/master.zip

# Option 2: Git clone
git clone https://github.com/evaera/Cmdr.git temp_cmdr
```

### 2️⃣ Extract to ServerScriptService

```
ServerScriptService/
└── cmdr/                    ← วางที่นี่!
    ├── Cmdr.lua             ← Server module
    ├── CmdrClient.lua       ← Client module
    ├── Shared/
    ├── Types/
    ├── Commands/
    └── ...
```

### 3️⃣ สร้าง Hooks (Admin Permissions)

```
ServerScriptService/cmdr/
└── Hooks/
    └── ModuleScript         ← สร้างไฟล์นี้
```

**เนื้อหาใน ModuleScript:**

```lua
-- filepath: ServerScriptService/cmdr/Hooks/ModuleScript
local ADMINS = {
    [YOUR_ROBLOX_USER_ID] = true,  -- ใส่ User ID ของคุณ
    [8867252400] = true,            -- ตัวอย่าง
}

return function(registry)
    registry:RegisterHook("BeforeRun", function(context)
        -- Check if command requires admin
        if context.Group == "DefaultAdmin" and not ADMINS[context.Executor.UserId] then
            return "⛔ You don't have permission to run this command"
        end
    end)
end
```

**หา User ID:**
- เข้า https://www.roblox.com/users/profile
- ดูที่ URL: `roblox.com/users/YOUR_ID_HERE/profile`

### 4️⃣ Test ใน Studio

```
1. Run Game (F5)
2. กด F2
3. พิมพ์: help
4. ควรเห็นรายการคำสั่ง!
```

---

## 🏗️ Architecture

### Runtime Component

```
❌ Edit Mode (Studio - ไม่รันเกม):
   ReplicatedStorage/
   └── (ไม่มี CmdrClient!)  ← ปกติ!

✅ Play Mode (รันเกม):
   ReplicatedStorage/
   └── CmdrClient         ← CmdrService clone มาให้อัตโนมัติ!
```

**Flow:**
1. Server Start → `CmdrService:Start()`
2. Cmdr clones `CmdrClient` → `ReplicatedStorage`
3. Client Start → `CmdrController:Init()`
4. CmdrController waits for `CmdrClient` (retry 10x)
5. ✅ Ready! Press F2

---

## 📝 Built-in Commands

| Command | Description | Admin? |
|---------|-------------|--------|
| `help` | List all commands | ❌ |
| `version` | Show Cmdr version | ❌ |
| `players` | List online players | ❌ |
| `teleport <player> <x> <y> <z>` | Teleport player | ✅ |
| `kick <player> <reason>` | Kick player | ✅ |
| `kill <player>` | Kill player | ✅ |
| `respawn <player>` | Respawn player | ✅ |

---

## 🎯 Custom Commands

### สร้าง Command: `coins`

**1. สร้างโฟลเดอร์:**

```
ServerScriptService/
└── CmdrCommands/           ← สร้างโฟลเดอร์นี้
    ├── coins.lua
    └── coinsServer.lua
```

**2. Command Definition (coins.lua):**

```lua
-- filepath: ServerScriptService/CmdrCommands/coins.lua
return {
    Name = "coins",
    Aliases = {},
    Description = "Give coins to a player",
    Group = "DefaultAdmin",  -- Requires admin
    Args = {
        {
            Type = "player",
            Name = "target",
            Description = "Player to give coins",
        },
        {
            Type = "integer",
            Name = "amount",
            Description = "Amount of coins",
        },
    },
}
```

**3. Server Logic (coinsServer.lua):**

```lua
-- filepath: ServerScriptService/CmdrCommands/coinsServer.lua
local ServerScriptService = game:GetService("ServerScriptService")

return function(context, targetPlayer, amount)
    -- Get PlayerDataService
    local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)
    local PDS = ServiceLocator:Get("PlayerDataService")
    
    if not PDS then
        return "❌ PlayerDataService not available!"
    end
    
    -- Check if data loaded
    if not PDS:IsDataLoaded(targetPlayer) then
        return "❌ Player data not loaded yet!"
    end
    
    -- Give coins
    local success, newValue = PDS:Increment(targetPlayer, "Coins", amount)
    
    if success then
        return `✅ Gave {amount} coins to {targetPlayer.Name} (Total: {newValue})`
    else
        return "❌ Failed to give coins!"
    end
end
```

**4. Test:**

```
กด F2 → พิมพ์:
> coins Player1 1000
✅ Gave 1000 coins to Player1 (Total: 1000)
```

---

## 🐛 Troubleshooting

### ❌ Cmdr Console ไม่ขึ้น (กด F2 ไม่เกิดอะไร)

**สาเหตุที่เป็นไปได้:**

| ปัญหา | วิธีตรวจสอบ | วิธีแก้ |
|-------|-------------|---------|
| **Cmdr ไม่ได้ติดตั้ง** | `ServerScriptService/cmdr` มีไหม? | ติดตั้งตามขั้นตอน |
| **CmdrService ล้มเหลว** | F9 Server Output มี error? | เช็ค error log |
| **CmdrClient ยังไม่ clone** | F9 Client Output มี "retrying"? | รอให้ server clone (retry 10x) |
| **Activation key ผิด** | เปลี่ยน F2 เป็นปุ่มอื่น? | เช็ค CONFIG.ActivationKey |

**Debug Steps:**

```lua
-- F9 Console (Client)

-- 1. เช็ค CmdrClient
print(game.ReplicatedStorage:FindFirstChild("CmdrClient"))
-- ต้องไม่เป็น nil!

-- 2. เช็ค Controller
print(_G.Controllers["Core.CmdrController"])

-- 3. เช็ค Analytics
print(_G.Controllers["Core.CmdrController"]:GetAnalytics())
```

**Expected Output (Success):**

```
[CmdrController] ✅ Loaded CmdrClient (after 0 retries, 0.123s)
[CmdrController] ✅ Initialized. Press [F2] to open console
```

---

### ❌ Commands ไม่ทำงาน

**1. เช็ค Server Output:**

```
[CmdrService] ✅ Registered custom commands from CmdrCommands/
```

**2. เช็ค File Structure:**

```
ServerScriptService/CmdrCommands/
├── coins.lua           ✅ ต้องมี
└── coinsServer.lua     ✅ ต้องมี (ชื่อต้องตรง!)
```

**3. เช็ค Permissions:**

```lua
-- Hooks/ModuleScript
local ADMINS = {
    [YOUR_ROBLOX_USER_ID] = true,  -- ✅ ใส่ User ID ของคุณ!
}
```

---

## 📊 Analytics & Debug

```lua
-- F9 Console (Server)

-- Get CmdrService analytics
print(_G.Services.CmdrService:GetAnalytics())

-- Expected:
{
    loadSuccess = true,
    commandsRegistered = 2,
    hooksRegistered = 1,
    initTime = 0.015,
}
```

```lua
-- F9 Console (Client)

-- Get CmdrController analytics
print(_G.Controllers["Core.CmdrController"]:GetAnalytics())

-- Expected:
{
    loadSuccess = true,
    retries = 0,
    loadTime = 0.123,
}
```

---

## ⚙️ Configuration

### เปลี่ยน Activation Key

```lua
-- filepath: CmdrController.luau
local CONFIG = {
    ActivationKey = Enum.KeyCode.Backquote,  -- เปลี่ยนเป็น ` (backtick)
    // ...existing code...
}
```

### เพิ่ม Admin

```lua
-- filepath: ServerScriptService/cmdr/Hooks/ModuleScript
local ADMINS = {
    [123456] = true,  -- User 1
    [789012] = true,  -- User 2
    [345678] = true,  -- User 3
}
```

---

## ✅ Best Practices

```
✅ DO:
• ติดตั้งแบบ Manual (stable กว่า Wally)
• ใส่ User ID ใน Hooks/ModuleScript
• สร้าง custom commands ใน CmdrCommands/
• ใช้ F2 เป็น debug tool ใน Studio
• Test commands ใน Studio ก่อน publish

❌ DON'T:
• ใช้ Wally (structure ซับซ้อน, อาจเกิด error)
• ลืมใส่ Admin permissions
• Execute dangerous commands (delete all data)
• Share admin access กับคนที่ไม่ trust
• ปล่อย Cmdr ใน Production without security
```

---

## 🔗 Resources

- [Cmdr GitHub](https://github.com/evaera/Cmdr)
- [Cmdr Documentation](https://eryn.io/Cmdr/)
- [Creating Custom Commands](https://eryn.io/Cmdr/guide/Commands.html)

---

## 📝 Summary

```
┌─────────────────────────────────────────────────────────────────┐
│  ✅ CMDR INSTALLATION CHECKLIST                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Server:                                                        │
│  ☑️ Download Cmdr from GitHub                                   │
│  ☑️ วางใน ServerScriptService/cmdr/                             │
│  ☑️ สร้าง Hooks/ModuleScript (admin permissions)               │
│  ☑️ CmdrService.luau ทำงาน                                      │
│                                                                 │
│  Client:                                                        │
│  ☑️ CmdrController.luau ทำงาน                                   │
│  ☑️ CmdrClient ถูก clone มา ReplicatedStorage                  │
│                                                                 │
│  Testing:                                                       │
│  ☑️ Run Game → กด F2 → เห็น console                            │
│  ☑️ พิมพ์ "help" → เห็นรายการคำสั่ง                             │
│  ☑️ สร้าง custom command "coins" → ทดสอบ                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Version:** 1.0  
**Installation Method:** Manual (Production-grade)  
**Status:** ✅ Tested & Working  
**Activation Key:** F2 (configurable)

---

**Built with ❤️ for OneShortArena**