--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║           DATA MAPPER - EXPLICIT FIELD MAPPING                 ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Transform data between Roblox and PocketBase formats ║
║ Features:                                                      ║
║  ✅ Explicit field mapping - No magic/auto conversion          ║
║  ✅ Type coercion - Convert types safely                       ║
║  ✅ Validation - Ensure data integrity                         ║
║  ✅ Default values - Handle missing fields                     ║
║  ✅ Versioning - Support schema migrations                     ║
╚════════════════════════════════════════════════════════════════╝

ARCHITECTURE:
  Roblox (ProfileService)     DataMapper      PocketBase (VPS)
  ════════════════════════    ══════════      ═════════════════
  
  PlayerData {                 toRemote()     player_stats {
    Coins: number        ──────────────────►    coins: number
    Level: number        ──────────────────►    level: number
    Kills: number        ──────────────────►    kills: number
    ...                                         ...
  }                                           }
                               
  PlayerData {                 fromRemote()   player_stats {
    Coins: number        ◄──────────────────    coins: number
    Level: number        ◄──────────────────    level: number
    Kills: number        ◄──────────────────    kills: number
    ...                                         ...
  }
]]

local DataMapper = {}

-- ═══════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

export type FieldMapping = {
	robloxKey: string,
	remoteKey: string,
	robloxType: string,
	remoteType: string,
	default: any?,
	transform: ((value: any) -> any)?,
	reverseTransform: ((value: any) -> any)?,
	required: boolean?,
}

export type MappingSchema = {
	version: number,
	name: string,
	fields: {FieldMapping},
}

-- ═══════════════════════════════════════════════════════════════
-- MAPPING SCHEMAS
-- ═══════════════════════════════════════════════════════════════

-- ✅ PlayerData → player_stats mapping
local PLAYER_DATA_SCHEMA: MappingSchema = {
	version = 1,
	name = "PlayerData",
	fields = {
		-- Currency
		{
			robloxKey = "Coins",
			remoteKey = "coins",
			robloxType = "number",
			remoteType = "number",
			default = 0,
			required = true,
		},
		{
			robloxKey = "Gems",
			remoteKey = "gems",
			robloxType = "number",
			remoteType = "number",
			default = 0,
			required = true,
		},
		
		-- Stats
		{
			robloxKey = "Level",
			remoteKey = "level",
			robloxType = "number",
			remoteType = "number",
			default = 1,
			required = true,
		},
		{
			robloxKey = "Experience",
			remoteKey = "experience",
			robloxType = "number",
			remoteType = "number",
			default = 0,
			required = true,
		},
		
		-- Combat stats
		{
			robloxKey = "Kills",
			remoteKey = "kills",
			robloxType = "number",
			remoteType = "number",
			default = 0,
			required = true,
		},
		{
			robloxKey = "Deaths",
			remoteKey = "deaths",
			robloxType = "number",
			remoteType = "number",
			default = 0,
			required = true,
		},
		{
			robloxKey = "Wins",
			remoteKey = "wins",
			robloxType = "number",
			remoteType = "number",
			default = 0,
			required = true,
		},
		{
			robloxKey = "Losses",
			remoteKey = "losses",
			robloxType = "number",
			remoteType = "number",
			default = 0,
			required = true,
		},
		
		-- Metadata
		{
			robloxKey = "_version",
			remoteKey = "data_version",
			robloxType = "number",
			remoteType = "number",
			default = 1,
			required = false,
		},
	},
}

-- Store schemas
local schemas: {[string]: MappingSchema} = {
	PlayerData = PLAYER_DATA_SCHEMA,
}

-- ═══════════════════════════════════════════════════════════════
-- PRIVATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function coerceType(value: any, targetType: string): any
	local sourceType = type(value)
	
	if sourceType == targetType then
		return value
	end
	
	-- Number conversions
	if targetType == "number" then
		if sourceType == "string" then
			return tonumber(value) or 0
		elseif sourceType == "boolean" then
			return value and 1 or 0
		end
		return 0
	end
	
	-- String conversions
	if targetType == "string" then
		return tostring(value)
	end
	
	-- Boolean conversions
	if targetType == "boolean" then
		if sourceType == "number" then
			return value ~= 0
		elseif sourceType == "string" then
			return value == "true" or value == "1"
		end
		return false
	end
	
	return value
end

local function validateField(value: any, mapping: FieldMapping): (boolean, string?)
	if value == nil then
		if mapping.required then
			return false, `Required field '{mapping.robloxKey}' is nil`
		end
		return true
	end
	
	local expectedType = mapping.robloxType
	local actualType = type(value)
	
	if actualType ~= expectedType then
		return false, `Field '{mapping.robloxKey}' expected {expectedType}, got {actualType}`
	end
	
	return true
end

-- ✅ NEW: Helper to convert dictionary to array for PocketBase
local function dictToArray(dict: {[string]: boolean}): {string}
	local arr: {string} = {}
	for key, value in pairs(dict) do
		if value == true then
			table.insert(arr, key)
		end
	end
	return arr
end

-- ✅ NEW: Helper to convert array to dictionary for Roblox
local function arrayToDict(arr: {string}): {[string]: boolean}
	local dict: {[string]: boolean} = {}
	for _, key in ipairs(arr) do
		dict[key] = true
	end
	return dict
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC METHODS (UPDATED)
-- ═══════════════════════════════════════════════════════════════

--[[
    Convert Roblox data to remote format (for PocketBase)
    @param schemaName string - Schema name (e.g., "PlayerData")
    @param robloxData table - Data from ProfileService
    @param userId number - Player userId for roblox_id field
    @return table - Data formatted for PocketBase
]]
function DataMapper.ToRemote(schemaName: string, robloxData: {[string]: any}, userId: number): {[string]: any}
	local schema = schemas[schemaName]
	if not schema then
		warn(`[DataMapper] ❌ Unknown schema: {schemaName}`)
		return {}
	end
	
	local remoteData: {[string]: any} = {
		roblox_id = tostring(userId),
		last_sync = os.time(),
	}
	
	for _, mapping in ipairs(schema.fields) do
		local value = robloxData[mapping.robloxKey]
		
		-- Use default if nil
		if value == nil then
			value = mapping.default
		end
		
		-- ✅ NEW: Convert dictionary to array for OwnedItems
		if mapping.robloxKey == "OwnedItems" and type(value) == "table" then
			value = dictToArray(value)
		end
		
		-- Apply transform if exists
		if mapping.transform and value ~= nil then
			value = mapping.transform(value)
		end
		
		-- Coerce type
		if value ~= nil then
			value = coerceType(value, mapping.remoteType)
		end
		
		remoteData[mapping.remoteKey] = value
	end
	
	return remoteData
end

--[[
    Convert remote data to Roblox format (from PocketBase)
    @param schemaName string - Schema name (e.g., "PlayerData")
    @param remoteData table - Data from PocketBase
    @return table - Data formatted for ProfileService
]]
function DataMapper.FromRemote(schemaName: string, remoteData: {[string]: any}): {[string]: any}
	local schema = schemas[schemaName]
	if not schema then
		warn(`[DataMapper] ❌ Unknown schema: {schemaName}`)
		return {}
	end
	
	local robloxData: {[string]: any} = {}
	
	for _, mapping in ipairs(schema.fields) do
		local value = remoteData[mapping.remoteKey]
		
		-- Use default if nil
		if value == nil then
			value = mapping.default
		end
		
		-- ✅ NEW: Convert array to dictionary for OwnedItems
		if mapping.robloxKey == "OwnedItems" and type(value) == "table" then
			value = arrayToDict(value)
		end
		
		-- Apply reverse transform if exists
		if mapping.reverseTransform and value ~= nil then
			value = mapping.reverseTransform(value)
		end
		
		-- Coerce type
		if value ~= nil then
			value = coerceType(value, mapping.robloxType)
		end
		
		robloxData[mapping.robloxKey] = value
	end
	
	return robloxData
end

--[[
    Validate Roblox data against schema
    @param schemaName string - Schema name
    @param robloxData table - Data to validate
    @return (boolean, {string}?) - Success and list of errors
]]
function DataMapper.Validate(schemaName: string, robloxData: {[string]: any}): (boolean, {string}?)
	local schema = schemas[schemaName]
	if not schema then
		return false, {`Unknown schema: {schemaName}`}
	end
	
	local errors: {string} = {}
	
	for _, mapping in ipairs(schema.fields) do
		local value = robloxData[mapping.robloxKey]
		local valid, err = validateField(value, mapping)
		
		if not valid and err then
			table.insert(errors, err)
		end
	end
	
	if #errors > 0 then
		return false, errors
	end
	
	return true
end

--[[
    Get schema by name
    @param schemaName string - Schema name
    @return MappingSchema?
]]
function DataMapper.GetSchema(schemaName: string): MappingSchema?
	return schemas[schemaName]
end

--[[
    Register a custom schema
    @param schema MappingSchema - Schema definition
]]
function DataMapper.RegisterSchema(schema: MappingSchema)
	schemas[schema.name] = schema
	print(`[DataMapper] ✅ Registered schema: {schema.name} (v{schema.version})`)
end

--[[
    Print all schemas
]]
function DataMapper.PrintSchemas()
	print("╔════════════════════════════════════════════════════════════════╗")
	print("║              DATA MAPPER SCHEMAS                               ║")
	print("╠════════════════════════════════════════════════════════════════╣")
	
	for name, schema in pairs(schemas) do
		print(`║ 📋 {name} (v{schema.version}) - {#schema.fields} fields`)
	end
	
	print("╚════════════════════════════════════════════════════════════════╝")
end

return DataMapper
