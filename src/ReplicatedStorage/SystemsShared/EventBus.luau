---- หัวใจสำคัญของการสื่อสารในระบบของเรา -
-- EventBus Module

local EventBus = {}
EventBus.signals = {}

local function getSignal(eventName: string): Instance
    if not EventBus.signals[eventName] then
        EventBus.signals[eventName] = Instance.new("BindableEvent")
    end
    return EventBus.signals[eventName]
end

function EventBus.On(eventName: string, callback: () -> ())
    local signal = getSignal(eventName)
    return signal.Event:Connect(callback)
end

function EventBus.Emit(eventName: string, ...)
    local signal = getSignal(eventName)
    signal:Fire(...)
end

function Once(eventName: string, callback: () -> ())
    local connection
    connection = EventBus.On(eventName, function(...)
        if connection then
            connection:Disconnect()
            connection = nil
        end
        callback(...)
    end)
    
end
return EventBus