local serverScriptService = game:GetService("ServerScriptService")
local Services = serverScriptService:WaitForChild("Services") -- ใช้ WaitForChild กันพลาด

print("🔌 Server Init: Starting Services...")

-- Initialize gameplay services
local GameService = require(script.Services.GameService)
local ArenaService = require(script.Services.ArenaService)
local CombatService = require(script.Services.CombatService)

-- Initialize in dependency order
GameService:Init()
ArenaService:Init()
CombatService:Init()

for _, serviceModule in pairs(Services:GetChildren()) do
    if serviceModule:IsA("ModuleScript") then
        -- ใช้ task.spawn เพื่อแยก Thread (ตัวใครตัวมัน ไม่รอกัน)
        task.spawn(function()
            local service = require(serviceModule)
            
            -- เช็คว่ามีฟังก์ชัน Init ไหม ถ้ามีให้เรียกใช้
            if type(service.Init) == "function" then
                -- ใช้ pcall กัน Error พังทั้งระบบ
                local success, err = pcall(function()
                    service:Init() -- แนะนำใช้ : ถ้าออกแบบเป็น OOP/Singleton
                end)
                
                if not success then
                    warn("❌ Failed to init " .. serviceModule.Name .. ": " .. err)
                end
            end
        end)
    end
end

print("✅ Services initialized.")