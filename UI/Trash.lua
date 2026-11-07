-- Blackthornes Butler -- UI/Trash.lua
-- A small gold can on the item worth the least, while the bags are full
-- (the owner asked 2026-10-13: "a small can icon for the lowest value
-- item", for a player who wants to throw something away).
--
-- What it picks: only what Butler would sell, auction or disenchant anyway,
-- with a price, in a bag that takes anything (a herb in the herb bag frees
-- no room). Never a quest item, gear an upgrade or an alt wants, goal or
-- craft material, pet food, anything under Keep, Mail, Bank, Wait or Look
-- at it, and never an item Butler has no price for. The stack worth the
-- least in all (Butler's own worth, the verdict's `unit`, times the stack)
-- gets the can. A trade good (cloth, herbs, ore and the like) counts as
-- `Trash.MATERIAL_LEAN` times its worth there, so when it is close the can
-- leans to junk and leaves the material (the owner, 2026-10-16).
--
-- Stacking first (the owner, 2026-10-16): when two short stacks of one item
-- fit in one slot, the can sits on the smaller one and says to stack them,
-- whatever the item is. A click joins them; nothing has to go.
--
-- A red glow lies round the picked slot too (the owner, 2026-10-19: "a red
-- glowing outline around the item in the bag"), so it is easy to spot. It
-- is its own frame beside the can, shown and hidden with it, and pulses
-- slowly; Media/Trash/PickGlow.tga comes from the same tool as the can.
--
-- Nothing is ever deleted by Butler. A click on the can picks the item up
-- and says so; the player drops it outside the bags and the game's own box
-- asks before anything is destroyed, or clicks its slot to put it back.
--
-- The can is Butler's own button, a child of the game's item
-- button (Equipment's way of finding them: retail's EnumerateValidItems
-- and GetBagID, else classic's ContainerFrame<n>Item<m>), or, while
-- Butler's Bags window stands in for the game's bags, of that window's
-- square for the slot (the game's are veiled then, so never used). Nothing is
-- written on a game frame: the bag windows' UpdateItems, OnShow and OnHide
-- are only hooked. It hides in combat and at a vendor, where Butler's Sell
-- button is the better way to make room.
--
-- Smooth play: bag events only mark it stale; one look follows 0.2 s after
-- the burst, only while a bag window is open, and the bags are read (and
-- judged) only once they are nearly full.

local _, ns = ...
local L = ns.L

local Trash = ns.NewModule("Trash")

-- Shows only at this many free slots or fewer: none, so the can goes the
-- moment a slot frees up.
Trash.FREE = 0
Trash.SETTLE = 0.2
Trash.ART = [[Interface\AddOns\Blackthornes_Butler\Media\Trash\TrashCan]]
-- The can's side, as a share of the item button's.
Trash.SHARE = 0.6
Trash.GLOW_ART = [[Interface\AddOns\Blackthornes_Butler\Media\Trash\PickGlow]]
-- How far the glow reaches past each edge of the slot, as a share of its
-- side (the art's slot sits a seventh of the way in from each side).
Trash.GLOW_REACH = 0.2

-- The verdicts an item can be thrown away from.
Trash.FROM = { sell = true, auction = true, disenchant = true }
-- A trade good counts as this many times its worth when picking, so junk
-- worth up to half as much again goes first.
Trash.MATERIAL_LEAN = 1.5
-- Enum.ItemClass.Tradegoods on every build.
local TRADE_GOODS = 7

local MAX_FRAMES = 13
local MAX_BUTTONS = 36

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Ask(object, method, ...)
    local fn = Field(object, method)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
    return nil
end

local function InCombat()
    local fn = rawget(_G, "InCombatLockdown")
    return type(fn) == "function" and fn() and true or false
end

function Trash:Enabled()
    return ns.db ~= nil and ns.db.trashCan ~= false
end

--- Turn the can on or off (Settings and /bbutler trash).
function Trash:SetEnabled(on)
    ns.db.trashCan = on and true or false
    if on then self:Changed() else self:Hide() end
end

--------------------------------------------------------------------------------
-- The game's bag windows
--------------------------------------------------------------------------------

--- The bag windows this client has, open or not.
function Trash:Frames()
    local frames = {}
    local combined = rawget(_G, "ContainerFrameCombinedBags")
    if type(combined) == "table" then frames[#frames + 1] = combined end
    local count = tonumber(rawget(_G, "NUM_CONTAINER_FRAMES")) or MAX_FRAMES
    for i = 1, count do
        local frame = rawget(_G, "ContainerFrame" .. i)
        if type(frame) == "table" then frames[#frames + 1] = frame end
    end
    return frames
end

function Trash:ShownFrames()
    local shown = {}
    for _, frame in ipairs(self:Frames()) do
        if Ask(frame, "IsShown") then shown[#shown + 1] = frame end
    end
    return shown
end

--- The item buttons in one bag window.
function Trash:Buttons(frame)
    local buttons = {}
    local enumerate = Field(frame, "EnumerateValidItems")
    if type(enumerate) == "function" then
        local ok = pcall(function()
            for _, button in enumerate(frame) do buttons[#buttons + 1] = button end
        end)
        if ok and #buttons > 0 then return buttons end
        buttons = {}
    end
    local name = Ask(frame, "GetName")
    if type(name) == "string" then
        for i = 1, MAX_BUTTONS do
            local button = rawget(_G, name .. "Item" .. i)
            if type(button) ~= "table" then break end
            buttons[#buttons + 1] = button
        end
    end
    return buttons
end

-- Stands in for the list of bag windows while Butler's Bags covers the
-- game's: the can goes on its squares.
Trash.BUTLER_BAGS = "butler bags"

--- The shown item button for a bag slot, or nil.
function Trash:FindButton(frames, bag, slot)
    if frames == self.BUTLER_BAGS then
        return ns.BagWindow and ns.BagWindow:ButtonFor(bag, slot) or nil
    end
    for _, frame in ipairs(frames) do
        for _, button in ipairs(self:Buttons(frame)) do
            local buttonBag = Ask(button, "GetBagID")
            if type(buttonBag) ~= "number" then buttonBag = Ask(Ask(button, "GetParent") or frame, "GetID") end
            if buttonBag == bag and Ask(button, "GetID") == slot and Ask(button, "IsVisible") then
                return button
            end
        end
    end
    return nil
end

--- Hear the bag windows open, close and redraw: hooks only, once each.
function Trash:InstallHooks()
    self.hooked = self.hooked or {}
    local hook = rawget(_G, "hooksecurefunc")
    for _, frame in ipairs(self:Frames()) do
        if not self.hooked[frame] then
            self.hooked[frame] = true
            if type(hook) == "function" and type(Field(frame, "UpdateItems")) == "function" then
                pcall(hook, frame, "UpdateItems", function() Trash:Changed() end)
            end
            if type(Field(frame, "HookScript")) == "function" then
                pcall(frame.HookScript, frame, "OnShow", function() Trash:Changed() end)
                pcall(frame.HookScript, frame, "OnHide", function() Trash:Changed() end)
            end
        end
    end
    if type(hook) == "function" and not self.hookedUpdate and type(rawget(_G, "ContainerFrame_Update")) == "function" then
        self.hookedUpdate = pcall(hook, "ContainerFrame_Update", function() Trash:Changed() end)
    end
end

--------------------------------------------------------------------------------
-- What to throw away
--------------------------------------------------------------------------------

--- How many of an item fit in one slot, or nil while the client does not say.
function Trash.MaxStack(itemID)
    local name, _, _, _, _, _, _, max = ns.Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, itemID)
    if not name then return nil end
    return tonumber(max)
end

--- Two short stacks of one item that fit in one slot: { merge = true,
--- entry, to, max }, or nil. The smaller stack (`entry`, in a bag that
--- takes anything) goes onto the fullest stack that still has room for it.
function Trash:Merge(bags)
    local byItem = {}
    for _, entry in pairs(ns.Bags.slots) do
        if entry.itemID and not entry.locked then
            local list = byItem[entry.itemID]
            if not list then
                list = {}
                byItem[entry.itemID] = list
            end
            list[#list + 1] = entry
        end
    end
    local function Before(a, b)
        if (a.count or 1) ~= (b.count or 1) then return (a.count or 1) < (b.count or 1) end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end
    local best
    for itemID, list in pairs(byItem) do
        local max = #list > 1 and self.MaxStack(itemID)
        if max and max > 1 then
            table.sort(list, Before)
            for _, from in ipairs(list) do
                if not bags or bags[from.bag] then
                    local to
                    for i = #list, 1, -1 do
                        local other = list[i]
                        if other ~= from and (from.count or 1) + (other.count or 1) <= max then
                            to = other
                            break
                        end
                    end
                    if to then
                        if not best or Before(from, best.entry) then
                            best = { merge = true, entry = from, to = to, max = max }
                        end
                        break
                    end
                end
            end
        end
    end
    return best
end

--- The stack worth the least that may be thrown away: { entry, row, worth,
--- unit }, or nil. `bags` is the set of bag IDs that take anything. A trade
--- good is weighed at MATERIAL_LEAN times its worth. `from` is the set of
--- verdicts to look in, Trash.FROM unless given (Swap When Full's quest loot).
function Trash:Pick(bags, from)
    from = from or self.FROM
    local best
    for _, group in ipairs(ns.Verdicts:Groups()) do
        if from[group.verdict] then
            for _, row in ipairs(group.rows) do
                local unit = tonumber(row.unit)
                if unit and unit > 0 then
                    for _, entry in ipairs(row.slots) do
                        if not entry.locked and not entry.quest and (not bags or bags[entry.bag]) then
                            local worth = unit * (entry.count or 1)
                            local weight = worth
                            if ns.Items.ClassID(entry.itemID) == TRADE_GOODS then
                                weight = worth * self.MATERIAL_LEAN
                            end
                            if not best or weight < best.weight
                                or (weight == best.weight and (entry.bag < best.entry.bag
                                    or (entry.bag == best.entry.bag and entry.slot < best.entry.slot))) then
                                best = { entry = entry, row = row, worth = worth, unit = unit, weight = weight }
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- The can
--------------------------------------------------------------------------------

function Trash:Can()
    if self.can then return self.can end
    local can = CreateFrame("Button", "BlackthornesButlerTrashCan", UIParent)
    can:SetSize(16, 16)
    can:Hide()
    local icon = can:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints(can)
    icon:SetTexture(self.ART)
    can.icon = icon
    -- A slow pulse (size and glow) so it is easy to spot among the icons.
    pcall(function()
        local group = can:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        local fade = group:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.5)
        fade:SetDuration(0.6)
        fade:SetSmoothing("IN_OUT")
        local grow = group:CreateAnimation("Scale")
        grow:SetScaleFrom(1, 1)
        grow:SetScaleTo(1.3, 1.3)
        grow:SetDuration(0.6)
        grow:SetSmoothing("IN_OUT")
        grow:SetOrigin("CENTER", 0, 0)
        can.pulse = group
    end)
    can:SetScript("OnShow", function(owner)
        if owner.pulse then pcall(owner.pulse.Play, owner.pulse) end
    end)
    can:SetScript("OnHide", function(owner)
        if owner.pulse then pcall(owner.pulse.Stop, owner.pulse) end
    end)
    can:SetScript("OnClick", function() Trash:Take() end)
    can:SetScript("OnEnter", function(owner) Trash:ShowTooltip(owner) end)
    can:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.can = can
    return can
end

--- The red glow round the picked slot: our own frame, no mouse, so a click
--- still reaches the item button under it.
function Trash:Glow()
    if self.glow then return self.glow end
    local glow = CreateFrame("Frame", nil, UIParent)
    glow:Hide()
    pcall(glow.EnableMouse, glow, false)
    local texture = glow:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(glow)
    texture:SetTexture(self.GLOW_ART)
    glow.texture = texture
    pcall(function()
        local group = glow:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        local fade = group:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.45)
        fade:SetDuration(0.8)
        fade:SetSmoothing("IN_OUT")
        glow.pulse = group
    end)
    glow:SetScript("OnShow", function(owner)
        if owner.pulse then pcall(owner.pulse.Play, owner.pulse) end
    end)
    glow:SetScript("OnHide", function(owner)
        if owner.pulse then pcall(owner.pulse.Stop, owner.pulse) end
    end)
    self.glow = glow
    return glow
end

function Trash:Hide()
    self.pick = nil
    if self.glow then
        self.glow:Hide()
        if Ask(self.glow, "GetParent") ~= UIParent then pcall(self.glow.SetParent, self.glow, UIParent) end
    end
    if self.can then
        self.can:Hide()
        -- Back to UIParent, so a button the game gives to another slot
        -- never carries it away.
        if Ask(self.can, "GetParent") ~= UIParent then pcall(self.can.SetParent, self.can, UIParent) end
    end
end

--- Lay the can on the picked item's button.
function Trash:Place(frames, bags)
    self.waiting = false
    if self.stale then return self:Changed() end
    local pick = self:Merge(bags) or self:Pick(bags)
    local button = pick and self:FindButton(frames, pick.entry.bag, pick.entry.slot)
    if not button then return self:Hide() end

    local can = self:Can()
    self.pick = pick
    -- A child of the item button it sits on, so it is drawn with that
    -- button, at its scale and strata, over it, and goes when it does. Our
    -- own frame; nothing is written on the game's.
    if Ask(can, "GetParent") ~= button then pcall(can.SetParent, can, button) end
    local size = (tonumber(Ask(button, "GetWidth")) or 37) * self.SHARE
    can:SetSize(size, size)
    can:SetFrameLevel((Ask(button, "GetFrameLevel") or 1) + 10)
    can:ClearAllPoints()
    can:SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 1)
    can:Show()

    local glow = self:Glow()
    if Ask(glow, "GetParent") ~= button then pcall(glow.SetParent, glow, button) end
    local reach = (tonumber(Ask(button, "GetWidth")) or 37) * self.GLOW_REACH
    glow:SetFrameLevel((Ask(button, "GetFrameLevel") or 1) + 9)
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", button, "TOPLEFT", -reach, reach)
    glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", reach, -reach)
    glow:Show()
end

--- Look again once the burst is over, if a bag window is open.
function Trash:Changed()
    self.stale = true
    if self.settling or self.waiting then return end
    if not self:Enabled() or InCombat() or self.atVendor then return self:Hide() end
    self.settling = true
    C_Timer.After(self.SETTLE, function()
        Trash.settling = false
        Trash:Refresh()
    end)
end

function Trash:Refresh()
    self.stale = false
    if not self:Enabled() or InCombat() or self.atVendor then return self:Hide() end
    -- While the cursor holds something (the item the can picked up, say),
    -- the can waits rather than jump to the next item.
    local cursor = rawget(_G, "GetCursorInfo")
    if type(cursor) == "function" and cursor() then return self:Hide() end
    local frames
    if ns.BagWindow and ns.BagWindow:Covering() then
        if not ns.BagWindow:ShowsBags() then return self:Hide() end
        frames = self.BUTLER_BAGS
    else
        frames = self:ShownFrames()
        if #frames == 0 then return self:Hide() end
    end
    local read = ns.FreeSpace and ns.FreeSpace.Read()
    if not read or read.free > self.FREE then return self:Hide() end

    local bags = {}
    for _, entry in ipairs(read.bags) do bags[entry.bag] = true end
    self.free = read.free
    ns.Verdicts:ForgetIfOld()
    self.waiting = true
    ns.Bags:Fresh(function() Trash:Place(frames, bags) end)
end

function Trash:ShowTooltip(owner)
    local pick = self.pick
    if not (pick and GameTooltip) then return end
    pcall(function()
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        if pick.merge then
            local entry, to = pick.entry, pick.to
            local name = ns.Items.NameFromLink(entry.link) or L.Format("item %s", tostring(entry.itemID))
            GameTooltip:AddLine(L["Stack these to make room"], 1, 0.82, 0)
            name = ns.Items:ColorName(name, entry.itemID, entry.quality)
            GameTooltip:AddLine(L.Format("%s x%d", name, entry.count or 1), 1, 1, 1)
            GameTooltip:AddLine(L.Format("It fits on your other stack of %d.", to.count or 1), 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Click to stack them. Nothing is thrown away."], 0.2, 1, 0.2, true)
            GameTooltip:Show()
            return
        end
        GameTooltip:AddLine(L["Throw away to make room"], 1, 0.82, 0)
        local row, count = pick.row, pick.entry.count or 1
        local name = row.name or L.Format("item %s", tostring(pick.entry.itemID))
        name = ns.Items:ColorName(name, pick.entry.itemID, pick.entry.quality)
        if count > 1 then name = L.Format("%s x%d", name, count) end
        GameTooltip:AddLine(name, 1, 1, 1)
        GameTooltip:AddLine(L.Format("Worth %s in all, the least in your bags",
            ns.Items.FormatMoney(pick.worth)), 1, 1, 1, true)
        if type(row.reason) == "string" and row.reason ~= "" then
            GameTooltip:AddLine(row.reason, 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to pick it up. Nothing is thrown away until you say so."],
            0.2, 1, 0.2, true)
        GameTooltip:Show()
    end)
end

--- The click: pick the item up, after making sure it is still there.
--- Butler never deletes it; the game's own box asks when it is dropped.
function Trash:Take()
    local pick = self.pick
    if not pick or InCombat() then return false end
    local entry = pick.entry
    local now = ns.Bags.ReadSlot(entry.bag, entry.slot)
    if not now or now.key ~= entry.key then
        self:Changed()
        return false
    end
    if pick.merge then
        local there = ns.Bags.ReadSlot(pick.to.bag, pick.to.slot)
        if not there or there.key ~= pick.to.key then
            self:Changed()
            return false
        end
    end
    local cursor = rawget(_G, "GetCursorInfo")
    if type(cursor) == "function" and cursor() then
        ns.Print(L["Your cursor is already holding something. Put it down first."])
        return false
    end
    if pick.merge then
        -- Pick the smaller stack up and drop it on the other: the game joins them.
        local names = { "C_Container.PickupContainerItem", "PickupContainerItem" }
        ns.Items.Call(names, entry.bag, entry.slot)
        ns.Items.Call(names, pick.to.bag, pick.to.slot)
        if GameTooltip then GameTooltip:Hide() end
        return true
    end
    ns.Items.Call({ "C_Container.PickupContainerItem", "PickupContainerItem" }, entry.bag, entry.slot)
    if GameTooltip then GameTooltip:Hide() end
    ns.Print(L.Format("%s is on your cursor. Drop it outside your bags and the game will ask before it is destroyed, or click its bag slot to put it back.",
        pick.row.link or pick.row.name or "?"))
    return true
end

--- Where the can sits against its button, for the probe: the button's
--- window, its strata and level, and the can's own size, scale, alpha and
--- whether the art file gave it a texture.
function Trash:ButtonText(button)
    local parent = Ask(button, "GetParent")
    local parts = { ("button in %s (%s)"):format(tostring(Ask(parent, "GetName") or "?"),
        Ask(parent, "IsVisible") and "visible" or "not visible") }
    parts[#parts + 1] = ("button strata %s level %s"):format(tostring(Ask(button, "GetFrameStrata")),
        tostring(Ask(button, "GetFrameLevel")))
    local can = self.can
    if can then
        parts[#parts + 1] = ("can in %s, %s, strata %s level %s size %s scale %s alpha %s %s"):format(
            tostring(Ask(Ask(can, "GetParent"), "GetName") or "?"),
            Ask(can, "IsVisible") and "visible" or "not visible",
            tostring(Ask(can, "GetFrameStrata")), tostring(Ask(can, "GetFrameLevel")),
            tostring(Ask(can, "GetWidth")), tostring(Ask(can, "GetScale")),
            tostring(Ask(can, "GetAlpha")), can.icon and Ask(can.icon, "GetTexture") and "art set" or "no art")
        local left, bottom = Ask(can, "GetLeft"), Ask(can, "GetBottom")
        parts[#parts + 1] = ("can at %s,%s; button at %s,%s"):format(tostring(left), tostring(bottom),
            tostring(Ask(button, "GetLeft")), tostring(Ask(button, "GetBottom")))
    else
        parts[#parts + 1] = "no can made yet"
    end
    return table.concat(parts, "; ")
end

--- One line for /bbutler probe: why the can is or is not up right now.
function Trash:ProbeText()
    local frames = #self:Frames()
    local shown = #self:ShownFrames()
    local state = self.can and self.can:IsShown() and "showing" or "hidden"
    local parts = { ("%d bag windows, %d open, can %s"):format(frames, shown, state) }
    if not self:Enabled() then parts[#parts + 1] = "turned off" end
    local read = ns.FreeSpace and ns.FreeSpace.Read()
    if read then
        parts[#parts + 1] = ("%d free of %d in the bags that take anything"):format(read.free, read.total)
        local bags = {}
        for _, entry in ipairs(read.bags) do bags[entry.bag] = true end
        local merge = self:Merge(bags)
        if merge then
            parts[#parts + 1] = ("would stack bag %d slot %d onto bag %d slot %d"):format(merge.entry.bag,
                merge.entry.slot, merge.to.bag, merge.to.slot)
        end
        local pick = self:Pick(bags)
        if pick then
            parts[#parts + 1] = ("would pick bag %d slot %d, %s"):format(pick.entry.bag, pick.entry.slot,
                tostring(pick.row.name or pick.row.itemID or "?"))
            local covering = ns.BagWindow and ns.BagWindow:Covering()
            local found = self:FindButton(covering and self.BUTLER_BAGS or self:ShownFrames(),
                pick.entry.bag, pick.entry.slot)
            parts[#parts + 1] = found and "its button was found" or "its button was NOT found"
            if found then parts[#parts + 1] = self:ButtonText(found) end
        else
            local counts = {}
            for _, group in ipairs(ns.Verdicts:Groups()) do
                counts[#counts + 1] = ("%s %d"):format(tostring(group.verdict), #group.rows)
            end
            parts[#parts + 1] = "nothing to pick (" .. table.concat(counts, ", ") .. ")"
        end
    else
        parts[#parts + 1] = "the client gave no bag count"
    end
    return table.concat(parts, "; ")
end

function Trash:OnEnable()
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function() Trash:Changed() end)
    ns.RegisterEvent(self, "BAG_CONTAINER_UPDATE", function() Trash:Changed() end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        Trash:InstallHooks()
        Trash:Changed()
    end)
    ns.RegisterEvent(self, "CURSOR_CHANGED", function() Trash:Changed() end)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() Trash:Hide() end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function() Trash:Changed() end)
    ns.RegisterEvent(self, "MERCHANT_SHOW", function()
        Trash.atVendor = true
        Trash:Hide()
    end)
    ns.RegisterEvent(self, "MERCHANT_CLOSED", function()
        Trash.atVendor = false
        Trash:Changed()
    end)
end

ns.RegisterCommand("trash", L["show or hide the trash can on the item worth the least when your bags are full"], function()
    Trash:SetEnabled(not Trash:Enabled())
    ns.Print(Trash:Enabled() and L["the trash can shows on the item worth the least when your bags are full."]
        or L["the trash can no longer shows when your bags are full."])
end)
