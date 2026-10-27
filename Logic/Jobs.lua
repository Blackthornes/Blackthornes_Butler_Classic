-- Blackthornes Butler -- Logic/Jobs.lua
-- Jobs on other characters: a step list across the player's characters
-- for Tradeskills' craft queue (the owner asked 2026-10-11: "if you need
-- to log on another character to do a step ... such as now you need to go
-- craft Medium Leather on another then send back").
--
-- Addons can't pick a character: they don't run on the character list. So
-- Butler does the rest. The window's first group, Jobs, lists what the
-- character playing has to do for the queue (craft this, mail that to
-- whom), each craft with a Craft button, and one line for each other
-- character with work waiting, the next one first. A Log out button on
-- the next one's line takes the player to the character list to switch.
-- Logging in on a character with a job brings the window up on its steps,
-- and once the last one here is done Butler says who is next.
--
-- Tradeskills keeps the queue and works out every step, inside a pcall,
-- read only (its Logic/Butler.lua):
--
--   _G.BlackthornesTS.Butler:Jobs()            -- one entry per character
--   _G.BlackthornesTS.Butler:Craft(recipeID)   -- from Butler's click
--
-- Without Tradeskills there are no jobs and nothing shows.
--
-- What is never done:
--   * Craft, mail or log out for the player: each is their own click.
--     Craft starts the queued craft only when the profession window is
--     open (Tradeskills' Crafting:Start, which needs a real click), and
--     mail is still Fill mail at a mailbox, where the player presses Send.
--   * Log out from addon code: the button is a secure button running the
--     game's own /logout, as a macro would, hidden in combat.
--   * Shorten a name: characters are named first and last, in full.
--
-- Smooth play: the jobs are asked for only while the window draws them,
-- again only when the bags moved (Bags.version, itself read 0.2 s after a
-- burst) or the window opened (Jobs.version). Nothing runs on a timer
-- apart from the one look a few seconds after logging in.

local _, ns = ...
local L = ns.L

local Jobs = ns.NewModule("Jobs")

local Items = ns.Items

-- After logging in, how long before Butler looks for a job here: the
-- other addons read their saves and the bags first.
Jobs.LOGIN_DELAY = 5

-- Moves whenever the jobs should be asked for again.
Jobs.version = 0

local BUTTON_WIDTH = 90
local BUTTON_HEIGHT = 20

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

--- Tradeskills' Butler table when it is loaded and has `method`.
local function Tradeskills(method)
    local global = rawget(_G, "BlackthornesTS")
    if type(global) ~= "table" then return nil end
    local butler = rawget(global, "Butler")
    if type(butler) ~= "table" or type(butler[method]) ~= "function" then return nil end
    return butler
end

--------------------------------------------------------------------------------
-- Reading Tradeskills' answer
--------------------------------------------------------------------------------

local function Text(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function Count(value)
    value = tonumber(value)
    if value and value == value and value > 0 then return math.floor(value) end
    return nil
end

local function ItemList(list)
    local items = {}
    for _, item in ipairs(type(list) == "table" and list or {}) do
        local itemID = type(item) == "table" and Count(item.itemID)
        local count = type(item) == "table" and Count(item.count)
        if itemID and count then
            -- `vendor`: a vendor sells it (Tradeskills gives the copper for
            -- one, or true), so it is bought rather than waited for.
            local vendor = type(item) == "table" and (item.vendor == true or Count(item.vendor) ~= nil)
            items[#items + 1] = { itemID = itemID, count = count, from = Text(item.from),
                bank = Count(item.bank), vendor = vendor or nil }
        end
    end
    return items
end

--- One step, or nil when it is not one Butler can read.
local function CleanStep(step)
    if type(step) ~= "table" then return nil end
    if step.kind == "craft" then
        local recipeID = Count(step.recipeID)
        if not recipeID then return nil end
        local forNames = {}
        for _, name in ipairs(type(step.forNames) == "table" and step.forNames or {}) do
            if Text(name) then forNames[#forNames + 1] = name end
        end
        return {
            kind = "craft",
            recipeID = recipeID,
            itemID = Count(step.itemID),
            name = Text(step.name),
            count = Count(step.count) or Count(step.crafts) or 1,
            forNames = forNames,
            ready = step.ready == true,
            missing = ItemList(step.missing),
        }
    elseif step.kind == "mail" then
        local to = Text(step.to)
        local items = ItemList(step.items)
        if not to or #items == 0 then return nil end
        return { kind = "mail", to = to, items = items, crafts = step.crafts == true,
            forCraft = step.forCraft == true }
    elseif step.kind == "pickup" then
        -- Mail waiting in the character's mailbox (the owner, 2026-10-13:
        -- a mailbox visit for something sent to it goes up the list).
        local items = ItemList(step.items)
        if #items == 0 then return nil end
        return { kind = "pickup", items = items, forCraft = step.forCraft == true }
    elseif step.kind == "cooldown" then
        -- A profession cooldown that is up (a transmute, Mooncloth): Craft
        -- makes it when it has a recipe; an item (the Salt Shaker) is used
        -- by hand.
        local name = Text(step.name)
        if not name then return nil end
        return { kind = "cooldown", name = name, craft = Text(step.craft) or name,
            recipeID = Count(step.recipeID), itemID = Count(step.itemID), ready = true }
    end
    return nil
end

--- Do two names name the same character? Without regard to case or
--- spacing; a mail step to the character doing it is never kept.
function Jobs.SameName(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    local function Fold(text) return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""):lower()) end
    return Fold(a) == Fold(b)
end

--- What a character's crafts still need to get, as up to two steps:
--- "buy" for materials a vendor sells, "gather" for the rest (the auction
--- house or out in the world; the owner, 2026-10-13: "missing materials
--- too that need to be purchased or gathered"). Left out: what another
--- character holds (`from`, a mail step brings it), what a queued craft
--- makes (`made`), and what is already waiting in the mailbox.
function Jobs.GetSteps(steps, made)
    made = made or {}
    local inMail = {}
    for _, step in ipairs(steps) do
        if step.kind == "craft" and step.itemID then made[step.itemID] = made[step.itemID] or true end
        if step.kind == "pickup" then
            for _, item in ipairs(step.items) do inMail[item.itemID] = true end
        end
    end
    local lists = { buy = { items = {}, byID = {} }, gather = { items = {}, byID = {} } }
    for _, step in ipairs(steps) do
        if step.kind == "craft" then
            for _, need in ipairs(step.missing) do
                if not need.from and not made[need.itemID] and not inMail[need.itemID] then
                    local list = need.vendor and lists.buy or lists.gather
                    local item = list.byID[need.itemID]
                    if not item then
                        item = { itemID = need.itemID, count = 0 }
                        list.byID[need.itemID] = item
                        list.items[#list.items + 1] = item
                    end
                    item.count = item.count + need.count
                end
            end
        end
    end
    local found = {}
    for _, kind in ipairs({ "buy", "gather" }) do
        if #lists[kind].items > 0 then found[#found + 1] = { kind = kind, items = lists[kind].items } end
    end
    return found
end

--- A character's steps in the order to do them (the owner, 2026-10-13:
--- "collecting all vendor materials and subcrafts should go to the top"):
--- a mailbox visit first, then buying vendor materials, then buying or
--- gathering the other materials (`made`: item IDs any queued craft
--- makes, on any character's line, which are not got), then the crafts
--- that make parts another craft on the line still needs, in Tradeskills'
--- order but never before a part they are made from, then the rest as
--- Tradeskills gave them.
function Jobs.Order(steps, made)
    -- How many crafts down the line a craft's item goes: 0 for one that
    -- nothing here waits on.
    local wantedBy = {}
    for _, step in ipairs(steps) do
        if step.kind == "craft" then
            for _, need in ipairs(step.missing) do
                wantedBy[need.itemID] = wantedBy[need.itemID] or {}
                table.insert(wantedBy[need.itemID], step)
            end
        end
    end
    local depth, visiting = {}, {}
    local function Depth(step)
        if depth[step] then return depth[step] end
        if visiting[step] or not step.itemID then return 0 end
        visiting[step] = true
        local most = 0
        for _, user in ipairs(wantedBy[step.itemID] or {}) do
            if user ~= step then most = math.max(most, Depth(user) + 1) end
        end
        visiting[step] = nil
        depth[step] = most
        return most
    end

    local pickups, parts, rest = {}, {}, {}
    for index, step in ipairs(steps) do
        if step.kind == "pickup" then
            pickups[#pickups + 1] = step
        elseif step.kind == "craft" and Depth(step) > 0 then
            parts[#parts + 1] = { step = step, depth = depth[step], index = index }
        else
            rest[#rest + 1] = step
        end
    end
    -- In Tradeskills' order, which keeps a profession's parts together
    -- (every bar before the anvil, a player's report 2026-10-19), except
    -- that a part never comes before a part it is made from. Sorting by
    -- depth alone split them: forge, anvil, forge.
    local byItem = {}
    for _, part in ipairs(parts) do
        byItem[part.step.itemID] = byItem[part.step.itemID] or {}
        table.insert(byItem[part.step.itemID], part)
    end
    local inOrder, placed = {}, {}
    local function Free(part)
        for _, need in ipairs(part.step.missing) do
            for _, from in ipairs(byItem[need.itemID] or {}) do
                if from ~= part and not placed[from] then return false end
            end
        end
        return true
    end
    for _ = 1, #parts do
        local pick
        for _, part in ipairs(parts) do
            if not placed[part] and Free(part) and (not pick or part.index < pick.index) then pick = part end
        end
        if not pick then
            -- Parts made from each other: the deepest first, as before.
            for _, part in ipairs(parts) do
                if not placed[part] and (not pick or part.depth > pick.depth
                    or (part.depth == pick.depth and part.index < pick.index)) then
                    pick = part
                end
            end
        end
        placed[pick] = true
        inOrder[#inOrder + 1] = pick
    end
    parts = inOrder

    -- The plain crafts: the ones freeing the most bag slots first (Tradeskills
    -- gives `slots` for the character playing). They swap places among
    -- themselves; other steps stay where they were, and ties keep order.
    local places = {}
    for position, step in ipairs(rest) do
        if step.kind == "craft" and type(step.slots) == "number" then
            places[#places + 1] = { position = position, step = step, index = #places + 1 }
        end
    end
    if #places > 1 then
        local sorted = {}
        for i, place in ipairs(places) do sorted[i] = place end
        table.sort(sorted, function(a, b)
            if a.step.slots ~= b.step.slots then return a.step.slots > b.step.slots end
            return a.index < b.index
        end)
        for i, place in ipairs(places) do rest[place.position] = sorted[i].step end
    end

    local ordered = {}
    for _, step in ipairs(pickups) do ordered[#ordered + 1] = step end
    for _, get in ipairs(Jobs.GetSteps(steps, made)) do ordered[#ordered + 1] = get end
    for _, part in ipairs(parts) do ordered[#ordered + 1] = part.step end
    for _, step in ipairs(rest) do ordered[#ordered + 1] = step end
    return ordered
end

--- What each mail of materials is for (the owner, 2026-10-14: a player
--- thought Wool Cloth a craft here needed was being mailed away, when it
--- went to the alt who makes the Bolt of Woolen Cloth for it): the crafts
--- on the receiver's line still missing an item the mail carries, kept on
--- the step as `forSteps`. Finished crafts sent back say nothing more.
function Jobs.NoteWhy(list)
    for _, job in ipairs(list) do
        for _, step in ipairs(job.steps) do
            if step.kind == "mail" and not step.crafts then
                local carried = {}
                for _, item in ipairs(step.items) do carried[item.itemID] = true end
                local forSteps = {}
                for _, other in ipairs(list) do
                    if other ~= job and Jobs.SameName(other.name, step.to) then
                        for _, craft in ipairs(other.steps) do
                            if craft.kind == "craft" then
                                for _, need in ipairs(craft.missing) do
                                    if carried[need.itemID] then
                                        forSteps[#forSteps + 1] = craft
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                if #forSteps > 0 then step.forSteps = forSteps end
            end
        end
    end
end

--- Tradeskills' list with anything of the wrong shape left out.
function Jobs.Clean(answer)
    local list, made = {}, {}
    for _, job in ipairs(type(answer) == "table" and answer or {}) do
        local name = type(job) == "table" and Text(job.name)
        if name then
            local steps = {}
            for _, step in ipairs(type(job.steps) == "table" and job.steps or {}) do
                local clean = CleanStep(step)
                -- Never a mail to the character doing it.
                if clean and not (clean.kind == "mail" and Jobs.SameName(clean.to, name)) then
                    steps[#steps + 1] = clean
                    if clean.kind == "craft" and clean.itemID then made[clean.itemID] = true end
                end
            end
            if #steps > 0 then
                list[#list + 1] = { name = name, isCurrent = job.isCurrent == true, steps = steps }
            end
        end
    end
    Jobs.NoteWhy(list)
    -- Ordered once every line is read, so a part another character makes
    -- is never sent out to be bought or gathered.
    for _, job in ipairs(list) do job.steps = Jobs.Order(job.steps, made) end
    return list
end

--- Every character's jobs, kept until the bags or Jobs.version move.
function Jobs:Read()
    local key = ("%d:%d"):format(ns.Bags and ns.Bags.version or 0, self.version)
    if self.readKey == key and self.list then return self.list end
    self.readKey = key

    local list = {}
    local ts = Tradeskills("Jobs")
    if ts then
        local ok, answer = pcall(ts.Jobs, ts)
        if ok then list = Jobs.Clean(answer) end
    end
    self.list = list
    self:Noticed()
    return list
end

--- Ask Tradeskills again on the next look (the window opened).
function Jobs:Changed()
    self.version = self.version + 1
end

--------------------------------------------------------------------------------
-- Ignore until next login
--
-- A player asked, the owner said yes (2026-10-18): right-click a
-- character's jobs to put them away, and they come back the next time that
-- character logs in. Kept account wide by full name in jobsIgnored
-- ([name] = time put away; made when first needed, never rename it), so
-- the character logging in, wherever it was put away from, brings its own
-- back. Nothing in the queue changes; only the lines are left out.
--------------------------------------------------------------------------------

local function IgnoredList(make)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.jobsIgnored) ~= "table" then
        if not make then return nil end
        db.jobsIgnored = {}
    end
    return db.jobsIgnored
end

--- Is this character's line put away?
function Jobs:Ignored(name)
    local list = IgnoredList(false)
    if not list or type(name) ~= "string" then return false end
    if list[name] then return true end
    for kept in pairs(list) do
        if Jobs.SameName(kept, name) then return true end
    end
    return false
end

--- Put a character's jobs away until it next logs in.
function Jobs:Ignore(name)
    if type(name) ~= "string" or name == "" then return end
    local list = IgnoredList(true)
    if not list then return end
    list[name] = type(time) == "function" and time() or true
    self:Changed()
    if ns.UI and ns.UI.IsShown and ns.UI:IsShown() then ns.UI:Refresh(true) end
end

--- Is `name` the character playing? Its own name first, so this works
--- before Tradeskills has read the characters.
function Jobs.IsPlaying(name)
    if type(name) ~= "string" then return false end
    local ok, mine = pcall(UnitName, "player")
    if ok and type(mine) == "string" and Jobs.SameName(mine, name) then return true end
    local errands = ns.Errands
    return errands and errands.IsMe and errands:IsMe(name) or false
end

--- Logging in: this character's jobs come back.
function Jobs:Welcome()
    local list = IgnoredList(false)
    if not list then return end
    local moved = false
    for name in pairs(list) do
        if Jobs.IsPlaying(name) then
            list[name] = nil
            moved = true
        end
    end
    if moved then self:Changed() end
end

--- Can the character do any of its steps now? A mail, a vendor run or
--- materials to buy or gather always can; a craft once it has what it takes.
function Jobs.Ready(job)
    for _, step in ipairs(job.steps) do
        if step.kind == "mail" or step.kind == "pickup" or step.kind == "buy" or step.kind == "gather"
            or step.kind == "cooldown"
            or step.ready then return true end
    end
    return false
end

--- The character playing's jobs (`here`), the character to switch to next
--- (`nextJob`: the first other one that can get on with a step, else the
--- first), and every other one with work (`others`, next first).
--- `goFirst` when nothing here can be done yet and the next one can (the
--- owner, 2026-10-11: a sub-craft whose materials are on hand goes to the
--- top), so the window and the gold Log out send the player there first.
function Jobs:Plan()
    local here, others = nil, {}
    local errands = ns.Errands
    for _, job in ipairs(self:Read()) do
        if Jobs:Ignored(job.name) then
            -- Put away until that character logs in again.
        elseif job.isCurrent or (errands and errands.IsMe and errands:IsMe(job.name)) then
            -- The character playing, under any record of it, is never one
            -- to log out for (a player was told to, 2026-10-11).
            here = here or { name = job.name, isCurrent = true, steps = {} }
            for _, step in ipairs(job.steps) do here.steps[#here.steps + 1] = step end
        else
            others[#others + 1] = job
        end
    end
    -- Next: one that can get on with it. First one whose mail or craft
    -- unblocks a craft here, then one with mail waiting for its crafts, then one with
    -- any mail waiting (the owner, 2026-10-13: a mailbox visit for
    -- something sent to it goes up the list).
    -- What the crafts here still wait on, so a character who can make one
    -- of those parts now goes next (the owner, 2026-10-13: subcrafts go
    -- to the top).
    local wantedHere = {}
    for _, step in ipairs(here and here.steps or {}) do
        if step.kind == "craft" then
            for _, need in ipairs(step.missing) do wantedHere[need.itemID] = true end
        end
    end
    local function Rank(job)
        local rank = 0
        for _, step in ipairs(job.steps) do
            if step.kind == "mail" and step.forCraft and here and Jobs.SameName(step.to, here.name) then return 3 end
            if step.kind == "craft" and step.ready and step.itemID and wantedHere[step.itemID] then return 3 end
            if step.kind == "pickup" then rank = math.max(rank, step.forCraft and 2 or 1) end
        end
        return rank
    end
    local nextJob, nextIndex, nextRank
    for index, job in ipairs(others) do
        if Jobs.Ready(job) then
            local rank = Rank(job)
            if not nextJob or rank > nextRank then
                nextJob, nextIndex, nextRank = job, index, rank
            end
        end
    end
    if nextJob then
        table.remove(others, nextIndex)
        table.insert(others, 1, nextJob)
    end
    local goFirst = here ~= nil and nextJob ~= nil and not Jobs.Ready(here)
    return { here = here, nextJob = nextJob or others[1], others = others, goFirst = goFirst }
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- An item's name, asked of the client (and loaded when it doesn't know
--- it yet), else the name Tradeskills gave, else "Item N". In the item's
--- rarity colour once the client knows it (Items:ColorName), only the name,
--- so the line around it keeps its own colour.
function Jobs.ItemName(itemID, fallback)
    if itemID then
        local name = Items.Call({ "C_Item.GetItemNameByID", "GetItemInfo" }, itemID)
        if Text(name) then return Items:ColorName(name, itemID) end
        Items:RequestLoad(itemID)
        if Text(fallback) then return Items:ColorName(fallback, itemID) end
    end
    return fallback or L.Format("Item %s", tostring(itemID))
end

--- True once the client knows the name of every item a step names, so a
--- line said in chat reads "Linen Cloth", not "Item 2589". Asks for the
--- ones it doesn't know yet.
function Jobs.NamesKnown(step)
    local known = true
    local function Check(itemID)
        if not itemID then return end
        local name = Items.Call({ "C_Item.GetItemNameByID", "GetItemInfo" }, itemID)
        if not Text(name) then
            Items:RequestLoad(itemID)
            known = false
        end
    end
    if step then
        if step.kind ~= "cooldown" then Check(step.itemID) end
        for _, item in ipairs(step.items or {}) do Check(item.itemID) end
    end
    return known
end

--- Says a chat line once the step's item names are in, looking again
--- every NAME_WAIT seconds; after NAME_TRIES looks it says it anyway.
Jobs.NAME_WAIT = 0.5
Jobs.NAME_TRIES = 10

function Jobs.SayWhenNamed(step, say, tries)
    tries = tries or 0
    if Jobs.NamesKnown(step) or tries >= Jobs.NAME_TRIES or not (C_Timer and C_Timer.After) then
        say()
        return
    end
    C_Timer.After(Jobs.NAME_WAIT, function() Jobs.SayWhenNamed(step, say, tries + 1) end)
end

local function ItemIcon(itemID)
    if not itemID then return nil end
    local icon = Items.Call({ "C_Item.GetItemIconByID", "GetItemIcon" }, itemID)
    return icon
end

--- "20 Medium Leather", or "Linen Bag" for one.
local function Amount(count, name)
    if count == 1 then return name end
    return ("%d %s"):format(count, name)
end

local function JoinNames(names)
    if #names <= 1 then return names[1] or "" end
    if #names == 2 then return L.Format("%s and %s", names[1], names[2]) end
    return L.Format("%s and %s", table.concat(names, ", ", 1, #names - 1), names[#names])
end

--- "20 Medium Leather", "20 Medium Leather and 3 Light Leather", or the
--- first and how many more.
function Jobs.ItemsText(items)
    local first = items[1]
    if not first then return "" end
    local text = Amount(first.count, Jobs.ItemName(first.itemID))
    if #items == 2 then
        return L.Format("%s and %s", text, Amount(items[2].count, Jobs.ItemName(items[2].itemID)))
    elseif #items > 2 then
        return L.Format("%s and %d more", text, #items - 1)
    end
    return text
end

--- "2 Bolt of Woolen Cloth", two crafts joined, or the first and how many more.
function Jobs.CraftsText(steps)
    local function One(step) return Amount(step.count, Jobs.ItemName(step.itemID, step.name)) end
    if #steps == 2 then return L.Format("%s and %s", One(steps[1]), One(steps[2])) end
    if #steps > 2 then return L.Format("%s and %d more", One(steps[1]), #steps - 1) end
    return One(steps[1])
end

--- A step as a title and a line under it, and for some a hint the
--- tooltip adds.
function Jobs.StepText(step)
    if step.kind == "cooldown" then
        if step.recipeID then
            return L.Format("%s is ready", step.name),
                L.Format("Your %s cooldown is up. Open the profession and click Craft to make %s.", step.name, step.craft)
        end
        return L.Format("%s is ready", step.name),
            L.Format("Your %s cooldown is up. Use it from your bags.", step.name)
    end
    if step.kind == "quest" then
        local what = Jobs.ItemsText(step.items)
        if ns.Quests.CanSearch() then
            return L["For your quests"], L.Format("%s. Search finds them on the auction house.", what)
        end
        return L["For your quests"],
            L.Format("%s. Buy them on the auction house or find them out in the world.", what),
            L["At the auction house, with Blackthornes Tradeskills, this line has a Search button."]
    end
    if step.kind == "pickup" then
        local what = Jobs.ItemsText(step.items)
        if step.forCraft then
            return L["Get your mail"],
                L.Format("%s for your crafts is in your mailbox. Take it out before you craft.", what)
        end
        return L["Get your mail"], L.Format("%s was sent to you and is waiting in your mailbox.", what)
    end
    if step.kind == "buy" then
        return L["Buy from a vendor"],
            L.Format("Buy %s at the Tradeskills Vendor.", Jobs.ItemsText(step.items))
    end
    if step.kind == "gather" then
        return L["Buy or gather"],
            L.Format("Buy %s at the auction house, or gather it.", Jobs.ItemsText(step.items))
    end
    if step.kind == "mail" then
        local what = Jobs.ItemsText(step.items)
        -- What is in the bank has to come out before Fill mail can see it.
        local banked = {}
        for _, item in ipairs(step.items) do
            if item.bank then banked[#banked + 1] = { itemID = item.itemID, count = math.min(item.bank, item.count) } end
        end
        -- Why it goes: the crafts the receiver makes with it. How Fill mail
        -- works then moves to the tooltip, so the row keeps to two lines.
        if step.forSteps then
            local made = Jobs.CraftsText(step.forSteps)
            local why = L.Format("%s, so %s can make %s.", what, step.to, made)
            if #banked > 0 then
                why = L.Format("%s, so %s can make %s. Take %s out of the bank first.",
                    what, step.to, made, Jobs.ItemsText(banked))
            end
            return L.Format("Mail to %s", step.to), why, L["At a mailbox, Fill mail adds it."]
        end
        if #banked > 0 then
            return L.Format("Mail to %s", step.to),
                L.Format("%s. Take %s out of the bank first, then at a mailbox Fill mail adds it.",
                    what, Jobs.ItemsText(banked))
        end
        return L.Format("Mail to %s", step.to),
            L.Format("%s. At a mailbox, Fill mail adds it.", what)
    end
    local title = L.Format("Craft %s", Amount(step.count, Jobs.ItemName(step.itemID, step.name)))
    local detail
    if not step.ready and step.missing[1] then
        detail = L.Format("Still needs %s first.", Jobs.ItemsText(step.missing))
        local from = step.missing[1].from
        if from then detail = L.Format("%s %s has it.", detail, from) end
    elseif #step.forNames > 0 then
        detail = L.Format("For %s. Mail it over once it's made.", JoinNames(step.forNames))
    else
        detail = L["For your own queue."]
    end
    return title, detail
end

--- A step in one line, for the line about another character.
function Jobs.Short(step)
    if step.kind == "quest" then
        return L.Format("get %s for your quests", Jobs.ItemsText(step.items))
    end
    if step.kind == "cooldown" then
        return L.Format("use the %s cooldown, it's ready", step.name)
    end
    if step.kind == "pickup" then
        return L.Format("get %s from the mailbox", Jobs.ItemsText(step.items))
    end
    if step.kind == "buy" then
        return L.Format("buy %s from a vendor", Jobs.ItemsText(step.items))
    end
    if step.kind == "gather" then
        return L.Format("buy or gather %s", Jobs.ItemsText(step.items))
    end
    if step.kind == "mail" then
        return L.Format("mail %s to %s", Jobs.ItemsText(step.items), step.to)
    end
    local text = L.Format("craft %s", Amount(step.count, Jobs.ItemName(step.itemID, step.name)))
    if #step.forNames > 0 then
        text = L.Format("%s, then mail it to %s", text, JoinNames(step.forNames))
    end
    return text
end

--- What another character has to do: its first step and how many more.
function Jobs.Summary(job)
    local first = job.steps[1]
    local text = Jobs.Short(first)
    text = text:sub(1, 1):upper() .. text:sub(2)
    if #job.steps > 1 then
        text = #job.steps == 2 and L.Format("%s, and %d more step", text, #job.steps - 1)
            or L.Format("%s, and %d more steps", text, #job.steps - 1)
    end
    if not Jobs.Ready(job) then return L.Format("%s. Waiting on materials.", text) end
    return text .. "."
end

function Jobs.Icon(step)
    if step.kind == "mail" or step.kind == "pickup" then return [[Interface\Icons\INV_Letter_15]] end
    if step.kind == "buy" or step.kind == "gather" or step.kind == "quest" then
        return ItemIcon(step.items[1] and step.items[1].itemID) or [[Interface\Icons\INV_Misc_Coin_01]]
    end
    if step.kind == "cooldown" then
        return ItemIcon(step.itemID) or [[Interface\Icons\INV_Misc_PocketWatch_01]]
    end
    return ItemIcon(step.itemID) or [[Interface\Icons\Trade_LeatherWorking]]
end

--------------------------------------------------------------------------------
-- The window's rows
--------------------------------------------------------------------------------

--- The Jobs group's rows: this character's steps, then a line for each
--- other character with work, the next one first. Empty with no jobs.
function Jobs:Lines()
    local plan = self:Plan()
    -- Only spells to train now lead; the rest waits under Later.
    local rows = {}
    for _, row in ipairs(self:TrainingLines()) do
        if row.type == "train" then rows[#rows + 1] = row end
    end
    -- What the open quests still want that can be bought (Logic/Quests.lua).
    local quest = ns.Quests and ns.Quests:Step()
    if quest then
        rows[#rows + 1] = { type = "job", step = quest }
        -- At the auction house, a row an item with its own Buy (Logic/QuestBuy.lua).
        if ns.QuestBuy then
            for _, row in ipairs(ns.QuestBuy:Rows(quest)) do rows[#rows + 1] = row end
        end
    end
    -- At a vendor with something for the queue, a Buy row even when no
    -- step here names a vendor material, since Tradeskills' own button
    -- over the vendor window stands down while Butler is loaded.
    local buy = self:VendorStep(plan.here)
    if buy then rows[#rows + 1] = { type = "job", step = buy } end
    -- Nothing here can be done yet: the one who can goes first.
    if plan.goFirst then
        rows[#rows + 1] = { type = "jobnext", job = plan.nextJob, isNext = true, isFirst = true }
    end
    for _, step in ipairs(plan.here and plan.here.steps or {}) do
        rows[#rows + 1] = { type = "job", step = step, job = plan.here }
    end
    for index, job in ipairs(plan.others) do
        if not (plan.goFirst and index == 1) then
            rows[#rows + 1] = { type = "jobnext", job = job, isNext = index == 1 }
        end
    end
    return rows
end

--- The Later group's rows, at the foot of the list by Gold goals (the
--- owner, 2026-10-13: what can be done now goes at the top): spells at
--- the next level and other characters' spells to train.
function Jobs:LaterLines()
    local rows = {}
    for _, row in ipairs(self:TrainingLines()) do
        if row.type ~= "train" then rows[#rows + 1] = row end
    end
    return rows
end

--- Class spells to train lead the group (Logic/ClassTraining.lua): what
--- can be trained now, what comes at the next level, and a line for each
--- other character with spells waiting.
function Jobs:TrainingLines()
    local training = ns.ClassTraining
    local rows = {}
    if not (training and training:IsOn()) then return rows end
    local plan = training:Plan()
    if #plan.ready > 0 then
        rows[#rows + 1] = { type = "train", plan = plan }
    end
    if #plan.next > 0 then
        rows[#rows + 1] = { type = "trainnext", plan = plan }
    end
    for _, other in ipairs(training:Others()) do
        if not (ns.Errands and ns.Errands.IsMe and ns.Errands:IsMe(other.name)) then
            rows[#rows + 1] = { type = "trainalt", other = other }
        end
    end
    return rows
end

--------------------------------------------------------------------------------
-- Craft
--------------------------------------------------------------------------------

--- A Craft click on a step: Tradeskills starts it with the profession
--- open, else opens its Queue tab, where the Open button opens it.
function Jobs:Craft(step)
    if not (step and (step.kind == "craft" or (step.kind == "cooldown" and step.recipeID))) then return false end
    if InCombat() then
        ns.Print(L["crafting waits until the fight is over."])
        return false
    end
    local ts = Tradeskills("Craft")
    if not ts then
        ns.Print(L["crafting from here needs Blackthornes Tradeskills."])
        return false
    end
    local name = step.kind == "cooldown" and step.craft or Jobs.ItemName(step.itemID, step.name)
    if Jobs.InBlockingForm() then
        ns.Print(L.Format("leave your form first, then click Craft for %s again.", name))
        return false
    end
    local ok, done, why = pcall(ts.Craft, ts, step.recipeID)
    if not ok then
        ns.Print(L.Format("couldn't start %s.", name))
        return false
    end
    if done and why == "opened" then
        ns.Print(L.Format("open your profession for %s: Tradeskills' Open button is on its Queue tab. Then click Craft again.", name))
    elseif not done then
        ns.Print(L.Format("can't craft %s yet: %s.", name, tostring(why or L["the game said no"])))
    end
    return done == true
end

--------------------------------------------------------------------------------
-- Buying materials at a vendor
--------------------------------------------------------------------------------

-- The owner asked (2026-10-14) for Tradeskills' Buy materials button, the
-- one over the vendor window, on the Buy from a vendor row too. Tradeskills
-- works out what this vendor has for the queue and buys it, inside a pcall:
--
--   _G.BlackthornesTS.Butler:VendorOffer()     -- { count, cost, items, cheaperElsewhere, buying }
--   _G.BlackthornesTS.Butler:BuyFromVendor()   -- true, or false and why
--
-- Read only while a vendor is open, each time the window is drawn
-- (UI:Refresh), so the row redraws only when the offer moves (vendorKey).

-- How often the row looks again while a run is buying, and for how long.
Jobs.BUY_LOOK = 0.5
Jobs.BUY_LOOKS = 60

Jobs.vendorKey = ""

local function Money(value)
    value = tonumber(value)
    if value and value == value and value >= 0 then return math.floor(value) end
    return 0
end

--- What the open vendor sells for the queue, kept as `Jobs.offer`; nil
--- away from a vendor, without Tradeskills or before it has read the
--- vendor's list.
function Jobs:VendorOffer()
    local offer
    local ts = ns.Selling and ns.Selling.merchantOpen and Tradeskills("VendorOffer")
    if ts then
        local ok, answer = pcall(ts.VendorOffer, ts)
        if ok and type(answer) == "table" then
            local items = {}
            for _, item in ipairs(type(answer.items) == "table" and answer.items or {}) do
                local itemID = type(item) == "table" and Count(item.itemID)
                local amount = type(item) == "table" and Count(item.amount)
                if itemID and amount then
                    items[#items + 1] = { itemID = itemID, count = amount, cost = Money(item.cost),
                        short = item.short == true or nil }
                end
            end
            offer = { count = #items, cost = Money(answer.cost), items = items,
                cheaperElsewhere = Count(answer.cheaperElsewhere) or 0, buying = answer.buying == true }
        end
    end
    self.offer = offer
    self.vendorKey = offer and ("%d:%d:%d:%s"):format(offer.count, offer.cost, offer.cheaperElsewhere,
        tostring(offer.buying)) or ""
    return offer
end

--- A Buy from a vendor step made from the open vendor's offer, for when
--- no step here has one (the owner, 2026-10-18: Tradeskills' Buy materials
--- button over the vendor window hides while Butler is loaded, so Butler
--- has to offer everything it would have bought). nil away from a vendor,
--- with nothing to buy, or when a step here already buys.
function Jobs:VendorStep(here)
    local offer = self.offer
    if not (offer and (offer.buying or offer.count > 0)) then
        self.vendorItems = nil
        return nil
    end
    for _, step in ipairs(here and here.steps or {}) do
        if step.kind == "buy" then return nil end
    end
    if offer.count > 0 then
        local items = {}
        for _, item in ipairs(offer.items) do
            items[#items + 1] = { itemID = item.itemID, count = item.count }
        end
        self.vendorItems = items
    end
    -- While it buys the offer is empty, so the row keeps what it was buying.
    if not (self.vendorItems and self.vendorItems[1]) then return nil end
    return { kind = "buy", items = self.vendorItems, atVendor = true }
end

--- Does this step get the Buy button? A Buy from a vendor step, at a
--- vendor that has something for the queue, or while it is buying.
function Jobs.Buyable(step)
    local offer = Jobs.offer
    return step ~= nil and step.kind == "buy" and offer ~= nil and (offer.buying or offer.count > 0)
end

--- Does this step get the Search button? The quest line, at the auction
--- house, with Tradeskills loaded.
function Jobs.Searchable(step)
    return step ~= nil and step.kind == "quest" and ns.Quests ~= nil and ns.Quests.CanSearch()
end

--- The Search button's words: "Search", or "Next 2/5" while the game
--- takes one item a search.
function Jobs.SearchLabel(step)
    local pos, total = ns.Quests:SearchPlace(step.items)
    if pos then return L.Format("Next %d/%d", pos, total) end
    return L["Search"]
end

--- The Search button's tooltip: each item, how many, and for which quest.
function Jobs.SearchTooltip(step)
    local lines = { L["Finds these on the auction house for your quests:"] }
    for index = 1, math.min(#step.items, 10) do
        local item = step.items[index]
        lines[#lines + 1] = L.Format("  %s for %s", Amount(item.count, Jobs.ItemName(item.itemID)),
            table.concat(item.quests or {}, ", "))
    end
    if #step.items > 10 then lines[#lines + 1] = "  " .. L.Format("and %d more", #step.items - 10) end
    return table.concat(lines, "\n")
end

--- The Buy from a vendor line at a vendor: what this one has for the
--- queue, or why it has nothing. nil away from a vendor.
function Jobs.VendorText(step)
    local offer = Jobs.offer
    if not (step and step.kind == "buy" and offer) then return nil end
    if offer.buying then return L["Buying..."] end
    if offer.count > 0 then
        return L.Format("Buy %s here for %s.",
            Jobs.ItemsText(offer.items), Items.FormatMoney(offer.cost))
    end
    if offer.cheaperElsewhere > 0 then
        return L.Format("Buy %s at the auction house. It's cheaper there.", Jobs.ItemsText(step.items))
    end
    return L.Format("This vendor doesn't sell %s.", Jobs.ItemsText(step.items))
end

--- The Buy button's tooltip: each material and its cost.
function Jobs.BuyTooltip()
    local offer = Jobs.offer
    if not offer then return nil end
    if offer.buying then return L["Buying..."] end
    local lines = { L.Format("Buy for your crafts, %s:", Items.FormatMoney(offer.cost)) }
    for index = 1, math.min(#offer.items, 10) do
        local item = offer.items[index]
        local line = ("  %s  %s"):format(Amount(item.count, Jobs.ItemName(item.itemID)), Items.FormatMoney(item.cost))
        if item.short then line = line .. "  " .. L["(limited stock)"] end
        lines[#lines + 1] = line
    end
    if #offer.items > 10 then lines[#lines + 1] = "  " .. L.Format("and %d more", #offer.items - 10) end
    return table.concat(lines, "\n")
end

--- The Buy click: Tradeskills' Buy materials run, one stack at a time, each
--- checked again first. The row looks again every BUY_LOOK seconds until
--- the run is over, so it says Buying... and then what is left.
function Jobs:BuyAtVendor()
    if InCombat() then
        ns.Print(L["buying waits until the fight is over."])
        return false
    end
    local ts = Tradeskills("BuyFromVendor")
    if not ts then
        ns.Print(L["buying from here needs Blackthornes Tradeskills."])
        return false
    end
    local ok, started, why = pcall(ts.BuyFromVendor, ts)
    if not ok then
        ns.Print(L["couldn't buy from this vendor."])
        return false
    end
    -- Tradeskills says in chat why when it buys nothing; a reason it hands
    -- back instead is said here.
    if not started and type(why) == "string" and why ~= "" then ns.Print(why) end
    self:WatchBuying()
    return started == true
end

--- Redraw the window until Tradeskills' run is over. One look at a time.
function Jobs:WatchBuying()
    if not (C_Timer and C_Timer.After) then return end
    self.buyRun = (self.buyRun or 0) + 1
    local run, looks = self.buyRun, 0
    local function Look()
        if Jobs.buyRun ~= run then return end
        looks = looks + 1
        local ui = ns.UI
        if not (ui and ui.IsShown and ui:IsShown()) then return end
        ui:Refresh()
        if looks < Jobs.BUY_LOOKS and Jobs.offer and Jobs.offer.buying then
            C_Timer.After(Jobs.BUY_LOOK, Look)
        end
    end
    C_Timer.After(Jobs.BUY_LOOK, Look)
end

--------------------------------------------------------------------------------
-- Log out
--------------------------------------------------------------------------------

--- The Log out button: the game's own /logout, run by the player's click
--- on a secure button as a macro would (addon code may not log out by
--- itself). It sits on the row of the character to switch to, where a
--- craft's Craft button sits (the owner asked 2026-10-11: "the log out
--- button should be next to the step that needs the logout").
function Jobs:CreateLogout()
    if self.button then return self.button end
    local button = ns.Widgets.CreateButton(UIParent, L["Log out"], nil, {
        name = "BlackthornesButlerLogout", template = "SecureActionButtonTemplate",
        width = BUTTON_WIDTH, height = BUTTON_HEIGHT, primary = true,
    })
    button:Hide()
    -- Inside the window out of combat (UI:Dock), so it comes to the front
    -- with it and a window in front covers it too.
    button:SetFrameStrata("DIALOG")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "/logout")
    button:HookScript("OnEnter", function(frame)
        if frame.tooltipText then
            GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
            GameTooltip:SetText(frame.tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.button = button
    return button
end

local function Tip(nextJob)
    return L.Format("Log out for %s. %s\nThen pick %s on the character list.",
        nextJob.name, Jobs.Summary(nextJob), nextJob.name)
end

--- Everything here is done, or can't be until the next character has done
--- its part: the footer says so.
function Jobs:DoneHere()
    local plan = self:Plan()
    -- Items to get for the quests are something to do here too.
    if ns.Quests and ns.Quests:Step() then return false end
    return plan.nextJob ~= nil and (plan.here == nil or plan.goFirst == true)
end

--- The list row showing the next character ("First:" or "Next:"), when it
--- is on screen.
function Jobs.NextRow(list)
    for _, row in ipairs((list and list.rows) or {}) do
        local data = row.data
        if row:IsShown() and data and data.type == "jobnext" and data.isNext then return row end
    end
end

--- Put the Log out button on the next character's row, while it is on
--- screen. Inside the window out of combat, as the Sell button is
--- (UI:Dock), and handed back to UIParent as a fight starts, so the window
--- stays free to move and close in combat; hidden in combat, while the
--- window moves and in All characters. Called each time the list is drawn
--- or scrolled, so it follows its row.
function Jobs:UpdateLogout()
    if self.fighting or InCombat() then return end
    local ui = ns.UI
    local list = ui and ui.list
    local show = list and ui:IsShown() and not ui.dragging and ui.view ~= "all"
    local row = show and Jobs.NextRow(list)
    local right, top, bottom = row and row:GetRight(), row and row:GetTop(), row and row:GetBottom()
    if not (right and top and bottom) then
        if self.button then self.button:Hide() end
        return
    end
    local button = self:CreateLogout()
    button.tooltipText = Tip(row.data.job)
    if not ui:Dock(button) then
        button:Hide()
        return
    end
    button:ClearAllPoints()
    button:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    button:Show()
end

--------------------------------------------------------------------------------
-- Leaving a form first
--------------------------------------------------------------------------------

-- A craft will not start in travel form, cat form and the like, as
-- Tradeskills' craft buttons know (its UI/ProfessionOpener.lua). Leaving one
-- is protected, so it takes the player's own click on a secure button set to
-- /cancelform: the first click leaves the form, the next crafts. Never both
-- in one click. Only a druid's forms and a shaman's Ghost Wolf count: a
-- warrior's stance is a "form" to the client too, and crafting works in it.
local FORM_CLASSES = { DRUID = true, SHAMAN = true }

--- Is the character in a form that stops a craft?
function Jobs.InBlockingForm()
    local ok, inForm = pcall(function()
        if type(UnitClass) ~= "function" or type(GetShapeshiftForm) ~= "function" then return false end
        local _, class = UnitClass("player")
        if not FORM_CLASSES[class] then return false end
        local form = GetShapeshiftForm()
        return type(form) == "number" and form > 0
    end)
    return ok and inForm == true
end

--- A step with a Craft button.
function Jobs.Craftable(step)
    return step ~= nil and ((step.kind == "craft" and step.ready == true)
        or (step.kind == "cooldown" and step.recipeID ~= nil))
end

--- The Leave form button: a secure button, as Log out is, laid over the
--- Craft button of the first craft line on screen.
function Jobs:CreateLeaveForm()
    if self.formButton then return self.formButton end
    local button = ns.Widgets.CreateButton(UIParent, L["Leave form"], nil, {
        name = "BlackthornesButlerLeaveForm", template = "SecureActionButtonTemplate",
        width = 80, height = 22, primary = true,
    })
    button:Hide()
    -- Inside the window out of combat (UI:Dock), so it comes to the front
    -- with it and a window in front covers it too.
    button:SetFrameStrata("DIALOG")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "/cancelform")
    button.tooltipText = L["You can't craft in this form. Click to leave it, then click Craft."]
    button:HookScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
        GameTooltip:SetText(frame.tooltipText, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.formButton = button
    return button
end

--- The first craft line on screen.
function Jobs.CraftRow(list)
    for _, row in ipairs((list and list.rows) or {}) do
        local data = row.data
        if row:IsShown() and data and data.type == "job" and Jobs.Craftable(data.step) then return row end
    end
end

--- Put Leave form over the first craft line's button while in a form that
--- stops a craft. Hidden in combat, while the window moves and in All
--- characters, as Log out is; called each time the list is drawn or
--- scrolled.
function Jobs:UpdateLeaveForm()
    if self.fighting or InCombat() then return end
    local ui = ns.UI
    local list = ui and ui.list
    local show = list and ui:IsShown() and not ui.dragging and ui.view ~= "all" and Jobs.InBlockingForm()
    local row = show and Jobs.CraftRow(list)
    local right, top, bottom = row and row:GetRight(), row and row:GetTop(), row and row:GetBottom()
    if not (right and top and bottom) then
        if self.formButton then self.formButton:Hide() end
        return
    end
    local button = self:CreateLeaveForm()
    if not ui:Dock(button) then
        button:Hide()
        return
    end
    button:ClearAllPoints()
    button:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    button:Show()
end

--------------------------------------------------------------------------------
-- Opening the profession
--------------------------------------------------------------------------------

-- The owner asked (2026-10-15) for Craft to open the profession window when
-- it is closed, as Tradeskills' own craft button does, and to craft once it
-- is open. Opening one is a cast, which only the player's click on a secure
-- button may do, so the Open button is a secure button set to the spell
-- Tradeskills names (its Butler:Profession), laid over the Craft button of
-- the first craft line whose window is not open. Its click opens the
-- window; the line's Craft then crafts. Never both in one click.

--- The profession a craft step is made in: { name, spell, open }, or nil.
function Jobs.Profession(step)
    if not (step and step.recipeID) then return nil end
    local ts = Tradeskills("Profession")
    if not ts then return nil end
    local ok, info = pcall(ts.Profession, ts, step.recipeID)
    if not ok or type(info) ~= "table" or not Text(info.spell) then return nil end
    return { name = Text(info.name) or info.spell, spell = info.spell, open = info.open == true }
end

--- The first craft line on screen whose profession window is not open, and
--- that profession.
function Jobs.OpenRow(list)
    for _, row in ipairs((list and list.rows) or {}) do
        local data = row.data
        if row:IsShown() and data and data.type == "job" and Jobs.Craftable(data.step) then
            local profession = Jobs.Profession(data.step)
            if profession and not profession.open then return row, profession end
        end
    end
end

function Jobs:CreateOpenButton()
    if self.openButton then return self.openButton end
    local button = ns.Widgets.CreateButton(UIParent, L["Craft"], nil, {
        name = "BlackthornesButlerOpenProfession", template = "SecureActionButtonTemplate",
        width = 80, height = 22, primary = true,
    })
    button:Hide()
    -- Inside the window out of combat (UI:Dock), as Leave form is.
    button:SetFrameStrata("DIALOG")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", "spell")
    button:HookScript("OnEnter", function(frame)
        if not frame.tooltipText then return end
        GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
        GameTooltip:SetText(frame.tooltipText, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.openButton = button
    return button
end

--- Put Open over the first craft line whose window is closed. Leave form
--- wins while in a form. Hidden in combat, while the window moves and in
--- All characters; called each time the list is drawn or scrolled.
function Jobs:UpdateOpenProfession()
    if self.fighting or InCombat() then return end
    local ui = ns.UI
    local list = ui and ui.list
    local show = list and ui:IsShown() and not ui.dragging and ui.view ~= "all" and not Jobs.InBlockingForm()
    local row, profession
    if show then row, profession = Jobs.OpenRow(list) end
    local right, top, bottom = row and row:GetRight(), row and row:GetTop(), row and row:GetBottom()
    if not (right and top and bottom) then
        if self.openButton then self.openButton:Hide() end
        return
    end
    local button = self:CreateOpenButton()
    if not ui:Dock(button) then
        button:Hide()
        return
    end
    if button:GetAttribute("spell") ~= profession.spell then
        button:SetAttribute("spell", profession.spell)
    end
    button:SetText(L.Format("Open %s", profession.name))
    button.tooltipText = L.Format("Opens %s. Then click Craft.", profession.name)
    button:ClearAllPoints()
    button:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    button:Show()
end

--- The profession window opened or closed: a moment later, once
--- Tradeskills has read it, the lines say Open or Craft again.
function Jobs:WindowChanged()
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(0.3, function()
        if ns.UI and ns.UI.IsShown and ns.UI:IsShown() then ns.UI:Refresh(true) end
    end)
end

--------------------------------------------------------------------------------
-- Speaking up
--------------------------------------------------------------------------------

--- After a read: once the last step here is done and another character
--- has work, say who is next (once each time it happens).
function Jobs:Noticed()
    local plan = self:Plan()
    local hasHere = plan.here ~= nil
    if self.hadHere and not hasHere and plan.nextJob then
        local job = plan.nextJob
        Jobs.SayWhenNamed(job.steps[1], function()
            ns.Print(L.Format("that's everything here. Next: %s. %s Log out on their line in the Butler window to switch.",
                job.name, Jobs.Summary(job)))
        end)
    end
    self.hadHere = hasHere
end

--- A few seconds after logging in: a character with a job brings the
--- window up on its steps ("Jobs at login", on unless unticked).
function Jobs:Greet()
    if InCombat() or not (ns.db and ns.db.jobsAtLogin ~= false) then return end
    self:Changed()
    local plan = self:Plan()
    local first = plan.here and plan.here.steps[1]
    if not first then return end
    if ns.UI and not ns.UI:IsShown() then ns.UI:Show("bags") end
    Jobs.SayWhenNamed(first, function()
        ns.Print(L.Format("a job on this character: %s.", Jobs.Short(first)))
    end)
end

--- Every character's jobs in chat.
function Jobs:Report()
    local list = self:Read()
    if not Tradeskills("Jobs") then
        ns.Print(L["jobs come from Blackthornes Tradeskills' craft queue, and it isn't loaded."])
        return
    end
    if #list == 0 then
        ns.Print(L["no jobs right now. Nothing in the craft queue needs one of your characters."])
        return
    end
    for _, job in ipairs(list) do
        ns.Print(job.isCurrent and L.Format("%s (you):", job.name) or (job.name .. ":"))
        for _, step in ipairs(job.steps) do
            ns.PrintRaw("   " .. Jobs.Short(step))
        end
    end
end

function Jobs:ProbeText()
    local secure
    if type(issecurevariable) == "function" then
        local ok, isSecure = pcall(issecurevariable, "Logout")
        secure = ok and isSecure
    end
    return ("Tradeskills jobs %s, Logout %s%s, /logout %s"):format(
        Tradeskills("Jobs") and "yes" or "no",
        type(rawget(_G, "Logout")) == "function" and "found" or "missing",
        secure and " (secure)" or "",
        rawget(_G, "SLASH_LOGOUT1") and "found" or "not found")
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

--- At a class trainer with spells to train, the window comes up on them
--- (Train all is on their row) and goes when the trainer closes.
function Jobs:AtTrainer(open)
    local ui, training = ns.UI, ns.ClassTraining
    if not ui then return end
    if not open then
        if ui.openedFor == "trainer" then return ui:LeftPlace("trainer") end
        if ui:IsShown() then ui:Refresh(true) end
        return
    end
    if ui:IsShown() then return ui:Refresh(true) end
    if not (training:IsOn() and training.atClassTrainer and #training:Plan().ready > 0) then return end
    ui:Show("bags")
    ui.openedFor = "trainer"
end

function Jobs:OnEnable()
    local training = ns.ClassTraining
    if training then
        training.OnChanged = function()
            if ns.UI and ns.UI.IsShown and ns.UI:IsShown() then ns.UI:Refresh() end
        end
        training.OnTrainer = function(open) Jobs:AtTrainer(open) end
    end
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function(_, _, isInitialLogin)
        if isInitialLogin then Jobs:Welcome() end
        if isInitialLogin and C_Timer and C_Timer.After then
            C_Timer.After(Jobs.LOGIN_DELAY, function()
                -- Again once Tradeskills has read every name of this character.
                Jobs:Welcome()
                Jobs:Greet()
            end)
        end
    end)
    -- Just before combat locks secure frames: the button can still hide.
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        Jobs.fighting = true
        if Jobs.button then Jobs.button:Hide() end
        if Jobs.formButton then Jobs.formButton:Hide() end
        if Jobs.openButton then Jobs.openButton:Hide() end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        Jobs.fighting = false
        if ns.UI and ns.UI.frame then ns.UI:FootRoom() end
    end)
    -- Tradeskills reads the vendor's list a moment after it opens; the Buy
    -- from a vendor row looks once more after that.
    ns.RegisterEvent(self, "MERCHANT_SHOW", function()
        if not (C_Timer and C_Timer.After) then return end
        C_Timer.After(0.5, function()
            if ns.UI and ns.UI.IsShown and ns.UI:IsShown() then ns.UI:Refresh() end
        end)
    end)
    ns.RegisterEvent(self, "TRADE_SKILL_SHOW", function() Jobs:WindowChanged() end)
    ns.RegisterEvent(self, "TRADE_SKILL_CLOSE", function() Jobs:WindowChanged() end)
    -- Era opens Enchanting in the craft window, which has its own events.
    ns.RegisterEvent(self, "CRAFT_SHOW", function() Jobs:WindowChanged() end)
    ns.RegisterEvent(self, "CRAFT_CLOSE", function() Jobs:WindowChanged() end)
    -- Into or out of a form: the craft lines say Leave form or Craft. Only
    -- on the change itself, and only while the window shows.
    ns.RegisterEvent(self, "UPDATE_SHAPESHIFT_FORM", function()
        local inForm = Jobs.InBlockingForm()
        if inForm == Jobs.lastInForm then return end
        Jobs.lastInForm = inForm
        -- Forced: the form is not in the window's redraw key, so a plain
        -- Refresh drew nothing and left the Leave form button where it was.
        if ns.UI and ns.UI.IsShown and ns.UI:IsShown() then ns.UI:Refresh(true) end
    end)
end

ns.RegisterCommand("jobs", L["list every character's jobs for the craft queue"], function()
    Jobs:Report()
end)

ns.RegisterCommand("joblogin", L["turn bringing the window up for a job at login on or off"], function()
    ns.db.jobsAtLogin = ns.db.jobsAtLogin == false
    ns.Print(ns.db.jobsAtLogin and L["logging in on a character with a job brings the Butler window up."]
        or L["Butler no longer comes up at login for a job."])
end)
