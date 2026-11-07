-- Swap When Full and quest loot (the owner, 2026-11-06): picking up a
-- quest item with full bags always offers the swap for the least valuable
-- item, though a quest item sells for nothing.
--
-- What must hold:
--   1. Quest loot with no vendor price is offered against the cheapest item.
--   2. Quest loot wins over loot worth more in the same window.
--   3. The game's quest flag, item class 12 and an open quest's item all count.
--   4. With nothing to sell, auction or break, the cheapest Wait item goes.
--   5. Keep, Mail, Bank and Look at it are never offered: no popup.
--   6. Ordinary loot still needs to be worth more.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("swapquest")

local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 701, name = "Broken Fang", quality = 0, price = 12, count = 3 },
    { bag = 0, slot = 2, id = 702, name = "Ruined Pelt", quality = 0, price = 5 },
})
fake.info[801] = { id = 801, name = "Ringed Helm", quality = 2, price = 300, stack = 1 }
fake.info[901] = { id = 901, name = "Gnoll Paw", quality = 1, price = 0, stack = 1, class = 12 }
fake.info[902] = { id = 902, name = "Murloc Fin", quality = 1, price = 0, stack = 1 }
fake.info[903] = { id = 903, name = "Strange Note", quality = 1, price = 0, stack = 1 }
fake.info[804] = { id = 804, name = "Old Stone", quality = 0, price = 1, stack = 1 }

_G.C_Container.GetContainerNumFreeSlots = function() return 0, 0 end
local loot = {}
local function Link(id, name) return ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(id, name) end
_G.GetNumLootItems = function() return #loot end
_G.GetLootSlotType = function() return 1 end
_G.GetLootSlotLink = function(slot) local item = loot[slot]; return item and Link(item.id, item.name) end
_G.GetLootSlotInfo = function(slot)
    local item = loot[slot]
    if not item then return nil end
    return 134400, item.name, 1, nil, item.quality or 1, false, item.questFlag or false
end
_G.LootSlot = function() end
_G.LootFrame = env.Stub({ _shown = true })

env.Enable(ns)
local Swap = ns.SwapWhenFull
env.Fire("PLAYER_ENTERING_WORLD")
ns.db.swapWhenFull = true

local function Showing() return Swap.frame ~= nil and Swap.frame:IsShown() end
local function Open(items)
    env.Fire("LOOT_CLOSED")
    loot = items
    env.Fire("LOOT_OPENED")
end

-- 1.
Open({ { id = 901, name = "Gnoll Paw" } })
suite.check("quest loot with no price: the popup shows", Showing())
suite.check("it offers the quest item", Swap.loot and Swap.loot.itemID == 901 and Swap.loot.quest)
suite.check("against the cheapest item", Swap.pick and Swap.pick.entry.itemID == 702)
suite.check("the row says Quest item", env.Plain(Swap.newRow.worth:GetText() or "") == "Quest item",
    tostring(Swap.newRow.worth:GetText()))
suite.check("the words say it's for a quest",
    env.Plain(Swap.say:GetText() or ""):find("quest", 1, true) ~= nil, tostring(Swap.say:GetText()))

-- 2.
Open({ { id = 801, name = "Ringed Helm", quality = 2 }, { id = 901, name = "Gnoll Paw" } })
suite.check("quest loot wins over loot worth more", Swap.loot and Swap.loot.itemID == 901 and Swap.loot.slot == 2)

-- 3.
Open({ { id = 902, name = "Murloc Fin", questFlag = true } })
suite.check("the game's quest flag counts", Showing() and Swap.loot.itemID == 902)
local realFor = ns.Quests.For
ns.Quests.For = function(_, id) if id == 903 then return { need = 2, quests = { "Notes" } } end end
Open({ { id = 903, name = "Strange Note" } })
suite.check("an open quest's item counts", Showing() and Swap.loot.itemID == 903)
ns.Quests.For = realFor

-- 4. and 5.
local realGroups = ns.Verdicts.Groups
local function OnlyGroup(verdict)
    local entry = ns.Bags.slots and select(2, next(ns.Bags.slots))
    ns.Verdicts.Groups = function()
        return { { verdict = verdict, rows = { { name = "Ruined Pelt", unit = 5,
            slots = { { bag = 0, slot = 2, itemID = 702, count = 1, key = entry and entry.key } } } } } }
    end
end
OnlyGroup("wait")
Open({ { id = 901, name = "Gnoll Paw" } })
suite.check("nothing to sell: the cheapest Wait item goes", Showing() and Swap.pick and Swap.pick.entry.itemID == 702)
Open({ { id = 801, name = "Ringed Helm", quality = 2 } })
suite.check("ordinary loot never pushes out a Wait item", not Showing())
for _, verdict in ipairs({ "keep", "mail", "bank", "look" }) do
    OnlyGroup(verdict)
    Open({ { id = 901, name = "Gnoll Paw" } })
    suite.check(verdict .. " is never offered", not Showing())
end
ns.Verdicts.Groups = realGroups

-- 6.
Open({ { id = 804, name = "Old Stone", quality = 0 } })
suite.check("ordinary loot worth less: nothing", not Showing())
Open({ { id = 801, name = "Ringed Helm", quality = 2 } })
suite.check("ordinary loot worth more: shows as before", Showing() and not Swap.loot.quest)
suite.check("with the usual words",
    env.Plain(Swap.say:GetText() or ""):find("worth more", 1, true) ~= nil)

suite.done()
