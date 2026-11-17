-- Spliffbars: the experience mote
-- ns.SendMote(bar, color, onArrive, lift): a glowing, spinning mote of light
-- leaves your cursor, curves across the screen shedding sparkles, and
-- bursts into the bar; onArrive runs as it lands (the bar's flourish).
-- Used by Skills.lua on a skill-up ("Experience Mote" in a row's Edit Mode
-- panel). Purely visual: nothing here can be clicked.

local _, ns = ...

local STAR = "Interface\\Cooldown\\star4" -- the game's four-point sparkle
local RING = "Interface\\Cooldown\\ping4" -- a soft ring

-- everything draws on one layer above the whole UI
local layer = CreateFrame("Frame", nil, UIParent)
layer:SetAllPoints()
layer:SetFrameStrata("TOOLTIP")
layer:SetFrameLevel(50)

local function Bright(c, k)
    -- the colour lifted toward white (k: how much)
    return c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k
end

-- positions are in UIParent's units, from its bottom left
local function UIScale() return UIParent:GetEffectiveScale() end
local function CursorPos()
    local x, y = GetCursorPosition()
    local s = UIScale()
    return x / s, y / s
end
local function CenterOf(frame)
    local x, y = frame:GetCenter()
    if not x then return nil end
    local k = frame:GetEffectiveScale() / UIScale()
    return x * k, y * k
end

---------------------------------------------------------------------------
-- Sparkles: small stars that drift and fade (pooled)
---------------------------------------------------------------------------
local sparks = {}
local function Spark()
    for _, s in ipairs(sparks) do
        if not s.busy then return s end
    end
    local s = layer:CreateTexture(nil, "OVERLAY")
    s:SetTexture(STAR)
    s:SetBlendMode("ADD")
    s:Hide()
    s.anim = s:CreateAnimationGroup()
    s.fade = s.anim:CreateAnimation("Alpha")
    s.fade:SetFromAlpha(1)
    s.fade:SetToAlpha(0)
    s.shrink = s.anim:CreateAnimation("Scale")
    s.shrink:SetScale(0.25, 0.25)
    s.drift = s.anim:CreateAnimation("Translation")
    s.drift:SetSmoothing("OUT")
    s.anim:SetScript("OnFinished", function() s:Hide(); s.busy = false end)
    sparks[#sparks + 1] = s
    return s
end

-- one sparkle at (x, y), drifting by (dx, dy) over its life
local function Sparkle(x, y, r, g, b, size, life, dx, dy)
    local s = Spark()
    s.busy = true
    s.anim:Stop()
    s:ClearAllPoints()
    s:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    s:SetSize(size, size)
    s:SetVertexColor(r, g, b)
    s:SetRotation(math.random() * math.pi)
    s.fade:SetDuration(life)
    s.shrink:SetDuration(life)
    s.drift:SetDuration(life)
    s.drift:SetOffset(dx, dy)
    s:Show()
    s.anim:Play()
end

---------------------------------------------------------------------------
-- Motes (pooled, so several skill-ups at once each get one)
---------------------------------------------------------------------------
local motes = {}

local function Ease(t) -- slow out, fast through the middle, soft landing
    if t < 0.5 then return 2 * t * t end
    return 1 - (-2 * t + 2) ^ 2 / 2
end

local function Burst(m)
    local x, y = m.x2, m.y2
    local r, g, b = m.r, m.g, m.b
    -- a ring swells and fades where it lands
    local ring = m.ring
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    ring:SetVertexColor(r, g, b)
    ring.anim:Stop()
    ring:Show()
    ring.anim:Play()
    -- and sparkles fly out all round
    for i = 1, 10 do
        local a = (i / 10) * 2 * math.pi + math.random() * 0.4
        local d = 18 + math.random() * 22
        Sparkle(x, y, r, g, b, 8 + math.random() * 8, 0.5 + math.random() * 0.3,
            math.cos(a) * d, math.sin(a) * d)
    end
end

local function Step(m, elapsed)
    m.t = m.t + elapsed / m.dur
    -- the bar's centre now (in case it moved), else where it was
    if m.target then
        local tx, ty = CenterOf(m.target)
        if tx then m.x2, m.y2 = tx, ty end
    end
    if m.t >= 1 then
        m:SetScript("OnUpdate", nil)
        m:Hide()
        m.active = false
        Burst(m)
        if m.onArrive then
            local f = m.onArrive
            m.onArrive = nil
            pcall(f)
        end
        return
    end
    local u = Ease(m.t)
    local v = 1 - u
    -- along a curve: start, a bend point off to one side, the bar
    local x = v * v * m.x0 + 2 * v * u * m.cx + u * u * m.x2
    local y = v * v * m.y0 + 2 * v * u * m.cy + u * u * m.y2
    m:ClearAllPoints()
    m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    -- spin and shimmer
    local pulse = 1 + 0.18 * math.sin(m.t * 24)
    m.core:SetRotation(m.t * 9)
    m.core2:SetRotation(-m.t * 7 + math.pi / 4)
    m.core:SetSize(26 * pulse, 26 * pulse)
    m.core2:SetSize(18 * pulse, 18 * pulse)
    m.halo:SetAlpha(0.45 + 0.25 * math.sin(m.t * 17))
    -- a trail of sparkles, about one every 7 pixels travelled
    local lx, ly = m.lx or x, m.ly or y
    m.travel = (m.travel or 0) + math.sqrt((x - lx) ^ 2 + (y - ly) ^ 2)
    m.lx, m.ly = x, y
    local n = 0
    while m.travel >= 7 and n < 4 do
        m.travel = m.travel - 7
        n = n + 1
        Sparkle(x + (math.random() - 0.5) * 8, y + (math.random() - 0.5) * 8, m.r, m.g, m.b,
            5 + math.random() * 7, 0.45 + math.random() * 0.35,
            (math.random() - 0.5) * 10, -4 - math.random() * 10)
    end
end

local function NewMote()
    local m = CreateFrame("Frame", nil, layer)
    m:SetSize(32, 32)
    m:Hide()
    m.halo = m:CreateTexture(nil, "BACKGROUND")
    m.halo:SetTexture(RING)
    m.halo:SetBlendMode("ADD")
    m.halo:SetSize(40, 40)
    m.halo:SetPoint("CENTER")
    m.core = m:CreateTexture(nil, "ARTWORK")
    m.core:SetTexture(STAR)
    m.core:SetBlendMode("ADD")
    m.core:SetPoint("CENTER")
    m.core2 = m:CreateTexture(nil, "OVERLAY")
    m.core2:SetTexture(STAR)
    m.core2:SetBlendMode("ADD")
    m.core2:SetPoint("CENTER")
    -- the landing ring
    m.ring = layer:CreateTexture(nil, "OVERLAY")
    m.ring:SetTexture(RING)
    m.ring:SetBlendMode("ADD")
    m.ring:SetSize(24, 24)
    m.ring:Hide()
    m.ring.anim = m.ring:CreateAnimationGroup()
    local grow = m.ring.anim:CreateAnimation("Scale")
    grow:SetScale(3.2, 3.2)
    grow:SetDuration(0.45)
    grow:SetSmoothing("OUT")
    local fade = m.ring.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.45)
    m.ring.anim:SetScript("OnFinished", function() m.ring:Hide() end)
    motes[#motes + 1] = m
    return m
end

---------------------------------------------------------------------------
-- Flying items: ns.FlyItem(icon, quality, count, target, delay): an item's
-- icon pops out at your cursor and swoops into target (your bag button),
-- trailing sparkles in its quality colour, and lands with a burst. Used by
-- Loot.lua for what you mine.
---------------------------------------------------------------------------
local fliers = {}

local function QualityColor(q)
    if type(q) == "number" and not ns.isSecret(q) and q >= 2 then
        local ok, r, g, b
        if C_Item and C_Item.GetItemQualityColor then ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
        elseif GetItemQualityColor then ok, r, g, b = pcall(GetItemQualityColor, q) end
        if ok and type(r) == "number" then return r, g, b end
    end
    return 1, 0.85, 0.5 -- plain items: a soft gold
end

local function NewFlier()
    local f = CreateFrame("Frame", nil, layer)
    f:SetSize(28, 28)
    f:Hide()
    f.halo = f:CreateTexture(nil, "BACKGROUND")
    f.halo:SetTexture(RING)
    f.halo:SetBlendMode("ADD")
    f.halo:SetPoint("CENTER")
    f.border = f:CreateTexture(nil, "BORDER")
    f.border:SetAllPoints()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.count:SetPoint("BOTTOMRIGHT", 3, -2)
    -- its name, under it, in its quality colour
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.name:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.name:SetShadowOffset(1, -1)
    f.ring = layer:CreateTexture(nil, "OVERLAY")
    f.ring:SetTexture(RING)
    f.ring:SetBlendMode("ADD")
    f.ring:SetSize(22, 22)
    f.ring:Hide()
    f.ring.anim = f.ring:CreateAnimationGroup()
    local grow = f.ring.anim:CreateAnimation("Scale")
    grow:SetScale(2.6, 2.6)
    grow:SetDuration(0.4)
    grow:SetSmoothing("OUT")
    local fade = f.ring.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.4)
    f.ring.anim:SetScript("OnFinished", function() f.ring:Hide() end)
    fliers[#fliers + 1] = f
    return f
end

local function FlierStep(f, elapsed)
    f.t = f.t + elapsed / f.dur
    if f.target then
        local tx, ty = CenterOf(f.target)
        if tx then f.x2, f.y2 = tx, ty end
    end
    if f.t >= 1 then
        f:SetScript("OnUpdate", nil)
        f:Hide()
        f.active = false
        -- the landing: a ring and a little shower of sparkles
        f.ring:ClearAllPoints()
        f.ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", f.x2, f.y2)
        f.ring:SetVertexColor(f.r, f.g, f.b)
        f.ring.anim:Stop()
        f.ring:Show()
        f.ring.anim:Play()
        for i = 1, 6 do
            local a = (i / 6) * 2 * math.pi + math.random() * 0.5
            local d = 12 + math.random() * 14
            Sparkle(f.x2, f.y2, f.r, f.g, f.b, 6 + math.random() * 6, 0.4 + math.random() * 0.25,
                math.cos(a) * d, math.sin(a) * d)
        end
        if f.onArrive then
            local cb = f.onArrive
            f.onArrive = nil
            pcall(cb)
        end
        return
    end
    local u = Ease(f.t)
    local v = 1 - u
    local x = v * v * f.x0 + 2 * v * u * f.cx + u * u * f.x2
    local y = v * v * f.y0 + 2 * v * u * f.cy + u * u * f.y2
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    -- pops up big as it leaves, shrinks as it nears the bag
    local pop = 1 + 0.35 * math.sin(math.pi * math.min(f.t * 3, 1))
    local size = 30 * pop * (1 - 0.45 * u)
    f:SetSize(size, size)
    -- the name shows through most of the flight, fading near the bag
    f.name:SetAlpha(math.max(0, math.min(1, (0.85 - f.t) / 0.25)))
    f.halo:SetSize(size * 1.9, size * 1.9)
    f.halo:SetAlpha(0.5 + 0.2 * math.sin(f.t * 20))
    -- the trail
    local lx, ly = f.lx or x, f.ly or y
    f.travel = (f.travel or 0) + math.sqrt((x - lx) ^ 2 + (y - ly) ^ 2)
    f.lx, f.ly = x, y
    local n = 0
    while f.travel >= 9 and n < 3 do
        f.travel = f.travel - 9
        n = n + 1
        Sparkle(x + (math.random() - 0.5) * size * 0.6, y + (math.random() - 0.5) * size * 0.6, f.r, f.g, f.b,
            4 + math.random() * 6, 0.4 + math.random() * 0.3, (math.random() - 0.5) * 8, -3 - math.random() * 8)
    end
end

function ns.FlyItem(icon, quality, count, target, delay, name, onArrive)
    local function Go()
        local f
        for _, x in ipairs(fliers) do
            if not x.active then f = x break end
        end
        f = f or NewFlier()
        local x0, y0 = CursorPos()
        local x2, y2
        if target then x2, y2 = CenterOf(target) end
        if not x2 then -- no bag button showing: the bottom-right corner
            x2, y2 = UIParent:GetWidth() - 40, 40
            target = nil
        end
        f.x0, f.y0, f.x2, f.y2, f.target = x0, y0, x2, y2, target
        local dx, dy = x2 - x0, y2 - y0
        local dist = math.sqrt(dx * dx + dy * dy)
        local nx, ny = 0, 0
        if dist > 0 then nx, ny = -dy / dist, dx / dist end
        local bend = math.min(160, dist * 0.25) * ((math.random() < 0.5) and -1 or 1)
        f.cx = (x0 + x2) / 2 + nx * bend
        f.cy = (y0 + y2) / 2 + ny * bend + 90 -- a toss up into the air first
        -- slow enough to see what it is
        f.dur = math.min(2.2, 1.3 + dist / 1600)
        f.r, f.g, f.b = QualityColor(quality)
        f.name:SetText(name or "")
        f.name:SetTextColor(f.r, f.g, f.b)
        f.border:SetColorTexture(f.r * 0.8, f.g * 0.8, f.b * 0.8, 1)
        f.halo:SetVertexColor(f.r, f.g, f.b)
        f.icon:SetTexture(icon)
        f.count:SetText((type(count) == "number" and count > 1) and count or "")
        f.t, f.travel, f.lx, f.ly = 0, 0, nil, nil
        f.onArrive = onArrive
        f.active = true
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x0, y0)
        f:Show()
        f:SetScript("OnUpdate", FlierStep)
    end
    if delay and delay > 0 then C_Timer.After(delay, Go) else Go() end
end

---------------------------------------------------------------------------
-- A swarm: ns.SendSwarm(target, color, count, onEach, onAll). Little motes
-- burst out of your cursor and each finds its own wild way into target:
-- a looping curve with two random bend points flung far out, a wobble that
-- calms as it closes in, its own speed and start. Each lands with a tiny
-- burst (onEach), the last one with onAll. Used for learning a recipe.
---------------------------------------------------------------------------
local imps = {}

local function NewImp()
    local m = CreateFrame("Frame", nil, layer)
    m:SetSize(16, 16)
    m:Hide()
    m.halo = m:CreateTexture(nil, "BACKGROUND")
    m.halo:SetTexture(RING)
    m.halo:SetBlendMode("ADD")
    m.halo:SetPoint("CENTER")
    m.core = m:CreateTexture(nil, "ARTWORK")
    m.core:SetTexture(STAR)
    m.core:SetBlendMode("ADD")
    m.core:SetPoint("CENTER")
    imps[#imps + 1] = m
    return m
end

local function ImpStep(m, elapsed)
    if m.wait > 0 then
        -- (shown but see-through while it waits: a hidden frame gets no updates)
        m.wait = m.wait - elapsed
        if m.wait > 0 then return end
        m:SetAlpha(1)
    end
    m.t = m.t + elapsed / m.dur
    if m.target then
        local tx, ty = CenterOf(m.target)
        if tx then m.x3, m.y3 = tx, ty end
    end
    if m.t >= 1 then
        m:SetScript("OnUpdate", nil)
        m:Hide()
        m.active = false
        for i = 1, 4 do
            local a = math.random() * 2 * math.pi
            local d = 8 + math.random() * 12
            Sparkle(m.x3, m.y3, m.r, m.g, m.b, 5 + math.random() * 5, 0.35 + math.random() * 0.2,
                math.cos(a) * d, math.sin(a) * d)
        end
        if m.onLand then pcall(m.onLand) end
        return
    end
    local u = Ease(m.t)
    local v = 1 - u
    -- a cubic curve through two far-flung bend points
    local x = v * v * v * m.x0 + 3 * v * v * u * m.c1x + 3 * v * u * u * m.c2x + u * u * u * m.x3
    local y = v * v * v * m.y0 + 3 * v * v * u * m.c1y + 3 * v * u * u * m.c2y + u * u * u * m.y3
    -- plus a wobble that settles as it arrives
    local w = math.sin(m.t * m.freq + m.phase) * m.amp * (1 - u)
    x, y = x + w * m.wx, y + w * m.wy
    m:ClearAllPoints()
    m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    local pulse = 1 + 0.3 * math.sin(m.t * 30 + m.phase)
    m.core:SetSize(14 * pulse, 14 * pulse)
    m.core:SetRotation(m.t * m.spin)
    m.halo:SetSize(20 * pulse, 20 * pulse)
    -- a fine trail
    local lx, ly = m.lx or x, m.ly or y
    m.travel = (m.travel or 0) + math.sqrt((x - lx) ^ 2 + (y - ly) ^ 2)
    m.lx, m.ly = x, y
    if m.travel >= 10 then
        m.travel = 0
        Sparkle(x, y, m.r, m.g, m.b, 3 + math.random() * 4, 0.3 + math.random() * 0.25,
            (math.random() - 0.5) * 6, -2 - math.random() * 6)
    end
end

function ns.SendSwarm(target, color, count, onEach, onAll, lift)
    local x3, y3 = CenterOf(target)
    if not x3 then
        if onAll then onAll() end
        return
    end
    local x0, y0 = CursorPos()
    local r, g, b = Bright(color or { 1, 0.85, 0.4 }, lift or 0.3)
    count = count or 7
    local left = count
    for i = 1, count do
        local m
        for _, x in ipairs(imps) do
            if not x.active then m = x break end
        end
        m = m or NewImp()
        m.x0, m.y0, m.x3, m.y3, m.target = x0, y0, x3, y3, target
        local dx, dy = x3 - x0, y3 - y0
        local dist = math.max(60, math.sqrt(dx * dx + dy * dy))
        -- two bend points flung out in random directions: loops and swoops
        local reach = 80 + dist * 0.45
        local a1, a2 = math.random() * 2 * math.pi, math.random() * 2 * math.pi
        m.c1x = x0 + math.cos(a1) * reach * (0.5 + math.random() * 0.6)
        m.c1y = y0 + math.sin(a1) * reach * (0.5 + math.random() * 0.6) + 40
        m.c2x = x3 + math.cos(a2) * reach * (0.4 + math.random() * 0.5)
        m.c2y = y3 + math.sin(a2) * reach * (0.4 + math.random() * 0.5) + 60
        -- the wobble, across its way
        m.wx, m.wy = -dy / dist, dx / dist
        m.amp = 10 + math.random() * 22
        m.freq = 10 + math.random() * 14
        m.phase = math.random() * 2 * math.pi
        m.spin = (math.random() < 0.5 and -1 or 1) * (6 + math.random() * 8)
        m.dur = 1.1 + math.random() * 0.9
        m.wait = (i - 1) * 0.05 + math.random() * 0.12
        m.r, m.g, m.b = r, g, b
        m.halo:SetVertexColor(r, g, b)
        m.core:SetVertexColor(1, 1, 1)
        m.t, m.travel, m.lx, m.ly = 0, 0, nil, nil
        m.onLand = function()
            left = left - 1
            if onEach then onEach(count - left) end
            if left == 0 and onAll then onAll() end
        end
        m.active = true
        m:ClearAllPoints()
        m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x0, y0)
        m:SetAlpha(0)
        m:Show()
        m:SetScript("OnUpdate", ImpStep)
    end
end

function ns.SendMote(target, color, onArrive, lift)
    local x2, y2 = CenterOf(target)
    if not x2 then
        if onArrive then onArrive() end
        return
    end
    local m
    for _, x in ipairs(motes) do
        if not x.active then m = x break end
    end
    m = m or NewMote()
    local x0, y0 = CursorPos()
    m.x0, m.y0, m.x2, m.y2, m.target = x0, y0, x2, y2, target
    -- the bend: off to one side of the straight line, and lifted a little
    local dx, dy = x2 - x0, y2 - y0
    local dist = math.sqrt(dx * dx + dy * dy)
    local side = (math.random() < 0.5) and -1 or 1
    local bend = math.min(220, dist * 0.35) * side
    local nx, ny = 0, 0
    if dist > 0 then nx, ny = -dy / dist, dx / dist end
    m.cx = (x0 + x2) / 2 + nx * bend
    m.cy = (y0 + y2) / 2 + ny * bend + 60
    m.dur = math.min(1.4, 0.7 + dist / 1800)
    m.r, m.g, m.b = Bright(color or { 1, 0.85, 0.4 }, lift or 0.55)
    m.halo:SetVertexColor(m.r, m.g, m.b)
    m.core:SetVertexColor(1, 1, 1)
    m.core2:SetVertexColor(m.r, m.g, m.b)
    m.t, m.travel, m.lx, m.ly = 0, 0, nil, nil
    m.onArrive = onArrive
    m.active = true
    m:ClearAllPoints()
    m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x0, y0)
    m:Show()
    m:SetScript("OnUpdate", Step)
end
