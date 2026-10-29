-- Class spells to train (the owner said build it 2026-10-13).
--
-- What must hold:
--   1. Ready now: spells at or below the level, not known, whose rank
--      before is known or trained first; never another race's spell or one
--      no trainer teaches.
--   2. The next level's spells are listed apart.
--   3. A class trainer's window keeps prices, what it does not teach and
--      where it stands; the filter is put back as it was.
--   4. Train all buys one at a time, only what the purse pays for.
--   5. The Jobs group leads with the spells to train, and other
--      characters' waiting spells, only for characters on this realm and
--      side.
--   6. The gold fund keeps back what this character's spells cost and
--      tops up another character for theirs.
--   7. Turned off, nothing shows and no gold is kept back.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("classtraining")

local ns = env.Load()
local fake = env.FakeBags({})
fake.money = 100 * 10000

local G = 10000
local saved = {}
for _, name in ipairs({ "UnitGUID", "UnitRace", "UnitFactionGroup", "IsPlayerSpell", "GetNumTrainerServices",
    "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceLevelReq", "BuyTrainerService",
    "GetTrainerServiceTypeFilter", "SetTrainerServiceTypeFilter", "IsTradeskillTrainer",
    "GetRealZoneText", "GetSubZoneText" }) do
    saved[name] = rawget(_G, name)
end

-- A small spell list: { id, level, rank, name, races, rank before }.
ns.CLASS_SPELLS = { MAGE = {
    { 1, 4, 1, "Frostbolt" },
    { 2, 8, 2, "Frostbolt", nil, 1 },
    { 3, 10, 1, "Frost Nova" },
    { 4, 12, 3, "Frostbolt", nil, 2 },
    { 5, 12, 1, "Gnome Trick", { 7 } },
    { 6, 12, 1, "Quest Spell" },
    { 7, 12, 2, "Talent Thing", nil, 99 },
    { 8, 14, 1, "Arcane Explosion" },
    { 9, 14, 1, "Flamestrike" },
    { 10, 16, 1, "Later Spell" },
} }

-- Classic's price for Frost Nova, until a trainer says 200.
ns.CLASS_SPELL_PRICES = { [3] = 150 }

local level, known = 12, { [1] = true }
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitLevel = function() return level end
_G.UnitRace = function() return "Human", "Human", 1 end
_G.UnitFactionGroup = function() return "Alliance" end
_G.UnitName = function(unit) return unit == "npc" and "Jennea Cannon" or "Me Here" end
_G.UnitGUID = function(unit)
    if unit == "npc" then return "Creature-0-1-2-3-5498-0000" end
    return "Player-1-AAA"
end
_G.IsPlayerSpell = function(id) return known[id] == true end
_G.GetRealZoneText = function() return "Stormwind City" end
_G.GetSubZoneText = function() return "Wizard's Sanctum" end
_G.C_Map = {
    GetBestMapForUnit = function() return 1453 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.38, 0.79 end } end,
}

env.Enable(ns)
local CT, Jobs, Funds = ns.ClassTraining, ns.Jobs, ns.Funds

-- 1. Ready now.
local plan = CT:Plan()
local ids = {}
for _, spell in ipairs(plan.ready) do ids[#ids + 1] = spell.id end
suite.check("ready: rank 2, Frost Nova, rank 3 after rank 2, the quest spell",
    table.concat(ids, ",") == "2,3,4,6", table.concat(ids, ","))
suite.check("never another race's spell", not table.concat(ids, ","):find("5"))
suite.check("never a rank whose rank before nobody here has", not table.concat(ids, ","):find("7"))
suite.check("Classic's price stands in until a trainer is seen", plan.cost == 150 and plan.unknown == 3
    and plan.guessed == 1, plan.cost .. " " .. plan.unknown)

-- 2. The next level.
suite.check("the next level is 14", plan.nextLevel == 14 and #plan.next == 2)

-- 2b. The game can drop an older rank from the book once a newer one is
-- learned: knowing Frostbolt Rank 2 alone means Rank 1 is known too.
known = { [2] = true }
CT:Changed()
plan = CT:Plan()
ids = {}
for _, spell in ipairs(plan.ready) do ids[#ids + 1] = spell.id end
suite.check("an older rank is never offered once a newer one is known",
    table.concat(ids, ",") == "3,4,6", table.concat(ids, ","))
suite.check("the ranks before a known one count as known", CT.KnownIn(ns.CLASS_SPELLS.MAGE)[1] == true)
known = { [1] = true }
CT:Changed()
plan = CT:Plan()

-- 2c. A spell skipped in Equipment's Training drawer (2026-10-22) leaves
-- the plan, so the gold goal and the gold kept back follow; Equipment's
-- copy is read through its global, the newest change winning.
local cost = CT:Plan().cost
_G.BlackthornesEquipment = { ClassTraining = {
    OwnSkips = function() return { [3] = 100 } end,
    KeepSkip = function() end,
} }
CT:Changed()
plan = CT:Plan()
ids = {}
for _, spell in ipairs(plan.ready) do ids[#ids + 1] = spell.id end
suite.check("a spell skipped in Equipment leaves the list", not table.concat(ids, ","):find("3")
    and #plan.skipped == 1, table.concat(ids, ","))
suite.check("and the cost the gold goal counts", plan.cost < cost or plan.unknown < 3, plan.cost .. " " .. cost)
CT:SetSkipped(3, false)
_G.BlackthornesEquipment = nil
suite.check("brought back here, it is ready again", CT:IsSkipped(3) == false and #CT:Plan().skipped == 0)
CT:Data().skipped = {}
CT:Changed()
plan = CT:Plan()

-- 3. At a class trainer. The list hides spells not learnable yet; the
-- addon shows them to read prices, then hides them again.
local filterShown = false
local filterSets = {}
local services = {
    { "Frostbolt", "Rank 2", "available", 100, 8, 2 },
    { "Frost Nova", "", "available", 200, 10, 3 },
    { "Frostbolt", "Rank 3", "available", 300, 12, 4 },
    { "Arcane Explosion", "", "unavailable", 1000, 14, 8 },
    { "Flamestrike", "", "unavailable", 1200, 14, 9 },
}
local function Shown()
    local list = {}
    for _, s in ipairs(services) do
        if s[3] ~= "unavailable" or filterShown then list[#list + 1] = s end
    end
    return list
end
_G.IsTradeskillTrainer = function() return false end
_G.GetTrainerServiceTypeFilter = function(kind) return kind ~= "unavailable" or filterShown end
_G.SetTrainerServiceTypeFilter = function(kind, on)
    filterSets[#filterSets + 1] = kind .. "=" .. tostring(on)
    if kind == "unavailable" then filterShown = on == 1 end
end
_G.GetNumTrainerServices = function() return #Shown() end
_G.GetTrainerServiceInfo = function(i) local s = Shown()[i] return s[1], s[2], s[3] end
_G.GetTrainerServiceCost = function(i) return Shown()[i][4] end
_G.GetTrainerServiceLevelReq = function(i) return Shown()[i][5] end
local boughtIndex = {}
_G.BuyTrainerService = function(i)
    local s = Shown()[i]
    boughtIndex[#boughtIndex + 1] = s[1] .. " " .. s[2]
    fake.money = fake.money - s[4]
    s[3] = "used"
    known[s[6]] = true
end

env.Fire("TRAINER_SHOW")
local data = CT:Data()
suite.check("prices kept, the later ones too", data.prices[2] == 100 and data.prices[3] == 200
    and data.prices[8] == 1000 and data.prices[9] == 1200)
suite.check("the filter is put back as it was", not filterShown and #filterSets == 2)
suite.check("a spell the trainer doesn't list is not taught there", data.notTaught[6] == true)
suite.check("a spell it lists is", not data.notTaught[2])
suite.check("another race's spell is not marked", not data.notTaught[5])
local spot = data.trainers.MAGE and data.trainers.MAGE[5498]
suite.check("the trainer's spot is kept", spot and spot.name == "Jennea Cannon" and spot.mapID == 1453
    and spot.x == 0.38 and spot.zone == "Stormwind City")
suite.check("it says where", CT.Where(spot) == "Wizard's Sanctum in Stormwind City")
plan = CT:Plan()
suite.check("the trainer's own price wins", plan.guessed == 0)
suite.check("the quest spell leaves the list", #plan.ready == 3 and plan.cost == 600 and plan.unknown == 0,
    #plan.ready .. " " .. plan.cost)
suite.check("the next level is priced", plan.nextCost == 2200 and plan.nextUnknown == 0)
suite.check("this character is written down", data.characters["Player-1-AAA"]
    and #data.characters["Player-1-AAA"].ready == 3)

-- 5. The Jobs group leads with it.
local rows = Jobs:TrainingLines()
suite.check("a row for now and one for the next level", rows[1] and rows[1].type == "train"
    and rows[2] and rows[2].type == "trainnext")
local jobRows = Jobs:Lines()
suite.check("Jobs leads with the spells to train now only", jobRows[1] and jobRows[1].type == "train"
    and not (jobRows[2] and jobRows[2].type == "trainnext"))
local later = Jobs:LaterLines()
suite.check("the next level waits under Later", later[1] and later[1].type == "trainnext")

-- 4. Train all, with the purse short for the last.
fake.money = 350
CT:TrainAll()
suite.check("bought one at a time, cheapest level first, while the purse pays",
    table.concat(boughtIndex, ",") == "Frostbolt Rank 2,Frost Nova ", table.concat(boughtIndex, ","))
suite.check("and says so", env.ChatText():find("trained 2 spells", 1, true) ~= nil)
suite.check("the rest waits", #CT:Plan().ready == 1 and CT:Plan().ready[1].id == 4, #CT:Plan().ready .. " " .. tostring(CT:Plan().ready[1] and CT:Plan().ready[1].id))
fake.money = 100 * G
-- A buy the game quietly refuses is tried once, not every step.
local realBuy, refused = _G.BuyTrainerService, 0
_G.BuyTrainerService = function() refused = refused + 1 end
CT:TrainAll()
_G.BuyTrainerService = realBuy
suite.check("a refused buy is tried once a run", refused == 1 and not CT.buying, refused)
CT:TrainAll()
suite.check("the next click trains the last", known[4] == true and #CT:Plan().ready == 0)
env.Fire("TRAINER_CLOSED")
suite.check("closed, nothing more can be bought", #CT:Buyable() == 0)

-- 6. The gold fund. Another character with spells waiting.
level = 14
CT:Changed()
data.characters["Player-1-BBB"] = { name = "Bob Stone", class = "MAGE", level = 14, ready = { 8, 9 }, at = 1 }
local holdings = {
    { key = "Player-1-AAA", short = "Me Here", realm = "R", faction = "Alliance", isCurrent = true, gold = fake.money, goldAt = 1 },
    { key = "Player-1-BBB", short = "Bob Stone", realm = "R", faction = "Alliance", gold = 10 * G, goldAt = 1 },
}
_G.BlackthornesTS = { Butler = { Holdings = function() return holdings end, Mailbox = function() end } }
Funds:SetMinimum(10 * G)
local fund = Funds:For("Bob Stone")
suite.check("an alt's training is added to its amount", fund and fund.amount == 2200, fund and fund.amount)
suite.check("and the row says why", fund and Funds.Reason(fund):find("to train new spells", 1, true) ~= nil)
fake.money = 10 * G + 2200 + 2200 + Funds.POSTAGE
Funds:MoneyChanged()
fund = Funds:For("Bob Stone")
suite.check("the sender keeps back its own training first", fund and fund.amount == 2200, fund and fund.amount)
fake.money = 10 * G + 2200 + 1000
Funds:MoneyChanged()
fund = Funds:For("Bob Stone")
suite.check("so it gives only what is left", fund and fund.amount == 1000 - Funds.POSTAGE, fund and fund.amount)

rows = Jobs:TrainingLines()
local alt
for _, row in ipairs(rows) do if row.type == "trainalt" then alt = row end end
suite.check("the other character has its own line", alt and alt.other.name == "Bob Stone" and alt.other.count == 2)
local laterAlt
for _, row in ipairs(Jobs:LaterLines()) do if row.type == "trainalt" then laterAlt = row end end
suite.check("and it waits under Later", laterAlt ~= nil)
for _, row in ipairs(Jobs:Lines()) do
    suite.check("not in Jobs", row.type ~= "trainalt" and row.type ~= "trainnext")
end

-- 5b. Only characters on this realm and side (a player saw the other
-- side's and other realms' characters, 2026-10-18).
local savedRealm = rawget(_G, "GetRealmName")
_G.GetRealmName = function() return "R" end
data.characters["Player-1-HHH"] = { name = "Hord Guy", class = "MAGE", level = 14, realm = "R",
    faction = "Horde", ready = { 8 }, at = 1 }
data.characters["Player-2-OOO"] = { name = "Far Away", class = "MAGE", level = 14, realm = "Other",
    faction = "Alliance", ready = { 8 }, at = 1 }
data.characters["Player-2-OLD"] = { name = "Old Note", class = "MAGE", level = 14, ready = { 8 }, at = 1 }
data.characters["Player-1-NEW"] = { name = "Fresh Note", class = "MAGE", level = 14,
    faction = "Alliance", ready = { 8 }, at = 1 }
local names = {}
for _, other in ipairs(CT:Others()) do names[other.name] = true end
suite.check("an alt on this realm and side is listed", names["Bob Stone"] and names["Fresh Note"])
suite.check("the other side is not", not names["Hord Guy"])
suite.check("another realm is not", not names["Far Away"])
suite.check("a note with no side known is not", not names["Old Note"])
holdings[#holdings + 1] = { key = "Player-2-OLD", short = "Old Note", realm = "R", faction = "Alliance" }
names = {}
for _, other in ipairs(CT:Others()) do names[other.name] = true end
suite.check("Tradeskills' record fills in an old note", names["Old Note"])
table.remove(holdings)
CT:Note()
suite.check("this character's note keeps its side", data.characters["Player-1-AAA"].faction == "Alliance"
    and data.characters["Player-1-AAA"].realm == "R")
for _, key in ipairs({ "Player-1-HHH", "Player-2-OOO", "Player-2-OLD", "Player-1-NEW" }) do
    data.characters[key] = nil
end
_G.GetRealmName = savedRealm

-- 8. A spell the character knows is never offered (a player was told to
-- train spells known a long time, 2026-10-19).
-- The data skips a rank now and then: a known higher rank still covers
-- every lower one of that name.
local gap = {
    { 20, 22, 4, "Holy Light", nil, 19 },
    { 21, 38, 6, "Holy Light" },
    { 22, 46, 7, "Holy Light", nil, 21 },
}
local savedKnown = known
known = { [22] = true }
local gapKnown = CT.KnownIn(gap)
suite.check("a lower rank past a gap in the data is known", gapKnown[20] and gapKnown[21] and gapKnown[22])
known = { [21] = true }
suite.check("a higher rank is not known from a lower one", not CT.KnownIn(gap)[22])

-- A trainer's "learned" line counts as known, whatever the client says.
level = 14
known = { [4] = true }
services = {
    { "Frost Nova", "", "used", 200, 10, 3 },
    { "Arcane Explosion", "", "available", 1000, 14, 8 },
    { "Flamestrike", "", "available", 1200, 14, 9 },
}
env.Fire("TRAINER_SHOW")
local learned = data.learned["Player-1-AAA"]
suite.check("the trainer's learned line is kept for this character", learned and learned[3] == true)
CT:Changed()
ids = {}
for _, spell in ipairs(CT:Plan().ready) do ids[#ids + 1] = spell.id end
suite.check("and never offered again", not ("," .. table.concat(ids, ",") .. ","):find(",3,", 1, true),
    table.concat(ids, ","))
suite.check("nor marked as not taught", not data.notTaught[3])
env.Fire("TRAINER_CLOSED")

-- A trainer line in another language matches by name and the rank's number.
local german = CT:ServiceSpell(1, "Frostbolt", "Rang 3", "MAGE")
suite.check("\"Rang 3\" finds Rank 3", german and german[1] == 4)
data.learned["Player-1-AAA"] = nil
known = savedKnown
level = 14
CT:Changed()

-- 6a. Show the way aims Butler's own arrow (Logic/WayArrow.lua) at the
-- trainer, not a map pin.
suite.check("Butler's arrow takes Show the way", type(CT.Guide) == "function")
local pinned = false
_G.UiMapPoint = { CreateFromCoordinates = function() return {} end }
C_Map.SetUserWaypoint = function() pinned = true end
ns.WayArrow:Clear()
suite.check("Show the way aims Butler's arrow", CT:ShowTheWay() == true)
local place = ns.WayArrow:Place()
suite.check("at the trainer", place and place.name and place.name:find("Jennea Cannon", 1, true) ~= nil
    and place.x and place.x > 0 and place.x < 1, place and place.name)
suite.check("the arrow shows", ns.WayArrow:IsOn())
suite.check("no map pin behind it", not pinned)
-- Our own marker goes on the map too, since Forever turns the game's pin
-- down (a German player found nothing at the Crossroads, 2026-10-29).
local light = ns.SpotMarker and ns.SpotMarker.current
suite.check("our marker on the trainer's spot", light and light.name == "Jennea Cannon"
    and light.map == place.map and math.abs(light.x - place.x * 100) < 0.001, light and light.name)
suite.check("it goes when you stand there", light and light.arrow == ns.WayArrow and not light.gamePin)
ns.SpotMarker:Clear()
ns.WayArrow:Clear()
suite.check("its close puts it away", not ns.WayArrow:IsOn() and ns.charDB.wayArrowPlace == nil)

-- 6b. Without Butler's own arrow, Show the way moves Equipment's arrow when
-- Equipment is loaded, not a map pin behind it (a player saw the quest
-- arrow stay put).
local ownGuide = CT.Guide
CT.Guide = nil
local aimed
_G.BlackthornesEquipment = { ClassTraining = { Guide = function(spot, title)
    aimed = { spot = spot, title = title }
    return true
end } }
pinned = false
suite.check("Show the way finds somewhere to go", CT:ShowTheWay() == true)
suite.check("Equipment's arrow is aimed at the trainer", aimed and aimed.spot
    and aimed.spot.name == "Jennea Cannon" and aimed.title:find("Jennea Cannon", 1, true) ~= nil)
suite.check("no map pin when the arrow took it", not pinned)
_G.BlackthornesEquipment = { ClassTraining = { Guide = function() error("broken") end } }
suite.check("a broken arrow falls back to the map pin", CT:ShowTheWay() == true and pinned)
_G.BlackthornesEquipment = nil

-- A trainer far away with "Guide Me:" ticked (Logic/Travel.lua): the pin
-- goes on the first stop and chat lists the steps.
local realTravel, pinMap = ns.Travel, nil
ns.Travel = { IsOn = function() return true end, Guide = function()
    return { lines = { "1. Take the boat to Theramore" }, point = { map = 1413, x = 0.5, y = 0.4, name = "Take the boat to Theramore" } }
end }
_G.UiMapPoint = { CreateFromCoordinates = function(map) pinMap = map return {} end }
suite.check("guided: somewhere to go", CT:ShowTheWay() == true)
suite.check("the pin is on the first stop", pinMap == 1413, tostring(pinMap))
ns.Travel = realTravel
_G.UiMapPoint = nil
C_Map.SetUserWaypoint = nil
CT.Guide = ownGuide

-- 7. Turned off.
ns.HandleSlash("training off")
suite.check("off is saved", ns.db.classTraining == false)
suite.check("no rows", #Jobs:TrainingLines() == 0)
suite.check("no gold kept back", CT:ReadyCost() == 0)
ns.HandleSlash("training on")
suite.check("and on again", CT:IsOn())

-- The window draws the rows without error.
ns.UI:Show("bags")
suite.check("the window shows with training rows", ns.UI:IsShown())
ns.UI:Hide()

for name, value in pairs(saved) do _G[name] = value end
_G.BlackthornesTS = nil
_G.C_Map = nil

suite.done()
