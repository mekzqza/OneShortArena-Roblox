--[[
	GameController - ตัวอย่างการใช้งาน EventBus ฝั่ง Client
	
	📌 หน้าที่:
	Controller นี้แสดงตัวอย่างการใช้งาน EventBus สำหรับการสื่อสารระหว่าง Client-Client
	
	🔧 ฟีเจอร์ตัวอย่าง:
	- รับฟังอีเวนต์จากระบบอื่นๆ ใน Client
	- ส่งอีเวนต์เพื่อให้ Controllers อื่นรับทราบ
	- แสดงตัวอย่างการใช้งานทั้ง On, Once, Emit
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

local player = Players.LocalPlayer
local GameController = {}
GameController.connections = {} -- เก็บ connections สำหรับ cleanup

--[[
	Init: เริ่มต้น Controller
	เรียกโดย Init.client.luau เมื่อ client เริ่มทำงาน
--]]
function GameController:Init()
	print("🎮 GameController: Initializing...")
	
	-- ตัวอย่าง: ฟังอีเวนต์เมื่อเกมเริ่ม
	local gameStartedConn = EventBus:On(Events.GAME_STARTED, function(gameMode)
		print("🎮 [Client] Game started! Mode:", gameMode)
		
		-- แจ้ง UI Controller ให้แสดง UI เกม
		EventBus:Emit(Events.TOGGLE_UI, "GameHUD", true)
		EventBus:Emit(Events.TOGGLE_UI, "MainMenu", false)
		
		-- เล่นเสียงเริ่มเกม
		EventBus:Emit(Events.AUDIO_PLAY, "GameStartSound")
	end)
	table.insert(self.connections, gameStartedConn)
	
	-- ตัวอย่าง: ฟังอีเวนต์เมื่อเกมจบ
	local gameEndedConn = EventBus:On(Events.GAME_ENDED, function(winner)
		print("🎮 [Client] Game ended! Winner:", winner or "None")
		
		-- แสดง UI ผลการเล่น
		EventBus:Emit(Events.TOGGLE_UI, "GameHUD", false)
		EventBus:Emit(Events.TOGGLE_UI, "ResultsScreen", true)
		
		-- ส่งข้อมูลผู้ชนะไปให้ UI
		EventBus:Emit(Events.RESULTS_SHOW_WINNER, winner)
	end)
	table.insert(self.connections, gameEndedConn)
	
	-- ตัวอย่าง: ฟังอีเวนต์เมื่อผู้เล่นได้คะแนน
	local scoreConn = EventBus:On(Events.PLAYER_SELF_SCORED, function(points)
		print("⭐ [Client] You scored " .. points .. " points!")
		
		-- แสดงเอฟเฟกต์ได้คะแนน
		EventBus:Emit(Events.EFFECT_SHOW_SCORE_POPUP, points)
		
		-- เล่นเสียง
		EventBus:Emit(Events.AUDIO_PLAY, "ScoreSound")
	end)
	table.insert(self.connections, scoreConn)
	
	-- ตัวอย่าง: ใช้ Once สำหรับอีเวนต์ที่เกิดครั้งเดียว
	EventBus:Once(Events.FIRST_TIME_TUTORIAL, function()
		print("📚 [Client] Showing tutorial...")
		EventBus:Emit(Events.TOGGLE_UI, "Tutorial", true)
	end)
	
	-- ตัวอย่าง: ฟังอีเวนต์เมื่อมีข้อความแจ้งเตือน
	local notificationConn = EventBus:On(Events.NOTIFICATION_SHOW, function(message, duration)
		print("📢 [Client] Notification:", message)
		-- ส่งต่อให้ UI Controller จัดการแสดงผล
		EventBus:Emit(Events.UI_SHOW_NOTIFICATION, message, duration or 3)
	end)
	table.insert(self.connections, notificationConn)
	
	-- ตัวอย่าง: ฟังอีเวนต์เมื่อมีการเปลี่ยนแปลงการตั้งค่า
	local settingsConn = EventBus:On(Events.SETTINGS_CHANGED, function(settingName, value)
		print("⚙️ [Client] Setting changed:", settingName, "=", value)
		
		-- จัดการการเปลี่ยนแปลงการตั้งค่า
		if settingName == "MusicVolume" then
			EventBus:Emit(Events.AUDIO_SET_MUSIC_VOLUME, value)
		elseif settingName == "SFXVolume" then
			EventBus:Emit(Events.AUDIO_SET_SFX_VOLUME, value)
		end
	end)
	table.insert(self.connections, settingsConn)
	
	-- ส่งอีเวนต์ว่า GameController พร้อมแล้ว
	EventBus:Emit(Events.CONTROLLER_READY, "GameController")
	
	-- ตัวอย่าง: แสดง debug info ของ EventBus
	self:ShowDebugInfo()
	
	print("✅ GameController initialized.")
end

--[[
	ShowDebugInfo: แสดงข้อมูล debug ของ EventBus
	ใช้สำหรับ development เพื่อดูว่ามี events อะไรอยู่ในระบบบ้าง
--]]
function GameController:ShowDebugInfo()
	-- ใช้ task.defer เพื่อให้ controllers อื่นๆ มีโอกาสลงทะเบียนก่อน
	-- หมายเหตุ: นี่เป็นฟังก์ชัน debug เท่านั้น
	-- ในระบบจริงควรใช้ proper initialization system แทนการพึ่งพา timing
	task.defer(function()
		local events = EventBus:GetEventNames()
		if #events > 0 then
			print("📋 [GameController] Active EventBus Events:")
			for _, eventName in ipairs(events) do
				print("   -", eventName)
			end
		else
			print("📋 [GameController] No active events in EventBus")
		end
	end)
end

--[[
	OnPlayerScored: เมื่อผู้เล่นทำคะแนน (ตัวอย่างฟังก์ชันที่เรียกจากที่อื่น)
	@param points: number - จำนวนคะแนนที่ได้
--]]
function GameController:OnPlayerScored(points: number)
	-- ส่งอีเวนต์แจ้งระบบอื่นๆ
	EventBus:Emit(Events.PLAYER_SELF_SCORED, points)
end

--[[
	RequestGameStart: ขอเริ่มเกม (ตัวอย่าง)
	@param gameMode: string - โหมดเกม
	
	หมายเหตุ: ในระบบจริง อาจต้องมีการตรวจสอบสิทธิ์หรือเงื่อนไขอื่นๆ
--]]
function GameController:RequestGameStart(gameMode: string)
	print("🎮 [Client] Requesting game start:", gameMode)
	
	-- ส่งอีเวนต์ (ในระบบจริงอาจต้องใช้ RemoteEvent เพื่อสื่อสารกับ Server)
	EventBus:Emit(Events.GAME_START_REQUESTED, gameMode)
end

--[[
	ShowNotification: แสดงการแจ้งเตือน
	@param message: string - ข้อความที่ต้องการแสดง
	@param duration: number? - ระยะเวลาที่แสดง (วินาที)
--]]
function GameController:ShowNotification(message: string, duration: number?)
	EventBus:Emit(Events.NOTIFICATION_SHOW, message, duration)
end

--[[
	Cleanup: ทำความสะอาด connections
	ควรเรียกเมื่อ Controller ถูกทำลายหรือไม่ใช้งานแล้ว
--]]
function GameController:Cleanup()
	print("🧹 [GameController] Cleaning up...")
	
	-- Disconnect ทุก connection
	for _, connection in ipairs(self.connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	
	self.connections = {}
	print("✅ [GameController] Cleanup complete.")
end

return GameController
