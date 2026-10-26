-- Blackthornes Butler -- Logic/Everyone.lua
-- Every character's items in one list: who has what, and whether it is in
-- their bags, their bank or their mailbox (a player asked, the owner
-- agreeing 2026-10-10).
--
-- Butler keeps no record of other characters. Blackthornes Tradeskills
-- already saves each character's bags, bank and mail as it last saw them,
-- so this asks it, once each time the list is built, inside a pcall and
-- read only:
--
--   _G.BlackthornesTS.Butler:Holdings()   -- a list, or nil
--
-- (see CLAUDE.md, "How Butler talks to the other four"; UI/WhoHas.lua
-- reads the same call for its tooltip lines). The bags of the
-- character playing come from Butler's own read (Logic/Bags.lua), which is
-- the freshest there is. Without Tradeskills the list shows only those.
--
-- Smooth play: the list is built only while it is shown, again only when
-- the bags moved (Bags.version) or it is asked for afresh, and the build
-- goes over the characters' items a few hundred a frame. Names come from
-- the client and are kept for the session; an item it has not loaded yet
-- is asked for and named when the answer comes (Items:Loaded).

local _, ns = ...

local L = ns.L

local Everyone = ns.NewModule("Everyone")

local Items = ns.Items

-- Item counts merged a frame, and new item names asked for a frame.
Everyone.BUDGET = 300
Everyone.NAME_BUDGET = 40

-- Where an item can be, in the order a holder's line names them.
Everyone.PLACES = { "bags", "bank", "mail" }
Everyone.PLACE_WORDS = { bags = L["in bags"], bank = L["in the bank"], mail = L["in the mail"] }

-- The built list: { [itemID] = item }, in name order in `sorted`.
Everyone.items = {}
Everyone.sorted = {}
Everyone.characters = {}
Everyone.version = 0
Everyone.stale = true

-- itemID = { name, lower, quality, icon }, kept for the session once named.
local names = {}

--------------------------------------------------------------------------------
-- Asking Tradeskills
--------------------------------------------------------------------------------

--- Tradeskills' Butler table when it is loaded and answers Holdings.
function Everyone.Tradeskills()
    local global = rawget(_G, "BlackthornesTS")
    if type(global) ~= "table" then return nil end
    local butler = rawget(global, "Butler")
    if type(butler) ~= "table" or type(butler.Holdings) ~= "function" then return nil end
    return butler
end

local function Counts(value)
    local counts = {}
    if type(value) ~= "table" then return counts end
    for itemID, count in pairs(value) do
        if type(itemID) == "number" and type(count) == "number" and count > 0 then
            counts[itemID] = math.floor(count)
        end
    end
    return counts
end

local function Text(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function Stamp(value)
    return type(value) == "number" and value or nil
end

--- Tradeskills' entry for the character playing in a Holdings() list, or nil.
function Everyone.PlayingEntry(list)
    if type(list) ~= "table" then return nil end
    for _, entry in ipairs(list) do
        if type(entry) == "table" and entry.isCurrent == true then return entry end
    end
    return nil
end

--- Is a friend's name? Tradeskills' Friends box, read in a pcall. A
--- friend's characters are never the player's own.
function Everyone.IsFriend(name)
    if not Text(name) then return false end
    local global = rawget(_G, "BlackthornesTS")
    local crafters = type(global) == "table" and rawget(global, "GuildCrafters")
    if type(crafters) ~= "table" or type(crafters.IsFriend) ~= "function" then return false end
    local ok, friend = pcall(crafters.IsFriend, crafters, name)
    return ok and friend == true
end

--- Is a Holdings() entry one of the player's own characters on this realm
--- and side? A character on another realm or side, or one a friend's
--- account shared (its `linked` name is under Tradeskills' Friends), is
--- left out of every list (a helper's items showed in the Bags window,
--- 2026-10-26). `me` is the character playing's entry; without one, or
--- without a realm or side on either, that part is not checked.
function Everyone.Ours(entry, me)
    if type(entry) ~= "table" then return false end
    if entry.isCurrent == true then return true end
    local realm = type(me) == "table" and Text(me.realm)
    local faction = type(me) == "table" and Text(me.faction)
    if realm and Text(entry.realm) and Text(entry.realm) ~= realm then return false end
    if faction and Text(entry.faction) and Text(entry.faction) ~= faction then return false end
    local linked = Text(entry.linked)
    if linked and Everyone.IsFriend(linked) then return false end
    return true
end

--- What the character playing carries, from Butler's own read of the bags.
function Everyone.OwnBags()
    local counts = {}
    for _, entry in pairs(ns.Bags.slots) do
        if entry.itemID then
            counts[entry.itemID] = (counts[entry.itemID] or 0) + (entry.count or 1)
        end
    end
    return counts
end

local function Now()
    return type(time) == "function" and time() or nil
end

local function Self()
    local name = Items.Call({ "UnitName" }, "player")
    return {
        key = "self", name = Text(name) or L["You"], short = Text(name) or L["You"],
        isCurrent = true, bags = {}, bank = {}, mail = {},
    }
end

--- Every character, as Tradeskills has them, checked field by field. A
--- field of the wrong type counts as not given. Nil when Tradeskills is
--- not loaded or its answer is no use; the character playing is then the
--- only one.
function Everyone:Read()
    local butler = Everyone.Tradeskills()
    if not butler then return nil end
    local ok, list = pcall(butler.Holdings, butler)
    if not ok or type(list) ~= "table" then return nil end

    local me = Everyone.PlayingEntry(list)
    local characters = {}
    for _, entry in ipairs(list) do
        -- An old record of the character playing (beside its GUID one) is
        -- the same character with an older count: only the live one
        -- counts, as on the tooltip (UI/WhoHas.lua).
        local oldSelf = type(entry) == "table" and entry.playing == true and entry.isCurrent ~= true
        if type(entry) == "table" and Text(entry.key) and not oldSelf and Everyone.Ours(entry, me) then
            characters[#characters + 1] = {
                key = entry.key,
                name = Text(entry.name) or entry.key,
                short = Text(entry.short) or Text(entry.name) or entry.key,
                isCurrent = entry.isCurrent == true,
                linked = Text(entry.linked),
                bags = Counts(entry.bags),
                bank = Counts(entry.bank),
                mail = Counts(entry.mail),
                bagsAt = Stamp(entry.bagsAt),
                bankAt = Stamp(entry.bankAt),
                mailAt = Stamp(entry.mailAt),
                -- Gold as Tradeskills last saw it, for the gold goals.
                gold = Stamp(entry.gold),
            }
        end
    end
    if #characters == 0 then return nil end
    return characters
end

--- Is the list everyone's, or only the bags of the character playing?
function Everyone:FromTradeskills()
    return self.fromTradeskills == true
end

--------------------------------------------------------------------------------
-- Names
--------------------------------------------------------------------------------

--- What the client says about an item: kept once it has a name, else
--- asked for and nil for now.
function Everyone.Info(itemID)
    local known = names[itemID]
    if known then return known end

    local name, _, quality, _, _, _, _, _, _, icon = Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, itemID)
    if type(name) ~= "string" or name == "" then
        Items:RequestLoad(itemID)
        return nil
    end
    if type(icon) ~= "number" and type(icon) ~= "string" then
        local _, _, _, _, instant = Items.Call({ "C_Item.GetItemInfoInstant", "GetItemInfoInstant" }, itemID)
        icon = instant
    end
    known = { name = name, lower = name:lower(), quality = tonumber(quality) or 1, icon = icon }
    names[itemID] = known
    return known
end

--- Forget the kept names (for tests, whose pretend items change).
function Everyone:ForgetNames()
    names = {}
end

local function Name(item)
    local info = Everyone.Info(item.itemID)
    if info then
        item.name, item.lower, item.quality, item.icon = info.name, info.lower, info.quality, info.icon
        item.named = true
    else
        item.name = L.Format("Item %d", item.itemID)
        item.lower = item.name:lower()
        item.quality = 1
        item.named = false
    end
end

local function SortItems(list)
    table.sort(list, function(a, b)
        if a.named ~= b.named then return a.named end
        if a.lower ~= b.lower then return a.lower < b.lower end
        return a.itemID < b.itemID
    end)
end

--- Names came in from the client: name the items still waiting and sort
--- again. Called once a burst of answers is over (Items:Loaded).
function Everyone:NamesArrived()
    if self.building then
        self.again = true
        return
    end
    local changed = false
    for _, item in ipairs(self.sorted) do
        if not item.named then
            Name(item)
            if item.named then changed = true end
        end
    end
    if changed then
        SortItems(self.sorted)
        self.version = self.version + 1
    end
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

--- The list must be built again before it is next shown.
function Everyone:Changed()
    self.stale = true
end

--- Is the list out of date: never built, asked afresh, or the bags moved?
function Everyone:IsStale()
    return self.stale or self.builtBags ~= ns.Bags.version
end

--- Build the list, a few hundred counts a frame. `done` runs when it is
--- over (when one is under way, after that one).
function Everyone:Build(done)
    if done then
        self.waiters = self.waiters or {}
        self.waiters[#self.waiters + 1] = done
    end
    if self.building then
        self.again = true
        return
    end
    self.building = true
    self.stale = false
    local bagsVersion = ns.Bags.version

    local characters = self:Read()
    self.fromTradeskills = characters ~= nil
    characters = characters or { Self() }

    -- The character playing carries what Butler's own read says.
    local ownRead = next(ns.Bags.slots) ~= nil or not ns.Bags.stale
    for _, character in ipairs(characters) do
        if character.isCurrent and ownRead then
            character.bags = Everyone.OwnBags()
            character.bagsAt = Now()
        end
    end

    -- One step per character and place, its counts merged a budget a frame.
    local steps = {}
    for _, character in ipairs(characters) do
        for _, place in ipairs(Everyone.PLACES) do
            local list = {}
            for itemID, count in pairs(character[place]) do list[#list + 1] = { itemID, count } end
            if #list > 0 then steps[#steps + 1] = { character = character, place = place, list = list } end
        end
    end

    local items, sorted = {}, {}
    local stepIndex, entryIndex = 1, 0

    local function Holder(item, character)
        local holder = item.byKey[character.key]
        if not holder then
            holder = { character = character, bags = 0, bank = 0, mail = 0, total = 0 }
            item.byKey[character.key] = holder
            item.holders[#item.holders + 1] = holder
        end
        return holder
    end

    local function Merge(step, itemID, count)
        local item = items[itemID]
        if not item then
            item = { itemID = itemID, total = 0, holders = {}, byKey = {} }
            items[itemID] = item
            sorted[#sorted + 1] = item
        end
        local holder = Holder(item, step.character)
        holder[step.place] = holder[step.place] + count
        holder.total = holder.total + count
        item.total = item.total + count
    end

    local nameIndex = 0

    local function Finish()
        for _, item in ipairs(sorted) do
            -- Most first; the character playing first among equals.
            table.sort(item.holders, function(a, b)
                if a.total ~= b.total then return a.total > b.total end
                if a.character.isCurrent ~= b.character.isCurrent then return a.character.isCurrent end
                return a.character.short < b.character.short
            end)
        end
        SortItems(sorted)

        Everyone.items, Everyone.sorted, Everyone.characters = items, sorted, characters
        Everyone.builtBags = bagsVersion
        Everyone.version = Everyone.version + 1
        Everyone.building = false

        if Everyone.again then
            Everyone.again = false
            return Everyone:Build()
        end
        local waiters = Everyone.waiters or {}
        Everyone.waiters = nil
        if Everyone.lateWaiter then
            waiters[#waiters + 1] = Everyone.lateWaiter
            Everyone.lateWaiter = nil
        end
        for _, fn in ipairs(waiters) do fn() end
    end

    local function NameStep()
        local stop = math.min(#sorted, nameIndex + Everyone.NAME_BUDGET)
        for i = nameIndex + 1, stop do Name(sorted[i]) end
        nameIndex = stop
        if nameIndex < #sorted then
            C_Timer.After(0, NameStep)
        else
            Finish()
        end
    end

    local function MergeStep()
        local budget = Everyone.BUDGET
        while budget > 0 and stepIndex <= #steps do
            local step = steps[stepIndex]
            local stop = math.min(#step.list, entryIndex + budget)
            for i = entryIndex + 1, stop do
                Merge(step, step.list[i][1], step.list[i][2])
            end
            budget = budget - (stop - entryIndex)
            entryIndex = stop
            if entryIndex >= #step.list then
                stepIndex, entryIndex = stepIndex + 1, 0
            end
        end
        if stepIndex <= #steps then
            C_Timer.After(0, MergeStep)
        else
            NameStep()
        end
    end

    MergeStep()
end

--- Build the list if it is out of date, then run `done`.
function Everyone:Fresh(done)
    if self.building then
        -- Wait for the build under way: asking for another made every
        -- redraw while it ran (a name arriving, a key typed in the search)
        -- build the whole list a second time. A change it missed is
        -- caught by IsStale once it ends. One such wait at a time: the
        -- latest replaces it, so a burst of redraws is one at the end.
        if done then self.lateWaiter = done end
    elseif self:IsStale() then
        self:Build(done)
    elseif done then
        done()
    end
end

--------------------------------------------------------------------------------
-- Reading the list
--------------------------------------------------------------------------------

--- How long ago a time() was, in a few words: "now", "today", "3 days ago".
function Everyone.Age(at, now)
    if type(at) ~= "number" then return L["never read"] end
    now = now or Now() or at
    local seconds = math.max(0, now - at)
    if seconds < 120 then return L["now"] end
    if seconds < 3600 then return L.Format("%d min ago", math.floor(seconds / 60)) end
    if seconds < 86400 then return L.Format("%d h ago", math.floor(seconds / 3600)) end
    local days = math.floor(seconds / 86400)
    return days == 1 and L["1 day ago"] or L.Format("%d days ago", days)
end

--- Where one character keeps an item: "20 in bags, 40 in the bank".
function Everyone.Where(holder)
    local parts = {}
    for _, place in ipairs(Everyone.PLACES) do
        if holder[place] > 0 then
            parts[#parts + 1] = L.Format("%d %s", holder[place], Everyone.PLACE_WORDS[place])
        end
    end
    return table.concat(parts, ", ")
end

--- When the oldest of the places holding an item was read: the least fresh
--- part of what the line says.
function Everyone.Seen(holder)
    local oldest
    for _, place in ipairs(Everyone.PLACES) do
        if holder[place] > 0 then
            local at = holder.character[place .. "At"]
            if at == nil then return nil end
            if not oldest or at < oldest then oldest = at end
        end
    end
    return oldest
end

--- Who has an item, shortest first: "Mia 20, Ana 40" (most first, three
--- names at most, then how many more).
function Everyone.Summary(item, most)
    most = most or 3
    local parts = {}
    for i, holder in ipairs(item.holders) do
        if i > most then
            parts[#parts + 1] = L.Format("%d more", #item.holders - most)

            break
        end
        parts[#parts + 1] = ("%s %d"):format(holder.character.short, holder.total)
    end
    return table.concat(parts, ", ")
end

--- Does an item match what was typed? Names, and an item number typed
--- whole.
function Everyone.Matches(item, search)
    if not search or search == "" then return true end
    if item.lower and item.lower:find(search, 1, true) then return true end
    return tostring(item.itemID) == search
end

--- The rows to show: each item that matches, and under an open one a row
--- per character holding it. `open` is { [itemID] = true }.
function Everyone:Lines(search, open)
    search = type(search) == "string" and search:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    open = open or {}
    local lines, shown = {}, 0
    for _, item in ipairs(self.sorted) do
        if Everyone.Matches(item, search) then
            shown = shown + 1
            local isOpen = open[item.itemID] == true
            lines[#lines + 1] = { type = "everyone", item = item, open = isOpen }
            if isOpen then
                for _, holder in ipairs(item.holders) do
                    lines[#lines + 1] = { type = "holder", item = item, holder = holder }
                end
            end
        end
    end
    return lines, shown
end

--- How many characters hold anything at all.
function Everyone:Holders()
    local count = 0
    for _, character in ipairs(self.characters) do
        if next(character.bags) or next(character.bank) or next(character.mail) then
            count = count + 1
        end
    end
    return count
end
