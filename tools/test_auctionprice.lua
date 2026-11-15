-- The auction price Butler shows: what one brings after the cut. A slow
-- seller shows its real number (it is weighed at less only to choose
-- between the auction house and a vendor), and today's cheapest listing
-- is used when it is higher than the usual price and the scan is fresh
-- (a player saw a number well under the lowest listing, 2026-11-11).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("auctionprice")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 701, name = "Linen Cloth", quality = 1, price = 10 },
    { bag = 0, slot = 2, id = 702, name = "Copper Ore", quality = 1, price = 10 },
    { bag = 0, slot = 3, id = 703, name = "Light Leather", quality = 1, price = 10 },
    { bag = 0, slot = 4, id = 704, name = "Tin Ore", quality = 1, price = 800 },
    { bag = 0, slot = 5, id = 705, name = "Bronze Bar", quality = 1, price = 10 },
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

_G.BlackthornesTS = { Butler = { Advise = function(_, id)
    if id == 701 then return { auction = 1000, fast = false } end        -- sells slowly
    if id == 702 then return { auction = 1000, auctionNow = 1400 } end   -- prices went up today
    if id == 703 then return { auction = 1000 } end                      -- no fresh scan
    if id == 704 then return { auction = 1000, fast = false } end        -- slow: the vendor wins at 800
    if id == 705 then return { auction = 1000, auctionNow = 950 } end    -- a little under: the usual
end } }
UI:Hide()
UI:Show()

local linen = Find("Linen Cloth")
suite.check("a slow seller still goes to auction", linen.verdict == "auction", linen.verdict)
suite.check("a slow seller shows its real price, not the lowered one", linen.unit == 1000, linen.unit)
suite.check("its reason says it sells slowly", linen.reason and linen.reason:find("slowly") ~= nil, linen.reason)

local copper = Find("Copper Ore")
suite.check("prices went up: still auction", copper.verdict == "auction", copper.verdict)
suite.check("prices went up: today's cheapest listing is shown", copper.unit == 1400, copper.unit)
suite.check("the reason names today's price", copper.reason and copper.reason:find("14") ~= nil, copper.reason)

local leather = Find("Light Leather")
suite.check("no fresh scan: the usual price", leather.unit == 1000, leather.unit)

local tin = Find("Tin Ore")
suite.check("slow and the vendor pays more than three quarters: sell", tin.verdict == "sell", tin.verdict)

local bronze = Find("Bronze Bar")
suite.check("today a little under: the usual price, no wait", bronze.verdict == "auction" and bronze.unit == 1000,
    tostring(bronze.verdict) .. " " .. tostring(bronze.unit))

suite.check("AuctionPrice picks the higher fresh price", Verdicts.AuctionPrice({ auction = 5, auctionNow = 9 }) == 9)
suite.check("AuctionPrice keeps the usual price otherwise", Verdicts.AuctionPrice({ auction = 5, auctionNow = 3 }) == 5)
suite.check("AuctionPrice is nil without a price", Verdicts.AuctionPrice({}) == nil)

suite.done()
