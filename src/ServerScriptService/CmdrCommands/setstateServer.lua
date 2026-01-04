local ServerScriptService = game:GetService("ServerScriptService")
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

return function(context, targetPlayer, newState)
	-- Validate state
	local validStates = {
		Lobby = true,
		Arena = true,
		Playing = true,
		Downed = true,
		Spectating = true,
	}
	
	if not validStates[newState] then
		return `❌ สถานะไม่ถูกต้อง! ใช้ได้: Lobby, Arena, Playing, Downed, Spectating`
	end
	
	-- Get PlayerStateService
	local PSS = ServiceLocator:Get("PlayerStateService")
	if not PSS then
		return "❌ PlayerStateService ไม่พร้อม!"
	end
	
	-- Transition
	local success, err = PSS:TransitionTo(targetPlayer, newState, {
		reason = "Admin command",
		forced = true,
	})
	
	if success then
		return `✅ เปลี่ยนสถานะ {targetPlayer.Name} เป็น {newState} สำเร็จ!`
	else
		return `❌ ล้มเหลว: {err}`
	end
end
