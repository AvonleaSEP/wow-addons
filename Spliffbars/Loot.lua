-- Spliffbars: gathered loot flies to your bag
-- After you mine a vein, pick herbs or skin a beast, each item you loot
-- from it (ore, stone, gems, herbs, leather, hides)
-- pops out at your cursor and flies into your bag button (Bag Button if
-- it's showing, else the game's backpack button), one after another,
-- trailing sparkles in its quality colour (ns.FlyItem, Mote.lua).
-- How it knows it's gathering: you cast Mining, Herb Gathering or Skinning
-- just before the loot opened, or the game calls it fishing loot (a catch
-- flies from the bobber you clicked).
-- From mobs and chests: coins fly into the Gold bar (which shines as they
-- land), quest items to the top of Questie's tracker, and green or better
-- items into your bag; the rest doesn't fly.
-- /spliffbars loot tests it with a few items.

local _, ns = ...
local isSecret = ns.isSecret

local function SpellName(id)
    local ok, n
    if C_Spell and C_Spell.GetSpellName then ok, n = pcall(C_Spell.GetSpellName, id)
    elseif GetSpellInfo then ok, n = pcall(GetSpellInfo, id) end
    if ok and type(n) == "string" and not isSecret(n) then return n end
end

-- the gathering spells, by their names in the game's language (every rank
-- shares its name)
local GATHER_SPELLS = { [2575] = "Mining", [2366] = "Herb Gathering", [8613] = "Skinning" }
local gatherNames
local function IsGathering(name)
    if not gatherNames then
        gatherNames = {}
        for id, english in pairs(GATHER_SPELLS) do
            gatherNames[SpellName(id) or english] = true
            gatherNames[english] = true
        end
    end
    return gatherNames[name] == true
end

-- where the items go
local function BagTarget()
    for _, name in ipairs({ "BagButtonFrame", "MainMenuBarBackpackButton", "BagsBarBackpackButton" }) do
        local f = _G[name]
        if f and f.IsVisible and f:IsVisible() then return f end
    end
end

local minedAt = -100 -- when you last cast a gathering spell
local pending = {}   -- loot slot -> { icon, name, quality, count } while its loot is open
local flying = 0     -- items sent in the last moment, to space them out
local lastSent = 0

-- quest items go to the top of Questie's tracker (top left), else the top
-- of your XP bar, else your bag. A small invisible spot marks where they
-- land, so it's the tracker's title, not its middle.
local questSpot = CreateFrame("Frame", nil, UIParent)
questSpot:SetSize(2, 2)
local function QuestTarget()
    local tracker = _G.Questie_BaseFrame
    questSpot:ClearAllPoints()
    if tracker and tracker:IsVisible() then
        questSpot:SetPoint("CENTER", tracker, "TOPLEFT", 40, -10)
        return questSpot
    end
    local xp = _G.XPRepBars_xp
    if xp and xp:IsVisible() then
        questSpot:SetPoint("CENTER", xp, "TOP", 0, -10)
        return questSpot
    end
end

-- coins go to the Gold bar when it's showing (else your bag)
local function GoldTarget()
    local f = _G.SpliffbarsGold
    if f and f:IsVisible() then return f end
end

local function Send(p)
    local now = GetTime()
    if now - lastSent > 0.6 then flying = 0 end
    lastSent = now
    local gold = p.coins and GoldTarget()
    local quest = p.quest and not gold and QuestTarget()
    ns.FlyItem(p.icon, p.quality, p.count, gold or quest or BagTarget(), flying * 0.35, p.name,
        gold and ns.GoldShine or nil)
    flying = flying + 1
end

-- is a loot slot coins?
local MONEY = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or LOOT_SLOT_MONEY or 2
local function IsCoins(slot)
    if not GetLootSlotType then return false end
    local ok, t = pcall(GetLootSlotType, slot)
    return ok and not isSecret(t) and t == MONEY
end

local events = CreateFrame("Frame")
pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
for _, e in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- a3: the spell's id
        if type(a3) == "number" and not isSecret(a3) and IsGathering(SpellName(a3)) then
            minedAt = GetTime()
        end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        -- gathering just now, or a fishing catch (the game says so; the cast
        -- itself can be 20 seconds before the bobber's clicked)
        local fishing = false
        if IsFishingLoot then
            local okF, f = pcall(IsFishingLoot)
            fishing = okF and f == true
        end
        -- otherwise (mobs, chests) only coins (to the Gold bar) and green or
        -- better items (to your bag) fly
        local gathering = GetTime() - minedAt <= 6
        local mobLoot = not gathering and not fishing
        if next(pending) then return end
        local ok, n = pcall(GetNumLootItems)
        if not ok or type(n) ~= "number" or isSecret(n) then return end
        for i = 1, n do
            local ok2, icon, name, count, _, quality, _, isQuest = pcall(GetLootSlotInfo, i)
            local coins = IsCoins(i)
            local special = type(quality) == "number" and not isSecret(quality) and quality >= 2 -- green+
            local quest = isQuest == true -- (a hidden value never equals true)
            if ok2 and icon and not isSecret(icon) and (coins or special or quest or not mobLoot) then
                -- (coins come as "12 Silver\n3 Copper": one line)
                pending[i] = { icon = icon, quality = (not isSecret(quality)) and quality or nil,
                    name = (type(name) == "string" and not isSecret(name)) and name:gsub("\n", " ") or nil,
                    count = (type(count) == "number" and not isSecret(count)) and count or 1,
                    coins = coins, quest = quest }
            end
        end
    elseif event == "LOOT_SLOT_CLEARED" then
        -- a1: the slot; it just went into your bags
        local p = type(a1) == "number" and pending[a1]
        if p then
            pending[a1] = nil
            Send(p)
        end
    elseif event == "LOOT_CLOSED" then
        wipe(pending)
        minedAt = -100 -- one node, one flight
    end
end)

-- /spliffbars loot: three test items from your cursor
ns.TestLoot = function()
    local tests = {
        { icon = "Interface\\Icons\\INV_Ore_Copper_01", name = "Copper Ore", quality = 1, count = 2 },
        { icon = "Interface\\Icons\\INV_Stone_02", name = "Rough Stone", quality = 1, count = 1 },
        { icon = "Interface\\Icons\\INV_Misc_Gem_Emerald_03", name = "Malachite", quality = 2, count = 1 },
    }
    for _, p in ipairs(tests) do Send(p) end
end
