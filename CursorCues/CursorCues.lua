-- Cursor Cues
-- Little icons that follow your mouse, each one a "cue" you set up in the
-- settings window (/cues, or Options > AddOns > Cursor Cues):
--
--   Buff missing on me        e.g. Battle Shout, a food buff
--   My buff missing on group  e.g. Oath of Light: yours isn't on anyone
--   Ability ready             e.g. Overpower / Revenge, or any cooldown
--   Tracking off              e.g. Find Minerals / Find Herbs
--
-- Each cue has its own spells, when it shows (in combat, out of combat,
-- always), look (steady, pulse, flash), size, brightness and spot. Cues
-- higher in the list win when two want the same spot.
--
-- This client (WoW Forever on the Midnight client) hides buffs from addons
-- during combat and can hide cooldowns. So buff cues note, out of combat,
-- when the buff runs out and go by that time in combat (restarted when you
-- cast the spell). When nothing is known, a cue stays hidden rather than
-- guessing.

local PREFIX = "|cffc79c6eCursor Cues|r "
local UPDATE_INTERVAL = 0.1
local MAX_CUES = 14
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- icons for when the game can't give one
local FALLBACK_ICONS = {
    ["Battle Shout"]  = "Interface\\Icons\\Ability_Warrior_BattleShout",
    ["Overpower"]     = "Interface\\Icons\\Ability_MeleeDamage",
    ["Revenge"]       = "Interface\\Icons\\Ability_Warrior_Revenge",
    ["Find Minerals"] = "Interface\\Icons\\Spell_Nature_Earthquake",
    ["Find Herbs"]    = "Interface\\Icons\\INV_Misc_Flower_02",
    ["Oath of Light"] = "Interface\\Icons\\Spell_Holy_HolyBolt",
}

-- The starting list (your cues from before the settings window).
local DEFAULT_CUES = {
    { name = "Overpower / Revenge", type = "ready", spells = "Overpower, Revenge",
      when = "always", style = "pulse", x = 0, y = 32, size = 36, alpha = 1,
      needTarget = true, hiddenCooldownOK = true },
    { name = "Battle Shout", type = "buff", spells = "Battle Shout",
      when = "combat", style = "steady", x = 0, y = 32, size = 36, alpha = 1,
      greyNoResource = true, requireKnown = true },
    { name = "Find Minerals / Herbs", type = "tracking", spells = "Find Minerals, Find Herbs",
      when = "nocombat", style = "steady", x = -32, y = -32, size = 36, alpha = 1 },
    { name = "Oath of Light", type = "groupbuff", spells = "Oath of Light",
      when = "combat", style = "steady", x = 32, y = -32, size = 36, alpha = 1 },
    { name = "Food buff", type = "buff", spells = "",
      buffs = "Well Fed, Mana Regeneration, Increased Agility, Increased Intellect",
      icon = "Interface\\Icons\\Spell_Misc_Food", requireKnown = false,
      when = "combat", style = "flash", every = 10, x = 0, y = -46, size = 26, alpha = 0.6 },
}

local NEW_CUE = { name = "New cue", type = "buff", spells = "", when = "combat", style = "steady",
    x = 0, y = 32, size = 36, alpha = 1, every = 10, requireKnown = true }

---------------------------------------------------------------------------
-- Game helpers. Every value is checked with issecretvalue before use:
-- comparing or testing a hidden ("secret") value is a Lua error.
---------------------------------------------------------------------------
local isSecret = issecretvalue or function() return false end
local function Num(v) return not isSecret(v) and type(v) == "number" end

local function PlayerKnows(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if not ok or isSecret(info) then return false end
        return info ~= nil
    elseif GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, name)
        if not ok or isSecret(n) then return false end
        return n ~= nil
    end
    return true
end

local function SpellTexture(name)
    local ok, tex
    if C_Spell and C_Spell.GetSpellTexture then
        ok, tex = pcall(C_Spell.GetSpellTexture, name)
    elseif GetSpellTexture then
        ok, tex = pcall(GetSpellTexture, name)
    end
    if not ok or tex == nil or isSecret(tex) then return FALLBACK_ICONS[name] or QUESTION end
    return tex
end

-- true / false, or nil when the game is hiding the answer
local function SpellUsable(name)
    local ok, usable
    if C_Spell and C_Spell.IsSpellUsable then
        ok, usable = pcall(C_Spell.IsSpellUsable, name)
    elseif IsUsableSpell then
        ok, usable = pcall(IsUsableSpell, name)
    end
    if not ok or isSecret(usable) then return nil end
    return usable and true or false
end

-- true / false, or nil when hidden. The global cooldown doesn't count.
local function OnCooldown(name)
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, name)
        if not ok or isSecret(info) then return nil end
        if not info then return false end
        start, duration = info.startTime, info.duration
    elseif GetSpellCooldown then
        local ok
        ok, start, duration = pcall(GetSpellCooldown, name)
        if not ok then return nil end
    else
        return nil
    end
    if isSecret(start) or isSecret(duration) then return nil end
    if not start or not duration then return false end
    return duration > 1.5 and (start + duration - GetTime()) > 0
end

local function SpellNameFromID(spellID)
    local ok, n
    if C_Spell and C_Spell.GetSpellName then
        ok, n = pcall(C_Spell.GetSpellName, spellID)
    elseif GetSpellInfo then
        ok, n = pcall(GetSpellInfo, spellID)
    end
    if not ok or isSecret(n) then return nil end
    return n
end

local function HasEnemyTarget()
    local canAttack = UnitCanAttack("player", "target")
    if isSecret(canAttack) or not canAttack then return false end
    local dead = UnitIsDead("target")
    if isSecret(dead) then return true end
    return not dead
end

-- true / false, or nil when the game won't say. Newer clients list every
-- tracking type with an on/off flag; older ones only report the icon of the
-- one that's on.
local function TrackingOn(name)
    local count
    if C_Minimap and C_Minimap.GetNumTrackingTypes then
        local ok, n = pcall(C_Minimap.GetNumTrackingTypes)
        if ok then count = n end
    elseif GetNumTrackingTypes then
        local ok, n = pcall(GetNumTrackingTypes)
        if ok then count = n end
    end
    local getInfo = (C_Minimap and C_Minimap.GetTrackingInfo) or GetTrackingInfo
    if getInfo and Num(count) then
        for i = 1, count do
            local ok, a, _, c = pcall(getInfo, i)
            if ok and a ~= nil and not isSecret(a) then
                local n, active
                if type(a) == "table" then n, active = a.name, a.active else n, active = a, c end
                if not isSecret(n) and not isSecret(active) and n == name then
                    return active and true or false
                end
            end
        end
    end
    if GetTrackingTexture then
        local ok, tex = pcall(GetTrackingTexture)
        if ok and not isSecret(tex) then
            if tex == nil then return false end
            local fallback = FALLBACK_ICONS[name]
            return tex == SpellTexture(name) or tex == fallback
                or (GetFileIDFromPath ~= nil and fallback ~= nil and tex == GetFileIDFromPath(fallback))
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Cue data
---------------------------------------------------------------------------
local DB -- CursorCuesDB

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local listCache = {}
local function List(s) -- "A, B" -> { "A", "B" }, cached
    s = s or ""
    local l = listCache[s]
    if not l then
        l = {}
        for part in s:gmatch("[^,]+") do
            local t = trim(part)
            if t ~= "" then l[#l + 1] = t end
        end
        listCache[s] = l
    end
    return l
end

local function Spells(cue) return List(cue.spells) end
local function Buffs(cue)
    local b = List(cue.buffs)
    if #b > 0 then return b end
    return Spells(cue)
end

local function CueIcon(cue, which)
    local ic = trim(cue.icon)
    if ic ~= "" then
        local id = tonumber(ic)
        if id then return id end
        if ic:find("[\\/]") then return ic end
        return SpellTexture(ic)
    end
    local name = which or Spells(cue)[1] or Buffs(cue)[1]
    return name and SpellTexture(name) or QUESTION
end

local state = setmetatable({}, { __mode = "k" }) -- per-cue timers
local function State(cue)
    local st = state[cue]
    if not st then st = { nextFlash = 0, nextRead = 0 }; state[cue] = st end
    return st
end

local function Duration(name, fallback)
    return DB and DB.durations and DB.durations[name] or fallback
end
local function NoteDuration(name, dur)
    if name and Num(dur) and dur > 0 and DB then
        DB.durations = DB.durations or {}
        DB.durations[name] = dur
    end
end

---------------------------------------------------------------------------
-- Reading buffs (out of combat only; in combat they're hidden)
---------------------------------------------------------------------------
-- your buffs: { [name] = { exp = expirationTime or nil, dur = duration or nil } },
-- or nil when they can't be read
local function PlayerAuras()
    if InCombatLockdown() then return nil end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local snap = {}
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or isSecret(aura) then return nil end
        if not aura then break end
        local n = aura.name
        if isSecret(n) then return nil end
        local exp, dur = aura.expirationTime, aura.duration
        snap[n] = { exp = (Num(exp) and exp > 0) and exp or nil, dur = (Num(dur) and dur > 0) and dur or nil }
    end
    return snap
end

local function GroupUnits()
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do units[#units + 1] = "raid" .. i end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    return units
end

-- is one of YOUR buffs in `set` on anyone in the group?
-- returns found, expirationTime, duration; or nil when hidden
local function ScanGroup(set)
    local hidden = false
    for _, unit in ipairs(GroupUnits()) do
        local exists = UnitExists(unit)
        if not isSecret(exists) and exists then
            for i = 1, 40 do
                local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL|PLAYER")
                if not ok or isSecret(aura) then hidden = true break end
                if not aura then break end
                local n = aura.name
                if isSecret(n) then hidden = true break end
                if set[n] then
                    local exp, dur = aura.expirationTime, aura.duration
                    return true, (Num(exp) and exp > 0) and exp or nil, (Num(dur) and dur > 0) and dur or nil
                end
            end
        end
    end
    if hidden then return nil end
    return false
end

---------------------------------------------------------------------------
-- Deciding whether each cue shows
---------------------------------------------------------------------------
local glowing = {} -- spell name -> true while the game lights it up on your bars

local function WhenOK(cue)
    local c = InCombatLockdown()
    if cue.when == "combat" then return c end
    if cue.when == "nocombat" then return not c end
    return true
end

-- buff on you: true = missing; false = there or unknown
local function BuffMissing(cue, st, snap)
    local buffs = Buffs(cue)
    if #buffs == 0 then return false end
    if snap then
        for _, b in ipairs(buffs) do
            local a = snap[b]
            if a then
                NoteDuration(buffs[1], a.dur)
                st.expires = a.exp or (GetTime() + 3600) -- no timer: treat as lasting
                return false
            end
        end
        st.expires = 0
        return true
    end
    if st.expires == nil then return false end -- don't guess
    return GetTime() >= st.expires
end

local function GroupMissing(cue, st)
    local buffs = Buffs(cue)
    if #buffs == 0 then return false end
    if cue.onlyGroup and not (IsInGroup and IsInGroup()) then return false end
    local now = GetTime()
    if not InCombatLockdown() and C_UnitAuras and now >= st.nextRead then
        st.nextRead = now + 0.5 -- the group scan runs twice a second
        local set = {}
        for _, b in ipairs(buffs) do set[b] = true end
        local found, exp, dur = ScanGroup(set)
        if found then
            NoteDuration(buffs[1], dur)
            st.expires = exp or (now + 3600)
        elseif found == false then
            st.expires = 0
        end
    end
    if st.expires == nil then return false end
    return now >= st.expires
end

-- returns show, spellNameForIcon, grey
local function Evaluate(cue, snap)
    local st = State(cue)
    local onTaxi = UnitOnTaxi("player")
    local t = cue.type
    if t == "buff" then
        local spells = Spells(cue)
        if cue.requireKnown ~= false and spells[1] and not PlayerKnows(spells[1]) then return false end
        local missing = BuffMissing(cue, st, snap) -- always runs: keeps the timer current
        if not missing or onTaxi or not WhenOK(cue) then return false end
        local grey = cue.greyNoResource and spells[1] and SpellUsable(spells[1]) == false
        return true, nil, grey
    elseif t == "groupbuff" then
        local spells = Spells(cue)
        if spells[1] and not PlayerKnows(spells[1]) then return false end
        local missing = GroupMissing(cue, st)
        if not missing or not WhenOK(cue) then return false end
        return true
    elseif t == "ready" then
        if onTaxi or not WhenOK(cue) then return false end
        if cue.needTarget and not HasEnemyTarget() then return false end
        for _, name in ipairs(Spells(cue)) do
            if PlayerKnows(name) then
                if glowing[name] then return true, name end
                if SpellUsable(name) == true then
                    local cd = OnCooldown(name)
                    if cd == false or (cd == nil and cue.hiddenCooldownOK) then return true, name end
                end
            end
        end
        return false
    elseif t == "tracking" then
        if not WhenOK(cue) then return false end
        local missing
        for _, name in ipairs(Spells(cue)) do
            if PlayerKnows(name) then
                local on = TrackingOn(name)
                if on == true then return false end
                if on == false and not missing then missing = name end
            end
        end
        if missing then return true, missing end
        return false
    end
    return false
end

---------------------------------------------------------------------------
-- The icons at the cursor
---------------------------------------------------------------------------
local frames = setmetatable({}, { __mode = "k" })

local function ApplyLook(f, cue)
    f:SetSize(cue.size or 36, cue.size or 36)
    local a = cue.alpha or 1
    f.pulseFade:SetFromAlpha(a)
    f.pulseFade:SetToAlpha(a * 0.35)
    f.fIn:SetToAlpha(a)
    f.fHold:SetFromAlpha(a)
    f.fHold:SetToAlpha(a)
    f.fOut:SetFromAlpha(a)
end

local function GetFrame(cue)
    local f = frames[cue]
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:EnableMouse(false) -- never blocks your clicks
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.pulse = f:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    f.pulseFade = f.pulse:CreateAnimation("Alpha")
    f.pulseFade:SetDuration(0.35)

    -- flash: fade in, hold, fade out, about a second
    f.flash = f:CreateAnimationGroup()
    f.fIn = f.flash:CreateAnimation("Alpha"); f.fIn:SetFromAlpha(0); f.fIn:SetDuration(0.3); f.fIn:SetOrder(1)
    f.fHold = f.flash:CreateAnimation("Alpha"); f.fHold:SetDuration(0.35); f.fHold:SetOrder(2)
    f.fOut = f.flash:CreateAnimation("Alpha"); f.fOut:SetToAlpha(0); f.fOut:SetDuration(0.35); f.fOut:SetOrder(3)
    f.flash:SetScript("OnFinished", function() f:Hide() end)

    f:Hide()
    ApplyLook(f, cue)
    frames[cue] = f
    return f
end

local function HideFrame(f)
    f.pulse:Stop()
    f.flash:Stop()
    f:Hide()
end

local previewing = false -- true while the settings window is open with Preview on

local function Display(f, cue, show, iconName, grey)
    local st = State(cue)
    if not show then
        HideFrame(f)
        st.nextFlash = GetTime() + 1.5 -- a flash cue's first flash comes shortly after it starts
        return
    end
    f.tex:SetTexture(CueIcon(cue, iconName))
    f.tex:SetDesaturated(grey and true or false)
    local style = previewing and "steady" or cue.style
    if style == "pulse" then
        f.flash:Stop()
        if not f.pulse:IsPlaying() then f:SetAlpha(cue.alpha or 1); f:Show(); f.pulse:Play() end
    elseif style == "flash" then
        f.pulse:Stop()
        local now = GetTime()
        if now >= st.nextFlash then
            st.nextFlash = now + (cue.every or 10)
            f:SetAlpha(0)
            f:Show()
            f.flash:Stop()
            f.flash:Play()
        end
    else
        f.pulse:Stop()
        f.flash:Stop()
        f:SetAlpha(cue.alpha or 1)
        f:Show()
    end
end

local function UpdateState()
    if not DB then return end
    local snap = PlayerAuras()
    local dead = UnitIsDeadOrGhost("player")
    local used, inList = {}, {}
    for _, cue in ipairs(DB.cues) do
        inList[cue] = true
        local f = GetFrame(cue)
        local show, iconName, grey = false, nil, nil
        if DB.enabled and cue.enabled ~= false then
            if previewing then
                show = true
            elseif not dead then
                show, iconName, grey = Evaluate(cue, snap)
            end
        end
        local spot = (cue.x or 0) .. "," .. (cue.y or 0)
        if show and used[spot] and not previewing then show = false end -- higher in the list wins
        if show then used[spot] = true end
        Display(f, cue, show, iconName, grey)
    end
    for cue, f in pairs(frames) do
        if not inList[cue] then HideFrame(f) end
    end
end

local function FollowCursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale, y / scale
    for cue, f in pairs(frames) do
        if f:IsShown() then
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + (cue.x or 0), y + (cue.y or 0))
        end
    end
end

---------------------------------------------------------------------------
-- Driver and events
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local sinceUpdate = UPDATE_INTERVAL
local lastCast -- the last spell you cast, for "Use last cast" in settings

-- Safety net: if anything ever errors, stop and say so once instead of
-- repeating the error 10 times a second.
driver:SetScript("OnUpdate", function(self, elapsed)
    sinceUpdate = sinceUpdate + elapsed
    if sinceUpdate >= UPDATE_INTERVAL then
        sinceUpdate = 0
        local ok, err = pcall(UpdateState)
        if not ok then
            self:SetScript("OnUpdate", nil)
            for _, f in pairs(frames) do HideFrame(f) end
            print(PREFIX .. "stopped after an error: " .. tostring(err))
            return
        end
    end
    FollowCursor()
end)

local function Refresh() sinceUpdate = UPDATE_INTERVAL end

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
-- not every client has these; registering a missing event is an error
pcall(driver.RegisterEvent, driver, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
pcall(driver.RegisterEvent, driver, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

local OnLoaded -- set up below (settings window)

driver:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" and ... == "CursorCues" then
        CursorCuesDB = CursorCuesDB or {}
        DB = CursorCuesDB
        if DB.enabled == nil then DB.enabled = true end
        if not DB.cues then -- first run of 2.0: start from your old cues
            DB.cues = CopyTable(DEFAULT_CUES)
            for _, cue in ipairs(DB.cues) do cue.enabled = true end
        end
        DB.durations = DB.durations or {}
        DB.debug = nil -- 1.x troubleshooting log, no longer kept
        if DB.preview == nil then DB.preview = true end
        driver:UnregisterEvent("ADDON_LOADED")
        if OnLoaded then OnLoaded() end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local spellID = ...
        local name = (spellID ~= nil and not isSecret(spellID)) and SpellNameFromID(spellID) or nil
        if name then
            glowing[name] = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW") or nil
            Refresh()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        wipe(glowing) -- never leave a glow stuck on after a fight
        Refresh()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if spellID == nil or isSecret(spellID) then return end
        local cast = SpellNameFromID(spellID)
        if not cast or not DB then return end
        lastCast = cast
        -- restart the timer of any buff cue whose spell this is
        local now = GetTime()
        for _, cue in ipairs(DB.cues) do
            if cue.type == "buff" or cue.type == "groupbuff" then
                for _, s in ipairs(Spells(cue)) do
                    if s == cast then
                        local st = State(cue)
                        st.expires = now + Duration(Buffs(cue)[1], cue.type == "groupbuff" and 3600 or 120)
                        st.nextRead = 0
                        break
                    end
                end
            end
        end
        Refresh()
    end
end)

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------
local TYPES = {
    { "buff", "Buff missing on me" },
    { "groupbuff", "My buff missing on group" },
    { "ready", "Ability ready" },
    { "tracking", "Tracking off" },
}
local WHENS = { { "combat", "In combat" }, { "nocombat", "Out of combat" }, { "always", "Always" } }
local STYLES = { { "steady", "Steady" }, { "pulse", "Pulse" }, { "flash", "Flash every few sec" } }
local SPOTS = {
    { "Above", 0, 32 }, { "Below", 0, -40 }, { "Left", -40, 0 }, { "Right", 40, 0 },
    { "Top-left", -32, 32 }, { "Top-right", 32, 32 }, { "Bottom-left", -32, -32 }, { "Bottom-right", 32, -32 },
}
local SPELL_LABELS = {
    buff = "Spell you cast for it (sets its icon and timer; blank if none)",
    groupbuff = "Your buff spell",
    ready = "Abilities (commas between; the first one ready shows)",
    tracking = "Tracking spells (commas between)",
}

local win, selected
local W = {} -- widgets

local function Text(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

local function Edit(parent, width, onCommit)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function(self) onCommit(self:GetText()) end)
    return e
end

local function Cycle(parent, width, options, onChange)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.options = options
    function b:Set(value)
        self.value = value
        local label = "?"
        for _, o in ipairs(self.options) do if o[1] == value then label = o[2] end end
        self:SetText(label)
    end
    b:SetScript("OnClick", function(self, button)
        local idx = 1
        for i, o in ipairs(self.options) do if o[1] == self.value then idx = i end end
        idx = idx + (button == "RightButton" and -1 or 1)
        if idx < 1 then idx = #self.options elseif idx > #self.options then idx = 1 end
        self:Set(self.options[idx][1])
        onChange(self.value)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Click for the next choice, right-click for the previous.")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Check(parent, label, onChange)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    if c.text then c.text:SetText("") end
    if c.Text then c.Text:SetText("") end
    c.label = Text(c, label, "GameFontHighlightSmall")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c:SetScript("OnClick", function(self) onChange(self:GetChecked() and true or false) end)
    return c
end

local function Slider(parent, label, minV, maxV, step, fmt, onChange)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(200, 36)
    h.label = Text(h, label, "GameFontNormalSmall")
    h.label:SetPoint("TOPLEFT")
    local s = CreateFrame("Frame", nil, h, "MinimalSliderWithSteppersTemplate") -- a Frame holding the slider and steppers
    s:SetPoint("TOPLEFT", 0, -14)
    s:SetSize(175, 20)
    h.slider = s
    s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
        if not h.loading then onChange(v) end
    end, h)
    function h:Set(v)
        self.loading = true
        s:Init(v, minV, maxV, math.floor((maxV - minV) / step + 0.5), {
            [MinimalSliderWithSteppersMixin.Label.Right] =
                CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt),
        })
        self.loading = false
    end
    return h
end

local function Place(widget, x, y) widget:ClearAllPoints(); widget:SetPoint("TOPLEFT", win, "TOPLEFT", x, y) end

local LoadSelected, RefreshList

local function Changed(cue)
    if cue and frames[cue] then ApplyLook(frames[cue], cue) end
    if cue then state[cue] = nil end -- start its timers over with the new settings
    RefreshList()
    Refresh()
end

local function SpotName(cue)
    for _, s in ipairs(SPOTS) do
        if s[2] == cue.x and s[3] == cue.y then return s[1] end
    end
    return "Custom"
end

local function BuildWindow()
    local ok, made = pcall(CreateFrame, "Frame", "CursorCuesSettings", UIParent, "BasicFrameTemplateWithInset")
    if ok then
        win = made
    else -- a plain dark window with a close button if that template is missing
        win = CreateFrame("Frame", "CursorCuesSettings", UIParent)
        local bg = win:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
        local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
    end
    win:SetSize(680, 500)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    table.insert(UISpecialFrames, "CursorCuesSettings") -- Escape closes it
    local title = Text(win, "Cursor Cues", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    win:SetScript("OnShow", function() previewing = DB.preview; Refresh() end)
    win:SetScript("OnHide", function() previewing = false; Refresh() end)

    -- top row: master switches
    W.enabled = Check(win, "Cursor Cues on", function(v) DB.enabled = v; Refresh() end)
    Place(W.enabled, 14, -30)
    W.preview = Check(win, "Preview: show every cue while this window is open", function(v)
        DB.preview = v; previewing = v; Refresh()
    end)
    Place(W.preview, 140, -30)

    -- left: the list
    local listTitle = Text(win, "Cues (higher wins a shared spot)")
    Place(listTitle, 16, -62)
    W.rows = {}
    for i = 1, MAX_CUES do
        local row = CreateFrame("Button", nil, win)
        row:SetSize(205, 22)
        Place(row, 12, -78 - (i - 1) * 23)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(0.25, 0.55, 1, 0.25)
        row.check = Check(row, "", function(v)
            local cue = DB.cues[i]
            if cue then cue.enabled = v; Changed(cue) end
        end)
        row.check:SetPoint("LEFT", 0, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 26, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.name = Text(row, "", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.name:SetPoint("RIGHT", -2, 0)
        row.name:SetWordWrap(false)
        row:SetScript("OnClick", function()
            selected = DB.cues[i]
            RefreshList()
            LoadSelected()
        end)
        W.rows[i] = row
    end

    local function ListButton(label, x, y, fn)
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        b:SetSize(100, 22)
        b:SetText(label)
        Place(b, x, y)
        b:SetScript("OnClick", fn)
        return b
    end
    local listBottom = -78 - MAX_CUES * 23 - 6
    W.add = ListButton("Add cue", 12, listBottom, function()
        if #DB.cues >= MAX_CUES then return end
        local cue = CopyTable(NEW_CUE)
        cue.enabled = true
        table.insert(DB.cues, cue)
        selected = cue
        Changed(cue)
        LoadSelected()
    end)
    W.remove = ListButton("Remove", 116, listBottom, function()
        if not selected then return end
        for i, cue in ipairs(DB.cues) do
            if cue == selected then table.remove(DB.cues, i) break end
        end
        selected = DB.cues[1]
        Changed(nil)
        LoadSelected()
    end)
    local function Move(dir)
        for i, cue in ipairs(DB.cues) do
            if cue == selected then
                local j = i + dir
                if j >= 1 and j <= #DB.cues then DB.cues[i], DB.cues[j] = DB.cues[j], DB.cues[i] end
                break
            end
        end
        Changed(nil)
    end
    W.up = ListButton("Move up", 12, listBottom - 24, function() Move(-1) end)
    W.down = ListButton("Move down", 116, listBottom - 24, function() Move(1) end)
    W.reset = ListButton("Defaults", 12, listBottom - 48, function()
        StaticPopup_Show("CURSORCUES_DEFAULTS")
    end)

    -- right: the selected cue
    local X, X2 = 240, 460
    local function Set(field) return function(v) if selected then selected[field] = v; Changed(selected); LoadSelected() end end end

    W.nameLabel = Text(win, "Name"); Place(W.nameLabel, X, -62)
    W.name = Edit(win, 200, function(v) if selected then selected.name = trim(v) ~= "" and trim(v) or "Cue"; Changed(selected) end end)
    Place(W.name, X + 6, -76)

    W.typeLabel = Text(win, "Type"); Place(W.typeLabel, X2, -62)
    W.type = Cycle(win, 190, TYPES, Set("type")); Place(W.type, X2, -76)

    W.spellLabel = Text(win, ""); Place(W.spellLabel, X, -104)
    W.spells = Edit(win, 300, function(v) if selected then selected.spells = trim(v); Changed(selected); LoadSelected() end end)
    Place(W.spells, X + 6, -118)
    W.useLast = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    W.useLast:SetSize(110, 22); W.useLast:SetText("Use last cast")
    Place(W.useLast, X2 + 92, -117)
    W.useLast:SetScript("OnClick", function()
        if not selected then return end
        if not lastCast then print(PREFIX .. "cast the spell once, then click this.") return end
        local l = Spells(selected)
        if selected.type == "ready" or selected.type == "tracking" then
            local copy = {}
            for _, s in ipairs(l) do copy[#copy + 1] = s end
            copy[#copy + 1] = lastCast
            selected.spells = table.concat(copy, ", ")
        else
            selected.spells = lastCast
        end
        if selected.name == "New cue" then selected.name = lastCast end
        Changed(selected)
        LoadSelected()
    end)
    W.spellStatus = Text(win, "", "GameFontHighlightSmall"); Place(W.spellStatus, X + 4, -141)

    W.buffLabel = Text(win, "Buff names that count (commas between; blank = same as the spell)")
    Place(W.buffLabel, X, -160)
    W.buffs = Edit(win, 410, function(v) if selected then selected.buffs = trim(v); Changed(selected) end end)
    Place(W.buffs, X + 6, -174)

    W.iconLabel = Text(win, "Icon (optional): a spell name, an icon ID, or Interface\\Icons\\...")
    Place(W.iconLabel, X, -202)
    W.icon = Edit(win, 360, function(v) if selected then selected.icon = trim(v); Changed(selected); LoadSelected() end end)
    Place(W.icon, X + 6, -216)
    W.iconPreview = win:CreateTexture(nil, "ARTWORK")
    W.iconPreview:SetSize(28, 28)
    W.iconPreview:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    Place(W.iconPreview, X2 + 178, -208)

    W.whenLabel = Text(win, "Show"); Place(W.whenLabel, X, -244)
    W.when = Cycle(win, 190, WHENS, Set("when")); Place(W.when, X, -258)
    W.styleLabel = Text(win, "Look"); Place(W.styleLabel, X2, -244)
    W.style = Cycle(win, 190, STYLES, Set("style")); Place(W.style, X2, -258)

    W.size = Slider(win, "Size", 16, 64, 1, function(v) return math.floor(v + 0.5) .. " px" end,
        function(v) if selected then selected.size = math.floor(v + 0.5); Changed(selected) end end)
    Place(W.size, X, -288)
    W.alpha = Slider(win, "Brightness", 0.2, 1, 0.05, function(v) return math.floor(v * 100 + 0.5) .. "%" end,
        function(v) if selected then selected.alpha = math.floor(v * 100 + 0.5) / 100; Changed(selected) end end)
    Place(W.alpha, X2, -288)

    W.every = Slider(win, "Flash every", 2, 30, 1, function(v) return math.floor(v + 0.5) .. " sec" end,
        function(v) if selected then selected.every = math.floor(v + 0.5); Changed(selected) end end)
    Place(W.every, X, -330)
    W.spotLabel = Text(win, "Spot (or nudge with X / Y below)"); Place(W.spotLabel, X2, -330)
    local spotOptions = {}
    for _, s in ipairs(SPOTS) do spotOptions[#spotOptions + 1] = { s[1], s[1] } end
    spotOptions[#spotOptions + 1] = { "Custom", "Custom" }
    W.spot = Cycle(win, 190, spotOptions, function(v)
        if not selected then return end
        for _, s in ipairs(SPOTS) do
            if s[1] == v then selected.x, selected.y = s[2], s[3] end
        end
        Changed(selected)
        LoadSelected()
    end)
    Place(W.spot, X2, -344)

    W.x = Slider(win, "X (left / right of the cursor)", -150, 150, 1, function(v) return math.floor(v + 0.5) end,
        function(v) if selected then selected.x = math.floor(v + 0.5); Changed(selected); W.spot:Set(SpotName(selected)) end end)
    Place(W.x, X, -372)
    W.y = Slider(win, "Y (below / above the cursor)", -150, 150, 1, function(v) return math.floor(v + 0.5) end,
        function(v) if selected then selected.y = math.floor(v + 0.5); Changed(selected); W.spot:Set(SpotName(selected)) end end)
    Place(W.y, X2, -372)

    W.needTarget = Check(win, "Only with an attackable target", Set("needTarget"))
    W.hiddenCd = Check(win, "Show even when the game hides its cooldown (reactive abilities)", Set("hiddenCooldownOK"))
    W.grey = Check(win, "Grey it out when I can't afford it", Set("greyNoResource"))
    W.known = Check(win, "Only if I know the spell", Set("requireKnown"))
    W.onlyGroup = Check(win, "Only while in a party or raid", Set("onlyGroup"))

    W.empty = Text(win, "Pick a cue on the left, or Add cue.", "GameFontDisable")
    Place(W.empty, X, -80)

    StaticPopupDialogs["CURSORCUES_DEFAULTS"] = {
        text = "Replace all your cues with the starting set?",
        button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = function()
            DB.cues = CopyTable(DEFAULT_CUES)
            for _, cue in ipairs(DB.cues) do cue.enabled = true end
            selected = DB.cues[1]
            Changed(nil)
            LoadSelected()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end

RefreshList = function()
    if not win or not win:IsShown() then return end
    for i, row in ipairs(W.rows) do
        local cue = DB.cues[i]
        if cue then
            row.name:SetText(cue.name or "Cue")
            row.icon:SetTexture(CueIcon(cue))
            row.check:SetChecked(cue.enabled ~= false)
            row.sel:SetShown(cue == selected)
            row:Show()
        else
            row:Hide()
        end
    end
    W.add:SetEnabled(#DB.cues < MAX_CUES)
end

local DETAIL = { "nameLabel", "name", "typeLabel", "type", "spellLabel", "spells", "useLast", "spellStatus",
    "buffLabel", "buffs", "iconLabel", "icon", "iconPreview", "whenLabel", "when", "styleLabel", "style",
    "size", "alpha", "every", "spotLabel", "spot", "x", "y",
    "needTarget", "hiddenCd", "grey", "known", "onlyGroup" }

LoadSelected = function()
    if not win then return end
    local cue = selected
    for _, k in ipairs(DETAIL) do W[k]:SetShown(cue ~= nil) end
    W.empty:SetShown(cue == nil)
    if not cue then return end
    local t = cue.type
    W.name:SetText(cue.name or "")
    W.type:Set(t)
    W.spellLabel:SetText(SPELL_LABELS[t] or "Spells")
    W.spells:SetText(cue.spells or "")
    -- which of the spells this character knows
    local spells, known, unknown = Spells(cue), {}, {}
    for _, s in ipairs(spells) do
        if PlayerKnows(s) then known[#known + 1] = s else unknown[#unknown + 1] = s end
    end
    if #spells == 0 then
        W.spellStatus:SetText("")
    elseif #unknown == 0 then
        W.spellStatus:SetText("|cff40ff40In your spellbook.|r")
    else
        W.spellStatus:SetText("|cffff8040Not in this character's spellbook: " .. table.concat(unknown, ", ") .. "|r")
    end
    local hasBuffs = (t == "buff" or t == "groupbuff")
    W.buffLabel:SetShown(hasBuffs)
    W.buffs:SetShown(hasBuffs)
    W.buffs:SetText(cue.buffs or "")
    W.icon:SetText(cue.icon or "")
    W.iconPreview:SetTexture(CueIcon(cue))
    W.when:Set(cue.when or "always")
    W.style:Set(cue.style or "steady")
    W.size:Set(cue.size or 36)
    W.alpha:Set(cue.alpha or 1)
    W.every:Set(cue.every or 10)
    W.every:SetShown(cue.style == "flash")
    W.spot:Set(SpotName(cue))
    W.x:Set(cue.x or 0)
    W.y:Set(cue.y or 0)

    -- options that apply to this type, stacked under everything else
    local checks = {}
    if t == "ready" then checks = { W.needTarget, W.hiddenCd }
    elseif t == "buff" then checks = { W.known, W.grey }
    elseif t == "groupbuff" then checks = { W.onlyGroup } end
    for _, c in ipairs({ W.needTarget, W.hiddenCd, W.grey, W.known, W.onlyGroup }) do c:Hide() end
    for i, c in ipairs(checks) do
        Place(c, 236, -414 - (i - 1) * 24)
        c:Show()
    end
    W.needTarget:SetChecked(cue.needTarget and true or false)
    W.hiddenCd:SetChecked(cue.hiddenCooldownOK and true or false)
    W.grey:SetChecked(cue.greyNoResource and true or false)
    W.known:SetChecked(cue.requireKnown ~= false)
    W.onlyGroup:SetChecked(cue.onlyGroup and true or false)
end

local function OpenSettings()
    if not DB then return end
    if not win then BuildWindow() end
    if win:IsShown() then win:Hide() return end
    if not selected or not tContains(DB.cues, selected) then selected = DB.cues[1] end
    win:Show()
    W.enabled:SetChecked(DB.enabled)
    W.preview:SetChecked(DB.preview)
    RefreshList()
    LoadSelected()
end

-- Options > AddOns > Cursor Cues: a button that opens the window
OnLoaded = function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    pcall(function()
        local panel = CreateFrame("Frame")
        local t = Text(panel, "Cursor Cues", "GameFontNormalLarge")
        t:SetPoint("TOPLEFT", 16, -16)
        local d = Text(panel, "Icons that follow your mouse. Set them up in their own window.", "GameFontHighlight")
        d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(200, 26)
        b:SetText("Open Cursor Cues settings")
        b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -12)
        b:SetScript("OnClick", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            OpenSettings()
        end)
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Cursor Cues")
        Settings.RegisterAddOnCategory(category)
    end)
end

SLASH_CURSORCUES1 = "/cues"
SlashCmdList.CURSORCUES = function(msg)
    msg = trim(msg):lower()
    if msg == "on" or msg == "off" then
        DB.enabled = (msg == "on")
        print(PREFIX .. (DB.enabled and "on" or "off"))
        Refresh()
    else
        OpenSettings()
    end
end
