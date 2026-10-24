-- The Classic Era copy.
--
-- This repo is Butler for WoW Classic Era. Classic's own data fits Era and
-- stays; what Forever's client tables gave (sell prices and bag families,
-- Data/ForeverItems.lua) does not, so the TOC leaves it out, and the TOC
-- must never point a tag at the Forever project on CurseForge. Forever's own
-- class spells are left out at runtime. Then the addon has to load, log in,
-- judge the bags and open its window with no sister addon loaded, since Era
-- may have none of them.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("era")

local handle = assert(io.open(lfs_cwd .. "/Blackthornes_Butler.toc", "r"))
local toc = handle:read("*a")
handle:close()

suite.check("the TOC is not Forever's", not toc:find("## Interface: 16001", 1, true))
suite.check("the TOC names a Classic Era interface", toc:find("## Interface: 115", 1, true) ~= nil)
suite.check("the TOC never names Forever's CurseForge project",
    not toc:find("^## X%-Curse%-Project%-ID:%s*1739020") and not toc:find("\n## X%-Curse%-Project%-ID:%s*1739020"))
suite.check("the TOC leaves out Forever's item table", not toc:find("\nData\\ForeverItems.lua", 1, true))
suite.check("the TOC keeps the class spells", toc:find("\nData\\ClassSpells.lua", 1, true) ~= nil)
suite.check("the TOC keeps the quest items", toc:find("\nData\\QuestItems.lua", 1, true) ~= nil)

-- Loading as Era does: no sister addons, no new auction house.
_G.BlackthornesTS, _G.BlackthornesFarmer, _G.BlackthornesEquipment, _G.BlackthornesPets = nil, nil, nil, nil
_G.C_AuctionHouse = nil
local ns = env.Load()
suite.check("no Forever item table", ns.ForeverItems == nil)

local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 2589, name = "Linen Cloth", quality = 1, price = 13, count = 5 },
    { bag = 0, slot = 2, id = 4865, name = "Ruined Pelt", quality = 0, price = 5 },
})

local boot = ns.modules.Bootstrap
local ok, err = pcall(function()
    boot:ADDON_LOADED("ADDON_LOADED", "Blackthornes_Butler")
    boot:PLAYER_LOGIN()
end)
suite.check("it loads and logs in", ok, err)

local shown, why = pcall(function() ns.UI:Show() end)
suite.check("the window opens", shown and ns.UI:IsShown(), why)
local judged, groups = pcall(function() return ns.Verdicts:Groups() end)
suite.check("the bags are judged", judged and type(groups) == "table", groups)
suite.check("no auction house buying without the new auction house", not ns.QuestBuy:Shows())

-- Class spells: Forever's own (1,000,000 and up) and any the client lacks
-- are left out, and a rank whose rank before went points past it.
local CT = ns.ClassTraining
ns.CLASS_SPELLS = { MAGE = {
    { 116, 4, 1, "Frostbolt" },
    { 1239696, 30, 2, "Arcane Blast", nil, 30451 },
    { 205, 8, 2, "Frostbolt", nil, 116 },
    { 777, 10, 3, "Frostbolt", nil, 205 },
    { 778, 12, 4, "Frostbolt", nil, 777 },
} }
_G.C_Spell = _G.C_Spell or {}
local saved = _G.C_Spell.DoesSpellExist
_G.C_Spell.DoesSpellExist = function(id) return id ~= 777 end
local list = CT.Spells("MAGE")
local ids = {}
for _, entry in ipairs(list) do ids[entry[1]] = entry end
suite.check("Forever's own spell is left out", ids[1239696] == nil)
suite.check("a spell the client lacks is left out", ids[777] == nil)
suite.check("the others stay", ids[116] and ids[205] and ids[778] and #list == 3, #list)
suite.check("the rank after the missing one follows the one before it", ids[778][6] == 205, ids[778][6])
suite.check("the data itself is left alone", ns.CLASS_SPELLS.MAGE[5][6] == 777)
suite.check("a class the data lacks has nothing", CT.Spells("NOBODY") == nil)
_G.C_Spell.DoesSpellExist = saved

suite.done()
