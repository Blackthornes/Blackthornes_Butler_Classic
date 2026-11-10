-- Quest items that can go on the auction house (a player's report,
-- 2026-11-10: farming a tradeable quest item, Butler kept it as "Quest
-- item" and it never followed Always mail or Auction).
--
-- What must hold:
--   1. A quest item that is not bound, binds neither on pickup nor as a
--      quest item, and that no open quest needs follows the usual rules:
--      Auction when the auction house pays most, Always mail when listed.
--   2. A bound copy, one that binds on pickup or as a quest item, and one
--      the client hasn't loaded yet stay Keep, "Quest item".
--   3. One an open quest needs stays Keep with the quest's reason.
--   4. An item that starts a quest stays Keep.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("tradequestitems")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 60001, name = "Soft Fur Tail", quality = 1, price = 5, count = 12, quest = "item" },
    { bag = 0, slot = 2, id = 60002, name = "Bound Tail", quality = 1, price = 5, quest = "item", bound = true },
    { bag = 0, slot = 3, id = 60003, name = "Pickup Tail", quality = 1, price = 5, quest = "item", bind = 1 },
    { bag = 0, slot = 4, id = 60004, name = "Quest Tail", quality = 1, price = 5, quest = "item", bind = 4 },
    { bag = 0, slot = 5, id = 60005, name = "Unknown Tail", quality = 1, price = 5, quest = "item" },
    { bag = 0, slot = 6, id = 60006, name = "Wanted Tail", quality = 1, price = 5, quest = "item" },
    { bag = 0, slot = 7, id = 60007, name = "Old Letter", quality = 1, price = 5, quest = "starts" },
})
-- The client hasn't said how the Unknown Tail binds yet.
local getInfo = _G.C_Item.GetItemInfo
_G.C_Item.GetItemInfo = function(id)
    local results = { getInfo(id) }
    if id == 60005 then results[14] = nil; return unpack(results, 1, 13) end
    return unpack(results, 1, math.max(#results, 14))
end

_G.BlackthornesTS = { Butler = {
    Advise = function(_, id)
        if id >= 60001 and id <= 60007 then return { auction = 500, fast = true } end
    end,
    Holdings = function()
        return {
            { key = "me", short = "Me Here", realm = "R", faction = "Horde", isCurrent = true },
            { key = "bob", short = "Bob Stone", realm = "R", faction = "Horde" },
        }
    end,
    Mailbox = function() end,
} }
env.Enable(ns)
local Verdicts, UI = ns.Verdicts, ns.UI

-- An open quest wants the Wanted Tail.
local reason = ns.Quests.Reason
ns.Quests.Reason = function(self, itemID)
    if itemID == 60006 then return "Tail Hunt needs 3 more" end
    return reason(self, itemID)
end

local function Row(id)
    for _, group in ipairs(Verdicts:Groups()) do
        for _, row in ipairs(group.rows) do
            if row.itemID == id then return row end
        end
    end
end

UI:Show("bags")
Verdicts:Changed(true)

-- 1. Tradeable and not needed: the usual rules.
local tail = Row(60001)
suite.check("a tradeable quest item goes to auction", tail.verdict == "auction", tail.verdict)
Verdicts:SetChoice(60001, "mail", "Bob Stone")
Verdicts:Changed(true)
tail = Row(60001)
suite.check("and follows Always mail", tail.verdict == "mail" and tail.mailTo == "Bob Stone",
    tostring(tail.verdict) .. " " .. tostring(tail.mailTo))

-- 2. Can't be traded, or not known yet: kept.
for _, id in ipairs({ 60002, 60003, 60004, 60005 }) do
    local row = Row(id)
    suite.check("kept: " .. row.name, row.verdict == "keep" and row.reason == "Quest item",
        tostring(row.verdict) .. " " .. tostring(row.reason))
end

-- 3. An open quest needs it: kept, saying why.
local wanted = Row(60006)
suite.check("an open quest's item is kept", wanted.verdict == "keep"
    and wanted.reason == "Tail Hunt needs 3 more", tostring(wanted.reason))

-- 4. Starts a quest: kept.
suite.check("an item that starts a quest is kept", Row(60007).reason == "Starts a quest")

suite.done()
