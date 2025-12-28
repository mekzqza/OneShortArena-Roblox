# 🚀 EventBus Usage Guide - Production Grade (Signal-Based)

## 📋 Overview

**EventBus** เป็นระบบ Event Communication ที่ใช้ **Signal Library** ซึ่งเป็น Production-grade implementation

### ✨ New Features (Signal-Based):

- ✅ **Better Performance** - Signal library optimized สำหรับ Roblox
- ✅ **Type Safety** - Full type support
- ✅ **Memory Efficient** - Auto cleanup connections
- ✅ **Error Handling** - Built-in error isolation
- ✅ **Analytics** - Track emits, subscribes, errors
- ✅ **Listener Count** - Query active listeners

---

## 🚀 Quick Start

### Basic Usage

```lua
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)

-- Subscribe
local connection = EventBus:On("PlayerJoined", function(playerName, level)
    print(playerName, "joined with level", level)
end)

-- Emit
EventBus:Emit("PlayerJoined", "John", 5)

-- Unsubscribe
connection:Disconnect()
```

---

## 📖 API Reference

### Core Methods

#### `EventBus:On(eventName: string, callback: function): SignalConnection`

Subscribe to event. Returns connection object.

```lua
local conn = EventBus:On("GameStart", function(gameMode)
    print("Game started:", gameMode)
end)

-- Later: disconnect
conn:Disconnect()
```

---

#### `EventBus:Once(eventName: string, callback: function): SignalConnection`

Subscribe once (auto-disconnects after first fire)

```lua
EventBus:Once("FirstTimeSetup", function()
    print("Setup complete!")
end)
```

---

#### `EventBus:Emit(eventName: string, ...args: any)`

Fire event with data

```lua
EventBus:Emit("PlayerDied", player, {
    killer = otherPlayer,
    weapon = "Sword"
})
```

---

#### `EventBus:Off(eventName: string)`

Disconnect ALL listeners for event

```lua
EventBus:Off("PlayerJoined")  -- All listeners disconnected
```

---

### Utility Methods

#### `EventBus:GetEventNames(): {string}`

Get all registered event names

```lua
local events = EventBus:GetEventNames()
for _, name in events do
    print("Event:", name)
end
```

---

#### `EventBus:GetListenerCount(eventName: string): number`

Get number of active listeners

```lua
local count = EventBus:GetListenerCount("PlayerJoined")
print("Active listeners:", count)
```

---

#### `EventBus:GetAnalytics(): table`

Get analytics data

```lua
local analytics = EventBus:GetAnalytics()
print("Total emits:", analytics.totalEmits)
print("Emits/sec:", analytics.emitsPerSecond)
print("Errors:", #analytics.errors)
```

---

#### `EventBus:PrintSummary()`

Print debug summary

```lua
EventBus:PrintSummary()
```

**Output:**
```
╔════════════════════════════════════════════════════════════════╗
║                    EVENTBUS SUMMARY                            ║
╠════════════════════════════════════════════════════════════════╣
║ Total Events: 5
║ Total Emits: 127
║ Emits/sec: 2.54
║ Uptime: 50.00s
╠════════════════════════════════════════════════════════════════╣
║ Events:
║   PlayerJoined                    Listeners: 3, Emits: 45
║   PlayerDied                      Listeners: 2, Emits: 12
╚════════════════════════════════════════════════════════════════╝
```

---

## 💡 Best Practices

### ✅ DO

```lua
-- 1. Store connections for cleanup
local connections = {}

function MyController:Init()
    table.insert(connections, EventBus:On("Event1", handler1))
    table.insert(connections, EventBus:On("Event2", handler2))
end

function MyController:Cleanup()
    for _, conn in connections do
        conn:Disconnect()
    end
end

-- 2. Use Once for one-time events
EventBus:Once("GameInitialized", function()
    -- Runs only once
end)

-- 3. Validate event names
local Events = require(ReplicatedStorage.Shared.Events)
EventBus:Emit(Events.PLAYER_JOINED, data)  -- ✅ Type-safe
```

### ❌ DON'T

```lua
-- 1. Don't forget to disconnect
EventBus:On("Event", handler)  -- ❌ Memory leak!

-- 2. Don't emit undefined events
EventBus:Emit(nil, data)  -- ❌ Error!

-- 3. Don't use string literals
EventBus:Emit("PlayerJoined", data)  -- ❌ Typo-prone
```

---

## 🎓 Advanced Usage

### Error Handling

```lua
-- Errors in listeners are isolated
EventBus:On("PlayerJoined", function()
    error("This error won't crash other listeners!")
end)

EventBus:On("PlayerJoined", function()
    print("This still runs!")  -- ✅ Still executes
end)

-- Check errors
local analytics = EventBus:GetAnalytics()
for _, err in analytics.errors do
    warn("Error:", err.event, err.error)
end
```

---

### Connection Management

```lua
local MyService = {}
MyService.connections = {}

function MyService:Init()
    -- Store all connections
    self.connections.playerJoined = EventBus:On("PlayerJoined", function(...)
        self:OnPlayerJoined(...)
    end)
    
    self.connections.gameStart = EventBus:Once("GameStart", function()
        self:OnGameStart()
    end)
end

function MyService:Cleanup()
    -- Disconnect all
    for _, conn in pairs(self.connections) do
        conn:Disconnect()
    end
    self.connections = {}
end
```

---

### Analytics Monitoring

```lua
-- Track event usage
task.spawn(function()
    while true do
        task.wait(60)  -- Every minute
        
        local analytics = EventBus:GetAnalytics()
        
        if analytics.emitsPerSecond > 50 then
            warn("High event rate detected!")
        end
        
        if #analytics.errors > 10 then
            warn("Many errors detected!")
            EventBus:PrintSummary()
        end
    end
end)
```

---

## 📊 Comparison: Old vs New

| Feature | Old (BindableEvent) | New (Signal) |
|---------|---------------------|--------------|
| **Performance** | Good | ✅ Better |
| **Type Safety** | Basic | ✅ Full |
| **Error Isolation** | ✅ Yes | ✅ Yes |
| **Listener Count** | ❌ No | ✅ Yes |
| **Analytics** | ❌ No | ✅ Yes |
| **Memory** | Good | ✅ Better |

---

## 🐛 Debugging

### Check Active Events

```lua
-- F9 Console
local events = EventBus:GetEventNames()
print("Active events:", #events)
for _, name in events do
    local count = EventBus:GetListenerCount(name)
    print(name, "listeners:", count)
end
```

### Print Full Summary

```lua
EventBus:PrintSummary()
```

### Monitor Performance

```lua
local analytics = EventBus:GetAnalytics()
print("Emits/sec:", analytics.emitsPerSecond)
print("Total emits:", analytics.totalEmits)
print("Uptime:", analytics.uptime)
```

---

**Version:** 3.0 - Signal-Based  
**Last Updated:** 2024  
**Library:** [Signal by sleitnick](https://github.com/sleitnick/rbxts-signal)  
**Author:** OneShortArena Team
