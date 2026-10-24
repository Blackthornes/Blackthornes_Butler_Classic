-- Logic/ClassTraining.lua
-- Class spells to train: which the character can learn now, what they cost
-- and where the trainer is (the owner said build it 2026-10-13, for Butler
-- and Equipment). The same file is in both addons, as is
-- Data/ClassSpells.lua and tools/make_class_spells.py; a fix to one belongs
-- in both. Neither addon calls the other for it.
--
-- What is known exactly, from Data/ClassSpells.lua (the Forever client's
-- game tables): every class spell, the level it is learned at and its
-- rank. Which ones the character knows is asked of the client
-- (IsPlayerSpell). What is learned only at a trainer: what each spell
-- costs, which spells a trainer teaches (a quest teaches some), and where
-- the trainer stands. The first look at a class trainer's window keeps
-- all three, account wide, so every character of that class gets them:
--
--   classTrainingData = {
--       prices = { [spell ID] = copper },
--       notTaught = { [spell ID] = true },        -- no trainer lists it
--       trainers = { [CLASS] = { [NPC ID] = { name, zone, sub, mapID, x, y, faction, at } } },
--       characters = { [GUID] = { name, class, level, realm, faction, ready = { spell IDs }, at } },
--       learned = { [GUID] = { [spell ID] = true } },  -- the trainer says known
--       skipped = { [GUID] = { [spell ID] = time } },  -- the player skipped it
--   }
--
-- Never rename it, nor the `classTraining` setting (on unless unticked).
--
-- Skipped spells (a player asked, the owner said yes, 2026-10-22): a
-- right-click on a spell in Equipment's Training drawer skips it for that
-- character, so it leaves the lists, the costs, Train all and Butler's gold
-- goal, until the player brings it back. Each addon keeps its own copy
-- (`skipped[guid][id]`, the time it was skipped, or minus the time it was
-- brought back) and tells the other's copy, read through its global inside
-- a pcall; the newest wins, so a change made while the other was not
-- loaded still counts.
--
-- What is never done: buy a spell without the player's click (Train all
-- is their click, one spell at a time, each checked again first), or touch
-- the game's trainer window. The trainer's own filter is turned to show the
-- spells not learnable yet just long enough to read their prices, then put
-- back as it was.
--
-- Smooth play: the list is worked out only when asked (a window drawing
-- it), again only when ClassTraining.version moves (a spell learned, a
-- level, a trainer read) and kept until then. Trainer events come in
-- bursts: one read 0.2 s after.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local CT = ns.NewModule("ClassTraining")

-- Moves whenever the list should be worked out again.
CT.version = 0
-- Between one spell bought and the next.
CT.GAP = 0.3
-- How long after a level the client has the new spells listed.
CT.LEVEL_DELAY = 2

local function Call(name, ...)
    local fn = _G
    for part in name:gmatch("[^%.]+") do
        if type(fn) ~= "table" then return nil end
        fn = rawget(fn, part)
    end
    if type(fn) ~= "function" then return nil end
    local function Pass(ok, ...)
        if not ok then return nil end
        return ...
    end
    return Pass(pcall(fn, ...))
end

local function Has(name)
    local fn = _G
    for part in name:gmatch("[^%.]+") do
        if type(fn) ~= "table" then return false end
        fn = rawget(fn, part)
    end
    return type(fn) == "function"
end

local function Text(value)
    if type(value) ~= "string" then return nil end
    local ok, empty = pcall(function() return value == "" end)
    if not ok or empty then return nil end
    return value
end

local function Number(value)
    local ok, read = pcall(function() return tonumber(value) end)
    return ok and read or nil
end

local function Now()
    return type(time) == "function" and time() or 0
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

--------------------------------------------------------------------------------
-- Saved data
--------------------------------------------------------------------------------

-- Forever's own spells sit at 1,000,000 and up; Era has none of them.
CT.FOREVER_FIRST = 1000000

--- The class's spells from Data/ClassSpells.lua as this client has them:
--- Forever's own left out, and any the client says it lacks; a rank before
--- that was left out gives way to the one before it. Laid out once a class.
function CT.Spells(class)
    local all = ns.CLASS_SPELLS and class and ns.CLASS_SPELLS[class]
    if type(all) ~= "table" then return nil end
    CT.spellLists = CT.spellLists or {}
    local kept = CT.spellLists[class]
    if kept and kept.from == all then return kept.list end
    local checks = Has("C_Spell.DoesSpellExist")
    local gone, list = {}, {}
    for _, entry in ipairs(all) do
        local id = entry[1]
        local drop = type(id) ~= "number" or id >= CT.FOREVER_FIRST
        if not drop and checks and Call("C_Spell.DoesSpellExist", id) == false then drop = true end
        if drop then gone[id] = entry[6] or false end
    end
    for _, entry in ipairs(all) do
        if gone[entry[1]] == nil then
            local before = entry[6]
            local hops = 0
            while before and gone[before] ~= nil and hops < 20 do
                before = gone[before] or nil
                hops = hops + 1
            end
            if before ~= entry[6] then
                entry = { entry[1], entry[2], entry[3], entry[4], entry[5], before }
            end
            list[#list + 1] = entry
        end
    end
    CT.spellLists[class] = { from = all, list = list }
    return list
end

--- The account save's table, made when first needed.
function CT:Data()
    local db = ns.db
    if not db then return { prices = {}, notTaught = {}, trainers = {}, characters = {}, learned = {}, skipped = {} } end
    local data = db.classTrainingData
    if type(data) ~= "table" then
        data = {}
        db.classTrainingData = data
    end
    for _, key in ipairs({ "prices", "notTaught", "trainers", "characters", "learned", "skipped" }) do
        if type(data[key]) ~= "table" then data[key] = {} end
    end
    return data
end

--- Is the feature on? ("Class training" in Settings, on unless unticked.)
function CT:IsOn()
    return not (ns.db and ns.db.classTraining == false)
end

function CT:SetOn(on)
    if not ns.db then return end
    ns.db.classTraining = on and true or false
    self:Changed()
end

function CT:Changed()
    self.version = self.version + 1
    self.plan = nil
    if type(self.OnChanged) == "function" then pcall(self.OnChanged) end
end

--------------------------------------------------------------------------------
-- The character playing
--------------------------------------------------------------------------------

--- { class, className, level, race, faction, realm, guid, name } for the
--- character playing.
function CT.Player()
    local className, class = Call("UnitClass", "player")
    local _, _, race = Call("UnitRace", "player")
    local faction = Call("UnitFactionGroup", "player")
    return {
        class = Text(class),
        className = Text(className) or Text(class),
        level = Number(Call("UnitLevel", "player")) or 1,
        race = Number(race),
        faction = Text(faction),
        realm = Text(Call("GetRealmName")),
        guid = Text(Call("UnitGUID", "player")),
        name = Text(Call("UnitName", "player")),
    }
end

--- Does the character playing know the spell?
function CT.Known(spellID)
    if Has("IsPlayerSpell") then
        if Call("IsPlayerSpell", spellID) then return true end
    end
    if Has("C_SpellBook.IsSpellKnown") then
        if Call("C_SpellBook.IsSpellKnown", spellID) then return true end
    end
    if Has("IsSpellKnown") then
        if Call("IsSpellKnown", spellID) then return true end
    end
    return false
end

--- The spell IDs of the class list the character playing knows: each the
--- client says it knows, each a class trainer showed as learned, and every
--- lower rank of a spell it knows, since the game can take an older rank
--- out of the spell book once a newer rank is learned (Backstab Rank 1
--- asked for again once Rank 2 was known). Lower ranks go by the rank
--- before and by name, as the data skips a rank now and then (Holy Light
--- Rank 5), so a gap never brings an old rank back.
function CT.KnownIn(list)
    local before, known, top = {}, {}, {}
    local learned = CT:Learned()
    for _, entry in ipairs(list) do
        if entry[6] then before[entry[1]] = entry[6] end
    end
    for _, entry in ipairs(list) do
        local id = entry[1]
        if not known[id] and (learned[id] or CT.Known(id)) then
            local name, rank = entry[4], entry[3] or 0
            if name and rank > (top[name] or 0) then top[name] = rank end
            while id and not known[id] do
                known[id] = true
                id = before[id]
            end
        end
    end
    for _, entry in ipairs(list) do
        local best = entry[4] and top[entry[4]]
        if best and (entry[3] or 0) > 0 and entry[3] < best then known[entry[1]] = true end
    end
    return known
end

--- The spells a class trainer showed the character playing as learned
--- ([spell ID] = true), for a spell the client's own check misses.
function CT:Learned()
    local guid = Text(Call("UnitGUID", "player"))
    local learned = guid and self:Data().learned[guid]
    return type(learned) == "table" and learned or {}
end

--------------------------------------------------------------------------------
-- Skipped spells
--------------------------------------------------------------------------------

-- The addons that carry this file, by global.
CT.SISTERS = { "BlackthornesEquipment", "BlackthornesButler" }

--- The other addon's copy of this module, when it is loaded.
function CT:Sisters()
    local list = {}
    for _, name in ipairs(self.SISTERS) do
        local addon = rawget(_G, name)
        local other = type(addon) == "table" and rawget(addon, "ClassTraining")
        if type(other) == "table" and other ~= self then list[#list + 1] = other end
    end
    return list
end

--- This addon's own record of skips for a character: { [spell ID] = time }.
function CT:OwnSkips(guid)
    local skips = guid and self:Data().skipped[guid]
    return type(skips) == "table" and skips or nil
end

--- The spells the character playing skipped ([spell ID] = true), from
--- this addon's record and the other's, the newest change winning.
function CT:Skipped()
    local guid = Text(Call("UnitGUID", "player"))
    local newest = {}
    local function Take(skips)
        if type(skips) ~= "table" then return end
        for id, at in pairs(skips) do
            if type(at) == "number" and (newest[id] == nil or math.abs(at) > math.abs(newest[id])) then
                newest[id] = at
            end
        end
    end
    Take(self:OwnSkips(guid))
    for _, other in ipairs(self:Sisters()) do
        local ok, skips = pcall(other.OwnSkips, other, guid)
        if ok then Take(skips) end
    end
    local skipped = {}
    for id, at in pairs(newest) do
        if at > 0 then skipped[id] = true end
    end
    return skipped
end

--- Keep one change in this addon's record (the other addon calls it too).
function CT:KeepSkip(guid, id, at)
    if not (guid and id and type(at) == "number") then return end
    local data = self:Data()
    local skips = data.skipped[guid]
    if type(skips) ~= "table" then
        skips = {}
        data.skipped[guid] = skips
    end
    skips[id] = at
    self:Changed()
end

--- Skip a spell for the character playing, or bring it back (on false).
function CT:SetSkipped(id, on)
    local guid = Text(Call("UnitGUID", "player"))
    if not (guid and id) then return false end
    local now = math.max(1, Now())
    local at = on and now or -now
    self:KeepSkip(guid, id, at)
    for _, other in ipairs(self:Sisters()) do
        pcall(other.KeepSkip, other, guid, id, at)
    end
    self:Note()
    return true
end

function CT:IsSkipped(id)
    return self:Skipped()[id] == true
end

--- The spell's name in the client's language, else the data's English.
function CT.SpellName(entry)
    local name = Text(Call("C_Spell.GetSpellName", entry[1]))
    if not name and Has("GetSpellInfo") then name = Text((Call("GetSpellInfo", entry[1]))) end
    return name or entry[4]
end

--- "Frostbolt (Rank 4)", or the name alone.
function CT.Label(entry)
    local name = CT.SpellName(entry)
    if (entry[3] or 0) > 0 then return L.Format("%s (Rank %d)", name, entry[3]) end
    return name
end

function CT.Icon(entry)
    local icon = Call("C_Spell.GetSpellTexture", entry[1])
    if not icon and Has("GetSpellTexture") then icon = Call("GetSpellTexture", entry[1]) end
    return icon or [[Interface\Icons\INV_Misc_Book_09]]
end

local function RaceOK(entry, race)
    local races = entry[5]
    if type(races) ~= "table" or not race then return true end
    for _, id in ipairs(races) do
        if id == race then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- The plan
--------------------------------------------------------------------------------

--- What a spell costs: the price a trainer showed, else Classic's
--- (Data/ClassSpells.lua's CLASS_SPELL_PRICES) until one does. The second
--- return is true for Classic's.
function CT.PriceOf(id, prices)
    prices = prices or CT:Data().prices
    if prices[id] then return prices[id], false end
    local base = ns.CLASS_SPELL_PRICES and ns.CLASS_SPELL_PRICES[id]
    if base then return base, true end
    return nil, false
end

local function Spell(entry, prices)
    local cost, guess = CT.PriceOf(entry[1], prices)
    return { id = entry[1], level = entry[2], rank = entry[3], entry = entry, cost = cost, guess = guess }
end

local function Sum(list)
    local cost, unknown, guessed = 0, 0, 0
    for _, spell in ipairs(list) do
        if spell.cost then cost = cost + spell.cost else unknown = unknown + 1 end
        if spell.guess then guessed = guessed + 1 end
    end
    return cost, unknown, guessed
end
CT.Sum = Sum

--- What the character playing can train: { ready = { spells }, cost,
--- unknown (how many have no price at all), guessed (how many go by
--- Classic's price until a trainer shows theirs), nextLevel, next = { spells },
--- nextCost, nextUnknown }. A spell is { id, level, rank, entry, cost }.
--- Kept until ClassTraining.version or the level moves.
function CT:Plan()
    local player = self.Player()
    local key = ("%d:%d"):format(self.version, player.level)
    if self.plan and self.planKey == key then return self.plan end
    self.planKey = key
    self.plan = self:Work(player)
    return self.plan
end

function CT:Work(player)
    local plan = { ready = {}, next = {}, skipped = {}, cost = 0, unknown = 0, nextCost = 0, nextUnknown = 0 }
    local list = CT.Spells(player.class)
    if type(list) ~= "table" then return plan end
    local data = self:Data()
    local prices, notTaught = data.prices, data.notTaught
    -- Spells learned before this one, or trained in the same visit (Train
    -- all learns them in order).
    local will = {}
    local knownIn = self.KnownIn(list)
    local skipped = self:Skipped()
    for _, entry in ipairs(list) do
        local id = entry[1]
        if not notTaught[id] and RaceOK(entry, player.race) then
            local known = knownIn[id]
            if known then
                will[id] = true
            elseif skipped[id] then
                -- Out of every list and cost; a later rank still shows.
                will[id] = true
                plan.skipped[#plan.skipped + 1] = Spell(entry, prices)
            elseif entry[2] <= player.level then
                local before = entry[6]
                if not before or will[before] or knownIn[before] then
                    will[id] = true
                    plan.ready[#plan.ready + 1] = Spell(entry, prices)
                end
            elseif not plan.nextLevel or entry[2] == plan.nextLevel then
                local before = entry[6]
                -- A later rank of a talent nobody here has is never next.
                local found = false
                for _, other in ipairs(list) do
                    if other[1] == before then found = true break end
                end
                if not before or will[before] or found then
                    plan.nextLevel = entry[2]
                    plan.next[#plan.next + 1] = Spell(entry, prices)
                end
            end
        end
    end
    plan.cost, plan.unknown, plan.guessed = Sum(plan.ready)
    plan.nextCost, plan.nextUnknown, plan.nextGuessed = Sum(plan.next)
    return plan
end

--- The gold the character playing needs for what it can train now (only
--- the prices known), for the gold fund.
function CT:ReadyCost()
    if not self:IsOn() then return 0 end
    return self:Plan().cost or 0
end

--------------------------------------------------------------------------------
-- Other characters
--------------------------------------------------------------------------------

--- Write down what this character can train, for the others to see.
function CT:Note()
    local player = self.Player()
    if not (player.guid and player.class) then return end
    local plan = self:Plan()
    local ready = {}
    for _, spell in ipairs(plan.ready) do ready[#ready + 1] = spell.id end
    self:Data().characters[player.guid] = {
        name = player.name, class = player.class, className = player.className,
        level = player.level, realm = player.realm, faction = player.faction,
        ready = ready, at = Now(),
    }
end

--- What another character (by GUID) can train, as last seen: { name,
--- class, className, level, count, cost, unknown, at }, or nil.
function CT:Other(guid)
    local note = guid and self:Data().characters[guid]
    if type(note) ~= "table" or type(note.ready) ~= "table" or #note.ready == 0 then return nil end
    local prices = self:Data().prices
    local cost, unknown, count = 0, 0, 0
    for _, id in ipairs(note.ready) do
        if not self:Data().notTaught[id] then
            count = count + 1
            local price = CT.PriceOf(id, prices)
            if price then cost = cost + price else unknown = unknown + 1 end
        end
    end
    if count == 0 then return nil end
    return { name = note.name, class = note.class, className = note.className, level = note.level,
        count = count, cost = cost, unknown = unknown, at = note.at, guid = guid }
end

--- The realm part of a character's GUID ("Player-<realm>-<id>").
local function ServerOf(guid)
    return type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil
end

--- Where other characters play, { [GUID] = { realm, faction } }, for notes
--- written before they kept it: Equipment's note of their gear, else
--- Tradeskills' record of them (read only, in a pcall).
local function KnownSides()
    local sides = {}
    local gear = ns.db and rawget(ns.db, "characterGear")
    if type(gear) == "table" then
        for guid, note in pairs(gear) do
            if type(note) == "table" then
                sides[guid] = { realm = Text(note.realm), faction = Text(note.faction) }
            end
        end
    end
    local ts = rawget(_G, "BlackthornesTS")
    local butler = type(ts) == "table" and rawget(ts, "Butler")
    local holdings = type(butler) == "table" and rawget(butler, "Holdings")
    if type(holdings) == "function" then
        local ok, list = pcall(holdings, butler)
        for _, entry in ipairs(ok and type(list) == "table" and list or {}) do
            local guid = type(entry) == "table" and Text(entry.key)
            if guid then
                local side = sides[guid] or {}
                -- Tradeskills writes "?" for a realm it could not read.
                side.realm = side.realm or (entry.realm ~= "?" and Text(entry.realm) or nil)
                side.faction = side.faction or Text(entry.faction)
                sides[guid] = side
            end
        end
    end
    return sides
end

--- Is another character on the realm and side of the one playing? Only
--- those can be sent gold for their spells, so only those are listed (a
--- player saw the other side's and other realms' characters, 2026-10-18).
--- A character whose side is not known yet is left out until it logs in.
function CT.SameSide(guid, note, player, sides)
    note = type(note) == "table" and note or {}
    local side = sides and sides[guid] or {}
    local realm = Text(note.realm) or side.realm
    local faction = Text(note.faction) or side.faction
    if not (player.faction and faction and faction == player.faction) then return false end
    if realm and player.realm then return realm == player.realm end
    local here, there = ServerOf(player.guid), ServerOf(guid)
    return here ~= nil and here == there
end

--- Every other character on this realm and side with spells waiting, most
--- first.
function CT:Others()
    local player = self.Player()
    local me = player.guid
    local list = {}
    local sides
    for guid, note in pairs(self:Data().characters) do
        if guid ~= me then
            local other = self:Other(guid)
            if other then
                if type(note) == "table" and not (Text(note.realm) and Text(note.faction)) then
                    sides = sides or KnownSides()
                end
                if CT.SameSide(guid, note, player, sides) then list[#list + 1] = other end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return tostring(a.name) < tostring(b.name)
    end)
    return list
end

--------------------------------------------------------------------------------
-- Trainers
--------------------------------------------------------------------------------

--- The trainer to go to for the character playing: one of its side in the
--- zone it is in first, else the last one visited. { name, zone, sub,
--- mapID, x, y } or nil when none has been visited yet.
function CT:Nearest()
    local player = self.Player()
    local trainers = player.class and self:Data().trainers[player.class]
    if type(trainers) ~= "table" then return nil end
    local mapID = Number(Call("C_Map.GetBestMapForUnit", "player"))
    local best, bestScore
    for _, spot in pairs(trainers) do
        if type(spot) == "table" and (not spot.faction or not player.faction or spot.faction == player.faction) then
            local score = (spot.at or 0) + ((mapID and spot.mapID == mapID) and 1e12 or 0)
            if not bestScore or score > bestScore then best, bestScore = spot, score end
        end
    end
    return best
end

--- Where a trainer stands, in words: "Wizard's Sanctum in Stormwind".
function CT.Where(spot)
    if not spot then return nil end
    local zone = Text(spot.zone)
    local sub = Text(spot.sub)
    if sub and zone and sub ~= zone then return L.Format("%s in %s", sub, zone) end
    return zone or sub
end

--- The arrow that shows the way: this addon's own (CT.Guide, set by
--- Equipment), else Equipment's when it is loaded beside this one, so
--- Butler's Show the way moves the quest arrow on screen rather than a pin
--- behind it.
function CT:GuideFn()
    if type(self.Guide) == "function" then return self.Guide end
    local equipment = rawget(_G, "BlackthornesEquipment")
    local ok, guide = pcall(function() return equipment.ClassTraining.Guide end)
    if ok and type(guide) == "function" then return guide end
    return nil
end

--- Show the way to the trainer: an arrow when one is loaded (GuideFn),
--- else TomTom, else the game's map pin. Says where in chat. True when
--- there was somewhere to go.
function CT:ShowTheWay()
    local spot = self:Nearest()
    local player = self.Player()
    if not spot then
        ns.Print(L.Format("no %s trainer seen yet. Open one once and it's remembered.", player.className or ""))
        return false
    end
    local title = L.Format("%s trainer: %s", player.className or "", spot.name or "")
    local shown = false
    local guide = self:GuideFn()
    if guide then
        local ok, done = pcall(guide, spot, title)
        shown = ok and done
    end
    -- A trainer in another zone or across the sea, with "Guide Me:" ticked
    -- (Logic/Travel.lua): the steps in chat and the pin on the first stop.
    local pin, steps = spot, nil
    if not shown then
        local trip = self.TripTo(spot)
        if trip then
            pin = { mapID = trip.point.map, x = trip.point.x, y = trip.point.y }
            title, steps = trip.point.name or title, trip.lines
        end
    end
    if not shown and pin.mapID and pin.x and pin.y then
        local tomtom = rawget(_G, "TomTom")
        if type(tomtom) == "table" and type(tomtom.AddWaypoint) == "function" and not (ns.db and ns.db.useTomTom == false) then
            shown = pcall(tomtom.AddWaypoint, tomtom, pin.mapID, pin.x, pin.y,
                { title = title, persistent = false, minimap = true, world = true })
        end
        if not shown and Has("C_Map.SetUserWaypoint") and Has("UiMapPoint.CreateFromCoordinates") then
            local point = Call("UiMapPoint.CreateFromCoordinates", pin.mapID, pin.x, pin.y)
            if point then
                shown = pcall(C_Map.SetUserWaypoint, point)
                if shown and Has("C_SuperTrack.SetSuperTrackedUserWaypoint") then
                    Call("C_SuperTrack.SetSuperTrackedUserWaypoint", true)
                end
            end
        end
    end
    if steps then
        ns.Print(L.Format("The way to your %s trainer, with a pin on the first stop:", player.className or ""))
        local say = ns.PrintRaw or ns.Print
        for _, line in ipairs(steps) do say("  " .. line) end
        return true
    end
    local where = self.Where(spot)
    if where then
        ns.Print(L.Format("%s, %s.", title, where))
    else
        ns.Print(title .. ".")
    end
    return true
end

--- The way there to a trainer far away, by Logic/Travel.lua (the same
--- file in every Blackthornes addon): { lines, point }, or nil when it is
--- near, "Guide Me:" is off, the addon has no Travel or no way is known.
function CT.TripTo(spot)
    local Travel = ns.Travel
    if not (Travel and Travel.IsOn and Travel.IsOn() and spot and spot.zone) then return nil end
    local target = { name = spot.name, zone = spot.zone, map = spot.mapID, mx = spot.x, my = spot.y }
    local ok, trip = pcall(Travel.Guide, Travel, target)
    if not ok or type(trip) ~= "table" or type(trip.point) ~= "table" or #trip.lines == 0 then return nil end
    return trip
end

--------------------------------------------------------------------------------
-- At a trainer
--------------------------------------------------------------------------------

--- The spell a trainer's line teaches, for the class: the tooltip's spell
--- ID when the client gives it, else matched by name and rank.
function CT:ServiceSpell(index, name, rank, class)
    local data = Call("C_TooltipInfo.GetTrainerService", index)
    local id = type(data) == "table" and Number(data.id) or nil
    local list = CT.Spells(class)
    if type(list) ~= "table" then return nil end
    if id then
        for _, entry in ipairs(list) do
            if entry[1] == id then return entry end
        end
    end
    name = Text(name)
    if not name then return nil end
    self.byName = self.byName or {}
    local names = self.byName[class]
    if not names then
        names = {}
        for _, entry in ipairs(list) do
            local subtext = Text(Call("C_Spell.GetSpellSubtext", entry[1]))
                or (Has("GetSpellSubtext") and Text((Call("GetSpellSubtext", entry[1])))) or ""
            names[CT.SpellName(entry) .. "|" .. subtext] = entry
            -- The English pair too, for a client that gives no subtext.
            local english = entry[3] > 0 and ("Rank " .. entry[3]) or ""
            names[entry[4] .. "|" .. english] = names[entry[4] .. "|" .. english] or entry
            -- The name and the rank's number, for any language ("Rang 4").
            local number = CT.SpellName(entry) .. "#" .. (entry[3] or 0)
            names[number] = names[number] or entry
        end
        self.byName[class] = names
    end
    local found = names[name .. "|" .. (Text(rank) or "")]
    if found then return found end
    local digits = Text(rank) and select(2, pcall(string.match, rank, "%d+"))
    return names[name .. "#" .. (Number(digits) or 0)]
end

--- The trainer's lines: { index, kind ("available", "unavailable",
--- "used"), entry, cost, level } for the class's spells only.
function CT:Services(class)
    local list = {}
    local count = Number(Call("GetNumTrainerServices")) or 0
    for index = 1, count do
        local name, rank, kind = Call("GetTrainerServiceInfo", index)
        if kind ~= "header" then
            local entry = self:ServiceSpell(index, name, rank, class)
            if entry then
                list[#list + 1] = {
                    index = index, kind = kind, entry = entry,
                    cost = Number((Call("GetTrainerServiceCost", index))),
                    level = Number(Call("GetTrainerServiceLevelReq", index)),
                }
            end
        end
    end
    return list
end

--- Read the open trainer: if it teaches the class, keep its prices, what
--- it teaches and where it stands.
function CT:ReadTrainer()
    if Has("IsTradeskillTrainer") and Call("IsTradeskillTrainer") then
        self.atClassTrainer = false
        return
    end
    local player = self.Player()
    if not player.class then return end

    -- Show the spells not learnable yet just long enough to read their
    -- prices, then put the filter back as the player had it.
    local hidden = Has("GetTrainerServiceTypeFilter") and Has("SetTrainerServiceTypeFilter")
        and not Call("GetTrainerServiceTypeFilter", "unavailable")
    if hidden then
        self.flipping = true
        Call("SetTrainerServiceTypeFilter", "unavailable", 1)
    end
    local services = self:Services(player.class)
    local sawLater = false
    for _, service in ipairs(services) do
        if service.kind == "unavailable" then sawLater = true end
    end
    if hidden then
        Call("SetTrainerServiceTypeFilter", "unavailable", 0)
        C_Timer.After(0.5, function() CT.flipping = false end)
    end

    self.atClassTrainer = #services > 0
    if not self.atClassTrainer then return end

    local data = self:Data()
    -- What the trainer shows as learned is known, whatever the client's
    -- own check says.
    if player.guid then
        local learned = type(data.learned[player.guid]) == "table" and data.learned[player.guid] or {}
        for _, service in ipairs(services) do
            if service.kind == "used" then learned[service.entry[1]] = true end
        end
        if next(learned) then data.learned[player.guid] = learned end
    end
    local listed, upTo = {}, player.level
    for _, service in ipairs(services) do
        listed[service.entry[1]] = true
        data.notTaught[service.entry[1]] = nil
        if service.cost and service.cost >= 0 then data.prices[service.entry[1]] = service.cost end
    end
    -- A spell up to the level the list covers that it doesn't teach, and
    -- this character doesn't know, comes from somewhere else (a quest).
    if sawLater then upTo = math.huge end
    local classList = CT.Spells(player.class) or {}
    local knownIn = self.KnownIn(classList)
    for _, entry in ipairs(classList) do
        if entry[2] <= upTo and not listed[entry[1]] and RaceOK(entry, player.race)
            and not knownIn[entry[1]] then
            data.notTaught[entry[1]] = true
        end
    end

    -- Where it stands.
    local guid = Text(Call("UnitGUID", "npc"))
    local npcID = guid and Number(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
    if npcID then
        local trainers = data.trainers
        trainers[player.class] = type(trainers[player.class]) == "table" and trainers[player.class] or {}
        local mapID = Number(Call("C_Map.GetBestMapForUnit", "player"))
        local x, y
        if mapID then
            local position = Call("C_Map.GetPlayerMapPosition", mapID, "player")
            if position and position.GetXY then
                local ok, px, py = pcall(position.GetXY, position)
                if ok then x, y = Number(px), Number(py) end
            end
        end
        trainers[player.class][npcID] = {
            name = Text(Call("UnitName", "npc")), zone = Text(Call("GetRealZoneText")) or Text(Call("GetZoneText")),
            sub = Text(Call("GetSubZoneText")), mapID = mapID, x = x, y = y,
            faction = player.faction, at = Now(),
        }
    end
    self:Changed()
    self:Note()
end

--- The spells Train all would buy here now, cheapest first: the trainer's
--- available lines for the class.
function CT:Buyable()
    local player = self.Player()
    local list = {}
    if not (self.trainerOpen and self.atClassTrainer and player.class) then return list end
    for _, service in ipairs(self:Services(player.class)) do
        if service.kind == "available" and not (service.entry and self:IsSkipped(service.entry[1])) then
            list[#list + 1] = service
        end
    end
    table.sort(list, function(a, b)
        if a.entry[2] ~= b.entry[2] then return a.entry[2] < b.entry[2] end
        return (a.cost or 0) < (b.cost or 0)
    end)
    return list
end

--- Train every spell this trainer has for the character that the purse
--- pays for: one every CT.GAP seconds, each read again first. Only on the
--- player's click.
function CT:TrainAll()
    if self.buying or InCombat() then return end
    if not Has("BuyTrainerService") then
        ns.Print(L["click Train in the trainer's window for each spell."])
        return
    end
    self.buying = true
    self.run = (self.run or 0) + 1
    local run = self.run
    local bought, spent = 0, 0
    -- Spells this run has bought already: a slow server can leave one
    -- "available" past the next step, and a buy the game quietly refuses
    -- would otherwise be tried every step until the trainer closes.
    local tried = {}
    if type(self.OnChanged) == "function" then pcall(self.OnChanged) end

    local function Done(why)
        CT.buying = false
        if bought > 0 then
            ns.Print(bought == 1 and L.Format("trained 1 spell for %s.", CT.Money(spent))
                or L.Format("trained %d spells for %s.", bought, CT.Money(spent)))
        elseif why then
            ns.Print(why)
        end
        CT:Changed()
        CT:Note()
    end

    local function Step()
        if CT.run ~= run or not CT.trainerOpen or InCombat() then return Done() end
        local purse = Number(Call("GetMoney")) or 0
        local pick, untried = nil, 0
        for _, service in ipairs(CT:Buyable()) do
            local id = service.entry and service.entry[1]
            if not tried[id] then
                untried = untried + 1
                if not pick and (service.cost or 0) <= purse then pick = service end
            end
        end
        if not pick then
            return Done(untried > 0 and L["you can't pay for the next spell yet."] or nil)
        end
        local ok = pcall(BuyTrainerService, pick.index)
        if not ok then return Done(L["the game wouldn't train it from here. Click Train in the trainer's window."]) end
        if pick.entry and pick.entry[1] ~= nil then tried[pick.entry[1]] = true end
        bought = bought + 1
        spent = spent + (pick.cost or 0)
        C_Timer.After(CT.GAP, Step)
    end

    Step()
end

--- Copper as gold, silver and copper, through the addon's own formatter.
function CT.Money(copper)
    local format = (ns.Items and ns.Items.FormatMoney) or (ns.Finder and ns.Finder.Money) or ns.FormatMoney
    if type(format) == "function" then
        local ok, text = pcall(format, copper)
        if ok and text then return text end
    end
    copper = math.floor(copper or 0)
    return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- "16g", or "16g and 2 not priced yet", or "price after a trainer visit".
function CT.CostText(cost, unknown, count)
    if unknown >= count then return L["price after a trainer visit"] end
    if unknown > 0 then return L.Format("%s, %d not priced yet", CT.Money(cost), unknown) end
    return CT.Money(cost)
end

--- The chat line after a level, or nil with nothing to train.
function CT:LevelLine()
    local plan = self:Plan()
    local count = #plan.ready
    if count == 0 then return nil end
    local player = self.Player()
    local spot = self:Nearest()
    local where = self.Where(spot)
    local what
    if plan.unknown >= count then
        what = count == 1 and L["you can train 1 new spell now."] or L.Format("you can train %d new spells now.", count)
    else
        what = count == 1 and L.Format("you can train 1 new spell now, %s.", CT.CostText(plan.cost, plan.unknown, count))
            or L.Format("you can train %d new spells now, %s in all.", count, CT.CostText(plan.cost, plan.unknown, count))
    end
    if where then
        return L.Format("%s The nearest %s trainer is in %s.", what, player.className or "", where)
    end
    return what
end

--- One line for the probe: the calls class training reads.
function CT:ProbeText()
    local parts = {}
    for _, name in ipairs({ "IsPlayerSpell", "GetNumTrainerServices", "GetTrainerServiceInfo",
        "GetTrainerServiceCost", "GetTrainerServiceTypeFilter", "BuyTrainerService",
        "C_TooltipInfo.GetTrainerService", "C_Spell.GetSpellName" }) do
        parts[#parts + 1] = name .. (Has(name) and " yes" or " no")
    end
    local player = self.Player()
    local list = CT.Spells(player.class)
    local plan = self:Plan()
    return ("%s; %s spells in the data, %d to train now, %d priced"):format(
        table.concat(parts, ", "), list and #list or 0, #plan.ready, #plan.ready - plan.unknown)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function CT:OnEnable()
    local function Learned()
        if CT.learning then return end
        CT.learning = true
        C_Timer.After(0.5, function()
            CT.learning = false
            CT:Changed()
            CT:Note()
        end)
    end
    ns.RegisterEvent(self, "LEARNED_SPELL_IN_TAB", Learned)
    ns.RegisterEvent(self, "SPELLS_CHANGED", Learned)
    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", function()
        C_Timer.After(CT.LEVEL_DELAY, function()
            CT:Changed()
            CT:Note()
            if CT:IsOn() and not CT.quietLevels then
                local line = CT:LevelLine()
                if line then ns.Print(line) end
            end
        end)
    end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function(_, _, isInitialLogin)
        if isInitialLogin or isInitialLogin == nil then
            C_Timer.After(CT.LEVEL_DELAY, function() CT:Note() end)
        end
    end)
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function() CT:Note() end)

    ns.RegisterEvent(self, "TRAINER_SHOW", function()
        CT.trainerOpen = true
        CT:ReadTrainer()
        if type(CT.OnTrainer) == "function" then pcall(CT.OnTrainer, true) end
    end)
    ns.RegisterEvent(self, "TRAINER_UPDATE", function()
        if CT.flipping or CT.reading or not CT.trainerOpen then return end
        CT.reading = true
        C_Timer.After(0.2, function()
            CT.reading = false
            if CT.trainerOpen and not CT.flipping then CT:ReadTrainer() end
        end)
    end)
    ns.RegisterEvent(self, "TRAINER_CLOSED", function()
        CT.trainerOpen, CT.atClassTrainer = false, false
        CT.run = (CT.run or 0) + 1
        CT:Changed()
        if type(CT.OnTrainer) == "function" then pcall(CT.OnTrainer, false) end
    end)
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

--- What the character can train, in chat, and the other characters'.
function CT:Report()
    local plan = self:Plan()
    local player = self.Player()
    if #plan.ready == 0 then
        ns.Print(L["no class spells to train right now."])
    else
        ns.Print(#plan.ready == 1 and L.Format("1 spell to train now, %s:", self.CostText(plan.cost, plan.unknown, 1))
            or L.Format("%d spells to train now, %s in all:", #plan.ready, self.CostText(plan.cost, plan.unknown, #plan.ready)))
        for _, spell in ipairs(plan.ready) do
            ns.PrintRaw(("   %s  %s"):format(self.Label(spell.entry), spell.cost and self.Money(spell.cost) or L["not priced yet"]))
        end
    end
    if plan.nextLevel then
        ns.PrintRaw(L.Format("   At level %d: %d more, %s.", plan.nextLevel, #plan.next,
            self.CostText(plan.nextCost, plan.nextUnknown, #plan.next)))
    end
    local where = self.Where(self:Nearest())
    if where then ns.PrintRaw(L.Format("   Your %s trainer: %s.", player.className or "", where)) end
    for _, other in ipairs(self:Others()) do
        ns.PrintRaw(L.Format("   %s: %d at level %d, %s.", other.name or "?", other.count, other.level or 0,
            self.CostText(other.cost, other.unknown, other.count)))
    end
    if not self:IsOn() then ns.PrintRaw(L["   Class training is turned off in Settings."]) end
end

ns.RegisterCommand("training", L["list the class spells you can train and what they cost (training on|off to turn it on or off)"], function(rest)
    local word = (rest or ""):lower():match("^%s*(%a+)")
    if word == "on" or word == "off" then
        CT:SetOn(word == "on")
        ns.Print(word == "on" and L["class training is on."] or L["class training is off."])
        if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
        return
    end
    CT:Report()
end)
