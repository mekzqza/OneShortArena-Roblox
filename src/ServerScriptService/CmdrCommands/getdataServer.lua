local ServerScriptService = game:GetService("ServerScriptService")
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

return function(context, targetPlayer)
	-- ถ้าไม่ระบุ target ใช้ตัวเอง
	targetPlayer = targetPlayer or context.Executor
	
	local PDS = ServiceLocator:Get("PlayerDataService")
	if not PDS then
		return "❌ PlayerDataService ไม่พร้อม!"
	end
	
	-- Get all data
	local data = PDS:GetAll(targetPlayer)
	if not data then
		return `❌ ไม่พบข้อมูลของ {targetPlayer.Name}!`
	end
	
	-- Format output
	local output = {
		`📊 ข้อมูลของ {targetPlayer.Name}:`,
		`━━━━━━━━━━━━━━━━━━━━━━━━━━━━`,
		`💰 เหรียญ: {data.Coins}`,
		`💎 เจมส์: {data.Gems}`,
		`⭐ เลเวล: {data.Level} (XP: {data.Experience})`,
		``,
		`⚔️ สถิติการต่อสู้:`,
		`  • ฆ่า: {data.Kills}`,
		`  • ตาย: {data.Deaths}`,
		`  • ชนะ: {data.Wins}`,
		`  • แพ้: {data.Losses}`,
		``,
		`🎒 ไอเท็ม: {PDS:GetItemCount(targetPlayer)} ชิ้น`,
	}
	
	return table.concat(output, "\n")
end
