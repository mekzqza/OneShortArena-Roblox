# 🎮 MatchService Guide v1.0 - Match Management & Statistics

## 📋 Overview

**MatchService v1.0** จัดการทุกอย่างเกี่ยวกับ Match:
- Match lifecycle (Create, Start, End)
- Player management (Join, Leave)
- Death statistics per match
- Kill tracking & kill streaks
- Respawn delays by match type
- Match analytics

---

## 🎯 Match Types

| Type | Respawn Delay | Description |
|------|---------------|-------------|
| `Casual` | 3s | โหมดทั่วไป |
| `Ranked` | 5s | โหมดจัดอันดับ |
| `Custom` | 3s | ห้องกำหนดเอง |
| `Tournament` | 10s | โหมดแข่งขัน |

---

## 🚀 Quick Start

### 1. Create a Match

```lua
local MatchService = require(ServerScriptService.Services.MatchService)

local matchId = MatchService:CreateMatch(
    "Casual",        -- matchType
    "Arena1",        -- arenaId (optional)
    {player1, player2, player3}  -- players
)

print("Match created:", matchId)
```

### 2. Start the Match

```lua
local success = MatchService:StartMatch(matchId)

if success then
    print("Match started!")
else
    warn("Failed to start match")
end
```

### 3. End the Match

```lua
local stats = MatchService:EndMatch(matchId, "Normal End")

print("Match ended!")
print("Total deaths:", stats.totalDeaths)
print("Winner:", determineWinner(stats))
```

---

## 📊 Match Statistics

### MatchDeathStats Structure

```lua
type MatchDeathStats = {
    matchId: string,
    matchType: MatchType,
    arenaId: string?,
    totalDeaths: number,
    deathsByPlayer: {[userId]: number},      -- Deaths per player
    killsByPlayer: {[userId]: number},       -- Kills per player
    killStreaks: {[userId]: number},         -- Current streak
    deathsByCause: {[cause]: number},        -- Combat/Environmental/etc
    startTime: number,
    endTime: number?,
}
```

### Get Stats During Match

```lua
local stats = MatchService:GetMatchStats(matchId)

if stats then
    print("Match:", stats.matchId)
    print("Duration:", os.clock() - stats.startTime, "seconds")
    
    -- Find top killer
    local topKiller, topKills = nil, 0
    for userId, kills in pairs(stats.killsByPlayer) do
        if kills > topKills then
            topKiller, topKills = userId, kills
        end
    end
    
    print("Top killer:", topKiller, "with", topKills, "kills")
end
```

---

## 👥 Player Management

### Add Player to Match

```lua
local success = MatchService:AddPlayerToMatch(matchId, player)

if success then
    print(player.Name, "joined match")
else
    warn("Failed to add player (match full or player already in match)")
end
```

### Remove Player from Match

```lua
local success = MatchService:RemovePlayerFromMatch(matchId, player)

-- Note: Match auto-ends if all players leave
```

### Check Player's Match

```lua
local matchContext = MatchService:GetPlayerMatch(player)

if matchContext then
    print("Player is in match:", matchContext.matchId)
    print("Match type:", matchContext.matchType)
    print("Status:", matchContext.status)
else
    print("Player is not in any match")
end
```

---

## 🔄 Death Tracking (Auto)

MatchService listens to `PLAYER_DIED` events from DeathService:

```lua
-- Automatic tracking (no manual code needed)
EventBus:On(Events.PLAYER_DIED, function(player, deathData)
    local matchId = MatchService:GetPlayerMatchId(player)
    if matchId then
        -- Auto-update:
        -- ✅ stats.totalDeaths++
        -- ✅ stats.deathsByPlayer[victim]++
        -- ✅ stats.killsByPlayer[killer]++
        -- ✅ stats.killStreaks[killer]++
        -- ✅ stats.killStreaks[victim] = 0 (reset)
    end
end)
```

---

## ⏱️ Match Timeout

Matches auto-end after timeout:

```lua
-- Config
MatchTimeout = 1800  -- 30 minutes

-- Automatic check every minute
-- If match.duration > MatchTimeout:
--   MatchService:EndMatch(matchId, "Timeout")
```

---

## 📈 Analytics

### Global Analytics

```lua
local analytics = MatchService:GetAnalytics()

print("Total matches:", analytics.totalMatches)
print("Active matches:", analytics.activeMatches)
print("Total deaths:", analytics.totalDeaths)
print("Total kills:", analytics.totalKills)

-- By match type
for matchType, count in pairs(analytics.matchesByType) do
    print(matchType, "matches:", count)
end
```

---

## 🎯 Integration Example: Full Match Flow

```lua
-- Example: Matchmaking System
local MatchmakingService = {}

function MatchmakingService:CreateCasualMatch(players)
    -- 1. Create match
    local matchId = MatchService:CreateMatch("Casual", "Arena1", players)
    
    -- 2. Teleport players
    for _, player in ipairs(players) do
        ArenaService:SpawnPlayerInArena(player, "Arena1")
    end
    
    -- 3. Start match
    task.delay(5, function()  -- 5 second countdown
        MatchService:StartMatch(matchId)
    end)
    
    return matchId
end

function MatchmakingService:EndMatchAndDetermineWinner(matchId)
    -- 1. End match
    local stats = MatchService:EndMatch(matchId, "Game Over")
    
    -- 2. Find winner
    local winner, highestKills = nil, 0
    for userId, kills in pairs(stats.killsByPlayer) do
        if kills > highestKills then
            winner, highestKills = userId, kills
        end
    end
    
    -- 3. Broadcast results
    NetworkHandler:Broadcast(Events.MATCH_RESULTS, {
        matchId = matchId,
        winner = winner,
        stats = stats,
    })
    
    -- 4. Teleport players back
    for _, userId in ipairs(stats.deathsByPlayer) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            LobbyService:TeleportPlayerToLobby(player)
        end
    end
end
```

---

## 🔧 API Reference

### Match Lifecycle

| Method | Description |
|--------|-------------|
| `CreateMatch(type, arenaId, players)` | Create new match |
| `StartMatch(matchId)` | Start pending match |
| `EndMatch(matchId, reason)` | End match, get stats |
| `CancelMatch(matchId, reason)` | Cancel match |

### Player Management

| Method | Description |
|--------|-------------|
| `AddPlayerToMatch(matchId, player)` | Add player to match |
| `RemovePlayerFromMatch(matchId, player)` | Remove player from match |
| `GetPlayerMatch(player)` | Get player's match context |
| `GetPlayerMatchId(player)` | Get player's match ID |

### Queries

| Method | Description |
|--------|-------------|
| `GetMatch(matchId)` | Get match context |
| `GetMatchStats(matchId)` | Get match death stats |
| `GetActiveMatches()` | Get all active matches |
| `GetRespawnDelay(matchType)` | Get respawn delay for type |
| `GetAnalytics()` | Get global analytics |

---

## ⚠️ Important Notes

### 1. Always End Matches

```lua
// ❌ Don't forget to end matches!
MatchService:CreateMatch(...)
// ... game logic ...
// If match never ends → memory leak!

// ✅ Always end properly
MatchService:EndMatch(matchId, "Normal")
```

### 2. Player Leave Handling

```lua
// ✅ Auto-handled by MatchService
Players.PlayerRemoving:Connect(function(player)
    -- MatchService auto-removes player from match
    -- Match auto-ends if all players leave
end)
```

### 3. Match Status

```lua
type MatchStatus = "Pending" | "Active" | "Ended" | "Cancelled"

// Only "Active" matches count stats
// "Pending" matches waiting to start
```

---

**Version:** 1.0  
**Status:** Production Ready  
**Author:** OneShortArena Team
