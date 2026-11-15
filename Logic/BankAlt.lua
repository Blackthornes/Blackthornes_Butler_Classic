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
-- bankAltList (a shopping list's name, nil for none), bankAltAuctions
-- (true while Auction Items is ticked, off unless ticked) and
-- bankAltFullStacks (true while Full Stacks Only is ticked, off unless
-- ticked).
--
-- Full Stacks Only (a player asked, the owner said build it, 2026-11-02):
-- each mail slot costs postage however few it holds, and small stacks cost
-- more to list at the auction house. Ticked, the bank alt takes a stack
-- only once it is full (its count reaches the item's stack size; an item
-- that doesn't stack always counts). A smaller stack gets its next verdict
-- and stays in the bags. An item whose stack size the client hasn't loaded
-- yet is let through, as with the box unticked.
--
-- Each kind to its own character (the owner said build it, 2026-11-09,
-- from a mockup): a ticked kind can name a character of its own beside its
-- tick box, saved account wide in bankAltKindTo ([kind] = full name; nil,
-- the usual, sends it to the bank alt; never renamed). That kind then goes
-- to its own character, even when no bank alt is picked, by the same When,
-- Full Stacks Only, bound, grey and character-playing rules. On the
-- character a kind names, that kind stays put: it is never sent on to the
-- bank alt (as an Always mail item stays on its own character), so it
-- falls to Butler's usual rules there. The shopping list and Auction Items
-- still go to the bank alt everywhere else. Fill mail already makes one
-- mail a character.
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
--- another account is not; it is still kept and mailed as typed.
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

local function KindTo()
    local map = ns.db and ns.db.bankAltKindTo
    return type(map) == "table" and map or nil
end

--- The character this kind goes to instead of the bank alt, or nil for
--- the bank alt (the usual).
function BankAlt:KindTo(key)
    local map = KindTo()
    return map and Text(map[key]) or nil
end

--- Send a kind to its own character (nil puts it back on the bank alt).
--- A first name alone or "Ana S." is read as one of the player's
--- characters, as for the bank alt.
function BankAlt:SetKindTo(key, name)
    if not (ns.db and LABELS[key]) then return end
    name = Text(name)
    if name and ns.Errands and ns.Errands.FullName then name = ns.Errands:FullName(name) end
    local map = KindTo()
    if name then
        if not map then
            map = {}
            ns.db.bankAltKindTo = map
        end
        map[key] = name
    elseif map then
        map[key] = nil
    end
    self:Changed()
end

--- A name the player typed for a kind: any character's name, as TypeName
--- takes it (Era names are one word). Returns the name kept, or
--- nil and why.
function BankAlt:TypeKindTo(key, name)
    name = Text(name)
    if not name then return nil end
    if ns.Errands and ns.Errands.FullName then name = ns.Errands:FullName(name) end
    self:SetKindTo(key, name)
    return self:KindTo(key)
end

--- Does any ticked kind go to a character of its own?
function BankAlt:AnyKindTo()
    for _, kind in ipairs(self.KINDS) do
        if self:KindOn(kind.key) and self:KindTo(kind.key) then return true end
    end
    return false
end

--- Is anything sent by kind at all (a bank alt, or a kind's own character)?
function BankAlt:Active()
    return self:Name() ~= nil or self:AnyKindTo()
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

function BankAlt:FullStacksOn()
    return ns.db and ns.db.bankAltFullStacks == true or false
end

function BankAlt:SetFullStacks(on)
    if not ns.db then return end
    ns.db.bankAltFullStacks = on and true or nil
    self:Changed()
end

--- Is this carried stack full? True when its count reaches the item's
--- stack size, or the stack size isn't known yet.
function BankAlt:FullStack(entry)
    if not (entry and entry.itemID) then return false end
    local most = tonumber((select(8, Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, entry.itemID))))
    if not most or most <= 1 then return true end
    return (tonumber(entry.count) or 1) >= most
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

--- `name` when that character may take this carried item at all: not
--- soulbound, not grey, a full stack when asked for, and not the
--- character playing.
function BankAlt:MayTakeFor(entry, name)
    if not (name and entry and entry.itemID) then return nil end
    if entry.bound or entry.quality == 0 then return nil end
    if self:FullStacksOn() and not self:FullStack(entry) then return nil end
    if ns.Verdicts and ns.Verdicts:IsMe(name) then return nil end
    return name
end

--- The bank alt's name when it may take this carried item at all.
function BankAlt:MayTake(entry)
    return self:MayTakeFor(entry, self:Name())
end

--- The ticked kind of this item and the character of its own it goes to,
--- or nil when it goes to the bank alt (or nowhere).
function BankAlt:OwnTarget(entry)
    local kind = self.KindOf(entry)
    if not (kind and self:KindOn(kind)) then return nil end
    local to = self:KindTo(kind)
    if to then return kind, to end
    return nil
end

--- On the character this item's kind is sent to, it stays put: never sent
--- on to the bank alt.
function BankAlt:Stays(entry)
    local _, to = self:OwnTarget(entry)
    return to ~= nil and ns.Verdicts ~= nil and ns.Verdicts:IsMe(to)
end

--- Who takes this carried item? Their name, why ("Cloth" or the list's
--- name) and true when it is a kind's own character, not the bank alt; or
--- nil.
function BankAlt:Takes(entry)
    local kind, to = self:OwnTarget(entry)
    if to then
        local name = self:MayTakeFor(entry, to)
        if name then return name, LABELS[kind], true end
        return nil
    end
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
    if self:Stays(entry) then return nil end
    if TAKES[self:When()][verdict] then
        local name, what, own = self:Takes(entry)
        if name and own then
            return "mail", L.Format("%s, for %s", what, name), { to = name }
        elseif name then
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
    local own = {}
    for _, kind in ipairs(self.KINDS) do
        local to = self:KindOn(kind.key) and self:KindTo(kind.key)
        if to then own[#own + 1] = L.Format("%s, for %s", kind.label, to) end
    end
    if not name then
        ns.Print(L["no bank alt yet. Pick one on the Bank alt page in Settings, or type /bbutler bankalt Name."])
        for _, line in ipairs(own) do ns.Print(line) end
        return
    end
    local kinds = {}
    for _, kind in ipairs(self.KINDS) do
        if self:KindOn(kind.key) and not self:KindTo(kind.key) then kinds[#kinds + 1] = kind.label end
    end
    ns.Print(L.Format("your bank alt is %s (%s).", name, self.WHEN_LABELS[self:When()]))
    ns.Print(#kinds > 0 and L.Format("It takes: %s.", table.concat(kinds, ", ")) or L["It takes no kinds of items."])
    if self:ListName() then ns.Print(L.Format("And everything on your %s list.", self:ListName())) end
    for _, line in ipairs(own) do ns.Print(line) end
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
        elseif ns.Verdicts:IsMe(name) then
            ns.Print(L.Format("%s is your bank alt. You're playing it, so nothing gets mailed to it from here.", BankAlt:Name()))
        else
            ns.Print(L.Format("%s is your bank alt.", BankAlt:Name()))
        end
    end
end)
