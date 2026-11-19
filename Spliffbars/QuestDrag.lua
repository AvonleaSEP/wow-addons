-- Spliffbars: Shift-drag a quest item out of Questie's tracker onto your
-- action bars.
--
-- Questie's quest-item buttons (Questie_ItemButton1, 2 ...) are secure
-- buttons that use the item as soon as you press the mouse, so a plain drag
-- would use the item as well. Holding Shift is the game's own "pick it up"
-- (as on locked action bars): with Shift held, pressing the button does
-- nothing, and dragging puts the item on your cursor to drop on a bar.
-- A plain click still uses the item.
--
-- Questie's own files are left alone (an update would undo any change);
-- its buttons are found by name once its tracker has made them. On/off in
-- the Spliffbars options (Quest Items).

local _, ns = ...

local MAX_BUTTONS = 40
local hooked = {}

local pickup = (C_Item and C_Item.PickupItem) or PickupItem

-- Shift: no action (the secure button has no "none" action, so pressing
-- does nothing), leaving the drag free. Attributes can only change out of
-- combat.
local function Apply(btn)
    if InCombatLockdown() then return false end
    btn:SetAttribute("shift-type1", ns.Opt("questDrag") and "none" or nil)
    return true
end

local function Hook(btn)
    if hooked[btn] then return end
    hooked[btn] = true
    btn:RegisterForDrag("LeftButton")
    btn:HookScript("OnDragStart", function(self)
        if not ns.Opt("questDrag") or not IsShiftKeyDown() then return end
        local id = self.itemId -- set by Questie for the item it's showing
        if type(id) == "number" and pickup then pcall(pickup, id) end
    end)
    Apply(btn)
end

-- find Questie's buttons (made a little after login, once its tracker is up)
local function HookAll()
    if InCombatLockdown() then return false end
    local any = false
    for i = 1, MAX_BUTTONS do
        local btn = _G["Questie_ItemButton" .. i]
        if btn then
            any = true
            Hook(btn)
        end
    end
    return any
end

-- the options panel calls this after the switch changes
function ns.ApplyQuestDrag()
    if not HookAll() then return end
    for btn in pairs(hooked) do Apply(btn) end
end

local tries = 0
local function TryHook()
    tries = tries + 1
    if not HookAll() and tries < 30 then C_Timer.After(2, TryHook) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        tries = 0
        C_Timer.After(2, TryHook)
    else
        ns.ApplyQuestDrag() -- anything that had to wait out a fight
    end
end)
