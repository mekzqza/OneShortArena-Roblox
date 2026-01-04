# 🎯 Cmdr Custom Commands - Complete Guide

## 📋 Overview

คู่มือนี้สอนวิธีสร้าง **Custom Commands** สำหรับ Cmdr Console ที่เข้ากับระบบ **OneShortArena**

**สิ่งที่จะได้เรียนรู้:**
- ✅ โครงสร้างพื้นฐานของ Command
- ✅ การใช้ ServiceLocator
- ✅ การทำงานกับ PlayerDataService
- ✅ ตัวอย่าง Command จริง (ใช้งานได้ทันที!)

---

## 🏗️ โครงสร้างพื้นฐาน

### Command ประกอบด้วย 2 ไฟล์:

```
ServerScriptService/CmdrCommands/
├── {commandName}.lua         ← Definition (บอก Cmdr ว่า command นี้มีอะไรบ้าง)
└── {commandName}Server.lua   ← Logic (โค้ดที่ทำงานจริง)
```

**ตัวอย่าง:**
- `coins.lua` + `coinsServer.lua`
- `getdata.lua` + `getdataServer.lua`
- `setlevel.lua` + `setlevelServer.lua`

---

## 📝 Template พื้นฐาน

### 1️⃣ Command Definition Template

```lua
-- filepath: ServerScriptService/CmdrCommands/{commandName}.lua
return {
    Name = "commandname",           -- ชื่อคำสั่ง (lowercase)
    Aliases = {},                   -- ชื่อเรียกอื่นๆ (optional)
    Description = "คำอธิบาย",       -- อธิบายว่าทำอะไร
    Group = "DefaultAdmin",         -- ต้องการ admin permission
    Args = {
        {
            Type = "player",        -- ชนิดข้อมูล
            Name = "target",        -- ชื่อตัวแปร
            Description = "ผู้เล่นเป้าหมาย",
            Optional = false,       -- บังคับใส่
        },
        -- เพิ่ม arguments ตามต้องการ...
    },
}
```

### 2️⃣ Server Logic Template

```lua
-- filepath: ServerScriptService/CmdrCommands/{commandName}Server.lua
local ServerScriptService = game:GetService("ServerScriptService")

-- ✅ ใช้ ServiceLocator (อย่า require ตรง!)
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

return function(context, ...) -- arguments ตรงตาม Definition
    -- 1. Get services
    local PDS = ServiceLocator:Get("PlayerDataService")
    
    if not PDS then
        return "❌ Service ไม่พร้อม!"
    end
    
    -- 2. Validate
    -- ... เช็คข้อมูลก่อนทำงาน
    
    -- 3. Execute
    -- ... ทำงานจริง
    
    -- 4. Return result (string)
    return "✅ สำเร็จ!"
end
```

---

## 🎓 Argument Types ที่ใช้บ่อย

| Type | Description | Example Usage |
|------|-------------|---------------|
| `player` | ผู้เล่น 1 คน | `Player1` |
| `players` | ผู้เล่นหลายคน | `Player1 Player2 *` |
| `integer` | จำนวนเต็ม | `100` |
| `number` | ตัวเลข (ทศนิยมได้) | `3.14` |
| `string` | ข้อความ | `"Hello"` |
| `boolean` | true/false | `true` |

---

## 💡 ตัวอย่างจริง - พร้อมใช้งาน!

### Example 1: Give Coins Command

**1.1 Definition:**

```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\CmdrCommands\coins.lua
return {
    Name = "coins",
    Aliases = {"givemoney", "cash"},
    Description = "ให้เหรียญกับผู้เล่น",
    Group = "DefaultAdmin",
    Args = {
        {
            Type = "player",
            Name = "target",
            Description = "ผู้เล่นที่จะให้เหรียญ",
        },
        {
            Type = "integer",
            Name = "amount",
            Description = "จำนวนเหรียญ",
        },
    },
}
```

**1.2 Server Logic:**

```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\CmdrCommands\coinsServer.lua
local ServerScriptService = game:GetService("ServerScriptService")
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

return function(context, targetPlayer, amount)
    -- Get PlayerDataService
    local PDS = ServiceLocator:Get("PlayerDataService")
    
    if not PDS then
        return "❌ PlayerDataService ไม่พร้อม!"
    end
    
    -- Check if data loaded
    if not PDS:IsDataLoaded(targetPlayer) then
        return `❌ ข้อมูลของ {targetPlayer.Name} ยังไม่โหลด!`
    end
    
    -- Give coins
    local success, newValue = PDS:Increment(targetPlayer, "Coins", amount)
    
    if success then
        return `✅ ให้ {amount} เหรียญกับ {targetPlayer.Name} สำเร็จ! (รวม: {newValue})`
    else
        return "❌ ไม่สามารถให้เหรียญได้!"
    end
end
```

**ทดสอบ:**
```
> coins Player1 1000
✅ ให้ 1000 เหรียญกับ Player1 สำเร็จ! (รวม: 1000)
```

---

### Example 2: Get Data Command (ดูข้อมูลผู้เล่น)

**2.1 Definition:**

```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\CmdrCommands\getdata.lua
return {
    Name = "getdata",
    Aliases = {"data", "stats"},
    Description = "ดูข้อมูลผู้เล่น",
    Group = "DefaultAdmin",
    Args = {
        {
            Type = "player",
            Name = "target",
            Description = "ผู้เล่นที่จะดูข้อมูล",
            Optional = true,  -- ✅ ไม่ใส่ = ดูตัวเอง
        },
    },
}
```

**2.2 Server Logic:**

```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\CmdrCommands\getdataServer.lua
local ServerScriptService = game:GetService("ServerScriptService")
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

return function(context, targetPlayer)
    -- ถ้าไม่ระบุ target ใช้ตัวเอง
    targetPlayer = targetPlayer or context.Executor
    
    local PDS = ServiceLocator:Get("PlayerDataService")
    if not PDS then
        return "❌ PlayerDataService ไม่พร้อม!"
    end
    
    -- Get all data
    local data = PDS:GetAll(targetPlayer)
    if not data then
        return `❌ ไม่พบข้อมูลของ {targetPlayer.Name}!`
    end
    
    -- Format output
    local output = {
        `📊 ข้อมูลของ {targetPlayer.Name}:`,
        `━━━━━━━━━━━━━━━━━━━━━━━━━━━━`,
        `💰 เหรียญ: {data.Coins}`,
        `💎 เจมส์: {data.Gems}`,
        `⭐ เลเวล: {data.Level} (XP: {data.Experience})`,
        ``,
        `⚔️ สถิติการต่อสู้:`,
        `  • ฆ่า: {data.Kills}`,
        `  • ตาย: {data.Deaths}`,
        `  • ชนะ: {data.Wins}`,
        `  • แพ้: {data.Losses}`,
        ``,
        `🎒 ไอเท็ม: {PDS:GetItemCount(targetPlayer)} ชิ้น`,
    }
    
    return table.concat(output, "\n")
end
```

**ทดสอบ:**
```
> getdata
📊 ข้อมูลของ Sukpatzqza:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💰 เหรียญ: 0
💎 เจมส์: 0
⭐ เลเวล: 1 (XP: 0)

⚔️ สถิติการต่อสู้:
  • ฆ่า: 0
  • ตาย: 0
  • ชนะ: 0
  • แพ้: 0

🎒 ไอเท็ม: 0 ชิ้น

> getdata Player1
📊 ข้อมูลของ Player1:
...
```

---

### Example 3: Set Level Command

**3.1 Definition:**

```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\CmdrCommands\setlevel.lua
return {
    Name = "setlevel",
    Aliases = {"level"},
    Description = "ตั้งเลเวลให้ผู้เล่น",
    Group = "DefaultAdmin",
    Args = {
        {
            Type = "player",
            Name = "target",
            Description = "ผู้เล่นเป้าหมาย",
        },
        {
            Type = "integer",
            Name = "level",
            Description = "เลเวลใหม่ (1-100)",
        },
    },
}
```

**3.2 Server Logic:**

```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\CmdrCommands\setlevelServer.lua
local ServerScriptService = game:GetService("ServerScriptService")
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

return function(context, targetPlayer, level)
    local PDS = ServiceLocator:Get("PlayerDataService")
    
    if not PDS then
        return "❌ PlayerDataService ไม่พร้อม!"
    end
    
    -- Validate level (1-100)
    if level < 1 or level > 100 then
        return "❌ เลเวลต้องอยู่ระหว่าง 1-100!"
    end
    
    -- Check if data loaded
    if not PDS:IsDataLoaded(targetPlayer) then
        return `❌ ข้อมูลของ {targetPlayer.Name} ยังไม่โหลด!`
    end
    
    -- Set level
    local success = PDS:Set(targetPlayer, "Level", level)
    
    if success then
        return `✅ ตั้งเลเวล {targetPlayer.Name} เป็น {level} สำเร็จ!`
    else
        return "❌ ไม่สามารถตั้งเลเวลได้!"
    end
end
```

---

### Example 4: Reset Data Command

**4.1 Definition:**

```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\CmdrCommands\resetdata.lua
return {
    Name = "resetdata",
    Aliases = {},
    Description = "รีเซ็ตข้อมูลผู้เล่น (อันตราย!)",
    Group = "DefaultAdmin",
    Args = {
        {
            Type = "player",
            Name = "target",
            Description = "ผู้เล่นที่จะรีเซ็ต",
        },
        {
            Type = "string",
            Name = "confirm",
            Description = 'พิมพ์ "CONFIRM" เพื่อยืนยัน',
        },
    },
}
```

**4.2 Server Logic:**

```lua
-- filepath: c:\TDM-GCC-64\test\งาน\ProjectRoblox02\OneShortArena-Roblox\src\ServerScriptService\CmdrCommands\resetdataServer.lua
local ServerScriptService = game:GetService("ServerScriptService")
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

return function(context, targetPlayer, confirm)
    -- Safety check
    if confirm ~= "CONFIRM" then
        return `❌ ต้องพิมพ์ "CONFIRM" เพื่อยืนยัน!`
    end
    
    local PDS = ServiceLocator:Get("PlayerDataService")
    
    if not PDS then
        return "❌ PlayerDataService ไม่พร้อม!"
    end
    
    if not PDS:IsDataLoaded(targetPlayer) then
        return `❌ ข้อมูลของ {targetPlayer.Name} ยังไม่โหลด!`
    end
    
    -- Reset all stats
    local success = true
    
    success = success and PDS:Set(targetPlayer, "Coins", 0)
    success = success and PDS:Set(targetPlayer, "Gems", 0)
    success = success and PDS:Set(targetPlayer, "Level", 1)
    success = success and PDS:Set(targetPlayer, "Experience", 0)
    success = success and PDS:Set(targetPlayer, "Kills", 0)
    success = success and PDS:Set(targetPlayer, "Deaths", 0)
    success = success and PDS:Set(targetPlayer, "Wins", 0)
    success = success and PDS:Set(targetPlayer, "Losses", 0)
    
    if success then
        return `✅ รีเซ็ตข้อมูล {targetPlayer.Name} สำเร็จ!`
    else
        return "❌ รีเซ็ตข้อมูลล้มเหลว!"
    end
end
```

---

## 🎯 Special Shorthands

Cmdr รองรับ shorthand สำหรับ player arguments:

| Shorthand | Meaning | Example |
|-----------|---------|---------|
| `.` | ตัวเอง (Me) | `coins . 1000` |
| `*` | ทุกคน (All) | `coins * 100` |
| `**` | คนอื่นทั้งหมด | `kill **` |
| `?` | สุ่ม 1 คน | `teleport ? 0 10 0` |
| `?3` | สุ่ม 3 คน | `coins ?3 500` |

---

## ✅ Best Practices

```
✅ DO:
• ใช้ ServiceLocator แทน require ตรง
• เช็คว่า Service พร้อมก่อนใช้
• Validate input ทุกครั้ง (level 1-100, amount > 0)
• Return ข้อความที่ชัดเจน (มี emoji)
• ใส่ Optional = true สำหรับ arg ที่ไม่บังคับ
• ใช้ pcall สำหรับ risky operations

❌ DON'T:
• Require service ตรงใน command
• ลืมเช็ค IsDataLoaded()
• Return error แบบไม่มีข้อความ
• ทำงานหนักเกินไป (block server)
• Hardcode values (ใช้ config)
```

---

## 🧪 การทดสอบ Command

### 1. เช็คว่า Command ขึ้นหรือไม่

```
กด F2 → พิมพ์:
> help

ควรเห็น command ของคุณใน list!
```

### 2. ทดสอบ Error Cases

```
> coins
This command has required arguments.

> coins InvalidPlayer 100
Player not found: InvalidPlayer

> coins Player1 -100
❌ จำนวนต้องมากกว่า 0!
```

### 3. ทดสอบ Happy Path

```
> coins . 1000
✅ ให้ 1000 เหรียญกับ Sukpatzqza สำเร็จ! (รวม: 1000)

> getdata
📊 ข้อมูลของ Sukpatzqza:
...เห็นเหรียญ 1000...
```

---

## 🐛 Troubleshooting

### ❌ Command ไม่ขึ้นใน help

**สาเหตุ:**
- ไฟล์ไม่ได้อยู่ใน `CmdrCommands/`
- ไฟล์ชื่อไม่ตรงกัน (`coins.lua` ≠ `coinsServer.lua`)
- Syntax error ในไฟล์

**วิธีแก้:**
```lua
-- F9 Server Console
-- เช็ค CmdrService
print(_G.Services.CmdrService:GetAnalytics())

-- Restart Studio
```

---

### ❌ Command รันแล้ว error

**สาเหตุ:**
- Service ไม่พร้อม
- Data ไม่โหลด
- Validation ผิดพลาด

**วิธี Debug:**
```lua
-- เพิ่มใน Server Logic
return function(context, ...)
    print("Args:", ...)  -- Debug args
    
    local PDS = ServiceLocator:Get("PlayerDataService")
    print("PDS:", PDS)  -- Check if loaded
    
    -- ... rest of code
end
```

---

## 📚 Resources

- [Cmdr GitHub](https://github.com/evaera/Cmdr)
- [Cmdr Documentation](https://eryn.io/Cmdr/)
- [ServiceLocator Guide](./Data-System-Guide.md)
- [PlayerDataService API](./Data-System-Guide.md#api-reference)

---

## 🎯 Challenge: สร้าง Command เอง!

ลองสร้าง command เหล่านี้เพื่อฝึกฝน:

```
☐ giveitem <player> <itemId>       - ให้ไอเท็มกับผู้เล่น
☐ removeitem <player> <itemId>     - เอาไอเท็มออก
☐ setexp <player> <amount>         - ตั้ง Experience
☐ addkill <player> [amount]        - เพิ่ม Kills (default 1)
☐ leaderboard [stat]               - แสดง top 10 players
```

**Hint:** ใช้ Template ด้านบนแล้วปรับแต่งตามต้องการ!

---

**Version:** 1.0  
**Last Updated:** 2024  
**Status:** ✅ Production Ready

**Happy Commanding!** 🎮✨
