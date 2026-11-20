-- Mount Ring
-- A ring on your minimap, 28 yards out from you (the minimap is a to-scale
-- view from above, so the ring is true distance whatever the zoom). Anything
-- inside it, a node, a quest marker, a mailbox, is closer than it's worth
-- mounting for. (Addons can't draw on the ground in the world, so the
-- minimap is where the bubble goes.)
--
--   Mount Ring key (Options > Keybindings > AddOns > Mount Ring)
--     tap          ring on / off
--     hold         ring shows while you hold it
--   /mountring           on / off
--   /mountring 28        set the distance in yards
--   /mountring auto      also show it by itself whenever you're on foot,
--                        out of combat (type it again to stop)
--
-- If you zoom the minimap in so far that the ring won't fit, it says so at
-- the edge: zoom out a step.

local PREFIX = "|cffc79c6eMount Ring|r "
local DEFAULT_YARDS = 28
local DOTS = 72         -- dots around the ring
local HOLD = 0.3        -- a key press longer than this is a hold
local COLOR = { 0.35, 1, 0.45 }

BINDING_HEADER_MOUNTRING = "Mount Ring"
BINDING_NAME_MOUNTRING_TOGGLE = "Mount range ring (tap: on / off, hold: while held)"

local DB
local isSecret = issecretvalue or function() return false end

---------------------------------------------------------------------------
-- How many yards the minimap shows from its centre to its edge
---------------------------------------------------------------------------
-- (the game's sizes per zoom step, centre to edge, when it can't tell us)
local RADIUS = {
    outdoor = { [0] = 233.33, 200, 166.67, 133.33, 100, 66.67 },
    indoor  = { [0] = 150, 120, 90, 60, 40, 25 },
}

local function ViewRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, r = pcall(C_Minimap.GetViewRadius)
        if ok and not isSecret(r) and type(r) == "number" and r > 0 then return r end
    end
    local zoom = Minimap:GetZoom() or 0
    local inside = IsIndoors and IsIndoors()
    if isSecret(inside) then inside = false end
    local t = inside and RADIUS.indoor or RADIUS.outdoor
    return t[zoom] or t[0]
end

---------------------------------------------------------------------------
-- The ring
---------------------------------------------------------------------------
local ring = CreateFrame("Frame", "MountRingFrame", Minimap)
ring:SetPoint("CENTER", Minimap, "CENTER")
ring:SetFrameLevel(Minimap:GetFrameLevel() + 4)
ring:EnableMouse(false) -- never blocks clicks on the minimap
ring:Hide()

-- a soft tint inside
local fill = ring:CreateTexture(nil, "BACKGROUND")
fill:SetAllPoints()
fill:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
fill:SetVertexColor(COLOR[1], COLOR[2], COLOR[3], 0.1)

-- the edge: a ring of small dots (crisp at any size, no picture needed)
local dots = {}
for i = 1, DOTS do
    local d = ring:CreateTexture(nil, "OVERLAY")
    d:SetColorTexture(COLOR[1], COLOR[2], COLOR[3], 0.95)
    d:SetSize(2, 2)
    dots[i] = d
end

local label = ring:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetTextColor(COLOR[1], COLOR[2], COLOR[3])
label:SetShadowOffset(1, -1)

-- shown instead when the ring is bigger than the minimap
local tooFar = Minimap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tooFar:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 14)
tooFar:SetTextColor(COLOR[1], COLOR[2], COLOR[3])
tooFar:Hide()

local fadeIn = ring:CreateAnimationGroup()
local fade = fadeIn:CreateAnimation("Alpha")
fade:SetFromAlpha(0)
fade:SetToAlpha(1)
fade:SetDuration(0.15)

local lastR, lastW
local function Layout(force)
    local yards = (DB and DB.yards) or DEFAULT_YARDS
    local view = ViewRadius()
    local half = Minimap:GetWidth() / 2
    local r = yards / view * half
    if not force and r == lastR and half == lastW then return end
    lastR, lastW = r, half
    if r > half - 1 then
        -- won't fit: say so at the edge instead
        for _, d in ipairs(dots) do d:Hide() end
        fill:Hide()
        label:Hide()
        tooFar:SetText(yards .. " yd is past the edge: zoom out")
        tooFar:Show()
        return
    end
    tooFar:Hide()
    fill:Show()
    ring:SetSize(r * 2, r * 2)
    local size = r < 30 and 2 or 3
    for i, d in ipairs(dots) do
        local a = (i - 1) / DOTS * 2 * math.pi
        d:ClearAllPoints()
        d:SetSize(size, size)
        d:SetPoint("CENTER", ring, "CENTER", math.cos(a) * r, math.sin(a) * r)
        d:Show()
    end
    label:ClearAllPoints()
    label:SetPoint("BOTTOM", ring, "TOP", 0, 1)
    label:SetText(yards .. " yd")
    -- the label hides when it would sit off the top of the minimap
    label:SetShown(r + 12 < half)
end

local since = 0
ring:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.2 then return end -- zoom and indoor changes, five times a second
    since = 0
    Layout(false)
end)

---------------------------------------------------------------------------
-- When it shows
---------------------------------------------------------------------------
local toggled = false -- tapped on
local held = false    -- the key is down
local auto = false    -- /mountring auto wants it now

local function Apply()
    local want = toggled or held or auto
    if want and not ring:IsShown() then
        Layout(true)
        ring:Show()
        fadeIn:Play()
    elseif not want and ring:IsShown() then
        ring:Hide()
        tooFar:Hide()
    end
end

local function OnFoot()
    if not DB or not DB.auto then return false end
    local mounted, combat = IsMounted(), InCombatLockdown()
    local taxi, dead = UnitOnTaxi("player"), UnitIsDeadOrGhost("player")
    if isSecret(mounted) or isSecret(taxi) or isSecret(dead) then return false end
    return not mounted and not combat and not taxi and not dead
end

local function CheckAuto()
    auto = OnFoot()
    Apply()
end

local downAt
function MountRing_Key(keystate)
    if keystate == "down" then
        downAt = GetTime()
        held = true
        Apply()
    else
        held = false
        -- a quick tap flips it; a hold only showed it while held
        if downAt and GetTime() - downAt < HOLD then toggled = not toggled end
        downAt = nil
        Apply()
    end
end

---------------------------------------------------------------------------
-- Chat command and events
---------------------------------------------------------------------------
SLASH_MOUNTRING1 = "/mountring"
SlashCmdList.MOUNTRING = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local n = tonumber(msg:match("^(%d+%.?%d*)"))
    if n then
        if n < 5 or n > 100 then
            print(PREFIX .. "pick a distance from 5 to 100 yards.")
            return
        end
        DB.yards = n
        print(PREFIX .. "the ring is now " .. n .. " yards.")
        Layout(true)
    elseif msg == "auto" then
        DB.auto = not DB.auto
        print(PREFIX .. (DB.auto and "shows by itself whenever you're on foot out of combat."
            or "only shows from your key or /mountring now."))
        CheckAuto()
    elseif msg == "" then
        toggled = not toggled
        Apply()
    else
        print(PREFIX .. "/mountring (on / off), /mountring 28 (yards), /mountring auto. "
            .. "Bind a key in Options > Keybindings > AddOns > Mount Ring: tap to toggle, hold to peek.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
pcall(events.RegisterEvent, events, "PLAYER_MOUNT_DISPLAY_CHANGED")
pcall(events.RegisterEvent, events, "MINIMAP_UPDATE_ZOOM")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "MountRing" then return end
        MountRingDB = MountRingDB or {}
        DB = MountRingDB
        DB.yards = DB.yards or DEFAULT_YARDS
        events:UnregisterEvent("ADDON_LOADED")
        -- a once-a-second look too, for clients that don't say when you mount
        C_Timer.NewTicker(1, function() if DB.auto or auto then CheckAuto() end end)
        return
    end
    if event == "MINIMAP_UPDATE_ZOOM" then
        if ring:IsShown() then Layout(true) end
        return
    end
    -- mounting, a fight, dying: /mountring auto follows along
    -- (PLAYER_REGEN_DISABLED fires just before combat lockdown starts)
    if event == "PLAYER_REGEN_DISABLED" then
        auto = false
        Apply()
    else
        C_Timer.After(0.1, CheckAuto)
    end
end)
