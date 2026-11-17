-- Minimap Menu
-- A gear button on the edge of your minimap. Click it for a drop-down with
-- the game's menu buttons: Character Info, Professions, Spellbook, Talents,
-- Achievements, Quest Log, Group Finder, Collections, Game Menu and the
-- rest (whatever this client's menu bar has).
--
--   Left-click        open / close the drop-down
--   Drag              slide the button around the minimap (out of combat)
--   Right-click       hide / show the game's menu bar at the bottom
--   /mmenu hide|show  the same, from chat
--
-- Each entry is a secure button that "clicks" the game's own menu button
-- for you, so it works exactly like the original, in combat too, without
-- "action blocked" errors. The list is built out of combat (at login).

local PREFIX = "|cffc79c6eMinimap Menu|r "
local DB
local ApplyMenuBar -- defined further down; used by the gear's right-click

-- nicer names for the menu buttons this addon knows; others use the game's tooltip
local LABELS = {
    CharacterMicroButton = "Character Info",
    ProfessionMicroButton = "Professions",
    PlayerSpellsMicroButton = "Talents & Spellbook",
    SpellbookMicroButton = "Spellbook & Abilities",
    TalentMicroButton = "Talents",
    AchievementMicroButton = "Achievements",
    QuestLogMicroButton = "Quest Log",
    HousingMicroButton = "Housing",
    GuildMicroButton = "Guild & Communities",
    SocialsMicroButton = "Social",
    LFDMicroButton = "Group Finder",
    LFGMicroButton = "Group Finder",
    PVPMicroButton = "Player vs. Player",
    CollectionsMicroButton = "Collections",
    EJMicroButton = "Adventure Guide",
    WorldMapMicroButton = "World Map",
    StoreMicroButton = "Shop",
    MainMenuMicroButton = "Game Menu",
    HelpMicroButton = "Help",
}
-- if the client has no list of its menu buttons, try these
local FALLBACK = { "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
    "SpellbookMicroButton", "TalentMicroButton", "AchievementMicroButton", "QuestLogMicroButton",
    "HousingMicroButton", "GuildMicroButton", "SocialsMicroButton", "LFDMicroButton", "LFGMicroButton",
    "PVPMicroButton", "CollectionsMicroButton", "EJMicroButton", "WorldMapMicroButton",
    "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton" }

local function Clean(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s*%b()%s*$", "")
    return text ~= "" and text or nil
end

local function Label(name, mb)
    return LABELS[name] or Clean(mb.tooltipText) or Clean(mb.newbieText)
        or name:gsub("MicroButton$", ""):gsub("(%l)(%u)", "%1 %2")
end

---------------------------------------------------------------------------
-- The gear button on the minimap and the drop-down
---------------------------------------------------------------------------
local gear, menu
local ROW, WIDTH = 22, 190

local function Angle() return DB and DB.angle or 225 end -- degrees; 225 = bottom-left

local function PlaceGear()
    if InCombatLockdown() then return end
    local a = math.rad(Angle())
    local r = (Minimap:GetWidth() / 2) + 6
    gear:ClearAllPoints()
    gear:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(a), r * math.sin(a))
    -- open the drop-down toward the middle of the screen
    menu:ClearAllPoints()
    local gx, gy = gear:GetCenter()
    local sx, sy = UIParent:GetCenter()
    if gx and sx then
        local h = gx > sx and "RIGHT" or "LEFT"
        local v = gy > sy and "TOP" or "BOTTOM"
        local other = (v == "TOP" and "BOTTOM" or "TOP") .. (h == "RIGHT" and "LEFT" or "RIGHT")
        menu:SetPoint(v .. h, gear, other, 0, 0)
    else
        menu:SetPoint("TOPRIGHT", gear, "BOTTOMLEFT", 0, 0)
    end
end

local function Build()
    -- the drop-down: a protected frame, so the secure toggle can show it in combat
    menu = CreateFrame("Frame", "MinimapMenuDropDown", UIParent, "SecureHandlerStateTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:Hide()
    local bg = menu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.94)
    local edge = menu:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.55, 0.42, 0.16, 0.9)
    edge:SetDrawLayer("BACKGROUND", -1)

    -- the gear: LibDBIcon-style round minimap button
    gear = CreateFrame("Button", "MinimapMenuButton", Minimap, "SecureHandlerClickTemplate")
    gear:SetSize(31, 31)
    gear:SetFrameStrata("MEDIUM")
    gear:SetFrameLevel(8)
    gear:RegisterForClicks("AnyUp")
    gear:RegisterForDrag("LeftButton")
    gear:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local ring = gear:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local back = gear:CreateTexture(nil, "BACKGROUND")
    back:SetSize(20, 20)
    back:SetPoint("TOPLEFT", 7, -5)
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = gear:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    gear:SetFrameRef("menu", menu)
    gear:SetAttribute("_onclick", [[
        if button ~= "LeftButton" then return end
        local m = self:GetFrameRef("menu")
        if m:IsShown() then m:Hide() else m:Show() end
    ]])
    gear:HookScript("OnClick", function(_, button)
        if button == "RightButton" then
            DB.hideBar = not DB.hideBar
            ApplyMenuBar()
            print(PREFIX .. "the game's menu bar is " .. (DB.hideBar and "hidden" or "back")
                .. (InCombatLockdown() and " after this fight." or "."))
        end
    end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Menu")
        GameTooltip:AddLine("Click: open the menu", 0.5, 0.8, 1)
        GameTooltip:AddLine("Right-click: " .. (DB and DB.hideBar and "show" or "hide") .. " the menu bar", 0.5, 0.8, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- dragging it around the minimap edge (out of combat: it's a protected frame)
    gear:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local x, y = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            DB.angle = math.deg(math.atan2 and math.atan2(y / s - my, x / s - mx) or math.atan(y / s - my, x / s - mx))
            PlaceGear()
        end)
    end)
    gear:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

-- one row per menu button the game has right now
local entries = {}
local function Fill()
    if InCombatLockdown() then return false end
    local names = type(MICRO_BUTTONS) == "table" and MICRO_BUTTONS or FALLBACK
    local n = 0
    for _, name in ipairs(names) do
        local mb = _G[name]
        if mb and mb.Click and mb:IsShown() then
            n = n + 1
            local e = entries[n]
            if not e then
                e = CreateFrame("Button", "MinimapMenuEntry" .. n, menu, "SecureActionButtonTemplate")
                e:SetSize(WIDTH - 8, ROW)
                e:RegisterForClicks("AnyUp")
                e:SetAttribute("useOnKeyDown", false)
                e:SetAttribute("type", "click") -- securely clicks the game's own button
                e:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                e.icon = e:CreateTexture(nil, "ARTWORK")
                e.icon:SetSize(18, 18)
                e.icon:SetPoint("LEFT", 4, 0)
                e.text = e:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                e.text:SetPoint("LEFT", e.icon, "RIGHT", 6, 0)
                e.text:SetJustifyH("LEFT")
                -- pick one, the drop-down closes
                gear:WrapScript(e, "OnClick", [[ return nil, true ]], [[ owner:GetFrameRef("menu"):Hide() ]])
                entries[n] = e
            end
            e:SetAttribute("clickbutton", mb)
            e:ClearAllPoints()
            e:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (n - 1) * ROW)
            e.text:SetText(Label(name, mb))
            -- the button's own picture, where it has a simple one
            local nt = mb.GetNormalTexture and mb:GetNormalTexture()
            local atlas = nt and nt.GetAtlas and nt:GetAtlas()
            if atlas then e.icon:SetAtlas(atlas)
            elseif nt and nt:GetTexture() then e.icon:SetTexture(nt:GetTexture()); e.icon:SetTexCoord(nt:GetTexCoord())
            else e.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
            e:Show()
        end
    end
    for i = n + 1, #entries do entries[i]:Hide() end
    menu:SetSize(WIDTH, 8 + n * ROW)
    return true
end

---------------------------------------------------------------------------
-- Hiding the game's menu bar at the bottom: see-through and click-through
-- (its buttons still work for this drop-down), only changed out of combat.
---------------------------------------------------------------------------
local BARS = { "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar" }
local hooked, savedMouse, barHidden = {}, {}, false

local function SetMouseDeep(frame, on)
    if frame.EnableMouse and frame.IsMouseEnabled then
        if on then
            if savedMouse[frame] ~= nil then pcall(frame.EnableMouse, frame, savedMouse[frame]) end
        else
            if savedMouse[frame] == nil then savedMouse[frame] = frame:IsMouseEnabled() end
            pcall(frame.EnableMouse, frame, false)
        end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do SetMouseDeep(child, on) end
    end
end

ApplyMenuBar = function()
    local hide = DB and DB.hideBar and true or false
    if not hide and not barHidden then return end
    if InCombatLockdown() then return end
    local touched = {}
    local function Apply(g)
        if not g or touched[g] or not g.SetAlpha then return end
        touched[g] = true
        if hide and not hooked[g] then
            hooked[g] = true
            hooksecurefunc(g, "SetAlpha", function(self, a)
                if DB and DB.hideBar and not self.mmBusy and type(a) == "number" and a > 0 then
                    self.mmBusy = true
                    self:SetAlpha(0)
                    self.mmBusy = nil
                end
            end)
        end
        g.mmBusy = true
        pcall(g.SetAlpha, g, hide and 0 or 1)
        g.mmBusy = nil
        SetMouseDeep(g, not hide)
    end
    for _, n in ipairs(BARS) do Apply(_G[n]) end
    -- on clients without one container, the buttons themselves
    if not (_G.MicroMenuContainer or _G.MicroMenu or _G.MicroButtonAndBagsBar) then
        for _, n in ipairs(type(MICRO_BUTTONS) == "table" and MICRO_BUTTONS or FALLBACK) do Apply(_G[n]) end
    end
    barHidden = hide
end

SLASH_MINIMAPMENU1 = "/mmenu"
SlashCmdList.MINIMAPMENU = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if not DB then return end
    if msg == "hide" or msg == "show" then
        DB.hideBar = (msg == "hide")
        ApplyMenuBar()
        print(PREFIX .. "the game's menu bar is " .. (DB.hideBar and "hidden" or "back")
            .. (InCombatLockdown() and " after this fight." or "."))
    else
        print(PREFIX .. "/mmenu hide or show for the game's menu bar. Drag the gear to move it around the minimap.")
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
local filled = false
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "MinimapMenu" then
            MinimapMenuDB = MinimapMenuDB or {}
            DB = MinimapMenuDB
        end
        return
    end
    if not DB then return end
    if InCombatLockdown() then return end -- everything below waits for the fight to end
    if not gear then Build() end
    PlaceGear()
    if not filled then
        -- the menu buttons settle a moment after login
        C_Timer.After(1, function()
            if not InCombatLockdown() and Fill() then filled = true end
        end)
    end
    ApplyMenuBar()
end)
