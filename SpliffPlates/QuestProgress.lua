-- Spliff Plates: quest progress (Spliff's own addition to this copy of
-- Threat Plates; see NOTICE.md). The plates themselves are Threat Plates'
-- code, renamed; their own options: /splates.
--
-- Quest progress on nameplates: "3/8" just under the health bar, at its
-- right end below the level, on each mob your quests need. Gold while
-- there's more to do, a green tick once it's done. Only objectives in your
-- own quest log count.
--
-- Where the numbers come from, in order:
--   1. the game's own tooltip for that mob, which lists the quest
--      objectives it counts for ("Kobold Vermin slain: 3/8"), drops
--      included;
--   2. otherwise your quest log: an objective that names the mob
--      ("Kobold Vermin slain"), for kill quests.
-- This client can hide unit details from addons in combat; then the plate
-- keeps the last number it had and catches up after the fight.
--
-- Nameplates only show out of combat with "Always Show Nameplates" on
-- (Options > Interface > Nameplates, or Shift+V).
-- /plates turns it on and off.

local PREFIX = "|cffc79c6eSpliff Plates|r "
local isSecret = issecretvalue or function() return false end
local function Str(v) if type(v) == "string" and not isSecret(v) then return v end end
local function Num(v) if type(v) == "number" and not isSecret(v) then return v end end

local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"

---------------------------------------------------------------------------
-- Your quest log's objectives (rebuilt when it changes)
---------------------------------------------------------------------------
local objectives = {} -- { text (lower case), key, cur, max, done }

-- an objective's words only, for matching a tooltip line to it:
-- "Kobold Vermin slain: 3/8" and "- 3/8 Kobold Vermin slain" -> "koboldverminslain"
local function Key(text)
    return (text:lower():gsub("[%d%p%s]", ""))
end

local function ReadQuestLog()
    wipe(objectives)
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo
        and C_QuestLog.GetQuestObjectives) then return end
    local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    for i = 1, (ok and Num(n)) or 0 do
        local okI, info = pcall(C_QuestLog.GetInfo, i)
        info = okI and not isSecret(info) and type(info) == "table" and info or nil
        local id = info and not info.isHeader and Num(info.questID)
        if id then
            local okO, list = pcall(C_QuestLog.GetQuestObjectives, id)
            if okO and type(list) == "table" and not isSecret(list) then
                for _, o in ipairs(list) do
                    local text = type(o) == "table" and Str(o.text)
                    local cur, max = Num(o.numFulfilled), Num(o.numRequired)
                    if text and cur and max and max > 0 then
                        objectives[#objectives + 1] = { text = text:lower(), key = Key(text), cur = cur, max = max,
                            done = o.finished == true or cur >= max }
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- What a nameplate's mob counts for: "3/8", a tick, or nil
---------------------------------------------------------------------------
local QUEST_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective

-- from the game's tooltip data for the unit
local function FromTooltip(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or isSecret(data) or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local best, allDone, any
    for _, line in ipairs(data.lines) do
        local text = type(line) == "table" and Str(line.leftText)
        local lineType = text and Num(line.type)
        local isObjective = text and (QUEST_LINE == nil or lineType == QUEST_LINE or text:find("%d+/%d+"))
        -- only an objective that's in your own quest log counts (a tooltip
        -- can carry other "0/10"s, like quests you don't have)
        local key = isObjective and Key(text)
        local mine = false
        if key and #key >= 4 then
            for _, o in ipairs(objectives) do
                if o.key ~= "" and (o.key == key or o.key:find(key, 1, true) or key:find(o.key, 1, true)) then
                    mine = true
                    break
                end
            end
        end
        if mine then
            local cur, max = text:match("(%d+)%s*/%s*(%d+)")
            cur, max = tonumber(cur), tonumber(max)
            if cur and max and max > 0 then
                any = true
                if cur < max then
                    -- the one with the most left to do
                    if not best or (max - cur) > (best[2] - best[1]) then best = { cur, max } end
                else
                    allDone = true
                end
            end
        end
    end
    if best then return best[1] .. "/" .. best[2] end
    if any and allDone then return TICK end
    return nil
end

-- from your quest log, by the mob's name
local function FromQuestLog(unit)
    local name = Str(UnitName(unit))
    if not name then return nil end
    name = name:lower()
    local best, done
    for _, o in ipairs(objectives) do
        if o.text:find(name, 1, true) then
            if o.done then
                done = true
            elseif not best or (o.max - o.cur) > (best.max - best.cur) then
                best = o
            end
        end
    end
    if best then return best.cur .. "/" .. best.max end
    if done then return TICK end
    return nil
end

local function ProgressFor(unit)
    -- quest mobs only (no players or pets)
    local guid = Str(UnitGUID(unit))
    if not guid then return nil, true end -- hidden right now: keep what's shown
    local kind = guid:match("^(%a+)")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    local text = FromTooltip(unit)
    if text then return text end
    return FromQuestLog(unit)
end

---------------------------------------------------------------------------
-- The labels
---------------------------------------------------------------------------
-- settings (SpliffPlatesDB; set on the Spliff Plates page in /spliffbars)
local DEFAULTS = { enabled = true, size = 13, pos = "right" }
local function Opt(k)
    local db = SpliffPlatesDB
    if type(db) == "table" and db[k] ~= nil then return db[k] end
    return DEFAULTS[k]
end
local function SetOpt(k, v)
    SpliffPlatesDB = SpliffPlatesDB or {}
    SpliffPlatesDB[k] = v
end

local labels = {} -- unit token -> label frame
local spare = {}
local POINTS = { left = { "TOPLEFT", "BOTTOMLEFT", "LEFT" }, center = { "TOP", "BOTTOM", "CENTER" },
    right = { "TOPRIGHT", "BOTTOMRIGHT", "RIGHT" } }

local function GetLabel(unit, plate)
    local f = labels[unit]
    if not f then
        f = table.remove(spare) or CreateFrame("Frame")
        if not f.text then
            f:EnableMouse(false)
            f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f.text:SetShadowOffset(1, -1)
            f.font = f.text:GetFont()
        end
        labels[unit] = f
    end
    local pts = POINTS[Opt("pos")] or POINTS.right
    if f.font then f.text:SetFont(f.font, Opt("size"), "OUTLINE") end
    f.text:ClearAllPoints()
    f.text:SetPoint(pts[1])
    f.text:SetJustifyH(pts[3])
    f:SetParent(plate)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(10)
    f:SetSize(60, Opt("size") + 4)
    f:ClearAllPoints()
    -- just under the health bar, at its right end (below the level).
    -- With Threat Plates the bar is its own: it hands it over through
    -- plate.TPFrame:GetAnchor() (its health bar, or its name when the bar's
    -- hidden, or the game's frame on plates it isn't drawing)
    local bar
    local tp = plate.TPFrame
    if tp and tp.GetAnchor then
        local ok, anchor = pcall(tp.GetAnchor, tp)
        if ok and anchor then bar = anchor end
    end
    if not bar then
        local uf = plate.UnitFrame
        bar = uf and (uf.healthBar or uf.HealthBarsContainer or uf.HealthBar) or plate
    end
    f:SetPoint(pts[1], bar, pts[2], 0, -1)
    return f
end

local function Release(unit)
    local f = labels[unit]
    if not f then return end
    labels[unit] = nil
    f:Hide()
    f:SetParent(nil)
    f:ClearAllPoints()
    spare[#spare + 1] = f
end

local function UpdatePlate(unit)
    if not Opt("enabled") then Release(unit) return end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then Release(unit) return end
    local text, keep = ProgressFor(unit)
    if keep then return end -- the game is hiding it: leave the last number
    if not text then Release(unit) return end
    local f = GetLabel(unit, plate)
    f.text:SetText(text)
    if text == TICK then f.text:SetTextColor(0.4, 1, 0.4) else f.text:SetTextColor(1, 0.82, 0) end
    f:Show()
end

local function UpdateAll()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local seen = {}
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then
            seen[unit] = true
            UpdatePlate(unit)
        end
    end
    for unit in pairs(labels) do
        if not seen[unit] then Release(unit) end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_REGEN_ENABLED" }) do
    pcall(events.RegisterEvent, events, e)
end

local queued = false
local function Soon()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        ReadQuestLog()
        UpdateAll()
    end)
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        if type(unit) == "string" then UpdatePlate(unit) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" then Release(unit) end
    else
        Soon()
    end
end)

-- kills and loot change counts without always touching the quest log
-- right away: a light refresh every second keeps the numbers fresh
local tick = 0
events:SetScript("OnUpdate", function(_, elapsed)
    tick = tick + elapsed
    if tick < 1 then return end
    tick = 0
    if Opt("enabled") then UpdateAll() end
end)

-- /plates why: for your target, where its number comes from
local function Why()
    if not UnitExists("target") then print(PREFIX .. "target the mob first.") return end
    ReadQuestLog()
    print(PREFIX .. "target: " .. tostring(Str(UnitName("target")) or "(hidden)"))
    local ok, data = false, nil
    if C_TooltipInfo and C_TooltipInfo.GetUnit then ok, data = pcall(C_TooltipInfo.GetUnit, "target") end
    if ok and type(data) == "table" and not isSecret(data) and type(data.lines) == "table" then
        for i, line in ipairs(data.lines) do
            local text = type(line) == "table" and Str(line.leftText)
            local key = text and Key(text) or ""
            local match
            if #key >= 4 then
                for _, o in ipairs(objectives) do
                    if o.key ~= "" and (o.key == key or o.key:find(key, 1, true) or key:find(o.key, 1, true)) then
                        match = o.text
                        break
                    end
                end
            end
            print(("  tooltip %d [type %s]: %s%s"):format(i, tostring(type(line) == "table" and Num(line.type)),
                tostring(text or "(hidden)"), match and ("  -> matches \"" .. match .. "\"") or ""))
        end
    else
        print("  tooltip: not available")
    end
    print("  from tooltip: " .. tostring(FromTooltip("target")) .. "; from quest log: " .. tostring(FromQuestLog("target")))
end

SLASH_SPLIFFPLATES1 = "/plates"
SlashCmdList.SPLIFFPLATES = function(msg)
    if msg and msg:lower():match("^%s*why") then Why() return end
    SetOpt("enabled", not Opt("enabled"))
    if Opt("enabled") then Soon() else for unit in pairs(labels) do Release(unit) end end
    print(PREFIX .. "quest progress on nameplates " .. (Opt("enabled") and "on." or "off."))
end

---------------------------------------------------------------------------
-- Its page in Spliffbars' options (/spliffbars > Spliff Plates)
---------------------------------------------------------------------------
local function ShowAlways() -- the game's "Always Show Nameplates"
    local v = GetCVarBool and GetCVarBool("nameplateShowAll")
    return v and true or false
end

local function Redraw()
    for unit in pairs(labels) do Release(unit) end -- (placed afresh with the new look)
    if Opt("enabled") then Soon() end
end

if Spliffbars and Spliffbars.AddOptionsTab then
    Spliffbars.AddOptionsTab("Spliff Plates",
        "Your nameplates (a copy of Threat Plates), and quest progress on them: \"3/8\" under each mob your quests need.",
        function(page)
            local L = page:Column(16, -70)
            page:Heading(L, "Quest Progress")
            page:Check(L, "Show it on nameplates", function() return Opt("enabled") end,
                function(v) SetOpt("enabled", v); Redraw() end)
            local function on() return Opt("enabled") end
            page:Choice(L, "Under the health bar, at the", { { "Left", "left" }, { "Centre", "center" }, { "Right", "right" } },
                function() return Opt("pos") end, function(v) SetOpt("pos", v); Redraw() end, on)
            page:Slider(L, "Text size", 8, 24, 1, function() return Opt("size") end,
                function(v) SetOpt("size", v); Redraw() end, nil, on)

            local R = page:Column(340, -70)
            page:Heading(R, "Nameplates")
            page:Check(R, "Always show nameplates", ShowAlways, function(v)
                if InCombatLockdown() then print(PREFIX .. "that can only change out of combat.") return end
                SetCVar("nameplateShowAll", v and "1" or "0")
            end)
            page:Note(R, "The game's own setting: without it, nameplates show only in combat.", 20)
            page:Heading(R, "The Plates")
            page:Note(R, "Their look, colours, threat and widgets have their own (large) options window.")
            page:Button(R, "Open Plate Options", function()
                if SlashCmdList and SlashCmdList.ACECONSOLE_SPLATES then
                    SlashCmdList.ACECONSOLE_SPLATES("")
                else
                    print(PREFIX .. "type /splates for the plates' own options.")
                end
            end)
        end)
end
