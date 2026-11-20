-- Spliffbars: shared bits for the pieces (Gold.lua, Skills.lua; XP.lua
-- keeps its own copies, it came first).
--
-- Pieces, each its own Edit Mode frame:
--   XP.lua      experience and reputation bars (vertical, left edge)
--   Gold.lua    a gold goal bar that grows into a timeline on hover
--   Skills.lua  a row of weapon skill bars and a row of trade skill bars

local _, ns = ...

-- Spliffbars is the hub of the Spliff package: modules in their own
-- folders (SpliffFrames ...) reach these shared bits through this global.
_G.Spliffbars = ns

ns.LEM = LibStub("LibEditMode")
ns.PREFIX = "|cffe8c45aSpliffbars|r "

ns.isSecret = issecretvalue or function() return false end
local isSecret = ns.isSecret
function ns.Num(v) return not isSecret(v) and type(v) == "number" end
function ns.Tbl(v) if not isSecret(v) and type(v) == "table" then return v end end

function ns.Big(n)
    n = math.floor((n or 0) + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

-- 12g 34s 56c with the game's coin pictures (zeros left out)
function ns.Money(copper, plain)
    copper = math.floor(math.abs(copper or 0) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local G = plain and "g" or "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
    local S = plain and "s" or "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
    local C = plain and "c" or "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
    local parts = {}
    if g > 0 then parts[#parts + 1] = ns.Big(g) .. G end
    if s > 0 or (g > 0 and c > 0) then parts[#parts + 1] = s .. S end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. C end
    return table.concat(parts, " ")
end

-- short money for tight spots: 12.3g / 45s / 7c
function ns.ShortMoney(copper)
    copper = math.abs(copper or 0)
    if copper >= 100000 then return string.format("%.0fg", copper / 10000) end
    if copper >= 10000 then return string.format("%.1fg", copper / 10000) end
    if copper >= 100 then return string.format("%ds", math.floor(copper / 100)) end
    return string.format("%dc", math.floor(copper))
end

---------------------------------------------------------------------------
-- Account-wide switches (the Spliffbars options panel, Options.lua), kept
-- in SpliffbarsDB. Read when an effect is about to happen, so a change
-- takes hold at once.
---------------------------------------------------------------------------
ns.OPTION_DEFAULTS = {
    loot = true,         -- every loot effect (the master switch)
    lootGather = true,   --   mining, herbs, skinning, fishing -> your bag
    lootCoins = true,    --   coins -> the Gold bar
    lootQuest = true,    --   quest items -> the quest tracker
    lootItems = true,    --   green or better from mobs and chests -> your bag
    skillMotes = true,   -- skill-up motes (each row's own setting too)
    recipeSwarm = true,  -- the swarm when you learn a recipe
    journalClick = true, -- clicking the XP bar opens the Leveling Journal
    goldClick = true,    -- clicking the Gold bar opens the Money Book (SpliffGold module)
    questDrag = true,    -- Shift-drag quest items from Questie's tracker (QuestDrag.lua)
}

function ns.Opt(key)
    local db = SpliffbarsDB
    if type(db) == "table" and db[key] ~= nil then return db[key] end
    return ns.OPTION_DEFAULTS[key]
end

function ns.SetOpt(key, value)
    SpliffbarsDB = SpliffbarsDB or {}
    SpliffbarsDB[key] = value
end

---------------------------------------------------------------------------
-- Modules: the bigger pieces of the package live in their own folders and
-- load only when switched on (the options panel's Modules), so a module
-- that's off runs no code at all. A module says it is one in its .toc:
--   ## Dependencies: Spliffbars
--   ## LoadOnDemand: 1
--   ## X-Spliff-Module: Unit Frames     (its name in the options)
--   ## X-Spliff-Default: off            (optional: off until switched on)
-- Switching one on or off takes a /reload (code can't be unloaded).
---------------------------------------------------------------------------
local AddOns = C_AddOns or {}
local NumAddOns = AddOns.GetNumAddOns or GetNumAddOns
local AddOnInfo = AddOns.GetAddOnInfo or GetAddOnInfo
local AddOnMeta = AddOns.GetAddOnMetadata or GetAddOnMetadata
local LoadModule = AddOns.LoadAddOn or LoadAddOn
local IsLoaded = AddOns.IsAddOnLoaded or IsAddOnLoaded

function ns.Modules()
    local out = {}
    if not (NumAddOns and AddOnInfo and AddOnMeta) then return out end
    for i = 1, NumAddOns() do
        local name = AddOnInfo(i)
        local label = type(name) == "string" and AddOnMeta(name, "X-Spliff-Module")
        if label then
            out[#out + 1] = { addon = name, name = label, notes = AddOnMeta(name, "Notes"),
                default = (AddOnMeta(name, "X-Spliff-Default") or ""):lower() ~= "off" }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function ns.ModuleOn(m)
    local v = ns.Opt("module:" .. m.addon)
    if v == nil then return m.default end
    return v
end

function ns.ModuleLoaded(m) return IsLoaded and IsLoaded(m.addon) and true or false end

local moduleLoader = CreateFrame("Frame")
moduleLoader:RegisterEvent("PLAYER_LOGIN")
moduleLoader:SetScript("OnEvent", function()
    if not LoadModule then return end
    for _, m in ipairs(ns.Modules()) do
        if ns.ModuleOn(m) and not ns.ModuleLoaded(m) then
            local ok, why = LoadModule(m.addon)
            if not ok then
                print(ns.PREFIX .. m.name .. " didn't load" .. (why == "DISABLED"
                    and ": it's turned off in the game's AddOns list." or (why and (": " .. tostring(why)) or ".")))
            end
        end
    end
end)

-- Each bar registers here so the options panel can show and hide it:
-- { name, get = hidden?, set = function(hidden) }. Like Edit Mode's "Hide
-- This Bar", it's for the Edit Mode layout you're using.
ns.pieces = {}
function ns.RegisterPiece(p) ns.pieces[#ns.pieces + 1] = p end

function ns.CharKey()
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    return (name or UnitName("player") or "?") .. "-" .. (realm or (GetRealmName and GetRealmName()) or "")
end

---------------------------------------------------------------------------
-- Fonts: the game's own plus every font other addons share through
-- LibSharedMedia (HealBot adds 25).
---------------------------------------------------------------------------
local GAME_FONTS = {
    { "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" }, { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\SKURRI.TTF" }, { "Morpheus", "Fonts\\MORPHEUS.TTF" },
}
local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

function ns.FontPath(name)
    if name and name ~= "Game default" then
        local lsm = LSM()
        local path = lsm and lsm:Fetch("font", name, true)
        if path then return path end
        for _, f in ipairs(GAME_FONTS) do if f[1] == name then return f[2] end end
    end
    return (GameFontHighlightSmall:GetFont())
end

function ns.FontChoices()
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

function ns.ApplyFont(fs, fontName, size, outline)
    fs:SetFont(ns.FontPath(fontName), size, outline or "OUTLINE")
    if not fs:GetFont() then fs:SetFont(ns.FontPath(nil), size, outline or "OUTLINE") end
end

---------------------------------------------------------------------------
-- Smooth fill: a gradient across the whole bar, revealed as it fills (a
-- clipping frame follows the status bar's fill), so shades stay put.
---------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8X8"
ns.WHITE = WHITE

function ns.SmoothFill(sb)
    sb:SetStatusBarTexture(WHITE)
    sb:SetStatusBarColor(1, 1, 1, 0)
    local clip = CreateFrame("Frame", nil, sb)
    clip:SetClipsChildren(true)
    clip:SetAllPoints(sb:GetStatusBarTexture())
    local grad = clip:CreateTexture(nil, "ARTWORK")
    grad:SetTexture(WHITE)
    grad:SetAllPoints(sb)
    sb.grad = grad
    sb.clip = clip
end

-- dark at one end, light at the other ("VERTICAL": bottom to top)
function ns.Gradient(t, dir, r1, g1, b1, a1, r2, g2, b2, a2)
    if CreateColor and pcall(t.SetGradient, t, dir, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2)) then return end
    if t.SetGradientAlpha and pcall(t.SetGradientAlpha, t, dir, r1, g1, b1, a1, r2, g2, b2, a2) then return end
    t:SetColorTexture((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
end

function ns.SetFill(sb, r, g, b, a, dir)
    a = a or 1
    ns.Gradient(sb.grad, dir or "VERTICAL", r * 0.55, g * 0.55, b * 0.55, a,
        math.min(r * 1.1 + 0.12, 1), math.min(g * 1.1 + 0.12, 1), math.min(b * 1.1 + 0.12, 1), a)
end

---------------------------------------------------------------------------
-- Per-layout settings for a piece: db.layouts[layout][key], with defaults
---------------------------------------------------------------------------
function ns.Look(db, layoutName, key, defaults)
    -- Edit Mode can ask before the saved settings have loaded: the defaults
    -- for now (a fresh copy, so nothing's kept from it)
    if not db then return CopyTable(defaults) end
    db.layouts = db.layouts or {}
    local lname = layoutName or "Default"
    db.layouts[lname] = db.layouts[lname] or {}
    local l = db.layouts[lname][key]
    if not l then l = {}; db.layouts[lname][key] = l end
    for k, v in pairs(defaults) do
        if l[k] == nil then l[k] = v end
    end
    return l
end

-- an icon path, or the question mark if this client hasn't got it
function ns.Icon(path)
    if type(path) ~= "string" then return path end
    if not path:find("\\", 1, true) then path = "Interface\\Icons\\" .. path end
    if GetFileIDFromPath and not GetFileIDFromPath(path) then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    return path
end

---------------------------------------------------------------------------
-- /spliffbars            the options panel (Options.lua)
-- /spliffbars help       the commands
-- /spliffbars goal 250   set the gold goal (250, 250g 50s, 1.5k)
---------------------------------------------------------------------------
SLASH_SPLIFFBARS1 = "/spliffbars"
SlashCmdList.SPLIFFBARS = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if cmd and cmd:lower() == "goal" and rest ~= "" and ns.SetGoldGoal then
        ns.SetGoldGoal(rest)
    elseif cmd and cmd:lower() == "recipe" and ns.TestRecipe then
        if not ns.TestRecipe() then print(ns.PREFIX .. "no trade skill bars showing to send a swarm to.") end
    elseif cmd and cmd:lower() == "journal" and ns.ToggleJournal then
        ns.ToggleJournal()
    elseif (cmd == "" or cmd:lower() == "options") and ns.OpenOptions then
        ns.OpenOptions()
    elseif cmd and cmd:lower() == "flight" and ns.TestFlight then
        ns.TestFlight()
    elseif cmd and cmd:lower() == "loot" and ns.TestLoot then
        ns.TestLoot()
    elseif cmd and cmd:lower() == "mote" and ns.TestMote then
        if not ns.TestMote() then print(ns.PREFIX .. "no skill bars showing to send a mote to.") end
    else
        print(ns.PREFIX .. "/spliffbars  opens the options (show or hide bars, loot and skill effects, and more).")
        print(ns.PREFIX .. "move and set up each piece in Edit Mode (Esc > Edit Mode): XP, Reputation, Gold, Weapon Skills, Trade Skills.")
        print(ns.PREFIX .. "/spliffbars journal (or /lj, or click the XP bar)  opens your Leveling Journal.")
        print(ns.PREFIX .. "/spliffbars goal 250  sets your gold goal.")
        print(ns.PREFIX .. "/spliffbars flight  shows a 20 second test flight on the Flight Timer.")
        print(ns.PREFIX .. "/spliffbars mote  sends a test skill-up mote from your cursor.")
        print(ns.PREFIX .. "/spliffbars loot  sends test mined items from your cursor to your bag.")
        print(ns.PREFIX .. "/spliffbars recipe  sends a test learned-recipe swarm into your first trade bar.")
    end
end

---------------------------------------------------------------------------
-- RXP Guides plays the minimap ping (sound 3175, its default) each time a
-- mob your guide step wants turns up on a nameplate. Devon doesn't want it.
-- RXP keeps a settings profile per character (RXPSettings.profiles), so
-- at every login each profile still on that default gets "none", and the
-- one in use now too. A sound picked there on purpose (not the ping) is
-- left alone.
---------------------------------------------------------------------------
local PING = 3175
local function QuietRXP()
    local changed = false
    local sv = type(RXPSettings) == "table" and RXPSettings
    if sv and type(sv.profiles) == "table" then
        for _, profile in pairs(sv.profiles) do
            if type(profile) == "table" and (profile.soundOnFind == nil or profile.soundOnFind == PING) then
                profile.soundOnFind = "none"
                changed = true
            end
        end
    end
    -- the live one (the same table once RXP has made it, but not always yet)
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    local ok, rxp = pcall(function() return ace and ace:GetAddon("RXPGuides", true) end)
    local live = ok and rxp and rxp.settings and rxp.settings.profile
    if type(live) == "table" and (live.soundOnFind == nil or live.soundOnFind == PING) then
        live.soundOnFind = "none"
        changed = true
    end
    if changed and SpliffbarsDB and not SpliffbarsDB.rxpPingOff then
        SpliffbarsDB.rxpPingOff = true
        print(ns.PREFIX .. "turned off RXP Guides' ping when a quest mob shows up (RXP options > Targeting > Play Sound).")
    end
end

local quiet = CreateFrame("Frame")
quiet:RegisterEvent("PLAYER_ENTERING_WORLD")
quiet:SetScript("OnEvent", function()
    QuietRXP()
    C_Timer.After(5, QuietRXP) -- (RXP can set its profile up a moment later)
end)
