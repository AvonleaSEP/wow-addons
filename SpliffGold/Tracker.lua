-- Spliff Gold: the tracker.
-- Works out where each money change came from or went, the way Accountant
-- Classic does it (Core/Core.lua and Core/Constants.lua, v2.30.03, by arith
-- and kamusis, GPLv2; see LICENSE and NOTICE.md): the window you have open
-- when the money changes picks the category (a merchant, the mailbox, the
-- trainer ...), with a few special cases:
--   - repairs: repair mode at a merchant, or Repair All;
--   - the mailbox: an auction house invoice makes it Auction House;
--   - shared and solo loot: the chat message's amount is logged as Loot;
--   - bank bag slots: Bank;
--   - money that changed while the game was closed (another addon setup,
--     another computer): Other, marked as untracked.
--
-- Every change goes to:
--   SpliffGoldHistory           the ledger (History.lua): day, hour, zone, recent list
--   SpliffGoldDB.life[char]     all-time totals per category
--   SpliffGoldDB.zones[char]    all-time totals per zone and category
--   the session table           since you logged in (not saved)
--
-- The first time it loads with Accountant Classic installed, it copies your
-- Accountant Classic data in (Import below).

local _, ns = ...
local S = Spliffbars -- the hub (Spliffbars\Core.lua)
local History = ns.History
local issecretvalue = _G.issecretvalue

local function Usable(v)
    if issecretvalue and issecretvalue(v) then return false end
    return type(v) == "number"
end

local function Str(v)
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) == "string" and v ~= "" then return v end
end

---------------------------------------------------------------------------
-- Categories, in the order the Money Book lists them
---------------------------------------------------------------------------
local CATEGORIES = {
    { key = "LOOT",    label = "Loot",           icon = "INV_Misc_Bag_10",           color = { 1, 0.82, 0 } },
    { key = "QUEST",   label = "Quests",         icon = "INV_Misc_Note_01",          color = { 1, 0.65, 0.2 } },
    { key = "MERCH",   label = "Merchants",      icon = "INV_Misc_Coin_01",          color = { 0.45, 0.85, 0.45 } },
    { key = "AH",      label = "Auction House",  icon = "INV_Hammer_15",             color = { 0.4, 0.7, 1 } },
    { key = "MAIL",    label = "Mail",           icon = "INV_Letter_15",             color = { 0.75, 0.6, 1 } },
    { key = "TRADE",   label = "Trades",         icon = "INV_Misc_Coin_02",          color = { 0.3, 0.9, 0.85 } },
    { key = "TAXI",    label = "Flights",        icon = "Ability_Mount_Gryphon_01",  color = { 0.55, 0.75, 0.95 } },
    { key = "TRAIN",   label = "Training",       icon = "INV_Misc_Book_09",          color = { 0.95, 0.45, 0.8 } },
    { key = "REPAIRS", label = "Repairs",        icon = "Trade_BlackSmithing",       color = { 0.95, 0.35, 0.3 } },
    { key = "BANK",    label = "Bank",           icon = "INV_Misc_Bag_07",           color = { 0.7, 0.55, 0.35 } },
    { key = "GUILD",   label = "Guild Bank",     icon = "INV_Shirt_GuildTabard_01",  color = { 0.35, 0.95, 0.35 } },
    { key = "BARBER",  label = "Barber",         icon = "INV_Misc_Comb_01",          color = { 0.9, 0.7, 0.55 } },
    { key = "TRANSMO", label = "Transmog",       icon = "INV_Chest_Cloth_17",        color = { 0.8, 0.5, 1 } },
    { key = "LFG",     label = "Dungeon Finder", icon = "INV_Misc_GroupNeedMore",    color = { 0.5, 0.8, 0.6 } },
    { key = "OTHER",   label = "Other",          icon = "INV_Misc_QuestionMark",     color = { 0.6, 0.6, 0.66 } },
}
local BY_KEY = {}
for i, c in ipairs(CATEGORIES) do c.order = i; BY_KEY[c.key] = c end
ns.CATEGORIES = CATEGORIES

-- the category's display info; unknown keys (WARBAND, GARRISON from other
-- clients' data) get a plain entry
function ns.Category(key)
    local c = BY_KEY[key]
    if not c then
        c = { key = key, label = key:sub(1, 1) .. key:sub(2):lower(), icon = "INV_Misc_Coin_03",
            color = { 0.6, 0.6, 0.66 }, order = 99 }
        BY_KEY[key] = c
    end
    return c
end

---------------------------------------------------------------------------
-- Who you are (the same keys as Accountant Classic, so its data lines up)
---------------------------------------------------------------------------
local SERVER, PLAYER, CHAR

-- Forever names have a first and a second part ("Spliff" "Rite"):
-- Accountant Classic stores them as "Spliff-Rite"
local function PlayerKey()
    local first, second = UnitName("player")
    first = Str(first) or "?"
    second = Str(second)
    if second then return first .. "-" .. second end
    return first
end

function ns.CharKey() return CHAR end
function ns.Server() return SERVER end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local DB
local session = {} -- [cat] = { i, o }

local function Bucket(t, key)
    local b = t[key]
    if not b then b = { i = 0, o = 0 }; t[key] = b end
    return b
end

local function Add(b, diff)
    if diff > 0 then b.i = b.i + diff else b.o = b.o - diff end
end

function ns.DB() return DB end
function ns.Session() return session end

-- the zone a change is filed under in the all-time zone list
local function ZoneName()
    local z = Str(GetZoneText and GetZoneText())
    return z or "Unknown"
end

---------------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------------
local logType = ""      -- the category the next money change goes to
local lastMoney         -- the balance at the last logged change
local untrackedNext     -- the next log is the change found at login
local refreshers = {}   -- the Money Book redraws on these

function ns.OnChange(fn) refreshers[#refreshers + 1] = fn end

local function Log(diff, money)
    if not DB or not Usable(diff) or diff == 0 then return end
    local cat = logType
    if cat == "" or not BY_KEY[cat] then cat = "OTHER" end
    local untracked = untrackedNext
    untrackedNext = nil

    if not untracked then Add(Bucket(session, cat), diff) end
    local life = DB.life[CHAR]
    if not life then life = {}; DB.life[CHAR] = life end
    Add(Bucket(life, cat), diff)
    if not untracked then
        local zones = DB.zones[CHAR]
        if not zones then zones = {}; DB.zones[CHAR] = zones end
        local z = zones[ZoneName()]
        if not z then z = {}; zones[ZoneName()] = z end
        Add(Bucket(z, cat), diff)
    end
    -- the ledger must never break the totals above
    pcall(History.Record, History, SERVER, PLAYER, cat, diff, money, untracked)

    -- (Accountant Classic: once a repair is logged you're back to buying and selling)
    if logType == "REPAIRS" then logType = "MERCH" end
    for _, fn in ipairs(refreshers) do pcall(fn) end
end

-- logs the difference since the last logged balance
local function Update()
    local money = GetMoney()
    if not Usable(money) then return end
    if not lastMoney then lastMoney = money return end
    local diff = money - lastMoney
    lastMoney = money
    if diff ~= 0 then Log(diff, money) end
end

---------------------------------------------------------------------------
-- Loot messages ("You loot 1 Gold, 2 Silver"): Accountant Classic's
-- parser, built from the client's own coin strings
---------------------------------------------------------------------------
local function CoinPattern(fmt)
    if type(fmt) ~= "string" or not fmt:find("%d", 1, true) or fmt:find("|4", 1, true) then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%d", "(%%d+)")
    return p
end

local COINS = {}
for _, info in ipairs({
    { global = "GOLD_AMOUNT",   fallback = "(%d+) Gold",   value = 10000 },
    { global = "SILVER_AMOUNT", fallback = "(%d+) Silver", value = 100 },
    { global = "COPPER_AMOUNT", fallback = "(%d+) Copper", value = 1 },
}) do
    local patterns = {}
    local p = CoinPattern(_G[info.global])
    if p then patterns[#patterns + 1] = p end
    if info.fallback ~= p then patterns[#patterns + 1] = info.fallback end
    COINS[#COINS + 1] = { patterns = patterns, value = info.value }
end

local function ParseMoney(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return 0 end
    local money = 0
    for _, coin in ipairs(COINS) do
        for _, pattern in ipairs(coin.patterns) do
            local amount = msg:match(pattern)
            if amount then
                money = money + (tonumber(amount) or 0) * coin.value
                break
            end
        end
    end
    return money
end

local pendingLoot -- GetTime() of a loot message we couldn't read
local PENDING_LOOT_WINDOW = 2

local function OnLootMoney(msg)
    if logType == "LOOT" or not lastMoney then return end
    local old = logType
    local money = GetMoney()
    -- the balance already has it: log the real difference as loot now
    if Usable(money) and money ~= lastMoney then
        pendingLoot = nil
        logType = "LOOT"
        Update()
        logType = old
        return
    end
    local amount = ParseMoney(msg)
    if amount <= 0 then
        -- couldn't read it: the PLAYER_MONEY just after counts as loot
        pendingLoot = GetTime()
        return
    end
    -- log the amount now, and step the baseline so the PLAYER_MONEY that
    -- follows finds nothing left to log
    lastMoney = lastMoney - amount
    logType = "LOOT"
    Update()
    logType = old
    lastMoney = lastMoney + amount
end

---------------------------------------------------------------------------
-- What's open (Accountant Classic's eventLogTypes; "" = nothing special)
---------------------------------------------------------------------------
local EVENT_TYPES = {
    GUILDBANKFRAME_OPENED = "GUILD", GUILDBANK_UPDATE_MONEY = "GUILD",
    GUILDBANK_UPDATE_WITHDRAWMONEY = "GUILD", GUILDBANKFRAME_CLOSED = "",
    LFG_COMPLETION_REWARD = "LFG",
    BARBER_SHOP_OPEN = "BARBER", BARBER_SHOP_RESULT = "BARBER",
    BARBER_SHOP_FORCE_CUSTOMIZATIONS_UPDATE = "BARBER", BARBER_SHOP_COST_UPDATE = "BARBER",
    BARBER_SHOP_APPEARANCE_APPLIED = "", BARBER_SHOP_CLOSE = "",
    TRANSMOGRIFY_OPEN = "TRANSMO", TRANSMOGRIFY_CLOSE = "",
    MERCHANT_SHOW = "MERCH", MERCHANT_CLOSED = "",
    TAXIMAP_OPENED = "TAXI",
    LOOT_OPENED = "LOOT",
    TRADE_SHOW = "TRADE", TRADE_CLOSED = "",
    QUEST_COMPLETE = "QUEST", QUEST_TURNED_IN = "QUEST",
    TRAINER_SHOW = "TRAIN", TRAINER_CLOSED = "", CONFIRM_TALENT_WIPE = "TRAIN",
    AUCTION_HOUSE_SHOW = "AH", AUCTION_HOUSE_CLOSED = "",
    BANKFRAME_OPENED = "BANK", BANKFRAME_CLOSED = "",
}

-- (codes by Tntdruid, via Accountant Classic) a sale invoice in the inbox
local function AuctionMail()
    if not (GetInboxNumItems and GetInboxInvoiceInfo) then return false end
    local ok, _, total = pcall(GetInboxNumItems)
    if not ok or not Usable(total) then return false end
    for i = 1, total do
        local ok2, kind = pcall(GetInboxInvoiceInfo, i)
        if ok2 and kind == "seller" then return true end
    end
    return false
end

local BANK_INTERACTIONS = {}
do
    local types = Enum and Enum.PlayerInteractionType
    if types then
        for _, name in ipairs({ "Banker", "AccountBanker", "CharacterBanker" }) do
            if types[name] then BANK_INTERACTIONS[types[name]] = true end
        end
    end
end

local function InRepair()
    return (InRepairMode and InRepairMode()) and true or false
end

---------------------------------------------------------------------------
-- Import from Accountant Classic
---------------------------------------------------------------------------
local function Copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = Copy(v) end
    return out
end

-- "Stormwind City - Trade District" -> "Stormwind City"
local function ZoneOnly(text)
    return (text:match("^(.-) %- ") or text)
end

function ns.AccountantPresent()
    return type(_G.Accountant_ClassicSaveData) == "table" or type(_G.Accountant_ClassicHistory) == "table"
end

-- replaces Spliff Gold's history, lifetime and zone totals with Accountant
-- Classic's (keeps the settings). Returns the number of characters brought in.
local function Import()
    local save = _G.Accountant_ClassicSaveData
    local zoneDB = _G.Accountant_ClassicZoneDB
    local hist = _G.Accountant_ClassicHistory
    if type(save) ~= "table" and type(hist) ~= "table" then return 0 end

    -- the ledger, as it is
    if type(hist) == "table" and type(hist.chars) == "table" then
        local copy = Copy(hist)
        copy.settings = (SpliffGoldHistory and SpliffGoldHistory.settings) or copy.settings
        SpliffGoldHistory = copy
    end
    History:InitDB()
    local db = History:GetDB()

    DB.life, DB.zones = {}, {}
    local count = 0
    if type(save) == "table" then
        for server, chars in pairs(save) do
            if type(chars) == "table" then
                for name, c in pairs(chars) do
                    if type(c) == "table" and type(c.data) == "table" then
                        count = count + 1
                        local key = History.CharKey(server, name)
                        -- all-time totals per category
                        local life = {}
                        for cat, periods in pairs(c.data) do
                            local t = type(periods) == "table" and periods.Total
                            if type(t) == "table" and ((t.In or 0) > 0 or (t.Out or 0) > 0) then
                                life[cat] = { i = t.In or 0, o = t.Out or 0 }
                            end
                        end
                        DB.life[key] = life
                        -- all-time zones, by zone name
                        local zc = type(zoneDB) == "table" and type(zoneDB[server]) == "table" and zoneDB[server][name]
                        local total = type(zc) == "table" and type(zc.data) == "table" and zc.data.Total
                        if type(total) == "table" then
                            local zones = {}
                            for cat, byZone in pairs(total) do
                                if type(byZone) == "table" then
                                    for text, amt in pairs(byZone) do
                                        if type(text) == "string" and type(amt) == "table" then
                                            local z = zones[ZoneOnly(text)]
                                            if not z then z = {}; zones[ZoneOnly(text)] = z end
                                            local b = Bucket(z, cat)
                                            b.i, b.o = b.i + (amt.In or 0), b.o + (amt.Out or 0)
                                        end
                                    end
                                end
                            end
                            DB.zones[key] = zones
                        end
                        -- characters only the classic data knows: a ledger entry
                        -- so they show with their gold
                        if db and not db.chars[key] then
                            local o = type(c.options) == "table" and c.options or {}
                            db.chars[key] = {
                                server = server, name = name, since = History.DayKey(), days = {},
                                class = o.class, faction = o.faction,
                                money = tonumber(o.totalcash),
                            }
                        end
                    end
                end
            end
        end
    end
    DB.imported = time()
    return count
end

StaticPopupDialogs["SPLIFFGOLD_REIMPORT"] = {
    text = "Copy your Accountant Classic data into the Money Book again?\n\nEverything the Money Book logged since the last import is replaced by Accountant Classic's records.",
    button1 = OKAY,
    button2 = CANCEL,
    OnAccept = function()
        local n = Import()
        History:Detach()
        History:Reattach(SERVER, PLAYER, { guid = UnitGUID("player"), faction = UnitFactionGroup("player"),
            class = select(2, UnitClass("player")), money = GetMoney() })
        session = {}
        lastMoney = GetMoney()
        print(S.PREFIX .. ("copied %d character%s from Accountant Classic."):format(n, n == 1 and "" or "s"))
        for _, fn in ipairs(refreshers) do pcall(fn) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns.Reimport() if DB then StaticPopup_Show("SPLIFFGOLD_REIMPORT") end end

---------------------------------------------------------------------------
-- Start. The module loads at PLAYER_LOGIN (Spliffbars' LoadAddOn), but the
-- game hands it its saved tables only after these files have run, just
-- before ADDON_LOADED: everything that touches SpliffGoldDB or
-- SpliffGoldHistory waits for that.
---------------------------------------------------------------------------
local lastSeen -- the balance this character had when last seen

local function Init()
    SpliffGoldDB = SpliffGoldDB or {}
    DB = SpliffGoldDB
    DB.life = DB.life or {}
    DB.zones = DB.zones or {}

    SERVER = Str(GetRealmName()) or "?"
    PLAYER = PlayerKey()
    CHAR = History.CharKey(SERVER, PLAYER)

    if not DB.imported and ns.AccountantPresent() then
        local ok, n = pcall(Import)
        if ok and n > 0 then
            print(S.PREFIX .. ("Money Book: copied %d character%s from Accountant Classic. You can switch Accountant Classic off now."):format(n, n == 1 and "" or "s"))
        end
    end
    History:InitDB()
    -- Accountant Classic keeps 2000 changes, about a week of play here:
    -- room for the 30 days it means to keep
    local hdb = History:GetDB()
    if hdb and hdb.settings and (hdb.settings.recentMax or 0) < 6000 then hdb.settings.recentMax = 6000 end
    if not DB.imported then DB.imported = 0 end -- (0: nothing to import; the button can still do it later)

    -- before OnLogin can change it
    local node = hdb and hdb.chars[CHAR]
    lastSeen = node and Usable(node.money) and node.money or nil

    -- money=nil: GetMoney() can still be 0 this early; PLAYER_ENTERING_WORLD sets it
    local _, class = UnitClass("player")
    History:OnLogin(SERVER, PLAYER, { guid = UnitGUID("player"), faction = UnitFactionGroup("player"), class = class })
    History:RegisterEvents()
end

-- the first balance: logs what changed while we weren't watching, then
-- starts counting from here
local function Baseline()
    if lastMoney or not DB then return end
    local money = GetMoney()
    if not Usable(money) then return end
    if lastSeen and lastSeen ~= money then
        local old = logType
        logType, untrackedNext = "OTHER", true
        Log(money - lastSeen, money)
        logType = old
    else
        History:SetBalance(money)
    end
    lastMoney = money
end

local function HookRepairs()
    if RepairAllItems then
        hooksecurefunc("RepairAllItems", function(guildBank) if not guildBank then logType = "REPAIRS" end end)
    end
    if CursorHasItem then
        hooksecurefunc("CursorHasItem", function() if InRepair() then logType = "REPAIRS" end end)
    end
    if PurchaseSlot then hooksecurefunc("PurchaseSlot", function() logType = "BANK" end) end
end
HookRepairs()

local events = CreateFrame("Frame")
local EXTRA = { "MERCHANT_UPDATE", "MAIL_INBOX_UPDATE", "CHAT_MSG_MONEY", "PLAYER_MONEY",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "PLAYER_ENTERING_WORLD", "ADDON_LOADED" }
for e in pairs(EVENT_TYPES) do pcall(events.RegisterEvent, events, e) end
for _, e in ipairs(EXTRA) do pcall(events.RegisterEvent, events, e) end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "SpliffGold" then
            events:UnregisterEvent("ADDON_LOADED")
            Init()
            -- (a load after the loading screen gets no PLAYER_ENTERING_WORLD)
            C_Timer.After(3, Baseline)
        end
        return
    end
    if not DB then return end
    local t = EVENT_TYPES[event]
    if t then
        logType = t
    elseif event == "MERCHANT_UPDATE" then
        if InRepair() then logType = "REPAIRS" end
    elseif event == "MAIL_INBOX_UPDATE" then
        logType = AuctionMail() and "AH" or "MAIL"
    elseif event == "CHAT_MSG_MONEY" then
        OnLootMoney(arg1)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if BANK_INTERACTIONS[arg1] then logType = "BANK" end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if BANK_INTERACTIONS[arg1] and logType == "BANK" then logType = "" end
    elseif event == "PLAYER_MONEY" then
        local pending = pendingLoot
        pendingLoot = nil
        if pending and GetTime() - pending <= PENDING_LOOT_WINDOW then
            local old = logType
            logType = "LOOT"
            Update()
            logType = old
        else
            Update()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Baseline()
    end
end)

---------------------------------------------------------------------------
-- Reading the numbers (for the Money Book)
---------------------------------------------------------------------------
local DayKey, AddDays = History.DayKey, History.AddDays

ns.PERIODS = {
    { key = "session",   label = "Session" },
    { key = "today",     label = "Today" },
    { key = "yesterday", label = "Yesterday" },
    { key = "week",      label = "This week" },
    { key = "lastweek",  label = "Last week" },
    { key = "month",     label = "This month" },
    { key = "lastmonth", label = "Last month" },
    { key = "year",      label = "This year" },
    { key = "all",       label = "All time" },
}
local PERIOD_LABEL = {}
for _, p in ipairs(ns.PERIODS) do PERIOD_LABEL[p.key] = p.label end
function ns.PeriodLabel(key) return PERIOD_LABEL[key] or key end

-- the first day of the week holding day (weeks start on DB.weekStart:
-- 1 = Sunday ... 7 = Saturday, as in Accountant Classic)
local function WeekStart(day)
    local t = History.DayToTime(day)
    local back = (tonumber(date("%w", t)) + 1 - (DB.weekStart or 1)) % 7
    return AddDays(day, -back)
end

-- the day range of a period (nil for session and all time)
function ns.Range(key)
    local today = DayKey()
    if key == "today" then return today, today end
    if key == "yesterday" then local y = AddDays(today, -1) return y, y end
    if key == "week" then return WeekStart(today), today end
    if key == "lastweek" then
        local first = WeekStart(today)
        return AddDays(first, -7), AddDays(first, -1)
    end
    local month = math.floor(today / 100) * 100 + 1
    if key == "month" then return month, today end
    if key == "lastmonth" then
        local last = AddDays(month, -1)
        return math.floor(last / 100) * 100 + 1, last
    end
    if key == "year" then return math.floor(today / 10000) * 10000 + 101, today end
end

-- a scope for the ledger's queries: "char" (this character) or "all"
function ns.Scope(scope)
    if scope == "char" then return { char = CHAR } end
    return nil
end

-- totals of a period: { [cat] = { i, o, ni?, no?, mi?, mo? } }, income, expense
function ns.Totals(period, scope)
    if not DB then return {}, 0, 0 end
    local out, income, expense = {}, 0, 0
    local function add(cat, i, o, extra)
        local b = out[cat]
        if not b then b = { i = 0, o = 0 }; out[cat] = b end
        b.i, b.o = b.i + (i or 0), b.o + (o or 0)
        if extra then
            b.ni, b.no = (b.ni or 0) + (extra.ni or 0), (b.no or 0) + (extra.no or 0)
            b.mi, b.mo = math.max(b.mi or 0, extra.mi or 0), math.max(b.mo or 0, extra.mo or 0)
        end
        income, expense = income + (i or 0), expense + (o or 0)
    end
    if period == "session" then
        for cat, b in pairs(session) do add(cat, b.i, b.o) end
    elseif period == "all" then
        for key, life in pairs(DB.life) do
            if scope ~= "char" or key == CHAR then
                for cat, b in pairs(life) do add(cat, b.i, b.o) end
            end
        end
    else
        local from, to = ns.Range(period)
        local totals = History:GetTotals(ns.Scope(scope), from, to)
        for cat, b in pairs(totals) do add(cat, b.i, b.o, b) end
    end
    return out, income, expense
end

-- all-time zone totals: list of { name, i, o, cats = { [cat] = { i, o } } }
function ns.AllTimeZones(scope)
    if not DB then return {} end
    local merged = {}
    for key, zones in pairs(DB.zones) do
        if scope ~= "char" or key == CHAR then
            for name, cats in pairs(zones) do
                local z = merged[name]
                if not z then z = { name = name, i = 0, o = 0, cats = {} }; merged[name] = z end
                for cat, b in pairs(cats) do
                    local c = Bucket(z.cats, cat)
                    c.i, c.o = c.i + b.i, c.o + b.o
                    z.i, z.o = z.i + b.i, z.o + b.o
                end
            end
        end
    end
    local list = {}
    for _, z in pairs(merged) do list[#list + 1] = z end
    return list
end

-- zone totals of a day range from the ledger, in the same shape
function ns.PeriodZones(period, scope)
    if not DB then return {} end
    local from, to = ns.Range(period)
    if not from then return {} end
    local list = {}
    for mapID, zt in pairs(History:GetLocationTotals(ns.Scope(scope), from, to)) do
        local name = History:GetLocationKeyName(mapID)
        local cats = {}
        for cat, b in pairs(zt.categories) do cats[cat] = { i = b.i, o = b.o } end
        local subs = {}
        for subKey, st in pairs(zt.subZones or {}) do
            local _, subName = History:GetLocationKeyName(mapID, subKey)
            subs[#subs + 1] = { name = subName or subKey, i = st.i, o = st.o }
        end
        list[#list + 1] = { name = name, i = zt.i, o = zt.o, cats = cats, subs = subs }
    end
    return list
end

-- every character: { key, name, server, class, faction, money, moneyAt, life = { i, o } }
function ns.Characters()
    if not DB then return {} end
    local list, seen = {}, {}
    local hdb = History:GetDB()
    for key, node in pairs(hdb and hdb.chars or {}) do
        if not node.deleted and not key:find("#", 1, true) then
            seen[key] = true
            local c = { key = key, name = node.name, server = node.server, class = node.class,
                faction = node.faction, money = node.money, moneyAt = node.moneyAt, i = 0, o = 0 }
            if key == CHAR then
                local m = GetMoney()
                if Usable(m) then c.money, c.moneyAt = m, time() end
            end
            for _, b in pairs(DB.life[key] or {}) do c.i, c.o = c.i + b.i, c.o + b.o end
            list[#list + 1] = c
        end
    end
    for key, life in pairs(DB.life) do
        if not seen[key] then
            local server, name = key:match("^(.-)|(.*)$")
            local c = { key = key, name = name or key, server = server, i = 0, o = 0 }
            for _, b in pairs(life) do c.i, c.o = c.i + b.i, c.o + b.o end
            list[#list + 1] = c
        end
    end
    table.sort(list, function(a, b) return (a.money or -1) > (b.money or -1) end)
    return list
end
