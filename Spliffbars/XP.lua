-- XP & Rep Bars
-- An experience bar and a reputation bar like the game's own, that can lie
-- flat or stand up. Everything is set in Edit Mode (Esc > Edit Mode): drag a
-- bar, click it for its settings:
--   Vertical, Scale, Width, Height, Text (presets or your own), Font Size,
--   Text Position, Rotate Text, Segment Ticks;
--   XP also: Show Rested XP, Hide at Max Level, Hide the Game's Bars.
-- Each Edit Mode layout keeps its own settings.
--
-- Your own text: pick "Custom" under Text, then "Edit Custom Text..." and
-- use these words in curly brackets:
--   both bars  {cur} {max} {pct} {left}
--   XP         {level} {rested} {restedpct}
--   rep        {name} {standing}
--
-- The reputation bar shows the faction you're watching (Reputation tab,
-- "Show as Experience Bar"); with none watched it stays hidden.
--
-- Edit Mode support comes from LibEditMode by p3lim (Libs\LibEditMode).

local LEM = LibStub("LibEditMode")
local isSecret = issecretvalue or function() return false end
local function Num(v) return not isSecret(v) and type(v) == "number" end

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local XP_COLOR     = { 0.58, 0.00, 0.55 } -- the game's purple
local RESTED_COLOR = { 0.00, 0.39, 0.88 } -- the game's blue while rested

-- The standard layout (Devon's, 16 Nov): both bars stand up the far left
-- edge of the screen, top to bottom. A thin rep bar against the edge, the
-- XP bar just right of it; percent text to the right, shown on hover.
-- Everything here assumes vertical bars.
local DEFAULTS = {
    xp  = { vertical = true, fullHeight = true, scale = 1, width = 20, height = 1200, text = "pct",
            custom = "{cur} / {max} ({pct}%)", font = "2002 Bold", outline = "OUTLINE",
            fontSize = 17, textPos = "RIGHT", textX = 0, textY = -24, rotate = false, ticks = true,
            rested = true, hideMax = true, questTimeline = true, playtime = true, questPreview = "hover",
            lifeEvents = true,
            hoverText = true, tooltip = "default" },
    rep = { vertical = true, fullHeight = true, scale = 1, width = 6, height = 1200, text = "pct",
            custom = "{name}: {standing} {cur} / {max}", font = "2002 Bold", outline = "OUTLINE",
            fontSize = 18, textPos = "RIGHT", textX = 20, textY = 0, rotate = false, ticks = false,
            hoverText = true, tooltip = "default" },
}

-- the bar's height: the whole screen ("Fill Screen Height"), or the Height setting
local function BarHeight(l)
    if l.fullHeight then return UIParent:GetHeight() / (l.scale or 1) end
    return l.height
end

local TEXT_PRESETS = {
    xp = {
        { "full",   "1,234 / 5,000 (24%)",  "{cur} / {max} ({pct}%)" },
        { "rested", "... + rested",         "{cur} / {max} ({pct}%) +{rested} rested" },
        { "curmax", "1,234 / 5,000",        "{cur} / {max}" },
        { "pct",    "24%",                  "{pct}%" },
        { "left",   "3,766 to go",          "{left} to go" },
        { "level",  "Level 30 - 24%",       "Level {level} - {pct}%" },
        { "none",   "No text",              "" },
        { "custom", "Custom",               nil },
    },
    rep = {
        { "full",   "Name: Friendly 1,234 / 6,000", "{name}: {standing} {cur} / {max}" },
        { "short",  "Name - Friendly",              "{name} - {standing}" },
        { "curmax", "1,234 / 6,000",                "{cur} / {max}" },
        { "pct",    "20%",                          "{pct}%" },
        { "left",   "4,766 to go",                  "{left} to go" },
        { "none",   "No text",                      "" },
        { "custom", "Custom",                       nil },
    },
}

local POSITIONS = {
    { text = "Center", value = "CENTER" }, { text = "Above", value = "ABOVE" },
    { text = "Below", value = "BELOW" }, { text = "Left", value = "LEFT" },
    { text = "Right", value = "RIGHT" },
}

local DB
local layoutName

local function Look(key)
    DB.layouts = DB.layouts or {}
    local lname = layoutName or "Default"
    DB.layouts[lname] = DB.layouts[lname] or {}
    local l = DB.layouts[lname][key]
    if not l then l = {}; DB.layouts[lname][key] = l end
    for k, v in pairs(DEFAULTS[key]) do
        if l[k] == nil then l[k] = v end
    end
    return l
end

local function Big(n)
    n = math.floor(n + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function Template(key, l)
    if l.text == "custom" then return l.custom or "" end
    for _, p in ipairs(TEXT_PRESETS[key]) do
        if p[1] == l.text then return p[3] or "" end
    end
    return ""
end

local function Fill(template, vars)
    return (template:gsub("{(%w+)}", function(k)
        local v = vars[k]
        if v == nil then return "{" .. k .. "}" end
        return tostring(v)
    end))
end

---------------------------------------------------------------------------
-- Fonts: the game's own, plus every font other addons share through
-- LibSharedMedia (HealBot, Questie and ArkInventory load it; HealBot adds
-- its 25 fonts). Looked up when needed, since those addons may load after
-- this one.
---------------------------------------------------------------------------
local GAME_FONTS = {
    { "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" },
    { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\SKURRI.TTF" },
    { "Morpheus", "Fonts\\MORPHEUS.TTF" },
}
local DEFAULT_FONT = "Game default"

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- the font file for a saved font name (nil or "Game default" = the game's)
local function FontPath(name)
    if name and name ~= DEFAULT_FONT then
        local lsm = LSM()
        local path = lsm and lsm:Fetch("font", name, true)
        if path then return path end
        for _, f in ipairs(GAME_FONTS) do
            if f[1] == name then return f[2] end
        end
    end
    return (GameFontHighlightSmall:GetFont())
end

local function FontChoices()
    local names, seen = { DEFAULT_FONT }, { [DEFAULT_FONT] = true }
    local list = {}
    local lsm = LSM()
    if lsm then
        for _, n in ipairs(lsm:List("font")) do list[#list + 1] = n end
    end
    for _, f in ipairs(GAME_FONTS) do list[#list + 1] = f[1] end
    table.sort(list)
    for _, n in ipairs(list) do
        if not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
    local values = {}
    for _, n in ipairs(names) do values[#values + 1] = { text = n, value = n } end
    return values
end

local OUTLINES = {
    { text = "Outline", value = "OUTLINE" },
    { text = "Thick Outline", value = "THICKOUTLINE" },
    { text = "None", value = "" },
}

---------------------------------------------------------------------------
-- The bars
---------------------------------------------------------------------------
local bars = {}

-- Smooth fill. The game's status-bar texture is a small image with only a
-- few shades, so stretched along a long (or vertical) bar its steps show as
-- bands. Instead: one gradient covering the whole bar, darker at the bottom
-- and lighter at the top, revealed as the bar fills (a clipping frame that
-- follows the status bar's fill), so the shades stay put as XP grows.
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function SmoothFill(sb)
    sb:SetStatusBarTexture(WHITE)
    sb:SetStatusBarColor(1, 1, 1, 0) -- invisible: only marks where the fill ends
    local clip = CreateFrame("Frame", nil, sb)
    clip:SetClipsChildren(true)
    clip:SetAllPoints(sb:GetStatusBarTexture())
    local grad = clip:CreateTexture(nil, "ARTWORK")
    grad:SetTexture(WHITE)
    grad:SetAllPoints(sb) -- the whole bar, not just the filled part
    sb.grad = grad
end

local function SetFill(sb, r, g, b, a)
    a = a or 1
    local t = sb.grad
    local r1, g1, b1 = r * 0.55, g * 0.55, b * 0.55
    local r2, g2, b2 = math.min(r * 1.1 + 0.12, 1), math.min(g * 1.1 + 0.12, 1), math.min(b * 1.1 + 0.12, 1)
    if CreateColor and pcall(t.SetGradient, t, "VERTICAL", CreateColor(r1, g1, b1, a), CreateColor(r2, g2, b2, a)) then
        return
    end
    if t.SetGradientAlpha and pcall(t.SetGradientAlpha, t, "VERTICAL", r1, g1, b1, a, r2, g2, b2, a) then
        return -- older clients
    end
    t:SetColorTexture(r, g, b, a) -- no gradient support: plain colour
end

local TICKS = 19 -- a line every 5%

local function MakeBar(key, label)
    local f = CreateFrame("Frame", "XPRepBars_" .. key, UIParent)
    f.key = key
    f.editModeName = label
    f:SetClampedToScreen(true)
    f:SetFrameStrata("LOW")
    f:SetSize(DEFAULTS[key].width, DEFAULTS[key].height)

    local edge = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 0.85)
    local back = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    back:SetPoint("TOPLEFT", 1, -1)
    back:SetPoint("BOTTOMRIGHT", -1, 1)
    back:SetColorTexture(0.1, 0.1, 0.12, 0.8)

    -- rested XP shows as a paler bar running ahead of the real one
    f.ahead = CreateFrame("StatusBar", nil, f)
    f.ahead:SetPoint("TOPLEFT", 1, -1)
    f.ahead:SetPoint("BOTTOMRIGHT", -1, 1)
    SmoothFill(f.ahead)
    SetFill(f.ahead, RESTED_COLOR[1], RESTED_COLOR[2], RESTED_COLOR[3], 0.45)

    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetPoint("TOPLEFT", 1, -1)
    f.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    f.bar:SetFrameLevel(f.ahead:GetFrameLevel() + 2) -- above the rested bar's fill
    SmoothFill(f.bar)

    -- segment lines every 5%, on top of both fills
    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints()
    over:SetFrameLevel(f.bar:GetFrameLevel() + 5)
    f.over = over
    f.ticks = {}
    for i = 1, TICKS do
        local t = over:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 0.5)
        f.ticks[i] = t
    end

    f.text = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetWordWrap(false)

    if f.EnableMouseMotion then f:EnableMouseMotion(true) else f:EnableMouse(true) end
    bars[key] = f
    return f
end

local xpBar = MakeBar("xp", "Experience Bar")
local repBar = MakeBar("rep", "Reputation Bar")

local function Arrange(f)
    local l = Look(f.key)
    f:SetScale(l.scale)
    local height = BarHeight(l)
    f:SetSize(l.width, height)
    local orient = l.vertical and "VERTICAL" or "HORIZONTAL"
    f.bar:SetOrientation(orient)
    f.ahead:SetOrientation(orient)

    local w, h = l.width - 2, height - 2
    for i, t in ipairs(f.ticks) do
        t:ClearAllPoints()
        if l.vertical then
            t:SetSize(w, 1)
            t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1 + h * i / (TICKS + 1))
        else
            t:SetSize(1, h)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 1 + w * i / (TICKS + 1), -1)
        end
        t:SetShown(l.ticks)
    end

    f.text:SetFont(FontPath(l.font), l.fontSize, l.outline or "OUTLINE")
    if not f.text:GetFont() then -- the font file wouldn't load: use the game's
        f.text:SetFont(FontPath(nil), l.fontSize, l.outline or "OUTLINE")
    end
    f.text:ClearAllPoints()
    local p = l.textPos
    local tx, ty = l.textX or 0, l.textY or 0 -- "Text Nudge X / Y"
    if p == "ABOVE" then f.text:SetPoint("BOTTOM", f, "TOP", tx, 3 + ty)
    elseif p == "BELOW" then f.text:SetPoint("TOP", f, "BOTTOM", tx, -3 + ty)
    elseif p == "LEFT" then f.text:SetPoint("RIGHT", f, "LEFT", -4 + tx, ty)
    elseif p == "RIGHT" then f.text:SetPoint("LEFT", f, "RIGHT", 4 + tx, ty)
    else f.text:SetPoint("CENTER", f, "CENTER", tx, ty) end
    if f.text.SetRotation then
        pcall(f.text.SetRotation, f.text, (l.vertical and l.rotate) and math.rad(90) or 0)
    end
end

---------------------------------------------------------------------------
-- Experience
---------------------------------------------------------------------------
local function AtMaxLevel()
    if IsPlayerAtEffectiveMaxLevel then
        local ok, v = pcall(IsPlayerAtEffectiveMaxLevel)
        if ok and not isSecret(v) then return v and true or false end
    end
    if GetMaxPlayerLevel then
        local ok, maxLevel = pcall(GetMaxPlayerLevel)
        local level = UnitLevel("player")
        if ok and Num(maxLevel) and Num(level) then return level >= maxLevel end
    end
    return false
end

local xpInfo -- for the tooltip

local function UpdateXP()
    local f, l = xpBar, Look("xp")
    local editing = LEM:IsInEditMode()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local level = UnitLevel("player")
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    if not Num(cur) or not Num(max) then cur, max = 0, 1 end
    if not Num(rested) then rested = 0 end
    local disabled = IsXPUserDisabled and IsXPUserDisabled()
    local atMax = AtMaxLevel() or disabled

    if atMax and l.hideMax and not editing then
        f:Hide()
        xpInfo = nil
        return
    end
    f:Show()
    if atMax or max <= 0 then cur, max, rested = 1, 1, 0 end

    f.bar:SetMinMaxValues(0, max)
    f.bar:SetValue(cur)
    f.ahead:SetMinMaxValues(0, max)
    f.ahead:SetValue(l.rested and math.min(cur + rested, max) or 0)
    local c = (rested > 0 and l.rested) and RESTED_COLOR or XP_COLOR
    SetFill(f.bar, c[1], c[2], c[3])

    local vars = {
        cur = Big(cur), max = Big(max), left = Big(max - cur),
        pct = string.format("%.1f", cur / max * 100):gsub("%.0$", ""),
        level = Num(level) and level or "?",
        rested = Big(rested), restedpct = math.floor(rested / max * 100 + 0.5),
    }
    f.text:SetText(atMax and "Max level" or Fill(Template("xp", l), vars))
    xpInfo = { cur = cur, max = max, rested = rested, atMax = atMax }
end

---------------------------------------------------------------------------
-- Reputation (the faction you're watching)
---------------------------------------------------------------------------
-- name, reaction (1-8), bottom of this standing, top of it, your value
local function WatchedFaction()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local ok, d = pcall(C_Reputation.GetWatchedFactionData)
        if ok and type(d) == "table" and not isSecret(d) and type(d.name) == "string" and d.name ~= "" then
            return d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
        end
        if ok then return nil end
    end
    if GetWatchedFactionInfo then
        local ok, name, reaction, low, high, value = pcall(GetWatchedFactionInfo)
        if ok and type(name) == "string" and not isSecret(name) then return name, reaction, low, high, value end
    end
    return nil
end

local repInfo

local function UpdateRep()
    local f, l = repBar, Look("rep")
    local editing = LEM:IsInEditMode()
    local name, reaction, low, high, value = WatchedFaction()
    if not name or not (Num(reaction) and Num(low) and Num(high) and Num(value)) then
        repInfo = nil
        if editing then -- something to grab and place
            f:Show()
            f.bar:SetMinMaxValues(0, 1); f.bar:SetValue(0.5)
            f.ahead:SetValue(0)
            SetFill(f.bar, 0, 0.6, 0.1)
            f.text:SetText("Watch a faction to fill this")
        else
            f:Hide()
        end
        return
    end
    f:Show()
    local cur, max = value - low, high - low
    if max <= 0 then cur, max = 1, 1 end -- top standing
    f.bar:SetMinMaxValues(0, max)
    f.bar:SetValue(cur)
    f.ahead:SetMinMaxValues(0, 1)
    f.ahead:SetValue(0)
    local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if color then SetFill(f.bar, color.r, color.g, color.b) else SetFill(f.bar, 0, 0.6, 0.1) end
    local standing = _G["FACTION_STANDING_LABEL" .. reaction]
    if not standing and GetText then
        local ok, s = pcall(GetText, "FACTION_STANDING_LABEL" .. reaction, UnitSex("player"))
        standing = ok and s or nil
    end
    standing = standing or ""

    local vars = {
        name = name, standing = standing,
        cur = Big(cur), max = Big(max), left = Big(max - cur),
        pct = string.format("%.1f", cur / max * 100):gsub("%.0$", ""),
    }
    f.text:SetText(Fill(Template("rep", l), vars))
    repInfo = { name = name, standing = standing, cur = cur, max = max, color = color }
end

---------------------------------------------------------------------------
-- Hiding the game's own bars (optional, setting on the XP bar)
---------------------------------------------------------------------------
local GAME_BARS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
    "StatusTrackingBarManager", "MainMenuExpBar", "ReputationWatchBar" }

-- See-through and click-through rather than hidden: hiding or moving
-- Blizzard's Edit Mode frames from an addon can cause errors there. While
-- the setting is on, the game putting their alpha back is undone at once
-- (hooked), and they stop taking the mouse so they show no tooltips.
local gameBarsHidden = false
local hooked = {}
local savedMouse = {}

local function SetMouseDeep(frame, on)
    if frame.EnableMouse and frame.IsMouseEnabled then
        if on then
            if savedMouse[frame] ~= nil then pcall(frame.EnableMouse, frame, savedMouse[frame]) end
        else
            if savedMouse[frame] == nil then savedMouse[frame] = frame:IsMouseEnabled() end
            pcall(frame.EnableMouse, frame, false)
        end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do SetMouseDeep(child, on) end
    end
end

local function ApplyGameBars()
    local hide = DB and DB.hideGame and true or false
    if not hide and not gameBarsHidden then return end
    if InCombatLockdown() then return end -- mouse changes wait for the fight to end
    for _, n in ipairs(GAME_BARS) do
        local g = _G[n]
        if g and g.SetAlpha then
            if hide and not hooked[g] then
                hooked[g] = true
                hooksecurefunc(g, "SetAlpha", function(self, a)
                    if DB and DB.hideGame and not self.xprbBusy and type(a) == "number" and a > 0 then
                        self.xprbBusy = true
                        self:SetAlpha(0)
                        self.xprbBusy = nil
                    end
                end)
            end
            g.xprbBusy = true
            pcall(g.SetAlpha, g, hide and 0 or 1)
            g.xprbBusy = nil
            SetMouseDeep(g, not hide)
        end
    end
    gameBarsHidden = hide
end

---------------------------------------------------------------------------
-- Hiding the game's party frames (optional). They're protected frames, so
-- see-through isn't safe (they'd stay clickable); instead they're moved
-- into a hidden frame, the way unit-frame addons do it. Only out of combat;
-- a change made in a fight waits until it ends. Turning it off puts them
-- back where they were.
---------------------------------------------------------------------------
local PARTY_FRAMES = { "PartyFrame", "CompactPartyFrame",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local originalParent = {}
local partyPending = false

local function ApplyParty()
    if not DB then return end
    if InCombatLockdown() then partyPending = true return end
    partyPending = false
    for _, n in ipairs(PARTY_FRAMES) do
        local f = _G[n]
        if f and f.SetParent and f.GetParent then
            if DB.hideParty then
                if f:GetParent() ~= hiddenParent then
                    originalParent[f] = f:GetParent()
                    pcall(f.SetParent, f, hiddenParent)
                end
            elseif originalParent[f] then
                pcall(f.SetParent, f, originalParent[f])
                originalParent[f] = nil
            end
        end
    end
end

-- The raid frame manager: the little tab on the left edge with markers and
-- raid tools. Hidden the same way. On clients where the raid frames
-- themselves sit inside it, they're moved out to the screen first, so only
-- the tab goes.
local managerMoved = false
local containerParent

local function ApplyRaidManager()
    if not DB then return end
    if InCombatLockdown() then partyPending = true return end
    local m = _G.CompactRaidFrameManager
    if not (m and m.SetParent) then return end
    local c = _G.CompactRaidFrameContainer
    if DB.hideRaidManager then
        if m:GetParent() ~= hiddenParent then
            if c and c.GetParent and c:GetParent() == m then
                containerParent = m
                pcall(c.SetParent, c, UIParent)
            end
            originalParent[m] = m:GetParent()
            pcall(m.SetParent, m, hiddenParent)
            managerMoved = true
        end
    elseif managerMoved then
        if originalParent[m] then pcall(m.SetParent, m, originalParent[m]) end
        originalParent[m] = nil
        if c and containerParent then pcall(c.SetParent, c, containerParent) end
        containerParent = nil
        managerMoved = false
    end
end

local function UpdateAll()
    if not DB then return end
    Arrange(xpBar)
    Arrange(repBar)
    UpdateXP()
    UpdateRep()
    ApplyGameBars()
    ApplyParty()
    ApplyRaidManager()
    -- Text Only on Mouseover (see UpdateTextShown below; same rule)
    for _, f in ipairs({ xpBar, repBar }) do
        f.text:SetShown(not Look(f.key).hoverText or f.hovered or LEM:IsInEditMode())
    end
end

---------------------------------------------------------------------------
-- Tooltips. The Tooltip setting: "default" = where the game puts its own
-- tooltips, "bar" = just above the bar, "off" = none.
-- Returns true when a tooltip should be filled in.
---------------------------------------------------------------------------
local function TooltipOwner(f)
    local mode = Look(f.key).tooltip
    if mode == "off" then return false end
    if mode == "bar" or not GameTooltip_SetDefaultAnchor then
        GameTooltip:SetOwner(f, "ANCHOR_TOP")
    else
        GameTooltip_SetDefaultAnchor(GameTooltip, f)
    end
    return true
end

xpBar:SetScript("OnEnter", function(self)
    if not xpInfo or not TooltipOwner(self) then return end
    GameTooltip:AddLine("Experience")
    if xpInfo.atMax then
        GameTooltip:AddLine("Max level", 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("XP", Big(xpInfo.cur) .. " / " .. Big(xpInfo.max), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("To level", Big(xpInfo.max - xpInfo.cur), 1, 0.82, 0, 1, 1, 1)
        if xpInfo.rested > 0 then
            GameTooltip:AddDoubleLine("Rested", Big(xpInfo.rested), 1, 0.82, 0, 0.4, 0.6, 1)
        end
    end
    GameTooltip:Show()
end)
repBar:SetScript("OnEnter", function(self)
    if not repInfo or not TooltipOwner(self) then return end
    GameTooltip:AddLine(repInfo.name)
    local c = repInfo.color or { r = 1, g = 1, b = 1 }
    GameTooltip:AddDoubleLine(repInfo.standing, Big(repInfo.cur) .. " / " .. Big(repInfo.max), c.r, c.g, c.b, 1, 1, 1)
    GameTooltip:Show()
end)
xpBar:SetScript("OnLeave", function() GameTooltip:Hide() end)
repBar:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- "Text Only on Mouseover": the bar's text shows while the mouse is on it
-- (always in Edit Mode, so you can see what you're setting)
local function UpdateTextShown(f)
    local l = Look(f.key)
    f.text:SetShown(not l.hoverText or f.hovered or LEM:IsInEditMode())
end
for _, f in ipairs({ xpBar, repBar }) do
    f:HookScript("OnEnter", function(self) self.hovered = true; UpdateTextShown(self) end)
    f:HookScript("OnLeave", function(self) self.hovered = false; UpdateTextShown(self) end)
end

---------------------------------------------------------------------------
-- Quest timeline (XP bar, "Quest Timeline on Mouseover"). Each quest you
-- hand in is noted with its XP and where on the bar it landed. Hovering
-- the XP bar lights each quest's slice in gold along the bar and lists the
-- quests at this level beside it, newest first. Starts fresh each level
-- (the quest that levels you up shows at the start of the new one).
---------------------------------------------------------------------------
local QUEST_COLORS = { { 1, 0.82, 0 }, { 1, 0.55, 0.1 } } -- alternating golds, so neighbours stand apart
local KILL_COLORS  = { { 0.95, 0.25, 0.25 }, { 0.75, 0.12, 0.12 } } -- reds for kill XP
local FOUND_COLORS = { { 1, 0.45, 0.8 }, { 0.85, 0.3, 0.65 } }      -- pinks for discovery XP
local FOUND_ROWS = 3 -- latest areas listed under "Discovered"
local MAX_LINES = 18
local KILL_GROUPS = 5 -- mobs listed under "Kills"

local function CharKey()
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    return (name or UnitName("player") or "?") .. "-" .. (realm or (GetRealmName and GetRealmName()) or "")
end

-- this character's quests at its current level
local function QuestLog()
    DB.quests = DB.quests or {}
    local key, level = CharKey(), UnitLevel("player")
    local q = DB.quests[key]
    if not q or q.level ~= level then
        q = { level = level, list = {} }
        DB.quests[key] = q
    end
    q.kills = q.kills or {}       -- [mob name] = { n = kills, xp = total }
    q.killSegs = q.killSegs or {} -- stretches of the bar filled by kills
    q.found = q.found or {}       -- areas discovered: { name, xp, s, e }
    return q
end

local lastQuestTitle -- the title on the hand-in window, in case the log has forgotten it
local function QuestName(id)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, n = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and not isSecret(n) and type(n) == "string" and n ~= "" then return n end
    end
    return lastQuestTitle or ("Quest " .. tostring(id))
end

local pendingQuest
local function RecordPending()
    local p = pendingQuest
    pendingQuest = nil
    if not p or not DB then return end
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if not Num(cur) or not Num(max) or max <= 0 then return end
    local q = QuestLog()
    table.insert(q.list, { name = p.name, xp = p.xp, s = math.max(0, cur - p.xp), e = cur })
    while #q.list > 40 do table.remove(q.list, 1) end
end

-- A kill: from the game's "<mob> dies, you gain N experience." message.
-- Back-to-back kills join one stretch on the bar.
local function RecordKill(mob, xp)
    if not DB then return end
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if not Num(cur) or not Num(max) or max <= 0 then return end
    local q = QuestLog()
    local k = q.kills[mob] or { n = 0, xp = 0 }
    k.n, k.xp = k.n + 1, k.xp + xp
    q.kills[mob] = k
    local s = math.max(0, cur - xp)
    local last = q.killSegs[#q.killSegs]
    if last and math.abs(last.e - s) <= 1 then
        last.e = cur
    else
        q.killSegs[#q.killSegs + 1] = { s = s, e = cur }
        while #q.killSegs > 150 do table.remove(q.killSegs, 1) end
    end
end

-- A discovered area: from "Discovered <area>: N experience gained".
local function RecordFound(area, xp)
    if not DB then return end
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if not Num(cur) or not Num(max) or max <= 0 then return end
    local q = QuestLog()
    q.found[#q.found + 1] = { name = area, xp = xp, s = math.max(0, cur - xp), e = cur }
    while #q.found > 40 do table.remove(q.found, 1) end
end

local function ParseFound(msg)
    if isSecret(msg) or type(msg) ~= "string" then return nil end
    local area, xp = msg:match("^Discovered (.+): ([%d,]+) experience gained")
    if not area then return nil end
    xp = tonumber((xp:gsub(",", "")))
    if not xp or xp <= 0 then return nil end
    return area, xp
end

-- "%s dies, you gain %d experience." and its rested / group variants
local function ParseKill(msg)
    if isSecret(msg) or type(msg) ~= "string" then return nil end
    local mob, xp = msg:match("^(.+) dies, you gain ([%d,]+) experience")
    if not mob then return nil end
    xp = tonumber((xp:gsub(",", "")))
    if not xp or xp <= 0 then return nil end
    return mob, xp
end

-- the slices on the bar
local segLayer = CreateFrame("Frame", nil, xpBar)
segLayer:SetAllPoints(xpBar.bar)
segLayer:SetFrameLevel(xpBar.bar:GetFrameLevel() + 3) -- above the fill, under the 5% lines
segLayer:Hide()
local segs = {}

local function HideTimeline()
    segLayer:Hide()
end

local function ShowTimeline()
    if not DB then return end
    local l = Look("xp")
    if not l.questTimeline or not xpInfo or xpInfo.atMax then return HideTimeline() end
    local q = QuestLog()
    local list, killSegs, found = q.list, q.killSegs, q.found
    local killCount, killXP = 0, 0
    for _, k in pairs(q.kills) do killCount, killXP = killCount + k.n, killXP + k.xp end
    local foundXP = 0
    for _, e in ipairs(found) do foundXP = foundXP + e.xp end
    if #list == 0 and killCount == 0 and #found == 0 then return HideTimeline() end

    -- slices, positioned along the bar by where the XP landed: kills (red)
    -- first, then quests (gold) on top
    local max = xpInfo.max
    local w, h = xpBar.bar:GetWidth(), xpBar.bar:GetHeight()
    local used = 0
    local function Slice(e, c, minSize)
        minSize = minSize or 1
        used = used + 1
        local t = segs[used]
        if not t then
            t = segLayer:CreateTexture(nil, "ARTWORK")
            segs[used] = t
        end
        t:SetColorTexture(c[1], c[2], c[3], 0.5)
        t:ClearAllPoints()
        local a, b = math.min(e.s, max) / max, math.min(e.e, max) / max
        if l.vertical then
            t:SetPoint("BOTTOMLEFT", segLayer, "BOTTOMLEFT", 0, h * a)
            t:SetSize(w, math.max(minSize, h * (b - a)))
        else
            t:SetPoint("TOPLEFT", segLayer, "TOPLEFT", w * a, 0)
            t:SetSize(math.max(minSize, w * (b - a)), h)
        end
        t:Show()
    end
    -- kills: one clean red fill from the bottom up to where you are (the
    -- per-kill stretches overlapped and looked choppy); quests (gold) and
    -- discoveries (pink breaks) sit on top
    if killCount > 0 then Slice({ s = 0, e = xpInfo.cur }, KILL_COLORS[1]) end
    for i, e in ipairs(list) do Slice(e, QUEST_COLORS[(i - 1) % 2 + 1]) end
    for i, e in ipairs(found) do Slice(e, FOUND_COLORS[(i - 1) % 2 + 1], 2) end -- slivers: at least 2 px
    for i = used + 1, #segs do segs[i]:Hide() end
    segLayer:Show()

    -- the list: quests newest first, then kills grouped by mob
    local questXP = 0
    for _, e in ipairs(list) do questXP = questXP + e.xp end
    local function Pct(x) return math.floor(x / max * 100 + 0.5) end
    local title = ("Level %s: |cffffd100%d%% quests|r, |cffff5555%d%% kills|r"):format(
        tostring(q.level), Pct(questXP), Pct(killXP))
    if #found > 0 then title = title .. (", |cffff73cc%d%% discovery|r"):format(Pct(foundXP)) end
    -- (title goes into the tooltip below)

    local rows = {}
    local groups = {}
    for mob, k in pairs(q.kills) do groups[#groups + 1] = { mob = mob, n = k.n, xp = k.xp } end
    table.sort(groups, function(a, b) return a.xp > b.xp end)
    local killRows = (killCount > 0) and (1 + math.min(#groups, KILL_GROUPS)) or 0
    local foundRows = (#found > 0) and (1 + math.min(#found, FOUND_ROWS)) or 0
    local questRows = math.min(#list, MAX_LINES - killRows - foundRows)
    for i = 1, questRows do
        local e = list[#list - i + 1]
        rows[#rows + 1] = { e.name, "+" .. Big(e.xp), QUEST_COLORS[(#list - i) % 2 + 1] }
    end
    if killCount > 0 then
        rows[#rows + 1] = { ("Kills: %d"):format(killCount), "+" .. Big(killXP), KILL_COLORS[1] }
        for i = 1, math.min(#groups, KILL_GROUPS) do
            local g = groups[i]
            rows[#rows + 1] = { "   " .. g.mob .. " x" .. g.n, "+" .. Big(g.xp), KILL_COLORS[1] }
        end
    end
    if #found > 0 then
        rows[#rows + 1] = { ("Discovered: %d area%s"):format(#found, #found == 1 and "" or "s"),
            "+" .. Big(foundXP), FOUND_COLORS[1] }
        for i = 1, math.min(#found, FOUND_ROWS) do
            local e = found[#found - i + 1] -- newest first
            rows[#rows + 1] = { "   " .. e.name, "+" .. Big(e.xp), FOUND_COLORS[1] }
        end
    end
    -- into the game's tooltip, under the XP lines (the bar's OnEnter has just
    -- filled it; this hook runs after). With the bar's Tooltip set to Off
    -- there's no tooltip, so no list either.
    if GameTooltip:GetOwner() == xpBar and GameTooltip:IsShown() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(title)
        for _, r in ipairs(rows) do
            local c = r[3]
            GameTooltip:AddDoubleLine(r[1], r[2], c[1], c[2], c[3], c[1], c[2], c[3])
        end
        GameTooltip:Show() -- resize to fit
    end
end

xpBar:HookScript("OnEnter", ShowTimeline)
xpBar:HookScript("OnLeave", HideTimeline)

---------------------------------------------------------------------------
-- Playtime milestones (XP bar, "Playtime Milestones on Mouseover"). The
-- game's /played timer is asked once at login and on level-up (its chat
-- message hidden); from then on the time this level is counted here. Each
-- time you pass 10%, 20% ... of the level, that time is noted. Hovering the
-- bar puts a marker and label at each of those spots, plus a green one for
-- now, so the bar reads like a timeline of the level.
---------------------------------------------------------------------------
local levelBase, levelBaseAt -- /played's "this level" seconds, and GetTime() when we got them

local function LevelTime()
    if not levelBase then return nil end
    return levelBase + (GetTime() - levelBaseAt)
end

local function FormatTime(s)
    s = math.floor(s or 0)
    if s < 3600 then return math.max(1, math.floor(s / 60 + 0.5)) .. "m" end
    if s < 86400 then return math.floor(s / 3600) .. "h " .. math.floor(s % 3600 / 60) .. "m" end
    return math.floor(s / 86400) .. "d " .. math.floor(s % 86400 / 3600) .. "h"
end

-- ask /played without its "Total time played" lines appearing in chat
local playedQuiet = false
local function AskPlayed()
    if not RequestTimePlayed then return end
    playedQuiet = true
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.UnregisterEvent then pcall(cf.UnregisterEvent, cf, "TIME_PLAYED_MSG") end
    end
    pcall(RequestTimePlayed)
    -- put the chat frames back even if no answer comes
    C_Timer.After(5, function()
        if not playedQuiet then return end
        playedQuiet = false
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local cf = _G["ChatFrame" .. i]
            if cf and cf.RegisterEvent then pcall(cf.RegisterEvent, cf, "TIME_PLAYED_MSG") end
        end
    end)
end

-- note every 10% mark you've just passed
local function NoteMilestones()
    if not DB then return end
    local t = LevelTime()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if not t or not Num(cur) or not Num(max) or max <= 0 then return end
    local q = QuestLog()
    q.marks = q.marks or {}
    local pct = cur / max * 100
    for m = 10, 90, 10 do
        if pct >= m and not q.marks[m] then q.marks[m] = t end
    end
end

local markLayer = CreateFrame("Frame", nil, xpBar)
markLayer:SetAllPoints(xpBar)
-- the time labels sit above every other window (the bar itself is low)
markLayer:SetFrameStrata("TOOLTIP")
markLayer:SetFrameLevel(200)
markLayer:Hide()
local markPool = {} -- one set of pieces per label: pin, leader lines, icon, text

local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local CROSS = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7"

local function MarkParts(i)
    local m = markPool[i]
    if m then return m end
    m = {
        pin = markLayer:CreateTexture(nil, "OVERLAY"),   -- across the bar, at the real spot
        out = markLayer:CreateTexture(nil, "OVERLAY"),   -- leader: out from the bar
        rise = markLayer:CreateTexture(nil, "OVERLAY"),  -- leader: up/down to a nudged label
        into = markLayer:CreateTexture(nil, "OVERLAY"),  -- leader: into the label
        icon = markLayer:CreateTexture(nil, "OVERLAY"),
        text = markLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
    }
    m.text:SetShadowOffset(1, -1)
    markPool[i] = m
    return m
end

local function HideParts(m)
    m.pin:Hide(); m.out:Hide(); m.rise:Hide(); m.into:Hide(); m.icon:Hide(); m.text:Hide()
end

local function HideMilestones() markLayer:Hide() end

-- The hover timeline, to the right of the bar: playtime at each 10%, now
-- (green), deaths (skull) and close calls (red X). Each label gets a short
-- leader line from the bar at the exact spot it happened; labels that
-- would overlap are nudged apart, the leader bending to reach them.
local function ShowMilestones()
    if not DB or not xpInfo or xpInfo.atMax then return HideMilestones() end
    local l = Look("xp")
    local q = QuestLog()
    local items = {}
    if l.playtime then
        local marks = q.marks or {}
        for m = 10, 90, 10 do
            if marks[m] then items[#items + 1] = { frac = m / 100, text = FormatTime(marks[m]), c = { 0.85, 0.85, 1 } } end
        end
        local now = LevelTime()
        if now then
            items[#items + 1] = { frac = math.min(xpInfo.cur / xpInfo.max, 1), text = FormatTime(now), c = { 0.3, 1, 0.3 } }
        end
    end
    if l.lifeEvents ~= false then
        for _, e in ipairs(q.events or {}) do
            local frac = math.min(e.e / xpInfo.max, 1)
            if e.kind == "death" then
                items[#items + 1] = { frac = frac, icon = SKULL, text = e.by or "died", c = { 1, 0.35, 0.35 } }
            else
                items[#items + 1] = { frac = frac, icon = CROSS, text = (e.left and ("~" .. e.left .. "% HP left") or "close call"),
                    c = { 1, 0.6, 0.3 } }
            end
        end
    end
    if #items == 0 then return HideMilestones() end

    local w, h = xpBar.bar:GetWidth(), xpBar.bar:GetHeight()
    local font = FontPath(l.font)
    local size = math.max(8, l.fontSize - 2)
    for _, it in ipairs(items) do it.y = h * it.frac end

    if l.vertical then
        -- nudge: bottom to top, keep each label a line apart; then from the
        -- top down, keep them on the screen
        local gap = size + 4
        table.sort(items, function(a, b) return a.y < b.y end)
        local last
        for _, it in ipairs(items) do
            it.ly = last and math.max(it.y, last + gap) or it.y
            last = it.ly
        end
        local top = h - gap / 2
        for i = #items, 1, -1 do
            local it = items[i]
            local limit = (i == #items) and top or (items[i + 1].ly - gap)
            if it.ly > limit then it.ly = limit end
        end
    end

    local OUT, BEND = 6, 4 -- leader: out from the bar, then into the label
    for i, it in ipairs(items) do
        local m = MarkParts(i)
        HideParts(m)
        local r, g, b = it.c[1], it.c[2], it.c[3]
        for _, t in ipairs({ m.pin, m.out, m.rise, m.into }) do t:SetColorTexture(r, g, b, 0.8); t:ClearAllPoints() end
        m.text:ClearAllPoints()
        m.icon:ClearAllPoints()
        m.text:SetFont(font, size, "OUTLINE")
        m.text:SetText(it.text)
        m.text:SetTextColor(r, g, b)
        if l.vertical then
            -- a thin line across the bar, at the real spot
            m.pin:SetSize(w, 1)
            m.pin:SetPoint("BOTTOMLEFT", xpBar.bar, "BOTTOMLEFT", 0, it.y)
            m.pin:Show()
            -- leader: out from the bar's edge...
            m.out:SetSize(OUT, 1)
            m.out:SetPoint("BOTTOMLEFT", xpBar, "BOTTOMRIGHT", 0, it.y)
            m.out:Show()
            -- ...bending up or down to a nudged label...
            local dy = it.ly - it.y
            if math.abs(dy) >= 1 then
                m.rise:SetSize(1, math.abs(dy) + 1)
                m.rise:SetPoint("BOTTOMLEFT", xpBar, "BOTTOMRIGHT", OUT, math.min(it.y, it.ly))
                m.rise:Show()
            end
            -- ...and into it
            m.into:SetSize(BEND, 1)
            m.into:SetPoint("BOTTOMLEFT", xpBar, "BOTTOMRIGHT", OUT, it.ly)
            m.into:Show()
            local x = OUT + BEND + 2
            if it.icon then
                m.icon:SetTexture(it.icon)
                m.icon:SetSize(size + 2, size + 2)
                m.icon:SetPoint("LEFT", xpBar, "BOTTOMRIGHT", x, it.ly)
                m.icon:Show()
                x = x + size + 4
            end
            m.text:SetPoint("LEFT", xpBar, "BOTTOMRIGHT", x, it.ly)
            m.text:Show()
        else
            -- a lying bar: a pin across it and the label just below
            m.pin:SetSize(1, h + 6)
            m.pin:SetPoint("BOTTOM", xpBar.bar, "BOTTOMLEFT", w * it.frac, -3)
            m.pin:Show()
            m.text:SetPoint("TOP", xpBar, "BOTTOMLEFT", 1 + w * it.frac, -4)
            m.text:Show()
        end
    end
    for i = #items + 1, #markPool do HideParts(markPool[i]) end
    markLayer:Show()

    local now = LevelTime()
    -- time this level, and the pace, in the tooltip
    if now and GameTooltip:GetOwner() == xpBar and GameTooltip:IsShown() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Time this level", FormatTime(now), 0.3, 1, 0.3, 1, 1, 1)
        local gained = xpInfo.cur
        if now > 60 and gained > 0 then
            local left = (xpInfo.max - xpInfo.cur) / (gained / now)
            GameTooltip:AddDoubleLine("Level up at this pace", "~" .. FormatTime(left), 0.3, 1, 0.3, 1, 1, 1)
        end
        GameTooltip:Show()
    end
end

xpBar:HookScript("OnEnter", ShowMilestones)
xpBar:HookScript("OnLeave", HideMilestones)

local playEvents = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "TIME_PLAYED_MSG", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP" }) do
    pcall(playEvents.RegisterEvent, playEvents, e)
end
playEvents:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_ENTERING_WORLD" then
        if a1 or a2 or not levelBase then C_Timer.After(3, AskPlayed) end -- login or /reload
    elseif event == "TIME_PLAYED_MSG" then
        -- a1 = total played, a2 = this level, in seconds
        if Num(a2) then levelBase, levelBaseAt = a2, GetTime() end
        if playedQuiet then
            playedQuiet = false
            for i = 1, (NUM_CHAT_WINDOWS or 10) do
                local cf = _G["ChatFrame" .. i]
                if cf and cf.RegisterEvent then pcall(cf.RegisterEvent, cf, "TIME_PLAYED_MSG") end
            end
        end
        NoteMilestones()
    elseif event == "PLAYER_LEVEL_UP" then
        levelBase, levelBaseAt = 0, GetTime() -- the level clock starts over
        C_Timer.After(2, AskPlayed)           -- and the game confirms it
    else -- PLAYER_XP_UPDATE
        NoteMilestones()
    end
end)

local questEvents = CreateFrame("Frame")
pcall(questEvents.RegisterEvent, questEvents, "QUEST_TURNED_IN")
pcall(questEvents.RegisterEvent, questEvents, "QUEST_COMPLETE")
pcall(questEvents.RegisterEvent, questEvents, "CHAT_MSG_COMBAT_XP_GAIN")
pcall(questEvents.RegisterEvent, questEvents, "CHAT_MSG_SYSTEM")  -- "Discovered <area>: N experience gained"
pcall(questEvents.RegisterEvent, questEvents, "UI_INFO_MESSAGE")  -- newer clients may say it here instead
local lastFound -- the same discovery can arrive both ways; count it once
questEvents:SetScript("OnEvent", function(_, event, questID, xpReward)
    if event == "CHAT_MSG_SYSTEM" or event == "UI_INFO_MESSAGE" then
        -- the message is the first argument (system) or second (info message)
        local msg = event == "UI_INFO_MESSAGE" and xpReward or questID
        local area, xp = ParseFound(msg)
        if area then
            local key = area .. ":" .. xp
            if lastFound and lastFound.key == key and GetTime() - lastFound.t < 3 then return end
            lastFound = { key = key, t = GetTime() }
            C_Timer.After(0.3, function() RecordFound(area, xp) end)
        end
        return
    end
    if event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local mob, xp = ParseKill(questID) -- (the first argument is the message here)
        -- read where it landed once the game has added the XP
        if mob then C_Timer.After(0.3, function() RecordKill(mob, xp) end) end
        return
    end
    if event == "QUEST_COMPLETE" then
        -- the hand-in window is open: note its title
        local ok, title = pcall(GetTitleText)
        if ok and type(title) == "string" and not isSecret(title) and title ~= "" then lastQuestTitle = title end
        return
    end
    -- QUEST_TURNED_IN: questID, XP reward, money
    if not Num(xpReward) or xpReward <= 0 then return end
    pendingQuest = { name = QuestName(questID), xp = xpReward }
    -- read where the XP landed once the game has added it
    C_Timer.After(0.5, RecordPending)
end)

---------------------------------------------------------------------------
-- Deaths and close calls (XP bar, "Deaths & Close Calls on Mouseover"):
-- a skull on the bar where you died, a red X where you nearly did.
--
-- A death is the game's own PLAYER_DEAD. A close call has to be worked
-- out: this client hides your health from addons, always. So after each
-- fight the game's damage meter is read (its numbers open up once combat
-- ends): the damage you took, less the healing you received, against your
-- maximum health. Under 15% left (estimated) and still alive = a close call. An
-- estimate (the meter has totals, not your lowest moment), the same way
-- social_diary judges them.
---------------------------------------------------------------------------
local CLOSE_CALL = 0.85 -- down at least 85%: under 15% health left (estimated)
local meterAPI = C_DamageMeter
local MT = Enum and Enum.DamageMeterType

local function Tbl(v) if not isSecret(v) and type(v) == "table" then return v end end

local function LatestSession()
    if not (meterAPI and meterAPI.GetAvailableCombatSessions) then return nil end
    local ok, list = pcall(meterAPI.GetAvailableCombatSessions)
    local best
    for _, s in ipairs(ok and Tbl(list) or {}) do
        s = Tbl(s)
        local id = s and s.sessionID
        if Num(id) and (not best or id > best) then best = id end
    end
    return best
end

local function Sources(id, kind)
    if not (MT and MT[kind]) then return nil end
    local ok, session = pcall(meterAPI.GetCombatSessionFromID, id, MT[kind])
    session = ok and Tbl(session)
    return session and Tbl(session.combatSources)
end

local function MyName()
    local n = UnitName("player")
    if isSecret(n) or type(n) ~= "string" then return nil end
    return n
end

local function IsMe(name, me)
    if isSecret(name) or type(name) ~= "string" or not me then return false end
    return (name:match("^[^%-]+") or name) == me
end

-- damage you took in a session; nil while it can't be read
local function TakenIn(id)
    local sources = Sources(id, "DamageTaken")
    if not sources then return nil end
    for _, src in ipairs(sources) do
        src = Tbl(src)
        if src and not isSecret(src.isLocalPlayer) and src.isLocalPlayer == true then
            return Num(src.totalAmount) and src.totalAmount or nil
        end
    end
    return 0
end

-- healing you received in a session, from anyone the meter lists
local function ReceivedIn(id)
    local sources = Sources(id, "HealingDone")
    if not sources then return nil end
    local me, total = MyName(), 0
    for _, src in ipairs(sources) do
        src = Tbl(src)
        if not src then return nil end
        local ok, data = pcall(meterAPI.GetCombatSessionSourceFromID, id, MT.HealingDone, src.sourceGUID, src.sourceCreatureID)
        local spells = ok and Tbl(data) and Tbl(data.combatSpells)
        for _, sp in ipairs(spells or {}) do
            sp = Tbl(sp)
            local d = sp and Tbl(sp.combatSpellDetails)
            if d then
                local alone = isSecret(d.unitName) or isSecret(d.amount) or d.unitName ~= nil or d.amount ~= nil
                if alone then d = { d } end
                for _, t in ipairs(d) do
                    t = Tbl(t)
                    if t and IsMe(t.unitName, me) then
                        local amount = (alone and Num(sp.totalAmount)) and sp.totalAmount or t.amount
                        if Num(amount) then total = total + amount end
                    end
                end
            end
        end
    end
    return total
end

local seen = {} -- per session: what was already judged, so a session that carries on counts only what's new

local function NoteEvent(kind, extra)
    if not DB then return end
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if not Num(cur) or not Num(max) or max <= 0 then return end
    local q = QuestLog()
    q.events = q.events or {}
    local e = { kind = kind, e = cur, when = date("%H:%M") }
    for k, v in pairs(extra or {}) do e[k] = v end
    q.events[#q.events + 1] = e
    while #q.events > 60 do table.remove(q.events, 1) end
end

local function JudgeFight(tries)
    tries = (tries or 0) + 1
    local dead = UnitIsDeadOrGhost("player")
    if not DB or isSecret(dead) or dead then return end
    local id = LatestSession()
    local maxHP = UnitHealthMax("player")
    if not id or not Num(maxHP) or maxHP <= 0 then return end
    local okT, taken = pcall(TakenIn, id)
    local okH, healed = pcall(ReceivedIn, id)
    if not okT then taken = nil end
    if not okH then healed = nil end
    if not taken or not healed then
        if tries < 6 then C_Timer.After(1.5, function() JudgeFight(tries) end) end
        return
    end
    local before = seen[id] or { taken = 0, healed = 0 }
    seen[id] = { taken = taken, healed = healed }
    local lost = math.max(0, (taken - before.taken) - (healed - before.healed))
    if lost >= maxHP * CLOSE_CALL then
        NoteEvent("close", { left = math.max(0, math.floor((1 - lost / maxHP) * 100 + 0.5)) })
    end
end

local lastFoe -- the last thing you targeted that could attack you, for "killed by"
local deathEvents = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED" }) do
    pcall(deathEvents.RegisterEvent, deathEvents, e)
end
deathEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
        local can = UnitCanAttack("player", "target")
        local name = UnitName("target")
        if not isSecret(can) and can and not isSecret(name) and type(name) == "string" then lastFoe = name end
    elseif event == "PLAYER_DEAD" then
        NoteEvent("death", { by = lastFoe })
    elseif event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(1.5, JudgeFight) -- the meter opens its numbers a moment after
    end
end)

-- deaths and close calls are drawn in the hover timeline (ShowMilestones);
-- here, their lines in the tooltip
local function ShowEvents()
    if not DB or not xpInfo or xpInfo.atMax then return end
    local l = Look("xp")
    if l.lifeEvents == false then return end
    local events = QuestLog().events or {}
    if #events == 0 then return end
    local deaths, closes, killers, closest = 0, 0, {}, nil
    for _, e in ipairs(events) do
        if e.kind == "death" then
            deaths = deaths + 1
            if e.by and not tContains(killers, e.by) then killers[#killers + 1] = e.by end
        else
            closes = closes + 1
            if e.left and (not closest or e.left < closest) then closest = e.left end
        end
    end
    if GameTooltip:GetOwner() == xpBar and GameTooltip:IsShown() then
        GameTooltip:AddLine(" ")
        if deaths > 0 then
            GameTooltip:AddDoubleLine("|T" .. SKULL .. ":14|t Deaths this level", deaths
                .. (#killers > 0 and ("  (" .. table.concat(killers, ", ") .. ")") or ""), 1, 0.4, 0.4, 1, 1, 1)
        end
        if closes > 0 then
            GameTooltip:AddDoubleLine("|T" .. CROSS .. ":14|t Close calls", closes
                .. (closest and ("  (lowest: ~" .. closest .. "% HP)") or ""), 1, 0.6, 0.3, 1, 1, 1)
        end
        GameTooltip:Show()
    end
end

xpBar:HookScript("OnEnter", ShowEvents)

---------------------------------------------------------------------------
-- Quest XP preview (XP bar, "Quest XP Preview": Always / On hover / Off).
-- The quests in your log that are complete and only need handing in, and
-- the XP they'll give: a pale gold block sits on top of your current XP
-- showing where you'll land, and the tooltip lists them.
---------------------------------------------------------------------------
local ready = { list = {}, xp = 0, unknown = 0 } -- refreshed from the quest log

-- the XP a quest in your log will give; nil when this client won't say
local function RewardXP(questID, index)
    if not GetQuestLogRewardXP then return nil end
    local ok, v = pcall(GetQuestLogRewardXP, questID)
    if ok and Num(v) and v > 0 then return v end
    -- older form: reads the selected quest, so select it and put it back
    if index and SelectQuestLogEntry then
        local prev = GetQuestLogSelection and GetQuestLogSelection()
        pcall(SelectQuestLogEntry, index)
        ok, v = pcall(GetQuestLogRewardXP)
        if prev then pcall(SelectQuestLogEntry, prev) end
        if ok and Num(v) and v > 0 then return v end
    end
    return nil
end

local function ReadReady()
    local list, total, unknown = {}, 0, 0
    local n = 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local ok, a = pcall(C_QuestLog.GetNumQuestLogEntries)
        if ok and Num(a) then n = a end
    elseif GetNumQuestLogEntries then
        local ok, a = pcall(GetNumQuestLogEntries)
        if ok and Num(a) then n = a end
    end
    for i = 1, n do
        local id, title, header, done
        if C_QuestLog and C_QuestLog.GetInfo then
            local ok, info = pcall(C_QuestLog.GetInfo, i)
            if ok and type(info) == "table" then
                id, title, header = info.questID, info.title, info.isHeader
                if id and C_QuestLog.IsComplete then
                    local ok2, c = pcall(C_QuestLog.IsComplete, id)
                    done = ok2 and c == true
                end
            end
        elseif GetQuestLogTitle then
            local ok, t, _, _, isHeader, _, isComplete, _, qid = pcall(GetQuestLogTitle, i)
            if ok then id, title, header, done = qid, t, isHeader, isComplete == 1 end
        end
        if not header and done and Num(id) then
            local xp = RewardXP(id, i)
            list[#list + 1] = { title = type(title) == "string" and title or ("Quest " .. id), xp = xp }
            if xp then total = total + xp else unknown = unknown + 1 end
        end
    end
    table.sort(list, function(a, b) return (a.xp or 0) > (b.xp or 0) end)
    ready = { list = list, xp = total, unknown = unknown }
end

-- the pale gold block, just above the XP you have
local previewLayer = CreateFrame("Frame", nil, xpBar)
previewLayer:SetAllPoints(xpBar.bar)
previewLayer:SetFrameLevel(xpBar.bar:GetFrameLevel() + 2) -- over the fill, under the timeline
-- faint: a whisper of fill and a thin outline around where you'd land
local preview = previewLayer:CreateTexture(nil, "ARTWORK")
preview:SetColorTexture(1, 0.85, 0.35, 0.07)
local outline = {}
for i = 1, 4 do
    local t = previewLayer:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 0.85, 0.35, 0.45)
    outline[i] = t
end
local previewHover = false

local function DrawPreview()
    preview:Hide()
    for _, t in ipairs(outline) do t:Hide() end
    if not DB or not xpInfo or xpInfo.atMax or ready.xp <= 0 then return end
    local l = Look("xp")
    local mode = l.questPreview or "always"
    if mode == "off" or (mode == "hover" and not previewHover) then return end
    local cur, max = xpInfo.cur, xpInfo.max
    local a, b = math.min(cur / max, 1), math.min((cur + ready.xp) / max, 1)
    if b <= a then return end
    local w, h = xpBar.bar:GetWidth(), xpBar.bar:GetHeight()
    preview:ClearAllPoints()
    if l.vertical then
        preview:SetPoint("BOTTOMLEFT", previewLayer, "BOTTOMLEFT", 0, h * a)
        preview:SetSize(w, math.max(1, h * (b - a)))
    else
        preview:SetPoint("TOPLEFT", previewLayer, "TOPLEFT", w * a, 0)
        preview:SetSize(math.max(1, w * (b - a)), h)
    end
    -- the outline hugs the faint fill: top, bottom, left, right edges, 1 px
    local top, bottom, left, right = outline[1], outline[2], outline[3], outline[4]
    for _, t in ipairs(outline) do t:ClearAllPoints() end
    top:SetPoint("TOPLEFT", preview, "TOPLEFT"); top:SetPoint("TOPRIGHT", preview, "TOPRIGHT"); top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT"); bottom:SetHeight(1)
    left:SetPoint("TOPLEFT", preview, "TOPLEFT"); left:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT"); left:SetWidth(1)
    right:SetPoint("TOPRIGHT", preview, "TOPRIGHT"); right:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT"); right:SetWidth(1)
    preview:Show()
    for _, t in ipairs(outline) do t:Show() end
end

local function PreviewTooltip()
    if not DB or not xpInfo or xpInfo.atMax then return end
    local l = Look("xp")
    if (l.questPreview or "always") == "off" or #ready.list == 0 then return end
    if not (GameTooltip:GetOwner() == xpBar and GameTooltip:IsShown()) then return end
    local cur, max = xpInfo.cur, xpInfo.max
    GameTooltip:AddLine(" ")
    if ready.xp > 0 then
        local after = cur + ready.xp
        local where
        if after >= max then
            where = ("level up! +%d%% into the next"):format(math.floor((after - max) / max * 100 + 0.5))
        else
            where = ("-> %d%%"):format(math.floor(after / max * 100 + 0.5))
        end
        GameTooltip:AddDoubleLine(("Ready to hand in: %d quest%s"):format(#ready.list, #ready.list == 1 and "" or "s"),
            "+" .. Big(ready.xp) .. "  " .. where, 1, 0.85, 0.35, 1, 0.85, 0.35)
    else
        GameTooltip:AddLine(("Ready to hand in: %d quest%s"):format(#ready.list, #ready.list == 1 and "" or "s"), 1, 0.85, 0.35)
    end
    for i = 1, math.min(#ready.list, 8) do
        local q = ready.list[i]
        GameTooltip:AddDoubleLine("   " .. q.title, q.xp and ("+" .. Big(q.xp)) or "?", 1, 0.95, 0.7, 1, 0.95, 0.7)
    end
    if ready.unknown > 0 then
        GameTooltip:AddLine("   (the game doesn't say the XP for " .. ready.unknown .. " of them)", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

xpBar:HookScript("OnEnter", function()
    previewHover = true
    DrawPreview()
    PreviewTooltip()
end)
xpBar:HookScript("OnLeave", function()
    previewHover = false
    DrawPreview()
end)

-- re-read the quest log when it changes (a moment later, so bursts of
-- updates count once)
local previewQueued = false
local function QueuePreview()
    if previewQueued then return end
    previewQueued = true
    C_Timer.After(0.5, function()
        previewQueued = false
        ReadReady()
        DrawPreview()
    end)
end
local previewEvents = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP", "UNIT_QUEST_LOG_CHANGED" }) do
    pcall(previewEvents.RegisterEvent, previewEvents, e)
end
previewEvents:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
    QueuePreview()
end)

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------
local DEFAULT_POS = {
    xp  = { point = "LEFT", x = 5, y = 0 },  -- just right of the rep bar
    rep = { point = "LEFT", x = 0, y = 0 },  -- against the left edge
}

local function Place(f)
    local l = Look(f.key)
    f:ClearAllPoints()
    local p = l.point and l or DEFAULT_POS[f.key]
    f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

local editingKey -- which bar the custom-text popup is for

StaticPopupDialogs["XPREPBARS_CUSTOM_TEXT"] = {
    text = "Your own text for this bar. Use words in curly brackets:\n"
        .. "{cur} {max} {pct} {left}   XP: {level} {rested} {restedpct}   Rep: {name} {standing}",
    button1 = OKAY or "Okay",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    editBoxWidth = 320,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
        if eb and editingKey then eb:SetText(Look(editingKey).custom or ""); eb:HighlightText() end
    end,
    OnAccept = function(self)
        local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
        if eb and editingKey then
            local l = Look(editingKey)
            l.custom = eb:GetText()
            l.text = "custom"
            UpdateAll()
            pcall(LEM.RefreshFrameSettings, LEM, bars[editingKey])
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local accept = StaticPopupDialogs["XPREPBARS_CUSTOM_TEXT"].OnAccept
        accept(parent)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function Setting(key, kind, name, field, extra)
    local s = {
        kind = kind,
        name = name,
        default = DEFAULTS[key][field],
        get = function(layout) layoutName = layout; return Look(key)[field] end,
        set = function(layout, value) layoutName = layout; Look(key)[field] = value; UpdateAll() end,
    }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

local function Register(f)
    local key = f.key
    LEM:AddFrame(f, function(_, layout, point, x, y)
        layoutName = layout
        local l = Look(key)
        l.point, l.x, l.y = point, x, y
    end, DEFAULT_POS[key], f.editModeName)

    local textValues = {}
    for _, p in ipairs(TEXT_PRESETS[key]) do textValues[#textValues + 1] = { text = p[2], value = p[1] } end

    local settings = {
        Setting(key, LEM.SettingType.Checkbox, "Vertical", "vertical", {
            -- standing it up swaps width and height, so it keeps its shape
            set = function(layout, value)
                layoutName = layout
                local l = Look(key)
                if l.vertical ~= value then l.width, l.height = l.height, l.width end
                l.vertical = value
                UpdateAll()
                pcall(LEM.RefreshFrameSettings, LEM, f)
            end,
        }),
        Setting(key, LEM.SettingType.Slider, "Scale", "scale", {
            minValue = 0.5, maxValue = 2, valueStep = 0.05,
            formatter = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
        }),
        Setting(key, LEM.SettingType.Slider, "Width", "width", { minValue = 4, maxValue = 1200, valueStep = 1 }),
        Setting(key, LEM.SettingType.Checkbox, "Fill Screen Height", "fullHeight", {
            set = function(layout, value)
                layoutName = layout
                Look(key).fullHeight = value
                UpdateAll()
                pcall(LEM.RefreshFrameSettings, LEM, f) -- greys Height in and out
            end,
        }),
        Setting(key, LEM.SettingType.Slider, "Height", "height", {
            minValue = 4, maxValue = 1600, valueStep = 1,
            disabled = function() return Look(key).fullHeight end,
        }),
        Setting(key, LEM.SettingType.Dropdown, "Text", "text", { values = textValues }),
        Setting(key, LEM.SettingType.Dropdown, "Font", "font", { values = FontChoices, height = 300 }),
        Setting(key, LEM.SettingType.Slider, "Font Size", "fontSize", { minValue = 6, maxValue = 30, valueStep = 1 }),
        Setting(key, LEM.SettingType.Dropdown, "Font Outline", "outline", { values = OUTLINES }),
        Setting(key, LEM.SettingType.Dropdown, "Text Position", "textPos", { values = POSITIONS }),
        Setting(key, LEM.SettingType.Slider, "Text Nudge Left / Right", "textX", { minValue = -200, maxValue = 200, valueStep = 1 }),
        Setting(key, LEM.SettingType.Slider, "Text Nudge Down / Up", "textY", { minValue = -400, maxValue = 400, valueStep = 1 }),
        Setting(key, LEM.SettingType.Checkbox, "Rotate Text (vertical)", "rotate", {
            disabled = function() return not f.text.SetRotation end,
        }),
        Setting(key, LEM.SettingType.Checkbox, "Text Only on Mouseover", "hoverText"),
        Setting(key, LEM.SettingType.Dropdown, "Tooltip", "tooltip", { values = {
            { text = "Default tooltip spot", value = "default" },
            { text = "Above the bar", value = "bar" },
            { text = "Off", value = "off" },
        } }),
        Setting(key, LEM.SettingType.Checkbox, "Segment Ticks", "ticks"),
    }
    if key == "xp" then
        settings[#settings + 1] = Setting(key, LEM.SettingType.Checkbox, "Show Rested XP", "rested")
        settings[#settings + 1] = Setting(key, LEM.SettingType.Checkbox, "Quest Timeline on Mouseover", "questTimeline")
        settings[#settings + 1] = Setting(key, LEM.SettingType.Checkbox, "Playtime Milestones on Mouseover", "playtime")
        settings[#settings + 1] = Setting(key, LEM.SettingType.Checkbox, "Deaths & Close Calls on Mouseover", "lifeEvents")
        settings[#settings + 1] = Setting(key, LEM.SettingType.Dropdown, "Quest XP Preview", "questPreview", {
            values = {
                { text = "Always", value = "always" }, { text = "On hover", value = "hover" }, { text = "Off", value = "off" },
            },
            set = function(layout, value)
                layoutName = layout
                Look(key).questPreview = value
                UpdateAll()
                DrawPreview()
            end,
        })
        settings[#settings + 1] = Setting(key, LEM.SettingType.Checkbox, "Hide at Max Level", "hideMax")
    end
    -- on both bars' panels; one setting for the account
    settings[#settings + 1] = {
        kind = LEM.SettingType.Checkbox,
        name = "Hide the Game's XP & Rep Bars",
        default = false,
        get = function() return DB and DB.hideGame or false end,
        set = function(_, value)
            if DB then DB.hideGame = value end
            ApplyGameBars()
            for _, other in pairs(bars) do pcall(LEM.RefreshFrameSettings, LEM, other) end
        end,
    }
    settings[#settings + 1] = {
        kind = LEM.SettingType.Checkbox,
        name = "Hide the Game's Party Frames",
        default = false,
        get = function() return DB and DB.hideParty or false end,
        set = function(_, value)
            if DB then DB.hideParty = value end
            ApplyParty()
            for _, other in pairs(bars) do pcall(LEM.RefreshFrameSettings, LEM, other) end
        end,
    }
    settings[#settings + 1] = {
        kind = LEM.SettingType.Checkbox,
        name = "Hide the Raid Manager Tab",
        desc = "The little tab on the left edge with markers and raid tools.",
        default = false,
        get = function() return DB and DB.hideRaidManager or false end,
        set = function(_, value)
            if DB then DB.hideRaidManager = value end
            ApplyRaidManager()
            for _, other in pairs(bars) do pcall(LEM.RefreshFrameSettings, LEM, other) end
        end,
    }
    LEM:AddFrameSettings(f, settings)
    LEM:AddFrameSettingsButton(f, {
        text = "Edit Custom Text...",
        click = function()
            editingKey = key
            StaticPopup_Show("XPREPBARS_CUSTOM_TEXT")
        end,
    })
end

Register(xpBar)
Register(repBar)

LEM:RegisterCallback("layout", function(layout)
    layoutName = layout
    Place(xpBar)
    Place(repBar)
    UpdateAll()
end)
LEM:RegisterCallback("enter", UpdateAll)
LEM:RegisterCallback("exit", UpdateAll)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
SLASH_XPREPBARS1 = "/xpbars"
SlashCmdList.XPREPBARS = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if not DB then return end
    local tabCmd = msg:match("^raidtab%s+(%a+)$")
    if tabCmd == "hide" or tabCmd == "show" then
        DB.hideRaidManager = (tabCmd == "hide")
        ApplyRaidManager()
        print("|cffc79c6eXP & Rep Bars|r the raid manager tab is " .. (DB.hideRaidManager and "hidden" or "back")
            .. (InCombatLockdown() and " after this fight." or "."))
        return
    end
    local partyCmd = msg:match("^party%s+(%a+)$")
    if partyCmd == "hide" or partyCmd == "show" then
        DB.hideParty = (partyCmd == "hide")
        ApplyParty()
        print("|cffc79c6eXP & Rep Bars|r the game's party frames are " .. (DB.hideParty and "hidden" or "back")
            .. (InCombatLockdown() and " after this fight." or "."))
        return
    end
    if msg == "hide" or msg == "show" then
        DB.hideGame = (msg == "hide")
        ApplyGameBars()
        print("|cffc79c6eXP & Rep Bars|r the game's own bars are " .. (DB.hideGame and "hidden" or "back")
            .. (InCombatLockdown() and " after this fight." or "."))
    else
        print("|cffc79c6eXP & Rep Bars|r /xpbars hide|show (the game's XP bars), /xpbars party hide|show (party frames), /xpbars raidtab hide|show (the raid manager tab). Everything else is in Edit Mode.")
    end
end

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE",
    "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
    "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING", "UPDATE_FACTION", "CHAT_MSG_COMBAT_FACTION_CHANGE",
    "DISABLE_XP_GAIN", "ENABLE_XP_GAIN", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
    pcall(events.RegisterEvent, events, e) -- some aren't in every client
end
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_CompactRaidFrames" then -- the raid manager can load after us
            if DB and DB.hideRaidManager then ApplyRaidManager() end
            return
        end
        if arg1 ~= "Spliffbars" then return end
        XPRepBarsDB = XPRepBarsDB or {}
        DB = XPRepBarsDB
        -- 2.4-2.5 had skill bars that pushed the XP bar right; they're gone,
        -- so (once) put the XP bar back against the rep bar
        if not DB.skillsRemoved then
            DB.skillsRemoved = true
            for _, layout in pairs(DB.layouts or {}) do
                local x, r = layout.xp, layout.rep
                if x and r and x.point == "LEFT" and (r.point or "LEFT") == "LEFT" and Num(x.x) and x.x > 5 and x.x < 60 then
                    x.x = (r.x or 0) + (r.width or 6) - 1
                end
            end
        end
        -- once: the quest XP preview shows only while hovering the bar
        if not DB.previewHoverSet then
            DB.previewHoverSet = true
            for _, layout in pairs(DB.layouts or {}) do
                if layout.xp then layout.xp.questPreview = "hover" end
            end
        end
        return
    end
    if not DB then return end
    if event == "PLAYER_ENTERING_WORLD" then
        Place(xpBar)
        Place(repBar)
        UpdateAll()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ApplyGameBars() -- anything that had to wait for the fight
        if partyPending or DB.hideParty then ApplyParty() end
        ApplyRaidManager()
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- raid-style party frames can be made when a group forms
        if DB.hideParty then ApplyParty() end
        if DB.hideRaidManager then ApplyRaidManager() end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        UpdateAll() -- "Fill Screen Height" follows the new screen size
        DrawPreview()
    elseif event == "UPDATE_FACTION" or event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        UpdateRep()
    else
        UpdateXP()
    end
end)
