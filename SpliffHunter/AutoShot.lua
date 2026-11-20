-- Spliff Hunter: Auto Shot timer
-- A slim bar, in Spliffbars' look, for your Auto Shot. After each shot it
-- fills while your bow (or gun) reloads, as long as your ranged speed. The
-- last half second is the aim: a gold mark shows where it starts. Moving
-- during the aim holds the shot (the game won't fire while you move), so
-- the bar turns red until you stand still; the aim then starts over.
-- It shows while Auto Shot is on and a moment after; always in Edit Mode.
--
-- Edit Mode (Esc > Edit Mode): drag it; click it for Width, Height, Time
-- Text, Text Size and Hide.

local _, ns = ...
local S = Spliffbars
local AIM = 0.5            -- the aim before each shot, in seconds
local AUTO_SHOT = 75       -- Auto Shot's spell id
local LINGER = 1.5         -- seconds it stays up after Auto Shot stops

local DEFAULTS = { width = 200, height = 10, timeText = true, fontSize = 10, hidden = false }
local DEFAULT_POS = { point = "CENTER", x = 0, y = -140 }

local COLORS = {
    reload = { 0.67, 0.83, 0.45 }, -- hunter green
    aim    = { 1, 0.82, 0.2 },     -- gold
    held   = { 0.95, 0.25, 0.2 },  -- moving: the shot waits
}

local feature = ns.Feature({
    key = "autoshot",
    name = "Auto Shot timer",
    notes = "A bar for each shot's reload and aim; red while moving holds the shot. Move it in Edit Mode.",
})

if not ns.isHunter then return end -- (the switch still shows on the Hunter page)

local LEM = S.LEM
local isSecret = S.isSecret
local layoutName
local function Look() return S.Look(ns.DB, layoutName, "autoshot", DEFAULTS) end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local bar = CreateFrame("Frame", "SpliffHunterAutoShot", UIParent)
bar.editModeName = "Spliff Hunter: Auto Shot"
bar:SetSize(DEFAULTS.width, DEFAULTS.height)
bar:SetClampedToScreen(true)
bar:SetFrameStrata("MEDIUM")
bar:Hide()

local edge = bar:CreateTexture(nil, "BACKGROUND", nil, 0)
edge:SetAllPoints()
edge:SetColorTexture(0, 0, 0, 0.9)
local inside = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
inside:SetPoint("TOPLEFT", 1, -1)
inside:SetPoint("BOTTOMRIGHT", -1, 1)
inside:SetColorTexture(0.06, 0.07, 0.05, 0.92)

local sb = CreateFrame("StatusBar", nil, bar)
sb:SetPoint("TOPLEFT", 1, -1)
sb:SetPoint("BOTTOMRIGHT", -1, 1)
sb:SetMinMaxValues(0, 1)
S.SmoothFill(sb)

local over = CreateFrame("Frame", nil, bar)
over:SetAllPoints()
over:SetFrameLevel(sb:GetFrameLevel() + 5)
-- where the aim starts
local mark = over:CreateTexture(nil, "OVERLAY")
mark:SetColorTexture(1, 0.82, 0.2, 0.95)
mark:SetWidth(2)
local timeText = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
timeText:SetPoint("RIGHT", over, "RIGHT", -3, 0)

local function Paint(color)
    local c = COLORS[color]
    S.SetFill(sb, c[1], c[2], c[3], 1, "VERTICAL")
end
Paint("reload")

local function Arrange()
    local l = Look()
    bar:SetSize(l.width, l.height)
    S.ApplyFont(timeText, nil, l.fontSize, "OUTLINE")
    timeText:SetShown(l.timeText and l.height >= 8)
    mark:ClearAllPoints()
    mark:SetPoint("TOP", over, "TOP", 0, -1)
    mark:SetPoint("BOTTOM", over, "BOTTOM", 0, 1)
end

---------------------------------------------------------------------------
-- The shot cycle
---------------------------------------------------------------------------
local state = "idle"  -- idle / reload / aim
local speed = 2       -- this cycle's ranged speed
local shotAt          -- when the last shot went off
local aimStart        -- when the current aim began
local auto = false    -- Auto Shot switched on
local stoppedAt       -- when Auto Shot was switched off

local function RangedSpeed()
    local ok, s = pcall(UnitRangedDamage, "player")
    if ok and not isSecret(s) and type(s) == "number" and s > 0 then return s end
    return speed
end

local function Moving()
    local ok, v = pcall(GetUnitSpeed, "player")
    local moving = ok and not isSecret(v) and type(v) == "number" and v > 0
    if not moving and IsFalling then
        local f = IsFalling()
        moving = not isSecret(f) and f and true or false
    end
    return moving
end

local function PlaceMark()
    local w = bar:GetWidth() - 2
    local at = math.max(0, (speed - AIM) / speed)
    mark:ClearAllPoints()
    mark:SetPoint("TOP", over, "TOPLEFT", 1 + w * at, -1)
    mark:SetPoint("BOTTOM", over, "BOTTOMLEFT", 1 + w * at, 1)
end

local function Shot()
    speed = RangedSpeed()
    shotAt = GetTime()
    state = "reload"
    PlaceMark()
end

local function Visible()
    if not (ns.IsOn(feature) and ns.DB) then return false end
    local l = Look()
    if LEM:IsInEditMode() then return true end
    if l.hidden then return false end
    if auto or state == "reload" then return true end
    return stoppedAt ~= nil and GetTime() - stoppedAt < LINGER
end

local function Update()
    local now = GetTime()
    local progress, left, color = 0, nil, "reload"
    if state == "reload" then
        local reloadEnd = shotAt + speed - AIM
        if now >= reloadEnd then
            state, aimStart = "aim", now
        else
            progress = (now - shotAt) / speed
            left = speed - (now - shotAt)
        end
    end
    if state == "aim" then
        if Moving() then
            aimStart = now -- the aim starts over once you stop
            color = "held"
        else
            color = "aim"
        end
        local aimed = math.min(AIM, now - aimStart)
        progress = (speed - AIM + aimed) / speed
        left = AIM - aimed
        if not auto and now - aimStart > AIM + 0.5 then state = "idle" end -- (no shot came)
    end
    if state == "idle" then progress, left = 0, nil end
    sb:SetValue(math.min(1, math.max(0, progress)))
    Paint(color)
    timeText:SetText(left and left > 0.05 and ("%.1f"):format(left) or "")
end

bar:SetScript("OnUpdate", function() Update() end)

local function EditPreview()
    -- something to see while placing it: frozen mid-reload
    speed, shotAt, state = 2.8, GetTime() - 1.2, "reload"
    PlaceMark()
    Update()
    bar:SetScript("OnUpdate", nil)
end

local function Refresh()
    if not ns.DB then bar:Hide() return end
    Arrange()
    local editing = LEM:IsInEditMode()
    bar:SetAlpha((editing and Look().hidden) and 0.4 or 1)
    if editing and not auto and state == "idle" then
        EditPreview()
    else
        bar:SetScript("OnUpdate", function() Update() end)
        PlaceMark()
    end
    bar:SetShown(Visible())
end

-- the feature's switch (Hunter page)
feature.start = Refresh
feature.stop = function() bar:Hide() end

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
    Setting(LEM.SettingType.Slider, "Width", "width", { minValue = 60, maxValue = 600, valueStep = 1 }),
    Setting(LEM.SettingType.Slider, "Height", "height", { minValue = 4, maxValue = 40, valueStep = 1 }),
    Setting(LEM.SettingType.Checkbox, "Time Text", "timeText"),
    Setting(LEM.SettingType.Slider, "Text Size", "fontSize", { minValue = 7, maxValue = 20, valueStep = 1 }),
})

LEM:RegisterCallback("layout", function(layout)
    layoutName = layout
    Place()
    Refresh()
end)
LEM:RegisterCallback("enter", function() Refresh() end)
LEM:RegisterCallback("exit", function()
    if state ~= "reload" and not auto then state = "idle" end -- (drop the preview)
    Refresh()
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("START_AUTOREPEAT_SPELL")
events:RegisterEvent("STOP_AUTOREPEAT_SPELL")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "ADDON_LOADED" then
        if a1 == "SpliffHunter" then Place(); Refresh() end
        return
    end
    if not ns.DB then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- a3: the spell's id
        if not isSecret(a3) and a3 == AUTO_SHOT then Shot(); Refresh() end
    elseif event == "START_AUTOREPEAT_SPELL" then
        auto, stoppedAt = true, nil
        if state == "idle" then
            -- the first shot of a string: straight to the aim
            speed = RangedSpeed()
            state, aimStart, shotAt = "aim", GetTime(), GetTime() - (speed - AIM)
            PlaceMark()
        end
        Refresh()
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        auto, stoppedAt = false, GetTime()
        if state == "aim" then state = "idle" end
        Refresh()
        C_Timer.After(LINGER + 0.1, Refresh)
    else -- PLAYER_ENTERING_WORLD
        Place()
        Refresh()
    end
end)
