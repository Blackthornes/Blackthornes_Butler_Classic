-- Butler on tooltips: the last line on a carried item's tooltip says what
-- Butler would do with it and what one is worth (the owner said yes
-- 2026-10-13: the last line, only while Butler is loaded).
--
-- What must hold:
--   1. The hook goes in only after the loading screen, so it is added after
--      the other lines (Who has it's among them).
--   2. A carried item gets "Butler: VERDICT" and its worth each.
--   3. An item not carried gets nothing; neither does the compare tooltip.
--   4. The hovered bag slot is read even when Butler's own read is stale.
--   5. Settings and /bbutler tooltip turn it off and on.
--   6. A mail says why under the line.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("verdicttip")

local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 701, name = "Broken Fang", quality = 0, price = 125 },
})

local postCalls = {}
_G.Enum = { TooltipDataType = { Item = 0 } }
_G.TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn) postCalls[#postCalls + 1] = { kind = kind, fn = fn } end,
}
local function Double(self, left, right) self._lines[#self._lines + 1] = left .. " | " .. right end
_G.GameTooltip.AddDoubleLine = Double
_G.ItemRefTooltip.AddDoubleLine = Double
local compare = env.Stub({ _lines = {}, AddLine = function(self, t) self._lines[#self._lines + 1] = t end })

env.Enable(ns)
local VerdictTip = ns.VerdictTip

-- 1.
suite.check("not hooked before the loading screen", VerdictTip.installed == nil and #postCalls == 1,
    #postCalls)
env.Fire("PLAYER_ENTERING_WORLD")
suite.check("hooked after it, after Who has it", VerdictTip.installed == "post call" and #postCalls == 2)
env.Fire("PLAYER_ENTERING_WORLD")
suite.check("and only once", #postCalls == 2)

local function Hover(tooltip, itemID, owner)
    tooltip._lines = {}
    tooltip.GetOwner = function() return owner end
    for _, call in ipairs(postCalls) do call.fn(tooltip, { id = itemID }) end
    return tooltip._lines
end

-- 4. Butler's window has never been open, so its own read is empty.
local button = env.Stub({ GetBagID = function() return 0 end, GetID = function() return 1 end })
local lines = Hover(GameTooltip, 701, button)
local last = lines[#lines]
suite.check("the hovered slot gets the line though Butler's read is stale",
    last ~= nil and last:find("^Butler: Sell") ~= nil, tostring(last))

-- 2.
suite.check("with what one is worth", last ~= nil and last:find("each", 1, true) ~= nil, tostring(last))

-- A chat link has no slot: on stale bags it asks for one read (which the
-- tests' timers run at once), and the next hover has it.
Hover(ItemRefTooltip, 701, nil)
lines = Hover(ItemRefTooltip, 701, nil)
suite.check("a link to a carried item gets it too", (lines[#lines] or ""):find("^Butler: Sell") ~= nil,
    tostring(lines[#lines]))

-- 3.
suite.check("an item not carried gets nothing", #Hover(GameTooltip, 999, nil) == 0)
compare._lines = {}
for _, call in ipairs(postCalls) do call.fn(compare, { id = 701 }) end
suite.check("the compare tooltip gets nothing", #compare._lines == 0)

-- A slot that no longer holds the item is not believed.
fake.bags[0][1] = nil
suite.check("an emptied slot gets nothing", #Hover(GameTooltip, 701, button) == 0)
fake.Put({ bag = 0, slot = 1, id = 701, name = "Broken Fang", quality = 0, price = 125 })

-- 6. A mail says why under it, so "Mail to NAME" is never read as "NAME
-- can wear it" (a player read an enchanter's mail as an upgrade).
fake.Put({ bag = 0, slot = 2, id = 702, name = "Heavy Mace", quality = 2, price = 900 })
ns.db.alwaysMail = { [702] = "Bob Stone" }
ns.Verdicts:Changed(true)
local mailButton = env.Stub({ GetBagID = function() return 0 end, GetID = function() return 2 end })
lines = Hover(GameTooltip, 702, mailButton)
local mailLine, whyLine = lines[#lines - 1] or "", lines[#lines] or ""
suite.check("a mail names who it goes to", mailLine:find("^Butler: Mail to Bob Stone") ~= nil, mailLine)
suite.check("and says why under it", whyLine ~= "" and not whyLine:find("^Butler:"), whyLine)
lines = Hover(GameTooltip, 701, button)
suite.check("a sale has no reason line", #lines == 1, #lines)

-- 5.
ns.HandleSlash("tooltip")
suite.check("/bbutler tooltip turns it off", ns.db.verdictTip == false and #Hover(GameTooltip, 701, button) == 0)
ns.HandleSlash("settings")
local box = ns.SettingsUI.controls.verdictTip
suite.check("Settings shows it off", box:GetValue() == ns.TooltipShift.OFF)
box:Pick(box:GetValue() + 1)
box:Pick(box:GetValue() + 1)
suite.check("Always turns it on", ns.db.verdictTip == true and #Hover(GameTooltip, 701, button) == 1)

suite.check("the probe says how it is hooked", VerdictTip:ProbeText():find("post call", 1, true) ~= nil)

suite.done()
