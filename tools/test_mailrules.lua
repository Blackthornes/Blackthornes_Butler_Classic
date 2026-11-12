-- Mail to anyone and the one Mail Rules list (Logic/MailRules.lua, a
-- player asked for several mail rules; the owner said build it from a
-- mockup, 2026-11-12).
--
-- What must hold:
--   1. A typed name must be whole unless it is one of the player's own,
--      and is never the character playing.
--   2. Typed names are remembered once each, newest last, at most KEEP;
--      never the one playing or one of the player's own characters.
--   3. OTHER PLAYERS lists typed names and anyone an item mails to.
--   4. All() gathers Always mail, list Mail To, learned mail and (when
--      asked) kinds; Remove() and Change() act where each lives.
--   5. A typed name on Always mail sends the item there.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("mailrules")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 4776, name = "Light Feather", quality = 1, price = 4, count = 20 },
})

local lists = { { name = "Herbs", id = 1, items = { [2447] = 0 } } }
_G.BlackthornesTS = { Butler = {
    Advise = function() return {} end,
    Lists = function() return lists, 1 end,
    Holdings = function()
        return {
            { key = "me", short = "Me Here", realm = "R", faction = "Horde", isCurrent = true },
            { key = "bob", short = "Bob Wither", realm = "R", faction = "Horde" },
        }
    end,
    FillMail = function() return true end,
    Mailbox = function() end,
} }
env.Enable(ns)
local MR, Verdicts = ns.MailRules, ns.Verdicts

-- 1. Typing a name.
suite.check("a first name alone is refused", MR:TypeName("Ana") == nil)
suite.check("a whole name is taken", MR:TypeName("  Ana Stone ") == "Ana Stone", MR:TypeName("Ana Stone"))
suite.check("the one playing is refused", MR:TypeName("Me Here") == nil)
suite.check("one of your own needs no last name", MR.IsOwn("Bob Wither"))

-- 2. Remembering.
MR:Remember("Ana Stone")
MR:Remember("Cal Reed")
MR:Remember("ana stone")
suite.check("remembered once each, newest last",
    #ns.db.mailNames == 2 and ns.db.mailNames[2] == "ana stone", table.concat(ns.db.mailNames, ","))
MR:Remember("Me Here")
MR:Remember("Bob Wither")
suite.check("never the one playing or your own", #ns.db.mailNames == 2, #ns.db.mailNames)
for i = 1, MR.KEEP + 3 do MR:Remember("Name Number" .. i) end
suite.check("kept to KEEP", #ns.db.mailNames == MR.KEEP, #ns.db.mailNames)
ns.db.mailNames = { "Ana Stone" }

-- 5. Always mail to a typed name.
suite.check("MailTo sets it", MR:MailTo(4776, "Dee Fox") == "Dee Fox")
suite.check("saved on Always mail", ns.db.alwaysMail[4776] == "Dee Fox", ns.db.alwaysMail[4776])
ns.UI:Show("bags")
Verdicts:Changed(true)
local row
for _, group in ipairs(Verdicts:Groups()) do
    for _, each in ipairs(group.rows) do if each.itemID == 4776 then row = each end end
end
suite.check("the feathers go to that player", row and row.verdict == "mail" and row.mailTo == "Dee Fox",
    row and (row.verdict .. " " .. tostring(row.mailTo)))

-- 3. Other players.
local others = MR:OtherNames()
suite.check("typed and mailed names, sorted",
    #others == 2 and others[1] == "Ana Stone" and others[2] == "Dee Fox", table.concat(others, ","))

-- 4. The one list.
ns.ListRules:SetMailTo(1, "Bob Wither")
ns.db.learned = ns.db.learned or {}
ns.db.learned[2589] = { verdict = "mail", to = "Bob Wither", at = 1 }
local function Find(rows, kind)
    for _, each in ipairs(rows) do if each.kind == kind then return each end end
end
local rows = MR:All()
suite.check("Always mail row", Find(rows, "item") and Find(rows, "item").to == "Dee Fox")
suite.check("list row", Find(rows, "list") and Find(rows, "list").name == "Herbs")
suite.check("learned row", Find(rows, "learned") and Find(rows, "learned").itemID == 2589)
suite.check("no kinds unless asked", Find(rows, "kind") == nil)
ns.BankAlt:SetName("Bob Wither")
ns.BankAlt:SetKindTo("cloth", "Ana Stone")
local withKinds = MR:All(true)
local cloth
for _, each in ipairs(withKinds) do if each.kind == "kind" and each.key == "cloth" then cloth = each end end
suite.check("a kind with its own character", cloth and cloth.to == "Ana Stone" and not cloth.bankAlt)

MR:Change(Find(rows, "item"), "Cal Reed")
suite.check("Change moves Always mail", ns.db.alwaysMail[4776] == "Cal Reed", ns.db.alwaysMail[4776])
MR:Change(Find(rows, "learned"), "Cal Reed")
suite.check("a learned mail becomes Always mail", ns.db.alwaysMail[2589] == "Cal Reed", ns.db.alwaysMail[2589])
MR:Remove(cloth)
suite.check("a kind's own character goes back to the bank alt", ns.BankAlt:KindTo("cloth") == nil)
MR:Remove(Find(rows, "list"))
suite.check("list Mail To removed", (ns.ListRules:Get(1) or {}).mailTo == nil)
MR:Remove({ kind = "item", itemID = 4776 })
suite.check("Always mail removed", ns.db.alwaysMail[4776] == nil)

-- The Settings list draws.
ns.SettingsUI:Show()
suite.check("the Mail Rules list is on the page", ns.SettingsUI.controls.ruleList ~= nil)
ns.SettingsUI:SyncMailRules()
suite.check("the count says rules", (ns.SettingsUI.controls.ruleCount:GetText() or ""):find("rule") ~= nil,
    ns.SettingsUI.controls.ruleCount:GetText())

suite.done()
