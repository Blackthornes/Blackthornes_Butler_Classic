-- Blackthornes Butler -- UI/SwapWhenFull.lua
-- A popup beside the loot window when the bags are full and the loot is
-- worth more than what the bags hold (a player asked, the owner said build
-- it from a mockup, 2026-10-28; mockups/butler-bags-full-swap.png in the
-- project files).
--
-- What it offers: the loot item worth the most that has nowhere to go (no
-- free slot, no stack with room, no profession bag that takes it), against
-- the item the trash can would pick (Trash:Pick: only what Butler would
-- sell, auction or disenchant anyway, the stack worth the least). Only
-- when the loot is worth more, at Butler's own worth (Verdicts:Judge's
-- `unit` times the count) on both sides.
--
-- The one place Butler destroys an item (the owner, 2026-10-28: a player
-- who turned this on wants Butler to do it, with no step past saying yes).
-- The popup is the question and Swap is the yes: the click picks the cheap
-- item up and destroys it (DeleteCursorItem), only when the cursor then
-- holds that very item. Once its slot is empty and the loot window is still
-- open, Butler loots the item the popup named (LootSlot). Nothing else in
-- Butler ever deletes; the trash can still only picks up.
--
-- Off unless ticked: "Swap When Full:" on the General page (`swapWhenFull`,
-- account wide, never rename it). Butler's own frame on UIParent, only
-- placed beside LootFrame by its corner; no game frame is touched. Hidden
-- in combat. Loot events only mark it stale; one look follows a moment
-- later, and the bags are read only while a loot window is open with them
-- full.

local _, ns = ...
local L = ns.L

local Swap = ns.NewModule("SwapWhenFull")

local Theme = ns.Theme
local Widgets = ns.Widgets

Swap.SETTLE = 0.2
-- How long a swap waits for the cheap item to go before it lets go.
Swap.WAIT = 60

local WIDTH = 330
local PAD = 18
local ROW_HEIGHT = 40
local ICON = 30
-- GetLootSlotType's answer for an item (LOOT_SLOT_ITEM on every build).
local LOOT_ITEM = 1

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

local function Global(name, ...)
    local fn = rawget(_G, name)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2)
end

local function InCombat()
    return Global("InCombatLockdown") and true or false
end

local function CursorHolds()
    return Global("GetCursorInfo") ~= nil
end

local function Now()
    return tonumber(Global("GetTime")) or 0
end

function Swap:Enabled()
    return ns.db ~= nil and ns.db.swapWhenFull == true
end

--- Turn the popup on or off (Settings).
function Swap:SetEnabled(on)
    ns.db.swapWhenFull = on and true or false
    if on then self:Changed() else self:Hide() end
end

--------------------------------------------------------------------------------
-- What to offer
--------------------------------------------------------------------------------

--- Can the bags take some of this item without a free slot: a stack of it
--- with room, or a profession bag with a free slot that takes it.
function Swap.Fits(itemID, read)
    local max = ns.Trash.MaxStack(itemID)
    if max and max > 1 then
        for _, entry in pairs(ns.Bags.slots or {}) do
            if entry.itemID == itemID and (entry.count or 1) < max then return true end
        end
    end
    local family = tonumber(ns.Items.Call({ "C_Item.GetItemFamily", "GetItemFamily" }, itemID)) or 0
    if family ~= 0 and read then
        for _, bag in ipairs(read.special or {}) do
            if (bag.free or 0) > 0 then
                local _, bagFamily = ns.Items.Call({ "C_Container.GetContainerNumFreeSlots",
                    "GetContainerNumFreeSlots" }, bag.bag)
                bagFamily = tonumber(bagFamily) or 0
                if bit and bit.band and bit.band(family, bagFamily) ~= 0 then return true end
            end
        end
    end
    return false
end

--- What one of a loot item is worth to Butler, or nil while unknown.
function Swap.Worth(itemID, link, quality)
    local ok, _, _, unit = pcall(ns.Verdicts.Judge, ns.Verdicts,
        { itemID = itemID, link = link, count = 1, quality = quality })
    unit = ok and tonumber(unit) or nil
    if not unit then unit = tonumber(ns.Items:SellPrice(itemID)) end
    return unit
end

--- The loot worth the most that has nowhere to go: { slot, itemID, link,
--- name, icon, quality, count, worth }, or nil.
function Swap:BestLoot(read)
    local best
    local slots = tonumber(Global("GetNumLootItems")) or 0
    for slot = 1, slots do
        local kind = Global("GetLootSlotType", slot)
        local link = Global("GetLootSlotLink", slot)
        if (kind == nil or kind == LOOT_ITEM) and type(link) == "string" then
            local icon, name, count, _, quality, locked = Global("GetLootSlotInfo", slot)
            local itemID = tonumber(link:match("item:(%d+)"))
            count = tonumber(count) or 1
            if count < 1 then count = 1 end
            if itemID and not locked and not self.Fits(itemID, read) then
                local unit = self.Worth(itemID, link, tonumber(quality))
                if unit and unit > 0 then
                    local worth = unit * count
                    if not best or worth > best.worth then
                        best = { slot = slot, itemID = itemID, link = link, icon = icon, count = count,
                            name = type(name) == "string" and name or ns.Items.NameFromLink(link),
                            quality = tonumber(quality), worth = worth }
                    end
                end
            end
        end
    end
    return best
end

--- What the popup offers right now: loot, pick (Trash:Pick's), or nil.
function Swap:Offer(read)
    local bags = {}
    for _, entry in ipairs(read.bags) do bags[entry.bag] = true end
    local pick = ns.Trash:Pick(bags)
    if not pick then return nil end
    local loot = self:BestLoot(read)
    if not loot or loot.worth <= pick.worth then return nil end
    return loot, pick
end

--------------------------------------------------------------------------------
-- Looking
--------------------------------------------------------------------------------

function Swap:Changed()
    if self.settling then return end
    self.settling = true
    C_Timer.After(self.SETTLE, function()
        Swap.settling = false
        Swap:Refresh()
    end)
end

function Swap:Refresh()
    if self.pending then return self:FollowSwap() end
    if not self:Enabled() or InCombat() or not self.looting then return self:Hide() end
    if self.dismissed or CursorHolds() then return self:Hide() end
    local read = ns.FreeSpace and ns.FreeSpace.Read()
    if not read or read.free > 0 then return self:Hide() end
    -- Butler reads the bags only while one of its windows or a vendor is
    -- up, so what it last read may be old.
    if not ns.Bags:Wanted() then ns.Bags.stale = true end
    ns.Verdicts:ForgetIfOld()
    ns.Bags:Fresh(function()
        if not Swap.looting then return Swap:Hide() end
        local loot, pick = Swap:Offer(read)
        if loot then Swap:Show(loot, pick) else Swap:Hide() end
    end)
end

--------------------------------------------------------------------------------
-- The swap
--------------------------------------------------------------------------------

--- The Swap click: destroy the cheap item, after making sure both it and
--- the loot are still there, then wait for its slot to empty.
function Swap:Take()
    local loot, pick = self.loot, self.pick
    if not (loot and pick) or InCombat() then return false end
    if CursorHolds() then
        ns.Print(L["Your cursor is already holding something. Put it down first."])
        return false
    end
    local entry = pick.entry
    local now = ns.Bags.ReadSlot(entry.bag, entry.slot)
    if not now or now.key ~= entry.key or Global("GetLootSlotLink", loot.slot) ~= loot.link then
        self:Changed()
        return false
    end
    local names = { "C_Container.PickupContainerItem", "PickupContainerItem" }
    ns.Items.Call(names, entry.bag, entry.slot)
    -- Destroy only what is really on the cursor: the item the popup named.
    local kind, itemID = Global("GetCursorInfo")
    if kind ~= "item" or tonumber(itemID) ~= entry.itemID then
        if kind then ns.Items.Call(names, entry.bag, entry.slot) end
        self:Changed()
        return false
    end
    Global("DeleteCursorItem")
    self.pending = { bag = entry.bag, slot = entry.slot,
        lootSlot = loot.slot, lootLink = loot.link, at = Now() }
    self:Hide()
    return true
end

--- After Swap: loot the item once the cheap one's slot is empty, or let go
--- when the loot window closed or the wait ran out.
function Swap:FollowSwap()
    local pending = self.pending
    if not pending then return end
    if not self.looting or Now() - pending.at > self.WAIT then
        self.pending = nil
        return
    end
    if ns.Bags.ReadSlot(pending.bag, pending.slot) or CursorHolds() then return end
    self.pending = nil
    if Global("GetLootSlotLink", pending.lootSlot) == pending.lootLink then
        Global("LootSlot", pending.lootSlot)
    end
end

--------------------------------------------------------------------------------
-- The popup
--------------------------------------------------------------------------------

local function Row(parent, active)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row.fill = Theme.Fill(row, active and "glassActive" or "glass")
    if active then
        Theme.AccentStripe(row, 3)
    else
        Theme.Border(row, "loss", 0.7)
    end
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", 8, 0)
    row.icon = icon
    local worth = Theme.CreateLabel(row, "normal", "text", "RIGHT")
    worth:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.worth = worth
    local name = Theme.CreateLabel(row, "normal", "text")
    name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    name:SetPoint("RIGHT", worth, "LEFT", -8, 0)
    name:SetHeight(ROW_HEIGHT - 4)
    name:SetWordWrap(true)
    row.name = name
    return row
end

local function Heading(parent, text)
    local label = Theme.CreateLabel(parent, "small", "accent")
    label:SetText(text)
    return label
end

function Swap:Build()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "BlackthornesButlerSwapWhenFull", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    Theme.Fill(frame, "window")
    if ns.Titanforged then
        self.trim = ns.Titanforged:Dress(frame, {
            title = L["Bags Full"],
            close = function() Swap:NotNow() end,
        })
    else
        Theme.Border(frame, "borderLit")
    end

    local say = Theme.CreateLabel(frame, "normal", "text")
    say:SetPoint("TOPLEFT", PAD, -30)
    say:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    say:SetHeight(32)
    say:SetWordWrap(true)
    say:SetJustifyV("TOP")
    say:SetText(L["Your bags are full. This is worth more than what you have."])

    local newHead = Heading(frame, L["NEW LOOT"])
    newHead:SetPoint("TOPLEFT", say, "BOTTOMLEFT", 0, -8)
    local newRow = Row(frame, true)
    newRow:SetPoint("TOPLEFT", newHead, "BOTTOMLEFT", 0, -4)
    newRow:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    self.newRow = newRow

    local dropHead = Heading(frame, L["DROP TO MAKE ROOM"])
    dropHead:SetPoint("TOPLEFT", newRow, "BOTTOMLEFT", 0, -10)
    local dropRow = Row(frame, false)
    dropRow:SetPoint("TOPLEFT", dropHead, "BOTTOMLEFT", 0, -4)
    dropRow:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    self.dropRow = dropRow

    local note = Theme.CreateLabel(frame, "small", "muted")
    note:SetPoint("TOPLEFT", dropRow, "BOTTOMLEFT", 0, -10)
    note:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    note:SetHeight(30)
    note:SetWordWrap(true)
    note:SetJustifyV("TOP")
    self.note = note

    local swap = Widgets.CreateButton(frame, L["Swap"], function() Swap:Take() end,
        { width = 100, height = 24, primary = true })
    swap:SetPoint("BOTTOMRIGHT", -PAD, PAD - 4)
    self.swapButton = swap
    local later = Widgets.CreateButton(frame, L["Not Now"], function() Swap:NotNow() end,
        { width = 100, height = 24 })
    later:SetPoint("RIGHT", swap, "LEFT", -8, 0)
    self.laterButton = later

    frame:SetHeight(30 + 32 + 8 + 14 + 4 + ROW_HEIGHT + 10 + 14 + 4 + ROW_HEIGHT + 10 + 30 + 8 + 24 + PAD)
    self.frame = frame
    return frame
end

--- Beside the loot window, else a little above the middle.
function Swap:Place()
    local frame = self.frame
    frame:ClearAllPoints()
    local lootFrame = rawget(_G, "LootFrame")
    if type(lootFrame) == "table" and Ask(lootFrame, "IsShown") then
        frame:SetPoint("TOPLEFT", lootFrame, "TOPRIGHT", 12, -12)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
end

local function Fill(row, icon, name, itemID, quality, count, worth)
    row.icon:SetTexture(icon or 134400)
    name = ns.Items:ColorName(name or L.Format("item %s", tostring(itemID)), itemID, quality)
    if (count or 1) > 1 then name = L.Format("%s x%d", name, count) end
    row.name:SetText(name)
    row.worth:SetText(ns.Items.FormatMoney(worth))
end

function Swap:Show(loot, pick)
    self:Build()
    self.loot, self.pick = loot, pick
    Fill(self.newRow, loot.icon, loot.name, loot.itemID, loot.quality, loot.count, loot.worth)
    local entry = pick.entry
    local pickIcon = ns.Items.Call({ "C_Item.GetItemIconByID", "GetItemIcon" }, entry.itemID)
    Fill(self.dropRow, pickIcon, pick.row.name, entry.itemID, entry.quality, entry.count, pick.worth)
    self.note:SetText(L.Format("Swap drops %1$s and picks up %2$s.",
        pick.row.name or "?", loot.name or "?"))
    self:Place()
    self.frame:Show()
end

function Swap:Hide()
    if self.frame then self.frame:Hide() end
end

function Swap:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

--- Not Now and the close gem: put away until the next loot window.
function Swap:NotNow()
    self.dismissed = true
    self:Hide()
end

--- One line for /bbutler probe.
function Swap:ProbeText()
    local parts = { self:Enabled() and "on" or "off" }
    parts[#parts + 1] = self.looting and "loot window open" or "no loot window"
    parts[#parts + 1] = self:IsShown() and "popup showing" or "popup hidden"
    if self.pending then parts[#parts + 1] = "waiting for bag slot to empty" end
    return table.concat(parts, "; ")
end

function Swap:OnEnable()
    ns.RegisterEvent(self, "LOOT_OPENED", function()
        Swap.looting, Swap.dismissed = true, false
        Swap:Changed()
    end)
    ns.RegisterEvent(self, "LOOT_SLOT_CLEARED", function() Swap:Changed() end)
    ns.RegisterEvent(self, "LOOT_SLOT_CHANGED", function() Swap:Changed() end)
    ns.RegisterEvent(self, "LOOT_CLOSED", function()
        Swap.looting, Swap.pending = false, nil
        Swap:Hide()
    end)
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function() if Swap.looting then Swap:Changed() end end)
    ns.RegisterEvent(self, "CURSOR_CHANGED", function() if Swap.looting then Swap:Changed() end end)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() Swap:Hide() end)
end
