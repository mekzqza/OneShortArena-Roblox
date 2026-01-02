--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CmdrController = {}

local CmdrClient = nil

export type CmdrController = {
	Init: (self: CmdrController) -> (),
	Start: (self: CmdrController) -> (),
}

function CmdrController:Init()
	print("[CmdrController] 🔧 Initializing...")
	
	-- ✅ Load CmdrClient from ReplicatedStorage
	local success, result = pcall(function()
		return require(ReplicatedStorage:WaitForChild("CmdrClient"))
	end)
	
	if success and result then
		CmdrClient = result
		print("[CmdrController] ✅ Loaded CmdrClient")
	else
		warn(`[CmdrController] ⚠️ Failed to load CmdrClient: {result}`)
		return
	end
	
	-- ✅ Set activation keys
	if CmdrClient.SetActivationKeys then
		CmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })
		print("[CmdrController] ✅ Initialized. Press [F2] to open console")
	else
		warn("[CmdrController] ⚠️ SetActivationKeys not found!")
	end
end

function CmdrController:Start()
	print("[CmdrController] 🚀 Starting...")
	
	-- Nothing to do in Start for Cmdr
	
	print("[CmdrController] ✅ Started")
end

return CmdrController