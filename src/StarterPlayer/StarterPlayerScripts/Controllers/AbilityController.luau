--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ดึงของที่เราเตรียมไว้
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local InputSettings = require(ReplicatedStorage.Shared.InputSettings)

local AbilityController = {}

-- ฟังก์ชันเสกของ (ทำงานฝั่ง Client เห็นคนเดียวไปก่อน)
local function SpawnMagicCube()
	local player = Players.LocalPlayer
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: Part
	
	-- 1. สร้างชิ้นส่วน (Part)
	local magicPart = Instance.new("Part")
	magicPart.Name = "MagicCube"
	magicPart.Size = Vector3.new(2, 2, 2)
	magicPart.Color = Color3.fromRGB(0, 255, 255) -- สีฟ้า
	magicPart.Material = Enum.Material.Neon
	
	-- 2. วางไว้ข้างหน้าตัวละคร 5 หน่วย
	magicPart.CFrame = rootPart.CFrame * CFrame.new(0, 0, -5)
	
	-- 3. ใส่แรงให้มันพุ่งไปข้างหน้า (แถมให้)
	local velocity = Instance.new("LinearVelocity")
	velocity.MaxForce = 100000
	velocity.VectorVelocity = rootPart.CFrame.LookVector * 50 -- พุ่งเร็ว 50
	velocity.Attachment0 = Instance.new("Attachment", magicPart)
	velocity.Parent = magicPart
	
	-- 4. โชว์ในโลก
	magicPart.Parent = workspace
	
	-- 5. ลบทิ้งเมื่อผ่านไป 3 วินาที (กันแลค)
	game:GetService("Debris"):AddItem(magicPart, 3)
	
	print("✨ Spawned Magic Cube!")
end

function AbilityController:Init()
	-- รอฟัง Event ชื่อ INPUT_ACTION จาก InputController
	EventBus:On(Events.INPUT_ACTION, function(actionName)
		
		-- เช็คว่าปุ่มที่กด คือปุ่ม "โจมตี" หรือไม่?
		if actionName == "ATTACK" then
			SpawnMagicCube()
			
		elseif actionName == "INTERACT" then
			print("🔘 Interact button pressed (Nothing spawned)")
		end
		
	end)
end

return AbilityController