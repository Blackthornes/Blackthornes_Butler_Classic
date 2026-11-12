-- Blackthornes Butler -- Logic/MailRules.lua
-- Mail to anyone, and one list of every mail rule (a player asked for
-- several mail rules, a guildie getting all their Light Feathers; the
-- owner said build it from a mockup, 2026-11-12).
--
-- Always Mail To takes any whole name now, not only the player's own
-- characters: a typed name (Type a Name...) is remembered, account wide,
-- under OTHER PLAYERS so it is one click next time. Saved, never renamed:
--   mailNames = { "Full Name", ... }  (names typed, newest last)
-- Nothing else is new in the save: the rules this list shows live where
-- they always did (alwaysMail, bankAltKindTo, listRules, learned).
--
-- MailRules:All() gathers them for Settings' MAIL RULES list:
--   { kind = "item" | "kind" | "list" | "learned", itemID | key | id,
--     to = full name, from = "Always Mail" | "Kind" | "Your List" | "Learned" }
-- and MailRules:Remove(row) takes one off where it lives.

local _, ns = ...
local L = ns.L

local MailRules = ns.NewModule("MailRules")

-- The most typed names kept; the oldest goes first.
MailRules.KEEP = 20

local function Text(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

local function IsMe(name)
    return ns.Verdicts and ns.Verdicts.IsMe and ns.Verdicts:IsMe(name) or false
end

local function Saved()
    if not ns.db then return nil end
    if type(ns.db.mailNames) ~= "table" then ns.db.mailNames = {} end
    return ns.db.mailNames
end

--- Is this one of the player's own characters (this realm and side)?
function MailRules.IsOwn(name)
    name = Text(name)
    if not name then return false end
    if ns.BankAlt and ns.BankAlt.IsKnown then return ns.BankAlt:IsKnown(name) end
    local lower = name:lower()
    for _, each in ipairs(ns.Errands and ns.Errands:Characters() or {}) do
        if each:lower() == lower then return true end
    end
    return false
end

--- Keep a typed name for next time (never the character playing, never
--- one of the player's own, which are listed anyway).
function MailRules:Remember(name)
    name = Text(name)
    local saved = Saved()
    if not (name and saved) or IsMe(name) or self.IsOwn(name) then return end
    local lower = name:lower()
    for index = #saved, 1, -1 do
        if type(saved[index]) ~= "string" or saved[index]:lower() == lower then table.remove(saved, index) end
    end
    saved[#saved + 1] = name
    while #saved > self.KEEP do table.remove(saved, 1) end
end

--- Names to offer under OTHER PLAYERS: the ones typed before, and anyone an
--- item is already set to mail to, never the player's own characters or
--- the one playing. Sorted.
function MailRules:OtherNames()
    local seen, names = {}, {}
    local function Add(name)
        name = Text(name)
        if not name or IsMe(name) or self.IsOwn(name) then return end
        local lower = name:lower()
        if seen[lower] then return end
        seen[lower] = true
        names[#names + 1] = name
    end
    for _, name in ipairs(ns.db and type(ns.db.mailNames) == "table" and ns.db.mailNames or {}) do Add(name) end
    for _, to in pairs(ns.db and type(ns.db.alwaysMail) == "table" and ns.db.alwaysMail or {}) do Add(to) end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

--- A name the player typed: it must be whole, first and last, unless it is
--- one of their characters, and never the character playing. Returns the
--- name, or nil and why.
function MailRules:TypeName(name)
    name = Text(name)
    if not name then return nil end
    if ns.Errands and ns.Errands.FullName then name = ns.Errands:FullName(name) end
    if IsMe(name) then return nil, L["That's the character you're playing."] end
    if not self.IsOwn(name) and not name:find("%S%s+%S") then
        return nil, L["Type the whole name, first and last."]
    end
    return name
end

--- Always mail this item to a typed name: checked, remembered and set.
--- Returns the name, or nil and why.
function MailRules:MailTo(itemID, text)
    local name, why = self:TypeName(text)
    if not name then return nil, why end
    if not (itemID and ns.Verdicts) then return nil end
    self:Remember(name)
    ns.Verdicts:SetChoice(itemID, "mail", name)
    return name
end

--------------------------------------------------------------------------------
-- The one list
--------------------------------------------------------------------------------

local FROM = {
    item = L["Always Mail"],
    kind = L["Kind"],
    list = L["Your List"],
    learned = L["Learned"],
}
MailRules.FROM = FROM

--- Every mail rule, best known first: Always mail items, your lists' Mail
--- To and what Butler learned; with `showKinds`, each ticked kind and where
--- it goes too (the bank alt, or its own character).
function MailRules:All(showKinds)
    local rows = {}
    local db = ns.db
    if not db then return rows end
    for itemID, to in pairs(type(db.alwaysMail) == "table" and db.alwaysMail or {}) do
        to = Text(to)
        if to and tonumber(itemID) then
            if ns.Errands and ns.Errands.FullName then to = ns.Errands:FullName(to) end
            rows[#rows + 1] = { kind = "item", itemID = tonumber(itemID), to = to, from = FROM.item }
        end
    end
    if ns.ListRules then
        for _, list in ipairs(ns.ListRules:Lists()) do
            local rule = list.id ~= nil and ns.ListRules:Get(list.id) or {}
            if rule.mailTo then
                rows[#rows + 1] = { kind = "list", id = list.id, name = list.name, to = rule.mailTo, from = FROM.list }
            end
        end
    end
    for itemID, entry in pairs(type(db.learned) == "table" and db.learned or {}) do
        if type(entry) == "table" and entry.verdict == "mail" and Text(entry.to) and tonumber(itemID)
            and not (type(db.alwaysMail) == "table" and db.alwaysMail[itemID]) then
            rows[#rows + 1] = { kind = "learned", itemID = tonumber(itemID), to = Text(entry.to), from = FROM.learned }
        end
    end
    if showKinds and ns.BankAlt then
        local bankAlt = ns.BankAlt:Name()
        for _, kind in ipairs(ns.BankAlt.KINDS) do
            if ns.BankAlt:KindOn(kind.key) then
                local to = ns.BankAlt:KindTo(kind.key)
                if to or bankAlt then
                    rows[#rows + 1] = { kind = "kind", key = kind.key, name = kind.label, to = to or bankAlt,
                        bankAlt = to == nil, from = FROM.kind }
                end
            end
        end
    end
    return rows
end

--- Take one rule off where it lives. A kind going to its own character goes
--- back to the bank alt; one going to the bank alt is unticked.
function MailRules:Remove(row)
    if type(row) ~= "table" then return false end
    if row.kind == "item" and row.itemID and ns.Verdicts then
        ns.Verdicts:SetChoice(row.itemID, nil)
        return true
    elseif row.kind == "learned" and row.itemID and ns.Learning then
        ns.Learning:Forget(row.itemID)
        if ns.Verdicts then ns.Verdicts:Changed(true) end
        return true
    elseif row.kind == "list" and row.id ~= nil and ns.ListRules then
        return ns.ListRules:SetMailTo(row.id, nil)
    elseif row.kind == "kind" and row.key and ns.BankAlt then
        if row.bankAlt then ns.BankAlt:SetKind(row.key, false) else ns.BankAlt:SetKindTo(row.key, nil) end
        return true
    end
    return false
end

--- Change who a rule goes to. Lists and kinds keep their own place;
--- a learned mail becomes an Always mail.
function MailRules:Change(row, to)
    to = Text(to)
    if type(row) ~= "table" or not to then return false end
    self:Remember(to)
    if (row.kind == "item" or row.kind == "learned") and row.itemID and ns.Verdicts then
        ns.Verdicts:SetChoice(row.itemID, "mail", to)
        return true
    elseif row.kind == "list" and row.id ~= nil and ns.ListRules then
        return ns.ListRules:SetMailTo(row.id, to)
    elseif row.kind == "kind" and row.key and ns.BankAlt then
        ns.BankAlt:SetKindTo(row.key, to)
        return true
    end
    return false
end
