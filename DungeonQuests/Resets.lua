-- Dungeon Quests: resets
-- Never walk into a dungeon you already cleared.
--
-- Once you've been inside a dungeon, it counts as NOT reset until the game
-- says "<dungeon> has been reset." (resetting: right-click your portrait,
-- Reset all instances, as leader or solo, outside). Until then:
--   * walking up to its entrance, a warning sits under your minimap:
--     "The Deadmines: not reset (in it 40m ago)", with a sound the first
--     time; right-click the warning if you know it was reset some other way;
--   * zoning in to it, a big warning on screen and in chat.
-- (Not while you're a ghost: a corpse run back in is meant.)
--
-- Also counts the dungeons you've started this hour (the game allows 5 an
-- hour); the count shows in the warning, and /dq resets lists everything.
--
-- If someone else leads and resets, you may not see the message: clear it
-- with a right-click or /dq resets clear. Kept per character.

local PREFIX = "|cffc79c6eDungeon Quests|r "
local NEAR = 200          -- yards from an entrance that count as "approaching"
local HOUR_LIMIT = 5      -- dungeons the game lets you start in an hour
local isSecret = issecretvalue or function() return false end

-- a dungeon's name made comparable: "The Deadmines" / "Deadmines" -> "deadmines"
local function Norm(name)
    if type(name) ~= "string" or isSecret(name) then return nil end
    return (name:lower():gsub("^the ", ""):gsub("[^%w]", ""))
end

local function CharKey()
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    return (name or UnitName("player") or "?") .. "-" .. (realm or (GetRealmName and GetRealmName()) or "")
end

-- this character's records: dirty[key] = { name, entered, left }, started = { times }
local function Store()
    DungeonQuestsDB = DungeonQuestsDB or {}
    local db = DungeonQuestsDB
    db.resets = db.resets or {}
    local key = CharKey()
    db.resets[key] = db.resets[key] or { dirty = {}, started = {} }
    return db.resets[key]
end

local function Ago(t)
    local s = math.max(0, time() - (t or time()))
    if s < 60 then return "just now" end
    if s < 3600 then return math.floor(s / 60) .. "m ago" end
    return math.floor(s / 3600) .. "h " .. math.floor(s % 3600 / 60) .. "m ago"
end

-- dungeons started in the last hour (and forget older ones)
local function ThisHour()
    local st = Store().started
    local cutoff = time() - 3600
    for i = #st, 1, -1 do if st[i] < cutoff then table.remove(st, i) end end
    return #st
end

---------------------------------------------------------------------------
-- Dungeon entrances, from Questie's zone data: key -> { name, places }
-- (places: { uiMap, x, y } with x, y from 0 to 1)
---------------------------------------------------------------------------
local entrances

local function ZoneDB()
    if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
    local ok, z = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    return ok and z or nil
end

local function Entrances()
    if entrances then return entrances end
    local z = ZoneDB()
    if not (z and z.GetDungeons) then return nil end
    local ok, dungeons = pcall(z.GetDungeons, z)
    if not ok or type(dungeons) ~= "table" then return nil end
    entrances = {}
    for areaId, entry in pairs(dungeons) do
        local name = (C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaId)) or entry[1]
        local key = Norm(name)
        if key and type(entry[4]) == "table" then
            local places = {}
            for _, loc in ipairs(entry[4]) do
                if type(loc) == "table" and loc[1] and loc[2] and loc[3] then
                    local okM, uiMap = pcall(z.GetUiMapIdByAreaId, z, loc[1])
                    if okM and uiMap then places[#places + 1] = { uiMap = uiMap, x = loc[2] / 100, y = loc[3] / 100 } end
                end
            end
            if #places > 0 then
                entrances[key] = { name = name, places = places }
                -- (the English name too, in case the game's differs)
                local en = Norm(entry[1])
                if en and en ~= key and not entrances[en] then entrances[en] = entrances[key] end
            end
        end
    end
    return entrances
end

---------------------------------------------------------------------------
-- Inside a dungeon: it's not reset from now on
---------------------------------------------------------------------------
local inside -- the key of the dungeon you're in, or nil

local function Alert(text)
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo.RAID_WARNING)
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
    print(PREFIX .. text)
end

local function Ghost()
    local g = UnitIsDeadOrGhost("player")
    return not isSecret(g) and g == true
end

local function CheckInstance()
    local name, kind = GetInstanceInfo()
    local key = kind == "party" and Norm(name) or nil
    if key == inside then return end
    local s = Store()
    if inside and s.dirty[inside] then s.dirty[inside].left = time() end -- (just came out)
    inside = key
    if not key then return end
    local rec = s.dirty[key]
    if rec then
        -- back in one you haven't reset (after leaving it: a /reload or
        -- relog inside doesn't count, nor does a corpse run)
        if rec.left and not Ghost() then
            Alert(("|cffff4040%s was NOT reset|r: you were in it %s. Its mobs may already be dead.")
                :format(rec.name or name, Ago(rec.left or rec.entered)))
        end
        rec.left = nil
    else
        -- a fresh one: it counts toward the hour, and isn't reset from now on
        s.dirty[key] = { name = name, entered = time() }
        s.started[#s.started + 1] = time()
        local n = ThisHour()
        if n >= HOUR_LIMIT - 1 then
            print(PREFIX .. ("dungeons started this hour: %d of %d."):format(n, HOUR_LIMIT))
        end
    end
end

-- "The Deadmines has been reset." (and the "all instances" form)
local resetPattern
local function ResetMessage(msg)
    if isSecret(msg) or type(msg) ~= "string" then return end
    if not resetPattern and type(INSTANCE_RESET_SUCCESS) == "string" then
        -- the game's "%s has been reset." as a pattern: the name in (.+)
        local p = INSTANCE_RESET_SUCCESS:gsub("%%s", "\001")
        p = p:gsub("([%(%)%.%-%+%*%?%[%]%^%$%%])", "%%%1")
        resetPattern = "^" .. p:gsub("\001", "(.+)") .. "$"
    end
    local name = resetPattern and msg:match(resetPattern)
    local key = Norm(name)
    if key and Store().dirty[key] then
        Store().dirty[key] = nil
        print(PREFIX .. name .. " is reset: fresh next time.")
    end
end

---------------------------------------------------------------------------
-- Approaching an entrance: a warning under the minimap
---------------------------------------------------------------------------
local warn = CreateFrame("Button", "DungeonQuestsResetWarning", UIParent)
warn:SetSize(220, 34)
warn:SetFrameStrata("MEDIUM")
warn:RegisterForClicks("RightButtonUp")
warn:Hide()
do
    local bg = warn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.25, 0.02, 0.02, 0.85)
    local edge = warn:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("TOPRIGHT")
    edge:SetHeight(1)
    edge:SetColorTexture(1, 0.3, 0.3, 0.9)
    local edge2 = warn:CreateTexture(nil, "BORDER")
    edge2:SetPoint("BOTTOMLEFT")
    edge2:SetPoint("BOTTOMRIGHT")
    edge2:SetHeight(1)
    edge2:SetColorTexture(1, 0.3, 0.3, 0.9)
end
warn.title = warn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
warn.title:SetPoint("TOP", 0, -4)
warn.title:SetTextColor(1, 0.45, 0.45)
warn.sub = warn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
warn.sub:SetPoint("TOP", warn.title, "BOTTOM", 0, -2)

local function PlaceWarning()
    warn:ClearAllPoints()
    if Minimap and Minimap:IsVisible() then
        warn:SetPoint("TOP", Minimap, "BOTTOM", 0, -18)
    else
        warn:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

warn:SetScript("OnClick", function(self)
    if self.key then
        Store().dirty[self.key] = nil
        print(PREFIX .. (self.name or "it") .. " marked as reset.")
        self:Hide()
    end
end)
warn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(self.name or "Dungeon", 1, 0.45, 0.45)
    GameTooltip:AddLine("You've been in it since it was last reset.", 1, 1, 1, true)
    GameTooltip:AddLine("Reset: right-click your portrait, Reset all instances (as leader, or solo).", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Right-click here if it was reset some other way.", 0.5, 0.8, 1, true)
    GameTooltip:Show()
end)
warn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- yards between you and a spot on a map (nil when you're not on that map)
local function Yards(place)
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetMapWorldSize) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, place.uiMap, "player")
    if not ok or not pos or isSecret(pos) then return nil end
    local px, py = pos:GetXY()
    if not px or isSecret(px) or (px == 0 and py == 0) then return nil end
    local okW, w, h = pcall(C_Map.GetMapWorldSize, place.uiMap)
    if not okW or not w or w == 0 then return nil end
    local dx, dy = (px - place.x) * w, (py - place.y) * h
    return math.sqrt(dx * dx + dy * dy)
end

local warnedFor -- the dungeon whose warning sounded (once per approach)

local function CheckNearby()
    if inside or Ghost() then warn:Hide() return end
    local s = Store()
    local list = next(s.dirty) and Entrances()
    if not list then warn:Hide() warnedFor = nil return end
    for key, rec in pairs(s.dirty) do
        local e = list[key]
        if e then
            for _, place in ipairs(e.places) do
                local d = Yards(place)
                if d and d <= NEAR then
                    warn.key, warn.name = key, rec.name or e.name
                    warn.title:SetText((rec.name or e.name) .. ": NOT reset")
                    warn.sub:SetText(("in it %s  -  this hour: %d/%d"):format(Ago(rec.left or rec.entered), ThisHour(), HOUR_LIMIT))
                    warn:SetWidth(math.max(220, warn.title:GetStringWidth() + 24, warn.sub:GetStringWidth() + 24))
                    PlaceWarning()
                    if not warn:IsShown() then warn:Show() end
                    if warnedFor ~= key then
                        warnedFor = key
                        if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
                    end
                    return
                end
            end
        end
    end
    warn:Hide()
    warnedFor = nil
end

---------------------------------------------------------------------------
-- /dq resets: the list; /dq resets clear: forget them all
---------------------------------------------------------------------------
local function List(clear)
    local s = Store()
    if clear then
        wipe(s.dirty)
        print(PREFIX .. "all dungeons marked as reset.")
        warn:Hide()
        return
    end
    local any = false
    for _, rec in pairs(s.dirty) do
        any = true
        print(PREFIX .. "|cffff6060not reset|r  " .. (rec.name or "?") .. "  (in it " .. Ago(rec.left or rec.entered) .. ")")
    end
    if not any then print(PREFIX .. "every dungeon you've been in is reset.") end
    print(PREFIX .. ("dungeons started this hour: %d of %d."):format(ThisHour(), HOUR_LIMIT))
end
_G.DungeonQuests_Resets = List -- (the /dq command hands "resets" to this)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_SYSTEM" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, msg)
    if event == "CHAT_MSG_SYSTEM" then
        ResetMessage(msg)
    else
        C_Timer.After(1, CheckInstance) -- (the instance's name settles a moment after zoning)
    end
end)
C_Timer.NewTicker(1, CheckNearby)
