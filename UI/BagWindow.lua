-- Blackthornes Butler -- UI/BagWindow.lua
-- The Bags window: every bag in one window in the house frame, with Bags,
-- Bank and Everyone tabs, a search, chips and three ways to group (What To
-- Do, Item Type, One Grid). The owner asked for it, 2026-10-19, with the
-- words he approved from the mockup.
--
-- Off unless ticked ("Use Butler Bags", `bagWindow`). On, it opens and
-- closes when the game's bags do, and the game's own bag frames are put out
-- of sight with ns.Veil (see-through and no mouse; never Hide or Show), so
-- they are still there underneath. Turned off, they are put back.
--
-- What it shows comes from Logic/BagView.lua. The item squares on the Bags
-- tab are the game's own item button template, bound to a bag and slot, so a
-- click, a right-click, a drag and the tooltip are the game's. Buttons are
-- made a few a frame and laid out only out of combat; in a fight only their
-- look is refreshed.

local _, ns = ...
local L = ns.L

local BagWindow = ns.NewModule("BagWindow")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Items = ns.Items

local WIDTH = 520
local HEIGHT = 600
local PADDING = 18
local EDGE_PAD = 11
local SORT_RIGHT = 32   -- clear of the close gem in the top right corner
local FOOT = 40
-- The free count's size over large: well above the foot's other words, so
-- it reads at a glance.
BagWindow.FREE_SIZE_UP = 6
local WELL_TOP = 116
local GAP = 4
local HEADING = 24
local SECTION_GAP = 8
local SCROLL_STEP = 48
local MAKE_BUDGET = 24
local SCALE_MIN = 0.6
local SCALE_MAX = 1.5
local GRIP_SIZE = 20

BagWindow.tab = "bags"
BagWindow.chip = nil

-- The game's bag windows, veiled while Butler Bags is on.
local GAME_FRAMES = { "ContainerFrameCombinedBags" }
for i = 1, 13 do GAME_FRAMES[#GAME_FRAMES + 1] = "ContainerFrame" .. i end

local function InCombat()
    local fn = rawget(_G, "InCombatLockdown")
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn)
    return ok and value == true
end

local function QualityColor(quality)
    local r, g, b = Items.QualityRGB(quality or 1)
    if not r then return 1, 1, 1 end
    return r, g, b
end

--------------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------------

function BagWindow:On()
    return ns.BagView:On()
end

--- True while the game's bags are veiled under this window.
function BagWindow:Covering()
    return self:On()
end

function BagWindow:SetOn(on)
    if ns.db then ns.db.bagWindow = on and true or false end
    if on then
        self:Hook()
        self:CoverGame()
    else
        self:UncoverGame()
        self:Hide()
    end
    if ns.Trash then ns.Trash:Changed() end
end

--------------------------------------------------------------------------------
-- The game's bags
--------------------------------------------------------------------------------

local function GameFrame(name)
    local frame = rawget(_G, name)
    return type(frame) == "table" and frame or nil
end

function BagWindow:CoverGame()
    if not self:On() then return end
    local waiting = false
    for _, name in ipairs(GAME_FRAMES) do
        local frame = GameFrame(name)
        if frame and frame.IsShown and frame:IsShown() then
            if not ns.Veil:Cover(frame) then waiting = true end
        end
    end
    self.coverWaiting = waiting
end

function BagWindow:UncoverGame()
    local waiting = false
    for _, name in ipairs(GAME_FRAMES) do
        local frame = GameFrame(name)
        if frame and ns.Veil:Covers(frame) then
            if not ns.Veil:Uncover(frame) then waiting = true end
        end
    end
    self.uncoverWaiting = waiting
end

-- What the game did to its bags this frame, settled once the frame is over:
-- a toggle flips this window once; with no toggle an open shows it and a
-- close hides it. The game's own state is never read or changed.
local pending

local function Settle()
    local seen = pending
    pending = nil
    if not (seen and BagWindow:On()) then return end
    if seen.toggle then
        BagWindow:Toggle()
    elseif seen.open then
        BagWindow:Show()
    elseif seen.close then
        BagWindow:Hide()
    end
end

local function Saw(kind)
    if not BagWindow:On() then return end
    if not pending then
        pending = {}
        C_Timer.After(0, Settle)
        if not pending then return end
    end
    pending[kind] = true
end

local HOOKS = {
    ToggleAllBags = "toggle", ToggleBackpack = "toggle", ToggleBag = "toggle",
    OpenAllBags = "open", OpenBackpack = "open",
    CloseAllBags = "close", CloseBackpack = "close",
}

function BagWindow:Hook()
    if self.hooked then return end
    local hook = rawget(_G, "hooksecurefunc")
    if type(hook) ~= "function" then return end
    self.hooked = true
    for name, kind in pairs(HOOKS) do
        if type(rawget(_G, name)) == "function" then
            pcall(hook, name, function() Saw(kind) end)
        end
    end
    -- A game bag window that shows while Butler Bags is on goes under the
    -- veil at once.
    for _, name in ipairs(GAME_FRAMES) do
        local frame = GameFrame(name)
        if frame and type(frame.HookScript) == "function" then
            pcall(frame.HookScript, frame, "OnShow", function(shown)
                if BagWindow:On() and not ns.Veil:Cover(shown) then BagWindow.coverWaiting = true end
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- Size and place
--------------------------------------------------------------------------------

function BagWindow.ClampScale(value)
    value = tonumber(value)
    if not value or value ~= value then return 1 end
    value = math.max(SCALE_MIN, math.min(SCALE_MAX, value))
    return math.floor(value * 100 + 0.5) / 100
end

function BagWindow:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.bagPoint, ns.db.bagRelPoint, ns.db.bagX, ns.db.bagY = point, relativePoint, x, y
end

function BagWindow:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.bagPoint or "BOTTOMRIGHT", UIParent, db.bagRelPoint or "BOTTOMRIGHT",
        db.bagX or -80, db.bagY or 120)
end

function BagWindow:SetScale(value)
    local scale = BagWindow.ClampScale(value)
    if ns.db then ns.db.bagScale = scale end
    local frame = self.frame
    if not frame then return end
    local old = frame:GetScale()
    if type(old) ~= "number" or old <= 0 then old = 1 end
    local left, top = frame:GetLeft(), frame:GetTop()
    frame:SetScale(scale)
    if type(left) == "number" and type(top) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
        self:SavePosition()
    end
end

--- The house size grip below the bottom right corner (as the Butler
--- window's): drag for size, right-click for normal. Only the scale moves.
function BagWindow:BuildSizeGrip()
    local frame = self.frame
    local below = 3
    if self.trim and ns.Titanforged and ns.Titanforged.Reach then
        local _, _, _, bottom = ns.Titanforged.Reach(self.trim)
        if type(bottom) == "number" then below = bottom + 3 end
    end

    local grip = Theme.CreatePanel(frame, "panel", "borderLit")
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -6, -below)
    grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    grip:EnableMouse(true)
    if Theme.TopSheen then Theme.TopSheen(grip) end
    self.sizeGrip = grip

    local dots = {}
    for row = 0, 2 do
        for column = 2 - row, 2 do
            local dot = grip:CreateTexture(nil, "ARTWORK")
            dot:SetSize(3, 3)
            dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -3 - (2 - column) * 5, 3 + (2 - row) * 5)
            dot:SetColorTexture(Theme.Unpack("accent"))
            dots[#dots + 1] = dot
        end
    end

    local function Light(on)
        Theme.SetBorderColor(grip, on and "accent" or "borderLit")
        for _, dot in ipairs(dots) do dot:SetColorTexture(Theme.Unpack(on and "accentHi" or "accent")) end
    end

    local function ScaleText(scale)
        return ("%d%%"):format(math.floor((tonumber(scale) or 1) * 100 + 0.5))
    end

    local function Track(self)
        local cx, cy = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        if not (cx and cy and type(uiScale) == "number" and uiScale > 0) then return end
        cx, cy = cx / uiScale, cy / uiScale
        local width = cx - self.grabX - self.anchorLeft
        local height = self.anchorTop - (cy + self.grabY)
        local scale = BagWindow.ClampScale((width / WIDTH + height / HEIGHT) / 2)
        if math.abs(scale - (frame:GetScale() or 1)) < 0.005 then return end
        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.anchorLeft / scale, self.anchorTop / scale)
        if GameTooltip:IsOwned(self) then
            GameTooltip:SetText(ScaleText(scale), Theme.Unpack("accentHi"))
            GameTooltip:Show()
        end
    end

    local function StopSizing(self)
        if not self.sizing then return end
        self.sizing = false
        self:SetScript("OnUpdate", nil)
        if ns.db then ns.db.bagScale = BagWindow.ClampScale(frame:GetScale()) end
        BagWindow:SavePosition()
    end

    grip:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            BagWindow:SetScale(1)
            return
        end
        if button ~= "LeftButton" then return end
        if ns.Motion and ns.Motion.Stop then pcall(ns.Motion.Stop, ns.Motion, frame, "open", true) end
        local scale = frame:GetScale() or 1
        local left, top = frame:GetLeft(), frame:GetTop()
        local cx, cy = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        if not (type(left) == "number" and type(top) == "number" and cx and cy
            and type(uiScale) == "number" and uiScale > 0) then
            return
        end
        self.anchorLeft, self.anchorTop = left * scale, top * scale
        self.grabX = cx / uiScale - (self.anchorLeft + WIDTH * scale)
        self.grabY = (self.anchorTop - HEIGHT * scale) - cy / uiScale
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        self.sizing = true
        self:SetScript("OnUpdate", Track)
    end)
    grip:SetScript("OnMouseUp", StopSizing)
    grip:SetScript("OnHide", StopSizing)
    grip:SetScript("OnEnter", function(self)
        Light(true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ScaleText(frame:GetScale()), Theme.Unpack("accentHi"))
        GameTooltip:AddLine(L["Drag to make the window bigger or smaller."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Right-click to go back to the normal size."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        Light(false)
        GameTooltip:Hide()
    end)
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local TABS = { "bags", "bank", "everyone" }
local TAB_WORDS = { bags = L["Bags"], bank = L["Bank"], everyone = L["Everyone"] }

function BagWindow:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesButlerBags", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetScale(BagWindow.ClampScale(ns.db and ns.db.bagScale or 1))
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    Theme.Fill(frame, "window")

    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = L["Bags"],
            portrait = true,
            close = function() BagWindow:Hide() end,
        })
        self.trim = trim
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then frame:SetClampRectInsets(-left, right, top, -bottom) end
    else
        Theme.Border(frame, "borderLit")
    end

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        BagWindow:SavePosition()
    end)
    frame:SetScript("OnHide", function()
        GameTooltip:Hide()
        -- Closing the bags is looking at them, as with the game's own.
        if ns.BagView.seen then ns.BagView:ClearNew() end
        if ns.Trash then ns.Trash:Changed() end
    end)
    -- The fold gem beside the close gem (UI/FoldWindow.lua). Folded, the
    -- squares are out of sight, so the trash can leaves them.
    if ns.FoldWindow then
        ns.FoldWindow:Add(frame, { onToggle = function(folded)
            if not folded then BagWindow:Changed(true) end
            if ns.Trash then ns.Trash:Changed() end
        end })
    end
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "BlackthornesButlerBags") end
    self.frame = frame

    self:BuildHeader()
    self:BuildWell()
    self:BuildFoot()
    self:BuildSizeGrip()

    frame:Hide()
    return frame
end

--- Tabs along the top past the portrait, a gold rule under them, the search
--- across the window, then the chips and Group By.
function BagWindow:BuildHeader()
    local frame = self.frame
    self.tabs = {}
    local x = 59
    for _, key in ipairs(TABS) do
        local tab = Widgets.CreateButton(frame, TAB_WORDS[key], function() BagWindow:SetTab(key) end,
            { height = 22 })
        tab:SetWidth(math.max(70, Theme.TextWidth("small", TAB_WORDS[key]) + 28))
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -EDGE_PAD - 6)
        x = x + tab:GetWidth() + 6
        self.tabs[key] = tab
    end

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", EDGE_PAD, -44)
    rule:SetPoint("TOPRIGHT", -EDGE_PAD, -44)
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)

    local search = Widgets.CreateSearchBox(frame, L["Search all your characters"], function()
        BagWindow:Changed(true)
    end)
    search:SetPoint("TOPLEFT", PADDING, -52)
    search:SetPoint("TOPRIGHT", -PADDING, -52)
    self.search = search

    self.chips = {}
    local chipX = PADDING
    for _, key in ipairs(ns.BagView.CHIPS) do
        local word = ns.BagView.CHIP_WORDS[key]
        local chip = Widgets.CreateButton(frame, word, function()
            BagWindow.chip = BagWindow.chip ~= key and key or nil
            BagWindow:PaintChips()
            BagWindow:Changed(true)
        end, { height = 20 })
        chip:SetWidth(Theme.TextWidth("small", word) + 20)
        chip:SetPoint("TOPLEFT", frame, "TOPLEFT", chipX, -86)
        chipX = chipX + chip:GetWidth() + 4
        self.chips[key] = chip
    end

    local words = {}
    for _, key in ipairs(ns.BagView.GROUPS) do words[#words + 1] = ns.BagView.GROUP_WORDS[key] end
    local group = Widgets.CreateChoice(frame, {
        min = 1, max = #ns.BagView.GROUPS, step = 1,
        value = BagWindow.GroupIndex(),
        format = function(v) return ns.BagView.GROUP_WORDS[ns.BagView.GROUPS[v]] end,
        onChange = function(v) ns.BagView:SetGroupBy(ns.BagView.GROUPS[v]) end,
    })
    if ns.SettingsPages and ns.SettingsPages.FitStepper then ns.SettingsPages.FitStepper(group, words) end
    group:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -86)
    self.groupStepper = group

    local groupLabel = Theme.CreateLabel(frame, "small", "muted", "RIGHT")
    groupLabel:SetPoint("RIGHT", group, "LEFT", -6, 0)
    groupLabel:SetText(L["Group By:"])
    self.groupLabel = groupLabel

    self:PaintTabs()
    self:PaintChips()
end

function BagWindow.GroupIndex()
    local now = ns.BagView:GroupBy()
    for i, key in ipairs(ns.BagView.GROUPS) do
        if key == now then return i end
    end
    return 1
end

function BagWindow:PaintTabs()
    for key, tab in pairs(self.tabs or {}) do
        local on = key == self.tab
        if tab.SetLabelColor then tab:SetLabelColor(on and "accentHi" or nil) end
        Theme.SetBorderColor(tab, on and "accent" or "border")
    end
    local bags = self.tab == "bags"
    for _, chip in pairs(self.chips or {}) do chip:SetShown(bags) end
    if self.groupStepper then self.groupStepper:SetShown(bags) end
    if self.groupLabel then self.groupLabel:SetShown(bags) end
end

function BagWindow:PaintChips()
    for key, chip in pairs(self.chips or {}) do
        local on = key == self.chip
        if chip.SetLabelColor then chip:SetLabelColor(on and "good" or nil) end
        Theme.SetBorderColor(chip, on and "good" or "border")
    end
end

--- The sunk well the items sit in, scrolled by the wheel or the bar.
function BagWindow:BuildWell()
    local frame = self.frame
    local well = Theme.CreatePanel(frame, "panel", "border")
    well:SetPoint("TOPLEFT", PADDING, -WELL_TOP)
    well:SetPoint("BOTTOMRIGHT", -PADDING, FOOT)
    if Theme.Recess then Theme.Recess(well) end
    self.well = well

    local scroll = CreateFrame("ScrollFrame", nil, well)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -16, 6)
    self.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 2 * PADDING - 22, 10)
    scroll:SetScrollChild(content)
    self.content = content

    local bar = Widgets.CreateScrollbar and Widgets.CreateScrollbar(well, "metal")
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", well, "TOPRIGHT", -4, -6)
        bar:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -4, 6)
        bar.onValueChanged = function(value) scroll:SetVerticalScroll(value) end
        self.bar = bar
    end

    well:EnableMouseWheel(true)
    well:SetScript("OnMouseWheel", function(_, delta) BagWindow:ScrollBy(-delta * SCROLL_STEP) end)

    local empty = Theme.CreateLabel(well, "normal", "muted", "CENTER")
    empty:SetPoint("CENTER", 0, 0)
    empty:SetWidth(WIDTH - 4 * PADDING)
    empty:SetWordWrap(true)
    empty:Hide()
    self.emptyLabel = empty
end

function BagWindow:ScrollBy(pixels)
    local scroll = self.scroll
    if not scroll then return end
    local most = math.max(0, (self.contentHeight or 0) - (tonumber(scroll:GetHeight() or 0) or 0))
    local value = math.max(0, math.min(most, (tonumber(scroll:GetVerticalScroll() or 0) or 0) + pixels))
    scroll:SetVerticalScroll(value)
    if self.bar then self.bar:SetValue(value) end
end

function BagWindow:SizeScroll()
    local scroll, bar = self.scroll, self.bar
    local view = tonumber(scroll:GetHeight() or 0) or 0
    local most = math.max(0, (self.contentHeight or 0) - view)
    if (tonumber(scroll:GetVerticalScroll() or 0) or 0) > most then scroll:SetVerticalScroll(most) end
    if bar then
        bar:SetMinMaxValues(0, most)
        bar:SetValue(tonumber(scroll:GetVerticalScroll() or 0) or 0)
        bar:SizeThumb(view, math.max(view, self.contentHeight or 0))
        bar:SetShown(most > 0)
    end
end

--- Free slots, this character's gold and the gold on every character along
--- the foot; Sort at the
--- top right, on the tabs' row, clear of the close gem.
function BagWindow:BuildFoot()
    local frame = self.frame
    local free = Theme.CreateLabel(frame, Theme.sizes.large + BagWindow.FREE_SIZE_UP, "text")
    free:SetPoint("BOTTOMLEFT", PADDING, 11)
    self.freeLabel = free

    -- This character's gold first and brighter, the total after it.
    local mine = Theme.CreateLabel(frame, "normal", "text")
    mine:SetPoint("LEFT", free, "RIGHT", 16, 0)
    self.myGoldLabel = mine

    local gold = Theme.CreateLabel(frame, "small", "muted")
    gold:SetPoint("LEFT", mine, "RIGHT", 16, 0)
    self.goldLabel = gold

    local sort = Widgets.CreateButton(frame, L["Sort"], function() BagWindow:Sort() end,
        { height = 22 })
    sort:SetWidth(math.max(70, Theme.TextWidth("small", L["Sort"]) + 28))
    sort:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SORT_RIGHT, -EDGE_PAD - 6)
    self.sortButton = sort
    sort:SetShown(BagWindow.CanSort())

    -- Empty Slots: each way of grouping keeps its own choice (BagView).
    local empty = Widgets.CreateCheckbox(frame, L["Empty Slots"], function(on)
        ns.BagView:SetShowsEmpty(on)
    end, ns.BagView:ShowsEmpty())
    empty:SetPoint("RIGHT", sort, "LEFT", -12, 0)
    self.emptyBox = empty
end


--- The game's own bag sort, where the client has one.
function BagWindow.GameSorts()
    local container = rawget(_G, "C_Container")
    return type(container) == "table" and type(container.SortBags) == "function"
end

--- Sort shows when the game sorts, or Butler can do it itself (Era has no
--- bag sort; Logic/BagSort.lua moves the items one at a time).
function BagWindow.CanSort()
    if BagWindow.GameSorts() then return true end
    return ns.BagSort ~= nil and ns.BagSort.CanSort()
end

-- The sound the game's own bag sort button plays: SOUNDKIT's name when the
-- client has it, else its ID. Played by ID, so no game audio ships here.
BagWindow.SORT_SOUND = 73933

function BagWindow.SortSound()
    local kit = rawget(_G, "SOUNDKIT")
    local id = type(kit) == "table" and kit.UI_BAG_SORTING_01
    return type(id) == "number" and id or BagWindow.SORT_SOUND
end

function BagWindow:Sort()
    if InCombat() or not BagWindow.CanSort() then return end
    -- No channel, as the game's button: it follows the player's sound effects.
    local play = rawget(_G, "PlaySound")
    if BagWindow.GameSorts() then
        if type(play) == "function" then pcall(play, BagWindow.SortSound()) end
        pcall(C_Container.SortBags)
        return
    end
    if ns.BagSort:Running() then return end
    if ns.BagSort:Start() and type(play) == "function" then pcall(play, BagWindow.SortSound()) end
    self:UpdateFoot()
end

function BagWindow:UpdateFoot()
    local free = ns.BagView.Free()
    self.freeLabel:SetText(free and L.Format("%d free", free) or "")
    if free and ns.FreeSpace then
        local color = ns.FreeSpace.COLORS[ns.FreeSpace.Level(free)]
        self.freeLabel:SetTextColor(color[1], color[2], color[3])
    end
    local mine = ns.BagView.MyGold()
    self.myGoldLabel:SetText(mine and L.Format("Gold: %s", Items.FormatMoney(mine)) or "")
    local gold = ns.BagView.Gold()
    self.goldLabel:SetText(gold and L.Format("All characters: %s", Items.FormatMoney(gold)) or "")
    self.sortButton:SetShown(BagWindow.CanSort() and self.tab == "bags")
    if self.emptyBox then
        self.emptyBox:SetShown(self.tab == "bags")
        self.emptyBox:SetChecked(ns.BagView:ShowsEmpty())
    end
    if self.sortButton.SetEnabled then
        local busy = ns.BagSort and ns.BagSort:Running()
        self.sortButton:SetEnabled(not InCombat() and not busy)
    end
end

--------------------------------------------------------------------------------
-- Item buttons (Bags tab)
--------------------------------------------------------------------------------

-- [bag] = holder frame whose ID is the bag, as the game's template reads it.
local holders = {}
-- ["bag:slot"] = the game's item button for that slot.
local buttons = {}
local made = 0

local function Holder(bag)
    local holder = holders[bag]
    if holder then return holder end
    holder = CreateFrame("Frame", nil, BagWindow.content)
    holder:SetAllPoints(BagWindow.content)
    if holder.SetID then pcall(holder.SetID, holder, bag) end
    holders[bag] = holder
    return holder
end

--- The pieces every square wears, on the game's button or our own.
local function Dress(button, size)
    if rawget(button, "bfrDressed") then return end
    button.bfrDressed = true

    local back = button:CreateTexture(nil, "BACKGROUND", nil, -7)
    back:SetPoint("TOPLEFT", -1, 1)
    back:SetPoint("BOTTOMRIGHT", 1, -1)
    back:SetColorTexture(Theme.Unpack("border", 0.9))
    button.bfrBack = back
    local glass = button:CreateTexture(nil, "BACKGROUND", nil, -6)
    glass:SetAllPoints(button)
    glass:SetColorTexture(Theme.Unpack("glass"))
    button.bfrGlass = glass

    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints(button)
    over:SetFrameLevel((button:GetFrameLevel() or 1) + 3)
    button.bfrOver = over

    local mark = over:CreateTexture(nil, "OVERLAY")
    mark:SetSize(14, 14)
    mark:SetPoint("TOPRIGHT", -1, -1)
    mark:Hide()
    button.bfrMark = mark

    local level = Theme.CreateLabel(over, "tiny", "accentHi", "LEFT")
    level:SetPoint("TOPLEFT", 2, -2)
    button.bfrLevel = level

    local glow = CreateFrame("Frame", nil, over)
    glow:SetAllPoints(button)
    Theme.Border(glow, "accentHi")
    if Theme.Halo then Theme.Halo(glow, 4, 0.5, "accentHi") end
    glow:Hide()
    button.bfrGlow = glow
end

-- The game's template brings its own new item glow (a blue wash and a flash)
-- that its bag frames turn on and off. On our squares it stayed lit, empty
-- slots too (2026-10-20), so it is kept out of sight; Butler's gold glow is
-- the only one.
local TEMPLATE_GLOWS = { "NewItemTexture", "BattlepayItemTexture" }
local TEMPLATE_ANIMS = { "flashAnim", "newitemglowAnim" }

local function QuietTemplateGlow(button)
    for _, key in ipairs(TEMPLATE_GLOWS) do
        local texture = rawget(button, key)
        if type(texture) == "table" then
            if texture.SetAlpha then pcall(texture.SetAlpha, texture, 0) end
            if texture.Hide then pcall(texture.Hide, texture) end
        end
    end
    for _, key in ipairs(TEMPLATE_ANIMS) do
        local anim = rawget(button, key)
        if type(anim) == "table" and anim.Stop then pcall(anim.Stop, anim) end
    end
end
BagWindow.QuietTemplateGlow = QuietTemplateGlow

-- Our own picture, for a client without the game's template.
local function OwnIcon(button)
    if rawget(button, "bfrIcon") then return button.bfrIcon end
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    button.bfrIcon = icon
    local count = Theme.CreateLabel(button.bfrOver or button, "small", "text", "RIGHT")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    button.bfrCount = count
    return icon
end

local function MakeButton(bag, slot)
    local place = bag .. ":" .. slot
    if buttons[place] then return buttons[place] end
    made = made + 1
    local name = "BlackthornesButlerBagItem" .. made
    local holder = Holder(bag)
    local ok, button = pcall(CreateFrame, "ItemButton", name, holder, "ContainerFrameItemButtonTemplate")
    if ok and type(button) == "table" then
        BagWindow.templateOK = true
    else
        BagWindow.templateOK = false
        button = CreateFrame("Button", name, holder)
    end
    if button.SetID then pcall(button.SetID, button, slot) end
    if type(button.SetBagID) == "function" then pcall(button.SetBagID, button, bag) end
    button.bfrBag, button.bfrSlot = bag, slot
    Dress(button)
    if not BagWindow.templateOK then OwnIcon(button) end
    QuietTemplateGlow(button)
    -- The template turns its glow back on by itself; ours turns it off after.
    for _, method in ipairs({ "UpdateNewItem" }) do
        if type(rawget(button, method) or button[method]) == "function" and hooksecurefunc then
            pcall(hooksecurefunc, button, method, QuietTemplateGlow)
        end
    end
    button:HookScript("OnShow", QuietTemplateGlow)

    button:HookScript("OnEnter", function(self)
        local entry = ns.Bags.slots[self.bfrBag .. ":" .. self.bfrSlot]
        if entry and BagWindow.newShown and BagWindow.newShown[self] then
            if ns.BagView:Saw(entry) then
                if GameTooltip:IsOwned(self) then
                    GameTooltip:AddLine(L["New since you last looked."], Theme.Unpack("accentHi"))
                    GameTooltip:Show()
                end
                BagWindow:Changed()
            end
        end
    end)
    button:Hide()
    buttons[place] = button
    return button
end

--- Make every square the bags need, a few a frame, out of combat. `done`
--- runs once they are all there.
function BagWindow:MakeButtons(done)
    if InCombat() then
        self.layoutWaiting = true
        return
    end
    local places = ns.BagView.AllSlots()
    local index = 0
    local function Step()
        if InCombat() then
            BagWindow.layoutWaiting = true
            return
        end
        local stop = math.min(#places, index + MAKE_BUDGET)
        for i = index + 1, stop do MakeButton(places[i].bag, places[i].slot) end
        index = stop
        if index < #places then
            C_Timer.After(0, Step)
        elseif done then
            done()
        end
    end
    Step()
end

-- The coin is for vendor items only; an item for the auction house gets no
-- mark (the To Sell chip still finds both).
local MARK_ORDER = { "quest", "upgrade", "goal", "craft", "mail", "vendor" }

local function ShowMark(texture, kind)
    if kind == "upgrade" then
        local ok = texture.SetAtlas and pcall(texture.SetAtlas, texture, "bags-greenarrow")
        if not ok then
            texture:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
            texture:SetTexCoord(0, 1, 1, 0)
        end
    else
        texture:SetTexCoord(0, 1, 0, 1)
        local files = {
            vendor = "Interface\\MoneyFrame\\UI-GoldIcon",
            mail = "Interface\\Minimap\\Tracking\\Mailbox",
            goal = "Interface\\RaidFrame\\ReadyCheck-Ready",
            craft = "Interface\\RaidFrame\\ReadyCheck-Ready",
            quest = "Interface\\GossipFrame\\AvailableQuestIcon",
        }
        texture:SetTexture(files[kind])
    end
    texture:Show()
end

--- How a square looks: the item, its count and colour, its mark, item
--- level, the new glow and whether the search or chip leaves it dim.
function BagWindow:Paint(button, entry, search)
    local icon = entry and entry.icon or nil
    local count = entry and entry.count or 0
    if self.templateOK then
        local G = _G
        if type(G.SetItemButtonTexture) == "function" then pcall(G.SetItemButtonTexture, button, icon) end
        if type(G.SetItemButtonCount) == "function" then pcall(G.SetItemButtonCount, button, count) end
        if type(G.SetItemButtonQuality) == "function" then
            pcall(G.SetItemButtonQuality, button, entry and entry.quality or nil, entry and entry.link or nil)
        end
        if type(G.SetItemButtonDesaturated) == "function" then
            pcall(G.SetItemButtonDesaturated, button, entry and entry.locked and true or false)
        end
    else
        local own = OwnIcon(button)
        own:SetTexture(icon)
        button.bfrCount:SetText(count > 1 and tostring(count) or "")
    end

    local marks = entry and ns.BagView:Marks(entry)
    button.bfrMark:Hide()
    if marks then
        for _, kind in ipairs(MARK_ORDER) do
            if marks[kind] then
                ShowMark(button.bfrMark, kind)
                break
            end
        end
    end

    local level = entry and ns.BagView:ItemLevelOn() and ns.BagView.ItemLevel(entry)
    button.bfrLevel:SetText(level and tostring(level) or "")

    QuietTemplateGlow(button)
    local new = entry and ns.BagView:NewGlowOn() and ns.BagView:IsNew(entry)
    button.bfrGlow:SetShown(new and true or false)
    self.newShown[button] = new and true or nil


    local lit = true
    if entry then
        lit = ns.BagView.Matches(ns.BagView.NameOf(entry), entry.itemID, search)
            and ns.BagView:MatchesChip(entry, self.chip)
    elseif search or self.chip then
        lit = false
    end
    button:SetAlpha(lit and 1 or 0.25)
end

--------------------------------------------------------------------------------
-- View-only squares (Bank and Everyone tabs)
--------------------------------------------------------------------------------

local plain = {}

local function PlainButton(index)
    local button = plain[index]
    if button then return button end
    button = CreateFrame("Button", nil, BagWindow.content)
    Dress(button)
    OwnIcon(button)
    button:SetScript("OnEnter", function(self)
        local item = self.bfrItem
        if not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if item.link then
            pcall(GameTooltip.SetHyperlink, GameTooltip, item.link)
        elseif item.itemID then
            pcall(GameTooltip.SetItemByID, GameTooltip, item.itemID)
        end
        for _, holder in ipairs(item.holders or {}) do
            local line = ns.Everyone.Where(holder)
            if line then GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    plain[index] = button
    return button
end

local function PaintPlain(button, item)
    button.bfrItem = item
    button.bfrIcon:SetTexture(item.icon)
    local count = item.total or item.count or 1
    button.bfrCount:SetText(count > 1 and tostring(count) or "")
    local r, g, b = QualityColor(item.quality)
    -- The edge in the item's rarity colour, as the game's own squares have.
    button.bfrBack:SetColorTexture(r, g, b, 0.9)
    button.bfrGlass:SetColorTexture(r * 0.18, g * 0.18, b * 0.18, 0.9)
    button.bfrMark:Hide()
    button.bfrLevel:SetText("")
    button.bfrGlow:Hide()
    button:SetAlpha(1)
end

--------------------------------------------------------------------------------
-- Section headings
--------------------------------------------------------------------------------

local headings = {}

local function Heading(index)
    local heading = headings[index]
    if heading then return heading end
    heading = CreateFrame("Frame", nil, BagWindow.content)
    heading:SetHeight(HEADING - 2)
    Theme.Fill(heading, "glassAlt")
    local line = heading:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))

    local name = Theme.CreateLabel(heading, "small", "accent", "LEFT")
    name:SetPoint("LEFT", 6, 0)
    heading.nameLabel = name
    local count = Theme.CreateLabel(heading, "small", "muted", "LEFT")
    count:SetPoint("LEFT", name, "RIGHT", 6, 0)
    heading.countLabel = count
    local worth = Theme.CreateLabel(heading, "small", "text", "RIGHT")
    worth:SetPoint("RIGHT", -6, 0)
    heading.worthLabel = worth
    headings[index] = heading
    return heading
end

-- Fill mail on MAIL at a mailbox, Move to bank on BANK at the bank.
function BagWindow:HeadingButton(kind)
    self.headingButtons = self.headingButtons or {}
    local button = self.headingButtons[kind]
    if button then return button end
    local function Run(fn)
        return function()
            local _, message = fn(ns.Errands)
            if message then ns.Print(message) end
        end
    end
    if kind == "mail" then
        button = Widgets.CreateButton(self.content, L["Fill mail"], Run(ns.Errands.FillMail), { height = 18, primary = true })
    else
        button = Widgets.CreateButton(self.content, L["Move to bank"], Run(ns.Errands.MoveToBank), { height = 18, primary = true })
    end
    button:SetWidth(Theme.TextWidth("small", kind == "mail" and L["Fill mail"] or L["Move to bank"]) + 24)
    button:Hide()
    self.headingButtons[kind] = button
    return button
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

BagWindow.newShown = {}

--- Something moved: draw again, once, in a moment. `now` draws at once.
function BagWindow:Changed(now)
    if not self:IsShown() then return end
    if now then return self:Draw() end
    if self.drawSoon then return end
    self.drawSoon = true
    C_Timer.After(0.05, function()
        BagWindow.drawSoon = false
        BagWindow:Draw()
    end)
end

local function Columns(width, size)
    return math.max(1, math.floor((width + GAP) / (size + GAP)))
end

function BagWindow:Draw()
    if not self:IsShown() then return end
    local content = self.content
    local width = (tonumber(self.scroll:GetWidth()) or (WIDTH - 2 * PADDING - 22))
    if width < 100 then width = WIDTH - 2 * PADDING - 22 end
    content:SetWidth(width)

    for _, heading in ipairs(headings) do heading:Hide() end
    for _, button in pairs(self.headingButtons or {}) do button:Hide() end
    for _, button in ipairs(plain) do button:Hide() end
    self.emptyLabel:Hide()

    local search = ns.BagView.Fold(self.search:GetText())
    if self.tab == "bags" then
        self:DrawBags(width, search)
    else
        for _, button in pairs(buttons) do button:Hide() end
        self:DrawList(width, search)
    end
    self:UpdateFoot()
    self:SizeScroll()
end

function BagWindow:DrawBags(width, search)
    local size = ns.BagView:Pixels()
    local columns = Columns(width, size)
    local fighting = InCombat()
    self.newShown = {}

    -- In a fight nothing moves: only what each square shows is refreshed.
    if fighting then
        for place, button in pairs(buttons) do
            if button:IsShown() then self:Paint(button, ns.Bags.slots[place], search) end
        end
        self.layoutWaiting = true
        return
    end

    local sections = ns.BagView:Sections()
    local missing = false
    for _, section in ipairs(sections) do
        for _, place in ipairs(section.places) do
            if not buttons[place.bag .. ":" .. place.slot] then missing = true end
        end
    end
    if missing and not self.making then
        self.making = true
        self:MakeButtons(function()
            BagWindow.making = false
            BagWindow:Changed()
        end)
    end

    local used = {}
    local y = 0
    local headingIndex = 0
    local errands = ns.Errands
    for _, section in ipairs(sections) do
        if section.label then
            headingIndex = headingIndex + 1
            local heading = Heading(headingIndex)
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
            heading:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
            heading.nameLabel:SetText(section.label)
            heading.countLabel:SetText(tostring(#section.places))
            heading.worthLabel:SetText(section.worth and Items.FormatMoney(section.worth) or "")
            heading:Show()
            local kind = (section.verdict == "mail" and errands and errands.mailOpen and "mail")
                or (section.verdict == "bank" and errands and errands.bankOpen and "bank") or nil
            if kind then
                local button = self:HeadingButton(kind)
                button:ClearAllPoints()
                button:SetPoint("RIGHT", heading.worthLabel, "LEFT", -8, 0)
                button:SetFrameLevel(heading:GetFrameLevel() + 2)
                button:Show()
            end
            y = y + HEADING
        end
        local column = 0
        for _, place in ipairs(section.places) do
            local key = place.bag .. ":" .. place.slot
            local button = buttons[key]
            if button then
                button:SetSize(size, size)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", self.content, "TOPLEFT", column * (size + GAP), -y)
                self:Paint(button, place.entry, search)
                button:Show()
                used[key] = true
            end
            column = column + 1
            if column >= columns then
                column = 0
                y = y + size + GAP
            end
        end
        if column > 0 then y = y + size + GAP end
        y = y + SECTION_GAP
    end
    for key, button in pairs(buttons) do
        if not used[key] then button:Hide() end
    end
    self.layoutWaiting = false
    self.contentHeight = y
    self.content:SetHeight(math.max(10, y))
    -- The trash can and its glow sit on these squares (UI/Trash.lua): a
    -- look once the layout settles, so a new square or size is followed.
    if ns.Trash then ns.Trash:Changed() end
end

function BagWindow:DrawList(width, search)
    local size = ns.BagView:Pixels()
    local columns = Columns(width, size)
    local list, note
    if self.tab == "bank" then
        list = ns.BagView:BankItems()
        if #list == 0 then note = L["Nothing here yet. Open your bank once and it shows here."] end
    else
        list = ns.BagView:EveryoneItems(function() BagWindow:Changed() end)
        if #list == 0 then note = L["Needs Blackthornes Tradeskills to see your other characters."] end
    end

    local index, column, y = 0, 0, 0
    for _, item in ipairs(list) do
        if ns.BagView.Matches(item.name, item.itemID, search) then
            index = index + 1
            local button = PlainButton(index)
            button:SetSize(size, size)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", self.content, "TOPLEFT", column * (size + GAP), -y)
            PaintPlain(button, item)
            button:Show()
            column = column + 1
            if column >= columns then
                column = 0
                y = y + size + GAP
            end
        end
    end
    if column > 0 then y = y + size + GAP end
    if note then
        self.emptyLabel:SetText(note)
        self.emptyLabel:Show()
    end
    self.contentHeight = y
    self.content:SetHeight(math.max(10, y))
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

function BagWindow:IsShown()
    return self.frame ~= nil and self.frame:IsShown() == true
end

function BagWindow:SetTab(tab)
    self.tab = tab
    self:PaintTabs()
    if self.scroll then self.scroll:SetVerticalScroll(0) end
    self:Changed(true)
    if ns.Trash then ns.Trash:Changed() end
end

--- True while the window is up on Your bags, where the squares are.
function BagWindow:ShowsBags()
    if ns.FoldWindow and self.frame and ns.FoldWindow:IsFolded(self.frame) then return false end
    return self:IsShown() and (self.tab or "bags") == "bags"
end

--- The square shown for a bag slot, for the trash can, or nil.
function BagWindow:ButtonFor(bag, slot)
    if not self:ShowsBags() then return nil end
    local button = buttons[bag .. ":" .. slot]
    if not button then return nil end
    local ok, shown = pcall(button.IsShown, button)
    if ok and shown then return button end
    return nil
end

function BagWindow:Show()
    self:Build()
    if ns.FoldWindow then ns.FoldWindow:Unfold(self.frame) end
    if self.frame:IsShown() then return end
    ns.BagView:NoteSeen()
    self:RestorePosition()
    self.frame:Show()
    if ns.Motion and ns.Motion.Open then pcall(ns.Motion.Open, ns.Motion, self.frame) end
    if ns.Titanforged and ns.Titanforged.Opened then pcall(ns.Titanforged.Opened, ns.Titanforged, self.frame) end
    self:CoverGame()
    self:Draw()
    -- The bags may not have been read while nothing was looking.
    ns.Bags:Fresh(function() BagWindow:Changed() end)
    if ns.Trash then ns.Trash:Changed() end
end

function BagWindow:Hide()
    if self.frame then self.frame:Hide() end
end

function BagWindow:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

--------------------------------------------------------------------------------
-- Settings (UI/Settings.lua's General page)
--------------------------------------------------------------------------------

function BagWindow:AddSettings(pages, controls, x)
    pages:Section("general", 2, L["BAGS"])

    local onRow = pages:Row("general", 2, L["Use Butler Bags:"],
        L["Opens Butler's bag window when you open your bags. The game's own bags are still there underneath."])
    controls.bagWindow = Widgets.CreateCheckbox(onRow, L["On"], function(checked)
        BagWindow:SetOn(checked)
    end, false)
    controls.bagWindow:SetPoint("TOPLEFT", x, -2)

    local groupRow = pages:Row("general", 2, L["Group By:"], nil)
    local words = {}
    for _, key in ipairs(ns.BagView.GROUPS) do words[#words + 1] = ns.BagView.GROUP_WORDS[key] end
    local group = Widgets.CreateChoice(groupRow, {
        min = 1, max = #ns.BagView.GROUPS, step = 1, value = BagWindow.GroupIndex(),
        format = function(v) return ns.BagView.GROUP_WORDS[ns.BagView.GROUPS[v]] end,
        onChange = function(v) ns.BagView:SetGroupBy(ns.BagView.GROUPS[v]) end,
    })
    if ns.SettingsPages and ns.SettingsPages.FitStepper then ns.SettingsPages.FitStepper(group, words) end
    group:SetPoint("TOPLEFT", x, -2)
    controls.bagGroupBy = group

    local sizeRow = pages:Row("general", 2, L["Item Size:"], nil)
    local sizeWords = {}
    for _, key in ipairs(ns.BagView.SIZES) do sizeWords[#sizeWords + 1] = ns.BagView.SIZE_WORDS[key] end
    local size = Widgets.CreateChoice(sizeRow, {
        min = 1, max = #ns.BagView.SIZES, step = 1, value = BagWindow.SizeIndex(),
        format = function(v) return ns.BagView.SIZE_WORDS[ns.BagView.SIZES[v]] end,
        onChange = function(v) ns.BagView:SetItemSize(ns.BagView.SIZES[v]) end,
    })
    if ns.SettingsPages and ns.SettingsPages.FitStepper then ns.SettingsPages.FitStepper(size, sizeWords) end
    size:SetPoint("TOPLEFT", x, -2)
    controls.bagItemSize = size

    local levelRow = pages:Row("general", 2, L["Item Level on Gear:"], nil)
    controls.bagItemLevel = Widgets.CreateCheckbox(levelRow, L["On"], function(checked)
        ns.BagView:SetItemLevelOn(checked)
    end, true)
    controls.bagItemLevel:SetPoint("TOPLEFT", x, -2)

    local glowRow = pages:Row("general", 2, L["New Item Glow:"], nil)
    controls.bagNewGlow = Widgets.CreateCheckbox(glowRow, L["On"], function(checked)
        ns.BagView:SetNewGlowOn(checked)
    end, true)
    controls.bagNewGlow:SetPoint("TOPLEFT", x, -2)
end

function BagWindow.SizeIndex()
    local now = ns.BagView:ItemSize()
    for i, key in ipairs(ns.BagView.SIZES) do
        if key == now then return i end
    end
    return 1
end

--- Put the Settings controls back in step with what is saved.
function BagWindow:SyncSettings(controls)
    if not controls.bagWindow then return end
    controls.bagWindow:SetChecked(self:On())
    controls.bagGroupBy:SetValue(BagWindow.GroupIndex(), true)
    controls.bagItemSize:SetValue(BagWindow.SizeIndex(), true)
    controls.bagItemLevel:SetChecked(ns.BagView:ItemLevelOn())
    controls.bagNewGlow:SetChecked(ns.BagView:NewGlowOn())
    if self.groupStepper then self.groupStepper:SetValue(BagWindow.GroupIndex(), true) end
end

--------------------------------------------------------------------------------
-- Probe
--------------------------------------------------------------------------------

function BagWindow:ProbeText()
    local parts = {}
    parts[#parts + 1] = self:On() and "on" or "off"
    local template = "not made yet"
    if self.templateOK == true then template = "game template" elseif self.templateOK == false then template = "own buttons" end
    parts[#parts + 1] = "buttons " .. template
    local _, any = next(buttons)
    if any and type(any.IsProtected) == "function" then
        local ok, protected = pcall(any.IsProtected, any)
        parts[#parts + 1] = "protected " .. tostring(ok and protected or "?")
    end
    parts[#parts + 1] = "SetBagID " .. tostring(any and type(any.SetBagID) == "function" or false)
    parts[#parts + 1] = "SortBags " .. tostring(BagWindow.GameSorts()) .. " own sort " .. tostring(ns.BagSort ~= nil and ns.BagSort.CanSort())
    local container = rawget(_G, "C_Item")
    parts[#parts + 1] = "item level " .. tostring(type(rawget(_G, "GetDetailedItemLevelInfo")) == "function"
        or (type(container) == "table" and type(container.GetDetailedItemLevelInfo) == "function"))
    local found = 0
    for _, name in ipairs(GAME_FRAMES) do if GameFrame(name) then found = found + 1 end end
    parts[#parts + 1] = "game bag frames " .. found
    return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- Events and command
--------------------------------------------------------------------------------

function BagWindow:OnEnable()
    if self:On() then self:Hook() end
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if BagWindow.coverWaiting then BagWindow:CoverGame() end
        if BagWindow.uncoverWaiting then BagWindow:UncoverGame() end
        if BagWindow.layoutWaiting then BagWindow:Changed() end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        if BagWindow.sortButton then BagWindow:UpdateFoot() end
    end)
    for _, event in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_MONEY" }) do
        ns.RegisterEvent(self, event, function() C_Timer.After(0.1, function() BagWindow:Changed() end) end)
    end
end

ns.RegisterCommand("bags", L["open your bags in Butler's bag window, or turn it on or off (bags on|off)"], function(rest)
    rest = (rest or ""):lower()
    if rest == "on" then
        BagWindow:SetOn(true)
        ns.Print(L["Butler Bags is on."])
    elseif rest == "off" then
        BagWindow:SetOn(false)
        ns.Print(L["Butler Bags is off."])
    else
        BagWindow:Toggle()
    end
end)
