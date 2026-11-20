-- Spliff Frames: unit frames for the Spliff package.
--
-- A Spliffbars module: it loads only when switched on in Spliffbars'
-- options (Modules), so while it's off none of this runs and the game's
-- own frames are left alone. Shared bits (fonts, smooth fills, Edit Mode,
-- the option switches) come from Spliffbars through the global Spliffbars.
--
-- Frames: you, your target, and your target's target. Each has a health
-- bar (class colour for players, friend / foe colour for the rest) and a
-- power bar under it, with name, level and health text, in Spliffbars'
-- look (dark rim, smooth gradient fills). Click to target, right-click for
-- the unit's menu. The target frame's rim turns gold for elites and silver
-- for rares, and shows combo points; yours shows when you're in combat or
-- resting. Each moves and sets up in Edit Mode.
--
-- This client can hide health and power numbers from addons. The bars
-- are filled by the game itself, so they always work; the text shows what
-- the game allows and stays blank otherwise.

local _, ns = ...
local S = Spliffbars -- the hub (Spliffbars\Core.lua)
local LEM, isSecret, Num = S.LEM, S.isSecret, S.Num

---------------------------------------------------------------------------
-- The frames and their settings
---------------------------------------------------------------------------
local UNITS = {
    player = { label = "Spliff Frames: Player", piece = "Player Frame",
        width = 230, height = 46, power = 10, pos = { point = "CENTER", x = -300, y = -190 } },
    target = { label = "Spliff Frames: Target", piece = "Target Frame",
        width = 230, height = 46, power = 10, pos = { point = "CENTER", x = 300, y = -190 } },
    targettarget = { label = "Spliff Frames: Target of Target", piece = "Target of Target Frame",
        width = 130, height = 26, power = 5, pos = { point = "CENTER", x = 490, y = -215 } },
    -- the four party frames share one set of settings ("party") and stack
    -- under one anchor that moves in Edit Mode
    party = { label = "Spliff Frames: Party", piece = "Party Frames",
        width = 180, height = 36, power = 6, pos = { point = "LEFT", x = 30, y = 120 } },
}
local ORDER = { "player", "target", "targettarget" }
local PARTY = { "party1", "party2", "party3", "party4" }

-- the settings a unit uses: each party member uses the party's
local function KeyOf(unit)
    if type(unit) == "string" and unit:match("^party%d$") then return "party" end
    return unit
end

local function Defaults(unit)
    local u = UNITS[unit]
    return { width = u.width, height = u.height, power = u.power, font = "Game default",
        fontSize = unit == "targettarget" and 10 or 12, healthText = unit == "targettarget" and "none" or "both",
        classColor = true, showLevel = unit ~= "targettarget", hidden = false,
        -- portrait: "3d" (the model), "2d" (the game's round picture) or "off";
        -- on the outer side: yours on the left, the target's on the right
        portrait = unit == "targettarget" and "off" or "3d",
        portraitSide = (unit == "player" or unit == "party") and "left" or "right",
        heals = true, -- incoming heals: a see-through green strip past the health
        powerText = "none", -- on the power bar: "both", "current", "percent" or "none"
        powerTextPos = "center", powerTextY = 0, -- left, centre or right on it, and nudged up / down
        castBar = unit == "target", castHeight = 15, castGap = 4, -- (the target's: enemy casts above it)
        auras = unit ~= "targettarget", -- buffs above (allies), debuffs below (everyone); party: debuffs to the right
        spacing = 14, -- (the party's: the gap between its frames)
        showRole = unit == "party", -- (the party's: the role they chose for the group, on their portrait)
        showPvP = unit == "player", -- the PvP flag (faction, or free-for-all) on the portrait's bottom corner
        stanceTabs = unit == "player", -- (yours: your stances as tabs on the health bar's top edge, Stance.lua)
        syncSize = false } -- (kept on the player's: player and target the same size)
end
local DEFAULTS = {}
for unit in pairs(UNITS) do DEFAULTS[unit] = Defaults(unit) end

local DB, layoutName
local function Look(unit)
    local key = KeyOf(unit)
    return S.Look(DB, layoutName, key, DEFAULTS[key])
end
ns.Look = Look -- (Stance.lua reads your frame's settings)

-- run now, or once the fight is over (secure frames can't change in combat)
local queue = {}
local function OutOfCombat(fn)
    if InCombatLockdown() then queue[#queue + 1] = fn else fn() end
end

---------------------------------------------------------------------------
-- Reading the unit (each value checked: a hidden one can't be compared)
---------------------------------------------------------------------------
-- call f, passing on everything it returns (nothing if it errors)
local function Pack(ok, ...)
    if ok then return ... end
end
local function Safe(f, ...) return Pack(pcall(f, ...)) end

-- tests that never touch a hidden value (comparing or testing one is an error)
local function IsTrue(v) return not isSecret(v) and v == true end
local function IsFalse(v) return not isSecret(v) and v == false end
local function Present(v) return isSecret(v) or v ~= nil end

local function ClassColor(unit)
    local _, class = Safe(UnitClass, unit)
    if isSecret(class) or type(class) ~= "string" then return nil end
    local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    return c and { c.r, c.g, c.b }
end

local function HealthColor(unit, l)
    if UnitIsTapDenied and IsTrue(Safe(UnitIsTapDenied, unit)) then return { 0.5, 0.5, 0.5 } end
    if l.classColor and IsTrue(Safe(UnitIsPlayer, unit)) then
        local c = ClassColor(unit)
        if c then return c end
    end
    local reaction = Safe(UnitReaction, unit, "player")
    if Num(reaction) and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction] then
        local c = FACTION_BAR_COLORS[reaction]
        return { c.r, c.g, c.b }
    end
    return { 0.2, 0.8, 0.25 }
end

local function PowerColor(unit)
    local ptype, token = Safe(UnitPowerType, unit)
    if isSecret(token) then token = nil end
    local c = PowerBarColor and ((token and PowerBarColor[token]) or (Num(ptype) and PowerBarColor[ptype]))
    if c and c.r then return { c.r, c.g, c.b } end
    return { 0.2, 0.4, 0.9 }
end

-- health text: "12.3K", "85%", both, or none, as far as the game lets us
local function Short(v)
    if AbbreviateNumbers then
        local ok, s = pcall(AbbreviateNumbers, v)
        if ok then return s end
    end
    if Num(v) then return S.Big(v) end
    return nil
end

-- the text for a mode from an amount and a percent, either possibly hidden
-- (a hidden string can be shown or joined, never tested: so no "a or b")
local function Combine(mode, amount, pct)
    if mode == "current" then
        if Present(amount) then return amount end
        return ""
    end
    if mode == "percent" then
        if Present(pct) then return pct end
        return ""
    end
    if Present(amount) and Present(pct) then
        local ok, s = pcall(string.format, "%s  %s", amount, pct)
        if ok then return s end
    end
    if Present(amount) then return amount end
    if Present(pct) then return pct end
    return ""
end

local function HealthText(unit, mode)
    if mode == "none" then return "" end
    if IsTrue(Safe(UnitIsDeadOrGhost, unit)) then
        return IsTrue(Safe(UnitIsGhost, unit)) and "Ghost" or "Dead"
    end
    if IsFalse(Safe(UnitIsConnected, unit)) then return "Offline" end
    local cur, max = Safe(UnitHealth, unit), Safe(UnitHealthMax, unit)
    local pct
    if Num(cur) and Num(max) and max > 0 then
        pct = math.floor(cur / max * 100 + 0.5) .. "%"
    elseif UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        -- the game works out the percent itself, hidden numbers and all
        local ok, p = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
        if ok and Present(p) then
            local ok2, s = pcall(string.format, "%d%%", p)
            if ok2 then pct = s end
        end
    end
    local amount
    if Present(cur) then amount = Short(cur) end
    return Combine(mode, amount, pct)
end

-- power text, the same way: "4.2K", "62%", both, or none
local function PowerText(unit, mode)
    if mode == "none" then return "" end
    local cur, max = Safe(UnitPower, unit), Safe(UnitPowerMax, unit)
    if Num(max) and max <= 0 then return "" end -- (no power bar to speak of)
    local pct
    if Num(cur) and Num(max) then
        pct = math.floor(cur / max * 100 + 0.5) .. "%"
    elseif UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, p = pcall(UnitPowerPercent, unit, nil, true, CurveConstants.ScaleTo100)
        if ok and Present(p) then
            local ok2, s = pcall(string.format, "%d%%", p)
            if ok2 then pct = s end
        end
    end
    local amount
    if Present(cur) then amount = Short(cur) end
    return Combine(mode, amount, pct)
end

---------------------------------------------------------------------------
-- Building a frame
---------------------------------------------------------------------------
local frames = {}
ns.frames = frames -- (Stance.lua puts its tabs on yours)

local function NewBar(parent)
    local sb = CreateFrame("StatusBar", nil, parent)
    S.SmoothFill(sb)
    return sb
end

local function Build(unit)
    local u = UNITS[KeyOf(unit)]
    local f = CreateFrame("Button", "SpliffFrames_" .. unit, UIParent, "SecureUnitButtonTemplate")
    f.unit = unit
    f.partyIndex = tonumber(unit:match("^party(%d)$")) -- (1-4 for the party's frames)
    f.editModeName = u.label
    f:SetClampedToScreen(true)
    f:SetFrameStrata("LOW")
    f:SetAttribute("unit", unit)
    f:SetAttribute("type1", "target")
    f:SetAttribute("type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    f:SetSize(u.width, u.height)

    -- the rim (tinted for elites and rares) and the dark inside
    f.edge = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.edge:SetAllPoints()
    f.edge:SetColorTexture(0, 0, 0, 0.9)
    f.rim = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.rim:SetPoint("TOPLEFT", 1, -1)
    f.rim:SetPoint("BOTTOMRIGHT", -1, 1)
    f.inside = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    f.inside:SetPoint("TOPLEFT", 2, -2)
    f.inside:SetPoint("BOTTOMRIGHT", -2, 2)
    f.inside:SetColorTexture(0.06, 0.06, 0.08, 0.92)

    f.health = NewBar(f)
    f.power = NewBar(f)

    -- incoming heals: a strip that starts where the health fill ends,
    -- clipped to the health bar so a big heal stops at full
    f.healClip = CreateFrame("Frame", nil, f.health)
    f.healClip:SetAllPoints(f.health)
    f.healClip:SetClipsChildren(true)
    f.healClip:SetFrameLevel(f.health:GetFrameLevel() + 2)
    f.heal = CreateFrame("StatusBar", nil, f.healClip)
    f.heal:SetStatusBarTexture(S.WHITE)
    f.heal:SetStatusBarColor(0.25, 1, 0.45, 0.45)
    f.heal:SetPoint("TOPLEFT", f.health:GetStatusBarTexture(), "TOPRIGHT")
    f.heal:SetPoint("BOTTOMLEFT", f.health:GetStatusBarTexture(), "BOTTOMRIGHT")
    f.heal:Hide()
    -- a bandage's healing still to come: brighter, just past the incoming
    -- heals, flashing as each tick lands
    f.band = CreateFrame("StatusBar", nil, f.healClip)
    f.band:SetStatusBarTexture(S.WHITE)
    f.band:SetStatusBarColor(0.5, 1, 0.55, 0.6)
    f.band:SetPoint("TOPLEFT", f.heal:GetStatusBarTexture(), "TOPRIGHT")
    f.band:SetPoint("BOTTOMLEFT", f.heal:GetStatusBarTexture(), "BOTTOMRIGHT")
    f.band:Hide()
    -- this client's heal prediction: a calculator the game fills for a unit
    -- (as HealBot does on Forever), capped at the health that's missing
    if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
        local ok, calc = pcall(CreateUnitHealPredictionCalculator)
        if ok and calc then
            if calc.SetIncomingHealClampMode and Enum and Enum.UnitIncomingHealClampMode then
                pcall(calc.SetIncomingHealClampMode, calc, Enum.UnitIncomingHealClampMode.MissingHealth)
            end
            if calc.SetIncomingHealOverflowPercent then pcall(calc.SetIncomingHealOverflowPercent, calc, 1) end
            f.calc = calc
        end
    end

    -- the portrait: a square at one end, the 3D model or the 2D picture,
    -- with a thin line between it and the bars
    f.pbox = CreateFrame("Frame", nil, f)
    f.pbox:SetFrameLevel(f.health:GetFrameLevel())
    f.pbg = f.pbox:CreateTexture(nil, "BACKGROUND")
    f.pbg:SetAllPoints()
    f.pbg:SetColorTexture(0.1, 0.1, 0.13, 1)
    f.model = CreateFrame("PlayerModel", nil, f.pbox)
    f.model:SetAllPoints()
    f.ptex = f.pbox:CreateTexture(nil, "ARTWORK")
    f.ptex:SetAllPoints()
    f.ptex:SetTexCoord(0.12, 0.88, 0.12, 0.88) -- the round picture, squared
    f.pline = f:CreateTexture(nil, "BORDER")
    f.pline:SetColorTexture(0, 0, 0, 0.9)
    f.pline:SetWidth(1)

    -- text and icons above the bars
    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints()
    over:SetFrameLevel(f.health:GetFrameLevel() + 5)
    f.over = over
    f.name = over:CreateFontString(nil, "OVERLAY")
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.level = over:CreateFontString(nil, "OVERLAY")
    f.hp = over:CreateFontString(nil, "OVERLAY")
    f.hp:SetJustifyH("RIGHT")
    f.hp:SetWordWrap(false)
    f.pp = over:CreateFontString(nil, "OVERLAY") -- power text, on the power bar
    f.pp:SetWordWrap(false)
    -- the PvP flag: placed on the portrait's top corner (Arrange)
    f.pvp = over:CreateTexture(nil, "OVERLAY", nil, 2)
    f.pvp:SetTexCoord(0, 0.62, 0, 0.62) -- (the badge sits in the top-left of the game's picture)
    f.pvp:Hide()
    -- hovering it: how long the flag has left. Mouse-over only, so clicks
    -- still reach the frame underneath (target, menu).
    f.pvpHover = CreateFrame("Frame", nil, over)
    f.pvpHover:SetAllPoints(f.pvp)
    f.pvpHover:SetFrameLevel(over:GetFrameLevel() + 3)
    if f.pvpHover.SetMouseClickEnabled then
        f.pvpHover:SetMouseClickEnabled(false)
        f.pvpHover:SetMouseMotionEnabled(true)
    end
    f.pvpHover:Hide()
    if f.partyIndex then
        -- the role they chose for the group (tank, healer, damage): placed
        -- in the portrait's bottom-left corner (Arrange)
        f.role = over:CreateTexture(nil, "OVERLAY")
        f.role:Hide()
    end
    f.raid = over:CreateTexture(nil, "OVERLAY")
    f.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.raid:SetSize(16, 16)
    f.raid:SetPoint("CENTER", f, "TOP", 0, 0)
    f.raid:Hide()

    if unit == "player" then
        -- in combat: crossed swords; resting: the game's "zzz"
        f.state = over:CreateTexture(nil, "OVERLAY")
        f.state:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
        f.state:SetSize(18, 18)
        f.state:SetPoint("CENTER", f, "TOPLEFT", 2, -2)
        f.state:Hide()
    elseif unit == "target" then
        -- combo points: small pips inside the top edge, at the right (above
        -- the frame is the cast bar's)
        f.pips = {}
        for i = 1, 5 do
            local p = over:CreateTexture(nil, "OVERLAY")
            p:SetColorTexture(1, 0.85, 0.25, 1)
            p:SetSize(8, 3)
            p:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4 - (5 - i) * 10, -3)
            p:Hide()
            f.pips[i] = p
        end
    end

    if f.EnableMouseMotion then f:EnableMouseMotion(true) end
    f:SetScript("OnEnter", function(self)
        if UnitFrame_OnEnter then pcall(UnitFrame_OnEnter, self) return end
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:SetUnit(self.unit)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function(self)
        if UnitFrame_OnLeave then pcall(UnitFrame_OnLeave, self) return end
        GameTooltip:Hide()
    end)
    frames[unit] = f
    return f
end

for _, unit in ipairs(ORDER) do Build(unit) end
for _, unit in ipairs(PARTY) do Build(unit) end

-- the PvP flag's tooltip: yours says how long it has left (ticking while
-- you hover); anyone else's just that they're flagged (the game doesn't
-- say their time)
local function PvPTime(ms)
    local s = math.max(0, math.floor(ms / 1000))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function PvPTooltip(hover)
    local f = hover:GetParent():GetParent() -- (over, then the frame)
    local unit = f.unit
    GameTooltip:SetOwner(hover, "ANCHOR_RIGHT")
    if IsTrue(Safe(UnitIsPVPFreeForAll, unit)) then
        GameTooltip:AddLine("Free-for-all PvP", 1, 0.3, 0.3)
        GameTooltip:AddLine("Anyone here can attack you, and you them.", 1, 1, 1, true)
    elseif unit == "player" then
        GameTooltip:AddLine("Flagged for PvP", 1, 0.82, 0)
        local running = IsPVPTimerRunning and Safe(IsPVPTimerRunning)
        local ms = GetPVPTimer and Safe(GetPVPTimer)
        if IsTrue(running) and Num(ms) then
            GameTooltip:AddDoubleLine("Time left", PvPTime(ms), 1, 1, 1, 0.4, 1, 0.4)
            GameTooltip:AddLine("Attacking or helping flagged players starts it over.", 0.7, 0.7, 0.7, true)
        else
            GameTooltip:AddLine("Staying on: you turned it on, or you're somewhere that keeps it on.", 1, 1, 1, true)
            GameTooltip:AddLine("Type /pvp to let it run out (5 minutes, once you stop fighting).", 0.7, 0.7, 0.7, true)
        end
    else
        GameTooltip:AddLine("Flagged for PvP", 1, 0.82, 0)
    end
    GameTooltip:Show()
end

for _, f in pairs(frames) do
    f.pvpHover:SetScript("OnEnter", function(self)
        PvPTooltip(self)
        -- keep the time ticking while the mouse stays
        local since = 0
        self:SetScript("OnUpdate", function(s, elapsed)
            since = since + elapsed
            if since < 0.5 then return end
            since = 0
            if GameTooltip:GetOwner() == s then PvPTooltip(s) end
        end)
    end)
    f.pvpHover:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end)
end

-- the party's anchor: the frames stack down from its top-left; it's what
-- moves in Edit Mode (sized to cover all four)
local partyAnchor = CreateFrame("Frame", "SpliffFrames_PartyAnchor", UIParent)
partyAnchor.editModeName = UNITS.party.label
partyAnchor:SetClampedToScreen(true)
partyAnchor:SetSize(UNITS.party.width, UNITS.party.height * 4)

---------------------------------------------------------------------------
-- Layout and painting
---------------------------------------------------------------------------
local RIM = { 0.28, 0.28, 0.32 }
local RIM_ELITE = { 1, 0.78, 0.25 }
local RIM_RARE = { 0.8, 0.85, 0.95 }

-- the name runs from just after the role icon (when one's showing), else
-- after the level, else the bar's left end, up to the health text
local function PlaceName(f)
    local l = Look(f.unit)
    f.name:ClearAllPoints()
    if f.role and f.role:IsShown() then
        f.name:SetPoint("LEFT", f.role, "RIGHT", 3, 0)
    elseif l.showLevel then
        f.name:SetPoint("LEFT", f.level, "RIGHT", 4, 0)
    else
        f.name:SetPoint("LEFT", f.health, "LEFT", 5, 0)
    end
    f.name:SetPoint("RIGHT", f.hp, "LEFT", -6, 0)
end

local function Arrange(f)
    local l = Look(f.unit)
    local ph = math.min(l.power, l.height - 10)
    -- the portrait takes a square at one end; the bars fill the rest
    local left, right = 2, 2
    f.pbox:ClearAllPoints()
    f.pline:ClearAllPoints()
    if l.portrait ~= "off" then
        local size = l.height - 4
        f.pbox:SetSize(size, size)
        if l.portraitSide == "right" then
            f.pbox:SetPoint("TOPRIGHT", -2, -2)
            f.pline:SetPoint("TOPRIGHT", f.pbox, "TOPLEFT")
            f.pline:SetPoint("BOTTOMRIGHT", f.pbox, "BOTTOMLEFT")
            right = 2 + size + 1
        else
            f.pbox:SetPoint("TOPLEFT", 2, -2)
            f.pline:SetPoint("TOPLEFT", f.pbox, "TOPRIGHT")
            f.pline:SetPoint("BOTTOMLEFT", f.pbox, "BOTTOMRIGHT")
            left = 2 + size + 1
        end
        f.pbox:Show()
        f.pline:Show()
    else
        f.pbox:Hide()
        f.pline:Hide()
    end
    f.portraitMode = nil -- (asks UpdatePortrait to draw it afresh)
    f.health:ClearAllPoints()
    f.health:SetPoint("TOPLEFT", left, -2)
    f.health:SetPoint("TOPRIGHT", -right, -2)
    f.health:SetPoint("BOTTOM", f, "BOTTOM", 0, 2 + (ph > 0 and (ph + 1) or 0))
    f.heal:SetWidth(math.max(1, l.width - left - right)) -- as long as the health bar
    f.band:SetWidth(math.max(1, l.width - left - right))
    f.power:ClearAllPoints()
    f.power:SetPoint("BOTTOMLEFT", left, 2)
    f.power:SetPoint("BOTTOMRIGHT", -right, 2)
    f.power:SetHeight(math.max(1, ph))
    f.power:SetShown(ph > 0)
    S.ApplyFont(f.name, l.font, l.fontSize, "OUTLINE")
    S.ApplyFont(f.level, l.font, l.fontSize, "OUTLINE")
    S.ApplyFont(f.hp, l.font, l.fontSize, "OUTLINE")
    f.level:ClearAllPoints()
    f.level:SetPoint("LEFT", f.health, "LEFT", 5, 0)
    f.level:SetShown(l.showLevel)
    if f.role then
        -- the role icon: right after the level (or where the level would be)
        local s = l.fontSize + 2
        f.role:SetSize(s, s)
        f.role:ClearAllPoints()
        if l.showLevel then f.role:SetPoint("LEFT", f.level, "RIGHT", 3, 0)
        else f.role:SetPoint("LEFT", f.health, "LEFT", 5, 0) end
    end
    f.hp:ClearAllPoints()
    f.hp:SetPoint("RIGHT", f.health, "RIGHT", -5, 0)
    -- power text: small, in the middle of the power bar (a thin bar gets
    -- small text that spills over it a little)
    S.ApplyFont(f.pp, l.font, math.max(7, math.min(l.fontSize - 1, ph + 3)), "OUTLINE")
    f.pp:ClearAllPoints()
    local ny = l.powerTextY or 0
    if l.powerTextPos == "left" then
        f.pp:SetPoint("LEFT", f.power, "LEFT", 4, ny)
    elseif l.powerTextPos == "right" then
        f.pp:SetPoint("RIGHT", f.power, "RIGHT", -4, ny)
    else
        f.pp:SetPoint("CENTER", f.power, "CENTER", 0, ny)
    end
    f.pp:SetShown(ph > 0 and l.powerText ~= "none")
    -- the PvP flag: on the portrait's outer bottom corner, hanging off the
    -- frame a little like the game's own (the top corner is the combat /
    -- resting icon's); with no portrait, the frame's bottom corner
    local ps = math.max(16, math.floor(l.height * 0.7))
    f.pvp:SetSize(ps, ps)
    f.pvp:ClearAllPoints()
    if l.portrait ~= "off" and l.portraitSide == "right" then
        f.pvp:SetPoint("CENTER", f.pbox, "BOTTOMRIGHT", -ps * 0.1, ps * 0.1)
    elseif l.portrait ~= "off" then
        f.pvp:SetPoint("CENTER", f.pbox, "BOTTOMLEFT", ps * 0.1, ps * 0.1)
    else
        f.pvp:SetPoint("CENTER", f, "BOTTOMLEFT", ps * 0.1, ps * 0.1)
    end
    PlaceName(f)
end

-- The portrait, redrawn only when it's someone new (or force): the 3D
-- model needs the unit close enough to see; otherwise the 2D picture.
local function UpdatePortrait(f, force)
    local l = Look(f.unit)
    if l.portrait == "off" then return end
    local guid = Safe(UnitGUID, f.unit)
    local known = not isSecret(guid) -- (a hidden GUID can't be compared: draw on events only)
    if not force and known and guid == f.portraitGUID and f.portraitMode == l.portrait then return end
    if not force and not known and f.portraitMode == l.portrait then return end
    f.portraitGUID = known and guid or nil
    f.portraitMode = l.portrait
    local visible = IsTrue(Safe(UnitIsVisible, f.unit))
    if l.portrait == "3d" and visible then
        f.ptex:Hide()
        f.model:Show()
        pcall(f.model.ClearModel, f.model)
        pcall(f.model.SetUnit, f.model, f.unit)
        pcall(f.model.SetPortraitZoom, f.model, 1)
        pcall(f.model.SetCamDistanceScale, f.model, 1)
    else
        f.model:Hide()
        f.ptex:Show()
        if SetPortraitTexture then pcall(SetPortraitTexture, f.ptex, f.unit) end
    end
end

-- healing on its way to a unit: the game's own prediction, else
-- LibHealComm (HealBot brings it) on clients that don't have that
local function HealComm() return LibStub and LibStub("LibHealComm-4.0", true) end

local function IncomingHeals(unit)
    if UnitGetIncomingHeals then
        local ok, v = pcall(UnitGetIncomingHeals, unit)
        if ok and Present(v) then return v end
    end
    local hc = HealComm()
    if hc and hc.GetHealAmount then
        local guid = Safe(UnitGUID, unit)
        if not isSecret(guid) and guid then
            local ok, amount = pcall(hc.GetHealAmount, hc, guid, hc.ALL_HEALS)
            if ok and Num(amount) then
                local ok2, mod = pcall(hc.GetHealModifier, hc, guid)
                return amount * ((ok2 and Num(mod)) and mod or 1)
            end
        end
    end
    return nil
end

local testHealsUntil = 0 -- the options' test: a pretend heal for a few seconds

local function PaintHeals(f, l)
    if not l.heals then f.heal:Hide() return end
    if GetTime() < testHealsUntil then
        -- (health shown at 60% for the test, so the strip has room to show)
        f.health:SetMinMaxValues(0, 1)
        f.health:SetValue(0.6)
        f.heal:SetMinMaxValues(0, 1)
        f.heal:SetValue(0.25)
        f.heal:Show()
        return
    end
    -- the game sizes the strip: no sums on numbers it may hide
    if f.calc and pcall(UnitGetDetailedHealPrediction, f.unit, "player", f.calc) then
        local okA, amount = pcall(f.calc.GetIncomingHeals, f.calc)
        local okM, maxHP = pcall(f.calc.GetMaximumHealth, f.calc)
        if okA and okM and Present(amount) and Present(maxHP) then
            pcall(f.heal.SetMinMaxValues, f.heal, 0, maxHP)
            pcall(f.heal.SetValue, f.heal, amount)
            f.heal:Show()
            return
        end
    end
    -- older ways: the plain call, or LibHealComm
    local incoming = IncomingHeals(f.unit)
    pcall(f.heal.SetMinMaxValues, f.heal, 0, UnitHealthMax(f.unit))
    -- (none: an empty strip, still there for the bandage strip to start from)
    if Present(incoming) then pcall(f.heal.SetValue, f.heal, incoming) else f.heal:SetValue(0) end
    f.heal:Show()
end

---------------------------------------------------------------------------
-- Heals over time: bandages (channelled), Renew and Rejuvenation. The
-- game's prediction counts none of them, so the ones you cast are worked
-- out here: the total from the spell's text ("Heals 66 damage over 6
-- sec", "Heals the target of 45 damage over 15 sec"), shared over its
-- ticks (a bandage's every second, the others' every 3), less those
-- already landed. Other people's come from LibHealComm when it's there
-- (they need an addon with it too). The strip shows what's still to come
-- and flashes as each tick lands. A bandage goes on your target if it's a
-- friendly player, else on you.
---------------------------------------------------------------------------
local timed = {} -- [key] = { guid, total, ticks, start, finish }

local function SpellText(spellID)
    local d
    if C_Spell and C_Spell.GetSpellDescription then d = Safe(C_Spell.GetSpellDescription, spellID)
    elseif GetSpellDescription then d = Safe(GetSpellDescription, spellID) end
    if isSecret(d) or type(d) ~= "string" then return nil end
    return d
end

local function SpellNameOf(id)
    local n
    if C_Spell and C_Spell.GetSpellName then n = Safe(C_Spell.GetSpellName, id) end
    if (isSecret(n) or type(n) ~= "string") and GetSpellInfo then n = Safe(GetSpellInfo, id) end
    if isSecret(n) or type(n) ~= "string" then return nil end
    return n
end

-- the heals over time this knows, by name (every rank shares its name;
-- every bandage's channel is "First Aid"), and the seconds between ticks
local KINDS
local function TickEvery(name)
    if not KINDS then
        KINDS = { ["First Aid"] = 1, Renew = 3, Rejuvenation = 3 }
        for id, step in pairs({ [746] = 1, [139] = 3, [774] = 3 }) do
            local n = SpellNameOf(id) -- (the game's language)
            if n then KINDS[n] = step end
        end
    end
    if isSecret(name) or type(name) ~= "string" then return nil end
    return KINDS[name]
end

-- "... 45 damage over 15 sec" / "... for 32 over 12 sec" -> 45, 15
local function TotalAndTime(spellID)
    local text = Num(spellID) and SpellText(spellID)
    if not text then return nil end
    local total, secs = text:match("([%d,]+)%D-over ([%d%.]+) sec")
    if not total then return nil end
    return tonumber((total:gsub(",", ""))), tonumber(secs)
end

local function GuidOf(unit)
    local g = Safe(UnitGUID, unit)
    if isSecret(g) or type(g) ~= "string" then return nil end
    return g
end

local function AddTimed(key, guid, total, step, start, finish)
    if not (guid and total and total > 0 and finish > start) then return end
    timed[key] = { guid = guid, total = total, start = start, finish = finish,
        ticks = math.max(1, math.floor((finish - start) / step + 0.5)) }
end

-- bandaging: your target if it's a friendly player, else you
local function StartBandage(spellID)
    timed.bandage = nil
    local info = { Safe(UnitChannelInfo, "player") }
    local name, startMS, endMS = info[1], info[4], info[5]
    -- (the spell's ID: from the event, else 8th on newer clients, 7th on older)
    if not Num(spellID) then spellID = Num(info[8]) and info[8] or info[7] end
    if TickEvery(name) ~= 1 or not Num(startMS) or not Num(endMS) then return end
    local who = "player"
    if IsTrue(Safe(UnitExists, "target")) and IsTrue(Safe(UnitIsPlayer, "target"))
        and IsTrue(Safe(UnitIsFriend, "player", "target")) and not IsTrue(Safe(UnitIsUnit, "target", "player")) then
        who = "target"
    end
    AddTimed("bandage", GuidOf(who), (TotalAndTime(spellID)), 1, startMS / 1000, endMS / 1000)
end

-- Renew / Rejuvenation: who it went on comes from the cast's target name
local sentTo = {} -- [cast] = the target's name, from UNIT_SPELLCAST_SENT
local function GuidForName(name)
    if isSecret(name) then return nil end
    if name == nil or name == "" then return GuidOf("player") end -- (cast on yourself)
    for _, u in ipairs({ "player", "target", "targettarget", "focus", "party1", "party2", "party3", "party4" }) do
        local n = Safe(UnitName, u)
        if not isSecret(n) and n == name then return GuidOf(u) end
    end
end

local function CastHot(cast, spellID)
    local name = SpellNameOf(spellID)
    local step = TickEvery(name)
    if not step or step == 1 then return end
    local total, secs = TotalAndTime(spellID)
    local guid = GuidForName(sentTo[cast])
    sentTo[cast] = nil
    if not (total and secs and guid) then return end
    local now = GetTime()
    -- (casting it again on the same person replaces the old one)
    AddTimed(name .. ":" .. guid, guid, total, step, now, now + secs)
end

-- healing still to come from your own, on one person, and how bright the
-- flash is (1 just as a tick lands, fading out over most of a second)
local function TimedLeft(guid)
    local now, sum, glow = GetTime(), 0, 0
    for key, e in pairs(timed) do
        if now >= e.finish then
            timed[key] = nil
        elseif e.guid == guid then
            local step = (e.finish - e.start) / e.ticks
            local landed = math.min(e.ticks, math.floor((now - e.start) / step))
            sum = sum + e.total * (e.ticks - landed) / e.ticks
            local since = (now - e.start) % step
            glow = math.max(glow, landed > 0 and math.max(0, 1 - since / 0.8) or 0)
        end
    end
    return sum, glow
end

-- other people's heals over time (LibHealComm; it leaves out yours)
local function OthersHots(guid)
    local hc = HealComm()
    if not (hc and hc.GetOthersHealAmount and hc.HOT_HEALS) then return 0 end
    local ok, amount = pcall(hc.GetOthersHealAmount, hc, guid, hc.HOT_HEALS)
    if not ok or not Num(amount) then return 0 end
    local ok2, mod = pcall(hc.GetHealModifier, hc, guid)
    return amount * ((ok2 and Num(mod)) and mod or 1)
end

local function PaintBand(f)
    local l = Look(f.unit)
    local guid = l.heals and IsTrue(Safe(UnitExists, f.unit)) and GuidOf(f.unit)
    if not guid then f.band:Hide() return end
    local mine, glow = TimedLeft(guid)
    local total = mine + OthersHots(guid)
    if total <= 0 then f.band:Hide() return end
    pcall(f.band.SetMinMaxValues, f.band, 0, UnitHealthMax(f.unit))
    f.band:SetValue(total)
    f.band:SetAlpha(0.45 + 0.55 * glow)
    f.band:Show()
end


local function Paint(f, force)
    if not DB then return end
    local unit, l = f.unit, Look(f.unit)
    if not IsTrue(Safe(UnitExists, unit)) then return end
    UpdatePortrait(f, force)

    -- health: the game fills the bar, hidden numbers and all
    pcall(f.health.SetMinMaxValues, f.health, 0, UnitHealthMax(unit))
    pcall(f.health.SetValue, f.health, UnitHealth(unit))
    local hc = HealthColor(unit, l)
    S.SetFill(f.health, hc[1], hc[2], hc[3])
    PaintHeals(f, l) -- (after the health, which it starts from)
    PaintBand(f)
    if f.role and ns.ShowRole then ns.ShowRole(f) end
    if l.power > 0 then
        pcall(f.power.SetMinMaxValues, f.power, 0, UnitPowerMax(unit))
        pcall(f.power.SetValue, f.power, UnitPower(unit))
        local pc = PowerColor(unit)
        S.SetFill(f.power, pc[1], pc[2], pc[3])
    end

    local name = Safe(UnitName, unit)
    if Present(name) then pcall(f.name.SetText, f.name, name) else f.name:SetText("") end
    local okT, hpText = pcall(HealthText, unit, l.healthText)
    if okT then pcall(f.hp.SetText, f.hp, hpText) else f.hp:SetText("") end
    if f.pp:IsShown() then
        local okP, ppText = pcall(PowerText, unit, l.powerText)
        if okP then pcall(f.pp.SetText, f.pp, ppText) else f.pp:SetText("") end
    end

    -- level, coloured by how tough it is for you
    if l.showLevel then
        local lvl = Safe(UnitLevel, unit)
        if Num(lvl) then
            f.level:SetText(lvl < 0 and "??" or tostring(lvl))
            local c = GetCreatureDifficultyColor and lvl > 0 and GetCreatureDifficultyColor(lvl)
                or (lvl < 0 and { r = 1, g = 0.1, b = 0.1 }) or { r = 1, g = 0.82, b = 0 }
            f.level:SetTextColor(c.r, c.g, c.b)
        else
            f.level:SetText("")
        end
    end

    -- the rim: gold for elites, silver for rares
    local class = Safe(UnitClassification, unit)
    if isSecret(class) then class = nil end
    local rim = (class == "elite" or class == "worldboss" or class == "rareelite") and RIM_ELITE
        or (class == "rare") and RIM_RARE or RIM
    f.rim:SetColorTexture(rim[1], rim[2], rim[3], 1)

    -- PvP flag: free-for-all, or the unit's faction badge
    local pvpTex
    if l.showPvP then
        if IsTrue(Safe(UnitIsPVPFreeForAll, unit)) then
            pvpTex = "Interface\\TargetingFrame\\UI-PVP-FFA"
        elseif IsTrue(Safe(UnitIsPVP, unit)) then
            local faction = Safe(UnitFactionGroup, unit)
            if not isSecret(faction) and (faction == "Alliance" or faction == "Horde") then
                pvpTex = "Interface\\TargetingFrame\\UI-PVP-" .. faction
            end
        end
    end
    if pvpTex then
        f.pvp:SetTexture(pvpTex)
        f.pvp:Show()
    else
        f.pvp:Hide()
    end
    f.pvpHover:SetShown(pvpTex and true or false)

    -- raid marker
    local idx = Safe(GetRaidTargetIndex, unit)
    if Num(idx) and SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(f.raid, idx)
        f.raid:Show()
    else
        f.raid:Hide()
    end

    if f.state then
        if IsTrue(Safe(UnitAffectingCombat, "player")) then
            f.state:SetTexCoord(0.5, 1, 0, 0.5)
            f.state:Show()
        elseif IsTrue(Safe(IsResting)) then
            f.state:SetTexCoord(0, 0.5, 0, 0.421875)
            f.state:Show()
        else
            f.state:Hide()
        end
    end
    if f.pips then
        local cp = Safe(GetComboPoints, "player", "target")
        if not Num(cp) and UnitPower and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
            cp = Safe(UnitPower, "player", Enum.PowerType.ComboPoints)
        end
        for i = 1, 5 do f.pips[i]:SetShown(Num(cp) and cp >= i) end
    end
end

local function PaintAll(force)
    for _, f in pairs(frames) do Paint(f, force) end
end

-- the options' "Test incoming heals": a pretend heal on every frame showing
function ns.TestHeals()
    testHealsUntil = GetTime() + 5
    PaintAll()
    C_Timer.After(5.1, function() PaintAll() end) -- the real health back
end

-- show / hide: the game does it (unit watch) so it works in combat; in
-- Edit Mode every frame shows so you can place it, and "Hide This Frame"
-- takes it away (faded in Edit Mode)
local function Visibility(f)
    OutOfCombat(function()
        local l = Look(f.unit)
        local editing = LEM:IsInEditMode()
        f:SetAlpha(l.hidden and 0.4 or 1)
        if editing then
            UnregisterUnitWatch(f)
            f:Show()
            -- an empty party slot: a stand-in, to see the stack while placing it
            if f.partyIndex and not IsTrue(Safe(UnitExists, f.unit)) then
                f.name:SetText("Party " .. f.partyIndex)
                f.hp:SetText("")
                f.health:SetMinMaxValues(0, 1)
                f.health:SetValue(1)
                S.SetFill(f.health, 0.3, 0.6, 0.35)
            end
        elseif l.hidden then
            UnregisterUnitWatch(f)
            f:Hide()
        elseif f.unit == "player" then
            UnregisterUnitWatch(f)
            f:Show()
        else
            RegisterUnitWatch(f)
        end
    end)
end

local function Place(f)
    OutOfCombat(function()
        local l = Look(f.unit)
        f:ClearAllPoints()
        if f.partyIndex then
            -- the party stacks down from its anchor, which sits where it's placed
            local p = l.point and l or UNITS.party.pos
            partyAnchor:ClearAllPoints()
            partyAnchor:SetPoint(p.point, UIParent, p.point, p.x, p.y)
            partyAnchor:SetSize(l.width, l.height * 4 + l.spacing * 3)
            f:SetPoint("TOPLEFT", partyAnchor, "TOPLEFT", 0, -(f.partyIndex - 1) * (l.height + l.spacing))
        else
            local p = l.point and l or UNITS[f.unit].pos
            f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
        end
        f:SetSize(l.width, l.height)
        Arrange(f)
    end)
end

local function UpdateAll()
    if not DB then return end
    for _, f in pairs(frames) do
        Place(f)
        Visibility(f)
    end
    PaintAll(true)
    if ns.RefreshCast then ns.RefreshCast() end
    if ns.RefreshAuras then ns.RefreshAuras() end
end

---------------------------------------------------------------------------
-- Buffs and debuffs, allies and enemies alike: buffs in rows on top of the
-- frame (lifted above the target's cast bar while it shows), debuffs
-- below. Each row is exactly the
-- frame's width, icons sized so a full row runs edge to edge, with a thin
-- border (a debuff's in its dispel colour: magic, curse, disease, poison).
--
-- Sizes: a few auras get big icons (9 to a row), more get medium (12), lots
-- get small (16), never more than 3 rows.
--
-- How: this client won't let addons read auras in combat, but it will draw
-- them itself into "aura containers" (as HealBot does on Forever): we give
-- it a filter and our own icon, border and cooldown, and it fills them. A
-- container can't be made in combat, so all three sizes are made ahead,
-- out of combat, and the right one is shown. Out of combat the auras are
-- counted to pick the size; in a fight the size holds (the count can't be
-- read), still within 3 rows.
---------------------------------------------------------------------------
local TIERS = { 9, 12, 16 } -- icons to a row: big, medium, small
local AURA_GAP, AURA_OFFSET = 2, 3 -- between icons; between the rows and the frame
local DISPEL = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 },
    Poison = { 0, 0.6, 0 }, Bleed = { 0.8, 0, 0 } }

local auraSupport -- nil: not checked yet (only out of combat)
local function CanAura()
    if auraSupport ~= nil then return auraSupport end
    if InCombatLockdown() then return false end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    auraSupport = (ok and c and type(c.AddAuraGroup) == "function") and true or false
    if ok and c then c:Hide() end
    return auraSupport
end

-- Stack counts: the game fills a text we hand it, but the setter's name
-- isn't documented anywhere we can see. These are tried in order; the one
-- that takes is noted (SpliffFramesDB.stackSetter), and the button's own
-- methods are listed once (SpliffFramesDB.auraButtonMethods) to check by.
local STACK_SETTERS = { "SetApplicationsFontString", "SetApplicationsText", "SetApplicationCount",
    "SetApplications", "SetStackText", "SetStackCount", "SetCountText", "SetCountFontString", "SetCount" }
local probedButton = false
local function ProbeButton(btn)
    if probedButton or not DB then return end
    probedButton = true
    local names, seen = {}, {}
    local function scan(t)
        if type(t) ~= "table" then return end
        for k, v in pairs(t) do
            if type(k) == "string" and type(v) == "function" and not seen[k] and k:find("^[SA]") then
                seen[k] = true
                names[#names + 1] = k
            end
        end
    end
    scan(btn)
    local mt = getmetatable(btn)
    scan(mt and mt.__index)
    table.sort(names)
    DB.auraButtonMethods = table.concat(names, " ")
end

local function AddStacks(btn, size)
    local over = CreateFrame("Frame", nil, btn)
    over:SetAllPoints(btn)
    over:SetFrameLevel(btn:GetFrameLevel() + 5)
    local fs = over:CreateFontString(nil, "OVERLAY")
    fs:SetFont(S.FontPath(nil), math.max(8, math.floor(size * 0.4)), "OUTLINE")
    fs:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    fs:SetJustifyH("RIGHT")
    for _, name in ipairs(STACK_SETTERS) do
        if type(btn[name]) == "function" and pcall(btn[name], btn, fs) then
            if DB and DB.stackSetter ~= name then DB.stackSetter = name end
            return fs
        end
    end
    fs:Hide()
    return nil
end

-- each icon the game makes: click-through (clicks reach the frame), a thin
-- border, the icon, a cooldown sweep and a stack count, handed to the game
-- to fill. numbers: the time left written on the sweep (the big icons).
local function InitIcon(size, debuff, numbers)
    return function(btn)
        pcall(function()
            if btn.SetMouseClickEnabled then btn:SetMouseClickEnabled(false) end
            if btn.SetMouseMotionEnabled then btn:SetMouseMotionEnabled(false) end
            btn:SetSize(size, size)
            if btn.sfIcon then return end
            ProbeButton(btn)
            local border = btn:CreateTexture(nil, "BACKGROUND")
            border:SetAllPoints(btn)
            border:SetTexture(S.WHITE)
            border:SetVertexColor(0, 0, 0, 1)
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", -1, 1)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
            cd:SetAllPoints(icon)
            cd:SetReverse(true)
            cd:SetDrawEdge(false)
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(not numbers) end
            btn.sfIcon, btn.sfCD = icon, cd
            if btn.SetIcon then btn:SetIcon(icon) end
            if btn.SetDurationCooldown then btn:SetDurationCooldown(cd) end
            btn.sfStacks = AddStacks(btn, size)
            if debuff then
                local map = {}
                for k, c in pairs(DISPEL) do map[k] = CreateColor(c[1], c[2], c[3]) end
                local style = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
                local opts = { style = style and style.PreserveAsset, customDispelColorMap = map }
                if btn.AddDispelTypeTexture then pcall(btn.AddDispelTypeTexture, btn, border, opts)
                elseif btn.SetAuraBorder then pcall(btn.SetAuraBorder, btn, border, opts) end
            end
        end)
    end
end

-- one row-set (all its rows) of one size: buffs grow up from the frame's
-- top-left, debuffs down from its bottom-left; out of combat only, in the
-- order the game needs (make, place, unit, group, enable last)
-- groups: { { name, maxFrameCount, size, numbers }, ... }, each its own
-- icon size, laid out one after another in the same rows
local function BuildContainer(f, side, width, groups)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, f, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    local up = side == "buffs"
    pcall(function()
        c:ClearAllPoints()
        if up then c:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, AURA_OFFSET)
        else c:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -AURA_OFFSET) end
        local anchor = up and "BOTTOMLEFT" or "TOPLEFT"
        if c.SetFlowLayoutAnchorPoint then c:SetFlowLayoutAnchorPoint(anchor) end
        local dirs = AnchorUtil and AnchorUtil.FlowDirection
        if c.SetFlowLayoutGrowthDirection and dirs then
            pcall(c.SetFlowLayoutGrowthDirection, c, dirs.Right, up and dirs.Up or dirs.Down)
        end
        local axis = AnchorUtil and AnchorUtil.FlowLayoutAxis
        if c.SetFlowLayoutAxis and axis then c:SetFlowLayoutAxis(axis.Horizontal) end
        -- a row wraps at the frame's width (a hair over, for rounding)
        if c.SetFlowLayoutMaximumLineSize then c:SetFlowLayoutMaximumLineSize(width + 0.5) end
        c:SetFrameLevel(f:GetFrameLevel() + 20)
        if c.SetMouseClickEnabled then c:SetMouseClickEnabled(false) end
        if c.SetMouseMotionEnabled then c:SetMouseMotionEnabled(false) end
    end)
    if not pcall(c.SetUnit, c, f.unit) then c:Hide() return nil end
    local sort = AuraContainerSortMethod
    for _, g in ipairs(groups) do
        local size = g[3]
        local okG = pcall(c.AddAuraGroup, c, g[1] .. side, up and "HELPFUL" or "HARMFUL", {
            maxFrameCount = g[2],
            initializeFrame = InitIcon(size, not up, g[4]),
            sortMethod = (not up and sort) and sort.UnitFrameDebuff or nil,
            layout = { elementWidth = size, elementHeight = size, elementSpacing = AURA_GAP, lineSpacing = AURA_GAP,
                groupSpacing = AURA_GAP, elementSpacingX = AURA_GAP, elementSpacingY = AURA_GAP, gapX = 0 },
        })
        if not okG then c:Hide() return nil end
    end
    pcall(c.SetEnabled, c, true) -- last
    c:Hide()
    return c
end

-- one size for all: perRow icons to a row, never more than 3 rows
local function BuildRows(f, side, perRow, width)
    local size = (width - (perRow - 1) * AURA_GAP) / perRow
    return BuildContainer(f, side, width, { { "spliff", perRow * 3, size, false } })
end

-- for enemies: the first LEAD auras big (5 would fill a row; 4 leave room
-- for a couple of small ones beside them), with the time left on them;
-- the rest small after them, 12 to a row
local LEAD, LEAD_SLOTS, REST_PER_ROW = 4, 5, 12
local function BuildLead(f, side, width)
    local big = math.floor((width - (LEAD_SLOTS - 1) * AURA_GAP) / LEAD_SLOTS)
    local small = (width - (REST_PER_ROW - 1) * AURA_GAP) / REST_PER_ROW
    return BuildContainer(f, side, width, {
        { "spliffLead", LEAD, big, true },
        { "spliffRest", REST_PER_ROW * 2, small, false },
    })
end

-- a party frame's debuffs: one row to its right, icons as tall as the
-- frame so the row lines up with its top and bottom edges
local PARTY_ICONS = 8
local function BuildPartyRow(f, height)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, f, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    pcall(function()
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", f, "TOPRIGHT", AURA_OFFSET, 0)
        if c.SetFlowLayoutAnchorPoint then c:SetFlowLayoutAnchorPoint("TOPLEFT") end
        local dirs = AnchorUtil and AnchorUtil.FlowDirection
        if c.SetFlowLayoutGrowthDirection and dirs then pcall(c.SetFlowLayoutGrowthDirection, c, dirs.Right, dirs.Down) end
        local axis = AnchorUtil and AnchorUtil.FlowLayoutAxis
        if c.SetFlowLayoutAxis and axis then c:SetFlowLayoutAxis(axis.Horizontal) end
        if c.SetFlowLayoutMaximumLineSize then
            c:SetFlowLayoutMaximumLineSize(PARTY_ICONS * height + (PARTY_ICONS - 1) * AURA_GAP + 0.5)
        end
        c:SetFrameLevel(f:GetFrameLevel() + 20)
        if c.SetMouseClickEnabled then c:SetMouseClickEnabled(false) end
        if c.SetMouseMotionEnabled then c:SetMouseMotionEnabled(false) end
    end)
    if not pcall(c.SetUnit, c, f.unit) then c:Hide() return nil end
    local sort = AuraContainerSortMethod
    local okG = pcall(c.AddAuraGroup, c, "spliffparty", "HARMFUL", {
        maxFrameCount = PARTY_ICONS,
        -- combat debuffs only: the game leaves out anything lasting over 2
        -- minutes, and anything with no end (Resurrection Sickness, Deserter ...)
        candidateFilters = { maxDuration = 120 },
        initializeFrame = InitIcon(height, true),
        sortMethod = sort and sort.UnitFrameDebuff or nil,
        layout = { elementWidth = height, elementHeight = height, elementSpacing = AURA_GAP, lineSpacing = AURA_GAP,
            groupSpacing = 0, elementSpacingX = AURA_GAP, elementSpacingY = AURA_GAP, gapX = 0 },
    })
    if not okG then c:Hide() return nil end
    pcall(c.SetEnabled, c, true) -- last
    c:Hide()
    return c
end

-- (re)make a frame's rows for its width; the old ones are left hidden
local function BuildAuras(f)
    if InCombatLockdown() or not CanAura() then return false end
    if f.partyIndex then
        local height = Look(f.unit).height
        if f.auras and f.auras.height == height then return true end
        if f.auras and f.auras.right then f.auras.right:Hide() end
        f.auras = { height = height, right = BuildPartyRow(f, height) }
        return true
    end
    local width = Look(f.unit).width
    if f.auras and f.auras.width == width then return true end
    if f.auras then
        for _, side in pairs({ f.auras.buffs, f.auras.debuffs, f.auras.lead or {} }) do
            for _, c in pairs(side) do c:Hide() end
        end
    end
    f.auras = { width = width, buffs = {}, debuffs = {}, tier = { buffs = 1, debuffs = 1 } }
    for t, perRow in ipairs(TIERS) do
        f.auras.buffs[t] = BuildRows(f, "buffs", perRow, width)
        f.auras.debuffs[t] = BuildRows(f, "debuffs", perRow, width)
    end
    -- the target (and its target) can be an enemy: big leading icons then
    if f.unit == "target" or f.unit == "targettarget" then
        f.auras.lead = { buffs = BuildLead(f, "buffs", width), debuffs = BuildLead(f, "debuffs", width) }
    end
    return true
end

-- how many auras (out of combat; nil when the game won't say)
local function CountAuras(unit, filter)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    for i = 1, 60 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        if not ok or isSecret(a) then return nil end
        if a == nil then return i - 1 end
    end
    return 60
end

local function TierFor(n)
    if n <= TIERS[1] then return 1 end          -- one row of big ones
    if n <= TIERS[2] * 2 then return 2 end      -- up to two rows of medium
    return 3                                    -- small, up to three rows
end

-- The buffs sit right on top of the frame; while the target's cast bar is
-- showing (something's casting) they lift above it, and settle back down
-- when the cast ends.
local function AnchorBuffs(f)
    local a = f.auras
    if not (a and a.buffs) then return end
    local castBar = f.unit == "target" and ns.castBarFrame
    if castBar and not castBar:IsShown() then castBar = nil end
    local all = {}
    for _, c in pairs(a.buffs) do all[#all + 1] = c end
    if a.lead and a.lead.buffs then all[#all + 1] = a.lead.buffs end
    for _, c in ipairs(all) do
        pcall(function()
            c:ClearAllPoints()
            if castBar then
                c:SetPoint("BOTTOMLEFT", castBar, "TOPLEFT", 0, AURA_OFFSET)
            else
                -- (your frame's: above the stance tabs, Stance.lua)
                local lift = ns.StanceLift and ns.StanceLift(f) or 0
                c:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, AURA_OFFSET + lift)
            end
        end)
    end
end

local function ShowAuras(f)
    local a = f.auras
    if not a then return end
    AnchorBuffs(f)
    local l = Look(f.unit)
    local on = l.auras and not l.hidden and IsTrue(Safe(UnitExists, f.unit))
    if f.partyIndex then
        if a.right then
            pcall(a.right.SetShown, a.right, on)
            if on and a.right.UpdateAllAuras then pcall(a.right.UpdateAllAuras, a.right) end
        end
        return
    end
    -- an enemy: its first few auras big, with the time left on them
    local enemy = a.lead and IsTrue(Safe(UnitCanAttack, "player", f.unit))
    for _, side in ipairs({ "buffs", "debuffs" }) do
        local want = on -- (buffs on top and debuffs below, for allies and enemies alike)
        local lead = a.lead and a.lead[side]
        if lead then
            local show = want and enemy and true or false
            pcall(lead.SetShown, lead, show)
            if show and lead.UpdateAllAuras then pcall(lead.UpdateAllAuras, lead) end
            if show then want = false end -- (the even-sized rows step aside)
        end
        if want and not InCombatLockdown() then
            local n = CountAuras(f.unit, side == "buffs" and "HELPFUL" or "HARMFUL")
            if n then a.tier[side] = TierFor(n) end
        end
        for t, c in pairs(a[side]) do
            local show = want and t == a.tier[side]
            pcall(c.SetShown, c, show)
            if show and c.UpdateAllAuras then pcall(c.UpdateAllAuras, c) end
        end
    end
end

-- (called from settings, Edit Mode and the frames' refresh, earlier in the file)
function ns.RefreshAuras()
    if not DB then return end
    for _, unit in ipairs({ "player", "target", "targettarget", "party1", "party2", "party3", "party4" }) do
        local f = frames[unit]
        if Look(unit).auras then BuildAuras(f) end
        ShowAuras(f)
    end
end

local auraEvents = CreateFrame("Frame")
pcall(auraEvents.RegisterUnitEvent, auraEvents, "UNIT_AURA", "player", "target")
auraEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
auraEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
auraEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
auraEvents:SetScript("OnEvent", function(_, event, unit)
    if not DB then return end
    if event == "PLAYER_REGEN_ENABLED" then
        ns.RefreshAuras() -- anything that had to wait, and sizes for now
    elseif event == "GROUP_ROSTER_UPDATE" then
        for _, u in ipairs(PARTY) do ShowAuras(frames[u]) end -- (party members came or went)
    elseif event == "PLAYER_TARGET_CHANGED" then
        ShowAuras(frames.target)
        ShowAuras(frames.targettarget)
    elseif not InCombatLockdown() and not isSecret(unit) then
        -- (in a fight the game keeps the icons current itself)
        if unit == "player" then ShowAuras(frames.player) end
        if unit == "target" then ShowAuras(frames.target) end
    end
end)

---------------------------------------------------------------------------
-- Party members' roles: the role each chose for the group (tank, healer,
-- damage), as a small icon right after their level, before their name.
---------------------------------------------------------------------------
-- the role icons: the game's small ones, else its older role picture
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local ROLE_COORDS = { TANK = { 0, 19 / 64, 22 / 64, 41 / 64 }, HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } }

local function SetRoleIcon(tex, role)
    if tex.SetAtlas and pcall(tex.SetAtlas, tex, ROLE_ATLAS[role]) and (not tex.GetAtlas or tex:GetAtlas()) then return end
    tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
    tex:SetTexCoord(unpack(ROLE_COORDS[role]))
end

local function ShowRole(f)
    if not f.role then return end
    local l = Look(f.unit)
    local role = l.showRole and not l.hidden and Safe(UnitGroupRolesAssigned, f.unit)
    if isSecret(role) or not ROLE_ATLAS[role] then role = nil end
    if role then
        SetRoleIcon(f.role, role)
        f.role:Show()
    else
        f.role:Hide()
    end
    PlaceName(f) -- (the name moves over for it, or back)
end

ns.ShowRole = ShowRole -- (the frames' paint, earlier in the file, shows it too)

local roleEvents = CreateFrame("Frame")
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM" }) do
    pcall(roleEvents.RegisterEvent, roleEvents, e)
end
roleEvents:SetScript("OnEvent", function()
    if not DB then return end
    for _, u in ipairs(PARTY) do ShowRole(frames[u]) end
end)

---------------------------------------------------------------------------
-- The target's cast bar: a slim bar of its own just above the target
-- frame, exactly as wide, a few pixels clear of it, with the spell's name.
-- Only for enemies. It fills as the cast goes (a channel drains), turns
-- grey when it can't be interrupted, and flashes "Interrupted" in red when
-- it's stopped.
---------------------------------------------------------------------------
local CAST_COLOR = { 1, 0.7, 0.2 }
local CAST_LOCKED = { 0.6, 0.6, 0.65 } -- can't be interrupted
local CAST_STOPPED = { 0.9, 0.2, 0.2 }

local cast = CreateFrame("Frame", nil, frames.target)
cast:SetFrameLevel(frames.target:GetFrameLevel() + 10)
do
    local edge = cast:CreateTexture(nil, "BACKGROUND", nil, 0)
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 0.9)
    local rim = cast:CreateTexture(nil, "BACKGROUND", nil, 1)
    rim:SetPoint("TOPLEFT", 1, -1)
    rim:SetPoint("BOTTOMRIGHT", -1, 1)
    rim:SetColorTexture(0.28, 0.28, 0.32, 1)
    local inside = cast:CreateTexture(nil, "BACKGROUND", nil, 2)
    inside:SetPoint("TOPLEFT", 2, -2)
    inside:SetPoint("BOTTOMRIGHT", -2, 2)
    inside:SetColorTexture(0.06, 0.06, 0.08, 0.92)
end
cast.sb = NewBar(cast)
cast.sb:SetPoint("TOPLEFT", 2, -2)
cast.sb:SetPoint("BOTTOMRIGHT", -2, 2)
local castOver = CreateFrame("Frame", nil, cast)
castOver:SetAllPoints()
castOver:SetFrameLevel(cast.sb:GetFrameLevel() + 5)
cast.name = castOver:CreateFontString(nil, "OVERLAY")
cast.name:SetPoint("LEFT", 5, 0)
cast.name:SetPoint("RIGHT", -5, 0)
cast.name:SetJustifyH("LEFT")
cast.name:SetWordWrap(false)
cast:Hide()
ns.castBarFrame = cast -- (the target's buffs lift above it while it shows)
cast:HookScript("OnShow", function() AnchorBuffs(frames.target) end)
cast:HookScript("OnHide", function() AnchorBuffs(frames.target) end)

local function ArrangeCast()
    local l = Look("target")
    cast:ClearAllPoints()
    cast:SetPoint("BOTTOMLEFT", frames.target, "TOPLEFT", 0, l.castGap)
    cast:SetPoint("BOTTOMRIGHT", frames.target, "TOPRIGHT", 0, l.castGap)
    cast:SetHeight(l.castHeight)
    S.ApplyFont(cast.name, l.font, math.max(7, math.min(l.fontSize - 1, l.castHeight - 3)), "OUTLINE")
end

-- the cast (or channel) on the target: name, start and end (in seconds,
-- when the game says), can it be interrupted, is it a channel
local function CastInfo(unit)
    local c = { Safe(UnitCastingInfo, unit) }
    local channel = false
    if not Present(c[1]) then
        c = { Safe(UnitChannelInfo, unit) }
        channel = true
    end
    if not Present(c[1]) then return nil end
    -- "can't be interrupted": 8th for a cast, 7th for a channel (newer clients)
    -- (picked with if, not "a and b or c": that would test a hidden value)
    local locked
    if channel then locked = c[7] else locked = c[8] end
    locked = not isSecret(locked) and locked == true
    local s, e = c[4], c[5]
    if Num(s) and Num(e) and e > s then s, e = s / 1000, e / 1000 else s, e = nil, nil end
    return c[1], s, e, locked, channel
end

local stoppedUntil = 0 -- "Interrupted" stays up a moment

local function ShowCast()
    local l = Look("target")
    local enemy = IsTrue(Safe(UnitCanAttack, "player", "target"))
    if not l.castBar or l.hidden or not enemy then
        cast:Hide()
        cast:SetScript("OnUpdate", nil)
        return
    end
    local name, s, e, locked, channel = CastInfo("target")
    if not Present(name) then
        if GetTime() >= stoppedUntil then
            cast:Hide()
            cast:SetScript("OnUpdate", nil)
        end
        return
    end
    stoppedUntil = 0
    pcall(cast.name.SetText, cast.name, name)
    local c = locked and CAST_LOCKED or CAST_COLOR
    S.SetFill(cast.sb, c[1], c[2], c[3], 1, "VERTICAL")
    if s then
        -- timed here: fills (a channel drains) until it ends
        cast.s, cast.e, cast.channel = s, e, channel
        cast.sb:SetMinMaxValues(0, e - s)
        cast:SetScript("OnUpdate", function(self)
            local now = GetTime()
            if now >= self.e then
                self:SetScript("OnUpdate", nil)
                return
            end
            self.sb:SetValue(self.channel and (self.e - now) or (now - self.s))
        end)
    else
        -- the times are hidden: the game's own timer, where it has one
        cast:SetScript("OnUpdate", nil)
        local getDur = channel and UnitChannelDuration or UnitCastingDuration
        if getDur and cast.sb.SetTimerDuration then
            local ok, dur = pcall(getDur, "target")
            if ok and dur then
                local dir = Enum and Enum.StatusBarTimerDirection
                pcall(cast.sb.SetTimerDuration, cast.sb, dur,
                    dir and (channel and dir.RemainingTime or dir.ElapsedTime) or nil)
            end
        else
            cast.sb:SetMinMaxValues(0, 1)
            cast.sb:SetValue(1)
        end
    end
    ArrangeCast()
    cast:Show()
end

local function CastStopped(interrupted)
    if interrupted and cast:IsShown() then
        cast:SetScript("OnUpdate", nil)
        cast.sb:SetMinMaxValues(0, 1)
        cast.sb:SetValue(1)
        S.SetFill(cast.sb, CAST_STOPPED[1], CAST_STOPPED[2], CAST_STOPPED[3], 1, "VERTICAL")
        cast.name:SetText(INTERRUPTED or "Interrupted")
        stoppedUntil = GetTime() + 0.8
        C_Timer.After(0.85, ShowCast)
    else
        ShowCast()
    end
end

-- in Edit Mode: a pretend cast, to see where it sits
local function PreviewCast()
    local l = Look("target")
    if not (LEM:IsInEditMode() and l.castBar) then return end
    ArrangeCast()
    cast:SetScript("OnUpdate", nil)
    S.SetFill(cast.sb, CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3], 1, "VERTICAL")
    cast.sb:SetMinMaxValues(0, 1)
    cast.sb:SetValue(0.6)
    cast.name:SetText("Fireball")
    cast:Show()
end

-- (called from settings changes and Edit Mode, which come earlier in the file)
function ns.RefreshCast()
    if not DB then return end
    ArrangeCast() -- (placed even while hidden: the buffs line up above it)
    if LEM:IsInEditMode() then
        if Look("target").castBar then PreviewCast() else cast:Hide() end
    else
        ShowCast()
    end
end

local castEvents = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
    pcall(castEvents.RegisterUnitEvent, castEvents, e, "target")
end
castEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
castEvents:SetScript("OnEvent", function(_, event)
    if not DB then return end
    if LEM:IsInEditMode() then PreviewCast() return end
    if event == "PLAYER_TARGET_CHANGED" then
        stoppedUntil = 0
        ShowCast()
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        CastStopped(true)
    else
        ShowCast()
    end
end)

---------------------------------------------------------------------------
-- The game's own frames: hidden while Spliff Frames is on (the usual way:
-- quiet, hidden, and moved into a hidden frame). Turning it off in Edit
-- Mode brings them back after a reload.
---------------------------------------------------------------------------
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local GAME_FRAMES = { "PlayerFrame", "TargetFrame", "TargetFrameToT", "ComboFrame" }

-- (the game's party frames too, while Spliff's party frames are showing)
local GAME_PARTY = { "PartyFrame", "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3",
    "PartyMemberFrame4", "CompactPartyFrame" }

local function HideGameFrames()
    if not (DB and DB.hideGame ~= false) then return end
    OutOfCombat(function()
        local names = {}
        for _, n in ipairs(GAME_FRAMES) do names[#names + 1] = n end
        if not Look("party").hidden then
            for _, n in ipairs(GAME_PARTY) do names[#names + 1] = n end
        end
        for _, n in ipairs(names) do
            local g = _G[n]
            if g and g.GetParent and g:GetParent() ~= hiddenParent then
                pcall(g.UnregisterAllEvents, g)
                pcall(g.Hide, g)
                pcall(g.SetParent, g, hiddenParent)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------
-- "Same size": the player and target frames share width, height, power
-- bar height and font size; changing either changes both
local SIZE_FIELDS = { width = true, height = true, power = true, fontSize = true }
local function Partner(unit) return (unit == "player" and "target") or (unit == "target" and "player") or nil end
local function Synced() return DB and Look("player").syncSize and true or false end

local function Mirror(unit, field, value)
    local other = Partner(unit)
    if not (other and SIZE_FIELDS[field] and Synced()) then return end
    Look(other)[field] = value
    Place(frames[other])
    Paint(frames[other], true)
    pcall(LEM.RefreshFrameSettings, LEM, frames[other])
end

-- switching it on: the other frame takes this one's size
local function SetSynced(on, from)
    Look("player").syncSize = on and true or false
    if on then
        for field in pairs(SIZE_FIELDS) do Mirror(from, field, Look(from)[field]) end
    end
end

local HEALTH_TEXT = {
    { text = "Amount and %", value = "both" }, { text = "Amount", value = "current" },
    { text = "Percent", value = "percent" }, { text = "None", value = "none" },
}
local PORTRAITS = {
    { text = "3D model", value = "3d" }, { text = "2D picture", value = "2d" }, { text = "Off", value = "off" },
}
local SIDES = { { text = "Left", value = "left" }, { text = "Right", value = "right" } }
local TEXT_POS = { { text = "Left", value = "left" }, { text = "Centre", value = "center" }, { text = "Right", value = "right" } }

-- each frame's panel; the party has one (on its anchor) for all four
for _, unit in ipairs({ "player", "target", "targettarget", "party" }) do
    local isParty = unit == "party"
    local f = isParty and partyAnchor or frames[unit]
    local members = isParty and { frames.party1, frames.party2, frames.party3, frames.party4 } or { f }
    local function Redo(force)
        for _, m in ipairs(members) do
            Place(m)
            Visibility(m)
            Paint(m, force)
        end
    end
    LEM:AddFrame(f, function(_, layout, point, x, y)
        layoutName = layout
        local l = Look(unit)
        l.point, l.x, l.y = point, x, y
    end, UNITS[unit].pos, f.editModeName)

    local function Setting(kind, name, field, extra)
        local s = {
            kind = kind, name = name, default = DEFAULTS[unit][field],
            get = function(layout) layoutName = layout; return Look(unit)[field] end,
            set = function(layout, value)
                layoutName = layout
                Look(unit)[field] = value
                Redo()
                Mirror(unit, field, value) -- (its partner too, when they're the same size)
                if ns.RefreshCast then ns.RefreshCast() end
                if ns.RefreshAuras then ns.RefreshAuras() end
            end,
        }
        for k, v in pairs(extra or {}) do s[k] = v end
        return s
    end

    local settings = {
        Setting(LEM.SettingType.Checkbox, "Hide This Frame", "hidden", {
            desc = "Gone outside Edit Mode; shown faded here so you can bring it back.",
        }),
        Setting(LEM.SettingType.Slider, "Width", "width", { minValue = 60, maxValue = 500, valueStep = 1 }),
        Setting(LEM.SettingType.Slider, "Height", "height", { minValue = 14, maxValue = 120, valueStep = 1 }),
        Setting(LEM.SettingType.Slider, "Power Bar Height", "power", {
            minValue = 0, maxValue = 40, valueStep = 1,
            formatter = function(v) v = math.floor(v + 0.5); return v == 0 and "off" or tostring(v) end,
        }),
        Setting(LEM.SettingType.Dropdown, "Portrait", "portrait", { values = PORTRAITS,
            set = function(layout, value)
                layoutName = layout
                Look(unit).portrait = value
                Redo(true)
                pcall(LEM.RefreshFrameSettings, LEM, f) -- greys Portrait Side in and out
            end,
        }),
        Setting(LEM.SettingType.Dropdown, "Portrait Side", "portraitSide", { values = SIDES,
            disabled = function() return Look(unit).portrait == "off" end,
        }),
        Setting(LEM.SettingType.Dropdown, "Health Text", "healthText", { values = HEALTH_TEXT }),
        Setting(LEM.SettingType.Dropdown, "Power Text", "powerText", { values = HEALTH_TEXT,
            set = function(layout, value)
                layoutName = layout
                Look(unit).powerText = value
                Redo()
                pcall(LEM.RefreshFrameSettings, LEM, f) -- greys its position in and out
            end,
        }),
        Setting(LEM.SettingType.Dropdown, "Power Text Position", "powerTextPos", { values = TEXT_POS,
            disabled = function() return Look(unit).powerText == "none" end,
        }),
        Setting(LEM.SettingType.Slider, "Power Text Nudge Down / Up", "powerTextY", {
            minValue = -40, maxValue = 40, valueStep = 1,
            disabled = function() return Look(unit).powerText == "none" end,
        }),
        Setting(LEM.SettingType.Checkbox, "Incoming Heals", "heals"),
        Setting(LEM.SettingType.Checkbox, isParty and "Debuffs" or "Buffs & Debuffs", "auras", {
            desc = isParty and "A row of debuffs to the right of each party frame, as tall as the frame."
                or "Buffs on top (above the cast bar while one shows), debuffs below. Rows as wide as the frame, up to 3.",
        }),
        Setting(LEM.SettingType.Checkbox, "PvP Flag on the Portrait", "showPvP"),
        Setting(LEM.SettingType.Checkbox, "Show Level", "showLevel"),
        Setting(LEM.SettingType.Checkbox, "Class Colours (players)", "classColor"),
        Setting(LEM.SettingType.Dropdown, "Font", "font", { values = S.FontChoices, height = 300 }),
        Setting(LEM.SettingType.Slider, "Font Size", "fontSize", { minValue = 6, maxValue = 24, valueStep = 1 }),
        {
            kind = LEM.SettingType.Checkbox,
            name = "Hide the Game's Unit Frames",
            desc = "Turning this off brings them back after a /reload.",
            default = true,
            get = function() return DB and DB.hideGame ~= false end,
            set = function(_, value)
                if DB then DB.hideGame = value end
                HideGameFrames()
                for _, other in pairs(frames) do pcall(LEM.RefreshFrameSettings, LEM, other) end
            end,
        },
    }
    -- the target: its cast bar
    if unit == "target" then
        settings[#settings + 1] = Setting(LEM.SettingType.Checkbox, "Cast Bar (enemies)", "castBar", {
            set = function(layout, value)
                layoutName = layout
                Look(unit).castBar = value
                if ns.RefreshCast then ns.RefreshCast() end
                pcall(LEM.RefreshFrameSettings, LEM, f) -- greys its size in and out
            end,
        })
        settings[#settings + 1] = Setting(LEM.SettingType.Slider, "Cast Bar Height", "castHeight", {
            minValue = 8, maxValue = 30, valueStep = 1, disabled = function() return not Look(unit).castBar end,
        })
        settings[#settings + 1] = Setting(LEM.SettingType.Slider, "Cast Bar Gap", "castGap", {
            minValue = 0, maxValue = 20, valueStep = 1, disabled = function() return not Look(unit).castBar end,
        })
    end

    -- yours: the stance tabs
    if unit == "player" then
        settings[#settings + 1] = Setting(LEM.SettingType.Checkbox, "Stance Tabs", "stanceTabs", {
            desc = "Your stances as small tabs on the health bar's top edge; the current one shows its icon. Click one to change.",
            set = function(layout, value)
                layoutName = layout
                Look(unit).stanceTabs = value
                if ns.RefreshStance then ns.RefreshStance() end
            end,
        })
    end

    -- the party: the gap between its frames, and each member's spec
    if isParty then
        table.insert(settings, 5, Setting(LEM.SettingType.Slider, "Spacing", "spacing", {
            minValue = 0, maxValue = 60, valueStep = 1,
        }))
        settings[#settings + 1] = Setting(LEM.SettingType.Checkbox, "Role Icon by the Level", "showRole")
    end

    -- the player and target: "Same Size as ..." under the size sliders
    local partner = Partner(unit)
    if partner then
        table.insert(settings, 5, {
            kind = LEM.SettingType.Checkbox,
            name = "Same Size as " .. (partner == "target" and "Target" or "Player"),
            desc = "Width, height, power bar and font size shared by the player and target frames.",
            default = false,
            get = function(layout) layoutName = layout; return Synced() end,
            set = function(layout, value)
                layoutName = layout
                SetSynced(value, unit)
                for _, other in pairs(frames) do pcall(LEM.RefreshFrameSettings, LEM, other) end
            end,
        })
    end
    LEM:AddFrameSettings(f, settings)

    -- in Spliffbars' options too (Bars: Show the ...)
    S.RegisterPiece({
        module = true, -- (on the Unit Frames page, not Spliffbars' Bars page)
        name = UNITS[unit].piece,
        get = function() return DB and Look(unit).hidden or false end,
        set = function(hidden)
            if not DB then return end
            Look(unit).hidden = hidden
            for _, m in ipairs(members) do Visibility(m) end
            if isParty then HideGameFrames() end
            pcall(LEM.RefreshFrameSettings, LEM, f)
        end,
    })
end

---------------------------------------------------------------------------
-- Its own tab in the options (Spliffbars > Unit Frames): pick a frame at
-- the top, then its look and size. The same settings as Edit Mode, for
-- the layout you're using; frames are moved in Edit Mode.
---------------------------------------------------------------------------
local selected = "player"
if S.AddOptionsTab then
    S.AddOptionsTab("Unit Frames",
        "You, your target, its target and your party. Settings are for the Edit Mode layout you're using; move the frames in Edit Mode.",
        function(page)
            local function Get(field) return function() return Look(selected)[field] end end
            -- the frames the picked one stands for (the party: all four)
            local function Members()
                if selected == "party" then return { frames.party1, frames.party2, frames.party3, frames.party4 } end
                return { frames[selected] }
            end
            local function Apply()
                for _, f in ipairs(Members()) do
                    Place(f)
                    Visibility(f)
                    Paint(f, true)
                end
                pcall(LEM.RefreshFrameSettings, LEM, selected == "party" and partyAnchor or frames[selected])
                if selected == "party" then HideGameFrames() end
                if ns.RefreshCast then ns.RefreshCast() end
                if ns.RefreshAuras then ns.RefreshAuras() end
            end
            local function Set(field)
                return function(v)
                    Look(selected)[field] = v
                    Apply()
                    Mirror(selected, field, v) -- (its partner too, when they're the same size)
                end
            end

            local top = page:Column(16, -74) -- (under the title and its line of text)
            page:Choice(top, nil, {
                { "Player", "player" }, { "Target", "target" }, { "Target of Target", "targettarget" },
                { "Party", "party" },
            }, function() return selected end, function(v) selected = v end)

            local L = page:Column(16, top.y)
            page:Heading(L, "Look")
            page:Check(L, "Show this frame", function() return not Look(selected).hidden end,
                function(v) Look(selected).hidden = not v; Apply() end)
            page:Choice(L, "Portrait", { { "3D", "3d" }, { "2D", "2d" }, { "Off", "off" } },
                Get("portrait"), Set("portrait"))
            page:Choice(L, "Portrait side", { { "Left", "left" }, { "Right", "right" } },
                Get("portraitSide"), Set("portraitSide"), function() return Look(selected).portrait ~= "off" end)
            page:Choice(L, "Health text", { { "Amount & %", "both" }, { "Amount", "current" }, { "%", "percent" },
                { "None", "none" } }, Get("healthText"), Set("healthText"))
            page:Choice(L, "Power text", { { "Amount & %", "both" }, { "Amount", "current" }, { "%", "percent" },
                { "None", "none" } }, Get("powerText"), Set("powerText"), function() return Look(selected).power > 0 end)
            local function powerTextOn()
                local l = Look(selected)
                return l.power > 0 and l.powerText ~= "none"
            end
            page:Choice(L, "Power text position", { { "Left", "left" }, { "Centre", "center" }, { "Right", "right" } },
                Get("powerTextPos"), Set("powerTextPos"), powerTextOn)
            page:Check(L, "Incoming heals (green past the health)", Get("heals"), Set("heals"))
            page:Button(L, "Test Incoming Heals (5 sec)", function() ns.TestHeals() end, 200)
            page:Check(L, "Buffs & debuffs (party: combat debuffs at the right)", Get("auras"), Set("auras"))
            page:Check(L, "Each party member's group role, by their level", function() return Look("party").showRole end,
                function(v) Look("party").showRole = v; Apply() end, nil, function() return selected == "party" end)
            page:Check(L, "PvP flag on the portrait", Get("showPvP"), Set("showPvP"))
            page:Check(L, "Stance tabs on the health bar (yours)", function() return Look("player").stanceTabs ~= false end,
                function(v)
                    Look("player").stanceTabs = v
                    if ns.RefreshStance then ns.RefreshStance() end
                end, nil, function() return selected == "player" end)
            page:Check(L, "Show level", Get("showLevel"), Set("showLevel"))
            page:Check(L, "Class colours for players", Get("classColor"), Set("classColor"))

            page:Heading(L, "Cast Bar (target)")
            local function isTarget() return selected == "target" end
            page:Check(L, "Enemy casts above the target frame", function() return Look("target").castBar end,
                function(v) Look("target").castBar = v; Apply() end, nil, isTarget)

            page:Heading(L, "The Game's Frames")
            page:Check(L, "Hide the game's unit frames", function() return DB and DB.hideGame ~= false end,
                function(v)
                    if DB then DB.hideGame = v end
                    HideGameFrames()
                end)
            page:Note(L, "Bringing them back takes a /reload.", 20)

            local R = page:Column(340, top.y)
            page:Heading(R, "Size")
            local function pair() return selected == "player" or selected == "target" end
            page:Check(R, "Player and target the same size", function() return Synced() end,
                function(v) SetSynced(v, pair() and selected or "player") end, nil, pair)
            page:Slider(R, "Width", 60, 500, 1, Get("width"), Set("width"))
            page:Slider(R, "Height", 14, 120, 1, Get("height"), Set("height"))
            page:Slider(R, "Power bar height", 0, 40, 1, Get("power"), Set("power"),
                function(v) return v == 0 and "off" or tostring(v) end)
            page:Slider(R, "Font size", 6, 24, 1, Get("fontSize"), Set("fontSize"))
            page:Slider(R, "Party spacing", 0, 60, 1, function() return Look("party").spacing end,
                function(v) Look("party").spacing = v; Apply() end, nil, function() return selected == "party" end)
            page:Slider(R, "Power text: down / up", -40, 40, 1, Get("powerTextY"), Set("powerTextY"), nil,
                function() local l = Look(selected); return l.power > 0 and l.powerText ~= "none" end)
            local function castOn() return selected == "target" and Look("target").castBar end
            page:Slider(R, "Cast bar height", 8, 30, 1, function() return Look("target").castHeight end,
                function(v) Look("target").castHeight = v; Apply() end, nil, castOn)
            page:Slider(R, "Cast bar gap", 0, 20, 1, function() return Look("target").castGap end,
                function(v) Look("target").castGap = v; Apply() end, nil, castOn)
            page:Button(R, "Move Frames (Edit Mode)", function() if S.OpenEditMode then S.OpenEditMode() end end, 190)
        end)
end

LEM:RegisterCallback("layout", function(layout)
    layoutName = layout
    UpdateAll()
end)
LEM:RegisterCallback("enter", UpdateAll)
LEM:RegisterCallback("exit", UpdateAll)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("RAID_TARGET_UPDATE")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_UPDATE_RESTING")
for _, e in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE",
    "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_LEVEL",
    "UNIT_FACTION", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_COMBO_POINTS",
    "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_HEAL_PREDICTION", "PLAYER_FLAGS_CHANGED" }) do
    pcall(events.RegisterEvent, events, e) -- not every client has every one
end

events:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= "SpliffFrames" then return end
        SpliffFramesDB = SpliffFramesDB or {}
        DB = SpliffFramesDB
        ns.DB = DB
        layoutName = layoutName or LEM:GetActiveLayoutName()
        HideGameFrames()
        UpdateAll()
        return
    end
    if not DB then return end
    if event == "PLAYER_ENTERING_WORLD" then
        HideGameFrames()
        UpdateAll()
    elseif event == "PLAYER_REGEN_ENABLED" then
        local todo = queue
        queue = {}
        for _, fn in ipairs(todo) do fn() end
        Paint(frames.player)
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_UPDATE_RESTING" then
        Paint(frames.player)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Paint(frames.player)
        Paint(frames.target, true) -- someone new: their portrait too
        Paint(frames.targettarget, true)
    elseif event == "RAID_TARGET_UPDATE" then
        PaintAll()
    elseif event == "GROUP_ROSTER_UPDATE" then
        for _, u in ipairs(PARTY) do Paint(frames[u], true) end -- new faces: portraits too
    elseif not isSecret(a1) and type(a1) == "string" then
        -- a unit event: repaint the frames showing that unit
        local portrait = event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED"
        for _, f in pairs(frames) do
            if f.unit == a1 or (a1 == "player" and f.unit == "target") then Paint(f, portrait and f.unit == a1) end
        end
    end
end)

-- LibHealComm says when heals start, change and stop
do
    local hc = HealComm()
    if hc and hc.RegisterCallback then
        local listener = {}
        local function Changed()
            if not DB then return end
            for _, f in pairs(frames) do
                PaintHeals(f, Look(f.unit))
                PaintBand(f) -- (their heals over time)
            end
        end
        for _, e in ipairs({ "HealComm_HealStarted", "HealComm_HealUpdated", "HealComm_HealDelayed",
            "HealComm_HealStopped", "HealComm_ModifierChanged", "HealComm_GUIDDisappeared" }) do
            pcall(hc.RegisterCallback, listener, e, Changed)
        end
    end
end

-- your heals over time: bandaging (starts, gets pushed back, stops) and
-- Renew / Rejuvenation casts (who they're on comes with "sent"). While any
-- are running, the strips step down a tick at a time and flash as each lands.
local hotWatch = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(hotWatch.RegisterUnitEvent, hotWatch, e, "player")
end
local running = false
hotWatch:SetScript("OnEvent", function(_, event, _, a2, a3, a4)
    if not DB then return end
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        timed.bandage = nil
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        StartBandage(a3) -- (unit, cast, spell)
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- (unit, target's name, cast, spell)
        if not isSecret(a3) and a3 ~= nil then
            local n = 0
            for _ in pairs(sentTo) do n = n + 1 end
            if n > 20 then wipe(sentTo) end -- (casts that never finished)
            sentTo[a3] = a2
        end
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if isSecret(a2) or a2 == nil then return end
        CastHot(a2, a3) -- (unit, cast, spell)
    end
    running = true
    for _, f in pairs(frames) do PaintBand(f) end
end)
local tick = 0
hotWatch:SetScript("OnUpdate", function(_, elapsed)
    if not running or not DB then return end
    tick = tick + elapsed
    if tick < 0.05 then return end
    tick = 0
    for _, f in pairs(frames) do PaintBand(f) end
    if not next(timed) then running = false end -- the last tick is in
end)

-- the target's target has no events of its own: a light check instead
local since = 0
frames.targettarget:HookScript("OnUpdate", function(self, elapsed)
    since = since + elapsed
    if since < 0.2 then return end
    since = 0
    Paint(self)
end)
