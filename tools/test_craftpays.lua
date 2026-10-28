-- Craft When It Pays More (a player asked, the owner said build it,
-- 2026-10-19): Butler says when a craft the character knows earns more
-- than selling, with a Queue button that puts it in Tradeskills' queue.
--
-- What must hold:
--   1. Off until ticked: nothing asks Tradeskills, items keep their verdict.
--   2. Ticked: an item a craft makes worth more goes under Craft, saying
--      what to make and about how much more, the row worth that gain.
--   3. Other materials the bags lack are named.
--   4. Not for a craft that pays only a little more, or with nothing
--      known; keeping still wins.
--   5. Queue asks Tradeskills once a recipe and says how many it added.
--   6. The tick box and /bbutler craft change the same saved value.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("craftpays")

local ns = env.Load()
local bags = env.FakeBags({
    { bag = 0, slot = 1, id = 2592, name = "Wool Cloth", quality = 1, price = 33, count = 12 },
    { bag = 0, slot = 2, id = 10940, name = "Strange Dust", quality = 1, price = 10, count = 6 },
    { bag = 0, slot = 3, id = 2589, name = "Linen Cloth", quality = 1, price = 13, count = 4 },
})
bags.info[17034] = { id = 17034, name = "Maple Seed", price = 5 }
env.Enable(ns)

local Verdicts = ns.Verdicts

local function Find(name)
    for _, group in ipairs(Verdicts:Groups()) do
        for _, row in ipairs(group.rows) do
            if row.name == name then return row end
        end
    end
end

local asked, queued, goal, lastSkip = 0, {}, false, nil
_G.BlackthornesTS = { Butler = {
    Advise = function() return { auction = 40 } end,
    CraftFor = function(_, id, carried, skip)
        asked = asked + 1
        lastSkip = skip
        if id == 2592 then
            -- Bolt of Woolen Cloth: 3 wool a bolt, 4 bolts.
            return { recipeID = 2964, name = "Bolt of Woolen Cloth", itemID = 2997, per = 3,
                crafts = math.floor(carried / 3), perItem = 120, needs = {} }
        elseif id == 10940 then
            return { recipeID = 7836, name = "Minor Mana Oil", itemID = 20744, per = 3,
                crafts = 2, perItem = 120, needs = { { itemID = 17034, count = 2 } } }
        elseif id == 2589 then
            -- Barely more than selling: not worth the trip.
            return { recipeID = 2963, name = "Bolt of Linen Cloth", itemID = 2996, per = 2,
                crafts = 2, perItem = 42, needs = {} }
        end
    end,
    QueueCraft = function(_, recipeID, crafts)
        queued[#queued + 1] = recipeID .. "x" .. crafts
        return true
    end,
} }
_G.BlackthornesFarmer = { Butler = { Advise = function(_, id)
    if id == 2592 and goal then return { goal = "Wool Cloth", have = 12, target = 20, need = 8 } end
end } }

ns.UI:Show()

-- 1. Off by default.
Verdicts:Changed(true)
suite.check("off unless ticked", ns.db.craftPays == false and not Verdicts:CraftPaysOn())
suite.check("off: wool goes to auction as before", Find("Wool Cloth").verdict == "auction", Find("Wool Cloth").verdict)
suite.check("off: Tradeskills is never asked", asked == 0, asked)

-- 2. Ticked.
ns.HandleSlash("craft on")
suite.check("/bbutler craft on ticks it", ns.db.craftPays == true)
local wool = Find("Wool Cloth")
suite.check("wool goes under Craft", wool.verdict == "craft", wool.verdict)
-- 12 wool worth 120 each made into bolts, 40 each sold: 960 more.
suite.check("saying what to make and how much more",
    env.Plain(wool.reason) == "Make Bolt of Woolen Cloth, about " .. env.Plain(ns.Items.FormatMoney(960))
        .. " more than selling it", wool.reason)
suite.check("the row is worth the gain", wool.worth == 960, wool.worth)
local group = Verdicts:Group("craft")
suite.check("Craft is the first group", Verdicts:Groups()[1].verdict == "craft")
suite.check("its heading reads Craft", group.label == "Craft")

-- 3. Other materials named.
local dust = Find("Strange Dust")
suite.check("dust goes under Craft", dust.verdict == "craft", dust.verdict)
suite.check("naming what else it needs", env.Plain(dust.reason):find("(needs 2 Maple Seed)", 1, true) ~= nil,
    dust.reason)

-- 4. Not for a little more, and keeping wins.
suite.check("a craft that pays only a little more is left out", Find("Linen Cloth").verdict ~= "craft",
    Find("Linen Cloth").verdict)
goal = true
Verdicts:Changed(true)
suite.check("a goal's item is kept", Find("Wool Cloth").verdict == "keep", Find("Wool Cloth").verdict)
goal = false
Verdicts:Changed(true)

-- 5. Queue.
env.chat = {}
ns.UI:QueueCrafts()
suite.check("each craft goes in the queue", table.concat(queued, ",") == "2964x4,7836x2", table.concat(queued, ","))
suite.check("and chat says how many", env.ChatText():find("Added 2 crafts to your Tradeskills queue.", 1, true) ~= nil,
    env.ChatText())

-- 6. Settings and the command agree.
ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.craftPays
suite.check("the box shows it ticked", box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("unticking turns it off", ns.db.craftPays == false)
suite.check("and wool goes back to auction", Find("Wool Cloth").verdict == "auction", Find("Wool Cloth").verdict)
ns.HandleSlash("craft")
suite.check("/bbutler craft alone turns it on", ns.db.craftPays == true and box:GetChecked())
ns.HandleSlash("craft off")
suite.check("/bbutler craft off turns it off", ns.db.craftPays == false)
suite.check("craft is not in the help line", (function()
    for _, name in ipairs(ns.commandOrder) do if name == "craft" then return false end end
    return true
end)())

-- 7. Saying no to one craft (the owner, 2026-10-26).
ns.HandleSlash("craft on")
wool = Find("Wool Cloth")
ns.UI:ShowMenu(wool)
local menu = ns.UI.menu
suite.check("a Craft row's menu offers to stop suggesting it", menu.skipCraft:IsShown())
suite.check("reading Don't Suggest This Craft", menu.skipCraft.label:GetText() == "Don't Suggest This Craft",
    menu.skipCraft.label:GetText())
ns.UI:ShowKeepMenu()
suite.check("the keep page puts it away", not menu.skipCraft:IsShown())
ns.UI:ShowMenu(Find("Linen Cloth"))
suite.check("other rows don't offer it", not menu.skipCraft:IsShown())
ns.UI:ShowMenu(wool)
env.chat = {}
menu.skipCraft:GetScript("OnClick")(menu.skipCraft)
suite.check("the recipe is kept by its ID", ns.db.craftSkip and ns.db.craftSkip[2964] == "Bolt of Woolen Cloth")
suite.check("chat says so", env.ChatText():find("Butler won't suggest Bolt of Woolen Cloth again.", 1, true) ~= nil,
    env.ChatText())
suite.check("wool is no longer under Craft", Find("Wool Cloth").verdict == "auction", Find("Wool Cloth").verdict)
suite.check("Tradeskills is told which to pass over", type(lastSkip) == "table" and lastSkip[2964] ~= nil)
suite.check("other crafts still show", Find("Strange Dust").verdict == "craft", Find("Strange Dust").verdict)
ns.SettingsUI:Refresh()
local again = ns.SettingsUI.controls.craftSkip
suite.check("Settings offers Show Again", again.label:GetText() == "Show Again", again.label:GetText())
again:GetScript("OnClick")(again)
suite.check("Show Again brings them back", ns.db.craftSkip == nil and Find("Wool Cloth").verdict == "craft",
    Find("Wool Cloth").verdict)
suite.check("and the button reads None", again.label:GetText() == "None", again.label:GetText())

suite.done()
