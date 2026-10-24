-- The Forever client's own game tables standing in where the client has not
-- loaded an item yet (Data/ForeverItems.lua, tools/make_forever_items.py).
--
-- What must hold:
--   1. The live game wins: item info, and the tooltip over item info.
--   2. An item the client has not loaded gets the table's sell price, is
--      still asked for, and the live price replaces it once it loads.
--   3. An item the tables don't know stays "still loading" (nil).
--   4. A bag's family comes from the client; only when it gives none does
--      the table say, by the bag's own item.
--   5. A quiver the client gives no family for is still found for ammo.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("foreveritems")

local ns = env.Load()
-- The Classic Era TOC leaves the file out (tools/test_era.lua), so it is
-- loaded here by hand: the readers still work whenever it is there.
assert(loadfile(lfs_cwd .. "/Data/ForeverItems.lua"))("Blackthornes_Butler", ns)
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 2589, name = "Linen Cloth", quality = 1, price = 20, count = 5 },
})
local Items = ns.Items

-- 1. The data loads and holds what the generator wrote.
suite.check("the table is loaded", type(ns.ForeverItems) == "table" and type(ns.ForeverItems.SELL) == "table")
suite.check("Linen Cloth has a price there", ns.ForeverItems.SELL[2589] == 13, ns.ForeverItems.SELL[2589])
suite.check("Light Quiver holds arrows", ns.ForeverItems.BAGS[2101] == 1)
suite.check("Small Ammo Pouch holds bullets", ns.ForeverItems.BAGS[2102] == 2)

-- Live item info beats the table.
Items:Forget()
suite.check("item info wins over the table", Items:SellPrice(2589) == 20, Items:SellPrice(2589))

-- The tooltip wins over both.
_G.C_TooltipInfo = { GetItemByID = function(id)
    if id == 2589 then return { lines = { { type = 11, price = 7 } } } end
end }
Items:Forget()
suite.check("the tooltip wins over everything", Items:SellPrice(2589) == 7, Items:SellPrice(2589))
_G.C_TooltipInfo = nil

-- 2. Not loaded yet: Silk Cloth (4306) has no item info.
Items:Forget()
fake.requested = nil
Items.waiting = {}
suite.check("an unloaded item gets the table's price", Items:SellPrice(4306) == 150, Items:SellPrice(4306))
suite.check("and is still asked for", fake.requested == 4306, fake.requested)

-- It loads with a different price: the live one replaces the table's.
fake.info[4306] = { id = 4306, name = "Silk Cloth", quality = 1, price = 120 }
suite.check("the live price replaces it once loaded", Items:SellPrice(4306) == 120, Items:SellPrice(4306))

-- 3. Unknown to the tables and not loaded: still loading.
Items:Forget()
suite.check("an item nobody knows stays unjudged", Items:SellPrice(999999) == nil)

-- Item info without a sell price falls back to the table, then 0.
fake.info[2592] = { id = 2592, name = "Wool Cloth", quality = 1, price = false }
local itemInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function(id)
    if id == 2592 then return "Wool Cloth", "link", 1, 1, 1, "Misc", "Misc", 20, "", 134400, nil end
    return itemInfo(id)
end
Items:Forget()
suite.check("no price in item info: the table's", Items:SellPrice(2592) == 33, Items:SellPrice(2592))

-- 4. Bag family.
local bagItem = { [1] = 2101 }
_G.C_Container.ContainerIDToInventoryID = function(bag) return 30 + bag end
_G.GetInventoryItemID = function(_, slot) return bagItem[slot - 30] end
suite.check("the table names the quiver in bag 1", Items.TableBagFamily(1) == 1, Items.TableBagFamily(1))
suite.check("a bag it doesn't know is nil", Items.TableBagFamily(2) == nil)
suite.check("the backpack is never asked", Items.TableBagFamily(0) == nil)

-- 5. A hunter with a bow and a quiver whose family the client won't say.
_G.UnitClass = function() return "Hunter", "HUNTER" end
C_Item.GetItemInfoInstant = function(id)
    if id == 2504 then return id, "Weapon", "Bow", "", 134400, 2, 2 end
    return id, "Misc", "Misc", "", 134400, 15, 0
end
_G.GetInventoryItemID = function(_, slot)
    if slot == 18 then return 2504 end
    return bagItem[slot - 30]
end
_G.C_Container.GetContainerNumFreeSlots = function(bag)
    if bag == 1 then return 3, nil end
    return 0, 0
end
local bag = ns.Ammo:Bag()
suite.check("the quiver is found from the table", bag ~= nil and bag.bag == 1 and bag.holds == "arrow")

-- The client's own family wins over the table: it says bullets.
_G.C_Container.GetContainerNumFreeSlots = function(b)
    if b == 1 then return 3, 2 end
    return 0, 0
end
bag = ns.Ammo:Bag()
suite.check("the client's family wins", bag ~= nil and bag.holds == "bullet")

suite.done()
