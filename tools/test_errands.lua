-- At a mailbox and the bank: Fill mail fills one character's mail a click
-- through Tradeskills and never sends; Move to bank puts the Always bank
-- list away; Take from bank brings out what the craft queue wants. The
-- window comes up for each when there is something to do, and goes with it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("errands")

local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 401, name = "Bolt of Wool", quality = 1, price = 50, count = 3 },
    { bag = 0, slot = 2, id = 402, name = "Patched Cloak", quality = 1, price = 30 },
    { bag = 0, slot = 3, id = 403, name = "Linen Cloth", quality = 1, price = 13, count = 20 },
    { bag = 0, slot = 4, id = 404, name = "Copper Ore", quality = 1, price = 5, count = 10 },
})

-- A bank of 16 slots, holding three stacks of Silk Cloth.
fake.bags[-1] = {}
local function PutBank(slot, id, count)
    local item = { bag = -1, slot = slot, id = id, name = "Silk Cloth", quality = 1, price = 40, count = count }
    fake.bags[-1][slot] = item
    fake.info[id] = item
end
PutBank(1, 501, 20)
PutBank(2, 501, 4)
PutBank(3, 501, 8)
_G.C_Container.GetContainerNumSlots = function(bag)
    if bag == 0 or bag == -1 then return fake.numSlots end
    return 0
end

-- Using an item at the bank moves it to the first free slot on the other
-- side, unless that side is full.
local bankFull, bagsFull = false, false
local used = {}
_G.C_Container.UseContainerItem = function(bag, slot)
    used[#used + 1] = bag .. ":" .. slot
    local item = fake.bags[bag][slot]
    if not item then return end
    local to = bag == -1 and 0 or -1
    if (to == -1 and bankFull) or (to == 0 and bagsFull) then return end
    for free = 1, fake.numSlots do
        if not fake.bags[to][free] then
            fake.bags[bag][slot] = nil
            item.bag, item.slot = to, free
            fake.bags[to][free] = item
            return
        end
    end
end

local filled, mailboxSaid = {}, {}
_G.BlackthornesTS = { Butler = {
    Advise = function(_, id)
        if id == 401 then return { mailTo = "Bob", mailCount = 1, auction = 300 } end
        if id == 403 then return { mailTo = "Bob", mailCount = 5 } end
        -- This character's queue wants 4 of the 10, and Bob's the other 6.
        if id == 404 then return { need = 4, mailTo = "Bob", mailCount = 6 } end
        if id == 402 then return { auction = 25, disenchant = 500, canDisenchant = false, enchanter = "Ana" } end
    end,
    FillMail = function(_, name, items)
        filled[#filled + 1] = { name = name, items = items }
        return true
    end,
    FromBank = function() return { [501] = 10 } end,
    Holdings = function()
        return {
            { key = "me", short = "Me", realm = "Here", faction = "Horde", isCurrent = true },
            { key = "bob", short = "Bob", realm = "Here", faction = "Horde" },
            { key = "ana", short = "Ana", realm = "Here", faction = "Horde" },
            { key = "cy", short = "Cy", realm = "Here", faction = "Alliance" },
            { key = "di", short = "Di", realm = "Elsewhere", faction = "Horde" },
        }
    end,
    Mailbox = function(_, covered) mailboxSaid[#mailboxSaid + 1] = covered end,
} }
env.Enable(ns)
-- Mailing upgrades to alts is off unless ticked; these checks need it on.
ns.db.altUpgrades = true

local UI, Errands = ns.UI, ns.Errands

-- The line carrying a character's Fill mail button, and a click on it.
local function FillLine(name)
    for _, line in ipairs(UI.list.data) do
        if UI.fillRows[line] == name then return line end
    end
end
local function ClickFill(name)
    name = name or (Errands:NextRecipient() or {}).to
    UI.RowAction(FillLine(name))
end

-- The mailbox.
env.Fire("MAIL_SHOW")
suite.check("a mailbox brings the window up", UI:IsShown() and UI.openedFor == "mail")
suite.check("on Your bags", UI.view == "bags")
local bobLine = FillLine("Bob")
suite.check("Fill mail sits on Bob's first Mail line", bobLine and bobLine.mailTo == "Bob"
    and bobLine == (function()
        for _, row in ipairs(UI.list.data) do if row.mailTo == "Bob" then return row end end
    end)())
suite.check("and on Ana's", FillLine("Ana") ~= nil and FillLine("Ana").mailTo == "Ana")
suite.check("once each", (function()
    local n = 0
    for _ in pairs(UI.fillRows) do n = n + 1 end
    return n == 2
end)())
suite.check("so the foot has no Fill mail", not UI.mailButton:IsShown())
-- The button takes the worth column's place, so the note keeps its width
-- (notes ran over the row when the worth moved left of it, 2026-10-12).
local fillRow
for _, row in ipairs(UI.list.rows) do
    if row.data and UI.fillRows[row.data] then fillRow = row end
end
suite.check("a row with Fill mail shows the button", fillRow and fillRow.action:IsShown())
suite.check("in the worth column, with the worth on its tooltip", fillRow and fillRow.worth:GetText() == ""
    and fillRow.worth._point[1] == "RIGHT" and fillRow.worth._point[2] == -6)
suite.check("the footer says who presses Send", UI.footer:GetText():find("You press Send", 1, true) ~= nil)
suite.check("no bank buttons at a mailbox", not UI.bankButton:IsShown() and not UI.takeButton:IsShown())
suite.check("Tradeskills' mail panel is told to step aside", mailboxSaid[#mailboxSaid] == true)
-- The test frames run no scripts on Hide, so its OnHide is run by hand.
local function Close()
    UI:Hide()
    local onHide = UI.frame:GetScript("OnHide")
    if onHide then onHide(UI.frame) end
end
Close()
suite.check("closing Butler brings it back", mailboxSaid[#mailboxSaid] == false)
UI:Show("bags")
UI.openedFor = "mail"
suite.check("and opening it again covers it", mailboxSaid[#mailboxSaid] == true)

ClickFill("Bob")
local first = filled[1]
suite.check("a click fills Bob's mail", first and first.name == "Bob")
local counts = {}
for _, item in ipairs(first and first.items or {}) do counts[item.itemID] = item.count end
suite.check("as many as the alt needs, no more", counts[401] == 1 and counts[403] == 5)
suite.check("an alt's share goes even when this character's crafts want some",
    counts[404] == 6, tostring(counts[404]))
local ore = ns.Verdicts:Group("mail").rows
local oreReason
for _, row in ipairs(ore) do if row.itemID == 404 then oreReason = row.reason end end
suite.check("and the row says what stays", oreReason == "Mail 6 to Bob for their crafts, keep 4 for yours",
    tostring(oreReason))
suite.check("own crafts alone still keep it", ns.Verdicts:Kept({ ts = { need = 4 } }) == "keep")
suite.check("and nothing to spare keeps it", ns.Verdicts:Kept({ ts = { need = 4, mailTo = "Bob", mailCount = 0 } }) == "keep")
suite.check("then the next character", Errands:NextRecipient().to == "Ana")
ClickFill("Ana")
suite.check("the enchanter gets the whole item", filled[2] and filled[2].name == "Ana"
    and filled[2].items[1].itemID == 402 and filled[2].items[1].count == 1)
suite.check("nobody left", Errands:NextRecipient() == nil and not UI.mailButton:IsShown())
local ok, why = Errands:FillMail()
suite.check("and nothing more is filled", not ok and why == "Nothing left to mail." and #filled == 2)


-- After a mail Butler filled is sent, the next one fills by itself.
env.Fire("MAIL_CLOSED")
env.Fire("MAIL_SHOW")
local before = #filled
env.Fire("MAIL_SEND_SUCCESS")
suite.check("a mail sent by hand fills nothing", #filled == before)
ClickFill()
suite.check("Fill mail fills Bob's", #filled == before + 1 and filled[#filled].name == "Bob")
env.Fire("MAIL_SEND_SUCCESS")
suite.check("sending it fills Ana's straight away", #filled == before + 2 and filled[#filled].name == "Ana")
suite.check("and says so", env.ChatText():find("Sent. Filled a mail to Ana", 1, true) ~= nil)
env.Fire("MAIL_FAILED")
suite.check("a mail that fails can be filled again", Errands:NextRecipient().to == "Ana")
ClickFill()
env.Fire("MAIL_SEND_SUCCESS")
suite.check("the last one sent: nothing more to fill", #filled == before + 3)
suite.check("and Butler says that's all", env.ChatText():find("That's all the mail for now.", 1, true) ~= nil)
env.Fire("MAIL_CLOSED")
env.Fire("MAIL_SHOW")
ns.HandleSlash("fillnext")
suite.check("/bbutler fillnext turns it off", ns.db.fillNext == false)
ClickFill()
before = #filled
env.Fire("MAIL_SEND_SUCCESS")
suite.check("off, a Send fills nothing more", #filled == before)
ns.HandleSlash("fillnext")
suite.check("and back on", ns.db.fillNext == true)

env.Fire("MAIL_CLOSED")
suite.check("leaving the mailbox closes the window it opened", not UI:IsShown())
suite.check("and the cover comes off", mailboxSaid[#mailboxSaid] == false)

-- Already open when the mailbox opens, it still goes when the player leaves.
UI:Show("bags")
env.Fire("MAIL_SHOW")
suite.check("open before the mailbox: it takes the mailbox", UI.openedFor == "mail")
env.Fire("MAIL_CLOSED")
suite.check("and goes when the mailbox closes", not UI:IsShown())

-- Walking away can end the interaction without MAIL_CLOSED.
env.Fire("MAIL_SHOW")
suite.check("the mailbox brings it up again", UI:IsShown())
env.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
suite.check("walking away from the mailbox closes it", not UI:IsShown() and not Errands.mailOpen)
env.Fire("MAIL_CLOSED")
suite.check("and a MAIL_CLOSED after that changes nothing", not UI:IsShown())
UI:Show("bags")
env.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
suite.check("another interaction ending leaves it be", UI:IsShown())
Close()

-- A new visit starts again from the first character.
env.Fire("MAIL_SHOW")
suite.check("a new visit starts again", Errands:NextRecipient().to == "Bob")

-- With the Mail group folded, Fill mail goes back to the window's foot.
UI:Folded().mail = true
UI:Refresh(true)
suite.check("folded away, the foot fills Bob's", UI.mailButton:IsShown()
    and UI.mailButton.label:GetText() == "Fill mail to Bob", UI.mailButton.label:GetText())
local count = #filled
UI.mailButton:GetScript("OnClick")(UI.mailButton)
suite.check("and a click there fills it", #filled == count + 1 and filled[#filled].name == "Bob")
suite.check("then Ana's", UI.mailButton.label:GetText() == "Fill mail to Ana", UI.mailButton.label:GetText())
UI:Folded().mail = nil
UI:Refresh(true)
ClickFill("Bob")
suite.check("a row's button fills that character again", #filled == count + 2 and filled[#filled].name == "Bob")
env.Fire("MAIL_CLOSED")

-- Without Tradeskills' FillMail.
local fillMail = _G.BlackthornesTS.Butler.FillMail
_G.BlackthornesTS.Butler.FillMail = nil
env.Fire("MAIL_SHOW")
ok, why = Errands:FillMail()
suite.check("without Tradeskills it says so", not ok and why:find("Tradeskills", 1, true) ~= nil)
_G.BlackthornesTS.Butler.FillMail = function() error("boom") end
ok = Errands:FillMail()
suite.check("a Tradeskills that raises fills nothing", not ok)
_G.BlackthornesTS.Butler.FillMail = function() return false, "still filling the last mail" end
ok, why = Errands:FillMail()
suite.check("and its reason is passed on", not ok and why:find("still filling", 1, true) ~= nil, why)
_G.BlackthornesTS.Butler.FillMail = fillMail
env.Fire("MAIL_CLOSED")

-- The setting off.
ns.db.openAtMailbox = false
env.Fire("MAIL_SHOW")
suite.check("Open at a mailbox off: it stays shut", not UI:IsShown())
env.Fire("MAIL_CLOSED")
ns.db.openAtMailbox = true

-- The bank. Copper Ore goes on the Always bank list.
ns.Verdicts:SetChoice(404, "bank")
ns.Bags:Changed()
env.Fire("BANKFRAME_OPENED")
suite.check("the bank brings the window up", UI:IsShown() and UI.openedFor == "bank")
suite.check("with Move to bank", UI.bankButton:IsShown() and UI.bankButton.label:GetText() == "Move 1 to bank",
    UI.bankButton.label:GetText())
suite.check("and Take from bank", UI.takeButton:IsShown())
suite.check("no Fill mail at the bank", not UI.mailButton:IsShown())
local bankLine = UI:HeaderRow("bank")
suite.check("Move to bank sits on the Bank line", bankLine ~= nil and UI.bankButton._point[2] == bankLine
    and UI.bankButton._point[4] == -UI.LINE_BUTTON_RIGHT)
suite.check("Take from bank waits at the foot with no Jobs line", UI.takeButton._point[1] == "BOTTOMRIGHT"
    and UI.errandRoom ~= nil)

UI.bankButton:GetScript("OnClick")(UI.bankButton)
suite.check("the ore went to the bank", fake.bags[0][4] == nil and used[#used] == "0:4")
local banked = false
for _, item in pairs(fake.bags[-1]) do if item.id == 404 then banked = true end end
suite.check("and is there", banked)
suite.check("nothing left to put away: the button goes", not UI.bankButton:IsShown())

used = {}
UI.takeButton:GetScript("OnClick")(UI.takeButton)
suite.check("takes the smallest stacks that cover the need", table.concat(used, ",") == "-1:2,-1:3",
    table.concat(used, ","))
suite.check("and leaves the big one", fake.bags[-1][1] ~= nil and fake.bags[-1][1].count == 20)

-- Gear in the bank that Equipment calls an upgrade to wear now comes out
-- too: the better of two chests, and not a ring that waits on a level.
local function PutGear(slot, id, equipLoc)
    local item = { bag = -1, slot = slot, id = id, name = "Gear " .. id, quality = 2, price = 100, equipLoc = equipLoc }
    fake.bags[-1][slot] = item
    fake.info[id] = item
end
PutGear(10, 601, "INVTYPE_CHEST")
PutGear(11, 602, "INVTYPE_CHEST")
PutGear(12, 603, "INVTYPE_FINGER")
local gearSays = { [601] = { upgrade = "now", gain = 10 }, [602] = { upgrade = "now", gain = 20 }, [603] = { upgrade = "later" } }
_G.BlackthornesEquipment = { Butler = { Advise = function(_, link)
    local id = tonumber(tostring(link):match("item:(%d+)")) or link
    return gearSays[id]
end } }
env.Fire("PLAYERBANKSLOTS_CHANGED")
suite.check("a bank upgrade to wear now is offered", #Errands:BankUpgrades() == 1
    and Errands:BankUpgrades()[1].itemID == 602, #Errands:BankUpgrades())
used = {}
Errands:TakeFromBank()
suite.check("Take from bank brings it out first", used[1] == "-1:11", table.concat(used, ","))
suite.check("and leaves the weaker chest and the ring", fake.bags[-1][10] ~= nil and fake.bags[-1][12] ~= nil)
_G.BlackthornesEquipment = nil
Errands:ForgetBankUpgrades()
suite.check("without Equipment, no bank upgrades", #Errands:BankUpgrades() == 0)

-- A full bank stops the run.
ns.Verdicts:SetChoice(403, "bank")
ns.Bags:Changed()
bankFull = true
local before = #env.chat
ok = Errands:MoveToBank()
suite.check("a full bank stops and says so", ok and env.ChatText():find("bank is full", 1, true) ~= nil)
suite.check("and the cloth stays", fake.bags[0][3] ~= nil)
bankFull = false

-- Not in combat.
_G.InCombatLockdown = function() return true end
ok, why = Errands:MoveToBank()
suite.check("nothing moves in combat", not ok and why == "Not in combat.")
_G.InCombatLockdown = nil

env.Fire("BANKFRAME_CLOSED")
suite.check("leaving the bank closes the window it opened", not UI:IsShown())
ok, why = Errands:MoveToBank()
suite.check("away from the bank nothing moves", not ok and why == "Open your bank first.")

-- The right-click menu offers Always bank.
UI:Show()
UI:ShowMenu({ itemID = 401, name = "Bolt of Wool" })
UI.menu.bank:GetScript("OnClick")(UI.menu.bank)
suite.check("the menu puts it on the Always bank list", ns.db.alwaysBank[401] == true
    and ns.Verdicts:Choice(401) == "bank")
UI:ShowMenu({ itemID = 401, name = "Bolt of Wool" })
suite.check("and says so", UI.menu.bank.label:GetText() == "Always bank (now)" and UI.menu.decide:IsShown())
UI.menu.decide:GetScript("OnClick")(UI.menu.decide)
suite.check("Let Butler decide takes it off", ns.db.alwaysBank[401] == nil)

-- Always mail to: the player's characters on this realm and side.
local names = Errands:Characters()
suite.check("characters to mail to: same realm and side, not this one",
    table.concat(names, ",") == "Ana,Bob", table.concat(names, ","))
UI:ShowMenu({ itemID = 404, name = "Copper Ore" })
suite.check("the menu offers Always mail to", UI.menu.mail:IsShown())
UI.menu.mail:GetScript("OnClick")(UI.menu.mail)
suite.check("which lists them", UI.menu.characters[1]:IsShown()
    and UI.menu.characters[1].label:GetText() == "Ana" and UI.menu.back:IsShown())
UI.menu.characters[2]:GetScript("OnClick")(UI.menu.characters[2])
local choice, to = ns.Verdicts:Choice(404)
suite.check("a pick puts it on the Always mail list", choice == "mail" and to == "Bob"
    and ns.db.alwaysMail[404] == "Bob" and not ns.db.alwaysBank[404])
UI:ShowMenu({ itemID = 404, name = "Copper Ore" })
suite.check("and the menu says who", UI.menu.mail.label:GetText() == "Always mail to Bob")
UI:HideMenu()
local verdict, reason, _, _, extra = ns.Verdicts:Decide({ itemID = 404, count = 10 })
suite.check("it goes under Mail, to Bob", verdict == "mail" and extra and extra.to == "Bob", reason)
suite.check("less the 4 this character's queue needs", extra and extra.count == 6, extra and extra.count)
suite.check("all of it kept while the queue needs it all",
    (ns.Verdicts:Decide({ itemID = 404, count = 1 })) == "keep")
suite.check("bound to this character it is kept instead",
    (ns.Verdicts:Decide({ itemID = 404, count = 1, bound = true })) == "keep")
UI:ShowMenu({ itemID = 405, name = "Bound thing", bound = true })
suite.check("bound gear is not offered for mail", not UI.menu.mail:IsShown())
UI:ShowMenu({ itemID = 404, name = "Copper Ore" })
UI.menu.decide:GetScript("OnClick")(UI.menu.decide)
suite.check("Let Butler decide takes it off the mail list", ns.db.alwaysMail[404] == nil)

-- A bank alt typed by hand (another account) is offered too, once, never
-- this character, and Characters() itself is unchanged.
ns.db.bankAlt = "Zed"
suite.check("the typed bank alt joins the mail menu",
    table.concat(Errands:MailNames(), ",") == "Ana,Bob,Zed", table.concat(Errands:MailNames(), ","))
suite.check("but not the characters Butler knows",
    table.concat(Errands:Characters(), ",") == "Ana,Bob")
ns.db.bankAlt = "bob"
suite.check("a bank alt that is one of them shows once",
    table.concat(Errands:MailNames(), ",") == "Ana,Bob", table.concat(Errands:MailNames(), ","))
ns.db.bankAlt = "Me"
suite.check("never the character playing",
    table.concat(Errands:MailNames(), ",") == "Ana,Bob", table.concat(Errands:MailNames(), ","))
ns.db.bankAlt = "Zed"
UI:ShowMenu({ itemID = 404, name = "Copper Ore" })
UI.menu.mail:GetScript("OnClick")(UI.menu.mail)
suite.check("the menu lists the bank alt", UI.menu.characters[3]:IsShown()
    and UI.menu.characters[3].label:GetText() == "Zed")
UI.menu.characters[3]:GetScript("OnClick")(UI.menu.characters[3])
suite.check("and a pick mails it there", ns.db.alwaysMail[404] == "Zed")
UI:ShowMenu({ itemID = 404, name = "Copper Ore" })
UI.menu.decide:GetScript("OnClick")(UI.menu.decide)
ns.db.bankAlt = nil

-- Never a mail to the character playing (a player found one, 2026-10-11):
-- the Always mail list is account wide, so it can name this character, and
-- an older Tradeskills could too.
-- On the character it names, it has arrived: the usual rules decide it, as
-- if it were on no list (the owner, 2026-10-18).
local usualVerdict, usualReason = ns.Verdicts:Decide({ itemID = 404, count = 1 })
ns.Verdicts:SetChoice(404, "mail", "Me")
verdict, reason = ns.Verdicts:Decide({ itemID = 404, count = 1 })
suite.check("Always mail to the character you're on is decided as usual",
    verdict == usualVerdict and reason == usualReason and not reason:find("Always mail", 1, true), reason)
ns.Verdicts:SetChoice(404, nil)
local advise = _G.BlackthornesTS.Butler.Advise
_G.BlackthornesTS.Butler.Advise = function(_, id)
    if id == 401 then return { mailTo = "Me", mailCount = 1 } end
    if id == 402 then return { disenchant = 500, canDisenchant = false, enchanter = "Me" } end
end
suite.check("a craft mail to the character you're on is no mail",
    (ns.Verdicts:Decide({ itemID = 401, count = 1, link = "item:401" })) ~= "mail")
suite.check("nor a disenchant mail", (ns.Verdicts:Decide({ itemID = 402, count = 1, link = "item:402" })) ~= "mail")
_G.BlackthornesTS.Butler.Advise = advise

-- The chat line names the full name Tradeskills filled in.
_G.BlackthornesTS.Butler.FillMail = function(_, name) return true, nil, name .. " Smith" end
ns.Verdicts:Changed(true)
env.Fire("MAIL_SHOW")
ok, why = Errands:FillMail()
suite.check("the chat line has the full name", ok and why:find(" Smith: check it", 1, true) ~= nil, why)
_G.BlackthornesTS.Butler.FillMail = fillMail
env.Fire("MAIL_CLOSED")

-- Names are never shortened (the owner's rule, 2026-10-11). A choice saved
-- as "Bob S." before then is read as the full name, and the menu grows to
-- fit a long one.
local holdings = _G.BlackthornesTS.Butler.Holdings
_G.BlackthornesTS.Butler.Holdings = function()
    return {
        { key = "me", short = "Me Myself", realm = "Here", faction = "Horde", isCurrent = true },
        { key = "bob", short = "Bob Stonebreakerson", realm = "Here", faction = "Horde" },
        { key = "bob2", short = "Bob Ashenmoor", realm = "Here", faction = "Horde" },
    }
end
ns.Verdicts:Changed(true)
ns.db.alwaysMail[404] = "Bob S."
local _, savedTo = ns.Verdicts:Choice(404)
suite.check("an old short name is read as the full one", savedTo == "Bob Stonebreakerson", savedTo)
suite.check("and is left as saved", ns.db.alwaysMail[404] == "Bob S.")
ns.db.alwaysMail[404] = "Me M."
do
    local v, _, _, _, x = ns.Verdicts:Decide({ itemID = 404, count = 1 })
    suite.check("an old short name for the character playing is never mailed", not (v == "mail" and x and ns.Verdicts:IsMe(x.to)), x and x.to)
end
-- A first name alone, saved before last names were read.
ns.db.alwaysMail[404] = "Me"
local _, bareTo = ns.Verdicts:Choice(404)
suite.check("a first name alone is read as the full one", bareTo == "Me Myself", tostring(bareTo))
do
    local v, _, _, _, x = ns.Verdicts:Decide({ itemID = 404, count = 1 })
    suite.check("and the character playing never mails it", not (v == "mail" and x and ns.Verdicts:IsMe(x.to)), x and x.to)
end
ns.db.alwaysMail[404] = "Bob"
local _, twoBobs = ns.Verdicts:Choice(404)
suite.check("a first name two characters share is left as saved", twoBobs == "Bob", tostring(twoBobs))
_G.BlackthornesTS.Butler.Holdings = function()
    return {
        { key = "me", short = "Bob Myself", realm = "Here", faction = "Horde", isCurrent = true },
        { key = "bob", short = "Bob Stonebreakerson", realm = "Here", faction = "Horde" },
    }
end
ns.Verdicts:Changed(true)
local _, sharedMine = ns.Verdicts:Choice(404)
suite.check("one the character playing shares is read as the one playing", sharedMine == "Bob Myself",
    tostring(sharedMine))
suite.check("so it is kept, never mailed", (ns.Verdicts:Decide({ itemID = 404, count = 1 })) == "keep")
_G.BlackthornesTS.Butler.Holdings = function()
    return {
        { key = "me", short = "Me Myself", realm = "Here", faction = "Horde", isCurrent = true },
        { key = "bob", short = "Bob Stonebreakerson", realm = "Here", faction = "Horde" },
        { key = "bob2", short = "Bob Ashenmoor", realm = "Here", faction = "Horde" },
    }
end
ns.Verdicts:Changed(true)
ns.db.alwaysMail[404] = "Bob S."
UI:ShowMenu({ itemID = 404, name = "Copper Ore" })
local menuWidth = UI.menu:GetWidth()
suite.check("the menu is as wide as its longest button",
    menuWidth >= UI.menu.mail:GetWidth() + 16 and UI.menu.keep:GetWidth() == UI.menu.mail:GetWidth(),
    menuWidth)
UI.menu.mail:GetScript("OnClick")(UI.menu.mail)
suite.check("and the characters page too", UI.menu:GetWidth() >= UI.menu.characters[1]:GetWidth() + 16)
UI:HideMenu()
ns.db.alwaysMail[404] = nil
_G.BlackthornesTS.Butler.Holdings = holdings
ns.Verdicts:Changed(true)

-- At a mailbox with nothing to mail, Butler still takes over.
_G.BlackthornesTS.Butler.Advise = function() return nil end
ns.Verdicts:Changed(true)
ns.Bags:Changed()
Close()
env.Fire("MAIL_SHOW")
suite.check("nothing to mail: the window still comes up", UI:IsShown() and UI.openedFor == "mail")
suite.check("without a Fill mail button", not UI.mailButton:IsShown())
env.Fire("MAIL_CLOSED")

-- Typed toggles.
ns.HandleSlash("bank")
suite.check("/bbutler bank turns it off", ns.db.openAtBank == false)
ns.HandleSlash("mailbox")
suite.check("/bbutler mailbox turns it off", ns.db.openAtMailbox == false)

-- An alt's queued craft beats the Always keep list for its share; the
-- list keeps the rest.
_G.BlackthornesTS.Butler.Advise = advise
ns.Verdicts:Forget()
ns.db.alwaysKeep = ns.db.alwaysKeep or {}
ns.db.alwaysKeep[403] = true
local verdict, reason, _, _, extra = ns.Verdicts:Decide({ itemID = 403, count = 20, quality = 1 })
suite.check("Always keep still mails an alt's craft share", verdict == "mail" and extra and extra.to == "Bob"
    and extra.count == 5 and reason == "Mail 5 to Bob for their crafts, keep the rest", tostring(reason))
verdict = ns.Verdicts:Decide({ itemID = 403, count = 20, quality = 1, bound = true })
suite.check("but soulbound stays kept", verdict == "keep")
ns.db.alwaysKeep[403] = nil
ns.db.alwaysKeep[402] = true
verdict = ns.Verdicts:Decide({ itemID = 402, count = 1, quality = 1 })
suite.check("and with no alt craft the list keeps it", verdict == "keep")
ns.db.alwaysKeep[402] = nil

-- Gear that is no use here but an upgrade for another character goes in
-- the mail to them, named by Tradeskills from Equipment's GUID.
local altSays = { alt = { key = "bob", gain = 12 } }
_G.BlackthornesEquipment = { Butler = { Advise = function() return altSays end } }
ns.Verdicts:Forget()
local gear = { itemID = 405, count = 1, quality = 2, link = "item:405" }
verdict, reason, _, _, extra = ns.Verdicts:Decide(gear)
suite.check("an upgrade for an alt is mailed to them", verdict == "mail" and extra and extra.to == "Bob",
    tostring(verdict))
suite.check("saying by how much", reason == "An upgrade for Bob (+12%)", tostring(reason))
altSays = { alt = { key = "bob", level = 25 } }
ns.Verdicts:Forget()
_, reason = ns.Verdicts:Decide(gear)
suite.check("an empty slot and a level to wait for", reason == "An upgrade for Bob (an empty slot) at level 25",
    tostring(reason))
gear.bound = true
suite.check("soulbound gear is never mailed", (ns.Verdicts:Decide(gear)) ~= "mail")
gear.bound = nil
altSays = { alt = { key = "cy", gain = 5 } }
ns.Verdicts:Forget()
suite.check("nor to the other side", (ns.Verdicts:Decide(gear)) ~= "mail")
altSays = { alt = { key = "me", gain = 5 } }
ns.Verdicts:Forget()
suite.check("nor to the character playing", (ns.Verdicts:Decide(gear)) ~= "mail")
altSays = { upgrade = "now", alt = { key = "bob", gain = 5 } }
ns.Verdicts:Forget()
suite.check("an upgrade here is kept to wear", (ns.Verdicts:Decide(gear)) == "keep")
_G.BlackthornesEquipment = nil

-- The next suites run in this same Lua, without Tradeskills.
_G.BlackthornesTS = nil

suite.done()
