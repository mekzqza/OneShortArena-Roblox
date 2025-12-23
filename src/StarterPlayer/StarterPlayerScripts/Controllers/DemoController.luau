--!strict

--[ [
	DemoController - ตัวอย่างการใช้ InputController + NetworkController
	
	การทำงาน:
	1. InputController จับ input (เช่น กดปุ่ม E)
	2. InputController ส่ง event ผ่าน EventBus
	3. DemoController รับ event และส่งไปยัง Server
	4. Server ประมวลผลและส่งกลับ
-- ]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkController = require(script.Parent.NetworkController)

export type DemoController = {
	Init: (self: DemoController) -> (),
	Start: (self: DemoController) -> (),
	SendTestEventToServer: (self: DemoController) -> (),
	[string]: any,
}

local DemoController: DemoController = {}

local player = Players.LocalPlayer

function DemoController:Init()
	print("[DemoController] 🎮 Initializing...")
end

function DemoController:Start()
	-- รอรับ INPUT_ACTION จาก InputController
	EventBus:On(Events.INPUT_ACTION, function(actionName: string)
		self:OnInputAction(actionName)
	end)
	
	print("[DemoController] 🚀 Started - Listening for input actions")
	print("[DemoController] 📋 Try pressing:")
	print("  • E = Attack")
	print("  • Q = Defend")
	print("  • R = Special")
	print("  • P = Ping Server")
	print("  • 1/2/3 = Test Buttons")
end

-- ฟังก์ชันหลักที่จัดการ input
function DemoController:OnInputAction(actionName: string)
	print(`[DemoController] 🎮 Input detected: {actionName}`)
	
	-- แปลง input เป็น server events ตามประเภท
	if actionName == "Attack" then
		self:SendAttack()
		
	elseif actionName == "Defend" then
		self:SendDefend()
		
	elseif actionName == "Special" then
		self:SendSpecial()
		
	elseif actionName == "Ping" then
		self:SendPing()
		
	elseif actionName == "TestButton1" then
		self:SendTestButton(1)
		
	elseif actionName == "TestButton2" then
		self:SendTestButton(2)
		
	elseif actionName == "TestButton3" then
		self:SendTestButton(3)
		
	else
		-- Actions อื่นๆ ที่ไม่ต้องส่งไปยัง server
		print(`[DemoController] ℹ️ Action '{actionName}' handled locally`)
	end
end

-- ส่ง Attack ไปยัง Server
function DemoController:SendAttack()
	print("[DemoController] ⚔️ Sending Attack to server...")
	
	NetworkController:Send(Events.PLAYER_ATTACK, {
		timestamp = tick(),
		position = player.Character and player.Character.PrimaryPart.Position or Vector3.zero,
	})
end

-- ส่ง Defend ไปยัง Server
function DemoController:SendDefend()
	print("[DemoController] 🛡️ Sending Defend to server...")
	
	NetworkController:Send(Events.PLAYER_DEFEND, {
		timestamp = tick(),
		isBlocking = true,
	})
end

-- ส่ง Special ไปยัง Server
function DemoController:SendSpecial()
	print("[DemoController] ✨ Sending Special to server...")
	
	NetworkController:Send(Events.PLAYER_SPECIAL, {
		timestamp = tick(),
		skillType = "Ultimate",
	})
end

-- ส่ง Ping (Demo)
function DemoController:SendPing()
	print("[DemoController] 📡 Sending Ping to server...")
	
	NetworkController:Send(Events.DEMO_PING, tick())
end

-- ส่ง Test Button
function DemoController:SendTestButton(buttonNumber: number)
	print(`[DemoController] 🔘 Sending TestButton{buttonNumber} to server...`)
	
	NetworkController:Send(Events.TEST_BUTTON_PRESSED, {
		buttonId = buttonNumber,
		playerName = player.Name,
		timestamp = tick(),
	})
end

-- สามารถเรียกจาก Console ได้
function DemoController:SendTestEventToServer()
	print("[DemoController] 📤 Manual test event sent")
	NetworkController:Send(Events.TEST_CLIENT_BUTTON_CLICK, "Hello from Client!")
end

return DemoController