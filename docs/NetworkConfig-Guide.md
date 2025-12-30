# 📡 NetworkConfig Guide

## 📋 Overview

**NetworkConfig** เป็นไฟล์ configuration กลางสำหรับ NetworkHandler ที่ใช้จัดการ:
- Rate limiting (Global & Per-event)
- Security settings
- Performance tuning
- Monitoring settings

**Location:** `ServerStorage/Configs/NetworkConfig.luau`

---

## 🔧 Configuration Sections

### 1. Global Rate Limits

```lua
-- Maximum events per player per window
GlobalRateLimit = 10,      -- 10 events
GlobalRateWindow = 5,      -- per 5 seconds

-- Burst protection
BurstLimit = 3,            -- 3 events
BurstWindow = 0.5,         -- per 0.5 seconds
```

---

### 2. Per-Event Rate Limits

```lua
EventRateLimits = {
    -- Arena/Lobby (Very Strict)
    ["PlayerRequestToArena"] = {rate = 1, window = 5},
    ["PlayerRequestToLobby"] = {rate = 1, window = 5},
    
    -- Combat (Moderate)
    ["PlayerAttack"] = {rate = 10, window = 5},
    ["PlayerDefend"] = {rate = 10, window = 5},
    ["PlayerSpecial"] = {rate = 5, window = 5},
    
    -- Movement (Lenient)
    ["PlayerMove"] = {rate = 30, window = 5},
    ["PlayerJump"] = {rate = 20, window = 5},
    
    -- ...more events...
}

-- Default for unlisted events
DefaultEventRateLimit = {rate = 10, window = 5}
```

---

### 3. Security Settings

```lua
-- Strike system
MaxStrikes = 5,            -- Kick after 5 violations

-- Anti-replay
MessageIdTTL = 60,         -- Track message IDs for 60s

-- Payload limits
MaxPayloadSize = 10000,    -- 10 KB
MaxStringLength = 1000,    -- 1000 characters
MaxTableDepth = 5,         -- 5 levels deep
```

---

### 4. Logging

```lua
-- "None" | "Error" | "Warn" | "Info" | "Debug"
LogLevel = "Warn",
```

---

## 🎮 Adding New Events

```lua
-- 1. Add to Events.luau
return {
    -- ...existing...
    MY_NEW_EVENT = "MyNewEvent",
}

-- 2. Add rate limit in NetworkConfig.luau
EventRateLimits = {
    -- ...existing...
    ["MyNewEvent"] = {rate = 5, window = 5},
}

-- 3. Allow in service Init
NetworkHandler:AllowClientEvent(Events.MY_NEW_EVENT)
```

---

## 🔄 Runtime Changes

```lua
-- Change rate limit at runtime
NetworkHandler:SetEventRateLimit("MyEvent", 10, 5)

-- Get current config
local config = NetworkHandler:GetEventRateLimitConfig()

-- Get player stats
local stats = NetworkHandler:GetPlayerEventStats(player)
```

---

## 🛠️ Development Mode

Config auto-detects Studio:
```lua
if RunService:IsStudio() then
    LogLevel = "Info"      -- More verbose
    MaxStrikes = 10        -- More forgiving
    AnalyticsInterval = 30 -- More frequent
end
```

---

## 📊 Rate Limit Categories

| Category | Rate | Window | Use Case |
|----------|------|--------|----------|
| **Strict** | 1 | 5s | Teleport, Purchase |
| **Moderate** | 5-10 | 5s | Combat, UI |
| **Lenient** | 20-30 | 5s | Movement, Testing |

---

**Version:** 1.0  
**Author:** OneShortArena Team
