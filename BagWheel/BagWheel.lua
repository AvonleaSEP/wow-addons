-- Bag Wheel
-- Press your key: a ring of your Baganator custom categories opens at the
-- cursor. Hover a category and a second ring shows the items from it that
-- are in your bags. Click one to use it; the wheel closes. Press the key
-- again, or click the X in the middle, to close without using anything.
--
-- Set the key in Options > Keybindings > AddOns > Bag Wheel.
-- Out of combat, /bagwheel opens it too.
--
-- Where the categories come from: only your own Baganator settings
-- (BAGANATOR_CONFIG, the categories you made and the items you dragged into
-- them). Nothing of Baganator's code is used or changed. Add an item to a
-- category in Baganator and it shows up here the next time you open the
-- wheel out of combat.
--
-- Works in combat: everything is built from the game's secure buttons, set
-- up out of combat. The one limit is that the item list can only be rebuilt
-- out of combat, so something you loot mid-fight appears after the fight.
-- Item counts still update during a fight.

---------------------------------------------------------------------------
-- Settings: change these, then type /reload in game
---------------------------------------------------------------------------
-- nil = every custom category, in Baganator's order. Or list the ones you
-- want, in the order you want them, e.g. { "Healing", "Food", "Elixirs" }
local CATEGORIES = nil

local CAT_RADIUS  = 80   -- middle to the category ring, in pixels
local CAT_SIZE    = 40   -- category icon size
local ITEM_RADIUS = 152  -- middle to the item ring
local ITEM_SIZE   = 34   -- item icon size
local MAX_CATS    = 10
local MAX_ITEMS   = 10   -- per category

---------------------------------------------------------------------------
BINDING_HEADER_BAGWHEEL = "Bag Wheel"
_G["BINDING_NAME_CLICK BagWheelToggle:LeftButton"] = "Open / close the bag wheel (works in combat)"

local PREFIX = "|cffc79c6eBag Wheel|r "
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local isSecret = issecretvalue or function() return false end

local function ItemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, id)
    if ok and not isSecret(n) and type(n) == "number" then return n end
    return 0
end

local function ItemIcon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    local ok, icon = pcall(f, id)
    if ok and icon and not isSecret(icon) then return icon end
    return QUESTION
end

---------------------------------------------------------------------------
-- How often you use each item (BagWheelDB.uses[itemID]), however you use
-- it: the wheel, your bags, an action bar, or a /use macro. A category's
-- icon pictures (and its click uses) the one you use most.
---------------------------------------------------------------------------
local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local function CountUse(id)
    if not BagWheelDB or isSecret(id) or type(id) ~= "number" then return end
    BagWheelDB.uses = BagWheelDB.uses or {}
    BagWheelDB.uses[id] = (BagWheelDB.uses[id] or 0) + 1
end

local function Uses(id)
    return BagWheelDB and BagWheelDB.uses and BagWheelDB.uses[id] or 0
end

-- from your bags (also what a /use macro and the wheel's buttons end up calling)
local function OnBagUse(bag, slot)
    local id
    if C_Container and C_Container.GetContainerItemID then
        local ok, v = pcall(C_Container.GetContainerItemID, bag, slot)
        if ok then id = v end
    elseif GetContainerItemID then
        local ok, v = pcall(GetContainerItemID, bag, slot)
        if ok then id = v end
    end
    CountUse(id)
end
if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", OnBagUse)
elseif UseContainerItem then
    hooksecurefunc("UseContainerItem", OnBagUse)
end

-- by name or link ("/use Major Healing Potion", the wheel's buttons)
local function OnNamedUse(name)
    if isSecret(name) or name == nil or not getInstant then return end
    local ok, id = pcall(getInstant, name)
    if ok then CountUse(id) end
end
for _, owner in ipairs({ C_Item or false, _G }) do
    if owner and type(owner.UseItemByName) == "function" then
        hooksecurefunc(owner, "UseItemByName", OnNamedUse)
        break
    end
end

-- from an action bar
if UseAction then
    hooksecurefunc("UseAction", function(slot)
        local ok, kind, id = pcall(GetActionInfo, slot)
        if ok and not isSecret(kind) and kind == "item" then CountUse(id) end
    end)
end

---------------------------------------------------------------------------
-- Your categories, from your Baganator settings (data only)
---------------------------------------------------------------------------
local function Profile()
    local cfg = _G.BAGANATOR_CONFIG
    if type(cfg) ~= "table" or type(cfg.Profiles) ~= "table" then return nil end
    local p = cfg.Profiles.DEFAULT
    if type(p) ~= "table" then
        for _, v in pairs(cfg.Profiles) do
            if type(v) == "table" then p = v break end
        end
    end
    return type(p) == "table" and p or nil
end

-- list of { name, items = { itemID, ... } }, or nil when the settings aren't there
-- (all: include the ones left out, for the options list)
local function ReadCategories(all)
    local p = Profile()
    if not p then return nil end
    local custom = type(p.custom_categories) == "table" and p.custom_categories or {}
    local mods = type(p.category_modifications) == "table" and p.category_modifications or {}

    -- Baganator's display order first, then any custom category not in it
    local order, seen = {}, {}
    if type(p.category_display_order) == "table" then
        for _, key in ipairs(p.category_display_order) do
            if custom[key] and not seen[key] then order[#order + 1] = key; seen[key] = true end
        end
    end
    for key in pairs(custom) do
        if not seen[key] then order[#order + 1] = key; seen[key] = true end
    end

    local cats, byName = {}, {}
    for _, key in ipairs(order) do
        local c = custom[key]
        local items = {}
        local added = type(mods[key]) == "table" and mods[key].addedItems
        if type(added) == "table" then
            for k in pairs(added) do
                local id = tonumber(tostring(k):match("^i:(%d+)"))
                if id then items[#items + 1] = id end
            end
        end
        table.sort(items)
        local entry = { name = type(c) == "table" and c.name or ("Category " .. key), items = items }
        byName[entry.name:lower()] = entry
        -- left out in Options > AddOns > Bag Wheel (Tools, to start with)
        if all or not (BagWheelDB and BagWheelDB.hidden and BagWheelDB.hidden[entry.name:lower()]) then
            cats[#cats + 1] = entry
        end
    end

    if CATEGORIES then
        local picked = {}
        for _, name in ipairs(CATEGORIES) do
            local e = byName[name:lower()]
            if e then picked[#picked + 1] = e end
        end
        cats = picked
    end
    return cats
end

---------------------------------------------------------------------------
-- Frames (made once, out of combat)
---------------------------------------------------------------------------
local wheel, toggle
local catButtons, rings, itemButtons = {}, {}, {}
local UpdateCooldowns -- below

-- classic action-button look: icon, slot frame, hover highlight, count
local function Dress(b, size)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "BACKGROUND")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    local frame = b:GetNormalTexture()
    frame:ClearAllPoints()
    frame:SetSize(size * 66 / 36, size * 66 / 36)
    frame:SetPoint("CENTER", 0, -1)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    -- the cooldown sweep and its countdown numbers, under the count
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    if b.cooldown.SetHideCountdownNumbers then b.cooldown:SetHideCountdownNumbers(false) end
    b.cooldown:SetFrameLevel(b:GetFrameLevel() + 1)
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints()
    top:SetFrameLevel(b:GetFrameLevel() + 3)
    b.count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
end

-- an item's cooldown on a button (b.cdItem); fine in combat
local GetCD = (C_Item and C_Item.GetItemCooldown) or (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
local function ShowCooldown(b)
    local cd = b.cooldown
    local function Clear() if cd.Clear then cd:Clear() else cd:SetCooldown(0, 0) end end
    if not (b.cdItem and GetCD) then Clear(); return end
    local ok, start, duration, enable = pcall(GetCD, b.cdItem)
    if not ok then Clear(); return end
    if isSecret(start) or isSecret(duration) then
        pcall(cd.SetCooldown, cd, start, duration) -- the sweep takes hidden numbers as they are
        return
    end
    -- (enable 0: a potion used in combat; its cooldown starts when the fight ends)
    if type(start) == "number" and type(duration) == "number" and start > 0 and duration > 0
        and enable ~= 0 and enable ~= false then
        cd:SetCooldown(start, duration)
    else
        Clear()
    end
end

local function Build()
    wheel = CreateFrame("Frame", "BagWheelFrame", UIParent, "SecureHandlerStateTemplate")
    local size = (ITEM_RADIUS + ITEM_SIZE) * 2
    wheel:SetSize(size, size)
    wheel:SetFrameStrata("DIALOG")
    wheel:SetClampedToScreen(true)
    wheel:Hide()
    wheel:HookScript("OnShow", function() UpdateCooldowns() end)

    -- soft dark disc behind the category ring
    local disc = wheel:CreateTexture(nil, "BACKGROUND")
    disc:SetSize((CAT_RADIUS + CAT_SIZE) * 2, (CAT_RADIUS + CAT_SIZE) * 2)
    disc:SetPoint("CENTER")
    disc:SetColorTexture(0, 0, 0, 0.4)
    local mask = wheel:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(disc)
    disc:AddMaskTexture(mask)

    -- the X in the middle closes it
    local close = CreateFrame("Button", nil, wheel, "SecureHandlerClickTemplate")
    close:SetSize(30, 30)
    close:SetPoint("CENTER")
    close:RegisterForClicks("AnyUp")
    close:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    close:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    close:SetAttribute("_onclick", [[ self:GetParent():Hide() ]])

    -- the key: opens at the cursor with no item ring showing, or closes
    toggle = CreateFrame("Button", "BagWheelToggle", UIParent, "SecureHandlerClickTemplate")
    toggle:SetSize(1, 1)
    toggle:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10) -- off screen; only the key clicks it
    toggle:RegisterForClicks("AnyUp")
    toggle:SetFrameRef("wheel", wheel)
    toggle:SetAttribute("_onclick", ([[
        local wheel = self:GetFrameRef("wheel")
        if wheel:IsShown() then
            wheel:Hide()
            return
        end
        for i = 1, %d do
            local ring = self:GetFrameRef("ring" .. i)
            if ring then ring:Hide() end
        end
        wheel:ClearAllPoints()
        wheel:SetPoint("CENTER", "$cursor", "BOTTOMLEFT", 0, 0)
        wheel:Show()
    ]]):format(MAX_CATS))

    -- hovering a category shows its item ring and hides the others
    local HOVER = ([[
        for i = 1, %d do
            local ring = self:GetFrameRef("ring" .. i)
            if ring then ring:Hide() end
        end
        self:GetFrameRef("own"):Show()
    ]]):format(MAX_CATS)

    for c = 1, MAX_CATS do
        local ring = CreateFrame("Frame", nil, wheel, "SecureFrameTemplate")
        ring:SetAllPoints(wheel)
        ring:Hide()
        rings[c] = ring
        toggle:SetFrameRef("ring" .. c, ring)
    end

    for c = 1, MAX_CATS do
        -- a category icon: hover for its items; click to use the item it
        -- pictures (the one of them you use most), then the wheel closes
        local cat = CreateFrame("Button", "BagWheelCategory" .. c, wheel,
            "SecureActionButtonTemplate,SecureHandlerEnterLeaveTemplate")
        Dress(cat, CAT_SIZE)
        cat:EnableMouse(true)
        cat:RegisterForClicks("AnyUp")
        cat:SetAttribute("useOnKeyDown", false)
        cat:SetAttribute("type1", "item")
        cat:SetAttribute("*type1", "item")
        cat:SetAttribute("checkselfcast", false)
        cat:SetAttribute("checkfocuscast", false)
        toggle:WrapScript(cat, "OnClick", [[ return nil, true ]], [[ owner:GetFrameRef("wheel"):Hide() ]])
        cat:HookScript("OnEnter", function(self)
            if not self.cdItem then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.cdItem)
            GameTooltip:AddLine("Click to use", 0.6, 0.8, 1)
            GameTooltip:Show()
        end)
        cat:HookScript("OnLeave", function() GameTooltip:Hide() end)
        cat.label = cat:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cat.label:SetPoint("TOP", cat, "BOTTOM", 0, -3)
        cat:SetFrameRef("own", rings[c])
        for j = 1, MAX_CATS do cat:SetFrameRef("ring" .. j, rings[j]) end
        cat:SetAttribute("_onenter", HOVER)
        cat:Hide()
        catButtons[c] = cat

        itemButtons[c] = {}
        for i = 1, MAX_ITEMS do
            local b = CreateFrame("Button", "BagWheelItem" .. c .. "_" .. i, rings[c], "SecureActionButtonTemplate")
            Dress(b, ITEM_SIZE)
            b:RegisterForClicks("AnyUp")
            b:SetAttribute("useOnKeyDown", false)
            b:SetAttribute("type1", "item")
            b:SetAttribute("*type1", "item") -- same with a modifier held
            b:SetAttribute("checkselfcast", false)
            b:SetAttribute("checkfocuscast", false)
            -- after using it, close the wheel
            toggle:WrapScript(b, "OnClick", [[ return nil, true ]], [[ owner:GetFrameRef("wheel"):Hide() ]])
            b:HookScript("OnEnter", function(self)
                if not self.itemID then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.itemID)
                GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function() GameTooltip:Hide() end)
            b:Hide()
            itemButtons[c][i] = b
        end
    end
end

---------------------------------------------------------------------------
-- Filling it in (out of combat only)
---------------------------------------------------------------------------
local dirty = true
local warned = false

local function Pos(angle, radius)
    local a = math.rad(angle)
    return radius * math.cos(a), radius * math.sin(a)
end

-- every button's cooldown (when the wheel opens and whenever one changes)
UpdateCooldowns = function()
    if not wheel then return end
    for c = 1, MAX_CATS do
        if catButtons[c] then ShowCooldown(catButtons[c]) end
        for i = 1, MAX_ITEMS do
            local b = itemButtons[c] and itemButtons[c][i]
            if b then ShowCooldown(b) end
        end
    end
end

local function Rebuild()
    if not wheel or InCombatLockdown() then dirty = true; return end
    dirty = false
    local cats = ReadCategories()
    if not cats then
        if not warned then
            warned = true
            print(PREFIX .. "couldn't find your Baganator settings (is Baganator on?).")
        end
        cats = {}
    elseif #cats == 0 and not warned then
        warned = true
        print(PREFIX .. "no custom categories found in your Baganator settings.")
    end

    local n = math.min(#cats, MAX_CATS)
    local itemStep = math.deg((ITEM_SIZE + 5) / ITEM_RADIUS)
    for c = 1, MAX_CATS do
        local cat, ring = catButtons[c], rings[c]
        local entry = c <= n and cats[c]
        if entry then
            local angle = 90 - (c - 1) * 360 / n -- clockwise from the top
            cat:ClearAllPoints()
            cat:SetPoint("CENTER", wheel, "CENTER", Pos(angle, CAT_RADIUS))
            cat.label:SetText(entry.name)

            local owned = {}
            for _, id in ipairs(entry.items) do
                if ItemCount(id) > 0 then owned[#owned + 1] = id end
            end
            -- the one you use most (ties: the category's order)
            local top = owned[1]
            for _, id in ipairs(owned) do
                if Uses(id) > Uses(top) then top = id end
            end
            cat:SetAttribute("item", top and ("item:" .. top) or nil)
            local shownIcon = top or entry.items[1]
            cat.icon:SetTexture(shownIcon and ItemIcon(shownIcon) or QUESTION)
            cat.icon:SetDesaturated(#owned == 0)
            cat.count:SetText(#owned > 0 and #owned or "")
            cat.cdItem = top -- the category shows the cooldown of the item it pictures
            cat:Show()

            local m = math.min(#owned, MAX_ITEMS)
            for i = 1, MAX_ITEMS do
                local b = itemButtons[c][i]
                local id = i <= m and owned[i]
                if id then
                    local a = angle - (i - (m + 1) / 2) * itemStep
                    b:ClearAllPoints()
                    b:SetPoint("CENTER", wheel, "CENTER", Pos(a, ITEM_RADIUS))
                    b:SetAttribute("item", "item:" .. id)
                    b.itemID = id
                    b.cdItem = id
                    b.icon:SetTexture(ItemIcon(id))
                    local count = ItemCount(id)
                    b.count:SetText(count > 1 and count or "")
                    b:Show()
                else
                    b.itemID = nil
                    b.cdItem = nil
                    b:SetAttribute("item", nil)
                    b:Hide()
                end
            end
        else
            cat.cdItem = nil
            cat:SetAttribute("item", nil)
            cat:Hide()
            ring:Hide()
        end
    end
    UpdateCooldowns()
end

-- counts only (allowed in combat: just text)
local function UpdateCounts()
    for c = 1, MAX_CATS do
        for i = 1, MAX_ITEMS do
            local b = itemButtons[c] and itemButtons[c][i]
            if b and b.itemID then
                local count = ItemCount(b.itemID)
                b.count:SetText(count > 1 and count or "")
                b.icon:SetDesaturated(count == 0)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
local rebuildQueued = false

local function QueueRebuild()
    if rebuildQueued then return end
    rebuildQueued = true
    C_Timer.After(0.3, function()
        rebuildQueued = false
        Rebuild()
    end)
end

local function Init()
    if wheel then return end
    Build()
    -- re-read your Baganator categories each time it opens out of combat
    toggle:HookScript("PreClick", function()
        if not InCombatLockdown() then Rebuild() end
    end)
    Rebuild()
    if not GetBindingKey("CLICK BagWheelToggle:LeftButton") then
        print(PREFIX .. "set a key in Options > AddOns > Bag Wheel (or /bagwheel out of combat).")
    end
end

---------------------------------------------------------------------------
-- Options > AddOns > Bag Wheel: set the key right there. It's the same
-- binding as Options > Keybindings > AddOns > Bag Wheel.
---------------------------------------------------------------------------
local COMMAND = "CLICK BagWheelToggle:LeftButton"
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }

local function KeyText()
    local key = GetBindingKey(COMMAND)
    if not key then return "Not set" end
    return (GetBindingText and GetBindingText(key)) or key
end

local function SetWheelKey(key)
    if InCombatLockdown() then
        print(PREFIX .. "key bindings can't change in combat; try again after the fight.")
        return
    end
    -- free the old key(s), then claim the new one
    for _, old in ipairs({ GetBindingKey(COMMAND) }) do SetBinding(old, nil) end
    if key then
        local was = GetBindingAction(key)
        if was and was ~= "" and was ~= COMMAND then
            print(PREFIX .. key .. " was " .. ((GetBindingName and GetBindingName(was)) or was) .. "; it now opens the wheel.")
        end
        SetBinding(key, COMMAND)
    end
    SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1)
end

local function BuildOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Bag Wheel")
    local about = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    about:SetWidth(560)
    about:SetJustifyH("LEFT")
    about:SetText("Your Baganator categories in a ring at the cursor; hover one for its items, click one to use it. Works in combat.")

    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -20)
    label:SetText("Open / close key")

    local bind = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    bind:SetSize(180, 26)
    bind:SetPoint("LEFT", label, "RIGHT", 12, 0)
    local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clear:SetSize(80, 26)
    clear:SetPoint("LEFT", bind, "RIGHT", 6, 0)
    clear:SetText("Clear")
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -14)
    hint:SetText("Click the button, then press a key (with Shift / Ctrl / Alt if you like). Escape cancels.")

    local listening = false
    local function Show()
        bind:SetText(listening and "Press a key..." or KeyText())
    end
    local function Stop()
        listening = false
        bind:EnableKeyboard(false)
        bind:SetScript("OnKeyDown", nil)
        Show()
    end
    local function Combo(key)
        local c = ""
        if IsAltKeyDown() then c = c .. "ALT-" end
        if IsControlKeyDown() then c = c .. "CTRL-" end
        if IsShiftKeyDown() then c = c .. "SHIFT-" end
        return c .. key
    end
    bind:RegisterForClicks("AnyUp")
    bind:SetScript("OnClick", function(self, mouseButton)
        if listening then
            -- a mouse button while listening: the extra mouse buttons can be bound too
            if mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then
                local map = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
                if map[mouseButton] then SetWheelKey(Combo(map[mouseButton])) end
            end
            Stop()
            return
        end
        listening = true
        self:EnableKeyboard(true)
        self:SetScript("OnKeyDown", function(_, key)
            if MODIFIER_KEYS[key] then return end -- wait for the real key
            if key ~= "ESCAPE" then SetWheelKey(Combo(key)) end
            Stop()
        end)
        Show()
    end)
    clear:SetScript("OnClick", function() SetWheelKey(nil); Stop() end)

    -- which categories the wheel shows (made fresh each time the page opens,
    -- so new Baganator categories appear)
    local showLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showLabel:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -24)
    showLabel:SetText("Show these categories")
    local checks = {}
    local function FillChecks()
        local cats = ReadCategories(true) or {}
        for i, entry in ipairs(cats) do
            local cb = checks[i]
            if not cb then
                cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
                cb:SetSize(24, 24)
                local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
                cb:SetPoint("TOPLEFT", showLabel, "BOTTOMLEFT", col * 220, -6 - row * 26)
                cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
                cb:SetScript("OnClick", function(self)
                    local key = self.catName:lower()
                    BagWheelDB.hidden[key] = (not self:GetChecked()) or nil
                    if InCombatLockdown() then dirty = true else Rebuild() end
                end)
                checks[i] = cb
            end
            cb.catName = entry.name
            cb.label:SetText(entry.name)
            cb:SetChecked(not BagWheelDB.hidden[entry.name:lower()])
            cb:Show()
        end
        for i = #cats + 1, #checks do checks[i]:Hide() end
    end

    panel:SetScript("OnShow", function() Stop(); FillChecks() end)
    panel:SetScript("OnHide", function() if listening then Stop() end end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Bag Wheel")
    Settings.RegisterAddOnCategory(category)
end

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_COOLDOWN" then
        if wheel and wheel:IsShown() then UpdateCooldowns() end
        return
    end
    if event == "PLAYER_LOGIN" then
        -- saved settings; Tools starts left out of the wheel
        BagWheelDB = BagWheelDB or {}
        if not BagWheelDB.hidden then BagWheelDB.hidden = { tools = true } end
        pcall(BuildOptions) -- Options > AddOns > Bag Wheel
        if InCombatLockdown() then return end -- the wheel is built when this fight ends
        Init()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not wheel then Init() elseif dirty then Rebuild() end
    elseif event == "BAG_UPDATE_DELAYED" then
        if InCombatLockdown() then
            dirty = true
            UpdateCounts()
        else
            QueueRebuild()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if not InCombatLockdown() then QueueRebuild() end
    end
end)

SLASH_BAGWHEEL1 = "/bagwheel"
SlashCmdList.BAGWHEEL = function()
    if not wheel then print(PREFIX .. "not ready yet.") return end
    if InCombatLockdown() then
        print(PREFIX .. "in combat, use the key (Options > Keybindings > AddOns > Bag Wheel).")
        return
    end
    if wheel:IsShown() then wheel:Hide() return end
    Rebuild()
    for c = 1, MAX_CATS do rings[c]:Hide() end
    local x, y = GetCursorPosition()
    local scale = wheel:GetEffectiveScale()
    wheel:ClearAllPoints()
    wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    wheel:Show()
end
