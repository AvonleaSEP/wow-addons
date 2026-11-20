-- Spliff Hunter
-- Hunter tools for the Spliff package, in place of macros. A Spliffbars
-- module: it loads when switched on in Spliffbars' options (Modules), and
-- on a character that isn't a hunter it does nothing at all.
--
-- Each tool is a "feature" added with Feature{} below: it gets an on / off
-- switch on the Hunter page of /spliffbars, kept in SpliffHunterDB, and its
-- Start / Stop run when you switch it (and Start once at login, if on).
--
-- Tools (each in its own file, listed in the .toc after this one):
--   AutoShot.lua   Auto Shot timer: reload, aim, and red while moving holds it
--   Pet.lua        pet health and happiness, with a warning when it's hungry

local _, ns = ...
local S = Spliffbars -- the hub (Spliffbars\Core.lua)
local PREFIX = "|cffabd473Spliff Hunter|r "
ns.PREFIX = PREFIX

local _, class = UnitClass("player")
ns.isHunter = (class == "HUNTER")

---------------------------------------------------------------------------
-- Saved settings (one table for the account; per-character bits go under
-- DB.chars[key])
---------------------------------------------------------------------------
-- (the game fills SpliffHunterDB in after this file runs, so it's picked
-- up on ADDON_LOADED, at the bottom; features start then)
local DB
local loaded = false

function ns.Char()
    if not DB then return {} end
    local key = (S and S.CharKey and S.CharKey()) or UnitName("player")
    DB.chars[key] = DB.chars[key] or {}
    return DB.chars[key]
end

---------------------------------------------------------------------------
-- Features
--   ns.Feature{ key = "autoshot", name = "Auto Shot timer",
--               notes = "one line for the options page", default = true,
--               start = function() ... end, stop = function() ... end }
---------------------------------------------------------------------------
ns.features = {}

local function IsOn(f)
    local v = DB and DB.on[f.key]
    if v == nil then return f.default ~= false end
    return v
end
ns.IsOn = IsOn

local function Start(f)
    if not (ns.isHunter and IsOn(f) and f.start) then return end
    local ok, err = pcall(f.start)
    if not ok then print(PREFIX .. f.name .. " failed to start: " .. tostring(err)) end
end

function ns.Feature(f)
    ns.features[#ns.features + 1] = f
    if loaded then Start(f) end -- (one added after loading starts at once)
    return f
end

local function Switch(f, on)
    if not DB then return end
    DB.on[f.key] = on
    if not ns.isHunter then return end
    local fn = on and f.start or f.stop
    if fn then pcall(fn) end
end

---------------------------------------------------------------------------
-- The Hunter page in /spliffbars
---------------------------------------------------------------------------
if S and S.AddOptionsTab then
    S.AddOptionsTab("Hunter",
        "Hunter tools, in place of macros. Each one switches on and off here.",
        function(page)
            local L = page:Column(16, -70)
            page:Heading(L, "Tools")
            if not ns.isHunter then
                page:Note(L, "This character isn't a hunter, so none of these run here.")
            end
            if #ns.features == 0 then
                page:Note(L, "None yet. They're on the way.")
                return
            end
            for _, f in ipairs(ns.features) do
                page:Check(L, f.name, function() return IsOn(f) end, function(v) Switch(f, v) end)
                if f.notes then page:Note(L, f.notes, 20) end
            end
        end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
    if name ~= "SpliffHunter" then return end
    events:UnregisterEvent("ADDON_LOADED")
    SpliffHunterDB = SpliffHunterDB or {}
    DB = SpliffHunterDB
    DB.on = DB.on or {}
    DB.chars = DB.chars or {}
    ns.DB = DB
    loaded = true
    for _, f in ipairs(ns.features) do Start(f) end
end)

SLASH_SPLIFFHUNTER1 = "/hunter"
SlashCmdList.SPLIFFHUNTER = function()
    if S and S.OpenOptions then S.OpenOptions("Hunter") end
end
