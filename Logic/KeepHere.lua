-- Blackthornes Butler -- Logic/KeepHere.lua
-- Keep a number of an item on one character (a player asked, the owner
-- said build it, 2026-10-17): keep 5 elixirs on the rogue, and anything
-- past that gets Butler's usual verdict.
--
-- Saved account wide, by character GUID, never renamed:
--   keepHere = { [GUID] = { name = full name, items = { [itemID] = count } } }
-- so Settings can show and change any character's list from any character.
-- The character playing's list is also copied to its own save
-- (BlackthornesButlerCharDB.keepHere, never renamed), read when the client
-- won't give the GUID (a dungeon); nothing is written then.
--
-- Which stacks are kept (KeepHere.Plan): the biggest stacks that still fit
-- what is left to keep, then the smallest stack past that. That last one
-- would hold more than the count, so while the Butler window is up and no
-- fight is on, Butler splits the extra off into a free bag slot
-- (KeepHere:SplitNext), one stack a look; the extra then gets its own
-- verdict. Nothing is sold or deleted by a split: items only move in the
-- bags. With no free slot the whole stack is kept.
--
-- Tradeskills has the same choice for its Sell list (its Logic/KeepHere.lua,
-- 2026-10-18). Where both have a number, the bigger one wins, in both
-- addons (the owner): KeepHere:Effective reads Tradeskills', inside a pcall,
-- read only, and Tradeskills reads Count here. Count stays Butler's own, so
-- neither asks the other back.

local _, ns = ...
local L = ns.L

local KeepHere = ns.NewModule("KeepHere")

local Items = ns.Items

-- The most a box takes. Keep All saves this too, so every stack stays.
KeepHere.MOST = 9999

--- True when the number means every one (Keep All).
function KeepHere.IsAll(count)
    return type(count) == "number" and count >= KeepHere.MOST
end

--- The number as a player reads it: "All" for Keep All.
function KeepHere.Shown(count)
    if KeepHere.IsAll(count) then return L["All"] end
    return tostring(count or 0)
end
-- How long after the window's lists are laid out a split waits, so the
-- bags have settled.
KeepHere.SPLIT_WAIT = 0.5
-- Splits tried for one item each time the window opens, in case the game
-- won't do one.
KeepHere.SPLITS = 4

local function Text(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

--- The character playing's GUID, or nil when the client won't give it.
function KeepHere.PlayerGUID()
    local guid = Items.Call({ "UnitGUID" }, "player")
    local ok, isPlayer = pcall(function()
        return type(guid) == "string" and guid:find("^Player%-") ~= nil
    end)
    if ok and isPlayer then return guid end
    return nil
end

--- The character playing's full name as Tradeskills gives it, else the
--- game's.
function KeepHere.PlayingName()
    local name = ns.Errands and ns.Errands.PlayingName and ns.Errands:PlayingName()
    if Text(name) then return name end
    local ok, first = pcall(Items.Call, { "UnitName" }, "player")
    return ok and Text(first) or nil
end

local function All(make)
    if not ns.db then return {} end
    if type(ns.db.keepHere) ~= "table" then
        if not make then return {} end
        ns.db.keepHere = {}
    end
    return ns.db.keepHere
end

local function Record(guid, make)
    local all = All(make)
    local record = all[guid]
    if type(record) == "table" and type(record.items) == "table" then return record end
    if not make then return nil end
    record = type(record) == "table" and record or {}
    record.items = {}
    all[guid] = record
    return record
end

local function Clean(count)
    count = math.floor(tonumber(count) or 0)
    return math.max(0, math.min(KeepHere.MOST, count))
end

local function CopyMine(items)
    if not ns.charDB then return end
    local copy = {}
    for itemID, count in pairs(items) do copy[itemID] = count end
    ns.charDB.keepHere = copy
end

--- The character playing's list, { [itemID] = count }.
function KeepHere:MyItems()
    local guid = self.PlayerGUID()
    if guid then
        local record = Record(guid)
        return record and record.items or {}
    end
    local mine = ns.charDB and ns.charDB.keepHere
    return type(mine) == "table" and mine or {}
end

--- How many of an item the character playing keeps, or nil for none.
function KeepHere:Count(itemID)
    if not itemID then return nil end
    local count = Clean(self:MyItems()[itemID])
    if count > 0 then return count end
    return nil
end

--- How many Tradeskills keeps on the character playing, or nil.
function KeepHere.FromTradeskills(itemID)
    local ts = _G.BlackthornesTS
    local keep = type(ts) == "table" and ts.KeepHere
    if type(keep) ~= "table" or type(keep.Count) ~= "function" then return nil end
    local ok, count = pcall(keep.Count, keep, itemID)
    if not ok or type(count) ~= "number" or count ~= count then return nil end
    count = Clean(count)
    if count > 0 then return count end
    return nil
end

--- The number Butler keeps by: the biggest of its own, Tradeskills' and a
--- list's Keep Here (Logic/ListRules.lua) and this character's share of
--- Keep Across Characters (Logic/KeepAcross.lua). The second return is
--- that list's name when its number is the one kept; the third is true
--- when the number across characters is.
function KeepHere:Effective(itemID)
    local own = self:Count(itemID)
    local ts = self.FromTradeskills(itemID)
    local best = own or ts
    if own and ts then best = math.max(own, ts) end
    local list, listName
    if ns.ListRules then list, listName = ns.ListRules:Keep(itemID) end
    local across = ns.KeepAcross and ns.KeepAcross:Here(itemID)
    if across and (not best or across > best) and (not list or across > list) then
        return across, nil, true
    end
    if list and (not best or list > best) then return list, listName end
    return best
end

--- How many a character (by GUID) keeps, or nil for none.
function KeepHere:CountFor(guid, itemID)
    local record = guid and Record(guid)
    local count = record and Clean(record.items[itemID]) or 0
    if count > 0 then return count end
    return nil
end

--- Keep `count` of an item on a character (`guid`, the one playing when
--- nil). 0 or nil takes it off the list. True, or false and why.
function KeepHere:Set(itemID, count, guid)
    itemID = tonumber(itemID)
    local playing = self.PlayerGUID()
    guid = guid or playing
    if not itemID then return false end
    if not guid then
        return false, L["Butler can't tell which character you're on right now. Try again outside the dungeon."]
    end
    count = Clean(count)
    local record = Record(guid, count > 0)
    if not record then return true end
    if guid == playing then record.name = self.PlayingName() or record.name end
    record.items[itemID] = count > 0 and count or nil
    if guid == playing then CopyMine(record.items) end
    if ns.Verdicts then ns.Verdicts:Changed(true) end
    return true
end

--- Every character with a list, and the one playing: { guid, name,
--- count (items listed), playing }, the one playing first, then by name.
function KeepHere:Characters()
    local list, playing = {}, self.PlayerGUID()
    for guid, record in pairs(All()) do
        if type(guid) == "string" and type(record) == "table" and type(record.items) == "table" then
            local count = 0
            for _ in pairs(record.items) do count = count + 1 end
            if count > 0 or guid == playing then
                list[#list + 1] = { guid = guid, name = Text(record.name) or L["A character"],
                    count = count, playing = guid == playing }
            end
        end
    end
    local listed = false
    for _, each in ipairs(list) do
        if each.playing then
            listed = true
            each.name = self.PlayingName() or each.name
        end
    end
    if playing and not listed then
        list[#list + 1] = { guid = playing, name = self.PlayingName() or L["A character"],
            count = 0, playing = true }
    end
    table.sort(list, function(a, b)
        if a.playing ~= b.playing then return a.playing end
        if a.name ~= b.name then return a.name < b.name end
        return a.guid < b.guid
    end)
    return list
end

--- A character's list: { itemID, count, name }, by name.
function KeepHere:Items(guid)
    local record = guid and Record(guid)
    local list = {}
    if not record then return list end
    for itemID, count in pairs(record.items) do
        count = Clean(count)
        if type(itemID) == "number" and count > 0 then
            local itemName = Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, itemID)
            if not itemName and Items.RequestLoad then Items:RequestLoad(itemID) end
            list[#list + 1] = { itemID = itemID, count = count,
                name = Text(itemName) or L.Format("item %s", tostring(itemID)) }
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.itemID < b.itemID
    end)
    return list
end

--------------------------------------------------------------------------------
-- Which stacks are kept
--------------------------------------------------------------------------------

local function BagOrder(a, b)
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

--- Which of an item's slots keep it. `slots` are bag entries, `count` the
--- number to keep. Returns a set ([entry] = true) of the kept slots and,
--- when one holds more than is left to keep, { entry, extra } to split.
--- The biggest stacks that fit are taken first, so once a stack is split
--- the same ones are kept again.
function KeepHere.Plan(slots, count)
    local list = {}
    for _, entry in ipairs(slots) do list[#list + 1] = entry end
    table.sort(list, BagOrder)
    local kept, left = {}, count
    while left > 0 do
        local best
        for _, entry in ipairs(list) do
            local size = entry.count or 1
            if not kept[entry] and size <= left and (not best or size > (best.count or 1)) then
                best = entry
            end
        end
        if not best then break end
        kept[best] = true
        left = left - (best.count or 1)
    end
    local split
    if left > 0 then
        for _, entry in ipairs(list) do
            if not kept[entry] and (not split or (entry.count or 1) < (split.count or 1)) then
                split = entry
            end
        end
        if split then
            kept[split] = true
            split = { entry = split, extra = (split.count or 1) - left }
        end
    end
    return kept, split
end

--------------------------------------------------------------------------------
-- Splitting the extra off
--------------------------------------------------------------------------------

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
    local has = Items.Call({ "CursorHasItem" })
    if has then return true end
    local kind = Items.Call({ "GetCursorInfo" })
    return kind ~= nil
end

local function CanSplit()
    return Has("C_Container.SplitContainerItem") or Has("SplitContainerItem")
end

--- An empty slot in a bag that takes anything, or nil.
function KeepHere:FreeSlot()
    local last = tonumber(_G.NUM_BAG_SLOTS) or 4
    for _, bag in ipairs(ns.Bags.BagIDs()) do
        if bag <= last then
            local _, family = Items.Call({ "C_Container.GetContainerNumFreeSlots", "GetContainerNumFreeSlots" }, bag)
            if family == nil or family == 0 then
                local slots = tonumber(Items.Call({ "C_Container.GetContainerNumSlots", "GetContainerNumSlots" }, bag)) or 0
                for slot = 1, slots do
                    if not ns.Bags.ReadSlot(bag, slot) then return bag, slot end
                end
            end
        end
    end
    return nil
end

--- Can Butler split a stack now? A free slot and a client that splits.
function KeepHere:CanSplitNow()
    return CanSplit() and self:FreeSlot() ~= nil
end

--- The stacks to split, from the window's lists (Verdicts:Groups): each
--- { bag, slot, itemID, count, extra }. One is split a little later.
function KeepHere:SplitSoon(jobs)
    if not jobs or #jobs == 0 then return end
    self.pending = jobs
    if self.waiting then return end
    self.waiting = true
    C_Timer.After(self.SPLIT_WAIT, function()
        KeepHere.waiting = false
        KeepHere:SplitNext()
    end)
end

--- Split the first stack still waiting. The bag events that follow lay the
--- lists out again, and that asks for the next.
function KeepHere:SplitNext()
    local jobs = self.pending
    self.pending = nil
    if not jobs then return false end
    if not (ns.UI and ns.UI.IsShown and ns.UI:IsShown()) then return false end
    if InCombat() or CursorBusy() then return false end
    local opened = ns.Verdicts and ns.Verdicts.forgotAt
    if self.triesAt ~= opened then self.tries, self.triesAt = {}, opened end
    self.tries = self.tries or {}
    for _, job in ipairs(jobs) do
        local tries = self.tries[job.itemID] or 0
        if tries < self.SPLITS then
            self.tries[job.itemID] = tries + 1
            if self:Split(job) then return true end
        end
    end
    return false
end

--- Split `extra` off one stack into a free slot. True when it was done.
function KeepHere:Split(job)
    if not CanSplit() then return false end
    local entry = ns.Bags.ReadSlot(job.bag, job.slot)
    if not entry or entry.itemID ~= job.itemID or entry.locked or entry.count ~= job.count then
        return false
    end
    if not job.extra or job.extra <= 0 or job.extra >= entry.count then return false end
    local bag, slot = self:FreeSlot()
    if not bag then return false end
    Items.Call({ "C_Container.SplitContainerItem", "SplitContainerItem" }, job.bag, job.slot, job.extra)
    Items.Call({ "C_Container.PickupContainerItem", "PickupContainerItem" }, bag, slot)
    -- Anything still held goes back where it came from.
    if CursorBusy() then Items.Call({ "ClearCursor" }) end
    return true
end

function KeepHere:OnEnable()
    -- Keep the copy in this character's own save up to date, and its name.
    local guid = self.PlayerGUID()
    local record = guid and Record(guid)
    if record then
        record.name = self.PlayingName() or record.name
        CopyMine(record.items)
    end
end

--------------------------------------------------------------------------------
-- Chat
--------------------------------------------------------------------------------

--- Print this character's list (with /bbutler lists).
function KeepHere:PrintMine()
    local guid = self.PlayerGUID()
    local list = guid and self:Items(guid) or {}
    if #list == 0 then return end
    local names = {}
    for _, each in ipairs(list) do
        local _, link = Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, each.itemID)
        names[#names + 1] = L.Format("%s: %s", link or each.name, KeepHere.Shown(each.count))
    end
    ns.PrintRaw(("  |c%s%s|r %s"):format(ns.COLORS.muted,
        L.Format("Keep on this character (%d):", #list), table.concat(names, ", ")))
end
