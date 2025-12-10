local ContexAcctionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local InputSettings=require(ReplicatedStorage.Shared.InputSettings)

local InputComtroller = {}

local function handlerInput(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
    if inputState == Enum.UserInputState.Begin then
        EventBus:Emit(Events.INPUT_ACTION_TRIGGERED, actionName, inputObject)
    end
    
end 


return InputComtroller