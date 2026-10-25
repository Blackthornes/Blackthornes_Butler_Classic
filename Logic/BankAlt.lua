-- Blackthornes Butler -- Logic/BankAlt.lua
-- A bank alt: one of the player's characters that takes whole kinds of
-- items by mail (a player asked, the owner said build it, 2026-10-14).
--
-- The player picks the character and ticks what goes there: cloth,
-- leather, ore and stone, herbs, meat, elemental, enchanting materials,
-- other trade goods and green or better gear that binds when worn, read
-- from the game's own item types (GetItemInfoInstant's class and
-- subclass), and with Tradeskills, everything on one of their shopping
-- lists (its Butler:Lists()). Those items show under Mail to the bank alt,
-- so Fill mail sends them; the player still presses Send.
--
-- Where it sits among the verdicts is the player's pick (`When`):
--   "first"      everything Butler would sell, auction, disenchant, wait on
--                or leave to look at goes to the bank alt instead
--   "vendor"     only what would be sold to a vendor or left to look at;
--                the auction house and a disenchant still win
--   "leftovers"  only what Butler would leave to look at
-- It is always after the player's own lists, quest items, equipment sets,
-- what the sisters keep (goals, the craft queue, upgrades, pet food), an
-- alt's queued crafts and every other mail, so none of those ever change.
-- Greys still sell, soulbound items stay, and nothing goes to the character
-- playing (Errands:IsMe): on the bank alt itself, nothing moves.
--
-- Saved account wide, never renamed: bankAlt (the character's full name,
-- nil off), bankAltWhen ("first", "vendor" or "leftovers"), bankAltKinds
-- ([kind] = false for each kind unticked; ticked unless unticked),
-- bankAltList (a shopping list's name, nil for none) and bankAltAuctions
-- (true while Auction Items is ticked, off unless ticked).
--
-- Auction Items (a player asked, the owner said build it, 2026-10-22): one
-- character sells everything at the auction house. Ticked, whatever
-- Butler's final word is Auction goes to the bank alt, whatever its kind,
-- in any When. Wait for a better price, Sell and the rest stay. A stack
-- worth less than a mail's postage stays too.

local _, ns = ...
local L = ns.L

local BankAlt = ns.NewModule("BankAlt")

local Items = ns.Items

-- The game's item classes and Trade Goods subclasses (Forever uses the
-- modern numbers: Linen Cloth is 7/5, Copper Ore 7/7, Peacebloom 7/9).
local TRADE_GOODS, WEAPON, ARMOR = 7, 2, 4
-- GetItemInfo's bindType for "Binds when equipped".
local BIND_ON_EQUIP = 2

-- In the order Settings shows them. `sub` is the Trade Goods subclass; the
-- "tradegoods" kind takes every other Trade Goods subclass.
BankAlt.KINDS = {
    { key = "cloth", sub = 5, label = L["Cloth"] },
    { key = "leather", sub = 6, label = L["Leather"] },
    { key = "metal", sub = 7, label = L["Ore, bars and stone"] },
    { key = "herb", sub = 9, label = L["Herbs"] },
    { key = "meat", sub = 8, label = L["Meat and cooking"] },
    { key = "elemental", sub = 10, label = L["Elemental"] },
    { key = "enchanting", sub = 12, label = L["Enchanting materials"] },
    { key = "tradegoods", label = L["Other trade goods"] },
    { key = "boe", label = L["Gear that binds when worn"] },
}

local KIND_BY_SUB, LABELS = {}, {}
for _, kind in ipairs(BankAlt.KINDS) do
    if kind.sub then KIND_BY_SUB[kind.sub] = kind.key end
    LABELS[kind.key] = kind.label
end

BankAlt.WHEN = { "first", "vendor", "leftovers" }
BankAlt.WHEN_LABELS = {
    first = L["Before Everything"],
    vendor = L["Before a Vendor"],
    leftovers = L["Only Leftovers"],
}

-- Which of Butler's own verdicts each pick takes over.
local TAKES = {
    first = { craft = true, sell = true, auction = true, disenchant = true, wait = true, look = true },
    vendor = { sell = true, look = true },
    leftovers = { look = true },
}

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function Text(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

--- The bank alt's full name, or nil when there is none.
function BankAlt:Name()
    return ns.db and Text(ns.db.bankAlt) or nil
end

--- Pick the bank alt (nil for nobody). A first name alone or "Ana S." is
--- read as the full name of one of the player's characters.
function BankAlt:SetName(name)
    if not ns.db then return end
    name = Text(name)
    if name and ns.Errands and ns.Errands.FullName then name = ns.Errands:FullName(name) end
    ns.db.bankAlt = name
    self:Changed()
end

--- Is the name one of the player's characters on this account (this
--- realm and side, or the one playing)? A name typed for a character on
--- another account is not, so Settings and chat say to check its spelling.
function BankAlt:IsKnown(name)
    name = Text(name)
    if not name then return false end
    if ns.Verdicts and ns.Verdicts:IsMe(name) then return true end
    local lower = name:lower()
    for _, each in ipairs(ns.Errands and ns.Errands:Characters() or {}) do
        if each:lower() == lower then return true end
    end
    return false
end

--- Set a name the player typed (a character on another account, say).
--- Era names are one word, so any name is taken as typed. Returns the
--- name kept, or nil.
function BankAlt:TypeName(name)
    name = Text(name)
    if not name then return nil end
    if ns.Errands and ns.Errands.FullName then name = ns.Errands:FullName(name) end
    self:SetName(name)
    return self:Name()
end

--- "first", "vendor" or "leftovers".
function BankAlt:When()
    local when = ns.db and ns.db.bankAltWhen
    if TAKES[when] then return when end
    return "first"
end

function BankAlt:SetWhen(when)
    if not (ns.db and TAKES[when]) then return end
    ns.db.bankAltWhen = when
    self:Changed()
end

local function Kinds()
    if type(ns.db.bankAltKinds) ~= "table" then ns.db.bankAltKinds = {} end
    return ns.db.bankAltKinds
end

--- Is this kind ticked? Every kind is, unless the player unticked it.
function BankAlt:KindOn(key)
    if not ns.db then return false end
    return Kinds()[key] ~= false
end

function BankAlt:SetKind(key, on)
    if not (ns.db and LABELS[key]) then return end
    if on then Kinds()[key] = nil else Kinds()[key] = false end
    self:Changed()
end

--- Does everything Butler would auction go to the bank alt?
function BankAlt:AuctionsOn()
    return ns.db and ns.db.bankAltAuctions == true or false
end

function BankAlt:SetAuctions(on)
    if not ns.db then return end
    ns.db.bankAltAuctions = on and true or nil
    self:Changed()
end

--- The shopping list it takes, by name, or nil.
function BankAlt:ListName()
    return ns.db and Text(ns.db.bankAltList) or nil
end

function BankAlt:SetList(name)
    if not ns.db then return end
    ns.db.bankAltList = Text(name)
    self:Changed()
end

function BankAlt:Changed()
    self.lists = nil
    if ns.Verdicts then ns.Verdicts:Changed(true) end
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end

--------------------------------------------------------------------------------
-- Tradeskills' shopping lists
--------------------------------------------------------------------------------

--- The player's shopping lists from Tradeskills, read once per
--- Verdicts.version (so once each time the window opens): { { name, id,
--- items = { [itemID] = want } } }. Empty without Tradeskills.
function BankAlt:Lists()
    local version = ns.Verdicts and ns.Verdicts.version
    if self.lists and self.listsVersion == version then return self.lists end
    local lists = {}
    local butler = ns.Errands and ns.Errands.Tradeskills("Lists")
    if butler then
        local ok, answer = pcall(butler.Lists, butler)
        if ok and type(answer) == "table" then
            for _, list in ipairs(answer) do
                if type(list) == "table" and Text(list.name) and type(list.items) == "table" then
                    lists[#lists + 1] = { name = Text(list.name), id = tonumber(list.id), items = list.items }
                end
            end
        end
    end
    self.lists, self.listsVersion = lists, version
    return lists
end

--- The names of the player's shopping lists, in their order.
function BankAlt:ListNames()
    local names = {}
    for _, list in ipairs(self:Lists()) do names[#names + 1] = list.name end
    return names
end

--- Is the item on the picked shopping list?
function BankAlt:OnList(itemID)
    local wanted = self:ListName()
    if not (wanted and itemID) then return false end
    for _, list in ipairs(self:Lists()) do
        if list.name == wanted then return list.items[itemID] ~= nil end
    end
    return false
end

--------------------------------------------------------------------------------
-- What goes
--------------------------------------------------------------------------------

--- The kind of an item ("cloth", "boe", ...), or nil when it is none of
--- them. `entry` is a bag slot (itemID, quality).
function BankAlt.KindOf(entry)
    local itemID = entry and entry.itemID
    if not itemID then return nil end
    local _, _, _, _, _, classID, subclassID =
        Items.Call({ "C_Item.GetItemInfoInstant", "GetItemInfoInstant" }, itemID)
    classID, subclassID = tonumber(classID), tonumber(subclassID)
    if classID == TRADE_GOODS then
        return KIND_BY_SUB[subclassID] or "tradegoods"
    end
    if (classID == WEAPON or classID == ARMOR) and (entry.quality or 0) >= 2 then
        local bindType = select(14, Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, itemID))
        if tonumber(bindType) == BIND_ON_EQUIP then return "boe" end
    end
    return nil
end

--- The bank alt's name when it may take this carried item at all: not
--- soulbound, not grey, and not the character playing.
function BankAlt:MayTake(entry)
    local name = self:Name()
    if not (name and entry and entry.itemID) then return nil end
    if entry.bound or entry.quality == 0 then return nil end
    if ns.Verdicts and ns.Verdicts:IsMe(name) then return nil end
    return name
end

--- Does the bank alt take this carried item? Its name and why ("Cloth" or
--- the list's name), or nil.
function BankAlt:Takes(entry)
    local name = self:MayTake(entry)
    if not name then return nil end
    if self:OnList(entry.itemID) then
        return name, L.Format("On your %s list", self:ListName())
    end
    local kind = self.KindOf(entry)
    if kind and self:KindOn(kind) then return name, LABELS[kind] end
    return nil
end

--- What Butler would do with the item (`verdict` from Verdicts:Best),
--- turned into Mail to the bank alt when the player's pick takes it over.
--- `worth` is one's worth, for Auction Items' postage check.
--- Returns "mail", why and { to, bankAlt = true }, or nil to leave it.
function BankAlt:Verdict(entry, verdict, worth)
    if TAKES[self:When()][verdict] then
        local name, what = self:Takes(entry)
        if name then
            return "mail", L.Format("%s, for your bank alt %s", what, name), { to = name, bankAlt = true }
        end
    end
    if verdict == "auction" and self:AuctionsOn() then
        local name = self:MayTake(entry)
        local postage = ns.Funds and ns.Funds.POSTAGE or 30
        local stack = (tonumber(worth) or 0) * (tonumber(entry.count) or 1)
        if name and stack >= postage then
            return "mail", L.Format("To auction, for your bank alt %s", name), { to = name, bankAlt = true }
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The command
--------------------------------------------------------------------------------

--- Say in chat who the bank alt is and what goes there.
function BankAlt:Report()
    local name = self:Name()
    if not name then
        ns.Print(L["no bank alt yet. Pick one on the Bank alt page in Settings, or type /bbutler bankalt Name."])
        return
    end
    local kinds = {}
    for _, kind in ipairs(self.KINDS) do
        if self:KindOn(kind.key) then kinds[#kinds + 1] = kind.label end
    end
    ns.Print(L.Format("your bank alt is %s (%s).", name, self.WHEN_LABELS[self:When()]))
    ns.Print(#kinds > 0 and L.Format("It takes: %s.", table.concat(kinds, ", ")) or L["It takes no kinds of items."])
    if self:ListName() then ns.Print(L.Format("And everything on your %s list.", self:ListName())) end
end

ns.RegisterCommand("bankalt", L["mail whole kinds of items to one of your characters (bankalt Name, off, first, vendor or leftovers)"], function(rest)
    rest = Text(rest)
    if not rest then
        BankAlt:Report()
        return
    end
    local word = rest:lower()
    if word == "off" then
        BankAlt:SetName(nil)
        ns.Print(L["no bank alt, so nothing is mailed by kind."])
    elseif TAKES[word] then
        BankAlt:SetWhen(word)
        ns.Print(L.Format("the bank alt is now set to: %s.", BankAlt.WHEN_LABELS[word]))
    else
        local name, why = BankAlt:TypeName(rest)
        if not name then
            ns.Print(why)
        elseif not BankAlt:IsKnown(name) then
            ns.Print(L.Format("%s is your bank alt. They aren't one of your characters here, so check the spelling.", name))
        elseif ns.Verdicts:IsMe(name) then
            ns.Print(L.Format("%s is your bank alt. You're playing it, so nothing gets mailed to it from here.", BankAlt:Name()))
        else
            ns.Print(L.Format("%s is your bank alt.", BankAlt:Name()))
        end
    end
end)
