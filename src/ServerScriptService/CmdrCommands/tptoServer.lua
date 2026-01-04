return function(context, fromPlayer, toPlayer)
	-- 1. เช็คว่าผู้เล่นมี Character หรือไม่
	local fromChar = fromPlayer.Character
	local toChar = toPlayer.Character
	
	if not fromChar or not toChar then
		return `❌ ผู้เล่นต้องอยู่ในเกม!`
	end
	
	-- 2. หา HumanoidRootPart
	local fromRoot = fromChar:FindFirstChild("HumanoidRootPart")
	local toRoot = toChar:FindFirstChild("HumanoidRootPart")
	
	if not fromRoot or not toRoot then
		return `❌ ไม่พบ HumanoidRootPart!`
	end
	
	-- 3. Teleport
	fromRoot.CFrame = toRoot.CFrame * CFrame.new(0, 0, -3)  -- วาร์ปหน้า 3 studs
	
	return `✅ วาร์ป {fromPlayer.Name} ไปหา {toPlayer.Name} สำเร็จ!`
end
