local ReplicatedStorage =game:GetService("ReplicatedStorage")

local EventBus =require(ReplicatedStorage.SystemsShared.EventBus)
local Events =require(ReplicatedStorage.Shared.Events)

local DegbugInputController = {}



function DegbugInputController:Init()
    print("DebugInputController initialized")   
end

function DegbugInputController:Start()
    print("DebugInputController started")   
    EventBus:On(Events.INPUT_ACTION, function(actionName: string)
        print("Input Action Triggered: " .. actionName)
    end)
end


return DegbugInputController