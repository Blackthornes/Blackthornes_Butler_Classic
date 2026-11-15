-- The Bags window's Bank tab remembers the bank away from the banker, on
-- its own, without Tradeskills (a player's report, 2026-11-10).
--
-- What must hold:
--   1. Away from the bank with nothing kept, the tab is empty.
--   2. A visit keeps a copy by GUID; after leaving, the tab still shows it.
--   3. A read that sees no bank slots never wipes a good copy.
--   4. Tradeskills' copy is used when it is newer; Butler's when it is.
--   5. Another character's copy is never shown.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bankcopy")

local GUID = "Player-1-0000AAAA"
local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 2589, name = "Linen Cloth", quality = 1, price = 13, count = 20 },
})
fake.bags[-1] = {}
local bankSlots = 4
_G.C_Container.GetContainerNumSlots = function(bag)
    if bag == 0 then return fake.numSlots end
    if bag == -1 then return bankSlots end
    return 0
end
fake.Put({ bag = -1, slot = 1, id = 2592, name = "Wool Cloth", quality = 1, price = 33, count = 12 })
fake.Put({ bag = -1, slot = 2, id = 2592, name = "Wool Cloth", quality = 1, price = 33, count = 8 })
_G.UnitGUID = function(unit) if unit == "player" then return GUID end end
env.Enable(ns)
local BagView, Errands = ns.BagView, ns.Errands

local function Count(list, id)
    local total = 0
    for _, item in ipairs(list) do if item.itemID == id then total = total + item.count end end
    return total
end

-- 1.
local list, live = BagView:BankItems()
suite.check("nothing kept, nothing shown", #list == 0 and live == false)

-- 2.
env.Fire("BANKFRAME_OPENED")
list, live = BagView:BankItems()
suite.check("at the bank it reads live", live == true and Count(list, 2592) == 20)
env.Fire("BANKFRAME_CLOSED")
suite.check("the bank shut", not Errands.bankOpen)
list, live = BagView:BankItems()
suite.check("after leaving, the tab still shows the bank", live == false and Count(list, 2592) == 20, #list)
local copy = ns.db.bankCopies and ns.db.bankCopies[GUID]
suite.check("kept by GUID with a time", copy and copy.items[2592] == 20 and type(copy.at) == "number")

-- 3.
bankSlots = 0
Errands.bankOpen = true
suite.check("a read with no slots keeps nothing", BagView:NoteBank() == false)
Errands.bankOpen = false
list = BagView:BankItems()
suite.check("the good copy is still there", Count(list, 2592) == 20)
bankSlots = 4

-- 4.
local tsAt = 0
Errands.Holdings = function()
    local me = { isCurrent = true, bank = { [2592] = 5, [4306] = 3 }, bankAt = tsAt }
    return { me }, me
end
tsAt = copy.at + 100
list = BagView:BankItems()
suite.check("Tradeskills' newer copy wins", Count(list, 2592) == 5 and Count(list, 4306) == 3)
tsAt = copy.at - 100
list = BagView:BankItems()
suite.check("Butler's newer copy wins", Count(list, 2592) == 20 and Count(list, 4306) == 0)

-- 5.
Errands.Holdings = function() return nil end
_G.UnitGUID = function(unit) if unit == "player" then return "Player-1-0000BBBB" end end
list = BagView:BankItems()
suite.check("another character sees none of it", #list == 0)
_G.UnitGUID = function() return nil end
list = BagView:BankItems()
suite.check("no GUID, nothing shown", #list == 0)
_G.UnitGUID = nil

suite.done()
