-- Keep Across Characters: one number for the account, counted over every
-- character on this realm and side, bank too unless unticked. Bag copies
-- under the number are kept; the rest get the usual verdict. The number is
-- shared out the same way on every character, so two never both let go.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("keepacross")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 2840, name = "Copper Bar", count = 20, price = 10, stack = 20 },
    { bag = 0, slot = 2, id = 2840, name = "Copper Bar", count = 20, price = 10, stack = 20 },
    { bag = 0, slot = 3, id = 2840, name = "Copper Bar", count = 20, price = 10, stack = 20 },
})
local GUID = "Player-1-0000AAAA"
_G.UnitGUID = function(unit) if unit == "player" then return GUID end end
_G.UnitName = function() return "Mirelda Stormvale" end

-- Two characters: the one playing (60 in bags, 30 in the bank) and a bank
-- alt with 62 in bags, as Tradeskills last saw them.
local holdings = {
    { key = GUID, name = "Mirelda Stormvale", isCurrent = true,
      bags = { [2840] = 60 }, bank = { [2840] = 30 }, mail = {} },
    { key = "Player-1-0000BBBB", name = "Dorgan Ashbrook",
      bags = { [2840] = 62 }, bank = {}, mail = { [2840] = 5 } },
}
_G.BlackthornesTS = { Butler = { Holdings = function() return holdings end } }
env.Enable(ns)

local Verdicts, UI, KeepAcross, KeepHere = ns.Verdicts, ns.UI, ns.KeepAcross, ns.KeepHere

local function Kept(name)
    UI:Hide()
    UI:Show()
    local count, reason = 0, nil
    for _, group in ipairs(Verdicts:Groups()) do
        for _, row in ipairs(group.rows) do
            if row.name == name and row.verdict == "keep" then
                count = count + row.count
                reason = row.reason
            end
        end
    end
    return count, reason
end

Verdicts:SetChoice(2840, "sell")
suite.check("off until an item is added", Kept("Copper Bar") == 0)
suite.check("nothing saved before", ns.db.keepAcross == nil)

-- Share order is by key: AAAA (playing) first. Keep 140, bank counts:
-- 30 in the bank comes off, 110 left, the 60 here are all kept.
KeepAcross:Set(2840, 140)
suite.check("saved account wide", ns.db.keepAcross[2840] == 140)
local kept, reason = Kept("Copper Bar")
suite.check("this character keeps its share", kept == 60, kept)
suite.check("the row says why", reason == "Keeping 60 for your characters", reason)

local status = KeepAcross:Status(2840)
suite.check("have counts bags and bank", status.have == 152, status.have)
suite.check("kept, not short", status.short == 0)

-- Keep 70: 30 bank comes off, 40 left for the bags here.
KeepAcross:Set(2840, 70)
kept = Kept("Copper Bar")
suite.check("only the share is kept", kept == 40, kept)

-- Unticking Count Bank: 70 all from bags here.
KeepAcross:SetCountsBank(false)
suite.check("bank unticked saves false", ns.db.keepAcrossBank == false)
kept = Kept("Copper Bar")
suite.check("bank no longer counts", kept == 60, kept)
KeepAcross:SetCountsBank(true)
suite.check("ticked again clears the key", ns.db.keepAcrossBank == nil)

-- Count Mail: 30 bank + 5 mail off 55 leaves 20 here.
KeepAcross:Set(2840, 55)
KeepAcross:SetCountsMail(true)
kept = Kept("Copper Bar")
suite.check("mail counts when ticked", kept == 20, kept)
KeepAcross:SetCountsMail(false)

-- The other character's view: it comes after, so with 140 it keeps
-- 140 - 30 - 60 = 50 of its 62.
local holders = {
    { key = GUID, bags = 60, bank = 30, mail = 0 },
    { key = "Player-1-0000BBBB", bags = 62, bank = 0, mail = 5 },
}
local shares = KeepAcross.Share(140, holders, true, false)
suite.check("the next character keeps the rest", shares[1] == 60 and shares[2] == 50, shares[2])
suite.check("shares never pass the number", shares[1] + shares[2] + 30 == 140)
KeepAcross:Set(2840, 200)
status = KeepAcross:Status(2840)
suite.check("short by the gap", status.short == 48, status.short)

-- The bigger number wins: Keep Here 20 against a share of 0.
KeepAcross:Set(2840, 20)
kept = Kept("Copper Bar")
suite.check("bank covers it, nothing kept here", kept == 0, kept)
KeepHere:Set(2840, 20)
kept, reason = Kept("Copper Bar")
suite.check("Keep Here still wins when bigger", kept == 20 and reason == "Keeping 20 on this character", reason)
KeepHere:Set(2840, 0)

-- Keep All keeps every copy.
KeepAcross:Set(2840, KeepHere.MOST)
kept, reason = Kept("Copper Bar")
suite.check("Keep All keeps every copy", kept == 60, kept)
suite.check("Keep All says so", reason == "Keeping all for your characters", reason)

-- Tradeskills' read stays Butler's own Keep Here only.
suite.check("Count is untouched", KeepHere:Count(2840) == nil)

-- Without Tradeskills only the bags here count.
_G.BlackthornesTS = nil
KeepAcross:Set(2840, 40)
KeepAcross.read = nil
kept = Kept("Copper Bar")
suite.check("own bags only without Tradeskills", kept == 40, kept)

-- Settings lists it: a row with keep, have and status; a click opens
-- each character's line.
_G.BlackthornesTS = { Butler = { Holdings = function() return holdings end } }
KeepAcross.read = nil
KeepAcross:Set(2840, 140)
local SettingsUI = ns.SettingsUI
SettingsUI:Show()
local controls = SettingsUI.controls
local list = controls.acrossList
local row = list.rows[1]
suite.check("Settings has a row", row and row.itemID == 2840)
suite.check("row shows the number", row and row.keep:GetText() == "140", row and row.keep:GetText())
suite.check("row says kept", row and row.status:GetText() == "Kept", row and row.status:GetText())
suite.check("foot counts it", controls.acrossCount:GetText() == "1 item kept", controls.acrossCount:GetText())
local closedHeight = list.fixedHeight
row:GetScript("OnClick")(row, "LeftButton")
suite.check("a click opens the characters", #list.lines >= 2 and list.fixedHeight > closedHeight)
suite.check("whole names, you marked", list.lines[1].name:GetText() == "Mirelda Stormvale (you)",
    list.lines[1].name:GetText())
suite.check("where they are", list.lines[1].where:GetText() == "60 bags, 30 bank", list.lines[1].where:GetText())
KeepAcross:Set(2840, 400)
suite.check("short shows", list.rows[1].status:GetText():find("Short") ~= nil, list.rows[1].status:GetText())
SettingsUI:Hide()
KeepAcross:Set(2840, 0)
_G.BlackthornesTS = nil
KeepAcross.read = nil

-- Taking it off clears the save.
KeepAcross:Set(2840, 0)
suite.check("emptied list leaves nothing saved", ns.db.keepAcross == nil)
suite.check("nothing kept after", Kept("Copper Bar") == 0)

suite.done()
