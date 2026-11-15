-- Blackthornes Butler -- UI/RuleOrder.lua
-- The Order page of Settings: every rule Butler asks, in the order it asks
-- them, to drag into the player's own order and turn on or off (the owner
-- said build it, 2026-10-17, from the mockup he asked for).
--
-- Equipment sets and quest items always come first, and the best price,
-- then Look at it, always come last; the rules between them move. The first
-- rule that fits an item decides it (Verdicts:Decide). Set Default puts the
-- order Butler ships with back, and Undo Move takes back the last change.
--
-- Two columns of dark glass rows, the slots read top to bottom, then the
-- second column. A row is picked up with the mouse and follows it; the
-- others slide out of its way and into their new places. Only while
-- something moves does the board run an OnUpdate, and it stops once all
-- rows have landed (smooth play). The order is saved when the row is let
-- go (Verdicts:SetOrder), never while dragging.

local _, ns = ...
local L = ns.L

local RuleOrderUI = ns.NewModule("RuleOrderUI")

local Theme = ns.Theme
local Widgets = ns.Widgets

RuleOrderUI.ROW = 24
RuleOrderUI.SLOT = 26
-- How many of the rules that move sit in the first column.
RuleOrderUI.PER_COLUMN = 13
-- How quickly a row eases into its place: the larger, the snappier.
RuleOrderUI.EASE = 16

local HEADING = 24
local SECTION_GAP = 10

-- Each rule's name, the verdict it gives, and what it does.
RuleOrderUI.RULES = {
    sets = { L["Equipment Sets:"], "keep", L["Gear in one of your equipment sets is never sold, mailed or broken."] },
    quests = { L["Quest Items:"], "keep", L["Quest items, things that start a quest, and things your quests ask for."] },
    keepHere = { L["Kept on This Character:"], "keep", L["The number you keep on this character stays. The rest go on down the rules."] },
    keepList = { L["Always Keep List:"], "keep", L["Things you put on the list stay. A queued craft on another character still gets its share."] },
    bankList = { L["Always Bank List:"], "bank", L["Goes in the bank when you click Move to bank."] },
    mailList = { L["Always Mail List:"], "mail", L["Each item goes to the character you picked for it. An upgrade you can wear now stays."] },
    lists = { L["Your Lists:"], "mail" },
    buyback = { L["Things You Bought Back:"], "keep", L["Butler sold it and you bought it back, so it stays from now on."] },
    noValue = { L["Vendors Won't Buy It:"], "keep", L["No vendor pays for it, so it stays. A queued craft on another character still gets its share."] },
    sellList = { L["Always Sell List:"], "sell", L["Sold at a vendor, unless a goal, a craft or an upgrade still needs it."] },
    auctionList = { L["Always Auction List:"], "auction", L["Goes to the auction house even when a vendor pays more. An upgrade you can wear now stays."] },
    disenchantList = { L["Always Disenchant List:"], "disenchant", L["Broken even when selling would pay more. An upgrade you can wear now stays."] },
    ammo = { L["Your Ammo:"], "keep", L["Arrows or bullets for the weapon you use."] },
    upgrades = { L["Upgrades and Tools:"], "keep", L["Gear you can wear, gear for a later level, and tools like a skinning knife."] },
    altCrafts = { L["Crafts on Your Characters:"], "mail", L["Materials another character's queued crafts need go to them."] },
    goals = { L["Farmer Goals:"], "keep", L["Kept until your goal has enough."] },
    queue = { L["Your Craft Queue:"], "keep", L["Kept for crafts this character has queued."] },
    altUpgrades = { L["Upgrades for Your Characters:"], "mail", L["Gear another character could wear goes to them."] },
    petFood = { L["Pet Food:"], "keep", L["Food your pet eats."] },
    bought = { L["Bought to Disenchant:"], "disenchant", L["Things you bought on the auction house to break."] },
    levelEnch = { L["Level Your Enchanting:"], "disenchant", L["Greens that break into what your next skill points need, even when selling pays more."] },
    greensHere = { L["Disenchant Greens Here:"], "disenchant", L["On your disenchanter, greens get broken unless selling pays more."] },
    disenchanter = { L["Your Disenchanter:"], "mail", L["Greens you can't break go to your disenchanter, when breaking them pays as much as selling."] },
    mailHabit = { L["Things You Always Mail:"], "mail", L["You mailed it to the same character twice, so Butler does it for you."] },
    sellHabit = { L["Things You Always Sell:"], "sell", L["You sold it by hand twice, so Butler sells it for you."] },
    greys = { L["Grey Items:"], "sell", L["Only a vendor pays for these."] },
    bankAlt = { L["Bank Alt:"], "mail", L["The kinds of items you ticked go to your bank alt."] },
    sellBelow = { L["Sell Below:"], "sell", L["Anything worth less than your amount goes to a vendor."] },
    best = { L["Best Price:"], "best", L["Auction, disenchant or vendor, whichever pays most. Waits when the auction house pays too little today."] },
    look = { L["Look at It:"], "look", L["Anything no rule caught waits for you to decide."] },
}

-- The chip on each row: the verdict's word and its colour.
local CHIPS = {
    keep = { L["Keep"], { 0.310, 0.820, 0.545 } },
    bank = { L["Bank"], { 0.722, 0.808, 0.957 } },
    mail = { L["Mail"], { 0.945, 0.831, 0.533 } },
    sell = { L["Sell"], { 0.784, 0.643, 0.302 } },
    auction = { L["Auction"], { 0.957, 0.722, 0.380 } },
    disenchant = { L["Disenchant"], { 0.761, 0.580, 0.957 } },
    best = { L["Best"], { 0.902, 0.910, 0.925 } },
    look = { L["Look"], { 0.478, 0.502, 0.541 } },
}

-- Rules turned on on another page, where their amount or character is set.
local OPENS = { sellBelow = "selling", bankAlt = "bankalt" }

local function Copy(list)
    local copy = {}
    for k, v in pairs(list or {}) do copy[k] = v end
    return copy
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function Heading(board, text, x, y, width)
    local heading = Theme.CreateLabel(board, "tiny", "accent")
    heading:SetPoint("TOPLEFT", board, "TOPLEFT", x, -y - 4)
    heading:SetText(text)
    local line = board:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", board, "TOPLEFT", x, -y - 18)
    line:SetSize(width, 1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))
    return heading
end

--- Light a row: under the mouse, picked up, or neither.
local function Paint(row)
    local lifted = RuleOrderUI.drag and RuleOrderUI.drag.row == row
    row.active:SetShown(lifted and true or false)
    row.activeEdge:SetShown(lifted and true or false)
    Widgets.SetRowLight(row, (row.hovered and not lifted) and 1 or 0)
    if Theme.SetHalo then Theme.SetHalo(row, lifted and 0.55 or 0) end
end

local function Tooltip(row)
    local rule = RuleOrderUI.RULES[row.id]
    if not (rule and GameTooltip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine((rule[1]:gsub(":$", "")), Theme.Unpack("accentHi"))
    if rule[3] then GameTooltip:AddLine(rule[3], Theme.Muted(true)) end
    local Verdicts = ns.Verdicts
    if row.id == "sellBelow" then
        local below = Verdicts:SellBelow()
        GameTooltip:AddLine(below and L.Format("Now: less than %s.", ns.Items.FormatMoney(below))
            or L["Off. Set an amount on the Errands page."], Theme.Unpack("text"))
    elseif row.id == "bankAlt" then
        local name = ns.BankAlt and ns.BankAlt:Name()
        if name then
            GameTooltip:AddLine(L.Format("Now: %s.", name), Theme.Unpack("text"))
        elseif not (ns.BankAlt and ns.BankAlt:Active()) then
            -- A kind sent to its own character keeps the rule on with no bank alt.
            GameTooltip:AddLine(L["Off. Pick a character on the Bank Alt page."], Theme.Unpack("text"))
        end
    elseif not row.locked then
        GameTooltip:AddLine(L["Drag it up or down to change when Butler asks it."], Theme.Unpack("dim"))
    end
    GameTooltip:Show()
end

local function MakeRow(board, id, width, locked)
    local row = CreateFrame("Frame", nil, board)
    -- Every field read later is set here: a field never set is nil in
    -- game, but the tests' stand-in frames answer one with a function.
    row.id, row.locked = id, locked and true or false
    row.check, row.open, row.control, row.hovered = false, false, false, false
    row.x, row.y, row.tx, row.ty = false, false, false, false
    row:SetSize(width, RuleOrderUI.ROW)
    row:EnableMouse(true)

    row.bg = Theme.Fill(row, "glass")
    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.line:SetColorTexture(Theme.Unpack("border", 0.6))
    Widgets.RowLight(row)
    -- Picked up: gold in the dark with a bright gold edge, and a soft halo.
    row.active = Theme.Fill(row, "glassActive", nil, "BORDER")
    row.active:Hide()
    row.activeEdge = row:CreateTexture(nil, "OVERLAY")
    row.activeEdge:SetPoint("TOPLEFT")
    row.activeEdge:SetPoint("BOTTOMLEFT")
    row.activeEdge:SetWidth(2)
    row.activeEdge:SetColorTexture(Theme.Unpack("accentHi"))
    row.activeEdge:Hide()
    if Theme.Halo then Theme.Halo(row, 6, 0, "accent") end

    -- The grip: two columns of three dots.
    if not locked then
        for i = 0, 5 do
            local dot = row:CreateTexture(nil, "ARTWORK")
            dot:SetSize(2, 2)
            dot:SetPoint("LEFT", row, "LEFT", 6 + (i % 2) * 4, (math.floor(i / 2) - 1) * 4)
            dot:SetColorTexture(Theme.Unpack("muted"))
        end
    end

    row.number = Theme.CreateLabel(row, "tiny", "muted", "RIGHT")
    row.number:SetPoint("LEFT", row, "LEFT", 14, 0)
    row.number:SetWidth(18)

    -- The control on the right: a tick box, or Open for a rule its own page
    -- turns on. Locked rows have none.
    local rightX = -6
    if OPENS[id] then
        row.open = Widgets.CreateButton(row, L["Open"], function()
            if RuleOrderUI.showPage then RuleOrderUI.showPage(OPENS[id]) end
        end, { width = math.max(52, Theme.TextWidth("small", L["Open"]) + 20), height = 18 })
        row.open:SetPoint("RIGHT", row, "RIGHT", rightX, 0)
        row.control = row.open
    elseif not locked then
        row.check = Widgets.CreateCheckbox(row, "", function(checked)
            RuleOrderUI:Toggle(id, checked)
        end, true)
        row.check:SetPoint("RIGHT", row, "RIGHT", rightX, 0)
        row.control = row.check
    end

    local chip = CreateFrame("Frame", nil, row)
    local word, color = CHIPS[RuleOrderUI.RULES[id][2]][1], CHIPS[RuleOrderUI.RULES[id][2]][2]
    chip:SetSize(Theme.TextWidth("tiny", word) + 14, 16)
    if row.control then
        chip:SetPoint("RIGHT", row.control, "LEFT", -8, 0)
    else
        chip:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    end
    chip.bg = Theme.Fill(chip, "well")
    chip.edges = Theme.Border(chip, "border")
    chip.label = Theme.CreateLabel(chip, "tiny", "text", "CENTER")
    chip.label:SetPoint("CENTER")
    chip.label:SetText(word)
    chip.color = color
    row.chip = chip

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", row, "LEFT", 38, 0)
    row.name:SetPoint("RIGHT", chip, "LEFT", -6, 0)
    -- Long names (German runs longer) wrap onto two lines, never "...".
    row.name:SetWordWrap(true)
    row.name:SetText(RuleOrderUI.RULES[id][1])

    row:SetScript("OnEnter", function(self)
        self.hovered = true
        Paint(self)
        Tooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hovered = false
        Paint(self)
        if GameTooltip then GameTooltip:Hide() end
    end)
    if not locked then
        row:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then RuleOrderUI:PickUp(self) end
        end)
        row:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then RuleOrderUI:LetGo() end
        end)
    end
    return row
end

--- Dim a row whose rule is off, and colour its chip by its verdict.
local function Shade(row, on)
    row.name:SetTextColor(Theme.Unpack(on and "text" or "muted"))
    local c = row.chip.color
    local alpha = on and 1 or 0.45
    row.chip.label:SetTextColor(c[1], c[2], c[3], alpha)
    for _, edge in ipairs(row.chip.edges or {}) do
        edge:SetColorTexture(c[1], c[2], c[3], 0.5 * alpha)
    end
end

--------------------------------------------------------------------------------
-- The board
--------------------------------------------------------------------------------

--- Where slot `i` of the rules that move sits, from the board's top left.
function RuleOrderUI:SlotAt(i)
    local per = self.PER_COLUMN
    if i <= per then return 0, self.top + (i - 1) * self.SLOT end
    return self.secondX, self.top + (i - per - 1) * self.SLOT
end

--- Build the board on `parent` (the Order page's content). `showPage`
--- opens another Settings page by key. Returns the board, with
--- `fixedHeight` for the page's layout and `words` for its search.
function RuleOrderUI:Build(parent, columnWidth, columnGap, showPage)
    local Verdicts = ns.Verdicts
    self.showPage = showPage
    self.columnWidth = columnWidth
    self.secondX = columnWidth + columnGap

    local board = CreateFrame("Frame", nil, parent)
    board:SetWidth(columnWidth * 2 + columnGap)
    self.board = board

    local SLOT = self.SLOT
    -- Column one: ALWAYS FIRST, then YOUR ORDER. Column two: the buttons
    -- across from ALWAYS FIRST, then the rest of the order, then LAST.
    Heading(board, L["ALWAYS FIRST"], 0, 0, columnWidth)
    self.fixed = {}
    for i, id in ipairs(Verdicts.FIRST) do
        local row = MakeRow(board, id, columnWidth, true)
        row:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -(HEADING + (i - 1) * SLOT))
        row.number:SetText(i)
        self.fixed[#self.fixed + 1] = row
    end
    local orderY = HEADING + #Verdicts.FIRST * SLOT + SECTION_GAP
    Heading(board, L["YOUR ORDER"], 0, orderY, columnWidth)
    self.top = orderY + HEADING

    Heading(board, L["CHANGE THE ORDER"], self.secondX, 0, columnWidth)
    local hint = Theme.CreateLabel(board, "tiny", "muted")
    hint:SetPoint("TOPLEFT", board, "TOPLEFT", self.secondX, -(HEADING + 2))
    hint:SetWidth(columnWidth)
    hint:SetWordWrap(true)
    hint:SetText(L["Drag a rule to move it. The first rule that fits an item decides what Butler says."])

    self.defaultButton = Widgets.CreateButton(board, L["Set Default"], function()
        RuleOrderUI:SetDefault()
    end, { width = math.max(96, Theme.TextWidth("small", L["Set Default"]) + 24), height = 22 })
    self.defaultButton:SetPoint("TOPLEFT", board, "TOPLEFT", self.secondX, -(HEADING + 34))
    self.undoButton = Widgets.CreateButton(board, L["Undo Move"], function()
        RuleOrderUI:Undo()
    end, { width = math.max(96, Theme.TextWidth("small", L["Undo Move"]) + 24), height = 22 })
    self.undoButton:SetPoint("LEFT", self.defaultButton, "RIGHT", 8, 0)

    -- Where the row being dragged would land: a faint gold outline.
    local mark = CreateFrame("Frame", nil, board)
    mark:SetSize(columnWidth, self.ROW)
    mark.fill = Theme.Fill(mark, "accent", 0.06)
    Theme.Border(mark, "accent", 0.55)
    mark:Hide()
    self.mark = mark

    self.rows = {}
    local words = { L["ALWAYS FIRST"], L["YOUR ORDER"], L["LAST"], L["Set Default"] }
    for id, rule in pairs(self.RULES) do words[#words + 1] = rule[1] end
    for _, id in ipairs(Verdicts.DEFAULT_ORDER) do
        self.rows[id] = MakeRow(board, id, columnWidth, false)
    end

    local count = #Verdicts.DEFAULT_ORDER
    local secondCount = math.max(0, count - self.PER_COLUMN)
    local lastY = self.top + secondCount * SLOT + SECTION_GAP
    Heading(board, L["LAST"], self.secondX, lastY, columnWidth)
    for i, id in ipairs(Verdicts.LAST) do
        local row = MakeRow(board, id, columnWidth, true)
        row:SetPoint("TOPLEFT", board, "TOPLEFT", self.secondX, -(lastY + HEADING + (i - 1) * SLOT))
        row.number:SetText(#Verdicts.FIRST + count + i)
        self.fixed[#self.fixed + 1] = row
    end

    local height = math.max(self.top + math.min(count, self.PER_COLUMN) * SLOT,
        lastY + HEADING + #Verdicts.LAST * SLOT)
    board:SetHeight(height)
    board.fixedHeight = height
    board.words = table.concat(words, " ")

    self.undo = {}
    board:SetScript("OnHide", function() RuleOrderUI:LetGo() end)
    self:Refresh(true)
    return board
end

--- Put every row in step with the saved order and switches. `snap` puts
--- them straight in place; otherwise they slide there.
function RuleOrderUI:Refresh(snap)
    if not self.board then return end
    local Verdicts = ns.Verdicts
    if not self.drag then self.order = Copy(Verdicts:Order()) end
    self:Lay(snap)
    for id, row in pairs(self.rows) do
        local on = Verdicts:RuleOn(id)
        if row.check then row.check:SetChecked(on) end
        Shade(row, on)
    end
    for _, row in ipairs(self.fixed) do Shade(row, true) end
    self.defaultButton:SetAlpha(self:CanSetDefault() and 1 or 0.5)
    self.undoButton:SetAlpha(#self.undo > 0 and 1 or 0.5)
end

--- Give each row the place its slot has, and number it.
function RuleOrderUI:Lay(snap)
    local first = #ns.Verdicts.FIRST
    for i, id in ipairs(self.order) do
        local row = self.rows[id]
        if row then
            local x, y = self:SlotAt(i)
            row.tx, row.ty = x, y
            row.number:SetText(first + i)
            if snap or not row.x then
                row.x, row.y = x, y
                row:SetPoint("TOPLEFT", self.board, "TOPLEFT", x, -y)
            end
        end
    end
    if not snap then self:Animate() end
end

--------------------------------------------------------------------------------
-- Dragging
--------------------------------------------------------------------------------

-- The cursor on the board, from its top left, in the board's own scale.
local function Cursor(board)
    local left, top = board:GetLeft(), board:GetTop()
    if not (left and top and GetCursorPosition) then return nil end
    local x, y = GetCursorPosition()
    local scale = board:GetEffectiveScale() or 1
    return x / scale - left, top - y / scale
end

local function IndexOf(list, id)
    for i, have in ipairs(list) do
        if have == id then return i end
    end
end

--- The slot nearest a point on the board.
function RuleOrderUI:NearestSlot(x, y)
    local best, bestDistance
    local halfW, halfH = self.columnWidth / 2, self.ROW / 2
    for i = 1, #self.order do
        local sx, sy = self:SlotAt(i)
        local dx, dy = (sx + halfW) - x, (sy + halfH) - y
        local distance = dx * dx * 0.05 + dy * dy
        if not bestDistance or distance < bestDistance then best, bestDistance = i, distance end
    end
    return best
end

function RuleOrderUI:PickUp(row)
    if self.drag then return end
    local cx, cy = Cursor(self.board)
    if not cx then return end
    self.drag = {
        row = row,
        dx = cx - (row.x or 0),
        dy = cy - (row.y or 0),
        before = Copy(self.order),
    }
    row:SetFrameLevel((self.board:GetFrameLevel() or 1) + 20)
    if GameTooltip then GameTooltip:Hide() end
    Paint(row)
    self:Animate()
end

--- Follow the cursor: the picked-up row under it, the others making room.
function RuleOrderUI:Follow()
    local drag = self.drag
    local cx, cy = Cursor(self.board)
    if not cx then return end
    local row = drag.row
    local maxX = self.secondX
    local maxY = self.top + (self.PER_COLUMN - 1) * self.SLOT
    local x = math.max(0, math.min(maxX, cx - drag.dx))
    local y = math.max(self.top - self.SLOT / 2, math.min(maxY + self.SLOT / 2, cy - drag.dy))
    row.x, row.y = x, y
    row:SetPoint("TOPLEFT", self.board, "TOPLEFT", x, -y)

    local want = self:NearestSlot(x + self.columnWidth / 2, y + self.ROW / 2)
    local at = IndexOf(self.order, row.id)
    if want and at and want ~= at then
        table.remove(self.order, at)
        table.insert(self.order, want, row.id)
        self:Lay(false)
    end
    local sx, sy = self:SlotAt(IndexOf(self.order, row.id) or 1)
    self.mark:SetPoint("TOPLEFT", self.board, "TOPLEFT", sx, -sy)
    self.mark:Show()
end

function RuleOrderUI:LetGo()
    local drag = self.drag
    if not drag then return end
    self.drag = nil
    self.mark:Hide()
    local row = drag.row
    row:SetFrameLevel((self.board:GetFrameLevel() or 1) + 1)
    Paint(row)
    local moved = false
    for i, id in ipairs(self.order) do
        if drag.before[i] ~= id then moved = true break end
    end
    if moved then
        self:Remember(drag.before)
        ns.Verdicts:SetOrder(self.order)
    end
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Motion
--------------------------------------------------------------------------------

--- Ease every row toward its slot, a frame at a time, until all have
--- landed. The row being dragged follows the cursor instead.
function RuleOrderUI:Step(elapsed)
    if self.drag then
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            self:LetGo()
        else
            self:Follow()
        end
    end
    local k = 1 - math.exp(-(elapsed or 0.016) * self.EASE)
    local moving = self.drag ~= nil
    for _, row in pairs(self.rows) do
        if not (self.drag and self.drag.row == row) and row.tx then
            local dx, dy = row.tx - row.x, row.ty - row.y
            if math.abs(dx) < 0.5 and math.abs(dy) < 0.5 then
                if dx ~= 0 or dy ~= 0 then
                    row.x, row.y = row.tx, row.ty
                    row:SetPoint("TOPLEFT", self.board, "TOPLEFT", row.x, -row.y)
                end
            else
                row.x, row.y = row.x + dx * k, row.y + dy * k
                row:SetPoint("TOPLEFT", self.board, "TOPLEFT", row.x, -row.y)
                moving = true
            end
        end
    end
    if not moving then self.board:SetScript("OnUpdate", nil) end
    return moving
end

function RuleOrderUI:Animate()
    if not self.board then return end
    self.board:SetScript("OnUpdate", function(_, elapsed) RuleOrderUI:Step(elapsed) end)
end

--------------------------------------------------------------------------------
-- Changes
--------------------------------------------------------------------------------

-- At most this many changes can be taken back.
RuleOrderUI.UNDO_KEEP = 20

function RuleOrderUI:Remember(order)
    local undo = self.undo
    local db = ns.db or {}
    undo[#undo + 1] = { order = Copy(order or self.order), off = Copy(db.rulesOff) }
    if #undo > self.UNDO_KEEP then table.remove(undo, 1) end
end

function RuleOrderUI:Toggle(id, on)
    local Verdicts = ns.Verdicts
    if not Verdicts.OWN_SWITCH[id] then self:Remember() end
    Verdicts:SetRuleOn(id, on)
    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
    self:Refresh()
end

function RuleOrderUI:CanSetDefault()
    local db = ns.db or {}
    return not ns.Verdicts:IsDefaultOrder() or (type(db.rulesOff) == "table" and next(db.rulesOff) ~= nil)
end

function RuleOrderUI:SetDefault()
    if not self:CanSetDefault() then return end
    self:Remember()
    ns.Verdicts:SetDefault()
    self:Refresh()
end

function RuleOrderUI:Undo()
    local last = table.remove(self.undo)
    if not last then return end
    if ns.db then
        ns.db.rulesOff = next(last.off) and last.off or nil
    end
    ns.Verdicts:SetOrder(last.order)
    self:Refresh()
end

--------------------------------------------------------------------------------
-- The command
--------------------------------------------------------------------------------

ns.RegisterCommand("order", L["open the order Butler asks its rules in (order default puts the usual order back)"], function(rest)
    local word = (rest or ""):lower():match("^%s*(.-)%s*$")
    if word == "default" then
        ns.Verdicts:SetDefault()
        RuleOrderUI:Refresh()
        ns.Print(L["Butler asks its rules in the usual order again."])
        return
    end
    ns.SettingsUI:Show()
    ns.SettingsUI.pages:Show("order")
end)
