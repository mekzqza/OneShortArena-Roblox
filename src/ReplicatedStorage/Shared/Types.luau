--!strict

--[[
╔════════════════════════════════════════════════════════════════╗
║              CORE TYPE DEFINITIONS - PRODUCTION GRADE          ║
╠════════════════════════════════════════════════════════════════╣
║ Purpose: Centralized type definitions for type safety         ║
║ Usage: local Types = require(ReplicatedStorage.Shared.Types)  ║
╚════════════════════════════════════════════════════════════════╝
]]

local Types = {}




-- ═══════════════════════════════════════════════════════════════
-- NETWORK TYPES
-- ═══════════════════════════════════════════════════════════════





-- ═══════════════════════════════════════════════════════════════
-- GAME TYPES
-- ═══════════════════════════════════════════════════════════════

export type GameState = {
	status: "Waiting" | "Starting" | "Playing" | "Ending" | "Ended",
	roundNumber: number,
	timeRemaining: number,
	players: {Player},
	winner: Player?,
}

export type MatchResult = {
	winner: Player?,
	duration: number,
	finalScores: {[number]: number}, -- userId -> score
	statistics: MatchStatistics,
}

export type MatchStatistics = {
	totalDamageDealt: number,
	totalDamageTaken: number,
	killCount: number,
	deathCount: number,
	assistCount: number,
}

-- ═══════════════════════════════════════════════════════════════
-- COMBAT TYPES
-- ═══════════════════════════════════════════════════════════════

export type AttackData = {
	attacker: Player,
	target: Player?,
	damage: number,
	attackType: "Normal" | "Charged" | "Dash" | "Special",
	position: Vector3,
	direction: Vector3,
	timestamp: number,
}

export type DefendData = {
	defender: Player,
	defendType: "Block" | "Parry" | "Dodge",
	timestamp: number,
}

export type SkillData = {
	caster: Player,
	skillId: string,
	skillName: string,
	cooldown: number,
	manaCost: number,
	targetPosition: Vector3?,
	timestamp: number,
}

-- ═══════════════════════════════════════════════════════════════
-- ABILITY TYPES
-- ═══════════════════════════════════════════════════════════════

export type Ability = {
	id: string,
	name: string,
	description: string,
	cooldown: number,
	manaCost: number,
	damage: number?,
	range: number,
	areaOfEffect: number?,
	duration: number?,
	effects: {AbilityEffect},
}

export type AbilityEffect = {
	type: "Damage" | "Heal" | "Buff" | "Debuff" | "Stun" | "Slow",
	value: number,
	duration: number?,
}

-- ═══════════════════════════════════════════════════════════════
-- COOLDOWN TYPES
-- ═══════════════════════════════════════════════════════════════

export type CooldownData = {
	action: string,
	startTime: number,
	duration: number,
	remaining: number,
}

-- ═══════════════════════════════════════════════════════════════
-- UI TYPES
-- ═══════════════════════════════════════════════════════════════

export type Notification = {
	message: string,
	duration: number,
	type: "Info" | "Success" | "Warning" | "Error",
	timestamp: number,
}

export type ScoreUpdate = {
	playerId: number,
	score: number,
	delta: number,
}

export type HealthUpdate = {
	current: number,
	max: number,
	percentage: number,
}

-- ═══════════════════════════════════════════════════════════════
-- INPUT TYPES
-- ═══════════════════════════════════════════════════════════════

export type InputAction = {
	actionName: string,
	inputType: "Tap" | "Hold" | "DoubleTap" | "Release",
	timestamp: number,
}

export type InputState = {
	enabled: boolean,
	holding: {[string]: boolean},
	bufferSize: number,
	buffer: {{action: string, time: number}},
}

-- ═══════════════════════════════════════════════════════════════
-- ANALYTICS TYPES
-- ═══════════════════════════════════════════════════════════════

export type AnalyticsData = {
	totalEvents: number,
	eventCounts: {[string]: number},
	playerEventCounts: {[number]: {[string]: number}},
	errors: {{timestamp: number, player: string, error: string}},
	uptime: number,
	eventsPerSecond: number,
}

-- ═══════════════════════════════════════════════════════════════
-- TEST/DEMO TYPES
-- ═══════════════════════════════════════════════════════════════

export type TestPayload = {
	dataString: string,
	dataNumber: number,
	dataArray: {
		data: {
			[string]: number,
		}
	},
}

export type TestResponse = {
	success: boolean,
	receivedData: any,
	serverTime: number,
	message: string?,
}

-- ═══════════════════════════════════════════════════════════════
-- CONTROLLER/SERVICE TYPES
-- ═══════════════════════════════════════════════════════════════

export type Controller = {
	Init: (self: Controller) -> (),
	Start: (self: Controller) -> (),
	[string]: any,
}

export type Service = {
	Init: (self: Service) -> (),
	Start: (self: Service) -> (),
	[string]: any,
}

-- ═══════════════════════════════════════════════════════════════
-- UTILITY TYPES
-- ═══════════════════════════════════════════════════════════════

export type Vector3Like = {
	X: number,
	Y: number,
	Z: number,
}

export type Color3Like = {
	R: number,
	G: number,
	B: number,
}

export type Callback = (...any) -> ()
export type ValidatorFunction = (Player, {any}) -> (boolean, string?)
export type EventConnection = RBXScriptConnection

-- ═══════════════════════════════════════════════════════════════
-- EXPORTS
-- ═══════════════════════════════════════════════════════════════


Types.GameState = {} :: GameState
Types.AttackData = {} :: AttackData
Types.Ability = {} :: Ability


return Types

--[[
	 ตรวจสอบ type ก่อนใช้
function handleData(data: any)
    if type(data) == "table" and data.userId then
        local playerData = data :: Types.PlayerData
        print(playerData.name)
    end
end
]]--