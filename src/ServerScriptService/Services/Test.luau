
-- ไฟล์นี้ใช้สำหรับทดสอบ server-side services
-- ไม่ควรนำไปรวมใน production build
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local NetworkHandler = require(ServerScriptService.Services.NetworkHandler)

export type TestService = {
    Init: (self: TestService) -> (),
    Start: (self: TestService) -> (),
    [string]: any,
}

local TestService = {} :: TestService

function TestService:Init()
    NetworkHandler:AllowClientEvent(Events.TEST_PING)

    print("[TestServie-Server] Initialized")
end

-- Runtime Service
function TestService:Start()


    print("[TestServie-Server] Started")
end

return TestService