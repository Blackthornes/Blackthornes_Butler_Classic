-- Who has it: item tooltips list which characters hold the item and where,
-- from Tradeskills' Holdings. A hover only reads the kept lookup; bag events
-- only mark it stale, and it is built again at most once a second. Only
-- GameTooltip and ItemRefTooltip get lines, and nothing is written on them.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("whohas")

local ns = env.Load()
env.FakeBags({})

local clock = 100
_G.GetTime = function() return clock end

-- The post call, as Forever has it.
local postCalls = {}
_G.Enum = { TooltipDataType = { Item = 0 } }
_G.TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn) postCalls[#postCalls + 1] = { kind = kind, fn = fn } end,
}

local function Double(self, left, right) self._lines[#self._lines + 1] = left .. " | " .. right end
_G.GameTooltip.AddDoubleLine = Double
_G.ItemRefTooltip.AddDoubleLine = Double
local compare = env.Stub({ _lines = {} })

-- Tradeskills: Ana Stone (playing, and an old record of her), Bob Wither,
-- and Mia Thorn.
local asked = 0
local holdings
_G.BlackthornesTS = { Butler = { Holdings = function()
    asked = asked + 1
    return holdings
end } }
holdings = {
    { key = "Player-1", name = "Ana Stone", isCurrent = true, playing = true,
        bags = { [501] = 4, [502] = 3 }, bank = { [501] = 8 }, mail = {} },
    { key = "Ana-Realm", name = "Ana Stone", isCurrent = false, playing = true,
        bags = { [501] = 99 }, bank = {}, mail = {} },
    { key = "Player-2", name = "Bob Wither", bags = { [501] = 20 }, bank = {}, mail = { [501] = 1 } },
    { key = "Player-3", name = "Mia Thorn", bags = {}, bank = { [503] = 2 }, mail = {} },
}

env.Enable(ns)
local WhoHas = ns.WhoHas

suite.check("hooked through the post call, once", WhoHas.installed == "post call"
    and #postCalls == 1 and postCalls[1].kind == 0)

local function Hover(tooltip, itemID)
    tooltip._lines = {}
    postCalls[1].fn(tooltip, { id = itemID })
    return tooltip._lines
end

local lines = Hover(GameTooltip, 501)
suite.check("a heading with the total", lines[2] == "Your characters have 33", table.concat(lines, " / "))
suite.check("most first, by full name", lines[3] == "Bob Wither | 21 (20 bags, 1 mail)", lines[3])
suite.check("the character playing is marked, bags and bank", lines[4] == "Ana Stone (you) | 12 (4 bags, 8 bank)", lines[4])
suite.check("an old record of the character playing is not counted again", #lines == 4, #lines)
suite.check("one Holdings call for the hover", asked == 1, asked)

lines = Hover(GameTooltip, 503)
suite.check("one place reads as words", lines[3] == "Mia Thorn | 2 in the bank", lines[3])

lines = Hover(GameTooltip, 502)
suite.check("only in your own bags says nothing", #lines == 0, table.concat(lines, " / "))
lines = Hover(GameTooltip, 999)
suite.check("nobody has it says nothing", #lines == 0)

lines = Hover(ItemRefTooltip, 501)
suite.check("a linked item's tooltip gets the lines too", lines[2] == "Your characters have 33")
lines = Hover(compare, 501)
suite.check("a compare tooltip gets none", #lines == 0)

suite.check("hovers read the kept lookup", asked == 1, asked)

-- A burst of loot: events only mark it stale, one rebuild on the next hover.
holdings[1].bags[501] = 10
for _ = 1, 5 do env.Fire("BAG_UPDATE_DELAYED") end
suite.check("bag events do no work", asked == 1, asked)
clock = clock + 0.4
lines = Hover(GameTooltip, 501)
suite.check("within a second of the last build the old lookup stands", asked == 1 and lines[2] == "Your characters have 33")
clock = clock + 1
lines = Hover(GameTooltip, 501)
suite.check("then it is built once more", asked == 2 and lines[2] == "Your characters have 39", lines[2])
Hover(GameTooltip, 501)
suite.check("and kept again", asked == 2)

-- More characters than fit.
for i = 1, 7 do
    holdings[#holdings + 1] = { key = "Alt-" .. i, name = "Alt Number" .. i, bags = { [503] = 1 }, bank = {}, mail = {} }
end
env.Fire("MAIL_CLOSED")
clock = clock + 2
lines = Hover(GameTooltip, 503)
suite.check("six names, then how many more", #lines == 9 and lines[9] == "and 2 more characters", lines[9])

-- Secret or broken data never raises.
GameTooltip._lines = {}
postCalls[1].fn(GameTooltip, { id = setmetatable({}, { __add = function() error("secret") end }) })
suite.check("an unreadable item says nothing", #GameTooltip._lines == 0)
_G.BlackthornesTS.Butler.Holdings = function() error("broken") end
env.Fire("BAG_UPDATE_DELAYED")
clock = clock + 2
lines = Hover(GameTooltip, 501)
suite.check("a Tradeskills that raises gives no lines", #lines == 0)

-- The setting.
_G.BlackthornesTS.Butler.Holdings = function() return holdings end
env.Fire("BAG_UPDATE_DELAYED")
clock = clock + 2
ns.HandleSlash("whohas")
suite.check("/bbutler whohas turns it off", ns.db.whoHas == false and #Hover(GameTooltip, 501) == 0)
ns.HandleSlash("whohas")
suite.check("and back on", ns.db.whoHas == true and #Hover(GameTooltip, 501) > 0)
suite.check("the probe says how it is hooked", WhoHas:ProbeText():find("post call", 1, true) ~= nil)

-- Another realm or side's characters, shared or not, add no lines.
_G.BlackthornesTS.Butler.Holdings = function()
    return {
        { key = "me", name = "Mia", isCurrent = true, realm = "Home", faction = "Horde", bags = {} },
        { key = "alt", name = "Ana", realm = "Home", faction = "Horde", bags = { [701] = 2 } },
        { key = "far", name = "Far", realm = "Away", faction = "Alliance", linked = "Helper",
          bags = { [701] = 50 } },
    }
end
local lookup = WhoHas.Build()
suite.check("only this realm and side's characters are counted",
    lookup[701] and lookup[701].total == 2 and #lookup[701].holders == 1)
_G.BlackthornesTS.Butler.Holdings = function() return holdings end

-- No post call: the script hook on the two tooltips.
_G.TooltipDataProcessor = nil
local scripts = {}
local function Hookable(tooltip, name)
    tooltip.HookScript = function(_, script, fn) scripts[name .. ":" .. script] = fn end
end
local ns2 = env.Load()
Hookable(_G.GameTooltip, "GameTooltip")
Hookable(_G.ItemRefTooltip, "ItemRefTooltip")
_G.GameTooltip.AddDoubleLine = Double
_G.GameTooltip.GetItem = function() return "Linen Cloth", "|cffffffff|Hitem:501::::|h[Linen Cloth]|h|r" end
env.Enable(ns2)
suite.check("an older client gets the script hook", ns2.WhoHas.installed == "script hook"
    and scripts["GameTooltip:OnTooltipSetItem"] ~= nil and scripts["ItemRefTooltip:OnTooltipSetItem"] ~= nil)
_G.GameTooltip._lines = {}
scripts["GameTooltip:OnTooltipSetItem"](_G.GameTooltip)
suite.check("and reads the item from the link", _G.GameTooltip._lines[2] == "Your characters have 39",
    tostring(_G.GameTooltip._lines[2]))

-- Without Tradeskills there is nothing to say.
_G.BlackthornesTS = nil
local ns3 = env.Load()
env.Enable(ns3)
suite.check("no Tradeskills is not an error", ns3.WhoHas.Build() == nil
    and ns3.WhoHas:ProbeText():find("no Tradeskills", 1, true) ~= nil)

_G.Enum = nil
_G.GetTime = nil
suite.done()
