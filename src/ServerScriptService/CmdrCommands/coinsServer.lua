local ServerScriptService = game:GetService("ServerScriptService")

return function(context, targetPlayer, amount)
	-- ✅ Debug logs
	print("[coins] Target:", targetPlayer.Name)
	print("[coins] Amount:", amount)
	
	-- ✅ Get ServiceLocator
	local success1, ServiceLocator = pcall(function()
		return require(ServerScriptService.Utils.ServiceLocator)
	end)
	
	if not success1 then
		warn("[coins] ❌ ServiceLocator failed:", ServiceLocator)
		return "❌ ServiceLocator error"
	end
	
	-- ✅ Get PlayerDataService
	local PDS = ServiceLocator:Get("PlayerDataService")
	
	if not PDS then
		warn("[coins] ❌ PlayerDataService not found")
		return "❌ PlayerDataService not found"
	end
	
	-- ✅ Check if data loaded
	if not PDS:IsDataLoaded(targetPlayer) then
		warn(`[coins] ❌ Data not loaded for {targetPlayer.Name}`)
		return "❌ Data not loaded"
	end
	
	-- ✅ Increment coins
	local success2, newValue = PDS:Increment(targetPlayer, "Coins", amount)
	
	if not success2 then
		warn("[coins] ❌ Increment failed")
		return "❌ Failed to give coins"
	end
	
	-- ✅ FIX: Use array with string interpolation + table.concat
	-- This is the SAME pattern as getdata command!
	local output = {
		`✅ ให้ {amount} เหรียญกับ {targetPlayer.Name} สำเร็จ!`,
		`💰 รวม: {newValue} เหรียญ`,
	}
	
	local result = table.concat(output, "\n")
	
	print(`[coins] ✅ Success: {result}`)
	
	return result
end
