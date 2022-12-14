function widget:GetInfo()
	return {
		name      = "Mobile Waypoint",
		desc      = "Allows mobile builders to set a rally point for built units",
		author    = "badosu",
		date      = "Nov 23 2022",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = true
	}
end

local CMD_MOVE = CMD.MOVE
local CMD_RECLAIM = CMD.RECLAIM
local CMD_FIGHT = CMD.FIGHT
local CMD_ATTACK = CMD.ATTACK
local CMD_PATROL = CMD.PATROL
local CMD_REPEAT = CMD.REPEAT
local CMD_LOAD_UNITS = CMD.LOAD_UNITS
local CMD_LOAD_ONTO = CMD.LOAD_ONTO
local CMD_GUARD = CMD.GUARD
local CMD_AREA_ATTACK = CMD.AREA_ATTACK

local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetUnitDefID = Spring.GetUnitDefID

local waypointCommandsList = {
	CMD_MOVE,
	CMD_RECLAIM,
	CMD_FIGHT,
	CMD_ATTACK,
	CMD_PATROL,
	CMD_REPEAT,
	CMD_LOAD_UNITS,
	CMD_LOAD_ONTO,
	CMD_GUARD,
	CMD_AREA_ATTACK
}

local isWaypointCommand = {}
for _, cmd in ipairs(waypointCommandsList) do
	isWaypointCommand[cmd] = true
end

local isMobileBuilder = {}
for uDefId, uDef in pairs(UnitDefs) do
	if uDef.isMobileBuilder and uDef.buildOptions and #uDef.buildOptions > 0 then
		isMobileBuilder[uDefId] = true
	end
end

local waypoints = {}
local gameStarted = false
local mobileWaypoint = false

local function maybeRemoveSelf()
	if Spring.GetSpectatingState() and (Spring.GetGameFrame() > 0 or gameStarted) then
		widgetHandler:RemoveWidget()
	end
end

local function setMobileWaypoint()
	mobileWaypoint = true
end

local function unsetMobileWaypoint()
	mobileWaypoint = false
end

function widget:GameStart()
	gameStarted = true
end

function widget:PlayerChanged(_)
	maybeRemoveSelf()
end

function widget:Initialize()
	maybeRemoveSelf()

	widgetHandler:AddAction("mobile_waypoint_modifier", unsetMobileWaypoint, nil, "r")
	widgetHandler:AddAction("mobile_waypoint_modifier", setMobileWaypoint, nil, "p")
end

local function issueWaypointCommand(unitID, cmdID, cmdParams, cmdOptions)
	local unitDefID = spGetUnitDefID(unitID)

	if not isMobileBuilder[unitDefID] then return end
	if not cmdOptions["shift"] then waypoints[unitID] = {} end

	table.insert(waypoints[unitID], { cmdID, cmdParams, cmdOptions })

	return true
end


function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
	if not mobileWaypoint then return false end
	if not isWaypointCommand[cmdID] then return false end

	local units = spGetSelectedUnits()
	local anyIssued = false
	for i=1,#units do
		if issueWaypointCommand(units[i], cmdID, cmdParams, cmdOptions) then
			anyIssued = true
		end
	end

	return anyIssued
end

function widget:UnitCreated(unitID, _, _, builderID)
	if not builderID then return end

	local builderDefID = Spring.GetUnitDefID(builderID)

	if not isMobileBuilder[builderDefID] then return end

	local waypoint = waypoints[builderID]

	if not waypoint then return end

	for _, wayCmd in ipairs(waypoint) do
		Spring.GiveOrderToUnit(unitID, wayCmd[1], wayCmd[2], wayCmd[3])
	end
end
