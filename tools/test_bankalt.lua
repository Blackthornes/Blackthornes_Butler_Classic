-- The bank alt (Logic/BankAlt.lua, a player asked, the owner said build it
-- 2026-10-14): whole kinds of items, and a Tradeskills shopping list, go
-- under Mail to one of the player's characters.
--
-- What must hold:
--   1. Off until a character is picked: nothing changes.
--   2. Picked, a ticked kind goes under Mail to it, and Fill mail sends it.
--   3. "Before selling" takes what would sell or go to auction; "Before a
--      vendor" leaves auction to the auction house; "Only leftovers" takes
--      only Look at it.
--   4. Never: quest items, Always lists, goals, the craft queue (only the
--      alt's share goes to the alt crafting), greys, soulbound items, the
--      character playing.
--   5. An unticked kind is left to Butler's other rules.
--   6. Gear that binds when worn is a kind; gear that binds on pickup isn't.
--   7. Everything on the picked shopping list goes, whatever its kind.
--   8. The command and Settings change the same saved values.
--   9. A name typed for another account's character must be whole, first
--      and last, and is known as not one of this account's characters.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bankalt")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 2589, name = "Linen Cloth", quality = 1, price = 13, count = 20, class = 7, subclass = 5 },
    { bag = 0, slot = 2, id = 2318, name = "Light Leather", quality = 1, price = 15, count = 10, class = 7, subclass = 6 },
    { bag = 0, slot = 3, id = 2770, name = "Copper Ore", quality = 1, price = 5, count = 8, class = 7, subclass = 7 },
    { bag = 0, slot = 4, id = 765, name = "Silverleaf", quality = 1, price = 10, count = 5, class = 7, subclass = 9 },
    { bag = 0, slot = 5, id = 818, name = "Tigerseye", quality = 1, price = 100, class = 7, subclass = 11 },
    { bag = 0, slot = 6, id = 3000, name = "Fine Sword", quality = 2, price = 500, class = 2, bind = 2 },
    { bag = 0, slot = 7, id = 3001, name = "Bound Helm", quality = 2, price = 500, class = 4, bind = 1 },
    { bag = 0, slot = 8, id = 3002, name = "Soulbound Cloth", quality = 1, price = 13, class = 7, subclass = 5, bound = true },
    { bag = 0, slot = 9, id = 3003, name = "Grey Scrap", quality = 0, price = 3, class = 7, subclass = 6 },
    { bag = 0, slot = 10, id = 3004, name = "Quest Hide", quality = 1, price = 4, class = 7, subclass = 6, quest = "item" },
    { bag = 0, slot = 11, id = 3005, name = "Wool Cloth", quality = 1, price = 30, count = 10, class = 7, subclass = 5 },
    { bag = 0, slot = 12, id = 3006, name = "Shiny Pebble", quality = 1, price = 7, class = 15 },
})

local ts = { Butler = {
    Advise = function(_, id)
        if id == 2318 then return { auction = 60 } end         -- sells well at auction
        if id == 2770 then return { need = 8 } end             -- this character's queue
        if id == 765 then return { mailTo = "Cara Reed", mailCount = 5 } end -- an alt's queue
        if id == 2589 then return { auction = 5 } end          -- vendor pays more
        if id == 818 then return {} end
    end,
    Holdings = function()
        return {
            { key = "me", short = "Me Here", realm = "R", faction = "Horde", isCurrent = true },
            { key = "bank", short = "Banky Vault", realm = "R", faction = "Horde" },
            { key = "cara", short = "Cara Reed", realm = "R", faction = "Horde" },
        }
    end,
    Lists = function()
        return { { name = "Gems", items = { [3006] = 10 } }, { name = "Potions", items = {} } }, 1
    end,
    FillMail = function() return true end,
    Mailbox = function() end,
} }
_G.BlackthornesTS = ts
env.Enable(ns)

local Verdicts, BankAlt, UI = ns.Verdicts, ns.BankAlt, ns.UI

local function Row(name)
    for _, group in ipairs(Verdicts:Groups()) do
        for _, row in ipairs(group.rows) do
            if row.name == name then return row end
        end
    end
end

local function ToBank(name)
    local row = Row(name)
    return row and row.verdict == "mail" and row.mailTo == "Banky Vault"
end

UI:Show("bags")

-- 1.
suite.check("off until a character is picked", BankAlt:Name() == nil and not ToBank("Linen Cloth"))
suite.check("every kind is ticked unless unticked", BankAlt:KindOn("cloth") and BankAlt:KindOn("boe"))
suite.check("before selling by default", BankAlt:When() == "first")

-- 2.
BankAlt:SetName("Banky")
suite.check("a first name is read as the full name", ns.db.bankAlt == "Banky Vault", tostring(ns.db.bankAlt))
local linen = Row("Linen Cloth")
suite.check("cloth goes to the bank alt", ToBank("Linen Cloth"), linen and linen.verdict)
suite.check("saying why", linen.reason:find("Cloth, for your bank alt Banky Vault", 1, true) ~= nil, linen.reason)
suite.check("other trade goods go", ToBank("Tigerseye"))
local recipient = ns.Errands:RecipientFor("Banky Vault")
suite.check("Fill mail sends it", recipient ~= nil and recipient.count >= 20)

-- 9. Typed names.
suite.check("one of your characters is known", BankAlt:IsKnown("Banky Vault"))
local kept = BankAlt:TypeName("Stranger")
suite.check("a one-word name is kept (Era names are one word)", kept == "Stranger" and ns.db.bankAlt == "Stranger",
    tostring(ns.db.bankAlt))
kept = BankAlt:TypeName("Otto Farside")
suite.check("a whole name is kept", kept == "Otto Farside" and ns.db.bankAlt == "Otto Farside", tostring(kept))
suite.check("and known as not one of yours", not BankAlt:IsKnown("Otto Farside"))
suite.check("cloth goes to the typed name", Row("Linen Cloth").mailTo == "Otto Farside", Row("Linen Cloth").mailTo)
suite.check("a first name of yours still works", BankAlt:TypeName("Banky") == "Banky Vault")
suite.check("the label says Before Everything", BankAlt.WHEN_LABELS.first == "Before Everything")

-- 3.
suite.check("before selling, even what sells well at auction", ToBank("Light Leather"))
BankAlt:SetWhen("vendor")
suite.check("before a vendor, the auction house still wins", Row("Light Leather").verdict == "auction",
    Row("Light Leather").verdict)
suite.check("and what a vendor would buy goes", ToBank("Linen Cloth"))
BankAlt:SetWhen("leftovers")
suite.check("only leftovers: a vendor sale stays a sale", Row("Linen Cloth").verdict == "sell", Row("Linen Cloth").verdict)
suite.check("and what was left to look at goes", ToBank("Tigerseye"))
BankAlt:SetWhen("first")

-- 4.
suite.check("quest items stay", Row("Quest Hide").verdict == "keep")
suite.check("this character's craft queue keeps it", Row("Copper Ore").verdict == "keep")
local silverleaf = Row("Silverleaf")
suite.check("an alt's queued craft gets it first", silverleaf.mailTo == "Cara Reed", silverleaf.mailTo)
suite.check("greys still sell", Row("Grey Scrap").verdict == "sell")
suite.check("soulbound stays", not ToBank("Soulbound Cloth"))
Verdicts:SetChoice(3005, "keep")
suite.check("Always keep wins", Row("Wool Cloth").verdict == "keep")
Verdicts:SetChoice(3005, "mail", "Cara Reed")
suite.check("Always mail to another character wins", Row("Wool Cloth").mailTo == "Cara Reed")
Verdicts:SetChoice(3005, "mail", "Me Here")
suite.check("mailed here by the Always mail list, it is not sent on", not ToBank("Wool Cloth"))
Verdicts:SetChoice(3005, nil)
suite.check("off every list, it goes to the bank alt", ToBank("Wool Cloth"))

-- 5.
BankAlt:SetKind("cloth", false)
suite.check("unticked is saved as false", ns.db.bankAltKinds.cloth == false)
suite.check("an unticked kind is left alone", not ToBank("Linen Cloth"))
BankAlt:SetKind("cloth", true)
suite.check("ticked again it goes", ToBank("Linen Cloth") and ns.db.bankAltKinds.cloth == nil)

-- 6.
suite.check("gear that binds when worn goes", ToBank("Fine Sword"))
suite.check("gear that binds on pickup doesn't", not ToBank("Bound Helm"))

-- 7.
suite.check("an item of no kind stays", not ToBank("Shiny Pebble"))
BankAlt:SetList("Gems")
local pebble = Row("Shiny Pebble")
suite.check("on the picked list it goes", ToBank("Shiny Pebble"), pebble and pebble.verdict)
suite.check("saying which list", pebble.reason:find("On your Gems list", 1, true) ~= nil, pebble.reason)
suite.check("the lists' names", table.concat(BankAlt:ListNames(), ",") == "Gems,Potions")
BankAlt:SetList(nil)

-- The character playing is never mailed to.
BankAlt:SetName("Me Here")
suite.check("on the bank alt itself nothing moves", not Row("Linen Cloth").mailTo)

-- Without Tradeskills there are no lists, and nothing raises.
_G.BlackthornesTS = nil
Verdicts:Changed(true)
suite.check("no lists without Tradeskills", #BankAlt:ListNames() == 0)
_G.BlackthornesTS = ts

-- 10. Auction Items: whatever Butler would auction goes, whatever its kind.
BankAlt:SetName("Banky Vault")
BankAlt:SetWhen("vendor")
BankAlt:SetKind("leather", false)
suite.check("auction items are off unless ticked", not BankAlt:AuctionsOn() and Row("Light Leather").verdict == "auction")
BankAlt:SetAuctions(true)
suite.check("ticked, it is saved", ns.db.bankAltAuctions == true)
local leather = Row("Light Leather")
suite.check("an auction item of an unticked kind goes", ToBank("Light Leather"), leather and leather.verdict)
suite.check("saying it's to auction", leather.reason:find("To auction, for your bank alt Banky Vault", 1, true) ~= nil, leather.reason)
suite.check("a vendor sale stays a sale", Row("Linen Cloth").verdict == "mail" or Row("Linen Cloth").verdict == "sell")
BankAlt:SetKind("cloth", false)
suite.check("with its kind unticked, a vendor sale is not sent", Row("Linen Cloth").verdict == "sell", Row("Linen Cloth").verdict)
BankAlt:SetName("Me Here")
suite.check("on the bank alt itself it stays Auction", Row("Light Leather").verdict == "auction", Row("Light Leather").verdict)
BankAlt:SetName("Banky Vault")
BankAlt:SetAuctions(false)
suite.check("unticked it stays Auction", Row("Light Leather").verdict == "auction" and ns.db.bankAltAuctions == nil)
BankAlt:SetKind("cloth", true)
BankAlt:SetKind("leather", true)
BankAlt:SetName(nil)
BankAlt:SetWhen("first")

-- 8.
ns.HandleSlash("bankalt Banky Vault")
suite.check("/bbutler bankalt Name picks it", BankAlt:Name() == "Banky Vault")
ns.HandleSlash("bankalt leftovers")
suite.check("/bbutler bankalt leftovers", ns.db.bankAltWhen == "leftovers")
ns.HandleSlash("bankalt")
ns.HandleSlash("bankalt off")
suite.check("/bbutler bankalt off", ns.db.bankAlt == nil and not ToBank("Tigerseye"))

ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
suite.check("Settings shows nobody picked", controls.bankAltPick:GetName() == "Nobody")
controls.bankAltPick:Pick(controls.bankAltPick.index + 1)
suite.check("the picker picks a character", ns.db.bankAlt == "Banky Vault", tostring(ns.db.bankAlt))
controls.bankAltWhen:Pick(controls.bankAltWhen:GetValue() - 1)
suite.check("the stepper sets when", ns.db.bankAltWhen == "vendor", tostring(ns.db.bankAltWhen))
local box = controls.bankAltKinds.leather
box:GetScript("OnClick")(box)
suite.check("a tick box sets a kind", ns.db.bankAltKinds.leather == false)
controls.bankAltList:Pick(controls.bankAltList.index + 1)
suite.check("the list picker picks a list", ns.db.bankAltList == "Gems", tostring(ns.db.bankAltList))
local auctions = controls.bankAltAuctions
auctions:GetScript("OnClick")(auctions)
suite.check("the Auction Items box ticks it", ns.db.bankAltAuctions == true)

_G.BlackthornesTS = nil
suite.done()
