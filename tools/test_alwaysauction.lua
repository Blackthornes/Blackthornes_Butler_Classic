-- The Always auction list (a player asked, the owner said build it,
-- 2026-11-12): an item the player picks goes to the auction house even
-- when a vendor pays more.
--
-- What must hold:
--   1. An item a vendor pays more for goes under Sell.
--   2. On the Always auction list it goes under Auction, and back to Sell
--      when taken off.
--   3. An upgrade to wear now and a soulbound copy are Look at it.
--   4. A Farmer goal or this character's craft queue keeps it.
--   5. Saved account wide as alwaysAuction, and the rule is on the Order
--      page's list.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("alwaysauction")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 901, name = "Heavy Linen Bandage", quality = 1, price = 5000 },
    { bag = 0, slot = 2, id = 902, name = "Bound Sash", quality = 1, price = 5000, bound = true },
})
env.Enable(ns)

local Verdicts = ns.Verdicts

local function Find(name)
    for _, group in ipairs(Verdicts:Groups()) do
        for _, row in ipairs(group.rows) do
            if row.name == name then return row end
        end
    end
end

local upgrade, goalNeed, queueNeed = false, 0, 0
_G.BlackthornesTS = { Butler = {
    Advise = function()
        local a = { auction = 1000 }
        if queueNeed > 0 then a.need = queueNeed end
        return a
    end,
} }
_G.BlackthornesEquipment = { Butler = { Advise = function()
    if upgrade then return { upgrade = "now", gain = 5 } end
end } }
_G.BlackthornesFarmer = { Butler = { Advise = function(_, id)
    if id == 901 and goalNeed > 0 then return { goal = "Heavy Linen Bandage", have = 1, target = 9, need = goalNeed } end
end } }

-- 1. A vendor pays more: Sell.
ns.UI:Show()
Verdicts:Changed(true)
suite.check("vendor pays more: sell", Find("Heavy Linen Bandage").verdict == "sell", Find("Heavy Linen Bandage").verdict)

-- 2. The player's pick wins.
Verdicts:SetChoice(901, "auction")
local row = Find("Heavy Linen Bandage")
suite.check("on the list: auction", row.verdict == "auction", row.verdict)
suite.check("saying why", row.reason == "On your Always auction list", row.reason)
suite.check("the choice reads back", Verdicts:Choice(901) == "auction")
suite.check("saved account wide", ns.db.alwaysAuction[901] == true)

-- 3. An upgrade and a soulbound copy stay.
upgrade = true
Verdicts:Changed(true)
suite.check("an upgrade is not auctioned", Find("Heavy Linen Bandage").verdict == "look", Find("Heavy Linen Bandage").verdict)
upgrade = false
Verdicts:SetChoice(902, "auction")
Verdicts:Changed(true)
suite.check("soulbound is not auctioned", Find("Bound Sash").verdict == "look", Find("Bound Sash").verdict)
Verdicts:SetChoice(902, nil)

-- 4. A goal and the craft queue keep it.
goalNeed = 3
Verdicts:Changed(true)
suite.check("a goal keeps it", Find("Heavy Linen Bandage").verdict == "keep", Find("Heavy Linen Bandage").verdict)
goalNeed, queueNeed = 0, 2
Verdicts:Changed(true)
suite.check("the craft queue keeps it", Find("Heavy Linen Bandage").verdict == "keep", Find("Heavy Linen Bandage").verdict)
queueNeed = 0

-- Picking another list takes it off this one.
Verdicts:SetChoice(901, "sell")
suite.check("another pick clears it", ns.db.alwaysAuction[901] == nil)

-- Taken off: back to sell.
Verdicts:SetChoice(901, nil)
Verdicts:Changed(true)
suite.check("off the list: sell again", Find("Heavy Linen Bandage").verdict == "sell", Find("Heavy Linen Bandage").verdict)

-- 5. On the Order page.
local listed = false
for _, id in ipairs(Verdicts:Order()) do
    if id == "auctionList" then listed = true end
end
suite.check("the rule is in the order", listed)
suite.check("the Order page names it", ns.RuleOrderUI == nil or ns.RuleOrderUI.RULES.auctionList ~= nil)

_G.BlackthornesFarmer, _G.BlackthornesTS, _G.BlackthornesEquipment = nil, nil, nil
suite.done()
