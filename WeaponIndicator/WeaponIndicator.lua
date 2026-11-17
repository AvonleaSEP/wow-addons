-- Weapon Indicator
-- A small badge showing what you're holding: Shield, Two-Hand, Dual Wield,
-- One-Hand, Off-Hand (a held-in-off-hand item) or Unarmed, with the weapon
-- icons beside it.
--
-- Moving it: open Edit Mode (Esc > Edit Mode) and it shows up like any
-- Blizzard frame. Drag it, or click it for its settings panel (size, icons,
-- label, exact position, reset). Each Edit Mode layout keeps its own spot.
-- It starts above your character portrait.
--
-- Edit Mode support comes from LibEditMode by p3lim (Libs\LibEditMode).

---------------------------------------------------------------------------
-- Defaults: a new Edit Mode layout starts with these
---------------------------------------------------------------------------
local DEFAULTS   = {
    scale = 1, icons = true, label = true,
    iconSize = 22,       -- weapon icon size in pixels, at 100% size
    iconGap = 2,         -- between the two weapon icons
    textPos = "BELOW",   -- the label: BELOW, ABOVE, LEFT or RIGHT of the icons
    textGap = 2,         -- between the icons and the label
    textSize = 10, font = "Game default", outline = "", textColor = "gear",
}

-- fonts: the game's own plus any shared by other addons (LibSharedMedia)
local GAME_FONTS = {
    { "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" }, { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\SKURRI.TTF" }, { "Morpheus", "Fonts\\MORPHEUS.TTF" },
}
local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end
local function FontPath(name)
    if name and name ~= "Game default" then
        local lsm = LSM()
        local path = lsm and lsm:Fetch("font", name, true)
        if path then return path end
        for _, f in ipairs(GAME_FONTS) do if f[1] == name then return f[2] end end
    end
    return (GameFontNormalSmall:GetFont())
end
local function FontChoices()
    local list, seen, values = {}, { ["Game default"] = true }, { { text = "Game default", value = "Game default" } }
    local lsm = LSM()
    if lsm then for _, n in ipairs(lsm:List("font")) do list[#list + 1] = n end end
    for _, f in ipairs(GAME_FONTS) do list[#list + 1] = f[1] end
    table.sort(list)
    for _, n in ipairs(list) do
        if not seen[n] then seen[n] = true; values[#values + 1] = { text = n, value = n } end
    end
    return values
end

-- label and colour for each state
local STATES = {
    shield  = { "Shield",     0.45, 0.75, 1.00 },
    twohand = { "Two-Hand",   1.00, 0.55, 0.25 },
    dual    = { "Dual Wield", 0.40, 1.00, 0.40 },
    onehand = { "One-Hand",   1.00, 0.82, 0.00 },
    held    = { "Off-Hand",   1.00, 0.82, 0.00 },
    none    = { "Unarmed",    0.60, 0.60, 0.60 },
}

---------------------------------------------------------------------------
local LEM = LibStub("LibEditMode")
local MAIN, OFF = 16, 17 -- equipment slots
local isSecret = issecretvalue or function() return false end
local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- What kind of item is in a slot (INVTYPE_SHIELD, INVTYPE_2HWEAPON, ...),
-- "UNKNOWN" if something is there but the game won't say what, nil if empty.
local function SlotKind(slot)
    local id = GetInventoryItemID("player", slot)
    if id == nil then return nil end
    if isSecret(id) or not getInstant then return "UNKNOWN" end
    local ok, _, _, _, loc = pcall(getInstant, id)
    if not ok or loc == nil or isSecret(loc) then return "UNKNOWN" end
    return loc
end

local OFFHAND_WEAPON = {
    INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_WEAPONMAINHAND = true, INVTYPE_2HWEAPON = true, -- Titan's Grip
}
local TWO_HANDED = {
    INVTYPE_2HWEAPON = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
}

-- What the item in a slot is, in a word ("Axe", "Sword", "Shield"), nil if
-- empty or unknown. Two-handed ones say so ("Two-Hand Axe").
local WEAPON_WORDS = {
    [0] = "Axe", [1] = "Two-Hand Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Two-Hand Mace",
    [6] = "Polearm", [7] = "Sword", [8] = "Two-Hand Sword", [10] = "Staff", [13] = "Fist Weapon",
    [15] = "Dagger", [16] = "Thrown", [18] = "Crossbow", [19] = "Wand", [20] = "Fishing Pole",
}
local function SlotWord(slot)
    local id = GetInventoryItemID("player", slot)
    if id == nil or isSecret(id) or not getInstant then return nil end
    local ok, _, _, _, loc, _, classID, subclassID = pcall(getInstant, id)
    if not ok or isSecret(classID) or isSecret(subclassID) then return nil end
    if classID == 2 then return WEAPON_WORDS[subclassID] end
    if classID == 4 and subclassID == 6 then return "Shield" end
    if loc == "INVTYPE_HOLDABLE" then return "Off-Hand" end
    return nil
end

-- the label: "Two-Hand Axe", "Axe and Shield", "Axe and Sword", "Dual
-- Daggers", "Mace"...; nil if the game won't say what something is
local function Detail(state)
    if state == "none" then return nil end
    local main, off = SlotWord(MAIN), SlotWord(OFF)
    if state == "twohand" or state == "onehand" then return main end
    if not main then return off end
    if not off then return nil end
    if main == off then return "Dual " .. (main:gsub("y$", "ie")) .. "s" end
    return main .. " and " .. off
end

local function CurrentState()
    local main, off = SlotKind(MAIN), SlotKind(OFF)
    if off == "INVTYPE_SHIELD" then return "shield" end
    if off and OFFHAND_WEAPON[off] then return "dual" end
    if main and TWO_HANDED[main] then return "twohand" end
    if off then return "held" end
    if main then return "onehand" end
    return "none"
end

---------------------------------------------------------------------------
-- Saved settings, one set per Edit Mode layout
---------------------------------------------------------------------------
local layoutName -- the Edit Mode layout in use

local function Layout()
    WeaponIndicatorDB = WeaponIndicatorDB or {}
    WeaponIndicatorDB.layouts = WeaponIndicatorDB.layouts or {}
    local key = layoutName or "Default"
    local l = WeaponIndicatorDB.layouts[key]
    if not l then
        l = {}
        WeaponIndicatorDB.layouts[key] = l
    end
    for k, v in pairs(DEFAULTS) do
        if l[k] == nil then l[k] = v end
    end
    return l
end

---------------------------------------------------------------------------
-- The badge (the name is what Edit Mode shows on it)
---------------------------------------------------------------------------
local badge = CreateFrame("Frame", "WeaponIndicatorFrame", UIParent)
badge.editModeName = "Weapon Indicator"
badge:SetFrameStrata("MEDIUM")
badge:SetClampedToScreen(true)
badge:SetSize(50, 36)

-- true while the game waits for you to pick an item (a sharpening stone,
-- weightstone, poison or oil you just used)
local function Targeting()
    if not SpellIsTargeting then return false end
    local ok, t = pcall(SpellIsTargeting)
    return ok and not isSecret(t) and t == true
end

-- A weapon icon, with a button over it: hover for the weapon's tooltip
-- (with how long its stone or oil lasts); while a stone etc. is waiting for
-- a weapon, the icon glows and a click puts it on that weapon.
--
-- Putting a stone on a weapon is protected, so the button is one of the
-- game's secure buttons, set to "use the item in this slot" (like the
-- "/use 16" macro line): with a stone waiting, that applies the stone. It
-- sits on its own (not anchored to the badge, which changes size when you
-- swap weapons in a fight) and is lined up over the icon out of combat.
local function Icon(slot)
    local border = badge:CreateTexture(nil, "BACKGROUND")
    border:SetSize(DEFAULTS.iconSize + 2, DEFAULTS.iconSize + 2)
    border:SetColorTexture(0, 0, 0, 0.9)
    local tex = badge:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", border, "TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex.border = border

    local btn = CreateFrame("Button", "WeaponIndicatorSlot" .. slot, UIParent, "SecureActionButtonTemplate")
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(badge:GetFrameLevel() + 10)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetAttribute("type1", "item")
    btn:SetAttribute("item", tostring(slot))
    btn:SetAttribute("checkselfcast", false)
    btn:SetAttribute("checkfocuscast", false)
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:Hide()
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip:SetInventoryItem("player", slot) then
            if Targeting() then
                GameTooltip:AddLine("Click to put it on this weapon", 0.4, 1, 0.4)
            elseif self:GetAttribute("type1") == "spell" then
                GameTooltip:AddLine("Click to fish", 0.4, 0.8, 1)
            end
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- the glow while a stone is waiting for a weapon (on the badge, so it
    -- follows the icon even mid-fight)
    local glow = badge:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", border, "TOPLEFT", -6, 6)
    glow:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 6, -6)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.4, 1, 0.4)
    glow:Hide()
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.6)
    glow.pulse = pulse

    tex.button, tex.glow = btn, glow
    return tex
end

local mainIcon, offIcon = Icon(MAIN), Icon(OFF)

-- What a click on the main-hand icon does: with a fishing pole in hand it
-- casts Fishing, except while a lure etc. waits for a weapon (then it goes
-- on the pole, like a stone on a weapon). Set out of combat only.
local FISHING_SPELL = 7620
local function FishingName()
    local ok, n
    if C_Spell and C_Spell.GetSpellName then ok, n = pcall(C_Spell.GetSpellName, FISHING_SPELL)
    elseif GetSpellInfo then ok, n = pcall(GetSpellInfo, FISHING_SPELL) end
    if ok and type(n) == "string" and not isSecret(n) then return n end
    return "Fishing"
end
local function SetClickAction()
    if InCombatLockdown() then return false end
    local btn = mainIcon.button
    if SlotWord(MAIN) == "Fishing Pole" and not Targeting() then
        btn:SetAttribute("type1", "spell")
        btn:SetAttribute("spell", FishingName())
    else
        btn:SetAttribute("type1", "item")
        btn:SetAttribute("spell", nil)
    end
    return true
end

-- line the secure buttons up over the icons (out of combat; in a fight it
-- waits for the end). Hidden while Edit Mode is open, so the badge drags.
local syncPending = false
local function Sync()
    if InCombatLockdown() then syncPending = true; return end
    syncPending = false
    SetClickAction()
    local editing = LEM:IsInEditMode()
    local k = UIParent:GetEffectiveScale()
    for _, icon in ipairs({ mainIcon, offIcon }) do
        local btn, border = icon.button, icon.border
        local cx, cy = border:GetCenter()
        if not editing and border:IsShown() and cx and not isSecret(cx) then
            local s = border:GetEffectiveScale() / k
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * s, cy * s)
            btn:SetSize(border:GetWidth() * s, border:GetHeight() * s)
            btn:Show()
        else
            btn:Hide()
        end
    end
end
-- (after the badge has been laid out)
local function SyncSoon() C_Timer.After(0, Sync) end

-- glow the weapon icons you can click while a stone etc. waits for a weapon
local function UpdateGlow()
    local t = Targeting()
    -- a lure waiting goes on the pole; otherwise the pole fishes
    if not SetClickAction() then syncPending = true end
    for _, icon in ipairs({ mainIcon, offIcon }) do
        local on = t and icon.border:IsShown()
        icon.glow:SetShown(on)
        if on then icon.glow.pulse:Play() else icon.glow.pulse:Stop() end
    end
end
local label = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetShadowOffset(1, -1)

-- lay out the icons and the label (Edit Mode: Icon Size, Icon Spacing,
-- Text Position, Text Distance, Text Size, Font, Outline)
local function Arrange(l)
    -- the icons showing, left to right
    local icons = {}
    for _, icon in ipairs({ mainIcon, offIcon }) do
        icon.border:ClearAllPoints()
        if icon.border:IsShown() then icons[#icons + 1] = icon.border end
    end
    label:ClearAllPoints()
    local size = l.iconSize + 2
    for _, b in ipairs(icons) do b:SetSize(size, size) end
    local gw = #icons > 0 and (#icons * size + (#icons - 1) * l.iconGap) or 0
    local gh = #icons > 0 and size or 0
    local showLabel = l.label and label:GetText() ~= nil
    local lw = showLabel and label:GetStringWidth() or 0
    local lh = showLabel and label:GetStringHeight() or 0
    local gap = (#icons > 0 and showLabel) and l.textGap or 0
    local pos = l.textPos

    -- the first icon's spot; the rest follow it to the right
    local function PlaceIcons(point, rel, x, y)
        if #icons == 0 then return end
        icons[1]:SetPoint(point, badge, rel, x, y)
        for i = 2, #icons do icons[i]:SetPoint("LEFT", icons[i - 1], "RIGHT", l.iconGap, 0) end
    end

    local w, h
    if pos == "LEFT" or pos == "RIGHT" then
        w, h = lw + gap + gw, math.max(gh, lh)
        if pos == "LEFT" then
            if showLabel then label:SetPoint("LEFT", badge, "LEFT", 0, 0) end
            PlaceIcons("LEFT", "RIGHT", -gw, 0)
        else
            PlaceIcons("LEFT", "LEFT", 0, 0)
            if showLabel then label:SetPoint("RIGHT", badge, "RIGHT", 0, 0) end
        end
    else
        w, h = math.max(gw, lw), gh + gap + lh
        if pos == "ABOVE" then
            if showLabel then label:SetPoint("TOP", badge, "TOP", 0, 0) end
            PlaceIcons("BOTTOMLEFT", "BOTTOM", -gw / 2, 0)
        else
            PlaceIcons("TOPLEFT", "TOP", -gw / 2, 0)
            if showLabel then label:SetPoint("BOTTOM", badge, "BOTTOM", 0, 0) end
        end
    end
    badge:SetSize(math.max(w, 12), math.max(h, 12))
end

local function Refresh()
    local l = Layout()
    badge:SetScale(l.scale)

    local key = CurrentState()
    local state = STATES[key]
    -- what's equipped by name ("Axe and Shield"), else the general kind
    label:SetText(Detail(key) or state[1])
    if l.textColor == "white" then label:SetTextColor(1, 1, 1)
    elseif l.textColor == "gold" then label:SetTextColor(1, 0.82, 0)
    else label:SetTextColor(state[2], state[3], state[4]) end -- by what you hold
    label:SetFont(FontPath(l.font), l.textSize, l.outline or "")
    if not label:GetFont() then label:SetFont(FontPath(nil), l.textSize, l.outline or "") end

    local mainTex = GetInventoryItemTexture("player", MAIN)
    local offTex = GetInventoryItemTexture("player", OFF)
    if isSecret(mainTex) then mainTex = nil end
    if isSecret(offTex) then offTex = nil end

    local showMain = l.icons and (mainTex ~= nil or offTex == nil)
    mainIcon:SetTexture(mainTex or "Interface\\Icons\\INV_Gauntlets_04") -- fist when unarmed
    mainIcon:SetShown(showMain)
    mainIcon.border:SetShown(showMain)

    local showOff = l.icons and offTex ~= nil
    offIcon:SetTexture(offTex)
    offIcon:SetShown(showOff)
    offIcon.border:SetShown(showOff)

    label:SetShown(l.label)
    Arrange(l)
    UpdateGlow()
    SyncSoon()
end

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------
-- Starts just above your character portrait. LibEditMode keeps a reference
-- to this table, so filling it in later also fixes its "Reset Position".
local default = { point = "CENTER", x = 0, y = 200 }

local function FindDefault()
    local portrait = _G.PlayerPortrait
        or (PlayerFrame and PlayerFrame.PlayerFrameContainer and PlayerFrame.PlayerFrameContainer.PlayerPortrait)
        or (PlayerFrame and PlayerFrame.portrait)
        or PlayerFrame
    local cx = portrait and portrait.GetCenter and portrait:GetCenter()
    local top = portrait and portrait.GetTop and portrait:GetTop()
    if not cx or not top or isSecret(cx) or isSecret(top) then return end
    -- portrait's coordinates -> offsets from the centre of the screen, in the badge's scale
    local k = portrait:GetEffectiveScale() / badge:GetEffectiveScale()
    local ux, uy = UIParent:GetCenter()
    local uk = UIParent:GetEffectiveScale() / badge:GetEffectiveScale()
    default.point = "CENTER"
    default.x = cx * k - ux * uk
    default.y = top * k - uy * uk + 4 + badge:GetHeight() / 2
end

local function Place()
    local l = Layout()
    badge:ClearAllPoints()
    if l.point then
        badge:SetPoint(l.point, UIParent, l.point, l.x, l.y)
    else
        badge:SetPoint(default.point, UIParent, default.point, default.x, default.y)
    end
    SyncSoon()
end

-- Edit Mode moved it (drag, arrow keys, the x/y boxes, or Reset Position)
local function OnMoved(_, layout, point, x, y)
    layoutName = layout
    local l = Layout()
    l.point, l.x, l.y = point, x, y
    SyncSoon()
end

LEM:AddFrame(badge, OnMoved, default)
-- the click buttons step aside while Edit Mode is open, so the badge drags
LEM:RegisterCallback("enter", Sync)
LEM:RegisterCallback("exit", SyncSoon)

local function Setting(kind, name, key, extra)
    local s = {
        kind = kind,
        name = name,
        default = DEFAULTS[key],
        get = function(layout)
            layoutName = layout
            return Layout()[key]
        end,
        set = function(layout, value)
            layoutName = layout
            Layout()[key] = value
            Refresh()
        end,
    }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

LEM:AddFrameSettings(badge, {
    Setting(LEM.SettingType.Slider, "Size", "scale", {
        minValue = 0.5, maxValue = 2, valueStep = 0.05,
        formatter = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
    }),
    Setting(LEM.SettingType.Checkbox, "Show Weapon Icons", "icons"),
    Setting(LEM.SettingType.Slider, "Icon Size", "iconSize", {
        minValue = 10, maxValue = 64, valueStep = 1,
        disabled = function() return not Layout().icons end,
    }),
    Setting(LEM.SettingType.Slider, "Icon Spacing", "iconGap", {
        minValue = 0, maxValue = 20, valueStep = 1,
        disabled = function() return not Layout().icons end,
    }),
    Setting(LEM.SettingType.Checkbox, "Show Label", "label"),
    Setting(LEM.SettingType.Dropdown, "Text Position", "textPos", { values = {
        { text = "Below the icons", value = "BELOW" }, { text = "Above the icons", value = "ABOVE" },
        { text = "Left of the icons", value = "LEFT" }, { text = "Right of the icons", value = "RIGHT" },
    }, disabled = function() return not Layout().label end }),
    Setting(LEM.SettingType.Slider, "Text Distance", "textGap", {
        minValue = -10, maxValue = 30, valueStep = 1,
        disabled = function() return not Layout().label end,
    }),
    Setting(LEM.SettingType.Slider, "Text Size", "textSize", {
        minValue = 6, maxValue = 24, valueStep = 1,
        disabled = function() return not Layout().label end,
    }),
    Setting(LEM.SettingType.Dropdown, "Font", "font", { values = FontChoices, height = 300,
        disabled = function() return not Layout().label end }),
    Setting(LEM.SettingType.Dropdown, "Outline", "outline", { values = {
        { text = "None", value = "" }, { text = "Outline", value = "OUTLINE" }, { text = "Thick", value = "THICKOUTLINE" },
    }, disabled = function() return not Layout().label end }),
    Setting(LEM.SettingType.Dropdown, "Text Colour", "textColor", { values = {
        { text = "By what you hold", value = "gear" }, { text = "White", value = "white" }, { text = "Gold", value = "gold" },
    }, disabled = function() return not Layout().label end }),
})

-- switching Edit Mode layouts (or the layout loading after login)
LEM:RegisterCallback("layout", function(layout)
    layoutName = layout
    Refresh()
    Place()
end)

SLASH_WEAPONINDICATOR1 = "/weapons"
SlashCmdList.WEAPONINDICATOR = function()
    print("|cffc79c6eWeapon Indicator|r move and size it in Edit Mode (Esc > Edit Mode).")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
badge:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
badge:RegisterEvent("PLAYER_ENTERING_WORLD")
badge:RegisterEvent("CURRENT_SPELL_CAST_CHANGED") -- a stone starts / stops waiting for a weapon
badge:RegisterEvent("PLAYER_REGEN_ENABLED")
badge:SetScript("OnEvent", function(_, event, slot)
    if event == "CURRENT_SPELL_CAST_CHANGED" then
        UpdateGlow()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if syncPending then Sync() end
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        if slot == nil or slot == MAIN or slot == OFF then Refresh() end
        return
    end
    Refresh()
    Place()
    -- Edit Mode places the player frame after login; until you move the
    -- badge, find the portrait again once things have settled.
    if C_Timer then
        C_Timer.After(1, function()
            FindDefault()
            if not Layout().point and not LEM:IsInEditMode() then Place() end
        end)
    end
end)
