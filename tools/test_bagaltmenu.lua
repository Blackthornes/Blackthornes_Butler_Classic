-- Alt + right-click on a Bags window square opens Butler's item menu (a
-- player asked, the owner said build it, 2026-11-12).
--
-- What must hold:
--   1. Alt + right-click on a square opens the menu for that slot's item.
--   2. A plain right-click, Alt + left-click, a fight or another tab open
--      nothing.
--   3. A small line at the foot says how, on the Bags tab only.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("bagaltmenu")

local ns = env.Load()
env.FakeBags({
    { bag = 0, slot = 1, id = 801, name = "Broken Fang", quality = 0, price = 12, count = 3 },
    { bag = 0, slot = 2, id = 802, name = "Linen Cloth", quality = 1, price = 13, count = 20, class = 7 },
})
env.Enable(ns)
ns.Bags:Scan()

local BagWindow, UI = ns.BagWindow, ns.UI
local shown
local before = UI.ShowMenu
UI.ShowMenu = function(_, data) shown = data end

local alt = false
_G.IsAltKeyDown = function() return alt end
local fighting = false
local combat = _G.InCombatLockdown
_G.InCombatLockdown = function() return fighting end

local square = { bfrBag = 0, bfrSlot = 2 }
BagWindow.tab = "bags"

-- 1.
alt = true
suite.check("Alt + right-click opens the menu", BagWindow:AltClick(square, "RightButton") == true)
suite.check("for that slot's item", shown and shown.itemID == 802)
suite.check("with its name", shown and shown.name == "Linen Cloth")

-- 2.
shown = nil
alt = false
suite.check("a plain right-click opens nothing", not BagWindow:AltClick(square, "RightButton") and shown == nil)
alt = true
suite.check("Alt + left-click opens nothing", not BagWindow:AltClick(square, "LeftButton") and shown == nil)
fighting = true
suite.check("nothing in a fight", not BagWindow:AltClick(square, "RightButton") and shown == nil)
fighting = false
BagWindow.tab = "bank"
suite.check("nothing on another tab", not BagWindow:AltClick(square, "RightButton") and shown == nil)
BagWindow.tab = "bags"
suite.check("nothing for an empty slot", not BagWindow:AltClick({ bfrBag = 0, bfrSlot = 9 }, "RightButton"))

-- With no row laid out, the slot alone is enough.
local data = BagWindow.MenuData({ itemID = 5, link = "|cffffffff|Hitem:5|h[Thing]|h|r", quality = 1, bound = true, count = 2 })
suite.check("a slot alone still makes the menu's data", data and data.itemID == 5 and data.bound == true)

-- 3.
local key = "Alt + right-click an item to choose what Butler does with it."
suite.check("the line is in every language", (function()
    for _, code in ipairs({ "deDE", "zhCN", "frFR", "esES", "ruRU" }) do
        local f = io.open(lfs_cwd .. "/Locale/" .. code .. ".lua")
        local text = f and f:read("*a") or ""
        if f then f:close() end
        if not text:find(key, 1, true) then return false end
    end
    return true
end)())
if not BagWindow.frame then pcall(BagWindow.Build, BagWindow) end
suite.check("the window has the line", BagWindow.hintLabel ~= nil)
if BagWindow.frame and BagWindow.hintLabel then
    BagWindow.tab = "bags"
    BagWindow:UpdateFoot()
    suite.check("the line shows on the Bags tab", BagWindow.hintLabel:IsShown())
    BagWindow.tab = "everyone"
    BagWindow:UpdateFoot()
    suite.check("and not on the others", not BagWindow.hintLabel:IsShown())
    BagWindow.tab = "bags"
end

UI.ShowMenu = before
_G.IsAltKeyDown = nil
_G.InCombatLockdown = combat
suite.done()
