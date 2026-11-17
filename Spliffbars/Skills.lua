-- Spliffbars: Weapon Skills and Trade Skills
-- Two rows of tiny bars, each about as wide as a small icon, with that
-- skill's icon at its foot. Each row is its own Edit Mode frame (they start
-- along the bottom of the screen) with its own settings: which way the row
-- runs, which way the bars grow, icon size, bar length, which skills.
--
-- Colours: steel blue weapon skills, green professions, orange secondary
-- skills (Cooking, First Aid, Fishing), gold when a skill is at its cap.
--
-- Hover a bar for its numbers. Click a trade skill to open its window
-- (Mining opens Smelting; Herbalism, Skinning and Fishing have no window).
-- Click a weapon skill to open the Skills tab of your character panel.

local _, ns = ...
local LEM, isSecret, Num = ns.LEM, ns.isSecret, ns.Num

local COLORS = {
    weapon = { 0.45, 0.62, 0.9 }, prof = { 0.35, 0.8, 0.35 }, second = { 1, 0.6, 0.2 }, capped = { 1, 0.82, 0 },
}
-- weapon skill-up motes fly red (lift: kept close to the red, not paled)
local WEAPON_MOTE, WEAPON_MOTE_LIFT = { 1, 0.12, 0.08 }, 0.15
-- each trade skill's mote has its own colour (others: the bar's colour)
local TRADE_MOTES = {
    ["Alchemy"]        = { 0.2, 1, 0.55 },   -- bubbling green
    ["Blacksmithing"]  = { 1, 0.45, 0.1 },   -- forge ember
    ["Enchanting"]     = { 0.75, 0.35, 1 },  -- arcane violet
    ["Engineering"]    = { 1, 0.8, 0.2 },    -- brass spark
    ["Herbalism"]      = { 0.3, 1, 0.15 },   -- bright leafy green
    ["Leatherworking"] = { 0.85, 0.55, 0.3 },-- tan
    ["Mining"]         = { 0.55, 0.57, 0.6 }, -- dark silver
    ["Skinning"]       = { 0.42, 0.26, 0.13 },-- dark brown
    ["Tailoring"]      = { 1, 0.4, 0.75 },   -- silk pink
    ["Jewelcrafting"]  = { 0.3, 0.9, 1 },    -- gem cyan
    ["Inscription"]    = { 0.35, 0.5, 1 },   -- ink blue
    ["Cooking"]        = { 1, 0.65, 0.25 },  -- campfire orange
    ["First Aid"]      = { 1, 0.95, 0.95 },  -- clean white (red is the weapons')
    ["Fishing"]        = { 0.25, 0.7, 1 },   -- water blue
}
local function SendSkillMote(b, d, c, land)
    if d.cat == "weapon" then
        ns.SendMote(b, WEAPON_MOTE, land, WEAPON_MOTE_LIFT)
    elseif TRADE_MOTES[d.name] then
        ns.SendMote(b, TRADE_MOTES[d.name], land, 0.2)
    else
        ns.SendMote(b, c, land)
    end
end

-- the colour a row's settings give a skill ("Bar Colour", "Capped Colour",
-- ...; saved as { r, g, b }), else the one above
local COLOR_FIELD = { weapon = "color", prof = "profColor", second = "secondColor", capped = "cappedColor" }
local function ColorOf(l, which)
    local c = l[COLOR_FIELD[which]]
    if type(c) == "table" and c[1] then return c end
    return COLORS[which]
end

local ICONS = {
    -- weapons
    ["Axes"] = "INV_Axe_04", ["Two-Handed Axes"] = "INV_Axe_09",
    ["Swords"] = "INV_Sword_04", ["Two-Handed Swords"] = "INV_Sword_39",
    ["Maces"] = "INV_Mace_01", ["Two-Handed Maces"] = "INV_Hammer_09",
    ["Daggers"] = "INV_Weapon_ShortBlade_05", ["Staves"] = "INV_Staff_08", ["Polearms"] = "INV_Spear_06",
    ["Bows"] = "INV_Weapon_Bow_05", ["Guns"] = "INV_Weapon_Rifle_01", ["Crossbows"] = "INV_Weapon_Crossbow_01",
    ["Thrown"] = "INV_ThrowingKnife_02", ["Wands"] = "INV_Wand_01", ["Fist Weapons"] = "INV_Gauntlets_04",
    ["Unarmed"] = "INV_Gauntlets_05", ["Defense"] = "Ability_Defend",
    -- trades
    ["Alchemy"] = "Trade_Alchemy", ["Blacksmithing"] = "Trade_BlackSmithing", ["Enchanting"] = "Trade_Engraving",
    ["Engineering"] = "Trade_Engineering", ["Herbalism"] = "INV_Misc_Flower_02",
    ["Leatherworking"] = "INV_Misc_ArmorKit_17", ["Mining"] = "Trade_Mining", ["Skinning"] = "INV_Misc_Pelt_Wolf_01",
    ["Tailoring"] = "Trade_Tailoring", ["Jewelcrafting"] = "INV_Misc_Gem_01",
    ["Inscription"] = "INV_Inscription_Tradeskill01", ["Cooking"] = "INV_Misc_Food_15",
    ["First Aid"] = "Spell_Holy_SealOfSacrifice", ["Fishing"] = "Trade_Fishing", ["Riding"] = "Spell_Nature_Swiftness",
}

-- the spell that opens each trade's window
local OPENS = {
    ["Alchemy"] = "Alchemy", ["Blacksmithing"] = "Blacksmithing", ["Enchanting"] = "Enchanting",
    ["Engineering"] = "Engineering", ["Leatherworking"] = "Leatherworking", ["Tailoring"] = "Tailoring",
    ["Jewelcrafting"] = "Jewelcrafting", ["Inscription"] = "Inscription", ["Cooking"] = "Cooking",
    ["First Aid"] = "First Aid", ["Mining"] = "Smelting",
}

local DEFAULTS = {
    -- scale: how much of the skill a weapon bar covers
    --   smart   zooms in as you close in on the cap (see SmartWindow)
    --   levels  your last "zoom" levels of skill (5 points a level)
    --   whole   0 to the cap
    weapon = { dir = "RIGHT", flip = false, icon = 14, length = 30, gap = 2, icons = true, show = "hands", thick = 0, mote = true,
        scale = "smart", zoom = 5 },
    trade = { dir = "RIGHT", flip = false, icon = 14, length = 30, gap = 2, icons = true, show = "all", thick = 0, art = true, mote = true },
}
local DEFAULT_POS = {
    weapon = { point = "BOTTOM", x = -360, y = 6 },
    trade = { point = "BOTTOM", x = 360, y = 6 },
}

local DB, layoutName
local function Look(kind) return ns.Look(DB, layoutName, kind, DEFAULTS[kind]) end

---------------------------------------------------------------------------
-- Reading skills (the classic skills list)
---------------------------------------------------------------------------
local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- weapon type (item subclass) -> its skill
local SUBCLASS_SKILL = {
    [0] = "Axes", [1] = "Two-Handed Axes", [2] = "Bows", [3] = "Guns", [4] = "Maces", [5] = "Two-Handed Maces",
    [6] = "Polearms", [7] = "Swords", [8] = "Two-Handed Swords", [10] = "Staves", [13] = "Fist Weapons",
    [15] = "Daggers", [16] = "Thrown", [18] = "Crossbows", [19] = "Wands",
}

-- the weapon skills for what you're holding: your hands (main and off
-- hand), plus your ranged slot when ranged is true; Unarmed with nothing
local function EquippedWeaponSkills(ranged)
    local set, any = {}, false
    for _, slot in ipairs(ranged and { 16, 17, 18 } or { 16, 17 }) do
        local id = GetInventoryItemID("player", slot)
        if Num(id) and getInstant then
            local ok, _, _, sub, _, _, classID, subclassID = pcall(getInstant, id)
            if ok and classID == 2 and SUBCLASS_SKILL[subclassID] then
                set[SUBCLASS_SKILL[subclassID]] = true
                any = true
            elseif ok and type(sub) == "string" and not isSecret(sub) then
                set[(sub:gsub("^One%-Handed ", ""))] = true -- (by its name, if the type is unknown)
            end
            if slot ~= 18 and ok and classID == 2 then any = true end
        end
    end
    if not any then set["Unarmed"] = true end
    return set
end

local allWeapons = {} -- every weapon skill, for the tooltip

local sessionStart = {} -- rank when first seen this session, for "+N this session"

-- WoW Forever lists skills through C_SkillInfo (one table per line); older
-- clients through the GetSkillLineInfo globals (a list of values)
local SI = C_SkillInfo
local NumLines = (SI and SI.GetNumSkillLines) or GetNumSkillLines
local LineInfo = (SI and SI.GetSkillLineInfo) or GetSkillLineInfo
local ExpandHeader = (SI and SI.ExpandSkillHeader) or ExpandSkillHeader

local WEAPON_NAMES = {}
for _, n in ipairs({ "Axes", "Two-Handed Axes", "Swords", "Two-Handed Swords", "Maces", "Two-Handed Maces",
    "Daggers", "Staves", "Polearms", "Bows", "Guns", "Crossbows", "Thrown", "Wands", "Fist Weapons", "Unarmed",
    "Defense" }) do WEAPON_NAMES[n] = true end
local SECONDARY = { ["Cooking"] = true, ["First Aid"] = true, ["Fishing"] = true, ["Riding"] = true }
local PROFS = {}
for _, n in ipairs({ "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking",
    "Mining", "Skinning", "Tailoring", "Jewelcrafting", "Inscription" }) do PROFS[n] = true end

-- one skill line as name, isHeader, collapsed, rank, max, modifier
local function Line(i)
    local ok, a, b, c, d, _, f, g = pcall(LineInfo, i)
    if not ok then return end
    if isSecret(a) then return end
    if type(a) == "table" then
        local t = a
        return t.name, t.isHeader, t.isCollapsed or (t.isExpanded == false),
            t.rank or t.skillRank, t.maxRank or t.skillMaxRank or t.max, t.modifier or t.skillModifier or 0
    end
    return a, b, c == false, d, g, f
end

local expandedOnce = {}

local function ReadSkills()
    local weapons, trades = {}, {}
    local scan = {}
    if NumLines and LineInfo then
        local ok, n = pcall(NumLines)
        n = (ok and Num(n)) and n or 0
        -- a heading collapsed in the skills window hides its skills: open
        -- each one once (back to front, as opening adds lines after it)
        if ExpandHeader and not InCombatLockdown() then
            for i = n, 1, -1 do
                local name, isHeader, collapsed = Line(i)
                if isHeader and collapsed and type(name) == "string" and not expandedOnce[name] then
                    expandedOnce[name] = true
                    pcall(ExpandHeader, i)
                end
            end
            ok, n = pcall(NumLines)
            n = (ok and Num(n)) and n or 0
        end
        local header
        for i = 1, n do
            local name, isHeader, _, rank, maxRank, mod = Line(i)
            if type(name) == "string" then
                if #scan < 60 then
                    scan[#scan + 1] = name .. (isHeader and " [header]" or (" " .. tostring(rank) .. "/" .. tostring(maxRank)))
                end
                if isHeader then
                    header = name
                elseif Num(rank) and Num(maxRank) and maxRank > 1 then
                    local h = type(header) == "string" and header or ""
                    local cat = ((WEAPON_NAMES[name] or h:find("Weapon")) and "weapon")
                        or ((PROFS[name] or h:find("Profession")) and "prof")
                        or ((SECONDARY[name] or h:find("Secondary")) and "second") or nil
                    if cat then
                        local d = { name = name, rank = rank, max = maxRank, mod = Num(mod) and mod or 0, cat = cat }
                        sessionStart[name] = sessionStart[name] or rank
                        if cat == "weapon" then weapons[#weapons + 1] = d else trades[#trades + 1] = d end
                    end
                end
            end
        end
    end
    if DB then DB.lastScan = scan end -- what the skill list said, for troubleshooting
    -- professions: the profession list where there is one (it has their icons)
    if GetProfessions and GetProfessionInfo then
        wipe(trades)
        local ok, p1, p2, arch, fish, cook = pcall(GetProfessions)
        if ok then
            for _, idx in ipairs({ p1 or 0, p2 or 0, cook or 0, fish or 0, arch or 0 }) do
                if idx ~= 0 then
                    local ok2, name, icon, rank, maxRank = pcall(GetProfessionInfo, idx)
                    if ok2 and type(name) == "string" and Num(rank) and Num(maxRank) then
                        sessionStart[name] = sessionStart[name] or rank
                        trades[#trades + 1] = { name = name, rank = rank, max = maxRank, mod = 0, icon = icon,
                            cat = (idx == p1 or idx == p2) and "prof" or "second" }
                    end
                end
            end
        end
    end
    table.sort(weapons, function(a, b)
        if a.name == "Defense" or b.name == "Defense" then return b.name == "Defense" end
        return a.name < b.name
    end)
    table.sort(trades, function(a, b)
        if a.cat ~= b.cat then return a.cat == "prof" end
        return a.name < b.name
    end)
    allWeapons = weapons
    return weapons, trades
end

local function KnownSpell(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        return ok and ns.Tbl(info) ~= nil
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, name)
        return ok and n ~= nil
    end
    return false
end

local function SkillIcon(d)
    if d.icon then return d.icon end
    if ICONS[d.name] then return ns.Icon(ICONS[d.name]) end
    local tex
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, d.name)
        if ok then tex = t end
    elseif GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, d.name)
        if ok then tex = t end
    end
    return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function OpenSkillsTab()
    if not ToggleCharacter then return end
    if _G.SkillFrame then ToggleCharacter("SkillFrame") else ToggleCharacter("PaperDollFrame") end
end

---------------------------------------------------------------------------
-- A row of bars
---------------------------------------------------------------------------
local rows = {}

---------------------------------------------------------------------------
-- Trade bars wear the game's own profession bar art: the animated fill
-- from the profession window's rank bar ("Skillbar_Fill_Flipbook_<kit>",
-- a sheet of frames 2 across, each 34 pixels high, played at 30 a second)
-- and its flare at the end of the fill ("Skillbar_Flare_<kit>"). The kit is
-- the profession's name without spaces (FirstAid); others get the game's
-- DefaultBlue. Standing bars get the art turned a quarter turn (by texture
-- coordinates, so it isn't squashed). Where the client has no such art,
-- the bars keep their plain colours.
---------------------------------------------------------------------------
local FRAME_H, COLS, FPS = 34, 2, 30
local FLARE_ASPECT = 53 / 16 -- the flare's width to its height, as the game draws it

local function AtlasInfo(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    info = ok and ns.Tbl(info) or nil
    if info and info.file and Num(info.leftTexCoord) then return info end
end

local artCache = {}
local function TradeArt(skillName)
    if artCache[skillName] ~= nil then return artCache[skillName] or nil end
    local kit = skillName:gsub("%s", "")
    local fill = AtlasInfo("Skillbar_Fill_Flipbook_" .. kit) or AtlasInfo("Skillbar_Fill_Flipbook_DefaultBlue")
    local art = false
    if fill and Num(fill.height) and fill.height >= FRAME_H then
        local rows = math.max(1, math.floor(fill.height / FRAME_H + 0.5))
        art = { fill = fill, rows = rows, frames = rows * COLS, flare = AtlasInfo("Skillbar_Flare_" .. kit),
            frameW = (Num(fill.width) and fill.width > 0) and fill.width / COLS or 441 }
    end
    artCache[skillName] = art
    return art or nil
end

-- show part of a texture sheet (l, r, t, b) on a bar, the whole of it
-- stretched to fill the bar and turned to match the way the bar grows
-- (the art's left end is where the fill starts):
--   grows right  as it is            grows left  turned 180
--   grows up     turned 90 left      grows down  turned 90 right
local function SetCoords(tex, l, r, t, b, standing, flipped)
    -- corners: top-left, bottom-left, top-right, bottom-right of the bar
    if standing then
        if flipped then
            tex:SetTexCoord(l, b, r, b, l, t, r, t) -- 90 right: the art's start at the top
        else
            tex:SetTexCoord(r, t, l, t, r, b, l, b) -- 90 left: the art's start at the bottom
        end
    elseif flipped then
        tex:SetTexCoord(r, l, b, t) -- 180: the art's start at the right
    else
        tex:SetTexCoord(l, r, t, b) -- as it is
    end
end

local function ShowFrame(b, i)
    local a, f = b.art, b.art.fill
    local L, R, T, B = f.leftTexCoord, f.rightTexCoord, f.topTexCoord, f.bottomTexCoord
    local col, row = i % COLS, math.floor(i / COLS)
    -- the whole strip, end to end along the bar (turned upright on a
    -- standing bar, by SetCoords)
    local u0 = L + (R - L) * col / COLS
    local u1 = u0 + (R - L) / COLS
    SetCoords(b.sb.grad, u0, u1,
        T + (B - T) * row / a.rows, T + (B - T) * (row + 1) / a.rows,
        b.standing, b.flipped)
end

-- the animation runs on the status bar (not the button: the trade bars are
-- secure buttons, which can't take new scripts in combat)
local function AnimStep(sb)
    local b = sb.owner
    if not b.art then sb:SetScript("OnUpdate", nil); return end
    local i = math.floor((GetTime() - b.animStart) * FPS)
    if i >= b.art.frames then
        if b.animLoop then
            i = i % b.art.frames
        else
            i = b.art.frames - 1
            sb:SetScript("OnUpdate", nil)
        end
    end
    ShowFrame(b, i)
end

local function Animate(b, loop)
    if not b.art then return end
    b.animStart, b.animLoop = GetTime(), loop
    b.sb:SetScript("OnUpdate", AnimStep)
end

local function StopAnimation(b)
    b.sb:SetScript("OnUpdate", nil)
    if b.art then ShowFrame(b, b.art.frames - 1) end
end

-- put the art (or the plain colours) on a trade bar
local function DressBar(b, d, standing, flipped, thick, len)
    local art = TradeArt(d.name)
    b.standing, b.flipped = standing, flipped
    b.artThick, b.artLen = thick, len
    local grad = b.sb.grad
    if not art then
        if b.art then grad:SetTexture(ns.WHITE); grad:SetTexCoord(0, 1, 0, 1) end
        b.art = nil
        b.flare:Hide()
        return false
    end
    if b.art ~= art then
        b.art = art
        grad:SetTexture(art.fill.file)
        ns.Gradient(grad, "VERTICAL", 1, 1, 1, 1, 1, 1, 1, 1) -- no tint
    end
    if not b.sb:GetScript("OnUpdate") then ShowFrame(b, art.frames - 1) end
    -- the flare, at the end of the fill (gone once the bar is full)
    local fl = art.flare
    if fl and d.rank < d.max then
        b.flare:SetTexture(fl.file)
        SetCoords(b.flare, fl.leftTexCoord, fl.rightTexCoord, fl.topTexCoord, fl.bottomTexCoord, standing, flipped)
        b.flare:ClearAllPoints()
        if standing then
            b.flare:SetSize(thick, thick * FLARE_ASPECT)
            b.flare:SetPoint(flipped and "BOTTOM" or "TOP", b.sb.clip, flipped and "BOTTOM" or "TOP")
        else
            b.flare:SetSize(thick * FLARE_ASPECT, thick)
            b.flare:SetPoint(flipped and "LEFT" or "RIGHT", b.sb.clip, flipped and "LEFT" or "RIGHT")
        end
        b.flare:Show()
    else
        b.flare:Hide()
    end
    return true
end

local function Tooltip(self)
    local d = self.data
    if not d then return end
    if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else GameTooltip:SetOwner(self, "ANCHOR_TOP") end
    local capped = d.rank >= d.max
    local c = capped and COLORS.capped or COLORS[d.cat]
    GameTooltip:AddLine(d.name, c[1], c[2], c[3])
    GameTooltip:AddDoubleLine("Skill", d.rank .. " / " .. d.max .. (d.mod ~= 0 and ("  (+" .. d.mod .. ")") or ""),
        1, 0.82, 0, 1, 1, 1)
    local gained = d.rank - (sessionStart[d.name] or d.rank)
    if gained > 0 then GameTooltip:AddDoubleLine("This session", "+" .. gained, 1, 0.82, 0, 0.4, 1, 0.4) end
    if d.cat == "weapon" and d.name ~= "Defense" then
        local level = UnitLevel("player")
        if Num(level) then GameTooltip:AddDoubleLine("Max at your level", level * 5, 1, 0.82, 0, 1, 1, 1) end
    end
    if capped then
        if d.cat == "weapon" then
            GameTooltip:AddLine("At its cap: it rises as you level.", 1, 0.82, 0)
        else
            GameTooltip:AddLine("At its cap: see a trainer for the next rank.", 1, 0.82, 0)
        end
    elseif d.cat == "weapon" then
        GameTooltip:AddLine((d.max - d.rank) .. " to go", 0.8, 0.8, 0.8)
    end
    if d.cat == "weapon" and self.window and self.window < d.max then
        GameTooltip:AddLine("The bar shows " .. (d.max - self.window) .. " to " .. d.max, 0.6, 0.6, 0.6)
    end
    -- every other weapon skill you have
    if d.cat == "weapon" and #allWeapons > 1 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("All weapon skills", 1, 0.82, 0)
        for _, w in ipairs(allWeapons) do
            local mine = w.name == d.name
            local wc = w.rank >= w.max and COLORS.capped or (mine and { 1, 1, 1 } or { 0.75, 0.75, 0.75 })
            GameTooltip:AddDoubleLine("   " .. (mine and "> " or "") .. w.name, w.rank .. " / " .. w.max,
                wc[1], wc[2], wc[3], wc[1], wc[2], wc[3])
        end
    end
    GameTooltip:AddLine(" ")
    if d.cat == "weapon" then
        GameTooltip:AddLine("Click: your skills", 0.6, 0.8, 1)
    elseif self.opens then
        GameTooltip:AddLine("Click: open " .. self.opens, 0.6, 0.8, 1)
    else
        GameTooltip:AddLine("No window for this one", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- the skill-up flourish, in the bar's colour, along the way it grows
local function Flourish(b, gain, c)
    local standing, flipped = b.standing, b.flipped
    local len = standing and b.sb:GetHeight() or b.sb:GetWidth()
    local thick = standing and b.sb:GetWidth() or b.sb:GetHeight()
    if not len or len <= 0 then return end
    local tail = math.max(10, len * 0.35)
    -- light, a touch of the bar's colour
    local r, g, bl = 0.6 + c[1] * 0.4, 0.6 + c[2] * 0.4, 0.6 + c[3] * 0.4
    local s = b.streak
    s:ClearAllPoints()
    if standing then
        s:SetSize(thick, tail)
        -- comet: faint tail behind, bright head in front
        if flipped then
            s:SetPoint("BOTTOM", b.sb, "TOP", 0, 0)
            ns.Gradient(s, "VERTICAL", r, g, bl, 0.9, r, g, bl, 0)
            b.streakMove:SetOffset(0, -(len + tail))
        else
            s:SetPoint("TOP", b.sb, "BOTTOM", 0, 0)
            ns.Gradient(s, "VERTICAL", r, g, bl, 0, r, g, bl, 0.9)
            b.streakMove:SetOffset(0, len + tail)
        end
    else
        s:SetSize(tail, thick)
        if flipped then
            s:SetPoint("LEFT", b.sb, "RIGHT", 0, 0)
            ns.Gradient(s, "HORIZONTAL", r, g, bl, 0.9, r, g, bl, 0)
            b.streakMove:SetOffset(-(len + tail), 0)
        else
            s:SetPoint("RIGHT", b.sb, "LEFT", 0, 0)
            ns.Gradient(s, "HORIZONTAL", r, g, bl, 0, r, g, bl, 0.9)
            b.streakMove:SetOffset(len + tail, 0)
        end
    end
    b.glow:SetVertexColor(r, g, bl)
    -- "+1" off the end the bar grows toward, drifting away from it
    b.plus:SetText("+" .. gain)
    b.plus:ClearAllPoints()
    if standing then
        b.plus:SetPoint(flipped and "TOP" or "BOTTOM", b.edge, flipped and "BOTTOM" or "TOP", 0, flipped and -2 or 2)
        b.plusMove:SetOffset(0, flipped and -14 or 14)
    else
        b.plus:SetPoint(flipped and "RIGHT" or "LEFT", b.edge, flipped and "LEFT" or "RIGHT", flipped and -3 or 3, 0)
        b.plusMove:SetOffset(0, 12)
    end
    for _, a in ipairs({ b.streakAnim, b.glowAnim, b.plusAnim }) do a:Stop(); a:Play() end
    if b.icon:IsShown() then b.iconPop:Stop(); b.iconPop:Play() end
end

local function NewBar(row)
    local b
    if row.secure then
        b = CreateFrame("Button", nil, row.frame, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
    else
        b = CreateFrame("Button", nil, row.frame)
        b:RegisterForClicks("AnyUp")
        b:SetScript("OnClick", OpenSkillsTab)
    end
    local edge = b:CreateTexture(nil, "BACKGROUND", nil, 0)
    b.edge = edge
    edge:SetColorTexture(0, 0, 0, 0.85)
    local back = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.back = back
    back:SetColorTexture(0.1, 0.1, 0.12, 0.8)
    b.sb = CreateFrame("StatusBar", nil, b)
    ns.SmoothFill(b.sb)
    b.iconEdge = b:CreateTexture(nil, "BACKGROUND", nil, 0)
    b.iconEdge:SetColorTexture(0, 0, 0, 0.9)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetPoint("TOPLEFT", b.iconEdge, "TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", b.iconEdge, "BOTTOMRIGHT", -1, 1)
    -- the skill-up flourish (see Flourish): a streak along the bar, a glow
    -- around it, the icon popping, and "+1" floating off
    local fx = CreateFrame("Frame", nil, b)
    fx:SetAllPoints()
    fx:SetFrameLevel(b:GetFrameLevel() + 6)
    b.fx = fx
    local function Group(region, onFinished)
        local g = region:CreateAnimationGroup()
        g:SetScript("OnPlay", function() region:Show() end)
        g:SetScript("OnFinished", function() region:Hide(); if onFinished then onFinished() end end)
        return g
    end
    -- the streak: a bright comet, clipped to the filled part
    b.streak = b.sb.clip:CreateTexture(nil, "OVERLAY")
    b.streak:SetTexture(ns.WHITE)
    b.streak:SetBlendMode("ADD")
    b.streak:Hide()
    b.streakAnim = Group(b.streak)
    b.streakMove = b.streakAnim:CreateAnimation("Translation")
    b.streakMove:SetDuration(0.55)
    b.streakMove:SetSmoothing("IN")
    -- the glow around the bar
    b.glow = fx:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture(ns.WHITE)
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("TOPLEFT", b.edge, "TOPLEFT", -2, 2)
    b.glow:SetPoint("BOTTOMRIGHT", b.edge, "BOTTOMRIGHT", 2, -2)
    b.glow:Hide()
    b.glowAnim = Group(b.glow)
    local g1 = b.glowAnim:CreateAnimation("Alpha")
    g1:SetFromAlpha(0); g1:SetToAlpha(0.55); g1:SetDuration(0.15); g1:SetOrder(1)
    local g2 = b.glowAnim:CreateAnimation("Alpha")
    g2:SetFromAlpha(0.55); g2:SetToAlpha(0); g2:SetDuration(0.8); g2:SetOrder(2); g2:SetSmoothing("OUT")
    -- the icon pops
    b.iconPop = b.icon:CreateAnimationGroup()
    local p1 = b.iconPop:CreateAnimation("Scale")
    p1:SetScale(1.35, 1.35); p1:SetDuration(0.12); p1:SetOrder(1); p1:SetSmoothing("OUT")
    local p2 = b.iconPop:CreateAnimation("Scale")
    p2:SetScale(1 / 1.35, 1 / 1.35); p2:SetDuration(0.25); p2:SetOrder(2); p2:SetSmoothing("IN")
    -- "+1"
    b.plus = fx:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.plus:SetTextColor(1, 0.9, 0.4)
    b.plus:Hide()
    b.plusAnim = Group(b.plus)
    b.plusMove = b.plusAnim:CreateAnimation("Translation")
    b.plusMove:SetDuration(1.2)
    b.plusMove:SetSmoothing("OUT")
    local pa = b.plusAnim:CreateAnimation("Alpha")
    pa:SetFromAlpha(1); pa:SetToAlpha(0); pa:SetDuration(0.7); pa:SetStartDelay(0.5)
    -- the game's profession art (trade bars): the flare, and the fill's
    -- animation looping while the mouse is on the bar
    b.sb.owner = b
    b.flare = b.sb.clip:CreateTexture(nil, "OVERLAY")
    b.flare:SetBlendMode("ADD")
    b.flare:Hide()
    b:SetScript("OnEnter", function(self)
        Tooltip(self)
        Animate(self, true)
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        StopAnimation(self)
    end)
    return b
end

-- size and place every bar for the row's direction (out of combat only:
-- the trade bars are secure buttons)
local function Layout(row)
    local l = Look(row.kind)
    local s, len, gap = l.icon, l.length, l.gap
    local iconPart = l.icons and (s + 1) or 0
    -- the bar's thickness ("Bar Thickness"; 0 = the icon size), and the
    -- cell's: room for the thicker of bar and icon, both centred across it
    local t = (l.thick or 0) > 0 and l.thick or s
    local cross = math.max(t, l.icons and s or 0)
    local inset = (cross - t) / 2
    local horizontalRow = l.dir == "RIGHT" or l.dir == "LEFT"
    local n = #row.data
    local cellW, cellH
    if horizontalRow then cellW, cellH = cross, iconPart + len else cellW, cellH = iconPart + len, cross end
    local count = math.max(n, 1)
    if horizontalRow then
        row.frame:SetSize(count * cellW + (count - 1) * gap, cellH)
    else
        row.frame:SetSize(cellW, count * cellH + (count - 1) * gap)
    end
    for i, b in ipairs(row.bars) do
        if i > n then
            b:Hide()
        else
            b:ClearAllPoints()
            b:SetSize(cellW, cellH)
            local step = (i - 1) * ((horizontalRow and cellW or cellH) + gap)
            if l.dir == "RIGHT" then b:SetPoint("TOPLEFT", row.frame, "TOPLEFT", step, 0)
            elseif l.dir == "LEFT" then b:SetPoint("TOPRIGHT", row.frame, "TOPRIGHT", -step, 0)
            elseif l.dir == "DOWN" then b:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, -step)
            else b:SetPoint("BOTTOMLEFT", row.frame, "BOTTOMLEFT", 0, step) end
            -- the bar part and the icon part of the cell
            b.edge:ClearAllPoints()
            b.iconEdge:ClearAllPoints()
            b.iconEdge:SetSize(s, s)
            b.iconEdge:SetShown(l.icons)
            b.icon:SetShown(l.icons)
            if horizontalRow then
                -- upright bars, icon at the foot (or on top when flipped, the bar hanging down)
                if l.flip then
                    b.iconEdge:SetPoint("TOP", b, "TOP")
                    b.edge:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", inset, 0)
                    b.edge:SetPoint("TOPRIGHT", b, "TOPRIGHT", -inset, -iconPart)
                else
                    b.iconEdge:SetPoint("BOTTOM", b, "BOTTOM")
                    b.edge:SetPoint("TOPLEFT", b, "TOPLEFT", inset, 0)
                    b.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, iconPart)
                end
                b.sb:SetOrientation("VERTICAL")
            else
                -- lying bars, icon at the start (or the end when flipped, growing leftward)
                if l.flip then
                    b.iconEdge:SetPoint("RIGHT", b, "RIGHT")
                    b.edge:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -inset)
                    b.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -iconPart, inset)
                else
                    b.iconEdge:SetPoint("LEFT", b, "LEFT")
                    b.edge:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -inset)
                    b.edge:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", iconPart, inset)
                end
                b.sb:SetOrientation("HORIZONTAL")
            end
            if b.sb.SetReverseFill then b.sb:SetReverseFill(l.flip) end
            b.back:ClearAllPoints()
            b.back:SetPoint("TOPLEFT", b.edge, "TOPLEFT", 1, -1)
            b.back:SetPoint("BOTTOMRIGHT", b.edge, "BOTTOMRIGHT", -1, 1)
            b.sb:ClearAllPoints()
            b.sb:SetPoint("TOPLEFT", b.edge, "TOPLEFT", 1, -1)
            b.sb:SetPoint("BOTTOMRIGHT", b.edge, "BOTTOMRIGHT", -1, 1)
            b:Show()
        end
    end
    row.layoutKey = n .. l.dir .. tostring(l.flip) .. s .. t .. len .. gap .. tostring(l.icons)
end

---------------------------------------------------------------------------
-- Smart scale: the bar covers a window of points below the cap, picked
-- from these steps: the smallest one that still shows you at least 30%
-- of the way. As you close in, a smaller window takes over, so the bar
-- opens back up and every skill point moves it visibly: about 30% to
-- 70% far from the cap, all the way to full in the last few points.
-- (No window is wider than the whole skill.)
---------------------------------------------------------------------------
local WINDOWS = { 5, 8, 12, 18, 25, 35, 50, 70, 100, 140, 200, 280, 400 }
local SMART_FILL = 0.3

local function SmartWindow(gap, max)
    for _, w in ipairs(WINDOWS) do
        if gap <= w * (1 - SMART_FILL) then return math.min(w, max) end
    end
    return max
end

-- the window (points below the cap) a bar covers
local function Window(d, l)
    if d.cat ~= "weapon" then return d.max end
    if l.scale == "levels" and (l.zoom or 0) > 0 then return math.min(d.max, l.zoom * 5) end
    if l.scale == "whole" then return d.max end
    return SmartWindow(d.max - d.rank, d.max)
end

-- set a bar's fill, gliding to it where the client can
local GLIDE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local function SetFillTo(sb, v)
    if GLIDE and pcall(sb.SetValue, sb, v, GLIDE) then return end
    sb:SetValue(v)
end

-- values and colours (fine in combat)
local function Paint(row)
    local l = Look(row.kind)
    for i, d in ipairs(row.data) do
        local b = row.bars[i]
        if not b then break end
        local old = b.data
        b.data = d
        -- the fill: how far through its window the skill is (0 to 1)
        local window = Window(d, l)
        b.window = window
        local fill = window > 0 and (d.rank - (d.max - window)) / window or 1
        b.sb:SetMinMaxValues(0, 1)
        SetFillTo(b.sb, math.max(0, math.min(1, fill)))
        local capped = d.rank >= d.max
        local c = ColorOf(l, capped and "capped" or d.cat)
        local standing = l.dir == "RIGHT" or l.dir == "LEFT"
        -- trade bars: the game's profession art if it has some; else colours
        local dressed = row.kind == "trade" and l.art and DressBar(b, d, standing, l.flip,
            math.max(4, ((l.thick or 0) > 0 and l.thick or l.icon) - 2), math.max(4, l.length - 2))
        if not dressed then
            if b.art then
                -- "Game Art" just turned off: back to a plain fill
                StopAnimation(b)
                b.art = nil
                b.sb.grad:SetTexture(ns.WHITE)
                b.sb.grad:SetTexCoord(0, 1, 0, 1)
                b.flare:Hide()
            end
            ns.SetFill(b.sb, c[1], c[2], c[3], 1, standing and "VERTICAL" or "HORIZONTAL")
        end
        b.standing, b.flipped = standing, l.flip
        -- a rim on the icon (the capped colour) when the skill is at its cap
        if capped then
            local cc = ColorOf(l, "capped")
            b.iconEdge:SetColorTexture(cc[1], cc[2], cc[3], 1)
        else
            b.iconEdge:SetColorTexture(0, 0, 0, 0.9)
        end
        b.icon:SetTexture(SkillIcon(d))
        if old and old.name == d.name and d.rank > old.rank then
            local gain = d.rank - old.rank
            local function Land()
                Flourish(b, gain, c)
                -- the game plays its bar animation once on a skill-up; so do we
                if b.art and not b.sb:GetScript("OnUpdate") then Animate(b, false) end
            end
            -- "Experience Mote": a mote flies from your cursor into the bar first
            if l.mote and ns.SendMote and b:IsVisible() then SendSkillMote(b, d, c, Land) else Land() end
        end
    end
end

local pending = false

local function Update()
    if not DB then return end
    local weapons, trades = ReadSkills()
    for kind, row in pairs(rows) do
        local l = Look(kind)
        local list = {}
        if kind == "weapon" then
            local equipped = (l.show == "hands" or l.show == "equipped") and EquippedWeaponSkills(l.show == "equipped")
            for _, d in ipairs(weapons) do
                if l.show == "all" or (equipped and equipped[d.name])
                    or (l.show == "leveling" and (d.rank < d.max or d.name == "Defense")) then
                    list[#list + 1] = d
                end
            end
        else
            for _, d in ipairs(trades) do
                if l.show == "all" or d.cat == "prof" then list[#list + 1] = d end
            end
        end
        -- the same skills in the same order only need new values
        local same = #list == #row.data
        if same then
            for i, d in ipairs(list) do if row.data[i].name ~= d.name then same = false; break end end
        end
        if not same or row.dirty then
            -- (only the trade row's secure buttons have to wait out combat;
            -- the weapon row follows a weapon swap mid-fight)
            if row.secure and InCombatLockdown() then
                pending = true
            else
                row.data = list
                for i = #row.bars + 1, #list do row.bars[i] = NewBar(row) end
                for i, d in ipairs(list) do
                    local b = row.bars[i]
                    if row.secure then
                        local spell = OPENS[d.name]
                        if spell and KnownSpell(spell) then
                            b:SetAttribute("type", "spell")
                            b:SetAttribute("spell", spell)
                            b.opens = spell
                        else
                            b:SetAttribute("type", nil)
                            b:SetAttribute("spell", nil)
                            b.opens = nil
                        end
                    end
                end
                Layout(row)
                row.dirty = false
            end
        else
            row.data = list
        end
        Paint(row)
        row.empty:SetShown(#row.data == 0 and LEM:IsInEditMode())
    end
end

local function MakeRow(kind, title, secure)
    local f = CreateFrame("Frame", kind == "weapon" and "SpliffbarsWeaponSkills" or "SpliffbarsTradeSkills", UIParent)
    f.editModeName = title
    f:SetClampedToScreen(true)
    f:SetFrameStrata("LOW")
    f:SetSize(40, 40)
    local row = { kind = kind, frame = f, secure = secure, bars = {}, data = {}, dirty = true }
    row.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.empty:SetPoint("CENTER")
    row.empty:SetText("none yet")
    row.empty:Hide()
    rows[kind] = row

    local function Setting(skind, name, field, extra, relayout)
        local s = {
            kind = skind, name = name, default = DEFAULTS[kind][field],
            get = function(layout) layoutName = layout; return Look(kind)[field] end,
            set = function(layout, value)
                layoutName = layout
                Look(kind)[field] = value
                if relayout ~= false then row.dirty = true end
                Update()
            end,
        }
        for k, v in pairs(extra or {}) do s[k] = v end
        return s
    end

    LEM:AddFrame(f, function(_, layout, point, x, y)
        layoutName = layout
        local l = Look(kind)
        l.point, l.x, l.y = point, x, y
    end, DEFAULT_POS[kind], title)

    local show = kind == "weapon" and {
        { text = "Weapon in my hands", value = "hands" },
        { text = "Hands and ranged", value = "equipped" },
        { text = "Still leveling", value = "leveling" },
        { text = "All weapon skills", value = "all" },
    } or {
        { text = "Professions and secondary", value = "all" },
        { text = "Professions only", value = "prof" },
    }
    local settings = {
        Setting(LEM.SettingType.Dropdown, "Row Runs", "dir", { values = {
            { text = "Left to right", value = "RIGHT" }, { text = "Right to left", value = "LEFT" },
            { text = "Top to bottom", value = "DOWN" }, { text = "Bottom to top", value = "UP" },
        } }),
        Setting(LEM.SettingType.Checkbox, "Flip Bars (grow the other way)", "flip"),
        Setting(LEM.SettingType.Dropdown, "Show", "show", { values = show }),
        Setting(LEM.SettingType.Slider, "Icon Size", "icon", { minValue = 8, maxValue = 32, valueStep = 1 }),
        Setting(LEM.SettingType.Slider, "Bar Thickness", "thick", {
            minValue = 0, maxValue = 60, valueStep = 1,
            formatter = function(v) v = math.floor(v + 0.5); return v == 0 and "icon size" or tostring(v) end,
        }),
        Setting(LEM.SettingType.Slider, "Bar Length", "length", { minValue = 6, maxValue = 160, valueStep = 1 }),
        Setting(LEM.SettingType.Slider, "Gap", "gap", { minValue = 0, maxValue = 12, valueStep = 1 }),
        Setting(LEM.SettingType.Checkbox, "Show Icons", "icons"),
    }
    if kind == "weapon" then
        table.insert(settings, 4, Setting(LEM.SettingType.Dropdown, "Bar Scale", "scale", { values = {
            { text = "Smart (zooms in near the cap)", value = "smart" },
            { text = "Last few levels", value = "levels" },
            { text = "Whole skill", value = "whole" },
        } }))
        table.insert(settings, 5, Setting(LEM.SettingType.Slider, "Last Levels", "zoom", {
            minValue = 1, maxValue = 20, valueStep = 1,
            disabled = function() return Look("weapon").scale ~= "levels" end,
            formatter = function(v)
                v = math.floor(v + 0.5)
                return v == 1 and "1 level" or (v .. " levels")
            end,
        }))
    end

    -- colours (Edit Mode's colour picker; saved as { r, g, b })
    local function ColorSetting(name, which, disabled)
        local fallback = COLORS[which]
        return {
            kind = LEM.SettingType.ColorPicker, name = name,
            default = CreateColor(fallback[1], fallback[2], fallback[3]),
            get = function(layout)
                layoutName = layout
                local c = ColorOf(Look(kind), which)
                return CreateColor(c[1], c[2], c[3])
            end,
            set = function(layout, color)
                layoutName = layout
                local r, g, b = color:GetRGB()
                Look(kind)[COLOR_FIELD[which]] = { r, g, b }
                Update()
            end,
            disabled = disabled,
        }
    end
    if kind == "weapon" then
        settings[#settings + 1] = ColorSetting("Bar Colour", "weapon")
    else
        settings[#settings + 1] = Setting(LEM.SettingType.Checkbox, "Game Art (animated)", "art")
        local function artOn() return Look("trade").art end
        settings[#settings + 1] = ColorSetting("Profession Colour", "prof", artOn)
        settings[#settings + 1] = ColorSetting("Secondary Colour", "second", artOn)
    end
    settings[#settings + 1] = ColorSetting("Capped Colour", "capped")
    settings[#settings + 1] = Setting(LEM.SettingType.Checkbox, "Experience Mote (skill-up)", "mote", nil, false)
    LEM:AddFrameSettings(f, settings)
    return row
end

MakeRow("weapon", "Spliffbars: Weapon Skills", false)
MakeRow("trade", "Spliffbars: Trade Skills", true)

-- /spliffbars mote: a test mote into your first trade bar (else weapon bar),
-- with its flourish, without a real skill-up
ns.TestMote = function()
    local sent = false
    for _, kind in ipairs({ "trade", "weapon" }) do
        local row = rows[kind]
        local b = row and row.bars[1]
        if b and b:IsVisible() and b.data then
            local l = Look(kind)
            local c = ColorOf(l, b.data.rank >= b.data.max and "capped" or b.data.cat)
            SendSkillMote(b, b.data, c, function()
                Flourish(b, 1, c)
                if b.art and not b.sb:GetScript("OnUpdate") then Animate(b, false) end
            end)
            sent = true
        end
    end
    return sent
end

local function Place()
    for kind, row in pairs(rows) do
        local l = Look(kind)
        local p = l.point and l or DEFAULT_POS[kind]
        row.frame:ClearAllPoints()
        row.frame:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    end
end

LEM:RegisterCallback("layout", function(layout)
    layoutName = layout
    if InCombatLockdown() then pending = true; return end
    Place()
    for _, row in pairs(rows) do row.dirty = true end
    Update()
end)
LEM:RegisterCallback("enter", function() for _, row in pairs(rows) do row.empty:SetShown(#row.data == 0) end end)
LEM:RegisterCallback("exit", function() for _, row in pairs(rows) do row.empty:Hide() end end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED" }) do
    pcall(events.RegisterEvent, events, e)
end
local queued = false
local function Soon()
    if queued then return end
    queued = true
    C_Timer.After(0.3, function() queued = false; Update() end)
end
events:SetScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" then
        if a1 == "Spliffbars" then
            SpliffbarsSkillsDB = SpliffbarsSkillsDB or {}
            DB = SpliffbarsSkillsDB
            -- once: weapon skill-ups send a mote too
            if not DB.weaponMoteOn then
                DB.weaponMoteOn = true
                for _, layout in pairs(DB.layouts or {}) do
                    if layout.weapon then layout.weapon.mote = true end
                end
            end
            -- once: the weapon row's new default is the weapon in your hands
            if not DB.handsDefault then
                DB.handsDefault = true
                for _, layout in pairs(DB.layouts or {}) do
                    if layout.weapon then layout.weapon.show = "hands" end
                end
            end
        end
        return
    end
    if not DB then return end
    if event == "PLAYER_ENTERING_WORLD" then
        if InCombatLockdown() then pending = true; return end
        Place()
        for _, row in pairs(rows) do row.dirty = true end
        Update()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then
            pending = false
            Place()
            for _, row in pairs(rows) do row.dirty = true end
            Update()
        end
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        -- a new trade spell: the click may open something now
        rows.trade.dirty = true
        Soon()
    else
        Soon()
    end
end)

---------------------------------------------------------------------------
-- Learning a recipe: a swarm of little motes in the profession's colour
-- bursts from your cursor and each finds its own wild way into that
-- profession's bar (ns.SendSwarm, Mote.lua); the bar glows as each lands.
-- Which profession: the game's "new recipe" news where it gives one, else
-- the recipe item you just used (Recipe / Pattern / Plans / Formula...),
-- else what you just bought from a trainer.
---------------------------------------------------------------------------
local RECIPE_SUBCLASS = {
    [1] = "Leatherworking", [2] = "Tailoring", [3] = "Engineering", [4] = "Blacksmithing", [5] = "Cooking",
    [6] = "Alchemy", [7] = "First Aid", [8] = "Enchanting", [9] = "Fishing", [10] = "Jewelcrafting",
    [11] = "Inscription",
}
local recentProf, recentAt = nil, -100 -- from a recipe item or a trainer, just now
local lastSwarm = -100

-- the trade bar showing a profession (by name, or a name it contains)
local function TradeBar(prof)
    local row = rows.trade
    if not (row and prof) then return end
    for i, d in ipairs(row.data) do
        if d.name == prof or prof:find(d.name, 1, true) then
            local b = row.bars[i]
            if b and b:IsVisible() then return b, d end
        end
    end
end

local function RecipeSwarm(prof)
    if GetTime() - lastSwarm < 1.5 then return false end -- one recipe, one swarm
    local b, d = TradeBar(prof)
    if not (b and ns.SendSwarm) then return false end
    lastSwarm = GetTime()
    local c = TRADE_MOTES[d.name] or ColorOf(Look("trade"), d.cat)
    ns.SendSwarm(b, c, 7, function()
        -- each landing: the bar glows
        b.glow:SetVertexColor(0.6 + c[1] * 0.4, 0.6 + c[2] * 0.4, 0.6 + c[3] * 0.4)
        b.glowAnim:Stop()
        b.glowAnim:Play()
    end, function()
        -- the last one: the icon pops and the game's bar animation plays
        if b.icon:IsShown() then b.iconPop:Stop(); b.iconPop:Play() end
        if b.art and not b.sb:GetScript("OnUpdate") then Animate(b, false) end
    end, 0.2)
    return true
end

-- /spliffbars recipe: a test swarm into your first trade bar
ns.TestRecipe = function()
    local d = rows.trade and rows.trade.data[1]
    if not d then return false end
    lastSwarm = -100
    return RecipeSwarm(d.name)
end

-- a recipe item used from your bags
local function OnBagUse(bag, slot)
    if not (C_Container and C_Container.GetContainerItemID and getInstant) then return end
    local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
    if not ok or not Num(id) then return end
    local ok2, _, _, _, _, _, classID, subclassID = pcall(getInstant, id)
    if ok2 and classID == 9 and RECIPE_SUBCLASS[subclassID] then
        recentProf, recentAt = RECIPE_SUBCLASS[subclassID], GetTime()
    end
end
if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", OnBagUse) end

-- something bought from a trainer
if BuyTrainerService and GetTrainerServiceSkillLine then
    hooksecurefunc("BuyTrainerService", function(index)
        local ok, line = pcall(GetTrainerServiceSkillLine, index)
        if ok and type(line) == "string" and not isSecret(line) then recentProf, recentAt = line, GetTime() end
    end)
end

-- "You have learned how to create a new item: %s." as a pattern
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    -- escape every magic character (the % in %s too), then let %s be anything
    local escaped = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
    local pattern = escaped:gsub("%%%%s", ".+")
    return "^" .. pattern .. "$"
end
local LEARN_RECIPE = Pattern(ERR_LEARN_RECIPE_S)
local LEARN_SPELL = Pattern(ERR_LEARN_SPELL_S)

local recipeEvents = CreateFrame("Frame")
pcall(recipeEvents.RegisterEvent, recipeEvents, "NEW_RECIPE_LEARNED")
pcall(recipeEvents.RegisterEvent, recipeEvents, "CHAT_MSG_SYSTEM")
recipeEvents:SetScript("OnEvent", function(_, event, a1)
    if not DB then return end
    if event == "NEW_RECIPE_LEARNED" then
        -- a1: the recipe; the game says which profession it belongs to
        local prof
        if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLineForRecipe and Num(a1) then
            local ok, _, lineName, parentID = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, a1)
            if ok and type(lineName) == "string" and not isSecret(lineName) then prof = lineName end
            if ok and Num(parentID) and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
                local ok2, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, parentID)
                info = ok2 and ns.Tbl(info)
                if info and type(info.professionName) == "string" and not isSecret(info.professionName) then
                    prof = info.professionName
                end
            end
        end
        if not RecipeSwarm(prof) and GetTime() - recentAt < 10 then RecipeSwarm(recentProf) end
    elseif event == "CHAT_MSG_SYSTEM" then
        if type(a1) ~= "string" or isSecret(a1) or GetTime() - recentAt > 10 then return end
        if (LEARN_RECIPE and a1:match(LEARN_RECIPE)) or (LEARN_SPELL and a1:match(LEARN_SPELL)) then
            RecipeSwarm(recentProf)
        end
    end
end)
