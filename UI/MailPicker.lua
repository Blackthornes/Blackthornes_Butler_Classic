-- The name picker on the mail To line (built from a mockup, 2026-11-09).
--
-- On the game's Send Mail page, a small Pick button sits right of the To
-- box. A click opens a list: LAST MAILED (the last name this account sent
-- mail to, from any character) and YOUR CHARACTERS (this realm and side,
-- whole names, the one playing left out). A click on a name puts it in the
-- To box and closes the list.
--
-- The button is Butler's own frame on UIParent, placed by screen position
-- next to the To box. Nothing is parented to, hidden, shown or written on
-- the game's mail frames; the only call into them is the To box's own
-- SetText. It hides in a fight and whenever Send Mail is not showing, and
-- it only looks while a mailbox is open.
--
-- Saved, account wide, never rename them: `namePicker` (nil reads as on)
-- and `namePickerLast` (a full name).

local _, ns = ...
local L = ns.L

local Picker = ns.NewModule("MailPicker")

local Theme = ns.Theme
local Widgets = ns.Widgets

-- How often the button looks where the To box is while a mailbox is open.
Picker.LOOK = 0.2
-- Room between the To box and the button, and the list's row height.
local GAP = 4
local ROW_HEIGHT = 22
local HEADING_HEIGHT = 20
local MENU_WIDTH = 200
local MENU_PAD = 4
-- How long the list waits after the mouse leaves before it closes.
local LEAVE_CLOSE = 0.3

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function Ask(object, method, ...)
    local fn = Field(object, method)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
    return nil
end

local function InCombat()
    local fn = rawget(_G, "InCombatLockdown")
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn)
    return ok and value and true or false
end

local function Now()
    local fn = rawget(_G, "GetTime")
    if type(fn) ~= "function" then return 0 end
    local ok, value = pcall(fn)
    return ok and tonumber(value) or 0
end

local function Trim(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    return text
end

--------------------------------------------------------------------------------
-- What the list holds
--------------------------------------------------------------------------------

function Picker:Enabled()
    return ns.db ~= nil and ns.db.namePicker ~= false
end

--- Turn the picker on or off (Settings).
function Picker:SetEnabled(on)
    if not ns.db then return end
    ns.db.namePicker = on and true or false
    self:Update()
end

--- The last name mailed, when it is not the character playing.
function Picker:LastMailed()
    local name = ns.db and Trim(ns.db.namePickerLast)
    if not name then return nil end
    if ns.Errands and ns.Errands:IsMe(name) then return nil end
    return name
end

--- The list's lines: { { heading = text } or { name = full name } }.
function Picker:Entries()
    local entries = {}
    local last = self:LastMailed()
    if last then
        entries[#entries + 1] = { heading = L["LAST MAILED"] }
        entries[#entries + 1] = { name = last }
    end
    local names = {}
    if ns.Errands then
        local ok, list = pcall(ns.Errands.Characters, ns.Errands)
        if ok and type(list) == "table" then names = list end
    end
    local listed = false
    for _, name in ipairs(names) do
        if type(name) == "string" and name ~= "" then
            if not listed then
                entries[#entries + 1] = { heading = L["YOUR CHARACTERS"] }
                listed = true
            end
            entries[#entries + 1] = { name = name }
        end
    end
    return entries
end

--------------------------------------------------------------------------------
-- Remembering the last name mailed
--------------------------------------------------------------------------------

--- From the SendMail hook: the name the mail is going to.
function Picker:Sending(recipient)
    local ok, text = pcall(tostring, recipient)
    self.pending = ok and Trim(text) or nil
end

function Picker:Sent()
    local name = self.pending
    self.pending = nil
    if not name or not ns.db then return end
    if ns.Errands and ns.Errands.FullName then
        local ok, full = pcall(ns.Errands.FullName, ns.Errands, name)
        if ok and type(full) == "string" and full ~= "" then name = full end
    end
    ns.db.namePickerLast = name
end

function Picker:Failed()
    self.pending = nil
end

--------------------------------------------------------------------------------
-- The button and the list
--------------------------------------------------------------------------------

local function DrawArrow(button)
    -- A small down arrow drawn in bars, since not every game font has one.
    local widths = { 7, 5, 3, 1 }
    for index, width in ipairs(widths) do
        local bar = button:CreateTexture(nil, "OVERLAY")
        bar:SetSize(width, 1)
        bar:SetColorTexture(Theme.Unpack("accent"))
        bar:SetPoint("RIGHT", button, "RIGHT", -6 - (7 - width) / 2, 2 - index)
    end
end

function Picker:BuildButton()
    if self.button then return self.button end
    local button = Widgets.CreateButton(UIParent, L["Pick"], function()
        Picker:Toggle()
    end, { height = 20 })
    button:SetFrameStrata("DIALOG")
    button:SetClampedToScreen(true)
    if button.label then
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", button, "LEFT", 8, 0)
    end
    local width = Theme.TextWidth and Theme.TextWidth("small", L["Pick"]) or 30
    button:SetWidth(math.max(44, (tonumber(width) or 30) + 30))
    DrawArrow(button)
    button:Hide()
    self.button = button
    return button
end

local function Heading(parent)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(HEADING_HEIGHT)
    line.text = Theme.CreateLabel(line, "small", "accent")
    line.text:SetPoint("LEFT", 8, 0)
    line.text:SetPoint("RIGHT", -8, 0)
    return line
end

local function NameRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row.fill = Theme.Fill(row, "glass")
    local rule = row:CreateTexture(nil, "BORDER")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetColorTexture(Theme.Unpack("border", 0.6))
    local edge = row:CreateTexture(nil, "OVERLAY")
    edge:SetWidth(2)
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetColorTexture(Theme.Unpack("accentHi"))
    edge:Hide()
    row.edge = edge
    row.text = Theme.CreateLabel(row, "normal", "text")
    row.text:SetPoint("LEFT", 10, 0)
    row.text:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnEnter", function(self)
        self.fill:SetColorTexture(Theme.Unpack("glassHover"))
        self.edge:Show()
        Picker.leftAt = nil
    end)
    row:SetScript("OnLeave", function(self)
        self.fill:SetColorTexture(Theme.Unpack(self.stripe or "glass"))
        self.edge:Hide()
    end)
    row:SetScript("OnClick", function(self)
        Picker:Choose(self.name)
    end)
    return row
end

function Picker:BuildMenu()
    if self.menu then return self.menu end
    local menu = CreateFrame("Frame", "BlackthornesButlerMailPicker", UIParent)
    menu:SetWidth(MENU_WIDTH)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    Theme.Fill(menu, "window")
    Theme.Border(menu, "accent")
    menu:Hide()
    menu.headings, menu.rows = {}, {}
    self.menu = menu
    return menu
end

function Picker:FillMenu(entries)
    local menu = self:BuildMenu()
    for _, line in ipairs(menu.headings) do line:Hide() end
    for _, row in ipairs(menu.rows) do row:Hide() end
    local y, headings, rows, stripe = -MENU_PAD, 0, 0, 0
    for _, entry in ipairs(entries) do
        local line
        if entry.heading then
            headings = headings + 1
            line = menu.headings[headings] or Heading(menu)
            menu.headings[headings] = line
            line.text:SetText(entry.heading)
            stripe = 0
        else
            rows = rows + 1
            line = menu.rows[rows] or NameRow(menu)
            menu.rows[rows] = line
            stripe = stripe + 1
            line.stripe = stripe % 2 == 1 and "glass" or "glassAlt"
            line.fill:SetColorTexture(Theme.Unpack(line.stripe))
            line.edge:Hide()
            line.name = entry.name
            line.text:SetText(entry.name)
        end
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_PAD, y)
        line:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -MENU_PAD, y)
        line:Show()
        y = y - (entry.heading and HEADING_HEIGHT or ROW_HEIGHT)
    end
    menu:SetHeight(-y + MENU_PAD)
end

function Picker:CloseMenu()
    if self.menu then self.menu:Hide() end
    self.leftAt = nil
end

function Picker:Toggle()
    if self.menu and self.menu:IsShown() then
        self:CloseMenu()
        return
    end
    if InCombat() or not (self.button and self.button:IsShown()) then return end
    local entries = self:Entries()
    if #entries == 0 then return end
    self:FillMenu(entries)
    local menu = self.menu
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", self.button, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

--- A click on a name: it goes in the To box, and the list closes.
function Picker:Choose(name)
    self:CloseMenu()
    if type(name) ~= "string" or name == "" or InCombat() then return end
    local box = rawget(_G, "SendMailNameEditBox")
    Ask(box, "SetText", name)
end

--------------------------------------------------------------------------------
-- Where the button sits
--------------------------------------------------------------------------------

--- True while the game's Send Mail page is up.
function Picker.SendMailShowing()
    local page = rawget(_G, "SendMailFrame")
    if not page then return false end
    local visible = Ask(page, "IsVisible")
    if visible == nil then visible = Ask(page, "IsShown") end
    return visible and true or false
end

--- The To box's right edge and middle on UIParent, or nil.
function Picker.BoxSpot()
    local box = rawget(_G, "SendMailNameEditBox")
    if not box then return nil end
    local right = tonumber(Ask(box, "GetRight"))
    local top = tonumber(Ask(box, "GetTop"))
    local bottom = tonumber(Ask(box, "GetBottom"))
    if not (right and top and bottom) then return nil end
    local boxScale = tonumber(Ask(box, "GetEffectiveScale")) or 1
    local uiScale = tonumber(Ask(UIParent, "GetEffectiveScale")) or 1
    if uiScale <= 0 then uiScale = 1 end
    local ratio = boxScale / uiScale
    return right * ratio, (top + bottom) / 2 * ratio
end

function Picker:Hide()
    if self.button then self.button:Hide() end
    self:CloseMenu()
end

function Picker:Update()
    if not self:Enabled() or not self.atMailbox or InCombat()
        or not Picker.SendMailShowing() then
        self:Hide()
        return
    end
    local x, y = Picker.BoxSpot()
    if not x or #self:Entries() == 0 then
        self:Hide()
        return
    end
    local button = self:BuildButton()
    if self.spotX ~= x or self.spotY ~= y or not button:IsShown() then
        button:ClearAllPoints()
        button:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x + GAP, y)
        self.spotX, self.spotY = x, y
    end
    button:Show()
    -- The list closes a moment after the mouse leaves it and the button.
    local menu = self.menu
    if menu and menu:IsShown() then
        local over = Ask(menu, "IsMouseOver") or Ask(button, "IsMouseOver")
        if over then
            self.leftAt = nil
        elseif not self.leftAt then
            self.leftAt = Now()
        elseif Now() - self.leftAt >= LEAVE_CLOSE then
            self:CloseMenu()
        end
    end
end

--- A frame of our own that looks only while a mailbox is open.
function Picker:Watch(on)
    self.atMailbox = on and true or false
    if not self.watcher then
        self.watcher = CreateFrame("Frame")
        self.watcher.wait = 0
    end
    local watcher = self.watcher
    if on then
        watcher.wait = 0
        watcher:SetScript("OnUpdate", function(frame, elapsed)
            frame.wait = frame.wait - (tonumber(elapsed) or 0)
            if frame.wait > 0 then return end
            frame.wait = Picker.LOOK
            Picker:Update()
        end)
    else
        watcher:SetScript("OnUpdate", nil)
    end
    self:Update()
end

function Picker:OnEnable()
    ns.RegisterEvent(self, "MAIL_SHOW", function() Picker:Watch(true) end)
    ns.RegisterEvent(self, "MAIL_CLOSED", function() Picker:Watch(false) end)
    ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, _, kind)
        if ns.Errands and ns.Errands.InteractionPlace(kind) == "mail" then
            Picker:Watch(false)
        end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function() Picker:Hide() end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function() Picker:Update() end)
    ns.RegisterEvent(self, "MAIL_SEND_SUCCESS", function() Picker:Sent() end)
    ns.RegisterEvent(self, "MAIL_FAILED", function() Picker:Failed() end)
    if type(rawget(_G, "hooksecurefunc")) == "function"
        and type(rawget(_G, "SendMail")) == "function" then
        pcall(hooksecurefunc, "SendMail", function(recipient)
            Picker:Sending(recipient)
        end)
    end
end
