-- Blackthornes Butler -- UI/Settings.lua
-- The settings window: every switch the addon has, in one place.
--
-- Built the way Tradeskills' Settings tab is (UI/SettingsPages.lua): pages
-- picked along the top, two columns of rows a page, a row being [label ..
-- control] on one line, and what it does in the row's tooltip or, with Show
-- descriptions ticked, underneath it.
--
-- Open it with /bbutler settings, a click on the minimap button, or from the
-- game's own Options > AddOns list. Nothing here deletes anything.

local _, ns = ...
local L = ns.L

local SettingsUI = ns.NewModule("SettingsUI")

local Theme = ns.Theme
local Widgets = ns.Widgets

local PADDING = 18
-- From the window's top to the gold rule under the header row.
local HEADER = 44
-- The metal rim sits on the window's edge and reaches this far inward, with
-- room to spare (UI/Titanforged.lua).
local EDGE_PAD = 11

local COLUMN_WIDTH = 330
local COLUMN_GAP = 18
-- Where the controls start: room for a label like "Free Bag Space:" in the
-- game's font, which runs wider than it looks.
local CONTROL_X = 150

local TITLE = "Blackthornes Butler"

-- The pages along the top (UI/SettingsPages.lua), as Tradeskills' Settings
-- tab has them. Every setting kept its saved name; only its place moved.
local PAGES = {
    { key = "selling", text = L["ERRANDS"],
      tip = L["Selling at a vendor, mail and the bank, and your Always keep, sell and bank lists"] },
    { key = "order", text = L["ORDER"],
      tip = L["The order Butler asks its rules in, and which ones are on"] },
    { key = "bankalt", text = L["BANK ALT"],
      tip = L["Mail whole kinds of items to one of your characters"] },
    { key = "lists", text = L["LISTS"] },
    { key = "gold", text = L["GOLD"],
      tip = L["How much gold each of your characters keeps, topped up by mail"] },
    { key = "general", text = L["GENERAL"],
      tip = L["Windows, tooltips and text size"] },
    { key = "about", text = L["ABOUT"],
      tip = L["How these addons are made, the version, the Discord and the other Blackthornes addons"] },
}

--- Put the Butler window and this one back where they started.
function SettingsUI:ResetPositions()
    ns.db.settingsPoint = nil
    ns.db.settingsRelativePoint = nil
    ns.db.settingsX = nil
    ns.db.settingsY = nil
    self:RestorePosition()
    ns.db.point, ns.db.relativePoint, ns.db.x, ns.db.y = nil, nil, nil, nil
    if ns.UI and ns.UI.RestorePosition then ns.UI:RestorePosition() end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function SettingsUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesButlerSettings", UIParent)
    frame:SetSize(COLUMN_WIDTH * 2 + COLUMN_GAP + PADDING * 2, 600)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    Theme.Fill(frame, "window")

    -- The house frame (UI/Titanforged.lua): the gold rim, the name on a
    -- plate and the red close gem. No portrait: on a window this narrow it
    -- would sit over the first section's heading.
    if ns.Titanforged then
        local trim = ns.Titanforged:Dress(frame, {
            title = TITLE,
            close = function() SettingsUI:Hide() end,
        })
        self.trim = trim

        local left, right, top, bottom = ns.Titanforged.Reach(trim)
        if frame.SetClampRectInsets then
            frame:SetClampRectInsets(-left, right, top, -bottom)
        end
    else
        Theme.Border(frame, "borderLit")
    end

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SettingsUI:SavePosition()
        if ns.ButlerTabs then ns.ButlerTabs:Save(self) end
    end)
    -- Closed for good, not stepping aside for another tab: Tradeskills'
    -- mail panel may come back.
    frame:SetScript("OnHide", function()
        if ns.ButlerTabs and ns.ButlerTabs.switching then return end
        if ns.Errands then ns.Errands:TellTradeskills() end
    end)

    -- Escape closes it, like the game's own windows.
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesButlerSettings")
    end

    self.frame = frame
    self.controls = {}

    self:BuildHeader()

    self.pages = ns.SettingsPages.New(frame, {
        pages = PAGES,
        top = HEADER + 4,
        bottom = 40,
        padding = PADDING,
        columnWidth = COLUMN_WIDTH,
        columnGap = COLUMN_GAP,
        controlX = CONTROL_X,
        db = function() return ns.db end,
    })
    self:BuildPages()
    -- The order Butler asks its rules in (UI/RuleOrder.lua): one board
    -- across both columns.
    if ns.RuleOrderUI then
        local pages = self.pages
        local board = ns.RuleOrderUI:Build(pages.pages.order.content, COLUMN_WIDTH, COLUMN_GAP, function(key)
            pages:Show(key)
        end)
        pages:Place("order", 1, board)
        pages:Searchable("order", board, board.words)
    end
    -- About (UI/About.lua): the note on how the addons are made, then the
    -- version, the Discord and the other Blackthornes addons.
    if ns.About then
        local pages = self.pages
        pages:Section("about", 1, L["HOW THESE ADDONS ARE MADE"])
        local note = pages:Place("about", 1, ns.About:Note(pages.pages.about.content, COLUMN_WIDTH))
        pages:Searchable("about", note, note.words)
        pages:Section("about", 2, L["ABOUT"])
        local info = pages:Place("about", 2, ns.About:Info(pages.pages.about.content, COLUMN_WIDTH))
        pages:Searchable("about", info, info.words)
    end
    -- Every tab is one size (UI/ButlerTabs.lua): Settings says what its
    -- fullest page needs, and the Butler window grows to match.
    local pages = self.pages
    local fit = pages.Fit
    pages.Fit = function(page)
        fit(page)
        if ns.ButlerTabs then ns.ButlerTabs:Need("settings", frame:GetWidth(), frame:GetHeight()) end
    end
    self.pages:Fit()

    local footer = Theme.CreateLabel(frame, "tiny", "dim")
    footer:SetPoint("BOTTOMLEFT", PADDING, 14)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 14)
    footer:SetText(L["Changes save as you make them."])
    self.footer = footer

    -- Your Bags, All Characters and Settings, last on the right.
    if ns.ButlerTabs then ns.ButlerTabs:Attach(self) end

    frame:Hide()
    return frame
end

--- The header row. The addon's name is on the plate across the top edge
--- and the close gem sits on the top right corner (UI/Titanforged.lua), so
--- the row says which page this is and which version is running.
function SettingsUI:BuildHeader()
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

    local subtitle = Theme.CreateLabel(header, "small", "muted")
    subtitle:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", PADDING - EDGE_PAD, 7)
    subtitle:SetText(L["Settings"])

    local version = Theme.CreateLabel(header, "tiny", "dim", "RIGHT")
    version:SetText(ns.VersionLabel())
    version:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -(PADDING - EDGE_PAD), 8)
end

--- A row whose button runs a /bbutler command. Chat-only commands have no
--- row (the owner, 2026-10-15).
local function CommandRow(pages, page, column, label, description, buttonText, command)
    local row = pages:Row(page, column, label, description)
    local button = Widgets.CreateButton(row, buttonText, function()
        ns.HandleSlash(command)
    end, { width = 100, height = 20 })
    button:SetPoint("TOPLEFT", CONTROL_X, 0)
    return row, button
end

--- Off, Shift or Always for a tooltip line (UI/TooltipShift.lua), on `row`
--- at CONTROL_X. `isOn()` reads the line's own on/off setting and `setOn`
--- is its setter, the one the old tick box called; Shift is kept apart.
function SettingsUI.TooltipShiftControl(row, key, isOn, setOn)
    local TooltipShift = ns.TooltipShift
    local stepper = Widgets.CreateChoice(row, {
        min = 0, max = 2, step = 1,
        format = function(value) return TooltipShift.NAMES[value] end,
        onChange = function(value)
            TooltipShift:Apply(value, key, isOn(), setOn)
        end,
    })
    ns.SettingsPages.FitStepper(stepper, TooltipShift.NAMES)
    stepper:SetPoint("TOPLEFT", CONTROL_X, -2)

    --- Show what is saved, without writing anything.
    function stepper:Sync()
        self:SetValue(TooltipShift:Mode(isOn(), key), true)
    end
    stepper:Sync()
    return stepper
end

-- The window styles, in the order their drop-down lists them.
local STYLES = { "titanforged", "blizzard" }
local STYLE_LABELS = { titanforged = "Titanforged", blizzard = "Blizzard" }

--- Titanforged or Blizzard, with Reload under it while the pick differs
--- from what is drawn, as the Text size row has. A drop-down, like Text
--- size.
function SettingsUI.WindowStyleControl(row, x)
    local reload
    local function Drawn()
        local Look = ns.BlizzardLook
        return Look and Look.Style() or "titanforged"
    end

    local stepper = Widgets.CreateChoice(row, {
        min = 1, max = #STYLES, step = 1,
        format = function(value) return STYLE_LABELS[STYLES[value]] end,
        onChange = function(value)
            ns.db.windowStyle = STYLES[value]
            reload:SetShown(STYLES[value] ~= Drawn())
        end,
    })
    -- As wide as "Titanforged" at the player's text size, with Reload under
    -- it: at 100 with Reload beside it, the word spilled out of its box and
    -- Reload out of the column (a player's report, 2026-10-13).
    ns.SettingsPages.FitStepper(stepper, STYLE_LABELS)
    stepper:SetPoint("TOPLEFT", x, -2)

    -- ReloadUI is allowed from a click, and saves everything first.
    reload = Widgets.CreateButton(row, L["Reload now"], function()
        if ReloadUI then ReloadUI() end
    end, { width = 60, height = 20 })
    ns.SettingsPages.ReloadUnder(row, stepper, reload)
    reload:Hide()
    stepper.reload = reload

    function stepper:Sync()
        local Look = ns.BlizzardLook
        local wanted = Look and Look.Wanted() or "titanforged"
        self:SetValue(wanted == "blizzard" and 2 or 1, true)
        reload:SetShown(wanted ~= Drawn())
    end

    return stepper
end

--- The player's characters on this realm and side by full name, in a
--- drop-down (the owner, 2026-10-23: drop-downs, never < > pickers), as
--- wide as the longest name so none is cut short. Also lists and items.
--- :SetNames(list), :GetName(), :Select(name); .index is the one picked,
--- and :Pick(index) is what a click on a line of its menu does.
function SettingsUI.CharacterPicker(row, x, onChange)
    local picker = Widgets.CreateDropdown(row, {}, nil,
        { width = 180, placeholder = L["No characters yet"] })
    picker:SetPoint("TOPLEFT", x, -1)
    picker.names, picker.index, picker.least = {}, 1, 180
    picker.text = picker.label

    local function Show()
        local count = #picker.names
        picker.index = math.max(1, math.min(picker.index, math.max(1, count)))
        local options = {}
        for index, name in ipairs(picker.names) do options[index] = { text = name, value = index } end
        picker.options = options
        -- Grows to the longest name; never narrower than `least`.
        picker:SetWidth(Widgets.DropdownWidth(options, picker.least))
        picker:SetValue(count > 0 and picker.index or nil)
    end

    function picker:Pick(index)
        if self.menu then self.menu:Hide() end
        index = tonumber(index)
        if not index or index < 1 or index > #self.names or index == self.index then return end
        self.index = index
        Show()
        if onChange then onChange() end
    end

    function picker:SetNames(names)
        local current = self.names[self.index]
        self.names = names
        self.index = 1
        for index, name in ipairs(names) do
            if name == current then self.index = index end
        end
        Show()
    end

    function picker:GetName()
        return self.names[self.index]
    end

    --- Show this name, or the first when it is nil or not there.
    function picker:Select(name)
        self.index = 1
        for index, each in ipairs(self.names) do
            if name ~= nil and each == name then self.index = index end
        end
        Show()
    end

    Show()
    return picker
end

--- The picked character's own amount (or the usual) in its money box.
function SettingsUI:SyncGoldFor()
    local controls = self.controls
    if not (controls and controls.goldPick) then return end
    local name = controls.goldPick:GetName()
    local own = name and ns.Funds:Override(name)
    controls.goldFor:SetValue(own or (name and ns.Funds:MinimumFor(name)) or 0)
    controls.goldUsual:SetShown(own ~= nil)
end

--- The picked character's upgrade mail: the tick, and Undo with how many
--- items are held back (dim with none).
function SettingsUI:SyncHeld()
    local controls = self.controls
    if not (controls and controls.heldPick) then return end
    local name = controls.heldPick:GetName()
    controls.heldAll:SetChecked(not (name and (ns.db.noUpgradesFor or {})[name]))
    local count = name and #ns.Verdicts:HeldItems(name) or 0
    controls.heldItems:SetText(count > 0 and L.Format("Undo %d", count) or L["None"])
    controls.heldItems:SetLabelColor(count == 0 and "dim" or nil)
end

--- Show Again, dim with "None" while no craft is turned off.
function SettingsUI:SyncCraftSkip()
    local controls = self.controls
    if not (controls and controls.craftSkip) then return end
    local count = ns.Verdicts:SkippedCraftCount()
    controls.craftSkip:SetText(count > 0 and L["Show Again"] or L["None"])
    controls.craftSkip:SetLabelColor(count == 0 and "dim" or nil)
end

-- The characters and items the keep pickers step through.
SettingsUI.keepState = { guids = {}, items = {} }

--- Keep on each character: the characters with a list (the one playing
--- first), the picked one's items, and the picked item's number.
function SettingsUI:SyncKeepHere()
    local controls = self.controls
    if not (controls and controls.keepWho and ns.KeepHere) then return end
    local state = self.keepState
    local who = controls.keepWho
    local current = state.guids[who.index]
    local names, guids = {}, {}
    for _, each in ipairs(ns.KeepHere:Characters()) do
        names[#names + 1] = each.name
        guids[#guids + 1] = each.guid
    end
    state.guids = guids
    who:SetNames(names)
    who.index = 1
    for index, guid in ipairs(guids) do
        if guid == current then who.index = index end
    end
    who:Select(names[who.index])
    who.index = math.max(1, math.min(#guids, who.index))

    local what = controls.keepWhat
    local items = ns.KeepHere:Items(guids[who.index])
    local itemNames = {}
    for _, each in ipairs(items) do itemNames[#itemNames + 1] = ns.Items:ColorName(each.name, each.itemID) end
    local index = what.index or 1
    state.items = items
    what:SetNames(itemNames)
    what.index = math.max(1, math.min(#items, index))
    what:Select(itemNames[what.index])
    if #items == 0 then what.text:SetText(L["Nothing kept yet"]) end

    local picked = items[what.index]
    local all = picked and ns.KeepHere.IsAll(picked.count)
    controls.keepCount:SetText(picked and not all and tostring(picked.count) or "")
    if controls.keepAll then
        controls.keepAll:SetText(all and L["Keeping All"] or L["Keep All"])
        controls.keepAll:SetLabelColor(picked and not all and nil or "dim")
    end
    controls.keepRemove:SetLabelColor(picked and nil or "dim")
end

--- The bank alt page: who, when, which list and the kinds, as saved.
function SettingsUI:SyncBankAlt()
    local controls = self.controls
    if not (controls and controls.bankAltPick) then return end
    local BankAlt = ns.BankAlt
    local picked = BankAlt:Name()
    local names, seen = { L["Nobody"] }, {}
    local playing = ns.Errands:PlayingName()
    for _, name in ipairs(ns.Errands:Characters()) do seen[name] = true end
    if playing then seen[playing] = true end
    if picked then seen[picked] = true end
    local sorted = {}
    for name in pairs(seen) do sorted[#sorted + 1] = name end
    table.sort(sorted)
    for _, name in ipairs(sorted) do names[#names + 1] = name end
    controls.bankAltPick:SetNames(names)
    controls.bankAltPick:Select(picked)
    controls.bankAltPick.text:SetTextColor(Theme.Unpack("text"))

    local lists = { L["None"] }
    for _, name in ipairs(BankAlt:ListNames()) do lists[#lists + 1] = name end
    local list = BankAlt:ListName()
    local known = false
    for _, name in ipairs(lists) do known = known or name == list end
    if list and not known then lists[#lists + 1] = list end
    controls.bankAltList:SetNames(lists)
    controls.bankAltList:Select(list)

    for index, when in ipairs(BankAlt.WHEN) do
        if when == BankAlt:When() then controls.bankAltWhen:SetValue(index, true) end
    end
    for key, box in pairs(controls.bankAltKinds) do box:SetChecked(BankAlt:KindOn(key)) end
    if controls.bankAltAuctions then controls.bankAltAuctions:SetChecked(BankAlt:AuctionsOn()) end
end

--- The Tradeskills list picked on the Lists page: { name, id, items }, or
--- nil when there are none.
function SettingsUI:PickedList()
    local controls = self.controls
    local lists = self.listsState or {}
    return controls and controls.listsPick and lists[controls.listsPick.index] or nil
end

--- The Lists page: the player's Tradeskills lists, and the picked one's
--- Mail To and Keep Here as saved.
function SettingsUI:SyncLists()
    local controls = self.controls
    if not (controls and controls.listsPick and ns.ListRules) then return end
    local lists = {}
    for _, list in ipairs(ns.ListRules:Lists()) do
        if list.id ~= nil then lists[#lists + 1] = list end
    end
    self.listsState = lists
    local names = {}
    for _, list in ipairs(lists) do names[#names + 1] = list.name end
    controls.listsPick:SetNames(names)
    if #names == 0 then controls.listsPick.text:SetText(L["None"]) end

    local list = self:PickedList()
    local rule = list and ns.ListRules:Get(list.id) or {}
    local picked = rule.mailTo
    -- Never the character playing: it can't mail itself.
    local choices, seen, sorted = { L["Nobody"] }, {}, {}
    for _, name in ipairs(ns.Errands:Characters()) do
        if not seen[name] and not ns.Verdicts:IsMe(name) then
            seen[name] = true
            sorted[#sorted + 1] = name
        end
    end
    if picked and not seen[picked] then sorted[#sorted + 1] = picked end
    table.sort(sorted)
    for _, name in ipairs(sorted) do choices[#choices + 1] = name end
    controls.listsMailTo:SetNames(choices)
    controls.listsMailTo:Select(picked)
    -- Dim with no list to set it for.
    controls.listsMailTo:SetAlpha(list and 1 or 0.45)

    if not controls.listsKeep.editBox:HasFocus() then
        controls.listsKeep:SetText(rule.keep and tostring(rule.keep) or "")
    end
end

function SettingsUI:BuildPages()
    local controls = self.controls
    local pages = self.pages

    -- Selling: the vendor on the left, the player's lists on the right.
    pages:Section("selling", 1, L["AT A VENDOR"])

    local vendorRow = pages:Row("selling", 1, L["Open at Vendors:"],
        L["Opens Butler at every vendor. Nothing sells until you click Sell."])
    controls.openAtVendor = Widgets.CreateCheckbox(vendorRow, L["On"], function(checked)
        ns.db.openAtVendor = checked
    end, true)
    controls.openAtVendor:SetPoint("TOPLEFT", CONTROL_X, -2)

    local buyRow = pages:Row("selling", 1, L["Buy More:"],
        L["Shift-click an item at a vendor to buy as many as you want, like 200."])
    controls.buyMany = Widgets.CreateCheckbox(buyRow, L["On"], function(checked)
        ns.BuyMany:SetOn(checked)
    end, true)
    controls.buyMany:SetPoint("TOPLEFT", CONTROL_X, -2)

    pages:Section("selling", 1, L["MAIL AND BANK"])

    local mailRow = pages:Row("selling", 1, L["Open at Mailboxes:"],
        L["Opens Butler at every mailbox. Fill Mail fills in the mail and you press Send. Needs Blackthornes Tradeskills."])
    controls.openAtMailbox = Widgets.CreateCheckbox(mailRow, L["On"], function(checked)
        ns.db.openAtMailbox = checked
    end, true)
    controls.openAtMailbox:SetPoint("TOPLEFT", CONTROL_X, -2)

    local nextRow = pages:Row("selling", 1, L["Fill the Next Mail:"],
        L["After you send one, Butler fills the next character's mail."])
    controls.fillNext = Widgets.CreateCheckbox(nextRow, L["On"], function(checked)
        ns.db.fillNext = checked
    end, true)
    controls.fillNext:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Jobs for the craft queue on other characters (Logic/Jobs.lua, asked
    -- 2026-10-11).
    local jobRow = pages:Row("selling", 1, L["Jobs at Login:"],
        L["Opens Butler at login when this character has crafting or mail to do."])
    controls.jobsAtLogin = Widgets.CreateCheckbox(jobRow, L["On"], function(checked)
        ns.db.jobsAtLogin = checked
    end, true)
    controls.jobsAtLogin:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Items for your quests (Logic/Quests.lua, a player asked 2026-10-14).
    local questRow = pages:Row("selling", 1, L["Quest Items:"],
        L["Keeps what your quests need and lists what's still missing."])
    controls.questItems = Widgets.CreateCheckbox(questRow, L["On"], function(checked)
        ns.Quests:SetOn(checked)
    end, true)
    controls.questItems:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Buy them at the auction house (Logic/QuestBuy.lua, 2026-10-18).
    local questBuyRow = pages:Row("selling", 1, L["Buy Quest Items:"],
        L["At the auction house, lists each item your quests need with its price and a Buy button."])
    controls.questBuy = Widgets.CreateCheckbox(questBuyRow, L["On"], function(checked)
        ns.QuestBuy:SetOn(checked)
    end, false)
    controls.questBuy:SetPoint("TOPLEFT", CONTROL_X, -2)

    local bankRow = pages:Row("selling", 1, L["Open at the Bank:"],
        L["Opens Butler at the bank when there's something to move."])
    controls.openAtBank = Widgets.CreateCheckbox(bankRow, L["On"], function(checked)
        ns.db.openAtBank = checked
    end, true)
    controls.openAtBank:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The owner asked 2026-10-14: on the disenchanter, break every green.
    pages:Section("selling", 1, L["DISENCHANTING"])

    local greensRow = pages:Row("selling", 1, L["Disenchant Greens Here:"],
        L["On your disenchanter, greens go under Disenchant unless selling pays more. Crafted greens, upgrades and things you need are still kept."])
    controls.disenchantGreens = Widgets.CreateCheckbox(greensRow, L["On"], function(checked)
        ns.Verdicts:SetDisenchantGreens(checked)
    end)
    controls.disenchantGreens:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- A player asked, the owner said yes (2026-10-16): your disenchanter
    -- takes a green only when breaking it pays as much as selling it,
    -- unless this is ticked. Levelling Enchanting takes it either way
    -- (the owner, 2026-10-17).
    local alwaysRow = pages:Row("selling", 1, L["Always Disenchant:"],
        L["Greens go to your disenchanter even when selling them pays more."])
    controls.alwaysDisenchant = Widgets.CreateCheckbox(alwaysRow, L["On"], function(checked)
        ns.Verdicts:SetAlwaysDisenchant(checked)
    end)
    controls.alwaysDisenchant:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Asked 2026-10-11: anything worth less than this joins Sell. It only
    -- ever adds to Sell; nothing sells until the player clicks.
    pages:Section("selling", 2, L["JUNK"])

    local belowRow = pages:Row("selling", 2, L["Sell Below:"],
        L["Anything worth less than this goes under Sell. 0 turns it off."])
    controls.sellBelow = Widgets.CreateMoneyBox(belowRow, function(copper)
        ns.Verdicts:SetSellBelow(copper)
    end)
    controls.sellBelow:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- A player asked, the owner said build it (2026-10-19): say when a
    -- known craft earns more than selling. Off unless ticked.
    pages:Section("selling", 2, L["CRAFTING"])

    local craftRow = pages:Row("selling", 2, L["Craft When It Pays More:"],
        L["Butler checks the recipes you know and says when crafting earns more than selling. Needs Blackthornes Tradeskills."])
    controls.craftPays = Widgets.CreateCheckbox(craftRow, L["On"], function(checked)
        ns.Verdicts:SetCraftPays(checked)
    end)
    controls.craftPays:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Crafts turned off from a Craft row's right-click (the owner,
    -- 2026-10-26); this brings them all back.
    local skipRow = pages:Row("selling", 2, L["Crafts You Turned Off:"],
        L["Brings back every craft you told Butler to stop suggesting."])
    controls.craftSkip = Widgets.CreateButton(skipRow, L["Show Again"], function()
        ns.Verdicts:ShowSkippedCrafts()
        SettingsUI:SyncCraftSkip()
    end, { width = 100, height = 20 })
    controls.craftSkip:SetPoint("TOPLEFT", CONTROL_X, 0)

    pages:Section("selling", 2, L["YOUR LISTS"])

    local learnRow = pages:Row("selling", 2, L["Learn From You:"],
        L["Butler learns what you keep, sell and mail. Your right-click picks always win."])
    controls.learn = Widgets.CreateCheckbox(learnRow, L["On"], function(checked)
        ns.db.learn = checked
        ns.Verdicts:Changed(true)
    end)
    controls.learn:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Upgrades held back from a character (the owner asked 2026-10-12):
    -- right-click an upgrade under Mail to hold it back; undone here.
    pages:Section("selling", 2, L["UPGRADES FOR YOUR CHARACTERS"])

    local altRow = pages:Row("selling", 2, L["Mail Upgrades to Alts:"],
        L["Gear that's an upgrade for another of your characters goes under Mail. Needs Blackthornes Equipment."])
    controls.altUpgrades = Widgets.CreateCheckbox(altRow, L["On"], function(checked)
        ns.Verdicts:SetAltUpgrades(checked)
    end)
    controls.altUpgrades:SetPoint("TOPLEFT", CONTROL_X, -2)

    local heldRow = pages:Row("selling", 2, L["Character:"],
        L["Pick a character to see what you hold back from them."])
    controls.heldPick = SettingsUI.CharacterPicker(heldRow, CONTROL_X, function()
        SettingsUI:SyncHeld()
    end)

    local allRow = pages:Row("selling", 2, L["Mail Them Upgrades:"], nil)
    controls.heldAll = Widgets.CreateCheckbox(allRow, L["On"], function(checked)
        local name = controls.heldPick:GetName()
        if name then ns.Verdicts:HoldAllUpgrades(name, not checked) end
    end)
    controls.heldAll:SetPoint("TOPLEFT", CONTROL_X, -2)

    local itemsRow = pages:Row("selling", 2, L["Items Held Back:"],
        L["Lets these items go to this character again."])
    controls.heldItems = Widgets.CreateButton(itemsRow, L["Undo"], function()
        local name = controls.heldPick:GetName()
        if not name then return end
        for _, itemID in ipairs(ns.Verdicts:HeldItems(name)) do
            ns.Verdicts:HoldUpgrade(itemID, name, false)
        end
        SettingsUI:SyncHeld()
    end, { width = 100, height = 20 })
    controls.heldItems:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- How many of an item each character keeps (Logic/KeepHere.lua, a
    -- player asked, the owner said build it 2026-10-17). Set with a
    -- right-click in the Butler window; seen and changed here.
    pages:Section("selling", 2, L["KEEP ON EACH CHARACTER"])

    local keepWhoRow = pages:Row("selling", 2, L["Character:"],
        L["Right-click an item in the Butler window to keep some on the character you're on."])
    controls.keepWho = SettingsUI.CharacterPicker(keepWhoRow, CONTROL_X, function()
        controls.keepWhat.index = 1
        SettingsUI:SyncKeepHere()
    end)

    local keepWhatRow = pages:Row("selling", 2, L["Item:"], nil)
    controls.keepWhat = SettingsUI.CharacterPicker(keepWhatRow, CONTROL_X, function()
        SettingsUI:SyncKeepHere()
    end)

    local function KeepPicked()
        local state = SettingsUI.keepState
        return state.guids[controls.keepWho.index], state.items[controls.keepWhat.index]
    end

    local keepCountRow = pages:Row("selling", 2, L["Keep:"], L["0 takes it off the list. Keep All keeps every one."])
    local function SaveCount()
        local who, what = KeepPicked()
        if not (who and what) then return end
        local text = controls.keepCount.editBox:GetText()
        -- An empty box beside Keep All means it is still all.
        if (text == nil or text == "") and ns.KeepHere.IsAll(what.count) then return end
        local count = tonumber(text) or 0
        if count == what.count then return end
        ns.KeepHere:Set(what.itemID, count, who)
        SettingsUI:SyncKeepHere()
    end
    controls.keepCount = Widgets.CreateSearchBox(keepCountRow, "0", nil, SaveCount, { plain = true })
    controls.keepCount:SetSize(60, 24)
    controls.keepCount:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.keepCount.editBox:SetMaxLetters(4)
    if controls.keepCount.editBox.SetNumeric then controls.keepCount.editBox:SetNumeric(true) end
    controls.keepCount.editBox:HookScript("OnEditFocusLost", SaveCount)
    controls.keepAll = Widgets.CreateButton(keepCountRow, L["Keep All"], function()
        local who, what = KeepPicked()
        if not (who and what) or ns.KeepHere.IsAll(what.count) then return end
        ns.KeepHere:Set(what.itemID, ns.KeepHere.MOST, who)
        SettingsUI:SyncKeepHere()
    end, { width = 100, height = 20 })
    controls.keepAll:SetPoint("LEFT", controls.keepCount, "RIGHT", 6, 0)

    local keepRemoveRow = pages:Row("selling", 2, L["Remove:"], nil)
    controls.keepRemove = Widgets.CreateButton(keepRemoveRow, L["Remove"], function()
        local who, what = KeepPicked()
        if not (who and what) then return end
        ns.KeepHere:Set(what.itemID, 0, who)
        SettingsUI:SyncKeepHere()
    end, { width = 100, height = 20 })
    controls.keepRemove:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Bank alt (Logic/BankAlt.lua, a player asked, the owner said build it
    -- 2026-10-14): who, where it sits among the verdicts and which list on
    -- the left, the kinds of items on the right.
    pages:Section("bankalt", 1, L["BANK ALT"])

    local altRow = pages:Row("bankalt", 1, L["Send To:"],
        L["The character that gets the kinds of items you tick. Fill Mail sends them."])
    controls.bankAltPick = SettingsUI.CharacterPicker(altRow, CONTROL_X, function()
        local picker = controls.bankAltPick
        ns.BankAlt:SetName(picker.index > 1 and picker:GetName() or nil)
        local name = ns.BankAlt:Name()
        if name then
            ns.Print(L.Format("%s is your bank alt.", name))
        else
            ns.Print(L["no bank alt, so nothing is mailed by kind."])
        end
    end)

    -- A character on another account, typed by hand (a player asked, the
    -- owner said yes, 2026-10-16). A name that isn't one of the player's
    -- characters is kept as typed; chat says it was set.
    local typeRow = pages:Row("bankalt", 1, L["Type a Name:"],
        L["For a character on your other account. Type its name."])
    controls.bankAltTyped = Widgets.CreateSearchBox(typeRow, L["Name"], nil, function(text)
        local name, why = ns.BankAlt:TypeName(text)
        controls.bankAltTyped:SetText("")
        if name then
            ns.Print(L.Format("%s is your bank alt.", name))
        elseif why then
            ns.Print(why)
        end
    end, { plain = true })
    controls.bankAltTyped:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.bankAltTyped:SetWidth(180)

    local whenRow = pages:Row("bankalt", 1, L["When:"],
        L["Before Everything sends what you tick, even things that sell well. Before a Vendor lets the auction house and disenchanting go first. Only Leftovers sends what's left."])
    controls.bankAltWhen = Widgets.CreateChoice(whenRow, {
        min = 1, max = #ns.BankAlt.WHEN, step = 1,
        format = function(value) return ns.BankAlt.WHEN_LABELS[ns.BankAlt.WHEN[value]] end,
        onChange = function(value) ns.BankAlt:SetWhen(ns.BankAlt.WHEN[value]) end,
    })
    ns.SettingsPages.FitStepper(controls.bankAltWhen, ns.BankAlt.WHEN_LABELS)
    controls.bankAltWhen:SetPoint("TOPLEFT", CONTROL_X, -2)

    local listRow = pages:Row("bankalt", 1, L["Shopping List:"],
        L["Everything on this list goes to the bank alt too."])
    controls.bankAltList = SettingsUI.CharacterPicker(listRow, CONTROL_X, function()
        local picker = controls.bankAltList
        ns.BankAlt:SetList(picker.index > 1 and picker:GetName() or nil)
    end)

    -- Rules for each of the player's Tradeskills lists (Logic/ListRules.lua,
    -- the owner said build it, 2026-10-19): pick a list, then who it mails
    -- to and how many of each stay on every character.
    pages:Section("lists", 1, L["YOUR TRADESKILLS LISTS"])
    local listRow = pages:Row("lists", 1, "", nil)
    controls.listsPick = SettingsUI.CharacterPicker(listRow, 0, function()
        SettingsUI:SyncLists()
    end)
    controls.listsPick.least = COLUMN_WIDTH
    controls.listsPick:SetWidth(COLUMN_WIDTH)

    local mailToRow = pages:Row("lists", 1, L["Mail To:"], nil)
    controls.listsMailTo = SettingsUI.CharacterPicker(mailToRow, CONTROL_X, function()
        local list = SettingsUI:PickedList()
        if not list then return end
        local picker = controls.listsMailTo
        ns.ListRules:SetMailTo(list.id, picker.index > 1 and picker:GetName() or nil)
    end)

    local keepRow = pages:Row("lists", 1, L["Keep Here:"], nil)
    local function SaveListKeep()
        local list = SettingsUI:PickedList()
        if not list then return end
        local count = tonumber(controls.listsKeep.editBox:GetText()) or 0
        if count == (ns.ListRules:Get(list.id).keep or 0) then return end
        ns.ListRules:SetKeep(list.id, count)
    end
    controls.listsKeep = Widgets.CreateSearchBox(keepRow, "0", nil, SaveListKeep, { plain = true })
    controls.listsKeep:SetSize(60, 24)
    controls.listsKeep:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.listsKeep.editBox:SetMaxLetters(4)
    if controls.listsKeep.editBox.SetNumeric then controls.listsKeep.editBox:SetNumeric(true) end
    controls.listsKeep.editBox:HookScript("OnEditFocusLost", SaveListKeep)
    local keepNote = Theme.CreateLabel(keepRow, "tiny", "muted")
    keepNote:SetPoint("LEFT", controls.listsKeep, "RIGHT", 6, 0)
    keepNote:SetWidth(COLUMN_WIDTH - CONTROL_X - 66)
    keepNote:SetWordWrap(true)
    keepNote:SetText(L["of each, on every character"])

    pages:Section("bankalt", 2, L["WHAT GOES THERE"])
    controls.bankAltKinds = {}
    -- The kinds' names as the Settings rows show them; chat keeps kind.label.
    local KIND_LABELS = {
        cloth = L["Cloth:"],
        leather = L["Leather:"],
        metal = L["Ore, Bars and Stone:"],
        herb = L["Herbs:"],
        meat = L["Meat and Cooking:"],
        elemental = L["Elemental:"],
        enchanting = L["Enchanting Materials:"],
        tradegoods = L["Other Trade Goods:"],
        boe = L["Gear That Binds When Worn:"],
    }
    for _, kind in ipairs(ns.BankAlt.KINDS) do
        local key = kind.key
        local description = key == "boe"
            and L["Green or better weapons and armor that bind when worn and aren't an upgrade for you."]
            or nil
        local row = pages:Row("bankalt", 2, KIND_LABELS[key] or kind.label, description)
        local box = Widgets.CreateCheckbox(row, L["On"], function(checked)
            ns.BankAlt:SetKind(key, checked)
        end, true)
        box:SetPoint("TOPLEFT", CONTROL_X, -2)
        controls.bankAltKinds[key] = box
    end

    -- Auction Items (a player asked, the owner said build it, 2026-10-22):
    -- whatever Butler would auction goes too, whatever its kind.
    local auctionRow = pages:Row("bankalt", 2, L["Auction Items:"],
        L["Everything Butler would put on the auction house goes to the bank alt, whatever kind it is."])
    controls.bankAltAuctions = Widgets.CreateCheckbox(auctionRow, L["On"], function(checked)
        ns.BankAlt:SetAuctions(checked)
    end, false)
    controls.bankAltAuctions:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Gold: the gold fund (the owner asked 2026-10-11). The usual amount on
    -- the left, one character's own on the right. Logic/Funds.lua.
    pages:Section("gold", 1, L["GOLD FUND"])

    local minRow = pages:Row("gold", 1, L["Keep at Least:"],
        L["Every character keeps at least this much. A character with more can mail gold to one with less. 0 turns it off."])
    controls.goldMinimum = Widgets.CreateMoneyBox(minRow, function(copper)
        ns.Funds:SetMinimum(copper)
    end)
    controls.goldMinimum:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- Class spells to train (Logic/ClassTraining.lua, the owner said build
    -- it 2026-10-13).
    pages:Section("gold", 1, L["CLASS TRAINING"])

    local trainingRow = pages:Row("gold", 1, L["Class Training:"],
        L["Spells you can train show at the top of Jobs with their cost."])
    controls.classTraining = Widgets.CreateCheckbox(trainingRow, L["On"], function(checked)
        ns.ClassTraining:SetOn(checked)
        ns.Funds:Changed()
    end, true)
    controls.classTraining:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- TomTom's arrow instead of Show the way's dial, when TomTom is
    -- installed (Logic/TomTom.lua). On unless unticked.
    local tomtomRow = pages:Row("gold", 1, L["Use TomTom:"],
        L["With TomTom installed, its arrow shows the way instead."])
    controls.useTomTom = Widgets.CreateCheckbox(tomtomRow, L["On"], function(checked)
        if ns.TomTom then ns.TomTom:SetOn(checked) end
    end, true)
    controls.useTomTom:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Show the way to a trainer far away step by step (Logic/Travel.lua,
    -- the same in every addon). On unless unticked.
    local guideRow = pages:Row("gold", 1, L["Guide Me:"],
        L["When the place is in another zone or across the sea, the arrow leads you there step by step."])
    controls.arrowRoute = Widgets.CreateCheckbox(guideRow, L["On"], function(checked)
        if ns.Travel then ns.Travel:SetOn(checked) end
    end, true)
    controls.arrowRoute:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Gold goals at the bottom of the window (Logic/GoldGoals.lua, the
    -- owner said build it 2026-10-13).
    pages:Section("gold", 1, L["GOLD GOALS"])

    local goalsRow = pages:Row("gold", 1, L["Gold Goals:"],
        L["Shows what your gold is for next: class spells, profession training and riding."])
    controls.goldGoals = Widgets.CreateCheckbox(goalsRow, L["On"], function(checked)
        ns.GoldGoals:SetOn(checked)
    end, true)
    controls.goldGoals:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The cheapest skill-up in Jobs (Logic/SkillUp.lua, a player asked,
    -- the owner said build it 2026-10-19).
    pages:Section("gold", 1, L["PROFESSIONS"])

    local skillUpRow = pages:Row("gold", 1, L["Cheapest Skill-Up:"],
        L["Shows the cheapest craft for your next skill point in each profession. Needs Blackthornes Tradeskills."])
    controls.skillUp = Widgets.CreateCheckbox(skillUpRow, L["On"], function(checked)
        ns.SkillUp:SetOn(checked)
    end, false)
    controls.skillUp:SetPoint("TOPLEFT", CONTROL_X, -2)

    pages:Section("gold", 2, L["ONE CHARACTER"])

    local pickRow = pages:Row("gold", 2, L["Character:"],
        L["Give one character its own amount."])
    controls.goldPick = SettingsUI.CharacterPicker(pickRow, CONTROL_X, function()
        SettingsUI:SyncGoldFor()
    end)

    local ownRow = pages:Row("gold", 2, L["They Keep:"],
        L["0 means it can give all it has."])
    controls.goldFor = Widgets.CreateMoneyBox(ownRow, function(copper)
        local name = controls.goldPick:GetName()
        if name then ns.Funds:SetMinimumFor(name, copper) end
    end)
    controls.goldFor:SetPoint("TOPLEFT", CONTROL_X, 0)

    local usualRow = pages:Row("gold", 2, L["Back to Usual:"], nil)
    controls.goldUsual = Widgets.CreateButton(usualRow, L["Reset"], function()
        local name = controls.goldPick:GetName()
        if name then ns.Funds:SetMinimumFor(name, nil) end
        SettingsUI:SyncGoldFor()
    end, { width = 100, height = 20 })
    controls.goldUsual:SetPoint("TOPLEFT", CONTROL_X, 0)

    -- General: windows and text on the left, debug on the right.
    pages:Section("general", 1, L["WINDOWS"])

    local windowRow = pages:Row("general", 1, L["Butler:"], nil)
    controls.openWindow = Widgets.CreateButton(windowRow, L["Open"], function()
        ns.HandleSlash("window")
    end, { width = 100, height = 20, primary = true })
    controls.openWindow:SetPoint("TOPLEFT", CONTROL_X, 0)

    local _, allButton = CommandRow(pages, "general", 1, L["All Characters:"],
        L["Every character's items in one list. Needs Blackthornes Tradeskills."],
        L["Open"], "all")
    controls.all = allButton

    -- The minimap button always shows (the owner, 2026-10-15), so it has
    -- no row here.

    local spaceRow = pages:Row("general", 1, L["Free Bag Space:"],
        L["Shows free slots on your backpack button."])
    controls.freeSpace = Widgets.CreateCheckbox(spaceRow, L["Show"], function(checked)
        if ns.FreeSpace then ns.FreeSpace:SetEnabled(checked) end
    end, true)
    controls.freeSpace:SetPoint("TOPLEFT", CONTROL_X, -2)

    local trashRow = pages:Row("general", 1, L["Trash Can:"],
        L["When your bags are full, a gold can marks the cheapest item Butler would sell. Click it to pick it up."])
    controls.trashCan = Widgets.CreateCheckbox(trashRow, L["Show"], function(checked)
        if ns.Trash then ns.Trash:SetEnabled(checked) end
    end, true)
    controls.trashCan:SetPoint("TOPLEFT", CONTROL_X, -2)

    local swapRow = pages:Row("general", 1, L["Swap When Full:"], nil)
    controls.swapWhenFull = Widgets.CreateCheckbox(swapRow, L["On"], function(checked)
        if ns.SwapWhenFull then ns.SwapWhenFull:SetEnabled(checked) end
    end, false)
    controls.swapWhenFull:SetPoint("TOPLEFT", CONTROL_X, -2)

    local whoRow = pages:Row("general", 1, L["Who Has It:"],
        L["Tooltips list which characters have the item. Needs Blackthornes Tradeskills."])
    controls.whoHas = SettingsUI.TooltipShiftControl(whoRow, "whoHas",
        function() return ns.db.whoHas ~= false end,
        function(on) if ns.WhoHas then ns.WhoHas:SetEnabled(on) end end)

    local tipRow = pages:Row("general", 1, L["Butler on Tooltips:"],
        L["The last tooltip line says what Butler would do with it."])
    controls.verdictTip = SettingsUI.TooltipShiftControl(tipRow, "verdictTip",
        function() return ns.db.verdictTip ~= false end,
        function(on) if ns.VerdictTip then ns.VerdictTip:SetEnabled(on) end end)

    local vendorRow = pages:Row("general", 1, L["Vendor Price:"], nil)
    controls.vendorPrice = SettingsUI.TooltipShiftControl(vendorRow, "vendorPrice",
        function() return ns.db.vendorPrice ~= false end,
        function(on) if ns.VendorPrices then ns.VendorPrices:SetEnabled(on) end end)

    local voiceRow = pages:Row("general", 1, L["Butler's Voice:"], nil)
    controls.voice = Widgets.CreateCheckbox(voiceRow, L["On"], function(checked)
        ns.db.voice = checked
    end, true)
    controls.voice:SetPoint("TOPLEFT", CONTROL_X, -2)

    local positionRow = pages:Row("general", 1, L["Window Position:"],
        L["Reset the Butler window to its default."])

    local reset = Widgets.CreateButton(positionRow, L["Set Default"], function()
        SettingsUI:ResetPositions()
        ns.Print(L["window set to default."])
    end, { width = 110, height = 20 })
    reset:SetPoint("TOPLEFT", CONTROL_X, 0)
    controls.resetPositions = reset

    -- Bigger letters in the same windows, as Tradeskills has. Every size
    -- is read as text is drawn, so it waits for /reload.
    local textRow = pages:Row("general", 1, L["Text Size:"], nil)
    controls.textSize = ns.SettingsPages.TextSizeControl(textRow, CONTROL_X, function() return ns.db end)

    -- Asked 2026-10-10: the game's own look for players who would rather
    -- the windows matched the rest of their screen. Read at login, so it
    -- waits for /reload as Text size does. See UI/BlizzardLook.lua.
    local styleRow = pages:Row("general", 1, L["Window Style:"], nil)
    controls.windowStyle = SettingsUI.WindowStyleControl(styleRow, CONTROL_X)

    -- One minimap button for every Blackthornes addon (UI/SharedMinimap.lua,
    -- the owner, 2026-10-28): ticked unless unticked, the same in all five.
    local combineRow = pages:Row("general", 1, L["Combine Addon Buttons:"], nil)
    controls.combineButtons = Widgets.CreateCheckbox(combineRow, L["On"], function(checked)
        if ns.SharedMinimap then ns.SharedMinimap.SetCombined(checked) end
    end, true)
    controls.combineButtons:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Butler's own bag window (UI/BagWindow.lua), off unless ticked.
    if ns.BagWindow then ns.BagWindow:AddSettings(pages, controls, CONTROL_X) end

    pages:Section("general", 2, L["ADVANCED"])

    -- Debug and the client check are typed only (/bbutler debug, probe;
    -- the owner, 2026-10-23): players don't need them.

    -- Core/SisterNote.lua: one chat line, once, naming the Blackthornes
    -- addons the player does not have. Off here is off in all of them.
    local sistersRow = pages:Row("general", 2, L["Sister Addons:"],
        L["Says once in chat which Blackthornes addons you don't have."])
    controls.sisters = Widgets.CreateCheckbox(sistersRow, L["On"], function(checked)
        ns.SisterNote:SetOn(checked)
    end, true)
    controls.sisters:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- UI/WhatsNew.lua: one window after an update for every Blackthornes
    -- addon. Off here is off in all of them, as the sister note is.
    local _, whatsNewButton = CommandRow(pages, "general", 2, L["What's New:"], nil,
        L["Open"], "whatsnew")
    controls.whatsnew = whatsNewButton

    local whatsNewRow = pages:Row("general", 2, L["What's New After Updates:"],
        L["Opens What's New the first time you play after an update."])
    controls.whatsNewPopup = Widgets.CreateCheckbox(whatsNewRow, L["On"], function(checked)
        ns.WhatsNew:SetOn(checked)
    end, true)
    controls.whatsNewPopup:SetPoint("TOPLEFT", CONTROL_X, -2)

    local whatsNewMotionRow = pages:Row("general", 2, L["What's New Motion:"], nil)
    controls.whatsNewMotion = Widgets.CreateCheckbox(whatsNewMotionRow, L["On"], function(checked)
        ns.WhatsNew:SetMotionOn(checked)
    end, true)
    controls.whatsNewMotion:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- The chat-only commands (help, jobs, lists, upgrademail, gold,
    -- training, goals and bankalt on its own) have no button here: they
    -- are typed only (the owner, 2026-10-15).
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Put every control back in step with what is saved. Called whenever the
--- page opens and after any /bbutler command, because each of these can also be
--- changed by typing.
function SettingsUI:Refresh()
    if not (self.frame and self.frame:IsShown() and ns.db) then return end

    local controls = self.controls
    if ns.BagWindow then ns.BagWindow:SyncSettings(controls) end
    controls.openAtVendor:SetChecked(ns.db.openAtVendor ~= false)
    controls.openAtMailbox:SetChecked(ns.db.openAtMailbox ~= false)
    controls.fillNext:SetChecked(ns.db.fillNext ~= false)
    controls.altUpgrades:SetChecked(ns.Verdicts:AltUpgradesOn())
    controls.disenchantGreens:SetChecked(ns.Verdicts:DisenchantGreensOn())
    controls.craftPays:SetChecked(ns.Verdicts:CraftPaysOn())
    self:SyncCraftSkip()
    controls.alwaysDisenchant:SetChecked(ns.Verdicts:AlwaysDisenchantOn())
    controls.jobsAtLogin:SetChecked(ns.db.jobsAtLogin ~= false)
    controls.questItems:SetChecked(ns.Quests:IsOn())
    controls.questBuy:SetChecked(ns.db.questBuy == true)
    controls.openAtBank:SetChecked(ns.db.openAtBank ~= false)
    controls.freeSpace:SetChecked(ns.db.freeSpace ~= false)
    controls.trashCan:SetChecked(ns.db.trashCan ~= false)
    controls.swapWhenFull:SetChecked(ns.db.swapWhenFull == true)
    controls.buyMany:SetChecked(ns.BuyMany:IsOn())
    controls.whoHas:Sync()
    controls.verdictTip:Sync()
    controls.vendorPrice:Sync()
    controls.voice:SetChecked(ns.db.voice ~= false)
    controls.learn:SetChecked(ns.db.learn ~= false)
    controls.classTraining:SetChecked(ns.ClassTraining:IsOn())
    controls.arrowRoute:SetChecked(ns.db.arrowRoute ~= false)
    controls.useTomTom:SetChecked(ns.db.useTomTom ~= false)
    controls.goldGoals:SetChecked(ns.GoldGoals:IsOn())
    controls.skillUp:SetChecked(ns.SkillUp:IsOn())
    controls.sisters:SetChecked(ns.SisterNote:IsOn())
    controls.whatsNewPopup:SetChecked(ns.WhatsNew:IsOn())
    controls.whatsNewMotion:SetChecked(ns.WhatsNew:IsMotionOn())
    controls.sellBelow:SetValue(ns.Verdicts:SellBelow() or 0)
    controls.goldMinimum:SetValue(ns.Funds:Minimum() or 0)
    local names = {}
    for _, character in ipairs((ns.Funds:Characters())) do names[#names + 1] = character.name end
    table.sort(names)
    controls.goldPick:SetNames(names)
    self:SyncGoldFor()
    local heldNames, seen = {}, {}
    for _, name in ipairs(ns.Errands:Characters()) do
        seen[name] = true
        heldNames[#heldNames + 1] = name
    end
    for _, name in ipairs(ns.Verdicts:HeldNames()) do
        if not seen[name] then heldNames[#heldNames + 1] = name end
    end
    table.sort(heldNames)
    controls.heldPick:SetNames(heldNames)
    self:SyncHeld()
    self:SyncKeepHere()
    self:SyncBankAlt()
    self:SyncLists()
    controls.textSize:Sync()
    controls.windowStyle:Sync()
    controls.combineButtons:SetChecked(not ns.SharedMinimap or ns.SharedMinimap.Combined())
    if ns.RuleOrderUI then ns.RuleOrderUI:Refresh() end
    self.pages:Refresh()
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function SettingsUI:SavePosition()
    if not (ns.db and self.frame) then return end

    local point, _, relativePoint, x, y = self.frame:GetPoint()

    ns.db.settingsPoint = point
    ns.db.settingsRelativePoint = relativePoint
    ns.db.settingsX = x
    ns.db.settingsY = y
end

function SettingsUI:RestorePosition()
    if not self.frame then return end

    local db = ns.db or {}

    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.settingsPoint or "CENTER", UIParent,
        db.settingsRelativePoint or "CENTER", db.settingsX or 0, db.settingsY or 0)
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

function SettingsUI:Show()
    self:Build()

    if not self.frame:IsShown() then
        -- In the Butler window's place when it is up, else where the tabs
        -- last stood (UI/ButlerTabs.lua).
        local how = ns.ButlerTabs and ns.ButlerTabs:Take(self)
        if not how then self:RestorePosition() end
        self.frame:Show()
        if not how and ns.ButlerTabs then ns.ButlerTabs:Settle(self.frame) end
        if how ~= "switch" then ns.Motion:Open(self.frame) end
        if ns.Errands then ns.Errands:TellTradeskills() end
    end

    self:Refresh()
end

function SettingsUI:Hide()
    if self.frame then self.frame:Hide() end
end

function SettingsUI:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--------------------------------------------------------------------------------
-- The game's own AddOns options list
--
-- As in Farmer: a small launcher under Options > AddOns rather than this page
-- squeezed into Blizzard's frame. Every call is guarded, because a missing
-- options entry is no reason for the addon to fail to load.
--------------------------------------------------------------------------------

function SettingsUI:RegisterGameOptions()
    if self.optionsPanel then return end

    local panel = CreateFrame("Frame")
    panel.name = TITLE

    local title = Theme.CreateLabel(panel, "title", "accent")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(TITLE)

    local blurb = Theme.CreateLabel(panel, "normal", "text")
    blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    blurb:SetText(L["Butler's settings have a window of their own."])

    local open = Widgets.CreateButton(panel, L["Open Butler settings"], function()
        -- The game's panel is left as it is: hiding a stock frame runs the
        -- game's own code as this addon and taints it (Equipment's Edit
        -- Mode error, 2026-10-10). Butler's window is top level in the dialog
        -- layer, so it comes up over the panel.
        SettingsUI:Show()
    end, { width = 190, height = 24 })
    open:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -14)

    local hint = Theme.CreateLabel(panel, "small", "muted")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
    hint:SetText(L["Or type /bbutler settings, or click the minimap button."])

    self.optionsPanel = panel

    local registered = false

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        registered = pcall(function()
            local category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
            Settings.RegisterAddOnCategory(category)
            SettingsUI.optionsCategory = category
        end)
    end

    -- The older options API, in case this client still has it instead.
    if not registered and type(InterfaceOptions_AddCategory) == "function" then
        registered = pcall(InterfaceOptions_AddCategory, panel)
    end

    if not registered then
        ns.Debug("no game options panel to register with; /bbutler settings still works")
    end

    return registered
end

function SettingsUI:OnEnable()
    local ok, err = pcall(self.RegisterGameOptions, self)
    if not ok then
        ns.Debug("could not add Butler to the game's options:", tostring(err))
    end
end

ns.RegisterCommand("settings", L["open the settings window"], function()
    SettingsUI:Toggle()
end)

-- Common names for the same thing, so a guess works. Kept out of the help
-- list, which would otherwise print the same line three times.
ns.commands.options = ns.commands.settings
ns.commands.config = ns.commands.settings
