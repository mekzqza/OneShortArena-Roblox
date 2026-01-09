--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║           PLAYER DATA SERVICE - PRODUCTION GRADE               ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Manage all player data with ProfileService           ║
╚════════════════════════════════════════════════════════════════╝
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Events = require(ReplicatedStorage.Shared.Events)
local EventBus = require(ReplicatedStorage.SystemsShared.EventBus)
local IdempotentGuard = require(ServerScriptService.Utils.IdempotentGuard)
local ServiceLocator = require(ServerScriptService.Utils.ServiceLocator)

-- Load ProfileService from Libs
local Libs = ServerScriptService:FindFirstChild("Libs")
local ProfileService: any = nil

if Libs then
	local ProfileServiceModule = Libs:FindFirstChild("ProfileService")
	if ProfileServiceModule then
		local success, result = pcall(function()
			return require(ProfileServiceModule)
		end)
		if success then
			ProfileService = result
			print("[PlayerDataService] ✅ Loaded ProfileService from Libs")
		else
			warn("[PlayerDataService] ⚠️ Failed to load ProfileService:", result)
		end
	else
		warn("[PlayerDataService] ⚠️ ProfileService module not found in Libs")	
	end	
end

 -- Lazy load PocketBaseService
local PocketBaseService: any = nil

local function getPocketBaseService()
	if not PocketBaseService then
		local success, service = pcall(function()
			return require(ServerScriptService.Services.Cloud.PocketBaseService)
		end)
		if success then
			PocketBaseService = service
			print("[PlayerDataService] ✅ Loaded PocketBaseService")
		else
			warn("[PlayerDataService] ⚠️ Failed to load PocketBaseService:", service)
			return nil
		end
	end
	return PocketBaseService
end

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type PlayerData = {
	_version: number,
	Coins: number,
	Gems: number,
	Level: number,
	Experience: number,
	Kills: number,
	Deaths: number,
	Wins: number,
	Losses: number,
	
	-- ✅ Dictionary-based for O(1) lookup
	OwnedItems: {[string]: boolean},  -- { ["Sword_001"] = true, ... }
	EquippedItems: {[string]: string?},
	
	Settings: {
		MusicVolume: number,
		SFXVolume: number,
		ShowDamageNumbers: boolean,
	},
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS & CONFIG
-- ═══════════════════════════════════════════════════════════════

local PlayerDataService = {}

local guard = IdempotentGuard.new("PlayerDataService", true)

local DATA_VERSION = 1

local DEFAULT_DATA: PlayerData = {
	_version = DATA_VERSION,
	Coins = 0,
	Gems = 0,
	Level = 1,
	Experience = 0,
	Kills = 0,
	Deaths = 0,
	Wins = 0,
	Losses = 0,
	
	-- ✅ Empty dictionary instead of array
	OwnedItems = {},
	EquippedItems = {},
	
	Settings = {
		MusicVolume = 0.5,
		SFXVolume = 0.8,
		ShowDamageNumbers = true,
	},
}

local VALIDATION_RULES: {[string]: {type: string, min: number?, max: number?}} = {
	Coins = { type = "number", min = 0, max = 999999999 },
	Gems = { type = "number", min = 0, max = 999999999 },
	Level = { type = "number", min = 1, max = 100 },
	Experience = { type = "number", min = 0, max = 999999999 },
	Kills = { type = "number", min = 0, max = 999999999 },
	Deaths = { type = "number", min = 0, max = 999999999 },
	Wins = { type = "number", min = 0, max = 999999999 },
	Losses = { type = "number", min = 0, max = 999999999 },
}

local PROFILE_STORE_NAME = "PlayerData_v1"

local SYNC_CONFIG = {
	EnableCloudSync = true,
	SyncOnWrite = true,
	SyncOnLeave = true,
	SyncDebounce = 5,
	CriticalKeys = {"Coins", "Gems", "Level", "Wins"},
}

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local ProfileStore: any = nil
local Profiles: {[number]: any} = {}
local LoadingPlayers: {[number]: boolean} = {}
local lastCloudSync: {[number]: number} = {}

local analytics = {
	totalLoads = 0,
	totalReleases = 0,
	loadFailures = 0,
	totalReads = 0,
	totalWrites = 0,
	blockedWrites = 0,
	migrations = 0,
	startTime = os.clock(),
}
-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function validateValue(key: string, value: any): {valid: boolean, clampedValue: any?, reason: string?}
	local rule = VALIDATION_RULES[key]
	if not rule then return { valid = true } end
	
	if type(value) ~= rule.type then
		return { valid = false, reason = `Expected {rule.type}, got {type(value)}` }
	end
	
	if rule.type == "number" then
		local num = value :: number
		local clamped = num
		if rule.min and num < rule.min then clamped = rule.min end
		if rule.max and num > rule.max then clamped = rule.max end
		if clamped ~= num then
			return { valid = true, clampedValue = clamped, reason = `Value clamped from {num} to {clamped}` }
		end
	end
	
	return { valid = true }
end

local function deepClone(original: any): any
	if type(original) ~= "table" then return original end
	local copy = {}
	for key, value in pairs(original) do
		copy[deepClone(key)] = deepClone(value)
	end
	return copy
end

local function shouldSyncToCloud(userId: number, key: string?): boolean
	if not SYNC_CONFIG.EnableCloudSync then return false end
	local now = os.time()
	local lastSync = lastCloudSync[userId]
	if lastSync and (now - lastSync) < SYNC_CONFIG.SyncDebounce then
		if key and table.find(SYNC_CONFIG.CriticalKeys, key) then return true end
		return false
	end
	return true
end

-- ❌ NOT RECOMMENDED (blocking)
local function syncToCloud(userId: number, data: {[string]: any})
	local pbs = getPocketBaseService()
	if not pbs then return end
	lastCloudSync[userId] = os.time()  -- ❌ Method ไม่มี!
	
	-- Spawn async to not block
	task.spawn(function()
		pbs:SyncPlayerAsync(userId, data)
	end)
end

-- ✅ NEW: Migrate OwnedItems from Array to Dictionary
local function migrateData(data: {[string]: any}, fromVersion: number): {[string]: any}
	print(`[PlayerDataService] 🔄 Migrating data from v{fromVersion} to v{DATA_VERSION}`)
	
	if fromVersion < 1 then
		-- Migrate OwnedItems from Array to Dictionary
		if data.OwnedItems and type(data.OwnedItems) == "table" then
			local oldItems = data.OwnedItems
			local newItems: {[string]: boolean} = {}
			
			-- Check if it's an array (has numeric indices)
			if oldItems[1] then
				-- Convert array to dictionary
				for _, itemId in ipairs(oldItems) do
					newItems[itemId] = true
				end
				data.OwnedItems = newItems
				print(`[PlayerDataService] ✅ Migrated {#oldItems} items to dictionary format`)
			end
		end
		
		-- Add missing fields
		data.Gems = data.Gems or 0
		data.Settings = data.Settings or {
			MusicVolume = 0.5,
			SFXVolume = 0.8,
			ShowDamageNumbers = true,
		}
		data.EquippedItems = data.EquippedItems or {}
	end
	
	data._version = DATA_VERSION
	analytics.migrations += 1
	
	return data
end

local function loadPlayerProfile(player: Player)
	local userId = player.UserId
	local profileKey = `Player_{userId}`
	
	if LoadingPlayers[userId] or Profiles[userId] then return end
	if not ProfileStore then
		warn("[PlayerDataService] ⚠️ ProfileStore not initialized")
		return
	end
	
	LoadingPlayers[userId] = true
	analytics.totalLoads += 1
	
	print(`[PlayerDataService] 📥 Loading profile for {player.Name}...`)
	
	local profile = ProfileStore:LoadProfileAsync(profileKey, "ForceLoad")
	
	if not player or not player.Parent then
		if profile then profile:Release() end
		LoadingPlayers[userId] = nil
		return
	end
	
	if not profile then
		LoadingPlayers[userId] = nil
		analytics.loadFailures += 1
		warn(`[PlayerDataService] ❌ Failed to load profile for {player.Name}`)
		player:Kick("Failed to load your data. Please rejoin.")
		return
	end
	
	profile:AddUserId(userId)
	profile:Reconcile()
	
	-- ✅ Check for migration
	local dataVersion = profile.Data._version or 0
	if dataVersion < DATA_VERSION then
		profile.Data = migrateData(profile.Data, dataVersion)
	end
	
	profile:ListenToRelease(function()
		Profiles[userId] = nil
		if player and player.Parent then
			player:Kick("Your data session ended. Please rejoin.")
		end
	end)
	
	Profiles[userId] = profile
	LoadingPlayers[userId] = nil
	
	print(`[PlayerDataService] ✅ Profile loaded for {player.Name}`)
	
	EventBus:Emit(Events.PLAYER_DATA_LOADED, player, {
		data = deepClone(profile.Data),
		timestamp = os.clock(),
	})
end

local function releasePlayerProfile(player: Player)
	local userId = player.UserId
	local profile = Profiles[userId]
	
	if profile then
		if SYNC_CONFIG.SyncOnLeave then
			local pbs = getPocketBaseService()
			if pbs then pbs:SyncPlayerAsync(userId, profile.Data) end
		end
		profile:Release()
		analytics.totalReleases += 1
	end
	
	LoadingPlayers[userId] = nil
	lastCloudSync[userId] = nil
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS
-- ═══════════════════════════════════════════════════════════════

function PlayerDataService:Init()
	if not guard:MarkInitialized() then return end
	
	if not ProfileService then
		warn("[PlayerDataService] ❌ ProfileService not available!")
		return
	end
	
	ProfileStore = ProfileService.GetProfileStore(PROFILE_STORE_NAME, DEFAULT_DATA)
	
	print("[PlayerDataService] 🗄️ Initialized")
	print(`  ✅ Store: {PROFILE_STORE_NAME}`)
	print(`  ✅ Data Version: {DATA_VERSION}`)
end

function PlayerDataService:Start()
	if not guard:MarkStarted() then return end
	
	if not ProfileStore then
		warn("[PlayerDataService] ⚠️ Cannot start - ProfileStore not available")
		return
	end
	
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadPlayerProfile, player)
	end
	
	Players.PlayerAdded:Connect(loadPlayerProfile)
	Players.PlayerRemoving:Connect(releasePlayerProfile)
	
	-- ✨ Register request handler
	local NetworkHandler = ServiceLocator:Get("NetworkHandler")
	
	if NetworkHandler then
		NetworkHandler:RegisterRequestHandler("GetPlayerData", function(player: Player, data: any)
			-- Get all player data
			local playerData = self:GetAll(player)
			
			if playerData then
				return true, playerData -- Success
			else
				return false, "Data not loaded" -- Error
			end
		end)
		
		NetworkHandler:RegisterRequestHandler("GetPlayerCoins", function(player: Player, data: any)
			local coins = self:Get(player, "Coins")
			
			if coins then
				return true, { coins = coins }
			else
				return false, "Could not get coins"
			end
		end)
	end
	
	print("[PlayerDataService] 🚀 Started")
end

function PlayerDataService:GetProfile(player: Player): any?
	return Profiles[player.UserId]
end

function PlayerDataService:IsDataLoaded(player: Player): boolean
	return Profiles[player.UserId] ~= nil
end

function PlayerDataService:WaitForData(player: Player, timeout: number?): boolean
	timeout = timeout or 10
	local startTime = os.clock()
	while not self:IsDataLoaded(player) do
		if (os.clock() - startTime) > timeout or not player or not player.Parent then return false end
		task.wait(0.1)
	end
	return true
end

function PlayerDataService:Get(player: Player, key: string): any?
	local profile = Profiles[player.UserId]
	if not profile then return nil end
	analytics.totalReads += 1
	
	local keys = string.split(key, ".")
	local value: any = profile.Data
	for _, k in ipairs(keys) do
		if type(value) ~= "table" then return nil end
		value = value[k]
	end
	return value
end

function PlayerDataService:GetAll(player: Player): PlayerData?
	local profile = Profiles[player.UserId]
	if not profile then return nil end
	analytics.totalReads += 1
	return deepClone(profile.Data) :: PlayerData
end

function PlayerDataService:Set(player: Player, key: string, value: any): boolean
	local profile = Profiles[player.UserId]
	if not profile or not profile:IsActive() then
		analytics.blockedWrites += 1
		return false
	end
	
	local validation = validateValue(key, value)
	if not validation.valid then
		analytics.blockedWrites += 1
		return false
	end
	
	local finalValue = validation.clampedValue or value
	local keys = string.split(key, ".")
	
	if #keys == 1 then
		profile.Data[key] = finalValue
	else
		local target: any = profile.Data
		for i = 1, #keys - 1 do
			if type(target[keys[i]]) ~= "table" then target[keys[i]] = {} end
			target = target[keys[i]]
		end
		target[keys[#keys]] = finalValue
	end
	
	analytics.totalWrites += 1
	EventBus:Emit(Events.PLAYER_DATA_CHANGED, player, { key = key, newValue = finalValue })
	
	if SYNC_CONFIG.SyncOnWrite and shouldSyncToCloud(player.UserId, key) then
		syncToCloud(player.UserId, profile.Data)
	end
	
	return true
end

function PlayerDataService:Increment(player: Player, key: string, amount: number): (boolean, number?)
	local currentValue = self:Get(player, key)
	if type(currentValue) ~= "number" then return false, nil end
	local newValue = currentValue + amount
	local success = self:Set(player, key, newValue)
	return success, success and newValue or nil
end

-- ═══════════════════════════════════════════════════════════════
-- INVENTORY API (Dictionary-based - O(1))
-- ═══════════════════════════════════════════════════════════════

function PlayerDataService:HasItem(player: Player, itemId: string): boolean
	local ownedItems = self:Get(player, "OwnedItems") :: {[string]: boolean}?
	if not ownedItems then return false end
	return ownedItems[itemId] == true
end

function PlayerDataService:AddItem(player: Player, itemId: string): boolean
	local profile = Profiles[player.UserId]
	if not profile or not profile:IsActive() then return false end
	
	-- Check if already owned (O(1))
	if profile.Data.OwnedItems[itemId] then
		warn(`[PlayerDataService] ⚠️ {player.Name} already owns {itemId}`)
		return false
	end
	
	-- Add item (O(1))
	profile.Data.OwnedItems[itemId] = true
	analytics.totalWrites += 1
	
	EventBus:Emit(Events.PLAYER_ITEM_ADDED, player, { itemId = itemId })
	
	return true
end

function PlayerDataService:RemoveItem(player: Player, itemId: string): boolean
	local profile = Profiles[player.UserId]
	if not profile or not profile:IsActive() then return false end
	
	-- Check if exists (O(1))
	if not profile.Data.OwnedItems[itemId] then return false end
	
	-- Remove item (O(1))
	profile.Data.OwnedItems[itemId] = nil
	analytics.totalWrites += 1
	
	-- Unequip if equipped
	for slot, equipped in pairs(profile.Data.EquippedItems) do
		if equipped == itemId then
			profile.Data.EquippedItems[slot] = nil
		end
	end
	
	EventBus:Emit(Events.PLAYER_ITEM_REMOVED, player, { itemId = itemId })
	
	return true
end

function PlayerDataService:GetOwnedItems(player: Player): {string}
	local ownedItems = self:Get(player, "OwnedItems") :: {[string]: boolean}?
	if not ownedItems then return {} end
	
	local itemList: {string} = {}
	for itemId, _ in pairs(ownedItems) do
		table.insert(itemList, itemId)
	end
	
	return itemList
end

function PlayerDataService:GetItemCount(player: Player): number
	local ownedItems = self:Get(player, "OwnedItems") :: {[string]: boolean}?
	if not ownedItems then return 0 end
	
	local count = 0
	for _ in pairs(ownedItems) do
		count += 1
	end
	
	return count
end

function PlayerDataService:GetAnalytics(): {[string]: any}
	local activeProfiles = 0
	for _ in pairs(Profiles) do activeProfiles += 1 end
	return {
		totalLoads = analytics.totalLoads,
		totalReleases = analytics.totalReleases,
		loadFailures = analytics.loadFailures,
		totalReads = analytics.totalReads,
		totalWrites = analytics.totalWrites,
		blockedWrites = analytics.blockedWrites,
		migrations = analytics.migrations,
		activeProfiles = activeProfiles,
		uptime = os.clock() - analytics.startTime,
		profileServiceAvailable = ProfileService ~= nil,
	}
end

return PlayerDataService
