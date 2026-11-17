-- Hunt Target
-- A small text box: type up to 3 mob names, separated by commas, and press
-- Enter. Then the Hunt key (Options > Keybindings > AddOns > Hunt Target >
-- "Hunt: target, mark and use your ability") does, each press:
--   * keeps your current target if it's alive and hostile; otherwise
--   * targets the nearest mob of the first name, or if none is around the
--     second, then the third;
--   * marks it with a skull and uses your hunt ability (Edit Mode: click
--     the box > Ability; or /hunt ability <spell>).
-- The key clicks a hidden button the addon owns (HuntTargetButton), set up
-- out of combat: like a macro, but no macro needed and room for 1023
-- characters instead of 255. It tries the names in order.
-- (The old "Hunt" macro isn't used or changed any more; delete it if you
-- like.)
--
-- Picking in the world:
--   Alt+click a mob          hunt just that mob
--   Shift+Alt+click a mob    add it to the list (up to 3; the oldest drops off)
--   Alt+click an ally        your "Follow" macro now follows them
--   key binding "Hunt my current target" (Options > Keybindings > AddOns)
--                            does the same for whatever you have targeted
--
-- /target matches part of a name: "Kobold" finds Kobold Vermin, Kobold
-- Worker and so on. Use the full name to be exact.
-- The macro can't change during combat (the game blocks it); names you set
-- mid-fight are saved when the fight ends.
--
-- Also: /hunt <names> sets them from chat, /hunt alone shows the current ones.
-- Edit Mode (Esc > Edit Mode): drag the box, click it for Width.
-- Edit Mode support comes from LibEditMode by p3lim (Libs\LibEditMode).

local MAX_MOBS = 3
local MAX_TEXT = 1023 -- what a button's macro text can hold

-- the hunt ability: what the key casts once the mob is targeted and marked
local ABILITIES = {
    -- Ctrl = Intercept (Berserker Stance first); otherwise Charge (Battle
    -- Stance first, out of combat only). Same as your Charge macro.
    charge = "/cast [mod:ctrl,form:3]Intercept;[mod:ctrl]Berserker Stance;[form:1]Charge;[nocombat]Battle Stance",
    -- your ranged weapon's attack, like your Shoot macro
    shoot = "/cast [equipped:Bows]Shoot Bow;[equipped:Guns]Shoot Gun;[equipped:Crossbows]Shoot Crossbow;[equipped:Thrown]Throw",
}
local ABILITY_CHOICES = {
    { text = "Charge (Battle Stance first)", value = "charge" },
    { text = "Shoot / Throw", value = "shoot" },
    { text = "Just target and mark", value = "none" },
    { text = "My own spell (/hunt ability ...)", value = "custom" },
}

-- The macro. Kept compact: the game allows 255 characters.
--   name lines              plain, never with [conditions] (see below)
--
--   /tm 0 + /tm 8           skull. Marking is protected on this client:
--                           /run is blocked (blamed on "ForceTaint_Strong"),
--                           the game's own /tm is allowed. Clearing first
--                           stops a second press toggling the skull off.
--   /cast ...               same as your Charge macro: Ctrl = Intercept
--                           (Berserker Stance first); otherwise Charge
--                           (Battle Stance first, out of combat only)
--   /stopmacro [noharm][dead]  if none of the names was found (and there's
--                           no live hostile target), stop here. Otherwise
--                           Charge/attack with nothing selected makes the
--                           game auto-pick the nearest enemy, and the skull
--                           would land on whatever that is.
--   /cleartarget [dead]     otherwise: a dead target is dropped (works in
--                           combat too, where the macro can't be rewritten)
--   /cleartarget            only when your current target isn't one of the
--                           hunted mobs (clear = true; see TargetIsHunted).
--                           A macro can't check names, so the addon watches
--                           your target out of combat and writes the macro
--                           with or without this line. Then a stray target
--                           is dropped, the hunted names are tried, and if
--                           none is near you're left with no target.
-- No #showtooltip: room is tight, and the button keeps Charge's icon.
-- On this client a targeting line whose name has a space SAYS part of the
-- name: "/target Two Words" (tested 16 Nov) and, it seems, any targeting
-- line with [conditions] in front of a name. Only a plain
-- "/targetexact Full Name" was proven silent. So name lines never carry
-- conditions:
--   clear = true (no target, or not a hunted one): drop it, then try each
--     name plainly. A later name can take over from an earlier one, which
--     is fine: they're all mobs you're hunting.
--   clear = false (your target IS a living hunted mob): no targeting lines
--     at all; it keeps what you have. A dead one is dropped.
local DB -- HuntTargetDB, once loaded

local function AbilityLines()
    local which = DB and DB.ability or "charge"
    if which == "none" then return {} end
    if which == "custom" then
        local spell = DB and DB.customAbility
        if not spell or spell == "" then return {} end
        return { "/cast " .. spell, "/startattack" }
    end
    if which == "shoot" then return { ABILITIES.shoot } end
    return { ABILITIES.charge, "/startattack" }
end

local function MacroBody(mobs, clear)
    local lines = {}
    if clear and #mobs > 0 then
        lines[1] = "/cleartarget"
        for _, mob in ipairs(mobs) do
            -- /targetexact for full names; one word keeps /target, which
            -- matches part of a name ("Vermin" finds Kobold Vermin)
            lines[#lines + 1] = (mob:find(" ", 1, true) and "/targetexact " or "/target ") .. mob
        end
    else
        lines[1] = "/cleartarget [dead]"
    end
    lines[#lines + 1] = "/stopmacro [noharm][dead]"
    lines[#lines + 1] = "/tm 0"
    lines[#lines + 1] = "/tm 8"
    for _, line in ipairs(AbilityLines()) do lines[#lines + 1] = line end
    return table.concat(lines, "\n")
end

local LAYOUT_DEFAULTS = { width = 220 }
local PREFIX = "|cffc79c6eHunt Target|r "
local LEM = LibStub("LibEditMode")

---------------------------------------------------------------------------
-- The list of names (saved as text: "Kobold Vermin, Kobold Worker")
---------------------------------------------------------------------------
local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function ParseMobs(text)
    local list, seen = {}, {}
    for part in (text or ""):gmatch("[^,]+") do
        local name = trim(part)
        if name ~= "" and not seen[name:lower()] and #list < MAX_MOBS then
            seen[name:lower()] = true
            list[#list + 1] = name
        end
    end
    return list
end

local function JoinMobs(list) return table.concat(list, ", ") end

local function Describe(list)
    if #list == 1 then return list[1] end
    return table.concat(list, ", then ")
end

---------------------------------------------------------------------------
-- The Hunt key's button (its text is set out of combat)
---------------------------------------------------------------------------
local pending = false
local events = CreateFrame("Frame")

local huntButton = CreateFrame("Button", "HuntTargetButton", UIParent, "SecureActionButtonTemplate")
huntButton:SetSize(1, 1)
huntButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10) -- off screen; only the key clicks it
huntButton:RegisterForClicks("AnyUp")
huntButton:SetAttribute("useOnKeyDown", false)
huntButton:SetAttribute("type", "macro")
_G["BINDING_NAME_CLICK HuntTargetButton:LeftButton"] = "Hunt: target, mark and use your ability"

-- Tab Mark: its own key ("Tab Mark: next enemy, next mark", under Tab Mark
-- in Keybindings). Each press targets the next enemy near you, the way Tab
-- does, and marks it with the next mark: skull, cross, square, moon,
-- triangle, diamond, circle, star, then round again. No ability: it's for
-- marking up a pack. The order starts over at the end of each fight, or
-- when you click the Tab Mark spot on the Hunt box. The mark is picked by a
-- small secure snippet on each press, which the game allows mid-fight.
-- (The button keeps its old name, HuntTargetNext, so your key stays bound.)
local NEXT_MARKS = { 8, 7, 6, 5, 4, 3, 2, 1 } -- skull ... star
BINDING_HEADER_TABMARK = "Tab Mark"
local nextButton = CreateFrame("Button", "HuntTargetNext", UIParent, "SecureActionButtonTemplate")
nextButton:SetSize(1, 1)
nextButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
nextButton:RegisterForClicks("AnyUp")
nextButton:SetAttribute("useOnKeyDown", false)
nextButton:SetAttribute("type", "macro")
nextButton:SetAttribute("markIndex", 0)
_G["BINDING_NAME_CLICK HuntTargetNext:LeftButton"] = "Tab Mark: next enemy, next mark"

local markHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
-- before each press: step to the next mark's text
markHeader:WrapScript(nextButton, "OnClick", ([[
    local n = (self:GetAttribute("markIndex") or 0) + 1
    if n > %d then n = 1 end
    self:SetAttribute("markIndex", n)
    self:SetAttribute("macrotext", self:GetAttribute("text" .. n))
]]):format(#NEXT_MARKS))

-- the texts, one per mark (set once; they never change)
for i, mark in ipairs(NEXT_MARKS) do
    nextButton:SetAttribute("text" .. i, "/targetenemy [nodead]\n/stopmacro [noharm][dead]\n/tm 0\n/tm " .. mark)
end

local UpdateTabMark -- the Hunt box's "next mark" spot, made below

-- Is your current target a living, attackable mob matching a hunted name?
-- (Same matching as /target: part of the name, any capitals.)
local function TargetIsHunted(list)
    local isSecret = issecretvalue or function() return false end
    if not UnitExists("target") then return false end
    local dead, canAttack = UnitIsDead("target"), UnitCanAttack("player", "target")
    if isSecret(dead) or isSecret(canAttack) or dead or not canAttack then return false end
    local name = UnitName("target")
    if isSecret(name) or type(name) ~= "string" then return false end
    name = name:lower()
    for _, mob in ipairs(list) do
        if name:find(mob:lower(), 1, true) then return true end
    end
    return false
end


-- Sets the Hunt key's text for the saved names and ability. Returns true
-- when it now matches them.
local function WriteMacro(verbose)
    local list = ParseMobs(DB.mob)
    local body = MacroBody(list, not TargetIsHunted(list))
    -- the version that finds a new target is the long one; it has to fit
    local finder = MacroBody(list, true)
    if #finder > MAX_TEXT then
        print(PREFIX .. "those names are too long together (" .. #finder .. "/" .. MAX_TEXT .. ").")
        return false
    end
    if InCombatLockdown() then
        pending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        if verbose then print(PREFIX .. "in combat; the Hunt key updates when the fight ends.") end
        return false
    end
    pending = false
    if huntButton:GetAttribute("macrotext") ~= body then
        huntButton:SetAttribute("macrotext", body)
    end
    return true
end

-- what the key's ability is, in words
local function AbilityText()
    local which = DB and DB.ability or "charge"
    if which == "custom" then
        return (DB.customAbility and DB.customAbility ~= "") and DB.customAbility or "nothing (no spell set)"
    end
    for _, c in ipairs(ABILITY_CHOICES) do
        if c.value == which then return c.text end
    end
    return which
end

local box -- the text box, made below
local RefreshRows -- the list under the box, made below

local function SetMobs(list, verbose)
    local previous = DB.mob
    DB.mob = JoinMobs(list)
    if box then box:SetText(DB.mob) end
    if RefreshRows then RefreshRows() end
    if WriteMacro(verbose) then
        if verbose then
            if #list == 0 then
                print(PREFIX .. "cleared; the Hunt key uses " .. AbilityText() .. " on your current target.")
            else
                print(PREFIX .. "the Hunt key now hunts " .. Describe(list) .. " (" .. AbilityText() .. ").")
            end
        end
    elseif not pending then
        -- too long or couldn't save: keep the old names
        DB.mob = previous
        if box then box:SetText(DB.mob) end
        if RefreshRows then RefreshRows() end
    end
end

---------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------
local holder = CreateFrame("Frame", "HuntTargetFrame", UIParent)
holder.editModeName = "Hunt Target"
holder:SetSize(LAYOUT_DEFAULTS.width, 36)
holder:SetClampedToScreen(true)

local title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", 4, 0)
title:SetText("Hunt")

box = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
box:SetAutoFocus(false)
box:SetHeight(20)
box:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -14) -- the template's edges sit outside its box
box:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -2, -14)
box:SetMaxLetters(90)

-- One row per hunted mob under the box: its order, its name and an X that
-- removes it.
local ROW_HEIGHT = 17
local rows = {}
for i = 1, MAX_MOBS do
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -36 - (i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.remove:SetSize(20, 20)
    row.remove:SetPoint("LEFT", row, "LEFT", -2, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.remove, "RIGHT", 0, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.remove:SetScript("OnClick", function() -- replaces the template's "close the window"
        local list = ParseMobs(DB.mob)
        table.remove(list, i)
        SetMobs(list, true)
    end)
    row.remove:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Stop hunting " .. (row.name or ""))
        GameTooltip:Show()
    end)
    row.remove:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:Hide()
    rows[i] = row
end

RefreshRows = function()
    local list = ParseMobs(DB and DB.mob)
    for i, row in ipairs(rows) do
        local name = list[i]
        row.name = name
        if name then
            row.text:SetText(i .. ". " .. name)
            row:Show()
        else
            row:Hide()
        end
    end
    -- the rows hang below the frame instead of resizing it, so the box
    -- never moves when the list changes
end

local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("LEFT", 2, 0)
hint:SetText("mob names, commas between, Enter")

local function UpdateHint()
    hint:SetShown(box:GetText() == "" and not box:HasFocus())
end

box:SetScript("OnEnterPressed", function(self)
    SetMobs(ParseMobs(self:GetText()), true)
    self:ClearFocus()
end)
box:SetScript("OnEscapePressed", function(self)
    self:SetText(DB and DB.mob or "") -- undo unsaved typing
    self:ClearFocus()
end)
box:SetScript("OnEditFocusGained", UpdateHint)
box:SetScript("OnEditFocusLost", function(self)
    self:SetText(DB and DB.mob or "")
    UpdateHint()
end)
box:SetScript("OnTextChanged", UpdateHint)

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------
local layoutName
local function Look()
    DB.layouts = DB.layouts or {}
    local key = layoutName or "Default"
    local l = DB.layouts[key]
    if not l then l = {}; DB.layouts[key] = l end
    for k, v in pairs(LAYOUT_DEFAULTS) do
        if l[k] == nil then l[k] = v end
    end
    return l
end

local default = { point = "CENTER", x = 0, y = 260 }

local function Apply()
    if not DB then return end
    local l = Look()
    holder:SetWidth(l.width)
    holder:ClearAllPoints()
    if l.point then
        holder:SetPoint(l.point, UIParent, l.point, l.x, l.y)
    else
        holder:SetPoint(default.point, UIParent, default.point, default.x, default.y)
    end
end

LEM:AddFrame(holder, function(_, layout, point, x, y)
    layoutName = layout
    local l = Look()
    l.point, l.x, l.y = point, x, y
end, default)

LEM:AddFrameSettings(holder, {
    {
        kind = LEM.SettingType.Slider,
        name = "Width",
        default = LAYOUT_DEFAULTS.width,
        minValue = 100, maxValue = 500, valueStep = 10,
        get = function(layout) layoutName = layout; return Look().width end,
        set = function(layout, value) layoutName = layout; Look().width = value; Apply() end,
    },
    {
        -- the same for every layout (it's what the key does, not where the box is)
        kind = LEM.SettingType.Dropdown,
        name = "Ability",
        default = "charge",
        values = ABILITY_CHOICES,
        get = function() return DB and DB.ability or "charge" end,
        set = function(_, value)
            DB.ability = value
            WriteMacro(true)
            if value == "custom" and not (DB.customAbility and DB.customAbility ~= "") then
                print(PREFIX .. "type /hunt ability <spell name> to set your spell.")
            end
        end,
    },
})

LEM:RegisterCallback("layout", function(layout)
    layoutName = layout
    Apply()
end)

---------------------------------------------------------------------------
-- Picking mobs from the world
---------------------------------------------------------------------------
local ALT_CLICK = true -- false = only the key binding

BINDING_HEADER_HUNTTARGET = "Hunt Target"
BINDING_NAME_HUNTTARGET_SET = "Hunt my current target"

-- temporary troubleshooting notes, saved in HuntTargetDB.debug
local function DebugAdd(line)
    if not DB then return end
    DB.debug = DB.debug or {}
    DB.debug[#DB.debug + 1] = date("%H:%M:%S") .. " " .. line
    while #DB.debug > 100 do table.remove(DB.debug, 1) end
end

-- What a unit is for us: "hunt" (a mob you can attack), "follow" (a
-- friendly player or NPC), or nil and the reason. Plus its name.
local function Classify(unit)
    if not UnitExists(unit) then return nil, "no " .. unit end
    local isSecret = issecretvalue or function() return false end
    local isMe = UnitIsUnit(unit, "player")
    local canAttack = UnitCanAttack("player", unit)
    local friend = UnitIsFriend("player", unit)
    local isPlayer = UnitIsPlayer(unit)
    if isSecret(isMe) or isSecret(canAttack) or isSecret(friend) or isSecret(isPlayer) then
        return nil, "hidden"
    end
    if isMe then return nil, "you" end
    local name
    if canAttack then
        if isPlayer then return nil, "an enemy player" end
        name = UnitName(unit)
    elseif friend then
        -- with the realm for players from other realms, as /follow needs
        name = isPlayer and GetUnitName and GetUnitName(unit, true) or UnitName(unit)
    else
        return nil, "neutral"
    end
    if isSecret(name) then return nil, "hidden" end
    if type(name) ~= "string" or name == "" then return nil, "no name" end
    return canAttack and "hunt" or "follow", name
end

---------------------------------------------------------------------------
-- Follow: your existing macro named "Follow" (any capitals, spaces at the
-- ends ignored). Only its /follow line is swapped; its name, icon and any
-- other lines stay as they are. If there isn't one, an account macro
-- "Follow" is made.
---------------------------------------------------------------------------
local FOLLOW_MACRO = "Follow"
local followPending = false
local followText -- "Follow: <name>" on the frame, made below

local function FindFollowMacro()
    local total = (MAX_ACCOUNT_MACROS or 120) + (MAX_CHARACTER_MACROS or 18)
    for i = 1, total do
        local name = GetMacroInfo(i)
        if type(name) == "string" and trim(name):lower() == FOLLOW_MACRO:lower() then return i end
    end
end

-- the macro's text with its /follow line pointed at `who`
-- The follow lines for `who`. On this client a slash command with a
-- two-word name ("/follow Danny Depriesto") uses the first word and SAYS
-- the rest (tested 16 Nov), and /follow has no "exact" form. So a name
-- with a space is targeted with /targetexact (which reads it whole),
-- followed with a plain /follow (= follow your target), and your old
-- target put back with /targetlasttarget.
local function FollowLines(who)
    if who:find(" ", 1, true) then
        return { "/targetexact " .. who, "/follow", "/targetlasttarget" }
    end
    return { "/follow " .. who }
end

-- the macro's text with its follow lines pointed at `who`; its other lines stay
local function FollowBody(current, who)
    local out, placed = {}, false
    for line in ((current or "") .. "\n"):gmatch("(.-)\r?\n") do
        local mine = line:match("^%s*/fol") or line:match("^%s*/targetexact ")
            or line:match("^%s*/targetlasttarget%s*$")
        if mine then
            if not placed then
                for _, l in ipairs(FollowLines(who)) do out[#out + 1] = l end
                placed = true
            end
        else
            out[#out + 1] = line
        end
    end
    while #out > 0 and out[#out] == "" do table.remove(out) end
    if not placed then
        for i, l in ipairs(FollowLines(who)) do table.insert(out, i, l) end
    end
    return table.concat(out, "\n")
end

-- the name the Follow macro follows now, read from its text
local function FollowFromMacro()
    local index = FindFollowMacro()
    if not index then return nil end
    local _, _, body = GetMacroInfo(index)
    if type(body) ~= "string" then return nil end
    local who = body:match("/targetexact%s+([^\r\n]+)") or body:match("/fol%a*%s+([^\r\n]+)")
    return who and trim(who) or nil
end

local function ShowFollow()
    if not followText then return end
    if DB and DB.follow and DB.follow ~= "" then
        followText:SetText("Follow: |cffffffff" .. DB.follow .. "|r")
    else
        followText:SetText("")
    end
end

local function WriteFollow(verbose)
    if not DB.follow or DB.follow == "" then return end
    if InCombatLockdown() then
        followPending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        if verbose then print(PREFIX .. "in combat; the Follow macro updates when the fight ends.") end
        return
    end
    followPending = false
    local index = FindFollowMacro()
    local ok, err
    if index then
        local name, icon, current = GetMacroInfo(index)
        local body = FollowBody(current, DB.follow)
        if trim(current) == trim(body) then return end
        if #body > 255 then
            print(PREFIX .. "the Follow macro would be too long.")
            return
        end
        ok, err = pcall(EditMacro, index, name, icon, body)
    else
        ok, err = pcall(CreateMacro, FOLLOW_MACRO, 134400, table.concat(FollowLines(DB.follow), "\n"), false)
    end
    if not ok then
        print(PREFIX .. "couldn't save the Follow macro: " .. tostring(err))
    elseif verbose then
        print(PREFIX .. "Follow macro now follows " .. DB.follow .. ".")
    end
end

-- Start following straight away too (AUTO_FOLLOW). If this client blocks
-- addons from starting a follow, the game says "action blocked" once; we
-- notice (ADDON_ACTION_BLOCKED below), say so, and stop trying.
local AUTO_FOLLOW = true
local followBlocked = false
local followTriedAt      -- GetTime() of the last attempt, until the game confirms it
local followFailNoted = false

local function StartFollow(unit)
    if not AUTO_FOLLOW or followBlocked or not FollowUnit or not unit then return end
    local exists = UnitExists(unit)
    DebugAdd("follow try: unit=" .. unit .. " exists=" .. tostring(exists)
        .. " combat=" .. tostring(InCombatLockdown()))
    followTriedAt = GetTime()
    local ok, err = pcall(FollowUnit, unit)
    if not ok then DebugAdd("follow error: " .. tostring(err)) end
    -- the game sends AUTOFOLLOW_BEGIN when a follow really starts; if it
    -- hasn't within a second, say so once
    local tried = followTriedAt
    C_Timer.After(1, function()
        if followTriedAt == tried then
            followTriedAt = nil
            DebugAdd("follow didn't start")
            if not followFailNoted then
                followFailNoted = true
                print(PREFIX .. "the follow didn't start on its own; your Follow macro is updated, press it to follow.")
            end
        end
    end)
end

-- unit = who to start following now ("target" for the key binding), or
-- nil to only update the Follow macro
local function Follow(name, unit)
    if DB.follow ~= name then
        DB.follow = name
        ShowFollow()
        WriteFollow(true)
    end
    StartFollow(unit) -- again on a repeat Alt+click, to pick the follow back up
end

-- An Alt+click on an ally starts the follow when the mouse button comes UP,
-- after the click has selected them. The game only lets an addon start a
-- follow straight from your input (a key press works, tested 16 Nov), and
-- it doesn't send addons the mouse-up for clicks on characters in the
-- world. So the follow is started from the world frame's own mouse-up,
-- which runs straight from your click. GLOBAL_MOUSE_UP stays as a backup;
-- whichever comes first starts it.
local followOnMouseUp

local function FollowOnRelease(button)
    if not followOnMouseUp or button ~= "LeftButton" then return end
    local recent = GetTime() - followOnMouseUp < 2
    followOnMouseUp = nil
    if not recent or not DB then return end
    -- the click has selected them by now; fall back to whoever's under the mouse
    local isSecret = issecretvalue or function() return false end
    local tname = GetUnitName and GetUnitName("target", true) or UnitName("target")
    local onTarget = not isSecret(tname) and tname == DB.follow
    StartFollow(onTarget and "target" or "mouseover")
end

if WorldFrame and WorldFrame.HookScript then
    WorldFrame:HookScript("OnMouseUp", function(_, button) FollowOnRelease(button) end)
end

-- Tab Mark's spot, top right of the box: the mark your next Tab Mark press
-- puts down. Click it to start over at the skull (out of combat).
local tabSpot = CreateFrame("Button", nil, holder)
tabSpot:SetSize(14, 14)
tabSpot:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -2, 1)
tabSpot.icon = tabSpot:CreateTexture(nil, "ARTWORK")
tabSpot.icon:SetAllPoints()
tabSpot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
local tabLabel = tabSpot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
tabLabel:SetPoint("RIGHT", tabSpot, "LEFT", -2, 0)
tabLabel:SetText("Tab")

UpdateTabMark = function()
    local n = (tonumber(nextButton:GetAttribute("markIndex")) or 0) + 1
    if n > #NEXT_MARKS then n = 1 end
    tabSpot.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. NEXT_MARKS[n])
end
UpdateTabMark()
nextButton:HookScript("OnClick", function() UpdateTabMark() end)

tabSpot:SetScript("OnClick", function()
    if InCombatLockdown() then
        print(PREFIX .. "Tab Mark starts over by itself when the fight ends.")
        return
    end
    nextButton:SetAttribute("markIndex", 0)
    UpdateTabMark()
end)
tabSpot:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Tab Mark")
    GameTooltip:AddLine("Your Tab Mark key targets the next enemy and puts this mark on it.", 1, 1, 1, true)
    GameTooltip:AddLine("Click to start over at the skull.", 0.6, 0.8, 1)
    GameTooltip:Show()
end)
tabSpot:SetScript("OnLeave", function() GameTooltip:Hide() end)

followText = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
followText:SetPoint("TOPRIGHT", tabLabel, "TOPLEFT", -8, 0)
followText:SetPoint("LEFT", title, "RIGHT", 8, 0)
followText:SetJustifyH("RIGHT")
followText:SetWordWrap(false)

-- add = true puts it on the end of the list; otherwise it replaces the list
local function Hunt(name, add)
    local list = ParseMobs(DB.mob)
    for i, mob in ipairs(list) do
        if mob:lower() == name:lower() then
            if add or #list == 1 then
                print(PREFIX .. "already hunting " .. Describe(list) .. ".")
                return
            end
        end
    end
    if add then
        list[#list + 1] = name
        while #list > MAX_MOBS do table.remove(list, 1) end
    else
        list = { name }
    end
    SetMobs(list, true)
end

function HuntTarget_FromTarget()
    if not DB then return end
    local kind, name = Classify("target")
    if kind == "hunt" then
        Hunt(name, false)
    elseif kind == "follow" then
        Follow(name, "target")
    else
        print(PREFIX .. "target a mob to hunt or an ally to follow first.")
    end
end

---------------------------------------------------------------------------
-- Chat command and events
---------------------------------------------------------------------------
SLASH_HUNTTARGET1 = "/hunt"
SlashCmdList.HUNTTARGET = function(msg)
    msg = trim(msg)
    if msg == "" then
        local list = ParseMobs(DB.mob)
        print(PREFIX .. (#list > 0 and ("hunting: " .. Describe(list)) or "no mob set")
            .. "; ability: " .. AbilityText() .. ". /hunt <name>, <name> to change it; /hunt ability <spell>.")
        return
    end
    -- /hunt ability <spell>: your own spell for the Hunt key
    local spell = msg:match("^[Aa]bility%s*(.*)$")
    if spell then
        spell = trim(spell)
        if spell == "" then
            print(PREFIX .. "the Hunt key uses " .. AbilityText() .. ". /hunt ability <spell name> sets your own.")
            return
        end
        DB.customAbility = spell
        DB.ability = "custom"
        if WriteMacro(true) then print(PREFIX .. "the Hunt key now uses " .. spell .. ".") end
        return
    end
    SetMobs(ParseMobs(msg), true)
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED") -- always: resync after each fight
events:RegisterEvent("ADDON_ACTION_BLOCKED")  -- in case the game won't let us start a follow
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
-- every mouse click; not in every client, and registering a missing event errors
local mouseEvent = pcall(events.RegisterEvent, events, "GLOBAL_MOUSE_DOWN")
local mouseUpEvent = pcall(events.RegisterEvent, events, "GLOBAL_MOUSE_UP")
pcall(events.RegisterEvent, events, "AUTOFOLLOW_BEGIN") -- the game confirming a follow started
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= "HuntTarget" then return end
        HuntTargetDB = HuntTargetDB or {}
        DB = HuntTargetDB
        DB.mob = DB.mob or ""
        box:SetText(DB.mob)
        UpdateHint()
        RefreshRows()
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        Apply()
        local isInitialLogin, isReloadingUi = arg1, arg2
        if isInitialLogin or isReloadingUi then
            -- macros load a moment after login; only touch an existing one
            -- here (making it is left to when you set a name), so a slow
            -- load can never create a duplicate
            C_Timer.After(3, function()
                WriteMacro(false)
                -- once: delete the old account "Hunt" macro (the key does its
                -- job now). Only the one this addon wrote (it marks a skull).
                if not DB.oldMacroDeleted and not InCombatLockdown() then
                    local index = GetMacroIndexByName("Hunt")
                    if index and index > 0 then
                        local _, _, body = GetMacroInfo(index)
                        if type(body) == "string" and body:find("/tm 8", 1, true) then
                            if pcall(DeleteMacro, index) then
                                DB.oldMacroDeleted = true
                                print(PREFIX .. "deleted the old \"Hunt\" macro; your Hunt key does its job now.")
                            end
                        else
                            DB.oldMacroDeleted = true -- a different macro by that name: leave it
                        end
                    else
                        DB.oldMacroDeleted = true -- already gone
                    end
                end
                -- the Follow macro is the truth for who you follow (you may
                -- have edited it by hand)
                local who = FollowFromMacro()
                if who then DB.follow = who end
                ShowFollow()
                -- put an old "/follow Two Words" into the safe form
                if DB.follow and DB.follow ~= "" then WriteFollow(false) end
            end)
        end
    elseif event == "PLAYER_TARGET_CHANGED" and DB and not InCombatLockdown()
        and not IsAltKeyDown() then
        -- keep the key's "drop a wrong target first" line in step with
        -- what you have targeted (it can't change in combat)
        WriteMacro(false)
    elseif event == "GLOBAL_MOUSE_DOWN" or event == "PLAYER_TARGET_CHANGED" then
        -- Alt held while you click a mob. The mouse event sees the click even
        -- on a mob that's already your target (which doesn't change the
        -- target); "target changed" is only the fallback for a client
        -- without the mouse event.
        if event == "GLOBAL_MOUSE_DOWN" and arg1 ~= "LeftButton" then return end
        if event == "PLAYER_TARGET_CHANGED" and mouseEvent then return end
        if ALT_CLICK and DB and IsAltKeyDown() then
            local unit = event == "GLOBAL_MOUSE_DOWN" and "mouseover" or "target"
            local kind, name = Classify(unit)
            local why = not kind and name or nil
            if event == "GLOBAL_MOUSE_DOWN" and why == "no mouseover" then return end -- clicked the ground or the UI
            DebugAdd("alt-click: " .. (kind and (kind .. "=" .. name) or ("skipped, " .. tostring(why)))
                .. " shift=" .. tostring(IsShiftKeyDown()) .. " combat=" .. tostring(InCombatLockdown())
                .. " current=" .. tostring(DB.mob))
            if kind == "hunt" then
                Hunt(name, IsShiftKeyDown())
            elseif kind == "follow" then
                if event == "GLOBAL_MOUSE_DOWN" and mouseUpEvent then
                    Follow(name, nil)              -- macro now,
                    followOnMouseUp = GetTime()    -- the follow itself on release
                else
                    Follow(name, unit)
                end
            elseif why == "hidden" then
                print(PREFIX .. "the game is hiding that mob's name right now"
                    .. (InCombatLockdown() and " (in combat); Alt+click it again after the fight." or "."))
            end
        end
    elseif event == "GLOBAL_MOUSE_UP" then
        FollowOnRelease(arg1) -- backup for the world frame's mouse-up
    elseif event == "AUTOFOLLOW_BEGIN" then
        followTriedAt = nil -- it worked
        DebugAdd("follow started: " .. tostring(arg1))
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- arg1 = the addon blamed, arg2 = what it tried
        if arg1 == "HuntTarget" and type(arg2) == "string" and arg2:find("FollowUnit") and not followBlocked then
            followBlocked = true
            print(PREFIX .. "this client doesn't let addons start a follow, so Alt+click only updates "
                .. "your Follow macro; press that to follow.")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- first thing: the fight's over, so Tab Mark starts at the skull again
        nextButton:SetAttribute("markIndex", 0)
        if UpdateTabMark then UpdateTabMark() end
        if pending then
            WriteMacro(true)
        else
            WriteMacro(false) -- catch up with the target you ended the fight on
        end
        if followPending then WriteFollow(true) end
    end
end)
