--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    factory_ui_keys.lua
--  brief:   Hotkeys for factory management
--  credits: very_bad_soldier for factoryqmanager implementation
--           lolsteamroller for initial clear_factory_queue implementation
--  actions:
--    buildfirst <unit1> <unit2> ..: attempts to build unit1 at current cursor, if can't, attempt unit2 and so on
--    enqueueunit <name> <n>: enqueues <n> units of name <name>
--      n: default 1
--    dequeueunit <name> <n>: dequeues <n> units of name <name>
--      n: if empty all units of that name are dequeued
--      name: if empty the whole queue is cleared
--    togglerepeat <on|off>: toggles repeat for select units
--      on|off: if empty, toggle between states
--    altenqueueunit <name> <n>: same as enqueueunit, but as a 'oneoff' enqueuing
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
    return {
      name      = "Factory Ui Keys",
      desc      = "Adds keybindings for Factory Management",
      author    = "badosu,lolsteamroller",
      date      = "Jun 13, 2021",
      license   = "GNU GPL, v2 or later",
      layer     = 1,     --  after the normal widgets
      enabled   = true  --  loaded by default?
    }
end

local GetMouseState          = Spring.GetMouseState
local TraceScreenRay         = Spring.TraceScreenRay
local SetActiveCommand       = Spring.SetActiveCommand
local TestBuildOrder         = Spring.TestBuildOrder
local GetSelectedUnits       = Spring.GetSelectedUnits
local GetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local GetUnitDefID           = Spring.GetUnitDefID
local GetUnitStates          = Spring.GetUnitStates
local GiveOrderToUnit        = Spring.GiveOrderToUnit
local GetRealBuildQueue      = Spring.GetRealBuildQueue
local GetActiveCommand       = Spring.GetActiveCommand

function widget:Initialize()
  widgetHandler:AddAction("buildfirst", HandleBuildFirst, nil, "p")
  widgetHandler:AddAction("dequeueunit", HandleDequeueUnit, nil, "t")
  widgetHandler:AddAction("enqueueunit", HandleEnqueueUnit, nil, "t")
  widgetHandler:AddAction("altenqueueunit", HandleAltEnqueueUnit, nil, "t")
  widgetHandler:AddAction("togglerepeat", HandleToggleRepeat, nil, "t")
end

local udefTab = UnitDefs
local unameTab = {}

local cmdidTab = {}
for _, cmd in ipairs(Spring.GetActiveCmdDescs()) do
  cmdidTab[cmd.action] = cmd.id
end

local isFactory = {}
for udid, ud in pairs(udefTab) do
  unameTab[ud.name] = udid

  if ud.isFactory then
    isFactory[udid] = true
  end
end

function HandleBuildFirst(_, _, args)
  local _, _, _, currentUnitName = GetActiveCommand()

  local mx, my = GetMouseState()
  local _, coords = TraceScreenRay(mx, my, true, true)

  if not coords then
    return false
  end

  for _, arg in ipairs(args) do
    if arg == "//" then
      return false
    end

    if arg ~= currentUnitName then
      local unitDefID = unameTab[arg]

      if unitDefID then
        if TestBuildOrder(unitDefID, coords[1], coords[2], coords[3], 1) ~= 0 then
          if SetActiveCommand('buildunit_'..arg) then
            return true
          end
        end
      end
    end
  end

  return false
end

function HandleToggleRepeat(_, _, args)
  local setting = args[1]

  local globalOnOff
  if setting == "on" then
    globalOnOff = { 1 }
  elseif setting == "off" then
    globalOnOff = { 0 }
  end

  local udTable = GetSelectedUnitsSorted()
  udTable.n = nil
  for _, uTable in pairs(udTable) do
    for _, uid in ipairs(uTable) do
      local onoff = globalOnOff

      if onoff == nil then
        onoff = { 1 }

        if select(4, GetUnitStates(uid, false, true)) then
          onoff = { 0 }
        end
      end

      GiveOrderToUnit(uid, CMD.REPEAT, onoff, 0)
    end
  end
end

-- dequeueunit unitname n -> dequeues unit by name, if n is not passed dequeue all
function HandleDequeueUnit(_, _, args)
  local unitName = args[1]

  if unitName == nil then
    ClearFactoryProduction()
    return
  end

  local count = tonumber(args[2])
  local unitDefId = unameTab[unitName]

  if unitDefId and SelectionCanBuild(unitDefId) then
    ClearFactoryProduction(unitDefId, count)
  end
end

-- enqueue unitname n -> enqueues unit by name, if n is not passed n=1
function HandleEnqueueUnit(_, _, args)
  local unitName = args[1]
  local count = tonumber(args[2]) or 1
  local unitDefId = unameTab[unitName]

  if unitDefId and SelectionCanBuild(unitDefId) then
    AddToFactoryProduction(unitDefId, count)
    return true
  end

  return false
end

function HandleAltEnqueueUnit(_, _, args)
  local unitName = args[1]
  local count = tonumber(args[2]) or 1
  local unitDefId = unameTab[unitName]

  if unitDefId and SelectionCanBuild(unitDefId) then
    AddToFactoryProduction(unitDefId, count, { "left", "alt" })
  end
end

function AddToFactoryProduction(unitDefId, unitCount, operation)
  operation = operation or { "left" }

  local udTable = GetSelectedUnitsSorted()
  udTable.n = nil
  for udidFac, uTable in pairs(udTable) do
    if isFactory[udidFac] then
      uTable.n = nil
      for _, uid in ipairs(uTable) do
        GiveBuildOrders(uid, unitDefId, unitCount, operation)
      end
    end
  end
end

function ClearFactoryProduction(unitDefId, unitCount)
  local udTable = GetSelectedUnitsSorted()
  udTable.n = nil
  for udidFac, uTable in pairs(udTable) do
    if isFactory[udidFac] then
      uTable.n = nil
      for _, uid in ipairs(uTable) do
        -- return early if unit and count defined, no need to iterate build queue
        if unitDefId and unitCount then
          GiveBuildOrders(uid, unitDefId, unitCount, { "right" })
          return
        end

        local queue = GetRealBuildQueue(uid)
        if queue ~= nil then
          for _, buildPair in ipairs(queue) do
            local udid, count = next(buildPair, nil)

            if unitDefId == nil or unitDefId == udid then
              count = unitCount or count

              GiveBuildOrders(uid, udid, count, { "right" })

              if unitDefId then
                return
              end
            end
          end
        end
      end
    end
  end
end

function GiveBuildOrders(unitID, buildDefID, count, operation)
  operation = operation or { "left" }

  local opts = {}

  while (count > 0) do
    if count >= 100 then
      opts = { "ctrl", "shift" }
      count = count - 100
    elseif count >= 20 then
      opts = { "ctrl" }
      count = count - 20
    elseif count >= 5 then
      opts = { "shift" }
      count = count - 5
    else
      count = count - 1
    end

    for _, v in ipairs(operation) do 
      table.insert(opts, v)
    end

    GiveOrderToUnit(unitID, -buildDefID, {}, opts)
  end
end

function SelectionCanBuild(unitDefId)
  local selUnits = GetSelectedUnits()

  for _, unit in ipairs(selUnits) do
    local factudid = GetUnitDefID(unit)

    if isFactory[factudid] then
      if unitDefId == nil then
        return true
      end

      for _, buildoption in ipairs(udefTab[factudid].buildOptions) do 
        if buildoption == unitDefId then
          return true
        end
      end
    end
  end

  return false
end
