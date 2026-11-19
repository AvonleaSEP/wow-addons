-- Spliffbars: the Leveling Journal.
-- Every level you finish is kept (XP.lua files it at the ding): how long it
-- took, where its XP came from (quests, kills, discoveries), your pace
-- through each tenth of it, every death and close call, the quests and mobs
-- that gave the most, and the zones you earned it in.
--
-- Open it by clicking the XP bar, or /spliffbars journal (or /lj).
--
--   Overview   every level side by side: a chart of time per level (each bar
--              coloured by where that level's XP came from, skulls for
--              deaths), records, and a table of the numbers.
--   A level    one level in full.
--
-- The journal starts from the level you were on when it was added; levels
-- before that weren't kept.

local _, ns = ...

local GOLD  = { 1, 0.82, 0 }
local DIM   = { 0.62, 0.62, 0.68 }
local WHITE = { 1, 1, 1 }
local COLORS = {
    quest = { 1, 0.82, 0 },
    kill  = { 0.95, 0.25, 0.25 },
    found = { 1, 0.45, 0.8 },
    other = { 0.5, 0.5, 0.56 },
    rested = { 0.35, 0.6, 1 },
    good  = { 0.3, 1, 0.3 },
    death = { 1, 0.35, 0.35 },
    close = { 1, 0.6, 0.3 },
    pace  = { 0.6, 0.7, 1 },
}
local SOURCES = { -- bottom to top in the chart, left to right in the bars
    { key = "kill",  field = "killXP",  label = "Kills" },
    { key = "quest", field = "questXP", label = "Quests" },
    { key = "found", field = "foundXP", label = "Discovery" },
    { key = "other", field = "otherXP", label = "Other" },
}
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local CROSS = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7"

local W, H = 880, 580
local PAD = 14
local LIST_W = 160
local TOP = 44                                  -- below the title strip
local BODY_W = W - LIST_W - PAD * 3 - 10        -- room for the scroll thumb

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
local Num, Big = ns.Num, ns.Big

local function Time(s)
    if not s then return "?" end
    return ns.xpJournal.FormatTime(s)
end

local function Pct(x, total)
    if not total or total <= 0 then return 0 end
    return math.floor(x / total * 100 + 0.5)
end

local function Sum(list, field)
    local t = 0
    for _, e in ipairs(list or {}) do t = t + (e[field] or 0) end
    return t
end

-- One level's log, boiled down. live = the level you're on now (played and
-- info come from the XP bar then).
local function Summarize(q, played, info)
    local s = { level = q.level, q = q, live = info ~= nil }
    s.max = (info and info.max) or q.max
    s.gained = (info and info.cur) or q.max
    s.played = played or q.played

    s.questN = q.qn or #(q.list or {})
    s.questXP = q.qxp or Sum(q.list, "xp")
    s.killN, s.killXP, s.mobs = 0, 0, {}
    for mob, k in pairs(q.kills or {}) do
        s.killN, s.killXP = s.killN + (k.n or 0), s.killXP + (k.xp or 0)
        s.mobs[#s.mobs + 1] = { name = mob, n = k.n or 0, xp = k.xp or 0 }
    end
    table.sort(s.mobs, function(a, b) return a.xp > b.xp end)
    s.foundN, s.foundXP = #(q.found or {}), Sum(q.found, "xp")

    local known = s.questXP + s.killXP + s.foundXP
    if not s.gained or s.gained <= 0 then s.gained = known end
    -- the quest that dings you shows at the start of the next level, so the
    -- known XP can run past the bar: shares are of whichever is bigger
    s.otherXP = math.max(0, s.gained - known)
    s.total = math.max(1, known + s.otherXP)
    s.restedXP = q.restedXP or 0

    s.deaths, s.closes, s.killers = 0, 0, {}
    for _, e in ipairs(q.events or {}) do
        if e.kind == "death" then
            s.deaths = s.deaths + 1
            if e.by then s.killers[#s.killers + 1] = e.by end
        else
            s.closes = s.closes + 1
            if e.left and (not s.lowest or e.left < s.lowest) then s.lowest = e.left end
        end
    end
    s.rate = (s.played and s.played > 60 and s.gained > 0) and (s.gained / s.played * 3600) or nil

    s.quests = {}
    for _, e in ipairs(q.list or {}) do s.quests[#s.quests + 1] = e end
    table.sort(s.quests, function(a, b) return (a.xp or 0) > (b.xp or 0) end)
    s.zones = {}
    for z, xp in pairs(q.zones or {}) do s.zones[#s.zones + 1] = { name = z, xp = xp } end
    table.sort(s.zones, function(a, b) return a.xp > b.xp end)
    return s
end

-- every level in the journal, newest first
local function Levels()
    local J = ns.xpJournal
    if not J then return {} end
    local out = {}
    local q, played, info = J.Current()
    for lvl, log in pairs(J.History()) do
        if Num(lvl) and not (q and q.level == lvl) then out[#out + 1] = Summarize(log) end
    end
    if q and Num(q.level) and (info or #(q.list or {}) > 0 or next(q.kills or {})) then
        out[#out + 1] = Summarize(q, played, info)
    end
    table.sort(out, function(a, b) return a.level > b.level end)
    return out
end

---------------------------------------------------------------------------
-- Building blocks: text, flat textures and buttons, pooled per pane so each
-- redraw reuses them
---------------------------------------------------------------------------
local function NewText(parent, size, c)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns.FontPath(nil), size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    if c then fs:SetTextColor(c[1], c[2], c[3]) end
    fs:SetJustifyH("LEFT")
    return fs
end

local Pool = {}
Pool.__index = Pool

local function NewPool(parent)
    return setmetatable({ parent = parent, fs = {}, tex = {}, btn = {}, nfs = 0, ntex = 0, nbtn = 0 }, Pool)
end

function Pool:Reset()
    for _, x in ipairs(self.fs) do x:Hide() end
    for _, x in ipairs(self.tex) do x:Hide() end
    for _, b in ipairs(self.btn) do
        b:Hide()
        b:SetScript("OnClick", nil)
        b:SetScript("OnEnter", nil)
        b.sel:Hide()
    end
    self.nfs, self.ntex, self.nbtn = 0, 0, 0
end

function Pool:Text(size, c, justify)
    self.nfs = self.nfs + 1
    local fs = self.fs[self.nfs]
    if not fs then
        fs = NewText(self.parent, size, c)
        self.fs[self.nfs] = fs
    end
    fs:SetFont(ns.FontPath(nil), size, "")
    c = c or WHITE
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    fs:SetWidth(0)
    fs:ClearAllPoints()
    fs:Show()
    return fs
end

-- a flat colour (r, g, b, a) or a picture (a path)
function Pool:Tex(r, g, b, a)
    self.ntex = self.ntex + 1
    local t = self.tex[self.ntex]
    if not t then
        t = self.parent:CreateTexture(nil, "ARTWORK")
        self.tex[self.ntex] = t
    end
    t:SetTexCoord(0, 1, 0, 1)
    if type(r) == "string" then
        t:SetTexture(r)
        t:SetVertexColor(1, 1, 1, 1)
    else
        t:SetColorTexture(r, g, b, a or 1)
    end
    t:ClearAllPoints()
    t:Show()
    return t
end

function Pool:Button()
    self.nbtn = self.nbtn + 1
    local b = self.btn[self.nbtn]
    if not b then
        b = CreateFrame("Button", nil, self.parent)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.07)
        b.sel = b:CreateTexture(nil, "BACKGROUND")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(1, 0.82, 0, 0.14)
        b.sel:Hide()
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- the wheel still scrolls the pane when the mouse is over a button
        local sf = self.scroller
        if sf then
            b:EnableMouseWheel(true)
            b:SetScript("OnMouseWheel", function(_, delta) sf:GetScript("OnMouseWheel")(sf, delta) end)
        end
        self.btn[self.nbtn] = b
    end
    b:SetFrameLevel(self.parent:GetFrameLevel() + 3)
    b:ClearAllPoints()
    b:Show()
    return b
end

-- A pane that scrolls with the mouse wheel, with a thin thumb showing where
-- you are.
local function Scroller(parent, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetSize(w, h)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(w - 10, 1)
    sf:SetScrollChild(child)
    sf.child = child

    local thumb = sf:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 1, 1, 0.2)
    thumb:SetWidth(3)
    local function Thumb()
        local ch = child:GetHeight()
        if ch <= h + 1 then thumb:Hide() return end
        local th = math.max(24, h * h / ch)
        local pos = sf:GetVerticalScroll() / (ch - h)
        thumb:ClearAllPoints()
        thumb:SetHeight(th)
        thumb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, -(h - th) * pos)
        thumb:Show()
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local most = math.max(0, child:GetHeight() - h)
        self:SetVerticalScroll(math.min(most, math.max(0, self:GetVerticalScroll() - delta * 50)))
        Thumb()
    end)
    function sf:SetContentHeight(ch, keepScroll)
        child:SetHeight(math.max(1, ch))
        local most = math.max(0, ch - h)
        self:SetVerticalScroll(keepScroll and math.min(self:GetVerticalScroll(), most) or 0)
        Thumb()
    end
    return sf
end

---------------------------------------------------------------------------
-- Pieces of a page. Each takes the pool and the y to start at (0 at the
-- top, going down), and returns the y below it.
---------------------------------------------------------------------------
local function Heading(P, y, text, note)
    local h = P:Text(14, GOLD)
    h:SetPoint("TOPLEFT", 0, y)
    h:SetText(text)
    if note then
        local n = P:Text(10, DIM)
        n:SetPoint("BOTTOMLEFT", h, "BOTTOMRIGHT", 8, 1)
        n:SetText(note)
    end
    local line = P:Tex(1, 0.82, 0, 0.22)
    line:SetPoint("TOPLEFT", 0, y - 20)
    line:SetSize(BODY_W, 1)
    return y - 30
end

local function Note(P, y, text, c)
    local n = P:Text(11, c or DIM)
    n:SetPoint("TOPLEFT", 0, y)
    n:SetText(text)
    return y - 18
end

-- a row of number tiles: { value, label, colour }
local function Tiles(P, y, tiles)
    local gap = 8
    local tw = (BODY_W - gap * (#tiles - 1)) / #tiles
    for i, t in ipairs(tiles) do
        local x = (i - 1) * (tw + gap)
        local bg = P:Tex(1, 1, 1, 0.045)
        bg:SetPoint("TOPLEFT", x, y)
        bg:SetSize(tw, 54)
        local accent = P:Tex((t[3] or WHITE)[1], (t[3] or WHITE)[2], (t[3] or WHITE)[3], 0.7)
        accent:SetPoint("TOPLEFT", x, y)
        accent:SetSize(2, 54)
        local v = P:Text(19, t[3] or WHITE)
        v:SetPoint("TOPLEFT", x + 10, y - 8)
        v:SetWidth(tw - 16)
        v:SetText(t[1])
        local l = P:Text(10, DIM)
        l:SetPoint("TOPLEFT", x + 10, y - 35)
        l:SetWidth(tw - 16)
        l:SetText(t[2])
    end
    return y - 54 - 16
end

-- where the XP came from: one bar split by source, a legend under it
local function SourceBar(P, y, s)
    local h = 16
    local back = P:Tex(1, 1, 1, 0.05)
    back:SetPoint("TOPLEFT", 0, y)
    back:SetSize(BODY_W, h)
    local x = 0
    for _, src in ipairs(SOURCES) do
        local v = s[src.field]
        if v > 0 then
            local c = COLORS[src.key]
            local pw = BODY_W * v / s.total
            local t = P:Tex(c[1], c[2], c[3], 0.85)
            t:SetPoint("TOPLEFT", x, y)
            t:SetSize(math.max(1, pw), h)
            x = x + pw
        end
    end
    y = y - h - 8
    local lx = 0
    for _, src in ipairs(SOURCES) do
        local v = s[src.field]
        if v > 0 then
            local c = COLORS[src.key]
            local sw = P:Tex(c[1], c[2], c[3], 1)
            sw:SetPoint("TOPLEFT", lx, y - 2)
            sw:SetSize(9, 9)
            local t = P:Text(11, c)
            t:SetPoint("TOPLEFT", lx + 13, y)
            t:SetText(("%s %d%%  |cffbbbbbb+%s|r"):format(src.label, Pct(v, s.total), Big(v)))
            lx = lx + 13 + t:GetStringWidth() + 18
        end
    end
    return y - 20
end

-- a titled list in a column: rows = { left, right, colour }
local function ColumnList(P, x, y, w, title, rows, empty)
    local h = P:Text(12, GOLD)
    h:SetPoint("TOPLEFT", x, y)
    h:SetText(title)
    local line = P:Tex(1, 0.82, 0, 0.18)
    line:SetPoint("TOPLEFT", x, y - 17)
    line:SetSize(w, 1)
    y = y - 24
    if #rows == 0 then
        local e = P:Text(11, DIM)
        e:SetPoint("TOPLEFT", x, y)
        e:SetText(empty or "None")
        return y - 17
    end
    for _, r in ipairs(rows) do
        local c = r[3] or { 0.9, 0.9, 0.9 }
        local a = P:Text(11, c)
        a:SetPoint("TOPLEFT", x, y)
        a:SetWidth(w - 76)
        a:SetText(r[1])
        local b = P:Text(11, c, "RIGHT")
        b:SetPoint("TOPRIGHT", P.parent, "TOPLEFT", x + w, y)
        b:SetText(r[2])
        y = y - 16
    end
    return y
end

local function Columns(P, y, left, right)
    local cw = (BODY_W - 24) / 2
    local yl = ColumnList(P, 0, y, cw, left[1], left[2], left[3])
    local yr = ColumnList(P, cw + 24, y, cw, right[1], right[2], right[3])
    return math.min(yl, yr) - 14
end

---------------------------------------------------------------------------
-- One level
---------------------------------------------------------------------------
-- the time spent on each tenth of the level, from the 10% marks
local function PaceSteps(s)
    local marks = s.q.marks or {}
    local at = { [0] = 0 }
    for i = 1, 9 do at[i] = marks[i * 10] end
    if not s.live then at[10] = s.played end
    local steps = {}
    for i = 1, 10 do
        if at[i - 1] and at[i] and at[i] >= at[i - 1] then steps[i] = at[i] - at[i - 1] end
    end
    return steps
end

local function Pace(P, y, s)
    local steps = PaceSteps(s)
    local most, least, fastest, slowest = 0, nil, nil, nil
    for i = 1, 10 do
        local d = steps[i]
        if d then
            if d > most then most, slowest = d, i end
            if not least or d < least then least, fastest = d, i end
        end
    end
    if most <= 0 then
        return Note(P, y, s.live and "Shows each tenth as you pass it (the addon needs your /played time, asked at login)."
            or "No pace for this level: it was under way before the journal started.")
    end
    local gap, barH = 6, 56
    local cw = (BODY_W - gap * 9) / 10
    for i = 1, 10 do
        local x = (i - 1) * (cw + gap)
        local back = P:Tex(1, 1, 1, 0.04)
        back:SetPoint("TOPLEFT", x, y - 14)
        back:SetSize(cw, barH)
        local d = steps[i]
        local label = P:Text(10, DIM, "CENTER")
        label:SetPoint("TOP", P.parent, "TOPLEFT", x + cw / 2, y - 14 - barH - 4)
        label:SetText(((i - 1) * 10) .. "-" .. (i * 10) .. "%")
        if d then
            local c = (i == slowest and COLORS.kill) or (i == fastest and COLORS.good) or COLORS.pace
            local bh = math.max(2, barH * d / most)
            local bar = P:Tex(c[1], c[2], c[3], 0.75)
            bar:SetPoint("BOTTOMLEFT", P.parent, "TOPLEFT", x, y - 14 - barH)
            bar:SetSize(cw, bh)
            local t = P:Text(10, c, "CENTER")
            t:SetPoint("BOTTOM", P.parent, "TOPLEFT", x + cw / 2, y - 14 - barH + bh + 2)
            t:SetText(Time(d))
        end
    end
    y = y - 14 - barH - 20
    if slowest and fastest and slowest ~= fastest then
        y = Note(P, y, ("Slowest stretch %d-%d%% (%s), fastest %d-%d%% (%s)."):format(
            (slowest - 1) * 10, slowest * 10, Time(most), (fastest - 1) * 10, fastest * 10, Time(least)))
    end
    return y - 6
end

local function Events(P, y, s)
    local events = s.q.events or {}
    if #events == 0 then return Note(P, y, "No deaths, no close calls. A clean level.", COLORS.good) end
    for _, e in ipairs(events) do
        local death = e.kind == "death"
        local icon = P:Tex(death and SKULL or CROSS)
        icon:SetPoint("TOPLEFT", 0, y + 1)
        icon:SetSize(14, 14)
        local at = s.max and s.max > 0 and Pct(math.min(e.e or 0, s.max), s.max) or nil
        local what = death and ("Died" .. (e.by and (" to " .. e.by) or ""))
            or ("Close call" .. (e.left and (": ~" .. e.left .. "% HP left") or ""))
        local c = death and COLORS.death or COLORS.close
        local t = P:Text(11, c)
        t:SetPoint("TOPLEFT", 20, y)
        t:SetText(what)
        local where = {}
        if at then where[#where + 1] = at .. "% through" end
        if e.zone then where[#where + 1] = e.zone end
        if e.t then where[#where + 1] = date("%d %b %H:%M", e.t) elseif e.when then where[#where + 1] = e.when end
        local w = P:Text(11, DIM)
        w:SetPoint("TOPLEFT", 280, y)
        w:SetText(table.concat(where, ",  "))
        y = y - 18
    end
    return y - 4
end

local function LevelPage(P, s)
    local y = 0
    local title = P:Text(26, WHITE)
    title:SetPoint("TOPLEFT", 0, y)
    title:SetText("Level " .. s.level)
    local sub = P:Text(11, DIM)
    sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 12, 3)
    if s.live then
        sub:SetText(("|cff4dff4dIn progress|r, %d%% through%s"):format(Pct(s.gained, s.max or s.gained),
            s.played and (", " .. Time(s.played) .. " so far") or ""))
    else
        local parts = {}
        if s.q.started then parts[#parts + 1] = "Started " .. date("%d %b %Y", s.q.started) end
        if s.q.finished then parts[#parts + 1] = "dinged " .. date("%d %b %Y, %H:%M", s.q.finished) end
        sub:SetText(table.concat(parts, ", "))
    end
    y = y - 44

    y = Tiles(P, y, {
        { Time(s.played), s.live and "Time so far" or "Time played", COLORS.good },
        { s.rate and Big(s.rate) or "?", "XP per hour", COLORS.pace },
        { Big(s.questN), "Quests handed in", COLORS.quest },
        { Big(s.killN), "Kills", COLORS.kill },
        { tostring(s.deaths), "Deaths", s.deaths > 0 and COLORS.death or DIM },
        { tostring(s.closes), s.lowest and ("Close calls (low ~" .. s.lowest .. "%)") or "Close calls",
            s.closes > 0 and COLORS.close or DIM },
    })

    y = Heading(P, y, "Where the XP came from", s.max and (Big(s.gained) .. " of " .. Big(s.max) .. " XP") or nil)
    y = SourceBar(P, y, s)
    if s.restedXP > 0 then
        y = Note(P, y, ("Rested bonus: +%s on kills (%d%% of the level)"):format(Big(s.restedXP), Pct(s.restedXP, s.total)),
            COLORS.rested)
    end
    y = y - 10

    y = Heading(P, y, "Pace", "time spent on each tenth of the level")
    y = Pace(P, y, s)

    y = Heading(P, y, "Deaths & close calls")
    y = Events(P, y, s) - 10

    local questRows = {}
    for i = 1, math.min(12, #s.quests) do
        local e = s.quests[i]
        questRows[#questRows + 1] = { e.name or "?", "+" .. Big(e.xp or 0), COLORS.quest }
    end
    local mobRows = {}
    for i = 1, math.min(12, #s.mobs) do
        local m = s.mobs[i]
        mobRows[#mobRows + 1] = { m.name .. "  x" .. m.n, "+" .. Big(m.xp), COLORS.kill }
    end
    y = Columns(P, y,
        { ("Quests (%d, +%s)"):format(s.questN, Big(s.questXP)), questRows, "No quests handed in" },
        { ("Kills (%d, +%s)"):format(s.killN, Big(s.killXP)), mobRows, "No kills" })

    local foundRows = {}
    for i = #(s.q.found or {}), 1, -1 do
        local e = s.q.found[i]
        foundRows[#foundRows + 1] = { e.name, "+" .. Big(e.xp), COLORS.found }
        if #foundRows >= 10 then break end
    end
    local zoneRows = {}
    local zoneTotal = 0
    for _, z in ipairs(s.zones) do zoneTotal = zoneTotal + z.xp end
    for i = 1, math.min(10, #s.zones) do
        local z = s.zones[i]
        zoneRows[#zoneRows + 1] = { z.name, Pct(z.xp, zoneTotal) .. "%  +" .. Big(z.xp), { 0.85, 0.85, 0.9 } }
    end
    y = Columns(P, y,
        { ("Discoveries (%d, +%s)"):format(s.foundN, Big(s.foundXP)), foundRows, "Nowhere new" },
        { "Zones", zoneRows, "Not noted for this level" })
    return y
end

---------------------------------------------------------------------------
-- Overview: every level
---------------------------------------------------------------------------
local Select -- set below

local function LevelTooltip(owner, s)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Level " .. s.level .. (s.live and "  (now)" or ""), 1, 1, 1)
    GameTooltip:AddDoubleLine("Time", Time(s.played), 1, 0.82, 0, 1, 1, 1)
    if s.rate then GameTooltip:AddDoubleLine("XP per hour", Big(s.rate), 1, 0.82, 0, 1, 1, 1) end
    for _, src in ipairs(SOURCES) do
        local v = s[src.field]
        if v > 0 then
            local c = COLORS[src.key]
            GameTooltip:AddDoubleLine(src.label, Pct(v, s.total) .. "%", c[1], c[2], c[3], 1, 1, 1)
        end
    end
    if s.deaths > 0 then GameTooltip:AddDoubleLine("Deaths", s.deaths, 1, 0.35, 0.35, 1, 1, 1) end
    if s.closes > 0 then GameTooltip:AddDoubleLine("Close calls", s.closes, 1, 0.6, 0.3, 1, 1, 1) end
    GameTooltip:AddLine("Click for the full level", 0.5, 0.8, 1)
    GameTooltip:Show()
end

local function Chart(P, y, levels)
    local asc = {}
    for i = #levels, 1, -1 do asc[#asc + 1] = levels[i] end
    local most = 0
    for _, s in ipairs(asc) do if s.played and s.played > most then most = s.played end end
    local chartH = 150
    local slot = math.min(34, BODY_W / math.max(1, #asc))
    local bw = math.max(3, slot - 4)
    local base = y - 16 - chartH -- the chart's floor

    -- guide lines at a quarter, half and three quarters of the slowest level
    for _, f in ipairs({ 0.25, 0.5, 0.75, 1 }) do
        local g = P:Tex(1, 1, 1, f == 1 and 0.12 or 0.05)
        g:SetPoint("BOTTOMLEFT", P.parent, "TOPLEFT", 0, base + chartH * f)
        g:SetSize(BODY_W, 1)
        if most > 0 then
            local t = P:Text(9, DIM, "RIGHT")
            t:SetPoint("BOTTOMRIGHT", P.parent, "TOPLEFT", BODY_W, base + chartH * f + 1)
            t:SetText(Time(most * f))
        end
    end
    local floor = P:Tex(1, 1, 1, 0.25)
    floor:SetPoint("TOPLEFT", 0, base)
    floor:SetSize(BODY_W, 1)

    for i, s in ipairs(asc) do
        local x = (i - 1) * slot + (slot - bw) / 2
        local h = (s.played and most > 0) and math.max(2, chartH * s.played / most) or 3
        -- the bar, stacked by where its XP came from
        local yy = base
        if s.played then
            for _, src in ipairs(SOURCES) do
                local v = s[src.field]
                if v > 0 then
                    local c = COLORS[src.key]
                    local part = h * v / s.total
                    local t = P:Tex(c[1], c[2], c[3], s.live and 0.5 or 0.85)
                    t:SetPoint("BOTTOMLEFT", P.parent, "TOPLEFT", x, yy)
                    t:SetSize(bw, math.max(1, part))
                    yy = yy + part
                end
            end
        else
            local t = P:Tex(0.4, 0.4, 0.45, 0.6)
            t:SetPoint("BOTTOMLEFT", P.parent, "TOPLEFT", x, base)
            t:SetSize(bw, h)
        end
        -- skulls for deaths
        local top = base + h + 2
        if s.deaths > 0 then
            local sk = P:Tex(SKULL)
            local size = math.min(14, bw + 2)
            sk:SetPoint("BOTTOM", P.parent, "TOPLEFT", x + bw / 2, top)
            sk:SetSize(size, size)
            top = top + size
            if s.deaths > 1 then
                local n = P:Text(9, COLORS.death, "CENTER")
                n:SetPoint("BOTTOM", P.parent, "TOPLEFT", x + bw / 2, top)
                n:SetText("x" .. s.deaths)
            end
        end
        local lab = P:Text(9, s.live and COLORS.good or DIM, "CENTER")
        lab:SetPoint("TOP", P.parent, "TOPLEFT", x + bw / 2, base - 3)
        lab:SetText(tostring(s.level))
        -- hover and click
        local b = P:Button()
        b:SetPoint("BOTTOMLEFT", P.parent, "TOPLEFT", x - 1, base - 14)
        b:SetSize(bw + 2, chartH + 30)
        local lvl = s.level
        b:SetScript("OnEnter", function(self) LevelTooltip(self, s) end)
        b:SetScript("OnClick", function() Select(lvl) end)
    end
    -- legend
    local ly, lx = base - 20, 0
    for _, src in ipairs(SOURCES) do
        local c = COLORS[src.key]
        local sw = P:Tex(c[1], c[2], c[3], 1)
        sw:SetPoint("TOPLEFT", lx, ly - 2)
        sw:SetSize(9, 9)
        local t = P:Text(10, DIM)
        t:SetPoint("TOPLEFT", lx + 13, ly)
        t:SetText(src.label)
        lx = lx + 13 + t:GetStringWidth() + 16
    end
    local sk = P:Tex(SKULL)
    sk:SetPoint("TOPLEFT", lx, ly + 1)
    sk:SetSize(12, 12)
    local t = P:Text(10, DIM)
    t:SetPoint("TOPLEFT", lx + 15, ly)
    t:SetText("Death     Bar height = time played; a faded bar is the level you're on")
    return ly - 26
end

local TABLE_COLS = { -- header, x, width, right-aligned
    { "Level", 0, 50 }, { "Time", 56, 70, true }, { "XP / hour", 132, 80, true },
    { "Quests", 218, 70, true }, { "Kills", 294, 70, true }, { "Discovery", 370, 74, true },
    { "Deaths", 450, 56, true }, { "Close calls", 512, 76, true },
}

local function Table(P, y, levels)
    for _, col in ipairs(TABLE_COLS) do
        local h = P:Text(10, GOLD, col[4] and "RIGHT" or "LEFT")
        h:SetPoint("TOPLEFT", col[2], y)
        h:SetWidth(col[3])
        h:SetText(col[1])
    end
    y = y - 18
    for i, s in ipairs(levels) do
        local b = P:Button()
        b:SetPoint("TOPLEFT", P.parent, "TOPLEFT", -4, y + 3)
        b:SetSize(BODY_W + 8, 18)
        local lvl = s.level
        b:SetScript("OnEnter", function(self) LevelTooltip(self, s) end)
        b:SetScript("OnClick", function() Select(lvl) end)
        if i % 2 == 0 then
            local z = P:Tex(1, 1, 1, 0.025)
            z:SetPoint("TOPLEFT", -4, y + 3)
            z:SetSize(BODY_W + 8, 18)
        end
        local cells = {
            { tostring(s.level) .. (s.live and " |cff4dff4dnow|r" or ""), WHITE },
            { Time(s.played), WHITE },
            { s.rate and Big(s.rate) or "?", COLORS.pace },
            { Pct(s.questXP, s.total) .. "%", COLORS.quest },
            { Pct(s.killXP, s.total) .. "%", COLORS.kill },
            { Pct(s.foundXP, s.total) .. "%", COLORS.found },
            { s.deaths > 0 and tostring(s.deaths) or "-", s.deaths > 0 and COLORS.death or DIM },
            { s.closes > 0 and tostring(s.closes) or "-", s.closes > 0 and COLORS.close or DIM },
        }
        for c, col in ipairs(TABLE_COLS) do
            local t = P:Text(11, cells[c][2], col[4] and "RIGHT" or "LEFT")
            t:SetPoint("TOPLEFT", col[2], y)
            t:SetWidth(col[3])
            t:SetText(cells[c][1])
        end
        y = y - 18
    end
    return y - 10
end

local function OverviewPage(P, levels)
    local y = 0
    local title = P:Text(26, WHITE)
    title:SetPoint("TOPLEFT", 0, y)
    title:SetText("The climb")
    local name = UnitName("player")
    local sub = P:Text(11, DIM)
    sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 12, 3)
    y = y - 44

    if #levels == 0 then
        sub:SetText("")
        return Note(P, y, "Nothing yet. The journal fills in as you play: kill something, hand in a quest.")
    end
    local lowest, highest = levels[#levels].level, levels[1].level
    sub:SetText(((type(name) == "string" and name .. ", ") or "") .. "levels " .. lowest .. " to " .. highest)

    local played, timed, deaths, closes, quests, kills = 0, 0, 0, 0, 0, 0
    for _, s in ipairs(levels) do
        if s.played then played, timed = played + s.played, timed + 1 end
        deaths, closes = deaths + s.deaths, closes + s.closes
        quests, kills = quests + s.questN, kills + s.killN
    end
    y = Tiles(P, y, {
        { tostring(#levels), "Levels logged", WHITE },
        { Time(played > 0 and played or nil), "Time played", COLORS.good },
        { timed > 0 and Time(played / timed) or "?", "Average level", COLORS.pace },
        { Big(quests), "Quests", COLORS.quest },
        { Big(kills), "Kills", COLORS.kill },
        { deaths .. " / " .. closes, "Deaths / close calls", (deaths > 0 and COLORS.death) or DIM },
    })

    y = Heading(P, y, "Time per level", "hover a bar for its numbers, click it for the level")
    y = Chart(P, y, levels)

    -- records
    local fastest, slowest, best, deadliest, killiest, bigQuest, bigQuestLevel
    for _, s in ipairs(levels) do
        if not s.live and s.played then
            if not fastest or s.played < fastest.played then fastest = s end
            if not slowest or s.played > slowest.played then slowest = s end
            if s.rate and (not best or s.rate > best.rate) then best = s end
        end
        if s.deaths > 0 and (not deadliest or s.deaths > deadliest.deaths) then deadliest = s end
        if s.killN > 0 and (not killiest or s.killN > killiest.killN) then killiest = s end
        local q = s.quests[1]
        if q and (not bigQuest or (q.xp or 0) > (bigQuest.xp or 0)) then bigQuest, bigQuestLevel = q, s.level end
    end
    local left, right = {}, {}
    if fastest then left[#left + 1] = { "Fastest level", "Level " .. fastest.level .. ", " .. Time(fastest.played), COLORS.good } end
    if slowest then left[#left + 1] = { "Slowest level", "Level " .. slowest.level .. ", " .. Time(slowest.played), COLORS.kill } end
    if best then left[#left + 1] = { "Best XP per hour", Big(best.rate) .. " (level " .. best.level .. ")", COLORS.pace } end
    if deadliest then
        right[#right + 1] = { "Deadliest level", "Level " .. deadliest.level .. ", " .. deadliest.deaths .. " death"
            .. (deadliest.deaths == 1 and "" or "s"), COLORS.death }
    end
    if killiest then right[#right + 1] = { "Most kills", "Level " .. killiest.level .. ", " .. Big(killiest.killN), COLORS.kill } end
    if bigQuest then
        right[#right + 1] = { "Biggest quest", (bigQuest.name or "?") .. " (+" .. Big(bigQuest.xp or 0) .. ", " .. bigQuestLevel .. ")",
            COLORS.quest }
    end
    y = Columns(P, y, { "Records", left, "Finish a level to set one" }, { "Worst and best", right, "No deaths yet" })

    y = Heading(P, y, "Every level")
    y = Table(P, y, levels)
    return y
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local win, bodyPool, listPool
local selected = "overview"

local function ListRow(y, text, right, rightColor, isSel, onClick, deaths)
    local b = listPool:Button()
    b:SetPoint("TOPLEFT", listPool.parent, "TOPLEFT", 0, y)
    b:SetSize(LIST_W, 24)
    if isSel then b.sel:Show() end
    b:SetScript("OnClick", onClick)
    local t = listPool:Text(12, isSel and GOLD or WHITE)
    t:SetPoint("LEFT", b, "LEFT", 8, 0)
    t:SetText(text)
    if deaths and deaths > 0 then
        local sk = listPool:Tex(SKULL)
        sk:SetPoint("LEFT", t, "RIGHT", 5, 0)
        sk:SetSize(11, 11)
    end
    if right then
        local r = listPool:Text(10, rightColor or DIM, "RIGHT")
        r:SetPoint("RIGHT", b, "RIGHT", -6, 0)
        r:SetText(right)
    end
    return y - 25
end

local function Refresh(keepScroll)
    if not win or not win:IsShown() then return end
    local levels = Levels()
    local byLevel = {}
    for _, s in ipairs(levels) do byLevel[s.level] = s end
    if selected ~= "overview" and not byLevel[selected] then selected = "overview" end

    local name = UnitName("player")
    win.sub:SetText(type(name) == "string" and name or "")

    listPool:Reset()
    local y = 0
    y = ListRow(y, "Overview", nil, nil, selected == "overview", function() Select("overview") end)
    y = y - 6
    for _, s in ipairs(levels) do
        local lvl = s.level
        y = ListRow(y, "Level " .. s.level, s.live and "now" or Time(s.played), s.live and COLORS.good or DIM,
            selected == lvl, function() Select(lvl) end, s.deaths)
    end
    win.list:SetContentHeight(-y, true)

    bodyPool:Reset()
    local by
    if selected == "overview" then by = OverviewPage(bodyPool, levels)
    else by = LevelPage(bodyPool, byLevel[selected]) end
    win.body:SetContentHeight(-by + 10, keepScroll)
end

Select = function(key)
    selected = key
    Refresh(false)
end

local function Build()
    local f = CreateFrame("Frame", "SpliffbarsJournal", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "SpliffbarsJournal") -- Esc closes it

    local edge = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 0.92)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.065, 0.065, 0.08, 0.97)
    local strip = f:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", 1, -1)
    strip:SetPoint("TOPRIGHT", -1, -1)
    strip:SetHeight(34)
    strip:SetTexture(ns.WHITE)
    ns.Gradient(strip, "VERTICAL", 0.09, 0.07, 0.03, 1, 0.2, 0.15, 0.05, 1)
    local stripLine = f:CreateTexture(nil, "BORDER")
    stripLine:SetPoint("TOPLEFT", strip, "BOTTOMLEFT")
    stripLine:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT")
    stripLine:SetHeight(1)
    stripLine:SetColorTexture(1, 0.82, 0, 0.35)

    f.title = NewText(f, 16, GOLD)
    f.title:SetPoint("LEFT", f, "TOPLEFT", PAD, -18)
    f.title:SetText("Leveling Journal")
    f.sub = NewText(f, 11, DIM)
    f.sub:SetPoint("LEFT", f.title, "RIGHT", 10, -1)

    local ok, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
    if ok and close then
        close:SetPoint("TOPRIGHT", 3, 3)
    else
        close = CreateFrame("Button", nil, f)
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", -6, -5)
        local x = NewText(close, 16, WHITE)
        x:SetPoint("CENTER")
        x:SetText("x")
    end
    close:SetScript("OnClick", function() f:Hide() end)

    local div = f:CreateTexture(nil, "BORDER")
    div:SetColorTexture(1, 1, 1, 0.08)
    div:SetWidth(1)
    div:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + LIST_W + PAD / 2, -TOP)
    div:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + LIST_W + PAD / 2, PAD)

    f.list = Scroller(f, LIST_W + 10, H - TOP - PAD)
    f.list:SetPoint("TOPLEFT", PAD, -TOP)
    f.body = Scroller(f, BODY_W + 10, H - TOP - PAD)
    f.body:SetPoint("TOPLEFT", PAD * 2 + LIST_W, -TOP)
    listPool = NewPool(f.list.child)
    listPool.scroller = f.list
    bodyPool = NewPool(f.body.child)
    bodyPool.scroller = f.body

    f:SetScript("OnShow", function() Refresh(false) end)
    return f
end

function ns.ToggleJournal(level)
    if not ns.xpJournal then return end
    win = win or Build()
    if level then selected = level end
    if not win:IsShown() then
        win:Show() -- (draws it)
    elseif level then
        Refresh(false)
    else
        win:Hide()
    end
end

-- keep an open journal current as you play (at most once a second, and
-- without jumping you back to the top)
local queued = false
local live = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_DEAD", "QUEST_TURNED_IN", "PLAYER_REGEN_ENABLED" }) do
    pcall(live.RegisterEvent, live, e)
end
live:SetScript("OnEvent", function()
    if queued or not (win and win:IsShown()) then return end
    queued = true
    C_Timer.After(1, function()
        queued = false
        Refresh(true)
    end)
end)

SLASH_SPLIFFJOURNAL1 = "/lj"
SlashCmdList.SPLIFFJOURNAL = function() ns.ToggleJournal() end
