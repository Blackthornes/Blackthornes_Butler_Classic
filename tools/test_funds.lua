-- The gold fund (the owner asked 2026-10-11): every character keeps at
-- least an amount, and at a mailbox a character with more is offered a
-- gold mail to each below it.
--
-- What must hold:
--   1. Off until an amount is set; then each character below it on this
--      realm and side is topped up, biggest need first.
--   2. The sender never goes below its own amount, and postage counts.
--   3. A character's own amount wins over the usual; 0 keeps nothing back.
--   4. Fill mail puts the gold in (with that character's items, or alone).
--   5. Gold seen leaving is counted as on its way until the character is
--      seen taking it, so it is never sent twice.
--   6. A character whose gold was never seen is left out.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("funds")

local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 401, name = "Bolt of Wool", quality = 1, price = 50, count = 3 },
})
fake.money = 2000000 -- 200g

local G = 10000
local now = 1000000
_G.time = function() return now end

local holdings = {
    { key = "me", short = "Me Here", realm = "R", faction = "Horde", isCurrent = true, gold = 1000000, goldAt = now },
    { key = "bob", short = "Bob Stone", realm = "R", faction = "Horde", gold = 5 * G, goldAt = now - 7200 },
    { key = "ana", short = "Ana Ash", realm = "R", faction = "Horde", gold = 40 * G, goldAt = now - 3 * 86400 },
    { key = "cy", short = "Cy Far", realm = "R", faction = "Alliance", gold = 0, goldAt = now },
    { key = "di", short = "Di New", realm = "R", faction = "Horde" },
}
local filled = {}
_G.BlackthornesTS = { Butler = {
    Advise = function(_, id)
        if id == 401 then return { mailTo = "Ana Ash", mailCount = 2 } end
    end,
    FillMail = function(_, name, items, money)
        filled[#filled + 1] = { name = name, items = items, money = money }
        return true
    end,
    Holdings = function() return holdings end,
    Mailbox = function() end,
} }
env.Enable(ns)

local Funds, Errands, UI = ns.Funds, ns.Errands, ns.UI

-- 1. Off by default.
suite.check("off until an amount is set", #(Funds:Plan()) == 0)

Funds:SetMinimum(50 * G)
local plan = Funds:Plan()
suite.check("two characters below 50g", #plan == 2, #plan)
suite.check("the biggest need first", plan[1].to == "Bob Stone" and plan[1].amount == 45 * G)
suite.check("then the next", plan[2].to == "Ana Ash" and plan[2].amount == 10 * G)
suite.check("never the other side", Funds:For("Cy Far") == nil)
suite.check("gold never seen is left out", Funds:For("Di New") == nil)
suite.check("the row says how old the gold is", Funds.Reason(plan[2]):find("3 days ago", 1, true) ~= nil,
    Funds.Reason(plan[2]))

-- 2. The sender keeps its own amount, and postage.
fake.money = 80 * G
Funds:MoneyChanged()
plan = Funds:Plan()
suite.check("only what is above the sender's own amount", plan[1].amount == 30 * G - Funds.POSTAGE,
    plan[1] and plan[1].amount)
suite.check("nothing left for the next", #plan == 1)
fake.money = 50 * G
Funds:MoneyChanged()
suite.check("at its own amount, nothing to give", #(Funds:Plan()) == 0)

-- 3. A character's own amount.
fake.money = 100 * G
Funds:SetMinimumFor("Me Here", 0)
Funds:SetMinimumFor("Ana Ash", 100 * G)
plan = Funds:Plan()
suite.check("its own amount wins", Funds:For("Ana Ash") and Funds:For("Ana Ash").amount == 60 * G,
    Funds:For("Ana Ash") and Funds:For("Ana Ash").amount)
suite.check("0 keeps nothing back: it can give everything",
    Funds:For("Bob Stone").amount == 100 * G - 60 * G - 2 * Funds.POSTAGE, Funds:For("Bob Stone").amount)
Funds:SetMinimumFor("Ana Ash", nil)
Funds:SetMinimumFor("Me Here", nil)
fake.money = 200 * G
Funds:MoneyChanged()
suite.check("back to the usual", Funds:For("Ana Ash").amount == 10 * G)

-- 4. At the mailbox: rows, and Fill mail puts the gold in.
env.Fire("MAIL_SHOW")
local lines = UI:Lines()
suite.check("the Gold rows come first", lines[1].type == "header" and lines[1].group.verdict == "gold"
    and lines[2].type == "gold" and lines[2].entry.to == "Bob Stone")
UI.mailButton:GetScript("OnClick")(UI.mailButton)
suite.check("Ana's items and gold go together", filled[1] and filled[1].name == "Ana Ash"
    and filled[1].money == 10 * G and #filled[1].items == 1)

-- 5. The purse moving says nothing about the mail: gold taken from the
-- inbox, or spent, is not counted as sent.
fake.money = fake.money - 20 * G
env.Fire("PLAYER_MONEY")
suite.check("a purse drop alone writes nothing down", ns.db.goldSent == nil or ns.db.goldSent["Ana Ash"] == nil)
fake.money = fake.money + 20 * G
-- The mail goes: on its way, not offered again.
fake.money = fake.money - 10 * G - Funds.POSTAGE
env.Fire("PLAYER_MONEY")
env.Fire("MAIL_SEND_SUCCESS")
suite.check("seen leaving, it is written down", ns.db.goldSent["Ana Ash"]
    and ns.db.goldSent["Ana Ash"][1].amount == 10 * G)
suite.check("so Ana is not offered it again", Funds:For("Ana Ash") == nil)
UI.mailButton:GetScript("OnClick")(UI.mailButton)
suite.check("gold alone is a mail", filled[2] and filled[2].name == "Bob Stone"
    and filled[2].money == 45 * G and #filled[2].items == 0)
-- Gold alone goes under its own subject: with the SendMail hook in place
-- it must still count as the mail Butler filled, or Bob is offered the
-- same gold again the moment it goes.
local hooked = Errands.hookedSend
Errands.hookedSend = true
_G.GetSendMailMoney = function() return 45 * G end
Errands:OnSendMail("Bob Stone", Errands.GOLD_SUBJECT)
fake.money = fake.money - 45 * G - Funds.POSTAGE
env.Fire("PLAYER_MONEY")
env.Fire("MAIL_SEND_SUCCESS")
suite.check("gold sent alone is written down", ns.db.goldSent["Bob Stone"]
    and ns.db.goldSent["Bob Stone"][1].amount == 45 * G)
suite.check("so Bob is not offered it again", Funds:For("Bob Stone") == nil)
_G.GetSendMailMoney = nil
Errands.hookedSend = hooked
env.Fire("MAIL_CLOSED")

-- Ana logs in without taking the mail: still on its way.
holdings[3].goldAt = now + 60
now = now + 120
Funds:Changed()
suite.check("not taken yet, still counted", Funds:For("Ana Ash") == nil)
-- She takes it.
holdings[3].gold = 50 * G
holdings[3].goldAt = now + 60
now = now + 120
Funds:Changed()
Funds:Plan()
suite.check("taken, the note goes", ns.db.goldSent["Ana Ash"] == nil)
-- Never taken: after 30 days it went back.
ns.db.goldSent["Bob Stone"] = { { amount = 45 * G, at = now - Funds.KEEP_SENT - 1, before = 5 * G } }
Funds:Changed()
suite.check("unclaimed for 30 days, offered again", Funds:For("Bob Stone") ~= nil)

-- Collected, but Ana spent it since (a player's report, 2026-11-10): her
-- gold never shows the rise, but her mailbox read after the send holds
-- less than was sent, so it was taken.
ns.db.goldSent["Ana Ash"] = { { amount = 10 * G, at = now - 600, before = 40 * G } }
holdings[3].gold, holdings[3].goldAt = 5 * G, now - 60
holdings[3].mailAt, holdings[3].mailMoney = now - 60, 0
Funds:Changed()
Funds:Plan()
suite.check("an empty mailbox after the send lets the note go", ns.db.goldSent["Ana Ash"] == nil)
ns.db.goldSent["Ana Ash"] = { { amount = 10 * G, at = now - 600, before = 40 * G } }
holdings[3].mailMoney = 10 * G
Funds:Changed()
Funds:Plan()
suite.check("still in the mailbox, the note stays", ns.db.goldSent["Ana Ash"] ~= nil)
holdings[3].mailAt, holdings[3].mailMoney = now - 900, 0
Funds:Changed()
Funds:Plan()
suite.check("a mailbox read before the send says nothing", ns.db.goldSent["Ana Ash"] ~= nil)
holdings[3].clearedAt = now - 30
Funds:Changed()
Funds:Plan()
suite.check("Clear Items after the send lets the note go", ns.db.goldSent["Ana Ash"] == nil)
holdings[3].mailAt, holdings[3].mailMoney, holdings[3].clearedAt = nil, nil, nil
suite.check("Taken: a fresh note with nothing new is not taken",
    not Funds.Taken({ gold = 5 * G, goldAt = now - 900 }, 10 * G, now - 600, 40 * G))

-- Without Tradeskills, nothing.
_G.BlackthornesTS = nil
Funds:Changed()
suite.check("without Tradeskills, no plan", #(Funds:Plan()) == 0)

suite.done()
