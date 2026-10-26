-- All characters: every character's items in one list, from what
-- Tradeskills keeps (Butler:Holdings) and Butler's own read of the bags.
-- Without Tradeskills it shows the bags alone; a Tradeskills that raises
-- or answers nonsense is the same as none. The build is spread over frames,
-- names arrive late, and the save Tradeskills hands over is never changed.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("everyone")

local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 501, name = "Linen Cloth", quality = 1, price = 13, count = 20 },
    { bag = 0, slot = 2, id = 501, name = "Linen Cloth", quality = 1, price = 13, count = 5 },
    { bag = 0, slot = 3, id = 502, name = "Copper Ore", quality = 1, price = 5, count = 10 },
})
_G.UnitName = function() return "Mia" end
env.Enable(ns)
-- Mailing upgrades to alts is off unless ticked; these checks need it on.
ns.db.altUpgrades = true

local UI, Everyone = ns.UI, ns.Everyone

local function Find(name)
    for _, item in ipairs(Everyone.sorted) do
        if item.name == name then return item end
    end
end

local function Rows()
    return UI.list.data
end

-- Without Tradeskills: the bags of the character playing.
ns.HandleSlash("all")
suite.check("/bbutler all opens All characters", UI:IsShown() and UI.view == "all")
suite.check("the search box takes the subtitle's place", UI.search:IsShown() and not UI.subtitle:IsShown())
local linen = Find("Linen Cloth")
suite.check("stacks of one item are counted together", linen and linen.total == 25, linen and linen.total)
suite.check("held by the character playing", linen and linen.holders[1].character.short == "Mia")
suite.check("the footer says only these bags are shown",
    UI.footer:GetText():find("Only your bags", 1, true) ~= nil, UI.footer:GetText())
suite.check("no Sell button over the list", not UI.sellShown)

-- With Tradeskills.
local saved = {
    alt = { bags = { [502] = 3 }, bank = { [501] = 40, [503] = 7 }, mail = { [9999] = 2 } },
}
local holdingsAsked = 0
_G.BlackthornesTS = { Butler = { Holdings = function()
    holdingsAsked = holdingsAsked + 1
    return {
        { key = "Mia-R", name = "Mia", short = "Mia", isCurrent = true,
          bags = { [501] = 999 }, bank = { [502] = 1 }, bankAt = 1000 },
        { key = "Ana-R", name = "Ana", short = "Ana", isCurrent = false,
          bags = saved.alt.bags, bank = saved.alt.bank, mail = saved.alt.mail,
          bagsAt = 1000, bankAt = 500, mailAt = 900 },
        { key = "Mia-Old", name = "Mia", short = "Mia", playing = true,
          bags = { [501] = 500 } },
        { key = "Bob-R", name = "Bob", short = "Bob", linked = "Zed",
          bags = { [501] = "lots", [504] = -2 }, bank = "no" },
        "not a character",
    }
end } }

UI:Hide()
ns.HandleSlash("all")
suite.check("Tradeskills is asked once a build", holdingsAsked == 1, holdingsAsked)
linen = Find("Linen Cloth")
suite.check("Butler's own read wins for the character playing, an old record of it not counted again",
    linen.total == 65, linen.total)
suite.check("most first", linen.holders[1].character.short == "Ana" and linen.holders[2].total == 25)
suite.check("who has it, in short", Everyone.Summary(linen) == "Ana 40, Mia 25", Everyone.Summary(linen))
local ore = Find("Copper Ore")
suite.check("bags and bank are added up", ore.total == 14, ore.total)
suite.check("where one character keeps it", Everyone.Where(ore.byKey["Mia-R"]) == "10 in bags, 1 in the bank",
    Everyone.Where(ore.byKey["Mia-R"]))
suite.check("counts that are not numbers are left out", Find("Item 504") == nil)
suite.check("a character with nothing usable holds nothing", Everyone:Holders() == 2, Everyone:Holders())
suite.check("the footer counts items and characters",
    UI.footer:GetText():find("on 2 characters", 1, true) ~= nil, UI.footer:GetText())

-- Names the client has not loaded yet.
local waiting = Find("Item 9999")
suite.check("an item not loaded yet still shows", waiting ~= nil and waiting.named == false)
suite.check("and sorts last", Everyone.sorted[#Everyone.sorted] == waiting)
suite.check("and was asked for", ns.Items.waiting[9999] == true)
fake.info[9999] = { id = 9999, name = "Abyssal Crest", quality = 3, price = 1 }
env.Fire("GET_ITEM_INFO_RECEIVED", 9999)
local crest = Find("Abyssal Crest")
suite.check("its name comes in", crest ~= nil and crest.quality == 3)
suite.check("and it sorts by name", Everyone.sorted[1] == crest)
suite.check("the list was set again", Rows()[1].item == crest)

-- Search.
UI.search:SetText("ore")
UI:Refresh()
suite.check("search by name", #Rows() == 1 and Rows()[1].item.name == "Copper Ore", #Rows())
UI.search:SetText("503")
UI:Refresh()
suite.check("search by item number", #Rows() == 1 and Rows()[1].item.itemID == 503)
UI.search:SetText("mithril")
UI:Refresh()
suite.check("nothing found says so", UI.emptyLabel:IsShown()
    and UI.emptyLabel:GetText():find("mithril", 1, true) ~= nil)
UI.search:SetText("")
UI:Refresh()

-- A click opens a line per character.
local before = #Rows()
local rowFor
for _, line in ipairs(Rows()) do
    if line.item and line.item.name == "Linen Cloth" then rowFor = line end
end
UI:Clicked(rowFor, "LeftButton")
suite.check("a click opens a line per character", #Rows() == before + 2, #Rows())
local opened
for _, line in ipairs(Rows()) do
    if line.type == "holder" and line.holder.character.short == "Ana" then opened = line end
end
suite.check("with where it is", opened and Everyone.Where(opened.holder) == "40 in the bank")
local row = UI.list.rows and UI.list.rows[1]
if row then
    UI.UpdateRow(row, opened)
    suite.check("and how old that is", row.worth:GetText() ~= "", row.worth:GetText())
end
UI:Clicked(opened, "LeftButton")
suite.check("a second click closes it", #Rows() == before)

-- Ages.
suite.check("age: now", Everyone.Age(1000, 1030) == "now")
suite.check("age: days", Everyone.Age(1000, 1000 + 3 * 86400) == "3 days ago")
suite.check("age: never", Everyone.Age(nil, 1000) == "never read")
suite.check("seen is the oldest place holding it", Everyone.Seen(Find("Linen Cloth").byKey["Ana-R"]) == 500)

-- The bags move while it is shown: built again with the new count.
fake.bags[0][3] = nil
ns.Bags:Changed()
suite.check("the bags moved: built again", Find("Copper Ore").total == 4, Find("Copper Ore").total)

-- Tradeskills' tables are only read.
suite.check("the save is untouched", saved.alt.bank[501] == 40 and saved.alt.mail[9999] == 2)

-- A Tradeskills that raises is the same as none.
_G.BlackthornesTS.Butler.Holdings = function() error("boom") end
Everyone:Changed()
UI:Refresh()
suite.check("an error falls back to the bags", not Everyone:FromTradeskills() and Find("Linen Cloth").total == 25)

-- Spread over frames.
_G.BlackthornesTS = { Butler = { Holdings = function()
    return { { key = "Ana-R", short = "Ana", bank = { [601] = 1, [602] = 1, [603] = 1, [604] = 1 } } }
end } }
local queued = {}
local realAfter = C_Timer.After
C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
Everyone.BUDGET, Everyone.NAME_BUDGET = 1, 1
local doneNow = false
Everyone:Changed()
Everyone:Build(function() doneNow = true end)
suite.check("one frame does not do it all", not doneNow and #queued == 1, tostring(doneNow) .. " " .. #queued)
local frames = 1
while #queued > 0 do
    local fn = table.remove(queued, 1)
    fn()
    frames = frames + 1
end
suite.check("it finishes over several frames", doneNow and frames > 3, frames)
C_Timer.After = realAfter
Everyone.BUDGET, Everyone.NAME_BUDGET = 300, 40
_G.BlackthornesTS = nil
Everyone:Changed()

-- Only this realm and side's own characters: never another realm, another
-- side or a friend's shared characters (a helper's items showed, 2026-10-26).
local friends = { Pal = true }
_G.BlackthornesTS = {
    GuildCrafters = { IsFriend = function(_, name) return friends[name] == true end },
    Butler = { Holdings = function()
        return {
            { key = "Mia-R", name = "Mia", short = "Mia", isCurrent = true,
              realm = "Home", faction = "Horde", bags = {} },
            { key = "Ana-R", name = "Ana", short = "Ana", realm = "Home", faction = "Horde",
              bags = { [601] = 1 } },
            { key = "Far-R", name = "Far", short = "Far", realm = "Away", faction = "Alliance",
              linked = "Helper", bags = { [602] = 1 } },
            { key = "Side-R", name = "Side", short = "Side", realm = "Home", faction = "Alliance",
              bags = { [603] = 1 } },
            { key = "Pal-R", name = "Pal", short = "Pal", realm = "Home", faction = "Horde",
              linked = "Pal", bags = { [604] = 1 } },
            { key = "Two-R", name = "Two", short = "Two", realm = "Home", faction = "Horde",
              linked = "Mine", bags = { [605] = 1 } },
        }
    end },
}
local read = Everyone:Read()
local keys = {}
for _, character in ipairs(read) do keys[character.key] = true end
suite.check("this realm and side's characters are read", keys["Mia-R"] and keys["Ana-R"])
suite.check("another realm's shared characters are left out", not keys["Far-R"])
suite.check("the other side's characters are left out", not keys["Side-R"])
suite.check("a friend's shared characters are left out", not keys["Pal-R"])
suite.check("your own other account's characters here still show", keys["Two-R"])
_G.BlackthornesTS.GuildCrafters = nil
suite.check("without the Friends box, a shared character here shows",
    Everyone.Ours({ realm = "Home", faction = "Horde", linked = "Pal" }, { realm = "Home", faction = "Horde" }))
_G.BlackthornesTS.GuildCrafters = { IsFriend = function() error("broken") end }
suite.check("a Friends box that raises counts as no friend",
    Everyone.Ours({ realm = "Home", faction = "Horde", linked = "Pal" }, { realm = "Home", faction = "Horde" }))
_G.BlackthornesTS = nil
Everyone:Changed()

-- Back to the bags.
UI:SetView("bags")
suite.check("Your bags again, with its own search", UI.view == "bags" and UI.bagSearch:IsShown() and not UI.search:IsShown())
suite.check("with its own rows", Rows()[1].type == "header")
ns.HandleSlash("all")
suite.check("/bbutler all from the bags view switches", UI.view == "all" and UI:IsShown())
ns.HandleSlash("all")
suite.check("and again closes it", not UI:IsShown())

-- At a vendor it opens on the bags.
UI.view = "all"
ns.db.openAtVendor = true
env.Fire("MERCHANT_SHOW")
suite.check("a vendor opens it on your bags", UI:IsShown() and UI.view == "bags")

suite.done()
