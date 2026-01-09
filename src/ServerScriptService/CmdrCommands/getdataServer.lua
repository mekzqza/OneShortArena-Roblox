local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

return function(context, player)
	local PDS = ServiceLocator:Get("PlayerDataService")
	
	if not PDS then
		return "❌ PlayerDataService ไม่พร้อม!"
	end
	
	if not PDS:IsDataLoaded(player) then
		return `❌ ข้อมูลของ {player.Name} ยังไม่โหลด!`
	end
	
	local data = PDS:GetAll(player)
	
	if not data then
		return `❌ ไม่พบข้อมูลของ {player.Name}`
	end
	
	-- Format output
	local output = {
		`📊 ข้อมูลของ {player.Name}:`,
		`💰 Coins: {data.Coins}`,
		`💎 Gems: {data.Gems}`,
		`⭐ Level: {data.Level} (XP: {data.Experience})`,
		`⚔️ Kills: {data.Kills} | Deaths: {data.Deaths}`,
		`🏆 Wins: {data.Wins} | Losses: {data.Losses}`,
		`📦 Items: {PDS:GetItemCount(player)}`,
	}
	
	return table.concat(output, "\n")
end
