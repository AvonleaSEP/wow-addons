-- Spliffbars: Flight Timer
-- A bar that shows while you're on a flight path: where you're going and
-- how long is left, filling as you go.
--
-- The game doesn't say how long a flight takes, so it learns:
--   a route you've flown before   its time, counted down exactly
--   a route you haven't           an estimate from the length of the path
--                                 on the flight map and your pace on the
--                                 flights you've taken (shown with a ~)
--   your very first flight        it counts up, and times the route
-- Hovering a destination on the flight map shows the time too.
--
-- A /reload or relog mid-flight picks the flight back up. Routes are kept
-- for the account (SpliffbarsFlightDB). /spliffbars flight shows a short
-- test flight. Moves and sets up in Edit Mode like the other bars.

local _, ns = ...
local LEM, isSecret, Num = ns.LEM, ns.isSecret, ns.Num

local DEFAULTS = { width = 260, height = 18, font = "Game default", fontSize = 12, hidden = false }
local DEFAULT_POS = { point = "TOP", x = 0, y = -140 }
local ARRIVED_FOR = 2.5 -- seconds "Arrived" stays up

local DB, layoutName
local function Look() return ns.Look(DB, layoutName, "flight", DEFAULTS) end

-- Leatrix Plus' own flight times (exact ones for Forever) on: this bar and
-- its flight-map line step aside, so you don't get two of each
local function LeatrixFlights()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Leatrix_Plus")
    return loaded and type(LeaPlusDB) == "table" and LeaPlusDB.ShowFlightTimes == "On" or false
end

local function Clock(s)
    s = math.max(0, math.floor(s + 0.5))
    local floor = math.floor
    if s >= 3600 then return ("%d:%02d:%02d"):format(floor(s / 3600), floor(s % 3600 / 60), s % 60) end
    return ("%d:%02d"):format(floor(s / 60), s % 60)
end

---------------------------------------------------------------------------
-- The bar: sky blue, a gryphon (or wyvern) at the left, the destination
-- and the time left on it
---------------------------------------------------------------------------
local bar = CreateFrame("Frame", "SpliffbarsFlight", UIParent)
bar.editModeName = "Spliffbars: Flight Timer"
bar:SetSize(DEFAULTS.width, DEFAULTS.height)
bar:SetClampedToScreen(true)
bar:SetFrameStrata("MEDIUM")
bar:Hide()
if bar.EnableMouseMotion then bar:EnableMouseMotion(true) else bar:EnableMouse(true) end

local edge = bar:CreateTexture(nil, "BACKGROUND", nil, 0)
edge:SetAllPoints()
edge:SetColorTexture(0.05, 0.12, 0.22, 1)
local rim = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
rim:SetPoint("TOPLEFT", 1, -1)
rim:SetPoint("BOTTOMRIGHT", -1, 1)
rim:SetColorTexture(0.35, 0.6, 0.85, 1)
local inside = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
inside:SetPoint("TOPLEFT", 2, -2)
inside:SetPoint("BOTTOMRIGHT", -2, 2)
inside:SetColorTexture(0.03, 0.05, 0.09, 0.95)

local sb = CreateFrame("StatusBar", nil, bar)
sb:SetPoint("TOPLEFT", 2, -2)
sb:SetPoint("BOTTOMRIGHT", -2, 2)
ns.SmoothFill(sb)
ns.Gradient(sb.grad, "VERTICAL", 0.08, 0.28, 0.55, 1, 0.45, 0.78, 1, 1)

local over = CreateFrame("Frame", nil, bar)
over:SetAllPoints()
over:SetFrameLevel(sb:GetFrameLevel() + 5)
local mount = over:CreateTexture(nil, "OVERLAY")
mount:SetPoint("LEFT", 3, 0)
mount:SetTexCoord(0.08, 0.92, 0.08, 0.92)
-- (made with the game's font so they can always take text; Arrange() sets
-- the chosen one)
local destText = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
destText:SetPoint("LEFT", mount, "RIGHT", 4, 0)
destText:SetWordWrap(false)
destText:SetJustifyH("LEFT")
local timeText = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
timeText:SetPoint("RIGHT", -5, 0)
timeText:SetWordWrap(false)

---------------------------------------------------------------------------
-- Routes: where you are, where you picked, and how long the path is on
-- the flight map (every hop of it)
---------------------------------------------------------------------------
local function Call(f, ...)
    if not f then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok or isSecret(a) or isSecret(b) then return nil end
    return a, b
end

local function CurrentNode()
    local n = Call(NumTaxiNodes) or 0
    for i = 1, n do
        if Call(TaxiNodeGetType, i) == "CURRENT" then return i end
    end
end

-- name of where you are, name of where you're going, and the path's length
local function Route(index)
    local here = CurrentNode()
    local from = here and Call(TaxiNodeName, here)
    local to = Call(TaxiNodeName, index)
    local length = 0
    local hops = Call(GetNumRoutes, index) or 0
    for h = 1, hops do
        local x1, y1 = Call(TaxiGetSrcX, index, h), Call(TaxiGetSrcY, index, h)
        local x2, y2 = Call(TaxiGetDestX, index, h), Call(TaxiGetDestY, index, h)
        if Num(x1) and Num(y1) and Num(x2) and Num(y2) then
            length = length + math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        end
    end
    if length == 0 and here then -- no hops to read: straight across
        local x1, y1 = Call(TaxiNodePosition, here)
        local x2, y2 = Call(TaxiNodePosition, index)
        if Num(x1) and Num(y1) and Num(x2) and Num(y2) then length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) end
    end
    if type(from) ~= "string" or type(to) ~= "string" then return nil end
    return from .. " > " .. to, to, length
end

-- the time a route takes: known exactly, or estimated from its length
local function Expected(key, length)
    if not DB then return nil end
    if key and DB.routes[key] then return DB.routes[key], false end
    if DB.pace and length and length > 0 then return length * DB.pace, true end
    return nil
end

---------------------------------------------------------------------------
-- The flight
---------------------------------------------------------------------------
local pending  -- picked on the flight map, waiting to take off
local flight   -- in the air: { key, dest, length, expected, estimated, start }
local arrived  -- just landed: { dest, at }
local Refresh

local function SaveCurrent()
    if not DB then return end
    if flight and not flight.test then
        DB.current[ns.CharKey()] = { key = flight.key, dest = flight.dest, length = flight.length,
            expected = flight.expected, estimated = flight.estimated, startEpoch = time() - (GetTime() - flight.start) }
    else
        DB.current[ns.CharKey()] = nil
    end
end

local function Land()
    local f = flight
    flight = nil
    local elapsed = GetTime() - f.start
    -- learn it: the route's time, and your pace for estimating new ones. A
    -- flight much shorter than the known time was cut short (a disconnect):
    -- don't learn from that one.
    if DB and not f.test and f.key and not f.resumedBlind and elapsed > 5 then
        local known = DB.routes[f.key]
        if not known or elapsed >= known * 0.7 then
            DB.routes[f.key] = elapsed
            if f.length and f.length > 0 then
                local pace = elapsed / f.length
                DB.pace = DB.pace and (DB.pace * 0.7 + pace * 0.3) or pace
            end
        end
    end
    arrived = { dest = f.dest, at = GetTime() }
    SaveCurrent()
    Refresh()
end

local function Paint()
    local now = GetTime()
    if flight then
        local elapsed = now - flight.start
        destText:SetText(flight.dest or "In flight")
        if flight.expected and flight.expected > 0 then
            local left = flight.expected - elapsed
            sb:SetMinMaxValues(0, flight.expected)
            sb:SetValue(math.min(elapsed, flight.expected))
            if left > 0 then
                timeText:SetText((flight.estimated and "~" or "") .. Clock(left))
            else
                timeText:SetText("any moment")
            end
        else
            -- not timed yet: count up, the fill breathing gently
            sb:SetMinMaxValues(0, 1)
            sb:SetValue(0.5 + 0.5 * math.sin(elapsed * 1.5))
            timeText:SetText(Clock(elapsed) .. "  timing it")
        end
    elseif arrived then
        sb:SetMinMaxValues(0, 1)
        sb:SetValue(1)
        destText:SetText("Arrived: " .. (arrived.dest or ""))
        timeText:SetText("")
    elseif LEM:IsInEditMode() then -- something to see while placing it
        sb:SetMinMaxValues(0, 1)
        sb:SetValue(0.6)
        destText:SetText("Ironforge")
        timeText:SetText("1:23")
    end
end

local function Arrange()
    local l = Look()
    bar:SetSize(l.width, l.height)
    local s = math.max(8, l.height - 4)
    mount:SetSize(s, s)
    local faction = UnitFactionGroup("player")
    mount:SetTexture(ns.Icon(faction == "Horde" and "Ability_Mount_Wyvern_01" or "Ability_Mount_Gryphon_01"))
    ns.ApplyFont(destText, l.font, l.fontSize, "OUTLINE")
    ns.ApplyFont(timeText, l.font, l.fontSize, "OUTLINE")
    destText:SetPoint("RIGHT", timeText, "LEFT", -6, 0)
end

Refresh = function()
    if not DB then return end
    local l = Look()
    local editing = LEM:IsInEditMode()
    if arrived and GetTime() - arrived.at > ARRIVED_FOR then arrived = nil end
    local busy = flight or arrived
    -- (a test flight still shows, so you can see where it sits)
    if busy and not editing and LeatrixFlights() and not (flight and flight.test) then busy = nil end
    if (l.hidden and not editing) or not (busy or editing) then
        bar:Hide()
        return
    end
    bar:SetAlpha(l.hidden and 0.4 or 1)
    Arrange()
    Paint()
    bar:Show()
end

-- watch for take-off and landing (the game has no event for either on
-- every client, so a light check five times a second)
local driver = CreateFrame("Frame")
local since = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.2 then return end
    since = 0
    if not DB then return end
    if flight and flight.test then
        if GetTime() - flight.start >= flight.expected then Land() elseif bar:IsShown() then Paint() end
        return
    end
    local onTaxi = UnitOnTaxi("player")
    if isSecret(onTaxi) then return end
    if pending and not flight then
        if onTaxi then
            flight, pending = pending, nil
            flight.start = GetTime()
            SaveCurrent()
            Refresh()
        elseif GetTime() - pending.at > 15 then
            pending = nil -- never took off
        end
    elseif flight then
        -- (while it's stepped aside for Leatrix, or hidden, nothing to paint)
        if not onTaxi then Land() elseif bar:IsShown() then Paint() end
    elseif arrived then
        if GetTime() - arrived.at > ARRIVED_FOR then Refresh() end
    end
end)

-- picking a destination
if TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(index)
        if not DB or not Num(index) then return end
        local key, dest, length = Route(index)
        local expected, estimated = Expected(key, length)
        pending = { key = key, dest = dest, length = length, expected = expected, estimated = estimated, at = GetTime() }
    end)
end

-- the flight map: each destination's time in its tooltip
if TaxiNodeOnButtonEnter then
    hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
        if not DB or not button or not button.GetID or LeatrixFlights() then return end
        local index = button:GetID()
        if Call(TaxiNodeGetType, index) ~= "REACHABLE" then return end
        local key, _, length = Route(index)
        local t, estimated = Expected(key, length)
        if not GameTooltip:IsShown() then return end
        if t then
            GameTooltip:AddLine((estimated and "Flight: about " or "Flight: ") .. Clock(t), 0.55, 0.8, 1)
        else
            GameTooltip:AddLine("Flight: not timed yet", 0.55, 0.8, 1)
        end
        GameTooltip:Show()
    end)
end

bar:SetScript("OnEnter", function(self)
    if not flight then return end
    if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else GameTooltip:SetOwner(self, "ANCHOR_BOTTOM") end
    GameTooltip:AddLine(flight.key or flight.dest or "In flight", 0.55, 0.8, 1)
    GameTooltip:AddDoubleLine("In the air", Clock(GetTime() - flight.start), 1, 0.82, 0, 1, 1, 1)
    if flight.expected then
        GameTooltip:AddDoubleLine(flight.estimated and "Estimated" or "Usual time", Clock(flight.expected), 1, 0.82, 0, 1, 1, 1)
    end
    local n = 0
    for _ in pairs(DB.routes) do n = n + 1 end
    GameTooltip:AddLine(n .. " route" .. (n == 1 and "" or "s") .. " timed", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- /spliffbars flight: a 20 second test flight
ns.TestFlight = function()
    if not DB then return end
    flight = { dest = "Ironforge (test)", expected = 20, start = GetTime(), test = true }
    arrived = nil
    Refresh()
end

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------
local function Place()
    local l = Look()
    bar:ClearAllPoints()
    local p = l.point and l or DEFAULT_POS
    bar:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

LEM:AddFrame(bar, function(_, layout, point, x, y)
    layoutName = layout
    local l = Look()
    l.point, l.x, l.y = point, x, y
end, DEFAULT_POS, bar.editModeName)

local function Setting(kind, name, field, extra)
    local s = {
        kind = kind, name = name, default = DEFAULTS[field],
        get = function(layout) layoutName = layout; return Look()[field] end,
        set = function(layout, value) layoutName = layout; Look()[field] = value; Refresh() end,
    }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

LEM:AddFrameSettings(bar, {
    Setting(LEM.SettingType.Checkbox, "Hide This Bar", "hidden", {
        desc = "Gone outside Edit Mode; shown faded here so you can bring it back.",
    }),
    Setting(LEM.SettingType.Slider, "Width", "width", { minValue = 80, maxValue = 800, valueStep = 1 }),
    Setting(LEM.SettingType.Slider, "Height", "height", { minValue = 8, maxValue = 48, valueStep = 1 }),
    Setting(LEM.SettingType.Dropdown, "Font", "font", { values = ns.FontChoices, height = 300 }),
    Setting(LEM.SettingType.Slider, "Font Size", "fontSize", { minValue = 6, maxValue = 24, valueStep = 1 }),
})
LEM:AddFrameSettingsButton(bar, { text = "Test Flight (20 sec)", click = function() ns.TestFlight() end })
LEM:AddFrameSettingsButton(bar, { text = "Forget Timed Routes", click = function()
    if not DB then return end
    wipe(DB.routes)
    DB.pace = nil
    print(ns.PREFIX .. "flight times forgotten; they'll be learned again as you fly.")
end })

LEM:RegisterCallback("layout", function(layout)
    layoutName = layout
    Place()
    Refresh()
end)
LEM:RegisterCallback("enter", function() Refresh() end)
LEM:RegisterCallback("exit", function() Refresh() end)

-- for the options panel (Options.lua)
ns.RegisterPiece({
    name = "Flight Timer",
    get = function() return DB and Look().hidden or false end,
    set = function(hidden)
        if not DB then return end
        Look().hidden = hidden
        Refresh()
        pcall(LEM.RefreshFrameSettings, LEM, bar)
    end,
})

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 == "Spliffbars" then
            SpliffbarsFlightDB = SpliffbarsFlightDB or {}
            DB = SpliffbarsFlightDB
            DB.routes = DB.routes or {}   -- ["From > To"] = seconds
            DB.current = DB.current or {} -- [character] = the flight in progress
        end
        return
    end
    if not DB then return end
    Place()
    -- in the air at login or after a /reload: pick the flight back up
    local onTaxi = UnitOnTaxi("player")
    if not flight and not isSecret(onTaxi) and onTaxi then
        local c = DB.current[ns.CharKey()]
        local since = c and c.startEpoch and (time() - c.startEpoch)
        if c and since and since >= 0 and since < (c.expected or 1800) + 120 then
            flight = { key = c.key, dest = c.dest, length = c.length, expected = c.expected,
                estimated = c.estimated, start = GetTime() - since }
        else
            -- in the air with no record of taking off: count from now, and
            -- don't learn from it
            flight = { dest = "In flight", start = GetTime(), resumedBlind = true }
        end
    elseif not onTaxi then
        DB.current[ns.CharKey()] = nil
    end
    Refresh()
end)
