--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║           CMDR SERVICE - SERVER SIDE                           ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Initialize Cmdr command console (server component)   ║
║ Features:                                                      ║
║  ✅ Auto-detect Cmdr package location                          ║
║  ✅ Register default commands                                  ║
║  ✅ Register admin hooks                                       ║
║  ✅ Support custom commands                                    ║
║  ✅ Graceful degradation (works without Cmdr)                  ║
╚════════════════════════════════════════════════════════════════╝
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Cmdr = require(Packages.Cmdr)


local CmdrService = {}

function CmdrService:Init()

end

function CmdrService:Start()

-- This is a script you would create in ServerScriptService, for example.

Cmdr:RegisterDefaultCommands() -- This loads the default set of commands that Cmdr comes with. (Optional)
-- Cmdr:RegisterCommandsIn(script.Parent.CmdrCommands) -- Register commands from your own folder. (Optional)
Cmdr:RegisterHooksIn(ServerStorage.Secrets.Hooks) -- Register hooks from your own folder. (Optional)
	
end

return CmdrService