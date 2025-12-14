--!strict

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local Events = require(ReplicatedStorage.Shared.Events)
local InputSettings = require(ReplicatedStorage.Shared.InputSettings)

export type ModuleImpl = {
	Init: (self: ModuleImpl) -> (),
	Start: (self: ModuleImpl) -> (),
	BindAllActions: (self: ModuleImpl) -> (),
	UnbindAll: (self: ModuleImpl) -> (),
	[string]: any,
}

local InputController: ModuleImpl = {}

local EVENT_INPUT_ACTION = (Events :: any).INPUT_ACTION

local function onInput(actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject?)
	if inputState == Enum.UserInputState.Begin then
		EventBus:Emit(EVENT_INPUT_ACTION, actionName)
	end
end

function InputController:Init()
	-- Bind immediately so input works as soon as controllers load
	self:BindAllActions()
	print("🎮 InputController initialized and bindings applied")
end

function InputController:Start()
	-- No-op; bindings done in Init
end

function InputController:BindAllActions()
	for actionName, keys in pairs(InputSettings.Bindings) do
		ContextActionService:BindAction(actionName, onInput, true, table.unpack(keys))

		local title = InputSettings.MobileButtonNames[actionName]
		if title then
			ContextActionService:SetTitle(actionName, title)
		end
	end
end

function InputController:UnbindAll()
	for actionName, _ in pairs(InputSettings.Bindings) do
		ContextActionService:UnbindAction(actionName)
	end
end

return InputController