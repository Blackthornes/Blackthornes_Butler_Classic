-- Craft Details (Trent said build it from a mockup, 2026-11-14): with the
-- box ticked, Butler's tooltip line for a Craft verdict names what to make,
-- and a grey line under it says what else you carry, what you still need
-- and about how much more it earns than selling.
--
-- What must hold:
--   1. Off unless ticked: the line stays "Butler: Craft".
--   2. Ticked: "Butler: Craft PRODUCT" and the earnings under it.
--   3. Missing materials read "Needs N NAME."; carried ones "With NAME."
--   4. The tick box and /bbutler craftdetails change the same saved value.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("craftdetails")

local ns = env.Load()
local bags = env.FakeBags({
    { bag = 0, slot = 1, id = 2592, name = "Wool Cloth", quality = 1, price = 33, count = 12 },
    { bag = 0, slot = 2, id = 10940, name = "Strange Dust", quality = 1, price = 10, count = 6 },
})
bags.info[17034] = { id = 17034, name = "Maple Seed", price = 5 }

local postCalls = {}
_G.Enum = { TooltipDataType = { Item = 0 } }
_G.TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn) postCalls[#postCalls + 1] = { kind = kind, fn = fn } end,
}
local function Double(self, left, right) self._lines[#self._lines + 1] = left .. " | " .. right end
_G.GameTooltip.AddDoubleLine = Double
_G.GameTooltip.AddLine = function(self, t) self._lines[#self._lines + 1] = t end

env.Enable(ns)
env.Fire("PLAYER_ENTERING_WORLD")

local seedsCarried = false
_G.BlackthornesTS = { Butler = {
    Advise = function() return { auction = 40 } end,
    CraftFor = function(_, id, carried)
        if id == 2592 then
            return { recipeID = 2964, name = "Bolt of Woolen Cloth", itemID = 2997, per = 3,
                crafts = math.floor(carried / 3), perItem = 120, needs = {}, others = {} }
        elseif id == 10940 then
            if seedsCarried then
                return { recipeID = 7836, name = "Minor Mana Oil", itemID = 20744, per = 3,
                    crafts = 2, perItem = 120, needs = {}, others = { { itemID = 17034, count = 2 } } }
            end
            return { recipeID = 7836, name = "Minor Mana Oil", itemID = 20744, per = 3,
                crafts = 2, perItem = 120, needs = { { itemID = 17034, count = 2 } },
                others = { { itemID = 17034, count = 2 } } }
        end
    end,
    QueueCraft = function() return true end,
} }

ns.UI:Show()
ns.Verdicts:SetCraftPays(true)
ns.Verdicts:Changed(true)

local function Slot(slot)
    return env.Stub({ GetBagID = function() return 0 end, GetID = function() return slot end })
end
local function Hover(itemID, slot)
    GameTooltip._lines = {}
    GameTooltip.GetOwner = function() return Slot(slot) end
    for _, call in ipairs(postCalls) do call.fn(GameTooltip, { id = itemID }) end
    return GameTooltip._lines
end
local function Joined(lines) return env.Plain(table.concat(lines, "\n")) end

-- 1.
suite.check("off unless ticked", ns.db.craftDetails ~= true and not ns.VerdictTip:DetailsOn())
local text = Joined(Hover(2592, 1))
suite.check("off: the line stays Butler: Craft", text:find("Butler: Craft |", 1, true) ~= nil, text)
suite.check("off: no product named", text:find("Bolt of Woolen Cloth", 1, true) == nil, text)

-- 4 and 2.
ns.HandleSlash("craftdetails on")
suite.check("/bbutler craftdetails on ticks it", ns.db.craftDetails == true)
text = Joined(Hover(2592, 1))
suite.check("on: names the product", text:find("Butler: Craft Bolt of Woolen Cloth", 1, true) ~= nil, text)
suite.check("on: says what it earns",
    text:find("About " .. env.Plain(ns.Items.FormatMoney(960)) .. " more than selling it.", 1, true) ~= nil, text)

-- 3.
text = Joined(Hover(10940, 2))
suite.check("missing seeds are named", text:find("Needs 2 Maple Seed.", 1, true) ~= nil, text)
suite.check("not also as carried", text:find("With Maple Seed.", 1, true) == nil, text)
seedsCarried = true
ns.Verdicts:Changed(true)
text = Joined(Hover(10940, 2))
suite.check("carried seeds read With", text:find("With Maple Seed.", 1, true) ~= nil, text)

-- 4.
ns.HandleSlash("craftdetails off")
suite.check("/bbutler craftdetails off unticks it", ns.db.craftDetails == false)
ns.VerdictTip:SetDetails(true)
suite.check("Settings' box saves the same key", ns.db.craftDetails == true)

suite.done()
