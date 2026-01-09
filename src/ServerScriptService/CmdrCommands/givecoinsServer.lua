local ServerScriptService = game:GetService("ServerScriptService")
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

return function(context, player, amount)
	local PDS = ServiceLocator:Get("PlayerDataService")
	
	if not PDS then
		return "❌ PlayerDataService ไม่พร้อม!"
	end
	
	-- Check if data loaded
	if not PDS:IsDataLoaded(player) then
		return `❌ ข้อมูลของ {player.Name} ยังไม่โหลด!`
	end
	
	-- Give coins
	local success, newCoins = PDS:Increment(player, "Coins", amount)
	
	if success then
		return `✅ ให้ {amount} เหรียญแก่ {player.Name} (รวม: {newCoins})`
	else
		return `❌ ล้มเหลวในการให้เหรียญ!`
	end
end
