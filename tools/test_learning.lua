-- Learning: Butler remembers what the player does anyway. A buyback of
-- something its Sell button sold keeps it; an item sold by hand on two
-- visits goes under Sell; one mailed by hand to the same character twice
-- goes under Mail. The player's own choices win and clear it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("learning")

local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 201, name = "Broken Fang", quality = 0, price = 10 },
    { bag = 0, slot = 2, id = 300, name = "Linen Cloth", quality = 1, price = 13, count = 20 },
    { bag = 0, slot = 3, id = 300, name = "Linen Cloth", quality = 1, price = 13, count = 5 },
    { bag = 0, slot = 4, id = 301, name = "Wool Cloth", quality = 1, price = 33, count = 20 },
    { bag = 0, slot = 5, id = 302, name = "Shiny Ring", quality = 2, price = 90, bound = true },
})
fake.canSell = true

-- A post-hook, as the game's hooksecurefunc runs one.
_G.hooksecurefunc = function(a, b, c)
    local tbl, name, fn = a, b, c
    if type(a) == "string" then tbl, name, fn = _G, a, b end
    local original = tbl[name]
    tbl[name] = function(...)
        local results = { original(...) }
        fn(...)
        return unpack(results)
    end
end

-- The vendor's Buyback tab.
local buyback = {}
_G.GetNumBuybackItems = function() return #buyback end
_G.GetBuybackItemLink = function(index)
    local item = buyback[index]
    return item and ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(item.id, item.name)
end
_G.BuybackItem = function(index)
    local item = table.remove(buyback, index)
    if item then fake.Put(item) end
end
-- Selling puts the stack on the Buyback tab.
local use = _G.C_Container.UseContainerItem
_G.C_Container.UseContainerItem = function(bag, slot)
    local item = fake.bags[bag][slot]
    use(bag, slot)
    if item and not fake.bags[bag][slot] then buyback[#buyback + 1] = item end
end

-- The Send Mail page.
local attached = {}
local sent = {}
_G.GetSendMailItem = function(slot)
    local item = attached[slot]
    if not item then return nil end
    return item.name, item.id, 134400, item.count or 1
end
_G.SendMail = function(recipient, subject)
    sent[#sent + 1] = { to = recipient, subject = subject }
end
local function Mail(to, subject, ...)
    attached = { ... }
    _G.SendMail(to, subject, "")
end

_G.BlackthornesTS = { Butler = {
    Advise = function() return nil end,
    Holdings = function()
        return {
            { key = "me", short = "Ana Smith", realm = "Here", faction = "Horde", isCurrent = true },
            { key = "bob", short = "Bob Wither", realm = "Here", faction = "Horde" },
            { key = "cy", short = "Cy Morrow", realm = "Here", faction = "Horde" },
        }
    end,
} }

env.Enable(ns)
local Learning, Selling, Verdicts, UI = ns.Learning, ns.Selling, ns.Verdicts, ns.UI

local function Judge(bag, slot)
    local entry = ns.Bags.ReadSlot(bag, slot)
    entry.quest = ns.Bags.ReadQuest(bag, slot, entry.itemID)
    return Verdicts:Judge(entry)
end

--------------------------------------------------------------------------------
-- Bought back
--------------------------------------------------------------------------------

env.Fire("MERCHANT_SHOW")
UI.frame.GetRight = function() return 800 end
UI.frame.GetBottom = function() return 200 end
Selling:Update()
local button = Selling.button

-- Butler's Sell button sells the grey: the secure /use runs between
-- PreClick and PostClick.
button:GetScript("PreClick")(button)
suite.check("the Sell button aims at the grey", button:GetAttribute("macrotext") == "/use 0 1")
_G.C_Container.UseContainerItem(0, 1)
button:GetScript("PostClick")(button)
-- The game says the vendor's lists changed; Butler reads the Buyback tab.
env.Fire("MERCHANT_UPDATE")
suite.check("Butler's own sale is not a hand sale",
    not (ns.db.learnTally and ns.db.learnTally.sells and ns.db.learnTally.sells[201]))
suite.check("Butler remembers what it sold this visit", Selling.soldIDs[201] == true)

_G.BuybackItem(1)
suite.check("buying it back teaches Butler to keep it", Learning:Get(201) == "keep")
local verdict, reason = Judge(0, 1)
suite.check("so the grey is kept", verdict == "keep", verdict)
suite.check("and says why", reason == "You bought this back, so Butler keeps it", reason)
suite.check("said once in chat", env.ChatText():find("you bought it back", 1, true) ~= nil)

--------------------------------------------------------------------------------
-- Sold by hand
--------------------------------------------------------------------------------

suite.check("white cloth starts under Look at it", Judge(0, 2) == "look")
_G.C_Container.UseContainerItem(0, 2)
suite.check("a hand sale is counted", ns.db.learnTally.sells[300] == 1)
suite.check("but one sale teaches nothing yet", Learning:Get(300) == nil)
_G.C_Container.UseContainerItem(0, 3)
suite.check("a second stack on the same visit counts as one sale", ns.db.learnTally.sells[300] == 1)

env.Fire("MERCHANT_CLOSED")
env.Fire("MERCHANT_SHOW")
fake.Put({ bag = 0, slot = 6, id = 300, name = "Linen Cloth", quality = 1, price = 13, count = 8 })
fake.Put({ bag = 0, slot = 7, id = 300, name = "Linen Cloth", quality = 1, price = 13, count = 3 })
ns.Bags:Scan()
_G.C_Container.UseContainerItem(0, 6)
suite.check("sold by hand on a second visit: under Sell from now on", Learning:Get(300) == "sell")
verdict, reason = Judge(0, 7)
suite.check("the rest of the cloth is judged Sell", verdict == "sell", verdict)
suite.check("because you usually sell it", reason:find("You usually sell these", 1, true) == 1, reason)

-- Soulbound green or better is never learned as Sell.
_G.C_Container.UseContainerItem(0, 5)
env.Fire("MERCHANT_CLOSED")
env.Fire("MERCHANT_SHOW")
fake.Put({ bag = 0, slot = 5, id = 302, name = "Shiny Ring", quality = 2, price = 90, bound = true })
ns.Bags:Scan()
_G.C_Container.UseContainerItem(0, 5)
suite.check("soulbound green gear is never learned as Sell", Learning:Get(302) == nil)

-- Disenchanting at a vendor: the cast aims at the slot through the same
-- call, and the item stays (locked) while the cast runs. No sale.
fake.Put({ bag = 0, slot = 9, id = 304, name = "Green Belt", quality = 2, price = 70 })
ns.Bags:Scan()
local canSell = fake.canSell
fake.canSell = false
_G.SpellIsTargeting = function() return true end
_G.C_Container.UseContainerItem(0, 9)
_G.SpellIsTargeting = function() return false end
fake.bags[0][9].locked = true
_G.C_Container.UseContainerItem(0, 9)
suite.check("a disenchant at a vendor is not a hand sale", not ns.db.learnTally.sells[304])
fake.bags[0][9] = nil
_G.SpellIsTargeting = nil
fake.canSell = canSell

-- Away from a vendor, using an item teaches nothing.
env.Fire("MERCHANT_CLOSED")
fake.Put({ bag = 0, slot = 8, id = 303, name = "Silk Cloth", quality = 1, price = 40 })
ns.Bags:Scan()
_G.C_Container.UseContainerItem(0, 8)
suite.check("no vendor, no sale", not ns.db.learnTally.sells[303])

--------------------------------------------------------------------------------
-- The right-click menu forgets it
--------------------------------------------------------------------------------

UI:ShowMenu({ itemID = 300, name = "Linen Cloth", count = 3 })
suite.check("the menu offers to forget what was learned", UI.menu.decide:IsShown()
    and UI.menu.decide.label:GetText() == "Forget what Butler learned", UI.menu.decide.label:GetText())
UI.menu.decide:GetScript("OnClick")(UI.menu.decide)
suite.check("and forgets it", Learning:Get(300) == nil and not ns.db.learnTally.sells[300])
suite.check("so the cloth is up to Butler again", Judge(0, 7) == "look")

--------------------------------------------------------------------------------
-- Mailed by hand
--------------------------------------------------------------------------------

Mail("bob", "wool", { id = 301, name = "Wool Cloth", count = 20 })
env.Fire("MAIL_SEND_SUCCESS")
suite.check("a first name alone finds the character", ns.db.learnTally.mails[301]["Bob Wither"] == 1)
suite.check("one mail teaches nothing yet", Learning:Get(301) == nil)

Mail("Bob Wither-Here", "more wool", { id = 301, name = "Wool Cloth", count = 20 })
env.Fire("MAIL_FAILED")
env.Fire("MAIL_SEND_SUCCESS")
suite.check("a mail that failed is not counted", ns.db.learnTally.mails[301]["Bob Wither"] == 1)

Mail("Zed", "for a friend", { id = 301, name = "Wool Cloth", count = 20 })
env.Fire("MAIL_SEND_SUCCESS")
suite.check("mail to someone else's character teaches nothing", ns.db.learnTally.mails[301]["Zed"] == nil)

Mail("Bob Wither", "From Blackthornes Butler", { id = 301, name = "Wool Cloth", count = 20 })
env.Fire("MAIL_SEND_SUCCESS")
suite.check("mail an addon filled teaches nothing", ns.db.learnTally.mails[301]["Bob Wither"] == 1)

Mail("Bob Wither-Here", "wool again", { id = 301, name = "Wool Cloth", count = 20 })
env.Fire("MAIL_SEND_SUCCESS")
local learned, to = Learning:Get(301)
suite.check("mailed to Bob twice: under Mail to Bob from now on", learned == "mail" and to == "Bob Wither")
local _, mailReason, _, extra = Judge(0, 4)
suite.check("judged Mail to Bob, so Fill mail sends it", Judge(0, 4) == "mail" and extra and extra.to == "Bob Wither")
suite.check("because you usually mail it", mailReason == "You usually mail this to Bob Wither", mailReason)

-- The player's own pick wins and clears what was learned.
Verdicts:SetChoice(301, "keep")
suite.check("an Always keep pick replaces the learned mail", Learning:Get(301) == nil and Judge(0, 4) == "keep")
Verdicts:SetChoice(301, nil)

-- Mail to the character playing never teaches anything.
Mail("Ana Smith", "to me", { id = 301, name = "Wool Cloth", count = 20 })
env.Fire("MAIL_SEND_SUCCESS")
suite.check("never learns mail to the character playing",
    not (ns.db.learnTally.mails[301] and ns.db.learnTally.mails[301]["Ana Smith"]))

--------------------------------------------------------------------------------
-- Turned off
--------------------------------------------------------------------------------

ns.db.learn = false
Mail("Cy", "x", { id = 301, name = "Wool Cloth", count = 1 })
env.Fire("MAIL_SEND_SUCCESS")
suite.check("with learning off, nothing is counted",
    not (ns.db.learnTally.mails[301] and ns.db.learnTally.mails[301]["Cy Morrow"]))
ns.db.learn = true

-- reset confirm forgets it all.
ns.HandleSlash("reset confirm")
suite.check("reset confirm forgets what was learned", Learning:Get(201) == nil
    and next(ns.db.learnTally) == nil)

-- Era's older global is watched too, only when it is a call of its own.
local realHook, oldGlobal = _G.hooksecurefunc, rawget(_G, "UseContainerItem")
local hooks
_G.hooksecurefunc = function(a, b) hooks[#hooks + 1] = type(a) == "table" and b or a end
local function UseHooks()
    local count = 0
    for _, name in ipairs(hooks) do if name == "UseContainerItem" then count = count + 1 end end
    return count
end
hooks = {}
_G.UseContainerItem = _G.C_Container.UseContainerItem
Learning:OnEnable()
suite.check("one sale call, one watch", UseHooks() == 1)
hooks = {}
_G.UseContainerItem = function() end
Learning:OnEnable()
suite.check("a separate older call is watched too", UseHooks() == 2)
_G.hooksecurefunc, _G.UseContainerItem = realHook, oldGlobal

suite.done()
