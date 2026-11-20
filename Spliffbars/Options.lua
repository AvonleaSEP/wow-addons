-- Spliffbars: the options window (/spliffbars).
--
-- Its own movable window: pages down the left, the page on the right
-- (scrolls when it's long). Spliffbars' own pages first, then a page for
-- each module that's on (Unit Frames, Spliff Plates ...):
--
--   Bars           show or hide each bar; Edit Mode for their look
--   Effects        loot effects (all, or each kind) and skill effects
--   Journal & Gold the Leveling Journal, the gold goal, the flight timer
--   Quests         Shift-drag quest items from Questie's tracker
--   Game UI        the game's own bits Spliffbars can hide
--   Modules        switch the package's bigger pieces on and off
--
-- The game's Options > AddOns list has a Spliffbars entry with a button
-- that opens this window. Modules add their page with ns.AddOptionsTab,
-- built from the same small kit: checkboxes, rows of choice buttons,
-- sliders. The switches are account-wide (SpliffbarsDB, see Core.lua).

local _, ns = ...

local GOLD = { 1, 0.82, 0 }
local DIM = { 0.62, 0.62, 0.68 }
local WHITE = { 1, 1, 1 }
local COL_W = 290 -- a column's width

local WIN_W, WIN_H = 900, 620
local SIDE_W = 176 -- the page list
local TOP = 42     -- under the title strip

---------------------------------------------------------------------------
-- The kit: a page, columns down it, and the pieces placed in a column.
-- Every piece reads its value through get() each time the page shows (or
-- anything on it changes), so it always matches what's saved.
---------------------------------------------------------------------------
local Page = {}
Page.__index = Page

local function Text(parent, size, c)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns.FontPath(nil), size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH("LEFT")
    return fs
end

function Page:Refresh()
    for _, r in ipairs(self.refreshers) do r() end
end

-- a column: pieces are placed top to bottom from (x, y)
function Page:Column(x, y)
    local col = { x = x, y = y or -64 }
    self.cols[#self.cols + 1] = col
    return col
end

function Page:Heading(col, text)
    col.y = col.y - 8
    local h = Text(self.frame, 14, GOLD)
    h:SetPoint("TOPLEFT", col.x, col.y)
    h:SetText(text)
    local line = self.frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.22)
    line:SetPoint("TOPLEFT", col.x, col.y - 19)
    line:SetSize(COL_W, 1)
    col.y = col.y - 28
end

function Page:Note(col, text, indent)
    local n = Text(self.frame, 10, DIM)
    n:SetPoint("TOPLEFT", col.x + (indent or 0), col.y)
    n:SetWidth(COL_W - (indent or 0))
    n:SetWordWrap(true)
    n:SetText(text)
    col.y = col.y - math.max(14, n:GetStringHeight() + 6)
    return n
end

-- a checkbox: get() -> bool, set(bool); indent for ones under a master
-- switch; enabled() greys it out when false
function Page:Check(col, label, get, set, indent, enabled)
    local cb = CreateFrame("CheckButton", nil, self.frame)
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", col.x + (indent or 0) - 4, col.y + 4)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    local t = Text(cb, 12, WHITE)
    t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    t:SetText(label)
    cb:SetHitRectInsets(0, -(t:GetStringWidth() + 6), 0, 0) -- the label clicks it too
    self.refreshers[#self.refreshers + 1] = function()
        cb:SetChecked(get() and true or false)
        local on = not enabled or enabled()
        cb:SetEnabled(on)
        t:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
    end
    cb:SetScript("OnClick", function(b)
        set(b:GetChecked() and true or false)
        self:Refresh() -- (a master switch greys its children)
    end)
    col.y = col.y - 24
    return cb
end

function Page:Button(col, label, onClick, width)
    local b = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    b:SetSize(width or 180, 22)
    b:SetPoint("TOPLEFT", col.x, col.y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    col.y = col.y - 30
    return b
end

-- a row of buttons, one lit: options = { { text, value }, ... }
function Page:Choice(col, label, options, get, set, enabled)
    local t
    if label then
        t = Text(self.frame, 12, WHITE)
        t:SetPoint("TOPLEFT", col.x, col.y)
        t:SetText(label)
        col.y = col.y - 18
    end
    local buttons, x = {}, col.x
    for _, o in ipairs(options) do
        local b = CreateFrame("Button", nil, self.frame)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b.text = Text(b, 11, WHITE)
        b.text:SetPoint("CENTER")
        b.text:SetJustifyH("CENTER")
        b.text:SetText(o[1])
        local w = math.max(44, b.text:GetStringWidth() + 18)
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, col.y)
        x = x + w + 3
        b.value = o[2]
        b:SetScript("OnClick", function()
            set(o[2])
            self:Refresh()
        end)
        buttons[#buttons + 1] = b
    end
    self.refreshers[#self.refreshers + 1] = function()
        local v, on = get(), not enabled or enabled()
        for _, b in ipairs(buttons) do
            local lit = b.value == v
            b.bg:SetColorTexture(lit and 0.55 or 0.12, lit and 0.42 or 0.12, lit and 0.1 or 0.14, on and 0.95 or 0.5)
            b.text:SetTextColor(lit and 1 or 0.75, lit and 0.9 or 0.75, lit and 0.5 or 0.78)
            b:SetEnabled(on)
        end
        if t then t:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5) end
    end
    col.y = col.y - 30
    return buttons
end

-- a slider with its value at the right; fmt(v) for how the value reads
function Page:Slider(col, label, min, max, step, get, set, fmt, enabled)
    local t = Text(self.frame, 12, WHITE)
    t:SetPoint("TOPLEFT", col.x, col.y)
    t:SetText(label)
    local v = Text(self.frame, 12, GOLD)
    v:SetJustifyH("RIGHT")
    v:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", col.x + COL_W, col.y)
    local s = CreateFrame("Slider", nil, self.frame)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(COL_W, 16)
    s:SetPoint("TOPLEFT", col.x, col.y - 18)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(1, 1, 1, 0.12)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = s:GetThumbTexture()
    if thumb then thumb:SetSize(24, 24) end
    local function Show(val) v:SetText(fmt and fmt(val) or tostring(val)) end
    local syncing = false
    s:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val / step + 0.5) * step
        Show(val)
        if not syncing then set(val) end
    end)
    self.refreshers[#self.refreshers + 1] = function()
        syncing = true
        local val = get()
        s:SetValue(val)
        Show(val)
        syncing = false
        local on = not enabled or enabled()
        s:SetEnabled(on)
        t:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
    end
    col.y = col.y - 44
    return s
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local win, scroll, thumb
local pages = {}   -- in the order they're listed: { name, group, page }
local current

local function Thumb()
    if not (scroll and current) then return end
    local h, ch = scroll:GetHeight(), current.frame:GetHeight()
    if ch <= h + 1 then thumb:Hide() return end
    local th = math.max(24, h * h / ch)
    thumb:ClearAllPoints()
    thumb:SetHeight(th)
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 6, -(h - th) * (scroll:GetVerticalScroll() / (ch - h)))
    thumb:Show()
end

local function SavePos()
    local point, _, rel, x, y = win:GetPoint(1)
    if not point then return end
    SpliffbarsDB = SpliffbarsDB or {}
    SpliffbarsDB.optionsWin = { point = point, rel = rel, x = x, y = y }
end

local RefreshList -- below

local function Select(entry)
    if current and current ~= entry.page then current.frame:Hide() end
    current = entry.page
    local f = current.frame
    f:SetParent(scroll)
    f:SetWidth(WIN_W - SIDE_W - 30)
    scroll:SetScrollChild(f)
    scroll:SetVerticalScroll(0)
    f:Show() -- (builds it the first time, refreshes it after)
    if SpliffbarsDB then SpliffbarsDB.optionsPage = entry.name end
    RefreshList()
    Thumb()
end

local listButtons = {}

RefreshList = function()
    if not win then return end
    for _, b in ipairs(listButtons) do b:Hide() end
    local y, n, group = -8, 0, nil
    for _, entry in ipairs(pages) do
        if entry.group ~= group then
            group = entry.group
            n = n + 1
            local h = listButtons[n]
            if not h or h.sel then -- (a group heading, not a page button)
                h = CreateFrame("Frame", nil, win.side)
                h.text = Text(h, 10, DIM)
                h.text:SetPoint("LEFT", 12, 0)
                listButtons[n] = h
            end
            if y < -8 then y = y - 10 end -- a little room above each group after the first
            h:SetSize(SIDE_W - 8, 18)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 4, y)
            y = y - 18
            h.text:SetText(group:upper())
            h:Show()
        end
        n = n + 1
        local b = listButtons[n]
        if not b or not b.sel then
            b = CreateFrame("Button", nil, win.side)
            b.sel = b:CreateTexture(nil, "BACKGROUND")
            b.sel:SetAllPoints()
            b.sel:SetColorTexture(1, 0.82, 0, 0.16)
            local bar = b:CreateTexture(nil, "ARTWORK")
            bar:SetPoint("TOPLEFT")
            bar:SetPoint("BOTTOMLEFT")
            bar:SetWidth(2)
            bar:SetColorTexture(1, 0.82, 0, 0.9)
            b.bar = bar
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.06)
            b.text = Text(b, 13, WHITE)
            b.text:SetPoint("LEFT", 14, 0)
            listButtons[n] = b
        end
        b:SetSize(SIDE_W - 8, 26)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 4, y)
        y = y - 27
        b.text:SetText(entry.name)
        local on = current == entry.page
        b.sel:SetShown(on)
        b.bar:SetShown(on)
        b.text:SetTextColor(on and 1 or 0.85, on and 0.85 or 0.85, on and 0.4 or 0.88)
        b:SetScript("OnClick", function() Select(entry) end)
        b:Show()
    end
end

local function Build()
    local f = CreateFrame("Frame", "SpliffbarsOptions", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    f:Hide()
    tinsert(UISpecialFrames, "SpliffbarsOptions") -- Esc closes it
    local p = SpliffbarsDB and SpliffbarsDB.optionsWin
    if p then f:SetPoint(p.point, UIParent, p.rel or p.point, p.x, p.y) else f:SetPoint("CENTER") end

    local edge = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 0.92)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.065, 0.065, 0.08, 0.97)
    local strip = f:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", 1, -1)
    strip:SetPoint("TOPRIGHT", -1, -1)
    strip:SetHeight(TOP - 8)
    strip:SetTexture(ns.WHITE)
    ns.Gradient(strip, "VERTICAL", 0.09, 0.07, 0.03, 1, 0.2, 0.15, 0.05, 1)
    local line = f:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", strip, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.35)

    local title = Text(f, 16, GOLD)
    title:SetPoint("LEFT", f, "TOPLEFT", 16, -(TOP - 8) / 2)
    title:SetText("Spliffbars")
    local hint = Text(f, 10, DIM)
    hint:SetPoint("LEFT", title, "RIGHT", 12, -1)
    hint:SetText("drag the title bar to move")

    local ok, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
    if not (ok and close) then
        close = CreateFrame("Button", nil, f)
        close:SetSize(24, 24)
        local x = Text(close, 16, WHITE)
        x:SetPoint("CENTER")
        x:SetText("x")
    end
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)

    -- the page list
    local side = CreateFrame("Frame", nil, f)
    side:SetPoint("TOPLEFT", 0, -(TOP - 6))
    side:SetPoint("BOTTOMLEFT", 0, 1)
    side:SetWidth(SIDE_W)
    local sbg = side:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(0, 0, 0, 0.25)
    local div = side:CreateTexture(nil, "BORDER")
    div:SetPoint("TOPRIGHT")
    div:SetPoint("BOTTOMRIGHT")
    div:SetWidth(1)
    div:SetColorTexture(1, 1, 1, 0.08)
    f.side = side

    -- the page: scrolls with the mouse wheel when it's long
    scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", SIDE_W + 8, -(TOP - 4))
    scroll:SetPoint("BOTTOMRIGHT", -14, 8)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        if not current then return end
        local most = math.max(0, current.frame:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(most, math.max(0, self:GetVerticalScroll() - delta * 50)))
        Thumb()
    end)
    thumb = f:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 1, 1, 0.2)
    thumb:SetWidth(3)
    thumb:Hide()

    win = f
    return f
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
-- a page: built the first time it shows (build(page)), refreshed every time
local function NewPage(name, title, subtitle, build)
    local page = setmetatable({ name = name, refreshers = {}, cols = {} }, Page)
    local f = CreateFrame("Frame")
    f:SetSize(WIN_W - SIDE_W - 30, 10)
    f:Hide()
    page.frame = f
    f:SetScript("OnShow", function()
        if not page.built then
            page.built = true
            local h = Text(f, 20, WHITE)
            h:SetPoint("TOPLEFT", 16, -10)
            h:SetText(title or name)
            if subtitle then
                local sub = Text(f, 11, DIM)
                sub:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -5)
                sub:SetWidth(WIN_W - SIDE_W - 70)
                sub:SetWordWrap(true)
                sub:SetText(subtitle)
            end
            build(page)
            -- tall enough for its lowest column (the window scrolls it)
            local low = -60
            for _, col in ipairs(page.cols) do low = math.min(low, col.y) end
            f:SetHeight(-low + 16)
        end
        page:Refresh()
        Thumb()
    end)
    return page
end

-- add a page to the list ("Spliffbars" pages first, then "Modules")
local function AddPage(group, page)
    local entry = { name = page.name, group = group, page = page }
    pages[#pages + 1] = entry
    if win and win:IsShown() then RefreshList() end
    return entry
end

local function OpenEditMode()
    if win then win:Hide() end
    if HideUIPanel and SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if ShowUIPanel and EditModeManagerFrame then ShowUIPanel(EditModeManagerFrame) end
end
ns.OpenEditMode = OpenEditMode

-- an account-wide switch from Core.lua
local function OptCheck(page, col, label, key, indent, enabled)
    return page:Check(col, label, function() return ns.Opt(key) end, function(v) ns.SetOpt(key, v) end,
        indent, enabled)
end

AddPage("Spliffbars", NewPage("Bars", "Bars",
    "Show or hide each bar. Their look (size, text, colours, where they sit) is in Edit Mode: click a bar there.",
    function(page)
        local L = page:Column(16, -70)
        page:Heading(L, "Showing")
        for _, p in ipairs(ns.pieces) do
            if not p.module then -- (a module's frames are on its own page)
                page:Check(L, p.name, function() return not p.get() end, function(v) p.set(not v) end)
            end
        end
        page:Note(L, "For the Edit Mode layout you're using. A hidden bar still shows, faded, in Edit Mode, so you can bring it back.")
        page:Button(L, "Open Edit Mode", OpenEditMode)
    end))

AddPage("Spliffbars", NewPage("Effects", "Effects", "The little flourishes: loot flying to where it goes, and motes for skill-ups.",
    function(page)
        local L = page:Column(16, -70)
        page:Heading(L, "Loot")
        local function lootOn() return ns.Opt("loot") end
        OptCheck(page, L, "Loot effects", "loot")
        OptCheck(page, L, "Mining, herbs, skinning, fishing to your bag", "lootGather", 20, lootOn)
        OptCheck(page, L, "Coins hop out of the Gold bar", "lootCoins", 20, lootOn)
        OptCheck(page, L, "Quest items to the quest tracker", "lootQuest", 20, lootOn)
        OptCheck(page, L, "Green or better from mobs to your bag", "lootItems", 20, lootOn)
        L.y = L.y - 4
        page:Button(L, "Test", function() if ns.TestLoot then ns.TestLoot() end end, 100)

        local R = page:Column(340, -70)
        page:Heading(R, "Skills")
        OptCheck(page, R, "Skill-up motes", "skillMotes")
        page:Note(R, "Each skill row can turn its own off in Edit Mode too.", 20)
        OptCheck(page, R, "Recipe swarm when you learn a recipe", "recipeSwarm")
        R.y = R.y - 4
        page:Button(R, "Test", function()
            if ns.TestMote and not ns.TestMote() then print(ns.PREFIX .. "no skill bars showing to send a mote to.") end
        end, 100)
    end))

AddPage("Spliffbars", NewPage("Journal & Gold", "Journal & Gold", "Your leveling story, your gold goal, and flight times.",
    function(page)
        local L = page:Column(16, -70)
        page:Heading(L, "Leveling Journal")
        OptCheck(page, L, "Click the XP bar to open it", "journalClick")
        page:Note(L, "Or type /lj.", 20)
        page:Button(L, "Open the Journal", function() if ns.ToggleJournal then ns.ToggleJournal() end end)

        local R = page:Column(340, -70)
        page:Heading(R, "Gold")
        page:Button(R, "Set Gold Goal...", function() if ns.AskGoldGoal then ns.AskGoldGoal() end end)
        OptCheck(page, R, "Click the Gold bar for the Money Book", "goldClick")
        page:Note(R, "The Money Book is the Spliff Gold module (Modules page). Or type /mb.", 20)
        page:Heading(R, "Flight Timer")
        page:Note(R, "Learns each route as you fly it. Hide it or resize it on the Bars page and in Edit Mode. With Leatrix Plus' \"Show flight times\" on, it steps aside for Leatrix's (exact) one.")
        page:Button(R, "Test Flight", function() if ns.TestFlight then ns.TestFlight() end end, 120)
    end))

AddPage("Spliffbars", NewPage("Quests", "Quests", "Help with the quest items in Questie's tracker.",
    function(page)
        local L = page:Column(16, -70)
        page:Heading(L, "Quest Items")
        page:Check(L, "Shift-drag them onto your action bars",
            function() return ns.Opt("questDrag") end,
            function(v)
                ns.SetOpt("questDrag", v)
                if ns.ApplyQuestDrag then ns.ApplyQuestDrag() end
            end)
        page:Note(L, "A plain click still uses the item. A change made in a fight applies when it ends.", 20)
    end))

AddPage("Spliffbars", NewPage("Game UI", "Game UI", "The game's own bits Spliffbars can tuck away.",
    function(page)
        local L = page:Column(16, -70)
        page:Heading(L, "Hide")
        for _, g in ipairs(ns.gameUI or {}) do page:Check(L, g.name:gsub("^Hide the ", ""):gsub("^%l", string.upper), g.get, g.set) end
        page:Note(L, "Hidden ones can come back the same way; some need a /reload.")
    end))

AddPage("Spliffbars", NewPage("Modules", "Modules",
    "The package's bigger pieces, each in its own folder. A module that's off runs no code at all; one that's on has its own page here.",
    function(page)
        local L = page:Column(16, -70)
        page:Heading(L, "Switched on")
        local modules = ns.Modules()
        if #modules == 0 then
            page:Note(L, "None installed. They come in the Spliff package as their own folders (SpliffFrames ...).")
            return
        end
        local reload
        for _, m in ipairs(modules) do
            page:Check(L, m.name, function() return ns.ModuleOn(m) end, function(v)
                ns.SetOpt("module:" .. m.addon, v)
                if reload then reload:SetShown(v ~= ns.ModuleLoaded(m)) end
            end)
            if m.notes then page:Note(L, m.notes, 20) end
        end
        L.y = L.y - 4
        page:Note(L, "Switching one on or off takes a reload.")
        reload = page:Button(L, "Reload Now", function() ReloadUI() end, 120)
        reload:Hide()
    end))

-- a module's own page (Unit Frames, Spliff Plates ...): build(page) fills it
-- the first time it shows
function ns.AddOptionsTab(name, subtitle, build)
    local page = NewPage(name, name, subtitle, build)
    AddPage("Modules", page)
    return page
end

function ns.OpenOptions(name)
    if not win then Build() end
    win:Show()
    local want = name or (SpliffbarsDB and SpliffbarsDB.optionsPage)
    local pick = pages[1]
    for _, e in ipairs(pages) do if e.name == want then pick = e end end
    Select(pick)
end

---------------------------------------------------------------------------
-- The game's Options > AddOns list: a Spliffbars entry that opens this
---------------------------------------------------------------------------
local stub = CreateFrame("Frame")
stub.name = "Spliffbars"
stub:Hide()
stub:SetScript("OnShow", function(self)
    if self.built then return end
    self.built = true
    local h = Text(self, 20, GOLD)
    h:SetPoint("TOPLEFT", 16, -16)
    h:SetText("Spliffbars")
    local t = Text(self, 12, WHITE)
    t:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -10)
    t:SetText("Spliffbars has its own options window. Type /spliffbars, or:")
    local b = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
    b:SetSize(220, 26)
    b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
    b:SetText("Open Spliffbars Options")
    b:SetScript("OnClick", function()
        if HideUIPanel and SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns.OpenOptions()
    end)
end)
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(stub, "Spliffbars")
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(stub)
end
