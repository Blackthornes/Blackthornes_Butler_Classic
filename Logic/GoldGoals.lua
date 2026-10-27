-- Blackthornes Butler -- Logic/GoldGoals.lua
-- Gold goals (the owner said build it, 2026-10-13, from a mockup, with the
-- purse at the bottom of the window): the next training that costs gold,
-- each with a bar of the purse against its price.
--
-- Three goals, filled from one purse in order:
--   1. Class spells: what can be trained now (Logic/ClassTraining.lua), else
--      the next level's.
--   2. Professions: the next rank of each profession whose skill is high
--      enough (Journeyman, Expert, Artisan), and the trainers' recipes it
--      could learn now (Tradeskills' Butler:LearnCost, when it is loaded).
--   3. Riding: the next riding skill, when the level cap reaches it.
--
-- Prices are Classic's usual ones (RANKS, RIDING below) until a trainer
-- shows its own, which is kept account wide in goldGoalsData.prices. The
-- level cap is read from the game (it is 30 in the beta and 60 at
-- release), never assumed; 60 when the game does not say.
--
-- The purse is what the character carries less the gold the gold fund
-- will mail to another character (Logic/Funds.lua). The fund never limits
-- spending; it only says what is set aside.
--
-- Each character writes its goals down (goldGoalsData.characters[guid]) so
-- All characters can show everyone's. Saved, never renamed: goldGoals
-- (the setting, on unless unticked) and goldGoalsData.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local GG = ns.NewModule("GoldGoals")

-- Moves whenever the goals should be worked out again.
GG.version = 0
-- After a burst of skill, spell or recipe events.
GG.SETTLE = 0.5
-- When the game does not say the level cap.
GG.FALLBACK_CAP = 60

-- Classic's profession ranks, by Classic skill line, one per rank after
-- Apprentice: { spell, skill it needs, level it needs, usual price }.
-- Index 1 follows a cap of 75, 2 a cap of 150, 3 a cap of 225. Cooking and
-- First Aid go past Journeyman with a book, Fishing's Expert is a book too.
GG.RANKS = {
    [171] = { { 2280, 50, 10, 450 }, { 3465, 125, 20, 5000 }, { 11612, 200, 35, 45000 } },     -- Alchemy
    [164] = { { 2021, 50, 10, 450 }, { 3539, 125, 20, 4500 }, { 9786, 200, 35, 50000 } },      -- Blacksmithing
    [333] = { { 7415, 50, 10, 500 }, { 7416, 125, 20, 5000 }, { 13921, 200, 35, 50000 } },     -- Enchanting
    [202] = { { 4040, 50, 10, 450 }, { 4041, 125, 20, 4500 }, { 12657, 200, 35, 45000 } },     -- Engineering
    [182] = { { 2373, 50, 0, 500 }, { 3571, 125, 0, 5000 }, { 11994, 200, 0, 50000 } },        -- Herbalism
    [165] = { { 2154, 50, 10, 500 }, { 3812, 125, 20, 5000 }, { 10663, 200, 35, 50000 } },     -- Leatherworking
    [186] = { { 2582, 50, 0, 500 }, { 3568, 125, 0, 4500 }, { 10249, 200, 0, 50000 } },        -- Mining
    [393] = { { 8619, 50, 0, 500 }, { 8620, 125, 0, 5000 }, { 10769, 200, 35, 50000 } },       -- Skinning
    [197] = { { 3912, 50, 10, 450 }, { 3913, 125, 20, 4500 }, { 12181, 200, 35, 50000 } },     -- Tailoring
    [185] = { { 3412, 50, 10, 500 } },                                                       -- Cooking
    [129] = { { 3280, 50, 0, 500 } },                                                        -- First Aid
    [356] = { { 7734, 50, 0, 500 }, nil, { 18249, 200, 35, 10000 } },                        -- Fishing
}

-- Forever lists each crafting profession twice: its modern skill line and
-- Classic's. Both say the same skill.
GG.MODERN = {
    [2937] = 171, [2938] = 164, [2940] = 333, [2941] = 202, [2944] = 182,
    [2945] = 165, [2946] = 186, [2947] = 393, [2948] = 197,
}

-- Riding, in order: { spells that teach it, level, usual price }.
GG.RIDING = {
    { spells = { 33388, 33389 }, level = 40, price = 900000 },
    { spells = { 33391, 33392 }, level = 60, price = 9000000 },
}
-- Classic's riding skills by race; any of them counts as the first.
GG.RACE_RIDING = { 824, 825, 826, 828, 10861, 10906, 10907, 18995 }

GG.ICONS = {
    class = [[Interface\Icons\INV_Misc_Book_09]],
    profession = [[Interface\Icons\INV_Misc_Note_01]],
    riding = [[Interface\Icons\Ability_Mount_RidingHorse]],
}

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

--------------------------------------------------------------------------------
-- Saved data and the setting
--------------------------------------------------------------------------------

function GG:Data()
    local db = ns.db
    if not db then return { prices = {}, characters = {} } end
    local data = db.goldGoalsData
    if type(data) ~= "table" then
        data = {}
        db.goldGoalsData = data
    end
    for _, key in ipairs({ "prices", "characters" }) do
        if type(data[key]) ~= "table" then data[key] = {} end
    end
    return data
end

function GG:IsOn()
    return not (ns.db and ns.db.goldGoals == false)
end

function GG:SetOn(on)
    if not ns.db then return end
    ns.db.goldGoals = on and true or false
    self:Changed()
    if ns.UI and ns.UI.GoldGoalsChanged then ns.UI:GoldGoalsChanged() end
end

function GG:Changed()
    self.version = self.version + 1
    self.goals = nil
end

--------------------------------------------------------------------------------
-- What the game says
--------------------------------------------------------------------------------

--- The highest level a character can reach on this client: 30 in the beta,
--- 60 at release. Read from the game, 60 when it does not say.
function GG.MaxLevel()
    for _, name in ipairs({ "GetMaxLevelForPlayerExpansion", "GetMaxLevelForLatestExpansion", "GetMaxPlayerLevel" }) do
        local level = Number(Call(name))
        if level and level >= 10 and level <= 100 then return math.floor(level) end
    end
    local level = Number(rawget(_G, "MAX_PLAYER_LEVEL"))
    if level and level >= 10 and level <= 100 then return math.floor(level) end
    return GG.FALLBACK_CAP
end

function GG.Level()
    return Number(Call("UnitLevel", "player")) or 1
end

function GG.Known(spellID)
    if ns.ClassTraining and ns.ClassTraining.Known then return ns.ClassTraining.Known(spellID) end
    return Call("IsPlayerSpell", spellID) and true or false
end

--- A spell's name in the client's language, or nil.
function GG.SpellName(spellID)
    local name = Text(Call("C_Spell.GetSpellName", spellID))
    if not name and Has("GetSpellInfo") then name = Text((Call("GetSpellInfo", spellID))) end
    return name
end

-- English names, for a client that names no spell.
local ENGLISH = {
    [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering",
    [182] = "Herbalism", [165] = "Leatherworking", [186] = "Mining", [393] = "Skinning",
    [197] = "Tailoring", [185] = "Cooking", [129] = "First Aid", [356] = "Fishing",
}
local RANK_WORDS = { L["Journeyman"], L["Expert"], L["Artisan"] }
GG.RANK_WORDS = RANK_WORDS

--- A profession's Classic skill line from its English name, or nil.
function GG.LineOf(english)
    for line, name in pairs(ENGLISH) do
        if name == english then return line end
    end
    return nil
end

--- The character's professions: { [Classic skill line] = { skill, max,
--- name } }, only those with ranks to train.
function GG.Professions()
    local list = {}
    local lines = Call("C_TradeSkillUI.GetAllProfessionTradeSkillLines")
    if type(lines) == "table" then
        for _, id in ipairs(lines) do
            local info = Call("C_TradeSkillUI.GetProfessionInfoBySkillLineID", id)
            local line = GG.MODERN[id] or id
            if type(info) == "table" and GG.RANKS[line] then
                local max, skill = Number(info.maxSkillLevel), Number(info.skillLevel)
                if max and max > 0 then
                    local old = list[line]
                    list[line] = {
                        skill = math.max(skill or 0, old and old.skill or 0),
                        max = math.max(max, old and old.max or 0),
                        name = Text(info.professionName) or (old and old.name) or ENGLISH[line],
                    }
                end
            end
        end
        if next(list) then return list end
    end
    -- An older client: the skill list, by English name.
    local byName = {}
    for line, name in pairs(ENGLISH) do byName[name] = line end
    local count = Number(Call("GetNumSkillLines")) or 0
    for index = 1, count do
        local name, header, _, skill, _, _, max = Call("GetSkillLineInfo", index)
        local line = byName[Text(name) or ""]
        if line and not header and Number(max) and Number(max) > 0 then
            list[line] = { skill = Number(skill) or 0, max = Number(max), name = name }
        end
    end
    return list
end

--- What a training costs: the price a trainer showed, else Classic's. The
--- second return is true for Classic's.
function GG:PriceOf(spellID, usual)
    local seen = self:Data().prices[spellID]
    if type(seen) == "table" and Number(seen.cost) then return Number(seen.cost), false end
    return usual, true
end

--- The level a training needs: a trainer's, else Classic's.
function GG:LevelOf(spellID, usual)
    local seen = self:Data().prices[spellID]
    if type(seen) == "table" and Number(seen.level) then return Number(seen.level) end
    return usual
end

--------------------------------------------------------------------------------
-- The goals
--------------------------------------------------------------------------------

local function ClassGoal(level, cap)
    local CT = ns.ClassTraining
    if not (CT and CT:IsOn()) then return nil end
    local plan = CT:Plan()
    if #plan.ready > 0 then
        local count = #plan.ready
        return {
            kind = "class", count = count, cost = plan.cost, unknown = plan.unknown,
            guessed = (plan.guessed or 0) > 0, spells = plan.ready,
            label = count == 1 and L["Class spells: 1 to train"] or L.Format("Class spells: %d to train", count),
        }
    end
    if plan.nextLevel and plan.nextLevel <= cap then
        local count = #plan.next
        return {
            kind = "class", count = count, cost = plan.nextCost, unknown = plan.nextUnknown,
            guessed = (plan.nextGuessed or 0) > 0, spells = plan.next, level = plan.nextLevel,
            label = count == 1 and L.Format("Class spells: 1 at level %d", plan.nextLevel)
                or L.Format("Class spells: %d at level %d", count, plan.nextLevel),
        }
    end
    return nil
end

--- The next rank of one profession: { spell, name, cost, level, guess }.
function GG:NextRank(line, profession, cap)
    local ranks = self.RANKS[line]
    local max = profession.max
    local index
    if max >= 300 then
        index = nil
    elseif max >= 225 then
        index = 3
    elseif max >= 150 then
        index = 2
    elseif max >= 75 then
        index = 1
    end
    local rank = ranks and index and ranks[index]
    if not rank or profession.skill < rank[2] then return nil end
    local level = self:LevelOf(rank[1], rank[3])
    if level > cap then return nil end
    local cost, guess = self:PriceOf(rank[1], rank[4])
    return {
        spell = rank[1], cost = cost, guess = guess, level = level, profession = profession.name,
        line = line, teaches = (index + 1) * 75,
        name = GG.SpellName(rank[1]) or L.Format("%s %s", RANK_WORDS[index], profession.name or ENGLISH[line]),
    }
end

--- And, with Tradeskills: the trainers' recipes each could learn now.
local function LearnCost()
    local ts = rawget(_G, "BlackthornesTS")
    local butler = type(ts) == "table" and rawget(ts, "Butler")
    if type(butler) ~= "table" or type(butler.LearnCost) ~= "function" then return nil end
    local ok, answer = pcall(butler.LearnCost, butler)
    if ok and type(answer) == "table" then return answer end
    return nil
end

--- Each recipe Tradeskills names (2026-10-22, a player asked which one it
--- was): { { recipeID, name, cost } }, cheapest first. A field of the wrong
--- type is left out; an older Tradeskills gives none.
function GG.RecipeList(recipes)
    local list = {}
    if type(recipes) ~= "table" then return list end
    for _, recipe in ipairs(recipes) do
        if type(recipe) == "table" and Number(recipe.recipeID) and type(recipe.name) == "string" then
            list[#list + 1] = { recipeID = Number(recipe.recipeID), name = recipe.name, cost = Number(recipe.cost) or 0 }
        end
    end
    return list
end

--- The first recipe a goal names, to show the way to its trainer.
function GG.FirstRecipe(goal)
    for _, group in ipairs(type(goal) == "table" and goal.recipes or {}) do
        local recipe = group.list and group.list[1]
        if recipe then return recipe end
    end
    return nil
end

--- Show the way for a goal, through Tradeskills' own Show the way (its
--- arrow, "Guide Me:", TomTom and the spots the game saw), inside a pcall:
--- the trainer of a rank to train now first, so the cap goes up before the
--- recipes; once that is trained, the trainer who teaches its recipes
--- (2026-10-23). True when it set one.
function GG:ShowTheWay(goal)
    if type(goal) ~= "table" then return false end
    local ts = rawget(_G, "BlackthornesTS")
    local learn = type(ts) == "table" and rawget(ts, "LearnNext")
    if type(learn) ~= "table" then return false end
    if type(learn.TrainerFor) == "function" and type(learn.ShowTheWay) == "function" then
        for _, rank in ipairs(goal.ranks or {}) do
            if rank.line and not goal.level then
                local found, place = pcall(learn.TrainerFor, learn, rank.line, rank.teaches)
                if found and type(place) == "table" then
                    local ok, done = pcall(learn.ShowTheWay, learn, { place = place, name = rank.name })
                    if ok and done then return true end
                end
            end
        end
    end
    if not GG.FirstRecipe(goal) or type(learn.ShowTheWayFor) ~= "function" then return false end
    for _, group in ipairs(goal.recipes) do
        for _, each in ipairs(group.list or {}) do
            local ok, done = pcall(learn.ShowTheWayFor, learn, each.recipeID)
            if ok and done then return true end
        end
    end
    return false
end

--- One goal for each profession (the owner, 2026-10-23: "each should have
--- their own"): the rank to train now and, with Tradeskills, the trainers'
--- recipes it could learn now; else its next rank, levels away. The ones to
--- pay for now come first, cheapest first, then the ones levels away.
local function ProfessionGoals(level, cap)
    local professions = GG.Professions()
    local learn = LearnCost() or {}
    local now, later = {}, {}
    local lines = {}
    for line in pairs(professions) do lines[#lines + 1] = line end
    table.sort(lines)
    for _, line in ipairs(lines) do
        local profession = professions[line]
        local name = profession.name or ENGLISH[line]
        local rank = GG:NextRank(line, profession, cap)
        local recipe = learn[line]
        local count = recipe and Number(recipe.count) or 0
        local recipeCost = count > 0 and (Number(recipe.cost) or 0) or 0
        local ready = rank and rank.level <= level
        if ready or count > 0 then
            local parts, ranks, recipes = {}, {}, {}
            local cost, guess = recipeCost, false
            if ready then
                parts[1] = rank.name
                ranks[1] = rank
                cost, guess = cost + rank.cost, rank.guess
            end
            if count > 0 then
                if ready then
                    parts[2] = count == 1 and L["1 recipe"] or L.Format("%d recipes", count)
                else
                    parts[1] = count == 1 and L.Format("1 %s recipe", name)
                        or L.Format("%d %s recipes", count, name)
                end
                recipes[1] = { name = name, count = count, cost = recipeCost, list = GG.RecipeList(recipe.recipes) }
            end
            now[#now + 1] = {
                kind = "profession", cost = cost, guessed = guess, ranks = ranks, recipes = recipes,
                label = #parts == 2 and L.Format("%s and %s", parts[1], parts[2]) or parts[1],
            }
        elseif rank then
            later[#later + 1] = {
                kind = "profession", cost = rank.cost, guessed = rank.guess, ranks = { rank }, recipes = {},
                level = rank.level, label = L.Format("%s at level %d", rank.name, rank.level),
            }
        end
    end
    table.sort(now, function(x, y)
        if x.cost ~= y.cost then return x.cost < y.cost end
        return x.label < y.label
    end)
    table.sort(later, function(x, y)
        if x.level ~= y.level then return x.level < y.level end
        return x.label < y.label
    end)
    for _, goal in ipairs(later) do now[#now + 1] = goal end
    return now
end

local function KnowsAny(spells)
    for _, id in ipairs(spells) do
        if GG.Known(id) then return true end
    end
    return false
end

--- The riding skill as the skill list shows it, or nil when it shows none.
--- On Era riding is one skill a race, 75 at level 40 and 150 at 60, and
--- the later riding spells above don't exist, so the skill says what is
--- learned.
function GG.RidingSkill()
    local names = {}
    for _, id in ipairs(GG.RACE_RIDING) do
        local name = GG.SpellName(id)
        if name then names[name] = true end
    end
    local best
    local count = Number(Call("GetNumSkillLines")) or 0
    for index = 1, count do
        local name, header, _, skill = Call("GetSkillLineInfo", index)
        name = Text(name)
        if name and names[name] and not header then
            local rank = Number(skill)
            if rank and (not best or rank > best) then best = rank end
        end
    end
    return best
end

function GG:NextRiding(cap)
    local index = 1
    if KnowsAny(self.RIDING[1].spells) or KnowsAny(self.RACE_RIDING) then index = 2 end
    if index == 2 and KnowsAny(self.RIDING[2].spells) then return nil end
    local skill = GG.RidingSkill()
    if skill and skill >= 150 then return nil end
    if skill and skill >= 75 then index = 2 end
    local riding = self.RIDING[index]
    local spell = riding.spells[1]
    local level = self:LevelOf(spell, riding.level)
    if level > cap then return nil end
    local cost, guess = self:PriceOf(spell, riding.price)
    return { spell = spell, level = level, cost = cost, guess = guess,
        name = GG.SpellName(spell) or (index == 1 and L["Apprentice Riding"] or L["Journeyman Riding"]) }
end

local function RidingGoal(level, cap)
    local riding = GG:NextRiding(cap)
    if not riding then return nil end
    return {
        kind = "riding", cost = riding.cost, guessed = riding.guess, riding = riding,
        level = riding.level > level and riding.level or nil,
        label = riding.level > level and L.Format("%s at level %d", riding.name, riding.level) or riding.name,
    }
end

--- The gold the gold fund will mail to another character from this one.
function GG.SetAside()
    local funds = ns.Funds
    if not (funds and funds.IsOn and funds:IsOn()) then return 0 end
    local ok, plan = pcall(funds.Plan, funds)
    if not ok or type(plan) ~= "table" then return 0 end
    local total = 0
    for _, entry in ipairs(plan) do
        total = total + (entry.amount or 0) + (funds.POSTAGE or 0)
    end
    return total
end

--- Fill the goals in order from `purse`: each gets `have`, and a state:
--- "ready" (it can be paid), "saving", or "far" (levels away).
function GG.Fill(goals, purse)
    local left = math.max(0, purse or 0)
    local met = 0
    -- Goals that can be paid now are filled first, in order; one levels
    -- away takes only what they leave, so it never makes one you can
    -- afford today read as saving.
    local function Take(goal)
        local cost = math.max(0, goal.cost or 0)
        goal.have = math.min(left, cost)
        left = left - goal.have
        goal.short = cost - goal.have
    end
    for _, goal in ipairs(goals) do
        if not goal.level then Take(goal) end
    end
    for _, goal in ipairs(goals) do
        if goal.level then Take(goal) end
    end
    for _, goal in ipairs(goals) do
        if goal.level then
            goal.state = "far"
        elseif goal.short <= 0 then
            goal.state = "ready"
            met = met + 1
        else
            goal.state = "saving"
        end
    end
    return met, left
end

--- The character playing's goals: { goals, purse, aside, met, cap,
--- level }. Kept until the version, the purse, the level or the class
--- training moved.
function GG:Goals()
    local purse = Number(Call("GetMoney")) or 0
    local level = self.Level()
    local CT, funds = ns.ClassTraining, ns.Funds
    local key = ("%d:%d:%d:%d:%d"):format(self.version, purse, level, CT and CT.version or 0,
        funds and funds.version or 0)
    if self.goals and self.goalsKey == key then return self.goals end
    self.goalsKey = key

    local cap = self.MaxLevel()
    local result = { goals = {}, purse = purse, level = level, cap = cap }
    if self:IsOn() then
        local function Add(goal) result.goals[#result.goals + 1] = goal end
        local ok, goal = pcall(ClassGoal, level, cap)
        if ok and goal then Add(goal) end
        local listed, list = pcall(ProfessionGoals, level, cap)
        if listed and type(list) == "table" then
            for _, each in ipairs(list) do Add(each) end
        end
        ok, goal = pcall(RidingGoal, level, cap)
        if ok and goal then Add(goal) end
    end
    result.aside = math.min(purse, self.SetAside())
    result.met = self.Fill(result.goals, purse - result.aside)
    self.goals = result
    self:Note(result)
    return result
end

--------------------------------------------------------------------------------
-- Every character
--------------------------------------------------------------------------------

--- Write down this character's goals for All characters, only when they
--- changed.
function GG:Note(result)
    local guid = Text(Call("UnitGUID", "player"))
    if not guid then return end
    local goals = {}
    for _, goal in ipairs(result.goals) do
        goals[#goals + 1] = { kind = goal.kind, cost = goal.cost or 0, level = goal.level, label = goal.label }
    end
    local _, class = Call("UnitClass", "player")
    local className = Call("UnitClass", "player")
    local data = self:Data().characters
    local old = data[guid]
    local same = type(old) == "table" and old.level == result.level and old.money == result.purse
        and type(old.goals) == "table" and #old.goals == #goals
    if same then
        for index, goal in ipairs(goals) do
            local was = old.goals[index]
            if was.kind ~= goal.kind or was.cost ~= goal.cost or was.level ~= goal.level or was.label ~= goal.label then
                same = false
                break
            end
        end
    end
    if same then return end
    data[guid] = {
        name = Text(Call("UnitName", "player")), level = result.level, class = Text(class),
        className = Text(className), money = result.purse, goals = goals, at = Now(),
    }
end

--- Every character's goals, the character playing first: a list of {
--- key, name, level, className, isCurrent, goals (filled), met, money,
--- short (the first goal not met: its label and how short) }.
function GG:Everyone()
    local list = {}
    local me = Text(Call("UnitGUID", "player"))
    local mine = self:Goals()
    list[1] = {
        key = me, name = Text(Call("UnitName", "player")), level = mine.level, className = Text((Call("UnitClass", "player"))),
        isCurrent = true, goals = mine.goals, met = mine.met, money = mine.purse,
    }
    -- Gold as Tradeskills last saw it (All characters' own read of it)
    -- beats this addon's own note.
    local gold = {}
    for _, character in ipairs((ns.Everyone and ns.Everyone.characters) or {}) do
        if character.key and character.gold then gold[character.key] = character.gold end
    end
    local others = {}
    for guid, record in pairs(self:Data().characters) do
        if guid ~= me and type(record) == "table" and type(record.goals) == "table" then
            local goals = {}
            for index, goal in ipairs(record.goals) do
                goals[index] = { kind = goal.kind, cost = goal.cost, level = goal.level, label = goal.label }
            end
            local money = gold[guid] or record.money or 0
            others[#others + 1] = {
                key = guid, name = record.name, level = record.level, className = record.className,
                goals = goals, met = (GG.Fill(goals, money)), money = money, at = record.at,
            }
        end
    end
    table.sort(others, function(a, b) return (a.name or "") < (b.name or "") end)
    for _, entry in ipairs(others) do list[#list + 1] = entry end
    for _, entry in ipairs(list) do
        for _, goal in ipairs(entry.goals) do
            if goal.state ~= "ready" then
                entry.next = goal
                break
            end
        end
    end
    return list
end

--------------------------------------------------------------------------------
-- At a trainer
--------------------------------------------------------------------------------

--- The spells this keeps prices for: { [lower case name] = spellID }.
function GG:Names()
    if self.names then return self.names end
    local names = {}
    local function Add(id)
        local name = GG.SpellName(id)
        -- The first spell of a name wins: the riding spells share theirs.
        if name and not names[name:lower()] then names[name:lower()] = id end
    end
    for _, ranks in pairs(self.RANKS) do
        for index = 1, 3 do
            if ranks[index] then Add(ranks[index][1]) end
        end
    end
    for _, riding in ipairs(self.RIDING) do
        for _, id in ipairs(riding.spells) do Add(id) end
    end
    self.names = names
    return names
end

--- Which kept spell a trainer's line teaches, or nil.
function GG:ServiceSpell(index, name, rank)
    local data = Call("C_TooltipInfo.GetTrainerService", index)
    local id = type(data) == "table" and Number(data.id) or nil
    local names = self:Names()
    if id then
        for _, known in pairs(names) do
            if known == id then return id end
        end
    end
    name, rank = Text(name), Text(rank)
    if not name then return nil end
    -- The riding spells share one name; the first listed is kept.
    return names[name:lower()] or (rank and (names[(rank .. " " .. name):lower()] or names[(name .. " " .. rank):lower()]))
end

--- Read the open trainer's prices for professions and riding.
function GG:ReadTrainer()
    -- A class trainer teaches neither.
    local CT = ns.ClassTraining
    if CT and CT.atClassTrainer then return end
    local count = Number(Call("GetNumTrainerServices")) or 0
    if count == 0 then return end
    local hidden = Has("GetTrainerServiceTypeFilter") and Has("SetTrainerServiceTypeFilter")
        and not Call("GetTrainerServiceTypeFilter", "unavailable")
    if hidden then
        if CT then CT.flipping = true end
        Call("SetTrainerServiceTypeFilter", "unavailable", 1)
        count = Number(Call("GetNumTrainerServices")) or 0
    end
    local prices, found = self:Data().prices, false
    for index = 1, count do
        local name, rank, kind = Call("GetTrainerServiceInfo", index)
        if kind ~= "header" then
            local spell = self:ServiceSpell(index, name, rank)
            local cost = Number((Call("GetTrainerServiceCost", index)))
            if spell and cost and cost >= 0 then
                prices[spell] = { cost = cost, level = Number(Call("GetTrainerServiceLevelReq", index)), at = Now() }
                found = true
            end
        end
    end
    if hidden then
        Call("SetTrainerServiceTypeFilter", "unavailable", 0)
        C_Timer.After(0.5, function() if CT then CT.flipping = false end end)
    end
    if found then self:Changed() end
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- One line for the probe.
function GG:ProbeText()
    local parts = {}
    for _, name in ipairs({ "GetMaxLevelForPlayerExpansion", "GetMaxPlayerLevel",
        "C_TradeSkillUI.GetAllProfessionTradeSkillLines", "C_TradeSkillUI.GetProfessionInfoBySkillLineID" }) do
        parts[#parts + 1] = name .. (Has(name) and " yes" or " no")
    end
    local professions = 0
    for _ in pairs(GG.Professions()) do professions = professions + 1 end
    local goals = self:Goals()
    return ("%s; level cap %d, %d professions, %d goals, Tradeskills recipes %s"):format(
        table.concat(parts, ", "), goals.cap, professions, #goals.goals, LearnCost() and "yes" or "no")
end

--- The goals in chat.
function GG:Report()
    local result = self:Goals()
    local money = ns.Items and ns.Items.FormatMoney or tostring
    if not self:IsOn() then
        ns.Print(L["gold goals are turned off in Settings."])
        return
    end
    if #result.goals == 0 then
        ns.Print(L["no gold goals right now."])
        return
    end
    ns.Print(L.Format("gold goals, %s in your purse:", money(result.purse)))
    if result.aside > 0 then
        ns.PrintRaw(L.Format("   %s is set aside for your other characters.", money(result.aside)))
    end
    for _, goal in ipairs(result.goals) do
        local state = goal.state == "ready" and L["ready"]
            or goal.state == "far" and L.Format("at level %d", goal.level)
            or L.Format("%s to go", money(goal.short))
        ns.PrintRaw(("   %s: %s / %s, %s"):format(goal.label, money(goal.have), money(goal.cost), state))
    end
    local ok, everyone = pcall(self.Everyone, self)
    if ok and type(everyone) == "table" and #everyone > 1 then
        ns.PrintRaw(L["   Your other characters:"])
        for index = 2, #everyone do
            local entry = everyone[index]
            ns.PrintRaw(L.Format("      %s: %d of %d goals met", entry.name or "?", entry.met or 0, #(entry.goals or {})))
        end
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function GG:Soon()
    if self.waiting then return end
    self.waiting = true
    C_Timer.After(GG.SETTLE, function()
        GG.waiting = false
        GG:Changed()
        if ns.UI and ns.UI.IsShown and ns.UI:IsShown() then ns.UI:Refresh() end
    end)
end

function GG:OnEnable()
    local function Soon() GG:Soon() end
    for _, event in ipairs({ "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "NEW_RECIPE_LEARNED",
        "PLAYER_LEVEL_UP", "TRADE_SKILL_LIST_UPDATE" }) do
        ns.RegisterEvent(self, event, Soon)
    end
    ns.RegisterEvent(self, "TRAINER_SHOW", function()
        -- After the class trainer's read, which turns the filter and back.
        C_Timer.After(0.7, function() GG:ReadTrainer() end)
    end)
    ns.RegisterEvent(self, "TRAINER_CLOSED", Soon)
    ns.RegisterEvent(self, "PLAYER_LOGOUT", function() pcall(GG.Goals, GG) end)
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

ns.RegisterCommand("goals", L["list your gold goals: class spells, profession training and riding (goals on|off to show them or not)"], function(rest)
    local word = (rest or ""):lower():match("^%s*(%a+)")
    if word == "on" or word == "off" then
        GG:SetOn(word == "on")
        ns.Print(word == "on" and L["gold goals are on."] or L["gold goals are off."])
        if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
        return
    end
    GG:Report()
end)
