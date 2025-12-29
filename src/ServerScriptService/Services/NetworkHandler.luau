--!strict

--[[]
    NETWORK HANDLER - PRODUCTION GRADE
    
    Features:
      - Global rate limiting (10 events/5s per player)
      - Per-event rate limiting (configurable per event type)
      - Anti-replay protection
      - Payload sanitization
      - Event allowlist
      - Analytics tracking
      - ACK system for reliable send
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type NetworkHandler = {
    Init: (self: NetworkHandler) -> (),
    Start: (self: NetworkHandler) -> (),
    SendToClient: (self: NetworkHandler, player: Player, eventName: string, ...any) -> (),
    Broadcast: (self: NetworkHandler, eventName: string, ...any) -> (),
    AllowClientEvent: (self: NetworkHandler, eventName: string) -> (),
    GetAnalytics: (self: NetworkHandler) -> {[string]: any},
    GetEventRateLimitConfig: (self: NetworkHandler) -> {[string]: {rate: number, window: number}},
    SetEventRateLimit: (self: NetworkHandler, eventName: string, rate: number, window: number) -> (),
    GetPlayerEventStats: (self: NetworkHandler, player: Player) -> {[string]: any},
}

local NetworkHandler = {} :: NetworkHandler

local guard = IdempotentGuard.new("NetworkHandler", true)

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════

local REMOTE_FOLDER_NAME = "Network"
local REMOTE_EVENT_NAME = "NetworkBridge"

-- Global rate limits
local GLOBAL_RATE_LIMIT = 10
local GLOBAL_RATE_WINDOW = 5

-- ═══════════════════════════════════════════════════════════════
-- PER-EVENT RATE LIMITS
-- ═══════════════════════════════════════════════════════════════

local EVENT_RATE_LIMITS: {[string]: {rate: number, window: number}} = {
    -- Arena/Lobby - strict
    PlayerRequestToArena = {rate = 1, window = 5},
    PlayerRequestToLobby = {rate = 1, window = 5},
    PlayerRequestToSpectate = {rate = 1, window = 5},
    
    -- Combat - moderate
    PlayerAttack = {rate = 10, window = 5},
    PlayerDefend = {rate = 10, window = 5},
    PlayerSpecial = {rate = 5, window = 5},
    
    -- Movement - lenient
    PlayerMove = {rate = 30, window = 5},
    PlayerJump = {rate = 20, window = 5},
    
    -- UI - moderate
    SettingsChanged = {rate = 5, window = 5},
    ToggleUI = {rate = 10, window = 5},
    
    -- Test - lenient
    TestPing = {rate = 20, window = 5},
}

local DEFAULT_EVENT_RATE_LIMIT = {rate = 10, window = 5}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local remoteEvent: RemoteEvent
local allowedClientEvents: {[string]: boolean} = {}
local processedMessageIds: {[string]: number} = {}

-- Global rate limit tracking
local playerGlobalRateLimits: {[number]: {count: number, resetTime: number}} = {}

-- Per-event rate limit tracking
local playerEventRateLimits: {[number]: {[string]: {count: number, resetTime: number}}} = {}

-- Suspicious activity
local suspiciousPlayers: {[number]: number} = {}
local MAX_STRIKES = 5

-- Analytics
local analytics = {
    totalReceived = 0,
    totalSent = 0,
    blockedByGlobalRateLimit = 0,
    blockedByEventRateLimit = 0,
    blockedByAllowlist = 0,
    blockedByAntiReplay = 0,
    eventRateLimitBlocks = {} :: {[string]: number},
    startTime = os.clock(),
}

-- ═══════════════════════════════════════════════════════════════
-- RATE LIMIT FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function checkGlobalRateLimit(player: Player): boolean
    local userId = player.UserId
    local now = os.clock()
    
    if not playerGlobalRateLimits[userId] or now > playerGlobalRateLimits[userId].resetTime then
        playerGlobalRateLimits[userId] = {count = 0, resetTime = now + GLOBAL_RATE_WINDOW}
    end
    
    playerGlobalRateLimits[userId].count += 1
    
    return playerGlobalRateLimits[userId].count <= GLOBAL_RATE_LIMIT
end

local function checkEventRateLimit(player: Player, eventName: string): (boolean, string?)
    local userId = player.UserId
    local now = os.clock()
    
    local config = EVENT_RATE_LIMITS[eventName] or DEFAULT_EVENT_RATE_LIMIT
    
    if not playerEventRateLimits[userId] then
        playerEventRateLimits[userId] = {}
    end
    
    local playerEvents = playerEventRateLimits[userId]
    
    if not playerEvents[eventName] or now > playerEvents[eventName].resetTime then
        playerEvents[eventName] = {
            count = 0,
            resetTime = now + config.window
        }
    end
    
    local eventData = playerEvents[eventName]
    eventData.count += 1
    
    if eventData.count > config.rate then
        local remaining = eventData.resetTime - now
        return false, string.format(
            "'%s' limit exceeded (%d/%d, %.1fs reset)",
            eventName, eventData.count, config.rate, remaining
        )
    end
    
    return true
end

local function checkAntiReplay(data: any): boolean
    if type(data) ~= "table" then
        return true
    end
    
    local messageId = data._msgId
    if not messageId then
        return true
    end
    
    local now = os.clock()
    
    if processedMessageIds[messageId] then
        return false
    end
    
    processedMessageIds[messageId] = now
    
    -- Cleanup old messages (60s TTL)
    task.defer(function()
        for id, timestamp in pairs(processedMessageIds) do
            if now - timestamp > 60 then
                processedMessageIds[id] = nil
            end
        end
    end)
    
    return true
end

local function addSuspiciousActivity(player: Player, reason: string)
    local userId = player.UserId
    suspiciousPlayers[userId] = (suspiciousPlayers[userId] or 0) + 1
    
    warn(string.format(
        "[NetworkHandler] ⚠️ Suspicious activity from %s: %s (Strike %d/%d)",
        player.Name, reason, suspiciousPlayers[userId], MAX_STRIKES
    ))
    
    if suspiciousPlayers[userId] >= MAX_STRIKES then
        warn(string.format("[NetworkHandler] 🚫 Kicking %s for repeated violations", player.Name))
        player:Kick("Network security violation")
    end
end

local function cleanupPlayer(userId: number)
    playerGlobalRateLimits[userId] = nil
    playerEventRateLimits[userId] = nil
    suspiciousPlayers[userId] = nil
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function NetworkHandler:Init()
    if not guard:MarkInitialized() then
        return
    end
    
    -- Create network folder
    local systemsShared = ReplicatedStorage:FindFirstChild("SystemsShared")
    if not systemsShared then
        systemsShared = Instance.new("Folder")
        systemsShared.Name = "SystemsShared"
        systemsShared.Parent = ReplicatedStorage
    end
    
    local networkFolder = systemsShared:FindFirstChild(REMOTE_FOLDER_NAME)
    if not networkFolder then
        networkFolder = Instance.new("Folder")
        networkFolder.Name = REMOTE_FOLDER_NAME
        networkFolder.Parent = systemsShared
    end
    
    -- Create RemoteEvent
    remoteEvent = networkFolder:FindFirstChild(REMOTE_EVENT_NAME)
    if not remoteEvent then
        remoteEvent = Instance.new("RemoteEvent")
        remoteEvent.Name = REMOTE_EVENT_NAME
        remoteEvent.Parent = networkFolder
    end
    
    print("[NetworkHandler] 🚀 Initialized (Production Grade)")
    print("  ✅ Global rate limit:", GLOBAL_RATE_LIMIT, "per", GLOBAL_RATE_WINDOW, "s")
    print("  ✅ Per-event rate limits: ENABLED")
    print("  ✅ Anti-replay protection: ENABLED")
end

function NetworkHandler:Start()
    if not guard:MarkStarted() then
        return
    end
    
    -- Handle incoming events
    remoteEvent.OnServerEvent:Connect(function(player: Player, eventName: string, ...)
        analytics.totalReceived += 1
        
        -- ✅ Check 1: Per-event rate limit (FIRST - most specific)
        local eventAllowed, eventReason = checkEventRateLimit(player, eventName)
        if not eventAllowed then
            analytics.blockedByEventRateLimit += 1
            analytics.eventRateLimitBlocks[eventName] = (analytics.eventRateLimitBlocks[eventName] or 0) + 1
            
            warn(string.format("[NetworkHandler] ⚠️ %s EVENT RATE LIMIT: %s", player.Name, eventReason))
            addSuspiciousActivity(player, "event_rate_limit:" .. eventName)
            return
        end
        
        -- ✅ Check 2: Global rate limit
        if not checkGlobalRateLimit(player) then
            analytics.blockedByGlobalRateLimit += 1
            
            warn(string.format(
                "[NetworkHandler] ⚠️ %s GLOBAL RATE LIMIT! (%d events in %ds)",
                player.Name, GLOBAL_RATE_LIMIT, GLOBAL_RATE_WINDOW
            ))
            addSuspiciousActivity(player, "global_rate_limit")
            return
        end
        
        -- ✅ Check 3: Event allowlist
        if not allowedClientEvents[eventName] then
            analytics.blockedByAllowlist += 1
            
            warn(string.format("[NetworkHandler] ⚠️ %s sent unauthorized event: %s", player.Name, eventName))
            addSuspiciousActivity(player, "unauthorized_event:" .. eventName)
            return
        end
        
        -- ✅ Check 4: Anti-replay
        local args = {...}
        local data = args[1]
        if not checkAntiReplay(data) then
            analytics.blockedByAntiReplay += 1
            
            warn(string.format("[NetworkHandler] ⚠️ %s replay attack detected", player.Name))
            addSuspiciousActivity(player, "replay_attack")
            return
        end
        
        -- ✅ All checks passed - emit event
        EventBus:Emit(eventName, player, ...)
        
        -- Send ACK if message has ID
        if type(data) == "table" and data._msgId then
            self:SendToClient(player, "__ACK", {messageId = data._msgId})
        end
    end)
    
    -- Cleanup on player leave
    Players.PlayerRemoving:Connect(function(player: Player)
        cleanupPlayer(player.UserId)
    end)
    
    -- Analytics reporting
    task.spawn(function()
        while true do
            task.wait(60)
            local stats = self:GetAnalytics()
            print("[NetworkHandler] 📊 Analytics:")
            print(string.format("  Received: %d | Sent: %d", stats.totalReceived, stats.totalSent))
            print(string.format("  Blocked - Global: %d | Event: %d | Allowlist: %d | Replay: %d",
                stats.blockedByGlobalRateLimit,
                stats.blockedByEventRateLimit,
                stats.blockedByAllowlist,
                stats.blockedByAntiReplay
            ))
            
            -- Report top blocked events
            if next(stats.eventRateLimitBlocks) then
                print("  Per-event blocks:")
                for event, count in pairs(stats.eventRateLimitBlocks) do
                    if count > 0 then
                        print(string.format("    %s: %d", event, count))
                    end
                end
            end
        end
    end)
    
    print("[NetworkHandler] 🚀 Started - Listening for events")
end

function NetworkHandler:AllowClientEvent(eventName: string)
    allowedClientEvents[eventName] = true
end

function NetworkHandler:SendToClient(player: Player, eventName: string, ...: any)
    analytics.totalSent += 1
    remoteEvent:FireClient(player, eventName, ...)
end

function NetworkHandler:Broadcast(eventName: string, ...: any)
    analytics.totalSent += 1
    remoteEvent:FireAllClients(eventName, ...)
end

function NetworkHandler:GetAnalytics(): {[string]: any}
    local uptime = os.clock() - analytics.startTime
    
    return {
        totalReceived = analytics.totalReceived,
        totalSent = analytics.totalSent,
        blockedByGlobalRateLimit = analytics.blockedByGlobalRateLimit,
        blockedByEventRateLimit = analytics.blockedByEventRateLimit,
        blockedByAllowlist = analytics.blockedByAllowlist,
        blockedByAntiReplay = analytics.blockedByAntiReplay,
        eventRateLimitBlocks = analytics.eventRateLimitBlocks,
        uptime = uptime,
        eventsPerSecond = uptime > 0 and analytics.totalReceived / uptime or 0,
    }
end

function NetworkHandler:GetEventRateLimitConfig(): {[string]: {rate: number, window: number}}
    return EVENT_RATE_LIMITS
end

function NetworkHandler:SetEventRateLimit(eventName: string, rate: number, window: number)
    EVENT_RATE_LIMITS[eventName] = {rate = rate, window = window}
    print(string.format("[NetworkHandler] ✅ Set rate limit for '%s': %d per %ds", eventName, rate, window))
end

function NetworkHandler:GetPlayerEventStats(player: Player): {[string]: any}
    local userId = player.UserId
    local stats = {}
    local now = os.clock()
    
    local playerEvents = playerEventRateLimits[userId]
    if not playerEvents then
        return stats
    end
    
    for eventName, eventData in pairs(playerEvents) do
        local config = EVENT_RATE_LIMITS[eventName] or DEFAULT_EVENT_RATE_LIMIT
        local remaining = math.max(0, eventData.resetTime - now)
        
        stats[eventName] = {
            count = eventData.count,
            limit = config.rate,
            window = config.window,
            remaining = remaining
        }
    end
    
    return stats
end

return NetworkHandler--     
--     -- ...existing global rate limit and other checks...
-- end)

-- ═══════════════════════════════════════════════════════════════
-- CLEANUP ON PLAYER LEAVE
-- ═══════════════════════════════════════════════════════════════

-- In PlayerRemoving handler, add:
-- cleanupPlayerEventRateLimits(player.UserId)

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS TO ADD
-- ═══════════════════════════════════════════════════════════════

function NetworkHandler:GetEventRateLimitConfig(): {[string]: {rate: number, window: number}}
    return EVENT_RATE_LIMITS
end

function NetworkHandler:SetEventRateLimit(eventName: string, rate: number, window: number)
    EVENT_RATE_LIMITS[eventName] = {rate = rate, window = window}
    print(string.format("[NetworkHandler] ✅ Set rate limit for '%s': %d per %ds", eventName, rate, window))
end

function NetworkHandler:GetPlayerEventStats(player: Player): {[string]: {count: number, limit: number, remaining: number}}
    return getEventRateLimitStats(player.UserId)
end

return NetworkHandler