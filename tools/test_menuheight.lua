-- The item menu is tall enough for every row it shows: each choice that
-- shows (Always Auction among them) counts toward its height, so the last
-- row never hangs below the menu's edge.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("menuheight")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 901, name = "Tattered Feather", count = 5, price = 30, stack = 20 },
    { bag = 0, slot = 2, id = 902, name = "Bound Trinket", count = 1, price = 50, stack = 1, bound = true },
})
_G.UnitGUID = function(unit) if unit == "player" then return "Player-1-0000AAAA" end end
_G.UnitName = function() return "Ana Thornfield" end
env.Enable(ns)

local Verdicts, UI = ns.Verdicts, ns.UI
local MENU_ROW, TOP = 24, 30

local function RowFor(name)
    UI:Hide()
    UI:Show()
    for _, group in ipairs(Verdicts:Groups()) do
        for _, row in ipairs(group.rows) do
            if row.name == name then return row end
        end
    end
end

local function Shown(menu)
    local count = 0
    for _, key in ipairs({ "keep", "sell", "auction", "bank", "disenchant", "bought", "mail",
        "hold", "holdAll", "keepHere", "keepAcross", "decide" }) do
        if menu[key] and menu[key]:IsShown() then count = count + 1 end
    end
    return count
end

local function Check(label, name, choice)
    Verdicts:SetChoice((name == "Tattered Feather") and 901 or 902, choice)
    local row = RowFor(name)
    suite.check(label .. ": the row is there", row ~= nil)
    if not row then return end
    UI:ShowMenu(row)
    local menu = UI.menu
    local want = TOP + Shown(menu) * MENU_ROW
    suite.check(label .. ": tall enough for every row", menu:GetHeight() == want,
        tostring(menu:GetHeight()) .. " vs " .. want)
    return menu
end

local menu = Check("an item for the auction house", "Tattered Feather", nil)
suite.check("Always Auction shows for it", menu and menu.auction:IsShown())
Check("on the Always auction list", "Tattered Feather", "auction")
Check("on the Always sell list", "Tattered Feather", "sell")
local bound = Check("a soulbound item", "Bound Trinket", nil)
suite.check("no Always Auction for soulbound", bound and not bound.auction:IsShown())

suite.done()
