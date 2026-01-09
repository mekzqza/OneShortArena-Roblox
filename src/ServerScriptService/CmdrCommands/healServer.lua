return function(context, players, hp)
	hp = hp or 100
	
	local count = 0
	for _, player in ipairs(players) do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid.Health = math.min(hp, humanoid.MaxHealth)
				count += 1
			end
		end
	end
	
	return `✅ เติม HP ให้ {count} คนแล้ว!`
end
