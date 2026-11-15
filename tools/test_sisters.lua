-- What the other four addons say turns into verdicts: keep for an upgrade,
-- a goal, a craft or pet food; mail to the alt who needs it; and the best
-- of vendor, auction and disenchant. A sister that is missing or breaks is
-- skipped.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("sisters")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 401, name = "Ringed Helm", quality = 2, price = 300 },
    { bag = 0, slot = 2, id = 402, name = "Copper Ore", quality = 1, price = 5, count = 10 },
    { bag = 0, slot = 3, id = 403, name = "Light Leather", quality = 1, price = 10, count = 5 },
    { bag = 0, slot = 4, id = 404, name = "Tough Jerky", quality = 1, price = 1, count = 20 },
    { bag = 0, slot = 5, id = 405, name = "Silk Cloth", quality = 1, price = 40, count = 20 },
    { bag = 0, slot = 6, id = 406, name = "Linen Cloth", quality = 1, price = 13, count = 20 },
    { bag = 0, slot = 7, id = 407, name = "Glimmering Mail Boots", quality = 2, price = 200 },
    { bag = 0, slot = 8, id = 408, name = "Brutal Gauntlets", quality = 2, price = 150, bound = true },
    { bag = 0, slot = 9, id = 409, name = "Patched Cloak", quality = 1, price = 30 },
    { bag = 0, slot = 10, id = 410, name = "Bolt of Wool", quality = 1, price = 50 },
    { bag = 0, slot = 11, id = 411, name = "Broken Fang", quality = 0, price = 12 },
    { bag = 0, slot = 12, id = 412, name = "Mithril Pick", quality = 1, price = 80 },
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

-- Without any sister, Butler judges as it did on its own.
ns.UI:Show()
suite.check("alone, white items wait for the player", Find("Silk Cloth").verdict == "look")
suite.check("alone, greys sell", Find("Broken Fang").verdict == "sell")

-- The four sisters, as their Butler:Advise calls answer.
local asked = {}
local equipmentArgs
_G.BlackthornesEquipment = { Butler = { Advise = function(_, link, bag, slot)
    asked.equipment = (asked.equipment or 0) + 1
    local id = tonumber(tostring(link):match("item:(%d+)"))
    if id == 401 then equipmentArgs = { bag, slot } return { upgrade = "now", gain = 12 } end
    if id == 407 then return { upgrade = "later", gain = 30 } end
    if id == 412 then return { tool = true } end
    if id == 409 then return { sell = true } end
    if id == 408 then return { sell = true } end
    if id == 411 then error("broken") end
end } }
_G.BlackthornesFarmer = { Butler = { Advise = function(_, id)
    if id == 402 then return { goal = "Copper Ore", have = 10, target = 40, need = 30 } end
    if id == 406 then return { goal = "Linen Cloth", have = 20, target = 20, need = 0 } end
end } }
_G.BlackthornesTS = { Butler = { Advise = function(_, id)
    asked.ts = (asked.ts or 0) + 1
    if id == 403 then return { need = 4 } end
    if id == 405 then return { auction = 90, fast = true } end
    if id == 406 then return { auction = 20, fast = false } end
    if id == 410 then return { mailTo = "Bob", mailCount = 1, auction = 300 } end
    if id == 408 then return { disenchant = 400, canDisenchant = true } end
    if id == 409 then return { auction = 25, disenchant = 500, canDisenchant = false, enchanter = "Ana" } end
end } }
_G.BlackthornesPets = { Butler = { Advise = function(_, id)
    if id == 404 then return { eats = true, buff = false, hours = 2.46, count = 20 } end
    return "not a table"
end } }

-- Answers are kept until the window opens again.
ns.UI:Hide()
ns.UI:Show()

local helm = Find("Ringed Helm")
suite.check("an upgrade is kept to wear", helm.verdict == "keep" and helm.reason:find("wear", 1, true))
suite.check("Equipment gets the bag and slot", equipmentArgs and equipmentArgs[1] == 0 and equipmentArgs[2] == 1)
suite.check("an upgrade at a later level is kept", Find("Glimmering Mail Boots").verdict == "keep")
suite.check("a tool is kept", Find("Mithril Pick").reason == "A tool you use")

local ore = Find("Copper Ore")
suite.check("a goal keeps what it needs", ore.verdict == "keep" and ore.reason:find("30 more", 1, true))
suite.check("a finished goal keeps nothing", Find("Linen Cloth").verdict ~= "keep")

suite.check("the craft queue keeps its materials", Find("Light Leather").verdict == "keep"
    and Find("Light Leather").reason:find("needs 4", 1, true))
local wool = Find("Bolt of Wool")
suite.check("an alt's craft gets it mailed", wool.verdict == "mail" and wool.reason:find("Bob", 1, true))

local jerky = Find("Tough Jerky")
suite.check("pet food is kept", jerky.verdict == "keep" and jerky.reason:find("2.5 h", 1, true), jerky.reason)

local silk = Find("Silk Cloth")
suite.check("auction beats vendor", silk.verdict == "auction" and silk.worth == 90 * 20)

local linen = Find("Linen Cloth")
-- 20 weighed down for a slow sale is 15, still over the vendor's 13, so it
-- goes to auction and shows its real 20 (2026-11-11).
suite.check("a slow sale is weighed down but can still win", linen.verdict == "auction"
    and linen.unit == 20 and linen.reason:find("slowly", 1, true), linen.unit)

local gauntlets = Find("Brutal Gauntlets")
suite.check("soulbound gear is disenchanted when that pays most", gauntlets.verdict == "disenchant")

local cloak = Find("Patched Cloak")
suite.check("an enchanter alt gets it mailed", cloak.verdict == "mail" and cloak.reason:find("Ana", 1, true))

suite.check("a sister that raises is skipped", Find("Broken Fang").verdict == "sell")

-- Vendor wins once the auction house is asked and pays less.
_G.BlackthornesTS.Butler.Advise = function(_, id)
    if id == 405 then return { auction = 30 } end
    if id == 408 then return { disenchant = 10, canDisenchant = true } end
end
ns.UI:Hide()
ns.UI:Show()
local silkSold = Find("Silk Cloth")
suite.check("vendor beats a cheap auction: sell", silkSold.verdict == "sell"
    and silkSold.reason:find("Vendor pays more", 1, true))

-- A slow sale the vendor beats only once marked down says it is slow,
-- never that the vendor pays more (a player read that under a higher price).
local _, slowWhy = Verdicts:Best({ quality = 2 }, 2696, { ts = { auction = 3200, fast = false } })
suite.check("a slow sale lost to the vendor says it is slow",
    slowWhy:find("Sells slowly", 1, true) and not slowWhy:find("Vendor pays more", 1, true), slowWhy)
local bound = Find("Brutal Gauntlets")
suite.check("soulbound green is never sold for the player", bound.verdict == "look"
    and bound.reason:find("Not an upgrade", 1, true))
suite.check("white gear Equipment has no use for is sold", Find("Patched Cloak").verdict == "sell")

-- Soulbound green this class can never wear, with nothing left to weigh: Sell.
local soul = { quality = 2, bound = true }
local v, why = Verdicts:Best(soul, 150, { ts = { disenchant = 40, canDisenchant = true },
    equipment = { never = true, sell = false } })
suite.check("never wearable, disenchant known and lower: sell", v == "sell"
    and why:find("can't use", 1, true) and why:find("disenchanting", 1, true), why)
v, why = Verdicts:Best(soul, 150, { ts = { canDisenchant = false }, equipment = { never = true, sell = true } })
suite.check("never wearable, can't disenchant: sell", v == "sell" and why:find("can't use", 1, true), why)
v = Verdicts:Best(soul, 150, { ts = { canDisenchant = true }, equipment = { never = true } })
suite.check("disenchant value not known yet: still look", v == "look")
v = Verdicts:Best(soul, 150, { equipment = { never = true } })
suite.check("without Tradeskills: still look", v == "look")
v = Verdicts:Best(soul, 150, { ts = { canDisenchant = false }, equipment = { sell = true } })
suite.check("wearable but no upgrade: still look", v == "look")
v = Verdicts:Best(soul, 150, { ts = { disenchant = 400, canDisenchant = true }, equipment = { never = true } })
suite.check("disenchant pays more: still disenchant", v == "disenchant")

-- Asked once per item per look, not once per redraw.
local before = asked.ts
Verdicts:Groups()
ns.UI:Refresh(true)
suite.check("redraws ask nobody", asked.ts == before)

-- The Sell button never sells a kept or auction row.
for _, item in ipairs(ns.Selling:Queue()) do
    suite.check("only Sell rows are sold (" .. tostring(item.itemID) .. ")",
        Verdicts:Judge(ns.Bags.slots[item.bag .. ":" .. item.slot]) == "sell")
end

suite.done()
