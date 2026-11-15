-- Mail running out (Logic/MailRunsOut.lua). Tradeskills reads each
-- character's inbox at the mailbox and gives, on Butler:Holdings(), when
-- the box was read and how many days the soonest mail had left. Butler
-- counts on from then.
--
-- What must hold:
--   1. Off unless ticked: nothing shows, nothing is noted.
--   2. The days are counted on from when the box was read; mail already
--      gone, or more than 3 days off, says nothing.
--   3. This character's Get your mail step says "Runs out in N days".
--   4. Another character on this realm and side is the First: line with
--      the Log out button; another realm, side or the one playing is not.
--   5. The hover says how many mails, how many run out, where they go and
--      when the box was last seen.
--   6. The login note shows once.
--   7. The Settings tick box writes `mailRunsOut`.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("mailrunsout")

local ns = env.Load()
env.FakeBags({})

local DAY = 86400
local NOW = 1000 * DAY
_G.time = function() return NOW end
local clock = 100
_G.GetTime = function() return clock end

local jobs = {}
local holdings
_G.BlackthornesTS = { Butler = {
    Advise = function() return nil end,
    Mailbox = function() end,
    Jobs = function() return jobs end,
    Holdings = function() return holdings end,
} }

local ME = { key = "Player-1", name = "Ana Stone", realm = "Silverpine", faction = "Alliance",
    isCurrent = true, playing = true, bags = {}, bank = {}, mail = {},
    mailAt = NOW - DAY, mailCount = 3, mailSoonest = 3.5, mailSoonCount = 1, mailReturns = 1, mailGone = 0 }
local BOB = { key = "Player-2", name = "Bob Wither", realm = "Silverpine", faction = "Alliance",
    bags = {}, bank = {}, mail = {},
    mailAt = NOW - 3 * DAY, mailCount = 4, mailSoonest = 3.8, mailSoonCount = 2, mailReturns = 1, mailGone = 1 }
local CID = { key = "Player-3", name = "Cid Horde", realm = "Silverpine", faction = "Horde",
    bags = {}, bank = {}, mail = {}, mailAt = NOW, mailSoonest = 1, mailSoonCount = 1, mailCount = 1 }
local DEE = { key = "Player-4", name = "Dee Far", realm = "Silverpine", faction = "Alliance",
    bags = {}, bank = {}, mail = {}, mailAt = NOW, mailSoonest = 10, mailSoonCount = 0, mailCount = 2 }
holdings = { ME, BOB, CID, DEE }

local shown = {}
ns.Notice = { Show = function(_, text, opts) shown[#shown + 1] = { text = text, opts = opts } end }

env.Enable(ns)
local M, Jobs = ns.MailRunsOut, ns.Jobs

local function Fresh()
    clock = clock + 10
    M.cache = nil
    Jobs:Changed()
end

-- 1. Off unless ticked.
Fresh()
suite.check("off unless ticked", not M:IsOn() and ns.db.mailRunsOut == nil)
suite.check("off: nothing here", M:Here() == nil)
suite.check("off: no alts", #M:Alts() == 0)
local plan = Jobs:Plan()
suite.check("off: no First: line for mail", not (plan and plan.mailFirst))
M:Greet()
suite.check("off: no note", #shown == 0)

-- 2. The day math.
local info = M.Read(ME, NOW)
suite.check("counted on from when the box was read", info and math.abs(info.left - 2.5) < 1e-6, info and info.left)
suite.check("shown as whole days, rounded up", info.days == 3, info.days)
suite.check("last seen one day ago", info.seen == 1)
suite.check("mail already gone says nothing", M.Read({ mailAt = NOW - 5 * DAY, mailSoonest = 2 }, NOW) == nil)
suite.check("more than 3 days off says nothing", M.Read(DEE, NOW) == nil)
suite.check("no reading says nothing", M.Read({ name = "X" }, NOW) == nil)
suite.check("under a day still says 1 day", M.Read({ mailAt = NOW, mailSoonest = 0.2 }, NOW).days == 1)

-- 3 and 4. Ticked.
M:SetOn(true)
suite.check("ticked saves true", ns.db.mailRunsOut == true)
Fresh()
local here = M:Here()
suite.check("this character's mail runs out", here and here.days == 3)
suite.check("in its own words", M.HereText(here) == "Runs out in 3 days", M.HereText(here))
local alts = M:Alts()
suite.check("only the alt on this realm and side", #alts == 1 and alts[1].name == "Bob Wither",
    alts[1] and alts[1].name)
suite.check("its short words", M.ShortText(alts[1]) == "mail runs out in 1 day", M.ShortText(alts[1]))

plan = Jobs:Plan()
suite.check("the alt goes first", plan.nextJob and plan.nextJob.name == "Bob Wither" and plan.mailFirst)
local rows = Jobs:Lines()
local first
for _, row in ipairs(rows) do if row.type == "jobnext" then first = first or row end end
suite.check("its line is First: and has Log out", first and first.isFirst and first.isNext)
local shownRow = { data = first, IsShown = function() return true end }
suite.check("Log out follows that line", Jobs.NextRow({ rows = { shownRow } }) == shownRow)

-- The window's rows.
local function FakeRow()
    local row = {}
    local function Part()
        local part = { text = "" }
        return setmetatable(part, { __index = function(_, key)
            if key == "SetText" then return function(self, text) self.text = text or "" end end
            return function() end
        end })
    end
    for _, key in ipairs({ "fold", "icon", "name", "reason", "worth", "action" }) do row[key] = Part() end
    return row
end
local row = FakeRow()
ns.UI.UpdateNextRow(row, first)
suite.check("the row says First: and the name in full", row.name.text == "First: Bob Wither", row.name.text)
suite.check("and the mail in orange", row.reason.text:find("mail runs out in 1 day", 1, true)
    and row.reason.text:find("ff9a3c", 1, true), row.reason.text)

local pickup = { kind = "pickup", items = { { itemID = 2318, count = 1 } } }
row = FakeRow()
ns.UI.UpdateJobRow(row, { type = "job", step = pickup })
suite.check("Get your mail says when it runs out, in orange",
    row.worth.text:find("Runs out in 3 days", 1, true) and row.worth.text:find("ff9a3c", 1, true), row.worth.text)

-- An alt the player set aside is left alone.
Jobs:Ignore("Bob Wither")
Fresh()
plan = Jobs:Plan()
suite.check("an ignored alt gets no line", not (plan and plan.mailFirst))
Jobs.ignoredSeen = nil
if ns.db.jobsIgnored then ns.db.jobsIgnored["Bob Wither"] = nil end
Fresh()

-- 5. The hover.
local lines = {}
for _, line in ipairs(M.TipLines(M:Alts()[1])) do lines[#lines + 1] = line[1] end
local tip = table.concat(lines, "|")
suite.check("the hover reads as the mockup",
    tip == "4 mails in the box.|2 run out in 1 day.|1 goes back to the sender, 1 is gone for good.| |Last seen 3 days ago.", tip)
suite.check("the second line is orange", M.TipLines(M:Alts()[1])[2][2] == "orange")
suite.check("the last line is muted", M.TipLines(M:Alts()[1])[5][2] == "muted")
suite.check("fate: one going back only", M.FateText(1, 0) == "1 goes back to the sender.")
suite.check("fate: many gone", M.FateText(0, 3) == "3 are gone for good.")
suite.check("fate: neither says nothing", M.FateText(0, 0) == nil)
suite.check("seen today", M.TipLines({ count = 1, soon = 1, soonDays = 1, returns = 0, gone = 0, seen = 0 })[4][1]
    == "Last seen today.")

-- 6. The login note, once.
M:Greet()
suite.check("the note shows", #shown == 1 and shown[1].text == "You have mail that runs out in 3 days.",
    shown[1] and shown[1].text)
M:Greet()
suite.check("only once", #shown == 1)

-- The one playing's own old record is never an alt.
local OLD = { key = "Ana-Old", name = "Ana Stone", realm = "Silverpine", faction = "Alliance", playing = true,
    bags = {}, bank = {}, mail = {}, mailAt = NOW, mailSoonest = 1, mailSoonCount = 1, mailCount = 1 }
holdings = { ME, OLD }
Fresh()
suite.check("an old record of the one playing is not an alt", #M:Alts() == 0)
holdings = { ME, BOB, CID, DEE }

-- 7. Settings.
M:SetOn(false)
suite.check("unticked clears it", ns.db.mailRunsOut == nil)
local settings = ns.SettingsUI
if settings and settings.Show then
    pcall(settings.Show, settings)
    local box = settings.controls and settings.controls.mailRunsOut
    suite.check("Settings has the tick box", box ~= nil)
end

_G.BlackthornesTS = nil
suite.done()
