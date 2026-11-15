-- Sell below: anything worth less than the amount the player sets joins
-- Sell, judged on the most it could fetch. It never touches what is kept,
-- never soulbound green gear, and does nothing until Tradeskills has said
-- what the auction house pays.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("sellbelow")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 501, name = "Small Flame Sac", quality = 1, price = 30 },
    { bag = 0, slot = 2, id = 502, name = "Silk Cloth", quality = 1, price = 40, count = 20 },
    { bag = 0, slot = 3, id = 503, name = "Gnoll Paw", quality = 1, price = 5, quest = "item", bind = 4 },
    { bag = 0, slot = 4, id = 504, name = "Copper Ore", quality = 1, price = 5 },
    { bag = 0, slot = 5, id = 505, name = "Worn Gloves", quality = 2, price = 20, bound = true },
    { bag = 0, slot = 6, id = 506, name = "Ragged Shirt", quality = 1, price = 10 },
    { bag = 0, slot = 7, id = 507, name = "Wool Cloth", quality = 1, price = 8 },
    { bag = 0, slot = 8, id = 508, name = "Tarnished Ring", quality = 2, price = 25 },
    { bag = 0, slot = 9, id = 509, name = "Rough Stone", quality = 1, price = 2 },
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

local function Look()
    ns.UI:Hide()
    ns.UI:Show()
end

-- Reading an amount.
local Parse = Verdicts.ParseMoney
suite.check("50s is 5000 copper", Parse("50s") == 5000)
suite.check("1g 20s 5c", Parse("1g 20s 5c") == 12005)
suite.check("2g5s with no spaces", Parse("2g5s") == 20500)
suite.check("a plain number is gold", Parse("3") == 30000)
suite.check("off is 0", Parse("off") == 0 and Parse("") == 0)
suite.check("nonsense can't be read", Parse("lots") == nil and Parse("5x") == nil)

-- Off until set.
ns.UI:Show()
suite.check("off by default", Verdicts:SellBelow() == nil and ns.db.sellBelow == nil)
suite.check("so a cheap white item waits for the player", Find("Small Flame Sac").verdict == "look")

-- Without Tradeskills there is no auction price, so it does nothing.
Verdicts:SetSellBelow(100)
suite.check("saved in copper, account wide", ns.db.sellBelow == 100)
Look()
suite.check("without Tradeskills nothing is called junk", Find("Small Flame Sac").verdict == "look")

-- Tradeskills answers.
_G.BlackthornesTS = { Butler = { Advise = function(_, id)
    if id == 501 then return { auction = 900 } end   -- sells well on the auction house
    if id == 502 then return {} end                   -- never priced there
    if id == 503 then return { auction = 1 } end
    if id == 504 then return { need = 3 } end         -- the craft queue wants it
    if id == 505 then return { disenchant = 10, canDisenchant = true } end
    if id == 506 then return { auction = 40 } end
    if id == 507 then return { auction = 20 } end
    if id == 508 then return { disenchant = 400, canDisenchant = true } end
    if id == 509 then return { auction = 1 } end
end } }
_G.BlackthornesEquipment = { Butler = { Advise = function(_, link)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    if id == 506 then return { upgrade = "now" } end
end } }
Look()

local sac = Find("Small Flame Sac")
suite.check("an item the auction house pays well for is not junk", sac.verdict ~= "sell", sac.verdict)

local silk = Find("Silk Cloth")
suite.check("worth less than the amount: Sell", silk.verdict == "sell" and silk.reason:find("Worth less than", 1, true),
    silk.reason)
suite.check("at what a vendor pays", silk.unit == 40 and silk.worth == 800)

local wool = Find("Wool Cloth")
suite.check("judged on the most it fetches (auction 20 over vendor 8)", wool.verdict == "sell")
suite.check("quest items are never junk", Find("Gnoll Paw").verdict == "keep")
suite.check("craft materials are never junk", Find("Copper Ore").verdict == "keep")
suite.check("upgrades are never junk", Find("Ragged Shirt").verdict == "keep")
suite.check("soulbound green gear is never sold for the player", Find("Worn Gloves").verdict ~= "sell")
suite.check("a disenchant worth more than the amount wins", Find("Tarnished Ring").verdict == "disenchant")

-- The player's own lists beat it.
Verdicts:SetChoice(509, "keep")
suite.check("Always keep beats it", Find("Rough Stone").verdict == "keep")
Verdicts:SetChoice(509, "bank")
suite.check("Always bank beats it", Find("Rough Stone").verdict == "bank")
Verdicts:SetChoice(509, nil)
suite.check("taken off the lists, it is junk", Find("Rough Stone").verdict == "sell")

-- Selling still waits for the click, and sells only Sell rows.
for _, item in ipairs(ns.Selling:Queue()) do
    suite.check("only Sell rows are queued (" .. tostring(item.itemID) .. ")",
        Verdicts:Judge(ns.Bags.slots[item.bag .. ":" .. item.slot]) == "sell")
end

-- Raising the amount judges again at once.
Verdicts:SetSellBelow(1000)
suite.check("a higher amount takes in more", Find("Small Flame Sac").verdict == "sell")

-- The command.
ns.HandleSlash("sellbelow 1g 5s")
suite.check("/bbutler sellbelow sets it", ns.db.sellBelow == 10500)
ns.HandleSlash("sellbelow lots")
suite.check("an amount it can't read changes nothing", ns.db.sellBelow == 10500)
ns.HandleSlash("sellbelow off")
suite.check("/bbutler sellbelow off turns it off", ns.db.sellBelow == nil and Verdicts:SellBelow() == nil)
suite.check("and the item waits for the player again", Find("Silk Cloth").verdict ~= "sell")

_G.BlackthornesTS = nil
_G.BlackthornesEquipment = nil
suite.done()
