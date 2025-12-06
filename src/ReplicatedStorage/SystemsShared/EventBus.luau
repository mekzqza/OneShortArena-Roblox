--[[
	EventBus Module - ระบบสื่อสารภายในของเกม (Production-Ready)
	
	📌 หน้าที่หลัก:
	EventBus เป็นหัวใจสำคัญของการสื่อสารภายในระบบของเรา
	ใช้สำหรับส่งข้อมูลระหว่าง Client-Client และ Server-Server
	โดยไม่ต้องพึ่งพา RemoteEvent/RemoteFunction
	
	🔧 ฟีเจอร์:
	- On: สมัครรับฟังอีเวนต์ (Subscribe)
	- Once: สมัครรับฟังอีเวนต์แค่ครั้งเดียว แล้วจะถอนการสมัครอัตโนมัติ
	- Off: ถอนการสมัครรับฟังอีเวนต์ทั้งหมดของอีเวนต์นั้น
	- Emit: ส่งอีเวนต์พร้อมข้อมูล
	- Clear: ลบอีเวนต์ทั้งหมดและทำความสะอาด memory
	- GetEventNames: ดูรายชื่ออีเวนต์ทั้งหมดที่มีในระบบ
	
	📖 ตัวอย่างการใช้งาน:
	
	-- การสมัครรับฟังอีเวนต์
	local connection = EventBus:On("PlayerJoined", function(playerName, level)
		print(playerName .. " joined with level " .. level)
	end)
	
	-- การส่งอีเวนต์
	EventBus:Emit("PlayerJoined", "John", 5)
	
	-- การสมัครรับฟังแค่ครั้งเดียว
	EventBus:Once("GameStarted", function()
		print("Game has started!")
	end)
	
	-- การถอนการสมัคร (ผ่าน connection)
	connection:Disconnect()
	
	-- การถอนการสมัครทั้งหมดของอีเวนต์
	EventBus:Off("PlayerJoined")
	
	-- การลบอีเวนต์ทั้งหมด (ใช้ตอน cleanup)
	EventBus:Clear()
	
	⚠️ ข้อควรระวัง:
	- ต้องเก็บ connection ไว้ ถ้าต้องการ Disconnect ในภายหลัง
	- ใช้ Once สำหรับอีเวนต์ที่ต้องการรับแค่ครั้งเดียว เพื่อป้องกัน memory leak
	- ใช้ Off หรือ Clear เมื่อไม่ใช้งานแล้ว เพื่อป้องกัน memory leak
	- EventBus ใช้ได้ทั้ง Client และ Server แต่จะไม่สื่อสารข้ามกัน
	
	💡 Best Practices:
	- ตั้งชื่ออีเวนต์ให้มีความหมายชัด เช่น "Player_Died", "UI_Opened"
	- ใช้ Once สำหรับอีเวนต์ที่เกิดครั้งเดียว เช่น "GameInitialized"
	- จัดกลุ่มอีเวนต์ด้วย prefix เช่น "UI_", "Player_", "Game_"
	- ทำ cleanup ใน Destroy หรือ Cleanup functions
--]]

local EventBus = {}
EventBus.signals = {} -- เก็บ BindableEvent ทั้งหมด

type EventCallback = (...any) -> ()
type EventConnection = RBXScriptConnection

--[[
	ฟังก์ชันภายใน: getSignal
	หน้าที่: สร้างหรือดึง BindableEvent สำหรับ event ที่ระบุ
	@param eventName: string - ชื่อของ event
	@return BindableEvent - signal object สำหรับ event นั้น
--]]
local function getSignal(eventName: string): BindableEvent
	-- ตรวจสอบว่ามี signal อยู่แล้วหรือไม่
	if not EventBus.signals[eventName] then
		-- สร้างใหม่ถ้ายังไม่มี
		EventBus.signals[eventName] = Instance.new("BindableEvent")
	end
	return EventBus.signals[eventName]
end

--[[
	On: สมัครรับฟังอีเวนต์
	หน้าที่: เชื่อมต่อ callback function กับ event ที่ระบุ
	@param eventName: string - ชื่อของ event ที่ต้องการฟัง
	@param callback: function - ฟังก์ชันที่จะถูกเรียกเมื่อ event เกิดขึ้น
	@return RBXScriptConnection - connection object สำหรับ disconnect ในภายหลัง
	
	ตัวอย่าง:
	local conn = EventBus:On("PlayerDied", function(playerName)
		print(playerName .. " has died")
	end)
--]]
function EventBus:On(eventName: string, callback: EventCallback): EventConnection
	assert(type(eventName) == "string", "eventName must be a string")
	assert(type(callback) == "function", "callback must be a function")
	
	local signal = getSignal(eventName)
	return signal.Event:Connect(callback)
end

--[[
	Once: สมัครรับฟังอีเวนต์แค่ครั้งเดียว
	หน้าที่: เชื่อมต่อ callback function กับ event แต่จะถูกถอนการเชื่อมต่ออัตโนมัติหลังจากถูกเรียกครั้งแรก
	@param eventName: string - ชื่อของ event ที่ต้องการฟัง
	@param callback: function - ฟังก์ชันที่จะถูกเรียกเมื่อ event เกิดขึ้น
	@return RBXScriptConnection - connection object สำหรับ disconnect ในภายหลัง (ถ้าต้องการยกเลิกก่อนที่จะถูกเรียก)
	
	ตัวอย่าง:
	EventBus:Once("GameStarted", function()
		print("Game has started!")
	end)
--]]
function EventBus:Once(eventName: string, callback: EventCallback): EventConnection
	assert(type(eventName) == "string", "eventName must be a string")
	assert(type(callback) == "function", "callback must be a function")
	
	-- ใช้ flag เพื่อป้องกัน race condition
	local hasBeenCalled = false
	local connection
	
	connection = self:On(eventName, function(...)
		-- ตรวจสอบว่าถูกเรียกไปแล้วหรือยัง (thread-safe)
		if hasBeenCalled then
			return
		end
		hasBeenCalled = true
		
		-- ถอนการเชื่อมต่อ
		if connection then
			connection:Disconnect()
			connection = nil
		end
		
		-- เรียก callback พร้อมส่งต่อ arguments ทั้งหมด
		callback(...)
	end)
	
	return connection
end

--[[
	Emit: ส่งอีเวนต์พร้อมข้อมูล
	หน้าที่: เรียก callback functions ทั้งหมดที่สมัครรับฟัง event นี้
	@param eventName: string - ชื่อของ event ที่ต้องการส่ง
	@param ...: any - ข้อมูลที่ต้องการส่งไปยัง callbacks (รองรับหลาย arguments)
	
	ตัวอย่าง:
	EventBus:Emit("PlayerJoined", "John", 5, true)
--]]
function EventBus:Emit(eventName: string, ...: any)
	assert(type(eventName) == "string", "eventName must be a string")
	
	-- ตรวจสอบว่ามี signal หรือไม่ (ไม่สร้างใหม่ถ้ายังไม่มี)
	local signal = EventBus.signals[eventName]
	if signal then
		-- Fire ตรงๆ เพราะ BindableEvent มี error handling ภายในอยู่แล้ว
		-- Listener แต่ละตัวจะ run แยกกัน ถ้า listener ตัวหนึ่ง error จะไม่กระทบตัวอื่น
		signal:Fire(...)
	end
	-- ถ้าไม่มี signal ก็ไม่ต้องทำอะไร (ไม่มีใครสมัครรับฟัง)
	-- หมายเหตุ: เราไม่ใช้ getSignal() เพราะไม่ต้องการสร้าง signal ใหม่เมื่อยังไม่มีใครฟัง
end

--[[
	Off: ถอนการสมัครรับฟังอีเวนต์ทั้งหมด
	หน้าที่: ลบ callbacks ทั้งหมดที่สมัครรับฟัง event นี้และทำลาย signal
	@param eventName: string - ชื่อของ event ที่ต้องการถอนการสมัคร
	
	ตัวอย่าง:
	EventBus:Off("PlayerJoined")
--]]
function EventBus:Off(eventName: string)
	assert(type(eventName) == "string", "eventName must be a string")
	
	local signal = EventBus.signals[eventName]
	if signal then
		-- ทำลาย BindableEvent เพื่อถอน connections ทั้งหมด
		signal:Destroy()
		EventBus.signals[eventName] = nil
	end
end

--[[
	Clear: ลบอีเวนต์ทั้งหมดและทำความสะอาด
	หน้าที่: ทำลาย signals ทั้งหมดและล้าง memory
	ใช้เมื่อต้องการ reset ระบบ EventBus หรือก่อนจะปิดระบบ
	
	⚠️ ระวัง: จะลบ event listeners ทั้งหมดในระบบ!
	
	ตัวอย่าง:
	EventBus:Clear()
--]]
function EventBus:Clear()
	-- วนลบทุก signal และล้าง reference ในตาราง
	for eventName, signal in pairs(EventBus.signals) do
		if signal then
			signal:Destroy()
		end
		-- ล้าง reference ทันที
		EventBus.signals[eventName] = nil
	end
end

--[[
	GetEventNames: ดูรายชื่ออีเวนต์ทั้งหมด
	หน้าที่: ส่งคืนรายการชื่อ events ทั้งหมดที่มีในระบบ
	@return table - ตารางที่เก็บชื่อ events ทั้งหมด
	
	ตัวอย่าง:
	local events = EventBus:GetEventNames()
	for _, eventName in ipairs(events) do
		print("Event:", eventName)
	end
--]]
function EventBus:GetEventNames(): {string}
	local eventNames = {}
	for eventName, _ in pairs(EventBus.signals) do
		table.insert(eventNames, eventName)
	end
	return eventNames
end

return EventBus