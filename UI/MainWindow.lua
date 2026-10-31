-- Blackthornes Butler -- UI/MainWindow.lua
-- The Butler window: every item in your bags and what to do with it, in
-- groups (Sell, Look at it, Keep), each with its count and what it is worth.
--
-- It is what a click on the minimap button and a bare /bbutler open, and it
-- comes up by itself at every vendor and goes when the vendor closes (the
-- "Open at a vendor" setting). The Sell button (Logic/Selling.lua) sits over
-- its foot while a vendor is open, and the Disenchant button
-- (Logic/Disenchanting.lua) left of it while there is something to break.
--
-- It has a second view, All characters (Logic/Everyone.lua; /bbutler all,
-- the header's All characters button): every character's items in one
-- list with a search box, who has each and whether it is in their bags,
-- bank or mail. A click on an item opens a line per character under it.
--
-- Smooth play: the list is set again only when the bags or a verdict changed
-- (Bags.version, Verdicts.version; Everyone.version in All characters), and
-- only while the window is up. Only the rows on screen exist
-- (Widgets.CreateRowList).

local _, ns = ...
local L = ns.L

local UI = ns.NewModule("UI")

-- Which list the window shows: "bags" (what to do with each item) or "all"
-- (every character's items). Bags each time it opens at a vendor.
UI.view = "bags"
-- Items opened in All characters: { [itemID] = true }, for the session.
UI.open = {}

local Theme = ns.Theme
local Widgets = ns.Widgets
local Items = ns.Items

local PADDING = 18
-- From the window's top to the gold rule under the header row.
local HEADER = 44
-- The metal rim sits on the window's edge and reaches this far inward, with
-- room to spare (UI/Titanforged.lua).
local EDGE_PAD = 11
local WIDTH = 620
local HEIGHT = 500
-- Tall enough for a reason or a name on two lines: words wrap, never cut
-- short with "..." (a player found a sell reason cut off, 2026-10-11).
-- A row with more lines grows to hold them (UI.RowHeight): a long reason
-- in German ran over the rows below it (a player's report, 2026-10-21).
local ROW_HEIGHT = 30
-- The room left above and below a row's tallest text.
local ROW_TEXT_PAD = 4
-- From the well's foot to the window's.
local FOOT = 40

-- Where the Sell button sits: in from the window's right edge and up from
-- its foot (Selling:Place).
UI.SELL_INSET_X = PADDING
UI.SELL_INSET_Y = 9

-- The mailbox and bank buttons' widths; Fill mail carries a name.
local ERRAND_WIDTH = 140
local MAIL_WIDTH = 180

-- The window's size, dragged at the grip below its bottom right corner as
-- in Tradeskills' window and Equipment's upgrade quest panel. Saved as
-- `windowScale`, account wide.
local SCALE_MIN = 0.6
local SCALE_MAX = 1.5
local GRIP_SIZE = 20

-- The game's item quality colours (Items.QualityRGB), Common white for an
-- item not read yet.
local function QualityColor(quality)
    local r, g, b = Items.QualityRGB(quality or 1)
    if not r then return 1, 1, 1 end
    return r, g, b
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function UI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesButlerWindow", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetScale(self:GetWindowScale())
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window")

    -- The house frame (UI/Titanforged.lua): a gold rim with corner gems, the
    -- satchel in a round portrait, the name on a plate and a red close gem.
    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = "Blackthornes Butler",
            portrait = true,
            close = function() UI:Hide() end,
        })
        self.trim = trim

        -- Kept on the screen whole: the portrait and plate reach out past
        -- the top left, and the corner gems past every edge.
        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then
            frame:SetClampRectInsets(-left, right, top, -bottom)
        end
    else
        Theme.Border(frame, "borderLit")
    end

    -- The secure buttons hide while the window moves and come back where
    -- it lands.
    frame:SetScript("OnDragStart", function(self)
        UI.dragging = true
        if ns.Selling then ns.Selling:Update() end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI.dragging = false
        UI:SavePosition()
        if ns.ButlerTabs then ns.ButlerTabs:Save(self) end
        if ns.Selling then ns.Selling:Update() end
    end)
    frame:SetScript("OnHide", function()
        -- Only stepping aside for the Settings tab (UI/ButlerTabs.lua): the
        -- window is still up, so nothing is said and nothing let go.
        if ns.ButlerTabs and ns.ButlerTabs.switching then
            UI.dragging = false
            UI:HideMenu()
            if ns.Selling then ns.Selling:Update() end
            return
        end
        -- Closed by the player (close gem, Escape, /bbutler, the minimap
        -- button), not by leaving the vendor, mailbox or bank it came up for.
        if UI.closingByItself then
            UI.closingByItself = false
        else
            UI:Say("close")
        end
        UI.dragging = false
        UI.openedByVendor = false
        UI.openedFor = nil
        UI:HideMenu()
        if ns.Selling then ns.Selling:Update() end
        if ns.Errands then ns.Errands:TellTradeskills(false) end
        -- Inside the one window, it closes with this one.
        if ns.ButlerTabs then ns.ButlerTabs:Closed(frame) end
    end)

    -- The fold gem beside the close gem (UI/FoldWindow.lua): the window
    -- folds to its plate and opens again.
    if ns.FoldWindow then
        ns.FoldWindow:Add(frame, { onToggle = function(folded)
            if not folded then UI:Refresh() end
            UI:PlaceButtons()
        end })
    end

    -- Escape closes it, like the game's own windows.
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesButlerWindow")
    end

    self.frame = frame
    self:BuildHeader()

    -- The list's well, sunk into the window like Pets' and Equipment's.
    local well = Theme.CreatePanel(frame, "panel", "border")
    well:SetPoint("TOPLEFT", PADDING, -(HEADER + 10))
    well:SetPoint("BOTTOMRIGHT", -PADDING, FOOT)
    if Theme.Recess then Theme.Recess(well) end
    self.well = well

    self.list = Widgets.CreateRowList(well, {
        rowHeight = ROW_HEIGHT,
        fadeKey = "panel",
        createRow = function(row) UI.CreateRow(row) end,
        updateRow = function(row, data) UI.UpdateRow(row, data) end,
        fitRow = function(row) return UI.RowHeight(row) end,
        onClick = function(data, button) UI:Clicked(data, button) end,
        onEnter = function(row, data) UI:Enter(row, data) end,
        onLeave = function() GameTooltip:Hide() end,
        -- The buttons on group lines (Sell, Disenchant, Bank, Log out)
        -- follow their line as the list scrolls.
        onRefresh = function() UI:PlaceButtons() end,
    })
    self.list:SetPoint("TOPLEFT", 6, -6)
    self.list:SetPoint("BOTTOMRIGHT", -6, 6)

    -- Gold goals sit at the bottom, under the list (UI/GoldGoals.lua; the
    -- owner, 2026-10-13: "the purse section goes at the bottom").
    if ns.GoldGoalsUI then
        local goals = ns.GoldGoalsUI:Build(frame)
        goals:SetPoint("BOTTOMLEFT", PADDING, FOOT)
        goals:SetPoint("BOTTOMRIGHT", -PADDING, FOOT)
        goals:Hide()
    end

    -- The house empty block (UI/HouseKit.lua): the emblem faint, one line,
    -- and a button when there's a next step.
    local empty = Widgets.CreateEmpty(well, { width = WIDTH - 4 * PADDING })
    empty:SetPoint("CENTER", 0, 0)
    self.emptyLabel = empty

    -- The installed version, small and faint in the bottom right corner,
    -- so a player can see at a glance which one they run. The Sell button
    -- takes its place at a vendor.
    local version = Theme.CreateLabel(frame, "tiny", "dim", "RIGHT")
    version:SetPoint("BOTTOMRIGHT", -PADDING, 14)
    version:SetText(ns.VersionLabel())
    self.versionLabel = version

    local footer = Theme.CreateLabel(frame, "small", "muted")
    footer:SetPoint("BOTTOMLEFT", PADDING, 14)
    footer:SetPoint("RIGHT", frame, "RIGHT", -(PADDING + 90), 0)
    self.footer = footer

    -- At a mailbox or the bank (Logic/Errands.lua): plain buttons in the
    -- Sell button's place, which only shows at a vendor.
    local function Run(fn)
        return function()
            local _, message = fn(ns.Errands)
            if message then ns.Print(message) end
        end
    end
    self.mailButton = Widgets.CreateButton(frame, L["Fill Mail"], function()
            local _, message = ns.Errands:FillMail(UI.footMail)
            if message then ns.Print(message) end
        end,
        { width = MAIL_WIDTH, height = 24, primary = true })
    self.mailButton:SetPoint("BOTTOMRIGHT", -UI.SELL_INSET_X, UI.SELL_INSET_Y)
    self.mailButton.tooltipText = L["Fills in the mail for you. Check it, then press Send."]
    self.mailButton:Hide()

    self.bankButton = Widgets.CreateButton(frame, L["Move to bank"], Run(ns.Errands.MoveToBank),
        { width = ERRAND_WIDTH, height = 24, primary = true })
    self.bankButton:SetPoint("BOTTOMRIGHT", -UI.SELL_INSET_X, UI.SELL_INSET_Y)
    self.bankButton.tooltipText = L["Puts your Always bank items in the bank."]
    self.bankButton:Hide()

    self.takeButton = Widgets.CreateButton(frame, L["Take from bank"], Run(ns.Errands.TakeFromBank),
        { width = ERRAND_WIDTH, height = 24 })
    self.takeButton.tooltipText = L["Takes out upgrades to wear and what your crafts still need."]
    self.takeButton:Hide()

    -- Craft When It Pays More (2026-10-19): on the Craft heading, puts each
    -- row's craft in Tradeskills' queue.
    self.queueButton = Widgets.CreateButton(frame, L["Queue"], function() UI:QueueCrafts() end,
        { width = 80, height = 24, primary = true })
    self.queueButton:Hide()

    self:BuildSizeGrip()

    -- Your Bags, All Characters and Settings hang below it
    -- (UI/ButlerTabs.lua).
    if ns.ButlerTabs then ns.ButlerTabs:Attach(self) end

    -- A new frame starts shown, so this Hide runs OnHide: it is no close by
    -- the player, and must not say Moroes's closing line (both lines played
    -- on the first open, 2026-10-11).
    self.closingByItself = true
    frame:Hide()
    self.closingByItself = false
    return frame
end

--- The header row. The window's name is on the plate across the top edge
--- and the close gem sits on the top right corner (UI/Titanforged.lua), so
--- the row holds the search, clear of the portrait on the left. The views
--- and Settings are tabs below the window (UI/ButlerTabs.lua).
function UI:BuildHeader()
    local frame = self.frame

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", EDGE_PAD, -EDGE_PAD)
    header:SetPoint("TOPRIGHT", -EDGE_PAD, -EDGE_PAD)
    header:SetHeight(HEADER - EDGE_PAD)

    -- A gold rule under it, bright at the left and fading out to the right.
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Theme.SetGradientAlpha(rule, "HORIZONTAL", "accent", 0.6, 0.05)

    -- Past the portrait, which reaches 48 pixels into the window.
    local subtitle = Theme.CreateLabel(header, "small", "muted")
    subtitle:SetPoint("LEFT", header, "LEFT", 48, -4)
    self.subtitle = subtitle

    -- All characters' search, in the subtitle's place.
    local search = Widgets.CreateSearchBox(header, L["Search all characters"], function()
        UI:Refresh()
    end)
    search:SetPoint("LEFT", header, "LEFT", 48, -2)
    search:SetWidth(260)
    search:Hide()
    self.search = search

    -- Your bags' own search (the owner said yes, 2026-10-13), the same box
    -- in the same place, its words kept apart so each view keeps its own.
    local bagSearch = Widgets.CreateSearchBox(header, L["Search your bags"], function()
        UI:Refresh()
    end)
    bagSearch:SetPoint("LEFT", header, "LEFT", 48, -2)
    bagSearch:SetWidth(260)
    bagSearch:SetShown(self.view ~= "all")
    subtitle:Hide()
    self.bagSearch = bagSearch
end

--- Empty a search box and draw the list again (the empty block's Clear
--- Search).
function UI:ClearSearch(box)
    if box and box.SetText then box:SetText("") end
    self:Refresh()
end

--- Show one list or the other: "bags" or "all".
function UI:SetView(view)
    view = view == "all" and "all" or "bags"
    local changed = view ~= self.view
    self.view = view
    if not self.frame then return end

    local all = view == "all"
    -- Each view's search sits where the line on what is shown sat.
    self.subtitle:Hide()
    self.search:SetShown(all)
    self.bagSearch:SetShown(not all)
    if all then self.bagSearch:ClearFocus() else self.search:ClearFocus() end
    if ns.ButlerTabs then ns.ButlerTabs:Light(self) end

    if changed then
        self.drawnKey = nil
        GameTooltip:Hide()
        if all then ns.Everyone:Changed() end
        if ns.Selling then ns.Selling:Update() end
        self:UpdateErrands()
        self:Refresh(true)
    end
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- The worth column is WORTH_WIDTH wide and grows, up to WORTH_MOST, for
-- a longer text ("8s 00c, 1 not priced yet"), measured as the game draws
-- it; the note beside it gives way and wraps. Past WORTH_MOST it wraps too.
UI.WORTH_WIDTH = 96
UI.WORTH_MOST = 200

--- A row's pieces, built once: the item's icon and name, the reason, and
--- what the stack is worth. A group's heading uses the same pieces.
function UI.CreateRow(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
    row.icon:SetPoint("LEFT", 6, 0)
    if row.icon.SetTexCoord then row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    if ns.ItemLook then ns.ItemLook.Attach(row.icon) end

    row.fold = Theme.CreateLabel(row, "normal", "accent", "CENTER")
    row.fold:SetPoint("CENTER", row, "LEFT", 14, 0)
    row.fold:SetWidth(16)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 34, 0)
    row.name:SetWidth(184)
    row.name:SetWordWrap(true)

    row.worth = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.worth:SetPoint("RIGHT", -6, 0)
    row.worth:SetWidth(UI.WORTH_WIDTH)
    row.worth:SetWordWrap(true)

    -- Money as the game's coins, each in its own column (UI/Coins.lua),
    -- in the worth column's place.
    if ns.Coins then
        row.coins = ns.Coins.Create(row, function() return Theme.CreateLabel(row, "small", "text", "RIGHT") end)
        ns.Coins.Place(row.coins, row, "RIGHT", -6, 0)
    end

    row.reason = Theme.CreateLabel(row, "small", "muted")
    row.reason:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.reason:SetPoint("RIGHT", row.worth, "LEFT", -8, 0)
    row.reason:SetWordWrap(true)

    -- The small mark before what to do (UI/Marks.lua), on an item's row.
    if ns.Marks then
        row.mark = row:CreateTexture(nil, "ARTWORK")
        ns.Marks.Attach(row.mark)
        row.mark:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    end

    -- The Ammo row's Fill button and a job's Craft or Buy button sit where
    -- the worth goes (Logic/Ammo.lua, Logic/Jobs.lua).
    row.action = Widgets.CreateButton(row, L["Fill"], function() UI.RowAction(row.data) end, {
        primary = true, width = 80, height = 22,
    })
    row.action:SetPoint("RIGHT", -8, 0)
    row.action:Hide()
end

--- The row's button: Fill on the Ammo row, Craft on a job, Fill mail on
--- the line that mails a character.
function UI.RowAction(data)
    if not data then return end
    local to = UI.fillRows[data]
    if to then
        local _, message = ns.Errands:FillMail(to)
        if message then ns.Print(message) end
    elseif data.type == "ammo" then
        ns.Ammo:Buy()
    elseif data.type == "job" and data.step and data.step.kind == "buy" then
        ns.Jobs:BuyAtVendor()
    elseif data.type == "questbuy" then
        ns.QuestBuy:Click(data.item)
    elseif data.type == "skillup" then
        ns.SkillUp:Queue(data.entry)
    elseif data.type == "job" and data.step and data.step.kind == "quest" then
        if ns.Quests:Search(data.step.items) then UI:Refresh(true) end
    elseif data.type == "job" then
        ns.Jobs:Craft(data.step)
    elseif data.type == "train" then
        local training = ns.ClassTraining
        if training.trainerOpen and training.atClassTrainer then
            training:TrainAll()
        else
            training:ShowTheWay()
        end
    end
end

local function Plural(count, one, many)
    return L.Format("%d %s", count, count == 1 and one or many)
end

-- Fill mail sits on the first line that mails each character (a Jobs
-- step, a gold top-up or a Mail row), the way Log out sits on the next
-- character's line (the owner asked 2026-10-12). Set by UI:PlaceMail each
-- time the lines are built: { [line] = name }, and which names have one.
UI.fillRows = setmetatable({}, { __mode = "k" })
UI.mailOnRows = {}

--- What a row is worth: the coins in their columns, or the words for a
--- client without them. Nothing for no amount.
function UI.SetMoney(row, copper)
    local coins = rawget(row, "coins")
    if type(copper) ~= "number" or copper <= 0 then
        if coins then ns.Coins.Set(coins, nil) end
        row.worth:SetText("")
        return
    end
    if coins then
        row.worth:SetText("")
        ns.Coins.Set(coins, copper)
    else
        row.worth:SetText(Items.FormatMoney(copper))
    end
end

function UI.FitWorth(row)
    local text = row.worth:GetText()
    local width = UI.WORTH_WIDTH
    local coins = rawget(row, "coins")
    if coins and ns.Coins.Shown(coins) then
        width = math.max(width, ns.Coins.Width(coins))
    end
    if type(text) == "string" and text ~= "" then
        width = math.max(width, math.ceil(Theme.TextWidth("small", text)) + 4)
    end
    row.worth:SetWidth(math.min(width, UI.WORTH_MOST))
end

-- How tall a label's text stands: the game's own measure, never less than
-- its width says (a label laid out this frame can answer short), and the
-- width's count alone where the game says nothing.
local function TextHeight(label, size, width)
    local text = label:GetText()
    if type(text) ~= "string" or text == "" then return 0 end
    local lines = math.max(1, math.ceil(Theme.TextWidth(size, text) / math.max(1, width)))
    local guess = lines * ((Theme.sizes[size] or 11) + 2)
    local ok, height = pcall(label.GetStringHeight, label)
    if ok and type(height) == "number" and height > guess then return height end
    return guess
end

--- How tall a filled row must be to hold its name, reason and worth as
--- they wrap, and its button: never under ROW_HEIGHT.
function UI.RowHeight(row)
    local ok, rowWidth = pcall(row.GetWidth, row)
    rowWidth = ok and tonumber(rowWidth) or 0
    local ok2, worthWidth = pcall(row.worth.GetWidth, row.worth)
    worthWidth = ok2 and tonumber(worthWidth) or UI.WORTH_WIDTH
    local nameWidth = 184
    local reasonWidth = rowWidth - 34 - nameWidth - (rawget(row, "markGap") or 8) - 8 - worthWidth - 6
    if reasonWidth < 40 then reasonWidth = 40 end
    local tallest = math.max(
        TextHeight(row.name, "small", nameWidth),
        TextHeight(row.reason, "small", reasonWidth),
        TextHeight(row.worth, "small", worthWidth))
    local shown = row.action and row.action.IsShown and row.action:IsShown()
    if shown == true then tallest = math.max(tallest, 22) end
    return math.max(ROW_HEIGHT, math.ceil(tallest) + ROW_TEXT_PAD)
end

function UI.UpdateRow(row, data)
    if row.action then row.action.tooltipText = nil end
    UI.DrawRow(row, data)
    UI.FitWorth(row)
    local to = row.action and UI.fillRows[data]
    if to then
        -- The button takes the worth column's place, so the note keeps the
        -- width every other row gives it and wraps in two lines, never
        -- squeezed into lines that run over the row (seen in game
        -- 2026-10-12). The worth is still on the row's tooltip.
        row.worth:SetText("")
        if rawget(row, "coins") then ns.Coins.Set(row.coins, nil) end
        row.action:SetText(L["Fill Mail"])
        row.action.tooltipText = L.Format("Fills in a mail to %s. Check it, then press Send.", to)
        if (data.worth or 0) > 0 then
            row.action.tooltipText = row.action.tooltipText .. "\n"
                .. L.Format("What it's worth: %s", Items.FormatMoney(data.worth))
        end
        row.action:Show()
    end
end

function UI.DrawRow(row, data)
    local openEdge = rawget(row, "openEdge")
    if openEdge then openEdge:Hide() end
    row.worth:SetTextColor(Theme.Unpack("text"))
    row.reason:SetTextColor(Theme.Unpack("muted"))
    if rawget(row, "coins") then ns.Coins.Set(row.coins, nil) end
    UI.PlaceMark(row, nil)
    if row.action then row.action:Hide() end
    -- The quality ring and stack count (UI/ItemLook.lua) only on an item's
    -- own row.
    if ns.ItemLook then
        ns.ItemLook.SetQuality(row.icon, nil)
        ns.ItemLook.SetCount(row.icon, nil)
    end
    if data.type == "ammo" then return UI.UpdateAmmoRow(row, data) end
    if data.type == "everyone" then return UI.UpdateItemRow(row, data) end
    if data.type == "holder" then return UI.UpdateHolderRow(row, data) end
    if data.type == "gold" then return UI.UpdateGoldRow(row, data) end
    if data.type == "job" then return UI.UpdateJobRow(row, data) end
    if data.type == "jobnext" then return UI.UpdateNextRow(row, data) end
    if data.type == "questbuy" then return UI.UpdateQuestBuyRow(row, data) end
    if data.type == "skillup" then return UI.UpdateSkillUpRow(row, data) end
    if data.type == "train" or data.type == "trainnext" or data.type == "trainalt" then
        return UI.UpdateTrainRow(row, data)
    end

    if data.type == "header" then
        local group = data.group
        row.icon:Hide()
        row.fold:Show()
        row.fold:SetText(data.folded and "+" or "-")
        row.name:SetTextColor(Theme.Unpack("accent"))
        row.name:SetText(group.label:upper())
        row.reason:SetText(Plural(group.count, group.one or L["item"], group.many or L["items"]))
        UI.SetMoney(row, group.worth)
        return
    end

    row.fold:Hide()
    row.icon:Show()
    row.icon:SetTexture(data.icon or [[Interface\Icons\INV_Misc_QuestionMark]])
    row.name:SetTextColor(QualityColor(data.quality))
    if ns.ItemLook then
        ns.ItemLook.SetQuality(row.icon, data.quality)
        -- The stack's count sits on the icon's corner, as in the bags.
        ns.ItemLook.SetCount(row.icon, data.count)
        row.name:SetText(data.name)
    else
        row.name:SetText(data.count > 1 and L.Format("%s x%d", data.name, data.count) or data.name)
    end
    row.reason:SetText(data.reason or "")
    -- Bought to disenchant reads in the tag's violet, as on Tradeskills' tab.
    if data.bought then
        row.reason:SetTextColor(0.73, 0.55, 1)
    else
        row.reason:SetTextColor(Theme.Unpack("muted"))
    end
    -- What to do, with its mark, in the mark's colour.
    local kind = UI.MarkFor(data)
    UI.PlaceMark(row, kind)
    if kind and not data.bought and ns.Marks then ns.Marks.Paint(row.reason, kind) end
    UI.SetMoney(row, data.worth)
end

-- Each verdict's mark (UI/Marks.lua): a coin for Sell, a letter for Mail and
-- so on; a kept upgrade gets the arrow.
UI.VERDICT_MARKS = {
    sell = "sell", mail = "mail", keep = "keep", disenchant = "disenchant",
    bank = "bank", look = "look", auction = "list", wait = "waiting", craft = "craft",
}

function UI.MarkFor(data)
    if not data or data.type ~= "item" then return nil end
    if data.verdict == "keep" and data.keptUpgrade then return "upgrade" end
    return UI.VERDICT_MARKS[data.verdict]
end

-- Shows the mark (or none) and moves the words past it.
function UI.PlaceMark(row, kind)
    local mark = rawget(row, "mark")
    if not mark or not ns.Marks then return end
    ns.Marks.Set(mark, kind)
    local gap = kind and (8 + ns.Marks.SIZE + 4) or 8
    if row.markGap == gap then return end
    row.markGap = gap
    row.reason:ClearAllPoints()
    row.reason:SetPoint("LEFT", row.name, "RIGHT", gap, 0)
    row.reason:SetPoint("RIGHT", row.worth, "LEFT", -8, 0)
end

--- A gold top-up: who it goes to, what they have and keep, and how much.
function UI.UpdateGoldRow(row, data)
    local entry = data.entry
    row.fold:Hide()
    row.icon:Show()
    row.icon:SetTexture([[Interface\Icons\INV_Misc_Coin_01]])
    row.name:SetTextColor(Theme.Unpack("text"))
    row.name:SetText(entry.to)
    row.reason:SetText(ns.Funds.Reason(entry))
    UI.SetMoney(row, entry.amount)
end

--- A step for the character playing: what to craft or mail, and why, with
--- a Craft button on a craft it has the materials for.
function UI.UpdateJobRow(row, data)
    local step = data.step
    local title, detail = ns.Jobs.StepText(step)
    row.fold:Hide()
    row.icon:Show()
    row.icon:SetTexture(ns.Jobs.Icon(step))
    row.name:SetTextColor(Theme.Unpack("text"))
    row.name:SetText(title)
    row.reason:SetText(detail)
    if step.kind == "craft" and not step.ready then row.reason:SetTextColor(Theme.Unpack("accent")) end
    row.worth:SetText("")
    -- At a vendor, Buy from a vendor says what this one has, with Buy.
    local atVendor = ns.Jobs.VendorText(step)
    if atVendor then
        row.reason:SetText(atVendor)
        if not ns.Jobs.Buyable(step) then row.reason:SetTextColor(Theme.Unpack("accent")) end
    end
    if ns.Jobs.Searchable(step) then
        row.action:SetText(ns.Jobs.SearchLabel(step))
        row.action.tooltipText = ns.Jobs.SearchTooltip(step)
        row.action:Show()
    elseif ns.Jobs.Buyable(step) then
        row.action:SetText(ns.Jobs.offer.buying and L["Buying..."] or L["Buy"])
        row.action.tooltipText = ns.Jobs.BuyTooltip()
        row.action:Show()
    elseif ns.Jobs.Craftable(step) then
        -- In a form that stops a craft, the secure Leave form button
        -- (Jobs:UpdateLeaveForm) covers the first of these.
        row.action:SetText(ns.Jobs.InBlockingForm() and L["Leave form"] or L["Craft"])
        row.action:Show()
    end
end

--- An item an open quest needs, at the auction house: how many, for
--- which quest and about what it costs, with Buy, then Pay
--- (Logic/QuestBuy.lua).
function UI.UpdateQuestBuyRow(row, data)
    local item = data.item
    row.fold:Hide()
    row.icon:Show()
    row.icon:SetTexture(Items.Call({ "C_Item.GetItemIconByID", "GetItemIcon" }, item.itemID)
        or [[Interface\Icons\INV_Misc_QuestionMark]])
    local quality = Items.Call({ "C_Item.GetItemQualityByID" }, item.itemID)
    row.name:SetTextColor(QualityColor(tonumber(quality)))
    if ns.ItemLook then ns.ItemLook.SetQuality(row.icon, tonumber(quality)) end
    row.name:SetText(ns.Jobs.ItemName(item.itemID))
    local text, money = ns.QuestBuy:Text(item)
    row.reason:SetText(text)
    row.worth:SetText(money and Items.FormatMoney(money) or "")
    local label, tip = ns.QuestBuy:Button(item)
    if label then
        row.action:SetText(label)
        row.action.tooltipText = tip
        row.action:Show()
    end
end

--- The cheapest craft for the next skill point in a profession
--- (Logic/SkillUp.lua), with Queue, or Queued once it's in the queue.
function UI.UpdateSkillUpRow(row, data)
    local entry = data.entry
    local title, detail = ns.SkillUp.Text(entry)
    row.fold:Hide()
    row.icon:Show()
    row.icon:SetTexture(ns.SkillUp.Icon(entry))
    row.name:SetTextColor(Theme.Unpack("text"))
    row.name:SetText(title)
    -- Short of gold for what's missing: the red note takes the line's
    -- place (the row has room for two lines), the rest is on the hover.
    local short = ns.SkillUp.ShortNote(entry)
    if short then
        row.reason:SetText("|c" .. ns.COLORS.bad .. short .. "|r")
    else
        row.reason:SetText(detail)
    end
    row.worth:SetText("")
    if entry.capped then return end
    row.action:SetText(entry.queued and L["Queued"] or L["Queue"])
    row.action:Show()
end

--- Another character with work waiting: who, and what they have to do.
function UI.UpdateNextRow(row, data)
    local job = data.job
    row.fold:Hide()
    row.icon:Show()
    row.icon:SetTexture([[Interface\Icons\Ability_Rogue_Disguise]])
    row.name:SetTextColor(Theme.Unpack(data.isNext and "accent" or "text"))
    row.name:SetText(data.isFirst and L.Format("First: %s", job.name)
        or data.isNext and L.Format("Next: %s", job.name) or L.Format("Then: %s", job.name))
    row.reason:SetText(ns.Jobs.Summary(job))
    row.worth:SetText("")
end

--- Class spells to train (Logic/ClassTraining.lua): now, at the next
--- level, or on another character. The row for now has Show the way, or
--- Train all at the trainer.
function UI.UpdateTrainRow(row, data)
    local training = ns.ClassTraining
    row.fold:Hide()
    row.icon:Show()
    row.name:SetTextColor(Theme.Unpack("text"))
    if data.type == "train" then
        local plan = data.plan
        local count = #plan.ready
        row.icon:SetTexture(training.Icon(plan.ready[1].entry))
        row.name:SetText(count == 1 and L["Train 1 new spell"] or L.Format("Train %d new spells", count))
        local spot = training:Nearest()
        local where = training.Where(spot)
        local class = training.Player().className or ""
        if where then
            row.reason:SetText(L.Format("%s trainer, %s", class, where))
        else
            row.reason:SetText(L.Format("At any %s trainer", class))
        end
        row.worth:SetText("")
        if training.trainerOpen and training.atClassTrainer then
            row.action:SetText(training.buying and L["Training..."] or L["Train All"])
            row.action:Show()
        elseif spot then
            row.action:SetText(L["Show the Way"])
            row.action:Show()
        else
            row.worth:SetText(training.CostText(plan.cost, plan.unknown, count))
        end
        return
    end
    if data.type == "trainnext" then
        local plan = data.plan
        row.icon:SetTexture(training.Icon(plan.next[1].entry))
        row.name:SetTextColor(Theme.Unpack("muted"))
        local count = #plan.next
        row.name:SetText(count == 1 and L.Format("At level %d: 1 more spell", plan.nextLevel)
            or L.Format("At level %d: %d more spells", plan.nextLevel, count))
        local names = {}
        for index = 1, math.min(3, count) do names[index] = training.SpellName(plan.next[index].entry) end
        local text = table.concat(names, ", ")
        if count > 3 then text = L.Format("%s and %d more", text, count - 3) end
        row.reason:SetText(text)
        row.worth:SetText(training.CostText(plan.nextCost, plan.nextUnknown, count))
        row.worth:SetTextColor(Theme.Unpack("muted"))
        return
    end
    local other = data.other
    row.icon:SetTexture([[Interface\Icons\INV_Misc_Book_09]])
    row.name:SetTextColor(Theme.Unpack("accent"))
    row.name:SetText(L.Format("Then: %s", other.name or "?"))
    row.reason:SetText(other.count == 1
        and L.Format("1 %s spell to train at level %d", other.className or "", other.level or 0)
        or L.Format("%d %s spells to train at level %d", other.count, other.className or "", other.level or 0))
    row.worth:SetText(training.CostText(other.cost, other.unknown, other.count))
end

--- Filling the quiver or ammo pouch: the best ammo the vendor has, how
--- many fit and what they cost, and the Fill button when it can buy.
function UI.UpdateAmmoRow(row, data)
    local offer = data.offer
    row.fold:Hide()
    row.icon:Show()
    row.icon:SetTexture(offer.ammo.icon or [[Interface\Icons\INV_Ammo_Arrow_02]])
    row.name:SetTextColor(Theme.Unpack("text"))
    row.name:SetText(offer.ammo.name and Items:ColorName(offer.ammo.name, offer.ammo.itemID) or L["Ammo"])
    row.reason:SetText(ns.Ammo.Reason(offer))
    if offer.state ~= "fill" then row.reason:SetTextColor(Theme.Unpack("accent")) end
    row.worth:SetText("")
    if offer.state == "fill" then
        row.action:SetText(ns.Ammo.buying and L["Buying..."] or L["Fill"])
        row.action:Show()
    end
end

--- An item in All characters: its name, who has it and how many in all.
function UI.UpdateItemRow(row, data)
    local item = data.item
    row.fold:Hide()
    row.icon:Show()
    row.icon:SetTexture(item.icon or [[Interface\Icons\INV_Misc_QuestionMark]])
    if ns.ItemLook then ns.ItemLook.SetQuality(row.icon, item.quality) end
    row.name:SetTextColor(QualityColor(item.quality))
    row.name:SetText(item.name)
    row.reason:SetText(ns.Everyone.Summary(item))
    row.worth:SetText(tostring(item.total))
    -- The item opened to show each character is dark gold with a bright
    -- gold edge down its left, as every list's open row is (the house rule).
    if data.open then
        if row.stripe then row.stripe:SetColorTexture(Theme.Unpack("glassActive")) end
        if not rawget(row, "openEdge") then
            row.openEdge = row:CreateTexture(nil, "ARTWORK")
            row.openEdge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.openEdge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.openEdge:SetWidth(2)
        end
        row.openEdge:SetColorTexture(Theme.Unpack("accentHi"))
        row.openEdge:Show()
    end
end

--- One character's share of an opened item, set in under it.
function UI.UpdateHolderRow(row, data)
    local holder = data.holder
    local character = holder.character
    row.fold:Hide()
    row.icon:Hide()
    local name = "    " .. character.short
    if character.isCurrent then
        name = "    " .. L.Format("%s (you)", character.short)
    elseif character.linked then
        name = "    " .. L.Format("%s (other account)", character.short)
    end
    row.name:SetTextColor(Theme.Unpack("text"))
    row.name:SetText(name)
    row.reason:SetText(ns.Everyone.Where(holder))
    row.worth:SetTextColor(Theme.Unpack("muted"))
    row.worth:SetText(ns.Everyone.Age(ns.Everyone.Seen(holder)))
end

--- The rows to show: each group's heading, then its items unless folded.
--- Groups with nothing in them are left out.
--- What the Your bags search asks for, trimmed and lower case; "" for none.
function UI:BagSearch()
    local text = self.bagSearch and self.bagSearch:GetText() or ""
    return (text:lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Does an item row match the Your bags search? By name, as All
--- characters does (Everyone.Matches), or by item ID.
function UI.RowMatches(row, search)
    if search == "" then return true end
    local name = type(row.name) == "string" and row.name:lower() or ""
    return name:find(search, 1, true) ~= nil or tostring(row.itemID) == search
end

function UI:Lines()
    local lines = {}
    local folded = self:Folded()
    -- A search shows only the items it matches, under their groups, open
    -- whether folded or not; the ammo, jobs and gold lines wait.
    local search = self:BagSearch()
    if search ~= "" then
        self.matched = 0
        for _, group in ipairs(ns.Verdicts:Groups()) do
            local rows, worth = {}, 0
            for _, row in ipairs(group.rows) do
                if UI.RowMatches(row, search) then
                    rows[#rows + 1] = row
                    worth = worth + (row.worth or 0)
                end
            end
            if #rows > 0 then
                local shown = setmetatable({ count = #rows, worth = worth }, { __index = group })
                lines[#lines + 1] = { type = "header", group = shown, folded = false }
                for _, row in ipairs(rows) do lines[#lines + 1] = row end
                self.matched = self.matched + #rows
            end
        end
        self:PlaceMail(lines)
        return lines
    end
    -- At a vendor, filling a hunter's quiver or pouch comes first
    -- (Logic/Ammo.lua).
    local offer = ns.Ammo and ns.Ammo:Offer()
    if offer then
        local word = offer.bag and offer.bag.label or ns.Ammo.BAGS[offer.weapon.ammo].label
        local group = { verdict = "ammo", label = L["Ammo"], count = 1, worth = offer.cost or 0,
            one = word, many = word }
        local isFolded = folded.ammo == true
        lines[#lines + 1] = { type = "header", group = group, folded = isFolded }
        if not isFolded then lines[#lines + 1] = { type = "ammo", offer = offer } end
    end
    -- Jobs for the craft queue, here and on other characters
    -- (Logic/Jobs.lua).
    local jobRows = ns.Jobs and ns.Jobs:Lines() or {}
    if #jobRows > 0 then
        local group = { verdict = "jobs", label = L["Jobs"], count = #jobRows, worth = 0,
            one = L["step"], many = L["steps"] }
        local isFolded = folded.jobs == true
        lines[#lines + 1] = { type = "header", group = group, folded = isFolded }
        if not isFolded then
            for _, row in ipairs(jobRows) do lines[#lines + 1] = row end
        end
    end
    -- The cheapest craft for the next skill point in each profession
    -- (Logic/SkillUp.lua), its own group right under Jobs, so the queued
    -- crafts stay on top (the owner, 2026-10-20). Only while "Cheapest
    -- Skill-Up:" is ticked.
    local levelRows = ns.SkillUp and ns.SkillUp:Rows() or {}
    if #levelRows > 0 then
        local group = { verdict = "leveling", label = L["Profession Leveling"], count = #levelRows, worth = 0,
            one = L["profession"], many = L["professions"] }
        local isFolded = folded.leveling == true
        lines[#lines + 1] = { type = "header", group = group, folded = isFolded }
        if not isFolded then
            for _, row in ipairs(levelRows) do lines[#lines + 1] = row end
        end
    end
    -- At a mailbox, the gold fund's top-ups come first (Logic/Funds.lua).
    if ns.Errands.mailOpen and ns.Funds then
        local plan = ns.Funds:Plan()
        if #plan > 0 then
            local worth = 0
            for _, entry in ipairs(plan) do worth = worth + entry.amount end
            local group = { verdict = "gold", label = L["Gold"], count = #plan, worth = worth,
                one = L["character"], many = L["characters"] }
            local isFolded = folded.gold == true
            lines[#lines + 1] = { type = "header", group = group, folded = isFolded }
            if not isFolded then
                for _, entry in ipairs(plan) do lines[#lines + 1] = { type = "gold", entry = entry } end
            end
        end
    end
    for _, group in ipairs(ns.Verdicts:Groups()) do
        if group.count > 0 then
            local isFolded = UI.IsFolded(folded, group.verdict)
            lines[#lines + 1] = { type = "header", group = group, folded = isFolded }
            if not isFolded then
                for _, row in ipairs(group.rows) do lines[#lines + 1] = row end
            end
        end
    end
    -- Training that waits for a level or another character goes last,
    -- right above Gold goals (Jobs:LaterLines).
    local laterRows = ns.Jobs and ns.Jobs:LaterLines() or {}
    if #laterRows > 0 then
        local group = { verdict = "later", label = L["Later"], count = #laterRows, worth = 0,
            one = L["step"], many = L["steps"] }
        local isFolded = folded.later == true
        lines[#lines + 1] = { type = "header", group = group, folded = isFolded }
        if not isFolded then
            for _, row in ipairs(laterRows) do lines[#lines + 1] = row end
        end
    end
    self:PlaceMail(lines)
    return lines
end

--- Who a line mails to, when it does: a Jobs mail step, a gold top-up or
--- a row under Mail.
local function MailsTo(line)
    if line.type == "job" then return line.step and line.step.kind == "mail" and line.step.to or nil end
    if line.type == "gold" then return line.entry and line.entry.to end
    if line.type == "item" and line.verdict == "mail" then return line.mailTo end
    return nil
end

--- At a mailbox, give each character's mail a Fill mail button on the
--- first line that mails them. A character whose lines are all folded
--- away keeps the button at the window's foot (UI:UpdateErrands).
function UI:PlaceMail(lines)
    UI.fillRows = setmetatable({}, { __mode = "k" })
    UI.mailOnRows = {}
    if not ns.Errands.mailOpen then return end
    local recipients = ns.Errands:Recipients()
    if #recipients == 0 then return end
    for _, line in ipairs(lines) do
        local to = MailsTo(line)
        if type(to) == "string" then
            for _, recipient in ipairs(recipients) do
                if not UI.mailOnRows[recipient.to] and ns.Errands.SameName(recipient.to, to) then
                    UI.mailOnRows[recipient.to] = true
                    UI.fillRows[line] = recipient.to
                    break
                end
            end
        end
    end
end

--- Which groups are folded, per character: Keep starts folded, since there
--- is nothing to do there.
function UI:Folded()
    local char = ns.charDB or {}
    if type(char.folded) ~= "table" then char.folded = { keep = true } end
    return char.folded
end

-- Groups folded until the player opens them, on every character, even one
-- whose folds were saved before the group existed: false means opened.
UI.FOLDED_AT_FIRST = { wait = true }

function UI.IsFolded(folded, verdict)
    local state = folded[verdict]
    if state == nil then return UI.FOLDED_AT_FIRST[verdict] == true end
    return state == true
end

--------------------------------------------------------------------------------
-- Mouse
--------------------------------------------------------------------------------

-- The Ammo row's tooltip, one whole sentence per weapon (Logic/Ammo.lua's
-- internal words), so German can give each its own grammar.
UI.AMMO_BEST = {
    bow = L["The best ammo this vendor has for your bow at your level."],
    crossbow = L["The best ammo this vendor has for your crossbow at your level."],
    gun = L["The best ammo this vendor has for your gun at your level."],
}

function UI:Clicked(data, button)
    if data.type == "everyone" or data.type == "holder" then
        local itemID = data.item.itemID
        self.open[itemID] = not self.open[itemID] or nil
        self.openVersion = (self.openVersion or 0) + 1
        self:Refresh()
        return
    end
    if data.type == "header" then
        -- A search shows every group open, so a click would change a fold
        -- the player can't see.
        if self:BagSearch() ~= "" then return end
        local folded = self:Folded()
        local verdict = data.group.verdict
        local fold = not UI.IsFolded(folded, verdict)
        if fold then
            folded[verdict] = true
        elseif UI.FOLDED_AT_FIRST[verdict] then
            folded[verdict] = false
        else
            folded[verdict] = nil
        end
        self:Refresh(true)
        return
    end
    -- A character's jobs: right-click puts them away until it logs in again.
    if button == "RightButton" and (data.type == "job" or data.type == "jobnext")
        and type(data.job) == "table" and type(data.job.name) == "string" then
        return self:ShowJobMenu(data)
    end
    if data.type == "ammo" or data.type == "job" or data.type == "jobnext" or data.type == "questbuy"
        or data.type == "skillup"
        or data.type == "train" or data.type == "trainnext" or data.type == "trainalt" then return end
    if button == "RightButton" and data.type ~= "gold" then
        self:ShowMenu(data)
    end
end

function UI:Enter(row, data)
    -- A heading's +/- already says a click folds it, so only Wait for a
    -- better price, which needs saying why, has a hover (the owner, 2026-10-15).
    if data.type == "header" and data.group.verdict ~= "wait" then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if data.type == "everyone" or data.type == "holder" then
        return self:EnterEveryone(data)
    end
    if data.type == "header" then
        GameTooltip:AddLine(data.group.label, Theme.Unpack("accent"))
        GameTooltip:AddLine(L["These sell for a lot less than usual today. Hold on to them until the price comes back."], 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    if data.type == "ammo" then
        local offer = data.offer
        local shown = offer.ammo.index and pcall(GameTooltip.SetMerchantItem, GameTooltip, offer.ammo.index)
        if not shown then GameTooltip:AddLine(offer.ammo.name or L["Ammo"], 1, 1, 1) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Butler: Ammo"], Theme.Unpack("accent"))
        GameTooltip:AddLine(ns.Ammo.Reason(offer), 1, 1, 1, true)
        GameTooltip:AddLine(UI.AMMO_BEST[offer.weapon.word] or L["The best ammo this vendor has for you at your level."],
            Theme.Unpack("muted"))
        GameTooltip:Show()
        return
    end
    if data.type == "job" then
        local step = data.step
        local title, detail, hint = ns.Jobs.StepText(step)
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        GameTooltip:AddLine(detail, 1, 1, 1, true)
        if hint then GameTooltip:AddLine(hint, Theme.Unpack("muted")) end
        if step.kind == "craft" and not step.ready then
            GameTooltip:AddLine(L["You can craft it once you have the materials."], Theme.Unpack("muted"))
        end
        GameTooltip:Show()
        return
    end
    if data.type == "train" or data.type == "trainnext" then
        return self:EnterTraining(data)
    end
    if data.type == "trainalt" then
        local other = data.other
        GameTooltip:AddLine(other.name or "", Theme.Unpack("accent"))
        GameTooltip:AddLine(other.count == 1 and L["1 spell to train the last time they played."]
            or L.Format("%d spells to train the last time they played.", other.count), 1, 1, 1, true)
        GameTooltip:AddLine(ns.ClassTraining.CostText(other.cost, other.unknown, other.count), 1, 1, 1)
        GameTooltip:Show()
        return
    end
    if data.type == "skillup" and data.entry.capped then
        local title, detail = ns.SkillUp.Text(data.entry)
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        GameTooltip:AddLine(detail, 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    if data.type == "skillup" then
        local title, detail = ns.SkillUp.Text(data.entry)
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        local short = ns.SkillUp.ShortNote(data.entry)
        if short then
            GameTooltip:AddLine(detail, 1, 1, 1, true)
            GameTooltip:AddLine(short, Theme.Unpack("loss"))
        end
        GameTooltip:AddLine(L["This is the cheapest thing you can make for your next skill point. Tradeskills works it out from auction prices."],
            1, 1, 1, true)
        GameTooltip:AddLine(L["Queue adds one to your craft queue. Butler then lists what you still need to buy."],
            Theme.Unpack("muted"))
        GameTooltip:Show()
        return
    end
    if data.type == "questbuy" then
        local shown = pcall(GameTooltip.SetItemByID, GameTooltip, data.item.itemID)
        if not shown then GameTooltip:AddLine(ns.Jobs.ItemName(data.item.itemID), 1, 1, 1) end
        GameTooltip:Show()
        return
    end
    if data.type == "jobnext" then
        local job = data.job
        GameTooltip:AddLine(job.name, Theme.Unpack("accent"))
        for _, step in ipairs(job.steps) do
            local line = ns.Jobs.Short(step)
            GameTooltip:AddLine(line:sub(1, 1):upper() .. line:sub(2), 1, 1, 1, true)
        end
        GameTooltip:AddLine(data.isNext and L["Click Log out to switch to them."]
            or L["Do the steps above first."], Theme.Unpack("muted"))
        GameTooltip:Show()
        return
    end
    if data.type == "gold" then
        local entry = data.entry
        GameTooltip:AddLine(L.Format("Gold for %s", entry.to), Theme.Unpack("accent"))
        GameTooltip:AddLine(ns.Funds.Reason(entry), 1, 1, 1, true)
        GameTooltip:AddLine(L.Format("Fill mail sends %s. You press Send.", Items.FormatMoney(entry.amount)), 1, 1, 1, true)
        GameTooltip:AddLine(L["Their gold from the last time they played. Set the amounts on the Gold page in Settings."],
            Theme.Unpack("muted"))
        GameTooltip:Show()
        return
    end

    local slot = data.slots[1]
    local shown = slot and pcall(GameTooltip.SetBagItem, GameTooltip, slot.bag, slot.slot)
    if not shown and data.link then pcall(GameTooltip.SetHyperlink, GameTooltip, data.link) end

    GameTooltip:AddLine(" ")
    local r, g, b = Theme.Unpack("accent")
    GameTooltip:AddLine(L.Format("Butler: %s", ns.Verdicts.LABELS[data.verdict] or data.verdict), r, g, b)
    if data.reason and data.reason ~= "" then
        GameTooltip:AddLine(data.reason, 1, 1, 1, true)
    end
    if data.bought then
        GameTooltip:AddLine(L.Format("%d bought on the auction house to disenchant", data.bought), 0.73, 0.55, 1)
    end
    GameTooltip:AddLine(L["Right-click to always keep, sell or bank it"], Theme.Unpack("muted"))
    GameTooltip:Show()
end

--- An item in All characters: the item's own tooltip, then who has it.
--- The training rows' tooltip: each spell and what it costs.
function UI:EnterTraining(data)
    local training = ns.ClassTraining
    local plan = data.plan
    local list = data.type == "train" and plan.ready or plan.next
    local count = #list
    if data.type == "train" then
        GameTooltip:AddLine(count == 1 and L["Train 1 new spell"] or L.Format("Train %d new spells", count), 1, 1, 1)
        GameTooltip:AddLine(L.Format("Ready at level %d, from any %s trainer", training.Player().level,
            training.Player().className or ""), Theme.Unpack("muted"))
    else
        GameTooltip:AddLine(L.Format("At level %d", plan.nextLevel), 1, 1, 1)
    end
    for _, spell in ipairs(list) do
        GameTooltip:AddDoubleLine(training.Label(spell.entry),
            spell.cost and Items.FormatMoney(spell.cost) or L["not priced yet"], 1, 1, 1, 1, 1, 1)
    end
    local cost, unknown, guessed = training.Sum(list)
    GameTooltip:AddDoubleLine(L["In all"], training.CostText(cost, unknown, count), 1, 0.82, 0, 1, 1, 1)
    if unknown > 0 or guessed > 0 then
        GameTooltip:AddLine(L["Prices may change once you visit your trainer."],
            Theme.Muted(true))
    end
    if data.type == "train" then
        local ok, money = pcall(GetMoney)
        local purse = ok and tonumber(money) or 0
        if cost > 0 and purse >= cost then
            GameTooltip:AddLine(L["You have enough gold for them."], 0.31, 0.88, 0.42, true)
        elseif cost > 0 then
            GameTooltip:AddLine(L.Format("You're %s short.", Items.FormatMoney(cost - purse)), 1, 0.72, 0.29, true)
        end
        if training.trainerOpen and training.atClassTrainer then
            GameTooltip:AddLine(L["Train all trains as many as you can pay for."], Theme.Unpack("muted"))
        elseif training:Nearest() then
            GameTooltip:AddLine(L["Show the way points an arrow to your trainer."], Theme.Unpack("muted"))
        end
    end
    GameTooltip:Show()
end

function UI:EnterEveryone(data)
    local item = data.item
    -- Butler lists who has it below, so the who-has-it lines stay off
    -- this one tooltip (they said it all twice).
    if ns.WhoHas then ns.WhoHas.quiet = true end
    pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. item.itemID)
    if ns.WhoHas then ns.WhoHas.quiet = nil end
    GameTooltip:AddLine(" ")
    local r, g, b = Theme.Unpack("accent")
    GameTooltip:AddLine(L.Format("Butler: %d on %s", item.total,
        Plural(#item.holders, L["character"], L["characters"])), r, g, b)
    for _, holder in ipairs(item.holders) do
        GameTooltip:AddDoubleLine(holder.character.short, ns.Everyone.Where(holder), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine(data.type == "holder" and L["Click to close"]
        or (data.open and L["Click to close"] or L["Click to see each character"]), Theme.Unpack("muted"))
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- The right-click menu
--
-- A small window of Butler's own, never the game's dropdown menus: Always
-- Keep, Always Sell, Always Bank, Always Disenchant (green or better),
-- Always Mail To (which turns the menu into a list of the player's
-- characters), and Let Butler Decide once one is picked. A thin gold rim
-- round dark glass rows, the pick it holds now marked with a gold edge.
--------------------------------------------------------------------------------

local MENU_WIDTH = 170
local MENU_ROW = 24

--- One line of the menu: a dark glass row with its words on the left, lit
--- gold under the mouse, as the house lists are (UI audit, the owner said
--- yes 2026-10-27). Answers SetText and grows to fit its words, as a
--- button does; UI.FitMenu shades the rows by place.
function UI.MenuRow(parent, text, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(MENU_WIDTH - 16, MENU_ROW)
    row.fill = Theme.Fill(row, "glass")
    local line = row:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(Theme.Unpack("border", 0.6))
    Widgets.RowLight(row)
    -- The pick it holds now: a gold edge that stays.
    row.mark = row:CreateTexture(nil, "OVERLAY")
    row.mark:SetPoint("TOPLEFT")
    row.mark:SetPoint("BOTTOMLEFT")
    row.mark:SetWidth(2)
    row.mark:SetColorTexture(Theme.Unpack("accentHi"))
    row.mark:Hide()
    row.active = false

    row.label = Theme.CreateLabel(row, "small", "text")
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetPoint("RIGHT", -8, 0)

    function row:SetText(value)
        self.label:SetText(value)
        self:SetWidth(math.max(MENU_WIDTH - 16, Theme.TextWidth("small", value) + 20))
    end
    function row:GetText() return self.label:GetText() end
    function row:SetActive(on)
        self.active = on and true or false
        self.mark:SetShown(self.active)
    end
    row:SetText(text)

    row:SetScript("OnEnter", function(self) Widgets.SetRowLight(self, 1) end)
    row:SetScript("OnLeave", function(self) Widgets.SetRowLight(self, 0) end)
    row:SetScript("OnClick", onClick)
    return row
end

function UI:BuildMenu()
    if self.menu then return self.menu end

    local menu = CreateFrame("Frame", "BlackthornesButlerMenu", UIParent)
    menu:SetSize(MENU_WIDTH, 112)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    -- Over the Sell button, which shares this layer.
    menu:SetFrameLevel(50)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    -- A thin gold rim round dark glass, the house menu (UI audit #8).
    Theme.Fill(menu, "well")
    Theme.Border(menu, "accent")
    local inner = CreateFrame("Frame", nil, menu)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    Theme.Border(inner, "metal", 0.8)

    menu.title = Theme.CreateLabel(menu, "small", "accent")
    menu.title:SetPoint("TOPLEFT", 8, -8)
    menu.title:SetPoint("TOPRIGHT", -8, -8)
    -- A fine gold line under the item's name.
    menu.rule = menu:CreateTexture(nil, "BORDER")
    menu.rule:SetPoint("TOPLEFT", 6, -24)
    menu.rule:SetPoint("TOPRIGHT", -6, -24)
    menu.rule:SetHeight(1)
    menu.rule:SetColorTexture(Theme.Unpack("metal", 0.9))

    local function Pick(choice, to)
        local data = UI.menu.data
        UI:HideMenu()
        if data then ns.Verdicts:SetChoice(data.itemID, choice, to) end
    end
    menu.Pick = Pick

    menu.keep = UI.MenuRow(menu, L["Always Keep"], function() Pick("keep") end)
    menu.keep:SetPoint("TOPLEFT", 8, -26)
    menu.sell = UI.MenuRow(menu, L["Always Sell"], function() Pick("sell") end)
    menu.sell:SetPoint("TOPLEFT", menu.keep, "BOTTOMLEFT", 0, 0)
    menu.bank = UI.MenuRow(menu, L["Always Bank"], function() Pick("bank") end)
    menu.bank:SetPoint("TOPLEFT", menu.sell, "BOTTOMLEFT", 0, 0)
    -- Greens and better that sell for more go to auction; this breaks
    -- them anyway (the owner, 2026-10-17).
    menu.disenchant = UI.MenuRow(menu, L["Always Disenchant"], function() Pick("disenchant") end)
    -- Bought to disenchant: Tradeskills keeps the mark, for the whole account.
    menu.bought = UI.MenuRow(menu, L["Bought to disenchant"], function()
        local data = UI.menu.data
        UI:HideMenu()
        if not data then return end
        local done, why = ns.Sisters:MarkBought(data.itemID, not data.bought, data.count)
        if not done then
            if why then ns.Print(why) end
            return
        end
        ns.Verdicts:Changed(true)
    end)
    menu.bought:SetPoint("TOPLEFT", menu.bank, "BOTTOMLEFT", 0, 0)
    menu.mail = UI.MenuRow(menu, L["Always Mail To..."], function() UI:ShowMailMenu() end)
    menu.mail:SetPoint("TOPLEFT", menu.bank, "BOTTOMLEFT", 0, 0)
    menu.decide = UI.MenuRow(menu, L["Let Butler Decide"], function() Pick(nil) end)
    -- Keep a number on this character (Logic/KeepHere.lua, a player asked,
    -- the owner said build it 2026-10-17): its own page with a box.
    menu.keepHere = UI.MenuRow(menu, L["Keep on This Character..."], function() UI:ShowKeepMenu() end)
    local function SaveKeep()
        local data = UI.menu.data
        local count = tonumber(menu.keepBox.editBox:GetText()) or 0
        UI:HideMenu()
        if not data then return end
        local done, why = ns.KeepHere:Set(data.itemID, count)
        if not done and why then ns.Print(why) end
        if ns.SettingsUI and ns.SettingsUI.SyncKeepHere then ns.SettingsUI:SyncKeepHere() end
    end
    menu.keepBox = Widgets.CreateSearchBox(menu, "0", nil, SaveKeep, { plain = true })
    menu.keepBox:SetSize(MENU_WIDTH - 16, 24)
    local keepEdit = menu.keepBox.editBox
    keepEdit:SetMaxLetters(4)
    if keepEdit.SetNumeric then keepEdit:SetNumeric(true) end
    menu.keepNote = Theme.CreateLabel(menu, "small", "muted")
    menu.keepNote:SetWordWrap(true)
    menu.keepSave = Widgets.CreateButton(menu, L["Save"], SaveKeep,
        { width = math.floor((MENU_WIDTH - 20) / 2), height = 20, primary = true })
    -- Keep All (asked the same day): every one stays, nothing to type.
    menu.keepAll = Widgets.CreateButton(menu, L["Keep All"], function()
        local data = UI.menu.data
        UI:HideMenu()
        if not data then return end
        local done, why = ns.KeepHere:Set(data.itemID, ns.KeepHere.MOST)
        if not done and why then ns.Print(why) end
        if ns.SettingsUI and ns.SettingsUI.SyncKeepHere then ns.SettingsUI:SyncKeepHere() end
    end, { width = math.floor((MENU_WIDTH - 20) / 2), height = 20 })
    -- An alt's upgrade under Mail: hold this one back from them, or every
    -- upgrade (the owner asked 2026-10-12). Undone in Settings.
    menu.hold = UI.MenuRow(menu, L["Don't mail this"], function()
        local data = UI.menu.data
        UI:HideMenu()
        if data and data.mailTo then ns.Verdicts:HoldUpgrade(data.itemID, data.mailTo, true) end
    end)
    menu.holdAll = UI.MenuRow(menu, L["Never mail upgrades"], function()
        local data = UI.menu.data
        UI:HideMenu()
        if data and data.mailTo then ns.Verdicts:HoldAllUpgrades(data.mailTo, true) end
    end)

    -- A Craft row: stop suggesting that recipe (the owner, 2026-10-26).
    -- Brought back on the Selling page of Settings.
    menu.skipCraft = UI.MenuRow(menu, L["Don't Suggest This Craft"], function()
        local data = UI.menu.data
        UI:HideMenu()
        if data and type(data.craft) == "table" then
            ns.Verdicts:SkipCraft(data.craft.recipeID, data.craft.name)
            if ns.SettingsUI and ns.SettingsUI.SyncCraftSkip then ns.SettingsUI:SyncCraftSkip() end
        end
    end)
    menu.skipCraft:Hide()

    -- The characters page: one button a character, made as needed, and Back.
    -- A character's jobs line: put away until that character logs in.
    menu.ignoreJobs = UI.MenuRow(menu, L["Ignore Until Next Login"], function()
        local data = UI.menu.data
        UI:HideMenu()
        if data and data.job and ns.Jobs then ns.Jobs:Ignore(data.job.name) end
    end)
    menu.ignoreJobs:Hide()

    menu.characters = {}
    menu.back = UI.MenuRow(menu, L["Back"], function()
        if UI.menu.data then UI:ShowMenu(UI.menu.data, true) end
    end)

    -- Gone once the mouse has been off it for a moment, as the game's menus
    -- go. Only runs while the menu is up.
    menu:SetScript("OnUpdate", function(frame, elapsed)
        local ok, over = pcall(frame.IsMouseOver, frame)
        -- Never while the player types a number in it.
        local typing = frame.keepBox and frame.keepBox:IsShown() and frame.keepBox.editBox.HasFocus
            and frame.keepBox.editBox:HasFocus()
        frame.away = ((ok and over) or typing) and 0 or (frame.away or 0) + (elapsed or 0)
        if frame.away > 1.5 then UI:HideMenu() end
    end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesButlerMenu")
    end

    menu:Hide()
    self.menu = menu
    return menu
end

--- A row's item name in its rarity colour, for the menu's title.
function UI.ItemTitle(data)
    if type(data.name) ~= "string" then return data.name end
    return Items:ColorName(data.name, data.itemID, data.quality)
end

--- Show the menu's main page for `data` (a row). `stay` keeps it where it
--- is, coming back from the characters page.
function UI:ShowMenu(data, stay)
    local menu = self:BuildMenu()
    menu.data = data
    menu.away = 0
    menu.title:SetText(UI.ItemTitle(data))

    for _, button in ipairs(menu.characters) do button:Hide() end
    menu.back:Hide()
    menu.ignoreJobs:Hide()
    menu.keepBox:Hide()
    menu.keepNote:Hide()
    menu.keepSave:Hide()
    menu.keepAll:Hide()

    local choice, mailTo = ns.Verdicts:Choice(data.itemID)
    menu.keep:SetText(choice == "keep" and L["Always Keep (now)"] or L["Always Keep"])
    menu.sell:SetText(choice == "sell" and L["Always Sell (now)"] or L["Always Sell"])
    menu.bank:SetText(choice == "bank" and L["Always Bank (now)"] or L["Always Bank"])
    menu.mail:SetText(choice == "mail" and L.Format("Always Mail To %s", mailTo) or L["Always Mail To..."])
    menu.keep:SetActive(choice == "keep")
    menu.sell:SetActive(choice == "sell")
    menu.bank:SetActive(choice == "bank")
    menu.mail:SetActive(choice == "mail")
    menu.disenchant:SetActive(choice == "disenchant")
    menu.bought:SetActive(data.bought)
    menu.keep:Show()
    menu.sell:Show()
    menu.bank:Show()

    -- Only gear worth breaking: green or better.
    local canBreak = choice == "disenchant" or (data.quality or 0) >= 2
    menu.disenchant:SetShown(canBreak)
    menu.disenchant:SetText(choice == "disenchant" and L["Always Disenchant (now)"] or L["Always Disenchant"])
    menu.disenchant:ClearAllPoints()
    menu.disenchant:SetPoint("TOPLEFT", menu.bank, "BOTTOMLEFT", 0, 0)
    local above = canBreak and menu.disenchant or menu.bank

    -- Mail needs Tradeskills to know the player's characters, and gear
    -- bound to this one can't be mailed at all.
    local canMail = choice == "mail" or (not data.bound and #ns.Errands:MailNames() > 0)
    menu.mail:SetShown(canMail)

    -- Marked or unmarked through Tradeskills, so only with it loaded.
    local canMark = ns.Sisters.CanMarkBought()
    menu.bought:SetShown(canMark)
    menu.bought:SetText(data.bought and L["Bought to disenchant (now)"] or L["Bought to disenchant"])
    menu.bought:ClearAllPoints()
    menu.bought:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)
    menu.mail:ClearAllPoints()
    menu.mail:SetPoint("TOPLEFT", canMark and menu.bought or above, "BOTTOMLEFT", 0, 0)

    local last = canMail and menu.mail or (canMark and menu.bought or above)
    local upgradeTo = data.upgrade and type(data.mailTo) == "string" and data.mailTo or nil
    menu.hold:SetShown(upgradeTo ~= nil)
    menu.holdAll:SetShown(upgradeTo ~= nil)
    if upgradeTo then
        menu.hold:SetText(L.Format("Don't mail this to %s", upgradeTo))
        menu.holdAll:SetText(L.Format("Never mail upgrades to %s", upgradeTo))
        menu.hold:ClearAllPoints()
        menu.hold:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 0)
        menu.holdAll:ClearAllPoints()
        menu.holdAll:SetPoint("TOPLEFT", menu.hold, "BOTTOMLEFT", 0, 0)
        last = menu.holdAll
    end
    local craft = data.verdict == "craft" and type(data.craft) == "table" and data.craft.recipeID and data.craft or nil
    menu.skipCraft:SetShown(craft ~= nil)
    if craft then
        menu.skipCraft:ClearAllPoints()
        menu.skipCraft:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 0)
        last = menu.skipCraft
    end
    -- Keep on this character: the number kept, when there is one.
    local keepCount = ns.KeepHere and ns.KeepHere:Count(data.itemID)
    menu.keepHere:SetShown(ns.KeepHere ~= nil)
    menu.keepHere:SetText(keepCount and (ns.KeepHere.IsAll(keepCount) and L["Keep on This Character: All"]
        or L.Format("Keep on This Character: %d", keepCount)) or L["Keep on This Character..."])
    menu.keepHere:ClearAllPoints()
    menu.keepHere:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 0)
    if ns.KeepHere then last = menu.keepHere end
    menu.decide:ClearAllPoints()
    menu.decide:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 0)
    -- Also there for what Butler learned from the player (a buyback, a
    -- habit), which it forgets.
    local learned = choice == nil and ns.Learning and ns.Learning:Get(data.itemID) or nil
    local decides = choice ~= nil or learned ~= nil
    menu.decide:SetShown(decides)
    menu.decide:SetText(learned and L["Forget what Butler learned"] or L["Let Butler Decide"])

    local rows = 3 + (canBreak and 1 or 0) + (canMark and 1 or 0) + (canMail and 1 or 0) + (upgradeTo and 2 or 0)
        + (craft and 1 or 0) + (ns.KeepHere and 1 or 0) + (decides and 1 or 0)
    menu:SetHeight(30 + rows * MENU_ROW)
    UI.FitMenu(menu, { menu.keep, menu.sell, menu.bank, menu.disenchant, menu.bought, menu.mail,
        menu.hold, menu.holdAll, menu.skipCraft, menu.keepHere, menu.decide })

    if stay and menu:IsShown() then return end
    local x, y = 0, 0
    if type(GetCursorPosition) == "function" then
        x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        x, y = x / scale, y / scale
    end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - 10, y + 10)
    menu:Show()
end

--- The menu for a character's jobs line: its name, and one choice.
function UI:ShowJobMenu(data)
    local menu = self:BuildMenu()
    menu.data = data
    menu.away = 0
    menu.title:SetText(data.job.name)
    for _, button in ipairs({ menu.keep, menu.sell, menu.bank, menu.disenchant, menu.bought, menu.mail,
        menu.hold, menu.holdAll, menu.skipCraft, menu.keepHere, menu.decide, menu.back, menu.keepSave,
        menu.keepAll }) do
        button:Hide()
    end
    for _, button in ipairs(menu.characters) do button:Hide() end
    menu.keepBox:Hide()
    menu.keepNote:Hide()

    menu.ignoreJobs:ClearAllPoints()
    menu.ignoreJobs:SetPoint("TOPLEFT", 8, -26)
    menu.ignoreJobs:Show()
    menu:SetHeight(30 + MENU_ROW)
    UI.FitMenu(menu, { menu.ignoreJobs })

    local x, y = 0, 0
    if type(GetCursorPosition) == "function" then
        x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        x, y = x / scale, y / scale
    end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x - 10, y + 10)
    menu:Show()
end

--- The menu as wide as its widest button or title, so a long name (never
--- shortened) stays inside it; every shown button takes that width.
function UI.FitMenu(menu, buttons)
    local width = MENU_WIDTH - 16
    local title = menu.title and menu.title:GetText()
    if type(title) == "string" then width = math.max(width, Theme.TextWidth("small", title) or 0) end
    for _, button in ipairs(buttons) do
        if button:IsShown() then width = math.max(width, button:GetWidth() or 0) end
    end
    local place = 0
    for _, button in ipairs(buttons) do
        if button:IsShown() then
            button:SetWidth(width)
            place = place + 1
            if button.fill then
                button.fill:SetColorTexture(Theme.Unpack(button.active and "glassActive"
                    or (place % 2 == 1 and "glass" or "glassAlt")))
            end
        end
    end
    menu:SetWidth(width + 16)
end

--- The characters page: pick who this item always goes to.
function UI:ShowMailMenu()
    local menu = self.menu
    local data = menu and menu.data
    if not data then return end
    menu.away = 0

    local choice, mailTo = ns.Verdicts:Choice(data.itemID)
    local names = ns.Errands:MailNames()
    menu.title:SetText(L.Format("Always mail %s to", UI.ItemTitle(data)))

    menu.keep:Hide()
    menu.sell:Hide()
    menu.bank:Hide()
    menu.mail:Hide()
    menu.bought:Hide()
    menu.hold:Hide()
    menu.holdAll:Hide()
    menu.skipCraft:Hide()
    menu.decide:Hide()
    menu.keepHere:Hide()
    menu.disenchant:Hide()
    menu.ignoreJobs:Hide()

    local above
    for index, name in ipairs(names) do
        local button = menu.characters[index]
        if not button then
            button = UI.MenuRow(menu, name, function(self)
                menu.Pick("mail", self.character)
            end)
            menu.characters[index] = button
        end
        button.character = name
        button:SetActive(choice == "mail" and mailTo == name)
        button:SetText(choice == "mail" and mailTo == name and L.Format("%s (now)", name) or name)
        button:ClearAllPoints()
        if above then
            button:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)
        else
            button:SetPoint("TOPLEFT", 8, -26)
        end
        button:Show()
        above = button
    end
    for index = #names + 1, #menu.characters do menu.characters[index]:Hide() end

    menu.back:ClearAllPoints()
    if above then
        menu.back:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)
    else
        menu.back:SetPoint("TOPLEFT", 8, -26)
    end
    menu.back:Show()
    menu:SetHeight(30 + (#names + 1) * MENU_ROW)
    local buttons = {}
    for index = 1, #names do buttons[#buttons + 1] = menu.characters[index] end
    buttons[#buttons + 1] = menu.back
    UI.FitMenu(menu, buttons)
end

--- The menu's keep page: how many to keep on this character, typed in a
--- box. 0 takes it off the list.
function UI:ShowKeepMenu()
    local menu = self.menu
    local data = menu and menu.data
    if not data or not ns.KeepHere then return end
    menu.away = 0
    menu.title:SetText(L.Format("Keep %s on this character", UI.ItemTitle(data)))
    for _, button in ipairs({ menu.keep, menu.sell, menu.bank, menu.disenchant, menu.bought, menu.mail,
        menu.hold, menu.holdAll, menu.skipCraft, menu.keepHere, menu.decide, menu.ignoreJobs }) do
        button:Hide()
    end
    for _, button in ipairs(menu.characters) do button:Hide() end

    local count = ns.KeepHere:Count(data.itemID)
    menu.keepBox:ClearAllPoints()
    menu.keepBox:SetPoint("TOPLEFT", 8, -26)
    menu.keepBox:SetText(count and not ns.KeepHere.IsAll(count) and tostring(count) or "")
    menu.keepBox:Show()
    menu.keepNote:ClearAllPoints()
    menu.keepNote:SetPoint("TOPLEFT", menu.keepBox, "BOTTOMLEFT", 0, -4)
    menu.keepNote:SetPoint("RIGHT", menu, "RIGHT", -8, 0)
    menu.keepNote:SetText(ns.KeepHere.IsAll(count)
        and L["Keeping all of them now. Type a number to keep fewer, or 0 to clear it."]
        or L["Anything past this number goes on down Butler's rules. 0 clears it."])
    menu.keepNote:Show()
    menu.keepSave:ClearAllPoints()
    menu.keepSave:SetPoint("TOPLEFT", menu.keepNote, "BOTTOMLEFT", 0, -6)
    menu.keepSave:Show()
    menu.keepAll:ClearAllPoints()
    menu.keepAll:SetPoint("LEFT", menu.keepSave, "RIGHT", 4, 0)
    menu.keepAll:Show()
    menu.back:ClearAllPoints()
    menu.back:SetPoint("TOPLEFT", menu.keepSave, "BOTTOMLEFT", 0, -6)
    menu.back:Show()
    UI.FitMenu(menu, { menu.back })
    -- Save and Keep All share the row, whatever width the menu took.
    local inner = (tonumber((menu:GetWidth())) or MENU_WIDTH) - 16
    local need = math.max(Theme.TextWidth("small", L["Save"]) or 0, Theme.TextWidth("small", L["Keep All"]) or 0) + 24
    if inner < 2 * need + 4 then
        inner = 2 * need + 4
        menu:SetWidth(inner + 16)
        menu.back:SetWidth(inner)
    end
    menu.keepBox:SetWidth(inner)
    menu.keepSave:SetWidth(math.floor((inner - 4) / 2))
    menu.keepAll:SetWidth(math.floor((inner - 4) / 2))
    local noteHeight = menu.keepNote.GetStringHeight and tonumber((menu.keepNote:GetStringHeight())) or 0
    menu:SetHeight(30 + 28 + math.max(noteHeight, 28) + 10 + 2 * MENU_ROW)
    if menu.keepBox.editBox.SetFocus then menu.keepBox.editBox:SetFocus() end
end

function UI:HideMenu()
    if self.menu then
        self.menu.data = nil
        self.menu:Hide()
    end
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Bring the window up to date. The list is set again only when the bags,
--- a verdict or a fold changed (`force` for a fold).
function UI:Refresh(force)
    if not self:IsShown() then return end
    if self.view == "all" then return self:RefreshAll(force) end

    if ns.Ammo then ns.Ammo:Offer() end
    if ns.Jobs and ns.Jobs.VendorOffer then ns.Jobs:VendorOffer() end
    local search = self:BagSearch()
    local key = ("%d:%d:%s:%d:%d:%d:%d:%d:%s:%s:%s:%s:%s"):format(ns.QuestBuy and ns.QuestBuy.version or 0,
        ns.Quests and ns.Quests.version or 0,
        tostring(ns.Quests and ns.Quests.auctionOpen), ns.ClassTraining and ns.ClassTraining.version or 0,
        ns.Bags.version, ns.Verdicts.version,
        ns.Funds and ns.Funds.version or 0, ns.Jobs and ns.Jobs.version or 0, tostring(ns.Errands.mailOpen),
        tostring(ns.Selling and ns.Selling.merchantOpen), tostring(ns.Ammo and ns.Ammo.offerKey),
        ns.Jobs and ns.Jobs.vendorKey or "", search)
    if force or key ~= self.drawnKey then
        -- The same search keeps its place; a new one starts at the top.
        local keep = self.drawnKey ~= nil and search == self.drawnBagSearch
        self.drawnKey, self.drawnBagSearch = key, search
        self.list:SetData(self:Lines(), keep)
        -- The jobs may have moved: the footer's words with them.
        if ns.Jobs then self:FootRoom() end
    end

    local total = 0
    for _, entry in pairs(ns.Bags.slots) do total = total + 1 end
    self.subtitle:SetText(total > 0 and L.Format("Your bags: %s", Plural(total, L["stack"], L["stacks"])) or L["Your bags"])

    if total == 0 and (ns.Bags.scanning or ns.Bags.stale) then
        self.emptyLabel:SetText(L["Reading your bags..."])
    elseif total == 0 then
        self.emptyLabel:SetText(L["Your bags are empty."])
    elseif search ~= "" and (self.matched or 0) == 0 then
        self.emptyLabel:Set(L.Format('Nothing matches "%s".', self.bagSearch:GetText()), L["Clear Search"],
            function() UI:ClearSearch(UI.bagSearch) end)
    else
        self.emptyLabel:SetText("")
    end
    self.emptyLabel:SetShown(self.emptyLabel:GetText() ~= "")

    self:PlaceGoals()
    if ns.Errands.mailOpen or ns.Errands.bankOpen then
        self:UpdateErrands()
    else
        self:UpdateFooter()
    end
end

--- The gold goals under the list: the window grows by their height, so
--- the list keeps its own, and its top stays where it is.
function UI:PlaceGoals()
    local goalsUI = ns.GoldGoalsUI
    if not (goalsUI and goalsUI.panel) then return end
    local ok, height = pcall(goalsUI.Draw, goalsUI, self.view)
    height = ok and height or 0
    if not ok then
        goalsUI.panel:Hide()
        ns.Debug("gold goals:", tostring(height))
    end
    local extra = height > 0 and height + 6 or 0
    if extra == self.goalsExtra then return end
    self.goalsExtra = extra
    self.well:SetPoint("BOTTOMRIGHT", -PADDING, FOOT + extra)
    local frame = self.frame
    local left, top = frame:GetLeft(), frame:GetTop()
    if ns.ButlerTabs then
        -- Every tab is one size, so the Settings tab grows with it.
        ns.ButlerTabs:Need("bags", nil, HEIGHT + extra)
    else
        frame:SetHeight(HEIGHT + extra)
    end
    -- Laid in the one window, it fills that window's area and keeps no
    -- place of its own.
    local hosted = ns.ButlerTabs and ns.ButlerTabs.area
        and frame:GetParent() == ns.ButlerTabs.area
    if left and top and frame:IsShown() and not hosted then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        self:SavePosition()
    end
    if ns.Selling then ns.Selling:Update() end
end

function UI:GoldGoalsChanged()
    if self:IsShown() then self:Refresh(true) end
end

--- All characters: built again when the bags moved (once Butler's own read
--- of them is done), set again when the list, the search or an opened item
--- changed.
function UI:RefreshAll(force)
    local everyone = ns.Everyone
    if not ns.Bags.scanning and (everyone.building or everyone:IsStale()) then
        everyone:Fresh(function() UI:Refresh() end)
    end

    local search = self.search:GetText() or ""
    local key = ("all:%d:%s:%d"):format(everyone.version, search, self.openVersion or 0)
    if force or key ~= self.drawnKey then
        -- The same search keeps its place; a new one starts at the top.
        local keep = self.drawnKey ~= nil and search == self.drawnSearch
        self.drawnKey, self.drawnSearch = key, search
        local lines, shown = everyone:Lines(search, self.open)
        self.shownItems = shown
        self.list:SetData(lines, keep)
    end

    local text = ""
    if #everyone.sorted == 0 and (everyone.building or ns.Bags.scanning or everyone:IsStale()) then
        text = L["Reading every character's items..."]
    elseif #everyone.sorted == 0 then
        text = everyone:FromTradeskills() and L["No items seen yet."]
            or L["Your bags are empty. Blackthornes Tradeskills remembers your other characters' items."]
    elseif (self.shownItems or 0) == 0 then
        text = L.Format('Nothing matches "%s".', search)
    end
    if text ~= "" and (self.shownItems or 0) == 0 and #everyone.sorted > 0 then
        self.emptyLabel:Set(text, L["Clear Search"], function() UI:ClearSearch(UI.search) end)
    else
        self.emptyLabel:SetText(text)
    end
    self.emptyLabel:SetShown(text ~= "")

    self:PlaceGoals()
    self:UpdateFooter()
end

function UI:UpdateFooter()
    if self.view == "all" then
        local everyone = ns.Everyone
        local text
        if not everyone:FromTradeskills() then
            text = L["Only your bags. Load Blackthornes Tradeskills to add your other characters."]
        else
            text = L.Format("%s on %s.",
                Plural(#everyone.sorted, L["item"], L["items"]),
                Plural(everyone:Holders(), L["character"], L["characters"]))
        end
        self.footer:SetText(text)
        return
    end
    local sell = ns.Verdicts:Group("sell")
    local text = ""
    if self.errandText then
        text = self.errandText
    elseif ns.Jobs and ns.Jobs:DoneHere() then
        text = L["Everything here is done."]
    elseif self.sellShown then
        text = L["Sold items stay in the vendor's Buyback tab."]
    elseif sell and sell.count > 0 then
        text = L.Format("To sell: %s, %s.",
            Plural(sell.count, L["item"], L["items"]), Items.FormatMoney(sell.worth))
    else
        text = L["Nothing to sell."]
    end
    self.footer:SetText(text)
end

--------------------------------------------------------------------------------
-- Buttons on their lines
--------------------------------------------------------------------------------

-- The owner asked (2026-10-12) for each button to sit by the line it acts
-- on: Sell on the Sell group's line, Disenchant on Disenchant's, Move to
-- bank on Bank's, Take from bank on Jobs', as Log out sits on the next
-- character's line and Fill mail on each character's. A button whose line
-- is scrolled out of sight waits at the window's foot.

-- How far in from a line's right edge its button ends: past the column
-- that shows the group's worth, so that stays in sight.
UI.LINE_BUTTON_RIGHT = 110

--- The group's heading line, while it is on screen, or nil.
function UI:HeaderRow(verdict)
    if not (self.list and self:IsShown() and self.view ~= "all") then return nil end
    for _, row in ipairs(self.list.rows) do
        local data = row.data
        if row:IsShown() and data and data.type == "header" and data.group
            and data.group.verdict == verdict then
            return row
        end
    end
    return nil
end

--- Put a secure button on a line, inside the window (UI:Dock). True when
--- placed.
function UI.PlaceOnLine(button, row)
    if not (row and row:IsShown()) or not UI:Dock(button) then return false end
    button:ClearAllPoints()
    button:SetPoint("RIGHT", row, "RIGHT", -UI.LINE_BUTTON_RIGHT, 0)
    return true
end

--- The secure buttons (Sell, Disenchant, Log out, Leave form) live inside
--- the window out of combat. The game brings a window to the front when it
--- shows or is clicked and draws it over every frame outside it in its
--- layer, whatever their level: a button kept outside the window sat
--- under it and could not be seen (2026-10-15), and a button in a layer of
--- its own showed through every window in front (2026-10-14). Inside, a
--- button comes to the front with the window and another window in front
--- covers it, as it covers the window.
---
--- A fight locks secure buttons, and a window holding one could not be
--- moved or closed then. So just before it starts (PLAYER_REGEN_DISABLED,
--- UI:Undock) each one is hidden and handed back to UIParent, and the next
--- look after the fight puts it back.
UI.docked = setmetatable({}, { __mode = "k" })

--- In a fight, when secure buttons are locked, or one is starting.
function UI.InFight()
    if UI.fighting then return true end
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

--- Put one secure button inside the window, above everything drawn there.
--- Never in a fight. True when it is in.
function UI:Dock(button)
    local frame = self.frame
    if not (button and frame) or UI.InFight() then return false end
    -- Folded to its plate, the window has no room for one.
    if ns.FoldWindow and ns.FoldWindow:IsFolded(frame) then return false end
    UI.docked[button] = true
    if button:GetParent() ~= frame then button:SetParent(frame) end
    -- Its parent's size, so its own units are the window's.
    button:SetScale(1)
    button:SetFrameStrata(frame:GetFrameStrata() or "DIALOG")
    local target = self:InnerTop() + 2
    if button:GetFrameLevel() ~= target then button:SetFrameLevel(target) end
    return true
end

--- Every secure button hidden and handed back to UIParent, so the window
--- stays free to move and close in a fight.
function UI:Undock()
    for button in pairs(UI.docked) do
        button:Hide()
        button:ClearAllPoints()
        button:SetParent(UIParent)
    end
end

--- Where a frame stands in its layer: its level, and how far the game
--- brought it to the front, where the client says. For the probe.
function UI.Standing(frame)
    local level = frame:GetFrameLevel() or 1
    local raised
    if type(frame.GetRaisedFrameLevel) == "function" then
        local ok, value = pcall(frame.GetRaisedFrameLevel, frame)
        if ok and type(value) == "number" then raised = value end
    end
    return raised and (level .. ":" .. raised) or tostring(level)
end

--- The highest frame level inside the window, the secure buttons left out,
--- kept until the window's own level or its row count moves (rows are only
--- added, never taken away).
function UI:InnerTop()
    local frame = self.frame
    local level = frame:GetFrameLevel() or 1
    local rows = self.list and self.list.rows and #self.list.rows or 0
    if self.innerTop and self.innerTopAt == level and self.innerTopRows == rows then
        return self.innerTop
    end
    local top = level
    local function Walk(parent, depth)
        if depth > 12 or type(parent.GetChildren) ~= "function" then return end
        for _, child in ipairs({ parent:GetChildren() }) do
            if not UI.docked[child] then
                local ok, at = pcall(child.GetFrameLevel, child)
                if ok and type(at) == "number" and at > top then top = at end
                Walk(child, depth + 1)
            end
        end
    end
    Walk(frame, 1)
    self.innerTop, self.innerTopAt, self.innerTopRows = top, level, rows
    return top
end

function UI:OnEnable()
    -- Fires just before a fight locks secure buttons, while they can still
    -- be hidden and moved. Other handlers of the same event may run after
    -- this one, so nothing docks a button again until the fight is over.
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        UI.fighting = true
        UI:Undock()
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        UI.fighting = false
        if UI.frame and UI:IsShown() then UI:PlaceButtons() end
    end)
end

--- Every button that sits on a line, placed again: after the list is drawn
--- or scrolled. Selling:Update ends in UI:FootRoom, which places the rest.
function UI:PlaceButtons()
    if ns.Selling then ns.Selling:Update() else self:FootRoom() end
end

--- The Sell button came up (`width` when it waits at the window's foot,
--- nil when it sits on the Sell line), or went.
function UI:SellShown(shown, width)
    if not self.frame then return end
    self.sellShown = shown and true or false
    self.sellRoom = shown and width or nil
    self:FootRoom()
    if self:IsShown() then self:UpdateFooter() end
end

--- The footer's words stop short of whatever buttons sit at the foot, and
--- the version label gives way to them.
function UI:FootRoom()
    self:PlaceErrands()
    local room = math.max(self.sellRoom or 0, self.errandRoom or 0)
    -- The Disenchant button goes left of those.
    local disenchant = ns.Disenchanting and ns.Disenchanting:Update(room) or 0
    if disenchant > 0 then room = room + (room > 0 and 6 or 0) + disenchant end
    -- The Log out button sits on the next character's row.
    if ns.Jobs then ns.Jobs:UpdateLogout() end
    -- Leave form sits over the first Craft button while in one.
    if ns.Jobs then ns.Jobs:UpdateLeaveForm() end
    -- Open sits over the first Craft button whose profession is closed.
    if ns.Jobs then ns.Jobs:UpdateOpenProfession() end
    self.versionLabel:SetShown(room == 0)
    self.footer:SetPoint("RIGHT", self.frame, "RIGHT", -(PADDING + (room > 0 and room + 12 or 90)), 0)
end

--- The mailbox and bank buttons, from what Errands offers now. Only on
--- Your bags.
function UI:UpdateErrands()
    if not self.frame then return end
    local offers = (self:IsShown() and self.view ~= "all") and ns.Errands:Offers() or { toBank = 0, fromBank = 0 }

    -- Fill mail sits on each character's line; the foot keeps it only for
    -- one whose lines are folded away.
    local mail
    local onRows = false
    if offers.mail then
        for _, recipient in ipairs(ns.Errands:Recipients()) do
            if UI.mailOnRows[recipient.to] then
                onRows = true
            elseif not mail and not ns.Errands.filled[recipient.to] then
                mail = recipient
            end
        end
    end
    self.mailButton:SetShown(mail ~= nil)
    self.footMail = mail and mail.to
    if mail then self.mailButton:SetText(L.Format("Fill mail to %s", mail.to)) end

    self.bankButton:SetShown(offers.toBank > 0)
    self.bankButton:SetText(L.Format("Move %d to bank", offers.toBank))
    self.takeButton:SetShown(offers.fromBank > 0)
    self.takeButton:SetText(L["Take from bank"])

    local count = (mail and 1 or 0) + (offers.toBank > 0 and 1 or 0) + (offers.fromBank > 0 and 1 or 0)
    if mail or onRows then
        self.errandText = L["Fills the Send Mail page. You press Send."]
    elseif count > 0 then
        self.errandText = L["Moves whole stacks, one at a time."]
    else
        self.errandText = nil
    end
    self:FootRoom()
    if self:IsShown() then self:UpdateFooter() end
end

--- The errand buttons on their lines: Move to bank on the Bank group's,
--- Take from bank on the Jobs line (it brings out what the craft queue
--- wants). One whose line is out of sight, and a Fill mail left at the
--- foot, line up from the window's bottom right corner; `errandRoom` is
--- how much of the foot they take.
function UI:PlaceErrands()
    local foot = {}
    local function Place(button, verdict)
        if not button:IsShown() then return end
        local row = verdict and self:HeaderRow(verdict)
        button:ClearAllPoints()
        if row then
            button:SetPoint("RIGHT", row, "RIGHT", -UI.LINE_BUTTON_RIGHT, 0)
            button:SetFrameLevel(row:GetFrameLevel() + 5)
        else
            foot[#foot + 1] = button
        end
    end
    Place(self.mailButton)
    Place(self.bankButton, "bank")
    Place(self.takeButton, "jobs")
    -- Queue sits on the Craft heading only; out of sight, it waits for it.
    local craftRow = self:HeaderRow("craft")
    self.queueButton:SetShown(craftRow ~= nil)
    if craftRow then
        self.queueButton:ClearAllPoints()
        self.queueButton:SetPoint("RIGHT", craftRow, "RIGHT", -UI.LINE_BUTTON_RIGHT, 0)
        self.queueButton:SetFrameLevel(craftRow:GetFrameLevel() + 5)
    end
    local room = 0
    for index, button in ipairs(foot) do
        if index == 1 then
            button:SetPoint("BOTTOMRIGHT", -UI.SELL_INSET_X, UI.SELL_INSET_Y)
        else
            button:SetPoint("RIGHT", foot[index - 1], "LEFT", -6, 0)
            room = room + 6
        end
        -- A button grows to fit a long label, so measure what is shown.
        room = room + (button:GetWidth() or ERRAND_WIDTH)
    end
    self.errandRoom = room > 0 and room or nil
end

--- The Queue button: each Craft row's craft goes in Tradeskills' queue, at
--- least as many as the bags make. A recipe two rows share is asked once,
--- for the most either makes.
function UI:QueueCrafts()
    local craft = ns.Verdicts:Group("craft")
    if not (craft and craft.count > 0) then return end
    local most, order = {}, {}
    for _, row in ipairs(craft.rows) do
        local info = row.craft
        if info then
            if not most[info.recipeID] then order[#order + 1] = info.recipeID end
            most[info.recipeID] = math.max(most[info.recipeID] or 0, info.crafts)
        end
    end
    local queued = {}
    for _, recipeID in ipairs(order) do
        queued[recipeID] = ns.Sisters:QueueCraft(recipeID, most[recipeID])
    end
    local count = 0
    for _, row in ipairs(craft.rows) do
        if row.craft and queued[row.craft.recipeID] then count = count + 1 end
    end
    if count == 1 then
        ns.Print(L["Added 1 craft to your Tradeskills queue."])
    elseif count > 1 then
        ns.Print(L.Format("Added %d crafts to your Tradeskills queue.", count))
    end
    ns.Verdicts:Changed(true)
end

--------------------------------------------------------------------------------
-- At a vendor
--------------------------------------------------------------------------------

-- Whether the window waits for something to sell before it comes up at a
-- vendor. The owner asked (2026-10-10) for it at every vendor "for now",
-- and may want the wait back: setting this true restores it.
UI.ONLY_WITH_SALES = false

--- A vendor opened: come up by itself when the player wants that ("Open at
--- a vendor").
function UI:AtVendor()
    if self:IsShown() or not (ns.db and ns.db.openAtVendor) then return end
    if UI.ONLY_WITH_SALES then
        local sell = ns.Verdicts:Group("sell")
        if not (sell and sell.count > 0) then return end
    end
    self:Show("bags")
    self.openedByVendor = true
end

--- A mailbox ("mail") or the bank ("bank") opened: come up on Your bags
--- when the player wants that and there is something to do there.
function UI:AtPlace(place)
    if self:IsShown() then
        -- Already up at a mailbox: Butler is the mailbox's window now, so it
        -- goes when the mailbox does (a player found it left up, 2026-10-11).
        if place == "mail" and not self.openedFor and not self.openedByVendor then
            self.openedFor = place
        end
        ns.Errands:TellTradeskills()
        return self:UpdateErrands()
    end
    local setting = place == "mail" and "openAtMailbox" or "openAtBank"
    if not (ns.db and ns.db[setting]) then return end
    -- At a mailbox Butler takes over from Tradeskills' mail panel, so it
    -- comes up every time; at the bank only with something to move.
    if place ~= "mail" and not ns.Errands:HasWork(place) then return end
    self:Show("bags")
    self.openedFor = place
    ns.Errands:TellTradeskills()
end

--- The mailbox or bank closed: a window that came up for it goes with it.
function UI:LeftPlace(place)
    if self.openedFor == place then
        self.openedFor = nil
        self.closingByItself = true
        self:Hide()
    else
        self:UpdateErrands()
    end
end

--- The vendor closed: a window that came up for it goes with it.
function UI:LeftVendor()
    if self.openedByVendor then
        self.openedByVendor = false
        self.closingByItself = true
        self:Hide()
    elseif ns.Selling then
        ns.Selling:Update()
    end
end

--------------------------------------------------------------------------------
-- Size
--------------------------------------------------------------------------------

function UI.ClampScale(value)
    value = tonumber(value)
    if not value or value ~= value then return 1 end
    value = math.max(SCALE_MIN, math.min(SCALE_MAX, value))
    return math.floor(value * 100 + 0.5) / 100
end

--- The largest size at which the whole window, portrait and corner gems
--- included, still fits on the screen.
function UI.FitScale()
    local ok, width, height = pcall(function()
        return UIParent:GetWidth(), UIParent:GetHeight()
    end)
    if not ok or type(width) ~= "number" or type(height) ~= "number"
        or width <= 0 or height <= 0 then
        return SCALE_MAX
    end
    local w, h = WIDTH, HEIGHT
    if ns.ButlerTabs then w, h = ns.ButlerTabs:Size() end
    local fit = math.min(width / (w + 40), height / (h + 60))
    return math.max(SCALE_MIN, math.min(SCALE_MAX, math.floor(fit * 100) / 100))
end

--- The size the window is drawn at: the saved one, kept on the screen.
function UI:GetWindowScale()
    return math.min(UI.ClampScale(ns.db and ns.db.windowScale or 1), UI.FitScale())
end

function UI.ScaleText(scale)
    return ("%d%%"):format(math.floor((tonumber(scale) or 1) * 100 + 0.5))
end

--- Draw the window at `scale` with its top left corner where it was, so it
--- grows and shrinks toward the bottom right, as it does from the grip.
function UI:ApplyScale(scale)
    local frame = self.frame
    if not frame then return end
    scale = math.min(UI.ClampScale(scale), UI.FitScale())
    local old = frame:GetScale()
    if type(old) ~= "number" or old <= 0 then old = 1 end
    if math.abs(old - scale) < 0.001 then return end

    if ns.Motion and ns.Motion.Stop then pcall(ns.Motion.Stop, ns.Motion, frame, "open", true) end
    local left, top = frame:GetLeft(), frame:GetTop()
    frame:SetScale(scale)
    if type(left) == "number" and type(top) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
        self:SavePosition()
        if ns.ButlerTabs then ns.ButlerTabs:Save(frame) end
    end
    if ns.Selling then ns.Selling:Update() end
end

--- Save a size and draw the window at it.
function UI:SetWindowScale(value)
    local scale = UI.ClampScale(value)
    if ns.db then ns.db.windowScale = scale end
    self:ApplyScale(scale)
end

--- The grip below the bottom right corner: drag it to make the window
--- bigger or smaller, right-click it for the normal size. Only the
--- window's scale changes while dragging; the list is not filled again.
function UI:BuildSizeGrip()
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

    -- Six gold dots in a stair down to the bottom right corner, the shape
    -- every resizable window in the game wears.
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
        for _, dot in ipairs(dots) do
            dot:SetColorTexture(Theme.Unpack(on and "accentHi" or "accent"))
        end
    end

    local function Track(self)
        local cx, cy = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        if not (cx and cy and type(uiScale) == "number" and uiScale > 0) then return end
        cx, cy = cx / uiScale, cy / uiScale

        -- The size that keeps the cursor where it took hold of the grip:
        -- the width's and the height's answers averaged, so a drag off the
        -- diagonal still feels right.
        local width = cx - self.grabX - self.anchorLeft
        local height = self.anchorTop - (cy + self.grabY)
        local scale = UI.ClampScale((width / self.baseWidth + height / self.baseHeight) / 2)
        scale = math.min(scale, self.fit)
        if math.abs(scale - (frame:GetScale() or 1)) < 0.005 then return end

        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.anchorLeft / scale, self.anchorTop / scale)

        if GameTooltip:IsOwned(self) then
            GameTooltip:SetText(UI.ScaleText(scale), Theme.Unpack("accentHi"))
            GameTooltip:Show()
        end
    end

    local function StopSizing(self)
        if not self.sizing then return end
        self.sizing = false
        self:SetScript("OnUpdate", nil)
        UI.dragging = false
        if ns.db then ns.db.windowScale = UI.ClampScale(frame:GetScale()) end
        UI:SavePosition()
        if ns.ButlerTabs then ns.ButlerTabs:Save(frame) end
        if ns.Selling then ns.Selling:Update() end
    end

    grip:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            UI:SetWindowScale(1)
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

        -- All in the screen's units, which do not change with the window's.
        self.anchorLeft, self.anchorTop = left * scale, top * scale
        -- The window's own size, which the tabs may have made bigger.
        local okW, baseWidth = pcall(frame.GetWidth, frame)
        local okH, baseHeight = pcall(frame.GetHeight, frame)
        self.baseWidth = okW and type(baseWidth) == "number" and baseWidth > 0 and baseWidth or WIDTH
        self.baseHeight = okH and type(baseHeight) == "number" and baseHeight > 0 and baseHeight or HEIGHT
        self.grabX = cx / uiScale - (self.anchorLeft + self.baseWidth * scale)
        self.grabY = (self.anchorTop - self.baseHeight * scale) - cy / uiScale
        self.fit = UI.FitScale()

        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

        -- The Sell button and the menu sit outside the window: out of the
        -- way until the drag ends, as when the window is moved.
        UI.dragging = true
        UI:HideMenu()
        if ns.Selling then ns.Selling:Update() end

        self.sizing = true
        self:SetScript("OnUpdate", Track)
    end)
    grip:SetScript("OnMouseUp", StopSizing)
    grip:SetScript("OnHide", StopSizing)

    grip:SetScript("OnEnter", function(self)
        Light(true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(UI.ScaleText(frame:GetScale()), Theme.Unpack("accentHi"))
        GameTooltip:AddLine(L["Drag to make the window bigger or smaller."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Right-click to go back to the normal size."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        Light(false)
        GameTooltip:Hide()
    end)
    return grip
end

--------------------------------------------------------------------------------
-- Position and visibility
--------------------------------------------------------------------------------

function UI:SavePosition()
    if not (ns.db and self.frame) then return end
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    ns.db.point, ns.db.relativePoint, ns.db.x, ns.db.y = point, relativePoint, x, y
end

function UI:RestorePosition()
    if not self.frame then return end
    local db = ns.db or {}
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER",
        db.x or 0, db.y or 40)
end

function UI:IsShown()
    return self.frame ~= nil and self.frame:IsShown() == true
end

--- Bring the window up, on `view` ("bags" or "all") when one is given.
function UI:Show(view)
    -- With "One Window:" ticked, the one window opens on Butler instead
    -- (UI/ButlerTabs.lua), and lays this window in.
    if ns.ButlerTabs and ns.ButlerTabs:Route(view) then return end
    self:Build()
    if view then self:SetView(view) end
    if ns.FoldWindow then ns.FoldWindow:Unfold(self.frame) end
    if not self.frame:IsShown() then
        -- Ask the other addons afresh each time the window opens: a goal
        -- met, a craft queued or a level gained since the last look.
        ns.Verdicts:Forget()
        ns.Everyone:Changed()
        if ns.Jobs then ns.Jobs:Changed() end
        if ns.GoldGoals then ns.GoldGoals:Changed() end
        -- Coming from the Settings tab it takes that tab's place; else the
        -- place every tab keeps (UI/ButlerTabs.lua).
        local how = ns.ButlerTabs and ns.ButlerTabs:Take(self)
        if not how then self:RestorePosition() end
        self.frame:Show()
        if not how and ns.ButlerTabs then ns.ButlerTabs:Settle(self.frame) end
        if how ~= "switch" then ns.Motion:Open(self.frame) end
        if ns.Errands then ns.Errands:TellTradeskills() end
        -- A light runs round the portrait as it opens.
        if ns.Titanforged and how ~= "switch" then ns.Titanforged:Opened(self.frame) end
        -- The window rises a few pixels as it opens: place the Sell button
        -- again once it has landed.
        C_Timer.After(0.25, function()
            if ns.Selling then ns.Selling:Update() end
        end)
    end
    self:Refresh()
    -- Read the bags if they changed while the window was closed; the list
    -- follows when the read is done.
    ns.Bags:Fresh(function()
        UI:Refresh()
        if ns.Selling then ns.Selling:Update() end
    end)
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

function UI:Toggle()
    -- Any tab up, Settings too, closes the whole window.
    if ns.ButlerTabs and ns.ButlerTabs:AnyShown() then
        ns.ButlerTabs:Close()
    elseif self:IsShown() then
        self:Hide()
    else
        self:Show()
        self:Say("open")
    end
end

--------------------------------------------------------------------------------
-- Butler's voice
--
-- The owner asked (2026-10-11) for Moroes, Karazhan's butler, to answer when
-- the player opens Butler ("You rang?") and closes it ("Now, where was I?
-- Oh, yes..."): the game's own files, played by ID, so no sound ships here.
-- Never over an NPC: the client can't say when one is talking, so a line is
-- never said while a vendor, mailbox, bank or any NPC window is open, nor
-- when the window opens or closes by itself. Each line waits VOICE_GAP
-- seconds before it is said again. "Butler's voice" in Settings (`voice`,
-- account wide, on unless unticked).
--------------------------------------------------------------------------------

UI.VOICE = { open = 555818, close = 555814 }
UI.VOICE_GAP = 180
UI.voiceAt = {}

--- Is the player at a vendor, mailbox, bank or talking to any NPC?
function UI.AtAnNPC()
    if ns.Selling and ns.Selling.merchantOpen then return true end
    local errands = ns.Errands
    if errands and (errands.mailOpen or errands.bankOpen) then return true end
    if UI.openedByVendor or UI.openedFor then return true end
    local ok, talking = pcall(function() return UnitExists("npc") and true or false end)
    return ok and talking == true
end

--- Say Moroes's line for "open" or "close", when it may be said now.
function UI:Say(which)
    local id = self.VOICE[which]
    if not id or not (ns.db and ns.db.voice ~= false) then return false end
    if self.AtAnNPC() then return false end
    local ok, now = pcall(GetTime)
    if not (ok and type(now) == "number") then return false end
    local last = self.voiceAt[which]
    if last and now - last < self.VOICE_GAP then return false end
    ok = pcall(PlaySoundFile, id, "Dialog")
    if ok then self.voiceAt[which] = now end
    return ok
end

ns.RegisterCommand("window", L["open the Butler window (so does /bbutler on its own)"], function()
    UI:Toggle()
end)

ns.RegisterCommand("all", L["every character's items in one list, with where each one is"], function()

    if UI:IsShown() and UI.view == "all" then
        UI:Hide()
    else
        local wasShown = UI:IsShown()
        UI:Show("all")
        if not wasShown then UI:Say("open") end
    end
end)
