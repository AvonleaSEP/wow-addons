-- Spliff Hunter: Pet tracker
-- A small frame for your pet, in Spliffbars' look: its portrait, name and
-- level, a health bar with the percent, and its happiness face (happy,
-- content, unhappy) at the right, with the frame's edge tinted to match.
--   * Happiness drops: a line in chat and a soft sound; unhappy also pulses
--     the frame red until you feed it (an unhappy pet does 75% damage and
--     loses loyalty, a happy one 125%).
--   * Pet gone: "No pet out" (Call Pet, or Revive Pet if it died).
--   * Hover it: happiness, damage, loyalty and what it eats.
--   * Click it: target your pet.
-- Edit Mode (Esc > Edit Mode): drag it; click it for Width, No-Pet Text,
-- Chat Warnings, Sound and Hide.

local _, ns = ...
local S = Spliffbars

local DEFAULTS = { width = 190, showNoPet = true, chat = true, sound = true, hidden = false }
local DEFAULT_POS = { point = "CENTER", x = -260, y = -200 }
local H = 34 -- the frame's height

local feature = ns.Feature({
    key = "pet",
    name = "Pet happiness and health",
    notes = "Your pet's health and happiness, with a warning when it gets hungry. Move it in Edit Mode.",
})

if not ns.isHunter then return end

local LEM, isSecret = S.LEM, S.isSecret
local layoutName
local function Look() return S.Look(ns.DB, layoutName, "pet", DEFAULTS) end

local function Safe(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c
end
local function Plain(v) if not isSecret(v) then return v end end
local function IsTrue(v) return not isSecret(v) and v == true end

-- happiness: 1 unhappy, 2 content, 3 happy (the game's own faces)
local MOOD = {
    [1] = { "Unhappy", { 0.95, 0.25, 0.2 }, { 0.375, 0.5625, 0, 0.359375 } },
    [2] = { "Content", { 1, 0.82, 0.2 }, { 0.1875, 0.375, 0, 0.359375 } },
    [3] = { "Happy", { 0.35, 0.9, 0.35 }, { 0, 0.1875, 0, 0.359375 } },
}
local FACES = "Interface\\PetPaperDollFrame\\UI-PetHappiness"

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local f = CreateFrame("Frame", "SpliffHunterPet", UIParent)
f.editModeName = "Spliff Hunter: Pet"
f:SetSize(DEFAULTS.width, H)
f:SetClampedToScreen(true)
f:SetFrameStrata("MEDIUM")
f:Hide()

local edge = f:CreateTexture(nil, "BACKGROUND", nil, 0)
edge:SetAllPoints()
edge:SetColorTexture(0, 0, 0, 0.9)
local rim = f:CreateTexture(nil, "BACKGROUND", nil, 1) -- tinted by happiness
rim:SetPoint("TOPLEFT", 1, -1)
rim:SetPoint("BOTTOMRIGHT", -1, 1)
rim:SetColorTexture(0.3, 0.3, 0.3, 1)
local inside = f:CreateTexture(nil, "BACKGROUND", nil, 2)
inside:SetPoint("TOPLEFT", 2, -2)
inside:SetPoint("BOTTOMRIGHT", -2, 2)
inside:SetColorTexture(0.06, 0.07, 0.05, 0.94)

local portrait = f:CreateTexture(nil, "ARTWORK")
portrait:SetPoint("TOPLEFT", 2, -2)
portrait:SetSize(H - 4, H - 4)
portrait:SetTexCoord(0.12, 0.88, 0.12, 0.88)

local face = f:CreateTexture(nil, "OVERLAY")
face:SetSize(18, 18)
face:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -2)
face:SetTexture(FACES)

local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 5, -2)
name:SetPoint("RIGHT", face, "LEFT", -4, 0)
name:SetJustifyH("LEFT")
name:SetWordWrap(false)

local health = CreateFrame("StatusBar", nil, f)
health:SetPoint("BOTTOMLEFT", portrait, "BOTTOMRIGHT", 4, 1)
health:SetPoint("RIGHT", f, "RIGHT", -3, 0)
health:SetHeight(11)
health:SetMinMaxValues(0, 1)
S.SmoothFill(health)
S.SetFill(health, 0.3, 0.8, 0.3)
local healthBack = health:CreateTexture(nil, "BACKGROUND")
healthBack:SetAllPoints()
healthBack:SetColorTexture(0, 0, 0, 0.5)
local healthText = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
healthText:SetPoint("CENTER")
S.ApplyFont(healthText, nil, 9, "OUTLINE")

-- "No pet" and friends, in the middle when there's no pet out
local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
empty:SetPoint("LEFT", f, "LEFT", 8, 0)
empty:SetPoint("RIGHT", f, "RIGHT", -8, 0)

-- the red pulse while unhappy
local glow = f:CreateTexture(nil, "BORDER")
glow:SetPoint("TOPLEFT", -3, 3)
glow:SetPoint("BOTTOMRIGHT", 3, -3)
glow:SetColorTexture(0.95, 0.2, 0.15, 0.5)
glow:Hide()
local pulse = glow:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(0.15)
fade:SetToAlpha(0.7)
fade:SetDuration(0.6)

-- click to target your pet: a secure button the game shows only while you
-- have one (set up once, out of combat; it never moves)
local click = CreateFrame("Button", "SpliffHunterPetButton", UIParent, "SecureUnitButtonTemplate")
click:SetAllPoints(f)
click:SetFrameStrata("MEDIUM")
click:SetFrameLevel(f:GetFrameLevel() + 10)
click:SetAttribute("unit", "pet")
click:SetAttribute("type1", "target")
click:RegisterForClicks("AnyUp")
RegisterUnitWatch(click)

---------------------------------------------------------------------------
-- Reading the pet
---------------------------------------------------------------------------
local lastMood        -- the happiness last shown, to notice a drop

local function Happiness()
    if not GetPetHappiness then return nil end
    local h, dmg, loyalty = Safe(GetPetHappiness)
    h, dmg, loyalty = Plain(h), Plain(dmg), Plain(loyalty)
    if type(h) ~= "number" or not MOOD[h] then return nil end
    return h, dmg, loyalty
end

local function HealthPct()
    local cur, max = Plain(Safe(UnitHealth, "pet")), Plain(Safe(UnitHealthMax, "pet"))
    if type(cur) == "number" and type(max) == "number" and max > 0 then
        return math.floor(cur / max * 100 + 0.5)
    end
end

local function Warn(text, sound)
    local l = Look()
    if l.chat then print(ns.PREFIX .. text) end
    if l.sound and sound and PlaySound then pcall(PlaySound, sound, "Master") end
end

local function Moods(h, dmg)
    local m = MOOD[h]
    if h == 3 then return end
    if lastMood and h < lastMood then
        if h == 2 then
            Warn("your pet is getting hungry (content, " .. (dmg or 100) .. "% damage). Feed it soon.",
                SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN)
        else
            Warn("|cffff5040your pet is unhappy|r (" .. (dmg or 75) .. "% damage, losing loyalty). Feed it!",
                SOUNDKIT and SOUNDKIT.RAID_WARNING)
        end
    end
    return m
end

local function Update()
    if not ns.DB then return end
    local l = Look()
    local editing = LEM:IsInEditMode()
    local exists = IsTrue(Safe(UnitExists, "pet"))
    -- before you have a pet at all (Call Pet comes with the hunter's pet
    -- quest), "No pet out" would only nag
    local canCall = C_Spell and C_Spell.GetSpellInfo and Plain(Safe(C_Spell.GetSpellInfo, "Call Pet")) ~= nil
    if not ns.IsOn(feature) or (l.hidden and not editing)
        or (not exists and not (l.showNoPet and canCall) and not editing) then
        f:Hide()
        pulse:Stop()
        return
    end
    f:SetAlpha((editing and l.hidden) and 0.4 or 1)
    f:Show()

    if not exists then
        portrait:Hide(); face:Hide(); name:Hide(); health:Hide(); glow:Hide(); pulse:Stop()
        rim:SetColorTexture(0.3, 0.3, 0.3, 1)
        empty:SetText("No pet out: Call Pet (Revive Pet if it died)")
        empty:Show()
        return
    end
    empty:Hide()
    portrait:Show(); name:Show(); health:Show()
    SetPortraitTexture(portrait, "pet")

    -- name and level
    local n = Safe(UnitName, "pet")
    local lvl = Plain(Safe(UnitLevel, "pet"))
    local okN = pcall(name.SetText, name, n)
    if not okN then name:SetText("Pet") end
    if type(lvl) == "number" and type(Plain(n)) == "string" then
        name:SetText("|cffffd100" .. lvl .. "|r  " .. Plain(n))
    end

    -- health (the game fills the bar, hidden numbers and all)
    pcall(health.SetMinMaxValues, health, 0, UnitHealthMax("pet"))
    pcall(health.SetValue, health, UnitHealth("pet"))
    local pct = HealthPct()
    if pct then
        -- green, to yellow, to red as it drops
        local r = pct < 50 and 0.95 or (0.3 + (100 - pct) / 50 * 0.65)
        local g = pct > 50 and 0.8 or (0.25 + pct / 50 * 0.55)
        S.SetFill(health, r, g, 0.25)
        healthText:SetText(pct .. "%")
    else
        S.SetFill(health, 0.3, 0.8, 0.3)
        local text = ""
        if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
            local ok, p = pcall(UnitHealthPercent, "pet", true, CurveConstants.ScaleTo100)
            if ok then
                local ok2, s = pcall(string.format, "%d%%", p)
                if ok2 then text = s end
            end
        end
        pcall(healthText.SetText, healthText, text)
    end

    -- happiness
    local h, dmg = Happiness()
    if h then
        local m = MOOD[h]
        Moods(h, dmg)
        lastMood = h
        face:SetTexCoord(m[3][1], m[3][2], m[3][3], m[3][4])
        face:Show()
        rim:SetColorTexture(m[2][1] * 0.6, m[2][2] * 0.6, m[2][3] * 0.6, 1)
        if h == 1 then
            glow:Show()
            if not pulse:IsPlaying() then pulse:Play() end
        else
            glow:Hide()
            pulse:Stop()
        end
    else
        face:Hide()
        glow:Hide()
        pulse:Stop()
        rim:SetColorTexture(0.67 * 0.6, 0.83 * 0.6, 0.45 * 0.6, 1)
    end
end

-- hover: the details
local function Tooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    if not IsTrue(Safe(UnitExists, "pet")) then
        GameTooltip:AddLine("No pet out")
        GameTooltip:AddLine("Call Pet brings it out; if it died, Revive Pet.", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    local n = Plain(Safe(UnitName, "pet"))
    GameTooltip:AddLine(type(n) == "string" and n or "Your pet")
    local h, dmg, loyalty = Happiness()
    if h then
        local m = MOOD[h]
        GameTooltip:AddDoubleLine("Happiness", m[1], 1, 0.82, 0, m[2][1], m[2][2], m[2][3])
        if dmg then GameTooltip:AddDoubleLine("Damage", dmg .. "%", 1, 0.82, 0, 1, 1, 1) end
        if loyalty then
            GameTooltip:AddDoubleLine("Loyalty", loyalty > 0 and "growing" or (loyalty < 0 and "dropping" or "steady"),
                1, 0.82, 0, loyalty < 0 and 1 or 1, loyalty < 0 and 0.4 or 1, loyalty < 0 and 0.3 or 1)
        end
    end
    local pct = HealthPct()
    if pct then GameTooltip:AddDoubleLine("Health", pct .. "%", 1, 0.82, 0, 1, 1, 1) end
    if GetPetFoodTypes then
        local foods = { Safe(GetPetFoodTypes) }
        local list = {}
        for _, x in ipairs(foods) do if type(Plain(x)) == "string" then list[#list + 1] = x end end
        if #list > 0 then GameTooltip:AddDoubleLine("Eats", table.concat(list, ", "), 1, 0.82, 0, 1, 1, 1) end
    end
    GameTooltip:AddLine("Click to target your pet", 0.5, 0.8, 1)
    GameTooltip:Show()
end
click:HookScript("OnEnter", function(self) Tooltip(self) end)
click:HookScript("OnLeave", function() GameTooltip:Hide() end)
f:EnableMouse(true) -- (the "No pet" frame, under the click button)
f:SetScript("OnEnter", function(self) Tooltip(self) end)
f:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- the feature's switch (Hunter page)
feature.start = Update
feature.stop = function() f:Hide(); pulse:Stop() end

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------
local function Place()
    local l = Look()
    if InCombatLockdown() then return end -- (the click button sits on it)
    f:SetWidth(l.width)
    f:ClearAllPoints()
    local p = l.point and l or DEFAULT_POS
    f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

LEM:AddFrame(f, function(_, layout, point, x, y)
    layoutName = layout
    local l = Look()
    l.point, l.x, l.y = point, x, y
end, DEFAULT_POS, f.editModeName)

local function Setting(kind, label, field, extra)
    local s = {
        kind = kind, name = label, default = DEFAULTS[field],
        get = function(layout) layoutName = layout; return Look()[field] end,
        set = function(layout, value) layoutName = layout; Look()[field] = value; Place(); Update() end,
    }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

LEM:AddFrameSettings(f, {
    Setting(LEM.SettingType.Checkbox, "Hide This Frame", "hidden", {
        desc = "Gone outside Edit Mode; shown faded here so you can bring it back.",
    }),
    Setting(LEM.SettingType.Slider, "Width", "width", { minValue = 120, maxValue = 400, valueStep = 1 }),
    Setting(LEM.SettingType.Checkbox, "Show \"No Pet\"", "showNoPet"),
    Setting(LEM.SettingType.Checkbox, "Chat Warnings", "chat"),
    Setting(LEM.SettingType.Checkbox, "Sound", "sound"),
})

LEM:RegisterCallback("layout", function(layout)
    layoutName = layout
    Place()
    Update()
end)
LEM:RegisterCallback("enter", function() Update() end)
LEM:RegisterCallback("exit", function() Update() end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PET_UI_UPDATE", "UNIT_HAPPINESS",
    "PLAYER_REGEN_ENABLED" }) do
    pcall(events.RegisterEvent, events, e)
end
events:RegisterUnitEvent("UNIT_PET", "player")
for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_PORTRAIT_UPDATE" }) do
    pcall(events.RegisterUnitEvent, events, e, "pet")
end
events:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 == "SpliffHunter" then Place(); Update() end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then Place() end
    Update()
end)

-- happiness has no event on every client: a look every few seconds too
local since = 0
events:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 3 then return end
    since = 0
    Update()
end)
