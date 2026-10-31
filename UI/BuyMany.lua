-- Blackthornes Butler -- UI/BuyMany.lua
-- The Buy more box: any amount of a vendor item at once (the owner asked
-- 2026-10-14). Logic/BuyMany.lua plans and buys; this draws the box.
--
-- Shift-click an item at a vendor and the box comes up beside the vendor
-- window with that item, a box for how many, what that comes to and a Buy
-- button. Nothing is spent until Buy is clicked, and the box says first
-- when the bags, the purse or the vendor's stock allow fewer. While it
-- buys, Buy turns into Stop. `/bbutler buy 200 water` opens it too.
--
-- How it hears the click without touching the game's frames: each of the
-- vendor's item buttons gets a HookScript("OnClick"), which runs after the
-- game's own click and writes nothing on the button. A Shift-click that
-- links the item into chat (a chat box open) is left alone. The box is
-- Butler's own frame on UIParent, only anchored beside MerchantFrame.

local _, ns = ...
local L = ns.L

local BuyManyUI = ns.NewModule("BuyManyUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local BuyMany = ns.BuyMany

local WIDTH, HEIGHT = 280, 196
local PAD = 18
local BOX_WIDTH = 70
local MAX_BUTTONS = 12

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

local function ShiftDown()
    local fn = rawget(_G, "IsShiftKeyDown")
    return type(fn) == "function" and fn() and true or false
end

-- A chat box is open, so Shift-click links the item instead.
local function ChatOpen()
    local window = ns.Items.Call({ "ChatFrameUtil.GetActiveWindow", "ChatEdit_GetActiveWindow" })
    return window ~= nil
end

--------------------------------------------------------------------------------
-- The box
--------------------------------------------------------------------------------

function BuyManyUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesButlerBuyMany", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    Theme.Fill(frame, "window")
    if ns.Titanforged then
        self.trim = ns.Titanforged:Dress(frame, {
            title = L["Buy more"],
            close = function() BuyManyUI:Hide() end,
        })
    else
        Theme.Border(frame, "borderLit")
    end

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", PAD, -30)
    self.icon = icon

    local name = Theme.CreateLabel(frame, "normal", "text")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
    name:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    name:SetHeight(32)
    name:SetWordWrap(true)
    self.name = name

    local ask = Theme.CreateLabel(frame, "normal", "muted")
    ask:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -14)
    ask:SetText(L["How Many:"])

    local box = Widgets.CreateSearchBox(frame, "", function() BuyManyUI:Replan() end,
        function() BuyManyUI:Buy() end, { plain = true })
    box:SetWidth(BOX_WIDTH)
    box:SetPoint("LEFT", ask, "RIGHT", 10, 0)
    local edit = box.editBox
    edit:SetMaxLetters(4)
    edit:SetJustifyH("RIGHT")
    if edit.SetNumeric then edit:SetNumeric(true) end
    edit:SetScript("OnEscapePressed", function() BuyManyUI:Hide() end)
    self.box = box

    local total = Theme.CreateLabel(frame, "normal", "text")
    total:SetPoint("LEFT", box, "RIGHT", 10, 0)
    total:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    self.total = total

    local note = Theme.CreateLabel(frame, "small", "muted")
    note:SetPoint("TOPLEFT", ask, "BOTTOMLEFT", 0, -14)
    note:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    note:SetHeight(40)
    note:SetWordWrap(true)
    note:SetJustifyV("TOP")
    self.note = note

    local buy = Widgets.CreateButton(frame, L["Buy"], function() BuyManyUI:Buy() end,
        { width = 110, height = 24, primary = true })
    buy:SetPoint("BOTTOMRIGHT", -PAD, PAD - 4)
    self.buyButton = buy

    local cancel = Widgets.CreateButton(frame, L["Cancel"], function() BuyManyUI:Hide() end,
        { width = 90, height = 24 })
    cancel:SetPoint("RIGHT", buy, "LEFT", -8, 0)
    self.cancelButton = cancel

    frame:SetScript("OnHide", function()
        if BuyMany:Running() then BuyMany:Stop("player") end
    end)

    self.frame = frame
    return frame
end

--- The one window, when it sits beside the vendor, else nil.
local function DockedHere()
    local shared = ns.SharedWindow
    if not (shared and shared.DockedFrame and shared.Place) then return nil end
    local ok, place = pcall(shared.Place)
    if not ok or place ~= "vendor" then return nil end
    local okFrame, docked = pcall(shared.DockedFrame)
    if okFrame then return docked end
    return nil
end

--- Beside the vendor window (past the one window when it sits there),
--- else in the middle.
function BuyManyUI:Place()
    local frame = self.frame
    frame:ClearAllPoints()
    local merchant = rawget(_G, "MerchantFrame")
    local docked = DockedHere()
    if docked then
        frame:SetPoint("TOPLEFT", docked, "TOPRIGHT", 12, -24)
    elseif type(merchant) == "table" and Ask(merchant, "IsShown") then
        frame:SetPoint("TOPLEFT", merchant, "TOPRIGHT", 12, -24)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
    self:WatchWindow()
end

--- Place the box again when the one window docks or goes back, once.
function BuyManyUI:WatchWindow()
    local shared = ns.SharedWindow
    if self.watching or not (shared and shared.Watch) then return end
    self.watching = true
    shared.Watch(function()
        if BuyManyUI.frame and Ask(BuyManyUI.frame, "IsShown") then BuyManyUI:Place() end
    end)
end

--- Open the box for the vendor's item at `index`, with `amount` filled in
--- when given. `force` opens it with the Shift-click box turned off (the
--- typed command).
function BuyManyUI:Open(index, amount, force)
    if not (force or BuyMany:IsOn()) or BuyMany:Running() then return false end
    local item = BuyMany.Item(index)
    if not item then return false end
    self:Build()
    self.index = index
    self.itemID = item.itemID
    self.icon:SetTexture(item.icon or 134400)
    self.name:SetText(item.name and ns.Items:ColorName(item.name, item.itemID) or "")
    self.box:SetText(amount and tostring(amount) or "")
    self:Place()
    self.frame:Show()
    self.box:SetFocus()
    self:Replan()
    return true
end

function BuyManyUI:Hide()
    if self.frame then self.frame:Hide() end
end

function BuyManyUI:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

--- Work the plan out again from what is typed (each keystroke; one read
--- of the bags, no timer).
function BuyManyUI:Replan()
    if not self:IsShown() or BuyMany:Running() then return end
    local plan = BuyMany:Plan(self.index, self.box:GetText())
    if plan and plan.item.itemID ~= self.itemID then plan = nil end
    self.plan = plan
    if not plan then
        self.total:SetText("")
        self:FitTotal("")
        self.note:SetText(L["The vendor's list changed. Shift-click the item again."])
        self:SetBuyEnabled(false)
        return
    end
    local main, note = BuyMany.Describe(plan)
    self.total:SetText(main)
    self:FitTotal(main)
    self.note:SetText(note)
    self.buyButton:SetText(L["Buy"])
    self:SetBuyEnabled(plan.state == "buy")
end

--- Grow the box so the whole price shows beside the amount, measured as
--- the game draws it: the font runs wider than any width picked by eye.
function BuyManyUI:FitTotal(text)
    local need = PAD + Theme.TextWidth("normal", L["How Many:"]) + 10 + BOX_WIDTH + 10
        + Theme.TextWidth("normal", text or "") + 4 + PAD
    self.frame:SetWidth(math.max(WIDTH, math.ceil(need)))
end

function BuyManyUI:SetBuyEnabled(on)
    local button = self.buyButton
    if on then button:Enable() else button:Disable() end
    button:SetAlpha(on and 1 or 0.45)
end

--- The Buy button (or Enter in the box), and Stop while it buys.
function BuyManyUI:Buy()
    if BuyMany:Running() then
        BuyMany:Stop("player")
        return
    end
    self:Replan()
    local plan = self.plan
    if not (plan and plan.state == "buy") then return end
    self.box:ClearFocus()
    self.buyButton:SetText(L["Stop"])
    self.note:SetText(L.Format("Buying %s...", ns.Ammo.Thousands(plan.count)))
    BuyMany:Start(plan, function()
        BuyManyUI:Hide()
    end)
end

--------------------------------------------------------------------------------
-- The vendor's item buttons
--------------------------------------------------------------------------------

--- A click on one of the vendor's items, after the game's own.
function BuyManyUI:Clicked(button, mouseButton)
    if not BuyMany:IsOn() or not ShiftDown() or ChatOpen() then return end
    if mouseButton and mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then return end
    -- The Buyback tab's items are not for sale.
    local merchant = rawget(_G, "MerchantFrame")
    local tab = Field(merchant, "selectedTab")
    if type(tab) == "number" and tab ~= 1 then return end
    local index = Ask(button, "GetID")
    if type(index) == "number" and index > 0 then self:Open(index) end
end

--- Hear clicks on the vendor's item buttons: hooks only, once each.
function BuyManyUI:InstallHooks()
    self.hooked = self.hooked or {}
    local count = tonumber(rawget(_G, "MERCHANT_ITEMS_PER_PAGE")) or 10
    for i = 1, math.max(count, MAX_BUTTONS) do
        local button = rawget(_G, ("MerchantItem%dItemButton"):format(i))
        if type(button) == "table" and not self.hooked[button] and type(Field(button, "HookScript")) == "function" then
            self.hooked[button] = true
            pcall(button.HookScript, button, "OnClick", function(clicked, mouseButton)
                BuyManyUI:Clicked(clicked, mouseButton)
            end)
        end
    end
end

function BuyManyUI:OnEnable()
    ns.RegisterEvent(self, "MERCHANT_SHOW", function() BuyManyUI:InstallHooks() end)
    ns.RegisterEvent(self, "MERCHANT_CLOSED", function() BuyManyUI:Hide() end)
    -- The bags or the purse moved under an open box.
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function() BuyManyUI:Replan() end)
    ns.RegisterEvent(self, "PLAYER_MONEY", function() BuyManyUI:Replan() end)
end

--- One line for /bbutler probe.
function BuyManyUI:ProbeText()
    local hooked = 0
    for _ in pairs(self.hooked or {}) do hooked = hooked + 1 end
    local found = 0
    for i = 1, MAX_BUTTONS do
        if type(rawget(_G, ("MerchantItem%dItemButton"):format(i))) == "table" then found = found + 1 end
    end
    return ("%s; %d vendor item buttons found, %d hooked; BuyMerchantItem %s, GetMerchantItemMaxStack %s"):format(
        BuyMany:IsOn() and "on" or "off", found, hooked,
        ns.Items.Resolve("BuyMerchantItem") and "found" or "MISSING",
        ns.Items.Resolve("GetMerchantItemMaxStack") and "found" or "MISSING")
end

--------------------------------------------------------------------------------
-- /bbutler buy
--------------------------------------------------------------------------------

ns.RegisterCommand("buy", L["on or off: the Buy more box on Shift-click at a vendor; or an amount and a name, like buy 200 water"], function(rest)
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local word = rest:lower()
    if word == "" or word == "on" or word == "off" then
        local on
        if word == "" then on = not BuyMany:IsOn() else on = word == "on" end
        BuyMany:SetOn(on)
        ns.Print(on and L["Shift-click an item at a vendor to buy any amount of it."]
            or L["Shift-click at a vendor works as the game's own again."])
        return
    end
    local amount, text = rest:match("^(%d+)%s+(.+)$")
    if not amount then
        text, amount = rest:match("^(.-)%s+(%d+)$")
    end
    if not (amount and text) then
        ns.Print(L["Type an amount and a name, like /bbutler buy 200 water."])
        return
    end
    if not (ns.Selling and ns.Selling:MerchantOpen(true)) then
        ns.Print(L["Talk to a vendor first."])
        return
    end
    local item = BuyMany.Find(text)
    if not item then
        ns.Print(L.Format("This vendor doesn't sell anything called %s.", text))
        return
    end
    BuyManyUI:Open(item.index, tonumber(amount), true)
end)
