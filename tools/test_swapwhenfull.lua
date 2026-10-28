-- Swap When Full: with the bags full and loot worth more than the cheapest
-- item, a popup beside the loot window offers to swap them (the owner said
-- build it, 2026-10-28).
--
-- What must hold:
--   1. Off unless ticked; Settings turns it on.
--   2. Nothing while the bags have room, or with no loot window.
--   3. Full bags and loot worth more: the popup names both, worth and all.
--   4. Loot worth less, or loot that stacks onto a stack with room: nothing.
--   5. Swap destroys the cheap item in one click (the owner, 2026-10-28:
--      ticking the box is the yes), and only the item it named.
--   6. Once its slot is empty, Butler loots the item it named.
--   7. A slot that changed under it is left alone, nothing deleted.
--   8. Not Now hides it until the next loot window; a fight hides it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("swapwhenfull")

local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 701, name = "Broken Fang", quality = 0, price = 12, count = 3 },
    { bag = 0, slot = 2, id = 702, name = "Ruined Pelt", quality = 0, price = 5 },
})
fake.info[801] = { id = 801, name = "Ringed Helm", quality = 2, price = 300, stack = 1 }
fake.info[802] = { id = 802, name = "Tiny Pebble", quality = 0, price = 1, stack = 20 }

local freeSlots = 0
_G.C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and freeSlots or 0, 0 end
local picked, deleted = {}, 0
local holding, heldID, heldFrom = nil, nil, nil
local swapItem = nil
_G.C_Container.PickupContainerItem = function(bag, slot)
    picked[#picked + 1] = bag .. ":" .. slot
    if holding then holding, heldID, heldFrom = nil, nil, nil; return end
    local item = swapItem or (fake.bags[bag] and fake.bags[bag][slot])
    if item then holding, heldID, heldFrom = "item", item.id, { bag, slot } end
end
_G.DeleteCursorItem = function()
    deleted = deleted + 1
    if heldFrom then fake.bags[heldFrom[1]][heldFrom[2]] = nil end
    holding, heldID, heldFrom = nil, nil, nil
end
_G.GetCursorInfo = function() return holding, heldID end

local loot = {}
local looted = {}
local function Link(id, name) return ("|cff1eff00|Hitem:%d::::::::|h[%s]|h|r"):format(id, name) end
_G.GetNumLootItems = function() return #loot end
_G.GetLootSlotType = function() return 1 end
_G.GetLootSlotLink = function(slot) local item = loot[slot]; return item and Link(item.id, item.name) end
_G.GetLootSlotInfo = function(slot)
    local item = loot[slot]
    if not item then return nil end
    return 134400, item.name, item.count or 1, nil, item.quality or 1, false
end
_G.LootSlot = function(slot) looted[#looted + 1] = slot end
_G.LootFrame = env.Stub({ _shown = true })

env.Enable(ns)
local Swap = ns.SwapWhenFull
env.Fire("PLAYER_ENTERING_WORLD")

local function Showing() return Swap.frame ~= nil and Swap.frame:IsShown() end
local function Open(items)
    loot = items
    env.Fire("LOOT_OPENED")
end

-- 1.
Open({ { id = 801, name = "Ringed Helm", quality = 2 } })
suite.check("off unless ticked", ns.db.swapWhenFull ~= true and not Showing())
env.Fire("LOOT_CLOSED")
ns.HandleSlash("settings")
local box = ns.SettingsUI.controls.swapWhenFull
suite.check("Settings has the box, unticked", box ~= nil and not box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("ticking it turns it on", ns.db.swapWhenFull == true)

-- 2.
freeSlots = 1
Open({ { id = 801, name = "Ringed Helm", quality = 2 } })
suite.check("nothing while the bags have room", not Showing())
env.Fire("LOOT_CLOSED")
freeSlots = 0
env.Fire("BAG_UPDATE_DELAYED")
suite.check("nothing with no loot window", not Showing())

-- 3.
Open({ { id = 802, name = "Tiny Pebble", quality = 0 }, { id = 801, name = "Ringed Helm", quality = 2 } })
suite.check("full bags and better loot: the popup shows", Showing())
suite.check("it offers the helm", Swap.loot and Swap.loot.itemID == 801 and Swap.loot.slot == 2)
suite.check("against the cheapest item", Swap.pick and Swap.pick.entry.itemID == 702)
local note = env.Plain(Swap.note:GetText() or "")
suite.check("the note names both", note:find("Ruined Pelt", 1, true) ~= nil and note:find("Ringed Helm", 1, true) ~= nil, note)
suite.check("beside the loot window", Swap.frame._point and Swap.frame._point[2] == _G.LootFrame)
env.Fire("LOOT_CLOSED")
suite.check("closing the loot window hides it", not Showing())

-- 4.
Open({ { id = 802, name = "Tiny Pebble", quality = 0 } })
suite.check("loot worth less: nothing", not Showing())
env.Fire("LOOT_CLOSED")
fake.info[703] = { id = 703, name = "Shiny Rock", quality = 1, price = 400, stack = 20 }
fake.Put({ bag = 0, slot = 3, id = 703, name = "Shiny Rock", quality = 1, price = 400, count = 2, stack = 20 })
env.Fire("BAG_UPDATE_DELAYED")
Open({ { id = 703, name = "Shiny Rock", quality = 1 } })
suite.check("loot that fits on a stack: nothing", not Showing())
env.Fire("LOOT_CLOSED")
fake.bags[0][3] = nil

-- 5.
Open({ { id = 801, name = "Ringed Helm", quality = 2 } })
Swap.swapButton:GetScript("OnClick")(Swap.swapButton)
suite.check("Swap picks the cheap item up", picked[1] == "0:2", tostring(picked[1]))
suite.check("and destroys it in the same click", deleted == 1 and fake.bags[0][2] == nil)
suite.check("the popup goes", not Showing())

-- 6.
env.Fire("BAG_UPDATE_DELAYED")
suite.check("its slot is empty: the helm is looted", looted[1] == 1, tostring(looted[1]))
suite.check("only once", #looted == 1 and Swap.pending == nil)
env.Fire("LOOT_CLOSED")
fake.Put({ bag = 0, slot = 2, id = 702, name = "Ruined Pelt", quality = 0, price = 5 })
env.Fire("BAG_UPDATE_DELAYED")

-- 7.
looted, picked = {}, {}
Open({ { id = 801, name = "Ringed Helm", quality = 2 } })
swapItem = { id = 705 }
Swap:Take()
swapItem = nil
suite.check("a changed slot: nothing deleted", deleted == 1, tostring(deleted))
suite.check("what was picked up is put back", holding == nil and #picked == 2, table.concat(picked, ","))
suite.check("and nothing looted", #looted == 0 and Swap.pending == nil)
env.Fire("LOOT_CLOSED")

-- 8.
Open({ { id = 801, name = "Ringed Helm", quality = 2 } })
suite.check("shows again", Showing())
Swap.laterButton:GetScript("OnClick")(Swap.laterButton)
env.Fire("BAG_UPDATE_DELAYED")
suite.check("Not Now hides it for this loot window", not Showing())
env.Fire("LOOT_CLOSED")
Open({ { id = 801, name = "Ringed Helm", quality = 2 } })
suite.check("back at the next one", Showing())
env.Fire("PLAYER_REGEN_DISABLED")
suite.check("hidden in a fight", not Showing())
suite.check("nothing else was deleted", deleted == 1)

suite.done()
