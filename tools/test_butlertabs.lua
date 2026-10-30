-- The Butler window's tabs (the owner, 2026-10-27: "Last tab on bottom
-- right will always be settings").
--
-- What must hold:
--   1. The tabs are Your Bags, All Characters and Settings, Settings last
--      and flush right on the strip.
--   2. A tab opens in the place of the one up, at the same size, and only
--      one shows.
--   3. Stepping from one tab to another says no closing line and lets
--      nothing go.
--   4. The header has no Settings button any more.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("butlertabs")

local ns = env.Load()
local UI, SettingsUI, Tabs = ns.UI, ns.SettingsUI, ns.ButlerTabs

-- 1.
local list = Tabs.Tabs()
suite.check("three tabs", #list == 3)
suite.check("Your Bags first, All Characters second",
    list[1].key == "bags" and list[2].key == "all")
suite.check("Settings last, on the right", list[3].key == "settings" and list[3].right == true)

UI:Show("bags")
local strip = UI.tabStrip
suite.check("the window has the strip", strip ~= nil)
local bags, settings
for _, button in ipairs(strip and strip.tabs or {}) do
    if button.key == "bags" then bags = button end
    if button.key == "settings" then settings = button end
end
suite.check("Your Bags is lit", strip and strip.selected == "bags", strip and strip.selected)
suite.check("Settings sits past the others",
    settings and bags and settings.right == true and (settings.left or 0) > (bags.left or 0))

-- 2.
UI.frame._left, UI.frame._top = 200, 700
local said = 0
local say = UI.Say
UI.Say = function(...) said = said + 1 end
Tabs:Open("settings")
suite.check("Settings opens", SettingsUI.frame:IsShown())
suite.check("and the bags step aside", not UI.frame:IsShown())
suite.check("in their place", ns.db.windowLeft == 200 and ns.db.windowTop == 700)
local width, height = Tabs:Size()
suite.check("at the shared size", SettingsUI.frame:GetWidth() == width and SettingsUI.frame:GetHeight() == height
    and UI.frame:GetWidth() == width, SettingsUI.frame:GetWidth(), width)
suite.check("Settings is lit on its own strip", SettingsUI.tabStrip and SettingsUI.tabStrip.selected == "settings")
suite.check("one tab up", Tabs:Current() == "settings")

-- 3.
suite.check("stepping over said nothing", said == 0, said)
Tabs:Open("all")
suite.check("All Characters opens", UI.frame:IsShown() and UI.view == "all")
suite.check("and Settings steps aside", not SettingsUI.frame:IsShown())
suite.check("lit on the strip", UI.tabStrip.selected == "all")
suite.check("still nothing said", said == 0, said)
UI.Say = say

-- The minimap's right-click still opens Settings, and again closes it.
SettingsUI:Toggle()
suite.check("Settings opens from the minimap", SettingsUI.frame:IsShown() and not UI.frame:IsShown())
SettingsUI:Toggle()
suite.check("and closes", not SettingsUI.frame:IsShown())

-- 4.
suite.check("no Settings button in the header", rawget(UI, "settingsButton") == nil)

suite.done()
