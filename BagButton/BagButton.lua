-- Bag Button
-- One bag icon that shows how many bag slots you have free; click it to
-- open your bags (whatever bag addon you use, such as Baganator, opens).
-- Right-click: open just your backpack.
--
-- Edit Mode (Esc > Edit Mode): drag it, click it for Size, Show Count,
-- Count Size and "Hide the Game's Bag Buttons". It starts beside your
-- character portrait.
-- Edit Mode support comes from LibEditMode by p3lim (Libs\LibEditMode).

local LEM = LibStub("LibEditMode")
local isSecret = issecretvalue or function() return false end
local function Num(v) return not isSecret(v) and type(v) == "number" end

local DEFAULTS = { size = 36, count = true, countSize = 14 }
local DB, layoutName

local function Look()
    -- Edit Mode can ask before the saved settings have loaded: the defaults for now
    if not DB then return CopyTable(DEFAULTS) end
    DB.layouts = DB.layouts or {}
    local key = layoutName or "Default"
    local l = DB.layouts[key]
    if not l then l = {}; DB.layouts[key] = l end
    for k, v in pairs(DEFAULTS) do
        if l[k] == nil then l[k] = v end
    end
    return l
end

---------------------------------------------------------------------------
-- Counting free slots: your backpack and the bags in your bag slots (and a
-- reagent bag if this client has one); special bags such as quivers or
-- soul bags only count their own items, so they're left out of "free".
---------------------------------------------------------------------------
local function BagSlots()
    local free, total = 0, 0
    local last = (NUM_BAG_SLOTS or 4) + ((NUM_REAGENTBAG_SLOTS and NUM_REAGENTBAG_SLOTS > 0) and 1 or 0)
    for bag = 0, last do
        local slots, f, bagType
        if C_Container and C_Container.GetContainerNumSlots then
            slots = C_Container.GetContainerNumSlots(bag)
            f, bagType = C_Container.GetContainerNumFreeSlots(bag)
        else
            slots = GetContainerNumSlots(bag)
            f, bagType = GetContainerNumFreeSlots(bag)
        end
        if Num(slots) and slots > 0 and Num(f) and (isSecret(bagType) or bagType == nil or bagType == 0) then
            free, total = free + f, total + slots
        end
    end
    return free, total
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------
local button = CreateFrame("Button", "BagButtonFrame", UIParent)
button.editModeName = "Bag Button"
button:SetSize(DEFAULTS.size, DEFAULTS.size)
button:SetClampedToScreen(true)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
icon:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
button:SetPushedTexture("Interface\\Buttons\\Button-Backpack-Down")

local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
count:SetPoint("BOTTOMRIGHT", -1, 2)

local function Update()
    if not DB then return end
    local l = Look()
    button:SetSize(l.size, l.size)
    local font, _, flags = NumberFontNormal:GetFont()
    count:SetFont(font, l.countSize, flags or "OUTLINE")
    local free = BagSlots()
    count:SetText(free)
    -- green with room, yellow getting full, red when nearly full
    if free <= 2 then count:SetTextColor(1, 0.2, 0.2)
    elseif free <= 8 then count:SetTextColor(1, 0.82, 0)
    else count:SetTextColor(0.4, 1, 0.4) end
    count:SetShown(l.count)
end

button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
        if ToggleBackpack then ToggleBackpack() end
    elseif ToggleAllBags then
        ToggleAllBags()
    end
end)
button:SetScript("OnEnter", function(self)
    local free, total = BagSlots()
    if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
    GameTooltip:AddLine("Bags")
    GameTooltip:AddDoubleLine("Free slots", free .. " / " .. total, 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddLine("Click: open your bags", 0.5, 0.8, 1)
    GameTooltip:AddLine("Right-click: just the backpack", 0.5, 0.8, 1)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Hiding the game's bag buttons (optional): see-through and click-through,
-- like XP & Rep Bars does with the XP bar, rather than hidden, which can
-- upset Edit Mode. Only changed out of combat.
---------------------------------------------------------------------------
local GAME_BAGS = { "BagsBar", "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
    "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot", "BagBarExpandToggle",
    "KeyRingButton" }
local hooked, savedMouse, gameHidden = {}, {}, false

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

local function ApplyGameBags()
    local hide = DB and DB.hideGame and true or false
    if not hide and not gameHidden then return end
    if InCombatLockdown() then return end
    for _, n in ipairs(GAME_BAGS) do
        local g = _G[n]
        if g and g.SetAlpha then
            if hide and not hooked[g] then
                hooked[g] = true
                hooksecurefunc(g, "SetAlpha", function(self, a)
                    if DB and DB.hideGame and not self.bagButtonBusy and type(a) == "number" and a > 0 then
                        self.bagButtonBusy = true
                        self:SetAlpha(0)
                        self.bagButtonBusy = nil
                    end
                end)
            end
            g.bagButtonBusy = true
            pcall(g.SetAlpha, g, hide and 0 or 1)
            g.bagButtonBusy = nil
            SetMouseDeep(g, not hide)
        end
    end
    gameHidden = hide
end

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------
-- starts just right of your character portrait
local default = { point = "CENTER", x = -260, y = 200 }

local function FindDefault()
    local p = _G.PlayerPortrait
        or (PlayerFrame and PlayerFrame.PlayerFrameContainer and PlayerFrame.PlayerFrameContainer.PlayerPortrait)
        or PlayerFrame
    if not (p and p.GetRight) then return end
    local right, cy = p:GetRight(), select(2, p:GetCenter())
    if not right or not cy or isSecret(right) or isSecret(cy) then return end
    local k = p:GetEffectiveScale() / button:GetEffectiveScale()
    local ux, uy = UIParent:GetCenter()
    local uk = UIParent:GetEffectiveScale() / button:GetEffectiveScale()
    default.point = "CENTER"
    default.x = right * k - ux * uk + 24
    default.y = cy * k - uy * uk
end

local function Place()
    local l = Look()
    button:ClearAllPoints()
    if l.point then
        button:SetPoint(l.point, UIParent, l.point, l.x, l.y)
    else
        button:SetPoint(default.point, UIParent, default.point, default.x, default.y)
    end
end

LEM:AddFrame(button, function(_, layout, point, x, y)
    layoutName = layout
    local l = Look()
    l.point, l.x, l.y = point, x, y
end, default)

local function Setting(kind, name, key, extra)
    local s = {
        kind = kind, name = name, default = DEFAULTS[key],
        get = function(layout) layoutName = layout; return Look()[key] end,
        set = function(layout, value) layoutName = layout; Look()[key] = value; Update() end,
    }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

LEM:AddFrameSettings(button, {
    Setting(LEM.SettingType.Slider, "Size", "size", { minValue = 16, maxValue = 80, valueStep = 1 }),
    Setting(LEM.SettingType.Checkbox, "Show Free Slots", "count"),
    Setting(LEM.SettingType.Slider, "Count Size", "countSize", { minValue = 8, maxValue = 30, valueStep = 1 }),
    {
        kind = LEM.SettingType.Checkbox,
        name = "Hide the Game's Bag Buttons",
        default = false,
        get = function() return DB and DB.hideGame or false end,
        set = function(_, value) if DB then DB.hideGame = value end; ApplyGameBags() end,
    },
})

LEM:RegisterCallback("layout", function(layout)
    layoutName = layout
    Place()
    Update()
end)

SLASH_BAGBUTTON1 = "/bagbutton"
SlashCmdList.BAGBUTTON = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if not DB then return end
    if msg == "hide" or msg == "show" then
        DB.hideGame = (msg == "hide")
        ApplyGameBags()
        print("|cffc79c6eBag Button|r the game's bag buttons are " .. (DB.hideGame and "hidden" or "back")
            .. (InCombatLockdown() and " after this fight." or "."))
    else
        print("|cffc79c6eBag Button|r /bagbutton hide or show for the game's bag buttons. Move and size it in Edit Mode.")
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "BAG_UPDATE",
    "PLAYER_REGEN_ENABLED" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "BagButton" then
            BagButtonDB = BagButtonDB or {}
            DB = BagButtonDB
        end
        return
    end
    if not DB then return end
    if event == "PLAYER_ENTERING_WORLD" then
        Place()
        Update()
        ApplyGameBags()
        C_Timer.After(1, function() -- the player frame settles after login
            FindDefault()
            if not Look().point and not LEM:IsInEditMode() then Place() end
            ApplyGameBags()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        ApplyGameBags()
    else
        Update()
    end
end)
