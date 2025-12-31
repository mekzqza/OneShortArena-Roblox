-- src/ServerScriptService/Services/Cloud/PocketBaseService.luau
--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local PocketBaseService = {}
PocketBaseService.__index = PocketBaseService

-- ✅ SECURE: โหลดจากไฟล์ Secret (ไม่ commit)
local SECRET_CONFIG = nil
local hasSecret = pcall(function()
	local SecretsFolder = ServerStorage:FindFirstChild("Secrets")
	if SecretsFolder then
		local SecretModule = SecretsFolder:FindFirstChild("PocketBaseSecret")
		if SecretModule then
			SECRET_CONFIG = require(SecretModule)
		end
	end
end)

-- ✅ FALLBACK: Development config (ค่า dummy สำหรับ testing)
local CONFIG = SECRET_CONFIG or {
	URL = "https://example.com",  -- ❌ Dummy URL
	COLLECTION = "player_stats",
	ADMIN_EMAIL = "admin@example.com",  -- ❌ Dummy Email
	ADMIN_PASS = "dummy_password",       -- ❌ Dummy Password
}

-- ✅ Warning ถ้าไม่มี Secret Config
if not hasSecret or not SECRET_CONFIG then
	warn("⚠️ [PocketBase] SECRET CONFIG NOT FOUND!")
	warn("⚠️ [PocketBase] Using DUMMY config (service will NOT work!)")
	warn("⚠️ [PocketBase] Create: ServerStorage/Secrets/PocketBaseSecret.luau")
end

local authToken = nil
local tokenExpiry = 0

-- ฟังก์ชัน Login (Auto)
local function ensureAuth()
	if authToken and os.time() < tokenExpiry then 
		return true 
	end

	-- ✅ เช็คว่ามี config จริงหรือไม่
	if not SECRET_CONFIG then
		warn("❌ [PocketBase] Cannot authenticate: No secret config!")
		return false
	end

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = CONFIG.URL .. "/api/admins/auth-with-password",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({
				identity = CONFIG.ADMIN_EMAIL,
				password = CONFIG.ADMIN_PASS
			})
		})
	end)

	if success and response.StatusCode == 200 then
		local data = HttpService:JSONDecode(response.Body)
		authToken = data.token
		tokenExpiry = os.time() + (60 * 60)
		print("✅ [PocketBase] Connected via HTTPS!")
		return true
	else
		warn("❌ [PocketBase] Auth Failed: ", response)
		return false
	end
end

-- ฟังก์ชัน Sync ข้อมูล
function PocketBaseService:SyncPlayer(userId: number, data: table)
	task.spawn(function()
		if not ensureAuth() then return end

		-- 1. Search existing record
		local recordId = nil
		local searchUrl = CONFIG.URL .. "/api/collections/" .. CONFIG.COLLECTION .. "/records?filter=(roblox_id='" .. userId .. "')"
		
		local searchSuccess, searchRes = pcall(function()
			return HttpService:RequestAsync({
				Url = searchUrl,
				Method = "GET",
				Headers = { ["Authorization"] = authToken }
			})
		end)

		if searchSuccess and searchRes.StatusCode == 200 then
			local result = HttpService:JSONDecode(searchRes.Body)
			if result.items and #result.items > 0 then
				recordId = result.items[1].id
			end
		end

		-- 2. Prepare Data & Save
		local payload = {
			roblox_id = tostring(userId),
			coins = data.Coins or 0,
			level = data.Level or 1
		}

		local method = recordId and "PATCH" or "POST"
		local finalUrl = CONFIG.URL .. "/api/collections/" .. CONFIG.COLLECTION .. "/records"
		if recordId then finalUrl = finalUrl .. "/" .. recordId end

		local saveSuccess, saveRes = pcall(function()
			return HttpService:RequestAsync({
				Url = finalUrl,
				Method = method,
				Headers = {
					["Content-Type"] = "application/json",
					["Authorization"] = authToken
				},
				Body = HttpService:JSONEncode(payload)
			})
		end)

		if saveSuccess then
			print("💾 [PocketBase] Saved data for " .. userId)
		else
			warn("❌ [PocketBase] Save Error: " .. tostring(saveRes))
		end
	end)
end

function PocketBaseService:Init()
	if SECRET_CONFIG then
		print("🚀 PocketBase Service Initialized (SECURE MODE)")
	else
		warn("⚠️ PocketBase Service Initialized (DUMMY MODE - NOT FUNCTIONAL!)")
	end
end

return PocketBaseService