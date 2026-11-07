-- Blackthornes Butler -- Logic/KeepAcross.lua
-- Keep a number of an item across all your characters (a player asked on
-- Discord, the owner said build it from a mockup, 2026-11-07): keep 140
-- Copper Bars between a main and a bank alt, bank included, and anything
-- past that gets Butler's usual verdict.
--
-- Saved account wide, never renamed:
--   keepAcross     = { [itemID] = count }   (count 9999 is Keep All)
--   keepAcrossBank = false when Count Bank is unticked (nil reads as on)
--   keepAcrossMail = true when Count Mail is ticked (nil reads as off)
-- Nothing changes until an item is added.
--
-- Counted over the characters on this realm and side (Everyone:Read, from
-- Tradeskills' Holdings; the character playing's bags are Butler's own
-- live read). Without Tradeskills only the bags here count.
--
-- Two characters must never each think the other one holds enough, so the
-- number is shared out the same way on every character (KeepAcross.Share):
-- what the bank and mail hold (when counted) comes off first, since those
-- copies stay put anyway, then each character's bags in a fixed order (by
-- character key). What falls to the character playing is how many of its
-- bag copies are kept (KeepAcross:Here); KeepHere:Effective takes the
-- bigger of that and the other keeps.

local _, ns = ...

local KeepAcross = ns.NewModule("KeepAcross")

-- How long a read of everyone's counts is trusted while nothing moved.
KeepAcross.KEEP_FOR = 5

local function MostCount() return ns.KeepHere and ns.KeepHere.MOST or 9999 end

local function Clean(count)
    count = math.floor(tonumber(count) or 0)
    return math.max(0, math.min(MostCount(), count))
end

local function All(make)
    if not ns.db then return {} end
    if type(ns.db.keepAcross) ~= "table" then
        if not make then return {} end
        ns.db.keepAcross = {}
    end
    return ns.db.keepAcross
end

--- How many of an item are kept across characters, or nil for none.
function KeepAcross:Count(itemID)
    if not itemID then return nil end
    local count = Clean(All()[itemID])
    if count > 0 then return count end
    return nil
end

--- Every item kept, sorted by item ID: { { itemID, count } }.
function KeepAcross:Items()
    local list = {}
    for itemID, count in pairs(All()) do
        count = Clean(count)
        if type(itemID) == "number" and count > 0 then
            list[#list + 1] = { itemID = itemID, count = count }
        end
    end
    table.sort(list, function(a, b) return a.itemID < b.itemID end)
    return list
end

local function Moved()
    KeepAcross.version = (KeepAcross.version or 0) + 1
    KeepAcross.read = nil
    if ns.Verdicts then ns.Verdicts:Changed(true) end
    if ns.SettingsUI and ns.SettingsUI.SyncKeepAcross then
        pcall(ns.SettingsUI.SyncKeepAcross, ns.SettingsUI)
    end
end

--- Set the number (0 or nil takes the item off).
function KeepAcross:Set(itemID, count)
    if type(itemID) ~= "number" or not ns.db then return end
    count = Clean(count)
    local all = All(count > 0)
    all[itemID] = count > 0 and count or nil
    if next(all) == nil then ns.db.keepAcross = nil end
    Moved()
end

--- Does the bank count toward the number? On unless unticked.
function KeepAcross:CountsBank()
    return not (ns.db and ns.db.keepAcrossBank == false)
end

--- Does mail on its way or in a mailbox count? Off unless ticked.
function KeepAcross:CountsMail()
    return ns.db and ns.db.keepAcrossMail == true or false
end

function KeepAcross:SetCountsBank(on)
    if not ns.db then return end
    if on then ns.db.keepAcrossBank = nil else ns.db.keepAcrossBank = false end
    Moved()
end

function KeepAcross:SetCountsMail(on)
    if not ns.db then return end
    ns.db.keepAcrossMail = on and true or nil
    Moved()
end

--------------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------------

local function Now()
    local clock = rawget(_G, "GetTime")
    return type(clock) == "function" and clock() or 0
end

-- Everyone's counts, read once a look: kept while the bags and verdicts
-- stand still, for at most KEEP_FOR seconds, so a hundred items judged in
-- one burst cost one read.
function KeepAcross:Characters()
    local stamp = ("%d:%d"):format(ns.Bags and ns.Bags.version or 0,
        ns.Verdicts and ns.Verdicts.version or 0)
    local read = self.read
    if read and read.stamp == stamp and Now() - read.at < self.KEEP_FOR then
        return read.list
    end
    local list = ns.Everyone and ns.Everyone:Read() or nil
    self.read = { stamp = stamp, at = Now(), list = list }
    return list
end

local function CarriedHere(itemID)
    local count = ns.Bags and ns.Bags.Carried and ns.Bags:Carried(itemID)
    return type(count) == "number" and count or 0
end

--- Each character's copies of an item: { { key, name, isCurrent, bags,
--- bank, mail } } in the fixed order the number is shared out in.
function KeepAcross:Holders(itemID)
    local holders = {}
    local list = self:Characters()
    local sawMe = false
    for _, entry in ipairs(list or {}) do
        local mine = entry.isCurrent
        if mine then sawMe = true end
        holders[#holders + 1] = {
            key = entry.key,
            name = entry.name,
            isCurrent = mine,
            bags = mine and CarriedHere(itemID) or (entry.bags[itemID] or 0),
            bank = entry.bank[itemID] or 0,
            mail = entry.mail[itemID] or 0,
        }
    end
    if not sawMe then
        holders[#holders + 1] = {
            key = ns.KeepHere and ns.KeepHere.PlayerGUID() or "",
            name = ns.KeepHere and ns.KeepHere.PlayingName() or "",
            isCurrent = true, bags = CarriedHere(itemID), bank = 0, mail = 0,
        }
    end
    table.sort(holders, function(a, b) return tostring(a.key) < tostring(b.key) end)
    return holders
end

--- How many count toward the number, all characters together.
function KeepAcross:Have(itemID, holders)
    holders = holders or self:Holders(itemID)
    local bank, mail, have = self:CountsBank(), self:CountsMail(), 0
    for _, h in ipairs(holders) do
        have = have + h.bags + (bank and h.bank or 0) + (mail and h.mail or 0)
    end
    return have
end

--- Share the number out: what falls to each holder's bags, by index.
--- Bank and mail (when counted) come off first, then bags in order.
function KeepAcross.Share(count, holders, countBank, countMail)
    local left = count
    for _, h in ipairs(holders) do
        if countBank then left = left - h.bank end
        if countMail then left = left - h.mail end
    end
    local shares = {}
    for i, h in ipairs(holders) do
        local take = math.max(0, math.min(h.bags, left))
        shares[i] = take
        left = left - take
    end
    return shares
end

--- How many bag copies the character playing keeps for the number, or
--- nil for none. Keep All keeps every copy.
function KeepAcross:Here(itemID)
    local count = self:Count(itemID)
    if not count then return nil end
    if ns.KeepHere and ns.KeepHere.IsAll(count) then return count end
    local holders = self:Holders(itemID)
    local shares = self.Share(count, holders, self:CountsBank(), self:CountsMail())
    for i, h in ipairs(holders) do
        if h.isCurrent then
            local take = shares[i] or 0
            if take > 0 then return take end
            return nil
        end
    end
    return nil
end

--- The row Settings shows: keep, have and how many short (0 when kept).
function KeepAcross:Status(itemID)
    local count = self:Count(itemID)
    if not count then return nil end
    local holders = self:Holders(itemID)
    local have = self:Have(itemID, holders)
    local short = 0
    if not (ns.KeepHere and ns.KeepHere.IsAll(count)) then
        short = math.max(0, count - have)
    end
    return { count = count, have = have, short = short, holders = holders }
end
