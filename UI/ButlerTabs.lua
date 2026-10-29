-- Blackthornes Butler -- UI/ButlerTabs.lua
-- The Butler window's tabs, hanging below it: Your Bags, All Characters
-- and, last on the right, Settings (the owner, 2026-10-27: "Last tab on
-- bottom right will always be settings", from a mockup he said build).
-- Pets' UI/PetsTabs.lua, brought over and trimmed.
--
-- Your Bags and All Characters are the two views of one window
-- (UI/MainWindow.lua). Settings (UI/Settings.lua) is its own window
-- underneath, but it opens in the Butler window's place, at the same size
-- and scale, so the three read as one window. The size is the most any
-- tab needs (`ButlerTabs:Need`), the scale is `windowScale`. The place a
-- tab opens is the one the last stood, top left corner on top left corner,
-- kept account wide in `windowLeft` and `windowTop` (screen units from the
-- bottom left; never rename them).

local _, ns = ...

local L = ns.L
local Widgets = ns.Widgets

local ButlerTabs = ns.NewModule("ButlerTabs")

-- How far in from the window's left edge the first tab hangs, clear of
-- the corner gem.
ButlerTabs.INSET = 34

-- How far below the window the tabs reach, kept on screen with it.
ButlerTabs.REACH = 32

-- The usual size, the Butler window's, unless a tab needs more.
ButlerTabs.WIDTH = 620
ButlerTabs.HEIGHT = 500

--- The tabs, in order. Settings is always last, flush right.
function ButlerTabs.Tabs()
    return {
        { key = "bags", text = L["Your Bags"] },
        { key = "all", text = L["All Characters"] },
        { key = "settings", text = L["Settings"], right = true },
    }
end

--- The window behind a tab.
local function Owner(key)
    if key == "settings" then return ns.SettingsUI end
    if key == "bags" or key == "all" then return ns.UI end
    return nil
end
ButlerTabs.Owner = Owner

-- The windows, each once.
local function Windows()
    return { ns.UI, ns.SettingsUI }
end

local function FrameOf(window)
    return window and rawget(window, "frame")
end

local function Shown(frame)
    if not frame then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

--- The tab a window shows now.
function ButlerTabs:KeyOf(window)
    if window == ns.SettingsUI then return "settings" end
    if window == ns.UI then return rawget(window, "view") == "all" and "all" or "bags" end
    return nil
end

--- The tab showing now and its window, or nil.
function ButlerTabs:Current()
    for _, window in ipairs(Windows()) do
        if Shown(FrameOf(window)) then return self:KeyOf(window), window end
    end
    return nil
end

--- Is any of Butler's tabs up?
function ButlerTabs:AnyShown()
    return self:Current() ~= nil
end

--- Hang the tabs under a window. Called as each window is built.
function ButlerTabs:Attach(window)
    local frame = FrameOf(window)
    if not (frame and Widgets and Widgets.CreateTabStrip) then return nil end
    local ok, width = pcall(frame.GetWidth, frame)
    if not (ok and type(width) == "number" and width > 0) then width = ButlerTabs.WIDTH end
    local strip = Widgets.CreateTabStrip(frame, ButlerTabs.Tabs(), function(picked)
        ButlerTabs:Open(picked)
    end, { width = width - 2 * ButlerTabs.INSET, hanging = true })
    strip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", ButlerTabs.INSET, 0)
    window.tabStrip = strip
    self:Light(window)

    -- Kept on screen tabs and all.
    local trim = rawget(window, "trim")
    if trim and ns.Titanforged and ns.Titanforged.Reach and frame.SetClampRectInsets then
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        frame:SetClampRectInsets(-left, right, top, -math.max(bottom or 0, ButlerTabs.REACH))
    end
    self:Fit(window)
    return strip
end

--- Light the tab a window shows on its own strip.
function ButlerTabs:Light(window)
    local strip = window and rawget(window, "tabStrip")
    local key = self:KeyOf(window)
    if strip and strip.Select and key and strip.selected ~= key then strip:Select(key) end
end

--------------------------------------------------------------------------------
-- The one size
--------------------------------------------------------------------------------

-- What each window needs at least, { width, height }, as it last said.
ButlerTabs.needs = {}

--- The size every tab shares: the usual one, or the most any tab needs.
function ButlerTabs:Size()
    local width, height = ButlerTabs.WIDTH, ButlerTabs.HEIGHT
    for _, need in pairs(self.needs) do
        if need[1] and need[1] > width then width = need[1] end
        if need[2] and need[2] > height then height = need[2] end
    end
    return math.ceil(width), math.ceil(height)
end

--- Size one window to the shared size, its top left corner kept where it
--- is.
function ButlerTabs:Fit(window)
    local frame = FrameOf(window)
    if not frame then return end
    local width, height = self:Size()
    local okW, oldW = pcall(frame.GetWidth, frame)
    local okH, oldH = pcall(frame.GetHeight, frame)
    if okW and okH and oldW == width and oldH == height then return end
    local left, top
    if Shown(frame) then
        local okL, l = pcall(frame.GetLeft, frame)
        local okT, t = pcall(frame.GetTop, frame)
        if okL and okT and type(l) == "number" and type(t) == "number" then left, top = l, t end
    end
    frame:SetWidth(width)
    frame:SetHeight(height)
    if left then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    local strip = rawget(window, "tabStrip")
    if strip and strip.SetRoom and okW and oldW ~= width then strip:SetRoom(width - 2 * ButlerTabs.INSET) end
    if type(window.OnTabSize) == "function" then window:OnTabSize(width, height) end
end

--- Size every window built so far.
function ButlerTabs:FitAll()
    for _, window in ipairs(Windows()) do self:Fit(window) end
end

--- A window says how much room it needs; nil for either keeps the usual.
--- Every window follows.
function ButlerTabs:Need(key, width, height)
    self.needs[key] = { width, height }
    self:FitAll()
end

--- Give a window the shared scale, which the Butler window's size grip
--- sets.
function ButlerTabs.ApplyScale(frame)
    if not (frame and ns.UI and ns.UI.GetWindowScale) then return end
    local ok, scale = pcall(ns.UI.GetWindowScale, ns.UI)
    if ok and type(scale) == "number" and scale > 0 then
        local okNow, now = pcall(frame.GetScale, frame)
        if not (okNow and now == scale) then frame:SetScale(scale) end
    end
end

--------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------

--- Open a tab. The tab showing already stays as it is.
function ButlerTabs:Open(key)
    if key == "settings" then
        if ns.SettingsUI then ns.SettingsUI:Show() end
    elseif ns.UI then
        ns.UI:Show(key == "all" and "all" or "bags")
    end
    self:Light(Owner(key))
end

--- Close the whole window, whichever tab is up.
function ButlerTabs:Close()
    local _, window = self:Current()
    if window and window.Hide then window:Hide() end
end

--------------------------------------------------------------------------------
-- The one place
--------------------------------------------------------------------------------

local function ScaleOf(frame)
    local ok, scale = pcall(frame.GetScale, frame)
    return ok and type(scale) == "number" and scale > 0 and scale or 1
end

--- Where a window's top left corner is, in screen units, or nil.
function ButlerTabs.TopLeft(frame)
    local okLeft, left = pcall(frame.GetLeft, frame)
    local okTop, top = pcall(frame.GetTop, frame)
    if not (okLeft and okTop and type(left) == "number" and type(top) == "number") then return nil end
    local scale = ScaleOf(frame)
    return left * scale, top * scale
end

--- Put a window's top left corner at a place in screen units.
function ButlerTabs.PlaceAt(frame, left, top)
    local scale = ScaleOf(frame)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
end

--- Keep where a window stands as the place every tab opens.
function ButlerTabs:Save(frame)
    if not (ns.db and frame) then return end
    local left, top = ButlerTabs.TopLeft(frame)
    if left then ns.db.windowLeft, ns.db.windowTop = left, top end
end

--- A window opened at its own old place: anchor it by its top left corner,
--- so a change of height keeps its top still, and keep that as the place.
function ButlerTabs:Settle(frame)
    if not frame then return end
    local left, top = ButlerTabs.TopLeft(frame)
    if not left then return end
    ButlerTabs.PlaceAt(frame, left, top)
    if ns.db then ns.db.windowLeft, ns.db.windowTop = left, top end
end

-- True while a tab steps aside for another, so its OnHide knows the
-- window is not closing (no closing line, nothing let go).
ButlerTabs.switching = false

--- A window is about to show. The other one makes way for it, and it takes
--- that one's place, else the place kept. Says "switch" when it took
--- another tab's place, "placed" when it went to the place kept, nil when
--- the window should restore its own old place.
function ButlerTabs:Take(window)
    local frame = FrameOf(window)
    if not frame then return nil end
    self:Fit(window)
    ButlerTabs.ApplyScale(frame)
    for _, other in ipairs(Windows()) do
        local otherFrame = FrameOf(other)
        if other ~= window and Shown(otherFrame) then
            local left, top = ButlerTabs.TopLeft(otherFrame)
            self.switching = true
            local ok, err = pcall(other.Hide, other)
            self.switching = false
            if not ok then ns.Debug("tab switch:", tostring(err)) end
            if left then
                ButlerTabs.PlaceAt(frame, left, top)
                if ns.db then ns.db.windowLeft, ns.db.windowTop = left, top end
                return "switch"
            end
        end
    end
    local db = ns.db
    if db and type(db.windowLeft) == "number" and type(db.windowTop) == "number" then
        ButlerTabs.PlaceAt(frame, db.windowLeft, db.windowTop)
        return "placed"
    end
    return nil
end
