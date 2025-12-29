--!strict

--[[]
    NETWORK HANDLER - PRODUCTION GRADE
    
    Features:
      - Global rate limiting (configurable)
      - Per-event rate limiting (configurable)
      - Anti-replay protection
      - Payload sanitization
      - Event allowlist
      - Analytics tracking
      - ACK system for reliable send
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)

-- ✅ Load NetworkConfig
local NetworkConfig = require(ServerStorage.Configs.NetworkConfig)

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
-- LOAD CONFIGURATION FROM NetworkConfig
-- ═══════════════════════════════════════════════════════════════

local REMOTE_FOLDER_NAME = "Network"
local REMOTE_EVENT_NAME = "NetworkBridge"

-- ✅ Use config values
local GLOBAL_RATE_LIMIT = NetworkConfig.GlobalRateLimit
local GLOBAL_RATE_WINDOW = NetworkConfig.GlobalRateWindow
local BURST_LIMIT = NetworkConfig.BurstLimit
local BURST_WINDOW = NetworkConfig.BurstWindow

local EVENT_RATE_LIMITS = NetworkConfig.EventRateLimits
local DEFAULT_EVENT_RATE_LIMIT = NetworkConfig.DefaultEventRateLimit

local MAX_STRIKES = NetworkConfig.MaxStrikes
local MESSAGE_ID_TTL = NetworkConfig.MessageIdTTL
local MAX_PAYLOAD_SIZE = NetworkConfig.MaxPayloadSize
local MAX_STRING_LENGTH = NetworkConfig.MaxStringLength
local MAX_TABLE_DEPTH = NetworkConfig.MaxTableDepth

local LOG_LEVEL = NetworkConfig.LogLevel

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
-- LOGGING HELPER (Uses NetworkConfig.LogLevel)
-- ═══════════════════════════════════════════════════════════════

local LOG_LEVELS = {
    None = 0,
    Error = 1,
    Warn = 2,
    Info = 3,
    Debug = 4,
}

local function log(level: "Error" | "Warn" | "Info" | "Debug", message: string)
    local configLevel = LOG_LEVELS[LOG_LEVEL] or 0
    local messageLevel = LOG_LEVELS[level] or 0
    
    if messageLevel <= configLevel then
        if level == "Error" then
            error("[NetworkHandler] " .. message)
        elseif level == "Warn" then
            warn("[NetworkHandler] " .. message)
        else
            print("[NetworkHandler] " .. message)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- RATE LIMIT FUNCTIONS (Using NetworkConfig)
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
    
    -- ✅ Use NetworkConfig to get rate limit
    local config = NetworkConfig.GetEventRateLimit(eventName)
    
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

-- ✅ NEW: Payload validation
local function validatePayload(data: any): (boolean, string?)
    if type(data) ~= "table" then
        return true
    end
    
    -- Check table depth
    local function getDepth(tbl: any, depth: number): number
        depth = depth or 0
        if depth > MAX_TABLE_DEPTH then
            return depth
        end
        
        local maxChildDepth = depth
        for _, value in pairs(tbl) do
            if type(value) == "table" then
                local childDepth = getDepth(value, depth + 1)
                maxChildDepth = math.max(maxChildDepth, childDepth)
            end
        end
        return maxChildDepth
    end
    
    local depth = getDepth(data, 0)
    if depth > MAX_TABLE_DEPTH then
        return false, `Payload too deep: {depth} levels (max {MAX_TABLE_DEPTH})`
    end
    
    -- Check string lengths
    for key, value in pairs(data) do
        if type(value) == "string" and #value > MAX_STRING_LENGTH then
            return false, `String too long: {#value} chars (max {MAX_STRING_LENGTH})`
        end
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
    
    log("Info", "🚀 Initialized (Production Grade)")
    log("Info", `  ✅ Global rate limit: {GLOBAL_RATE_LIMIT} per {GLOBAL_RATE_WINDOW}s`)
    log("Info", `  ✅ Per-event rate limits: {#EVENT_RATE_LIMITS} events configured`)
    log("Info", `  ✅ Max strikes: {MAX_STRIKES}`)
    log("Info", `  ✅ Log level: {LOG_LEVEL}`)
    log("Info", "  ✅ Anti-replay protection: ENABLED")
    
    -- Print config summary
    NetworkConfig.PrintSummary()
end

function NetworkHandler:Start()
    if not guard:MarkStarted() then
        return
    end
    
    -- Handle incoming events
    remoteEvent.OnServerEvent:Connect(function(player: Player, eventName: string, ...)
        analytics.totalReceived += 1
        
        local args = {...}
        local data = args[1]
        
        -- ✅ Check 0: Payload validation
        if type(data) == "table" then
            local payloadValid, payloadReason = validatePayload(data)
            if not payloadValid then
                log("Warn", `⚠️ {player.Name} invalid payload: {payloadReason}`)
                addSuspiciousActivity(player, "invalid_payload")
                return
            end
        end
        
        -- ✅ Check 1: Per-event rate limit
        local eventAllowed, eventReason = checkEventRateLimit(player, eventName)
        if not eventAllowed then
            analytics.blockedByEventRateLimit += 1
            analytics.eventRateLimitBlocks[eventName] = (analytics.eventRateLimitBlocks[eventName] or 0) + 1
            
            log("Warn", `⚠️ {player.Name} EVENT RATE LIMIT: {eventReason}`)
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
        if not checkAntiReplay(data) then
            analytics.blockedByAntiReplay += 1
            
            warn(string.format("[NetworkHandler] ⚠️ %s replay attack detected", player.Name))
            addSuspiciousActivity(player, "replay_attack")
            return
        end
        
        -- ✅ All checks passed
        EventBus:Emit(eventName, player, ...)
        
        -- Send ACK
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
    
    log("Info", "🚀 Started - Listening for events")
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

-- ✅ NEW: Get current config
function NetworkHandler:GetConfig(): typeof(NetworkConfig)
    return NetworkConfig
end

-- ✅ NEW: Update rate limit (runtime)
function NetworkHandler:SetEventRateLimit(eventName: string, rate: number, window: number)
    NetworkConfig.SetEventRateLimit(eventName, rate, window)
end

function NetworkHandler:GetPlayerEventStats(player: Player): {[string]: {count: number, limit: number, remaining: number}}
    return getEventRateLimitStats(player.UserId)
end

return NetworkHandler