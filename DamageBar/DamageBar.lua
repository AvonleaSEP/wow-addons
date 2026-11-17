-- Damage Bar
-- One fixed-width bar split into coloured pieces, one per ability, each as
-- wide as that ability's share of your damage. It adds up across fights and
-- empties after 10 minutes out of combat (changeable in Edit Mode).
-- Hover it for the full list.
--
-- Where the numbers come from: this client closes the combat log to addons,
-- so the bar reads the game's own damage meter (C_DamageMeter). The meter
-- hides its per-ability numbers from addons during a fight (seen in the log
-- 15 Nov: "spells hidden", only the total, as a secret) and opens them up
-- about a second after. So the bar updates when each fight ends, exact,
-- with names and percentages. (If a future client shows the numbers in
-- combat, the live paths below pick them up on their own.)
--
-- Edit Mode (Esc > Edit Mode): drag it, click it for Width, Height, Labels,
-- Label Size, Hide When Empty and Reset After.
--
-- Edit Mode support comes from LibEditMode by p3lim (Libs\LibEditMode).

local DEBUG_LOG = true -- temporary: notes what the meter reports into the saved file

local LAYOUT_DEFAULTS = { width = 300, height = 16, labels = true, labelSize = 10, hideEmpty = false,
    hitSection = true, hitPct = 10,
    font = "Game default", outline = "", labelFormat = "namepct", textColor = "white",
    fill = "flat", bgAlpha = 0.75, border = true, scale = 1, maxAbilities = 8,
    showWhen = "always", tooltip = "default" }

---------------------------------------------------------------------------
-- Fonts: the game's own plus every font other addons share through
-- LibSharedMedia (HealBot adds 25). Looked up when needed.
---------------------------------------------------------------------------
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
    return (GameFontHighlightSmall:GetFont())
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
-- set a font string's font, falling back to the game's if the file won't load
local function ApplyFont(fs, l, size)
    fs:SetFont(FontPath(l.font), size, l.outline or "")
    if not fs:GetFont() then fs:SetFont(FontPath(nil), size, l.outline or "") end
end
local TEXT_COLORS = { white = { 1, 1, 1 }, gold = { 1, 0.82, 0 } }
local RESET_DEFAULT = 10 -- minutes out of combat

-- one colour per ability, given out in the order abilities are first seen
local PALETTE = {
    { 0.90, 0.30, 0.25 }, { 0.25, 0.60, 0.95 }, { 0.95, 0.75, 0.20 }, { 0.40, 0.80, 0.35 },
    { 0.70, 0.45, 0.90 }, { 0.95, 0.55, 0.20 }, { 0.30, 0.80, 0.80 }, { 0.90, 0.40, 0.65 },
    { 0.65, 0.65, 0.65 }, { 0.60, 0.40, 0.25 }, { 0.75, 0.90, 0.40 }, { 0.40, 0.45, 0.90 },
}

---------------------------------------------------------------------------
local LEM = LibStub("LibEditMode")
local isSecret = issecretvalue or function() return false end
local function Plain(v) if isSecret(v) then return nil end return v end
local function Tbl(v) if not isSecret(v) and type(v) == "table" then return v end end
local function Num(v) return not isSecret(v) and type(v) == "number" end

local DB -- DamageBarDB, once loaded

local function DebugAdd(line)
    if not DEBUG_LOG or not DB then return end
    DB.debug = DB.debug or {}
    DB.debug[#DB.debug + 1] = date("%H:%M:%S") .. " " .. line
    while #DB.debug > 300 do table.remove(DB.debug, 1) end
end
local lastNote
local function Note(line) -- only logs when it changes
    if line ~= lastNote then lastNote = line; DebugAdd(line) end
end

---------------------------------------------------------------------------
-- Reading the game's damage meter
---------------------------------------------------------------------------
local meter = C_DamageMeter
local DAMAGE = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone
local CURRENT = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current

-- Session ids the meter has, oldest first (one per fight).
local function SessionIDs()
    local out = {}
    if not (meter and meter.GetAvailableCombatSessions) then return out end
    local ok, list = pcall(meter.GetAvailableCombatSessions)
    for _, s in ipairs(ok and Tbl(list) or {}) do
        s = Tbl(s)
        local id = s and Plain(s.sessionID)
        if Num(id) then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

-- The meter keeps totals only (fields seen 16 Nov: amountPerSecond,
-- combatSpellDetails, creatureName, isAvoidable, isDeadly, overkillAmount,
-- spellID, totalAmount), so no single hits; the record kept instead is the
-- most one ability did in one fight.

-- Your damage by ability in one session (nil = this fight).
-- Returns list, status, total. Each entry is { key, id, amount }; id and
-- amount can be hidden ("secret") during a fight.
local function ReadMine(sessionID)
    if not (meter and DAMAGE) then return nil, "no meter" end
    local ok, session
    if sessionID then
        ok, session = pcall(meter.GetCombatSessionFromID, sessionID, DAMAGE)
    elseif CURRENT and meter.GetCombatSessionFromType then
        ok, session = pcall(meter.GetCombatSessionFromType, CURRENT, DAMAGE)
    end
    session = ok and Tbl(session)
    if not session then return nil, "no session" end
    local sources = Tbl(session.combatSources)
    if not sources then return nil, "sources hidden" end
    local me
    for _, src in ipairs(sources) do
        src = Tbl(src)
        if src and Plain(src.isLocalPlayer) == true then me = src break end
    end
    if not me then return {}, "no damage yet" end
    local okD, data
    if sessionID then
        okD, data = pcall(meter.GetCombatSessionSourceFromID, sessionID, DAMAGE, me.sourceGUID, me.sourceCreatureID)
    else
        okD, data = pcall(meter.GetCombatSessionSourceFromType, CURRENT, DAMAGE, me.sourceGUID, me.sourceCreatureID)
    end
    data = okD and Tbl(data)
    local spells = data and Tbl(data.combatSpells)
    if not spells then return nil, "spells hidden", me.totalAmount end
    local out = {}
    for _, sp in ipairs(spells) do
        sp = Tbl(sp)
        if sp then
            local id = sp.spellID
            if not isSecret(id) and id == nil then id = sp.spellId end
            local key
            if isSecret(id) then key = nil
            elseif Num(id) and id > 0 then key = id
            else key = "melee" end
            out[#out + 1] = { key = key, id = id, amount = sp.totalAmount }
        end
    end
    return out, "ok", me.totalAmount
end

local function SafeRead(sessionID)
    local ok, list, status, total = pcall(ReadMine, sessionID)
    if not ok then return nil, "error: " .. tostring(list) end
    return list, status, total
end

-- true when every key and amount can be used in plain Lua
local function AllPlain(list)
    for _, e in ipairs(list) do
        if e.key == nil or not Num(e.amount) then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- The running total since the last reset (saved, so /reload keeps it)
---------------------------------------------------------------------------
local inCombat = false

local function ResetSeconds() return (DB.resetMinutes or RESET_DEFAULT) * 60 end

-- When the bar empties by itself (Edit Mode "Reset"):
--   timer  after "Reset After (min)" out of combat (the default)
--   never  only when you right-click it or type /dbar reset
--   fight  at the start of each fight, so it shows your latest fight
--   zone   when you change zone
--   login  each time you log in (a /reload keeps it)
local RESET_MODES = {
    { text = "After time out of combat", value = "timer" },
    { text = "Never (right-click to clear)", value = "never" },
    { text = "Each fight", value = "fight" },
    { text = "On zone change", value = "zone" },
    { text = "Each login", value = "login" },
}
local function ResetMode() return DB and DB.resetMode or "timer" end

local function Expired()
    return ResetMode() == "timer" and not inCombat and DB.lastCombatEnd ~= nil and next(DB.acc) ~= nil
        and time() - DB.lastCombatEnd >= ResetSeconds()
end

local function AutoReset(why)
    if next(DB.acc) == nil then return end
    wipe(DB.acc)
    DebugAdd("reset: " .. why)
end

local function ColorFor(key)
    DB.colors = DB.colors or {}
    local i = DB.colors[key]
    if not i then
        DB.colorNext = (DB.colorNext or 0) % #PALETTE + 1
        i = DB.colorNext
        DB.colors[key] = i
    end
    return PALETTE[i]
end

local function SpellName(key)
    if key == "melee" then return "Melee" end
    local ok, n
    if C_Spell and C_Spell.GetSpellName then ok, n = pcall(C_Spell.GetSpellName, key)
    elseif GetSpellInfo then ok, n = pcall(GetSpellInfo, key) end
    n = ok and Plain(n)
    return type(n) == "string" and n or ("Spell " .. tostring(key))
end

---------------------------------------------------------------------------
-- Best records (the most one ability did in one fight): today's (starts over each calendar day) and ever.
-- { amount, spell = spell name or nil, when = "YYYY-MM-DD" }
---------------------------------------------------------------------------

local function NoteBest(amount, key)
    if not DB or not Num(amount) or amount <= 0 then return end
    local today = date("%Y-%m-%d")
    if not DB.bestDay or DB.bestDay.when ~= today then DB.bestDay = { amount = 0, when = today } end
    local spell = key and SpellName(key) or nil
    if amount > DB.bestDay.amount then DB.bestDay = { amount = amount, spell = spell, when = today } end
    if not DB.bestEver or amount > DB.bestEver.amount then
        DB.bestEver = { amount = amount, spell = spell, when = today }
    end
end

local function BestToday()
    if DB and DB.bestDay and DB.bestDay.when == date("%Y-%m-%d") and DB.bestDay.amount > 0 then return DB.bestDay end
end

---------------------------------------------------------------------------
-- Single hits: the biggest one number today and ever, and a high score per
-- ability. The source is the game's "your target took N damage" notice
-- (UNIT_COMBAT on your target, what puts hit numbers on portraits); the
-- ability is the one you cast just before the hit, else Auto Attack.
-- Solo only: in a group other players' hits land on your target too.
-- Whether this client lets addons read those numbers isn't known yet (the
-- game's docs mark them hidden); the log notes it on the first hit
-- ("target hit amount: plain / secret"). Until hits arrive, the box keeps
-- showing the best ability in one fight.
-- DB.hitDay / DB.hitEver = { amount, spell, when }; DB.hitScores[spell] = { amount, when }
---------------------------------------------------------------------------
local lastCast -- { name, at }: your latest spell, to name the next hit

local function NoteHit(amount, spell)
    local today = date("%Y-%m-%d")
    if not DB.hitDay or DB.hitDay.when ~= today then DB.hitDay = { amount = 0, when = today } end
    if amount > DB.hitDay.amount then DB.hitDay = { amount = amount, spell = spell, when = today } end
    if not DB.hitEver or amount > DB.hitEver.amount then DB.hitEver = { amount = amount, spell = spell, when = today } end
    DB.hitScores = DB.hitScores or {}
    local s = DB.hitScores[spell]
    if not s or amount > s.amount then DB.hitScores[spell] = { amount = amount, when = today } end
end

local function HitToday()
    if DB and DB.hitDay and DB.hitDay.when == date("%Y-%m-%d") and DB.hitDay.amount > 0 then return DB.hitDay end
end

---------------------------------------------------------------------------
-- Per-layout look settings
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

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local bar = CreateFrame("Frame", "DamageBarFrame", UIParent)
bar.editModeName = "Damage Bar"
bar:SetSize(LAYOUT_DEFAULTS.width, LAYOUT_DEFAULTS.height)
bar:SetClampedToScreen(true)
bar:SetFrameStrata("MEDIUM")

local edge = bar:CreateTexture(nil, "BACKGROUND", nil, 0)
edge:SetAllPoints()
edge:SetColorTexture(0, 0, 0, 0.9)

local inner = CreateFrame("Frame", nil, bar)
inner:SetPoint("TOPLEFT", 1, -1)
inner:SetPoint("BOTTOMRIGHT", -1, 1)
inner:SetClipsChildren(true)
local back = inner:CreateTexture(nil, "BACKGROUND")
back:SetAllPoints()
back:SetColorTexture(0.08, 0.08, 0.1, 0.75)

local emptyText = inner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
emptyText:SetPoint("CENTER")

-- The best-of-the-day box at the left end: the most one ability did in one
-- fight today ("Best-in-a-Fight Section" / "Width %"); the split fills the rest.
local hitBox = CreateFrame("Frame", nil, inner)
hitBox:SetPoint("TOPLEFT")
hitBox:SetPoint("BOTTOMLEFT")
hitBox:SetFrameLevel(inner:GetFrameLevel() + 3)
local hitBg = hitBox:CreateTexture(nil, "BACKGROUND")
hitBg:SetAllPoints()
hitBg:SetColorTexture(0.2, 0.15, 0.02, 0.95)
local hitEdge = hitBox:CreateTexture(nil, "ARTWORK")
hitEdge:SetPoint("TOPRIGHT")
hitEdge:SetPoint("BOTTOMRIGHT")
hitEdge:SetWidth(1)
hitEdge:SetColorTexture(1, 0.82, 0, 0.8)
local hitText = hitBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hitText:SetPoint("CENTER")
hitText:SetTextColor(1, 0.82, 0)
hitText:SetWordWrap(false)

local function HitShort(n)
    if n >= 1e6 then return string.format("%.1fm", n / 1e6) end
    if n >= 1e4 then return string.format("%.0fk", n / 1e3) end
    if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
    return tostring(math.floor(n + 0.5))
end

local function HitWidth()
    local l = Look()
    if not l.hitSection then return 0 end
    return math.floor((l.width - 2) * (l.hitPct or 10) / 100 + 0.5)
end

local function UpdateHitBox()
    local w = HitWidth()
    emptyText:ClearAllPoints()
    emptyText:SetPoint("CENTER", inner, "CENTER", w / 2, 0) -- centred in the damage part
    hitBox:SetShown(w > 0)
    if w == 0 then return end
    hitBox:SetWidth(w)
    ApplyFont(hitText, Look(), Look().labelSize)
    hitText:SetWidth(w - 2)
    -- today's biggest single hit once hits come through; else the best
    -- ability in one fight
    local b = (DB and DB.hitEver) and HitToday() or (not (DB and DB.hitEver) and BestToday()) or nil
    hitText:SetText(b and HitShort(b.amount) or "-")
end

local segs = {}
local function Seg(i)
    local s = segs[i]
    if not s then
        s = CreateFrame("StatusBar", nil, inner)
        s:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        s:SetFrameLevel(inner:GetFrameLevel() + 1)
        s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.text:SetPoint("LEFT", s:GetStatusBarTexture(), "LEFT", 3, 0)
        s.text:SetPoint("RIGHT", s:GetStatusBarTexture(), "RIGHT", -2, 0)
        s.text:SetJustifyH("LEFT")
        s.text:SetWordWrap(false)
        segs[i] = s
    end
    return s
end

-- Lays out pieces left to right: each piece is a full-width status bar that
-- starts where the previous one's fill ends, so no adding up is needed and
-- hidden numbers can be shown as they are.
local function Draw(entries, total, withText)
    local l = Look()
    local hw = HitWidth() -- the biggest-hit box takes the left end
    local w = l.width - 2 - hw
    local tc = TEXT_COLORS[l.textColor] or TEXT_COLORS.white
    for i, e in ipairs(entries) do
        local s = Seg(i)
        s:SetSize(w, l.height - 2)
        s:ClearAllPoints()
        if i == 1 then
            s:SetPoint("LEFT", inner, "LEFT", hw, 0)
        else
            s:SetPoint("LEFT", segs[i - 1]:GetStatusBarTexture(), "RIGHT", 0, 0)
        end
        s:SetMinMaxValues(0, total)
        s:SetValue(e.amount)
        local c = e.color
        s:SetStatusBarColor(c[1], c[2], c[3])
        if l.fill == "smooth" then
            -- darker at the bottom, lighter at the top, across the bar's height
            local t = s:GetStatusBarTexture()
            if CreateColor then
                pcall(t.SetGradient, t, "VERTICAL", CreateColor(c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 1),
                    CreateColor(math.min(c[1] * 1.1 + 0.12, 1), math.min(c[2] * 1.1 + 0.12, 1), math.min(c[3] * 1.1 + 0.12, 1), 1))
            end
        end
        -- a label only where the piece is wide enough to read it
        if withText and l.labels and e.label and e.pct and e.pct * w / 100 >= l.labelSize * 3.5 then
            ApplyFont(s.text, l, l.labelSize)
            s.text:SetTextColor(tc[1], tc[2], tc[3])
            s.text:SetText(e.label)
            s.text:Show()
        else
            s.text:Hide()
        end
        s:Show()
    end
    for i = #entries + 1, #segs do segs[i]:Hide() end
end

local shown -- what's on the bar, for the tooltip (plain mode only)

local function DrawPlain(totals)
    local entries, total = {}, 0
    for key, amount in pairs(totals) do
        entries[#entries + 1] = { key = key, amount = amount }
        total = total + amount
    end
    table.sort(entries, function(a, b) return a.amount > b.amount end)
    local l = Look()
    local function LabelFor(e)
        local pct = math.floor(e.pct + 0.5) .. "%"
        local f = l.labelFormat
        if f == "name" then return e.name
        elseif f == "pct" then return pct
        elseif f == "amount" then return HitShort(e.amount)
        elseif f == "nameamount" then return e.name .. " " .. HitShort(e.amount) end
        return e.name .. " " .. pct
    end
    for _, e in ipairs(entries) do
        e.color = ColorFor(e.key)
        e.name = SpellName(e.key)
        e.pct = total > 0 and e.amount / total * 100 or 0
        e.label = LabelFor(e)
    end
    shown = { entries = entries, total = total } -- the tooltip keeps every ability
    -- "Max Abilities": the smallest ones share one grey "Other" piece
    local drawn = entries
    local maxN = l.maxAbilities or 8
    if #entries > maxN then
        drawn = {}
        local other = { name = "Other", amount = 0, color = { 0.45, 0.45, 0.45 } }
        for i, e in ipairs(entries) do
            if i < maxN then drawn[#drawn + 1] = e else other.amount = other.amount + e.amount end
        end
        other.pct = total > 0 and other.amount / total * 100 or 0
        other.label = LabelFor(other)
        drawn[#drawn + 1] = other
    end
    if total > 0 then
        emptyText:SetText("")
        Draw(drawn, total, true)
    else
        Draw({}, 1, false)
        emptyText:SetText(inCombat and "Updates after this fight" or "No damage yet")
    end
    return total > 0
end

-- this fight only, straight from hidden numbers
local function DrawHidden(list, total)
    local entries = {}
    for i, e in ipairs(list) do
        entries[#entries + 1] = { amount = e.amount, color = e.key and ColorFor(e.key) or PALETTE[(i - 1) % #PALETTE + 1] }
    end
    shown = nil
    emptyText:SetText("")
    local ok, err = pcall(Draw, entries, total, false)
    if not ok then
        Note("hidden draw failed: " .. tostring(err))
        return false
    end
    return true
end

local function UpdateVisibility(hasData)
    local l = Look()
    bar:SetScale(l.scale or 1)
    bar:SetSize(l.width, l.height)
    edge:SetShown(l.border ~= false)
    back:SetColorTexture(0.08, 0.08, 0.1, l.bgAlpha or 0.75)
    if LEM:IsInEditMode() then bar:Show() return end -- always there to place
    local hide = false
    if l.showWhen == "combat" and not inCombat then hide = true end
    if l.showWhen == "nocombat" and inCombat then hide = true end
    -- Hide When Empty only hides it between fights
    if l.hideEmpty and not hasData and not inCombat then hide = true end
    bar:SetShown(not hide)
end

local function Refresh()
    if not DB then return end
    UpdateHitBox()
    if Expired() then
        wipe(DB.acc)
        DebugAdd("reset after " .. (DB.resetMinutes or RESET_DEFAULT) .. " min out of combat")
    end
    if not meter then
        Draw({}, 1, false)
        emptyText:SetText("No damage meter on this client")
        UpdateVisibility(false)
        return
    end
    local hasData
    if inCombat then
        local live, status, liveTotal = SafeRead(nil)
        local plain = live and AllPlain(live)
        Note("live: " .. tostring(status) .. " n=" .. (live and #live or 0) .. " plain=" .. tostring(plain)
            .. " total=" .. (isSecret(liveTotal) and "secret" or tostring(liveTotal)))
        if live and plain then
            -- if the meter is carrying on a session already partly counted,
            -- only add what's new in it
            local ids = SessionIDs()
            local base = DB.counted and ids[#ids] and DB.counted[ids[#ids]] or {}
            local merged = CopyTable(DB.acc)
            for _, e in ipairs(live) do
                local d = e.amount - (base[e.key] or 0)
                if d > 0 then merged[e.key] = (merged[e.key] or 0) + d end
            end
            hasData = DrawPlain(merged)
        elseif live and #live > 0 and (isSecret(liveTotal) or liveTotal ~= nil) and DrawHidden(live, liveTotal) then
            hasData = true
        else
            hasData = DrawPlain(DB.acc)
        end
    else
        hasData = DrawPlain(DB.acc)
    end
    UpdateVisibility(hasData)
end

-- After a fight: add what's new in the meter's sessions. Only sessions this
-- addon watched count: ones that started during your fight (newer than any
-- the meter had when the fight began), or one it has counted before that
-- carried on into this fight (only its growth is added; DB.counted keeps
-- what was already taken from it). Older stored fights are never counted.
-- The meter can take a moment to open its numbers, so it retries a few
-- times, then gives up on a session that never opens.
local TRIES = 8
-- The meter creates a fight's session the moment combat starts, before the
-- PLAYER_REGEN_DISABLED event, so "newest session at combat start" would
-- already be this fight. Instead the newest session is noted while out of
-- combat (outFloor, every few seconds and at login), and a fight counts
-- sessions newer than that.
local fightFloor -- outFloor when the current/last fight began
local outFloor   -- newest session id seen while out of combat

local function NoteOutFloor()
    if inCombat then return end
    local ids = SessionIDs()
    if ids[#ids] then outFloor = math.max(outFloor or -1, ids[#ids]) end
end

local function Watched(id)
    if DB.counted[id] then return true end
    return fightFloor ~= nil and id > fightFloor
end

local function Collect(tries)
    tries = tries or 0
    local waiting = false
    DB.counted = DB.counted or {}
    for _, id in ipairs(SessionIDs()) do
        if Watched(id) and not (DB.skipped and DB.skipped[id]) then
            local list, status = SafeRead(id)
            if list and AllPlain(list) then
                local now = {}
                for _, e in ipairs(list) do now[e.key] = (now[e.key] or 0) + e.amount end
                -- the record: the most one ability did in one fight
                for key, amount in pairs(now) do NoteBest(amount, key) end
                local prev = DB.counted[id] or {}
                local added = 0
                for key, amount in pairs(now) do
                    local d = amount - (prev[key] or 0)
                    if d > 0 then
                        DB.acc[key] = (DB.acc[key] or 0) + d
                        added = added + d
                    end
                end
                DB.counted = { [id] = now } -- only the latest can still grow
                if added > 0 then DebugAdd("counted session " .. id .. ": +" .. math.floor(added)) end
            elseif tries >= TRIES then
                DebugAdd("gave up on session " .. id .. ": " .. tostring(status))
                DB.skipped = DB.skipped or {}
                DB.skipped[id] = true
            else
                Note("session " .. id .. " not readable yet: " .. tostring(status))
                waiting = true
                break
            end
        end
    end
    if waiting then
        C_Timer.After(1.5, function() Collect(tries + 1) end)
    end
    Refresh()
end

---------------------------------------------------------------------------
-- Tooltip (between fights)
---------------------------------------------------------------------------
local function Short(n)
    if n >= 1e6 then return string.format("%.1fm", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
    return tostring(math.floor(n + 0.5))
end

bar:SetScript("OnEnter", function(self)
    -- "Tooltip": the game's usual spot, just above the bar, or none
    local mode = DB and Look().tooltip or "default"
    if mode == "off" then return end
    if mode == "bar" or not GameTooltip_SetDefaultAnchor then
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
    else
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    end
    GameTooltip:AddLine("Damage Bar")
    local today, ever = BestToday(), DB and DB.bestEver
    local function BestLine(label, b)
        if not b then
            GameTooltip:AddDoubleLine(label, "none yet", 1, 0.82, 0, 0.6, 0.6, 0.6)
            return
        end
        local what = Short(b.amount) .. (b.spell and ("  " .. b.spell) or "")
        if label == "Best ability, ever" and b.when then what = what .. "  (" .. b.when .. ")" end
        GameTooltip:AddDoubleLine(label, what, 1, 0.82, 0, 1, 1, 1)
    end
    if DB and DB.hitEver then
        -- single hits come through: the biggest ones and each ability's high score
        local function HitLine(label, h)
            if not h then
                GameTooltip:AddDoubleLine(label, "none yet", 1, 0.82, 0, 0.6, 0.6, 0.6)
                return
            end
            GameTooltip:AddDoubleLine(label, Short(h.amount) .. "  " .. (h.spell or ""), 1, 0.82, 0, 1, 1, 1)
        end
        HitLine("Biggest hit today", HitToday())
        HitLine("Biggest hit ever", DB.hitEver)
        local scores = {}
        for spell, s in pairs(DB.hitScores or {}) do scores[#scores + 1] = { spell = spell, s = s } end
        table.sort(scores, function(a, b) return a.s.amount > b.s.amount end)
        if #scores > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("High scores", 1, 0.82, 0)
            for i = 1, math.min(#scores, 8) do
                local x = scores[i]
                GameTooltip:AddDoubleLine("   " .. x.spell, Short(x.s.amount) .. "  (" .. x.s.when .. ")",
                    1, 1, 1, 1, 1, 1)
            end
        end
    else
        BestLine("Best ability in one fight, today", today)
        BestLine("Best ability, ever", ever)
    end
    GameTooltip:AddLine(" ")
    if shown and shown.total > 0 then
        for _, e in ipairs(shown.entries) do
            local c = e.color
            GameTooltip:AddDoubleLine(e.name, Short(e.amount) .. "  " .. string.format("%.1f%%", e.pct),
                c[1], c[2], c[3], 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("Total", Short(shown.total), 1, 0.82, 0, 1, 1, 1)
    elseif inCombat then
        GameTooltip:AddLine("Names and numbers show after the fight.", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine("No damage yet.", 0.7, 0.7, 0.7)
    end
    local mode = ResetMode()
    if mode == "timer" and DB.lastCombatEnd and not inCombat and next(DB.acc) then
        local left = math.max(math.floor(ResetSeconds() - (time() - DB.lastCombatEnd)), 0)
        GameTooltip:AddLine(string.format("Resets in %d:%02d", math.floor(left / 60), left % 60), 0.6, 0.6, 0.6)
    elseif mode ~= "timer" then
        local when = { never = "Never resets by itself", fight = "Resets when the next fight starts",
            zone = "Resets when you change zone", login = "Resets at your next login" }
        GameTooltip:AddLine(when[mode] or "", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Right-click to reset", 0.5, 0.8, 1)
    GameTooltip:Show()
end)
bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
bar:EnableMouse(true)

local function ResetNow()
    wipe(DB.acc)
    -- whatever the meter has finished is "before"; the next fight starts fresh
    NoteOutFloor()
    if not inCombat then fightFloor = outFloor end
    DB.counted = {}
    print("|cffc79c6eDamage Bar|r cleared.")
    GameTooltip:Hide()
    Refresh()
end

bar:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and DB then ResetNow() end
end)

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------
local default = { point = "CENTER", x = 0, y = -180 }

local function Place()
    local l = Look()
    bar:ClearAllPoints()
    if l.point then
        bar:SetPoint(l.point, UIParent, l.point, l.x, l.y)
    else
        bar:SetPoint(default.point, UIParent, default.point, default.x, default.y)
    end
end

LEM:AddFrame(bar, function(_, layout, point, x, y)
    layoutName = layout
    local l = Look()
    l.point, l.x, l.y = point, x, y
end, default)

local function Setting(kind, name, key, extra)
    local s = {
        kind = kind,
        name = name,
        default = LAYOUT_DEFAULTS[key],
        get = function(layout) layoutName = layout; return Look()[key] end,
        set = function(layout, value) layoutName = layout; Look()[key] = value; Refresh() end,
    }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

LEM:AddFrameSettings(bar, {
    Setting(LEM.SettingType.Slider, "Scale", "scale", {
        minValue = 0.5, maxValue = 2, valueStep = 0.05,
        formatter = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
    }),
    Setting(LEM.SettingType.Slider, "Width", "width", { minValue = 60, maxValue = 1200, valueStep = 1 }),
    Setting(LEM.SettingType.Slider, "Height", "height", { minValue = 6, maxValue = 150, valueStep = 1 }),
    Setting(LEM.SettingType.Dropdown, "Fill Style", "fill", { values = {
        { text = "Flat", value = "flat" }, { text = "Smooth gradient", value = "smooth" },
    } }),
    Setting(LEM.SettingType.Slider, "Background Opacity", "bgAlpha", {
        minValue = 0, maxValue = 1, valueStep = 0.05,
        formatter = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
    }),
    Setting(LEM.SettingType.Checkbox, "Border", "border"),
    Setting(LEM.SettingType.Slider, "Max Abilities", "maxAbilities", { minValue = 2, maxValue = 20, valueStep = 1 }),
    Setting(LEM.SettingType.Checkbox, "Show Labels", "labels"),
    Setting(LEM.SettingType.Dropdown, "Label Text", "labelFormat", { values = {
        { text = "Name and %", value = "namepct" }, { text = "Name", value = "name" },
        { text = "%", value = "pct" }, { text = "Damage", value = "amount" },
        { text = "Name and damage", value = "nameamount" },
    } }),
    Setting(LEM.SettingType.Dropdown, "Font", "font", { values = FontChoices, height = 300 }),
    Setting(LEM.SettingType.Slider, "Text Size", "labelSize", { minValue = 6, maxValue = 30, valueStep = 1 }),
    Setting(LEM.SettingType.Dropdown, "Font Outline", "outline", { values = {
        { text = "None", value = "" }, { text = "Outline", value = "OUTLINE" },
        { text = "Thick Outline", value = "THICKOUTLINE" },
    } }),
    Setting(LEM.SettingType.Dropdown, "Text Color", "textColor", { values = {
        { text = "White", value = "white" }, { text = "Gold", value = "gold" },
    } }),
    Setting(LEM.SettingType.Dropdown, "Show", "showWhen", { values = {
        { text = "Always", value = "always" }, { text = "Only in combat", value = "combat" },
        { text = "Only out of combat", value = "nocombat" },
    } }),
    Setting(LEM.SettingType.Dropdown, "Tooltip", "tooltip", { values = {
        { text = "Default tooltip spot", value = "default" }, { text = "Above the bar", value = "bar" },
        { text = "Off", value = "off" },
    } }),
    Setting(LEM.SettingType.Checkbox, "Hide When Empty", "hideEmpty"),
    Setting(LEM.SettingType.Checkbox, "Best-in-a-Fight Section", "hitSection", {
        set = function(layout, value)
            layoutName = layout
            Look().hitSection = value
            Refresh()
            pcall(LEM.RefreshFrameSettings, LEM, bar) -- greys the width slider in and out
        end,
    }),
    Setting(LEM.SettingType.Slider, "Best-in-a-Fight Width %", "hitPct", {
        minValue = 5, maxValue = 30, valueStep = 1,
        formatter = function(v) return math.floor(v + 0.5) .. "%" end,
        disabled = function() return not (DB and Look().hitSection) end,
    }),
    {
        kind = LEM.SettingType.Dropdown,
        name = "Reset",
        default = "timer",
        values = RESET_MODES,
        get = function() return ResetMode() end,
        set = function(_, value)
            if DB then DB.resetMode = value end
            Refresh()
            pcall(LEM.RefreshFrameSettings, LEM, bar) -- greys the minutes slider in and out
        end,
    },
    {
        kind = LEM.SettingType.Slider,
        name = "Reset After (min)",
        default = RESET_DEFAULT,
        minValue = 1, maxValue = 60, valueStep = 1,
        get = function() return DB and DB.resetMinutes or RESET_DEFAULT end,
        set = function(_, value) if DB then DB.resetMinutes = value end; Refresh() end,
        disabled = function() return ResetMode() ~= "timer" end,
    },
})

LEM:RegisterCallback("layout", function(layout)
    layoutName = layout
    Place()
    Refresh()
end)
LEM:RegisterCallback("enter", Refresh)
LEM:RegisterCallback("exit", Refresh)

SLASH_DAMAGEBAR1 = "/dbar"
SlashCmdList.DAMAGEBAR = function(msg)
    if (msg or ""):lower():match("reset") then
        ResetNow()
    else
        print("|cffc79c6eDamage Bar|r right-click the bar or /dbar reset to clear it. Move and size it in Edit Mode.")
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- its own frame, so it keeps running while the bar is hidden (Hide When Empty)
local driver = CreateFrame("Frame")
local ticker = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    ticker = ticker + elapsed
    local every = inCombat and 0.5 or 5
    if ticker >= every then
        ticker = 0
        NoteOutFloor()
        Refresh()
    end
end)

bar:RegisterEvent("ADDON_LOADED")
bar:RegisterEvent("PLAYER_ENTERING_WORLD")
bar:RegisterEvent("PLAYER_REGEN_DISABLED")
bar:RegisterEvent("PLAYER_REGEN_ENABLED")
bar:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pcall(bar.RegisterUnitEvent, bar, "UNIT_COMBAT", "target")
pcall(bar.RegisterUnitEvent, bar, "UNIT_SPELLCAST_SUCCEEDED", "player")
local hitKinds = {} -- what kinds of hit amounts the log has noted
bar:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- arg3: the spell's id
        if Num(arg3) then lastCast = { name = SpellName(arg3), at = GetTime() } end
        return
    end
    if event == "UNIT_COMBAT" then
        -- arg2: what happened (WOUND = took damage), arg4: how much
        if not DB or isSecret(arg2) or arg2 ~= "WOUND" then return end
        local kind = Num(arg4) and "plain" or (isSecret(arg4) and "secret" or type(arg4))
        if not hitKinds[kind] then
            hitKinds[kind] = true
            DebugAdd("target hit amount: " .. kind)
        end
        if kind == "plain" and arg4 > 0 and not IsInGroup() then
            local spell = (lastCast and GetTime() - lastCast.at < 0.6) and lastCast.name or "Auto Attack"
            NoteHit(arg4, spell)
            UpdateHitBox()
        end
        return
    end
    if event == "ZONE_CHANGED_NEW_AREA" then
        if DB and ResetMode() == "zone" then AutoReset("zone change"); Refresh() end
        return
    end
    if event == "ADDON_LOADED" then
        if arg1 ~= "DamageBar" then return end
        DamageBarDB = DamageBarDB or {}
        DB = DamageBarDB
        DB.acc = DB.acc or {}
        if (DB.version or 1) < 2 then
            -- 1.0 could count old fights stored in the meter: start clean
            wipe(DB.acc)
            DB.counted, DB.lastSession = {}, nil
            DB.version = 2
        end
        if not DEBUG_LOG then DB.debug = nil else DebugAdd("---- loaded, meter=" .. tostring(meter ~= nil)) end
        bar:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin = arg1
        if isInitialLogin then
            DB.counted = {} -- session ids may start over after a restart
            DB.skipped = {}
            if ResetMode() == "login" then AutoReset("new login") end
        end
        inCombat = InCombatLockdown()
        NoteOutFloor() -- stored fights that load later are caught by the tick
        Place()
        Refresh()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if Expired() then wipe(DB.acc) end
        if ResetMode() == "fight" then AutoReset("new fight") end
        fightFloor = outFloor or -1 -- see NoteOutFloor
        inCombat = true
        DebugAdd("fight starts, counting sessions after " .. tostring(fightFloor))
        Refresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        DB.lastCombatEnd = time()
        C_Timer.After(1.5, function() Collect(0) end)
    end
end)
