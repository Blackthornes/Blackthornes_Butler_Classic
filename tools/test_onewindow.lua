-- Butler's pages in the one Blackthornes window (UI/ButlerTabs.lua, the
-- owner said build it, 2026-10-30).
--
-- What must hold:
--   1. On unless unticked; unticked, the Butler window opens in its own
--      place.
--   2. Ticked, opening Butler opens the one window on Butler, with the
--      Butler window laid into its area, bare of its own rim and grip.
--   3. Settings opens in the same area; one tab up at a time.
--   4. The secure buttons still dock inside the Butler window.
--   5. Closing the one window gives the pages back their own place.
--   6. "One Window:" on the General page writes every save.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("onewindow")

_G.BlackthornesWindow = nil
local ns = env.Load()
local UI, SettingsUI, Tabs, SW = ns.UI, ns.SettingsUI, ns.ButlerTabs, ns.SharedWindow

ns.MinimapButton.button = env.Stub()
ns.MinimapButton:JoinShared()
local hub = _G.BlackthornesWindow
suite.check("Butler joins with its pages", hub.entries.butler and hub.entries.butler.host == Tabs.host)
suite.check("the one window is Butler's own copy", Tabs.One() == SW)

-- 1.
ns.db.oneWindow = nil
suite.check("on unless unticked", SW.On())
ns.db.oneWindow = false
UI:Show("bags")
suite.check("off: the Butler window opens by itself", UI.frame:IsShown() and not Tabs:Hosted())
suite.check("in its own place", UI.frame:GetParent() ~= (hub.frame and hub.frame.area))
UI:Hide()

-- 2.
SW.SetOn(true)
UI:Show("bags")
local area = hub.frame and hub.frame.area
suite.check("on: the one window opens", hub.frame and hub.frame:IsShown())
suite.check("on Butler", hub.current == hub.entries.butler and ns.db.oneWindowPick == "butler")
suite.check("Butler's pages are in it", Tabs:Hosted() and UI.frame:GetParent() == area)
suite.check("the Butler window shows", UI.frame:IsShown())
suite.check("without its own rim", UI.trim and not UI.trim:IsShown())
suite.check("or its own size grip", UI.sizeGrip and not UI.sizeGrip:IsShown())

-- 3.
Tabs:Open("settings")
suite.check("Settings is in the same area", SettingsUI.frame:GetParent() == area and SettingsUI.frame:IsShown())
suite.check("and the bags stepped aside", not UI.frame:IsShown())
suite.check("one tab up", Tabs:Current() == "settings")
Tabs:Open("all")
suite.check("All Characters back in the area", UI.frame:IsShown() and UI.view == "all"
    and UI.frame:GetParent() == area)

-- 4.
local button = env.Stub()
suite.check("a secure button docks in the Butler window", UI:Dock(button) and button:GetParent() == UI.frame)
UI:Undock()
suite.check("and goes back to UIParent for a fight", button:GetParent() == UIParent)

-- 5.
ns.db.windowLeft, ns.db.windowTop = 300, 650
hub.frame:Hide()
local onHide = hub.frame:GetScript("OnHide")
if onHide then onHide(hub.frame) end
suite.check("closing it lets Butler go", not Tabs:Hosted() and hub.current == nil)
suite.check("the Butler window is back on its own", UI.frame:GetParent() == UIParent and not UI.frame:IsShown())
suite.check("with its rim", UI.trim:IsShown() and UI.sizeGrip:IsShown())
suite.check("Settings too", SettingsUI.frame:GetParent() == UIParent)
local width = Tabs:Size()
suite.check("at the shared size", UI.frame:GetWidth() == width, UI.frame:GetWidth(), width)

-- 6.
local other = {}
SW:Join({ key = "pets", order = 3, name = "Pets", db = function() return other end })
SettingsUI:Show()
suite.check("Settings opens in the one window", Tabs:Hosted() and SettingsUI.frame:GetParent() == hub.frame.area)
SettingsUI.controls.oneWindow:SetChecked(false)
SettingsUI:SetOneWindow(false)
local onHideAgain = hub.frame:GetScript("OnHide")
if onHideAgain then onHideAgain(hub.frame) end
suite.check("unticked in every save", ns.db.oneWindow == false and other.oneWindow == false)
SettingsUI:Show()
suite.check("Settings opens on its own again", not Tabs:Hosted() and SettingsUI.frame:GetParent() == UIParent
    and SettingsUI.frame:IsShown())
SettingsUI:SetOneWindow(true)
suite.check("ticked again in every save", ns.db.oneWindow == true and other.oneWindow == true)
suite.check("and Settings moves into the one window", Tabs:Hosted() and SettingsUI.frame:GetParent() == hub.frame.area)

_G.BlackthornesWindow = nil
suite.done()
