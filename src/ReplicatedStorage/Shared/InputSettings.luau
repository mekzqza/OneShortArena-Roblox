
--!strict

-- InputSettings: centralized input action names and default bindings.
-- Note: ready for future dynamic remapping; current module provides read-only helpers.

export type ActionId = "ATTACK" | "DASH" | "INTERACT" 
export type ActionNameMap = { [ActionId]: string }
export type Binding = Enum.KeyCode | Enum.UserInputType
export type BindingMap = { [ActionId]: { Binding } }
export type MobileButtonMap = { [ActionId]: string }

local ACTIONS: ActionNameMap = table.freeze({
    ATTACK = "Attack",
    DASH = "Dash",
    INTERACT = "Interact",
    RESPAWN = "Respawn",
    TESTCLICK = "TestClick",
})

local DEFAULT_BINDINGS: BindingMap = table.freeze({
    ATTACK = table.freeze({ Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 }),
    DASH = table.freeze({ Enum.KeyCode.Q, Enum.KeyCode.ButtonL1 }),
    INTERACT = table.freeze({ Enum.KeyCode.F, Enum.KeyCode.ButtonX }),
    RESPAWN =table.freeze({ Enum.KeyCode.R, Enum.KeyCode.ButtonA }),
    TESTCLICK = table.freeze({ Enum.KeyCode.T, Enum.KeyCode.ButtonY }),
})

local MOBILE_BUTTON_NAMES: MobileButtonMap = table.freeze({
    ATTACK = "AttackButton",
    DASH = "DashButton",
    INTERACT = "InteractButton",
    RESPAWN = "RespawnButton",
    TESTCLICK = "TestClickButton",

})

local function copyArray<T>(source: { T }): { T }
    local clone = table.create(#source)
    for i, v in ipairs(source) do
        clone[i] = v
    end
    return clone
end

local InputSettings = {}

function InputSettings.GetActionName(actionId: ActionId): string
    return ACTIONS[actionId]
end

function InputSettings.GetBindings(actionId: ActionId): { Binding }?
    local bindings = DEFAULT_BINDINGS[actionId]
    if bindings == nil then
        return nil
    end
    return copyArray(bindings) -- protect against accidental external mutation
end

function InputSettings.GetMobileButtonName(actionId: ActionId): string?
    return MOBILE_BUTTON_NAMES[actionId]
end

function InputSettings.GetAllActions(): { ActionId }
    return { "ATTACK", "DASH", "INTERACT" }
end

-- Expose raw tables if needed (read-only, already frozen)
InputSettings.Actions = ACTIONS
InputSettings.Bindings = DEFAULT_BINDINGS
InputSettings.MobileButtonNames = MOBILE_BUTTON_NAMES

return InputSettings