-- Wait for a better price: an item Butler would put on the auction house
-- waits, folded away, while today's cheapest listing by someone else is
-- well under its usual price. Nothing is sold or deleted; the group only
-- starts folded, on every character, until the player opens it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("waitprice")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 601, name = "Silk Cloth", quality = 1, price = 40, count = 20 },
    { bag = 0, slot = 2, id = 602, name = "Iron Ore", quality = 1, price = 50 },
    { bag = 0, slot = 3, id = 603, name = "Mageweave Cloth", quality = 1, price = 60 },
    { bag = 0, slot = 4, id = 604, name = "Wool Cloth", quality = 1, price = 1200 },
    { bag = 0, slot = 5, id = 605, name = "Phoenix Gloves", quality = 2, price = 300 },
    { bag = 0, slot = 6, id = 606, name = "Runecloth Belt", quality = 2, price = 300 },
})
env.Enable(ns)

local Verdicts, UI = ns.Verdicts, ns.UI

local function Find(name)
    for _, group in ipairs(Verdicts:Groups()) do
        for _, row in ipairs(group.rows) do
            if row.name == name then return row end
        end
    end
end

local function Look()
    UI:Hide()
    UI:Show()
end

local function Header(lines, verdict)
    for _, line in ipairs(lines) do
        if line.type == "header" and line.group.verdict == verdict then return line end
    end
end

local function Shows(lines, name)
    for _, line in ipairs(lines) do
        if line.type == "item" and line.name == name then return true end
    end
    return false
end

_G.BlackthornesTS = { Butler = { Advise = function(_, id)
    if id == 601 then return { auction = 1000, auctionNow = 600 } end  -- a real dip
    if id == 602 then return { auction = 1000, auctionNow = 900 } end  -- a little under is normal
    if id == 603 then return { auction = 1000 } end                    -- no fresh scan
    if id == 604 then return { auction = 1000, auctionNow = 100 } end  -- the vendor pays more anyway
    if id == 605 then return { auction = 19355, belowCost = 21706 } end -- Tradeskills won't list it
    if id == 606 then return { auction = 19355, belowCost = 21706, disenchant = 30000, canDisenchant = true } end
end } }
Look()

local silk = Find("Silk Cloth")
suite.check("well under the usual price: Wait for a better price", silk.verdict == "wait", silk.verdict)
suite.check("the reason says today's price and the usual one",
    silk.reason:find("right now", 1, true) ~= nil, silk.reason)
suite.check("still worth its usual price", silk.unit == 1000, silk.unit)
suite.check("a little under is still Auction", Find("Iron Ore").verdict == "auction")
suite.check("no price for today is still Auction", Find("Mageweave Cloth").verdict == "auction")
suite.check("only items to auction wait", Find("Wool Cloth").verdict ~= "wait", Find("Wool Cloth").verdict)

-- Tradeskills' Sell list calls it a loss: its price is under what it costs
-- to make. Butler agrees and holds it back instead of saying Auction.
local gloves = Find("Phoenix Gloves")
suite.check("under what it costs to make: Wait", gloves.verdict == "wait", gloves.verdict)
suite.check("the reason names the cost", gloves.reason:find("to make", 1, true) ~= nil, gloves.reason)
suite.check("still worth its auction price", gloves.unit == 19355, gloves.unit)
suite.check("a better way still wins", Find("Runecloth Belt").verdict == "disenchant", Find("Runecloth Belt").verdict)

-- Folded at first, also on a character whose folds were saved before.
ns.charDB.folded = { keep = true }
local lines = UI:Lines()
local header = Header(lines, "wait")
suite.check("the group has a heading", header ~= nil)
suite.check("folded at first", header and header.folded == true)
suite.check("its items are out of the way", not Shows(lines, "Silk Cloth"))
suite.check("Auction still shows its items", Shows(lines, "Iron Ore"))

UI:Clicked(header, "LeftButton")
lines = UI:Lines()
suite.check("a click opens it", Header(lines, "wait").folded == false and Shows(lines, "Silk Cloth"))
suite.check("and is kept as opened", ns.charDB.folded.wait == false)
UI:Clicked(Header(lines, "wait"), "LeftButton")
lines = UI:Lines()
suite.check("a second click folds it again", Header(lines, "wait").folded == true and not Shows(lines, "Silk Cloth"))

-- Other groups fold as before.
UI:Clicked(Header(lines, "auction"), "LeftButton")
suite.check("Auction folds as before", ns.charDB.folded.auction == true)
UI:Clicked(Header(UI:Lines(), "auction"), "LeftButton")
suite.check("and opens back to nothing saved", ns.charDB.folded.auction == nil)

-- The Sell button never takes them.
suite.check("nothing waiting is under Sell", Find("Silk Cloth").verdict ~= "sell")

-- Why it waits, short, and Sell Anyway (the owner, 2026-11-14).
suite.check("the row says why in a few words", silk.wait and silk.wait.short:find("now", 1, true) ~= nil,
    silk.wait and silk.wait.short)
suite.check("it carries the prices for the hover", silk.wait.now == 600 and silk.wait.usual == 1000)
suite.check("a loss says it costs more to make", gloves.wait and gloves.wait.short == "Costs more to make")
suite.check("and carries what it costs", gloves.wait.cost == 21706)

local told = ns.Verdicts:Waiting(601, 0, 1)
suite.check("Tradeskills hears Butler says wait", told ~= nil and told.short ~= nil and told.reason == silk.reason)
suite.check("with the prices", told and told.now == 600 and told.usual == 1000)
suite.check("nothing for an item that does not wait", ns.Verdicts:Waiting(602, 0, 2) == nil)
suite.check("nothing for the wrong slot", ns.Verdicts:Waiting(601, 0, 2) == nil)
suite.check("nothing without a slot", ns.Verdicts:Waiting(601) == nil)

UI.RowAction(silk)
suite.check("Sell Anyway moves it to Auction", Find("Silk Cloth").verdict == "auction", Find("Silk Cloth").verdict)
suite.check("only that item", Find("Phoenix Gloves").verdict == "wait")
suite.check("Tradeskills hears it no longer waits", ns.Verdicts:Waiting(601, 0, 1) == nil)
ns.Verdicts:SellAnyway(605)
suite.check("a loss can be sold anyway too", Find("Phoenix Gloves").verdict == "auction")
ns.Verdicts:ClearSellAnyway()
suite.check("leaving the auction house makes them wait again",
    Find("Silk Cloth").verdict == "wait" and Find("Phoenix Gloves").verdict == "wait")
suite.check("nothing is saved", ns.db.sellAnyway == nil and ns.charDB.sellAnyway == nil)

-- The right-click menu leads with Sell Anyway on a waiting row only.
silk = Find("Silk Cloth")
UI:ShowMenu(silk)
suite.check("the menu leads with Sell Anyway", UI.menu.sellAnyway:IsShown())
UI.menu.sellAnyway:GetScript("OnClick")(UI.menu.sellAnyway)
suite.check("and it sells it anyway", Find("Silk Cloth").verdict == "auction")
UI:ShowMenu(Find("Iron Ore"))
suite.check("no Sell Anyway on other rows", not UI.menu.sellAnyway:IsShown())
ns.Verdicts:ClearSellAnyway()
local tip = { lines = {} }
function tip:AddLine(t) self.lines[#self.lines + 1] = t end
function tip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = a .. " " .. b end
UI.WaitLines(tip, Find("Phoenix Gloves").wait)
local joined = table.concat(tip.lines, "|")
suite.check("the hover shows the numbers", joined:find("Costs to Make:", 1, true) ~= nil
    and joined:find("Sell Anyway moves it", 1, true) ~= nil, joined)

_G.BlackthornesTS = nil
suite.done()
