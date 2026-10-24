-- Blackthornes Butler -- Logic/BagSort.lua
-- Butler's own bag sort, for a client with no bag sort of its own (Era).
-- The owner said build it, 2026-10-24, after the Bags window's Sort button
-- never showed on Era.
--
-- One move at a time: pick a stack up and put it down, then wait for both
-- slots to come unlocked before the next, since the server answers each
-- move. First the loose stacks of one item are put together, then every
-- item goes to its place. The plan is worked out again before each move
-- from the bags as they are, so a loot or a click mid-sort is no harm.
--
-- Bags that take only some things (quiver, ammo pouch, herb bag) are sorted
-- on their own, with what is already in them. A locked slot is waited for;
-- a fight, something on the cursor, or a move that never settles stops it.
-- Nothing is dropped, sold or deleted: an item only changes slots.

local _, ns = ...

local BagSort = ns.NewModule("BagSort")

local Items = ns.Items

-- Seconds between looks while a move settles.
BagSort.GAP = 0.05
-- Looks before a move that never settles stops the sort (about 3 s).
BagSort.WAIT_TRIES = 60
-- The most moves one click makes; a full set of bags needs far fewer.
BagSort.MOST_MOVES = 400

-- Hearthstone first, as players keep it.
BagSort.FIRST = { [6948] = true }

-- Item classes in the order they are laid out; anything else after them.
BagSort.CLASS_ORDER = {
    12, -- quest
    0,  -- food, drink, potions
    2,  -- weapons
    4,  -- armor
    6,  -- ammo
    1,  -- bags
    11, -- quivers
    7,  -- trade goods
    5,  -- reagents
    9,  -- recipes
    3,  -- gems
    13, -- keys
    15, -- the rest
}
local CLASS_RANK = {}
for rank, class in ipairs(BagSort.CLASS_ORDER) do CLASS_RANK[class] = rank end

local function Has(path)
    return Items.Resolve and Items.Resolve(path) ~= nil
end

local function InCombat()
    local fn = rawget(_G, "InCombatLockdown")
    if type(fn) ~= "function" then return false end
    local ok, fighting = pcall(fn)
    return ok and fighting and true or false
end

local function CursorBusy()
    if Items.Call({ "CursorHasItem" }) then return true end
    return Items.Call({ "GetCursorInfo" }) ~= nil
end

local function Pickup(bag, slot)
    Items.Call({ "C_Container.PickupContainerItem", "PickupContainerItem" }, bag, slot)
end

--- Can Butler sort here: the client picks up bag items.
function BagSort.CanSort()
    return Has("C_Container.PickupContainerItem") or Has("PickupContainerItem")
end

function BagSort:Running()
    return self.running and true or false
end

--------------------------------------------------------------------------------
-- Reading the bags
--------------------------------------------------------------------------------

local function NumSlots(bag)
    return tonumber(Items.Call({ "C_Container.GetContainerNumSlots", "GetContainerNumSlots" }, bag)) or 0
end

local function Family(bag)
    if bag == 0 then return 0 end
    local _, family = Items.Call({ "C_Container.GetContainerNumFreeSlots", "GetContainerNumFreeSlots" }, bag)
    return tonumber(family) or 0
end

--- The bags as groups that are sorted on their own: every bag that takes
--- anything together, then each bag that takes only some things. Each is
--- { slots = { { bag, slot, entry } } } in bag and slot order.
function BagSort.Read()
    local general, special = { slots = {} }, {}
    local last = tonumber(_G.NUM_BAG_SLOTS) or 4
    for _, bag in ipairs(ns.Bags.BagIDs()) do
        if bag <= last then
            local group = general
            if Family(bag) ~= 0 then
                group = { slots = {} }
                special[#special + 1] = group
            end
            for slot = 1, NumSlots(bag) do
                group.slots[#group.slots + 1] = { bag = bag, slot = slot, entry = ns.Bags.ReadSlot(bag, slot) }
            end
        end
    end
    local groups = { general }
    for _, group in ipairs(special) do groups[#groups + 1] = group end
    return groups
end

-- Item facts kept for the sort: name, class, most in a stack.
local facts = {}

local function Facts(itemID)
    local known = facts[itemID]
    if known then return known end
    local name, _, _, _, _, _, _, stack = Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, itemID)
    local _, _, _, _, _, class = Items.Call({ "C_Item.GetItemInfoInstant", "GetItemInfoInstant" }, itemID)
    known = { name = name, class = tonumber(class), stack = tonumber(stack) }
    -- Only keep it once the client has the item; until then ask again.
    if name then facts[itemID] = known end
    return known
end

--- What an item is matched by: its link, so a random suffix or an enchant
--- keeps apart, else its ID.
local function Same(a, b)
    if not a or not b then return a == b end
    return (a.link or a.itemID) == (b.link or b.itemID)
end

--- Does `a` go before `b`?
function BagSort.Before(a, b)
    local fa, fb = BagSort.FIRST[a.itemID] and 0 or 1, BagSort.FIRST[b.itemID] and 0 or 1
    if fa ~= fb then return fa < fb end
    -- Greys last, whatever they are.
    local ga, gb = (a.quality == 0) and 1 or 0, (b.quality == 0) and 1 or 0
    if ga ~= gb then return ga < gb end
    local ia, ib = Facts(a.itemID), Facts(b.itemID)
    local ca = CLASS_RANK[ia.class or -1] or (#BagSort.CLASS_ORDER + 1)
    local cb = CLASS_RANK[ib.class or -1] or (#BagSort.CLASS_ORDER + 1)
    if ca ~= cb then return ca < cb end
    local qa, qb = a.quality or 1, b.quality or 1
    if qa ~= qb then return qa > qb end
    local na, nb = ia.name or "", ib.name or ""
    if na ~= nb then return na < nb end
    if a.itemID ~= b.itemID then return a.itemID < b.itemID end
    local la, lb = tostring(a.link or ""), tostring(b.link or "")
    if la ~= lb then return la < lb end
    return (a.count or 1) > (b.count or 1)
end

--------------------------------------------------------------------------------
-- Planning one move
--------------------------------------------------------------------------------

--- Two loose stacks of one item that fit together: the last goes onto the
--- first. Returns from, to (slot records), or nil.
function BagSort.NextStack(group)
    local partial = {}
    for _, place in ipairs(group.slots) do
        local entry = place.entry
        if entry and not entry.locked then
            local stack = Facts(entry.itemID).stack
            if stack and stack > 1 and entry.count < stack then
                local key = entry.link or entry.itemID
                partial[key] = partial[key] or {}
                table.insert(partial[key], place)
            end
        end
    end
    for _, list in pairs(partial) do
        if #list > 1 then return list[#list], list[1] end
    end
    return nil
end

--- The first slot whose item is not the one that belongs there, and where
--- that one is now. Returns from, to, or nil when the group is in order.
function BagSort.NextPlace(group)
    local entries = {}
    for _, place in ipairs(group.slots) do
        if place.entry then entries[#entries + 1] = place.entry end
    end
    table.sort(entries, BagSort.Before)
    for i, want in ipairs(entries) do
        local place = group.slots[i]
        if not Same(place.entry, want) then
            -- The first copy of what belongs here, past this slot.
            for j = i + 1, #group.slots do
                local other = group.slots[j]
                if Same(other.entry, want) then
                    if other.entry.locked or (place.entry and place.entry.locked) then return nil, nil, true end
                    return other, place
                end
            end
        end
    end
    return nil
end

--- The next move over every group: stacks first, then places. A third
--- return of true means something is locked and the sort should wait.
function BagSort.NextMove(groups)
    for _, group in ipairs(groups) do
        local from, to = BagSort.NextStack(group)
        if from then return from, to end
    end
    local waiting = false
    for _, group in ipairs(groups) do
        local from, to, locked = BagSort.NextPlace(group)
        if from then return from, to end
        waiting = waiting or locked
    end
    return nil, nil, waiting
end

--------------------------------------------------------------------------------
-- Running
--------------------------------------------------------------------------------

local function Locked(bag, slot)
    local entry = ns.Bags.ReadSlot(bag, slot)
    return entry and entry.locked
end

--- Start a sort. False when it can't: a fight, something on the cursor, a
--- sort already going, or a client that can't pick items up.
function BagSort:Start()
    if self.running or not BagSort.CanSort() then return false end
    if InCombat() or CursorBusy() then return false end
    self.running = true
    self.moves = 0
    self.waits = 0
    self.last = nil
    self:Step()
    return true
end

function BagSort:Stop()
    if self.running and CursorBusy() then Items.Call({ "ClearCursor" }) end
    self.running = false
    self.last = nil
    if ns.BagWindow and ns.BagWindow.UpdateFoot and ns.BagWindow.frame then
        pcall(ns.BagWindow.UpdateFoot, ns.BagWindow)
    end
end

function BagSort:Later()
    C_Timer.After(self.GAP, function() BagSort:Step() end)
end

--- One look: wait while the last move settles, else make the next.
function BagSort:Step()
    if not self.running then return end
    if InCombat() then return self:Stop() end
    local last = self.last
    if last and (Locked(last[1], last[2]) or Locked(last[3], last[4])) then
        self.waits = self.waits + 1
        if self.waits > self.WAIT_TRIES then return self:Stop() end
        return self:Later()
    end
    self.last = nil
    if CursorBusy() or self.moves >= self.MOST_MOVES then return self:Stop() end

    local from, to, waiting = BagSort.NextMove(BagSort.Read())
    if not from then
        if waiting then
            self.waits = self.waits + 1
            if self.waits > self.WAIT_TRIES then return self:Stop() end
            return self:Later()
        end
        return self:Stop()
    end
    self.waits = 0
    self.moves = self.moves + 1
    Pickup(from.bag, from.slot)
    Pickup(to.bag, to.slot)
    -- Anything still held goes back where it came from.
    if CursorBusy() then Items.Call({ "ClearCursor" }) end
    self.last = { from.bag, from.slot, to.bag, to.slot }
    self:Later()
end

function BagSort:OnEnable()
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        if BagSort.running then BagSort:Stop() end
    end)
end
