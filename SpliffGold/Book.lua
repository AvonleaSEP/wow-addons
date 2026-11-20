-- Spliff Gold: the Money Book.
-- A window in the Leveling Journal's look over the ledger (History.lua) and
-- the totals (Tracker.lua). Open it by clicking the Gold bar, /moneybook or /mb.
--
--   Overview     what you have, the last 30 days, where it came from and went
--   Categories   Accountant Classic's table: in, out and net per category,
--                for any period from this session to all time
--   Zones        where you earn and spend it
--   Ledger       every money change of the last weeks
--   Characters   every character's gold, and the lot together
--
-- "This character" / "All characters" at the top switches every page.

local _, ns = ...
local S = Spliffbars
local History = ns.History
local Kit = S.JournalKit

local GOLD  = { 1, 0.82, 0 }
local DIM   = { 0.62, 0.62, 0.68 }
local WHITE = { 1, 1, 1 }
local GAIN  = { 0.35, 0.95, 0.4 }
local LOSS  = { 1, 0.38, 0.35 }
local CYAN  = { 0.55, 0.78, 1 }

local W, H = 880, 580
local PAD = 14
local LIST_W = 160
local TOP = 44
local BODY_W = W - LIST_W - PAD * 3 - 10

local win, bodyPool, listPool
local page = "overview"
local scope = "char"
local periods = { overview = "month", categories = "today", zones = "all" }
local Select

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
local function Money(c) return S.Money(c or 0) end

local function Net(c)
    c = c or 0
    if c > 0 then return "|cff59f266+" .. Money(c) .. "|r" end
    if c < 0 then return "|cffff6159-" .. Money(-c) .. "|r" end
    return "|cff9e9eae" .. Money(0) .. "|r"
end

local function NetColor(c)
    if c > 0 then return GAIN elseif c < 0 then return LOSS end
    return DIM
end

local function Icon(path, size)
    return ("|TInterface\\Icons\\%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(path, size or 14, size or 14)
end

local function DayText(day, fmt)
    return date(fmt or "%b %d", History.DayToTime(day))
end

local function ClassName(name, class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.colorStr then return "|c" .. c.colorStr .. (name or "?") .. "|r" end
    return name or "?"
end

---------------------------------------------------------------------------
-- Pieces of a page (each takes the pool and a y, returns the y below)
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
    n:SetWidth(BODY_W)
    n:SetWordWrap(true)
    n:SetText(text)
    return y - math.max(18, n:GetStringHeight() + 6)
end

local function Title(P, text)
    local title = P:Text(26, WHITE)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(text)
    local sub = P:Text(11, DIM)
    sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 12, 3)
    sub:SetText(scope == "char" and (UnitName("player") or "") or "All characters")
    return -44
end

-- number tiles: { value, label, colour }
local function Tiles(P, y, tiles)
    local gap = 8
    local tw = (BODY_W - gap * (#tiles - 1)) / #tiles
    for i, t in ipairs(tiles) do
        local x = (i - 1) * (tw + gap)
        local c = t[3] or WHITE
        local bg = P:Tex(1, 1, 1, 0.045)
        bg:SetPoint("TOPLEFT", x, y)
        bg:SetSize(tw, 54)
        local accent = P:Tex(c[1], c[2], c[3], 0.7)
        accent:SetPoint("TOPLEFT", x, y)
        accent:SetSize(2, 54)
        local v = P:Text(16, c)
        v:SetPoint("TOPLEFT", x + 10, y - 10)
        v:SetWidth(tw - 16)
        v:SetText(t[1])
        local l = P:Text(10, DIM)
        l:SetPoint("TOPLEFT", x + 10, y - 35)
        l:SetWidth(tw - 16)
        l:SetText(t[2])
    end
    return y - 54 - 16
end

-- a row of period buttons, the current one lit
local function PeriodRow(P, y, keys, current, set)
    local x = 0
    for _, key in ipairs(keys) do
        local b = P:Button()
        local t = P:Text(11, key == current and GOLD or WHITE, "CENTER")
        t:SetText(ns.PeriodLabel(key))
        local w = t:GetStringWidth() + 18
        b:SetPoint("TOPLEFT", P.parent, "TOPLEFT", x, y)
        b:SetSize(w, 20)
        t:SetPoint("CENTER", b, "CENTER", 0, 0)
        local bg = P:Tex(1, 1, 1, key == current and 0 or 0.05)
        bg:SetPoint("TOPLEFT", x, y)
        bg:SetSize(w, 20)
        if key == current then b.sel:Show() end
        b:SetScript("OnClick", function() set(key) end)
        x = x + w + 4
    end
    return y - 30
end

-- a titled list in a column: rows = { left, right, colour, tooltip() }
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
        e:SetText(empty or "Nothing yet")
        return y - 17
    end
    for _, r in ipairs(rows) do
        local c = r[3] or { 0.9, 0.9, 0.9 }
        local a = P:Text(11, WHITE)
        a:SetPoint("TOPLEFT", x, y)
        a:SetWidth(w - 110)
        a:SetText(r[1])
        local b = P:Text(11, c, "RIGHT")
        b:SetPoint("TOPRIGHT", P.parent, "TOPLEFT", x + w, y)
        b:SetText(r[2])
        if r[5] then -- a share bar under the row
            local bar = P:Tex(c[1], c[2], c[3], 0.35)
            bar:SetPoint("TOPLEFT", x, y - 14)
            bar:SetSize(math.max(1, w * r[5]), 2)
        end
        if r[4] then
            local btn = P:Button()
            btn:SetPoint("TOPLEFT", P.parent, "TOPLEFT", x - 2, y + 2)
            btn:SetSize(w + 4, 18)
            btn:SetScript("OnEnter", r[4])
        end
        y = y - 20
    end
    return y
end

local function Columns(P, y, left, right)
    local cw = (BODY_W - 24) / 2
    local yl = ColumnList(P, 0, y, cw, left[1], left[2], left[3])
    local yr = ColumnList(P, cw + 24, y, cw, right[1], right[2], right[3])
    return math.min(yl, yr) - 14
end

local function TipStart(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
end

-- a table: cols = { { header, x, width, right } }, cells = { { text, colour } }
local function Header(P, y, cols)
    for _, col in ipairs(cols) do
        local h = P:Text(10, GOLD, col[4] and "RIGHT" or "LEFT")
        h:SetPoint("TOPLEFT", col[2], y)
        h:SetWidth(col[3])
        h:SetText(col[1])
    end
    return y - 18
end

local function Row(P, y, i, cols, cells, onEnter)
    if i % 2 == 0 then
        local z = P:Tex(1, 1, 1, 0.025)
        z:SetPoint("TOPLEFT", -4, y + 3)
        z:SetSize(BODY_W + 8, 18)
    end
    if onEnter then
        local b = P:Button()
        b:SetPoint("TOPLEFT", P.parent, "TOPLEFT", -4, y + 3)
        b:SetSize(BODY_W + 8, 18)
        b:SetScript("OnEnter", onEnter)
    end
    for c, col in ipairs(cols) do
        local cell = cells[c]
        if cell then
            local t = P:Text(11, cell[2] or WHITE, col[4] and "RIGHT" or "LEFT")
            t:SetPoint("TOPLEFT", col[2], y)
            t:SetWidth(col[3])
            t:SetText(cell[1])
        end
    end
    return y - 18
end

-- categories sorted by a field, biggest first, zeros left out
local function Sorted(totals, field)
    local list = {}
    for cat, b in pairs(totals) do
        if (b[field] or 0) > 0 then list[#list + 1] = { cat = cat, b = b } end
    end
    table.sort(list, function(a, b) return a.b[field] > b.b[field] end)
    return list
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------
local function DayTooltip(owner, p)
    TipStart(owner)
    GameTooltip:AddLine(DayText(p.day, "%A, %B %d"), 1, 0.82, 0)
    if p.noData then
        GameTooltip:AddLine("Before the ledger began", 0.6, 0.6, 0.66)
    else
        GameTooltip:AddDoubleLine("In", Money(p.income), 0.35, 0.95, 0.4, 1, 1, 1)
        GameTooltip:AddDoubleLine("Out", Money(p.expense), 1, 0.38, 0.35, 1, 1, 1)
        GameTooltip:AddDoubleLine("Net", Net(p.net), 1, 0.82, 0, 1, 1, 1)
        if p.minutes > 0 then
            local h, m = math.floor(p.minutes / 60), p.minutes % 60
            GameTooltip:AddDoubleLine("Online", (h > 0 and (h .. "h ") or "") .. m .. "m", 0.6, 0.6, 0.66, 1, 1, 1)
            if p.minutes >= 10 then
                GameTooltip:AddDoubleLine("Per hour", Net(p.net / p.minutes * 60), 0.6, 0.6, 0.66, 1, 1, 1)
            end
        end
    end
    GameTooltip:Show()
end

local function Chart(P, y, series)
    local half = 62
    local most = 0
    for _, p in ipairs(series) do most = math.max(most, p.income, p.expense) end
    local slot = BODY_W / #series
    local bw = math.max(3, slot - 4)
    local mid = y - 10 - half
    -- guide lines
    for _, f in ipairs({ 0.5, 1 }) do
        for _, sign in ipairs({ 1, -1 }) do
            local g = P:Tex(1, 1, 1, 0.05)
            g:SetPoint("TOPLEFT", 0, mid + sign * half * f)
            g:SetSize(BODY_W, 1)
        end
        if most > 0 then
            local t = P:Text(9, DIM, "RIGHT")
            t:SetPoint("BOTTOMRIGHT", P.parent, "TOPLEFT", BODY_W, mid + half * f + 1)
            t:SetText(S.ShortMoney(most * f))
        end
    end
    local axis = P:Tex(1, 1, 1, 0.25)
    axis:SetPoint("TOPLEFT", 0, mid)
    axis:SetSize(BODY_W, 1)

    for i, p in ipairs(series) do
        local x = (i - 1) * slot + (slot - bw) / 2
        if not p.noData and most > 0 then
            if p.income > 0 then
                local t = P:Tex(GAIN[1], GAIN[2], GAIN[3], 0.8)
                t:SetPoint("BOTTOMLEFT", P.parent, "TOPLEFT", x, mid)
                t:SetSize(bw, math.max(1, half * p.income / most))
            end
            if p.expense > 0 then
                local t = P:Tex(LOSS[1], LOSS[2], LOSS[3], 0.8)
                t:SetPoint("TOPLEFT", P.parent, "TOPLEFT", x, mid - 1)
                t:SetSize(bw, math.max(1, half * p.expense / most))
            end
        elseif p.noData then
            local t = P:Tex(1, 1, 1, 0.06)
            t:SetPoint("TOPLEFT", P.parent, "TOPLEFT", x, mid + 1)
            t:SetSize(bw, 2)
        end
        if (#series - i) % 7 == 0 then -- today, and each week back from it
            local lab = P:Text(9, i == #series and GOLD or DIM, "CENTER")
            lab:SetPoint("TOP", P.parent, "TOPLEFT", x + bw / 2, mid - half - 4)
            lab:SetText(i == #series and "Today" or DayText(p.day))
        end
        local b = P:Button()
        b:SetPoint("TOPLEFT", P.parent, "TOPLEFT", x - 1, mid + half)
        b:SetSize(bw + 2, half * 2)
        b:SetScript("OnEnter", function(self) DayTooltip(self, p) end)
    end
    local ly = mid - half - 20
    local lx = 0
    for _, l in ipairs({ { GAIN, "Money in" }, { LOSS, "Money out" } }) do
        local sw = P:Tex(l[1][1], l[1][2], l[1][3], 1)
        sw:SetPoint("TOPLEFT", lx, ly - 2)
        sw:SetSize(9, 9)
        local t = P:Text(10, DIM)
        t:SetPoint("TOPLEFT", lx + 13, ly)
        t:SetText(l[2])
        lx = lx + 13 + t:GetStringWidth() + 16
    end
    return ly - 26
end

local function CategoryTooltip(cat, b, period)
    return function(self)
        local c = ns.Category(cat)
        TipStart(self)
        GameTooltip:AddLine(Icon(c.icon, 16) .. " " .. c.label, 1, 0.82, 0)
        GameTooltip:AddLine(ns.PeriodLabel(period), 0.6, 0.6, 0.66)
        GameTooltip:AddDoubleLine("In", Money(b.i) .. (b.ni and b.ni > 0 and ("  |cff9e9eae(" .. b.ni .. "x)|r") or ""),
            0.35, 0.95, 0.4, 1, 1, 1)
        GameTooltip:AddDoubleLine("Out", Money(b.o) .. (b.no and b.no > 0 and ("  |cff9e9eae(" .. b.no .. "x)|r") or ""),
            1, 0.38, 0.35, 1, 1, 1)
        GameTooltip:AddDoubleLine("Net", Net(b.i - b.o), 1, 0.82, 0, 1, 1, 1)
        if b.mi and b.mi > 0 then GameTooltip:AddDoubleLine("Biggest in", Money(b.mi), 0.6, 0.6, 0.66, 1, 1, 1) end
        if b.mo and b.mo > 0 then GameTooltip:AddDoubleLine("Biggest out", Money(b.mo), 0.6, 0.6, 0.66, 1, 1, 1) end
        GameTooltip:Show()
    end
end

local OVERVIEW_PERIODS = { "session", "today", "week", "month", "year", "all" }

local function OverviewPage(P)
    local y = Title(P, "Money Book")
    local on
    if scope == "char" then
        on = GetMoney()
    else
        on = 0
        for _, c in ipairs(ns.Characters()) do on = on + (c.money or 0) end
    end
    local function net(period) local _, i, o = ns.Totals(period, scope) return i - o end
    local sNet, tNet, wNet, aNet = net("session"), net("today"), net("week"), net("all")
    y = Tiles(P, y, {
        { Money(on), scope == "char" and "On hand" or "Net worth", GOLD },
        { Net(sNet), "This session", NetColor(sNet) },
        { Net(tNet), "Today", NetColor(tNet) },
        { Net(wNet), "This week", NetColor(wNet) },
        { Net(aNet), "All time", NetColor(aNet) },
    })

    local today = History.DayKey()
    local series = History:GetDailySeries(ns.Scope(scope), History.AddDays(today, -29), today)
    y = Heading(P, y, "The last 30 days", "hover a day for its numbers")
    y = Chart(P, y, series)

    local period = periods.overview
    y = Heading(P, y, "Where it came from, where it went")
    y = PeriodRow(P, y, OVERVIEW_PERIODS, period, function(k) periods.overview = k; Select(page) end)
    local totals, income, expense = ns.Totals(period, scope)
    local left, right = {}, {}
    for _, e in ipairs(Sorted(totals, "i")) do
        local c = ns.Category(e.cat)
        left[#left + 1] = { Icon(c.icon) .. " " .. c.label, Money(e.b.i), GAIN, CategoryTooltip(e.cat, e.b, period),
            income > 0 and e.b.i / income or 0 }
    end
    for _, e in ipairs(Sorted(totals, "o")) do
        local c = ns.Category(e.cat)
        right[#right + 1] = { Icon(c.icon) .. " " .. c.label, Money(e.b.o), LOSS, CategoryTooltip(e.cat, e.b, period),
            expense > 0 and e.b.o / expense or 0 }
    end
    y = Columns(P, y, { "Came from  |cff9e9eae" .. Money(income) .. "|r", left, "No money in" },
        { "Went to  |cff9e9eae" .. Money(expense) .. "|r", right, "No money out" })

    -- records: the biggest single changes the ledger has seen
    local all = History:GetTotals(ns.Scope(scope), 19000101, today)
    local gains, spends = {}, {}
    for _, e in ipairs(Sorted(all, "mi")) do
        if #gains < 5 then
            local c = ns.Category(e.cat)
            gains[#gains + 1] = { Icon(c.icon) .. " " .. c.label, Money(e.b.mi), GAIN }
        end
    end
    for _, e in ipairs(Sorted(all, "mo")) do
        if #spends < 5 then
            local c = ns.Category(e.cat)
            spends[#spends + 1] = { Icon(c.icon) .. " " .. c.label, Money(e.b.mo), LOSS }
        end
    end
    y = Columns(P, y, { "Biggest single take", gains, "None yet" }, { "Biggest single spend", spends, "None yet" })
    return y
end

---------------------------------------------------------------------------
-- Categories (Accountant Classic's table)
---------------------------------------------------------------------------
local CAT_COLS = { -- header, x, width, right-aligned
    { "Category", 0, 200 }, { "In", 200, 140, true }, { "Out", 346, 140, true }, { "Net", 492, 170, true },
}
local ALL_PERIODS = {}
for _, p in ipairs(ns.PERIODS) do ALL_PERIODS[#ALL_PERIODS + 1] = p.key end

local function CategoriesPage(P)
    local y = Title(P, "Categories")
    local period = periods.categories
    y = PeriodRow(P, y, ALL_PERIODS, period, function(k) periods.categories = k; Select(page) end)
    if period ~= "session" and period ~= "all" then
        local from, to = ns.Range(period)
        y = Note(P, y + 6, from == to and DayText(from, "%A, %B %d") or (DayText(from) .. " to " .. DayText(to))) - 4
    elseif period == "session" and scope == "all" then
        y = Note(P, y + 6, "The session is this character's only.") - 4
    end
    local totals, income, expense = ns.Totals(period, scope)
    local most = 1
    for _, b in pairs(totals) do most = math.max(most, b.i, b.o) end
    y = Header(P, y, CAT_COLS)
    local list = {}
    for cat, b in pairs(totals) do
        if b.i > 0 or b.o > 0 then list[#list + 1] = { cat = cat, b = b } end
    end
    table.sort(list, function(a, b) return ns.Category(a.cat).order < ns.Category(b.cat).order end)
    if #list == 0 then return Note(P, y, "Nothing in this period.") end
    for i, e in ipairs(list) do
        local c, b = ns.Category(e.cat), e.b
        -- bars behind the amounts, against the biggest in the table
        if b.i > 0 then
            local bar = P:Tex(GAIN[1], GAIN[2], GAIN[3], 0.16)
            bar:SetPoint("TOPRIGHT", P.parent, "TOPLEFT", 340, y + 2)
            bar:SetSize(math.max(1, 130 * b.i / most), 16)
        end
        if b.o > 0 then
            local bar = P:Tex(LOSS[1], LOSS[2], LOSS[3], 0.16)
            bar:SetPoint("TOPRIGHT", P.parent, "TOPLEFT", 486, y + 2)
            bar:SetSize(math.max(1, 130 * b.o / most), 16)
        end
        y = Row(P, y, i, CAT_COLS, {
            { Icon(c.icon) .. " " .. c.label, WHITE },
            { b.i > 0 and Money(b.i) or "-", b.i > 0 and WHITE or DIM },
            { b.o > 0 and Money(b.o) or "-", b.o > 0 and WHITE or DIM },
            { Net(b.i - b.o) },
        }, CategoryTooltip(e.cat, b, period))
    end
    local line = P:Tex(1, 0.82, 0, 0.3)
    line:SetPoint("TOPLEFT", 0, y + 2)
    line:SetSize(BODY_W, 1)
    y = y - 4
    y = Row(P, y, 1, CAT_COLS, {
        { "Total", GOLD }, { Money(income), GAIN }, { Money(expense), LOSS }, { Net(income - expense) },
    })
    if period == "all" and ns.DB() and next(ns.DB().life) then
        y = Note(P, y - 10, "All time counts everything since Accountant Classic started tracking (copied in), plus what the Money Book has logged since.")
    end
    return y
end

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------
local ZONE_PERIODS = { "today", "week", "month", "year", "all" }
local ZONE_COLS = {
    { "Zone", 0, 260 }, { "In", 260, 130, true }, { "Out", 396, 130, true }, { "Net", 532, 130, true },
}

local function ZoneTooltip(z)
    return function(self)
        TipStart(self)
        GameTooltip:AddLine(z.name, 1, 0.82, 0)
        local list = {}
        for cat, b in pairs(z.cats) do list[#list + 1] = { cat = cat, b = b } end
        table.sort(list, function(a, b) return (a.b.i + a.b.o) > (b.b.i + b.b.o) end)
        for i = 1, math.min(8, #list) do
            local c, b = ns.Category(list[i].cat), list[i].b
            GameTooltip:AddDoubleLine(Icon(c.icon) .. " " .. c.label,
                (b.i > 0 and ("|cff59f266+" .. Money(b.i) .. "|r") or "") .. (b.i > 0 and b.o > 0 and "  " or "")
                .. (b.o > 0 and ("|cffff6159-" .. Money(b.o) .. "|r") or ""), 1, 1, 1, 1, 1, 1)
        end
        if z.subs and #z.subs > 0 then
            table.sort(z.subs, function(a, b) return (a.i + a.o) > (b.i + b.o) end)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Places", 1, 0.82, 0)
            for i = 1, math.min(6, #z.subs) do
                local s = z.subs[i]
                GameTooltip:AddDoubleLine("   " .. s.name, Net(s.i - s.o), 0.9, 0.9, 0.9, 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end
end

local function ZonesPage(P)
    local y = Title(P, "Zones")
    local period = periods.zones
    y = PeriodRow(P, y, ZONE_PERIODS, period, function(k) periods.zones = k; Select(page) end)
    local list = period == "all" and ns.AllTimeZones(scope) or ns.PeriodZones(period, scope)
    table.sort(list, function(a, b) return (a.i + a.o) > (b.i + b.o) end)
    if #list == 0 then return Note(P, y, "Nothing in this period.") end
    local top = {}
    for _, z in ipairs(list) do top[#top + 1] = z end
    table.sort(top, function(a, b) return (a.i - a.o) > (b.i - b.o) end)
    local best, worst = top[1], top[#top]
    if best and best.i - best.o > 0 then
        y = Note(P, y, ("Best place for gold: |cffffffff%s|r (%s)."):format(best.name, Net(best.i - best.o)), CYAN)
    end
    if worst and worst ~= best and worst.i - worst.o < 0 then
        y = Note(P, y, ("Where it drains: |cffffffff%s|r (%s)."):format(worst.name, Net(worst.i - worst.o)), CYAN)
    end
    y = y - 6
    y = Header(P, y, ZONE_COLS)
    for i = 1, math.min(60, #list) do
        local z = list[i]
        y = Row(P, y, i, ZONE_COLS, {
            { z.name, WHITE },
            { z.i > 0 and Money(z.i) or "-", z.i > 0 and WHITE or DIM },
            { z.o > 0 and Money(z.o) or "-", z.o > 0 and WHITE or DIM },
            { Net(z.i - z.o) },
        }, ZoneTooltip(z))
    end
    if period == "all" then
        y = Note(P, y - 10, "All time is by zone name, kept since Accountant Classic started. The shorter periods come from the ledger and know the places inside each zone (hover).")
    end
    return y
end

---------------------------------------------------------------------------
-- Ledger (the recent list)
---------------------------------------------------------------------------
local LEDGER_MAX = 200

local function LedgerPage(P)
    local y = Title(P, "Ledger")
    local db = History:GetDB()
    local recent = db and db.recent or {}
    local me = ns.CharKey()
    local cols = scope == "all"
        and { { "When", 0, 96 }, { "What", 100, 150 }, { "Where", 254, 190 }, { "Who", 448, 100 }, { "Amount", 552, 110, true } }
        or { { "When", 0, 96 }, { "What", 100, 170 }, { "Where", 274, 250 }, { "Amount", 532, 130, true } }
    y = Header(P, y, cols)
    local shown = 0
    for idx = #recent, 1, -1 do
        local r = recent[idx]
        if scope == "all" or r.c == me then
            shown = shown + 1
            local c = ns.Category(r.k)
            local where
            if r.u then
                where = "|cff9e9eaewhile away|r"
            else
                local zone, sub = History:GetLocationName(r)
                where = sub and ((zone and (zone .. ", ") or "") .. sub) or zone or "?"
            end
            local what = Icon(c.icon) .. " " .. c.label .. (r.n and r.n > 1 and (" |cff9e9eaex" .. r.n .. "|r") or "")
            local cells = { { date("%b %d %H:%M", r.t), DIM }, { what, WHITE }, { where, { 0.85, 0.85, 0.85 } } }
            if scope == "all" then
                local name = (r.c or ""):match("|(.*)$") or r.c
                cells[#cells + 1] = { name, CYAN }
            end
            cells[#cells + 1] = { Net(r.a) }
            y = Row(P, y, shown, cols, cells)
            if shown >= LEDGER_MAX then break end
        end
    end
    if shown == 0 then return Note(P, y, "No money changes yet.") end
    local days = db and db.settings and db.settings.recentDays or 30
    return Note(P, y - 10, ("The newest %d. The ledger keeps every change for %d days (change it in /spliffbars > Money Book); the totals on the other pages are kept for good."):format(
        math.min(shown, LEDGER_MAX), days))
end

---------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------
local CHAR_COLS = {
    { "Character", 0, 170 }, { "Gold", 170, 130, true }, { "Last seen", 306, 80, true },
    { "All-time in", 392, 90, true }, { "Out", 486, 80, true }, { "Net", 572, 90, true },
}

local function CharactersPage(P)
    local y = Title(P, "Characters")
    local chars = ns.Characters()
    local worth, inAll, outAll = 0, 0, 0
    for _, c in ipairs(chars) do
        worth = worth + (c.money or 0)
        inAll, outAll = inAll + c.i, outAll + c.o
    end
    y = Tiles(P, y, {
        { Money(worth), "Net worth", GOLD },
        { tostring(#chars), "Characters", WHITE },
        { Net(inAll - outAll), "All-time net", NetColor(inAll - outAll) },
    })
    y = Header(P, y, CHAR_COLS)
    local me = ns.CharKey()
    for i, c in ipairs(chars) do
        local name = ClassName(c.name, c.class) .. (c.key == me and " |cffffd100(you)|r" or "")
        y = Row(P, y, i, CHAR_COLS, {
            { name, WHITE },
            { c.money and Money(c.money) or "?", c.money and WHITE or DIM },
            { c.moneyAt and date("%b %d", c.moneyAt) or "-", DIM },
            { c.i > 0 and S.ShortMoney(c.i) or "-", GAIN },
            { c.o > 0 and S.ShortMoney(c.o) or "-", LOSS },
            { Net(c.i - c.o) },
        }, function(self)
            TipStart(self)
            GameTooltip:AddLine(ClassName(c.name, c.class))
            if c.server then GameTooltip:AddLine(c.server, 0.6, 0.6, 0.66) end
            GameTooltip:AddDoubleLine("Gold", c.money and Money(c.money) or "?", 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine("All-time in", Money(c.i), 0.35, 0.95, 0.4, 1, 1, 1)
            GameTooltip:AddDoubleLine("All-time out", Money(c.o), 1, 0.38, 0.35, 1, 1, 1)
            GameTooltip:Show()
        end)
    end
    return y
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local PAGES = {
    { key = "overview",   label = "Overview",   build = OverviewPage },
    { key = "categories", label = "Categories", build = CategoriesPage },
    { key = "zones",      label = "Zones",      build = ZonesPage },
    { key = "ledger",     label = "Ledger",     build = LedgerPage },
    { key = "characters", label = "Characters", build = CharactersPage },
}

local function ListRow(y, text, isSel, onClick)
    local b = listPool:Button()
    b:SetPoint("TOPLEFT", listPool.parent, "TOPLEFT", 0, y)
    b:SetSize(LIST_W, 24)
    if isSel then b.sel:Show() end
    b:SetScript("OnClick", onClick)
    local t = listPool:Text(12, isSel and GOLD or WHITE)
    t:SetPoint("LEFT", b, "LEFT", 8, 0)
    t:SetText(text)
    return y - 25
end

local function Refresh(keepScroll)
    if not win or not win:IsShown() then return end
    win.scopeChar.sel:SetShown(scope == "char")
    win.scopeAll.sel:SetShown(scope == "all")
    win.scopeChar.text:SetTextColor(unpack(scope == "char" and GOLD or WHITE))
    win.scopeAll.text:SetTextColor(unpack(scope == "all" and GOLD or WHITE))

    listPool:Reset()
    local y = 0
    local build
    for _, p in ipairs(PAGES) do
        local key = p.key
        if key == page then build = p.build end
        y = ListRow(y, p.label, key == page, function() Select(key) end)
    end
    -- what you have, under the list
    y = y - 14
    local cap = listPool:Text(10, DIM)
    cap:SetPoint("TOPLEFT", 8, y)
    cap:SetText("On hand")
    local m = listPool:Text(12, WHITE)
    m:SetPoint("TOPLEFT", 8, y - 14)
    m:SetText(Money(GetMoney()))
    win.list:SetContentHeight(-y + 40, true)

    bodyPool:Reset()
    local by = (build or OverviewPage)(bodyPool)
    win.body:SetContentHeight(-by + 10, keepScroll)
end

Select = function(key)
    page = key
    Refresh(false)
end

local function ScopeButton(f, label, value)
    local b = CreateFrame("Button", nil, f)
    b.text = Kit.NewText(b, 11, WHITE)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetSize(b.text:GetStringWidth() + 20, 22)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.05)
    b.sel = b:CreateTexture(nil, "BORDER")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(1, 0.82, 0, 0.18)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b:SetScript("OnClick", function()
        scope = value
        if SpliffGoldDB then SpliffGoldDB.scope = value end
        Refresh(false)
    end)
    return b
end

local function Build()
    local f = CreateFrame("Frame", "SpliffGoldBook", UIParent)
    f:SetSize(W, H)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        if SpliffGoldDB then SpliffGoldDB.win = { point, rel, x, y } end
    end)
    local pos = SpliffGoldDB and SpliffGoldDB.win
    if type(pos) == "table" and pos[1] then
        f:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
    else
        f:SetPoint("CENTER")
    end
    f:Hide()
    tinsert(UISpecialFrames, "SpliffGoldBook") -- Esc closes it

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
    strip:SetTexture(S.WHITE)
    S.Gradient(strip, "VERTICAL", 0.09, 0.07, 0.03, 1, 0.2, 0.15, 0.05, 1)
    local stripLine = f:CreateTexture(nil, "BORDER")
    stripLine:SetPoint("TOPLEFT", strip, "BOTTOMLEFT")
    stripLine:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT")
    stripLine:SetHeight(1)
    stripLine:SetColorTexture(1, 0.82, 0, 0.35)

    local coin = f:CreateTexture(nil, "ARTWORK")
    coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    coin:SetSize(16, 16)
    coin:SetPoint("LEFT", f, "TOPLEFT", PAD, -18)
    f.title = Kit.NewText(f, 16, GOLD)
    f.title:SetPoint("LEFT", coin, "RIGHT", 6, 0)
    f.title:SetText("Money Book")

    local ok, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
    if ok and close then
        close:SetPoint("TOPRIGHT", 3, 3)
    else
        close = CreateFrame("Button", nil, f)
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", -6, -5)
        local x = Kit.NewText(close, 16, WHITE)
        x:SetPoint("CENTER")
        x:SetText("x")
    end
    close:SetScript("OnClick", function() f:Hide() end)

    f.scopeAll = ScopeButton(f, "All characters", "all")
    f.scopeAll:SetPoint("RIGHT", f, "TOPRIGHT", -36, -18)
    f.scopeChar = ScopeButton(f, "This character", "char")
    f.scopeChar:SetPoint("RIGHT", f.scopeAll, "LEFT", -3, 0)

    local div = f:CreateTexture(nil, "BORDER")
    div:SetColorTexture(1, 1, 1, 0.08)
    div:SetWidth(1)
    div:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + LIST_W + PAD / 2, -TOP)
    div:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + LIST_W + PAD / 2, PAD)

    f.list = Kit.Scroller(f, LIST_W + 10, H - TOP - PAD)
    f.list:SetPoint("TOPLEFT", PAD, -TOP)
    f.body = Kit.Scroller(f, BODY_W + 10, H - TOP - PAD)
    f.body:SetPoint("TOPLEFT", PAD * 2 + LIST_W, -TOP)
    listPool = Kit.NewPool(f.list.child)
    listPool.scroller = f.list
    bodyPool = Kit.NewPool(f.body.child)
    bodyPool.scroller = f.body

    f:SetScript("OnShow", function() Refresh(false) end)
    return f
end

function ns.Toggle(which)
    if not ns.DB() then return end -- (not loaded yet)
    if not Kit then
        print(S.PREFIX .. "the Money Book needs a newer Spliffbars.")
        return
    end
    if not win then
        if SpliffGoldDB and (SpliffGoldDB.scope == "all" or SpliffGoldDB.scope == "char") then scope = SpliffGoldDB.scope end
        win = Build()
    end
    if which then page = which end
    if not win:IsShown() then
        win:Show() -- (draws it)
    elseif which then
        Refresh(false)
    else
        win:Hide()
    end
end
S.ToggleMoneyBook = ns.Toggle

-- keep an open book current (at most twice a second, keeping your place)
local queued = false
ns.OnChange(function()
    if queued or not (win and win:IsShown()) then return end
    queued = true
    C_Timer.After(0.5, function()
        queued = false
        Refresh(true)
    end)
end)

SLASH_SPLIFFMONEYBOOK1 = "/moneybook"
SLASH_SPLIFFMONEYBOOK2 = "/mb"
SlashCmdList.SPLIFFMONEYBOOK = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)") or ""
    for _, p in ipairs(PAGES) do
        if p.key == msg then return ns.Toggle(p.key) end
    end
    ns.Toggle()
end

---------------------------------------------------------------------------
-- Its page in /spliffbars
---------------------------------------------------------------------------
if S.AddOptionsTab then
    S.AddOptionsTab("Money Book", "Where your gold comes from and where it goes: by day, category, zone and character. Forked from Accountant Classic.",
        function(opt)
            local L = opt:Column(16, -70)
            opt:Heading(L, "Money Book")
            opt:Check(L, "Click the Gold bar to open it", function() return S.Opt("goldClick") end,
                function(v) S.SetOpt("goldClick", v) end)
            opt:Note(L, "Or type /mb (/mb ledger, /mb zones ... opens that page).", 20)
            opt:Button(L, "Open the Money Book", function() ns.Toggle() end)
            opt:Heading(L, "Accountant Classic")
            local status = opt:Note(L, "")
            local again = opt:Button(L, "Copy its data again...", function() ns.Reimport() end)
            opt:Note(L, "Replaces what the Money Book logged since the last copy with Accountant Classic's records. Once you're happy, Accountant Classic can be switched off.")
            opt.refreshers[#opt.refreshers + 1] = function()
                local t = ns.DB() and ns.DB().imported
                if type(t) == "number" and t > 0 then
                    status:SetText("Copied in on " .. date("%B %d, %Y", t) .. ".")
                elseif ns.AccountantPresent() then
                    status:SetText("Installed; nothing copied yet.")
                else
                    status:SetText("Not installed (or switched off), so there's nothing to copy.")
                end
                again:SetEnabled(ns.AccountantPresent())
            end

            local R = opt:Column(340, -70)
            opt:Heading(R, "Ledger")
            local function settings()
                local db = History:GetDB()
                return db and db.settings
            end
            opt:Slider(R, "Keep every money change for", 7, 120, 1,
                function() local s = settings() return s and s.recentDays or 30 end,
                function(v)
                    local s = settings()
                    if s then s.recentDays = v; History:TrimRecent() end
                end,
                function(v) return v .. " days" end)
            opt:Note(R, "That's the Ledger page. Totals by day, category and zone are kept for good either way.")
            opt:Choice(R, "Weeks start on", { { "Sunday", 1 }, { "Monday", 2 } },
                function() return (ns.DB() and ns.DB().weekStart) or 1 end,
                function(v) if ns.DB() then ns.DB().weekStart = v end end)
        end)
end
