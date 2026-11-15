-- Mail contents: hovering a mail in the inbox adds what it holds under the
-- game's own tooltip lines. Only lines are added; the inbox rows get an
-- OnEnter post hook and nothing else. Off unless ticked (`mailContents`).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("mailcontents")

local ns = env.Load()

-- Two inbox rows the game made, each with the game's own OnEnter.
local gameRan = 0
local buttons = {}
for row = 1, 2 do
    buttons[row] = env.Stub({ _scripts = { OnEnter = function() gameRan = gameRan + 1 end } })
    _G["MailItem" .. row .. "Button"] = buttons[row]
end
_G.INBOXITEMS_TO_DISPLAY = 2
_G.InboxFrame = { pageNum = 1 }

-- The tooltip keeps each line, double lines as "left | right".
local tip = _G.GameTooltip
tip.AddDoubleLine = function(self, left, right) self._lines[#self._lines + 1] = env.Plain(left) .. " | " .. env.Plain(right) end
tip.AddLine = function(self, text) self._lines[#self._lines + 1] = env.Plain(text) end
tip.GetOwner = function(self) return self._owner end
tip.SetOwner = function(self, owner) self._owner = owner; self._lines = {} end

-- The mailbox: mail 1 has two items, gold and 5 days left; mail 2 is empty
-- with 2.4 days left and asks for cash on delivery.
local mails = {
    { money = 15000, cod = 0, days = 4.6, items = {
        { name = "Linen Cloth", id = 2589, count = 20, quality = 1 },
        { name = "Broken Fang", id = 3300, count = 3, quality = 0 },
    } },
    { money = 0, cod = 25000, days = 2.4, items = {} },
}
_G.GetInboxNumItems = function() return #mails end
_G.GetInboxHeaderInfo = function(index)
    local m = mails[index]
    if not m then return nil end
    return nil, nil, "Bob Wither", "Hi", m.money, m.cod, m.days, #m.items > 0
end
_G.GetInboxItem = function(index, slot)
    local item = mails[index] and mails[index].items[slot]
    if not item then return nil end
    return item.name, item.id, 1000 + slot, item.count, item.quality
end
_G.GetInboxItemLink = function(index, slot)
    local item = mails[index] and mails[index].items[slot]
    return item and ("|Hitem:" .. item.id .. "|h") or nil
end

-- Vendor prices, and Tradeskills' auction price for the cloth.
local vendor = { [2589] = 13, [3300] = 50 }
ns.Items.SellPrice = function(_, id) return vendor[id] end
_G.BlackthornesTS = { Butler = { Advise = function(_, id)
    if id == 2589 then return { auction = 40 } end
    return {}
end } }

env.Enable(ns)
local MC = ns.MailContents

suite.check("each inbox row is hooked", MC.installed == true)
suite.check("off until ticked", not MC:Enabled())

local function Hover(row)
    tip._owner = nil
    tip._lines = {}
    buttons[row]:GetScript("OnEnter")(buttons[row])
    return tip._lines
end

suite.check("off adds nothing at first", #Hover(1) == 0)
gameRan = 0
MC:SetEnabled(true)

local lines = Hover(1)
suite.check("the game's own OnEnter still runs first", gameRan == 1, gameRan)
suite.check("heading first", lines[1] == "IN THIS MAIL", table.concat(lines, " / "))
suite.check("each item with its count", lines[2]:find("Linen Cloth", 1, true) and lines[2]:find("| x20", 1, true), lines[2])
suite.check("icon on the item line", lines[2]:find("|T1001:14:14", 1, true), lines[2])
suite.check("grey item too", lines[3]:find("Broken Fang", 1, true) and lines[3]:find("| x3", 1, true), lines[3])
suite.check("the mail's gold", lines[4] == "Gold: | 1g 50s 00c", lines[4])
-- 20 cloth at 40c auction (beats 13c vendor) + 3 greys at vendor 50c.
suite.check("items worth by Butler's prices, greys at vendor", lines[5] == "Items worth: | 9s 50c", lines[5])
suite.check("days left, rounded up", lines[6] == "Runs out in: | 5 days", lines[6])
suite.check("nothing else", #lines == 6, #lines)

lines = Hover(2)
suite.check("empty mail with COD still shows the heading", lines[1] == "IN THIS MAIL", table.concat(lines, " / "))
suite.check("no gold or worth lines without them", lines[2]:find("^Runs out in:"), lines[2])
suite.check("3 days or less", lines[2] == "Runs out in: | 3 days", lines[2])
suite.check("cash on delivery", lines[3] == "Costs: | 2g 50s 00c", lines[3])

-- Orange at 3 days or less, plain otherwise.
local soon = MC.Lines({ items = {}, daysLeft = 2.4 })
local later = MC.Lines({ items = {}, daysLeft = 4.6 })
suite.check("soon is orange", soon[#soon].right:find("ffff8c1a", 1, true), soon[#soon].right)
suite.check("later is not orange", not later[#later].right:find("ffff8c1a", 1, true), later[#later].right)
suite.check("no items or money: only Runs out in", #later == 1 and env.Plain(later[1].left) == "Runs out in:")
suite.check("one day", env.Plain(MC.Lines({ items = {}, daysLeft = 0.3 })[1].right) == "1 day")

-- Costs is red.
local cod = MC.Lines({ items = {}, cod = 100, daysLeft = 10 })
suite.check("costs in red", cod[#cod].left:find(ns.COLORS.bad, 1, true), cod[#cod].left)

-- Nothing priced: no Items worth line.
vendor = {}
_G.BlackthornesTS = nil
lines = Hover(1)
for _, line in ipairs(lines) do
    suite.check("no worth line when nothing is priced", not line:find("^Items worth:"), line)
end

-- A row past the last mail adds nothing.
mails[2] = nil
lines = Hover(2)
suite.check("a row with no mail adds nothing", #lines == 0, table.concat(lines, " / "))

-- Turned off: nothing is added. Saved as false, never renamed.
MC:SetEnabled(false)
suite.check("saved as mailContents", ns.db.mailContents == false)
lines = Hover(1)
suite.check("off adds nothing", #lines == 0, table.concat(lines, " / "))
MC:SetEnabled(true)
suite.check("back on", ns.db.mailContents == true and #Hover(1) > 0)

-- A client that raises adds nothing and never errors.
_G.GetInboxHeaderInfo = function() error("secret") end
local ok = pcall(Hover, 1)
suite.check("never raises", ok)

suite.done()
