-- Spliffbars: the options panel (Esc > Options > AddOns > Spliffbars, or
-- /spliffbars). One place for everything that isn't a bar's own look:
--
--   Bars          show or hide each bar (same as "Hide This Bar" in Edit
--                 Mode, for the layout you're using), and a way into Edit
--                 Mode for the rest
--   Loot Effects  one switch for all of them, or each kind on its own
--   Skill Effects skill-up motes and the recipe swarm
--   Leveling Journal, Gold, and the game's own bits Spliffbars can hide
--
-- The switches are account-wide (SpliffbarsDB, see Core.lua).

local _, ns = ...

local GOLD = { 1, 0.82, 0 }
local DIM = { 0.65, 0.65, 0.7 }

local panel = CreateFrame("Frame")
panel.name = "Spliffbars"
panel:Hide()

local refreshers = {} -- run when the panel shows, so it matches what's saved

local function Text(parent, size, c)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns.FontPath(nil), size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH("LEFT")
    return fs
end

-- a column: things are placed top to bottom from (x, y)
local function Column(x)
    return { x = x, y = -64 }
end

local function Heading(col, text)
    col.y = col.y - 8
    local h = Text(panel, 15, GOLD)
    h:SetPoint("TOPLEFT", col.x, col.y)
    h:SetText(text)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetPoint("TOPLEFT", col.x, col.y - 20)
    line:SetSize(290, 1)
    col.y = col.y - 28
end

local function Note(col, text, indent)
    local n = Text(panel, 10, DIM)
    n:SetPoint("TOPLEFT", col.x + (indent or 0), col.y)
    n:SetWidth(290 - (indent or 0))
    n:SetWordWrap(true)
    n:SetText(text)
    col.y = col.y - math.max(14, n:GetStringHeight() + 4)
end

-- a checkbox: get() -> bool, set(bool); indent for the ones under a master
-- switch; enabled() greys it out when false
local function Check(col, label, get, set, indent, enabled)
    local cb = CreateFrame("CheckButton", nil, panel)
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", col.x + (indent or 0) - 4, col.y + 4)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    local t = Text(cb, 12, { 1, 1, 1 })
    t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    t:SetText(label)
    cb:SetHitRectInsets(0, -(t:GetStringWidth() + 6), 0, 0) -- the label clicks it too
    local function Sync()
        cb:SetChecked(get() and true or false)
        local on = not enabled or enabled()
        cb:SetEnabled(on)
        t:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
    end
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        for _, r in ipairs(refreshers) do r() end -- (a master switch greys its children)
    end)
    refreshers[#refreshers + 1] = Sync
    col.y = col.y - 24
    return cb
end

local function Button(col, label, onClick, width)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(width or 170, 22)
    b:SetPoint("TOPLEFT", col.x, col.y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    col.y = col.y - 28
    return b
end

-- an account-wide switch from Core.lua
local function OptCheck(col, label, key, indent, enabled)
    return Check(col, label, function() return ns.Opt(key) end, function(v) ns.SetOpt(key, v) end, indent, enabled)
end

local function Build()
    local title = Text(panel, 20, GOLD)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Spliffbars")
    local sub = Text(panel, 11, DIM)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Each bar's look (size, text, colours, where it sits) is in Edit Mode: click the bar there.")

    -- left column: the bars and the game's own UI
    local L = Column(16)
    Heading(L, "Bars")
    for _, p in ipairs(ns.pieces) do
        Check(L, "Show the " .. p.name, function() return not p.get() end, function(v) p.set(not v) end)
    end
    Note(L, "For the Edit Mode layout you're using. A hidden bar still shows, faded, in Edit Mode.")
    Button(L, "Open Edit Mode", function()
        if HideUIPanel and SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if ShowUIPanel and EditModeManagerFrame then ShowUIPanel(EditModeManagerFrame) end
    end)

    if ns.gameUI then
        Heading(L, "The Game's Own UI")
        for _, g in ipairs(ns.gameUI) do Check(L, g.name, g.get, g.set) end
    end

    Heading(L, "Leveling Journal")
    OptCheck(L, "Click the XP bar to open it", "journalClick")
    Button(L, "Open the Journal", function()
        if ns.ToggleJournal then ns.ToggleJournal() end
    end)

    -- right column: effects and gold
    local R = Column(340)
    Heading(R, "Loot Effects")
    local function lootOn() return ns.Opt("loot") end
    OptCheck(R, "Loot effects (all of them)", "loot")
    OptCheck(R, "Mining, herbs, skinning, fishing fly to your bag", "lootGather", 20, lootOn)
    OptCheck(R, "Coins fly into the Gold bar", "lootCoins", 20, lootOn)
    OptCheck(R, "Quest items fly to the quest tracker", "lootQuest", 20, lootOn)
    OptCheck(R, "Green or better from mobs fly to your bag", "lootItems", 20, lootOn)
    Button(R, "Test (a few mined items)", function() if ns.TestLoot then ns.TestLoot() end end)

    Heading(R, "Skill Effects")
    OptCheck(R, "Skill-up motes", "skillMotes")
    Note(R, "Each skill row can turn its own off too (Edit Mode: Experience Mote).", 20)
    OptCheck(R, "Recipe swarm when you learn a recipe", "recipeSwarm")
    Button(R, "Test a skill-up mote", function()
        if ns.TestMote and not ns.TestMote() then print(ns.PREFIX .. "no skill bars showing to send a mote to.") end
    end)

    Heading(R, "Quest Items")
    Check(R, "Shift-drag items from Questie's tracker to your bars",
        function() return ns.Opt("questDrag") end,
        function(v)
            ns.SetOpt("questDrag", v)
            if ns.ApplyQuestDrag then ns.ApplyQuestDrag() end
        end)
    Note(R, "A plain click still uses the item. Changes made in a fight apply when it ends.", 20)

    Heading(R, "Gold")
    Button(R, "Set Gold Goal...", function() if ns.AskGoldGoal then ns.AskGoldGoal() end end)
end

local built = false
panel:SetScript("OnShow", function()
    if not built then built = true; Build() end
    for _, r in ipairs(refreshers) do r() end
end)

-- into the game's options (Esc > Options > AddOns)
local category
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, "Spliffbars")
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        local id = category.GetID and category:GetID() or category.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel) -- (the old panel needs asking twice)
    end
end
