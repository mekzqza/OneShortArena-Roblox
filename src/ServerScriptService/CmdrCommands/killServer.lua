return function(context, targets)
	local killed = 0
	
	-- targets เป็น array ของผู้เล่น
	for _, player in ipairs(targets) do
		local char = player.Character
		if char then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = 0
				killed += 1
			end
		end
	end
	
	return `✅ ฆ่าผู้เล่น {killed} คนสำเร็จ!`
end
