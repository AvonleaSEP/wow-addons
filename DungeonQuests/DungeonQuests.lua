-- Dungeon Quests
-- A checklist of every dungeon's quests, so you walk in with all of them.
-- /dq (or /dungeonquests) opens it.
--
-- Left: the dungeons, easiest first, with how many of their quests you
-- have ("3/7" = 3 in your log or done, of the 7 you can ever do).
-- Right: that dungeon's quests, each with
--   its level and where you stand with it:
--     done  /  in your log  /  pick it up  /  too low  /  needs a quest first
--   who starts it and where ("Map" pins them on your world map and opens it
--   there; Questie's own pin shows on the map too),
--   and the quests you need first (click one to see where it starts).
-- "Hide done" tidies the list; "Entrance" shows where the dungeon is.
--
-- Everything comes from Questie's quest database (it ships with Questie
-- and knows WoW Forever's quests), filtered to your race and class.

local PREFIX = "|cffc79c6eDungeon Quests|r "

local ICON_READY = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_HAVE = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_LOCK = "Interface\\RaidFrame\\ReadyCheck-NotReady"

-- not dungeons: battlegrounds and the like
local SKIP = { [2597] = true, [3277] = true, [3358] = true, [2257] = true, [2917] = true, [2918] = true }

local DB -- DungeonQuestsDB

---------------------------------------------------------------------------
-- Questie's modules
---------------------------------------------------------------------------
local QuestieDB, ZoneDB, QuestieMap

local function Mod(name)
    if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
    local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    return ok and m or nil
end

local function Ready()
    QuestieDB = QuestieDB or Mod("QuestieDB")
    ZoneDB = ZoneDB or Mod("ZoneDB")
    QuestieMap = QuestieMap or Mod("QuestieMap")
    return QuestieDB and ZoneDB and QuestieDB.QueryQuestSingle and QuestieDB.QuestPointers
        and ZoneDB.GetDungeons and ZoneDB:GetDungeons() and Questie and Questie.db and Questie.db.char
end

local function Q(id, field)
    local ok, v = pcall(QuestieDB.QueryQuestSingle, id, field)
    if ok then return v end
end

local function Done(id) return Questie.db.char.complete and Questie.db.char.complete[id] and true or false end

local function InLog(id)
    if C_QuestLog and C_QuestLog.IsOnQuest then
        local ok, on = pcall(C_QuestLog.IsOnQuest, id)
        if ok and on == true then return true end
    end
    return false
end

local function AreaName(areaId)
    if C_Map and C_Map.GetAreaInfo then
        local ok, n = pcall(C_Map.GetAreaInfo, areaId)
        if ok and type(n) == "string" then return n end
    end
    return "Zone " .. tostring(areaId)
end

---------------------------------------------------------------------------
-- Who starts a quest, and where
-- { kind = "npc" | "object" | "item", id, name, zone, x, y, inside }
---------------------------------------------------------------------------
local function SpawnOf(spawns)
    if type(spawns) ~= "table" then return nil end
    -- prefer a spot out in the world over one inside a dungeon
    local best
    for zone, list in pairs(spawns) do
        local first = type(list) == "table" and list[1]
        if type(first) == "table" and first[1] and first[1] >= 0 then
            local inside = ZoneDB.IsDungeonZone and ZoneDB.IsDungeonZone(zone)
            if not best or (best.inside and not inside) then
                best = { zone = zone, x = first[1], y = first[2], inside = inside }
            end
        end
    end
    return best
end

local giverCache = {}
local function Giver(questId)
    if giverCache[questId] ~= nil then return giverCache[questId] or nil end
    local g = false
    local startedBy = Q(questId, "startedBy")
    if type(startedBy) == "table" then
        local npcs, objects, items = startedBy[1], startedBy[2], startedBy[3]
        if type(npcs) == "table" and npcs[1] then
            local id = npcs[1]
            local okN, name = pcall(QuestieDB.QueryNPCSingle, id, "name")
            local okS, spawns = pcall(QuestieDB.QueryNPCSingle, id, "spawns")
            g = { kind = "npc", id = id, name = okN and name or ("NPC " .. id) }
            local s = okS and SpawnOf(spawns)
            if s then g.zone, g.x, g.y, g.inside = s.zone, s.x, s.y, s.inside end
        elseif type(objects) == "table" and objects[1] then
            local id = objects[1]
            local okN, name = pcall(QuestieDB.QueryObjectSingle, id, "name")
            local okS, spawns = pcall(QuestieDB.QueryObjectSingle, id, "spawns")
            g = { kind = "object", id = id, name = okN and name or ("Object " .. id) }
            local s = okS and SpawnOf(spawns)
            if s then g.zone, g.x, g.y, g.inside = s.zone, s.x, s.y, s.inside end
        elseif type(items) == "table" and items[1] then
            local id = items[1]
            local okN, name = pcall(QuestieDB.QueryItemSingle, id, "name")
            g = { kind = "item", id = id, name = okN and name or ("Item " .. id) }
        end
    end
    giverCache[questId] = g
    return g or nil
end

local function GiverText(g)
    if not g then return "|cff888888Starts: unknown|r" end
    if g.kind == "item" then return "Starts from an item: |cffffffff" .. g.name .. "|r (a drop)" end
    local where = ""
    if g.zone then
        where = " - " .. AreaName(g.zone)
        if g.x then where = where .. string.format(" (%.0f, %.0f)", g.x, g.y) end
        if g.inside then where = where .. " |cffaaaaaa(inside)|r" end
    end
    return "From |cffffffff" .. g.name .. "|r" .. where
end

-- pin a giver on the world map and open it there
local function ShowOnMap(g)
    if not g then return end
    if QuestieMap then
        if g.kind == "npc" and QuestieMap.ShowNPC then pcall(QuestieMap.ShowNPC, QuestieMap, g.id) end
        if g.kind == "object" and QuestieMap.ShowObject then pcall(QuestieMap.ShowObject, QuestieMap, g.id) end
    end
    if not g.zone then
        print(PREFIX .. g.name .. ": no map spot known.")
        return
    end
    local uiMap = ZoneDB.GetUiMapIdByAreaId and ZoneDB:GetUiMapIdByAreaId(g.zone)
    if not uiMap then return end
    if g.x and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMap, g.x / 100, g.y / 100))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end)
    end
    if OpenWorldMap then
        pcall(OpenWorldMap, uiMap)
    elseif WorldMapFrame then
        if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
        pcall(WorldMapFrame.SetMapID, WorldMapFrame, uiMap)
    end
end

---------------------------------------------------------------------------
-- The data: dungeons and their quests
---------------------------------------------------------------------------
local dungeonList -- { { areaId, name, quests = { id... }, minLevel } }, built on first open

local function Build()
    local dungeons = ZoneDB:GetDungeons()
    local ok, zoneMap = pcall(ZoneDB.GetZonesWithQuests, false)
    if not ok or type(zoneMap) ~= "table" then return false end
    dungeonList = {}
    for areaId, entry in pairs(dungeons) do
        local quests = zoneMap[areaId]
        if not SKIP[areaId] and quests and next(quests) then
            local list, minLevel = {}, 999
            for id in pairs(quests) do
                local name = Q(id, "name")
                if type(name) == "string" then
                    list[#list + 1] = id
                    local lvl = Q(id, "requiredLevel") or Q(id, "questLevel") or 0
                    if type(lvl) == "number" and lvl > 0 and lvl < minLevel then minLevel = lvl end
                end
            end
            if #list > 0 then
                table.sort(list, function(a, b)
                    local la, lb = Q(a, "questLevel") or 0, Q(b, "questLevel") or 0
                    if la ~= lb then return la < lb end
                    return (Q(a, "name") or "") < (Q(b, "name") or "")
                end)
                local name = (ZoneDB.GetLocalizedDungeonName and ZoneDB:GetLocalizedDungeonName(areaId)) or entry[1]
                local loc = type(entry[4]) == "table" and entry[4][1]
                dungeonList[#dungeonList + 1] = { areaId = areaId, name = name, quests = list,
                    minLevel = minLevel, entrance = loc }
            end
        end
    end
    table.sort(dungeonList, function(a, b)
        if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
        return a.name < b.name
    end)
    return true
end

-- where you stand with a quest: key, label, colour, icon
local function Status(id)
    if Done(id) then return "done", "Done", { 0.4, 1, 0.4 }, ICON_DONE end
    if InLog(id) then return "have", "In your log", { 1, 0.82, 0 }, ICON_HAVE end
    local ok, doable = pcall(QuestieDB.IsDoable, id)
    if ok and doable then return "ready", "Pick it up", { 1, 1, 1 }, ICON_READY end
    local req = Q(id, "requiredLevel") or 0
    if type(req) == "number" and req > (UnitLevel("player") or 0) then
        return "level", "Level " .. req, { 0.6, 0.6, 0.6 }, ICON_READY
    end
    return "locked", "Needs a quest first", { 1, 0.5, 0.25 }, ICON_LOCK
end

-- the quests you need first: { { id, name, done } }, and whether it's "any one of"
local function Prereqs(id)
    local out, anyOne = {}, false
    local single = Q(id, "preQuestSingle")
    local group = Q(id, "preQuestGroup")
    if type(single) == "table" and #single > 0 then
        anyOne = #single > 1
        for _, p in ipairs(single) do out[#out + 1] = { id = p, name = Q(p, "name"), done = Done(p) } end
    end
    if type(group) == "table" then
        for _, p in ipairs(group) do
            local pid = math.abs(p)
            out[#out + 1] = { id = pid, name = Q(pid, "name"), done = Done(pid) }
        end
    end
    return out, anyOne
end

-- "have or done" out of all, for the dungeon list
local function Counts(d)
    local got = 0
    for _, id in ipairs(d.quests) do
        if Done(id) or InLog(id) then got = got + 1 end
    end
    return got, #d.quests
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local win = CreateFrame("Frame", "DungeonQuestsFrame", UIParent, "BasicFrameTemplateWithInset")
win:SetSize(700, 540)
win:SetPoint("CENTER")
win:SetFrameStrata("HIGH")
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:SetClampedToScreen(true)
win:Hide()
tinsert(UISpecialFrames, "DungeonQuestsFrame") -- Esc closes it
win.title = win.TitleText or win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
if not win.TitleText then win.title:SetPoint("TOP", 0, -5) end
win.title:SetText("Dungeon Quests")

local selected -- the dungeon showing

-- left: the dungeons
local listFrame = CreateFrame("Frame", nil, win)
listFrame:SetPoint("TOPLEFT", 10, -30)
listFrame:SetPoint("BOTTOMLEFT", 10, 10)
listFrame:SetWidth(200)
local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
listBg:SetAllPoints()
listBg:SetColorTexture(0, 0, 0, 0.25)

local listScroll = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
listScroll:SetPoint("TOPLEFT", 2, -2)
listScroll:SetPoint("BOTTOMRIGHT", -24, 2)
local listContent = CreateFrame("Frame", nil, listScroll)
listContent:SetSize(170, 10)
listScroll:SetScrollChild(listContent)

local dungeonButtons = {}

-- right: the chosen dungeon's quests
local detail = CreateFrame("Frame", nil, win)
detail:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 8, 0)
detail:SetPoint("BOTTOMRIGHT", -10, 10)

local header = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
header:SetPoint("TOPLEFT", 4, -2)
header:SetJustifyH("LEFT")
local subheader = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subheader:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
subheader:SetJustifyH("LEFT")

local entranceBtn = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
entranceBtn:SetSize(80, 20)
entranceBtn:SetPoint("TOPRIGHT", -2, 0)
entranceBtn:SetText("Entrance")

local hideDone = CreateFrame("CheckButton", nil, detail, "UICheckButtonTemplate")
hideDone:SetSize(22, 22)
hideDone:SetPoint("TOPRIGHT", entranceBtn, "TOPLEFT", -70, 0)
local hideDoneText = hideDone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hideDoneText:SetPoint("LEFT", hideDone, "RIGHT", 0, 1)
hideDoneText:SetText("Hide done")

local questScroll = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
questScroll:SetPoint("TOPLEFT", 0, -44)
questScroll:SetPoint("BOTTOMRIGHT", -24, 0)
local questContent = CreateFrame("Frame", nil, questScroll)
questContent:SetSize(430, 10)
questScroll:SetScrollChild(questContent)

local blocks = {} -- one per quest shown
local prereqButtons = {} -- pooled small buttons

local ShowDungeon -- below

local function PrereqButton(i)
    local b = prereqButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, questContent)
    b:SetHeight(14)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT")
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self) ShowOnMap(Giver(self.questId)) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Q(self.questId, "name") or "?", 1, 0.82, 0)
        GameTooltip:AddLine(GiverText(Giver(self.questId)), 1, 1, 1, true)
        GameTooltip:AddLine("Click: show where it starts", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    prereqButtons[i] = b
    return b
end

local function Block(i)
    local f = blocks[i]
    if f then return f end
    f = CreateFrame("Frame", nil, questContent)
    f:SetWidth(430)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(16, 16)
    f.icon:SetPoint("TOPLEFT", 4, -4)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.name:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    f.name:SetJustifyH("LEFT")
    f.state = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.state:SetPoint("TOPRIGHT", -6, -6)
    f.name:SetPoint("RIGHT", f.state, "LEFT", -6, 0)
    f.name:SetWordWrap(false)
    f.giver = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.giver:SetPoint("TOPLEFT", 24, -24)
    f.giver:SetPoint("RIGHT", -60, 0)
    f.giver:SetJustifyH("LEFT")
    f.giver:SetWordWrap(false)
    f.map = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.map:SetSize(50, 18)
    f.map:SetPoint("TOPRIGHT", -4, -21)
    f.map:SetText("Map")
    f.map:SetScript("OnClick", function() ShowOnMap(Giver(f.questId)) end)
    -- hovering the quest: Questie's reason it isn't available, when it isn't
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Q(self.questId, "name") or "?", 1, 0.82, 0)
        local lvl, req = Q(self.questId, "questLevel"), Q(self.questId, "requiredLevel")
        GameTooltip:AddLine("Level " .. tostring(lvl) .. (req and req > 0 and ("  (needs level " .. req .. ")") or ""), 1, 1, 1)
        if self.status == "locked" and QuestieDB.IsDoableVerbose then
            local ok, why = pcall(QuestieDB.IsDoableVerbose, self.questId, false, true, true)
            if ok and type(why) == "string" and why ~= "" then GameTooltip:AddLine(why, 1, 0.6, 0.4, true) end
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    blocks[i] = f
    return f
end

ShowDungeon = function(d)
    selected = d
    for _, b in pairs(dungeonButtons) do b.sel:SetShown(b.dungeon == d) end
    if not d then return end
    local got, total = Counts(d)
    header:SetText(d.name)
    subheader:SetText(("%d of %d quests in your log or done"):format(got, total)
        .. (d.entrance and ("  -  entrance in " .. AreaName(d.entrance[1])) or ""))
    entranceBtn:SetShown(d.entrance ~= nil)

    local y, n, p = 0, 0, 0
    for _, id in ipairs(d.quests) do
        local key, label, color, icon = Status(id)
        if not (DB.hideDone and key == "done") then
            n = n + 1
            local f = Block(n)
            f.questId, f.status = id, key
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", 0, -y)
            f.icon:SetTexture(icon)
            f.icon:SetDesaturated(key == "level")
            f.name:SetText(("|cffaaaaaa[%s]|r %s"):format(tostring(Q(id, "questLevel") or "?"), Q(id, "name") or "?"))
            f.state:SetText(label)
            f.state:SetTextColor(color[1], color[2], color[3])
            local g = Giver(id)
            f.giver:SetText(GiverText(g))
            f.map:SetShown(g ~= nil and g.kind ~= "item")
            local h = 42
            -- the quests you need first
            local pre, anyOne = Prereqs(id)
            for i, pq in ipairs(pre) do
                p = p + 1
                local b = PrereqButton(p)
                b.questId = pq.id
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -h + 2)
                b:SetPoint("RIGHT", f, "RIGHT", -6, 0)
                local mark = pq.done and "|cff66ff66done|r" or (InLog(pq.id) and "|cffffd100in log|r" or "|cffff8040to do|r")
                local lead = (i == 1) and (anyOne and "Needs one of: " or "Needs: ") or "              "
                b.text:SetText("|cffaaaaaa" .. lead .. "|r" .. (pq.name or ("Quest " .. pq.id)) .. "  " .. mark)
                b:Show()
                h = h + 14
            end
            f:SetHeight(h + 4)
            f.bg:SetColorTexture(1, 1, 1, (n % 2 == 0) and 0.04 or 0.08)
            f:Show()
            y = y + h + 6
        end
    end
    for i = n + 1, #blocks do blocks[i]:Hide() end
    for i = p + 1, #prereqButtons do prereqButtons[i]:Hide() end
    questContent:SetHeight(math.max(y, 10))
    questScroll:SetVerticalScroll(0)
end

local function RefreshList()
    if not dungeonList then return end
    for i, d in ipairs(dungeonList) do
        local b = dungeonButtons[i]
        if not b then
            b = CreateFrame("Button", nil, listContent)
            b:SetSize(170, 20)
            b:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
            b.sel = b:CreateTexture(nil, "BACKGROUND")
            b.sel:SetAllPoints()
            b.sel:SetColorTexture(1, 0.82, 0, 0.18)
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.name:SetPoint("LEFT", 4, 0)
            b.name:SetJustifyH("LEFT")
            b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.count:SetPoint("RIGHT", -4, 0)
            b.name:SetPoint("RIGHT", b.count, "LEFT", -4, 0)
            b.name:SetWordWrap(false)
            b:SetScript("OnClick", function(self) DB.last = self.dungeon.areaId; ShowDungeon(self.dungeon) end)
            dungeonButtons[i] = b
        end
        b.dungeon = d
        local got, total = Counts(d)
        b.name:SetText(("|cffaaaaaa%d|r %s"):format(d.minLevel < 999 and d.minLevel or 0, d.name))
        b.count:SetText(got .. "/" .. total)
        if got == total then b.count:SetTextColor(0.4, 1, 0.4) else b.count:SetTextColor(1, 0.82, 0) end
        b.sel:SetShown(d == selected)
        b:Show()
    end
    listContent:SetHeight(#dungeonList * 20)
end

local function Open()
    if not Ready() then
        print(PREFIX .. "Questie is still loading its quests; try again in a moment.")
        return
    end
    if not dungeonList and not Build() then
        print(PREFIX .. "couldn't read Questie's quest list.")
        return
    end
    win:Show()
    RefreshList()
    if not selected then
        for _, d in ipairs(dungeonList) do
            if d.areaId == DB.last then selected = d end
        end
        selected = selected or dungeonList[1]
    end
    ShowDungeon(selected)
end

entranceBtn:SetScript("OnClick", function()
    local e = selected and selected.entrance
    if e then ShowOnMap({ kind = "place", name = selected.name, zone = e[1], x = e[2], y = e[3] }) end
end)
hideDone:SetScript("OnClick", function(self)
    DB.hideDone = self:GetChecked() and true or false
    ShowDungeon(selected)
end)

-- keep it current while it's open
local events = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP" }) do
    pcall(events.RegisterEvent, events, e)
end
local queued = false
events:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 == "DungeonQuests" then
            DungeonQuestsDB = DungeonQuestsDB or {}
            DB = DungeonQuestsDB
            hideDone:SetChecked(DB.hideDone and true or false)
        end
        return
    end
    if not win:IsShown() or queued then return end
    queued = true
    C_Timer.After(0.5, function()
        queued = false
        if win:IsShown() then RefreshList(); ShowDungeon(selected) end
    end)
end)

SLASH_DUNGEONQUESTS1 = "/dq"
SLASH_DUNGEONQUESTS2 = "/dungeonquests"
SlashCmdList.DUNGEONQUESTS = function(msg)
    -- /dq resets: which dungeons aren't reset (Resets.lua); /dq resets clear
    local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "resets" and DungeonQuests_Resets then
        DungeonQuests_Resets(rest == "clear")
        return
    end
    if win:IsShown() then win:Hide() else Open() end
end
