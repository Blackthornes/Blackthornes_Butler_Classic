-- The Bags window: Butler's own bag window, in the house look, laid out by
-- what Butler says to do with each item (the owner said build it,
-- 2026-10-19).
--
-- What must hold:
--   1. Off unless ticked: nothing hooked, nothing veiled, nothing saved.
--   2. Turned on, the game's bags are veiled (see-through), never hidden.
--   3. Opening the bags opens it; a toggle flips it once a frame.
--   4. What To Do groups by Butler's verdicts; Item Type by kind; One Grid
--      is every slot in bag order, empty ones too, with each bag that
--      takes only some things on rows of its own.
--   5. Search and the chips dim what does not match.
--   6. Settings and /bbutler bags set the same saved values.
--   7. Turned off, the veil comes off and the window goes.
--   8. Full bags: the trash can and its red glow sit on the cheapest
--      stack's square in this window, never on the game's veiled bags.
--   9. The foot shows this character's gold, then every character's.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bagwindow")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 801, name = "Broken Fang", quality = 0, price = 12, count = 3 },
    { bag = 0, slot = 2, id = 802, name = "Linen Cloth", quality = 1, price = 13, count = 20, class = 7 },
    { bag = 0, slot = 3, id = 803, name = "Old Letter", quality = 1, price = 1, quest = "item" },
    { bag = 0, slot = 5, id = 804, name = "Iron Sword", quality = 1, price = 300, class = 2, equipLoc = "INVTYPE_WEAPON" },
})

-- A post-hook, as the game's hooksecurefunc runs one.
_G.hooksecurefunc = function(a, b, c)
    local owner, name, fn = _G, a, b
    if type(a) == "table" then owner, name, fn = a, b, c end
    local before = owner[name]
    owner[name] = function(...)
        local result = before(...)
        fn(...)
        return result
    end
end
_G.ToggleAllBags = function() end
_G.OpenAllBags = function() end
_G.CloseAllBags = function() end

-- The game's combined bag window, shown.
_G.ContainerFrameCombinedBags = env.Stub({ _shown = true })

env.Enable(ns)

-- From here timers wait for the end of the frame, as the game's do, so a
-- burst of bag calls settles once.
local queued = {}
_G.C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
local function EndFrame()
    while #queued > 0 do
        local now = queued
        queued = {}
        for _, fn in ipairs(now) do fn() end
    end
end

local BagWindow, BagView = ns.BagWindow, ns.BagView

-- 1. Off unless ticked.
suite.check("it starts off", not BagWindow:On())
suite.check("nothing is saved for it yet", ns.db.bagWindow == nil)
_G.OpenAllBags(); EndFrame()
suite.check("opening the bags does nothing while it is off", not BagWindow:IsShown())
suite.check("the game's bags are left alone", not ns.Veil:Covers(_G.ContainerFrameCombinedBags))

-- 2. On: the game's bags are veiled, never hidden.
ns.HandleSlash("bags on"); EndFrame()
suite.check("/bbutler bags on turns it on", BagWindow:On() and ns.db.bagWindow == true)
suite.check("and says so", env.ChatText():find("Butler Bags is on.", 1, true) ~= nil)
suite.check("the game's bags go under the veil", ns.Veil:Covers(_G.ContainerFrameCombinedBags))
suite.check("but are never hidden", _G.ContainerFrameCombinedBags:IsShown())
suite.check("it covers the game's bags", BagWindow:Covering())

-- 3. Opening and toggling.
_G.OpenAllBags(); EndFrame()
suite.check("opening the bags opens it", BagWindow:IsShown())
_G.ToggleAllBags(); EndFrame()
suite.check("a toggle closes it", not BagWindow:IsShown())
_G.ToggleAllBags(); EndFrame()
suite.check("and opens it again", BagWindow:IsShown())
_G.CloseAllBags(); EndFrame()
suite.check("closing the bags closes it", not BagWindow:IsShown())
BagWindow:Show(); EndFrame()

-- 4. Grouping.
ns.Bags:Scan(); EndFrame()
local sections = BagView:Sections("todo")
suite.check("What To Do has sections", #sections > 0)
local sellSection
for _, section in ipairs(sections) do
    if section.verdict == "sell" then sellSection = section end
end
suite.check("the grey goes under Sell", sellSection ~= nil and sellSection.places[1].entry.itemID == 801)
suite.check("with what the group is worth", sellSection and sellSection.worth and sellSection.worth > 0)

local byType = {}
for _, section in ipairs(BagView:Sections("type")) do byType[section.key] = section end
suite.check("Item Type puts the quest item under QUEST", byType.quest and byType.quest.places[1].entry.itemID == 803)
suite.check("the cloth under TRADE GOODS", byType.trade and byType.trade.places[1].entry.itemID == 802)
suite.check("the sword under WEAPONS", byType.weapons and byType.weapons.places[1].entry.itemID == 804)

local grid = BagView:Sections("grid")
suite.check("One Grid is one section", #grid == 1)
suite.check("holding every slot, empty ones too", grid[1] and #grid[1].places == 16)
suite.check("in bag order", grid[1] and grid[1].places[4].entry == nil and grid[1].places[5].entry.itemID == 804)

-- Empty Slots: each way of grouping keeps its own choice, and nothing is
-- saved until one is changed.
do
    local function Last(list) return list[#list] end
    suite.check("What To Do starts without empty slots", not BagView:ShowsEmpty("todo")
        and Last(BagView:Sections("todo")).key ~= "empty")
    suite.check("One Grid starts with them, as before", BagView:ShowsEmpty("grid"))
    suite.check("nothing is saved for it yet", ns.db.bagEmptySlots == nil)
    BagView:SetShowsEmpty(true, "todo")
    local last = Last(BagView:Sections("todo"))
    suite.check("ticked, What To Do ends with EMPTY SLOTS", last.key == "empty" and last.label == "EMPTY SLOTS")
    suite.check("holding only the empty slots", last.places[1] and last.places[1].entry == nil)
    suite.check("Item Type keeps its own choice", Last(BagView:Sections("type")).key ~= "empty")
    BagView:SetShowsEmpty(true, "type")
    suite.check("and can show them too", Last(BagView:Sections("type")).key == "empty")
    BagView:SetShowsEmpty(false, "grid")
    local packed = BagView:Sections("grid")
    local gaps = false
    for _, place in ipairs(packed[1] and packed[1].places or {}) do
        if not place.entry then gaps = true end
    end
    suite.check("unticked, One Grid packs the items with no gaps", packed[1] and not gaps and #packed[1].places < 16)
    suite.check("What To Do is left as it was", BagView:ShowsEmpty("todo"))
    ns.db.bagEmptySlots = nil
end

-- A bag that takes only some things (a mining bag) gets rows of its own,
-- so what Sort puts in it is not lost in the middle of the grid.
do
    local read = ns.FreeSpace.Read
    local slots = ns.BagView.AllSlots
    ns.FreeSpace.Read = function() return { free = 0, total = 0, bags = {}, special = { { bag = 1 } } } end
    ns.BagView.AllSlots = function()
        return { { bag = 0, slot = 1 }, { bag = 0, slot = 2 }, { bag = 1, slot = 1, entry = { itemID = 2901 } },
            { bag = 1, slot = 2 }, { bag = 2, slot = 1 } }
    end
    local split = BagView:Sections("grid")
    suite.check("a mining bag starts its own rows", #split == 2 and split[2].key == "grid:1")
    suite.check("the bags that take anything stay together", split[1] and #split[1].places == 3
        and split[1].places[3].bag == 2)
    suite.check("with what is in the mining bag", split[2] and split[2].places[1].entry.itemID == 2901)
    ns.FreeSpace.Read, ns.BagView.AllSlots = read, slots
end

-- 5. Search.
suite.check("search finds by name", BagView.Matches("Linen Cloth", 802, "linen"))
suite.check("in any case", BagView.Matches("Linen Cloth", 802, BagView.Fold("  LINEN ")))
suite.check("or by item ID", BagView.Matches("Linen Cloth", 802, "802"))
suite.check("and skips what does not match", not BagView.Matches("Linen Cloth", 802, "sword"))

-- 6. Settings and the command set the same values.
BagView:SetGroupBy("grid")
suite.check("Group By is saved", ns.db.bagGroupBy == "grid")
BagView:SetGroupBy("nonsense")
suite.check("a word it does not know falls back", BagView:GroupBy() == "todo" or BagView:GroupBy() == "grid")
BagView:SetItemSize("large")
suite.check("Item Size is saved", ns.db.bagItemSize == "large" and BagView:Pixels() > 37)
BagView:SetItemLevelOn(false)
suite.check("Item Level on Gear can be turned off", ns.db.bagItemLevel == false and not BagView:ItemLevelOn())
BagView:SetNewGlowOn(false)
suite.check("New Item Glow can be turned off", ns.db.bagNewGlow == false and not BagView:NewGlowOn())

ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
suite.check("Settings has the Use Butler Bags box", controls.bagWindow ~= nil)
suite.check("and it shows what is saved", controls.bagWindow:GetChecked() == true)

-- Every way of laying it out draws without a fault, in each tab.
for _, groupBy in ipairs({ "todo", "type", "grid" }) do
    BagView:SetGroupBy(groupBy)
    BagWindow:Changed(true); EndFrame()
end
suite.check("the window still shows after redrawing", BagWindow:IsShown())
BagWindow:SetTab("bank"); EndFrame()
suite.check("the Bank tab draws", BagWindow.tab == "bank")
BagWindow:SetTab("everyone"); EndFrame()
suite.check("the Everyone tab draws", BagWindow.tab == "everyone")
BagWindow:SetTab("bags"); EndFrame()

-- 8. The trash can on this window's squares.
do
    local freeSlots = _G.C_Container.GetContainerNumFreeSlots
    _G.C_Container.GetContainerNumFreeSlots = function() return 0, 0 end
    BagWindow:Changed(true); EndFrame()
    local Trash = ns.Trash
    local square = BagWindow:ButtonFor(0, 1)
    suite.check("the cheapest stack has a square", square ~= nil)
    suite.check("full bags show the can", Trash.can ~= nil and Trash.can:IsShown())
    suite.check("on that square", Trash.can and Trash.can:GetParent() == square and square ~= nil)
    suite.check("the red glow lies round it too", Trash.glow ~= nil and Trash.glow:IsShown()
        and Trash.glow:GetParent() == square)
    BagWindow:SetTab("bank"); EndFrame()
    suite.check("the Bank tab has no squares for it", BagWindow:ButtonFor(0, 1) == nil)
    suite.check("so the can goes", not Trash.can:IsShown())
    BagWindow:SetTab("bags"); EndFrame()
    suite.check("and comes back on Your bags", Trash.can:IsShown() and Trash.can:GetParent() == square)
    _G.C_Container.GetContainerNumFreeSlots = freeSlots
    BagWindow:Changed(true); EndFrame()
    suite.check("a free slot puts it away", not Trash.can:IsShown())
end

-- 7. Off again.
ns.HandleSlash("bags off"); EndFrame()
suite.check("/bbutler bags off turns it off", not BagWindow:On() and ns.db.bagWindow == false)
suite.check("the veil comes off the game's bags", not ns.Veil:Covers(_G.ContainerFrameCombinedBags))
suite.check("and the window goes", not BagWindow:IsShown())
_G.OpenAllBags(); EndFrame()
suite.check("opening the bags leaves it closed", not BagWindow:IsShown())

-- Sort plays the game's own bag sort sound, by ID, then sorts.
do
    local played, sorted, saveSort, savePlay = {}, false, nil, _G.PlaySound
    _G.C_Container = _G.C_Container or {}
    saveSort = _G.C_Container.SortBags
    _G.C_Container.SortBags = function() sorted = true end
    _G.PlaySound = function(id, channel) played[#played + 1] = { id, channel } end
    BagWindow:Sort()
    suite.check("Sort plays the game's bag sort sound", #played == 1 and played[1][1] == 73933)
    suite.check("on the sound effects channel, as the game's button", played[1] and played[1][2] == nil)
    suite.check("and sorts the bags", sorted)
    _G.SOUNDKIT = { UI_BAG_SORTING_01 = 5555 }
    suite.check("the client's own sound name wins", BagWindow.SortSound() == 5555)
    _G.SOUNDKIT = nil
    _G.C_Container.SortBags, _G.PlaySound = saveSort, savePlay
end

-- The coin is for vendor items only, never for auction items.
do
    local saveJudge, saveAsk = ns.Verdicts.VerdictOf, ns.Sisters.AskAll
    local verdictFor = {}
    ns.Verdicts.VerdictOf = function(_, entry) return verdictFor[entry.itemID] end
    ns.Sisters.AskAll = function() return {} end
    ns.Verdicts.version = (ns.Verdicts.version or 0) + 1
    verdictFor[9001], verdictFor[9002] = "sell", "auction"
    local vendorItem = ns.BagView:Marks({ itemID = 9001, bag = 0, slot = 30, count = 1 })
    local auctionItem = ns.BagView:Marks({ itemID = 9002, bag = 0, slot = 31, count = 1 })
    suite.check("a vendor item gets the coin", vendorItem.vendor == true)
    suite.check("an auction item gets no coin", auctionItem.vendor == false)
    suite.check("the To Sell chip still finds both", vendorItem.sell and auctionItem.sell)
    ns.Verdicts.VerdictOf, ns.Sisters.AskAll = saveJudge, saveAsk
    ns.Verdicts.version = ns.Verdicts.version + 1
end

-- 9. The foot: this character's gold first, then every character's.
do
    local saveMoney, saveHoldings = _G.GetMoney, ns.Errands.Holdings
    _G.GetMoney = function() return 864050 end
    ns.Errands.Holdings = function()
        return { { isCurrent = true, gold = 1 }, { gold = 1000000 } }
    end
    BagWindow:UpdateFoot()
    local mine = BagWindow.myGoldLabel:GetText() or ""
    local all = BagWindow.goldLabel:GetText() or ""
    suite.check("the foot says this character's gold", mine:find("Gold: ", 1, true) == 1)
    suite.check("from the purse now", BagView.MyGold() == 864050)
    suite.check("and every character's after it", all:find("All characters: ", 1, true) == 1)
    suite.check("adding the purse to the others", BagView.Gold() == 1864050)
    -- Only this realm and side, and never another account's characters.
    ns.Errands.Holdings = function()
        local me = { isCurrent = true, gold = 1, realm = "Home", faction = "Horde" }
        return {
            me,
            { key = "alt", gold = 33, realm = "Home", faction = "Horde" },
            { key = "far", gold = 43928, realm = "Away", faction = "Alliance", linked = "Shared-Away" },
            { key = "shared", gold = 500, realm = "Home", faction = "Horde", linked = "Shared-Home" },
            { key = "other side", gold = 700, realm = "Home", faction = "Alliance" },
            { key = "other realm", gold = 900, realm = "Away", faction = "Horde" },
            { key = "old", gold = 999, realm = "Home", faction = "Horde", playing = true },
        }, me
    end
    suite.check("only this realm and side's own characters count", BagView.Gold() == 864050 + 33)
    ns.Errands.Holdings = function() return nil end
    BagWindow:UpdateFoot()
    suite.check("without Tradeskills this character's gold still shows",
        (BagWindow.myGoldLabel:GetText() or "") ~= "" and (BagWindow.goldLabel:GetText() or "") == "")
    _G.GetMoney, ns.Errands.Holdings = saveMoney, saveHoldings
    BagWindow:UpdateFoot()
end

-- The probe line is read without raising.
suite.check("the probe says what it found", type(BagWindow:ProbeText()) == "string")

-- Suites share one Lua state: take the game's bag calls away again.
_G.hooksecurefunc, _G.ToggleAllBags, _G.OpenAllBags, _G.CloseAllBags = nil, nil, nil, nil
_G.ContainerFrameCombinedBags = nil

suite.done()
