-- The verdicts: every item in the bags gets one, the rules go in order, and
-- keeping always beats selling. Also the bag reading that feeds them: only
-- while someone looks, and only slots that changed.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("verdicts")

local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 101, name = "Broken Fang", quality = 0, price = 12, count = 3 },
    { bag = 0, slot = 2, id = 102, name = "Linen Cloth", quality = 1, price = 13, count = 20 },
    { bag = 0, slot = 3, id = 103, name = "Gnoll Paw", quality = 1, price = 0, quest = "item", bind = 4 },
    { bag = 0, slot = 4, id = 104, name = "Torn Note", quality = 1, price = 0, quest = "starts" },
    { bag = 0, slot = 5, id = 105, name = "Hearthstone", quality = 1, price = 0, noValue = true },
    { bag = 0, slot = 6, id = 106, name = "Cracked Jar", quality = 0, price = nil },
    { bag = 0, slot = 7, id = 101, name = "Broken Fang", quality = 0, price = 12, count = 2 },
    { bag = 0, slot = 8, id = 108, name = "Old Pole", quality = 1, price = 5, class = 12, bind = 1 },
})
env.Enable(ns)

local Bags, Verdicts = ns.Bags, ns.Verdicts

-- Nobody looks: a bag event only marks the bags stale.
env.Fire("BAG_UPDATE_DELAYED")
suite.check("no read while the window is shut and no vendor is open", Bags.version == 0 and Bags.stale)

ns.UI:Show()
suite.check("opening the window reads the bags", Bags.version == 1 and not Bags.stale)

local function Find(name)
    for _, group in ipairs(Verdicts:Groups()) do
        for _, row in ipairs(group.rows) do
            if row.name == name then return row, group end
        end
    end
end

local fang, sellGroup = Find("Broken Fang")
suite.check("greys are sold", fang and fang.verdict == "sell")
suite.check("two stacks of the same item are one row", fang.count == 5 and #fang.slots == 2)
suite.check("worth what a vendor pays for all of them", fang.worth == 60)
suite.check("the Sell group adds it up", sellGroup.worth == 60 and sellGroup.count == 1)

local cloth = Find("Linen Cloth")
suite.check("white items wait for the player", cloth.verdict == "look")
suite.check("saying what a vendor pays", cloth.reason:find("Vendor", 1, true) ~= nil)

suite.check("quest items are kept", Find("Gnoll Paw").verdict == "keep"
    and Find("Gnoll Paw").reason == "Quest item")
suite.check("so are items that start a quest", Find("Torn Note").reason == "Starts a quest")
suite.check("and quest-class items", Find("Old Pole").verdict == "keep")
suite.check("what a vendor won't buy is kept", Find("Hearthstone").verdict == "keep")

local jar = Find("Cracked Jar")
suite.check("a grey whose price has not loaded is never sold", jar.verdict == "look"
    and jar.reason:find("loading", 1, true) ~= nil)
suite.check("and the game is asked for it", fake.requested == 106)

-- The game answers: judged again once the burst of answers is over.
fake.info[106].price = 4
env.Fire("GET_ITEM_INFO_RECEIVED", 106, true)
suite.check("once it loads, the grey goes to Sell", Find("Cracked Jar").verdict == "sell")

-- The player's own choices.
Verdicts:SetChoice(102, "sell")
suite.check("Always sell puts a white item under Sell", Find("Linen Cloth").verdict == "sell")
suite.check("saved by item ID, account wide", ns.db.alwaysSell[102] == true)
Verdicts:SetChoice(101, "keep")
suite.check("Always keep beats grey", Find("Broken Fang").verdict == "keep")
Verdicts:SetChoice(103, "sell")
suite.check("a quest item is kept even on the sell list", Find("Gnoll Paw").verdict == "keep")
Verdicts:SetChoice(101, nil)
suite.check("Let Butler decide takes it off both lists",
    ns.db.alwaysKeep[101] == nil and ns.db.alwaysSell[101] == nil and Find("Broken Fang").verdict == "sell")

-- The groups come in order: what to do first at the top.
local order = {}
for _, group in ipairs(Verdicts:Groups()) do order[#order + 1] = group.verdict end
suite.check("Craft, Sell, Auction, Disenchant, Mail, Bank, Look at it, Wait, then Keep",
    table.concat(order, ",") == "craft,sell,auction,disenchant,mail,bank,look,wait,keep")

-- Only a slot whose key changed is read further.
local questReads = 0
local realQuest = Bags.ReadQuest
Bags.ReadQuest = function(...) questReads = questReads + 1 return realQuest(...) end
fake.bags[0][2].count = 19
env.Fire("BAG_UPDATE_DELAYED")
suite.check("a bag event while the window is up reads again", Bags.version == 2)
suite.check("and looks further only at the slot that changed", questReads == 1, questReads)
local before = Bags.version
env.Fire("BAG_UPDATE_DELAYED")
suite.check("nothing changed, nothing redrawn", Bags.version == before)
Bags.ReadQuest = realQuest

-- An emptied slot leaves the list.
fake.bags[0][8] = nil
env.Fire("BAG_UPDATE_DELAYED")
suite.check("a sold or moved item leaves the list", Find("Old Pole") == nil)

-- The window shows it all.
local lines = ns.UI:Lines()
suite.check("each group has a heading", lines[1].type == "header" and lines[1].group.verdict == "sell")
local keepFolded = true
for _, line in ipairs(lines) do
    if line.type == "item" and line.verdict == "keep" then keepFolded = false end
end
suite.check("Keep starts folded away", keepFolded)
for _, line in ipairs(lines) do
    if line.type == "header" and line.group.verdict == "keep" then
        ns.UI:Clicked(line, "LeftButton")
    end
end
local keepRows = 0
for _, line in ipairs(ns.UI:Lines()) do
    if line.type == "item" and line.verdict == "keep" then keepRows = keepRows + 1 end
end
suite.check("a click on its heading opens it", keepRows > 0)
suite.check("remembered per character", ns.charDB.folded.keep == nil)

-- The right-click menu sets the lists.
local cloth2 = Find("Linen Cloth")
ns.UI:Clicked(cloth2, "RightButton")
suite.check("right-click opens Butler's own menu", ns.UI.menu:IsShown())
suite.check("offering Let Butler decide for an item on a list", ns.UI.menu.decide:IsShown())
ns.UI.menu.keep:GetScript("OnClick")(ns.UI.menu.keep)
suite.check("Always keep moves it", Find("Linen Cloth").verdict == "keep" and not ns.UI.menu:IsShown())

-- The typed reset empties both lists; without confirm it does nothing.
ns.HandleSlash("reset")
suite.check("reset without confirm keeps the lists", ns.db.alwaysKeep[102] == true)
ns.HandleSlash("reset confirm")
suite.check("reset confirm empties them", next(ns.db.alwaysKeep) == nil and next(ns.db.alwaysSell) == nil)

-- The bags change while a read is under way: the read goes again, and the
-- window is redrawn even when the second pass finds nothing new (what the
-- first found was left undrawn before).
do
    local queued = {}
    local realAfter = C_Timer.After
    C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
    local realBudget = Bags.BUDGET
    Bags.BUDGET = 4
    local redraws = 0
    local realChanged = Verdicts.BagsChanged
    Verdicts.BagsChanged = function(self, ...) redraws = redraws + 1 return realChanged(self, ...) end
    Bags:Scan()
    fake.Put({ bag = 0, slot = 14, id = 140, name = "Late Loot", quality = 0, price = 7 })
    Bags:Scan()
    while #queued > 0 do table.remove(queued, 1)() end
    suite.check("a read that goes again still redraws once", redraws == 1, redraws)
    suite.check("and has the new item", Bags.slots["0:14"] ~= nil)
    Verdicts.BagsChanged = realChanged
    Bags.BUDGET = realBudget
    C_Timer.After = realAfter
end

suite.done()
