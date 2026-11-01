-- Blackthornes Butler -- UI/Widgets.lua
-- The controls the windows need: a button, a checkbox, a stepper, a search
-- box and the scrolling row list, with the small tweens that make them feel
-- alive. Farmer's Widgets.lua, trimmed to those, so the pages feel the same
-- under the mouse.

local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local Theme = ns.Theme

--------------------------------------------------------------------------------
-- Motion
--
-- Small tweens for the windows and controls: a button easing into its hover
-- colour, a window fading up as it opens. Off means every tween lands at its
-- end at once.
--
-- One OnUpdate on one small frame, shown only while something is moving, so
-- an idle window costs nothing per frame. A tween that errors is dropped
-- rather than raised: a hover colour must never break a click.
--------------------------------------------------------------------------------

local Motion = {}
ns.Motion = Motion

Motion.tweens = {}

--- The Effects setting: Full, Subtle or Off, from most movement to none
--- (the owner, 2026-10-29: Butler's own Effects row, as its sisters have).
--- Full until the player picks another, so nobody's windows change.
Motion.LEVELS = { "full", "subtle", "off" }

--- "full", "subtle" or "off", as the player picked it.
function Motion.Level()
    local level = ns.db and ns.db.effectsLevel
    if level == "subtle" or level == "off" then return level end
    return "full"
end

function Motion.SetLevel(level)
    if not ns.db then return end
    ns.db.effectsLevel = (level == "subtle" or level == "off") and level or nil
    if ns.SharedChoices then ns.SharedChoices:Changed("effects", ns.db.effectsLevel or "full") end
end

function Motion.EaseOut(p)
    return 1 - (1 - p) ^ 3
end

--- Overshoots a touch and settles, for things that should feel like they
--- landed.
function Motion.EaseOutBack(p)
    local c = 1.4
    return 1 + (c + 1) * (p - 1) ^ 3 + c * (p - 1) ^ 2
end

function Motion.Lerp(from, to, p)
    return from + (to - from) * p
end

--- Two palette colours mixed, `p` of the way from `a` to `b`.
function Motion.Mix(a, b, p, alphaA, alphaB)
    local r1, g1, b1, a1 = Theme.Unpack(a, alphaA)
    local r2, g2, b2, a2 = Theme.Unpack(b, alphaB)
    return r1 + (r2 - r1) * p, g1 + (g2 - g1) * p, b1 + (b2 - b1) * p, a1 + (a2 - a1) * p
end

function Motion:Driver()
    if self.driver then return self.driver end

    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) Motion:Step(elapsed) end)
    driver:Hide()

    self.driver = driver
    return driver
end

local function Finish(tween)
    pcall(tween.apply, 1)
    if tween.done then pcall(tween.done) end
end

--- Run `apply(p)` with p going 0 to 1 over `duration` seconds.
--
-- `owner` and `slot` name the tween: a new one for the same owner and slot
-- replaces the old, so hovering on and off quickly never leaves two fighting.
-- opts: delay (seconds before it starts), done (called at the end), ease
-- (a function of p; EaseOut unless given, false for linear).
function Motion:Run(owner, slot, duration, apply, opts)
    opts = opts or {}

    self:Stop(owner, slot)

    local tween = { owner = owner, slot = slot, duration = duration or 0.2,
        apply = apply, done = opts.done, age = -(opts.delay or 0) }

    local ease = opts.ease
    if ease == nil then ease = Motion.EaseOut end
    tween.ease = ease or nil

    if self.Level() == "off" or tween.duration <= 0 then
        Finish(tween)
        return
    end

    -- Drawn at its start now, so nothing flashes at its end for a frame
    -- before the first step.
    pcall(apply, 0)

    self.tweens[#self.tweens + 1] = tween
    self:Driver():Show()
end

--- Stop a running tween where it is. `finish` lands it at its end first.
function Motion:Stop(owner, slot, finish)
    for index = #self.tweens, 1, -1 do
        local tween = self.tweens[index]
        if tween.owner == owner and (slot == nil or tween.slot == slot) then
            table.remove(self.tweens, index)
            if finish then Finish(tween) end
        end
    end
end

--- Whether a tween is running for this owner (and slot, when given).
function Motion:Running(owner, slot)
    for _, tween in ipairs(self.tweens) do
        if tween.owner == owner and (slot == nil or tween.slot == slot) then return true end
    end
    return false
end

--- Land every running tween at its end. For the tests, and for a window
--- being hidden mid-animation.
function Motion:FinishAll()
    local tweens = self.tweens
    self.tweens = {}
    for _, tween in ipairs(tweens) do Finish(tween) end
    if self.driver then self.driver:Hide() end
end

function Motion:Step(elapsed)
    elapsed = tonumber(elapsed) or 0

    local live = {}
    local tweens = self.tweens
    self.tweens = live

    for _, tween in ipairs(tweens) do
        tween.age = tween.age + elapsed

        if tween.age >= 0 then
            local p = math.min(1, tween.age / tween.duration)
            local eased = tween.ease and tween.ease(p) or p
            local ok = pcall(tween.apply, eased)

            if not ok or p >= 1 then
                if ok and tween.done then pcall(tween.done) end
            else
                live[#live + 1] = tween
            end
        else
            live[#live + 1] = tween
        end
    end

    -- Tweens started from inside an apply or done landed in `live` already.
    if #self.tweens == 0 and self.driver then self.driver:Hide() end
end

--- Ease a number kept on `owner` toward `target`, calling `apply(value)` as
--- it goes. Starts from wherever the last one left it, so a hover that is
--- undone halfway turns round smoothly instead of jumping.
function Motion:Blend(owner, slot, target, duration, apply)
    local from = self:Value(owner, slot)
    if from == target and not self:Running(owner, slot) then
        apply(target)
        return
    end

    self:Run(owner, slot, duration, function(p)
        local value = from + (target - from) * p
        self:SetValue(owner, slot, value)
        apply(value)
    end, { ease = false })
end

-- Blended values, kept here rather than as fields on the frames so they never
-- collide with a frame's own keys.
Motion.values = setmetatable({}, { __mode = "k" })

--- Where Blend last left `owner`'s `slot`: 0 until it has moved.
function Motion:Value(owner, slot)
    local values = self.values[owner]
    return values and values[slot] or 0
end

function Motion:SetValue(owner, slot, value)
    local values = self.values[owner]
    if not values then
        values = {}
        self.values[owner] = values
    end
    values[slot] = value
end

--- Fade a window up as it opens: from clear, and a few pixels low.
--
-- Only the alpha and one point's offset move, so the window's saved spot is
-- never touched: the last step puts back exactly the point it started with.
function Motion:Open(frame, rise)
    if not frame then return end

    local level = self.Level()
    if level == "off" then
        frame:SetAlpha(1)
        return
    end

    rise = level == "full" and (rise or 8) or 0

    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local canMove = rise ~= 0 and point ~= nil and type(x) == "number" and type(y) == "number"

    self:Run(frame, "open", level == "full" and 0.2 or 0.12, function(p)
        frame:SetAlpha(p)
        if canMove then
            frame:SetPoint(point, relativeTo, relativePoint, x, y - rise * (1 - p))
        end
    end)
end

--------------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------------

local HOVER_TIME = 0.12

--- A button in the house style.
--
-- opts: width, height; primary (solid gold with dark lettering, for the one
-- button on a screen that does the main thing); danger (lights red under
-- the mouse, for a close button); labelKey (the label's resting colour);
-- baseColor ({ r, g, b, a }, a resting face of its own); name and template,
-- for a button built on one of the game's templates (a secure action button,
-- say, which must then be given no onClick).
--
-- Titanforged (2026-10-04, as Tradeskills'): every button is raised metal,
-- a dark face in a gold edge with a gold label, lit and glowing under the
-- mouse. The primary one is solid gold, so it stands out at a glance.
function Widgets.CreateButton(parent, text, onClick, opts)
    opts = opts or {}

    local button = CreateFrame("Button", opts.name, parent, opts.template)
    button:SetSize(opts.width or 80, opts.height or 22)

    -- Dark lettering only on a gold face: a primary button given its own
    -- dark face (opts.baseColor) keeps a gold label, or its text would be
    -- dark on dark and the button would read as an empty box.
    -- The Blizzard window style has no gold face: every button wears the
    -- game's red with a gold label (UI/BlizzardLook.lua). A client missing
    -- that art keeps the house face, so the label is picked to suit it.
    local Look = ns.BlizzardLook
    local blizzard = Look and Look.DressesButtons()
    local goldFace = opts.primary and not opts.baseColor and not blizzard

    local baseKey = goldFace and "accent" or "row"
    local hotFill = goldFace and "accentHi" or opts.danger and "rowHover" or "rowActive"
    local edgeKey = goldFace and "accentHi" or "metal"
    local hotEdge = (opts.danger and "loss") or "accentHi"
    local defaultLabel = goldFace and "ink" or "gilt"
    local defaultHot = goldFace and "ink" or { 1, 0.953, 0.784 }
    local labelKey = opts.labelKey or defaultLabel
    local labelHot = opts.labelKey or defaultHot

    button.background = Theme.Fill(button, baseKey)
    -- Kept on the button, so the Blizzard style leaves a face of its own be.
    button.baseColor = opts.baseColor
    if opts.baseColor then
        button.background:SetColorTexture(unpack(opts.baseColor))
    end
    Theme.Border(button, edgeKey)
    button.sheen = Theme.TopSheen(button, 0.10)
    if Theme.Bevel then button.bevel = { Theme.Bevel(button) } end

    -- Every button glows round its edge under the mouse; the primary one
    -- glows a little even at rest. A button with a face of its own keeps to
    -- its own look.
    local haloRest = goldFace and 0.12 or 0
    if Theme.Halo and not opts.baseColor then
        Theme.Halo(button, 5, haloRest, opts.danger and "loss" or "accent")
    end

    button.label = Theme.CreateLabel(button, "small", labelKey, "CENTER")
    button.label:SetPoint("CENTER")
    button.label:SetText(text)

    -- Never narrower than its text: the game's font runs wider than a width
    -- picked by eye.
    local function Fit(value)
        button:SetWidth(math.max(opts.width or 80, Theme.TextWidth("small", value) + 12))
    end
    Fit(text)

    --- A palette key or an { r, g, b } colour, as four numbers.
    local function Color(value)
        if type(value) == "table" then return value[1], value[2], value[3], value[4] or 1 end
        return Theme.Unpack(value)
    end

    local function Blend(a, b, p)
        local r1, g1, b1, a1 = Color(a)
        local r2, g2, b2, a2 = Color(b)
        return r1 + (r2 - r1) * p, g1 + (g2 - g1) * p, b1 + (b2 - b1) * p, a1 + (a2 - a1) * p
    end

    --- How lit the button is: 0 at rest, 1 under the mouse.
    local function Light(p)
        local face = opts.baseColor or baseKey
        local hot = opts.baseColor and "rowHover" or hotFill
        button.background:SetColorTexture(Blend(face, hot, p))

        local r, g, b, a = Motion.Mix(edgeKey, hotEdge, p)
        for _, edge in ipairs(button.borderTextures or {}) do
            edge:SetColorTexture(r, g, b, a)
        end

        if opts.danger then
            button.label:SetTextColor(Blend(labelKey, "loss", p))
        else
            button.label:SetTextColor(Blend(labelKey, labelHot, p))
        end

        if rawget(button, "haloTextures") then
            Theme.SetHalo(button, haloRest + (0.4 - haloRest) * p)
        end
    end
    button.Light = Light

    button:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, HOVER_TIME, Light)
    end)

    button:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, HOVER_TIME * 1.5, Light)
    end)

    -- The label dips a pixel while held, so a click feels pressed. Wherever
    -- the label was put (a caller may have moved it beside an icon), it
    -- goes back to exactly there.
    button:SetScript("OnMouseDown", function(self)
        -- Held, for the Blizzard style's pressed art.
        self.held = true
        local point, relativeTo, relativePoint, x, y = self.label:GetPoint(1)
        if not (point and type(x) == "number" and type(y) == "number") then return end

        self.restPoint = { point, relativeTo, relativePoint, x, y }
        self.label:SetPoint(point, relativeTo, relativePoint, x, y - 1)
    end)

    button:SetScript("OnMouseUp", function(self)
        self.held = nil
        local rest = rawget(self, "restPoint")
        if not rest then return end

        self.restPoint = nil
        self.label:SetPoint(rest[1], rest[2], rest[3], rest[4], rest[5])
    end)

    if onClick then
        button:SetScript("OnClick", function(self, mouseButton)
            onClick(self, mouseButton)
        end)
    end

    function button:SetText(value)
        self.label:SetText(value)
        Fit(value)
    end

    --- The label's resting colour, for a button whose text means something
    --- (an upgrade in green, say), which it keeps under the mouse. No key
    --- puts back the house colour.
    function button:SetLabelColor(key)
        labelKey = key or defaultLabel
        labelHot = key or defaultHot
        Light(Motion:Value(self, "hover"))
    end

    if blizzard then Look.Button(button) end

    return button
end

--------------------------------------------------------------------------------
-- Checkbox
--------------------------------------------------------------------------------

--- A square toggle with its label beside it. Ported from the tradeskills addon
--- so the two settings pages feel the same under the mouse.
function Widgets.CreateCheckbox(parent, text, onToggle, initial)
    local checkbox = CreateFrame("Button", nil, parent)
    checkbox:SetHeight(18)

    local box = CreateFrame("Frame", nil, checkbox)
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    -- A small dark well in a gold edge, glowing when ticked (Titanforged).
    box.background = Theme.Fill(box, "well")
    Theme.Border(box, "metal")
    if Theme.Halo then Theme.Halo(box, 4, 0) end

    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("CENTER")
    tick:SetSize(8, 8)
    tick:SetColorTexture(Theme.Unpack("accentHi"))

    local label = Theme.CreateLabel(checkbox, "small", "text")
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    label:SetText(text)

    checkbox.label = label
    checkbox.tick = tick
    -- Measured as the game draws it, so the label is never cut short.
    checkbox:SetWidth(math.max(Theme.TextWidth("small", text), label:GetStringWidth() or 60) + 24)
    checkbox.checked = initial and true or false
    checkbox.disabled = false

    --- The box's edge and glow: lit gold when ticked, gold under the mouse,
    --- dim metal otherwise.
    local function PaintBox(hovered)
        local checked = checkbox.checked
        tick:SetShown(checked)
        Theme.SetBorderColor(box, checked and "accentHi" or hovered and "accent" or "metal")
        if rawget(box, "haloTextures") then
            Theme.SetHalo(box, checked and not checkbox.disabled and 0.3 or hovered and 0.15 or 0)
        end
    end
    PaintBox(false)

    function checkbox:SetChecked(value)
        self.checked = value and true or false
        PaintBox(false)
    end

    function checkbox:GetChecked()
        return self.checked
    end

    --- A disabled box keeps showing its state but ignores clicks, for a
    --- setting this client cannot honour.
    function checkbox:SetDisabled(disabled)
        self.disabled = disabled and true or false
        label:SetTextColor(Theme.Unpack(self.disabled and "dim" or "text"))
        -- In the Blizzard style the house tick stays out of sight.
        if not rawget(self, "blizzard") then tick:SetAlpha(self.disabled and 0.4 or 1) end
        PaintBox(false)
    end

    checkbox:SetScript("OnClick", function(self)
        if self.disabled then return end
        self:SetChecked(not self.checked)

        -- Ticking pops the mark in from small, a touch past size and back.
        if self.checked then
            Motion:Run(self, "tick", 0.22, function(p)
                local size = math.max(1, 8 * p)
                tick:SetSize(size, size)
            end, { ease = Motion.EaseOutBack })
        end

        if onToggle then onToggle(self.checked) end
    end)

    checkbox:SetScript("OnEnter", function(self)
        if not self.disabled then
            label:SetTextColor(Theme.Unpack("accent"))
            PaintBox(true)
        end
    end)

    checkbox:SetScript("OnLeave", function(self)
        label:SetTextColor(Theme.Unpack(self.disabled and "dim" or "text"))
        PaintBox(false)
    end)

    if ns.BlizzardLook and ns.BlizzardLook.Checkbox(checkbox, box, tick) then
        checkbox.blizzard = true
    end

    return checkbox
end

--------------------------------------------------------------------------------
-- Stepper
--------------------------------------------------------------------------------

--- [-] value [+], for a number with a small sensible range such as a scale.
--
-- Chosen over a slider: a slider on this client needs a thumb texture and a
-- drag to land on a round number, and a stepper only ever holds values from
-- its own list of steps.
--
-- @param opts
--   min, max, step  the range, in the stored unit
--   format          function(value) -> text shown between the buttons
--   onChange        function(value)
function Widgets.CreateStepper(parent, opts)
    opts = opts or {}

    local stepper = CreateFrame("Frame", nil, parent)
    stepper:SetSize(118, 20)

    local minus = Widgets.CreateButton(stepper, "-", nil, { width = 22, height = 20 })
    minus:SetPoint("LEFT")

    local plus = Widgets.CreateButton(stepper, "+", nil, { width = 22, height = 20 })
    plus:SetPoint("RIGHT")

    local well = Theme.CreatePanel(stepper, "panel", "border")
    well:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    well:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    well:SetHeight(20)
    -- Sunk between its buttons (Titanforged).
    if Theme.Recess then Theme.Recess(well) end

    local text = Theme.CreateLabel(well, "small", "text", "CENTER")
    text:SetPoint("CENTER")

    stepper.minus = minus
    stepper.plus = plus
    stepper.text = text

    local step = opts.step or 1
    local low = opts.min or 0
    local high = opts.max or 100

    local function Clamp(value)
        -- Snapped to a whole number of steps, so repeated presses never drift
        -- to 0.8999999 and show a value that is not on the list.
        value = low + math.floor((value - low) / step + 0.5) * step
        return math.max(low, math.min(high, value))
    end

    function stepper:SetValue(value, silent)
        self.value = Clamp(tonumber(value) or low)
        text:SetText(opts.format and opts.format(self.value) or tostring(self.value))

        -- Dim at the end of the range; the house gold otherwise.
        minus:SetLabelColor(self.value <= low and "dim" or nil)
        plus:SetLabelColor(self.value >= high and "dim" or nil)

        if not silent and opts.onChange then opts.onChange(self.value) end
    end

    function stepper:GetValue()
        return self.value
    end

    local function Nudge(direction)
        local wanted = Clamp((stepper.value or low) + direction * step)
        if wanted ~= stepper.value then stepper:SetValue(wanted) end
    end

    minus:SetScript("OnClick", function() Nudge(-1) end)
    plus:SetScript("OnClick", function() Nudge(1) end)

    stepper:SetValue(opts.value or low, true)
    return stepper
end

--------------------------------------------------------------------------------
-- Drop-down
--
-- Pets' (itself Tradeskills'), for the word choices in Settings: the owner,
-- 2026-10-23, drop-downs, never < > pickers.
--------------------------------------------------------------------------------

local MENU_ROWS = 12
local MENU_ROW_HEIGHT = 20

--- A box that opens a menu of options, each { text, value }; a click on one
--- picks it and calls onSelect(value, option). opts.width sets the box's
--- width; Widgets.DropdownWidth measures one that fits every option.
function Widgets.CreateDropdown(parent, options, onSelect, opts)
    opts = opts or {}

    local dropdown = Theme.CreatePanel(parent, "row")
    dropdown:SetSize(opts.width or 140, 22)
    dropdown:EnableMouse(true)
    Theme.TopSheen(dropdown)

    local label = Theme.CreateLabel(dropdown, "small", "text")
    label:SetPoint("LEFT", 6, 0)
    label:SetPoint("RIGHT", -18, 0)
    dropdown.label = label

    -- A small solid arrow pointing down, four rows of plain colour (7, 5, 3
    -- and 1 pixels wide), so it needs no texture file.
    local arrow = {}
    for row = 0, 3 do
        local bar = dropdown:CreateTexture(nil, "ARTWORK")
        bar:SetSize(7 - row * 2, 1)
        bar:SetPoint("TOPLEFT", dropdown, "RIGHT", -13 + row, 2 - row)
        bar:SetColorTexture(Theme.Unpack("muted"))
        arrow[#arrow + 1] = bar
    end

    local menu = Theme.CreatePanel(parent, "panel", "borderLit")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menu:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -2)
    menu:EnableMouse(true)
    menu:Hide()
    dropdown.menu = menu

    -- The first option a long menu shows, and a slim bar saying how far
    -- through the list that is.
    menu.first = 1
    local thumb = menu:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(Theme.Unpack("borderLit"))
    thumb:Hide()

    dropdown.options = options or {}
    dropdown.selected = nil

    local entries = {}
    dropdown.entries = entries

    local function Rebuild()
        local count = #dropdown.options
        local shown = math.min(count, MENU_ROWS)
        local scrolls = count > shown
        menu.first = math.max(1, math.min(menu.first or 1, count - shown + 1))

        for index, option in ipairs(dropdown.options) do
            local entry = entries[index]
            if not entry then
                entry = CreateFrame("Button", nil, menu)
                entry:SetHeight(MENU_ROW_HEIGHT)
                -- Drawn in full and faded with SetAlpha: made with a colour
                -- alpha of 0, no hover ever showed (Tradeskills).
                entry.highlight = Theme.Fill(entry, "rowHover", nil, "ARTWORK")
                entry.highlight:SetAlpha(0)
                entry.label = Theme.CreateLabel(entry, "small", "text")
                entry.label:SetPoint("LEFT", 8, 0)
                entry.label:SetPoint("RIGHT", -8, 0)
                entry.mark = Theme.AccentStripe(entry, 2)
                entry.mark:Hide()

                local function Light(value) entry.highlight:SetAlpha(value) end
                entry:SetScript("OnEnter", function(self) Motion:Blend(self, "hover", 1, 0.08, Light) end)
                entry:SetScript("OnLeave", function(self) Motion:Blend(self, "hover", 0, 0.15, Light) end)
                entries[index] = entry
            end

            local slot = index - menu.first
            if slot >= 0 and slot < shown then
                local y = -4 - slot * MENU_ROW_HEIGHT
                entry:SetPoint("TOPLEFT", 1, y)
                entry:SetPoint("TOPRIGHT", scrolls and -7 or -1, y)
                entry.label:SetText(option.text)
                local on = option.value == dropdown.selected
                entry.label:SetTextColor(Theme.Unpack(on and "accent" or "text"))
                entry.mark:SetShown(on)
                entry.option = option
                entry:Show()
            else
                entry:Hide()
            end

            entry:SetScript("OnClick", function()
                -- A choice (Widgets.CreateChoice) calls its own onChange.
                if rawget(dropdown, "Pick") then return dropdown:Pick(option.value) end
                dropdown:SetValue(option.value)
                menu:Hide()
                if onSelect then onSelect(option.value, option) end
            end)
        end
        for index = count + 1, #entries do entries[index]:Hide() end

        menu:SetHeight(math.max(8, shown * MENU_ROW_HEIGHT + 8))

        thumb:SetShown(scrolls)
        if scrolls then
            local track = shown * MENU_ROW_HEIGHT
            local size = math.max(12, math.floor(track * shown / count))
            local offset = math.floor((track - size) * (menu.first - 1) / (count - shown) + 0.5)
            thumb:SetHeight(size)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", -2, -4 - offset)
        end
    end

    --- New options; the choice stays when it is still one of them.
    function dropdown:SetOptions(newOptions)
        self.options = newOptions or {}
        local value = self.options[1] and self.options[1].value
        for _, option in ipairs(self.options) do
            if option.value == self.selected then value = self.selected break end
        end
        self:SetValue(value)
        if menu:IsShown() then Rebuild() end
    end

    --- Show `value` as the choice, without calling onSelect.
    function dropdown:SetValue(value)
        self.selected = value
        for _, option in ipairs(self.options) do
            if option.value == value then
                label:SetText(option.text)
                return
            end
        end
        label:SetText(opts.placeholder or "")
    end

    function dropdown:GetValue()
        return self.selected
    end

    --- Down from the box, or up from it when the screen has no room below.
    local function Place()
        local up = false
        pcall(function()
            local scale = dropdown:GetEffectiveScale()
            local need = (menu:GetHeight() + 2) * scale
            local below = dropdown:GetBottom() * scale
            local above = UIParent:GetTop() * UIParent:GetEffectiveScale() - dropdown:GetTop() * scale
            up = below < need and above >= need
        end)
        menu:ClearAllPoints()
        if up then
            menu:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
            menu:SetPoint("BOTTOMRIGHT", dropdown, "TOPRIGHT", 0, 2)
        else
            menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
            menu:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -2)
        end
    end

    function dropdown:Toggle()
        if menu:IsShown() then
            menu:Hide()
            return
        end
        -- A long menu opens with the choice in view, near its middle.
        menu.first = 1
        for index, option in ipairs(self.options) do
            if option.value == self.selected then
                menu.first = index - math.floor(MENU_ROWS / 2)
                break
            end
        end
        -- On UIParent at the box's own scale while open, so a list that
        -- scrolls (Settings' pages) can't cut it off at its edge.
        pcall(function()
            if not UIParent then return end
            if menu:GetParent() ~= UIParent then menu:SetParent(UIParent) end
            local scale = dropdown:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if type(scale) == "number" and scale > 0 then menu:SetScale(scale) end
        end)
        Rebuild()
        Place()
        -- Laid into the one window, the box's window takes that window's
        -- strata, and the menu with it, so the rows under the box drew over
        -- the open list. Lift it again each time it opens.
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:Show()
        menu:Raise()
        Motion:Run(menu, "open", 0.12, function(p) menu:SetAlpha(p) end)
    end

    dropdown:SetScript("OnMouseDown", function(self) self:Toggle() end)

    -- The wheel moves a long menu a row at a time.
    menu:EnableMouseWheel(true)
    menu:SetScript("OnMouseWheel", function(_, delta)
        local count = #dropdown.options
        if count <= MENU_ROWS then return end
        local step = (tonumber(delta) or 0) > 0 and -1 or 1
        local first = math.max(1, math.min(count - MENU_ROWS + 1, menu.first + step))
        if first ~= menu.first then
            menu.first = first
            Rebuild()
        end
    end)

    -- A click anywhere else closes the menu, as the game's own menus do. The
    -- event is asked for only while the menu is open, and inside a pcall: a
    -- client that does not know it raises, and the menu then stays open
    -- until picked from or clicked shut.
    menu:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnEvent", function(self)
        if self:IsMouseOver() or dropdown:IsMouseOver() then return end
        self:Hide()
    end)

    -- Its window closing takes the menu with it.
    dropdown:SetScript("OnHide", function() menu:Hide() end)

    --- How lit the box is under the mouse: its edge and its arrow.
    local function Light(p)
        local r, g, b = Motion.Mix("border", "borderLit", p)
        for _, edge in ipairs(dropdown.borderTextures or {}) do edge:SetColorTexture(r, g, b, 1) end
        local ar, ag, ab = Motion.Mix("muted", "accent", p)
        for _, bar in ipairs(arrow) do bar:SetColorTexture(ar, ag, ab, 1) end
    end
    dropdown:SetScript("OnEnter", function(self) Motion:Blend(self, "hover", 1, 0.12, Light) end)
    dropdown:SetScript("OnLeave", function(self) Motion:Blend(self, "hover", 0, 0.18, Light) end)

    dropdown:SetValue(nil)
    return dropdown
end

--- A drop-down in a stepper's place, for a setting that picks one of a
--- few words (the owner, 2026-10-23: drop-downs, never < > pickers). It
--- takes a stepper's opts (min, max, step, value, format, onChange) and
--- answers its calls: SetValue(value, silent), GetValue() and .text, so a
--- row swaps one for the other and nothing else changes. Number boxes stay
--- steppers. choice:Pick(value) is what a click on a line of its menu does.
function Widgets.CreateChoice(parent, opts)
    opts = opts or {}
    local step = opts.step or 1
    local low = opts.min or 0
    local high = opts.max or 100

    local function Clamp(value)
        value = low + math.floor((value - low) / step + 0.5) * step
        return math.max(low, math.min(high, value))
    end
    local function Words(value)
        return opts.format and opts.format(value) or tostring(value)
    end

    local options = {}
    for value = low, high, step do
        options[#options + 1] = { text = Words(value), value = value }
    end

    local choice = Widgets.CreateDropdown(parent, options, nil,
        { width = opts.width or Widgets.DropdownWidth(options, 100) })
    choice.text = choice.label

    local Show = choice.SetValue
    function choice:SetValue(value, silent)
        self.value = Clamp(tonumber(value) or low)
        -- The words are read again each time, since some follow the game
        -- (a level, a spec) and not only the value.
        for _, option in ipairs(self.options) do option.text = Words(option.value) end
        Show(self, self.value)
        if not silent and opts.onChange then opts.onChange(self.value) end
    end

    function choice:GetValue()
        return self.value
    end

    function choice:Pick(value)
        if self.menu then self.menu:Hide() end
        if Clamp(tonumber(value) or low) ~= self.value then self:SetValue(value) end
    end

    choice:SetValue(opts.value or low, true)
    return choice
end

--- A dropdown width that fits every option's words, never below `least`.
function Widgets.DropdownWidth(options, least)
    local widest = 0
    for _, option in ipairs(options or {}) do
        widest = math.max(widest, Theme.TextWidth("small", option.text))
    end
    return math.max(least or 0, math.ceil(widest) + 30)
end


--------------------------------------------------------------------------------
-- Search box
--
-- Farmer's, for Find a setting.
--------------------------------------------------------------------------------

--- Whether the mouse is on `frame` and the frame is on screen. Read in a
--- pcall, as every client value is; a client that cannot say answers no.
local function UnderMouse(frame)
    local ok, over = pcall(function() return frame:IsVisible() and frame:IsMouseOver() end)
    return ok and over and true or false
end

--- An edit box with placeholder text.
--
-- onChange fires on every keystroke so results follow typing; onAccept fires on
-- Enter. Escape clears focus rather than the text, because losing what you
-- typed on a mis-key is worse than an extra keystroke.
--
-- opts.plain leaves out the magnifier and the clear button, for a small box
-- that is not a search: the room they keep is most of a narrow box.
function Widgets.CreateSearchBox(parent, placeholder, onChange, onAccept, opts)
    opts = opts or {}
    local inset = opts.plain and 6 or 26

    local holder = Theme.CreatePanel(parent, "row", "border")
    holder:SetHeight(24)

    -- Sunk into the window, and glowing gold while it has the keyboard
    -- (Titanforged, as Tradeskills' search box).
    if Theme.Recess then Theme.Recess(holder) end
    if Theme.Halo then Theme.Halo(holder, 6, 0) end

    -- The game's own magnifier, so the box reads as search at a glance.
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 7, 0)
    icon:SetTexture([[Interface\Common\UI-Searchbox-Icon]])
    icon:SetVertexColor(Theme.Unpack("muted"))
    icon:SetShown(not opts.plain)
    holder.icon = icon

    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("TOPLEFT", inset, 0)
    box:SetPoint("BOTTOMRIGHT", -inset, 0)
    box:SetAutoFocus(false)
    box:SetFont(Theme.FONT, Theme.sizes.normal, "")
    box:SetTextColor(Theme.Unpack("text"))
    box:SetMaxLetters(80)

    local hint = Theme.CreateLabel(holder, "normal", "dim")
    hint:SetPoint("LEFT", inset, 0)
    hint:SetText(placeholder or "")

    -- Clears what you typed in one click, and only shows when there is
    -- something to clear.
    local clear = CreateFrame("Button", nil, holder)
    clear:SetSize(20, 20)
    clear:SetPoint("RIGHT", -3, 0)
    local cross = Theme.CreateLabel(clear, "normal", "muted", "CENTER")
    cross:SetPoint("CENTER", 0, 0)
    cross:SetText("x")
    clear:Hide()
    holder.clear = clear

    local function UpdateHint()
        local empty = box:GetText() == ""
        hint:SetShown(empty)
        clear:SetShown(not empty and not opts.plain)
    end

    --- The edge and the magnifier, from how far the mouse and the keyboard
    --- have each eased in: the edge lifts under the mouse and turns gold
    --- while the box has the keyboard, and the keyboard's gold wins.
    local function Paint()
        local hover = Motion:Value(holder, "hover")
        local focus = Motion:Value(holder, "focus")

        local r1, g1, b1 = Motion.Mix("border", "borderLit", hover)
        local r2, g2, b2 = Theme.Unpack("accent")
        local r, g, b = r1 + (r2 - r1) * focus, g1 + (g2 - g1) * focus, b1 + (b2 - b1) * focus
        for _, edge in ipairs(holder.borderTextures or {}) do
            edge:SetColorTexture(r, g, b, 1 - 0.2 * focus)
        end
        if rawget(holder, "haloTextures") then Theme.SetHalo(holder, 0.3 * focus) end

        icon:SetVertexColor(Motion.Mix("muted", "accent", math.max(focus, hover * 0.4)))
    end

    --- The mouse came onto part of the box or left it. Lit while it is
    --- anywhere on the box: going from the margin onto the text, or onto
    --- the x, is a leave and an enter of their own.
    local function Hover()
        local over = UnderMouse(holder)
        Motion:Blend(holder, "hover", over and 1 or 0, over and 0.12 or 0.18, Paint)
    end

    holder:EnableMouse(true)
    holder:SetScript("OnEnter", Hover)
    holder:SetScript("OnLeave", Hover)
    box:SetScript("OnEnter", Hover)
    box:SetScript("OnLeave", Hover)
    -- The margin answers the mouse now, so a click there (on the
    -- magnifier, say) gives the box the keyboard rather than nothing.
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)

    -- The x lifts to the text colour under the mouse, eased like the rest.
    local function LightCross(p)
        cross:SetTextColor(Motion.Mix("muted", "text", p))
    end
    clear:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, LightCross)
        Hover()
    end)
    clear:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, LightCross)
        Hover()
    end)

    -- Hidden under the mouse (its window closing, or the x going with the
    -- text it cleared), no leave may come: let go, or it shows again lit.
    local function LetGo(frame, apply)
        Motion:Stop(frame, "hover")
        Motion:SetValue(frame, "hover", 0)
        apply(0)
    end
    holder:SetScript("OnHide", function() LetGo(holder, Paint) end)
    clear:SetScript("OnHide", function() LetGo(clear, LightCross) end)

    box:SetScript("OnEditFocusGained", function()
        Motion:Blend(holder, "focus", 1, 0.15, Paint)
    end)

    box:SetScript("OnEditFocusLost", function()
        Motion:Blend(holder, "focus", 0, 0.2, Paint)
    end)

    box:SetScript("OnTextChanged", function(self, userInput)
        UpdateHint()
        if userInput and onChange then
            onChange(self:GetText())
        end
    end)

    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onAccept then onAccept(self:GetText()) end
    end)

    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    clear:SetScript("OnClick", function()
        box:SetText("")
        UpdateHint()
        if onChange then onChange("") end
        box:SetFocus()
    end)

    holder.editBox = box

    function holder:SetText(value)
        box:SetText(value or "")
        UpdateHint()
    end

    function holder:GetText()
        return box:GetText()
    end

    function holder:SetFocus()
        box:SetFocus()
    end

    function holder:ClearFocus()
        box:ClearFocus()
    end

    UpdateHint()
    return holder
end

--------------------------------------------------------------------------------
-- Money box
--------------------------------------------------------------------------------

-- The coin colours FormatMoney uses, so the boxes read as gold, silver and
-- copper at a glance.
local COINS = {
    { key = "gold", letter = "g", per = 10000, width = 46, letters = 5, color = { 1, 0.84, 0 } },
    { key = "silver", letter = "s", per = 100, width = 32, letters = 2, color = { 0.78, 0.78, 0.81 } },
    { key = "copper", letter = "c", per = 1, width = 32, letters = 2, color = { 0.93, 0.65, 0.37 } },
}

--- Three small boxes for an amount of money, gold, silver and copper, each
--- with its coin letter after it. `onChange(copper)` runs when the player
--- presses Enter or leaves a box, never on each key, so nothing is judged
--- again while they type. :SetValue(copper) and :GetValue() as copper.
function Widgets.CreateMoneyBox(parent, onChange)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(24)
    holder.boxes = {}

    local function Read()
        local total = 0
        for _, coin in ipairs(COINS) do
            local amount = tonumber(holder.boxes[coin.key]:GetText()) or 0
            total = total + math.max(0, math.floor(amount)) * coin.per
        end
        return total
    end

    local function Commit()
        local value = Read()
        if value == holder.value then return end
        holder.value = value
        if onChange then onChange(value) end
    end

    local x = 0
    for _, coin in ipairs(COINS) do
        local box = Widgets.CreateSearchBox(holder, "0", nil, Commit, { plain = true })
        box:SetWidth(coin.width)
        box:SetPoint("LEFT", x, 0)
        local edit = box.editBox
        edit:SetMaxLetters(coin.letters)
        edit:SetJustifyH("RIGHT")
        if edit.SetNumeric then edit:SetNumeric(true) end
        edit:HookScript("OnEditFocusLost", Commit)
        holder.boxes[coin.key] = box

        local letter = Theme.CreateLabel(holder, "normal", "text")
        letter:SetPoint("LEFT", box, "RIGHT", 3, 0)
        letter:SetText(coin.letter)
        letter:SetTextColor(coin.color[1], coin.color[2], coin.color[3])
        x = x + coin.width + 14
    end
    holder:SetWidth(x)

    function holder:SetValue(copper)
        copper = math.max(0, math.floor(tonumber(copper) or 0))
        self.value = copper
        for _, coin in ipairs(COINS) do
            local amount = math.floor(copper / coin.per)
            copper = copper - amount * coin.per
            -- Empty rather than 0, so the dim 0 hint shows.
            self.boxes[coin.key]:SetText(amount > 0 and tostring(amount) or "")
        end
    end

    function holder:GetValue()
        return Read()
    end

    holder:SetValue(0)
    return holder
end

--------------------------------------------------------------------------------
-- Scrollbar
--------------------------------------------------------------------------------

--- The thin bar down a list's right edge: a dark track, and a thumb that is
--- as long as the part of the list on screen and lights gold under the
--- mouse or while dragged.
---
--- Drawn and dragged by hand rather than with the game's Slider: on the
--- Forever client a vertical slider ran the wrong way (dragging the thumb
--- down scrolled the list up, 2026-10-13). Here the thumb sits `value`
--- steps down from the top and follows the cursor while it is held, so
--- down is always down. `onValueChanged(value)` is told of each move the
--- player makes; SetValue from code says nothing.
local function CreateScrollbar(list, thumbKey)
    local scrollbar = CreateFrame("Frame", nil, list)
    scrollbar:SetWidth(8)
    scrollbar:SetPoint("TOPRIGHT", 0, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollbar:EnableMouse(true)
    scrollbar.min, scrollbar.max, scrollbar.value = 0, 0, 0
    scrollbar.thumbHeight = 40

    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(scrollbar)
    track:SetColorTexture(Theme.Unpack("panel"))

    local thumb = scrollbar:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(Theme.Unpack(thumbKey))
    thumb:SetSize(8, 40)
    thumb:SetPoint("TOP", scrollbar, "TOP", 0, 0)
    scrollbar.thumb = thumb

    -- The Blizzard window style draws the thumb as the game's knob, lit by
    -- tint (UI/BlizzardLook.lua).
    local Look = ns.BlizzardLook
    if Look then Look.Thumb(thumb) end

    local function Light(p)
        if Look and Look.LightThumb(thumb, p >= 0.5) then return end
        thumb:SetColorTexture(Motion.Mix(thumbKey, "accent", p, 1, 0.9))
    end

    --- Pixels the thumb can travel: the bar less the thumb.
    function scrollbar:Room()
        local height = tonumber(self:GetHeight()) or 0
        return math.max(0, height - (self.thumbHeight or 0))
    end

    --- How far down the bar the thumb's top is, in pixels.
    function scrollbar:ThumbTop()
        local span = (self.max or 0) - (self.min or 0)
        if span <= 0 then return 0 end
        return self:Room() * ((self.value or 0) - self.min) / span
    end

    local function Place()
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", scrollbar, "TOP", 0, -scrollbar:ThumbTop())
    end

    function scrollbar:SetMinMaxValues(low, high)
        self.min, self.max = tonumber(low) or 0, math.max(tonumber(low) or 0, tonumber(high) or 0)
        self.value = math.max(self.min, math.min(self.max, self.value or 0))
        Place()
    end

    function scrollbar:GetMinMaxValues() return self.min, self.max end

    function scrollbar:SetValue(value)
        value = math.floor((tonumber(value) or 0) + 0.5)
        self.value = math.max(self.min or 0, math.min(self.max or 0, value))
        Place()
    end

    function scrollbar:GetValue() return self.value end

    -- The player moved it: a whole step, and the list told when it changed.
    local function Move(value)
        local before = scrollbar.value
        scrollbar:SetValue(value)
        if scrollbar.value ~= before and scrollbar.onValueChanged then
            scrollbar.onValueChanged(scrollbar.value)
        end
    end

    --- The value that puts the thumb's top `pos` pixels down the bar.
    function scrollbar:ValueAt(pos)
        local room = self:Room()
        if room <= 0 then return self.min or 0 end
        pos = math.max(0, math.min(room, pos))
        return (self.min or 0) + pos / room * ((self.max or 0) - (self.min or 0))
    end

    --- How far down the bar the cursor is, in the bar's own pixels, or nil.
    function scrollbar:CursorDown()
        local top = self:GetTop()
        if type(top) ~= "number" or type(GetCursorPosition) ~= "function" then return nil end
        local _, y = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        if type(y) ~= "number" then return nil end
        if type(scale) ~= "number" or scale <= 0 then scale = 1 end
        return top - y / scale
    end

    --- Press on the bar: on the thumb it is held where it was caught; off
    --- it, the thumb's middle jumps under the cursor. Until the button comes
    --- up the thumb follows the cursor (OnUpdate runs only then).
    function scrollbar:StartDrag()
        if (self.max or 0) <= (self.min or 0) then return end
        local pos = self:CursorDown()
        if not pos then return end
        local top, size = self:ThumbTop(), self.thumbHeight or 0
        if pos >= top and pos <= top + size then
            self.grabAt = pos - top
        else
            self.grabAt = size / 2
            Move(self:ValueAt(pos - self.grabAt))
        end
        self:SetScript("OnUpdate", function(bar)
            local now = bar:CursorDown()
            if now then Move(bar:ValueAt(now - (bar.grabAt or 0))) end
        end)
    end

    function scrollbar:StopDrag()
        self.grabAt = nil
        self:SetScript("OnUpdate", nil)
    end

    scrollbar:SetScript("OnEnter", function(self) Motion:Blend(self, "hover", 1, 0.12, Light) end)
    scrollbar:SetScript("OnLeave", function(self)
        if not self.held then Motion:Blend(self, "hover", 0, 0.2, Light) end
    end)
    scrollbar:SetScript("OnMouseDown", function(self, button)
        if button ~= nil and button ~= "LeftButton" then return end
        self.held = true
        Motion:Blend(self, "hover", 1, 0.08, Light)
        self:StartDrag()
    end)
    scrollbar:SetScript("OnMouseUp", function(self)
        self.held = false
        self:StopDrag()
        local over = type(self.IsMouseOver) == "function" and self:IsMouseOver()
        if not over then Motion:Blend(self, "hover", 0, 0.2, Light) end
    end)

    -- Hidden mid-drag (the list shrank), the mouse-up never comes: let go.
    scrollbar:SetScript("OnHide", function(self)
        self.held = false
        self:StopDrag()
        Motion:Stop(self, "hover")
        Motion:SetValue(self, "hover", 0)
        Light(0)
    end)

    scrollbar:SetScript("OnSizeChanged", function() Place() end)

    --- Size the thumb for `visible` of `total` rows on screen.
    function scrollbar:SizeThumb(visible, total)
        local height = tonumber(self:GetHeight())
        if not (height and height > 0 and total and total > 0) then return end
        self.thumbHeight = math.max(18, math.min(height, height * visible / total))
        thumb:SetHeight(self.thumbHeight)
        Place()
    end

    return scrollbar
end

-- The Bags window (UI/BagWindow.lua) wears the same bar.
Widgets.CreateScrollbar = CreateScrollbar

--------------------------------------------------------------------------------
-- Fade
--------------------------------------------------------------------------------

--- A soft fade over one cut edge of a scrolling list, drawn above its rows
--- in the colour behind them (`key`), so a list with more above or below
--- fades out rather than stopping hard. The caller anchors it. Nil where
--- the client has no gradients: a flat band would only hide a row.
function Widgets.CreateFade(parent, side, key, height)
    if type(CreateColor) ~= "function" then return nil end

    local fade = CreateFrame("Frame", nil, parent)
    fade:SetFrameLevel(parent:GetFrameLevel() + 12)
    fade:SetHeight(height or 16)

    local texture = fade:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(fade)
    texture:SetColorTexture(1, 1, 1, 1)

    local r, g, b = Theme.Unpack(key or "panel")
    local solid, clear = CreateColor(r, g, b, 0.95), CreateColor(r, g, b, 0)
    local ok
    if side == "TOP" then
        ok = pcall(texture.SetGradient, texture, "VERTICAL", clear, solid)
    else
        ok = pcall(texture.SetGradient, texture, "VERTICAL", solid, clear)
    end
    if not ok then return nil end

    fade:EnableMouse(false)
    fade:Hide()
    return fade
end

--------------------------------------------------------------------------------
-- Line list
--------------------------------------------------------------------------------

--- A scrolling list of preformatted text lines.
--
-- Distinct from the tradeskills addon's CreateScrollList, which recycles rows
-- of columns: results here are already formatted strings of varying shape --
-- an item heading, a note, a source -- so a row is one label and the list only
-- has to decide which lines are on screen.
--------------------------------------------------------------------------------
-- Row list
--------------------------------------------------------------------------------

--- The light a row wears under the mouse, built on `row` once: a lifted
--- wash, a thin gold edge down its left so your place in a long list is easy
--- to keep, and a soft gold light bleeding off that edge into the row.
--- Unlit until Widgets.SetRowLight lights it.
function Widgets.RowLight(row)
    -- Filled at full strength and hidden with SetAlpha: a texture whose
    -- colour is clear stays clear whatever alpha it is given later, which
    -- is how the hover went missing.
    row.highlight = Theme.Fill(row, "glassHover", nil, "BORDER")
    row.highlight:SetAlpha(0)

    row.edge = row:CreateTexture(nil, "OVERLAY")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(2)
    row.edge:SetColorTexture(Theme.Unpack("accentHi"))
    row.edge:SetAlpha(0)

    -- Titanforged: a soft gold wash fading across the row from its left, as
    -- Tradeskills' rows light. Both gold lights hide at rest and are lit by
    -- Theme.LightGradient: faded with SetAlpha alone they stayed on every
    -- row in game.
    row.lightWash = row:CreateTexture(nil, "BORDER", nil, 1)
    row.lightWash:SetAllPoints(row)
    row.lightWash:Hide()

    row.bleed = row:CreateTexture(nil, "BORDER", nil, 1)
    row.bleed:SetPoint("TOPLEFT", 2, 0)
    row.bleed:SetPoint("BOTTOMLEFT", 2, 0)
    row.bleed:SetWidth(18)
    pcall(row.bleed.SetBlendMode, row.bleed, "ADD")
    row.bleed:Hide()
end

--- How lit a row from Widgets.RowLight is: 0 at rest, 1 under the mouse.
function Widgets.SetRowLight(row, value)
    row.highlight:SetAlpha(value)
    row.edge:SetAlpha(value)
    Theme.LightGradient(row.bleed, "HORIZONTAL", "accent", 0.18, 0, value)
    Theme.LightGradient(row.lightWash, "HORIZONTAL", "accent", 0.10, 0, value)
end

--- A scrolling list that recycles row frames.
--
-- Where CreateLineList draws one label per line, this gives each row a set of
-- children the caller builds once and fills per row, which is what a table of
-- columns needs. Only the rows on screen exist, so the length of the data does
-- not change the cost of drawing it.
--
-- @param opts
--   rowHeight  pixel height of one row
--   createRow  function(row)            -- build the row's children once
--   updateRow  function(row, data, i)   -- fill a row with data
--   onClick    function(data, button)
--   onEnter    function(row, data)      -- the mouse came onto a row
--   onLeave    function(row)
--   onRefresh  function(list, shown, visible)
--   fitRow     function(row, data)      -- how tall a filled row must be to
--                                       -- hold its wrapped text; rows are
--                                       -- never shorter than rowHeight
function Widgets.CreateRowList(parent, opts)
    opts = opts or {}

    local list = CreateFrame("Frame", nil, parent)
    local rowHeight = opts.rowHeight or 20

    list.data = {}
    list.rows = {}
    list.offset = 0

    local scrollbar = CreateScrollbar(list, "metal")

    list.scrollbar = scrollbar

    -- The cut edges fade while there is more above or below.
    local fadeTop = Widgets.CreateFade(list, "TOP", opts.fadeKey, 14)
    local fadeBottom = fadeTop and Widgets.CreateFade(list, "BOTTOM", opts.fadeKey, 14)
    if fadeBottom then
        fadeTop:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
        fadeTop:SetPoint("TOPRIGHT", scrollbar, "TOPLEFT", -6, 0)
        fadeBottom:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 0, 0)
        fadeBottom:SetPoint("BOTTOMRIGHT", scrollbar, "BOTTOMLEFT", -6, 0)
        list.fadeTop, list.fadeBottom = fadeTop, fadeBottom
    end

    -- How tall each item's row was last drawn, by the item, so the list
    -- knows how far it scrolls. An item not drawn yet counts as rowHeight,
    -- the least a row can be.
    local heights = setmetatable({}, { __mode = "k" })

    local function Room()
        local height = list:GetHeight()
        if not height or height <= 0 then return 0 end
        return height
    end

    local function HeightOf(data)
        return (type(data) == "table" and heights[data]) or rowHeight
    end

    -- True while Refresh sets the scrollbar itself (see there).
    local syncing = false

    -- The row under the mouse, from its OnEnter to its OnLeave.
    local hovered

    --- How lit a row is: 0 at rest, 1 under the mouse.
    local Lit = Widgets.SetRowLight

    local function Unlight(row)
        Motion:Stop(row, "hover")
        Motion:SetValue(row, "hover", 0)
        Lit(row, 0)
    end

    --- The mouse is on `row`: light it, and let the caller show its tooltip.
    local function Enter(row)
        hovered = row
        if row.data and row.data.type ~= "spacer" then
            Motion:Blend(row, "hover", 1, 0.08, function(value) Lit(row, value) end)
        else
            Unlight(row)
        end
        if row.data and opts.onEnter then opts.onEnter(row, row.data) end
    end

    local function AcquireRow(index)
        local row = list.rows[index]
        if row then return row end

        row = CreateFrame("Button", nil, list)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
        row:SetPoint("RIGHT", scrollbar, "LEFT", -6, 0)
        row.top, row.height = (index - 1) * rowHeight, rowHeight
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        -- Dark glass: every other row a shade apart, with a fine line under
        -- each, so the rows read as separate.
        row.stripe = Theme.Fill(row, "glass")
        row.line = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.line:SetPoint("BOTTOMLEFT")
        row.line:SetPoint("BOTTOMRIGHT")
        row.line:SetHeight(1)
        row.line:SetColorTexture(Theme.Unpack("border", 0.6))

        -- The wash, the gold edge and the gold light that come up under the
        -- mouse.
        Widgets.RowLight(row)

        if opts.createRow then
            opts.createRow(row)
        end

        -- Callers hook hovering through opts rather than HookScript on the
        -- row: SetScript here would replace a hook set in createRow.
        row:SetScript("OnEnter", Enter)

        row:SetScript("OnLeave", function(self)
            if hovered == self then hovered = nil end
            Motion:Blend(self, "hover", 0, 0.18, function(value) Lit(self, value) end)
            if opts.onLeave then opts.onLeave(self) end
        end)

        row:SetScript("OnClick", function(self, button)
            if self.data and opts.onClick then
                opts.onClick(self.data, button)
            end
        end)

        list.rows[index] = row
        return row
    end

    --- The first item that can be on top with the last item still in
    --- sight, counted from the end by the rows' heights.
    function list:MaxOffset()
        local room = Room()
        local used = 0
        for index = #self.data, 1, -1 do
            used = used + HeightOf(self.data[index])
            if used > room then return index end
        end
        return 0
    end

    --- Fill rows from the offset down until the next one would not fit.
    --- A row grows to hold its wrapped text (opts.fitRow), so the rows
    --- below it move down rather than being written over. Gives how many
    --- rows show, and whether the last item is among them.
    local function Lay(self, stillOver)
        local room = Room()
        local top, count = 0, 0
        while true do
            local data = self.data[self.offset + count + 1]
            if not data then break end

            local index = count + 1
            local row = AcquireRow(index)
            row.data = data
            row.dataIndex = index + self.offset

            -- A row handed new data starts unlit, except the one under the
            -- mouse, which is lit again for its new data below.
            if not (stillOver and row == hovered) then Unlight(row) end

            -- Banding follows the row's place on screen rather than its
            -- index in the data, so the stripes do not crawl as you scroll.
            row.stripe:SetColorTexture(Theme.Unpack(index % 2 == 0 and "glassAlt" or "glass"))

            if opts.updateRow then
                opts.updateRow(row, data, index + self.offset)
            end

            local height = rowHeight
            if opts.fitRow then
                height = math.max(rowHeight, math.ceil(tonumber(opts.fitRow(row, data)) or 0))
            end
            if type(data) == "table" then heights[data] = height end

            -- The top row shows even when it is taller than the list.
            if top + height > room and (index > 1 or room < rowHeight) then
                row.data = nil
                row:Hide()
                break
            end

            if row.top ~= top or row.height ~= height then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -top)
                row:SetPoint("RIGHT", scrollbar, "LEFT", -6, 0)
                row:SetHeight(height)
                row.top, row.height = top, height
            end
            row:Show()

            top = top + height
            count = index
        end

        for index = count + 1, #self.rows do
            local row = self.rows[index]
            row.data = nil
            row:Hide()
        end
        return count, self.offset + count >= #self.data
    end

    function list:Refresh()
        local maxOffset = self:MaxOffset()

        if self.offset > maxOffset then self.offset = maxOffset end
        if self.offset < 0 then self.offset = 0 end

        -- Asked before the rows change: one emptied below is hidden, and a
        -- hidden row is under no mouse.
        local stillOver = hovered and UnderMouse(hovered)

        local wasAtEnd = self.offset >= maxOffset
        local visible, reachedEnd = Lay(self, stillOver)

        -- Rows not drawn before count as short. At the foot of the list a
        -- tall one can leave the last item out of sight: now its height is
        -- known, go down as far as the end really is.
        local tries = 0
        while wasAtEnd and not reachedEnd and tries < 4 do
            local further = self:MaxOffset()
            if further <= self.offset then break end
            maxOffset = further
            self.offset = further
            visible, reachedEnd = Lay(self, stillOver)
            tries = tries + 1
        end
        maxOffset = math.max(maxOffset, self.offset)

        -- A scroll or a redraw hands the row under a still mouse new data,
        -- and no OnEnter comes for that: it went dark, and its tooltip
        -- still spoke of the last row. Leave and enter it again, as if the
        -- mouse had just come onto what it shows now.
        if hovered then
            local row = hovered
            hovered = nil
            if stillOver and opts.onLeave then opts.onLeave(row) end
            if stillOver and row.data and row:IsShown() then
                Enter(row)
            else
                Unlight(row)
            end
        end

        -- The client clamps the slider's value to a new range and reports
        -- that as the player moving it. Taken as a move, a new list that was
        -- shorter than the last one opened scrolled to its end.
        syncing = true
        scrollbar:SetMinMaxValues(0, maxOffset)
        scrollbar:SetValue(self.offset)
        syncing = false
        scrollbar:SetShown(maxOffset > 0)
        scrollbar:SizeThumb(visible, #(self.data or self.lines))

        if fadeBottom then
            fadeTop:SetShown(self.offset > 0)
            fadeBottom:SetShown(self.offset < maxOffset)
        end

        if opts.onRefresh then
            opts.onRefresh(self, #self.data, visible)
        end
    end

    --- New rows. `keepPlace` keeps the list scrolled where it was (a redraw
    --- of the same results after a kill, a heading folded); otherwise it
    --- starts from the top.
    function list:SetData(data, keepPlace)
        self.data = data or {}
        if not keepPlace then self.offset = 0 end
        self:Refresh()
    end

    --- Bring the rows on screen in one after another, top down: a new set
    --- of results arriving rather than appearing. Full effects only.
    function list:Arrive()
        if Motion.Level() ~= "full" then return end

        local shown = 0
        for _, row in ipairs(self.rows) do
            if row:IsShown() and row.data then
                shown = shown + 1
                local delay = math.min(shown - 1, 14) * 0.02
                Motion:Run(row, "arrive", 0.22, function(p) row:SetAlpha(p) end,
                    { delay = delay })
            end
        end
    end

    function list:Scroll(delta)
        self.offset = self.offset - (delta * 3)
        self:Refresh()
    end

    -- Only the player's drags come here; Refresh sets the bar quietly.
    scrollbar.onValueChanged = function(value)
        if syncing then return end

        local wanted = math.floor(value + 0.5)
        if wanted ~= list.offset then
            list.offset = wanted
            list:Refresh()
        end
    end

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        list:Scroll(delta)
    end)

    return list
end

--------------------------------------------------------------------------------
-- Hanging tabs (Pets' tab strip, itself Farmer's, brought over 2026-10-27
-- for the Butler window's Your Bags, All Characters and Settings tabs)
--------------------------------------------------------------------------------

-- Room either side of a tab's name, and the narrowest a tab gets, when the
-- tabs are sized to their names.
local TAB_PAD = 20
local TAB_MIN = 56

--- Widths for tabs sized to their names: each name measured with room either
--- side, and what is left of `room` shared out, a little each, so a strip of
--- a few tabs does not stretch them wide. Nil when a name cannot be measured,
--- or when they do not all fit `room`.
local function NameWidths(buttons, room)
    local widths, total = {}, 0
    for index, button in ipairs(buttons) do
        local width = Theme.TextWidth(button.labelSize, button.label:GetText())
        if not width or width <= 0 then return nil end
        widths[index] = math.max(TAB_MIN, math.ceil(width) + TAB_PAD)
        total = total + widths[index]
    end

    if room and total > room then return nil end

    local extra = room and math.min(24, math.floor((room - total) / #buttons)) or 0
    for index in ipairs(widths) do widths[index] = widths[index] + extra end
    return widths
end

-- Hanging tabs (opts.hanging): how tall a tab is, and how far the one
-- showing reaches up over the window's rim to join it.
local HANG_HEIGHT = 26
local HANG_JOIN = 5

--- The metal edge round a hanging tab: down both sides and along the foot.
local function HangingEdges(button)
    local Gradient = ns.Titanforged and ns.Titanforged.Gradient
    local metalLo, metal = { 0.357, 0.267, 0.086 }, { 0.690, 0.545, 0.235 }
    local hi = { 0.941, 0.831, 0.541 }

    local function Edge(a, b, width, height)
        local edge = button:CreateTexture(nil, "BORDER", nil, 2)
        edge:SetPoint(a)
        edge:SetPoint(b)
        if width then edge:SetWidth(width) else edge:SetHeight(height) end
        return edge
    end

    local left = Edge("TOPLEFT", "BOTTOMLEFT", 2)
    local right = Edge("TOPRIGHT", "BOTTOMRIGHT", 2)
    local foot = Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
    button.edges = { left, right, foot }

    if Gradient then
        Gradient(left, "VERTICAL", hi, metalLo)
        Gradient(right, "VERTICAL", metal, metalLo)
        Gradient(foot, "HORIZONTAL", metal, hi)
    else
        for _, edge in ipairs({ left, right, foot }) do edge:SetColorTexture(Theme.Unpack("metal")) end
    end
end

--- A row of tabs, Tradeskills' tab strip. Each tab is { key, text, width };
--- a tab given no width is as wide as its name needs, and opts.width is the
--- room all of them have. opts.hanging hangs them below the strip's top
--- edge, as the game's own windows wear their tabs (Titanforged): anchor the
--- strip's top to the window's bottom.
function Widgets.CreateTabStrip(parent, tabs, onSelect, opts)
    opts = opts or {}
    local hanging = opts.hanging and true or false

    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(28)

    strip.tabs = {}
    -- False rather than nil until set: Farmer's test frames answer a field
    -- they were never given.
    strip.selected = false
    strip.lineX, strip.lineWidth = false, false

    -- In the Blizzard window style a resting tab's name is the game's gold,
    -- and hanging tabs wear the character window's tab art.
    local Look = ns.BlizzardLook
    local blizzard = Look and Look.On()
    local restKey = blizzard and "gilt" or "muted"

    --- How lit a tab is under the mouse, 0 to 1: its wash, its underline
    --- and its label.
    local function Hover(button, p)
        button.hover:SetAlpha(p)
        button.underline:SetAlpha(p)
        if strip.selected ~= button.key then
            button.label:SetTextColor(Motion.Mix(restKey, "text", p))
        end
    end

    for index, tab in ipairs(tabs) do
        local button = CreateFrame("Button", nil, strip)
        button:SetHeight(hanging and HANG_HEIGHT or 28)

        button.background = Theme.Fill(button, "panel")
        button.hover = Theme.Fill(button, "rowHover", 0.45, "BORDER")
        button.hover:SetAlpha(0)

        if hanging then
            HangingEdges(button)
            -- Each tab glows faintly gold when it is the one showing.
            if Theme.Halo then Theme.Halo(button, 6, 0) end
        end

        -- The tab showing sits in a soft gold light rising from its line.
        button.lit = button:CreateTexture(nil, "BORDER", nil, 1)
        button.lit:SetAllPoints(button)
        Theme.SetGradientAlpha(button.lit, "VERTICAL", "accent", hanging and 0.28 or 0.14, 0)
        button.lit:Hide()

        -- Under the mouse, a faint line along the tab's foot echoes the gold
        -- one under the tab showing. It is inset from the tab's edges and
        -- drawn on the tab, below the layer the gold line rides on, so the
        -- gold line passes over it as it slides, and the tab showing never
        -- lights its own.
        button.underline = button:CreateTexture(nil, "ARTWORK")
        button.underline:SetPoint("BOTTOMLEFT", 10, 0)
        button.underline:SetPoint("BOTTOMRIGHT", -10, 0)
        button.underline:SetHeight(1)
        button.underline:SetColorTexture(Theme.Unpack("muted"))
        button.underline:SetAlpha(0)

        -- A step smaller on a narrow tab given its width, so its name stays
        -- inside it. Tabs sized to their names are sized below.
        button.labelSize = tab.width and tab.width < 90 and "small" or "normal"
        button.label = Theme.CreateLabel(button, button.labelSize, restKey, "CENTER")
        button.label:SetPoint("CENTER", 0, 0)
        button.label:SetText(tab.text)

        if blizzard and hanging then Look.Tab(button) end

        button.key = tab.key
        button.fixedWidth = tab.width or false
        -- A tab marked right sits flush with the strip's right end (Settings
        -- is always last there, the owner 2026-10-27).
        button.right = tab.right and true or false

        button:SetScript("OnClick", function(self)
            strip:Select(self.key)
            if onSelect then onSelect(self.key) end
        end)

        button:SetScript("OnEnter", function(self)
            if strip.selected == self.key then return end
            Motion:Blend(self, "hover", 1, 0.12, function(p) Hover(self, p) end)
        end)

        button:SetScript("OnLeave", function(self)
            Motion:Blend(self, "hover", 0, 0.18, function(p) Hover(self, p) end)
        end)

        strip.tabs[index] = button
    end

    -- Tabs given no width are as wide as their names, at the full size when
    -- all of them fit opts.width and a step smaller when not. When a name
    -- cannot be measured they share the room equally.
    local sized, room = {}, opts.width
    for _, button in ipairs(strip.tabs) do
        if button.fixedWidth then
            if room then room = room - button.fixedWidth end
        else
            sized[#sized + 1] = button
        end
    end

    local widths = {}
    if #sized > 0 then
        local named = NameWidths(sized, room)
        if not named then
            for _, button in ipairs(sized) do
                button.labelSize = "small"
                button.label:SetFont(Theme.FONT, Theme.sizes.small, "")
            end
            named = NameWidths(sized, room)
        end

        for index, button in ipairs(sized) do
            widths[button] = named and named[index]
                or (room and math.min(96, math.floor(room / #sized)) or 96)
        end
    end

    -- Hanging tabs stand a little apart, so each reads as its own tab.
    local gap = hanging and 3 or 0
    local x = 0
    for _, button in ipairs(strip.tabs) do
        local width = button.fixedWidth or widths[button]
        if hanging then
            button:SetPoint("TOPLEFT", x, 0)
            width = math.max(1, width - gap)
        else
            button:SetPoint("BOTTOMLEFT", x, 0)
        end
        button:SetWidth(width)
        button.left, button.span = x, width
        x = x + width + gap
    end

    -- Tabs marked right move to the far end of the strip, keeping their
    -- order, when the strip has room for them. Again when the window it
    -- hangs from changes width (strip:SetRoom).
    local packed = math.max(x, 1)
    local function PlaceRight(width)
        local full = packed
        if hanging and type(width) == "number" and width > packed then
            local right = width
            for index = #strip.tabs, 1, -1 do
                local button = strip.tabs[index]
                if button.right then
                    right = right - button.span
                    button.left = right
                    right = right - gap
                    full = width
                end
            end
        end
        strip:SetWidth(full)
    end
    PlaceRight(opts.width)
    for _, button in ipairs(strip.tabs) do
        if button.right and hanging then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", button.left, 0)
        end
    end

    -- One gold line for the whole strip, gliding to the tab picked, with a
    -- soft glow over it. Both ride on a layer of their own above the tabs:
    -- drawn on the strip itself they sat under every tab's fill (a frame's
    -- children draw over it) and never showed.
    local layer = CreateFrame("Frame", nil, strip)
    layer:SetAllPoints(strip)
    local ok, level = pcall(strip.GetFrameLevel, strip)
    if ok and type(level) == "number" then layer:SetFrameLevel(level + 3) end
    pcall(layer.EnableMouse, layer, false)
    strip.lineLayer = layer

    local line = layer:CreateTexture(nil, "OVERLAY")
    line:SetHeight(2)
    line:SetColorTexture(Theme.Unpack("accent"))
    line:Hide()
    strip.line = line

    local glow = layer:CreateTexture(nil, "ARTWORK")
    glow:SetHeight(7)
    glow:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", -2, 0)
    glow:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", 2, 0)
    Theme.SetGradientAlpha(glow, "VERTICAL", "accent", 0.32, 0)
    pcall(glow.SetBlendMode, glow, "ADD")
    glow:Hide()
    strip.lineGlow = glow
    if blizzard and hanging then Look.TabStrip(strip) end

    --- Put the line under `button`, sliding there from wherever it is now,
    --- so a tab picked mid-slide turns the line round rather than making it
    --- jump back first.
    local function MarkTab(button)
        local fromX, fromWidth = strip.lineX or button.left, strip.lineWidth or button.span
        local still = fromX == button.left and fromWidth == button.span

        line:Show()
        glow:Show()

        -- Hung from the tab it is heading for, so it lands exactly under it;
        -- only the distance still to go is worked out.
        Motion:Run(line, "slide", still and 0 or 0.22, function(p)
            local x = fromX + (button.left - fromX) * p
            local width = fromWidth + (button.span - fromWidth) * p
            strip.lineX, strip.lineWidth = x, width

            line:ClearAllPoints()
            line:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", x - button.left, 0)
            line:SetWidth(math.max(1, width))
        end)
    end

    --- The strip's room changed (its window grew): the tabs marked right
    --- move to its new right end.
    function strip:SetRoom(width)
        PlaceRight(width)
        local picked = self.selected
        self.selected = false
        self.lineX, self.lineWidth = false, false
        if picked then self:Select(picked) end
    end

    function strip:Select(key)
        self.selected = key

        for _, button in ipairs(self.tabs) do
            local active = button.key == key
            button.selected = active
            Motion:Stop(button, "hover")
            Motion:SetValue(button, "hover", 0)
            button.hover:SetAlpha(0)
            button.underline:SetAlpha(0)
            button.lit:SetShown(active)
            button.label:SetTextColor(Theme.Unpack(active and (hanging and "accentHi" or "accent") or restKey))
            button.background:SetColorTexture(Theme.Unpack(active and "header" or (hanging and "window" or "panel")))
            if hanging then
                -- The tab showing is taller, reaching up over the window's
                -- rim so it joins the window, and glows.
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", strip, "TOPLEFT", button.left, active and HANG_JOIN or 0)
                button:SetHeight(HANG_HEIGHT + (active and HANG_JOIN or 0))
                if rawget(button, "haloTextures") then Theme.SetHalo(button, active and 0.22 or 0) end
            end
            if active then MarkTab(button) end
            if blizzard then Look.SelectTab(button, active) end
        end
    end

    return strip
end
