-- Blackthornes Butler -- Logic/Bags.lua
-- What the character carries, slot by slot, kept up to date without hitching.
--
-- The house rule on smooth play: bag events come in bursts (several per loot
-- or sale), so they only mark the bags stale, and one read follows 0.2 s
-- after the last of them, only while someone looks (the Butler window is up
-- or a vendor is open). The read goes over the slots a few dozen a frame,
-- and only a slot whose key (link, count, locked) changed is read further.
-- Bags.version moves only when something did, so the window redraws only
-- then.

local _, ns = ...

local Bags = ns.NewModule("Bags")

local Items = ns.Items

-- Slots read a frame. A full set of bags is about a hundred.
Bags.BUDGET = 40
-- How long after the last bag event the read waits.
Bags.SETTLE = 0.2

-- ["bag:slot"] = { bag, slot, itemID, link, count, quality, locked, noValue,
-- bound, icon, quest, key }
Bags.slots = {}
Bags.version = 0
Bags.stale = true

--- The bags a character carries: the backpack, the four bag slots and, on
--- clients that have one, the reagent bag.
function Bags.BagIDs()
    local ids = {}
    local last = tonumber(_G.NUM_BAG_SLOTS) or 4
    for bag = 0, last do ids[#ids + 1] = bag end
    local reagent = Bags.ReagentBag()
    if reagent and reagent > last then ids[#ids + 1] = reagent end
    return ids
end

--- The reagent bag's ID, or nil on a client without one. A number that is
--- also the first bank bag's (Era has no reagent bag, and its bank bags
--- start there) is the bank, never a carried bag.
function Bags.ReagentBag()
    local index = _G.Enum and _G.Enum.BagIndex
    if type(index) ~= "table" then return nil end
    local reagent = index.ReagentBag
    if type(reagent) ~= "number" then return nil end
    if index.BankBag_1 == reagent then return nil end
    return reagent
end

local function NumSlots(bag)
    local count = Items.Call({ "C_Container.GetContainerNumSlots", "GetContainerNumSlots" }, bag)
    return tonumber(count) or 0
end

--- One slot as the client has it now, or nil when it is empty.
function Bags.ReadSlot(bag, slot)
    local info = Items.Call({ "C_Container.GetContainerItemInfo" }, bag, slot)
    if type(info) ~= "table" then return nil end

    local ok, entry = pcall(function()
        if not info.itemID then return nil end
        local link = info.hyperlink
        local count = tonumber(info.stackCount) or 1
        local locked = info.isLocked and true or false
        return {
            bag = bag, slot = slot,
            itemID = info.itemID,
            link = link,
            count = count,
            quality = tonumber(info.quality),
            locked = locked,
            noValue = info.hasNoValue and true or false,
            bound = info.isBound and true or false,
            icon = info.iconFileID,
            key = ("%s:%d:%s"):format(tostring(link or info.itemID), count, locked and "l" or ""),
        }
    end)
    return ok and entry or nil
end

--- Whether the item in a slot is for a quest: an objective, or one that
--- starts a quest. Read only when the slot changed.
function Bags.ReadQuest(bag, slot, itemID)
    local info = Items.Call({ "C_Container.GetContainerItemQuestInfo" }, bag, slot)
    if type(info) == "table" then
        local ok, quest = pcall(function()
            if info.questID and not info.isActive then return "starts" end
            if info.isQuestItem or info.questID then return "item" end
        end)
        if ok and quest then return quest end
    end
    if Items.IsQuestClass(itemID) then return "item" end
    return nil
end

--- Does anyone want the bags read now?
function Bags:Wanted()
    if ns.UI and ns.UI:IsShown() then return true end
    if ns.BagWindow and ns.BagWindow:IsShown() then return true end
    if ns.Selling and ns.Selling:MerchantOpen() then return true end
    return false
end

--- The bags changed: read them once the burst is over, if anyone looks.
function Bags:Changed()
    self.stale = true
    if self.settling or not self:Wanted() then return end
    self.settling = true
    C_Timer.After(self.SETTLE, function()
        Bags.settling = false
        Bags:Scan()
    end)
end

--- Read the bags, a few dozen slots a frame. `done` runs when the read is
--- over (at once if one is under way, it runs when that one ends).
function Bags:Scan(done)
    if done then
        self.waiters = self.waiters or {}
        self.waiters[#self.waiters + 1] = done
    end
    if self.scanning then
        self.again = true
        return
    end
    self.scanning = true
    self.stale = false

    local places = {}
    for _, bag in ipairs(Bags.BagIDs()) do
        for slot = 1, NumSlots(bag) do
            places[#places + 1] = { bag, slot }
        end
    end

    local seen, changed, index = {}, false, 0

    local function Finish()
        for place in pairs(Bags.slots) do
            if not seen[place] then
                Bags.slots[place] = nil
                changed = true
            end
        end
        if changed then Bags.version = Bags.version + 1 end
        Bags.scanning = false

        if Bags.again then
            -- What this read found still needs a redraw, even when the
            -- read again finds nothing more.
            Bags.changedBefore = Bags.changedBefore or changed
            Bags.again = false
            return Bags:Scan()
        end
        changed = changed or Bags.changedBefore
        Bags.changedBefore = nil

        local waiters = Bags.waiters
        Bags.waiters = nil
        if changed and ns.Verdicts then ns.Verdicts:BagsChanged() end
        for _, fn in ipairs(waiters or {}) do fn() end
    end

    local function Step()
        local stop = math.min(#places, index + Bags.BUDGET)
        for i = index + 1, stop do
            local bag, slot = places[i][1], places[i][2]
            local place = bag .. ":" .. slot
            local entry = Bags.ReadSlot(bag, slot)
            local old = Bags.slots[place]
            if entry then
                seen[place] = true
                if not old or old.key ~= entry.key then
                    entry.quest = Bags.ReadQuest(bag, slot, entry.itemID)
                    Bags.slots[place] = entry
                    changed = true
                end
            end
        end
        index = stop
        if index < #places then
            C_Timer.After(0, Step)
        else
            Finish()
        end
    end

    Step()
end

--- How many of an item the bags hold, by the last read. Totted up once per
--- Bags.version, so asking for every item in a burst costs one pass.
function Bags:Carried(itemID)
    if self.carriedVersion ~= self.version then
        local totals = {}
        for _, entry in pairs(self.slots) do
            if entry.itemID then totals[entry.itemID] = (totals[entry.itemID] or 0) + (entry.count or 1) end
        end
        self.carried, self.carriedVersion = totals, self.version
    end
    return self.carried[itemID] or 0
end

--- Read the bags now if they changed since the last read, then run `done`.
function Bags:Fresh(done)
    if self.stale or self.scanning then
        self:Scan(done)
    elseif done then
        done()
    end
end

--- Does the slot still hold this item, unlocked? Asked again just before a
--- sale, since the bags can change between drawing a row and clicking it.
function Bags.Holds(bag, slot, itemID)
    local entry = Bags.ReadSlot(bag, slot)
    return entry ~= nil and entry.itemID == itemID and not entry.locked
end

function Bags:OnEnable()
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function() Bags:Changed() end)
    -- A new bag in a bag slot changes which slots there are.
    ns.RegisterEvent(self, "BAG_CONTAINER_UPDATE", function() Bags:Changed() end)
end
