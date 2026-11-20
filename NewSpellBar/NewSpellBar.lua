-- New Spell Bar
-- Each spell you learn (at a trainer, from a level-up, a quest or a book)
-- goes on the first empty button of Action Bar 5, so it's ready to press.
--   * Passives are skipped (nothing to press).
--   * A spell already on any of your bars is skipped, and so is a new rank
--     of one (same name), since the bar button already casts it.
--   * Learned mid-fight: placed when the fight ends (the game locks your
--     bars in combat).
--   * Bar 5 full: it says so in chat and leaves it in your spellbook.
-- Action Bar 5 has to be switched on to see it: Esc > Options > Action
-- Bars > Action Bar 5 (or Edit Mode).
--
--   /newspells           what it does and which bar it uses
--   /newspells bar 6     use another bar (2 to 8)
--   /newspells off / on  stop / start placing

local PREFIX = "|cffc79c6eNew Spell Bar|r "
local DEFAULT_BAR = 5

-- each bar's buttons (the game's names) and, if a button won't say, the
-- action slots they use
local BARS = {
    [2] = { "MultiBarBottomLeftButton", 61 },
    [3] = { "MultiBarBottomRightButton", 49 },
    [4] = { "MultiBarRightButton", 25 },
    [5] = { "MultiBarLeftButton", 37 },
    [6] = { "MultiBar5Button", 145 },
    [7] = { "MultiBar6Button", 157 },
    [8] = { "MultiBar7Button", 169 },
}

local DB
local isSecret = issecretvalue or function() return false end
local function Plain(v) if not isSecret(v) then return v end end

local function SpellName(id)
    local ok, n
    if C_Spell and C_Spell.GetSpellName then ok, n = pcall(C_Spell.GetSpellName, id)
    elseif GetSpellInfo then ok, n = pcall(GetSpellInfo, id) end
    n = ok and Plain(n)
    return type(n) == "string" and n or nil
end

local function IsPassive(id)
    local ok, p
    if C_Spell and C_Spell.IsSpellPassive then ok, p = pcall(C_Spell.IsSpellPassive, id)
    elseif IsPassiveSpell then ok, p = pcall(IsPassiveSpell, id) end
    return ok and Plain(p) == true
end

-- the action slots of the chosen bar, left to right
local function BarSlots()
    local bar = BARS[(DB and DB.bar) or DEFAULT_BAR] or BARS[DEFAULT_BAR]
    local slots = {}
    for i = 1, 12 do
        local b = _G[bar[1] .. i]
        local slot = b and (b.action or (b.GetAttribute and b:GetAttribute("action")))
        if type(slot) ~= "number" or slot < 1 then slot = bar[2] + i - 1 end
        slots[i] = slot
    end
    return slots
end

-- is this spell, or another rank of it, on any bar already?
local function OnBars(id, name)
    for slot = 1, 180 do
        local ok, kind, sid = pcall(GetActionInfo, slot)
        if ok and Plain(kind) == "spell" then
            sid = Plain(sid)
            if sid == id or (name and sid and SpellName(sid) == name) then return true end
        end
    end
    return false
end

local queue = {}   -- spell ids waiting to be placed
local frame = CreateFrame("Frame")

local function PlaceOne(id)
    local name = SpellName(id)
    if not name or IsPassive(id) or OnBars(id, name) then return true end
    for _, slot in ipairs(BarSlots()) do
        if not HasAction(slot) then
            if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(id) else PickupSpell(id) end
            local kind = GetCursorInfo()
            if kind ~= "spell" then
                ClearCursor()
                return true -- the game won't hand it over (not a castable spell): leave it
            end
            PlaceAction(slot)
            ClearCursor()
            print(PREFIX .. name .. " is on Action Bar " .. ((DB and DB.bar) or DEFAULT_BAR) .. ".")
            return true
        end
    end
    print(PREFIX .. "Action Bar " .. ((DB and DB.bar) or DEFAULT_BAR) .. " is full; " .. name
        .. " is in your spellbook.")
    return true
end

local function Drain()
    if InCombatLockdown() then frame:RegisterEvent("PLAYER_REGEN_ENABLED") return end
    -- never drop something you're holding on the cursor
    if GetCursorInfo() then C_Timer.After(1, Drain) return end
    while #queue > 0 do
        local id = table.remove(queue, 1)
        pcall(PlaceOne, id)
    end
end

local function Learned(id)
    id = Plain(id)
    if not DB or DB.off or type(id) ~= "number" then return end
    for _, q in ipairs(queue) do if q == id then return end end
    queue[#queue + 1] = id
    -- a moment's wait: a trainer can teach several at once, and the
    -- spellbook needs a beat to list a new spell
    C_Timer.After(0.5, Drain)
end

frame:RegisterEvent("ADDON_LOADED")
-- (the event's name differs between clients; registering a missing one errors)
pcall(frame.RegisterEvent, frame, "LEARNED_SPELL_IN_TAB")
pcall(frame.RegisterEvent, frame, "LEARNED_SPELL_IN_SKILL_LINE")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "NewSpellBar" then return end
        NewSpellBarDB = NewSpellBarDB or {}
        DB = NewSpellBarDB
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_REGEN_ENABLED" then
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Drain()
    else
        Learned(arg1)
    end
end)

SLASH_NEWSPELLBAR1 = "/newspells"
SlashCmdList.NEWSPELLBAR = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local n = tonumber(msg:match("^bar%s*(%d+)$"))
    if n then
        if not BARS[n] then print(PREFIX .. "pick a bar from 2 to 8.") return end
        DB.bar = n
        print(PREFIX .. "new spells now go on Action Bar " .. n .. ".")
    elseif msg == "off" or msg == "on" then
        DB.off = (msg == "off") or nil
        print(PREFIX .. (DB.off and "off: new spells stay in your spellbook." or "on."))
    else
        print(PREFIX .. (DB.off and "off" or ("new spells go on Action Bar " .. (DB.bar or DEFAULT_BAR)))
            .. ". /newspells bar 2-8, /newspells off, /newspells on.")
    end
end
