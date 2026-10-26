-- Blackthornes Butler -- Logic/Sisters.lua
-- What the other four Blackthornes addons say about an item.
--
-- Each sister has one call made for Butler (see CLAUDE.md, "How Butler
-- talks to the other four"), read only, inside a pcall, with no TOC
-- dependency. A sister that is not loaded, has no Butler call yet, raises
-- or answers something other than a table is simply not asked: its steps
-- in Logic/Verdicts.lua are skipped and Butler judges as it did on its own.
--
-- Answers are not kept here. Verdicts:Judge keeps its verdict per item
-- until Verdicts.version moves, which it does whenever the Butler window
-- opens, so each sister is asked about an item once per look.

local _, ns = ...

local L = ns.L

local Sisters = ns.NewModule("Sisters")

-- name = the global and whether Advise takes the item ID or the link.
-- Equipment also takes the bag and slot, which is how it tells soulbound
-- gear apart (its sell coin).
Sisters.LIST = {
    ts = { name = "Tradeskills", global = "BlackthornesTS", byLink = false },
    equipment = { name = "Equipment", global = "BlackthornesEquipment", byLink = true },
    farmer = { name = "Farmer", global = "BlackthornesFarmer", byLink = false },
    pets = { name = "Pets", global = "BlackthornesPets", byLink = false },
}

--- The sister's Butler table, when it is loaded and answers Butler.
function Sisters.Butler(key)
    local info = Sisters.LIST[key]
    if not info then return nil end
    local global = rawget(_G, info.global)
    if type(global) ~= "table" then return nil end
    local butler = rawget(global, "Butler")
    if type(butler) ~= "table" or type(butler.Advise) ~= "function" then return nil end
    return butler
end

--- What one sister says about a carried item (`entry` from Bags), or nil.
function Sisters:Ask(key, entry)
    local butler = Sisters.Butler(key)
    if not butler then return nil end
    -- Tradeskills takes the link too once it says so (TAKES_LINK), so a
    -- random suffix ("of the Monkey") is priced as that suffix sells.
    local byLink = Sisters.LIST[key].byLink or rawget(butler, "TAKES_LINK") == true
    local arg = byLink and (entry.link or entry.itemID) or entry.itemID
    if arg == nil then return nil end
    local ok, answer
    if key == "equipment" then
        ok, answer = pcall(butler.Advise, butler, arg, entry.bag, entry.slot)
    else
        ok, answer = pcall(butler.Advise, butler, arg)
    end
    if not ok then
        if ns.Debug then ns.Debug("Butler:Advise raised in " .. Sisters.LIST[key].name) end
        return nil
    end
    if type(answer) ~= "table" then return nil end
    return answer
end

--- Everything the four say about an item: { ts, equipment, farmer, pets },
--- each a table or nil.
function Sisters:AskAll(entry)
    return {
        ts = self:Ask("ts", entry),
        equipment = self:Ask("equipment", entry),
        farmer = self:Ask("farmer", entry),
        pets = self:Ask("pets", entry),
    }
end

--------------------------------------------------------------------------------
-- Bought to disenchant (Tradeskills keeps the marks, 2026-10-11)
--------------------------------------------------------------------------------

--- Can Tradeskills mark an item bought to disenchant?
function Sisters.CanMarkBought()
    local butler = Sisters.Butler("ts")
    return butler ~= nil and type(butler.SetBoughtToDisenchant) == "function"
end

--- Mark `count` of an item bought to disenchant, or take the mark off.
-- @return true, or false and why
function Sisters:MarkBought(itemID, on, count)
    if not Sisters.CanMarkBought() then return false, L["Blackthornes Tradeskills isn't loaded."] end
    local butler = Sisters.Butler("ts")
    local ok, done, why = pcall(butler.SetBoughtToDisenchant, butler, itemID, on and true or false, count)
    if not ok then return false, L["Tradeskills couldn't mark it."] end
    return done == true, why
end

--------------------------------------------------------------------------------
-- Craft When It Pays More (a player asked, the owner said build it, 2026-10-19)
--------------------------------------------------------------------------------

--- The known craft that makes one of an item worth the most, from
--- Tradeskills, or nil. `carried` is how many the bags hold. The answer is
--- checked field by field: { recipeID, name, crafts, per, perItem, needs }.
--- `skip` ({ [recipeID] = true-ish }) names recipes to pass over; an older
--- Tradeskills ignores it, and Verdicts still checks the answer.
function Sisters:CraftFor(itemID, carried, skip)
    local butler = Sisters.Butler("ts")
    if not (butler and type(butler.CraftFor) == "function") then return nil end
    local ok, answer = pcall(butler.CraftFor, butler, itemID, carried, skip)
    if not ok or type(answer) ~= "table" then return nil end
    local recipeID, crafts, perItem = Sisters.Number(answer, "recipeID"), Sisters.Number(answer, "crafts"),
        Sisters.Number(answer, "perItem")
    local name, per = Sisters.String(answer, "name"), Sisters.Number(answer, "per") or 1
    if not (recipeID and crafts and crafts >= 1 and perItem and name and per >= 1) then return nil end
    local needs = {}
    if type(answer.needs) == "table" then
        for _, need in ipairs(answer.needs) do
            local id, count = Sisters.Number(need, "itemID"), Sisters.Number(need, "count")
            if id and count and count > 0 then needs[#needs + 1] = { itemID = id, count = count } end
        end
    end
    return { recipeID = recipeID, name = name, crafts = math.floor(crafts), per = math.floor(per),
        perItem = perItem, needs = needs }
end

--- Queue at least `crafts` of a recipe in Tradeskills.
-- @return true, or false
function Sisters:QueueCraft(recipeID, crafts)
    local butler = Sisters.Butler("ts")
    if not (butler and type(butler.QueueCraft) == "function") then return false end
    local ok, done = pcall(butler.QueueCraft, butler, recipeID, crafts)
    return ok and done == true
end

--------------------------------------------------------------------------------
-- Reading answers safely: a field of the wrong type counts as not given.
--------------------------------------------------------------------------------

function Sisters.Number(answer, field)
    local value = answer and answer[field]
    if type(value) == "number" and value == value then return value end
    return nil
end

function Sisters.String(answer, field)
    local value = answer and answer[field]
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

function Sisters.True(answer, field)
    return answer ~= nil and answer[field] == true
end
