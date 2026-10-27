-- Free bag space: a number on the backpack button, white, amber at 8 or
-- fewer, red at 3 or fewer. Profession and reagent bags are listed on the
-- tooltip and left out of the number. Nothing is written on the button.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("freespace")

local ns = env.Load()
env.FakeBags({})

-- Backpack 16 slots, two bags of 10, a herb bag of 12 and a reagent bag of 8.
local slots = { [0] = 16, [1] = 10, [2] = 10, [3] = 12, [5] = 8 }
local free = { [0] = 4, [1] = 2, [2] = 1, [3] = 9, [5] = 6 }
local family = { [3] = 32 }
_G.Enum = { BagIndex = { ReagentBag = 5 } }
_G.C_Container.GetContainerNumSlots = function(bag) return slots[bag] or 0 end
_G.C_Container.GetContainerNumFreeSlots = function(bag) return free[bag] or 0, family[bag] or 0 end
_G.C_Container.GetBagName = function(bag)
    return ({ [0] = "Backpack", [1] = "Small Brown Pouch", [2] = "Linen Bag",
        [3] = "Herb Pouch", [5] = "Woolen Reagent Pouch" })[bag]
end

local button = env.Stub({ _shown = true })
local writes = {}
setmetatable(button, nil)
_G.MainMenuBarBackpackButton = setmetatable({}, {
    __index = button,
    __newindex = function(_, key) writes[#writes + 1] = key end,
})
_G.MainMenuBarBackpackButtonCount = nil

env.Enable(ns)
local FreeSpace = ns.FreeSpace

local read = FreeSpace.Read()
suite.check("only bags that take anything count", read.free == 7 and read.total == 36,
    tostring(read.free) .. " of " .. tostring(read.total))
suite.check("the herb bag and the reagent bag are listed apart", #read.special == 2
    and read.special[1].name == "Herb Pouch" and read.special[2].name == "Woolen Reagent Pouch")
suite.check("each counted bag is listed", #read.bags == 3 and read.bags[1].name == "Backpack")

suite.check("9 free is plenty", FreeSpace.Level(9) == "plenty")
suite.check("8 free is low", FreeSpace.Level(8) == "low")
suite.check("3 free is out", FreeSpace.Level(3) == "out")
suite.check("0 free is out", FreeSpace.Level(0) == "out")

suite.check("the number goes on the backpack button", FreeSpace:Attach() == true
    and FreeSpace.frame._parent == _G.MainMenuBarBackpackButton)
FreeSpace.frame.IsVisible = function() return true end

env.Fire("BAG_UPDATE_DELAYED")
local text = FreeSpace.frame.text
suite.check("it shows the free slots", text:GetText() == "7", text:GetText())
local c = text._color
suite.check("7 free is amber", c and c[1] == 1 and c[2] == 0.69)

free[0] = 12
env.Fire("BAG_UPDATE_DELAYED")
suite.check("it follows the bags", text:GetText() == "15")
suite.check("15 free is white", text._color[2] == 1)

-- The text is set again only when the number or its colour changes.
local sets = 0
local realSet = text.SetText
text.SetText = function(self, value) sets = sets + 1; return realSet(self, value) end
env.Fire("BAG_UPDATE_DELAYED")
suite.check("nothing redrawn when nothing changed", sets == 0)
text.SetText = realSet

-- Hidden bar: nothing is read until it shows again.
local reads = 0
local realFree = _G.C_Container.GetContainerNumFreeSlots
_G.C_Container.GetContainerNumFreeSlots = function(bag) reads = reads + 1; return realFree(bag) end
FreeSpace.frame.IsVisible = function() return false end
free[0] = 0
env.Fire("BAG_UPDATE_DELAYED")
suite.check("nothing is read while the bag bar is hidden", reads == 0)
FreeSpace.frame.IsVisible = function() return true end
FreeSpace.frame:GetScript("OnShow")(FreeSpace.frame)
suite.check("showing again reads what it missed", text:GetText() == "3" and text._color[2] == 0.28)

-- The game's own count wins, so there are never two numbers.
_G.MainMenuBarBackpackButtonCount = env.Stub({ _shown = true, _text = "(3)" })
env.Fire("BAG_UPDATE_DELAYED")
suite.check("stands down while the game shows its own count", text:GetText() == "")
_G.MainMenuBarBackpackButtonCount = nil
env.Fire("BAG_UPDATE_DELAYED")
suite.check("and comes back when it goes", text:GetText() == "3")

-- A game number that is not the free slots (a hunter's ammo) is put out of
-- sight with SetAlpha, never hidden, and ours stands in for it.
local alpha
local gameCount = env.Stub({ _shown = true, _text = "1307" })
gameCount.SetAlpha = function(_, value) alpha = value end
_G.MainMenuBarBackpackButtonCount = gameCount
env.Fire("BAG_UPDATE_DELAYED")
suite.check("a game number that is not the free slots gives way", text:GetText() == "3", text:GetText())
suite.check("and is put out of sight with SetAlpha", alpha == 0)
_G.MainMenuBarBackpackButtonCount = nil
FreeSpace:Refresh()
suite.check("and comes back when it goes", alpha == 1)

-- An ammo bag's count sits on its own bag bar button, not the backpack.
local realBag = ns.Ammo.Bag
ns.Ammo.Bag = function() return { bag = 3 } end
_G.CharacterBag2Slot = env.Stub({ _shown = true })
local realInfo = _G.C_Container.GetContainerItemInfo
_G.C_Container.GetContainerItemInfo = function(bag, slot)
    if bag == 3 and slot <= 2 then return { stackCount = 200 } end
end
FreeSpace:Refresh()
suite.check("the ammo count sits on the ammo bag's button", FreeSpace.ammoFrame
    and FreeSpace.ammoText:GetText() == "400", FreeSpace.ammoText and FreeSpace.ammoText:GetText())
ns.Ammo.Bag = function() return nil end
FreeSpace:Refresh()
suite.check("and goes when there is no ammo bag", FreeSpace.ammoText:GetText() == "")
ns.Ammo.Bag = realBag
_G.C_Container.GetContainerItemInfo = realInfo
_G.CharacterBag2Slot = nil

-- The tooltip lists each bag after the game's lines.
GameTooltip.GetOwner = function() return _G.MainMenuBarBackpackButton end
local doubles = {}
GameTooltip.AddDoubleLine = function(_, left, right) doubles[#doubles + 1] = left .. " = " .. right end
GameTooltip._lines = {}
button._scripts.OnEnter(_G.MainMenuBarBackpackButton)
local lines = table.concat(GameTooltip._lines, "|")
suite.check("the tooltip gives the total", lines:find("Free bag space: 3 of 36", 1, true) ~= nil, lines)
suite.check("and each bag", doubles[1] == "Backpack = 0 of 16 free"
    and doubles[4] == "Herb Pouch (only some items) = 9 of 12 free", table.concat(doubles, "; "))

-- Off: the number goes, and stays gone.
ns.HandleSlash("freespace")
suite.check("/bbutler freespace turns it off", ns.db.freeSpace == false and text:GetText() == "")
env.Fire("BAG_UPDATE_DELAYED")
suite.check("and it stays off", text:GetText() == "")
ns.HandleSlash("freespace")
suite.check("and back on", ns.db.freeSpace == true and text:GetText() == "3")

suite.check("nothing was written on the game's button", #writes == 0, table.concat(writes, ","))

-- A client with no backpack button, or a secret count, is not an error.
local ns2 = env.Load()
env.FakeBags({})
_G.MainMenuBarBackpackButton = nil
env.Enable(ns2)
env.Fire("BAG_UPDATE_DELAYED")
suite.check("no backpack button is not an error", ns2.FreeSpace.frame == nil)
_G.C_Container.GetContainerNumFreeSlots = function() error("secret") end
suite.check("an unreadable count is nil", ns2.FreeSpace.Read() == nil)
suite.check("the probe still answers", type(ns2.FreeSpace:ProbeText()) == "string")
-- Era: no reagent bag, and a ReagentBag that is also the first bank bag
-- is the bank, never carried.
_G.Enum = { BagIndex = { ReagentBag = 5, BankBag_1 = 5 } }
suite.check("a reagent number shared with the bank is not carried", ns2.Bags.ReagentBag() == nil
    and #ns2.Bags.BagIDs() == 5)
_G.Enum = { BagIndex = { ReagentBag = 5, BankBag_1 = 6 } }
suite.check("a real reagent bag is carried", ns2.Bags.ReagentBag() == 5 and #ns2.Bags.BagIDs() == 6)
_G.Enum = nil

suite.done()
