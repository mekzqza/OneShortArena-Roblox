local ServerScriptService = game:GetService("ServerScriptService")
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

return function(context, players)
	local LobbyService = ServiceLocator:Get("LobbyService")
	local PlayerStateService = ServiceLocator:Get("PlayerStateService")
	
	if not LobbyService or not PlayerStateService then
		return "❌ Services ไม่พร้อม!"
	end
	
	local count = 0
	for _, player in ipairs(players) do
		-- Set state to Lobby
		PlayerStateService:SetState(player, "Lobby", {
			reason = "Admin teleport",
			forced = true,
		})
		
		-- Spawn in lobby
		LobbyService:SpawnPlayerInLobby(player)
		count += 1
	end
	
	return `✅ ส่ง {count} คนไป Lobby แล้ว!`
end
