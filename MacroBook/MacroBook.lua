-- MacroBook
-- Keeps the macros listed in MACROS in your account-wide macros.
--   * A listed macro that doesn't exist yet is created.
--   * A listed macro whose text differs is updated to match this file.
--   * Macros NOT listed here are never touched.
-- Changes apply when you log in or /reload (or type /macrobook).
-- Note: if you edit a listed macro in game, this file wins on the next login,
-- so make lasting changes here.

---------------------------------------------------------------------------
-- Your macros. Names can be up to 16 characters; text up to 255 characters.
-- icon = 134400 is the question mark, which lets #showtooltip show the
-- spell's own icon.
---------------------------------------------------------------------------
local MACROS = {
    {
        name = "BRage",
        icon = 134400,
        body = [[
#showtooltip Berserker Rage
/cast [nostance:3] Berserker Stance; Berserker Rage]],
    },
    {
        -- Ctrl: Intercept (switches to Berserker Stance first if needed).
        -- No Ctrl: Charge only. Never goes to Berserker Stance. Out of combat
        -- it switches to Battle Stance first if needed; in combat it never
        -- changes stance.
        name = "Charge",
        icon = 132337,
        body = [[
#showtooltip Charge
/cast [mod:ctrl,stance:3] Intercept; [mod:ctrl] Berserker Stance; [stance:1] Charge; [nocombat] Battle Stance
/startattack]],
    },
    {
        -- Thunder Clap. Shift: Berserker Stance instead. Never changes
        -- stance on its own (Thunder Clap needs Battle Stance).
        name = "TClap",
        icon = 134400,
        body = [[
#showtooltip
/cast [mod:shift,nostance:3] Berserker Stance; [nomod:shift] Thunder Clap]],
    },
    {
        -- Each press:
        --   Victory Rush whenever it's up (it's on the global cooldown,
        --     Heroic Strike isn't, so one press does both);
        --   Throw, if you have a thrown weapon on: macros can't check
        --     range, but the game itself refuses Throw when the target is
        --     too close (melee) or too far, so it only throws when they're
        --     in throwing range;
        --   Heroic Strike on your next swing ("!": pressing again never
        --     un-queues it by accident).
        -- The last line clears the red "not ready" / "too close" text.
        -- (There's no Alt-to-cancel: nothing a macro can do un-queues
        -- Heroic Strike on Forever; /stopcasting, casting it again and
        -- /cqs were all tried.)
        name = "Heroic",
        icon = 132282,
        body = [[
#showtooltip Heroic Strike
/startattack
/cast Victory Rush
/cast [equipped:Thrown] Throw
/cast !Heroic Strike
/run UIErrorsFrame:Clear()]],
    },
    {
        -- Battle Stance: Mocking Blow; the next press within 2 minutes (its
        -- cooldown) switches to Defensive Stance. A cast sequence only moves
        -- on when a spell actually casts, and resets after 2 minutes, by
        -- which time Mocking Blow is ready again. (Stance changes ignore the
        -- global cooldown on this client, so a plain "try, then switch"
        -- macro swaps every time.)
        -- Shift: switch to Defensive Stance now, from any stance.
        -- Defensive Stance: Taunt. Berserker Stance: switches to Defensive.
        name = "Taunt",
        icon = 136080,
        body = [[
#showtooltip
/startattack
/cast [mod:shift,nostance:2] Defensive Stance
/castsequence [nomod,stance:1] reset=120 Mocking Blow, Defensive Stance
/cast [nostance:1,nostance:2] Defensive Stance; [stance:2] Taunt]],
    },

    -- Weapon swaps. {ButtonName} is replaced, at login / reload, with the
    -- item sitting on that action button, so you keep choosing the weapons by
    -- what's on those (hidden) bar buttons:
    --   MultiBarRightButton11  your two-hander
    --   MultiBarLeftButton12   your one-hander (main hand)
    --   MultiBarRightButton12  your shield
    -- /equipslot 16 / 17 say which hand. Clicking the buttons only "used"
    -- the item and let the game pick the hand, which goes wrong for a
    -- one-hand weapon (it can go in either hand) but not a main-hand one.
    {
        -- shield on: two-hander; otherwise one-hander + shield
        name = "Swap",
        icon = 132147,
        body = [[
/equip [equipped:Shields] {MultiBarRightButton11}
/equipslot [noequipped:Shields] 16 {MultiBarLeftButton12}
/equipslot [noequipped:Shields] 17 {MultiBarRightButton12}]],
    },
    {
        -- outside Berserker Stance, puts the one-hander + shield on first
        name = "Bash",
        icon = 132357,
        body = [[
#showtooltip Shield Bash
/stopcasting
/equipslot [nostance:3,noequipped:Shields] 16 {MultiBarLeftButton12}
/equipslot [nostance:3,noequipped:Shields] 17 {MultiBarRightButton12}
/cast [stance:3] Pummel; Shield Bash]],
    },
    {
        name = "Wall",
        icon = 132362,
        body = [[
#showtooltip Shield Wall
/equipslot [noequipped:Shields] 16 {MultiBarLeftButton12}
/equipslot [noequipped:Shields] 17 {MultiBarRightButton12}
/cast [nostance:2] Defensive Stance; Shield Wall]],
    },
}

---------------------------------------------------------------------------
-- {ButtonName}: the item on that action button
---------------------------------------------------------------------------
-- where each bar's buttons live in the action slots, if the button doesn't say
local BAR_FIRST_SLOT = {
    MultiBarRightButton = 25, MultiBarLeftButton = 37,
    MultiBarBottomRightButton = 49, MultiBarBottomLeftButton = 61,
}

local function ButtonSlot(buttonName)
    local b = _G[buttonName]
    local slot = b and b.action
    if type(slot) ~= "number" and b and b.GetAttribute then slot = b:GetAttribute("action") end
    if type(slot) == "number" and slot > 12 then return slot end -- 1-12 would be "button N", not a slot
    local bar, n = buttonName:match("^(%a+Button)(%d+)$")
    if bar and BAR_FIRST_SLOT[bar] then return BAR_FIRST_SLOT[bar] + tonumber(n) - 1 end
    return nil
end

-- the item's name (or item:ID if the name isn't loaded yet), or nil
local function ButtonItem(buttonName)
    local slot = ButtonSlot(buttonName)
    if not slot then return nil end
    local kind, id = GetActionInfo(slot)
    if kind ~= "item" or type(id) ~= "number" then return nil end
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or GetItemInfo(id)
    return name or ("item:" .. id)
end

-- body with every {ButtonName} filled in; nil and the first empty button if one isn't an item
local function Resolve(body)
    local missing
    local out = body:gsub("{(%w+)}", function(buttonName)
        local item = ButtonItem(buttonName)
        if not item then missing = missing or buttonName; return "" end
        return item
    end)
    if missing then return nil, missing end
    return out
end

---------------------------------------------------------------------------
-- Sync logic (no need to edit below here)
---------------------------------------------------------------------------
local PREFIX = "|cffc79c6eMacroBook|r "
local MAX_BODY = 255
local pendingAfterCombat = false
local retries = 0

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

---------------------------------------------------------------------------
-- Two-word names. On this client "/target Two Words" (and /tar) targets by
-- the first word and makes your character SAY the rest (tested 16 Nov);
-- /targetexact reads the whole name and stays quiet. So in all your macros
-- (account and this character's), a /tar or /target line whose name has a
-- space becomes /targetexact, keeping any [conditions]. Only those lines
-- change. The macros other addons write (Hunt by Hunt Target, which already
-- does this, and RXP Guides' own) are left alone, as are MacroBook's own.
---------------------------------------------------------------------------
local SKIP_FIX = { Hunt = true, RXPTargeting = true }

local function FixLine(line)
    local lead, cmd, rest = line:match("^(%s*)(/tar[get]*)%s+(.+)$")
    if not lead or (cmd ~= "/tar" and cmd ~= "/target") then return line end
    -- peel off any [conditions] in front of the name
    local conds = ""
    while true do
        local c, after = rest:match("^(%b[])%s*(.*)$")
        if not c then break end
        conds, rest = conds .. c, after
    end
    local name = rest:gsub("%s+$", "")
    if not name:find(" ", 1, true) then return line end -- one word: fine as it is
    return lead .. "/targetexact " .. (conds ~= "" and (conds .. " ") or "") .. name
end

local function FixTwoWordTargets()
    if InCombatLockdown() then return end
    local own = {}
    for _, m in ipairs(MACROS) do own[m.name] = true end
    local numAccount, numChar = GetNumMacros()
    local first = (MAX_ACCOUNT_MACROS or 120) + 1
    local indexes = {}
    for i = 1, numAccount or 0 do indexes[#indexes + 1] = i end
    for i = first, first + (numChar or 0) - 1 do indexes[#indexes + 1] = i end
    local fixed = {}
    for _, index in ipairs(indexes) do
        local name, icon, body = GetMacroInfo(index)
        if type(name) == "string" and type(body) == "string" and not own[name] and not SKIP_FIX[trim(name)] then
            local out, changed = {}, false
            for line in (body .. "\n"):gmatch("(.-)\r?\n") do
                local new = FixLine(line)
                if new ~= line then changed = true end
                out[#out + 1] = new
            end
            while #out > 0 and out[#out] == "" do table.remove(out) end
            local newBody = table.concat(out, "\n")
            if changed and #newBody <= MAX_BODY and pcall(EditMacro, index, name, icon, newBody) then
                fixed[#fixed + 1] = trim(name)
            end
        end
    end
    if #fixed > 0 then
        print(PREFIX .. "fixed two-word target names in: " .. table.concat(fixed, ", ")
            .. " (they used to make your character say the last word).")
    end
end

local function Sync(verbose)
    if InCombatLockdown() then
        pendingAfterCombat = true
        if verbose then print(PREFIX .. "in combat; will update when combat ends.") end
        return
    end
    pendingAfterCombat = false

    -- Macros can take a moment to load after login. An empty list usually
    -- means they aren't ready yet, so wait instead of creating duplicates.
    local numAccount = GetNumMacros()
    if numAccount == 0 and retries < 5 then
        retries = retries + 1
        C_Timer.After(2, function() Sync(verbose) end)
        return
    end

    local added, updated, unchanged, problems, skipped = {}, {}, 0, {}, {}

    for _, m in ipairs(MACROS) do
        local body, missing = Resolve((trim(m.body)))
        if not body then
            -- leave the macro as it is rather than write it with a hole
            -- (normal on a character without those weapons on its bars)
            table.insert(skipped, m.name .. " (no item on " .. missing .. ")")
        elseif #m.name > 16 then
            table.insert(problems, m.name .. " (name over 16 characters)")
        elseif #body > MAX_BODY then
            table.insert(problems, m.name .. " (" .. #body .. "/" .. MAX_BODY .. " characters)")
        else
            local index = GetMacroIndexByName(m.name)
            if index and index > 0 then
                local name, icon, currentBody = GetMacroInfo(index)
                if trim(currentBody) ~= body then
                    local ok, err = pcall(EditMacro, index, name, icon, body)
                    if ok and m.body:find("{%w+}") then
                        -- say which items a weapon macro picked up
                        local items = {}
                        for b in m.body:gmatch("{(%w+)}") do
                            local item = ButtonItem(b)
                            if item and not tContains(items, item) then items[#items + 1] = item end
                        end
                        table.insert(updated, m.name .. " (" .. table.concat(items, ", ") .. ")")
                    elseif ok then table.insert(updated, m.name)
                    else table.insert(problems, m.name .. " (" .. tostring(err) .. ")") end
                else
                    unchanged = unchanged + 1
                end
            else
                local ok, err = pcall(CreateMacro, m.name, m.icon or 134400, body, false)
                if ok then table.insert(added, m.name)
                else table.insert(problems, m.name .. " (" .. tostring(err) .. ")") end
            end
        end
    end

    if #added > 0 then print(PREFIX .. "added: " .. table.concat(added, ", ")) end
    if #updated > 0 then print(PREFIX .. "updated: " .. table.concat(updated, ", ")) end
    if #problems > 0 then print(PREFIX .. "couldn't save: " .. table.concat(problems, "; ")) end
    if verbose and #skipped > 0 then print(PREFIX .. "left as they are: " .. table.concat(skipped, "; ")) end
    if verbose and #added == 0 and #updated == 0 and #problems == 0 then
        print(PREFIX .. "all " .. unchanged .. " macros are up to date.")
    end
    FixTwoWordTargets()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, isInitialLogin, isReloadingUi)
    if event == "PLAYER_ENTERING_WORLD" then
        if isInitialLogin or isReloadingUi then
            C_Timer.After(1, function() Sync(false) end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" and pendingAfterCombat then
        Sync(false)
    end
end)

SLASH_MACROBOOK1 = "/macrobook"
SlashCmdList.MACROBOOK = function(msg)
    if msg and msg:lower():match("^%s*range") then
        if MacroBookRangeReport then MacroBookRangeReport() end
        return
    end
    retries = 0
    Sync(true)
end

---------------------------------------------------------------------------
-- Range on the Shoot macro's button
-- A macro button doesn't show range on this client, so this checks your
-- ranged weapon's own spell (Shoot Bow / Shoot Gun / Shoot Crossbow /
-- Throw) against your target, and tints every button holding the macro
-- named in RANGE_MACRO red while the target is out of range or too close
-- (inside the dead zone). Works in combat (it's only a texture).
---------------------------------------------------------------------------
local RANGE_MACRO = "Shoot"
local RANGED_SPELLS = { [2] = 2480, [3] = 7918, [18] = 7919, [16] = 2764 } -- weapon type -> its spell
local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}
local rangeSecret = issecretvalue or function() return false end
local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- the spell for the ranged weapon you have on, or nil
local function RangedSpell()
    local id = GetInventoryItemID("player", 18)
    if not id or rangeSecret(id) or not getInstant then return nil end
    local ok, _, _, _, _, _, classID, subclassID = pcall(getInstant, id)
    if ok and classID == 2 and not rangeSecret(subclassID) then return RANGED_SPELLS[subclassID] end
end

-- a range answer as true / false, or nil when there isn't one
local function Answer(ok, r)
    if not ok or rangeSecret(r) then return nil end
    if r == true or r == 1 then return true end
    if r == false or r == 0 then return false end
    return nil
end

local function SpellNameOf(spell)
    local ok, n
    if C_Spell and C_Spell.GetSpellName then ok, n = pcall(C_Spell.GetSpellName, spell)
    elseif GetSpellInfo then ok, n = pcall(GetSpellInfo, spell) end
    if ok and type(n) == "string" and not rangeSecret(n) then return n end
end

-- true / false, or nil when there's nothing to say (no target, unknown).
-- Tries the weapon's spell by id, then by name, then the button itself.
local lastHow -- which check answered (for /macrobook range)
local function InRange(spell, slot)
    lastHow = "no target"
    if not UnitExists("target") then return nil end
    local r
    if spell and C_Spell and C_Spell.IsSpellInRange then
        r = Answer(pcall(C_Spell.IsSpellInRange, spell, "target"))
        if r ~= nil then lastHow = "spell id"; return r end
        local name = SpellNameOf(spell)
        if name then
            r = Answer(pcall(C_Spell.IsSpellInRange, name, "target"))
            if r ~= nil then lastHow = "spell name"; return r end
        end
    end
    if spell and IsSpellInRange then
        local name = SpellNameOf(spell)
        if name then
            r = Answer(pcall(IsSpellInRange, name, "target"))
            if r ~= nil then lastHow = "old spell check"; return r end
        end
    end
    if slot then
        local f = (C_ActionBar and C_ActionBar.IsActionInRange) or IsActionInRange
        if f then
            r = Answer(pcall(f, slot, "target"))
            if r ~= nil then lastHow = "button"; return r end
        end
    end
    lastHow = "no answer"
    return nil
end

-- the action slots holding the macro (looked up again when bars or macros change)
local rangeSlots = {}
local function FindRangeSlots()
    wipe(rangeSlots)
    for slot = 1, 180 do
        -- (a macro's button reports the spell it casts as its id these
        -- days, so it's found by the name shown on the button)
        local ok, kind = pcall(GetActionInfo, slot)
        if ok and not rangeSecret(kind) and kind == "macro" then
            local okT, text = pcall(GetActionText, slot)
            if okT and not rangeSecret(text) and text == RANGE_MACRO then rangeSlots[slot] = true end
        end
    end
end

local tinted = {} -- buttons with the red tint made
local function Tint(b, on)
    local t = tinted[b]
    if not t then
        if not on then return end
        local icon = b.icon or b.Icon or _G[(b:GetName() or "") .. "Icon"]
        if not icon then return end
        t = b:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetAllPoints(icon)
        t:SetColorTexture(0.9, 0.08, 0.05, 0.55)
        tinted[b] = t
    end
    t:SetShown(on)
end

local function UpdateRange()
    local slot = next(rangeSlots)
    local out = false
    if slot then
        out = (InRange(RangedSpell(), slot) == false)
    end
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b and b:IsVisible() then
                local slot = b.action
                if not slot and b.GetAttribute then slot = b:GetAttribute("action") end
                Tint(b, out and slot ~= nil and rangeSlots[slot] == true)
            elseif b and tinted[b] then
                tinted[b]:Hide()
            end
        end
    end
end

local rangeFrame = CreateFrame("Frame")
local rangeTick = 0
rangeFrame:SetScript("OnUpdate", function(_, elapsed)
    rangeTick = rangeTick + elapsed
    if rangeTick < 0.15 then return end
    rangeTick = 0
    UpdateRange()
end)
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "ACTIONBAR_PAGE_CHANGED" }) do
    pcall(rangeFrame.RegisterEvent, rangeFrame, e)
end
rangeFrame:SetScript("OnEvent", function()
    C_Timer.After(0.2, function() FindRangeSlots(); UpdateRange() end)
end)

-- /macrobook range: what the Shoot range check sees right now
function MacroBookRangeReport()
    FindRangeSlots()
    local slots = {}
    for slot in pairs(rangeSlots) do slots[#slots + 1] = slot end
    table.sort(slots)
    local spell = RangedSpell()
    print(PREFIX .. "Shoot range: macro on action slots " .. (#slots > 0 and table.concat(slots, ", ") or "none found")
        .. "; ranged spell " .. tostring(spell and (SpellNameOf(spell) or spell) or "none (no ranged weapon?)"))
    local r = InRange(spell, slots[1])
    print(PREFIX .. "in range: " .. tostring(r) .. " (" .. tostring(lastHow) .. ")")
    local buttons = {}
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            local slot = b and (b.action or (b.GetAttribute and b:GetAttribute("action")))
            if slot and rangeSlots[slot] then buttons[#buttons + 1] = prefix .. i .. (b:IsVisible() and "" or " (hidden)") end
        end
    end
    print(PREFIX .. "buttons: " .. (#buttons > 0 and table.concat(buttons, ", ") or "none on the standard bars"))
end
