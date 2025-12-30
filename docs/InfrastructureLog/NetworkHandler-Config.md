# 🔧 NetworkHandler Configuration Guide

## 📋 ตารางค่า Config

| Setting | Type | Default | Testing | Production | Description |
|---------|------|---------|---------|------------|-------------|
| `DEBUG` | boolean | `false` | `true` | `false` | เปิด/ปิด debug logs |
| `RATE_LIMIT_WINDOW` | number | `5` | `10` | `5` | หน้าต่างเวลา (วินาที) |
| `MAX_EVENTS_PER_WINDOW` | number | `3` | `20` | `10-15` | Events สูงสุดต่อหน้าต่าง |
| `MAX_BURST_EVENTS` | number | `2` | `10` | `5` | Events สูงสุดใน 0.5s |
| `GLOBAL_RATE_LIMIT` | number | `100` | `500` | `100-200` | Events/sec ทั้งหมด |
| `MAX_STRING_LENGTH` | number | `1000` | `5000` | `1000-2000` | ความยาว string สูงสุด |
| `MAX_TABLE_SIZE` | number | `50` | `100` | `50-100` | Keys สูงสุดต่อ table |
| `MAX_DEPTH` | number | `5` | `10` | `5-10` | Nested depth สูงสุด |

---

## 🎯 วิธีใช้:

### 1. แก้ไขค่า Config

```lua
-- Development
local DEBUG = true
local MAX_EVENTS_PER_WINDOW = 20
local MAX_BURST_EVENTS = 10

-- Production
local DEBUG = false
local MAX_EVENTS_PER_WINDOW = 10
local MAX_BURST_EVENTS = 5
```

### 2. ใช้ Configure() Method

```lua
-- Runtime configuration
NetworkHandler:Configure({
    debug = true,
    maxPerWindow = 20,
    rateWindow = 10
})
```

---

## ⚠️ ผลกระทบของแต่ละค่า:

### เข้มงวดเกินไป:
- ❌ ผู้เล่นถูก kick บ่อย
- ❌ การเล่นไม่ลื่น
- ❌ False positives

### ผ่อนปรนเกินไป:
- ❌ Exploiter ส่ง spam ได้
- ❌ Server ถูก DDoS
- ❌ Memory overflow

### พอดี (Recommended):
- ✅ ป้องกัน spam ได้
- ✅ ผู้เล่นปกติไม่โดนเตะ
- ✅ Server ปลอดภัย

---

## 🧪 ทดสอบค่า Config:

```lua
-- F9 Console (Server)
local health = NetworkHandler:GetNetworkHealth()
print("EPS:", health.metrics.eventsPerSecond)
print("Suspicious:", health.metrics.suspiciousPlayers)

-- ถ้า EPS สูง → ลด limits
-- ถ้ามี Suspicious เยอะ → เข้มงวดขึ้น
```

---

**Version:** 2.0  
**Last Updated:** 2024
