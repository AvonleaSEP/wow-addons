-- Spliff Frames: stance tabs
-- Your stances (or forms) as tabs standing on the top edge of your frame's
-- health bar, sharing its full width between them. The one you're in
-- stands tall, with its icon and name; the others shrink to shorter
-- coloured bars. Hover one and it rises too. Click a tab to change to it
-- (works in combat).
--   Warrior: Battle red, Defensive steel blue, Berserker orange.
-- Your buffs lift above the tabs. Their own page in /spliffbars (Stance
-- Tabs, under Unit Frames) sets their heights, widths and the rest; the
-- settings follow your Edit Mode layout, like the frames'. The game's own
-- stance bar can be switched off in Edit Mode's list of bars.

local _, ns = ...
local S = Spliffbars

local MAX = 6 -- tabs made (warriors use 3; druids more)

-- colours by the stance's spell; others take the palette in order
local COLORS = {
    [2457] = { 0.85, 0.25, 0.2 },  -- Battle Stance
    [71]   = { 0.35, 0.55, 0.9 },  -- Defensive Stance
    [2458] = { 0.95, 0.6, 0.15 },  -- Berserker Stance
}
local PALETTE = { { 0.85, 0.25, 0.2 }, { 0.35, 0.55, 0.9 }, { 0.95, 0.6, 0.15 }, { 0.4, 0.8, 0.35 },
    { 0.7, 0.45, 0.9 }, { 0.3, 0.8, 0.8 } }

-- the settings (kept with your frame's, per Edit Mode layout)
local CFG = {
    stanceTabs = true,      -- on
    stanceFill = true,      -- share the health bar's full width
    stanceWidth = 60,       -- each tab's width when not filling
    stanceGap = 2,          -- between tabs
    stanceTall = 24,        -- the current stance's height
    stanceShort = 7,        -- the others' height
    stanceShortPct = 90,    -- the others' width, % of their share
    stanceIcon = true,      -- the current one's icon
    stanceIconCenter = false, -- the icon in the middle of the tab (else at its left end)
    stanceIconPad = 3,      -- room around the icon, top and bottom (and at the left end)
    stanceName = true,      -- the current one's name
    stanceFontSize = 11,
}

local isSecret = S.isSecret
local function Plain(v) if not isSecret(v) then return v end end

local function Cfg()
    local l = ns.Look and ns.Look("player") or {}
    for k, v in pairs(CFG) do
        if l[k] == nil then l[k] = v end
    end
    return l
end

local function On()
    local f = ns.frames and ns.frames.player
    if not (f and ns.DB and ns.Look) then return false end
    local l = Cfg()
    return l.stanceTabs ~= false and not l.hidden
end

local function Count()
    local ok, n = pcall(GetNumShapeshiftForms)
    n = ok and Plain(n)
    return type(n) == "number" and math.min(n, MAX) or 0
end

local function Info(i)
    local ok, icon, active, castable, spellID = pcall(GetShapeshiftFormInfo, i)
    if not ok then return nil end
    return Plain(icon), Plain(active) == true, Plain(castable) ~= false, Plain(spellID)
end

-- "Battle Stance" -> "Battle", "Cat Form" -> "Cat"
local function ShortName(spellID)
    if not spellID then return nil end
    local ok, n
    if C_Spell and C_Spell.GetSpellName then ok, n = pcall(C_Spell.GetSpellName, spellID)
    elseif GetSpellInfo then ok, n = pcall(GetSpellInfo, spellID) end
    n = ok and Plain(n)
    if type(n) ~= "string" then return nil end
    return (n:gsub(" Stance$", ""):gsub(" Form$", ""))
end

---------------------------------------------------------------------------
-- The tabs: a secure button for the click (sized out of combat), and a
-- look of its own on top that grows and shrinks freely
---------------------------------------------------------------------------
local tabs = {}

local function MakeTab(i)
    local btn = CreateFrame("Button", "SpliffFramesStance" .. i, UIParent, "SecureActionButtonTemplate")
    -- both: with "cast on key down" on, the game acts on the press, else
    -- the release (only "up" was registered at first: no clicks with it on)
    btn:RegisterForClicks("AnyDown", "AnyUp")
    btn:SetAttribute("type", "spell")
    btn:Hide()

    local look = CreateFrame("Frame", nil, UIParent)
    look:SetPoint("BOTTOM", btn, "BOTTOM")
    look:Hide()
    local edge = look:CreateTexture(nil, "BACKGROUND", nil, 0)
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 0.95)
    local fill = look:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetTexture(S.WHITE)
    -- the icon: a square, at the left end or in the middle (Place sets which)
    local icon = look:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", 3, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local name = look:CreateFontString(nil, "OVERLAY")
    name:SetFont(S.FontPath(nil), CFG.stanceFontSize, "OUTLINE")
    name:SetWordWrap(false)
    -- a soft light along the top of the current one
    local shine = look:CreateTexture(nil, "OVERLAY")
    shine:SetPoint("TOPLEFT", 1, -1)
    shine:SetPoint("TOPRIGHT", -1, -1)
    shine:SetHeight(1)
    shine:SetColorTexture(1, 1, 1, 0.55)

    local t = { btn = btn, look = look, fill = fill, icon = icon, name = name, shine = shine, index = i,
        h = 5, w = 20, slotW = 40, tall = CFG.stanceTall, short = CFG.stanceShort, shortW = 36 }

    btn:SetScript("OnEnter", function(self)
        t.hover = true
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if not pcall(GameTooltip.SetShapeshift, GameTooltip, i) then
            local _, _, _, spellID = Info(i)
            if spellID then pcall(GameTooltip.SetSpellByID, GameTooltip, spellID) end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() t.hover = false; GameTooltip:Hide() end)

    -- grow and shrink smoothly toward where it should be
    look:SetScript("OnUpdate", function(_, elapsed)
        local up = t.active or t.hover
        local wantH, wantW = up and t.tall or t.short, up and t.slotW or t.shortW
        local k = math.min(1, elapsed * 14)
        t.h = t.h + (wantH - t.h) * k
        t.w = t.w + (wantW - t.w) * k
        look:SetSize(math.max(2, t.w), math.max(2, t.h))
        local open = t.h > t.short + (t.tall - t.short) * 0.6 -- (most of the way up)
        local s = math.max(1, t.h - 2 * (t.pad or 3))
        icon:SetSize(s, s)
        icon:SetShown(open and t.showIcon and t.iconTex ~= nil)
        name:SetShown(open and t.showName and t.label ~= nil)
        shine:SetShown(t.active and true or false)
    end)
    tabs[i] = t
    return t
end

-- (out of combat) how many tabs, what each casts, their sizes and places
local function Place()
    if InCombatLockdown() then return false end
    local f = ns.frames and ns.frames.player
    local n = On() and Count() or 0
    local l = Cfg()
    local slotW = l.stanceWidth
    if n > 0 and l.stanceFill and f and f.health then
        slotW = (f.health:GetWidth() - (n - 1) * l.stanceGap) / n
    end
    slotW = math.max(8, slotW)
    for i = 1, MAX do
        local t = tabs[i] or (i <= n and MakeTab(i))
        if t then
            if i <= n then
                local _, _, _, spellID = Info(i)
                t.btn:SetAttribute("spell", spellID)
                t.btn:SetSize(slotW, l.stanceTall)
                -- above your frame (the button on top, for the click)
                t.btn:SetFrameStrata(f:GetFrameStrata())
                t.look:SetFrameStrata(f:GetFrameStrata())
                t.look:SetFrameLevel(f:GetFrameLevel() + 30)
                t.btn:SetFrameLevel(f:GetFrameLevel() + 31)
                t.btn:ClearAllPoints()
                -- standing on the health bar's top edge, left to right
                t.btn:SetPoint("BOTTOMLEFT", f.health, "TOPLEFT", (i - 1) * (slotW + l.stanceGap), 0)
                t.btn:Show()
                t.slotW, t.tall, t.short = slotW, l.stanceTall, l.stanceShort
                t.shortW = slotW * l.stanceShortPct / 100
                t.showIcon, t.showName = l.stanceIcon, l.stanceName
                t.pad = l.stanceIconPad
                t.icon:ClearAllPoints()
                if l.stanceIconCenter then
                    t.icon:SetPoint("CENTER", t.look, "CENTER")
                else
                    t.icon:SetPoint("LEFT", t.look, "LEFT", l.stanceIconPad, 0)
                end
                t.name:SetFont(S.FontPath(nil), l.stanceFontSize, "OUTLINE")
                t.name:ClearAllPoints()
                if l.stanceIcon then
                    -- after the icon, wherever it sits
                    t.name:SetPoint("LEFT", t.icon, "RIGHT", 4, 0)
                    t.name:SetJustifyH("LEFT")
                else
                    t.name:SetPoint("LEFT", t.look, "LEFT", 5, 0)
                    t.name:SetJustifyH("CENTER")
                end
                t.name:SetPoint("RIGHT", t.look, "RIGHT", -4, 0)
            else
                t.btn:Hide()
            end
        end
    end
    return true
end

-- the look: colour, icon, name, which is current (any time, combat too)
local function Paint()
    local n = On() and Count() or 0
    for i = 1, MAX do
        local t = tabs[i]
        if t then
            if i <= n and t.btn:IsShown() then
                local tex, active, castable, spellID = Info(i)
                local c = COLORS[spellID] or PALETTE[(i - 1) % #PALETTE + 1]
                t.active = active
                t.iconTex = tex
                t.label = ShortName(spellID)
                if tex then t.icon:SetTexture(tex) end
                t.name:SetText(t.label or "")
                local a = castable and 1 or 0.45
                if active then
                    S.Gradient(t.fill, "VERTICAL", c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, 1, c[1], c[2], c[3], 1)
                else
                    S.Gradient(t.fill, "VERTICAL", c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, a,
                        c[1] * 0.85, c[2] * 0.85, c[3] * 0.85, a)
                end
                t.icon:SetDesaturated(not castable)
                t.look:Show()
            else
                t.look:Hide()
            end
        end
    end
end

local function Refresh()
    Place()
    Paint()
    if ns.RefreshAuras then ns.RefreshAuras() end -- (your buffs rise above the tabs, or settle back)
end
ns.RefreshStance = Refresh

-- how far your frame's buffs rise for the tabs (0 when there are none)
function ns.StanceLift(f)
    if f ~= (ns.frames and ns.frames.player) then return 0 end
    if not (On() and Count() > 0) then return 0 end
    return Cfg().stanceTall + 1
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_SHAPESHIFT_USABLE", "UPDATE_SHAPESHIFT_COOLDOWN", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_USABLE" or event == "UPDATE_SHAPESHIFT_COOLDOWN" then
        Paint()
    else
        Refresh()
    end
end)
-- (your frame's width or the layout changing moves them too)
if S.LEM then
    S.LEM:RegisterCallback("layout", function() C_Timer.After(0, Refresh) end)
    S.LEM:RegisterCallback("exit", function() C_Timer.After(0, Refresh) end)
end

---------------------------------------------------------------------------
-- Their page in /spliffbars (under Unit Frames)
---------------------------------------------------------------------------
if S.AddOptionsTab then
    S.AddOptionsTab("Stance Tabs",
        "Your stances as tabs on your health bar's top edge: the current one tall, with its icon and name; the others shorter bars. Click one to change stance. For the Edit Mode layout you're using.",
        function(page)
            local function Get(k) return function() return Cfg()[k] end end
            local function Set(k) return function(v) Cfg()[k] = v; Refresh() end end
            local function on() return Cfg().stanceTabs ~= false end

            local L = page:Column(16, -80)
            page:Heading(L, "Tabs")
            page:Check(L, "Show the stance tabs", Get("stanceTabs"), Set("stanceTabs"))
            page:Check(L, "Fill the health bar's width", Get("stanceFill"), Set("stanceFill"), 20, on)
            page:Slider(L, "Each tab's width (when not filling)", 20, 200, 1, Get("stanceWidth"), Set("stanceWidth"),
                function(v) return math.floor(v + 0.5) .. " px" end,
                function() return on() and not Cfg().stanceFill end)
            page:Slider(L, "Gap between tabs", 0, 12, 1, Get("stanceGap"), Set("stanceGap"),
                function(v) return math.floor(v + 0.5) .. " px" end, on)
            page:Note(L, "Your buffs move up to stay clear of the tabs.")

            local R = page:Column(340, -80)
            page:Heading(R, "Sizes")
            page:Slider(R, "Current stance: height", 8, 48, 1, Get("stanceTall"), Set("stanceTall"),
                function(v) return math.floor(v + 0.5) .. " px" end, on)
            page:Slider(R, "Other stances: height", 2, 30, 1, Get("stanceShort"), Set("stanceShort"),
                function(v) return math.floor(v + 0.5) .. " px" end, on)
            page:Slider(R, "Other stances: width", 30, 100, 5, Get("stanceShortPct"), Set("stanceShortPct"),
                function(v) return math.floor(v + 0.5) .. "% of a tab" end, on)
            page:Heading(R, "On the current one")
            page:Check(R, "Its icon", Get("stanceIcon"), Set("stanceIcon"), nil, on)
            local function iconOn() return on() and Cfg().stanceIcon end
            page:Check(R, "Icon in the middle of the tab", Get("stanceIconCenter"), Set("stanceIconCenter"), 20, iconOn)
            page:Slider(R, "Room around the icon", 0, 10, 1, Get("stanceIconPad"), Set("stanceIconPad"),
                function(v) return math.floor(v + 0.5) .. " px" end, iconOn)
            page:Check(R, "Its name (Battle, Defensive ...)", Get("stanceName"), Set("stanceName"), nil, on)
            page:Slider(R, "Name size", 7, 20, 1, Get("stanceFontSize"), Set("stanceFontSize"),
                function(v) return math.floor(v + 0.5) end, function() return on() and Cfg().stanceName end)
        end)
end
