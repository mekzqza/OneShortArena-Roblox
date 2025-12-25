# 📡 Network System Documentation - Production Grade

## 🎯 Overview

ระบบสื่อสาร Client-Server แบบ Production Grade พร้อม:
- ✅ **Message Acknowledgment (ACK)** - ยืนยันว่าข้อมูลถึงปลายทาง
- ✅ **Auto-Retry System** - ส่งซ้ำอัตโนมัติถ้าไม่ได้รับ ACK
- ✅ **Anti-Replay Protection** - ป้องกันการส่งข้อมูลซ้ำ
- ✅ **Analytics Tracking** - ติดตามสถิติการใช้งาน
- ✅ **Priority Queue** - จัดลำดับความสำคัญ
- ✅ **Health Monitoring** - ตรวจสอบสุขภาพระบบ

---

## 📖 Table of Contents

1. [การส่งข้อมูลแบบปกติ (Normal Send)](#1-normal-send)
2. [การส่งข้อมูลแบบเชื่อถือได้ (Reliable Send)](#2-reliable-send)
3. [การตรวจสอบสถานะเครือข่าย (Network Health)](#3-network-health)
4. [การดู Analytics](#4-analytics)
5. [Migration Guide](#5-migration-guide)

---

## 1. Normal Send

### ใช้เมื่อไหร่?
- ข้อมูลที่ไม่สำคัญมาก (UI updates, notifications)
- ไม่ต้องการความแน่ใจ 100% ว่าถึงปลายทาง
- ต้องการ performance สูงสุด

### Client → Server

```lua
-- Old way (ยังใช้ได้)
NetworkController:Send(Events.SETTINGS_CHANGED, {
    volume = 0.5,
    graphics = "Medium"
})

-- New way (เหมือนเดิม)
NetworkController:Send(Events.SETTINGS_CHANGED, {
    volume = 0.5,
    graphics = "Medium"
})
```

### Server → Client

```lua
-- Old way (ยังใช้ได้)
NetworkHandler:SendToClient(player, Events.UI_SHOW_NOTIFICATION, {
    message = "Welcome!",
    duration = 3
})

-- New way - With Priority
NetworkHandler:BroadcastPriority(Events.UI_SHOW_NOTIFICATION, {
    message = "Game starting!",
    duration = 5
})
```

---

## 2. Reliable Send

### ใช้เมื่อไหร่?
- ข้อมูลสำคัญ (Combat actions, purchases, game results)
- ต้องการความแน่ใจว่าข้อมูลถึงปลายทาง
- ยอมรับ latency เพิ่มเล็กน้อย

### Client → Server (NEW! 🆕)

```lua
-- ส่งแบบมีการ Retry อัตโนมัติ
NetworkController:SendReliable(Events.PLAYER_ATTACK, {
    timestamp = tick(),
    position = character.PrimaryPart.Position,
    attackType = "Ultimate"
})

-- ระบุจำนวน retries (default = 3)
NetworkController:SendReliable(Events.PURCHASE_ITEM, {
    itemId = "Sword001",
    price = 100
}, 5) -- retry สูงสุด 5 ครั้ง
```

**สิ่งที่เกิดขึ้นภายใน:**
1. Client ส่งข้อมูล + messageId ไป Server
2. Client รอ ACK จาก Server (timeout 5 วินาที)
3. ถ้าไม่ได้รับ ACK → ส่งซ้ำอัตโนมัติ
4. ส่งซ้ำสูงสุด 3 ครั้ง (หรือตามที่กำหนด)
5. ถ้าเกินจำนวน retry → Emit `NETWORK_SEND_FAILED` event

### Server → Client (NEW! 🆕)

```lua
-- ส่งแบบมี ACK request + callback
NetworkHandler:SendToClientReliable(player, Events.REWARD_GRANTED, {
    itemId = "GoldCoin",
    amount = 100
}, function()
    print(`✅ Player {player.Name} confirmed reward receipt`)
    -- บันทึกลง database ว่า reward ถูกส่งสำเร็จแล้ว
end)
```

**Use Case ตัวอย่าง:**

```lua
-- Combat System
function CombatService:ProcessAttack(player: Player, targetId: number)
    local damage = 50
    local target = Players:GetPlayerByUserId(targetId)
    
    if target then
        -- ส่งแบบ Reliable เพราะเป็นข้อมูลสำคัญ
        NetworkHandler:SendToClientReliable(target, Events.TAKE_DAMAGE, {
            damage = damage,
            source = player.Name,
            timestamp = os.clock()
        }, function()
            print(`Target {target.Name} received damage notification`)
        end)
    end
end
```

---

## 3. Network Health

### ตรวจสอบสถานะเครือข่าย (Client)

```lua
-- ดูสถิติ real-time
local stats = NetworkController:GetStats()
print("Ping:", stats.ping, "ms")
print("Pending messages:", stats.pendingMessages)
print("Total sent:", stats.totalSent)

-- ตัวอย่าง Output:
-- Ping: 45 ms
-- Pending messages: 2
-- Total sent: 127
```

### ฟังเหตุการณ์ส่งล้มเหลว

```lua
EventBus:On("NETWORK_SEND_FAILED", function(eventName: string)
    warn(`Failed to send: {eventName}`)
    -- แสดง UI บอกผู้เล่นว่าเครือข่ายมีปัญหา
    UIController:ShowError("Network connection issue. Please check your internet.")
end)
```

### Force Retry ทั้งหมด

```lua
-- ถ้าเครือข่ายกลับมาปกติ แต่มี message ค้าง
NetworkController:RetryAllPending()
```

---

## 4. Analytics

### ดูสถิติการใช้งาน (Server)

```lua
-- ใน Admin Panel หรือ Command Console
local analytics = NetworkHandler:GetAnalytics()

print("Total events:", analytics.totalEvents)
print("Uptime:", analytics.uptime, "seconds")
print("Events/sec:", analytics.eventsPerSecond)

-- Event counts
for eventName, count in pairs(analytics.eventCounts) do
    print(`  {eventName}: {count}`)
end

-- Recent errors (last 100)
for _, error in ipairs(analytics.errors) do
    print(string.format("[%.2f] %s - %s", 
        error.timestamp, 
        error.player, 
        error.error
    ))
end
```

### ตรวจสอบสุขภาพระบบ

```lua
local health = NetworkHandler:GetNetworkHealth()
print("Status:", health.status) -- "Healthy" | "Warning" | "Critical"
print("Metrics:")
print("  EPS:", health.metrics.eventsPerSecond)
print("  Total Events:", health.metrics.totalEvents)
print("  Suspicious Players:", health.metrics.suspiciousPlayers)
print("  Uptime:", health.metrics.uptime, "seconds")

-- Auto-alert ถ้าสถานะไม่ดี
if health.status ~= "Healthy" then
    -- ส่ง alert ไป Discord webhook
    -- หรือบันทึก log
end
```

### Dashboard ตัวอย่าง

```lua
-- Admin Command: /network-stats
game.Players.PlayerAdded:Connect(function(player)
    if player:GetRankInGroup(YOUR_GROUP_ID) >= 250 then -- Admin only
        player.Chatted:Connect(function(msg)
            if msg == "/network-stats" then
                local health = NetworkHandler:GetNetworkHealth()
                local analytics = NetworkHandler:GetAnalytics()
                
                local report = string.format([[
=== Network Statistics ===
Status: %s
Events/Second: %.2f
Total Events: %d
Uptime: %.2f hours
Suspicious Players: %d

Top 5 Events:
]], 
                    health.status,
                    health.metrics.eventsPerSecond,
                    analytics.totalEvents,
                    analytics.uptime / 3600,
                    health.metrics.suspiciousPlayers
                )
                
                -- Sort events by count
                local sorted = {}
                for name, count in pairs(analytics.eventCounts) do
                    table.insert(sorted, {name = name, count = count})
                end
                table.sort(sorted, function(a, b) return a.count > b.count end)
                
                for i = 1, math.min(5, #sorted) do
                    report = report .. string.format("  %d. %s: %d\n", 
                        i, sorted[i].name, sorted[i].count)
                end
                
                -- Send to player
                NetworkHandler:SendToClient(player, Events.UI_SHOW_NOTIFICATION, {
                    message = report,
                    duration = 10
                })
            end
        end)
    end
end)
```

---

## 5. Migration Guide

### จากระบบเดิม → ระบบใหม่

#### ไม่ต้องเปลี่ยนแปลง (Backward Compatible)

```lua
-- ✅ โค้ดเหล่านี้ยังใช้ได้ปกติ
NetworkController:Send(eventName, data)
NetworkHandler:SendToClient(player, eventName, data)
NetworkHandler:Broadcast(eventName, data)
```

#### ควรเปลี่ยน (Recommended)

```lua
-- ❌ Old: Combat actions แบบปกติ
NetworkController:Send(Events.PLAYER_ATTACK, attackData)

-- ✅ New: ใช้ Reliable Send
NetworkController:SendReliable(Events.PLAYER_ATTACK, attackData)
```

```lua
-- ❌ Old: Broadcast แบบเดิม
NetworkHandler:Broadcast(Events.GAME_START, gameData)

-- ✅ New: Broadcast with Priority
NetworkHandler:BroadcastPriority(Events.GAME_START, gameData)
```

#### Events ที่ควรใช้ Reliable Send

- `PLAYER_ATTACK` - โจมตี
- `PLAYER_DEFEND` - ป้องกัน
- `PLAYER_SPECIAL` - สกิลพิเศษ
- `PURCHASE_ITEM` - ซื้อของ
- `TRADE_REQUEST` - แลกเปลี่ยน
- `MATCH_RESULT` - ผลการแข่งขัน
- `REWARD_CLAIM` - รับรางวัล

#### Events ที่ใช้ Normal Send ได้

- `UI_UPDATE` - อัพเดท UI
- `SETTINGS_CHANGED` - เปลี่ยนการตั้งค่า
- `CHAT_MESSAGE` - แชท (ไม่สำคัญถ้าหาย)
- `ANIMATION_TRIGGER` - เล่น animation

---

## 🔧 Configuration

### ปรับแต่ง Retry Settings (Client)

```lua
-- ใน NetworkController.luau
local MAX_RETRIES = 3        -- จำนวน retry สูงสุด
local RETRY_DELAY = 2        -- รอกี่วินาทีก่อน retry
local ACK_TIMEOUT = 5        -- รอ ACK สูงสุดกี่วินาที
```

### ปรับแต่ง Rate Limiting (Server)

```lua
-- ใน NetworkHandler:Start()
NetworkHandler:Configure({
    rateWindow = 5,          -- หน้าต่างเวลา (วินาที)
    maxPerWindow = 10,       -- event สูงสุดต่อหน้าต่าง
    debug = false            -- เปิด debug logs
})
```

---

## ⚠️ Best Practices

### DO ✅

1. **ใช้ Reliable Send สำหรับข้อมูลสำคัญ**
   ```lua
   NetworkController:SendReliable(Events.PURCHASE_ITEM, data)
   ```

2. **ตรวจสอบ Network Health เป็นระยะ**
   ```lua
   task.spawn(function()
       while true do
           task.wait(60)
           local health = NetworkHandler:GetNetworkHealth()
           if health.status ~= "Healthy" then
               -- Alert admins
           end
       end
   end)
   ```

3. **Handle NETWORK_SEND_FAILED events**
   ```lua
   EventBus:On("NETWORK_SEND_FAILED", function(eventName)
       -- แสดง error UI
       -- บันทึก log
   end)
   ```

### DON'T ❌

1. **อย่าใช้ Reliable Send สำหรับทุกอย่าง**
   - เพิ่ม latency และ bandwidth
   - ใช้เฉพาะข้อมูลสำคัญ

2. **อย่าลืม AllowClientEvent**
   ```lua
   -- Server: Init
   NetworkHandler:AllowClientEvent(Events.YOUR_NEW_EVENT)
   ```

3. **อย่าส่ง event มากเกินไป**
   - มี rate limiting อยู่แล้ว
   - แต่ควร optimize จาก client ด้วย

---

## 📊 Performance Tips

1. **Batch Events เมื่อเป็นไปได้**
   ```lua
   -- ❌ Bad: ส่งหลายครั้ง
   for i = 1, 10 do
       NetworkController:Send(Events.UPDATE_ITEM, items[i])
   end
   
   -- ✅ Good: รวมกันส่งครั้งเดียว
   NetworkController:Send(Events.UPDATE_ITEMS, {items = items})
   ```

2. **ใช้ Priority Queue อย่างชาญฉลาด**
   ```lua
   -- Combat = Priority 1 (High)
   -- UI Updates = Priority 3 (Low)
   ```

3. **Monitor Analytics**
   ```lua
   -- ถ้า EPS > 100 → ลด event frequency
   -- ถ้า Pending Messages > 10 → มีปัญหาเครือข่าย
   ```

---

## 🐛 Troubleshooting

### ปัญหา: ข้อมูลไม่ถึง Server

```lua
-- 1. ตรวจสอบว่า Allow แล้วหรือยัง
NetworkHandler:AllowClientEvent(Events.YOUR_EVENT)

-- 2. ดู pending messages
local stats = NetworkController:GetStats()
print("Pending:", stats.pendingMessages) -- ถ้า > 0 แสดงว่าติดค้าง

-- 3. ลอง retry
NetworkController:RetryAllPending()
```

### ปัญหา: Rate Limit

```lua
-- ลด frequency ของการส่ง หรือ เพิ่ม rate limit
NetworkHandler:Configure({
    maxPerWindow = 20 -- เพิ่มจาก 10 → 20
})
```

### ปัญหา: Suspicious Player Kicks

```lua
-- ดูว่าใครโดน kick
local suspicious = NetworkHandler:GetSuspiciousPlayers()
for userId, data in pairs(suspicious) do
    print(`User {userId}: {data.strikes} strikes`)
end

-- ถ้าเป็น false positive → ปรับ threshold
```

---

## 📝 Summary

| Feature | Old System | New System |
|---------|-----------|------------|
| Basic Send | ✅ | ✅ |
| Reliable Send | ❌ | ✅ NEW |
| Auto Retry | ❌ | ✅ NEW |
| ACK System | ❌ | ✅ NEW |
| Analytics | ❌ | ✅ NEW |
| Anti-Replay | ❌ | ✅ NEW |
| Priority Queue | ❌ | ✅ NEW |
| Health Monitor | ❌ | ✅ NEW |

**Backward Compatible:** ✅ โค้ดเดิมยังใช้ได้ทั้งหมด

---

**Created:** 2024  
**Version:** 2.0 - Production Grade  
**Author:** OneShortArena Team
