function widget:GetInfo()
	return {
	name      = "Key Tracker", --version 4.1
	desc      = "Displays pressed keys on the screen",
	author    = "MasterBel2",
	date      = "January 2022",
	license   = "GNU GPL, v2",
	layer     = 9999999999999999999, -- must be in front
	enabled   = true, --enabled by default
	}
end

------------------------------------------------------------------------------------------------------------
-- Includes
------------------------------------------------------------------------------------------------------------

local keyConfig = VFS.Include("luaui/configs/keyboard_layouts.lua")
local currentLayout = Spring.GetConfigString("KeyboardLayout", "qwerty")
local keyLayout = keyConfig.keyLayouts[currentLayout]
local hotkeyText

local MasterFramework
local requiredFrameworkVersion = 9

local Spring_GetPressedKeys = Spring.GetPressedKeys

------------------------------------------------------------------------------------------------------------
-- Keyboard
------------------------------------------------------------------------------------------------------------

local trackerKey
local keyboardKey

local keyCodes -- deferred to the end of the file, for readabilty
local keyNames
local keyCodeTypes

-- local label

local OperationKeys
local FKeys
local MainKeypad
local EscapeKey
local NavigationKeys
local ArrowKeys
local NumericKeypad

------------------------------------------------------------------------------------------------------------
-- Interface
------------------------------------------------------------------------------------------------------------

local mainKeypad
local escapeKeypad
local arrowKeypad
local navigationKeypad
local numericKeypad
local fKeypad
local operationKeypad

local keyboardRasterizer

local uiKeys = {}
local pressedUIKeys = {}

------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------

-- Creates a new table composed of the results of calling a function on each key-value pair of the original table.
local function map(table, transform)
    local newTable = {}

    for key, value in pairs(table) do
        local newKey, newValue = transform(key, value)
        newTable[newKey] = newValue
    end

    return newTable
end

-- Assembles a string by concatenating all string in an array, inserting the provided separator in between.
local function joinStrings(table, separator)
    if #table < 2 then if #table < 1 then return "" else return table[1] end end

    local string = ""

    for i=1, #table do
        string = string .. tostring(table[i])
        if i ~= #table then
            string = string .. separator
        end
    end
    
    return string
end

-- Returns an array containing all elements in the provided arrays, in the reverse order than provided.
local function joinArrays(arrayArray)
    local newArray = {}

    for _, array in pairs(arrayArray) do
        for _, value in pairs(array) do
            table.insert(newArray, value)
        end
    end

    return newArray
end

function string:remove(i) -- incomplete consideration of edge cases, but due to our use here we won't flesh that out yet. (Should this be public then?)
    if #self > i then 
        return self:sub(1, i - 1) .. self:sub(i + 1, #self)
    elseif #self == i then
        return self:sub(1, i - 1)
    else
        return self 
    end
end

------------------------------------------------------------------------------------------------------------
-- Interface Component Definitions
------------------------------------------------------------------------------------------------------------

-- An interface element that caches the size and position of its body, without impacting layout or drawing.
local function GeometryTarget(body)
    local geometryTarget = {}
    local width, height, cachedX, cachedY
    function geometryTarget:Layout(...)
        width, height = body:Layout(...)
        return width, height
    end
    function geometryTarget:Draw(x, y)
        cachedX = x
        cachedY = y
        body:Draw(x, y)
    end
    function geometryTarget:CachedPosition()
        return cachedX or 0, cachedY or 0
    end
    function geometryTarget:Size()
        if (not height) or (not width) then
            return self:Layout(0, 0) -- we need a value, so get one.
        end
        return width, height
    end

    return geometryTarget
end

-- Constrains the width of its body to the width of the provided GeometryTarget.
local function MatchWidth(target, body)
    local matchWidth = {}

    function matchWidth:Layout(availableWidth, availableHeight)
        local width, _ = target:Size(availableWidth, availableHeight)
        local _, height = body:Layout(width, availableHeight)
        return width, height
    end

    function matchWidth:Draw(...)
        body:Draw(...)
    end

    return matchWidth
end

-- A variable-width interface component that positions its content vertically, consuming all available vertical space.
local function VerticalFrame(body, yAnchor)
    local frame = {}

    local height
    local bodyHeight

    function frame:Layout(availableWidth, availableHeight)
        local bodyWidth, _bodyHeight = body:Layout(availableWidth, availableHeight)
        height = availableHeight
        bodyHeight = _bodyHeight
        return bodyWidth, availableHeight
    end
    function frame:Draw(x, y)
        body:Draw(x, y + (height - bodyHeight) * yAnchor)
    end

    return frame
end

-- An variable-height interface component that positions its content horizontally, consuming all horizontal space. 
local function HorizontalFrame(body, xAnchor)
    local frame = {}

    local width
    local bodyWidth

    function frame:Layout(availableWidth, availableHeight)
        local _bodyWidth, bodyHeight = body:Layout(availableWidth, availableHeight)
        width = availableWidth
        bodyWidth = _bodyWidth
        return availableWidth, bodyHeight
    end
    function frame:Draw(x, y)
        body:Draw(x + (width - bodyWidth) * xAnchor, y)
    end

    return frame
end

-- Constrains the height of its body to the height of the provided GeometryTarget.
local function MatchHeight(target, body)
    local matchHeight = {}

    function matchHeight:Layout(availableWidth, availableHeight)
        local _, height = target:Size(availableWidth, availableHeight)
        local width, _ = body:Layout(availableWidth, height)
        return width, height
    end

    function matchHeight:Draw(...)
        body:Draw(...)
    end

    return matchHeight
end

------------------------------------------------------------------------------------------------------------
-- Additional Keyboard Components
------------------------------------------------------------------------------------------------------------

local keyCornerRadius

-- Draws a single keyboard key into a drawable interface component
local function UIKey(key, baseKeyWidth, rowHeight, keySpacing)
    local backgroundColor = MasterFramework:Color(0, 0, 0, 0.66)
    local textColor = MasterFramework:Color(1, 1, 1, 1)

    local keyWidth = MasterFramework:Dimension(key.width * baseKeyWidth + (key.width - 1) * keySpacing)
    local keyHeight = MasterFramework:Dimension(rowHeight)

    local uiKey = MasterFramework:MouseOverResponder(
        MasterFramework:StackInPlace({
            MasterFramework:Rect(keyWidth, keyHeight, keyCornerRadius, { backgroundColor }),
            MasterFramework:Text(key.name, textColor, nil, nil, MasterFramework:Font("Poppins-Regular.otf", 14, 0.2, 1.3))
        }, 0.5, 0.5),
        function() return true end,
        function()
            backgroundColor.r = 1
            local text = 'Pressed keyset = ' .. key.name .. '\n'
            text = text .. '\n'
            for _, kb in pairs(Spring.GetKeyBindings(key.name) or {}) do
              text = text .. kb.command .. ' ' .. kb.extra .. '\n'
            end

            text = text .. '\n'
            text = text .. 'Shift: \n'
            for _, kb in pairs(Spring.GetKeyBindings('Shift+'..key.name) or {}) do
              text = text .. kb.command .. ' ' .. kb.extra .. '\n'
            end

            text = text .. '\n'
            text = text .. 'Alt: \n'
            for _, kb in pairs(Spring.GetKeyBindings('Alt+'..key.name) or {}) do
              text = text .. kb.command .. ' ' .. kb.extra .. '\n'
            end

            text = text .. '\n'
            text = text .. 'Ctrl+Alt: \n'
            for _, kb in pairs(Spring.GetKeyBindings('Ctrl+Alt+'..key.name) or {}) do
              text = text .. kb.command .. ' ' .. kb.extra .. '\n'
            end

            text = text .. '\n'
            text = text .. 'Any: \n'
            for _, kb in pairs(Spring.GetKeyBindings('Any+'..key.name) or {}) do
              text = text .. kb.command .. ' ' .. kb.extra .. '\n'
            end
            hotkeyText:SetString(text)
            keyboardRasterizer.invalidated = true
        end,
        function()
            backgroundColor.r = 0
            keyboardRasterizer.invalidated = true
        end
    )

    uiKey._keytracker_keyCode = key.code

    local wasPressed = false
    function uiKey:SetPressed(isPressed)
        local textBrightness
        if isPressed then
            textBrightness = 0
        else
            textBrightness = 1
        end

        local backgroundBrightness = 1 - textBrightness
        backgroundColor.r = backgroundBrightness
        backgroundColor.g = backgroundBrightness
        backgroundColor.b = backgroundBrightness
        textColor.r = textBrightness
        textColor.g = textBrightness
        textColor.b = textBrightness

        local shouldUpdate = (wasPressed ~= isPressed)
        wasPressed = isPressed

        return shouldUpdate
    end

    uiKey:SetPressed(false)

    return uiKey
end

-- Converts a keypad layout (columns of rows of keys) into a drawable interface component.
local function KeyPad(keyColumns, keySpacing, baseKeyWidth, baseKeyHeight)
    local keyPad = { keys = {} }

    local scalableKeySpacing = MasterFramework:Dimension(keySpacing)

    local uiColumns = map(keyColumns, function(key, column)
        local uiColumn = MasterFramework:VerticalStack(
            map(column, function(key, row)
                local rowHeight = row.height * baseKeyHeight + (row.height - 1) * keySpacing
                local keys = map(row.keys, function(key, value)
                    local uiKey = UIKey(value, baseKeyWidth, rowHeight, keySpacing)
                    return key, uiKey
                end)

                keyPad.keys = joinArrays({ keyPad.keys, keys })

                local uiRow = MasterFramework:HorizontalStack(
                    keys,
                    scalableKeySpacing,
                    0.5
                )
                return key, uiRow
            end),
            scalableKeySpacing,
            0.5
        )

        return key, uiColumn
    end)

    local body = MasterFramework:MarginAroundRect(
        MasterFramework:HorizontalStack(
            uiColumns,
            scalableKeySpacing,
            0.5
        ),
        scalableKeySpacing,
        scalableKeySpacing,
        scalableKeySpacing,
        scalableKeySpacing,
        {},
        5,
        false
    )

    function keyPad:HighlightSelectedKeys()
    end
    
    function keyPad:Layout(...)
        return body:Layout(...)
    end
    function keyPad:Draw(...)
        return body:Draw(...)
    end

    return keyPad
end

------------------------------------------------------------------------------------------------------------
-- Widget Events (Update, Initialize, Shutdown)
------------------------------------------------------------------------------------------------------------

function widget:Initialize()
    MasterFramework = WG.MasterFramework[requiredFrameworkVersion]
    if not MasterFramework then
        Spring.Echo("[Key Tracker] Error: MasterFramework " .. requiredFrameworkVersion .. " not found! Removing self.")
        widgetHandler:RemoveWidget(self)
        return
    end

    -- Interface structure

    -- label = MasterFramework:Text("", nil, nil, nil, MasterFramework:Font("Poppins-Regular.otf", 28, 0.2, 1.3))

		local uiscale = 1.5
    local keypadSpacing = 10 * uiscale
    local hotkeySpacing = 10 * uiscale
    local keySpacing = 2 * uiscale
    local baseKeyHeight = 32 * uiscale
    local baseKeyWidth = 30 * uiscale

    keyCornerRadius = MasterFramework:Dimension(math.floor(5 * uiscale))

    mainKeypad = KeyPad(MainKeypad, keySpacing, baseKeyWidth, baseKeyHeight)
    escapeKeypad = KeyPad(EscapeKey, keySpacing, baseKeyWidth, baseKeyHeight)
    arrowKeypad = KeyPad(ArrowKeys, keySpacing, baseKeyWidth, baseKeyHeight)
    navigationKeypad = KeyPad(NavigationKeys, keySpacing, baseKeyWidth, baseKeyHeight)
    numericKeypad = KeyPad(NumericKeypad, keySpacing, baseKeyWidth, baseKeyHeight)
    fKeypad = KeyPad(FKeys, keySpacing, baseKeyWidth, baseKeyHeight)
    operationKeypad = KeyPad(OperationKeys, keySpacing, baseKeyWidth, baseKeyHeight)

    for _, value in ipairs(joinArrays(map({ mainKeypad, escapeKeypad, arrowKeypad, navigationKeypad, numericKeypad, fKeypad, operationKeypad }, function(key, value) return key, value.keys end))) do
        if value._keytracker_keyCode then
            uiKeys[value._keytracker_keyCode] = value
        end
    end

    local mainKeypadGeometryTarget = GeometryTarget(mainKeypad)
    local backgroundColor = MasterFramework:Color(0, 0, 0, 0.66)
    local textColor = MasterFramework:Color(1, 1, 1, 1)
    hotkeyText = MasterFramework:Text('', textColor, nil, nil, MasterFramework:Font("Poppins-Regular.otf", 14, 0.2, 1.3))
    local hotkeyPad = MasterFramework:MarginAroundRect(
        hotkeyText,
        MasterFramework:Dimension(keypadSpacing),
        MasterFramework:Dimension(keypadSpacing),
        MasterFramework:Dimension(keypadSpacing),
        MasterFramework:Dimension(keypadSpacing + 500),
        { backgroundColor },
        MasterFramework:Dimension(5),
        false
    )

    keyboardRasterizer = MasterFramework:Rasterizer(MasterFramework:FrameOfReference(
        0.5,
        0.25,
        MasterFramework:VerticalStack({
          MatchWidth(
              mainKeypadGeometryTarget,
              hotkeyPad
          ),
          MasterFramework:HorizontalStack({
                  MasterFramework:VerticalStack({
                          MatchWidth(
                              mainKeypadGeometryTarget,
                              MasterFramework:StackInPlace({
                                  HorizontalFrame(escapeKeypad, 0),
                                  HorizontalFrame(fKeypad, 1)
                              }, 0, 0)
                          ),
                          mainKeypadGeometryTarget
                      },
                      MasterFramework:Dimension(keypadSpacing),
                      0
                  ),
                  MasterFramework:VerticalStack({
                          operationKeypad,
                          MatchHeight(
                              mainKeypadGeometryTarget,
                              MasterFramework:StackInPlace({
                                  VerticalFrame(navigationKeypad, 1),
                                  VerticalFrame(arrowKeypad, 0)
                              }, 0, 0)
                          )
                      },
                      MasterFramework:Dimension(keypadSpacing),
                      0
                  ),
                  numericKeypad
              },
              MasterFramework:Dimension(keypadSpacing),
              0
          )
        },
        MasterFramework:Dimension(hotkeySpacing),
        0
      )
    ))

    keyboardKey = MasterFramework:InsertElement(
        MasterFramework:PrimaryFrame(keyboardRasterizer),
        "Key Tracker Keyboard"
    )

    -- trackerKey = MasterFramework:InsertElement(
    --     MasterFramework:PrimaryFrame(MasterFramework:FrameOfReference(
    --         0.9,
    --         0.9,
    --         label
    --     )), 
    --     "Key Tracker"
    -- )
end

function widget:Update()
    local shouldUpdateKeyboard = false
    local wasPressed = pressedUIKeys
    pressedUIKeys = {}

    local keys = {}

    local pressedKeys = Spring_GetPressedKeys()
    for codeOrName, isPressed in pairs(pressedKeys) do
        if isPressed then
            if type(codeOrName) == "number" then
                local symbol = Spring.GetKeySymbol(codeOrName)
                if symbol then
                    while #symbol > 4 and symbol:sub(3,3) == "0" do
                        symbol = symbol:remove(3)
                    end
                    local key = keyCodes[symbol]

                    if key and key.name then
                        table.insert(keys, key.name) 
                    end

                    pressedUIKeys[symbol] = uiKeys[symbol]
                end
            end
        end
    end

    for key, uiKey in pairs(pressedUIKeys) do
        if not wasPressed[key] then
            uiKey:SetPressed(true)
            keyboardRasterizer.invalidated = true 
        end
    end
    for key, uiKey in pairs(wasPressed) do
        if not pressedUIKeys[key] then
            uiKey:SetPressed(false)
            keyboardRasterizer.invalidated = true
        end
    end

    -- label:SetString(joinStrings(keys, " + "))
end

function widget:Shutdown() 
    -- MasterFramework:RemoveElement(trackerKey)
    MasterFramework:RemoveElement(keyboardKey)
end

------------------------------------------------------------------------------------------------------------
-- Keyboard Components
------------------------------------------------------------------------------------------------------------

-- Describes the height and contents of a row of keys on the keyboard
local function KeyRow(height, keys)
    return {
        height = height,
        keys = keys
    }
end

-- Describes the name, code, and width of a key on a keyboard.
local function Key(name, width)
    local code = keyNames[name]
    local key = {
        width = width or 1,
        code = code,
        name = code and keyCodes[code].displayName or name,
        type = code and keyCodes[code].type or keyCodeTypes.unknown
    }

    return key
end

-- Describes a column of rows on the keyboard
local function KeyColumn(keyRows)
    return keyRows
end

------------------------------------------------------------------------------------------------------------
-- Keycode and Keypad data
------------------------------------------------------------------------------------------------------------

-- End of file. Now we'll declare keycodes and keypads.
-- These are declared as local at the top of the file, and defined here.

keyCodeTypes = {
    unknown = 0,
    modifier = 1,
    operation = 2,
    character = 3
}

keyCodes = {
    ["0x00"] = {
        name = "Unknown",
        type = keyCodeTypes.unkown
    },
    ["backspace"] = { -- Special case because ??????
        name = "Backspace",
        displayName = "BckSpc",
        type = keyCodeTypes.operation
    },
    ["0x08"] = {
        name = "Backspace",
        type = keyCodeTypes.operation
    },
    ["0x09"] = {
        name = "Tab",
        type = keyCodeTypes.character
    },
    ["0x0D"] = {
        name = "Return",
        type = keyCodeTypes.character
    },
    ["0x1B"] = {
        name = "Escape",
        displayName = "Esc",
        type = keyCodeTypes.operation
    },
    ["0x20"] = {
        name = "Space",
        type = keyCodeTypes.character
    },
    ["0x21"] = {
        name = "!",
        type = keyCodeTypes.character
    },
    ["0x22"] = {
        name = "\"",
        type = keyCodeTypes.character
    },
    ["0x23"] = {
        name = "#",
        type = keyCodeTypes.character
    },
    ["0x24"] = {
        name = "$",
        type = keyCodeTypes.character
    },
    ["0x25"] = {
        name = "%",
        type = keyCodeTypes.character
    },
    ["0x26"] = {
        name = "&",
        type = keyCodeTypes.character
    },
    ["0x27"] = {
        name = "\'",
        type = keyCodeTypes.character
    },
    ["0x28"] = {
        name = "(",
        type = keyCodeTypes.character
    },
    ["0x29"] = {
        name = ")",
        type = keyCodeTypes.character
    },
    ["0x2A"] = {
        name = "*",
        type = keyCodeTypes.character
    },
    ["0x2B"] = {
        name = "+",
        type = keyCodeTypes.character
    },
    ["0x2C"] = {
        name = ",",
        type = keyCodeTypes.character
    },
    ["0x2D"] = {
        name = "-",
        type = keyCodeTypes.character
    },
    ["0x2E"] = {
        name = ".",
        type = keyCodeTypes.character
    },
    ["0x2F"] = {
        name = "/",
        type = keyCodeTypes.character
    },
    ["0x30"] = {
        name = "0",
        type = keyCodeTypes.character
    },
    ["0x31"] = {
        name = "1",
        type = keyCodeTypes.character
    },
    ["0x32"] = {
        name = "2",
        type = keyCodeTypes.character
    },
    ["0x33"] = {
        name = "3",
        type = keyCodeTypes.character
    },
    ["0x34"] = {
        name = "4",
        type = keyCodeTypes.character
    },
    ["0x35"] = {
        name = "5",
        type = keyCodeTypes.character
    },
    ["0x36"] = {
        name = "6",
        type = keyCodeTypes.character
    },
    ["0x37"] = {
        name = "7",
        type = keyCodeTypes.character
    },
    ["0x38"] = {
        name = "8",
        type = keyCodeTypes.character
    },
    ["0x39"] = {
        name = "9",
        type = keyCodeTypes.character
    },
    ["0x3A"] = {
        name = ":",
        type = keyCodeTypes.character
    },
    ["0x3B"] = {
        name = ";",
        type = keyCodeTypes.character
    },
    ["0x3C"] = {
        name = "<",
        type = keyCodeTypes.character
    },
    ["0x3D"] = {
        name = "=",
        type = keyCodeTypes.character
    },
    ["0x3E"] = {
        name = ">",
        type = keyCodeTypes.character
    },
    ["0x3F"] = {
        name = "?",
        type = keyCodeTypes.character
    },
    ["0x40"] = {
        name = "@",
        type = keyCodeTypes.character
    },
    ["0x5B"] = {
        name = "[",
        type = keyCodeTypes.character
    },
    ["0x5C"] = {
        name = "\\",
        type = keyCodeTypes.character
    },
    ["0x5D"] = {
        name = "]",
        type = keyCodeTypes.character
    },
    ["0x5E"] = {
        name = "^",
        type = keyCodeTypes.character
    },
    ["0x5F"] = {
        name = "_",
        type = keyCodeTypes.character
    },
    ["0x60"] = {
        name = "`",
        type = keyCodeTypes.character
    },
    ["0x61"] = {
        name = "A",
        type = keyCodeTypes.character
    },
    ["0x62"] = {
        name = "B",
        type = keyCodeTypes.character
    },
    ["0x63"] = {
        name = "C",
        type = keyCodeTypes.character
    },
    ["0x64"] = {
        name = "D",
        type = keyCodeTypes.character
    },
    ["0x65"] = {
        name = "E",
        type = keyCodeTypes.character
    },
    ["0x66"] = {
        name = "F",
        type = keyCodeTypes.character
    },
    ["0x67"] = {
        name = "G",
        type = keyCodeTypes.character
    },
    ["0x68"] = {
        name = "H",
        type = keyCodeTypes.character
    },
    ["0x69"] = {
        name = "I",
        type = keyCodeTypes.character
    },
    ["0x6A"] = {
        name = "J",
        type = keyCodeTypes.character
    },
    ["0x6B"] = {
        name = "K",
        type = keyCodeTypes.character
    },
    ["0x6C"] = {
        name = "L",
        type = keyCodeTypes.character
    },
    ["0x6D"] = {
        name = "M",
        type = keyCodeTypes.character
    },
    ["0x6E"] = {
        name = "N",
        type = keyCodeTypes.character
    },
    ["0x6F"] = {
        name = "O",
        type = keyCodeTypes.character
    },
    ["0x70"] = {
        name = "P",
        type = keyCodeTypes.character
    },
    ["0x71"] = {
        name = "Q",
        type = keyCodeTypes.character
    },
    ["0x72"] = {
        name = "R",
        type = keyCodeTypes.character
    },
    ["0x73"] = {
        name = "S",
        type = keyCodeTypes.character
    },
    ["0x74"] = {
        name = "T",
        type = keyCodeTypes.character
    },
    ["0x75"] = {
        name = "U",
        type = keyCodeTypes.character
    },
    ["0x76"] = {
        name = "V",
        type = keyCodeTypes.character
    },
    ["0x77"] = {
        name = "W",
        type = keyCodeTypes.character
    },
    ["0x78"] = {
        name = "X",
        type = keyCodeTypes.character
    },
    ["0x79"] = {
        name = "Y",
        type = keyCodeTypes.character
    },
    ["0x7A"] = {
        name = "Z",
        type = keyCodeTypes.character
    },
    ["0x7F"] = {
        name = "Delete",
        displayName = "Del",
        type = keyCodeTypes.operation
    },
    ["0x40000039"] = {
        name = "Capslock",
        displayName = "Caps",
        type = keyCodeTypes.operation
    },
    ["0x4000003A"] = {
        name = "F1",
        type = keyCodeTypes.operation
    },
    ["0x4000003B"] = {
        name = "F2",
        type = keyCodeTypes.operation
    },
    ["0x4000003C"] = {
        name = "F3",
        type = keyCodeTypes.operation
    },
    ["0x4000003D"] = {
        name = "F4",
        type = keyCodeTypes.operation
    },
    ["0x4000003E"] = {
        name = "F5",
        type = keyCodeTypes.operation
    },
    ["0x4000003F"] = {
        name = "F6",
        type = keyCodeTypes.operation
    },
    ["0x40000040"] = {
        name = "F7",
        type = keyCodeTypes.operation
    },
    ["0x40000041"] = {
        name = "F8",
        type = keyCodeTypes.operation
    },
    ["0x40000042"] = {
        name = "F9",
        type = keyCodeTypes.operation
    },
    ["0x40000043"] = {
        name = "F10",
        type = keyCodeTypes.operation
    },
    ["0x40000044"] = {
        name = "F11",
        type = keyCodeTypes.operation
    },
    ["0x40000045"] = {
        name = "F12",
        type = keyCodeTypes.operation
    },
    ["0x40000046"] = {
        name = "Print Screen",
        displayName = "Prt",
        type = keyCodeTypes.operation
    },
    ["0x40000047"] = {
        name = "Scroll Lock",
        displayName = "Scr",
        type = keyCodeTypes.operation
    },
    ["0x40000048"] = {
        name = "Pause",
        displayName = "Pse",
        type = keyCodeTypes.operation
    },
    ["0x40000049"] = {
        name = "Insert",
        displayName = "Ins",
        type = keyCodeTypes.operation
    },
    ["0x4000004A"] = {
        name = "Home",
        displayName = "Hm",
        type = keyCodeTypes.operation
    },
    ["0x4000004B"] = {
        name = "Page Up",
        displayName = "PUp",
        type = keyCodeTypes.operation
    },
    ["0x4000004D"] = {
        name = "End",
        type = keyCodeTypes.operation
    },
    ["0x4000004E"] = {
        name = "Page Down",
        displayName = "PDn",
        type = keyCodeTypes.operation
    },
    ["0x4000004F"] = {
        name = "Right",
        displayName = "Rt",
        type = keyCodeTypes.operation
    },
    ["0x40000050"] = {
        name = "Left",
        displayName = "Lf",
        type = keyCodeTypes.operation
    },
    ["0x40000051"] = {
        name = "Down",
        displayName = "Dn",
        type = keyCodeTypes.operation
    },
    ["0x40000052"] = {
        name = "Up",
        type = keyCodeTypes.operation
    },
    ["0x40000053"] = {
        name = "Clear / Num Lock",
        displayName = "NLk",
        type = keyCodeTypes.operation
    },
    ["0x40000054"] = {
        name = "/ (KP)",
        displayName = "/",
        type = keyCodeTypes.character
    },
    ["0x40000055"] = {
        name = "* (KP)",
        displayName = "*",
        type = keyCodeTypes.character
    },
    ["0x40000056"] = {
        name = "- (KP)",
        displayName = "-",
        type = keyCodeTypes.character
    },
    ["0x40000057"] = {
        name = "+ (KP)",
        displayName = "+",
        type = keyCodeTypes.character
    },
    ["0x40000058"] = {
        name = "Enter (KP)",
        displayName = "Ent",
        type = keyCodeTypes.operation
    },
    ["0x40000059"] = {
        name = "1 (KP)",
        displayName = "1",
        type = keyCodeTypes.character
    },
    ["0x4000005A"] = {
        name = "2 (KP)",
        displayName = "2",
        type = keyCodeTypes.character
    },
    ["0x4000005B"] = {
        name = "3 (KP)",
        displayName = "3",
        type = keyCodeTypes.character
    },
    ["0x4000005C"] = {
        name = "4 (KP)",
        displayName = "4",
        type = keyCodeTypes.character
    },
    ["0x4000005D"] = {
        name = "5 (KP)",
        displayName = "5",
        type = keyCodeTypes.character
    },
    ["0x4000005E"] = {
        name = "6 (KP)",
        displayName = "6",
        type = keyCodeTypes.character
    },
    ["0x4000005F"] = {
        name = "7 (KP)",
        displayName = "7",
        type = keyCodeTypes.character
    },
    ["0x40000060"] = {
        name = "8 (KP)",
        displayName = "8",
        type = keyCodeTypes.character
    },
    ["0x40000061"] = {
        name = "9 (KP)",
        displayName = "9",
        type = keyCodeTypes.character
    },
    ["0x40000062"] = {
        name = "0 (KP)",
        displayName = "0",
        type = keyCodeTypes.character
    },
    ["0x40000063"] = {
        name = ". (KP)",
        displayName = ".",
        type = keyCodeTypes.character
    },
    ["0x40000065"] = {
        name = "Application",
        type = keyCodeTypes.operation
    },
    ["0x40000066"] = {
        name = "Power",
        type = keyCodeTypes.operation
    },
    ["0x40000067"] = {
        name = "= (KP)",
        displayName = "=",
        type = keyCodeTypes.character
    },
    ["0x40000068"] = {
        name = "F13",
        type = keyCodeTypes.operation
    },
    ["0x40000069"] = {
        name = "F14",
        type = keyCodeTypes.operation
    },
    ["0x4000006A"] = {
        name = "F15",
        type = keyCodeTypes.operation
    },
    ["0x4000006B"] = {
        name = "F16",
        type = keyCodeTypes.operation
    },
    ["0x4000006C"] = {
        name = "F17",
        type = keyCodeTypes.operation
    },
    ["0x4000006D"] = {
        name = "F18",
        type = keyCodeTypes.operation
    },
    ["0x4000006E"] = {
        name = "F19",
        type = keyCodeTypes.operation
    },
    ["0x4000006F"] = {
        name = "F20",
        type = keyCodeTypes.operation
    },
    ["0x40000070"] = {
        name = "F21",
        type = keyCodeTypes.operation
    },
    ["0x40000071"] = {
        name = "F22",
        type = keyCodeTypes.operation
    },
    ["0x40000072"] = {
        name = "F23",
        type = keyCodeTypes.operation
    },
    ["0x40000073"] = {
        name = "F24",
        type = keyCodeTypes.operation
    },
    ["0x40000074"] = {
        name = "Execute",
        type = keyCodeTypes.operation
    },
    ["0x40000075"] = {
        name = "Help",
        type = keyCodeTypes.operation
    },
    ["0x40000076"] = {
        name = "Menu",
        displayName = "Mu",
        type = keyCodeTypes.operation
    },
    ["0x40000077"] = {
        name = "Select",
        type = keyCodeTypes.operation
    },
    ["0x40000078"] = {
        name = "Stop",
        type = keyCodeTypes.operation
    },
    ["0x40000079"] = {
        name = "Again",
        type = keyCodeTypes.operation
    },
    ["0x4000007A"] = {
        name = "Undo",
        type = keyCodeTypes.operation
    },
    ["0x4000007B"] = {
        name = "Cut",
        type = keyCodeTypes.operation
    },
    ["0x4000007C"] = {
        name = "Copy",
        type = keyCodeTypes.operation
    },
    ["0x4000007D"] = {
        name = "Paste",
        type = keyCodeTypes.operation
    },
    ["0x4000007E"] = {
        name = "Find",
        type = keyCodeTypes.operation
    },
    ["0x4000007F"] = {
        name = "Mute",
        type = keyCodeTypes.operation
    },
    ["0x40000080"] = {
        name = "Volume Up",
        type = keyCodeTypes.operation
    },
    ["0x40000081"] = {
        name = "Volume Down",
        type = keyCodeTypes.operation
    },
    ["0x40000085"] = {
        name = ", (KP)",
        type = keyCodeTypes.character
    },
    ["0x40000086"] = {
        name = "Equals As 400 (KP)",
        type = keyCodeTypes.character
    },
    ["0x40000099"] = {
        name = "Alt Erase",
        type = keyCodeTypes.operation
    },
    ["0x4000009A"] = {
        name = "SysReq",
        type = keyCodeTypes.operation
    },
    ["0x4000009B"] = {
        name = "Cancel",
        type = keyCodeTypes.operation
    },
    ["0x4000009C"] = {
        name = "Clear",
        type = keyCodeTypes.operation
    },
    ["0x4000009D"] = {
        name = "Prior",
        type = keyCodeTypes.operation
    },
    ["0x4000009E"] = {
        name = "Return2",
        type = keyCodeTypes.operation
    },
    ["0x4000009F"] = {
        name = "Separator",
        type = keyCodeTypes.operation
    },
    ["0x400000A0"] = {
        name = "Out",
        type = keyCodeTypes.operation
    },
    ["0x400000A1"] = {
        name = "Oper",
        type = keyCodeTypes.operation
    },
    ["0x400000A2"] = {
        name = "Clear Again",
        type = keyCodeTypes.operation
    },
    ["0x400000A3"] = {
        name = "CRSEL",
        type = keyCodeTypes.operation
    },
    ["0x400000A4"] = {
        name = "EXSEL",
        type = keyCodeTypes.operation
    },
    ["0x400000B0"] = {
        name = "00 (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000B1"] = {
        name = "000 (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000B2"] = {
        name = "Thousands Separator",
        type = keyCodeTypes.character
    },
    ["0x400000B3"] = {
        name = "Decimal Separator",
        type = keyCodeTypes.character
    },
    ["0x400000B4"] = {
        name = "Currency Unit",
        type = keyCodeTypes.character
    },
    ["0x400000B5"] = {
        name = "Currency Sub Unit",
        type = keyCodeTypes.character
    },
    ["0x400000B6"] = {
        name = "( (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000B7"] = {
        name = ") (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000B8"] = {
        name = "{ (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000B9"] = {
        name = "} (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000BA"] = {
        name = "Tab (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000BB"] = {
        name = "Backspace (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000BC"] = {
        name = "A (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000BD"] = {
        name = "B (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000BE"] = {
        name = "C (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000BF"] = {
        name = "D (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000C0"] = {
        name = "E (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000C1"] = {
        name = "F (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000C2"] = {
        name = "XOR (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000C3"] = {
        name = "Power (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000C4"] = {
        name = "% (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000C5"] = {
        name = "< (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000C6"] = {
        name = "> (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000C7"] = {
        name = "& (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000C8"] = {
        name = "&& (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000C9"] = {
        name = "| (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000CA"] = {
        name = "|| (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000CB"] = {
        name = ": (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000CC"] = {
        name = "# (KP)",
        displayName = "#",
        type = keyCodeTypes.character
    },
    ["0x400000CD"] = {
        name = "Space (KP)",
        displayName = "Space",
        type = keyCodeTypes.character
    },
    ["0x400000CE"] = {
        name = "@ (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000CF"] = {
        name = "! (KP)",
        type = keyCodeTypes.character
    },
    ["0x400000D0"] = {
        name = "Memstore (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000D1"] = {
        name = "Memrecall (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000D2"] = {
        name = "Memclear (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000D3"] = {
        name = "Memadd (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000D4"] = {
        name = "MEMSUBTRACT (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000D5"] = {
        name = "MEMMULTIPLY (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000D6"] = {
        name = "MEMDIVIDE (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000D7"] = {
        name = "Plus Minus (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000D8"] = {
        name = "Clear (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000D9"] = {
        name = "Clear Entry (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000DA"] = {
        name = "Binary (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000DB"] = {
        name = "Octal (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000DC"] = {
        name = "Decimal (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000DD"] = {
        name = "Hexadecimal (KP)",
        type = keyCodeTypes.operation
    },
    ["0x400000E0"] = {
        name = "Left Control",
        displayName = "Ctrl",
        type = keyCodeTypes.modifier
    },
    ["0x400000E1"] = {
        name = "Left Shift",
        displayName = "Shift",
        type = keyCodeTypes.modifier
    },
    ["0x400000E2"] = {
        name = "Left Alt",
        displayName = "Alt",
        type = keyCodeTypes.modifier
    },
    ["0x400000E3"] = {
        name = "Left GUI",
        displayName = "GUI",
        type = keyCodeTypes.modifier
    },
    ["0x400000E4"] = {
        name = "Right Control",
        displayName = "Ctrl",
        type = keyCodeTypes.modifier
    },
    ["0x400000E5"] = {
        name = "Right Shift",
        displayName = "Shift",
        type = keyCodeTypes.modifier
    },
    ["0x400000E6"] = {
        name = "Right Alt",
        displayName = "Alt",
        type = keyCodeTypes.modifier
    },
    ["0x400000E7"] = {
        name = "Right GUIhift",
        displayName = "GUI",
        type = keyCodeTypes.modifier
    },
    ["0x40000101"] = {
        name = "Mode",
        type = keyCodeTypes.operation
    },
    ["0x40000102"] = {
        name = "Audio Next",
        type = keyCodeTypes.operation
    },
    ["0x40000103"] = {
        name = "Audio Previous",
        type = keyCodeTypes.operation
    },
    ["0x40000104"] = {
        name = "Audio Stop",
        type = keyCodeTypes.operation
    },
    ["0x40000105"] = {
        name = "Audio Play",
        type = keyCodeTypes.operation
    },
    ["0x40000106"] = {
        name = "Audio Mute",
        type = keyCodeTypes.operation
    },
    ["0x40000107"] = {
        name = "Media Select",
        type = keyCodeTypes.operation
    },
    ["0x40000108"] = {
        name = "WWW",
        type = keyCodeTypes.character
    },
    ["0x40000109"] = {
        name = "Mail",
        type = keyCodeTypes.operation
    },
    ["0x4000010A"] = {
        name = "Calculator",
        type = keyCodeTypes.operation
    },
    ["0x4000010B"] = {
        name = "Computer",
        type = keyCodeTypes.operation
    },
    ["0x4000010C"] = {
        name = "Search (AC)",
        type = keyCodeTypes.operation
    },
    ["0x4000010D"] = {
        name = "Home (AC)",
        type = keyCodeTypes.operation
    },
    ["0x4000010E"] = {
        name = "Back (AC)",
        type = keyCodeTypes.operation
    },
    ["0x4000010F"] = {
        name = "Forward (AC)",
        type = keyCodeTypes.operation
    },
    ["0x40000110"] = {
        name = "Stop (AC)",
        type = keyCodeTypes.operation
    },
    ["0x40000111"] = {
        name = "Refresh (AC)",
        type = keyCodeTypes.operation
    },
    ["0x40000112"] = {
        name = "Bookmarks (AC)",
        type = keyCodeTypes.operation
    },
    ["0x40000113"] = {
        name = "Brightness Down",
        type = keyCodeTypes.operation
    },
    ["0x40000114"] = {
        name = "Brightness Up",
        type = keyCodeTypes.operation
    },
    ["0x40000115"] = {
        name = "Switch Display",
        type = keyCodeTypes.operation
    },
    ["0x40000116"] = {
        name = "KBDILLUM Toggle",
        type = keyCodeTypes.operation
    },
    ["0x40000117"] = {
        name = "KBDILLUM Down",
        type = keyCodeTypes.operation
    },
    ["0x40000118"] = {
        name = "KBDILLUM Up",
        type = keyCodeTypes.operation
    },
    ["0x40000119"] = {
        name = "Eject",
        type = keyCodeTypes.operation
    },
    ["0x4000011A"] = {
        name = "Sleep",
        type = keyCodeTypes.operation
    },
}
keyNames = {}
for code, key in pairs(keyCodes) do
    keyNames[key.name] = code
end

-- Now we declare the stuff built on keycodes

OperationKeys = {
    [1] = KeyColumn({
        [1] = KeyRow(1, { [1] = Key("Print Screen"), [2] = Key("Scroll Lock"), [3] = Key("Pause") })
    })
}

FKeys = {
    [1] = KeyColumn({
        [1] = KeyRow(1, { [1] = Key("F1"), [2] = Key("F2"), [3] = Key("F3"), [4] = Key("F4"), [5] = Key("F5"), [6] = Key("F6"), [7] = Key("F7"), [8] = Key("F8"), [9] = Key("F9"), [10] = Key("F10"), [11] = Key("F11"), [12] = Key("F12") }),
    })
}

local upperRow = {}
for c=1,10 do
  table.insert(upperRow, Key(keyLayout[3][c]))
end

local midRow = {}
for c=1,9 do
  table.insert(midRow, Key(keyLayout[2][c]))
end

local bottomRow = {}
for c=1,7 do
  table.insert(bottomRow, Key(keyLayout[1][c]))
end

MainKeypad = {
    [1] = KeyColumn({
        [1] = KeyRow(1, { [1] = Key("`"), [2] = Key("1"), [3] = Key("2"), [4] = Key("3"), [5] = Key("4"), [6] = Key("5"), [7] = Key("6"), [8] = Key("7"), [9] = Key("8"), [10] = Key("9"), [11] = Key("0"), [12] = Key("-"), [13] = Key("="), [14] = Key("Backspace", 2) }),
        [2] = KeyRow(1, joinArrays({ { Key("Tab", 1.5) }, upperRow, { Key("["), Key("]"), Key("\\", 1.5) } })),
        [3] = KeyRow(1, joinArrays({ { Key("Capslock", 2) }, midRow, { Key(";"), Key("'"), Key("Return", 2) } })),
        [4] = KeyRow(1, joinArrays({ { Key("Left Shift", 2.5) }, bottomRow, { Key(","), Key("."), Key("/"), Key("Right Shift", 2.5) } })),
        [5] = KeyRow(1, { [1] = Key("Left Control", 1.5), [2] = Key(""), [3] = Key("Left Alt", 1.5), [4] = Key("Space", 7), [5] = Key("Right Alt", 1.5), [6] = Key("Menu"), [7] = Key("Right Control", 1.5) })
    })
}


EscapeKey = {
    [1] = KeyColumn({
        [1] = KeyRow(1, { [1] = Key("Escape") })
    })
}


NavigationKeys = {
    [1] = KeyColumn({
        [1] = KeyRow(1, { [1] = Key("Insert"), [2] = Key("Home"), [3] = Key("Page Up"  ) }),
        [2] = KeyRow(1, { [1] = Key("Delete"), [2] = Key("End" ), [3] = Key("Page Down") })
    })
}


ArrowKeys = {
    [1] = KeyColumn({
        [1] = KeyRow(1, { [1] = nil,         [2] = Key("Up"),   [3] = nil }),
        [2] = KeyRow(1, { [1] = Key("Left"), [2] = Key("Down"), [3] = Key("Right") })
    })
}

NumericKeypad = {
    [1] = KeyColumn({
        [1] = KeyRow(1, { [1] = Key("Clear / Num Lock"), [2] = Key("/ (KP)"), [3] = Key("* (KP)") }),
        [2] = KeyRow(1, { [1] = Key("7 (KP)"          ), [2] = Key("8 (KP)"), [3] = Key("9 (KP)") }),
        [3] = KeyRow(1, { [1] = Key("4 (KP)"          ), [2] = Key("5 (KP)"), [3] = Key("6 (KP)") }),
        [4] = KeyRow(1, { [1] = Key("1 (KP)"          ), [2] = Key("2 (KP)"), [3] = Key("3 (KP)") }),
        [5] = KeyRow(1, { [1] = Key("0 (KP)", 2       ),                      [2] = Key(". (KP)") })
    }),
    [2] = KeyColumn({
        [1] = KeyRow(1, { [1] = Key("- (KP)") }),
        [2] = KeyRow(2, { [1] = Key("+ (KP)") }),
        [3] = KeyRow(2, { [1] = Key("Enter (KP)") })
    })
}
