-- Blackthornes Butler -- UI/KeepAcross.lua
-- The Keep Across Characters box (the owner said build it from a mockup,
-- 2026-11-07): the right-click menu's "Keep Across Characters..." and the
-- Settings section's Add Item open it. Logic/KeepAcross.lua keeps the
-- number; nothing is saved until Save.
--
-- From the menu it names the item. From Add Item it asks for one first:
-- the item held on the cursor, else a name, an item ID or a Shift-clicked
-- link typed in the Item: box, found in the bags or by the client.

local _, ns = ...
local L = ns.L

local KeepAcrossUI = ns.NewModule("KeepAcrossUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Items = ns.Items

local WIDTH = 290
local PAD = 18
local BOX_WIDTH = 80

--------------------------------------------------------------------------------
-- Finding an item
--------------------------------------------------------------------------------

--- An item's name: the client's, else a bag copy's link, else "Item N".
function KeepAcrossUI.ItemName(itemID)
    local name = Items.Call({ "C_Item.GetItemNameByID", "GetItemInfo" }, itemID)
    if type(name) == "string" and name ~= "" then return name end
    for _, entry in pairs(ns.Bags and ns.Bags.slots or {}) do
        if entry.itemID == itemID then
            local fromLink = Items.NameFromLink(entry.link)
            if fromLink then return fromLink end
        end
    end
    return L.Format("Item %d", itemID)
end

--- The item ID a typed line names (an ID, a link, or a name in the bags or
--- known to the client), or nil.
function KeepAcrossUI.Find(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local id = tonumber(text) or tonumber(text:match("item:(%d+)"))
    if id and id > 0 then return math.floor(id) end
    local wanted = (Items.NameFromLink(text) or text):lower()
    for _, entry in pairs(ns.Bags and ns.Bags.slots or {}) do
        local name = Items.NameFromLink(entry.link)
        if name and name:lower() == wanted then return entry.itemID end
    end
    local found = Items.Call({ "C_Item.GetItemInfoInstant", "GetItemInfoInstant" }, text)
    found = tonumber(found)
    if found and found > 0 then return found end
    return nil
end

--- The item held on the cursor, or nil.
function KeepAcrossUI.Cursor()
    local kind, itemID = Items.Call({ "GetCursorInfo" })
    if kind == "item" and tonumber(itemID) then return tonumber(itemID) end
    return nil
end

--------------------------------------------------------------------------------
-- The box
--------------------------------------------------------------------------------

function KeepAcrossUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesButlerKeepAcross", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    Theme.Fill(frame, "window")
    if ns.Titanforged then
        ns.Titanforged:Dress(frame, {
            title = L["Keep Across Characters"],
            close = function() KeepAcrossUI:Hide() end,
        })
    else
        Theme.Border(frame, "borderLit")
    end

    -- Add Item asks for the item first.
    local itemLabel = Theme.CreateLabel(frame, "normal", "muted")
    itemLabel:SetText(L["Item:"])
    self.itemLabel = itemLabel
    local itemBox = Widgets.CreateSearchBox(frame, "", function() KeepAcrossUI:Typed() end,
        function() KeepAcrossUI:Save() end, { plain = true })
    itemBox:SetPoint("LEFT", itemLabel, "RIGHT", 10, 0)
    itemBox:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    itemBox:SetHeight(24)
    itemBox.editBox:SetScript("OnEscapePressed", function() KeepAcrossUI:Hide() end)
    self.itemBox = itemBox

    local name = Theme.CreateLabel(frame, "normal", "text")
    name:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    name:SetWordWrap(true)
    self.name = name

    local ask = Theme.CreateLabel(frame, "normal", "muted")
    ask:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -14)
    ask:SetText(L["Keep In All:"])
    self.ask = ask

    local box = Widgets.CreateSearchBox(frame, "", nil, function() KeepAcrossUI:Save() end, { plain = true })
    box:SetSize(BOX_WIDTH, 24)
    box:SetPoint("LEFT", ask, "RIGHT", 10, 0)
    local edit = box.editBox
    edit:SetMaxLetters(4)
    edit:SetJustifyH("RIGHT")
    if edit.SetNumeric then edit:SetNumeric(true) end
    edit:SetScript("OnEscapePressed", function() KeepAcrossUI:Hide() end)
    self.box = box

    local all = Widgets.CreateButton(frame, L["Keep All"], function() KeepAcrossUI:Save(true) end,
        { height = 24 })
    all:SetPoint("LEFT", box, "RIGHT", 8, 0)
    self.allButton = all

    local bank = Widgets.CreateCheckbox(frame, L["Count Bank:"], function(checked)
        if ns.KeepAcross then ns.KeepAcross:SetCountsBank(checked) end
    end)
    bank:SetPoint("TOPLEFT", ask, "BOTTOMLEFT", 0, -16)
    self.bankBox = bank

    local save = Widgets.CreateButton(frame, L["Save"], function() KeepAcrossUI:Save() end,
        { width = 100, height = 24, primary = true })
    save:SetPoint("BOTTOMRIGHT", -PAD, PAD - 4)
    self.saveButton = save

    local cancel = Widgets.CreateButton(frame, L["Cancel"], function() KeepAcrossUI:Hide() end,
        { width = 90, height = 24 })
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
    self.cancelButton = cancel

    self.frame = frame
    return frame
end

--- Lay the box out for a known item, or for asking which one.
function KeepAcrossUI:Layout()
    local asking = self.asking
    self.itemLabel:SetShown(asking)
    self.itemBox:SetShown(asking)
    self.itemLabel:ClearAllPoints()
    self.itemLabel:SetPoint("TOPLEFT", PAD, -32)
    self.name:ClearAllPoints()
    if asking then
        self.name:SetPoint("TOPLEFT", self.itemLabel, "BOTTOMLEFT", 0, -14)
    else
        self.name:SetPoint("TOPLEFT", PAD, -32)
    end
    self.name:SetPoint("RIGHT", self.frame, "RIGHT", -PAD, 0)
    self.frame:SetHeight(asking and 214 or 176)
end

--- Show the item picked (coloured by quality), and the number kept now.
function KeepAcrossUI:ShowItem(itemID, title)
    self.itemID = itemID
    if not itemID then
        self.name:SetText("")
        self.box:SetText("")
        if self.saveButton.SetEnabled then self.saveButton:SetEnabled(false) end
        if self.allButton.SetEnabled then self.allButton:SetEnabled(false) end
        return
    end
    title = title or Items:ColorName(self.ItemName(itemID), itemID)
    self.name:SetText(title or "")
    local count = ns.KeepAcross and ns.KeepAcross:Count(itemID)
    self.box:SetText(count and not ns.KeepHere.IsAll(count) and tostring(count) or "")
    if self.saveButton.SetEnabled then self.saveButton:SetEnabled(true) end
    if self.allButton.SetEnabled then self.allButton:SetEnabled(true) end
end

--- The Item: box changed: show the item it names, if any.
function KeepAcrossUI:Typed()
    if not self.asking then return end
    self:ShowItem(self.Find(self.itemBox.editBox:GetText()))
end

--- Open the box for `itemID` (the menu), or with none to ask which item
--- (Add Item, which takes the item held on the cursor first).
function KeepAcrossUI:Open(itemID, title)
    if not ns.KeepAcross then return false end
    self:Build()
    if not itemID then
        itemID = self.Cursor()
        if itemID then Items.Call({ "ClearCursor" }) end
    end
    self.asking = itemID == nil
    self:Layout()
    self.itemBox:SetText("")
    self:ShowItem(itemID, title)
    if self.bankBox.SetChecked then self.bankBox:SetChecked(ns.KeepAcross:CountsBank()) end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    self.frame:Show()
    if self.asking then
        if self.itemBox.editBox.SetFocus then self.itemBox.editBox:SetFocus() end
    elseif self.box.editBox.SetFocus then
        self.box.editBox:SetFocus()
    end
    return true
end

--- Save the number (Keep All saves every one; 0 or empty takes it off).
function KeepAcrossUI:Save(all)
    local itemID = self.itemID
    if not itemID or not ns.KeepAcross then return end
    local count = all and ns.KeepHere.MOST or (tonumber(self.box.editBox:GetText()) or 0)
    ns.KeepAcross:Set(itemID, count)
    self:Hide()
end

function KeepAcrossUI:Hide()
    if self.frame then self.frame:Hide() end
end
