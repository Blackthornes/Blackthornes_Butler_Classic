-- Blackthornes Butler -- Logic/Funds.lua
-- A gold fund for every character (the owner asked 2026-10-11: "a minimum
-- gold fund for your characters and others with excess have the ability to
-- send gold to your alts to keep their minimum fund balance").
--
-- The player sets how much every character should keep ("Keep at least",
-- BlackthornesButlerDB.goldMinimum, copper, nil when off) and, if they
-- like, a different amount for one character (goldMinimumFor[full name] =
-- copper). Never rename either.
--
-- At a mailbox, a character with more than its own minimum is offered a
-- gold mail to each of the player's characters (same realm and side) that
-- is below theirs: the Gold rows, and Fill mail puts the gold in the Send
-- Mail page through Tradeskills (Butler:FillMail's `money`). The player
-- presses Send. The sender never goes below its own minimum, and each
-- mail's postage is counted.
--
-- Balances are Tradeskills' record of each character's gold (Holdings'
-- `gold`, `goldAt`), as last seen when that character played, so a row
-- says how old it is. Gold Butler filled and saw leave the purse is kept
-- in goldSent[full name] = { { amount, at, before } } (never rename it),
-- counted toward that character until its own record shows it took the
-- gold (its gold seen after the send at least `before` plus the amount,
-- its mailbox read after the send holding less than the amount, or its
-- saved items cleared after the send), or for 30 days, when unclaimed mail goes back.
--
-- Class training (Logic/ClassTraining.lua) counts too: a character keeps
-- back what its spells to train cost, as well as its amount, and one that
-- can't pay for them is topped up for them, while the fund is on.
--
-- Smooth play: the plan is worked out only while the Butler window shows,
-- again only when the purse, the bags or a setting moved (Funds.version),
-- with one read of Tradeskills' Holdings each time.

local _, ns = ...
local L = ns.L

local Funds = ns.NewModule("Funds")

local Items = ns.Items

-- What one mail costs to send.
Funds.POSTAGE = 30
-- How long gold sent is counted toward a character that has not been seen
-- taking it: unclaimed mail goes back after 30 days.
Funds.KEEP_SENT = 30 * 24 * 60 * 60

Funds.version = 0

local function Text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function Copper(value)
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value)
    return value >= 1 and value or nil
end

local function Now()
    return type(time) == "function" and time() or 0
end

local function Purse()
    if type(GetMoney) ~= "function" then return nil end
    local ok, money = pcall(function() return tonumber(GetMoney()) end)
    return ok and money or nil
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

--- How much every character keeps, or nil when off.
function Funds:Minimum()
    return ns.db and Copper(ns.db.goldMinimum) or nil
end

local function Overrides()
    if not ns.db then return {} end
    if type(ns.db.goldMinimumFor) ~= "table" then ns.db.goldMinimumFor = {} end
    return ns.db.goldMinimumFor
end

--- One character's own amount, or nil when it keeps the usual.
function Funds:Override(name)
    name = Text(name)
    if not name then return nil end
    local amount = Overrides()[name]
    if amount == 0 then return 0 end
    return Copper(amount)
end

--- What `name` keeps: its own amount, else the usual, else 0.
function Funds:MinimumFor(name)
    local own = self:Override(name)
    if own then return own end
    return self:Minimum() or 0
end

--- Is a fund set up at all?
function Funds:IsOn()
    if self:Minimum() then return true end
    for _, amount in pairs(Overrides()) do
        if type(amount) == "number" and amount >= 1 then return true end
    end
    return false
end

function Funds:Changed()
    self.version = self.version + 1
    self.plan = nil
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh(true) end
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end

--- Save the usual amount (copper; nil or 0 turns it off).
function Funds:SetMinimum(copper)
    if not ns.db then return end
    copper = Copper(copper)
    if copper == ns.db.goldMinimum then return end
    ns.db.goldMinimum = copper
    self:Changed()
end

--- Save one character's own amount; nil puts it back on the usual. 0
--- means it keeps nothing back (so it can give all it has).
function Funds:SetMinimumFor(name, copper)
    name = Text(name)
    if not name then return end
    copper = tonumber(copper)
    if copper then copper = math.max(0, math.floor(copper)) end
    local list = Overrides()
    if list[name] == copper then return end
    list[name] = copper
    self:Changed()
end

--------------------------------------------------------------------------------
-- The characters
--------------------------------------------------------------------------------

--- Every character on this realm and side from Tradeskills' record:
--- { name, gold, goldAt, isCurrent } each, and the one playing.
function Funds:Characters()
    local list, me = ns.Errands:Holdings()
    local characters, current = {}, nil
    if not list then return characters, nil end
    local realm = me and Text(me.realm)
    local faction = me and Text(me.faction)
    local seen = {}
    for _, entry in ipairs(list) do
        local name = type(entry) == "table" and (Text(entry.short) or Text(entry.name))
        -- Another record of the character playing (an old one Tradeskills
        -- still has) is not somebody to send gold to.
        local other = type(entry) == "table" and entry.isCurrent ~= true
            and (ns.Errands.Mine(entry) or ns.Errands:IsMe(name))
        if name and not seen[name] and not other
            and (not realm or not Text(entry.realm) or Text(entry.realm) == realm)
            and (not faction or not Text(entry.faction) or Text(entry.faction) == faction) then
            seen[name] = true
            local character = {
                name = name,
                gold = tonumber(entry.gold),
                goldAt = tonumber(entry.goldAt),
                mailAt = tonumber(entry.mailAt),
                mailMoney = tonumber(entry.mailMoney),
                clearedAt = tonumber(entry.clearedAt),
                isCurrent = entry.isCurrent == true,
                key = Text(entry.key),
            }
            characters[#characters + 1] = character
            if character.isCurrent then current = character end
        end
    end
    return characters, current
end

--------------------------------------------------------------------------------
-- Gold on its way
--------------------------------------------------------------------------------

local function SentTable()
    if not ns.db then return {} end
    if type(ns.db.goldSent) ~= "table" then ns.db.goldSent = {} end
    return ns.db.goldSent
end

--- Whether a send of `amount` at `at` has been taken: the character's gold
--- rose by it since, its mailbox was read after the send and no longer
--- holds that much gold (Tradeskills' `mailMoney`), or its saved items
--- were cleared after the send.
function Funds.Taken(character, amount, at, before)
    if character.clearedAt and character.clearedAt > at then return true end
    if before and character.gold and character.goldAt and character.goldAt > at
        and character.gold >= before + amount then
        return true
    end
    if character.mailAt and character.mailAt > at and character.mailMoney
        and character.mailMoney < amount then
        return true
    end
    return false
end

--- Gold sent to `character` and not yet seen taken, after letting go of
--- sends it has taken or that went back.
function Funds:OnItsWay(character, now)
    local sent = SentTable()
    local list = sent[character.name]
    if type(list) ~= "table" then return 0 end
    now = now or Now()
    local kept, total = {}, 0
    for _, send in ipairs(list) do
        local amount, at = tonumber(type(send) == "table" and send.amount), tonumber(type(send) == "table" and send.at)
        if amount and at and now - at < self.KEEP_SENT then
            if not Funds.Taken(character, amount, at, tonumber(send.before)) then
                kept[#kept + 1] = send
                total = total + amount
            end
        end
    end
    sent[character.name] = #kept > 0 and kept or nil
    return total
end

--- Write down gold that left for `name`.
function Funds:Sent(name, amount, before)
    name, amount = Text(name), Copper(amount)
    if not (name and amount) then return end
    local sent = SentTable()
    local list = type(sent[name]) == "table" and sent[name] or {}
    list[#list + 1] = { amount = amount, at = Now(), before = tonumber(before) }
    sent[name] = list
    self:Changed()
end

--------------------------------------------------------------------------------
-- The plan
--------------------------------------------------------------------------------

--- The gold mails to offer now: a list of { to, amount, have, at,
--- minimum, sent }, biggest need first, and the sender's spare after
--- them. Empty with no fund set, without Tradeskills, or with nothing to
--- spare. Kept until Funds.version or the purse moves.
function Funds:Plan()
    local purse = Purse()
    local training = ns.ClassTraining
    local key = ("%d:%s:%d"):format(self.version, tostring(purse), training and training.version or 0)
    if self.plan and self.planKey == key then return self.plan, self.spare end
    self.planKey = key
    self.plan, self.spare = {}, 0
    if not (self:IsOn() and purse) then return self.plan, 0 end

    local characters, me = self:Characters()
    if not me then return self.plan, 0 end
    local spare = purse - self:MinimumFor(me.name) - (training and training:ReadyCost() or 0)

    local short = {}
    local now = Now()
    for _, character in ipairs(characters) do
        if not character.isCurrent and character.gold then
            local minimum = self:MinimumFor(character.name)
            local sent = self:OnItsWay(character, now)
            local have = character.gold + sent
            local other = training and training:IsOn() and character.key and training:Other(character.key)
            local train = other and other.cost or 0
            if minimum + train > 0 and have < minimum + train then
                short[#short + 1] = { to = character.name, need = minimum + train - have, have = have,
                    at = character.goldAt, minimum = minimum, sent = sent, train = train > 0 and train or nil }
            end
        end
    end
    table.sort(short, function(a, b)
        if a.need ~= b.need then return a.need > b.need end
        return a.to < b.to
    end)

    for _, entry in ipairs(short) do
        local give = math.min(entry.need, spare - self.POSTAGE)
        if give < 1 then break end
        entry.amount = give
        spare = spare - give - self.POSTAGE
        self.plan[#self.plan + 1] = entry
    end
    self.spare = math.max(0, spare)
    return self.plan, self.spare
end

--- The plan's mail for `name`, or nil.
function Funds:For(name)
    for _, entry in ipairs((self:Plan())) do
        if entry.to == name then return entry end
    end
    return nil
end

--- What a Gold row says: "Has 12g (2 days ago), keeps 50g".
function Funds.Reason(entry)
    local text = Funds.KeepsText(entry)
    if entry.train then
        return L.Format("%s, plus %s to train new spells", text, Items.FormatMoney(entry.train))
    end
    return text
end

function Funds.KeepsText(entry)
    local seen = ns.Everyone and ns.Everyone.Age and ns.Everyone.Age(entry.at) or ""
    local have, keeps = Items.FormatMoney(entry.have), Items.FormatMoney(entry.minimum)
    if (entry.sent or 0) > 0 then
        local sent = Items.FormatMoney(entry.sent)
        if seen ~= "" then
            return L.Format("Has %s as of %s, with %s on its way. Keeps %s", have, seen, sent, keeps)
        end
        return L.Format("Has %s, with %s on its way. Keeps %s", have, sent, keeps)
    end
    if seen ~= "" then return L.Format("Has %s as of %s. Keeps %s", have, seen, keeps) end
    return L.Format("Has %s. Keeps %s", have, keeps)
end

--------------------------------------------------------------------------------
-- Watching a filled mail go
--------------------------------------------------------------------------------

--- Fill mail put `amount` in a mail to `name`: it is written down when
--- that mail goes (MAIL_SEND_SUCCESS, Errands:Sent calls MailWent).
function Funds:Filled(name, amount)
    local entry = self:For(name)
    self.waiting = {
        to = name, amount = amount,
        before = entry and entry.have and (entry.have - (entry.sent or 0)) or nil,
    }
end

--- The mail Butler filled for `name` went, carrying `money` copper (read
--- off the form as it was sent; nil when it could not be read). Watching
--- the purse instead counted gold taken from the inbox against it, and any
--- spend after an unsent fill as gold sent.
function Funds:MailWent(name, money)
    local waiting = self.waiting
    self.waiting = nil
    if not (waiting and waiting.to == name) then return end
    local amount = waiting.amount
    if type(money) == "number" then
        if money < 1 then return end
        amount = math.min(amount, money)
    end
    self:Sent(waiting.to, amount, waiting.before)
end

function Funds:MoneyChanged()
    self.plan = nil
    if self.refreshing then return end
    self.refreshing = true
    -- The purse moves in bursts (a sale, a mail taken): one redraw after.
    C_Timer.After(0.2, function()
        Funds.refreshing = false
        Funds.version = Funds.version + 1
        if ns.UI and ns.UI.IsShown and ns.UI:IsShown() then ns.UI:Refresh() end
    end)
end

function Funds:OnEnable()
    ns.RegisterEvent(self, "PLAYER_MONEY", function() Funds:MoneyChanged() end)
    ns.RegisterEvent(self, "MAIL_CLOSED", function() Funds.waiting = nil end)
    ns.RegisterEvent(self, "MAIL_FAILED", function() Funds.waiting = nil end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

--- Each character's gold, what it keeps and what it would be sent.
function Funds:Report()
    local characters = self:Characters()
    if #characters == 0 then
        ns.Print(L["the gold fund needs Blackthornes Tradeskills, which remembers your characters' gold."])
        return
    end
    local usual = self:Minimum()
    ns.Print(usual and L.Format("every character keeps at least %s.", Items.FormatMoney(usual))
        or L["no usual amount set. Type /bbutler goldmin 50g to set one."])
    for _, character in ipairs(characters) do
        local own = self:Override(character.name)
        local entry = self:For(character.name)
        local line = ("  %s: %s"):format(character.name,
            character.gold and Items.FormatMoney(character.gold) or L["gold not seen yet"])
        if character.isCurrent then line = L.Format("%s (you)", line) end
        if own then line = L.Format("%s, keeps %s", line, Items.FormatMoney(own)) end
        if entry then line = L.Format("%s, send %s", line, Items.FormatMoney(entry.amount)) end
        ns.PrintRaw(line)
    end
end

ns.RegisterCommand("gold", L["list each character's gold and the top-ups the gold fund would send"], function()
    Funds:Report()
end)

ns.RegisterCommand("goldmin", L["set the gold every character keeps, e.g. goldmin 50g (goldmin off to stop)"], function(rest)
    rest = rest or ""
    if rest:match("^%s*$") then return Funds:Report() end
    local copper = ns.Verdicts.ParseMoney(rest)
    if not copper then
        ns.Print(L["type an amount like 50g or 20g 50s, or off."])
        return
    end
    Funds:SetMinimum(copper)
    local usual = Funds:Minimum()
    ns.Print(usual and L.Format("every character keeps at least %s now. At a mailbox, Fill mail tops up those below it.", Items.FormatMoney(usual))
        or L["the usual gold amount is off."])
end)
