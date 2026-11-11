-- Jobs on other characters (the owner asked 2026-10-11: "craft Medium
-- Leather on another then send back"). Tradeskills works out each
-- character's steps for its craft queue; Butler shows them.
--
-- What must hold:
--   1. Without Tradeskills there are no jobs and nothing shows.
--   2. The character playing's steps come first, then a line for each
--      other character with work, the one that can get on with it first.
--   3. Names are whole, first and last.
--   4. Craft asks Tradeskills to start it, and says what to do when the
--      profession is closed.
--   5. The Log out button is a secure /logout on the next character's
--      row, shown only while that row is on screen, never in combat, while
--      the window moves or in All characters.
--   6. Once the last step here is done, Butler says who is next.
--   7. Logging in on a character with a job brings the window up, unless
--      that is turned off.
--   8. Anything of the wrong shape, or an error, shows nothing.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("jobs")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 2318, name = "Light Leather", quality = 1, price = 15, count = 30 },
})
_G.C_Item.GetItemNameByID = function(id)
    return ({ [2318] = "Light Leather", [2319] = "Medium Leather", [4238] = "Linen Bag" })[id]
end

local Jobs, UI = ns.Jobs, ns.UI

-- Item names come in their rarity colour (Items:ColorName); these checks
-- read the words.
local Words = {}
for _, fn in ipairs({ "StepText", "Summary", "Short", "VendorText", "BuyTooltip", "SearchTooltip" }) do
    local raw = Jobs[fn]
    Words[fn] = function(...)
        local a, b, c = raw(...)
        return env.Plain(a), env.Plain(b), env.Plain(c)
    end
end

-- 1. No Tradeskills.
_G.BlackthornesTS = nil
env.Enable(ns)
suite.check("no Tradeskills, no jobs", #Jobs:Lines() == 0)

local jobs
local clearedName
local crafted = {}
local craftAnswer = { true, "crafting" }
_G.BlackthornesTS = { Butler = {
    Advise = function() return nil end,
    Holdings = function() return {} end,
    Mailbox = function() end,
    Jobs = function() return jobs end,
    ClearHoldings = function(_, name)
        clearedName = name
        return true, name
    end,
    Craft = function(_, recipeID)
        crafted[#crafted + 1] = recipeID
        return craftAnswer[1], craftAnswer[2]
    end,
} }

local function Fresh(list)
    jobs = list
    Jobs:Changed()
    return Jobs:Plan()
end

local ANA = { name = "Ana Blackthorne", isCurrent = true, steps = {
    { kind = "mail", to = "Blackthornes Wither", items = { { itemID = 2318, count = 30 } } },
    { kind = "craft", recipeID = 11, itemID = 4238, name = "Linen Bag", count = 1, forNames = {},
      ready = false, missing = { { itemID = 2996, count = 2, from = "Dee Tanner" } } },
} }
local CY = { name = "Cy Waiting", steps = {
    { kind = "craft", recipeID = 12, itemID = 9, name = "Thing", count = 2, forNames = {},
      ready = false, missing = { { itemID = 2318, count = 4, from = "Ana Blackthorne" } } },
} }
local WITHER = { name = "Blackthornes Wither", steps = {
    { kind = "craft", recipeID = 10, itemID = 2319, name = "Medium Leather", count = 20,
      forNames = { "Ana Blackthorne" }, ready = true, missing = {} },
} }

-- 2. Order.
local plan = Fresh({ ANA, CY, WITHER })
suite.check("the character playing is here", plan.here and plan.here.name == "Ana Blackthorne")
suite.check("next is the one that can get on with it", plan.nextJob.name == "Blackthornes Wither")
local rows = Jobs:Lines()
suite.check("two steps here and two characters", #rows == 4, #rows)
suite.check("this character's steps first", rows[1].type == "job" and rows[1].step.kind == "mail")
suite.check("then the next character", rows[3].type == "jobnext" and rows[3].isNext
    and rows[3].job.name == "Blackthornes Wither")
suite.check("then the one waiting", rows[4].job.name == "Cy Waiting" and not rows[4].isNext)

-- 3. Words, with whole names.
local title, detail = Words.StepText(rows[1].step)
suite.check("a mail names the character in full", title == "Mail to Blackthornes Wither", title)
suite.check("and says what goes", detail:find("30 Light Leather", 1, true) ~= nil, detail)
title, detail = Words.StepText(rows[2].step)
suite.check("a craft of one has no number", title == "Craft Linen Bag", title)
suite.check("short of materials says so", detail:find("Still needs", 1, true) == 1, detail)
local banked = Jobs.Clean({ { name = "Ana Blackthorne", isCurrent = true, steps = { { kind = "mail",
    to = "Blackthornes Wither", forCraft = true, items = { { itemID = 2318, count = 40, bank = 20 } } } } } })
title, detail = Words.StepText(banked[1].steps[1])
suite.check("a mail with some in the bank says to take it out first",
    detail:find("Take 20 Light Leather out of the bank first", 1, true) ~= nil, detail)
suite.check("and still says how many go", detail:find("40 Light Leather", 1, true) == 1, detail)
local summary = Words.Summary(WITHER)
suite.check("the next character's job in one line",
    summary == "Craft 20 Medium Leather, then mail it to Ana Blackthorne.", summary)
suite.check("one waiting on materials says so", Words.Summary(CY):find("Waiting on materials", 1, true) ~= nil)

-- The window shows them first.
UI:Show("bags")
local lines = UI:Lines()
suite.check("the Jobs group heads the window", lines[1].type == "header" and lines[1].group.verdict == "jobs")
suite.check("with its steps under it", lines[2].type == "job")

-- 4. Craft.
plan = Fresh({ { name = "Ana Blackthorne", isCurrent = true, steps = { WITHER.steps[1] } } })
suite.check("a craft with its materials", Jobs:Craft(plan.here.steps[1]) == true)
suite.check("asks Tradeskills for that recipe", crafted[1] == 10)
craftAnswer = { true, "opened" }
Jobs:Craft(plan.here.steps[1])
suite.check("a closed profession says how to open it", env.ChatText():find("Open button", 1, true) ~= nil)
craftAnswer = { false, "need materials" }
suite.check("a refusal is no craft", Jobs:Craft(plan.here.steps[1]) == false)
suite.check("and says why", env.ChatText():find("need materials", 1, true) ~= nil)
_G.InCombatLockdown = function() return true end
local before = #crafted
Jobs:Craft(plan.here.steps[1])
suite.check("never in combat", #crafted == before)
_G.InCombatLockdown = nil

-- 4b. A form that stops a craft (travel form, Ghost Wolf): the first click
-- leaves it through a secure /cancelform, the next crafts. As Tradeskills'.
local class, form = "WARRIOR", 1
_G.UnitClass = function() return "Ana", class end
_G.GetShapeshiftForm = function() return form end
suite.check("a warrior's stance is no form to leave", not Jobs.InBlockingForm())
class = "DRUID"
suite.check("a druid in a form has to leave it", Jobs.InBlockingForm())
before = #crafted
craftAnswer = { true }
suite.check("Craft in a form crafts nothing", Jobs:Craft(plan.here.steps[1]) == false and #crafted == before)
suite.check("and says to leave the form", env.ChatText():find("leave your form", 1, true) ~= nil)
local formRows = UI.list.rows
local function FormRow(data)
    return { data = data, IsShown = function() return true end,
        GetRight = function() return 700 end, GetTop = function() return 500 end,
        GetBottom = function() return 470 end, GetEffectiveScale = function() return 1 end }
end
UI.list.rows = { FormRow({ type = "header" }), FormRow({ type = "job", step = plan.here.steps[1] }) }
Jobs:UpdateLeaveForm()
local leave = Jobs.formButton
suite.check("Leave form shows over the Craft button", leave and leave:IsShown())
suite.check("it runs /cancelform and nothing else", leave:GetAttribute("type") == "macro"
    and leave:GetAttribute("macrotext") == "/cancelform" and leave:GetAttribute("spell") == nil)
suite.check("at the Craft button's place", leave._point[1] == "RIGHT" and leave._point[2] == UI.list.rows[2]
    and leave._point[4] == -8 and leave._point[5] == 0 and leave:GetParent() == UI.frame)
env.Fire("PLAYER_REGEN_DISABLED")
suite.check("combat hides it", not leave:IsShown())
env.Fire("PLAYER_REGEN_ENABLED")
Jobs:UpdateLeaveForm()
suite.check("and it comes back after", leave:IsShown())
form = 0
Jobs:UpdateLeaveForm()
suite.check("out of the form, it goes and Craft is back", not leave:IsShown())
suite.check("and Craft crafts again", Jobs:Craft(plan.here.steps[1]) == true and #crafted == before + 1)
form = 2
UI.list.rows = { FormRow({ type = "job", step = { kind = "craft", ready = false } }) }
Jobs:UpdateLeaveForm()
suite.check("no Craft button, no Leave form", not leave:IsShown())
UI.list.rows = formRows
_G.UnitClass, _G.GetShapeshiftForm = nil, nil
suite.check("a client without the calls is never in a form", not Jobs.InBlockingForm())

-- 4c. A closed profession (the owner asked 2026-10-15): Open, a secure
-- button set to the profession's spell, sits over the first Craft button
-- whose window is closed; once it opens, Craft is back and crafts.
local professionOpen = false
_G.BlackthornesTS.Butler.Profession = function(_, recipeID)
    if recipeID ~= plan.here.steps[1].recipeID then return nil end
    return { name = "Tailoring", spell = "Tailoring", open = professionOpen }
end
UI.list.rows = { FormRow({ type = "header" }), FormRow({ type = "job", step = plan.here.steps[1] }) }
Jobs:UpdateOpenProfession()
local open = Jobs.openButton
suite.check("Open shows over a closed profession's Craft", open and open:IsShown())
suite.check("it casts the profession and nothing else", open:GetAttribute("type") == "spell"
    and open:GetAttribute("spell") == "Tailoring" and open:GetAttribute("macrotext") == nil)
suite.check("named for it", open.label:GetText() == "Open Tailoring")
suite.check("at the Craft button's place", open._point[1] == "RIGHT" and open._point[2] == UI.list.rows[2]
    and open:GetParent() == UI.frame)
env.Fire("PLAYER_REGEN_DISABLED")
suite.check("combat hides Open", not open:IsShown())
env.Fire("PLAYER_REGEN_ENABLED")
professionOpen = true
Jobs:UpdateOpenProfession()
suite.check("an open profession has no Open, Craft crafts", not open:IsShown())
professionOpen = false
_G.UnitClass, _G.GetShapeshiftForm = function() return "Ana", "DRUID" end, function() return 1 end
Jobs:UpdateOpenProfession()
suite.check("Leave form comes first in a form", not open:IsShown())
_G.UnitClass, _G.GetShapeshiftForm = nil, nil
_G.BlackthornesTS.Butler.Profession = function() error("boom") end
Jobs:UpdateOpenProfession()
suite.check("a Tradeskills error shows no Open", not open:IsShown())
_G.BlackthornesTS.Butler.Profession = nil
Jobs:UpdateOpenProfession()
suite.check("an older Tradeskills shows no Open", not open:IsShown())
UI.list.rows = formRows

-- 5. Log out, on the next character's row (the owner asked 2026-10-11:
-- "the log out button should be next to the step that needs the logout").
local realRows = UI.list.rows
local function Row(data, shown)
    return { data = data, IsShown = function() return shown ~= false end,
        GetRight = function() return 700 end, GetTop = function() return 500 end,
        GetBottom = function() return 470 end, GetEffectiveScale = function() return 1 end }
end
local function ShowRows(list)
    local rows = {}
    for index, data in ipairs(list) do rows[index] = Row(data) end
    UI.list.rows = rows
    return rows
end
Fresh({ ANA, WITHER })
local shown = ShowRows(Jobs:Lines())
Jobs:UpdateLogout()
local button = Jobs.button
suite.check("the Log out button shows with someone next", button and button:IsShown())
suite.check("it is the game's own /logout", button:GetAttribute("type") == "macro"
    and button:GetAttribute("macrotext") == "/logout")
suite.check("its tooltip names who to pick", button.tooltipText:find("Blackthornes Wither", 1, true) ~= nil)
suite.check("it sits on that character's row", Jobs.NextRow(UI.list).data.job.name == "Blackthornes Wither")
local point = button._point
suite.check("at the row's right end, level with it", point[1] == "RIGHT" and point[2] == Jobs.NextRow(UI.list)
    and point[3] == "RIGHT" and point[4] == -8 and point[5] == 0, tostring(point[4]) .. "," .. tostring(point[5]))
suite.check("inside the window", button:GetParent() == UI.frame)
suite.check("work here, the footer doesn't say it's all done", not Jobs:DoneHere())
UI.list.rows = { Row(shown[1]), Row(shown[2]) }
Jobs:UpdateLogout()
suite.check("its row scrolled out of sight, no button", not button:IsShown())
ShowRows(Jobs:Lines())
Fresh({ ANA })
ShowRows(Jobs:Lines())
Jobs:UpdateLogout()
suite.check("nobody next, no button", not button:IsShown())
Fresh({ ANA, WITHER })
ShowRows(Jobs:Lines())
Jobs:UpdateLogout()
env.Fire("PLAYER_REGEN_DISABLED")
suite.check("combat hides it", not button:IsShown())
env.Fire("PLAYER_REGEN_ENABLED")
suite.check("and it comes back after", button:IsShown())
UI.view = "all"
Jobs:UpdateLogout()
suite.check("not in All characters", not button:IsShown())
UI.view = "bags"
UI.dragging = true
Jobs:UpdateLogout()
suite.check("not while the window moves", not button:IsShown())
UI.dragging = false
Fresh({ WITHER })
ShowRows(Jobs:Lines())
Jobs:UpdateLogout()
suite.check("done here, it is on the next one's row", button:IsShown())
suite.check("and the footer says everything here is done", Jobs:DoneHere())
suite.check("never a second button at the foot", Jobs.footButton == nil)

-- Nothing here can be done yet and the next one can: it goes first.
local STUCK = { name = "Ana Blackthorne", isCurrent = true, steps = {
    { kind = "craft", recipeID = 13, itemID = 2582, name = "Reinforced Woolen Shoulders", count = 5,
      forNames = {}, ready = false, missing = { { itemID = 2319, count = 10, from = "Blackthornes Wither" } } },
} }
plan = Fresh({ STUCK, CY, WITHER })
suite.check("stuck here, the next one goes first", plan.goFirst == true)
rows = Jobs:Lines()
suite.check("its line heads the Jobs group", rows[1].type == "jobnext" and rows[1].isFirst
    and rows[1].job.name == "Blackthornes Wither")
suite.check("then the craft here", rows[2].type == "job" and rows[2].step.recipeID == 13)
suite.check("then the rest, once each", #rows == 3 and rows[3].job.name == "Cy Waiting", #rows)
title, detail = Words.StepText(rows[2].step)
suite.check("the craft says who has what it needs",
    detail:find("Blackthornes Wither has it", 1, true) ~= nil, detail)
ShowRows(rows)
Jobs:UpdateLogout()
suite.check("and Log out sits on its line", button:IsShown()
    and Jobs.NextRow(UI.list) and Jobs.NextRow(UI.list).data.isFirst == true)
UI.list.rows = realRows
plan = Fresh({ STUCK, CY })
suite.check("nobody else can either, nothing jumps", not plan.goFirst and Jobs:Lines()[1].type == "job")
local clean = Jobs.Clean({ { name = "Dee Tanner", steps = { { kind = "mail", to = "Blackthornes Wither",
    forCraft = true, items = { { itemID = 2318, count = 40 } } } } } })
suite.check("a mail for a craft keeps its mark", clean[1] and clean[1].steps[1].forCraft == true)

-- The character playing under another record is never one to log out for,
-- and never mails itself; the one whose mail unblocks a craft here is next.
local errandsIsMe = ns.Errands.IsMe
ns.Errands.IsMe = function(_, name) return name == "Blackthornes Wither" end
local OLD_ME = { name = "Blackthornes Wither", steps = {
    { kind = "mail", to = "Blackthornes Wither", items = { { itemID = 2319, count = 8 } } },
    { kind = "craft", recipeID = 14, itemID = 2319, name = "Medium Leather", count = 10, forNames = {},
      ready = false, missing = { { itemID = 2318, count = 40, from = "Blackthornes Farmer" } } },
} }
local FARMER = { name = "Blackthornes Farmer", steps = {
    { kind = "mail", to = "Blackthornes Wither", forCraft = true, items = { { itemID = 2318, count = 40 } } },
} }
local ANA_MAIL = { name = "Ana Blackthorne", steps = {
    { kind = "mail", to = "Cy Waiting", items = { { itemID = 2319, count = 8 } } },
} }
plan = Fresh({ OLD_ME, ANA_MAIL, FARMER })
suite.check("the character playing is here under any record", plan.here and plan.here.name == "Blackthornes Wither")
suite.check("and not someone to log out for", plan.nextJob and plan.nextJob.name ~= "Blackthornes Wither")
suite.check("its mail to itself is dropped", #plan.here.steps == 1 and plan.here.steps[1].kind == "craft",
    #plan.here.steps)
suite.check("the one sending what the craft needs goes first", plan.goFirst
    and plan.nextJob.name == "Blackthornes Farmer", plan.nextJob.name)
ns.Errands.IsMe = errandsIsMe

-- 6. Done here.
Fresh({ ANA, WITHER })
env.chat = {}
Fresh({ WITHER })
suite.check("done here says who is next", env.ChatText():find("Next: Blackthornes Wither", 1, true) ~= nil,
    env.ChatText())
env.chat = {}
Fresh({ WITHER })
suite.check("and only once", env.ChatText() == "")

-- 7. At login.
UI:Hide()
jobs = { { name = "Blackthornes Wither", isCurrent = true, steps = WITHER.steps } }
env.Fire("PLAYER_ENTERING_WORLD", true, false)
suite.check("a job here brings the window up", UI:IsShown())
suite.check("and says what it is", env.ChatText():find("a job on this character", 1, true) ~= nil)
UI:Hide()
ns.HandleSlash("joblogin")
suite.check("joblogin turns it off", ns.db.jobsAtLogin == false)
env.Fire("PLAYER_ENTERING_WORLD", true, false)
suite.check("then the window stays down", not UI:IsShown())
env.Fire("PLAYER_ENTERING_WORLD", false, true)
suite.check("a reload never brings it up", not UI:IsShown())

-- 7b. Profession cooldowns (Tradeskills' "cooldown" steps, 2026-10-12).
ns.db.jobsAtLogin = true
UI:Hide()
local MOON = { name = "Blackthornes Wither", isCurrent = false, steps = {
    { kind = "cooldown", name = "Mooncloth", craft = "Mooncloth", recipeID = 18560 } } }
local HERE = { name = "Ana Blackthorne", isCurrent = true, steps = {
    { kind = "cooldown", name = "Transmute", craft = "Transmute: Arcanite", recipeID = 17187 },
    { kind = "cooldown", name = "Salt Shaker", itemID = 15846 } } }
local plan = Fresh({ HERE, MOON })
suite.check("a ready cooldown is a step here", plan.here and #plan.here.steps == 2)
suite.check("one on another character is a job to go to", plan.nextJob and plan.nextJob.name == "Blackthornes Wither")
local title, detail = Words.StepText(plan.here.steps[1])
suite.check("says it is ready", title == "Transmute is ready", title)
suite.check("and what to make", detail:find("Transmute: Arcanite", 1, true) ~= nil, detail)
suite.check("the other's line says so", Words.Summary(plan.nextJob):find("Mooncloth", 1, true) ~= nil,
    Words.Summary(plan.nextJob))
crafted = {}
craftAnswer = { true, "crafting" }
suite.check("Craft makes a ready transmute", Jobs:Craft(plan.here.steps[1]) == true and crafted[1] == 17187)
suite.check("an item's cooldown has no Craft", Jobs:Craft(plan.here.steps[2]) == false and #crafted == 1)
local _, itemDetail = Words.StepText(plan.here.steps[2])
suite.check("an item's says to use it", itemDetail:find("bags", 1, true) ~= nil, itemDetail)
suite.check("a cooldown without a name is left out",
    #Jobs.Clean({ { name = "X", steps = { { kind = "cooldown", recipeID = 1 } } } }) == 0)

-- 7c. Ignore Until Next Login (a player asked, the owner said yes,
-- 2026-10-18): a right-click puts a character's jobs away, and they come
-- back the next time that character logs in.
ns.db.jobsIgnored = nil
UI:Show("bags")
plan = Fresh({ ANA, CY, WITHER })
rows = Jobs:Lines()
local witherRow
for _, row in ipairs(rows) do
    if row.type == "jobnext" and row.job.name == "Blackthornes Wither" then witherRow = row end
end
suite.check("this character's steps carry its line", rows[1].type == "job" and rows[1].job
    and rows[1].job.name == "Ana Blackthorne")
UI:Clicked(witherRow, "RightButton")
suite.check("a right-click on another's line opens its menu", UI.menu and UI.menu:IsShown()
    and UI.menu.ignoreJobs:IsShown() and not UI.menu.keep:IsShown())
suite.check("the menu says it plainly", UI.menu.ignoreJobs.label:GetText() == "Ignore Until Next Login")
UI.menu.ignoreJobs:GetScript("OnClick")(UI.menu.ignoreJobs)
suite.check("the menu goes once picked", not UI.menu:IsShown())
suite.check("put away by its whole name", ns.db.jobsIgnored and ns.db.jobsIgnored["Blackthornes Wither"] ~= nil)
plan = Jobs:Plan()
suite.check("its line is gone", #plan.others == 1 and plan.others[1].name == "Cy Waiting")
suite.check("and it is no longer next", plan.nextJob.name == "Cy Waiting")
suite.check("the queue itself is untouched", #Jobs:Read() == 3)
UI:Clicked(rows[1], "RightButton")
UI.menu.ignoreJobs:GetScript("OnClick")(UI.menu.ignoreJobs)
plan = Jobs:Plan()
suite.check("this character's own steps can go too", plan.here == nil)
env.Fire("PLAYER_ENTERING_WORLD", false, true)
suite.check("a reload keeps them away", Jobs:Ignored("Ana Blackthorne"))
_G.UnitName = function() return "Blackthornes Wither" end
local realAfter = _G.C_Timer.After
_G.C_Timer.After = function() end
env.Fire("PLAYER_ENTERING_WORLD", true, false)
suite.check("logging in brings that character's jobs back", not Jobs:Ignored("Blackthornes Wither"))
suite.check("and only that character's", Jobs:Ignored("Ana Blackthorne"))
_G.UnitName = function() return "ana blackthorne" end
env.Fire("PLAYER_ENTERING_WORLD", true, false)
suite.check("names match in any case", not Jobs:Ignored("Ana Blackthorne"))
_G.C_Timer.After = realAfter
_G.UnitName = nil
plan = Fresh({ ANA, CY, WITHER })
suite.check("all lines are back", plan.here and #plan.others == 2)
UI:Clicked({ type = "jobnext" }, "RightButton")
suite.check("a line with no name opens nothing", not UI.menu:IsShown())
UI:Hide()
-- 7d. Clear Items (mechiah's report, the owner said build it, 2026-11-10):
-- under Ignore Until Next Login, armed by one click, done by the second.
UI:Show("bags")
plan = Fresh({ ANA, CY, WITHER })
rows = Jobs:Lines()
witherRow = nil
for _, row in ipairs(rows) do
    if row.type == "jobnext" and row.job.name == "Blackthornes Wither" then witherRow = row end
end
ns.db.goldSent = { ["Blackthornes Wither"] = { amount = 500, at = 1 }, ["Cy Waiting"] = { amount = 9, at = 1 } }
clearedName = nil
UI:Clicked(witherRow, "RightButton")
local clear = UI.menu.clearItems
local heldTimers = {}
local runTimers = _G.C_Timer.After
_G.C_Timer.After = function(_, fn) heldTimers[#heldTimers + 1] = fn end
suite.check("Clear Items shows for another character", clear and clear:IsShown())
suite.check("it says Clear Items", clear.label:GetText() == "Clear Items")
clear:GetScript("OnClick")(clear)
suite.check("the first click only arms it", clearedName == nil and clear.label:GetText() == "Confirm"
    and UI.menu:IsShown())
clear:GetScript("OnClick")(clear)
suite.check("the second click clears that character", clearedName == "Blackthornes Wither")
suite.check("the menu goes once cleared", not UI.menu:IsShown())
heldTimers = {}
UI:Clicked(witherRow, "RightButton")
clear:GetScript("OnClick")(clear)
for _, fn in ipairs(heldTimers) do fn() end
suite.check("an armed click lets go after a while", not clear.armed and clear.label:GetText() == "Clear Items")
_G.C_Timer.After = runTimers
suite.check("its gold notes go too", ns.db.goldSent["Blackthornes Wither"] == nil
    and ns.db.goldSent["Cy Waiting"] ~= nil)
clearedName = nil
UI:Clicked(rows[1], "RightButton")
suite.check("never for the character playing", not UI.menu.clearItems:IsShown())
_G.UnitName = function() return "Ana Blackthorne" end
suite.check("the one playing is refused", Jobs:ClearItems("Ana Blackthorne") == false and clearedName == nil)
_G.UnitName = nil
UI:Hide()

-- 9. At a mailbox, Fill mail sits on the Jobs line that mails the
-- character (the owner asked 2026-10-12), not on the Mail row below it.
local filledTo
_G.BlackthornesTS.Butler.Jobs = function() return jobs end
_G.BlackthornesTS.Butler.Advise = function(_, id)
    if id == 2318 then return { mailTo = "Blackthornes Wither", mailCount = 30 } end
end
_G.BlackthornesTS.Butler.FillMail = function(_, name) filledTo = name return true end
Fresh({ ANA, WITHER })
ns.Verdicts:Changed(true)
UI:Show("bags")
env.Fire("MAIL_SHOW")
UI:Refresh(true)
local fillLine, mailRow
for _, line in ipairs(UI.list.data) do
    if UI.fillRows[line] then fillLine = fillLine or line end
    if line.type == "item" and line.mailTo then mailRow = line end
end
suite.check("the Mail row is there too", mailRow ~= nil)
suite.check("Fill mail sits on the Jobs mail line", fillLine and fillLine.type == "job"
    and fillLine.step.to == "Blackthornes Wither", fillLine and fillLine.type)
suite.check("and only there", UI.fillRows[mailRow] == nil and not UI.mailButton:IsShown())
suite.check("the foot still says who presses Send", UI.footer:GetText():find("You press Send", 1, true) ~= nil)
UI.RowAction(fillLine)
suite.check("a click fills that character's mail", filledTo == "Blackthornes Wither")
env.Fire("MAIL_CLOSED")
UI:Show("bags")
UI:Refresh(true)
suite.check("away from the mailbox the button goes", next(UI.fillRows) == nil)
UI:Hide()
_G.BlackthornesTS.Butler.Advise = function() return nil end

-- Mail waiting (the owner, 2026-10-13): a mailbox visit for something
-- sent to a character goes up the list.
_G.BlackthornesTS.Butler.Jobs = function() return jobs end
local MIA = { name = "Mia Thorn", steps = {
    { kind = "craft", recipeID = 13, itemID = 8, name = "Other", count = 1, forNames = {}, ready = true, missing = {} },
    { kind = "pickup", items = { { itemID = 2319, count = 20 } }, forCraft = true },
} }
plan = Fresh({ ANA, CY, WITHER, MIA })
suite.check("a character with mail waiting for its crafts is next", plan.nextJob.name == "Mia Thorn",
    plan.nextJob.name)
suite.check("its mailbox is its first step", plan.nextJob.steps[1].kind == "pickup")
suite.check("its line says so", Words.Summary(plan.nextJob):find("^Get 20 ") ~= nil, Words.Summary(plan.nextJob))
local FEEDER = { name = "Dee Tanner", steps = {
    { kind = "mail", to = "Ana Blackthorne", items = { { itemID = 2996, count = 2 } }, forCraft = true },
} }
plan = Fresh({ ANA, MIA, FEEDER })
suite.check("one whose mail unblocks a craft here still comes before", plan.nextJob.name == "Dee Tanner")
local WAITING_HERE = { name = "Ana Blackthorne", isCurrent = true, steps = {
    { kind = "craft", recipeID = 11, itemID = 4238, name = "Linen Bag", count = 1, forNames = {},
      ready = true, missing = {} },
    { kind = "pickup", items = { { itemID = 7001, count = 1 } } },
} }
plan = Fresh({ WAITING_HERE, WITHER })
suite.check("here, the mailbox comes before the craft", plan.here.steps[1].kind == "pickup")
suite.check("and keeps this character here", plan.goFirst == false)
local title, detail = Words.StepText(plan.here.steps[1])
suite.check("it says to get the mail", title == "Get your mail" and detail:find("sent to you", 1, true) ~= nil,
    tostring(title) .. " / " .. tostring(detail))
title, detail = Words.StepText(MIA.steps[2])
suite.check("for crafts, it says to take it out first", detail:find("before you craft", 1, true) ~= nil, detail)
suite.check("an empty pickup is left out", #Jobs.Clean({ { name = "Z", steps = { { kind = "pickup", items = {} } } } }) == 0)

-- Materials to get and parts first (the owner, 2026-10-13: "collecting all
-- vendor materials and subcrafts should go to the top", "missing materials
-- too that need to be purchased or gathered").
local PARTS = { name = "Ana Blackthorne", isCurrent = true, steps = {
    { kind = "mail", to = "Cy Wither", items = { { itemID = 2318, count = 5 } } },
    { kind = "craft", recipeID = 21, itemID = 9001, name = "Final Belt", count = 1, forNames = {},
      ready = false, missing = { { itemID = 9002, count = 2 }, { itemID = 2321, count = 3, vendor = 10 } } },
    { kind = "craft", recipeID = 22, itemID = 9002, name = "Bolt", count = 2, forNames = {},
      ready = false, missing = { { itemID = 9003, count = 1 }, { itemID = 2321, count = 1, vendor = 10 } } },
    { kind = "craft", recipeID = 23, itemID = 9003, name = "Spool", count = 1, forNames = {},
      ready = true, missing = {} },
    { kind = "pickup", items = { { itemID = 7001, count = 1 } } },
    { kind = "craft", recipeID = 24, itemID = 9004, name = "Other", count = 1, forNames = {},
      ready = false, missing = { { itemID = 2996, count = 1, vendor = true, from = "Dee Tanner" } } },
} }
plan = Fresh({ PARTS })
local kinds = {}
for _, step in ipairs(plan.here.steps) do kinds[#kinds + 1] = step.kind .. ":" .. tostring(step.recipeID or "") end
local order = table.concat(kinds, " ")
suite.check("mailbox, vendor, deepest part, part, then the rest",
    order == "pickup: buy: craft:23 craft:22 mail: craft:21 craft:24", order)
local buy = plan.here.steps[2]
suite.check("the vendor step adds up what every craft is short",
    #buy.items == 1 and buy.items[1].itemID == 2321 and buy.items[1].count == 4)
title, detail = Words.StepText(buy)
suite.check("it says to buy them", title == "Buy from a vendor" and detail:find("Tradeskills Vendor", 1, true) ~= nil,
    tostring(title) .. " / " .. tostring(detail))
suite.check("a vendor run counts as a step to do now", Jobs.Ready({ steps = { buy } }))
-- Bars all at once (a player's report, 2026-10-19): Tradeskills lists
-- the bar before the deeper anvil parts, and that order stays.
plan = Fresh({ { name = "Ana Blackthorne", isCurrent = true, steps = {
    { kind = "craft", recipeID = 41, itemID = 9021, name = "Iron Bar", count = 1, forNames = {},
      ready = true, missing = {} },
    { kind = "craft", recipeID = 42, itemID = 9022, name = "Grit", count = 1, forNames = {},
      ready = true, missing = {} },
    { kind = "craft", recipeID = 43, itemID = 9023, name = "Plate", count = 1, forNames = {},
      ready = false, missing = { { itemID = 9022, count = 1 } } },
    { kind = "craft", recipeID = 44, itemID = 9024, name = "Helm", count = 1, forNames = {},
      ready = false, missing = { { itemID = 9023, count = 1 }, { itemID = 9021, count = 1 } } },
} } })
kinds = {}
for _, step in ipairs(plan.here.steps) do kinds[#kinds + 1] = step.kind .. ":" .. tostring(step.recipeID or "") end
order = table.concat(kinds, " ")
suite.check("the bar stays before the anvil parts", order == "craft:41 craft:42 craft:43 craft:44", order)

plan = Fresh({ { name = "Ana Blackthorne", isCurrent = true, steps = {
    { kind = "craft", recipeID = 31, itemID = 9010, name = "Plain", count = 1, forNames = {},
      ready = false, missing = { { itemID = 9011, count = 1 } } } } } })
suite.check("a material nobody makes is bought or gathered first",
    plan.here.steps[1].kind == "gather" and plan.here.steps[1].items[1].itemID == 9011 and #plan.here.steps == 2)
title, detail = Words.StepText(plan.here.steps[1])
suite.check("it says to buy or gather it", title == "Buy or gather" and detail:find("auction house", 1, true) ~= nil,
    tostring(title) .. " / " .. tostring(detail))
suite.check("no vendor step without vendor materials", plan.here.steps[1].kind ~= "buy")
plan = Fresh({ { name = "Ana Blackthorne", isCurrent = true, steps = {
    { kind = "pickup", items = { { itemID = 9011, count = 1 } }, forCraft = true },
    { kind = "craft", recipeID = 31, itemID = 9010, name = "Plain", count = 1, forNames = {},
      ready = false, missing = { { itemID = 9011, count = 1 } } } } } })
suite.check("what waits in the mailbox is not gathered again", plan.here.steps[2].kind == "craft")
local MAKER = { name = "Bo Smith", steps = {
    { kind = "craft", recipeID = 41, itemID = 9011, name = "Part", count = 1, forNames = { "Ana Blackthorne" },
      ready = true, missing = {} },
} }
plan = Fresh({ { name = "Ana Blackthorne", isCurrent = true, steps = {
    { kind = "craft", recipeID = 31, itemID = 9010, name = "Plain", count = 1, forNames = {},
      ready = false, missing = { { itemID = 9011, count = 1 } } } } }, MIA, MAKER })
suite.check("one who can make a part a craft here waits on is next", plan.nextJob.name == "Bo Smith",
    plan.nextJob.name)
suite.check("a part another character makes is not bought or gathered", plan.here.steps[1].kind == "craft")

-- A mail of materials says what the receiver makes with them (the owner,
-- 2026-10-14: Wool Cloth looked mailed away from a craft here).
_G.C_Item.GetItemNameByID = function(id)
    return ({ [2592] = "Wool Cloth", [2997] = "Bolt of Woolen Cloth", [2318] = "Light Leather" })[id]
end
plan = Fresh({ { name = "Ana Blackthorne", isCurrent = true, steps = {
    { kind = "mail", to = "Bo Smith", items = { { itemID = 2592, count = 6 } }, forCraft = true },
    { kind = "mail", to = "Bo Smith", items = { { itemID = 2318, count = 2 } }, crafts = true } } },
    { name = "Bo Smith", steps = {
        { kind = "craft", recipeID = 2964, itemID = 2997, name = "Bolt of Woolen Cloth", count = 2,
          forNames = { "Ana Blackthorne" }, ready = false,
          missing = { { itemID = 2592, count = 6, from = "Ana Blackthorne" } } } } } })
local wool = plan.here.steps[1]
title, detail = Words.StepText(wool)
local _, _, hint = Words.StepText(wool)
suite.check("a mail of materials says what they make",
    detail == "6 Wool Cloth, so Bo Smith can make 2 Bolt of Woolen Cloth.", detail)
suite.check("how Fill mail works goes in the tooltip", hint == "At a mailbox, Fill mail adds it.", hint)
_, detail = Words.StepText(plan.here.steps[2])
suite.check("finished crafts sent back keep their line",
    detail == "2 Light Leather. At a mailbox, Fill mail adds it.", detail)
wool.items[1].bank = 2
_, detail = Words.StepText(wool)
suite.check("banked materials still say to take them out",
    detail == "6 Wool Cloth, so Bo Smith can make 2 Bolt of Woolen Cloth. Take 2 Wool Cloth out of the bank first.",
    detail)

-- 7b. Plain crafts: the most bag slots freed first, other steps stay put.
local function craftStep(id, slots)
    return { kind = "craft", recipeID = id, itemID = 900 + id, slots = slots, missing = {}, ready = true }
end
local ordered = Jobs.Order({ craftStep(1, 0), { kind = "cooldown", name = "Transmute" },
    craftStep(2, 4), craftStep(3, 4), craftStep(4, 1) }, {})
local ids = {}
for _, step in ipairs(ordered) do ids[#ids + 1] = step.recipeID or step.kind end
suite.check("crafts freeing more slots come first", table.concat(ids, ",") == "2,cooldown,3,4,1", table.concat(ids, ","))
ordered = Jobs.Order({ craftStep(1), craftStep(2) }, {})
suite.check("with no slot counts the order stays", ordered[1].recipeID == 1 and ordered[2].recipeID == 2)

-- 7b. At login an item's name can still be loading: the line waits for
-- it rather than saying "Item 2605", and says it anyway in the end.
do
    local realName = _G.C_Item.GetItemNameByID
    local realAfter = _G.C_Timer.After
    local looks = 0
    _G.C_Item.GetItemNameByID = function(id)
        if id == 2605 then
            looks = looks + 1
            return looks > 2 and "Green Dye" or nil
        end
        return realName(id)
    end
    local waits = {}
    _G.C_Timer.After = function(_, fn) waits[#waits + 1] = fn end
    local said = {}
    local buy = { kind = "buy", items = { { itemID = 2605, count = 2 } } }
    Jobs.SayWhenNamed(buy, function() said[#said + 1] = Words.Short(buy) end)
    suite.check("a line waits while a name is loading", #said == 0 and #waits == 1)
    while #waits > 0 do table.remove(waits, 1)() end
    suite.check("the line names the item once it's in", said[1] == "buy 2 Green Dye from a vendor", tostring(said[1]))
    _G.C_Item.GetItemNameByID = function(id) if id ~= 2605 then return realName(id) end end
    said = {}
    Jobs.SayWhenNamed(buy, function() said[#said + 1] = Words.Short(buy) end)
    while #waits > 0 do table.remove(waits, 1)() end
    suite.check("a name that never comes doesn't hold the line forever", #said == 1)
    _G.C_Item.GetItemNameByID = realName
    _G.C_Timer.After = realAfter
end

-- 8. Wrong shapes and errors.
local clean = Jobs.Clean({ { name = "X", steps = { { kind = "craft" }, { kind = "mail", to = "Y", items = {} },
    "junk", { kind = "dance" } } }, "junk", { steps = {} } })
suite.check("steps of the wrong shape are left out", #clean == 0)
_G.BlackthornesTS.Butler.Jobs = function() error("boom") end
Jobs:Changed()
suite.check("an error shows nothing", #Jobs:Lines() == 0)
env.chat = {}
ns.HandleSlash("jobs")
suite.check("/bbutler jobs says when there are none", env.ChatText():find("no jobs", 1, true) ~= nil)

_G.BlackthornesTS = nil
suite.done()
