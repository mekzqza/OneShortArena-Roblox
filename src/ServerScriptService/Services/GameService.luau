--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- เรียกใช้ระบบ EventBus และ Events ที่เราเตรียมไว้
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)

local GameService = {}

-- ============================================================================
-- ⚙️ Config (ตั้งค่าเกม)
-- ============================================================================
local CONFIG = {
	MIN_PLAYERS = 1,        -- จำนวนคนขั้นต่ำเพื่อเริ่มนับถอยหลัง (ตั้ง 1 เพื่อเทสต์คนเดียว)
	WAIT_TIME = 10,         -- เวลารอใน Lobby (วินาที)
	INTERMISSION = 5        -- เวลาพักหลังจบเกม
}

-- ============================================================================
-- 📊 State (ตัวแปรเก็บสถานะ)
-- ============================================================================
local isMatchActive = false
local lobbyTimer = CONFIG.WAIT_TIME

--[[\
	Init: เตรียมความพร้อมก่อน Server เริ่ม
	สร้างโฟลเดอร์สำหรับเก็บจุดเกิด ถ้ายังไม่มี
--]]
function GameService:Init()
	print("🏗️ GameService: Initializing...")
	
	if not Workspace:FindFirstChild("Spawns") then
		local folder = Instance.new("Folder")
		folder.Name = "Spawns"
		folder.Parent = Workspace
		warn("⚠️ Auto-created 'Spawns' folder. Please add 'LobbySpawn' inside it!")
	end
end

--[[\
	Start: เริ่มทำงานจริง
	เชื่อมต่อ Event ผู้เล่น และเริ่ม Game Loop
--]]
function GameService:Start()
	print("🏁 GameService: Lobby System Started")

	-- 1. เมื่อมีคนเข้าเกม -> ส่งไปเกิดที่ Lobby
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerJoin(player)
	end)

	-- 2. เมื่อมีคนออกเกม -> แจ้งระบบอื่น
	Players.PlayerRemoving:Connect(function(player)
		EventBus:Emit(Events.PLAYER_LEFT, player)
	end)
	
	-- 3. ฟังคำสั่งจบเกม (จาก ArenaService หรือ Admin)
	EventBus:On(Events.GAME_ENDED, function()
		self:EndMatch()
	end)

	-- 4. รันลูปของเกมแยกเป็น Thread ใหม่ (ไม่ให้ขวางการทำงานอื่น)
	task.spawn(function()
		while true do
			self:GameLoop()
			task.wait(1) -- เช็คสถานะทุกๆ 1 วินาที
		end
	end)
end

--[[\
	OnPlayerJoin: จัดการผู้เล่นใหม่
	บังคับให้เกิดที่จุด LobbySpawn เท่านั้น
--]]
function GameService:OnPlayerJoin(player: Player)
	print("👋 " .. player.Name .. " joined the lobby.")
	
	-- ค้นหาจุดเกิด Lobby
	local spawns = Workspace:FindFirstChild("Spawns")
	local lobbySpawn = spawns and spawns:FindFirstChild("LobbySpawn")
	
	if lobbySpawn and lobbySpawn:IsA("SpawnLocation") then
		player.RespawnLocation = lobbySpawn -- ✅ ตั้งจุดเกิดถาวร
	else
		warn("⚠️ CRITICAL: 'LobbySpawn' not found in Workspace/Spawns!")
	end
	
	-- สั่งโหลดตัวละครทันที
	player:LoadCharacter()
	
	-- แจ้งระบบอื่น
	EventBus:Emit(Events.PLAYER_JOINED, player)
end

--[[\
	GameLoop: สมองของเกม
	คอยนับจำนวนคน และนับเวลาถอยหลัง
--]]
function GameService:GameLoop()
	-- ถ้าเกมเริ่มไปแล้ว (อยู่ใน Arena) ไม่ต้องทำอะไรใน Lobby Loop
	if isMatchActive then return end

	local playerCount = #Players:GetPlayers()

	-- เช็คจำนวนคน
	if playerCount >= CONFIG.MIN_PLAYERS then
		-- คนครบ! นับถอยหลัง
		lobbyTimer -= 1
		
		-- ส่งข้อความแจ้งเตือนทุกวินาที (เช่น "Starting in 5...")
		-- ใช้ Events.UI_SHOW_NOTIFICATION ที่คุณมีอยู่แล้ว
		if lobbyTimer <= 5 or lobbyTimer % 5 == 0 then
			EventBus:Emit(Events.UI_SHOW_NOTIFICATION, "Match starts in: " .. lobbyTimer)
			print("⏳ Lobby Countdown: " .. lobbyTimer)
		end

		-- เวลาหมด -> เริ่มเกม!
		if lobbyTimer <= 0 then
			self:StartMatch()
		end
	else
		-- คนไม่พอ -> รีเซ็ตเวลา
		if lobbyTimer ~= CONFIG.WAIT_TIME then
			lobbyTimer = CONFIG.WAIT_TIME
			EventBus:Emit(Events.UI_SHOW_NOTIFICATION, "Waiting for players...")
			print("❌ Not enough players. Timer reset.")
		end
	end
end

--[[\
	StartMatch: สั่งเริ่มแมตช์
--]]
function GameService:StartMatch()
	print("🚀 STARTING MATCH!")
	isMatchActive = true
	
	-- ส่งสัญญาณ "GAME_STARTED"
	-- ArenaService จะรับ Event นี้แล้ววาร์ปคนไปสู้กันเอง
	EventBus:Emit(Events.GAME_STARTED)
end

--[[\
	EndMatch: จบแมตช์ (พักยก)
--]]
function GameService:EndMatch()
	print("🛑 Match Ended. Cooldown before lobby...")
	task.wait(CONFIG.INTERMISSION)
	
	isMatchActive = false
	lobbyTimer = CONFIG.WAIT_TIME
	print("🔄 Back to Lobby Loop")
end

return GameService