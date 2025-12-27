--[[
	Events.luau - Event Names Constants
	
	📌 หน้าที่:
	เก็บชื่อ Events ทั้งหมดไว้ในที่เดียว เพื่อป้องกันการสะกดผิด
	และทำให้ง่ายต่อการจัดการและ refactor
	
	💡 วิธีใช้:
	local Events = require(ReplicatedStorage.Shared.Events)
	EventBus:On(Events.PLAYER_JOINED, function() ... end)
	EventBus:Emit(Events.PLAYER_JOINED)
	
	✅ ข้อดี:
	- ป้องกันการสะกดผิด (typos)
	- Auto-complete ใน IDE
	- ง่ายต่อการ rename/refactor
	- สามารถเห็นรายการ events ทั้งหมดได้ในที่เดียว
--]]

local Events = {}

-- ============================================================================
-- 🎮 Game Events
-- ============================================================================
Events.GAME_STARTED = "GameStarted"
Events.GAME_ENDED = "GameEnded"
Events.GAME_PAUSED = "Game_Paused"
Events.GAME_RESUMED = "Game_Resumed"
Events.GAME_CLEANUP_COMPLETE = "Game_Cleanup_Complete"
Events.GAME_START_REQUESTED = "GameStartRequested"
Events.GAME_START_FAILED = "GameStartFailed"
Events.GAME_STATE_UPDATE = "GameStateUpdate"

-- ============================================================================
-- 👤 Player Events
-- ============================================================================
Events.PLAYER_JOINED = "Player_Joined"
Events.PLAYER_LEFT = "Player_Left"
Events.PLAYER_DIED = "Player_Died"
Events.PLAYER_RESPAWNED = "Player_Respawned"
Events.PLAYER_SCORED = "Player_Scored"
Events.PLAYER_SELF_SCORED = "Player_SelfScored"
Events.PLAYER_STATS_UPDATED = "Player_StatsUpdated"
Events.PLAYER_DAMAGED = "Player_Damaged"
Events.PLAYER_HEALED = "Player_Healed"
Events.PLAYER_REQUEST_PLAY = "Player_RequestPlay"      -- Client → Server: Request to enter arena
Events.JOIN_SUCCESS = "JoinSuccess"
Events.JOIN_FAILED = "JoinFailed"

-- Gameplay Loop Events
Events.PLAYER_REQUEST_TO_ARENA = "Player_RequestToArena"      -- Client → Server: Request to enter arena
Events.PLAYER_REQUEST_TO_LOBBY = "Player_RequestToLobby"      -- Client → Server: Request to return to lobby
Events.PLAYER_REQUEST_TO_SPECTATE = "Player_RequestToSpectate" -- Client → Server: Request to spectate

Events.PLAYER_STATE_SET_LOBBY = "Player_StateSetLobby"
Events.PLAYER_STATE_SET_ARENA = "Player_StateSetArena"
Events.PLAYER_STATE_SET_DIED = "Player_StateSetDied"
Events.PLAYER_STATE_CHANGED = "Player_StateChanged"
Events.PLAYER_STATE_CHANGED_INTERNAL = "Player_StateChangedInternal"


Events.PLAYER_TELEPORTED_TO_LOBBY = "Player_TeleportedToLobby"

-- ============================================================================
-- 🖼️ UI Events
-- ============================================================================
Events.UI_OPENED = "UI_Opened"
Events.UI_CLOSED = "UI_Closed"
Events.TOGGLE_UI = "ToggleUI"
Events.UI_SHOW_NOTIFICATION = "UiShowNotification"
Events.UI_UPDATE_SCORE = "UiUpdateScore"
Events.UI_UPDATE_HEALTH = "UiUpdateHealth"

-- ============================================================================
-- 📢 Notification Events
-- ============================================================================
Events.NOTIFICATION_SHOW = "Notification_Show"
Events.NOTIFICATION_HIDE = "Notification_Hide"

-- ============================================================================
-- 🎵 Audio Events
-- ============================================================================
Events.AUDIO_PLAY = "Audio_Play"
Events.AUDIO_STOP = "Audio_Stop"
Events.AUDIO_SET_MUSIC_VOLUME = "Audio_SetMusicVolume"
Events.AUDIO_SET_SFX_VOLUME = "Audio_SetSFXVolume"

-- ============================================================================
-- ⚙️ Settings Events
-- ============================================================================
Events.SETTINGS_CHANGED = "SettingsChanged"
Events.SETTINGS_RESET = "Settings_Reset"

-- ============================================================================
-- ✨ Effect Events
-- ============================================================================
Events.EFFECT_SHOW_SCORE_POPUP = "Effect_ShowScorePopup"
Events.EFFECT_SHOW_DAMAGE = "Effect_ShowDamage"
Events.EFFECT_SHOW_HEAL = "Effect_ShowHeal"

-- ============================================================================
-- 📊 Results Events
-- ============================================================================
Events.RESULTS_SHOW_WINNER = "ResultsShowWinner"
Events.RESULTS_SHOW_STATS = "Results_ShowStats"

-- ============================================================================
-- 🔧 Service/Controller Events
-- ============================================================================
Events.SERVICE_READY = "Service_Ready"
Events.CONTROLLER_READY = "ControllerReady"

-- ============================================================================
-- 🐛 Debug Events
-- ============================================================================
Events.DEBUG_SHOW_EVENTS = "Debug_ShowEvents"
Events.DEBUG_TOGGLE = "Debug_Toggle"

-- ============================================================================
-- 📺 Demo Events
-- ============================================================================
Events.DEMO_PING = "DemoPing"                           -- Client → Server
Events.DEMO_PONG = "DemoPong"                           -- Server → Client
Events.DEMO_REQUEST_DATA = "DemoRequestData"             -- Client → Server
Events.DEMO_SEND_DATA = "DemoSendData"                   -- Server → Client
Events.DEMO_BROADCAST_MESSAGE = "DemoBroadcastMessage"   -- Server → All Clients
Events.DEMO_CHAT_MESSAGE = "DemoChatMessage"             -- Client → Server
Events.DEMO_UPDATE_COUNTER = "DemoUpdateCounter"         -- Server → Client
Events.DEMO_BUTTON_CLICKED = "DemoButtonClicked"         -- Client → Server

-- Input Events (Client → Internal)
Events.INPUT_ACTION = "InputAction"

-- Input Events (Client → Server)
Events.PLAYER_ATTACK = "PlayerAttack"
Events.PLAYER_DEFEND = "PlayerDefend"
Events.PLAYER_SPECIAL = "PlayerSpecial"
Events.PLAYER_JUMP = "PlayerJump"
Events.PLAYER_SPRINT = "PlayerSprint"

-- ============================================================================
-- 🕹️ TestEvent
-- ============================================================================
Events.TEST_PING = "TestPing"
Events.TEST_PONG = "TestPong"


Events.INPUT_ENABLED_CHANGED = "InputEnabledChanged"

--[[
	GetAllEvents: ดูรายการ Events ทั้งหมด
	@return table - ตารางที่เก็บชื่อ events ทั้งหมด
--]]
function Events.GetAllEvents(): {string}
	local allEvents = {}
	-- ใช้ table set สำหรับ O(1) lookup
	local excludedKeys = {
		GetAllEvents = true,
		PrintAllEvents = true
	}
	
	-- เก็บเฉพาะ string values ที่ไม่ใช่ฟังก์ชัน
	for key, value in pairs(Events) do
		if type(value) == "string" and not excludedKeys[key] then
			table.insert(allEvents, value)
		end
	end
	return allEvents
end

--[[
	PrintAllEvents: แสดง Events ทั้งหมดใน console
	ใช้สำหรับ debugging
--]]
function Events.PrintAllEvents()
	local allEvents = Events.GetAllEvents()
	table.sort(allEvents)
	
	print("\n" .. string.rep("=", 60))
	print("📋 All Available Events (" .. #allEvents .. " total)")
	print(string.rep("=", 60))
	
	for i, eventName in ipairs(allEvents) do
		print(string.format("%3d. %s", i, eventName))
	end
	
	print(string.rep("=", 60) .. "\n")
end

return Events
