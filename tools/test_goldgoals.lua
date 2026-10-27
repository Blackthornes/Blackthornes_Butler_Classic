-- Gold goals at the bottom of the window (the owner said build it
-- 2026-10-13, the purse at the bottom of Butler).
--
-- What must hold:
--   1. Three goals in order: class spells, profession training (the next
--      rank once the skill reaches it, and Tradeskills' trainer recipes),
--      riding. The level cap comes from the game; riding past it is left
--      out, and 60 stands in when the game does not say.
--   2. One purse fills them in order: ready (green), saving, or far
--      (levels away), and gold the gold fund sets aside is not counted.
--   3. A trainer's own price beats Classic's usual one, and is kept.
--   4. The panel sits under the list: the window grows by its height, a
--      click on its heading folds it, and turned off it goes.
--   5. Every character's goals are written down, and All characters lists
--      them with how many are met.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("goldgoals")

local ns = env.Load()
local fake = env.FakeBags({})
local G = 10000
fake.money = 23 * G + 1000

local saved = {}
for _, name in ipairs({ "UnitGUID", "UnitRace", "UnitFactionGroup", "IsPlayerSpell", "C_TradeSkillUI",
    "GetMaxLevelForPlayerExpansion", "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost",
    "GetTrainerServiceLevelReq", "IsTradeskillTrainer", "C_Spell", "BlackthornesTS" }) do
    saved[name] = rawget(_G, name)
end

ns.CLASS_SPELLS = { MAGE = {
    { 1, 4, 1, "Frostbolt" },
    { 2, 20, 2, "Frostbolt", nil, 1 },
    { 3, 20, 1, "Frost Nova" },
    { 4, 24, 1, "Arcane Explosion" },
} }
ns.CLASS_SPELL_PRICES = { [2] = 10 * G, [3] = 6 * G, [4] = 9 * G }

local level, cap, known = 22, 60, { [1] = true }
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitLevel = function() return level end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.UnitFactionGroup = function() return "Alliance" end
_G.UnitName = function(unit) return unit == "npc" and "Riding Rob" or "Elira Dawnmere" end
_G.UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-2-3-4752-0000" or "Player-1-AAA" end
_G.IsPlayerSpell = function(id) return known[id] == true end
_G.GetMaxLevelForPlayerExpansion = function() return cap end
_G.C_Spell = { GetSpellName = function(id)
    return ({ [3913] = "Expert Tailoring", [3912] = "Journeyman Tailoring", [33388] = "Apprentice Riding",
        [33389] = "Apprentice Riding", [3412] = "Journeyman Cook" })[id]
end }

-- Tailoring at 130 of 150 (Expert next, at level 20), First Aid with
-- nothing left to train, and Tailoring listed twice, as Forever does.
local professions = {
    [2948] = { professionName = "Tailoring", skillLevel = 130, maxSkillLevel = 150 },
    [197] = { professionName = "Tailoring", skillLevel = 130, maxSkillLevel = 150 },
    [129] = { professionName = "First Aid", skillLevel = 150, maxSkillLevel = 150 },
}
_G.C_TradeSkillUI = {
    GetAllProfessionTradeSkillLines = function() return { 2948, 197, 129 } end,
    GetProfessionInfoBySkillLineID = function(id) return professions[id] end,
}

local learnAsked = 0
local shownWay
_G.BlackthornesTS = { Butler = {
    LearnCost = function() learnAsked = learnAsked + 1 return { [197] = { skill = 130, count = 9, cost = 7700,
        recipes = { { recipeID = 3914, name = "Brown Linen Pants", cost = 500 }, { recipeID = "bad" } } } } end,
}, LearnNext = { ShowTheWayFor = function(_, id) shownWay = id return true end } }

env.Enable(ns)
local GG = ns.GoldGoals

-- 1 and 2. The goals.
local result = GG:Goals()
local goals = result.goals
suite.check("three goals", #goals == 3, #goals)
suite.check("class spells first, both ready ones", goals[1].kind == "class" and goals[1].count == 2
    and goals[1].cost == 16 * G and goals[1].label == "Class spells: 2 to train", goals[1].label)
suite.check("then the profession: Expert and the trainers' recipes", goals[2].kind == "profession"
    and goals[2].label == "Expert Tailoring and 9 recipes" and goals[2].cost == 4500 + 7700, goals[2].label)
suite.check("Tradeskills is asked once", learnAsked == 1)
suite.check("then riding, at level 40", goals[3].kind == "riding" and goals[3].level == 40
    and goals[3].cost == 900000 and goals[3].guessed, goals[3].label)
suite.check("the class spells are ready", goals[1].state == "ready" and goals[1].have == 16 * G)
suite.check("what is left goes to the next", goals[2].state == "ready" and goals[2].have == 12200)
suite.check("riding gets the rest and is levels away", goals[3].state == "far"
    and goals[3].have == 23 * G + 1000 - 16 * G - 12200)
suite.check("two of three met", result.met == 2)
suite.check("kept until something moves", GG:Goals() == result)

fake.money = 17 * G
ns.Funds:MoneyChanged()
result = GG:Goals()
suite.check("a smaller purse: the profession is still saving", result.goals[2].state == "saving"
    and result.goals[2].short == 2200, result.goals[2].short)

-- The gold fund's top-up for another character is set aside.
local holdings = {
    { key = "Player-1-AAA", short = "Elira Dawnmere", realm = "R", faction = "Alliance", isCurrent = true,
      gold = fake.money, goldAt = 1 },
    { key = "Player-1-BBB", short = "Bram Holloway", realm = "R", faction = "Alliance", gold = 1 * G, goldAt = 1 },
}
_G.BlackthornesTS.Butler.Holdings = function() return holdings end
_G.BlackthornesTS.Butler.Mailbox = function() end
fake.money = 40 * G
ns.Funds:MoneyChanged()
ns.Funds:SetMinimum(3 * G)
result = GG:Goals()
suite.check("gold set aside for an alt isn't counted", result.aside == 2 * G + ns.Funds.POSTAGE
    and result.goals[1].have + result.goals[2].have + result.goals[3].have == 40 * G - result.aside, result.aside)
ns.Funds:SetMinimum(nil)

-- A lower level: the rank waits, the class spells are the next level's.
level = 18
GG:Changed()
result = GG:Goals()
suite.check("the next level's spells, dim", result.goals[1].level == 20 and result.goals[1].state == "far")
suite.check("recipes still count", result.goals[2].label == "9 Tailoring recipes", result.goals[2].label)
level = 22

-- The level cap: 30 in the beta leaves riding out.
cap = 30
GG:Changed()
result = GG:Goals()
suite.check("riding past the cap is left out", #result.goals == 2)
_G.GetMaxLevelForPlayerExpansion = nil
suite.check("60 when the game does not say", GG.MaxLevel() == 60)
_G.GetMaxLevelForPlayerExpansion = function() return cap end
cap = 60

-- Without Tradeskills, only the rank.
local ts = _G.BlackthornesTS
_G.BlackthornesTS = nil
GG:Changed()
suite.check("without Tradeskills, the rank alone", GG:Goals().goals[2].label == "Expert Tailoring")
_G.BlackthornesTS = ts

-- Artisan learned: nothing more to train there.
professions[197].maxSkillLevel, professions[197].skillLevel = 300, 260
professions[2948].maxSkillLevel, professions[2948].skillLevel = 300, 260
GG:Changed()
suite.check("an Artisan has no rank left", GG:Goals().goals[2].label == "9 Tailoring recipes", GG:Goals().goals[2].label)
professions[197].maxSkillLevel, professions[197].skillLevel = 150, 130
professions[2948].maxSkillLevel, professions[2948].skillLevel = 150, 130

-- Apprentice Riding known: Journeyman, at 60.
known[33389] = true
GG:Changed()
suite.check("riding known, the next", GG:Goals().goals[3].riding.spell == 33391 and GG:Goals().goals[3].level == 60)
known[33389] = nil

-- Era: riding is one skill a race, read from the skill list. 75 waits for
-- the next one; 150 is the last, so no riding goal is left.
local savedName, savedLines, savedLine = GG.SpellName, rawget(_G, "GetNumSkillLines"), rawget(_G, "GetSkillLineInfo")
local riding = 75
GG.SpellName = function(id) if id == 824 then return "Horse Riding" end return savedName(id) end
_G.GetNumSkillLines = function() return 2 end
_G.GetSkillLineInfo = function(i)
    if i == 1 then return "Secondary Skills", true end
    return "Horse Riding", false, nil, riding
end
level = 60
GG:Changed()
suite.check("Era riding at 75, the next", GG.RidingSkill() == 75 and GG:NextRiding(60).spell == 33391)
riding = 150
GG:Changed()
suite.check("Era riding at 150, nothing left", GG:NextRiding(60) == nil)
GG.SpellName, _G.GetNumSkillLines, _G.GetSkillLineInfo = savedName, savedLines, savedLine
level = 22
GG:Changed()

-- 3. A riding trainer's own price.
local services = { { "Apprentice Riding", "", "unavailable", 80 * G, 30 } }
_G.IsTradeskillTrainer = function() return false end
_G.GetNumTrainerServices = function() return #services end
_G.GetTrainerServiceInfo = function(i) return services[i][1], services[i][2], services[i][3] end
_G.GetTrainerServiceCost = function(i) return services[i][4] end
_G.GetTrainerServiceLevelReq = function(i) return services[i][5] end
env.Fire("TRAINER_SHOW")
local kept = GG:Data().prices[33388]
suite.check("the trainer's price and level are kept", kept and kept.cost == 80 * G and kept.level == 30)
result = GG:Goals()
suite.check("and win over the usual", result.goals[3].cost == 80 * G and result.goals[3].level == 30
    and not result.goals[3].guessed)
env.Fire("TRAINER_CLOSED")

-- 4. The window.
fake.money = 23 * G + 1000
ns.Funds:MoneyChanged()
local UI, GoalsUI = ns.UI, ns.GoldGoalsUI
UI:Show("bags")
suite.check("the panel shows under the list", GoalsUI.panel:IsShown())
suite.check("a row a goal", GoalsUI.rows[1]:IsShown() and GoalsUI.rows[3]:IsShown())
suite.check("the purse in the heading", GoalsUI.head.purse:GetText():find("purse", 1, true) ~= nil)
suite.check("ready says so", GoalsUI.rows[1].value:GetText() == "Ready")
suite.check("the window grows by it", UI.frame:GetHeight() > 500 and UI.goalsExtra > 0)
local open = UI.frame:GetHeight()
GoalsUI.head:GetScript("OnClick")(GoalsUI.head)
suite.check("a click folds it", ns.charDB.folded.goldGoals == true and not GoalsUI.rows[1]:IsShown()
    and UI.frame:GetHeight() < open)
GoalsUI.head:GetScript("OnClick")(GoalsUI.head)
suite.check("and opens it", GoalsUI.rows[1]:IsShown() and UI.frame:GetHeight() == open)
GameTooltip.AddDoubleLine = function(self, left) self._lines[#self._lines + 1] = left end
GoalsUI.rows[2]:GetScript("OnEnter")(GoalsUI.rows[2])
local lines = table.concat(GameTooltip._lines, "\n")
suite.check("a row's tooltip lists what it is for", lines:find("Expert Tailoring and 9 recipes", 1, true) ~= nil, lines)
suite.check("the hover names each recipe", lines:find("Brown Linen Pants", 1, true) ~= nil, lines)
suite.check("and says a click shows the way", lines:find("Click to show the way to your trainer.", 1, true) ~= nil, lines)
GoalsUI.rows[2]:GetScript("OnClick")(GoalsUI.rows[2])
suite.check("a click shows the way to the recipe's trainer", shownWay == 3914, tostring(shownWay))
shownWay = nil
GoalsUI.rows[1]:GetScript("OnClick")(GoalsUI.rows[1])
suite.check("other goals do nothing on a click", shownWay == nil)

-- 5. Every character.
local data = GG:Data().characters
suite.check("this character's goals are written down", data["Player-1-AAA"] and #data["Player-1-AAA"].goals == 3)
data["Player-1-BBB"] = { name = "Bram Holloway", level = 18, className = "Warrior", money = 2 * G,
    goals = { { kind = "class", cost = 1 * G, label = "Class spells: 1 to train" },
        { kind = "riding", cost = 900000, level = 40, label = "Apprentice Riding at level 40" } }, at = 1 }
local everyone = GG:Everyone()
suite.check("you first, then the others", everyone[1].isCurrent and everyone[2].name == "Bram Holloway")
suite.check("their goals filled from their gold", everyone[2].met == 1)
UI:SetView("all")
suite.check("All characters lists them under the list", GoalsUI.rows[2]:IsShown()
    and GoalsUI.rows[2].label:GetText():find("Bram Holloway", 1, true) ~= nil)
suite.check("with how many are met", GoalsUI.rows[2].value:GetText() == "1 of 2 met", GoalsUI.rows[2].value:GetText())
UI:SetView("bags")

-- Turned off.
ns.HandleSlash("goals off")
suite.check("off is saved", ns.db.goldGoals == false)
suite.check("the panel goes and the window shrinks back", not GoalsUI.panel:IsShown() and UI.frame:GetHeight() == 500)
ns.HandleSlash("goals on")
suite.check("on again", GoalsUI.panel:IsShown())
ns.HandleSlash("goals")
suite.check("the command lists them", env.ChatText():find("Expert Tailoring and 9 recipes", 1, true) ~= nil)
-- A goal levels away takes only what the goals you can buy now leave.
local filled = { { cost = 2 * G, level = 20 }, { cost = 45 * 100 }, { cost = 100 * G, level = 40 } }
local filledMet = GG.Fill(filled, 2 * G + 20 * 100)
suite.check("a goal you can pay now is ready though a far one comes first",
    filled[2].state == "ready" and filled[2].have == 45 * 100 and filledMet == 1)
suite.check("the far one gets the rest", filled[1].state == "far" and filled[1].have == 2 * G + 20 * 100 - 45 * 100)
suite.check("and the one after it nothing", filled[3].have == 0)

-- Each profession its own goal (2026-10-23): a rank and another
-- profession's recipes are two rows, cheapest first, and each click goes to
-- its own trainer.
professions[2948] = nil
professions[197] = { professionName = "Tailoring", skillLevel = 130, maxSkillLevel = 300 }
professions[333] = { professionName = "Enchanting", skillLevel = 130, maxSkillLevel = 150 }
_G.C_TradeSkillUI.GetAllProfessionTradeSkillLines = function() return { 197, 333, 129 } end
GG:Changed()
local split = GG:Goals().goals
suite.check("class, two professions and riding", #split == 4, #split)
suite.check("the cheaper one first: the rank", split[2].kind == "profession"
    and split[2].label == "Expert Enchanting" and split[2].cost == 5000, split[2].label)
suite.check("then the other profession's recipes, named", split[3].kind == "profession"
    and split[3].label == "9 Tailoring recipes" and split[3].cost == 7700, split[3].label)
local askedLine, askedTeaches, shownPlace
_G.BlackthornesTS.LearnNext.TrainerFor = function(_, line, teaches)
    askedLine, askedTeaches = line, teaches
    return { kind = "trainer", name = "Enchanting Trainer", zone = "Stormwind City", x = 50, y = 50 }
end
_G.BlackthornesTS.LearnNext.ShowTheWay = function(_, row) shownPlace = row.place.name return true end
shownWay = nil
suite.check("the rank's row can show the way", GoalsUI.CanShowWay(split[2]))
GG:ShowTheWay(split[2])
suite.check("the rank's click goes to its trainer", shownPlace == "Enchanting Trainer"
    and askedLine == 333 and askedTeaches == 225 and shownWay == nil, tostring(shownPlace))
shownPlace = nil
GG:ShowTheWay(split[3])
suite.check("the recipes' click goes to the recipe's trainer", shownPlace == nil and shownWay == 3914)
level = 18
GG:Changed()
local waiting = GG:Goals().goals
suite.check("a rank levels away keeps its own row, after the rest",
    waiting[2].label == "9 Tailoring recipes" and waiting[3].label == "Expert Enchanting at level 20"
    and waiting[3].state == "far", waiting[3] and waiting[3].label)
level = 22

UI:Hide()

for name, value in pairs(saved) do _G[name] = value end

suite.done()
