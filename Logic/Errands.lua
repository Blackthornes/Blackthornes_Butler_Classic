-- Blackthornes Butler -- Logic/Errands.lua
-- At a mailbox and at the bank (the owner said start, 2026-10-11).
--
-- At a mailbox, Fill mail fills the game's own Send Mail page with the
-- Mail group for one character, through Tradeskills (its QueueMail:Fill,
-- which its Mail panel uses too):
--
--   _G.BlackthornesTS.Butler:FillMail(name, items, money)   -- true, or false and why
--
-- `money` is the gold fund's top-up for that character (Logic/Funds.lua),
-- put in the mail's gold boxes; gold alone is a mail too.
--
-- The player presses Send. Nothing is ever sent from here, the mail frame
-- is never hooked, moved, shown or hidden, and each click fills the next
-- character's mail. The Mail group only exists with Tradeskills loaded,
-- since it is Tradeskills that says who needs what, and who the player's
-- characters are for the Always mail list (Errands:Characters).
--
-- Butler takes over the mailbox (the owner picked it, 2026-10-11): it
-- comes up at every mailbox, and while its window is up there Tradeskills'
-- own mail panel steps aside, told through
--
--   _G.BlackthornesTS.Butler:Mailbox(covered)        -- true while Butler's window is up
--
-- Closing Butler's window brings Tradeskills' panel back.
--
-- At the bank, Move to bank puts the Bank group (the player's Always bank
-- list) into the bank, and Take from bank brings out what this character's
-- own queued crafts still want from it:
--
--   _G.BlackthornesTS.Butler:FromBank()              -- { [itemID] = count }
--
-- Both move whole stacks with C_Container.UseContainerItem, which the
-- selling test found works from addon code on Forever, one a step, each
-- slot read again just before it moves. A stack that does not move means
-- the bank or the bags are full, and the run stops there.
--
-- Smooth play: nothing here runs on a timer or reads the bank except for
-- a click; the bags are Butler's own coalesced read (Logic/Bags.lua).

local _, ns = ...
local L = ns.L

local Errands = ns.NewModule("Errands")

local Items = ns.Items
local Bags = ns.Bags

-- Seconds between one stack and the next, so the game has moved the last.
Errands.STEP = 0.2

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

--- Tradeskills' Butler table when it is loaded and has `method`.
function Errands.Tradeskills(method)
    local global = rawget(_G, "BlackthornesTS")
    if type(global) ~= "table" then return nil end
    local butler = rawget(global, "Butler")
    if type(butler) ~= "table" or type(butler[method]) ~= "function" then return nil end
    return butler
end

--------------------------------------------------------------------------------
-- The mailbox
--------------------------------------------------------------------------------

--- Who the Mail group goes to: a list of { to, items = { { itemID, count } },
--- count }, most items first. A row from Tradeskills' queue carries how many
--- the alt needs; one for the enchanter goes whole.
function Errands:Recipients()
    local byName, list = {}, {}
    local group = ns.Verdicts:Group("mail")
    for _, row in ipairs(group and group.rows or {}) do
        local to = row.mailTo
        if type(to) == "string" and to ~= "" and not self:IsMe(to) then
            local recipient = byName[to]
            if not recipient then
                recipient = { to = to, items = {}, byID = {}, count = 0, upgrades = {} }
                byName[to] = recipient
                list[#list + 1] = recipient
            end
            local count = row.count
            if type(row.mailCount) == "number" and row.mailCount > 0 then
                count = math.min(count, row.mailCount)
            end
            local item = recipient.byID[row.itemID]
            if item then
                item.count = item.count + count
            else
                item = { itemID = row.itemID, count = count }
                recipient.byID[row.itemID] = item
                recipient.items[#recipient.items + 1] = item
            end
            recipient.count = recipient.count + count
            -- An alt's upgrade is written down once the mail goes, so a
            -- copy left behind isn't offered again (Verdicts:UpgradesMailed).
            if row.upgrade then
                recipient.upgrades[#recipient.upgrades + 1] = { itemID = row.itemID, count = count }
            end
        end
    end
    -- The Jobs group's mail steps for this character (Logic/Jobs.lua):
    -- Fill mail sits on that line, so it sends what the line says, even
    -- an item Butler would keep for itself (two herbs a goal here was
    -- gathering were left out of a mail to the alt crafting with them,
    -- 2026-10-13). Tradeskills fills from the bags, never more than they
    -- hold.
    local plan = ns.Jobs and ns.Jobs.Plan and ns.Jobs:Plan()
    for _, step in ipairs(plan and plan.here and plan.here.steps or {}) do
        local to = step.kind == "mail" and step.to
        if type(to) == "string" and to ~= "" and not self:IsMe(to) then
            local recipient
            for _, known in ipairs(list) do
                if Errands.SameName(known.to, to) then recipient = known break end
            end
            if not recipient then
                recipient = { to = to, items = {}, byID = {}, count = 0, upgrades = {} }
                byName[to] = recipient
                list[#list + 1] = recipient
            end
            for _, wanted in ipairs(step.items or {}) do
                local item = recipient.byID[wanted.itemID]
                -- Gear in an equipment set never goes, whoever asks.
                if ns.Verdicts:InSet(wanted.itemID) then
                    item = false
                elseif not item then
                    item = { itemID = wanted.itemID, count = 0 }
                    recipient.byID[wanted.itemID] = item
                    recipient.items[#recipient.items + 1] = item
                end
                if item and wanted.count > item.count then
                    recipient.count = recipient.count + wanted.count - item.count
                    item.count = wanted.count
                end
            end
        end
    end
    -- Gold from the fund (Logic/Funds.lua) rides with that character's
    -- items, or goes as a mail of its own.
    if ns.Funds and self.mailOpen then
        for _, entry in ipairs((ns.Funds:Plan())) do
            if not self:IsMe(entry.to) then
                local recipient = byName[entry.to]
                if not recipient then
                    recipient = { to = entry.to, items = {}, byID = {}, count = 0 }
                    byName[entry.to] = recipient
                    list[#list + 1] = recipient
                end
                -- Postage is per item attached: the plan set aside one
                -- mail's, so the rest comes off the gold, or the purse can
                -- fall short of the stamps and the Send fail.
                local stacks = 0
                for _, item in ipairs(recipient.items) do
                    stacks = stacks + (Errands.Stacks(item.itemID, item.count) or 1)
                end
                local stamps = math.min(Errands.ATTACHMENTS, stacks) - 1
                local money = entry.amount - math.max(0, stamps) * (ns.Funds.POSTAGE or 30)
                recipient.money = money >= 1 and money or nil
            end
        end
    end
    table.sort(list, function(a, b)
        if #a.items ~= #b.items then return #a.items > #b.items end
        return a.to < b.to
    end)
    return list
end

--- The player's other characters an item can be mailed to: short names,
--- same realm and faction as the character playing, from Tradeskills'
--- record of them. Empty without Tradeskills.
local function Text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

--- Is a Holdings entry the character playing, under any of its records?
--- Tradeskills marks its own (`isCurrent`) and any old record of it
--- (`playing`, its Characters:IsPlaying).
local function Mine(entry)
    return type(entry) == "table" and (entry.isCurrent == true or entry.playing == true)
end
Errands.Mine = Mine

--- Tradeskills' Holdings and the entry for the character playing, or nil.
--- The entry is the first `isCurrent` one (Tradeskills lists it first).
local function Holdings()
    local butler = Errands.Tradeskills("Holdings")
    if not butler then return nil end
    local ok, list = pcall(butler.Holdings, butler)
    if not ok or type(list) ~= "table" then return nil end
    local me
    for _, entry in ipairs(list) do
        if not me and type(entry) == "table" and entry.isCurrent == true then me = entry end
    end
    return list, me
end

--- Tradeskills' Holdings and the character playing's entry (the gold fund
--- reads it), or nil without Tradeskills.
function Errands:Holdings()
    return Holdings()
end

--- Every character's name on this realm and side, the one playing too,
--- kept until Verdicts.version moves (the window opening, a choice made).
local namesCache, namesVersion, myName, myNames

local function Fold(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if text == "" then return nil end
    return text:lower()
end

--- Every way the character playing is named, folded: each name and short
--- name of every record of it, and its first name alone, which can't tell
--- it from another of that first name, so is never mailed. The game's own
--- first name too, so the guard holds without Tradeskills.
local function MyNames(list)
    local names = {}
    local function Add(text)
        local folded = Fold(text)
        if not folded then return end
        names[folded] = true
        names[folded:match("^(%S+)")] = true
    end
    for _, entry in ipairs(list or {}) do
        if Mine(entry) then
            Add(Text(entry.short))
            Add(Text(entry.name))
        end
    end
    local ok, first = pcall(Items.Call, { "UnitName" }, "player")
    if ok then pcall(Add, first) end
    return names
end

local function AllNames()
    local version = ns.Verdicts and ns.Verdicts.version
    if namesCache and namesVersion == version then return namesCache, myName, myNames end
    local names = {}
    local list, me = Holdings()
    myName = me and (Text(me.short) or Text(me.name)) or nil
    myNames = MyNames(list)
    local realm = me and Text(me.realm)
    local faction = me and Text(me.faction)
    for _, entry in ipairs(list or {}) do
        local name = type(entry) == "table" and (Text(entry.short) or Text(entry.name))
        if name and (not realm or not Text(entry.realm) or Text(entry.realm) == realm)
            and (not faction or not Text(entry.faction) or Text(entry.faction) == faction)
            and ns.Everyone.Ours(entry, me) then
            names[#names + 1] = name
        end
    end
    namesCache, namesVersion = names, version
    return names, myName, myNames
end

--- The full name Tradeskills gives a character, by its key (the GUID
--- Equipment names it by), when it is on this realm and side and is not
--- the character playing; nil otherwise. Read with the names above, once
--- per Verdicts.version.
local byKeyCache, byKeyVersion
function Errands:NameOf(key)
    if type(key) ~= "string" or key == "" then return nil end
    local version = ns.Verdicts and ns.Verdicts.version
    if not byKeyCache or byKeyVersion ~= version then
        byKeyCache, byKeyVersion = {}, version
        local list, me = Holdings()
        local realm = me and Text(me.realm)
        local faction = me and Text(me.faction)
        for _, entry in ipairs(list or {}) do
            local name = type(entry) == "table" and (Text(entry.short) or Text(entry.name))
            local entryKey = type(entry) == "table" and Text(entry.key)
            if name and entryKey and not Mine(entry)
                and (not realm or not Text(entry.realm) or Text(entry.realm) == realm)
                and (not faction or not Text(entry.faction) or Text(entry.faction) == faction)
                and ns.Everyone.Ours(entry, me) then
                byKeyCache[entryKey] = name
            end
        end
    end
    return byKeyCache[key]
end

--- The name Tradeskills gives the character playing (as Always mail and
--- mailTo name characters), or nil without Tradeskills. Read with the
--- names above, once per Verdicts.version.
function Errands:PlayingName()
    local _, name = AllNames()
    return name
end

--- Is this name the character playing? The one test every mail, gold
--- top-up, learned habit and Log out asks (2026-10-11: a player was told to
--- mail to, and log out for, the character they were on). Its full name,
--- the name of any old record of it, or its first name alone, without
--- regard to case or spacing; "Name-Realm" counts by its name. nil and
--- anything that is not a name are not.
function Errands:IsMe(name)
    if type(name) ~= "string" then return false end
    local folded = Fold(name:match("^(.-)%-[^%-%s]+$") or name)
    if not folded then return false end
    local _, _, mine = AllNames()
    return (mine or {})[folded] == true
end

--- The full name for a character name saved in an old short form: "Ana
--- S." or the first name alone ("Ana", from before last names were read).
--- Names are never shortened now (the owner's rule, 2026-10-11), but an
--- Always mail choice made before keeps what was saved. The one character
--- the short form fits answers. A first name alone that fits several
--- answers the character playing when it is one of them, as Tradeskills
--- reads it (its old name-realm records filed them all as one), so it is
--- never mailed to itself (the owner found Fill mail aimed at the
--- character he was on, 2026-10-11). Anything else is as given.
function Errands:FullName(name)
    if type(name) ~= "string" then return name end
    local prefix
    local first, initial = name:match("^(%S+) (%S+)%.$")
    if first then
        prefix = first .. " " .. initial
    elseif name:match("^%S+$") then
        prefix = name .. " "
    else
        return name
    end
    local names, me = AllNames()
    local found, several, mine
    for _, full in ipairs(names) do
        if full ~= name and full:sub(1, #prefix) == prefix then
            if found and found ~= full then several = true end
            found = found or full
            if full == me then mine = true end
        end
    end
    if several then
        return (not first and mine) and me or name
    end
    return found or name
end

function Errands:Characters()
    local list, me = Holdings()
    if not list then return {} end
    local realm = me and Text(me.realm)
    local faction = me and Text(me.faction)

    local names, seen = {}, {}
    for _, entry in ipairs(list) do
        local short = type(entry) == "table" and (Text(entry.short) or Text(entry.name))
        if short and not Mine(entry) and not self:IsMe(short) and not seen[short]
            and (not realm or not Text(entry.realm) or Text(entry.realm) == realm)
            and (not faction or not Text(entry.faction) or Text(entry.faction) == faction)
            and ns.Everyone.Ours(entry, me) then
            seen[short] = true
            names[#names + 1] = short
        end
    end
    table.sort(names)
    return names
end

--- The characters the Always mail menu offers: Characters(), and the bank
--- alt the player typed (one on another account, say) when it isn't one of
--- them already. Never the character playing.
function Errands:MailNames()
    local names = self:Characters()
    local alt = ns.BankAlt and ns.BankAlt:Name()
    if not alt or self:IsMe(alt) then return names end
    for _, name in ipairs(names) do
        if Errands.SameName(name, alt) then return names end
    end
    names[#names + 1] = alt
    table.sort(names)
    return names
end

--- Tell Tradeskills whether Butler's window covers the mailbox now, so its
--- mail panel steps aside or comes back. Only said when it changes.
--- `shown` is the window's state when the caller knows it (its OnHide).
function Errands:TellTradeskills(shown)
    if shown == nil then shown = ns.UI ~= nil and ns.UI:IsShown() == true end
    local covered = self.mailOpen == true and shown == true
    if covered == self.covered then return end
    self.covered = covered
    local butler = Errands.Tradeskills("Mailbox")
    if butler then pcall(butler.Mailbox, butler, covered) end
end

--- Do two names name the same character? Case and spacing aside.
function Errands.SameName(a, b)
    local fa, fb = Fold(a), Fold(b)
    return fa ~= nil and fa == fb
end

--- The mail for one character, filled already or not, or nil.
function Errands:RecipientFor(to)
    for _, recipient in ipairs(self:Recipients()) do
        if Errands.SameName(recipient.to, to) then return recipient end
    end
    return nil
end

--- The next character to fill a mail for on this visit, or nil.
function Errands:NextRecipient()
    for _, recipient in ipairs(self:Recipients()) do
        if not self.filled[recipient.to] then return recipient end
    end
    return nil
end

Errands.filled = {}

--- How many bag stacks `count` of an item takes, or nil when the client
--- has not said how many it stacks to.
function Errands.Stacks(itemID, count)
    local stack = select(8, Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, itemID))
    local ok, size = pcall(function() return math.floor(stack + 0) end)
    if not ok or not size or size < 1 then return nil end
    return math.ceil((tonumber(count) or 0) / size)
end

--- Put the items that take the fewest stacks first, in place. A mail holds
--- 12 stacks and Tradeskills fills it in this order, so a material that
--- fits in one stack goes in before a fifth stack of herbs: the vials for
--- an alt's potions were always last (worth the least) and left out
--- (a player found it, 2026-10-13). The rest goes in the next mail.
function Errands.FewestStacksFirst(items)
    local keys = {}
    for index, item in ipairs(items) do
        keys[item] = { stacks = Errands.Stacks(item.itemID, item.count) or math.huge, index = index }
    end
    table.sort(items, function(a, b)
        local ka, kb = keys[a], keys[b]
        if ka.stacks ~= kb.stacks then return ka.stacks < kb.stacks end
        return ka.index < kb.index
    end)
    return items
end

--- Fill the Send Mail page for one character (`to`, from the Fill mail
--- button on its row), or the next one. Returns true when it started, or
--- false and why.
function Errands:FillMail(to)
    if not self.mailOpen then return false, L["Open a mailbox first."] end
    if InCombat() then return false, L["Not in combat."] end
    local butler = Errands.Tradeskills("FillMail")
    if not butler then return false, L["Filling mail needs Blackthornes Tradeskills."] end
    -- Ask the other addons afresh: an alt's queue may have changed since
    -- the window last asked, and the click must send what it wants now.
    ns.Verdicts:Changed(true)
    local recipient
    if to then
        -- A click on a row fills that character's mail, again if need be.
        recipient = self:RecipientFor(to)
        if not recipient then return false, L.Format("Nothing left to mail to %s.", to) end
    else
        recipient = self:NextRecipient()
        if not recipient then return false, L["Nothing left to mail."] end
    end

    -- The last guard before the mail is filled: never the character playing.
    if self:IsMe(recipient.to) then return false, L["That's the character you're on."] end

    local items = {}
    for _, item in ipairs(recipient.items) do items[#items + 1] = { itemID = item.itemID, count = item.count } end
    Errands.FewestStacksFirst(items)

    local ok, started, why, fullName = pcall(butler.FillMail, butler, recipient.to, items, recipient.money)
    if not ok then return false, L["Tradeskills could not fill the mail."] end
    if started ~= true then
        return false, type(why) == "string" and L.Format("Couldn't fill it: %s.", why) or L["Couldn't fill it."]
    end
    self.filled[recipient.to] = true
    self.sending = recipient.to
    self.sendingUpgrades = recipient.upgrades
    self.sendingItems = items
    if recipient.money and ns.Funds then ns.Funds:Filled(recipient.to, recipient.money) end
    self:Update()
    -- The full name the mail went to, when Tradeskills says it: the short
    -- one ("Ana S.") read as a typo in chat.
    local to = type(fullName) == "string" and fullName ~= "" and fullName or recipient.to
    return true, L.Format("Filled a mail to %s: check it, then press Send.", to)
end

--- The mail Butler filled went (MAIL_SEND_SUCCESS): fill the next one
--- straight away, so a run of mail is one Send a character (the owner,
--- 2026-10-11: the addons should do the work). Only while the window is up
--- at the mailbox, out of combat, with "Fill the next mail" on; a mail the
--- player sent by hand fills nothing. The player still presses each Send.
function Errands:Sent()
    local was = self.sending
    self.sending = nil
    local upgrades = self.sendingUpgrades
    self.sendingUpgrades = nil
    local filledItems = self.sendingItems
    self.sendingItems = nil
    local call = self.sendCall
    self.sendCall = nil
    -- Only the mail Butler filled counts: a mail sent by hand after
    -- clearing the form records no upgrade and no gold (a ring once went
    -- down as mailed to the alt it was filled for while the player sent
    -- something else). Without the SendMail hook, trust the fill.
    if was and self.hookedSend and not (call and call.butler) then was = nil end
    if was then
        if upgrades then
            -- Only what was attached: Tradeskills fills at most a mail's
            -- worth of stacks and leaves the rest for the next one.
            if call and call.ids then
                local kept = {}
                for _, item in ipairs(upgrades) do
                    if call.ids[item.itemID] then kept[#kept + 1] = item end
                end
                upgrades = kept
            end
            ns.Verdicts:UpgradesMailed(was, upgrades)
        end
        if ns.Funds and ns.Funds.MailWent then ns.Funds:MailWent(was, call and call.money) end
        -- What did not fit in this mail (more than a mail's worth of
        -- stacks) is offered again for this character, so the next mail
        -- carries the rest.
        if call and call.ids and filledItems then
            for _, item in ipairs(filledItems) do
                local went = call.ids[item.itemID]
                if not went or (type(went) == "number" and went < (tonumber(item.count) or 0)) then
                    self.filled[was] = nil
                end
            end
        end
    elseif ns.Funds then
        ns.Funds.waiting = nil
    end
    if not was or not self.mailOpen or ns.db.fillNext == false then return end
    if not (ns.UI and ns.UI:IsShown()) then return end
    -- The bags say what left them a moment after the mail goes.
    C_Timer.After(Errands.NEXT_DELAY, function()
        if not Errands.mailOpen or InCombat() then return end
        Bags:Fresh(function()
            if not Errands.mailOpen or Errands.sending then return end
            if not Errands:NextRecipient() then
                ns.Print(L["Sent. That's all the mail for now."])
                return
            end
            local ok, message = Errands:FillMail()
            if message then ns.Print(ok and L.Format("Sent. %s", message) or message) end
        end)
    end)
end

Errands.NEXT_DELAY = 0.5

-- Stacks one mail carries.
Errands.ATTACHMENTS = tonumber(rawget(_G, "ATTACHMENTS_MAX_SEND")) or 12

--- SendMail was called (a post-hook, nothing is changed): note whether it
--- is the mail Butler filled (Tradeskills' subject), what it carries and
--- its gold, for MAIL_SEND_SUCCESS.
function Errands:OnSendMail(recipient, subject)
    local okSubject, said = pcall(function() return (subject or "") .. "" end)
    local ids = {}
    for slot = 1, Errands.ATTACHMENTS do
        local name, itemID, _, count = Items.Call({ "GetSendMailItem" }, slot)
        local okID, id = pcall(function() return itemID + 0 end)
        if name ~= nil and okID and id then
            local okCount, units = pcall(function() return count + 0 end)
            ids[id] = (ids[id] or 0) + ((okCount and units) or 1)
        end
    end
    local money = tonumber((Items.Call({ "GetSendMailMoney" })))
    self.sendCall = {
        butler = okSubject and Errands.SUBJECTS[said] == true,
        ids = ids,
        money = money,
    }
end

-- The subjects Tradeskills' FillMail gives the mail Butler fills: gold on
-- its own goes as "Gold from ...", so a gold top-up counted as a mail sent
-- by hand, was never written down and was offered again straight away.
Errands.SUBJECT = "From Blackthornes Butler"
Errands.GOLD_SUBJECT = "Gold from Blackthornes Butler"
Errands.SUBJECTS = {
    [Errands.SUBJECT] = true,
    [Errands.GOLD_SUBJECT] = true,
}

--- The mail did not go: it can be filled again.
function Errands:SendFailed()
    if self.sending then self.filled[self.sending] = nil end
    self.sending = nil
    self.sendingUpgrades = nil
    self.sendCall = nil
    self:Update()
end

--------------------------------------------------------------------------------
-- The bank
--------------------------------------------------------------------------------

--- The bank's containers: the bank itself, the reagent bank and the bank
--- bag slots, on clients that have each.
function Errands.BankBagIDs()
    local index = _G.Enum and _G.Enum.BagIndex
    local ids, seen = {}, {}
    local function Add(id)
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    Add(type(index) == "table" and index.Bank or -1)
    if type(index) == "table" then Add(index.Reagentbank or index.ReagentBank) end
    -- The bank bags come after every carried bag: on a retail client the
    -- reagent bag is 5, so a guess from NUM_BAG_SLOTS alone would count it
    -- as the bank, and Take from bank would put its items away.
    local carried = Bags.BagIDs()
    local lastCarried = 0
    for _, id in ipairs(carried) do
        seen[id] = true
        if id > lastCarried then lastCarried = id end
    end
    local first = type(index) == "table" and (index.BankBag_1 or index.CharacterBankTab_1) or (lastCarried + 1)
    local count = tonumber(_G.NUM_BANKBAGSLOTS) or 7
    for bag = first, first + count - 1 do Add(bag) end
    return ids
end

local function NumSlots(bag)
    return tonumber(Items.Call({ "C_Container.GetContainerNumSlots", "GetContainerNumSlots" }, bag)) or 0
end

--- The Bank group's carried slots: { bag, slot, itemID } in bag order.
function Errands:ToBank()
    local slots = {}
    local group = ns.Verdicts:Group("bank")
    for _, row in ipairs(group and group.rows or {}) do
        for _, entry in ipairs(row.slots) do
            if not entry.locked then
                slots[#slots + 1] = { bag = entry.bag, slot = entry.slot, itemID = entry.itemID }
            end
        end
    end
    table.sort(slots, function(a, b)
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return slots
end

--- What this character's queued crafts want from its bank, per Tradeskills:
--- { [itemID] = count }, empty without it.
function Errands:BankWants()
    local butler = Errands.Tradeskills("FromBank")
    if not butler then return {} end
    local ok, wants = pcall(butler.FromBank, butler)
    if not ok or type(wants) ~= "table" then return {} end
    local clean = {}
    for itemID, count in pairs(wants) do
        if type(itemID) == "number" and type(count) == "number" and count > 0 then
            clean[itemID] = math.floor(count)
        end
    end
    return clean
end

--- Bank gear Equipment calls an upgrade to wear now (the owner asked
--- 2026-10-13): { { bag, slot, itemID } }, the best for each slot only (two
--- for rings and trinkets). Read while the bank is open, kept until the
--- bags or the bank change.
function Errands:BankUpgrades()
    if not self.bankOpen or not ns.Sisters.Butler("equipment") then return {} end
    if self.upgradeCache and self.upgradeKey == Bags.version then return self.upgradeCache end

    local bySlot = {}
    for _, bag in ipairs(Errands.BankBagIDs()) do
        for slot = 1, NumSlots(bag) do
            local entry = Bags.ReadSlot(bag, slot)
            if entry and entry.link and not entry.locked then
                local answer = ns.Sisters:Ask("equipment", entry)
                if answer and answer.upgrade == "now" then
                    local _, _, _, equipLoc = Items.Call({ "C_Item.GetItemInfoInstant", "GetItemInfoInstant" }, entry.itemID)
                    local group = (type(equipLoc) == "string" and equipLoc ~= "") and equipLoc or entry.itemID
                    bySlot[group] = bySlot[group] or {}
                    -- An empty slot (no percent) beats any percent.
                    local gain = ns.Sisters.Number(answer, "gain") or math.huge
                    table.insert(bySlot[group], { bag = bag, slot = slot, itemID = entry.itemID, gain = gain })
                end
            end
        end
    end

    local found = {}
    for _, list in pairs(bySlot) do
        table.sort(list, function(a, b) return a.gain > b.gain end)
        for i = 1, math.min(#list, ns.Verdicts.Wears(list[1].itemID)) do
            found[#found + 1] = { bag = list[i].bag, slot = list[i].slot, itemID = list[i].itemID }
        end
    end
    table.sort(found, function(a, b)
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    self.upgradeCache, self.upgradeKey = found, Bags.version
    return found
end

function Errands:ForgetBankUpgrades()
    self.upgradeCache, self.upgradeKey = nil, nil
end

--- How many things Take from bank would bring out: the number of items
--- wanted, counted once each, and each upgrade.
function Errands:WantedCount()
    local count = #self:BankUpgrades()
    for _ in pairs(self:BankWants()) do count = count + 1 end
    return count
end

--- The bank stacks to take for what is wanted: smallest first, until each
--- item's count is covered. Read now, while the bank is open.
function Errands:FromBankSlots()
    local upgrades = self:BankUpgrades()
    local wants = self:BankWants()
    if not next(wants) then return upgrades end

    local stacks = {}
    for _, bag in ipairs(Errands.BankBagIDs()) do
        for slot = 1, NumSlots(bag) do
            local entry = Bags.ReadSlot(bag, slot)
            if entry and wants[entry.itemID] and not entry.locked then
                stacks[#stacks + 1] = entry
            end
        end
    end
    table.sort(stacks, function(a, b)
        if a.count ~= b.count then return a.count < b.count end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)

    local left, slots = {}, {}
    for _, step in ipairs(upgrades) do slots[#slots + 1] = step end
    for itemID, count in pairs(wants) do left[itemID] = count end
    for _, entry in ipairs(stacks) do
        if left[entry.itemID] > 0 then
            slots[#slots + 1] = { bag = entry.bag, slot = entry.slot, itemID = entry.itemID }
            left[entry.itemID] = left[entry.itemID] - entry.count
        end
    end
    return slots
end

--- Move `slots` one at a time with UseContainerItem while the bank stays
--- open. `full` is said when a stack does not move.
function Errands:Move(slots, done, full)
    if self.moving then return false, L["Still moving the last ones."] end
    if not self.bankOpen then return false, L["Open your bank first."] end
    if InCombat() then return false, L["Not in combat."] end
    if #slots == 0 then return false, L["Nothing to move."] end
    if not Items.Resolve("C_Container.UseContainerItem") then return false, L["This game can't move items for Butler."] end

    self.moving = true
    local index, moved = 0, 0

    local function Finish(message)
        Errands.moving = false
        Bags:Changed()
        Errands:Update()
        if message then ns.Print(message) end
        if done then done(moved) end
    end

    local function Next()
        if not Errands.bankOpen or InCombat() then return Finish() end
        index = index + 1
        local step = slots[index]
        if not step then return Finish(moved == 1 and L.Format("moved %d stack.", moved) or L.Format("moved %d stacks.", moved)) end

        if not Bags.Holds(step.bag, step.slot, step.itemID) then return Next() end
        Items.Call({ "C_Container.UseContainerItem" }, step.bag, step.slot)

        C_Timer.After(Errands.STEP, function()
            -- Still there, unlocked: nowhere for it to go.
            if Bags.Holds(step.bag, step.slot, step.itemID) then
                return Finish(full(moved))
            end
            moved = moved + 1
            Next()
        end)
    end

    Next()
    return true
end

function Errands:MoveToBank()
    return self:Move(self:ToBank(), nil, function(moved) return L.Format("moved %d, then the bank is full.", moved) end)
end

function Errands:TakeFromBank()
    return self:Move(self:FromBankSlots(), nil, function(moved) return L.Format("moved %d, then your bags are full.", moved) end)
end

--------------------------------------------------------------------------------
-- Showing the buttons
--------------------------------------------------------------------------------

--- What the window's foot offers now: { mail = recipient or nil,
--- toBank = count, fromBank = count }. Nothing outside a mailbox or bank.
function Errands:Offers()
    local offers = { toBank = 0, fromBank = 0 }
    if self.mailOpen then offers.mail = self:NextRecipient() end
    if self.bankOpen then
        offers.toBank = #self:ToBank()
        offers.fromBank = self:WantedCount()
    end
    return offers
end

--- Is there anything to do here, so the window is worth opening by itself?
function Errands:HasWork(place)
    local offers = self:Offers()
    if place == "mail" then return offers.mail ~= nil end
    return offers.toBank > 0 or offers.fromBank > 0
end

function Errands:Update()
    if ns.UI then ns.UI:UpdateErrands() end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Errands:Arrived(place)
    if place == "mail" then
        self.mailOpen = true
        self.filled = {}
        self.sending = nil
    else
        self.bankOpen = true
        self:ForgetBankUpgrades()
    end
    Bags:Fresh(function()
        if ns.UI then ns.UI:AtPlace(place) end
        Errands:Update()
    end)
end

function Errands:Left(place)
    -- Leaving can be said twice (MAIL_CLOSED and the interaction ending).
    if place == "mail" and not self.mailOpen and not (ns.UI and ns.UI.openedFor == "mail") then return end
    if place == "bank" and not self.bankOpen and not (ns.UI and ns.UI.openedFor == "bank") then return end
    if place == "mail" then
        self.mailOpen = false
        self.sending = nil
        self.sendingUpgrades = nil
        self.sendCall = nil
        if ns.Funds then ns.Funds.waiting = nil end
    else
        self.bankOpen = false
        self:ForgetBankUpgrades()
    end
    if ns.UI then ns.UI:LeftPlace(place) end
    self:TellTradeskills()
    self:Update()
end

function Errands:OnEnable()
    ns.RegisterEvent(self, "MAIL_SHOW", function() Errands:Arrived("mail") end)
    ns.RegisterEvent(self, "MAIL_CLOSED", function() Errands:Left("mail") end)
    ns.RegisterEvent(self, "MAIL_SEND_SUCCESS", function() Errands:Sent() end)
    if type(rawget(_G, "SendMail")) == "function" then
        Errands.hookedSend = pcall(hooksecurefunc, "SendMail", function(recipient, subject)
            Errands:OnSendMail(recipient, subject)
        end)
    end
    ns.RegisterEvent(self, "MAIL_FAILED", function() Errands:SendFailed() end)
    ns.RegisterEvent(self, "BANKFRAME_OPENED", function() Errands:Arrived("bank") end)
    ns.RegisterEvent(self, "BANKFRAME_CLOSED", function() Errands:Left("bank") end)
    -- The bank's own slots changed: look for upgrades again, once a burst.
    ns.RegisterEvent(self, "PLAYERBANKSLOTS_CHANGED", function()
        Errands:ForgetBankUpgrades()
        if Errands.bankWaiting or not Errands.bankOpen then return end
        Errands.bankWaiting = true
        C_Timer.After(0.2, function()
            Errands.bankWaiting = false
            Errands:Update()
        end)
    end)
    -- Walking away ends the game's interaction with the mailbox or banker;
    -- heard as well in case the client says that and not MAIL_CLOSED (a
    -- player found the window left up after walking off, 2026-10-11).
    ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, _, kind)
        local place = Errands.InteractionPlace(kind)
        if place then Errands:Left(place) end
    end)
end

--- "mail" or "bank" for the game's interaction types, else nil.
function Errands.InteractionPlace(kind)
    local types = rawget(_G, "Enum") and rawget(Enum, "PlayerInteractionType")
    local mail = type(types) == "table" and rawget(types, "MailInfo") or 17
    local bank = type(types) == "table" and rawget(types, "Banker") or 8
    if kind == mail then return "mail" end
    if kind == bank then return "bank" end
    return nil
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("mailbox", L["turn the Butler window coming up at a mailbox on or off"], function()
    ns.db.openAtMailbox = not ns.db.openAtMailbox
    ns.Print(ns.db.openAtMailbox and L["the Butler window comes up at every mailbox."]
        or L["the Butler window no longer comes up at a mailbox."])
end)

ns.RegisterCommand("fillnext", L["turn filling the next mail after each Send on or off"], function()
    ns.db.fillNext = ns.db.fillNext == false
    ns.Print(ns.db.fillNext and L["after each Send, Butler fills the next mail."]
        or L["Butler fills a mail only when you click Fill mail."])
end)

ns.RegisterCommand("bank", L["turn the Butler window coming up at the bank on or off"], function()
    ns.db.openAtBank = not ns.db.openAtBank
    ns.Print(ns.db.openAtBank and L["the Butler window comes up at the bank when there is something to move."]
        or L["the Butler window no longer comes up at the bank."])
end)
