-- Spliffbars: Gold
-- A small gold bar filling toward a gold goal you set ("Set Gold Goal..."
-- in its Edit Mode panel, or /spliffbars goal 250). Glossy fill, a shine
-- that sweeps across now and then, and a glow once you reach the goal.
--
-- Hover it: it grows taller and becomes a timeline of your big money
-- moments (big sales, loot, quest rewards, mail / auction money), each
-- marked where your gold stood at the time, with its icon and amount. The
-- tooltip has today, this session, gold per hour and your records.
--
-- "Big" means at least "Big Moment %" of your goal (and at least 10s), so
-- the small bar only keeps what matters. Everything is per character.

local _, ns = ...
local LEM, isSecret, Num = ns.LEM, ns.isSecret, ns.Num

-- as Devon has it: a long, slim bar along the bottom-left corner
-- Vertical: the bar stands up and fills bottom to top; Width and Height
-- swap so it keeps its shape, the text hides (no room), the hover grows it
-- wider and the timeline's labels sit to its right.
local DEFAULTS = {
    width = 475, height = 17, expand = false, expandHeight = 48, text = "goal",
    font = "Game default", fontSize = 11, shine = true, bigPct = 8, vertical = false, hidden = false,
}
local DEFAULT_POS = { point = "BOTTOMLEFT", x = 24, y = 20 }
local DEFAULT_GOAL = 100 * 10000 -- 100 gold, in copper
local BIG_FLOOR = 1000            -- never smaller than 10 silver

local DB, layoutName
local function Look() return ns.Look(DB, layoutName, "gold", DEFAULTS) end
local function Goal() return (DB and DB.goal) or DEFAULT_GOAL end

local function Char()
    DB.chars = DB.chars or {}
    local key = ns.CharKey()
    local c = DB.chars[key]
    if not c then c = { events = {}, days = {}, records = {} }; DB.chars[key] = c end
    c.events, c.days, c.records = c.events or {}, c.days or {}, c.records or {}
    return c
end

local function Today()
    local c = Char()
    local d = date("%Y-%m-%d")
    c.days[d] = c.days[d] or { gained = 0, spent = 0, kinds = {} }
    -- keep two weeks of days
    local n = 0
    for _ in pairs(c.days) do n = n + 1 end
    if n > 14 then
        local oldest
        for k in pairs(c.days) do if not oldest or k < oldest then oldest = k end end
        c.days[oldest] = nil
    end
    return c.days[d]
end

local function BigEnough(amount)
    return amount >= math.max(BIG_FLOOR, Goal() * (Look().bigPct or 2) / 100)
end

---------------------------------------------------------------------------
-- Where money comes from: what's open when it changes, and what just
-- happened (a sale, a quest hand-in, coin loot)
---------------------------------------------------------------------------
local open = {}          -- merchant / mail / auction / trade / trainer / taxi
local recentLootAt = 0   -- a "You loot ..." coin message
local recentQuest        -- { name, money, at }
local recentSales = {}   -- items you just sold: { name, icon, value, count, at }
local lastQuestTitle

local session = { at = GetTime(), gained = 0, spent = 0 }
local lastMoney

local KIND_LABEL = {
    sale = "Sold", loot = "Looted", quest = "Quest reward", mail = "Mail / auction",
    trade = "Trade", other = "Gained",
    vendor = "Bought / repaired", training = "Training", flight = "Flight", auction = "Auction house",
    spent = "Spent",
}
local KIND_ICON = {
    sale = "INV_Misc_Coin_01", loot = "INV_Misc_Bag_10", quest = "INV_Misc_Note_01",
    mail = "INV_Letter_15", trade = "INV_Misc_Coin_02", other = "INV_Misc_Coin_03",
}

-- an item sold at a vendor: noted when it leaves your bags there
local function NoteSale(bag, slot)
    if not open.merchant then return end
    local link, count, icon
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        info = ok and ns.Tbl(info)
        if info then link, count, icon = info.hyperlink, info.stackCount, info.iconFileID end
    elseif GetContainerItemInfo then
        local ok, ic, ct, _, _, _, _, lk = pcall(GetContainerItemInfo, bag, slot)
        if ok then link, count, icon = lk, ct, ic end
    end
    if type(link) ~= "string" or isSecret(link) then return end
    -- (this client keeps it under C_Item; the old name may be missing)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return end
    local ok2, name, _, _, _, _, _, _, _, _, _, sellPrice = pcall(getInfo, link)
    if not ok2 then return end
    count = Num(count) and count or 1
    if not Num(sellPrice) or sellPrice <= 0 then return end
    recentSales[#recentSales + 1] = { name = name or link, icon = icon, value = sellPrice * count, count = count, at = GetTime() }
end
if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", NoteSale)
elseif UseContainerItem then
    hooksecurefunc("UseContainerItem", NoteSale)
end

local function Classify(delta)
    local now = GetTime()
    if delta > 0 then
        if recentQuest and now - recentQuest.at < 4 then
            local q = recentQuest
            recentQuest = nil
            return "quest", q.name, nil
        end
        if open.merchant then
            -- the items sold in the last few seconds
            local items, total = {}, 0
            for i = #recentSales, 1, -1 do
                local s = recentSales[i]
                if now - s.at < 4 then items[#items + 1] = s; total = total + s.value end
                table.remove(recentSales, i)
            end
            if #items == 1 then
                local s = items[1]
                return "sale", s.name .. (s.count > 1 and (" x" .. s.count) or ""), s.icon
            elseif #items > 1 then
                table.sort(items, function(a, b) return a.value > b.value end)
                return "sale", items[1].name .. " and " .. (#items - 1) .. " more", items[1].icon
            end
            return "sale", "items", nil
        end
        if now - recentLootAt < 3 then return "loot", nil, nil end
        if open.mail or open.auction then return "mail", nil, nil end
        if open.trade then return "trade", nil, nil end
        return "other", nil, nil
    end
    if open.merchant then return "vendor" end
    if open.trainer then return "training" end
    if open.taxi then return "flight" end
    if open.auction then return "auction" end
    return "spent"
end

local Refresh -- below

local function OnMoney()
    local cur = GetMoney()
    if not Num(cur) then return end
    if not lastMoney then lastMoney = cur; return end
    local delta = cur - lastMoney
    lastMoney = cur
    if delta == 0 or not DB then return end
    local kind, text, icon = Classify(delta)
    local day = Today()
    day.kinds[kind] = (day.kinds[kind] or 0) + delta
    if delta > 0 then
        day.gained = day.gained + delta
        session.gained = session.gained + delta
        local c = Char()
        -- records
        local rec = c.records[kind]
        if not rec or delta > rec.amount then
            c.records[kind] = { amount = delta, text = text, when = date("%Y-%m-%d") }
        end
        -- the big moments, for the timeline
        if BigEnough(delta) then
            c.events[#c.events + 1] = { kind = kind, amount = delta, text = text, icon = icon,
                money = cur, t = time() }
            while #c.events > 50 do table.remove(c.events, 1) end
        end
    else
        day.spent = day.spent - delta
        session.spent = session.spent - delta
    end
    if Refresh then Refresh() end
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local bar = CreateFrame("Frame", "SpliffbarsGold", UIParent)
bar.editModeName = "Spliffbars: Gold"
bar:SetSize(DEFAULTS.width, DEFAULTS.height)
bar:SetClampedToScreen(true)
bar:SetFrameStrata("MEDIUM")
if bar.EnableMouseMotion then bar:EnableMouseMotion(true) else bar:EnableMouse(true) end

-- frame: dark bronze edge, a lighter inner rim, near-black inside
local edge = bar:CreateTexture(nil, "BACKGROUND", nil, 0)
edge:SetAllPoints()
edge:SetColorTexture(0.32, 0.22, 0.04, 1)
local rim = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
rim:SetPoint("TOPLEFT", 1, -1)
rim:SetPoint("BOTTOMRIGHT", -1, 1)
rim:SetColorTexture(0.75, 0.58, 0.2, 1)
local inside = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
inside:SetPoint("TOPLEFT", 2, -2)
inside:SetPoint("BOTTOMRIGHT", -2, 2)
inside:SetColorTexture(0.06, 0.045, 0.015, 0.95)

local sb = CreateFrame("StatusBar", nil, bar)
sb:SetPoint("TOPLEFT", 2, -2)
sb:SetPoint("BOTTOMRIGHT", -2, 2)
ns.SmoothFill(sb)
-- gold: deep amber at the bottom to bright gold at the top
ns.Gradient(sb.grad, "VERTICAL", 0.55, 0.36, 0.04, 1, 1, 0.86, 0.36, 1)

-- gloss: a soft light band across the top half of the fill
local gloss = sb.clip:CreateTexture(nil, "OVERLAY")
gloss:SetTexture(ns.WHITE)
gloss:SetPoint("TOPLEFT", sb, "TOPLEFT")
gloss:SetPoint("TOPRIGHT", sb, "TOPRIGHT")
ns.Gradient(gloss, "VERTICAL", 1, 1, 1, 0, 1, 0.97, 0.85, 0.35)

-- shine: a bright band that sweeps across the fill every few seconds
local shineHolder = CreateFrame("Frame", nil, sb.clip)
shineHolder:SetSize(40, 10)
local shineL = shineHolder:CreateTexture(nil, "OVERLAY")
shineL:SetTexture(ns.WHITE)
shineL:SetPoint("TOPLEFT"); shineL:SetPoint("BOTTOMLEFT"); shineL:SetWidth(20)
ns.Gradient(shineL, "HORIZONTAL", 1, 0.95, 0.75, 0, 1, 0.95, 0.75, 0.55)
local shineR = shineHolder:CreateTexture(nil, "OVERLAY")
shineR:SetTexture(ns.WHITE)
shineR:SetPoint("TOPRIGHT"); shineR:SetPoint("BOTTOMRIGHT"); shineR:SetWidth(20)
ns.Gradient(shineR, "HORIZONTAL", 1, 0.95, 0.75, 0.55, 1, 0.95, 0.75, 0)
local sweep = shineHolder:CreateAnimationGroup()
local move = sweep:CreateAnimation("Translation")
move:SetDuration(1.6)
move:SetSmoothing("IN_OUT")
sweep:SetScript("OnFinished", function()
    bar.shineWaiting = true
    C_Timer.After(6, function() bar.shineWaiting = nil; if Look().shine then sweep:Play() end end)
end)

-- goal reached: a soft gold halo pulses around the bar
local glowFrame = CreateFrame("Frame", nil, bar)
glowFrame:SetPoint("TOPLEFT", -3, 3)
glowFrame:SetPoint("BOTTOMRIGHT", 3, -3)
glowFrame:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
local glowTex = glowFrame:CreateTexture(nil, "BACKGROUND")
glowTex:SetAllPoints()
glowTex:SetColorTexture(1, 0.8, 0.25, 0.4)
glowFrame:Hide()
local glow = glowFrame:CreateAnimationGroup()
glow:SetLooping("BOUNCE")
local glowA = glow:CreateAnimation("Alpha")
glowA:SetFromAlpha(1)
glowA:SetToAlpha(0.15)
glowA:SetDuration(0.9)

-- coin and text, above everything
local over = CreateFrame("Frame", nil, bar)
over:SetAllPoints()
over:SetFrameLevel(sb:GetFrameLevel() + 5)
local coin = over:CreateTexture(nil, "OVERLAY")
coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
coin:SetPoint("LEFT", 4, 0)
local label = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("CENTER", 4, 0)
label:SetWordWrap(false)

-- the timeline of big moments (shown on hover, above all windows)
local timeline = CreateFrame("Frame", nil, bar)
timeline:SetAllPoints()
timeline:SetFrameStrata("TOOLTIP")
timeline:SetFrameLevel(200)
timeline:Hide()
local pool = {}

local hovered = false

-- the bar's length (along the fill) and thickness (across it, grown while
-- hovered with Grow on Hover), whichever way it stands
local function Dims()
    local l = Look()
    local vertical = l.vertical and true or false
    local long = vertical and l.height or l.width
    local thick = vertical and l.width or l.height
    if hovered and l.expand then thick = math.max(l.expandHeight, thick) end
    return vertical, long, thick
end

local function Arrange()
    local l = Look()
    local vertical, long, thick = Dims()
    if vertical then bar:SetSize(thick, long) else bar:SetSize(long, thick) end
    sb:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    -- shading runs across the bar: amber to bright gold, bottom to top when
    -- it lies down, left to right when it stands
    ns.Gradient(sb.grad, vertical and "HORIZONTAL" or "VERTICAL", 0.55, 0.36, 0.04, 1, 1, 0.86, 0.36, 1)

    local cs = math.max(8, math.min(thick - 6, 14))
    coin:SetSize(cs, cs)
    coin:ClearAllPoints()
    gloss:ClearAllPoints()
    shineHolder:ClearAllPoints()
    shineL:ClearAllPoints()
    shineR:ClearAllPoints()
    if vertical then
        coin:SetPoint("BOTTOM", 0, 4)
        -- gloss: a light band down the left side
        gloss:SetPoint("TOPLEFT", sb, "TOPLEFT")
        gloss:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT")
        gloss:SetWidth(math.max(1, (thick - 4) * 0.45))
        ns.Gradient(gloss, "HORIZONTAL", 1, 0.97, 0.85, 0.35, 1, 1, 1, 0)
        -- shine: sweeps up from below the bar
        shineHolder:SetSize(thick, 40)
        shineHolder:SetPoint("TOP", sb, "BOTTOM", 0, 0)
        shineL:SetPoint("BOTTOMLEFT"); shineL:SetPoint("BOTTOMRIGHT"); shineL:SetHeight(20)
        ns.Gradient(shineL, "VERTICAL", 1, 0.95, 0.75, 0, 1, 0.95, 0.75, 0.55)
        shineR:SetPoint("TOPLEFT"); shineR:SetPoint("TOPRIGHT"); shineR:SetHeight(20)
        ns.Gradient(shineR, "VERTICAL", 1, 0.95, 0.75, 0.55, 1, 0.95, 0.75, 0)
        move:SetOffset(0, long + 40)
    else
        coin:SetPoint("LEFT", 4, 0)
        gloss:SetPoint("TOPLEFT", sb, "TOPLEFT")
        gloss:SetPoint("TOPRIGHT", sb, "TOPRIGHT")
        gloss:SetHeight(math.max(1, (thick - 4) * 0.45))
        ns.Gradient(gloss, "VERTICAL", 1, 1, 1, 0, 1, 0.97, 0.85, 0.35)
        shineHolder:SetSize(40, thick)
        shineHolder:SetPoint("RIGHT", sb, "LEFT", 0, 0)
        shineL:SetPoint("TOPLEFT"); shineL:SetPoint("BOTTOMLEFT"); shineL:SetWidth(20)
        ns.Gradient(shineL, "HORIZONTAL", 1, 0.95, 0.75, 0, 1, 0.95, 0.75, 0.55)
        shineR:SetPoint("TOPRIGHT"); shineR:SetPoint("BOTTOMRIGHT"); shineR:SetWidth(20)
        ns.Gradient(shineR, "HORIZONTAL", 1, 0.95, 0.75, 0.55, 1, 0.95, 0.75, 0)
        move:SetOffset(long + 40, 0)
    end
    ns.ApplyFont(label, l.font, l.fontSize, "OUTLINE")
    label:SetShown(not vertical) -- no room for text on a standing bar
end

Refresh = function()
    if not DB then return end
    -- "Hide This Bar": gone outside Edit Mode, faded in it (looted coins
    -- then fly to your bag instead)
    local hidden = Look().hidden
    if hidden and not LEM:IsInEditMode() then
        bar:Hide()
        return
    end
    bar:Show()
    bar:SetAlpha(hidden and 0.4 or 1)
    Arrange()
    local money = GetMoney()
    if not Num(money) then money = 0 end
    local goal = Goal()
    sb:SetMinMaxValues(0, goal)
    sb:SetValue(math.min(money, goal))
    local pct = math.floor(money / goal * 100)
    local l = Look()
    if l.text == "money" then
        label:SetText(ns.Money(money))
    elseif l.text == "pct" then
        label:SetText(pct .. "%")
    elseif l.text == "none" then
        label:SetText("")
    else
        label:SetText(ns.Money(money) .. "  /  " .. ns.Money(goal, true) .. "   " .. math.min(pct, 999) .. "%")
    end
    -- goal reached
    if money >= goal then
        rim:SetColorTexture(1, 0.85, 0.35, 1)
        glowFrame:Show()
        if not glow:IsPlaying() then glow:Play() end
    else
        rim:SetColorTexture(0.75, 0.58, 0.2, 1)
        glow:Stop()
        glowFrame:Hide()
    end
    if l.shine and not sweep:IsPlaying() and not bar.shineWaiting then
        bar.shineWaiting = true
        C_Timer.After(2, function() bar.shineWaiting = nil; if Look().shine then sweep:Play() end end)
    elseif not l.shine then
        sweep:Stop()
    end
end

---------------------------------------------------------------------------
-- Hover: grow, timeline of big moments, tooltip
---------------------------------------------------------------------------
local function Parts(i)
    local p = pool[i]
    if p then return p end
    p = {
        pin = timeline:CreateTexture(nil, "OVERLAY"),
        lead = timeline:CreateTexture(nil, "OVERLAY"),
        rise = timeline:CreateTexture(nil, "OVERLAY"), -- standing bar: the bend up or down to a nudged label
        icon = timeline:CreateTexture(nil, "OVERLAY"),
        text = timeline:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
    }
    p.text:SetShadowOffset(1, -1)
    pool[i] = p
    return p
end

local function ShowTimeline()
    local events = Char().events
    local goal = Goal()
    -- sizes from the settings (the bar was just resized; its rect may not
    -- have caught up yet)
    local l = Look()
    local vertical, long, thick = Dims()
    local w = long - 4  -- along the fill
    local h = thick - 4 -- across it
    local size = math.max(8, l.fontSize - 1)
    -- sort by position along the bar
    local items = {}
    for _, e in ipairs(events) do
        items[#items + 1] = { e = e, x = w * math.min(e.money / goal, 1) }
    end
    table.sort(items, function(a, b) return a.x < b.x end)
    local n = 0

    if vertical then
        -- standing bar: a line across it at each moment, the label to its
        -- right; labels that would overlap are nudged up, the leader bending
        -- to reach them, and those that run past the top are left to the
        -- tooltip
        local gap = size + 5
        local OUT, BEND = 6, 4
        local last
        for _, it in ipairs(items) do
            local ly = last and math.max(it.x, last + gap) or it.x
            if ly > w + gap then break end
            last = ly
            n = n + 1
            local p = Parts(n)
            local e = it.e
            p.pin:SetColorTexture(1, 0.95, 0.7, 0.9)
            p.pin:ClearAllPoints()
            p.pin:SetSize(h, 1)
            p.pin:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, it.x)
            p.lead:SetColorTexture(1, 0.85, 0.4, 0.7)
            p.lead:ClearAllPoints()
            p.lead:SetSize(OUT, 1)
            p.lead:SetPoint("BOTTOMLEFT", sb, "BOTTOMRIGHT", 2, it.x)
            p.rise:SetColorTexture(1, 0.85, 0.4, 0.7)
            p.rise:ClearAllPoints()
            if math.abs(ly - it.x) >= 1 then
                p.rise:SetSize(1, math.abs(ly - it.x) + 1)
                p.rise:SetPoint("BOTTOMLEFT", sb, "BOTTOMRIGHT", 2 + OUT, math.min(it.x, ly))
                p.rise:Show()
            else
                p.rise:Hide()
            end
            p.icon:SetTexture(e.icon or ns.Icon(KIND_ICON[e.kind] or "INV_Misc_Coin_01"))
            p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            p.icon:ClearAllPoints()
            p.icon:SetSize(size + 2, size + 2)
            p.icon:SetPoint("LEFT", sb, "BOTTOMRIGHT", 2 + OUT + BEND, ly)
            ns.ApplyFont(p.text, l.font, size, "OUTLINE")
            p.text:SetText("+" .. ns.ShortMoney(e.amount))
            p.text:ClearAllPoints()
            p.text:SetPoint("LEFT", p.icon, "RIGHT", 2, 0)
            p.text:SetTextColor(1, 0.86, 0.4)
            p.pin:Show(); p.lead:Show(); p.icon:Show(); p.text:Show()
        end
        for i = n + 1, #pool do
            local p = pool[i]
            p.pin:Hide(); p.lead:Hide(); p.rise:Hide(); p.icon:Hide(); p.text:Hide()
        end
        timeline:Show()
        return
    end

    -- lying bar: each label gets a row above the bar where it fits, up to
    -- three rows (more go in the tooltip only)
    local rowEnd = { -1e9, -1e9, -1e9 }
    for _, it in ipairs(items) do
        local p = Parts(n + 1)
        local e = it.e
        local text = "+" .. ns.ShortMoney(e.amount)
        ns.ApplyFont(p.text, l.font, size, "OUTLINE")
        p.text:SetText(text)
        local width = p.text:GetStringWidth() + size + 6
        local row
        for r = 1, 3 do
            if it.x - width / 2 > rowEnd[r] + 4 then row = r; break end
        end
        if row then
            n = n + 1
            rowEnd[row] = it.x + width / 2
            local y = h + 4 + (row - 1) * (size + 6)
            p.pin:SetColorTexture(1, 0.95, 0.7, 0.9)
            p.pin:ClearAllPoints()
            p.pin:SetSize(1, h)
            p.pin:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", it.x, 0)
            p.lead:SetColorTexture(1, 0.85, 0.4, 0.7)
            p.lead:ClearAllPoints()
            p.lead:SetSize(1, y - h + 2)
            p.lead:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", it.x, h)
            p.icon:SetTexture(e.icon or ns.Icon(KIND_ICON[e.kind] or "INV_Misc_Coin_01"))
            p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            p.icon:ClearAllPoints()
            p.icon:SetSize(size + 2, size + 2)
            p.icon:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", it.x - width / 2, y)
            p.text:ClearAllPoints()
            p.text:SetPoint("LEFT", p.icon, "RIGHT", 2, 0)
            p.text:SetTextColor(1, 0.86, 0.4)
            p.pin:Show(); p.lead:Show(); p.rise:Hide(); p.icon:Show(); p.text:Show()
        else
            p.text:Hide()
        end
    end
    for i = n + 1, #pool do
        local p = pool[i]
        p.pin:Hide(); p.lead:Hide(); p.rise:Hide(); p.icon:Hide(); p.text:Hide()
    end
    timeline:Show()
end

local function Tooltip(self)
    if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else GameTooltip:SetOwner(self, "ANCHOR_TOP") end
    local money, goal = GetMoney(), Goal()
    GameTooltip:AddLine("Gold", 1, 0.82, 0)
    GameTooltip:AddDoubleLine("You have", ns.Money(money), 1, 0.82, 0, 1, 1, 1)
    if money < goal then
        GameTooltip:AddDoubleLine("Goal", ns.Money(goal) .. "  (" .. ns.Money(goal - money) .. " to go)", 1, 0.82, 0, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("Goal", ns.Money(goal) .. "  reached!", 1, 0.82, 0, 0.4, 1, 0.4)
    end
    local day = Today()
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Today", "+" .. ns.Money(day.gained) .. "   -" .. ns.Money(day.spent), 1, 0.82, 0, 1, 1, 1)
    local hours = (GetTime() - session.at) / 3600
    local rate = hours > 0.05 and (session.gained - session.spent) / hours or nil
    GameTooltip:AddDoubleLine("This session", "+" .. ns.Money(session.gained) .. "   -" .. ns.Money(session.spent),
        1, 0.82, 0, 1, 1, 1)
    if rate then
        GameTooltip:AddDoubleLine("Per hour", (rate >= 0 and "+" or "-") .. ns.Money(rate), 1, 0.82, 0, 1, 1, 1)
        if rate > 0 and money < goal then
            local left = (goal - money) / rate * 3600
            local t = left < 3600 and (math.floor(left / 60) .. "m")
                or (math.floor(left / 3600) .. "h " .. math.floor(left % 3600 / 60) .. "m")
            GameTooltip:AddDoubleLine("Goal at this pace", "~" .. t, 1, 0.82, 0, 1, 1, 1)
        end
    end
    -- records
    local c = Char()
    local recs = {}
    for kind, r in pairs(c.records) do
        if KIND_LABEL[kind] and r.amount >= BIG_FLOOR then recs[#recs + 1] = { kind = kind, r = r } end
    end
    table.sort(recs, function(a, b) return a.r.amount > b.r.amount end)
    if #recs > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Records", 1, 0.82, 0)
        for i = 1, math.min(#recs, 4) do
            local x = recs[i]
            GameTooltip:AddDoubleLine("   Biggest " .. KIND_LABEL[x.kind]:lower(),
                ns.Money(x.r.amount) .. (x.r.text and ("  " .. x.r.text) or ""), 1, 0.9, 0.6, 1, 1, 1)
        end
    end
    -- latest big moments
    local ev = c.events
    if #ev > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Big moments", 1, 0.82, 0)
        for i = #ev, math.max(1, #ev - 5), -1 do
            local e = ev[i]
            GameTooltip:AddDoubleLine("   " .. date("%b %d", e.t) .. "  " .. (KIND_LABEL[e.kind] or e.kind)
                .. (e.text and (": " .. e.text) or ""), "+" .. ns.Money(e.amount), 1, 0.9, 0.6, 1, 1, 1)
        end
    end
    if ns.ToggleMoneyBook and ns.Opt("goldClick") then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click: Money Book", 0.5, 0.8, 1)
    end
    GameTooltip:Show()
end

-- a click opens the Money Book (the SpliffGold module sets ns.ToggleMoneyBook)
if bar.SetMouseClickEnabled then bar:SetMouseClickEnabled(true) end
bar:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and ns.Opt("goldClick") and ns.ToggleMoneyBook and not LEM:IsInEditMode() then
        ns.ToggleMoneyBook()
    end
end)

bar:SetScript("OnEnter", function(self)
    hovered = true
    Refresh()
    ShowTimeline()
    Tooltip(self)
end)
bar:SetScript("OnLeave", function()
    hovered = false
    timeline:Hide()
    GameTooltip:Hide()
    Refresh()
end)

---------------------------------------------------------------------------
-- Goal
---------------------------------------------------------------------------
-- "250", "250g", "250g 50s", "1.5k" -> copper
local function ParseGold(text)
    text = (text or ""):lower():gsub(",", "")
    local total, any = 0, false
    for num, unit in text:gmatch("([%d%.]+)%s*([gsck]?)") do
        local v = tonumber(num)
        if v then
            any = true
            if unit == "s" then total = total + v * 100
            elseif unit == "c" then total = total + v
            elseif unit == "k" then total = total + v * 1000 * 10000
            else total = total + v * 10000 end
        end
    end
    if not any or total <= 0 then return nil end
    return math.floor(total + 0.5)
end

local function SetGoal(text)
    local goal = ParseGold(text)
    if not goal then
        print(ns.PREFIX .. "that isn't a gold amount; try 250 or 250g 50s.")
        return
    end
    DB.goal = goal
    print(ns.PREFIX .. "gold goal: " .. ns.Money(goal))
    Refresh()
end

StaticPopupDialogs["SPLIFFBARS_GOLD_GOAL"] = {
    text = "Your gold goal (for example 250, or 250g 50s):",
    button1 = OKAY or "Okay",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
        if eb then eb:SetText(ns.Money(Goal(), true)); eb:HighlightText() end
    end,
    OnAccept = function(self)
        local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
        if eb then SetGoal(eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        SetGoal(self:GetText())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------
local function Place()
    local l = Look()
    bar:ClearAllPoints()
    local p = l.point and l or DEFAULT_POS
    bar:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

LEM:AddFrame(bar, function(_, layout, point, x, y)
    layoutName = layout
    local l = Look()
    l.point, l.x, l.y = point, x, y
end, DEFAULT_POS, bar.editModeName)

local function Setting(kind, name, field, extra)
    local s = {
        kind = kind, name = name, default = DEFAULTS[field],
        get = function(layout) layoutName = layout; return Look()[field] end,
        set = function(layout, value) layoutName = layout; Look()[field] = value; Refresh() end,
    }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

LEM:AddFrameSettings(bar, {
    Setting(LEM.SettingType.Checkbox, "Hide This Bar", "hidden", {
        desc = "Gone outside Edit Mode; shown faded here so you can bring it back.",
    }),
    Setting(LEM.SettingType.Checkbox, "Vertical", "vertical", {
        -- standing it up swaps width and height, so it keeps its shape
        set = function(layout, value)
            layoutName = layout
            local l = Look()
            if (l.vertical and true or false) ~= value then l.width, l.height = l.height, l.width end
            l.vertical = value
            Refresh()
            pcall(LEM.RefreshFrameSettings, LEM, bar) -- greys Text in and out
        end,
    }),
    Setting(LEM.SettingType.Slider, "Width", "width", { minValue = 6, maxValue = 1000, valueStep = 1 }),
    Setting(LEM.SettingType.Slider, "Height", "height", { minValue = 6, maxValue = 1000, valueStep = 1 }),
    Setting(LEM.SettingType.Checkbox, "Grow on Hover", "expand"),
    Setting(LEM.SettingType.Slider, "Hover Thickness", "expandHeight", {
        minValue = 12, maxValue = 160, valueStep = 1, disabled = function() return not Look().expand end,
    }),
    Setting(LEM.SettingType.Dropdown, "Text (hidden when vertical)", "text", { values = {
        { text = "Gold / goal / %", value = "goal" }, { text = "Gold", value = "money" },
        { text = "%", value = "pct" }, { text = "None", value = "none" },
    }, disabled = function() return Look().vertical end }),
    Setting(LEM.SettingType.Dropdown, "Font", "font", { values = ns.FontChoices, height = 300 }),
    Setting(LEM.SettingType.Slider, "Font Size", "fontSize", { minValue = 6, maxValue = 24, valueStep = 1 }),
    Setting(LEM.SettingType.Checkbox, "Shine", "shine"),
    Setting(LEM.SettingType.Slider, "Big Moment (% of goal)", "bigPct", {
        minValue = 1, maxValue = 25, valueStep = 1, formatter = function(v) return math.floor(v + 0.5) .. "%" end,
    }),
})
LEM:AddFrameSettingsButton(bar, { text = "Set Gold Goal...", click = function() StaticPopup_Show("SPLIFFBARS_GOLD_GOAL") end })
LEM:AddFrameSettingsButton(bar, { text = "Reset Session", click = function()
    session = { at = GetTime(), gained = 0, spent = 0 }
    print(ns.PREFIX .. "gold session reset.")
end })

LEM:RegisterCallback("layout", function(layout)
    layoutName = layout
    Place()
    Refresh()
end)
-- a hidden bar shows (faded) while in Edit Mode
LEM:RegisterCallback("enter", function() Refresh() end)
LEM:RegisterCallback("exit", function() Refresh() end)

ns.SetGoldGoal = function(text) if DB then SetGoal(text) end end

-- for the options panel (Options.lua)
ns.RegisterPiece({
    name = "Gold Bar",
    get = function() return DB and Look().hidden or false end,
    set = function(hidden)
        if not DB then return end
        Look().hidden = hidden
        Refresh()
        pcall(LEM.RefreshFrameSettings, LEM, bar)
    end,
})
ns.AskGoldGoal = function() StaticPopup_Show("SPLIFFBARS_GOLD_GOAL") end

-- looted coins landing in the bar (Loot.lua): the shine sweeps across
-- right away and the coin icon pops
local coinPop = coin:CreateAnimationGroup()
local pop1 = coinPop:CreateAnimation("Scale")
pop1:SetScale(1.5, 1.5); pop1:SetDuration(0.12); pop1:SetOrder(1); pop1:SetSmoothing("OUT")
local pop2 = coinPop:CreateAnimation("Scale")
pop2:SetScale(1 / 1.5, 1 / 1.5); pop2:SetDuration(0.25); pop2:SetOrder(2); pop2:SetSmoothing("IN")
ns.GoldShine = function()
    sweep:Stop()
    sweep:Play()
    coinPop:Stop()
    coinPop:Play()
end

---------------------------------------------------------------------------
-- Looted coins (ns.GoldHop, from Loot.lua): a few little coins hop up out
-- of the bar at spots along the gold you have, each drifting a little
-- along it, and drop back in with a tiny ring and sparkles. Gold, silver
-- and copper coins for what you looted. Once they've all landed the shine
-- sweeps across. On a standing bar they hop out to its right.
---------------------------------------------------------------------------
local COIN_TEX = {
    gold = "Interface\\MoneyFrame\\UI-GoldIcon",
    silver = "Interface\\MoneyFrame\\UI-SilverIcon",
    copper = "Interface\\MoneyFrame\\UI-CopperIcon",
}
local COIN_TINT = { gold = { 1, 0.85, 0.35 }, silver = { 0.85, 0.9, 1 }, copper = { 1, 0.6, 0.35 } }
local RING = "Interface\\Cooldown\\ping4"

local hopLayer = CreateFrame("Frame", nil, bar)
hopLayer:SetAllPoints(sb)
hopLayer:SetFrameStrata("HIGH") -- above the bar and whatever's next to it
local hoppers = {}

local function Hopper()
    for _, h in ipairs(hoppers) do
        if not h.busy then return h end
    end
    local h = CreateFrame("Frame", nil, hopLayer)
    h:SetSize(13, 13)
    h:Hide()
    h.tex = h:CreateTexture(nil, "OVERLAY")
    h.tex:SetAllPoints()
    h.ring = hopLayer:CreateTexture(nil, "OVERLAY")
    h.ring:SetTexture(RING)
    h.ring:SetBlendMode("ADD")
    h.ring:SetSize(14, 14)
    h.ring:Hide()
    h.ringAnim = h.ring:CreateAnimationGroup()
    local grow = h.ringAnim:CreateAnimation("Scale")
    grow:SetScale(2.2, 2.2)
    grow:SetDuration(0.35)
    grow:SetSmoothing("OUT")
    local fade = h.ringAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.9)
    fade:SetToAlpha(0)
    fade:SetDuration(0.35)
    h.ringAnim:SetScript("OnFinished", function() h.ring:Hide() end)
    hoppers[#hoppers + 1] = h
    return h
end

-- where a coin is: "along" the bar from its start, "up" out of it
local function PlaceHop(region, h, along, up)
    region:ClearAllPoints()
    if h.vertical then
        region:SetPoint("CENTER", sb, "BOTTOM", up, along)
    else
        region:SetPoint("CENTER", sb, "LEFT", along, up)
    end
end

local function Burst(h, n, size)
    if not ns.Sparkle then return end
    local x, y = h:GetCenter()
    if not x then return end
    local k = h:GetEffectiveScale() / UIParent:GetEffectiveScale()
    x, y = x * k, y * k
    local c = h.tint
    for i = 1, n do
        local a = (i / n) * 2 * math.pi + math.random() * 0.6
        local d = 6 + math.random() * 8
        ns.Sparkle(x, y, c[1], c[2], c[3], size + math.random() * 4, 0.3 + math.random() * 0.2,
            math.cos(a) * d, math.sin(a) * d)
    end
end

local function HopStep(h, elapsed)
    h.t = h.t + elapsed / h.dur
    local t = math.min(h.t, 1)
    -- a hop: straight up and back down, drifting along the bar
    local along = h.a0 + (h.a1 - h.a0) * t
    local up = h.peak * 4 * t * (1 - t)
    PlaceHop(h, h, along, up)
    -- pops in quick, sinks a little smaller as it drops back in
    local size = h.size * (0.45 + 0.55 * math.min(1, t * 5)) * (t > 0.8 and (1 - (t - 0.8) * 1.75) or 1)
    h:SetSize(size, size)
    if h.tex.SetRotation then h.tex:SetRotation(h.spin * t) end
    h:SetAlpha(t > 0.9 and (1 - (t - 0.9) * 6) or 1)
    if h.t < 1 then return end

    -- landed: a little ring, a few sparkles, and once the last is in, the shine
    h:SetScript("OnUpdate", nil)
    PlaceHop(h.ring, h, h.a1, 0)
    local c = h.tint
    h.ring:SetVertexColor(c[1], c[2], c[3])
    h.ringAnim:Stop()
    h.ring:Show()
    h.ringAnim:Play()
    Burst(h, 4, 4)
    h:Hide()
    h.busy = false
    local batch = h.batch
    batch.left = batch.left - 1
    if batch.left == 0 then ns.GoldShine() end
end

-- the coins for a loot line like "1 Gold 12 Silver 3 Copper" (the game's
-- own wording, so any language): more coins for the bigger kinds
local function Amount(text, fmt)
    if type(text) ~= "string" or type(fmt) ~= "string" then return nil end
    local pattern = (fmt:gsub("%%d", "(%%d+)"))
    return tonumber(text:match(pattern))
end

local function CoinKinds(text)
    local g, s, c = Amount(text, GOLD_AMOUNT), Amount(text, SILVER_AMOUNT), Amount(text, COPPER_AMOUNT)
    local kinds = {}
    local function Add(kind, n) for _ = 1, n do kinds[#kinds + 1] = kind end end
    if g then Add("gold", 3) end
    if s then Add("silver", g and 1 or 2) end
    if c then Add("copper", (g or s) and 1 or 2) end
    if #kinds == 0 then Add("silver", 2); Add("copper", 1) end
    while #kinds > 5 do table.remove(kinds) end
    return kinds
end

-- false when the bar isn't showing (the coins fly to your bag instead)
ns.GoldHop = function(text)
    if not bar:IsVisible() then return false end
    local vertical, long = Dims()
    local length = long - 4
    local money = GetMoney()
    local fill = Num(money) and math.min(money / Goal(), 1) or 1
    -- they hop out of the gold you have (or the start of the bar, when it's
    -- nearly empty), and drift up to a couple of coins' width either way
    local reach = math.max(0.15, fill) * length
    local kinds = CoinKinds(text)
    local batch = { left = #kinds }
    for i, kind in ipairs(kinds) do
        local h = Hopper()
        h.busy = true
        h.batch = batch
        h.vertical = vertical
        h.a0 = reach * (0.06 + math.random() * 0.88)
        h.a1 = math.max(4, math.min(length - 4, h.a0 + (math.random() - 0.5) * 56))
        h.peak = 16 + math.random() * 18
        h.dur = 0.55 + math.random() * 0.25
        h.spin = (math.random() - 0.5) * 5
        h.size = 13
        h.tint = COIN_TINT[kind]
        h.tex:SetTexture(COIN_TEX[kind])
        h.t = 0
        C_Timer.After((i - 1) * 0.09, function()
            PlaceHop(h, h, h.a0, 0)
            h:SetSize(h.size * 0.45, h.size * 0.45)
            h:SetAlpha(1)
            h:Show()
            Burst(h, 2, 3) -- a glint where it leaves the bar
            h:SetScript("OnUpdate", HopStep)
        end)
    end
    return true
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
local OPENS = {
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
    AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
    TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
    TRAINER_SHOW = { "trainer", true }, TRAINER_CLOSED = { "trainer", false },
    TAXIMAP_OPENED = { "taxi", true }, TAXIMAP_CLOSED = { "taxi", false },
}
for e in pairs(OPENS) do pcall(events.RegisterEvent, events, e) end
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "CHAT_MSG_MONEY",
    "QUEST_TURNED_IN", "QUEST_COMPLETE" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "ADDON_LOADED" then
        if a1 == "Spliffbars" then
            SpliffbarsGoldDB = SpliffbarsGoldDB or {}
            DB = SpliffbarsGoldDB
        end
        return
    end
    if not DB then return end
    local o = OPENS[event]
    if o then
        -- the flag drops a moment after closing, so a payment that lands
        -- just after the window shuts still counts
        if o[2] then open[o[1]] = true else C_Timer.After(1, function() open[o[1]] = false end) end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        if not lastMoney then lastMoney = GetMoney() end
        Place()
        Refresh()
    elseif event == "PLAYER_MONEY" then
        OnMoney()
    elseif event == "CHAT_MSG_MONEY" then
        recentLootAt = GetTime()
    elseif event == "QUEST_COMPLETE" then
        local ok, t = pcall(GetTitleText)
        if ok and type(t) == "string" and not isSecret(t) then lastQuestTitle = t end
    elseif event == "QUEST_TURNED_IN" then
        -- a1 questID, a2 XP, a3 money
        local name = lastQuestTitle
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local ok, n = pcall(C_QuestLog.GetTitleForQuestID, a1)
            if ok and type(n) == "string" and not isSecret(n) and n ~= "" then name = n end
        end
        recentQuest = { name = name, money = a3, at = GetTime() }
    end
end)
