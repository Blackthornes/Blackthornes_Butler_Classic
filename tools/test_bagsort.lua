-- Butler's own bag sort, for a client with no bag sort (Era; the owner said
-- build it, 2026-10-24).
--
-- What must hold:
--   1. Sort shows on a client with no bag sort when Butler can move items.
--   2. Loose stacks of one item go together, then every item to its place:
--      Hearthstone first, greys last, kinds in order.
--   3. Only items change slots: nothing is lost, nothing on the cursor.
--   4. A bag that takes only some things keeps its own items.
--   5. A fight stops it, and it never starts with something on the cursor.
--   6. The game's own sort still wins where the client has one.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bagsort")

local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 901, name = "Broken Fang", quality = 0, price = 1, count = 2, class = 15 },
    { bag = 0, slot = 2, id = 902, name = "Linen Cloth", quality = 1, price = 1, count = 7, class = 7, stack = 20 },
    { bag = 0, slot = 4, id = 903, name = "Iron Sword", quality = 2, price = 9, class = 2 },
    { bag = 0, slot = 5, id = 902, name = "Linen Cloth", quality = 1, price = 1, count = 5, class = 7, stack = 20 },
    { bag = 0, slot = 6, id = 6948, name = "Hearthstone", quality = 1, price = 0, class = 15 },
    { bag = 0, slot = 8, id = 904, name = "Tough Jerky", quality = 1, price = 1, count = 3, class = 0, stack = 20 },
    { bag = 1, slot = 1, id = 905, name = "Rough Arrow", quality = 1, price = 1, count = 200, class = 6, stack = 200 },
    { bag = 1, slot = 3, id = 906, name = "Sharp Arrow", quality = 1, price = 1, count = 200, class = 6, stack = 200 },
})
fake.numSlots = 8

-- Bag 1 is a quiver: four slots that take arrows only.
local container = _G.C_Container
container.GetContainerNumSlots = function(bag)
    if bag == 0 then return fake.numSlots end
    if bag == 1 then return 4 end
    return 0
end
container.GetContainerNumFreeSlots = function(bag)
    return 0, bag == 1 and 1 or 0
end

-- Picking up and putting down as the client does: an empty hand takes the
-- slot's item, a full one drops on an empty slot, joins a loose stack of
-- the same item (what is left stays on the cursor) or swaps.
local cursor, picks = nil, 0
container.PickupContainerItem = function(bag, slot)
    picks = picks + 1
    local here = fake.bags[bag][slot]
    if not cursor then
        if here then cursor = { item = here, bag = bag, slot = slot } end
        fake.bags[bag][slot] = nil
        return
    end
    local held = cursor.item
    if not here then
        held.bag, held.slot = bag, slot
        fake.bags[bag][slot] = held
        cursor = nil
    elseif here.id == held.id and (here.count or 1) < (here.stack or 1) then
        local room = here.stack - here.count
        local put = math.min(room, held.count)
        here.count = here.count + put
        held.count = held.count - put
        if held.count <= 0 then cursor = nil end
    else
        held.bag, held.slot = bag, slot
        here.bag, here.slot = cursor.bag, cursor.slot
        fake.bags[bag][slot] = held
        fake.bags[cursor.bag][cursor.slot] = here
        cursor = nil
    end
end
_G.CursorHasItem = function() return cursor ~= nil end
_G.ClearCursor = function()
    if cursor then
        fake.bags[cursor.bag][cursor.slot] = cursor.item
        cursor = nil
    end
end

local function At(bag, slot)
    local item = fake.bags[bag][slot]
    return item and item.id or nil
end

local function Total(id)
    local n = 0
    for bag = 0, 4 do
        for _, item in pairs(fake.bags[bag]) do
            if item.id == id then n = n + (item.count or 1) end
        end
    end
    return n
end

env.Enable(ns)
local BagWindow = ns.BagWindow

-- 1. Sort shows with no game sort.
suite.check("the client has no bag sort", not BagWindow.GameSorts())
suite.check("Sort shows anyway, since Butler can sort", BagWindow.CanSort())

-- 5. Not with something on the cursor.
cursor = { item = { id = 1 }, bag = 4, slot = 1 }
suite.check("no sort with something on the cursor", ns.BagSort:Start() == false)
cursor = nil

-- 2 and 3. Sort the bags.
suite.check("the sort starts", ns.BagSort:Start())
suite.check("and is done", not ns.BagSort:Running())
suite.check("Hearthstone first", At(0, 1) == 6948)
suite.check("then food", At(0, 2) == 904)
suite.check("then weapons", At(0, 3) == 903)
suite.check("then trade goods, in one stack", At(0, 4) == 902 and fake.bags[0][4].count == 12)
suite.check("greys last", At(0, 5) == 901)
suite.check("the rest empty", At(0, 6) == nil and At(0, 7) == nil and At(0, 8) == nil)
suite.check("no cloth lost", Total(902) == 12)
suite.check("nothing left on the cursor", cursor == nil)

-- 4. The quiver keeps its arrows, packed in order.
suite.check("the quiver keeps its own", At(1, 1) == 905 and At(1, 2) == 906 and At(1, 3) == nil)

-- A second sort has nothing to do.
picks = 0
ns.BagSort:Start()
suite.check("sorted bags make no moves", picks == 0)

-- 5. A fight stops it between moves.
do
    fake.bags[0][1], fake.bags[0][6] = nil, fake.bags[0][1]
    fake.bags[0][6].slot = 6
    local saveAfter = _G.C_Timer.After
    local queued
    _G.C_Timer.After = function(_, fn) queued = fn end
    ns.BagSort:Start()
    suite.check("a move waits for the server", ns.BagSort:Running())
    env.Fire("PLAYER_REGEN_DISABLED")
    suite.check("a fight stops the sort", not ns.BagSort:Running())
    _G.C_Timer.After = saveAfter
end

-- 6. The game's own sort wins.
do
    local sorted = false
    container.SortBags = function() sorted = true end
    picks = 0
    BagWindow:Sort()
    suite.check("the game's sort is used where there is one", sorted and picks == 0)
    container.SortBags = nil
end

_G.CursorHasItem, _G.ClearCursor = nil, nil

suite.done()
