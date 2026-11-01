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
    -- Inside the one window it fills the area, which grows instead.
    if self.area then
        self:Grow()
        return
    end
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
    -- The one window has its own scale.
    if ButlerTabs.area then return end
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
function ButlerTabs:Close(byItself)
    if self.area then
        local One = ButlerTabs.One()
        if One and One.Close then pcall(One.Close, byItself) end
        return
    end
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
    if not (ns.db and frame) or self.area then return end
    local left, top = ButlerTabs.TopLeft(frame)
    if left then ns.db.windowLeft, ns.db.windowTop = left, top end
end

--- A window opened at its own old place: anchor it by its top left corner,
--- so a change of height keeps its top still, and keep that as the place.
function ButlerTabs:Settle(frame)
    if not frame or self.area then return end
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
    -- Inside the one window: laid in, and the other tab steps aside.
    if self.area then
        self:LayIn(window)
        for _, other in ipairs(Windows()) do
            if other ~= window and Shown(FrameOf(other)) then
                self.switching = true
                local ok, err = pcall(other.Hide, other)
                self.switching = false
                if not ok then ns.Debug("tab switch:", tostring(err)) end
            end
        end
        return "switch"
    end
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

--------------------------------------------------------------------------------
-- The one window
--
-- With "One Window:" ticked (UI/SharedWindow.lua, the owner said build it,
-- 2026-10-30), Butler's tabs show inside the one Blackthornes window: the
-- Butler window and Settings are laid into its area, filling it, without
-- their own rim, plate, portrait, gems or size grip, since the one window
-- has its own. Their tabs still hang below, under the one window's edge.
-- Unticked, or when another addon is picked on the rail, they go back to
-- their own place, size and scale. The secure buttons are untouched: they
-- live inside the Butler window out of a fight (UI:Dock) and go back to
-- UIParent as one starts (UI:Undock), wherever the window is.
--------------------------------------------------------------------------------

-- The one window's area while Butler's pages are in it, else nil.
ButlerTabs.area = nil
-- The tab to show when the one window lays Butler in.
ButlerTabs.wanted = nil
-- True while the pages go back, so their OnHide does not close the one
-- window too.
ButlerTabs.leaving = false

--- The copy of the one window that draws it, or nil.
function ButlerTabs.One()
    local SharedWindow = ns.SharedWindow
    if not (SharedWindow and SharedWindow.Drawer) then return nil end
    local ok, drawer = pcall(SharedWindow.Drawer)
    local api = ok and type(drawer) == "table" and drawer.api or nil
    return type(api) == "table" and api or nil
end

--- True while Butler's pages show in the one window.
function ButlerTabs:Hosted()
    return self.area ~= nil
end

-- What a window's own frame wears, put out of sight inside the one window
-- and back after: the trim (plate, portrait, close and fold gems, corners),
-- the size grip and the rim drawn on the frame itself.
local function Bare(window, bare)
    local frame = FrameOf(window)
    if not frame then return end
    local trim = rawget(window, "trim") or rawget(frame, "titan")
    if trim and trim.SetShown then trim:SetShown(not bare) end
    local grip = rawget(window, "sizeGrip")
    if grip and grip.SetShown then grip:SetShown(not bare) end
    if bare then
        local kept = {}
        local ok, regions = pcall(function() return { frame:GetRegions() } end)
        for _, region in ipairs(ok and regions or {}) do
            local okLayer, layer = pcall(region.GetDrawLayer, region)
            if okLayer and layer == "BORDER" and region:IsShown() then
                region:Hide()
                kept[#kept + 1] = region
            end
        end
        window.bareRim = kept
        pcall(frame.RegisterForDrag, frame)
    else
        for _, region in ipairs(rawget(window, "bareRim") or {}) do region:Show() end
        window.bareRim = nil
        pcall(frame.RegisterForDrag, frame, "LeftButton")
    end
end

--- Lay one window into the area, filling it.
function ButlerTabs:LayIn(window)
    local frame, area = FrameOf(window), self.area
    if not (frame and area) then return end
    if frame:GetParent() ~= area then frame:SetParent(area) end
    frame:ClearAllPoints()
    frame:SetAllPoints(area)
    frame:SetScale(1)
    Bare(window, true)
    local strip = rawget(window, "tabStrip")
    if strip then
        -- Hung from the one window's own bottom edge, not the area's.
        local one = area:GetParent()
        local drop = 8
        if one then
            local okA, a = pcall(area.GetBottom, area)
            local okO, o = pcall(one.GetBottom, one)
            if okA and okO and type(a) == "number" and type(o) == "number" then drop = a - o end
        end
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", area, "BOTTOMLEFT", ButlerTabs.INSET, -drop)
        local ok, width = pcall(area.GetWidth, area)
        if ok and type(width) == "number" and width > 0 and strip.SetRoom then
            strip:SetRoom(width - 2 * ButlerTabs.INSET)
        end
    end
    local okW, width = pcall(area.GetWidth, area)
    local okH, height = pcall(area.GetHeight, area)
    if okW and okH and type(window.OnTabSize) == "function" then window:OnTabSize(width, height) end
end

--- Give one window back its own place, size and scale.
function ButlerTabs:LayOut(window)
    local frame = FrameOf(window)
    if not frame then return end
    frame:SetParent(UIParent)
    Bare(window, false)
    local strip = rawget(window, "tabStrip")
    if strip then
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", ButlerTabs.INSET, 0)
    end
    frame:ClearAllPoints()
    local db = ns.db
    if db and type(db.windowLeft) == "number" and type(db.windowTop) == "number" then
        ButlerTabs.ApplyScale(frame)
        ButlerTabs.PlaceAt(frame, db.windowLeft, db.windowTop)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        ButlerTabs.ApplyScale(frame)
    end
    -- Fit keeps a size it already has, so ask for it afresh.
    frame:SetWidth(1)
    self:Fit(window)
end

--- Grow the one window until its area holds the size every tab shares.
function ButlerTabs:Grow()
    local area = self.area
    local one = area and area:GetParent()
    if not one then return end
    local width, height = self:Size()
    local okW, areaW = pcall(area.GetWidth, area)
    local okH, areaH = pcall(area.GetHeight, area)
    if okW and type(areaW) == "number" and areaW > 0 and areaW < width then
        one:SetWidth(one:GetWidth() + (width - areaW))
    end
    if okH and type(areaH) == "number" and areaH > 0 and areaH < height then
        one:SetHeight(one:GetHeight() + (height - areaH))
    end
end

--- Butler's pages go into the one window: called by it (host.enter).
function ButlerTabs:Enter(area)
    if not area then return end
    self.area = area
    for _, window in ipairs(Windows()) do
        if FrameOf(window) then self:LayIn(window) end
    end
    self:Grow()
    local key = self.wanted or (ns.UI and rawget(ns.UI, "view") == "all" and "all") or "bags"
    self.wanted = nil
    self:Open(key)
end

--- Butler's pages go back: called by the one window (host.leave).
function ButlerTabs:Leave()
    if not self.area then return end
    self.leaving = true
    for _, window in ipairs(Windows()) do
        local frame = FrameOf(window)
        if Shown(frame) then
            local ok, err = pcall(window.Hide, window)
            if not ok then ns.Debug("one window leave:", tostring(err)) end
        end
    end
    self.area = nil
    for _, window in ipairs(Windows()) do
        if FrameOf(window) then self:LayOut(window) end
    end
    self.leaving = false
end

--- What Butler gives the one window when it joins.
ButlerTabs.host = {
    enter = function(area) ButlerTabs:Enter(area) end,
    leave = function() ButlerTabs:Leave() end,
}

--- A Butler tab is asked to open. With "One Window:" ticked and Butler not
--- in it yet, the one window opens on Butler instead, on that tab. True when
--- it did, so the caller stops there.
function ButlerTabs:Route(key)
    if self.area then return false end
    local One = ButlerTabs.One()
    if not (One and One.Hosts and One.Hosts("butler")) then return false end
    self.wanted = key
    local ok, opened = pcall(One.Open, "butler")
    if ok and opened then return true end
    self.wanted = nil
    return false
end

--- One of Butler's windows closed (Escape, leaving a vendor): inside the
--- one window, the one window closes with it. `byItself` is true when
--- Butler closed it on leaving a place, so the one window may go back to
--- what was open before; a player's close stays closed.
function ButlerTabs:Closed(frame, byItself)
    if not self.area or self.leaving or self.switching then return end
    -- A window built for the first time hides itself before it is laid
    -- in, and that is no close: only one inside the area counts.
    if frame and frame.GetParent and frame:GetParent() ~= self.area then return end
    local One = ButlerTabs.One()
    if One and One.Close then pcall(One.Close, byItself) end
end
