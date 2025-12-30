--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)

export type Payload = {
    dataString: string,
dataNumber: number,
dataArray: {
        data: {
            mek1: number,
            mek2: number,
        }
    },
}

export type TestHandler = {
    Init: (self: TestHandler) -> (),
    Start: (self: TestHandler) -> (),
    SendPingWithTrigger_P: (self: TestHandler) -> (),
    SendPingTimer: (self: TestHandler, time: number?) -> (),
    SendPing: (self: TestHandler, data: any?) -> (),
    StopPingTimer: (self: TestHandler) -> (),
    [string]: any,
}

local TestHandler = {} :: TestHandler

-- ✅ เก็บ task สำหรับยกเลิก
TestHandler.pingTimerTask = nil

function TestHandler:Init()
    print("[TestHandler-Client] 🧪 Initialized")
end

function TestHandler:Start()
    print("[TestHandler-Client] 🚀 Starting...")

    -- ✅ Setup input trigger
    self:SendPingWithTrigger_P()
    print("[TestHandler-Client] ✅ Started")
    EventBus:On(Events.TEST_PONG, function(data: any)
        print("[TestHandler-Client] 📥 Received pong from server:", data)
    end)

end

-- ✅ ส่ง ping เมื่อกด P
function TestHandler:SendPingWithTrigger_P()
    EventBus:On(Events.INPUT_ACTION, function(actionName: string)
        if actionName == "TESTPING" then
            print("[TestHandler-Client] 🎮 P pressed - Sending ping...")
            
            local payload: Payload = {
                dataString = "888",
                dataNumber = 12345,
                dataArray = {
                    data = {
                        mek1 = 1,
                        mek2 = 2
                    }
                },
            }
            
            self:SendPing(payload)
        end
    end)
end

-- ✅ ส่ง ping อัตโนมัติทุก X วินาที
function TestHandler:SendPingTimer(time: number?)
    local interval = time or 5  -- ✅ แก้: ไม่ใช้ชื่อ wait
    
    -- ✅ หยุด timer เก่าก่อน (ถ้ามี)
    if self.pingTimerTask then
        task.cancel(self.pingTimerTask)
        print("[TestHandler-Client] 🛑 Stopped previous ping timer")
    end
    
    print(`[TestHandler-Client] 🔁 Starting auto ping (every {interval}s)`)
    
    -- ✅ สร้าง task ใหม่
    self.pingTimerTask = task.spawn(function()
        while true do
            task.wait(interval)
            
            -- ✅ สร้าง payload ทุกครั้ง
            local payload: Payload = {
                dataString = "Auto ping",
                dataNumber = math.random(1, 999),
                dataArray = {
                    data = {
                        mek1 = math.random(1, 10),
                        mek2 = math.random(1, 10)
                    }
                },
            }
            
            self:SendPing(payload)
        end
    end)
end

-- ✅ หยุด auto ping
function TestHandler:StopPingTimer()
    if self.pingTimerTask then
        task.cancel(self.pingTimerTask)
        self.pingTimerTask = nil
        print("[TestHandler-Client] 🛑 Ping timer stopped")
    else
        warn("[TestHandler-Client] ⚠️ No ping timer running")
    end
end

-- ✅ ส่ง ping (รับ any type)
function TestHandler:SendPing(data: any?)
    -- ✅ แก้ไข: ใช้ Registry ตอน runtime (ไม่ใช่ top level!)
    local Controllers = _G.ControllersByCategory
    
    if not Controllers or not Controllers.Core or not Controllers.Core.NetworkController then
        warn("[TestHandler-Client] ❌ NetworkController not found in Registry!")
        return
    end
    
    local NetworkController = Controllers.Core.NetworkController
    
    local payload = data
    
    -- ✅ ถ้าไม่ส่งข้อมูลมา ใช้ default
    if not payload then
        payload = {
            dataString = "Default ping",
            dataNumber = 0,
            dataArray = {
                data = {
                    mek1 = 0,
                    mek2 = 0
                }
            },
        }
    end
    
    print("[TestHandler-Client] 📤 Sending ping...")
    NetworkController:Send(Events.TEST_PING, payload)
end

return TestHandler