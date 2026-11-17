-- Emote Wheel
-- Hold F: a wheel of emotes opens around your mouse. Point at one and let go
-- of F to do it. Let go in the middle to cancel.
-- Tap F instead: the wheel stays open; click an emote, or press F or Escape
-- to close it.
--
-- If you have a target, most emotes are aimed at them ("You cheer at X"),
-- same as typing /cheer.
--
-- The emotes are drawn with the game's own action-button template, so they
-- match your action bars on whatever art this client uses.

---------------------------------------------------------------------------
-- Settings: change these, then type /reload in game
---------------------------------------------------------------------------
local KEY        = "F"   -- key that opens the wheel; nil = set it yourself in
                         -- Options > Keybindings > AddOns > Emote Wheel
local RADIUS     = 115   -- distance from the middle to each emote, in pixels
local ICON       = 42    -- size of each emote button, in pixels
local DEAD_ZONE  = 34    -- pointing closer to the middle than this = cancel
local HOLD_TIME  = 0.25  -- seconds; a shorter press counts as a tap
local SOUNDS     = true  -- the game's menu sounds on open, hover and pick

-- Clockwise from the top. Add, remove or reorder freely (up to about 12).
-- { label, emote command (same as its /command), icon from Interface\Icons }
-- An icon this game version doesn't have shows as a question mark.
local EMOTES = {
    { "Point",  "POINT",  "Ability_Hunter_MarkedForDeath" },
    { "Dance",  "DANCE",  "INV_Misc_Drum_02" },
    { "Laugh",  "LAUGH",  "Achievement_Halloween_Smiley_01" },
    { "Cheer",  "CHEER",  "Ability_Warrior_BattleShout" },
    { "Wave",   "WAVE",   "Achievement_Reputation_01" },
    { "Cry",    "CRY",    "Ability_Druid_Cower" },
    { "Kneel",  "KNEEL",  "Spell_Holy_PrayerOfHealing" },
    { "Bow",    "BOW",    "Achievement_Reputation_08" },
    { "Salute", "SALUTE", "INV_Sword_04" },
    { "Sleep",  "SLEEP",  "Spell_Nature_Sleep" },
}

---------------------------------------------------------------------------
-- Key Bindings menu labels
---------------------------------------------------------------------------
BINDING_HEADER_EMOTEWHEEL    = "Emote Wheel"
BINDING_NAME_EMOTEWHEEL_OPEN = "Open emote wheel (hold or tap)"

local MASK     = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function IconPath(name)
    local path = "Interface\\Icons\\" .. name
    if GetFileIDFromPath and not GetFileIDFromPath(path) then return QUESTION end
    return path
end

local function Sound(kit)
    if SOUNDS and SOUNDKIT and SOUNDKIT[kit] and PlaySound then
        pcall(PlaySound, SOUNDKIT[kit])
    end
end

---------------------------------------------------------------------------
-- Action-button look. At login we copy the frame, hover and selected art
-- from your real action bar button 1, so the wheel matches your bars on
-- whatever art this client uses. Plain frames, not the game's secure button
-- template: that one can't be shown or hidden in combat.
---------------------------------------------------------------------------
-- Sizes and offsets are fractions of the button's width.
local ART = {
    frame   = { file = "Interface\\Buttons\\UI-Quickslot2", w = 66/36, h = 66/36, x = 0, y = -1/36 },
    hover   = { file = "Interface\\Buttons\\ButtonHilight-Square", blend = "ADD", w = 1, h = 1, x = 0, y = 0 },
    checked = { file = "Interface\\Buttons\\CheckButtonHilight", blend = "ADD", w = 1, h = 1, x = 0, y = 0 },
    mask    = nil, -- newer clients round the icon corners with a mask
}

-- Reads one texture of a real button into the ART format, or nil.
local function Borrow(tex, btn)
    if not tex then return nil end
    local art = {}
    art.atlas = tex.GetAtlas and tex:GetAtlas() or nil
    if not art.atlas then
        art.file = tex:GetTexture()
        if not art.file then return nil end
        art.coords = { tex:GetTexCoord() }
    end
    art.blend = tex.GetBlendMode and tex:GetBlendMode() or nil
    local bw, bh = btn:GetSize()
    local tw, th = tex:GetSize()
    if not (bw and bw > 0 and bh > 0 and tw and tw > 0 and th > 0) then return nil end
    art.w, art.h = tw / bw, th / bh
    local bx, by = btn:GetCenter()
    local tx, ty = tex:GetCenter()
    if bx and tx then
        art.x, art.y = (tx - bx) / bw, (ty - by) / bh
    else
        art.x, art.y = 0, 0
    end
    return art
end

local function BorrowFromActionBar()
    local btn = _G.ActionButton1
    if not btn or not btn.GetNormalTexture then return end
    local frame = Borrow(btn:GetNormalTexture(), btn)
    -- an empty classic slot uses a dark socket that would cover the icon
    local socket = GetFileIDFromPath and GetFileIDFromPath("Interface\\Buttons\\UI-Quickslot")
    if frame and not (frame.file and (frame.file == socket or frame.file == "Interface\\Buttons\\UI-Quickslot")) then
        ART.frame = frame
    end
    ART.hover   = Borrow(btn:GetHighlightTexture(), btn) or ART.hover
    ART.checked = btn.GetCheckedTexture and Borrow(btn:GetCheckedTexture(), btn) or ART.checked
    local mask = btn.IconMask
    if mask and mask.GetAtlas and mask:GetAtlas() then ART.mask = mask:GetAtlas() end
end

local function Paint(tex, art, size)
    if art.atlas then
        tex:SetAtlas(art.atlas)
    else
        tex:SetTexture(art.file)
        if art.coords then tex:SetTexCoord(unpack(art.coords)) end
    end
    tex:SetBlendMode(art.blend or "BLEND")
    tex:ClearAllPoints()
    tex:SetSize(size * art.w, size * art.h)
    tex:SetPoint("CENTER", size * art.x, size * art.y)
end

local allSlots = {}

local function StyleSlot(s)
    Paint(s.frame, ART.frame, s.size)
    Paint(s.hover, ART.hover, s.size)
    Paint(s.checked, ART.checked, s.size)
    if ART.mask and not s.mask then
        s.mask = s:CreateMaskTexture()
        s.mask:SetAtlas(ART.mask)
        s.mask:SetAllPoints(s.icon)
        s.icon:AddMaskTexture(s.mask)
    end
end

-- One emote button. Mouse is off: the wheel does the pointing.
local function Slot(parent, size)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(size, size)
    s.size = size
    s.icon = s:CreateTexture(nil, "BACKGROUND")
    s.icon:SetAllPoints()
    s.frame = s:CreateTexture(nil, "ARTWORK")
    s.checked = s:CreateTexture(nil, "OVERLAY", nil, 0)
    s.hover = s:CreateTexture(nil, "OVERLAY", nil, 1)
    s.checked:Hide()
    s.hover:Hide()
    StyleSlot(s)
    allSlots[#allSlots + 1] = s
    return s
end

---------------------------------------------------------------------------
-- The wheel
---------------------------------------------------------------------------
local OUTER = RADIUS + ICON / 2 + 26 -- room for the labels under the buttons

-- Named so Escape closes it (UISpecialFrames).
local wheel = CreateFrame("Frame", "EmoteWheelFrame", UIParent)
wheel:SetSize(OUTER * 2, OUTER * 2)
wheel:SetFrameStrata("DIALOG")
wheel:Hide()
table.insert(UISpecialFrames, "EmoteWheelFrame")

-- soft dark disc behind it all, so it reads over bright scenery
local disc = wheel:CreateTexture(nil, "BACKGROUND")
disc:SetSize(OUTER * 2, OUTER * 2)
disc:SetPoint("CENTER")
disc:SetColorTexture(0, 0, 0, 0.45)
local discMask = wheel:CreateMaskTexture()
discMask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
discMask:SetAllPoints(disc)
disc:AddMaskTexture(discMask)

-- the middle: shows the emote you're pointing at
local hub = Slot(wheel, ICON * 1.3)
hub:SetPoint("CENTER")
local hubText = wheel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
hubText:SetPoint("TOP", hub, "BOTTOM", 0, -6)
local hubHint = wheel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hubHint:SetPoint("CENTER")

local slots = {}
local step = 360 / #EMOTES
for i, e in ipairs(EMOTES) do
    local a = math.rad(90 - (i - 1) * step)
    local s = Slot(wheel, ICON)
    s:SetPoint("CENTER", wheel, "CENTER", RADIUS * math.cos(a), RADIUS * math.sin(a))
    s.icon:SetTexture(IconPath(e[3]))
    s.label = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.label:SetPoint("TOP", s, "BOTTOM", 0, -4)
    s.label:SetText(e[1])
    slots[i] = s
end

-- quick fade-in when it opens
local intro = wheel:CreateAnimationGroup()
local fadeIn = intro:CreateAnimation("Alpha")
fadeIn:SetFromAlpha(0)
fadeIn:SetToAlpha(1)
fadeIn:SetDuration(0.12)

---------------------------------------------------------------------------
-- Picking
---------------------------------------------------------------------------
local hovered      -- index into EMOTES, or nil
local pressedAt    -- GetTime() when the key went down
local sticky       -- true after a tap: wheel stays open until a click

local function Highlight(index)
    if index == hovered then return end
    if index then Sound("U_CHAT_SCROLL_BUTTON") end
    hovered = index
    for i, s in ipairs(slots) do
        local on = (i == index)
        s.checked:SetShown(on)
        s.hover:SetShown(on)
        local v = (on or not index) and 1 or 0.55 -- dim the others while pointing
        s.icon:SetVertexColor(v, v, v)
        if on then
            s.label:SetTextColor(1, 1, 1)
        else
            s.label:SetTextColor(NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.r or 1,
                                 NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.g or 0.82,
                                 NORMAL_FONT_COLOR and NORMAL_FONT_COLOR.b or 0)
        end
    end
    if index then
        hub.icon:SetTexture(IconPath(EMOTES[index][3]))
        hub:Show()
        hubText:SetText(EMOTES[index][1])
        hubHint:SetText("")
    else
        hub:Hide()
        hubText:SetText("")
        hubHint:SetText(sticky and "Click one" or "Let go to cancel")
    end
end

local function PointedAt()
    local cx, cy = wheel:GetCenter()
    if not cx then return nil end
    local x, y = GetCursorPosition()
    local scale = wheel:GetEffectiveScale()
    local dx, dy = x / scale - cx, y / scale - cy
    if dx * dx + dy * dy < DEAD_ZONE * DEAD_ZONE then return nil end
    local fromTop = (90 - math.deg(atan2(dy, dx))) % 360 -- clockwise from the top
    return math.floor((fromTop + step / 2) / step) % #EMOTES + 1
end

local function Redraw(index)
    hovered = 0 -- force Highlight to redraw everything
    Highlight(index)
end

local function Open()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    wheel:ClearAllPoints()
    wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    sticky = false
    Redraw(nil)
    wheel:EnableMouse(false) -- holding: never eat clicks
    wheel:Show()
    intro:Play()
    Sound("IG_MAINMENU_OPEN")
end

local function Close(silent)
    if not wheel:IsShown() then return end
    wheel:Hide()
    if not silent then Sound("IG_MAINMENU_CLOSE") end
end

local function Perform(index)
    if not index then
        Close()
        return
    end
    Close(true)
    Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    local ok, err = pcall(DoEmote, EMOTES[index][2])
    if not ok then
        print("|cffc79c6eEmote Wheel|r couldn't do " .. EMOTES[index][1] .. ": " .. tostring(err))
    end
end

wheel:SetScript("OnUpdate", function()
    Highlight(PointedAt())
end)

-- After a tap the wheel takes clicks: click an emote to do it, click the
-- middle to close.
wheel:SetScript("OnMouseUp", function()
    Perform(PointedAt())
end)

function EmoteWheel_OnKey(keystate)
    if keystate == "down" then
        if wheel:IsShown() then
            Close() -- second press closes a tapped-open wheel
            pressedAt = nil
        else
            pressedAt = GetTime()
            Open()
        end
    elseif pressedAt then
        local held = GetTime() - pressedAt
        pressedAt = nil
        if held >= HOLD_TIME or PointedAt() then
            Perform(PointedAt())
        else
            sticky = true
            wheel:EnableMouse(true)
            Redraw(nil)
        end
    end
end

---------------------------------------------------------------------------
-- Put the wheel on F without touching your saved key bindings. Turning the
-- addon off gives F back. Bindings can't change in combat, so a /reload
-- mid-fight waits until the fight ends.
---------------------------------------------------------------------------
local binder = CreateFrame("Frame")

local styled = false

local function BindKey()
    if not styled then
        styled = true
        if pcall(BorrowFromActionBar) then
            for _, s in ipairs(allSlots) do pcall(StyleSlot, s) end
        end
    end
    if not KEY then return end
    if InCombatLockdown() then
        binder:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    binder:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ClearOverrideBindings(binder)
    SetOverrideBinding(binder, false, KEY, "EMOTEWHEEL_OPEN")
end

binder:RegisterEvent("PLAYER_LOGIN")
binder:SetScript("OnEvent", BindKey)
