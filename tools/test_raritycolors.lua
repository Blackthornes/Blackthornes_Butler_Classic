-- Item names show their rarity colour (the owner: "Item names should show
-- their rarity color always"). A Jobs line read "Craft 2 Truefaith Gloves"
-- in plain white for a green.
--
-- What must hold:
--   1. Items:ColorName puts only the name in its quality's colour: Common
--      white, Uncommon green.
--   2. A quality is kept once known; an item not loaded yet stays plain,
--      is asked for, and is coloured once GET_ITEM_INFO_RECEIVED says so.
--   3. A quality in hand (a bag slot's) wins, and a link stays as it is.
--   4. The Jobs line colours the name and keeps the rest of its words.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("raritycolors")

local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 2589, name = "Linen Cloth", quality = 1, price = 13, count = 5 },
    { bag = 0, slot = 2, id = 10000, name = "Truefaith Gloves", quality = 2, price = 900, count = 1 },
})
local names = { [2589] = "Linen Cloth", [10000] = "Truefaith Gloves" }
_G.C_Item.GetItemNameByID = function(id) return names[id] end

local Items, Jobs, UI = ns.Items, ns.Jobs, ns.UI
Items:Forget()

local WHITE, GREEN = "|cffffffff", "|cff1eff00"

-- 1. Colours by quality.
suite.check("common is white", Items:ColorName("Linen Cloth", 2589) == WHITE .. "Linen Cloth|r",
    Items:ColorName("Linen Cloth", 2589))
suite.check("uncommon is green", Items:ColorName("Truefaith Gloves", 10000) == GREEN .. "Truefaith Gloves|r",
    Items:ColorName("Truefaith Gloves", 10000))
suite.check("poor is grey", Items.QualityHex(0) == "ff9d9d9d", Items.QualityHex(0))
suite.check("rare is blue", Items.QualityHex(3) == "ff0070dd", Items.QualityHex(3))
suite.check("epic is purple", Items.QualityHex(4) == "ffa335ee", Items.QualityHex(4))

-- 2. Kept once known; a miss stays a miss and is asked for.
suite.check("the quality is kept", Items.qualityMemo[10000] == 2)
suite.check("an item not loaded stays plain", Items:ColorName("Item 777", 777) == "Item 777")
suite.check("and is asked for", fake.requested == 777 and Items.waiting[777] == true)
suite.check("a miss is not kept", Items.qualityMemo[777] == nil)
fake.info[777] = { id = 777, name = "Silk Cloth", quality = 1, price = 37 }
names[777] = "Silk Cloth"
env.Fire("GET_ITEM_INFO_RECEIVED", 777)
suite.check("once it loads it is coloured", Items:ColorName("Silk Cloth", 777) == WHITE .. "Silk Cloth|r")

-- 3. A quality in hand wins; a link is the game's own colour.
suite.check("a known quality wins", Items:ColorName("Linen Cloth", 2589, 3) == "|cff0070ddLinen Cloth|r")
local link = "|cff1eff00|Hitem:10000::::::::|h[Truefaith Gloves]|h|r"
suite.check("a link stays as it is", Items:ColorName(link, 10000) == link)
suite.check("nothing to colour stays nothing", Items:ColorName(nil, 10000) == nil)

-- 4. The Jobs line.
local step = { kind = "craft", recipeID = 1, itemID = 10000, name = "Truefaith Gloves", count = 2,
    forNames = {}, ready = true, missing = {} }
local title = Jobs.StepText(step)
suite.check("a craft's title colours the item", title == "Craft 2 " .. GREEN .. "Truefaith Gloves|r", title)
local mail = { kind = "mail", to = "Ana Blackthorne", items = { { itemID = 2589, count = 6 } } }
local _, detail = Jobs.StepText(mail)
suite.check("a mail's line colours the item and keeps its words",
    detail == "6 " .. WHITE .. "Linen Cloth|r. At a mailbox, Fill mail adds it.", detail)
local row = CreateFrame("Frame", nil, UIParent)
UI.CreateRow(row)
UI.DrawRow(row, { type = "job", step = step })
suite.check("the row shows it", row.name:GetText() == "Craft 2 " .. GREEN .. "Truefaith Gloves|r",
    row.name:GetText())
suite.check("colour codes take no room", ns.Theme.TextWidth("small", title)
    == ns.Theme.TextWidth("small", "Craft 2 Truefaith Gloves"))

-- 5. A stack's count sits on its icon's corner, not after its name.
UI.DrawRow(row, { type = "item", name = "Linen Cloth", count = 20, quality = 1, worth = 260 })
suite.check("the name has no count", row.name:GetText() == "Linen Cloth", row.name:GetText())
suite.check("the icon shows 20", ns.ItemLook.CountShown(row.icon) == 20)
UI.DrawRow(row, { type = "item", name = "Truefaith Gloves", count = 1, quality = 2, worth = 900 })
suite.check("one shows no number", ns.ItemLook.CountShown(row.icon) == nil)
UI.DrawRow(row, { type = "job", step = step })
suite.check("a job row shows no count", ns.ItemLook.CountShown(row.icon) == nil)

-- 6. Each verdict gets its mark and colour; the words stay.
local Marks = ns.Marks
local cases = {
    { "sell", "sell" }, { "mail", "mail" }, { "keep", "keep" }, { "disenchant", "disenchant" },
    { "bank", "bank" }, { "look", "look" }, { "auction", "list" }, { "wait", "waiting" },
    { "craft", "craft" },
}
for _, case in ipairs(cases) do
    UI.DrawRow(row, { type = "item", name = "Linen Cloth", count = 1, quality = 1,
        verdict = case[1], reason = "Words" })
    suite.check(case[1] .. " shows its mark", Marks.KindOf(row.mark) == case[2], Marks.KindOf(row.mark))
end
suite.check("the words stay", row.reason:GetText() == "Words")
UI.DrawRow(row, { type = "item", name = "Truefaith Gloves", count = 1, quality = 2,
    verdict = "keep", keptUpgrade = true, reason = "An upgrade: wear it" })
suite.check("a kept upgrade gets the arrow", Marks.KindOf(row.mark) == "upgrade")
UI.DrawRow(row, { type = "header", group = { label = "Sell", count = 2, worth = 0 } })
suite.check("a heading has no mark", Marks.KindOf(row.mark) == nil)
UI.DrawRow(row, { type = "job", step = step })
suite.check("a job row has no mark", Marks.KindOf(row.mark) == nil)

suite.done()
