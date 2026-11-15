-- Levelling Enchanting with your own greens (the owner asked 2026-10-13:
-- "If a non-crafted green can DE into materials needed to guarantee an
-- increase in your enchanting skill Butler should recommend disenchanting
-- it").
--
-- What must hold:
--   1. A green Tradeskills names `forEnchanting` for goes under Disenchant,
--      even when the auction house pays more, saying which craft needs it.
--   2. Only as many as cover what Enchanting lacks; the rest get their
--      usual verdict.
--   3. Keeping and the Always sell list still win.
--   4. Not when this character can't break it, and never for a blue.
--   5. With "Always Disenchant" unticked (the default) too, while a vendor
--      or the auction house pays at most twice what breaking it gives
--      (Verdicts.SKILL_LOSS; the owner, 2026-11-10: a green worth 20s at a
--      vendor was broken for 4s of essence). Past that, the best price.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("levelenchanting")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 701, name = "Ridge Cleaver", quality = 2, price = 400 },
    { bag = 0, slot = 2, id = 702, name = "Forest Leather Belt", quality = 2, price = 300 },
    { bag = 0, slot = 3, id = 703, name = "Brackwater Boots", quality = 2, price = 200 },
    { bag = 0, slot = 4, id = 704, name = "Silver Defias Belt", quality = 3, price = 900 },
})
env.Enable(ns)
-- 1 to 4 tick "Always Disenchant"; 5 checks the default.
ns.db.disenchantAnyPrice = true

local Verdicts = ns.Verdicts

local function Find(name)
    for _, group in ipairs(Verdicts:Groups()) do
        for _, row in ipairs(group.rows) do
            if row.name == name then return row end
        end
    end
end

local can, short, upgrade, auction, breaks = true, 2, false, 50000, 900
local wanted = { recipe = "Enchant Bracer - Minor Health", material = 10940,
    materialName = "Strange Dust", yield = 1.125 }
_G.BlackthornesTS = { Butler = {
    Advise = function(_, id)
        local answer = { auction = auction, disenchant = breaks, canDisenchant = can }
        if id ~= 704 then
            answer.forEnchanting = { recipe = wanted.recipe, material = wanted.material,
                materialName = wanted.materialName, yield = wanted.yield, short = short }
        end
        return answer
    end,
} }
_G.BlackthornesEquipment = { Butler = { Advise = function(_, link)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    if id == 701 and upgrade then return { upgrade = "now", gain = 5 } end
end } }

local function Verdict(name) return Find(name).verdict end

-- 1 and 2. Two greens give about 2.25 dust, enough for the 2 short.
ns.UI:Show()
Verdicts:Changed(true)
local cleaver = Find("Ridge Cleaver")
suite.check("a green for a sure point goes under Disenchant", cleaver.verdict == "disenchant", cleaver.verdict)
suite.check("saying which craft needs what",
    cleaver.reason:find("To level Enchanting: Enchant Bracer - Minor Health needs Strange Dust", 1, true) ~= nil,
    cleaver.reason)
suite.check("the second green too", Verdict("Forest Leather Belt") == "disenchant", Verdict("Forest Leather Belt"))
suite.check("enough covered: the third goes to auction", Verdict("Brackwater Boots") == "auction",
    Verdict("Brackwater Boots"))
suite.check("a blue is left alone", Verdict("Silver Defias Belt") == "auction", Verdict("Silver Defias Belt"))
suite.check("the slot's verdict agrees with the row",
    Verdicts:VerdictOf(ns.Bags.slots["0:3"] or Find("Brackwater Boots").slots[1]) == "auction")

short = 10
Verdicts:Changed(true)
suite.check("more short: all three", Verdict("Brackwater Boots") == "disenchant", Verdict("Brackwater Boots"))

-- 3. Keeping and the Always sell list still win.
upgrade = true
Verdicts:Changed(true)
suite.check("an upgrade here is kept", Verdict("Ridge Cleaver") == "keep", Verdict("Ridge Cleaver"))
upgrade = false
Verdicts:SetChoice(702, "sell")
suite.check("the Always sell list wins", Verdict("Forest Leather Belt") == "sell", Verdict("Forest Leather Belt"))
Verdicts:SetChoice(702, nil)

-- 4. Not when this character can't break it.
can = false
Verdicts:Changed(true)
suite.check("can't disenchant: its usual verdict", Verdict("Ridge Cleaver") ~= "disenchant", Verdict("Ridge Cleaver"))
can = true
short = 0
Verdicts:Changed(true)
suite.check("nothing short: its usual verdict", Verdict("Ridge Cleaver") == "auction", Verdict("Ridge Cleaver"))

-- 5. Unticked: a skill point beats a sale up to twice as good, no more.
short = 2
Verdicts:SetAlwaysDisenchant(false)
suite.check("auction pays far more: auction", Verdict("Ridge Cleaver") == "auction",
    Verdict("Ridge Cleaver"))
auction = 1500
Verdicts:Changed(true)
suite.check("auction pays under twice as much: still for Enchanting",
    Verdict("Ridge Cleaver") == "disenchant", Verdict("Ridge Cleaver"))
auction = 1800
Verdicts:Changed(true)
suite.check("auction pays just twice as much: still for Enchanting",
    Verdict("Ridge Cleaver") == "disenchant", Verdict("Ridge Cleaver"))
-- The player's report: a vendor paying five times what breaking gives.
auction, breaks = nil, 80
Verdicts:Changed(true)
-- Not broken: the best price decides what it is (here Look at it, with no
-- auction price to weigh a green by).
suite.check("vendor pays far more: not broken", Verdict("Ridge Cleaver") ~= "disenchant",
    Verdict("Ridge Cleaver"))
breaks = 300
Verdicts:Changed(true)
suite.check("vendor pays under twice as much: still for Enchanting",
    Verdict("Ridge Cleaver") == "disenchant", Verdict("Ridge Cleaver"))
auction, breaks = 50000, 900
short = 0
Verdicts:Changed(true)
suite.check("no skill point: selling pays more, so auction", Verdict("Ridge Cleaver") == "auction",
    Verdict("Ridge Cleaver"))
short = 2
auction = 500
Verdicts:Changed(true)
local row = Find("Ridge Cleaver")
suite.check("breaking it pays more: for Enchanting", row.verdict == "disenchant"
    and row.reason:find("To level Enchanting", 1, true) ~= nil, row.reason)

suite.done()
