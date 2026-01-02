# 🐛 Cmdr Console Guide - Complete Reference

## 📋 Overview

Cmdr เป็น **Production-grade command console** สำหรับ Roblox ที่ช่วยให้ developers และ admins สามารถ:
- 🔍 Debug game ได้ง่ายขึ้น
- ⚡ Execute commands แบบ real-time
- 🛠️ Admin tools สำหรับจัดการเซิร์ฟเวอร์

---

## 🚀 Quick Start

### เปิด Cmdr Console

**กด F2** ในเกม → Cmdr Console จะขึ้นมา

---

## 📁 Architecture

### Runtime Component

```
❌ Edit Mode (Studio):
   ReplicatedStorage/
   └── (ไม่มี CmdrClient!)

✅ Play Mode (Running):
   ReplicatedStorage/
   └── CmdrClient         ← Clone จาก Server อัตโนมัติ!
```

**คำอธิบาย:**
- CmdrService (Server) จะ clone `CmdrClient` ไปที่ `ReplicatedStorage`
- Client controllers จึงสามารถ `require(ReplicatedStorage.CmdrClient)` ได้

---

## 🏗️ File Structure

```
ServerScriptService/
├── cmdr/                          ← Cmdr package (ติดตั้งด้วยตัวเอง)
│   ├── Cmdr.lua                   ← Server module
│   ├── CmdrClient.lua             ← Client module
│   ├── Hooks/
│   │   └── ModuleScript           ← Admin permission checks
│   ├── Shared/
│   ├── Types/
│   └── Commands/
│
├── CmdrCommands/                  ← Custom commands (optional)
│   └── MyCommand.lua
│
└── Services/
    └── Core/
        └── CmdrService.luau       ← Wrapper service
```

---

## 🔐 Admin Permission System

### hooks/ModuleScript

```lua
-- filepath: ServerScriptService/cmdr/Hooks/ModuleScript
local ADMINS = {
    [YOUR_ROBLOX_USER_ID] = true,  -- Add your user ID
    [8867252400] = true,            -- Example admin
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

**วิธีหา User ID ของคุณ:**
1. เข้า https://www.roblox.com/users/profile
2. ดูที่ URL: `roblox.com/users/YOUR_ID_HERE/profile`

---

## 📝 Built-in Commands

| Command | Description | Example |
|---------|-------------|---------|
| `help` | List all commands | `help` |
| `version` | Show Cmdr version | `version` |
| `players` | List online players | `players` |
| `teleport` | Teleport player | `teleport Player1 0 10 0` |
| `kick` | Kick player (admin) | `kick Player1 Spamming` |
| `kill` | Kill player (admin) | `kill Player1` |
| `respawn` | Respawn player (admin) | `respawn Player1` |

---

## 🎯 Custom Commands

### สร้าง Command ใหม่

**1. สร้างโฟลเดอร์:**
```
ServerScriptService/
└── CmdrCommands/
    └── coins.lua
```

**2. Command Definition:**

```lua
-- filepath: ServerScriptService/CmdrCommands/coins.lua
return {
    Name = "coins",
    Aliases = {},
    Description = "Give coins to a player",
    Group = "DefaultAdmin",  -- Requires admin permission
    Args = {
        {
            Type = "player",
            Name = "target",
            Description = "The player to give coins to",
        },
        {
            Type = "integer",
            Name = "amount",
            Description = "Amount of coins to give",
            Optional = false,
        },
    },
}
```

**3. Command Server Script:**

```lua
-- filepath: ServerScriptService/CmdrCommands/coinsServer.lua
local ServerScriptService = game:GetService("ServerScriptService")

return function(context, targetPlayer, amount)
    -- Get PlayerDataService
    local PlayerDataService = require(ServerScriptService.Services.Data.PlayerDataService)
    
    -- Check if data loaded
    if not PlayerDataService:IsDataLoaded(targetPlayer) then
        return "❌ Player data not loaded yet!"
    end
    
    -- Give coins
    local success, newValue = PlayerDataService:Increment(targetPlayer, "Coins", amount)
    
    if success then
        return `✅ Gave {amount} coins to {targetPlayer.Name} (Total: {newValue})`
    else
        return "❌ Failed to give coins!"
    end
end
```

**4. Register in CmdrService:**

```lua
-- src/ServerScriptService/Services/Core/CmdrService.luau
function CmdrService:Start()
    // ...existing code...
    
    -- ✅ Register custom commands
    local customCommands = ServerScriptService:FindFirstChild("CmdrCommands")
    if customCommands then
        Cmdr:RegisterCommandsIn(customCommands)
        print("[CmdrService] 📋 Registered custom commands")
    end
end
```

---

## 🧪 Debug Commands

### Integration with Game Services

```lua
-- F2 Console
-- Give player 1000 coins
> coins Player1 1000

-- Check player state
> lua print(_G.Services.PlayerStateService:GetState(game.Players.Player1))

-- Get player data
> lua local data = _G.Services.PlayerDataService:GetAll(game.Players.Player1); print(data.Coins)

-- Manual sync to PocketBase
> lua _G.Services.PocketBaseService:SyncPlayer(game.Players.Player1.UserId, _G.Services.PlayerDataService:GetAll(game.Players.Player1))
```

---

## ⚙️ Configuration

### Change Activation Key

```lua
-- src/StarterPlayer/StarterPlayerScripts/Core/CmdrController.luau
function CmdrController:Init()
    -- Change F2 to another key
    CmdrClient:SetActivationKeys({ 
        Enum.KeyCode.F2,      -- Keep F2
        Enum.KeyCode.Backquote  -- Add ` (backtick)
    })
end
```

### Disable in Production

```lua
-- src/ServerScriptService/Init.server.luau
-- Comment out CmdrService for production:
-- local CmdrService = require(Core.CmdrService)
```

---

## 🐛 Troubleshooting

### Cmdr Console ไม่ขึ้น

**1. เช็ค CmdrClient ใน ReplicatedStorage:**

```lua
-- F9 Console (Client)
print(game.ReplicatedStorage:FindFirstChild("CmdrClient"))
-- ต้องไม่เป็น nil!
```

**2. เช็ค CmdrController:**

```lua
-- F9 Console (Client)
print(_G.Controllers["Core.CmdrController"])
```

**3. เช็ค Output:**

ควรเห็น:
```
[CmdrController] ✅ Loaded Cmdr Client
[CmdrController] ✅ Initialized. Press [F2]
```

---

### Commands ไม่ทำงาน

**1. เช็ค Server Output:**

```
[CmdrService] ✅ Registered custom commands
```

**2. เช็ค Command Definition:**

- ✅ ต้องมีทั้ง `coins.lua` และ `coinsServer.lua`
- ✅ ชื่อต้องตรงกัน
- ✅ Return type ต้องถูกต้อง

**3. เช็ค Permissions:**

```lua
-- hooks/ModuleScript
local ADMINS = {
    [YOUR_USER_ID] = true,  -- เพิ่ม User ID ของคุณ!
}
```

---

## 📚 Best Practices

```
✅ DO:
• ใช้ Cmdr เฉพาะใน Studio/Development
• ตั้ง admin permissions ให้ถูกต้อง
• สร้าง custom commands สำหรับ common tasks
• ใช้ `lua` command เพื่อ debug services

❌ DON'T:
• ใช้ Cmdr ใน Production without proper security
• ลืม add User ID ใน ADMINS table
• Execute dangerous commands (delete all data, etc.)
• Share admin access กับคนที่ไม่ trust
```

---

## 🔗 External Resources

- [Cmdr GitHub](https://github.com/evaera/Cmdr)
- [Cmdr Documentation](https://eryn.io/Cmdr/)
- [Creating Custom Commands](https://eryn.io/Cmdr/guide/Commands.html)

---

**Version:** 1.0  
**Last Updated:** 2024  
**Status:** ✅ Production Ready

**Installation Method:** Manual (not Wally)  
**Activation Key:** F2 (configurable)