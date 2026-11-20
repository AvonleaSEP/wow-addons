-- MacroBook
-- Keeps the macros listed here in your character macros, per class: a
-- warrior gets the warrior list (MACROS below), a hunter the hunter list
-- (HUNTER_MACROS, empty for now), and any other class nothing.
--   * A listed macro that doesn't exist yet is created (as a character macro).
--   * A listed macro whose text differs is updated to match this file.
--   * Macros NOT listed here are never touched.
-- Changes apply when you log in or /reload (or type /macrobook).
-- Note: if you edit a listed macro in game, this file wins on the next login,
-- so make lasting changes here.
--
-- Your warrior's old account macros (WARRIOR_ACCOUNT_MACROS, further down)
-- move into Spliff-Rite's character macros by themselves the next time
-- Spliff-Rite logs in, so the account list is free for your other
-- characters. Only those names move; macros made since stay where they are.

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
        -- The Rend / Taunt stance dance (presses the MacroBookDance button,
        -- set up below). The icon: Rend in Defensive Stance, Taunt otherwise.
        --   Defensive Stance: press 1 switches to Battle Stance, press 2 Rend.
        --   Battle (or Berserker) Stance: press 1 switches to Defensive
        --     Stance, press 2 Taunt.
        -- (A stance change and its spell can't happen in one press on this
        -- client, so the button remembers which spell it switched for.)
        -- The two /click lines: one for a key-down press, one for key-up;
        -- the button acts on whichever your "cast on key down" setting uses.
        name = "RendTaunt",
        icon = 134400,
        body = [[
#showtooltip [stance:2] Rend; Taunt
/click MacroBookDance LeftButton 1
/click MacroBookDance LeftButton]],
    },
    {
        -- Mortal Strike, and start attacking if you aren't already
        name = "MS",
        icon = 134400,
        body = [[
#showtooltip Mortal Strike
/startattack
/cast Mortal Strike]],
    },
    {
        -- Sweeping Strikes needs Battle Stance: outside it, the press
        -- switches to Battle Stance; in it, Sweeping Strikes.
        name = "Sweep",
        icon = 134400,
        body = [[
#showtooltip Sweeping Strikes
/cast [nostance:1] Battle Stance; Sweeping Strikes]],
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
        --   otherwise Mortal Strike when it's ready (also on the global
        --     cooldown, so it never clashes with Victory Rush);
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
/cast Mortal Strike
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

    -- Weapon swaps: they use the weapons on Action Bar 4 (MultiBarRight),
    -- so whatever sits on those buttons is what goes on, at the moment you
    -- press. No item names in the macros: change a weapon by changing the
    -- button.
    --   button 10  your two-hander
    --   button 11  your one-hander (main hand)
    --   button 12  your shield
    -- They press MacroBook's own hidden buttons (MacroBookSwap,
    -- MacroBookShield, set up further down), which use those bar slots
    -- directly: a plain "/click MultiBarRightButton12" line doesn't equip
    -- on this client. Each press sends a key-down and a key-up click; the
    -- buttons act on whichever your "cast on key down" setting uses.
    -- The shield goes on before the one-hander: putting the shield on
    -- takes the two-hander off, so the one-hander lands in the empty main
    -- hand.
    {
        -- shield on: two-hander; otherwise shield + one-hander. It presses
        -- the MacroBookSwap button (set up below), which looks at your
        -- shield once per press and then does one or the other, so the
        -- two halves can never both happen.
        name = "Swap",
        icon = 132147,
        body = [[
/click MacroBookSwap LeftButton 1
/click MacroBookSwap LeftButton
/click MacroBookSwapB LeftButton 1
/click MacroBookSwapB LeftButton]],
    },
    {
        -- Shield Bash, shield + one-hander on first if they aren't. In
        -- Berserker Stance (no Shield Bash there) the press switches to
        -- Defensive Stance and puts the shield on; press again to bash.
        name = "Bash",
        icon = 132357,
        body = [[
#showtooltip Shield Bash
/stopcasting
/click MacroBookShield LeftButton 1
/click MacroBookShield LeftButton
/click MacroBookShield2 LeftButton 1
/click MacroBookShield2 LeftButton
/cast [stance:3] Defensive Stance; Shield Bash]],
    },
    {
        name = "Wall",
        icon = 132362,
        body = [[
#showtooltip Shield Wall
/click MacroBookShield LeftButton 1
/click MacroBookShield LeftButton
/click MacroBookShield2 LeftButton 1
/click MacroBookShield2 LeftButton
/cast [nostance:2] Defensive Stance; Shield Wall]],
    },
}

-- Your hunter's macros go here, same shape as the warrior ones above.
local HUNTER_MACROS = {
}

-- which list each class keeps (classes not listed get none)
local BY_CLASS = { WARRIOR = MACROS, HUNTER = HUNTER_MACROS }

local function MyMacros()
    local _, class = UnitClass("player")
    return BY_CLASS[class] or {}
end

-- The warrior's account macros (as they were on 19 Nov), moved once into
-- MOVE_TO's character macros. RXPTargeting stays account-wide.
local MOVE_TO = "Spliff-Rite"
local WARRIOR_ACCOUNT_MACROS = {
    "Bash", "BRage", "Charge", "Cheer", "Def", "Fish", "Follow", "Hammy", "Heroic", "MS", "OPower",
    "Rend", "RendTaunt", "Retali", "Shoot", "Swap", "Sweep", "Targe", "Target", "Taunt", "TClap", "Wall",
}

---------------------------------------------------------------------------
-- The stance-dance button (the RendTaunt macro clicks it). A secure button,
-- so it works in combat: on each press it picks its spell from your stance
-- and from what it switched stance for last time:
--   switched to Battle for Rend, now in Battle      -> Rend
--   switched to Defensive for Taunt, now Defensive  -> Taunt
--   in Defensive                                    -> Battle Stance (then Rend)
--   anywhere else                                   -> Defensive Stance (then Taunt)
-- What it switched for is forgotten when a fight ends.
---------------------------------------------------------------------------
local dance = CreateFrame("Button", "MacroBookDance", UIParent, "SecureActionButtonTemplate, SecureHandlerBaseTemplate")
dance:RegisterForClicks("AnyDown", "AnyUp")
dance:SetSize(1, 1) -- (never seen: just off the top-left of the screen)
dance:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -10, 10)
dance:SetAttribute("type", "spell")
dance:SetAttribute("spell", "Defensive Stance")
-- the game keeps the stance on the button, in combat too
RegisterAttributeDriver(dance, "stance", "[stance:1] 1; [stance:2] 2; [stance:3] 3; 0")
dance:WrapScript(dance, "OnClick", [[
    -- act on the key-down click or the key-up one, as the game's setting says
    if (down and true or false) ~= (self:GetAttribute("keydown") and true or false) then return false end
    local stance = tonumber(self:GetAttribute("stance")) or 0
    if pending == "rend" and stance == 1 then
        pending = nil
        self:SetAttribute("spell", "Rend")
    elseif pending == "taunt" and stance == 2 then
        pending = nil
        self:SetAttribute("spell", "Taunt")
    elseif stance == 2 then
        pending = "rend"
        self:SetAttribute("spell", "Battle Stance")
    else
        pending = "taunt"
        self:SetAttribute("spell", "Defensive Stance")
    end
]])

---------------------------------------------------------------------------
-- The weapon-swap buttons (the Swap macro clicks MacroBookSwap, then
-- MacroBookSwapB). The first checks once, per press, whether a shield is
-- on, and sets up both:
--   shield on   -> first: Action Bar 4's button 10 (your two-hander);
--                  second: nothing
--   no shield   -> first: button 12 (shield); second: button 11 (one-hander)
-- Deciding once matters: done as separate macro lines, the game can see
-- the swap half-made and undo it within the same press. Both use the
-- bar's action slots directly ("action" buttons): a macro inside a macro
-- doesn't run, which is what broke the shield half the first time.
---------------------------------------------------------------------------
local SWAP_BAR = "MultiBarRightButton" -- Action Bar 4
local SWAP_BAR_FIRST = 25               -- its first action slot, if a button won't say

local function SwapButton(name)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate, SecureHandlerBaseTemplate")
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetSize(1, 1)
    b:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -10, 10)
    b:SetAttribute("type", "action")
    return b
end
local swap, swapB = SwapButton("MacroBookSwap"), SwapButton("MacroBookSwapB")
SecureHandlerSetFrameRef(swap, "second", swapB)
swap:WrapScript(swap, "OnClick", [[
    if (down and true or false) ~= (self:GetAttribute("keydown") and true or false) then return false end
    local second = self:GetFrameRef("second")
    if SecureCmdOptionParse("[equipped:Shields] two; one") == "two" then
        self:SetAttribute("action", self:GetAttribute("twoSlot"))
        second:SetAttribute("type", nil)
    else
        self:SetAttribute("action", self:GetAttribute("shieldSlot"))
        second:SetAttribute("type", "action")
        second:SetAttribute("action", self:GetAttribute("oneSlot"))
    end
]])
-- (the second only acts on the click your key-down setting uses, too)
swapB:WrapScript(swapB, "OnClick", [[
    if (down and true or false) ~= (self:GetAttribute("keydown") and true or false) then return false end
]])

-- Shield on (Bash and Wall click MacroBookShield, then MacroBookShield2):
-- with no shield equipped, the first puts on bar 4's button 12 (shield)
-- and the second button 11 (one-hander); with a shield on, neither does
-- anything. Decided once per press, like Swap.
local shieldOn, shieldOn2 = SwapButton("MacroBookShield"), SwapButton("MacroBookShield2")
SecureHandlerSetFrameRef(shieldOn, "second", shieldOn2)
shieldOn:WrapScript(shieldOn, "OnClick", [[
    if (down and true or false) ~= (self:GetAttribute("keydown") and true or false) then return false end
    local second = self:GetFrameRef("second")
    if SecureCmdOptionParse("[equipped:Shields] on; off") == "on" then
        self:SetAttribute("type", nil)
        second:SetAttribute("type", nil)
    else
        self:SetAttribute("type", "action")
        self:SetAttribute("action", self:GetAttribute("shieldSlot"))
        second:SetAttribute("type", "action")
        second:SetAttribute("action", self:GetAttribute("oneSlot"))
    end
]])
shieldOn2:WrapScript(shieldOn2, "OnClick", [[
    if (down and true or false) ~= (self:GetAttribute("keydown") and true or false) then return false end
]])

-- (out of combat: bar 4's action slots for buttons 10, 11 and 12)
local function SetUpSwap()
    if InCombatLockdown() then return end
    local function Slot(n)
        local b = _G[SWAP_BAR .. n]
        local slot = b and (b.action or (b.GetAttribute and b:GetAttribute("action")))
        if type(slot) ~= "number" or slot < 1 then slot = SWAP_BAR_FIRST + n - 1 end
        return slot
    end
    local down = GetCVarBool("ActionButtonUseKeyDown") and true or false
    swap:SetAttribute("keydown", down)
    swapB:SetAttribute("keydown", down)
    swap:SetAttribute("twoSlot", Slot(10))
    swap:SetAttribute("oneSlot", Slot(11))
    swap:SetAttribute("shieldSlot", Slot(12))
    shieldOn:SetAttribute("keydown", down)
    shieldOn2:SetAttribute("keydown", down)
    shieldOn:SetAttribute("oneSlot", Slot(11))
    shieldOn:SetAttribute("shieldSlot", Slot(12))
end

local danceEvents = CreateFrame("Frame")
danceEvents:RegisterEvent("PLAYER_LOGIN")
danceEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
danceEvents:RegisterEvent("CVAR_UPDATE")
danceEvents:SetScript("OnEvent", function()
    if InCombatLockdown() then return end
    dance:SetAttribute("keydown", GetCVarBool("ActionButtonUseKeyDown") and true or false)
    dance:Execute("pending = nil") -- (a fight's half-done dance)
    SetUpSwap()
end)

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
    -- {click:Button}: the button, said the way your key-down setting needs
    local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    body = body:gsub("{click:(%w+)}", function(buttonName)
        return down and (buttonName .. " LeftButton 1") or buttonName
    end)
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
    for _, list in pairs(BY_CLASS) do
        for _, m in ipairs(list) do own[m.name] = true end
    end
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

---------------------------------------------------------------------------
-- /macrobook move: your account macros become this character's. Each one
-- is copied into your character macros and the account copy deleted; any
-- action bar slot that held it gets the character copy, so your bars stay
-- as they were. RXP Guides' own macros (RXPTargeting ...) stay put. A
-- backup of everything moved is kept (MacroBookDB.moved).
---------------------------------------------------------------------------
local function MoveSkipped(name) return trim(name):sub(1, 3) == "RXP" end

-- this character's macro by that name, if there is one
local function CharacterMacro(name)
    local first = (MAX_ACCOUNT_MACROS or 120) + 1
    local _, numChar = GetNumMacros()
    for i = first, first + (numChar or 0) - 1 do
        if trim(GetMacroInfo(i) or "") == trim(name) then return i end
    end
end

-- the action bar slots holding macro number `index`. On this client a
-- macro's button reports the spell the macro casts as its id, not the
-- macro's number, so the name the button shows counts too (19 Nov: the
-- move went by the number alone, found no buttons, and the macros came
-- off the bars).
local function SlotsFor(index)
    local name = trim(GetMacroInfo(index) or "")
    local slots = {}
    for slot = 1, 180 do
        local ok, kind, id = pcall(GetActionInfo, slot)
        if ok and kind == "macro" then
            local okT, text = pcall(GetActionText, slot)
            if id == index or (okT and type(text) == "string" and name ~= "" and trim(text) == name) then
                slots[#slots + 1] = slot
            end
        end
    end
    return slots
end

---------------------------------------------------------------------------
-- /macrobook restore: puts your warrior macros back where they were on
-- 16 Nov (read off that day's screenshot, WoWScrnShot_111626_024025), by
-- where each button sits on screen, so it doesn't matter which bar is
-- which. Only empty buttons are filled; anything you've put there since
-- stays. The main bar changes with your stance, so its four (Rend, Hammy,
-- Bash, Heroic) go on the stance you're in when you type it.
---------------------------------------------------------------------------
-- macro name, button centre in that 3840 x 2160 screenshot
local OLD_SPOTS = {
    { "BRage", 945, 2023 }, { "Shoot", 1449, 2023 }, { "Taunt", 1620, 2023 },
    { "Wall", 2045, 2023 }, { "Retali", 2128, 2023 },
    { "Rend", 1447, 2112 }, { "Hammy", 1620, 2112 }, { "Bash", 1702, 2112 }, { "Heroic", 1870, 2112 },
    { "Charge", 1702, 1803 }, { "Swap", 1963, 1803 }, { "Follow", 2131, 1803 },
    { "Def", 1790, 1883 }, { "Fish", 2049, 1883 }, { "Target", 2131, 1883 },
}
local SHOT_W, SHOT_H = 3840, 2160
local BUTTON_BARS = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

-- the action button whose centre is at (x, y) of the screenshot, or nil
local function ButtonAt(x, y)
    local ui = UIParent:GetEffectiveScale()
    local sw, sh = GetScreenWidth() * ui, GetScreenHeight() * ui
    local best, bestD
    for _, prefix in ipairs(BUTTON_BARS) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b and b:IsVisible() then
                local cx, cy = b:GetCenter()
                if cx then
                    local s = b:GetEffectiveScale()
                    local bx = cx * s / sw * SHOT_W
                    local by = (1 - cy * s / sh) * SHOT_H
                    local d = math.abs(bx - x) + math.abs(by - y)
                    if d < 50 and (not bestD or d < bestD) then best, bestD = b, d end
                end
            end
        end
    end
    return best
end

local function ButtonSlotOf(b)
    local slot = b.action
    if type(slot) ~= "number" and b.GetAttribute then slot = b:GetAttribute("action") end
    if type(slot) ~= "number" and b.CalculateAction then
        local ok, s = pcall(b.CalculateAction, b)
        if ok then slot = s end
    end
    return type(slot) == "number" and slot or nil
end

local function RestoreBars()
    if InCombatLockdown() then print(PREFIX .. "can't change your bars in combat; try again after.") return end
    if GetCursorInfo() then ClearCursor() end
    local placed, taken, gone, nobutton = {}, {}, {}, {}
    for _, spot in ipairs(OLD_SPOTS) do
        local name, x, y = spot[1], spot[2], spot[3]
        local index = CharacterMacro(name) or GetMacroIndexByName(name)
        if not index or index == 0 then
            gone[#gone + 1] = name
        else
            local b = ButtonAt(x, y)
            local slot = b and ButtonSlotOf(b)
            if not slot then
                nobutton[#nobutton + 1] = name
            elseif HasAction(slot) then
                -- (already there, or something else is: either way, leave it)
                local okT, text = pcall(GetActionText, slot)
                if not (okT and type(text) == "string" and trim(text) == name) then taken[#taken + 1] = name end
            else
                PickupMacro(index)
                PlaceAction(slot)
                ClearCursor()
                placed[#placed + 1] = name
            end
        end
    end
    if #placed > 0 then print(PREFIX .. "back on your bars: " .. table.concat(placed, ", ")) end
    if #taken > 0 then print(PREFIX .. "something else sits where these were, so they weren't placed: " .. table.concat(taken, ", ")) end
    if #nobutton > 0 then print(PREFIX .. "no button where these were (bars moved since 16 Nov?): " .. table.concat(nobutton, ", ")) end
    if #gone > 0 then print(PREFIX .. "no macro by these names: " .. table.concat(gone, ", ")) end
    if #placed == 0 and #taken == 0 and #nobutton == 0 then print(PREFIX .. "nothing to put back.") end
    print(PREFIX .. "not in that screenshot, so place these yourself: MS, RendTaunt, Sweep, TClap, OPower, Cheer, Targe.")
end

-- onlyNames: a set of trimmed names to move (nil = every account macro but
-- RXP Guides' own). The character macros have a limit (MAX_CHARACTER_MACROS),
-- so the ones on your action bars go first, then this class's MacroBook
-- ones, then the rest; whatever doesn't fit stays account-wide and is named.
local function MoveToCharacter(onlyNames)
    if InCombatLockdown() then print(PREFIX .. "can't move macros in combat; try again after.") return end
    if GetCursorInfo() then ClearCursor() end
    MacroBookDB = MacroBookDB or {}
    MacroBookDB.moved = MacroBookDB.moved or {}
    local room = MAX_CHARACTER_MACROS or 18
    local moved, left, full = {}, {}, {}
    local mine = {}
    for _, m in ipairs(MyMacros()) do mine[m.name] = true end
    -- names first: deleting one renumbers the rest, so each is found afresh
    local names, rank = {}, {}
    local numAccount = GetNumMacros()
    for i = 1, numAccount or 0 do
        local name = GetMacroInfo(i)
        if type(name) == "string" and (not onlyNames or onlyNames[trim(name)]) then
            names[#names + 1] = name
            rank[name] = (#SlotsFor(i) > 0 and 1) or (mine[trim(name)] and 2) or 3
        end
    end
    local order = {}
    for i, name in ipairs(names) do order[name] = i end
    table.sort(names, function(a, b)
        if rank[a] ~= rank[b] then return rank[a] < rank[b] end
        return order[a] < order[b]
    end)
    for _, name in ipairs(names) do
        if MoveSkipped(name) then
            left[#left + 1] = trim(name)
        else
            local index
            for i = 1, (GetNumMacros()) do
                if GetMacroInfo(i) == name then index = i break end
            end
            local _, numChar = GetNumMacros()
            local existing = CharacterMacro(name)
            if index and (existing or (numChar or 0) < room) then
                local _, icon, body = GetMacroInfo(index)
                local slots = SlotsFor(index)
                table.insert(MacroBookDB.moved, { name = name, icon = icon, body = body, at = time() })
                local okD = pcall(DeleteMacro, index)
                local target = existing
                if okD and not target then
                    local okC = pcall(CreateMacro, name, icon or 134400, body or "", true)
                    target = okC and CharacterMacro(name)
                end
                if okD and target then
                    -- back on the bars where it was
                    for _, slot in ipairs(slots) do
                        PickupMacro(target)
                        PlaceAction(slot)
                        ClearCursor()
                    end
                    moved[#moved + 1] = trim(name)
                elseif not okD then
                    left[#left + 1] = trim(name)
                end
            elseif index then
                full[#full + 1] = trim(name)
            end
        end
    end
    if #moved > 0 then print(PREFIX .. "moved to this character: " .. table.concat(moved, ", ")) end
    if #full > 0 then
        print(PREFIX .. "no room left in your character macros (" .. room .. "), still account-wide: "
            .. table.concat(full, ", "))
    end
    if #left > 0 then print(PREFIX .. "left as account macros: " .. table.concat(left, ", ")) end
    if #moved == 0 and #full == 0 then print(PREFIX .. "no account macros to move.") end
    return moved, full
end

-- the character's name as the saved-data folders write it: "Spliff-Rite"
local function CharacterKey()
    local first, second = UnitName("player")
    if type(first) ~= "string" then return nil end
    if type(second) == "string" and second ~= "" then return first .. "-" .. second end
    return first
end

-- Once: the warrior's old account macros become Spliff-Rite's own.
local function AutoMoveWarrior()
    MacroBookDB = MacroBookDB or {}
    if MacroBookDB.warriorMoved then return end
    local _, class = UnitClass("player")
    if class ~= "WARRIOR" or CharacterKey() ~= MOVE_TO then return end
    local set = {}
    for _, n in ipairs(WARRIOR_ACCOUNT_MACROS) do set[trim(n)] = true end
    print(PREFIX .. "moving your warrior macros from the account list into " .. MOVE_TO .. "'s own macros...")
    MoveToCharacter(set)
    MacroBookDB.warriorMoved = time()
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

    -- first, once on Spliff-Rite: its old account macros become its own, so
    -- the loop below finds them as character macros
    AutoMoveWarrior()

    local added, updated, unchanged, problems, skipped = {}, {}, 0, {}, {}
    local list = MyMacros()
    if #list == 0 then
        if verbose then print(PREFIX .. "no MacroBook macros for this class yet.") end
        FixTwoWordTargets()
        return
    end

    for _, m in ipairs(list) do
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
                -- a character macro (account ones don't carry over on Forever)
                local ok, err = pcall(CreateMacro, m.name, m.icon or 134400, body, true)
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
frame:RegisterEvent("CVAR_UPDATE")
frame:SetScript("OnEvent", function(_, event, isInitialLogin, isReloadingUi)
    if event == "PLAYER_ENTERING_WORLD" then
        if isInitialLogin or isReloadingUi then
            C_Timer.After(1, function() Sync(false) end)
        end
    elseif event == "CVAR_UPDATE" then
        -- "cast on key down" changed: the weapon macros' /click lines follow it
        local cvar = isInitialLogin
        if type(cvar) == "string" and cvar:lower():find("keydown") then Sync(false) end
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
    if msg and msg:lower():match("^%s*move") then
        MoveToCharacter()
        return
    end
    if msg and msg:lower():match("^%s*restore") then
        RestoreBars()
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
