-- Blackthornes Butler -- Logic/Selling.lua
-- The Sell button: sells the Sell group at a vendor, and nothing else.
--
-- The rules from the plan:
--   * Nothing leaves the bags without the player's click. No auto-sell.
--   * Only rows judged Sell are sold (greys, the Always sell list, items
--     worth less than the player's Sell below amount, and what a vendor pays
--     most for).
--     Keep and Look at it rows never are.
--   * Every slot is read again just before its sale: it must still hold the
--     same item, unlocked, or it is left alone.
--   * At most 12 a click, which is what the vendor's Buyback tab holds, so
--     every sale of that click can be bought back.
--
-- Selling is using a bag item with a vendor open, and the Warcraft Wiki marks
-- C_Container.UseContainerItem as protected on current retail. So, as
-- Tradeskills' Sell marked button does (2026-10-07), the button is a secure
-- one, and each click sells one stack through a "/use bag slot" line set
-- just before the click runs, only while a vendor is open. If the game lets
-- addon code sell, one click sells the next 12. There is no Test button
-- (the owner, 2026-10-23): after the first click sells a stack, Butler
-- quietly sells the next one from addon code and keeps what happened
-- (`Selling:QuietTest`); /bbutler selltest still runs the old check.
--
-- The secure button sits inside the Butler window out of combat
-- (UI:Dock), on the Sell line or at the window's foot, and goes back to
-- UIParent as a fight starts, so the window stays free to move and close
-- in combat. It is hidden in combat, where nothing is sold anyway.

local _, ns = ...
local L = ns.L

local Selling = ns.NewModule("Selling")

local Items = ns.Items
local Bags = ns.Bags

-- What the vendor's Buyback tab holds.
Selling.BATCH = 12
-- The pause between sales when one click sells several.
Selling.GAP = 0.3
-- How long after the first click's sale the quiet check waits.
Selling.QUIET_WAIT = 1

-- What Butler's button sold this visit, [itemID] = true: a buyback of one
-- teaches Butler to keep it (Logic/Learning.lua).
Selling.soldIDs = {}

local BUTTON_WIDTH = 150
local BUTTON_HEIGHT = 24

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

--- Is a vendor's window open? MERCHANT_SHOW and MERCHANT_CLOSED say so.
--- `strict`, asked just before a sale, also wants the game's vendor window
--- on screen (read only), since a "/use" away from a vendor would use or
--- equip the item instead. Not asked when the event arrives, which can come
--- before the game has shown its window.
function Selling:MerchantOpen(strict)
    if not self.merchantOpen then return false end
    if not strict then return true end
    local frame = rawget(_G, "MerchantFrame")
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return true end
    local ok, shown = pcall(frame.IsShown, frame)
    return not ok or shown == true
end

--- What the selling test found: "works", "blocked", or nil when not run.
function Selling:TestResult()
    local test = ns.db and ns.db.sellTest
    return type(test) == "table" and test.result or nil, type(test) == "table" and test.at or nil
end

--- One click sells up to 12 from addon code, rather than a stack a click?
function Selling:CanSellBatch()
    return self:TestResult() == "works" and Items.Resolve("C_Container.UseContainerItem") ~= nil
end

--------------------------------------------------------------------------------
-- What to sell
--------------------------------------------------------------------------------

--- The Sell group's slots that can be sold now, in the order they go: up
--- to `limit` of them, each { bag, slot, itemID, name, count, unit }.
function Selling:Queue(limit)
    local queue = {}
    local group = ns.Verdicts:Group("sell")
    if not group then return queue end
    for _, row in ipairs(group.rows) do
        for _, entry in ipairs(row.slots) do
            if #queue >= (limit or math.huge) then return queue end
            if not entry.locked then
                queue[#queue + 1] = {
                    bag = entry.bag, slot = entry.slot, itemID = entry.itemID,
                    name = row.name, count = entry.count, unit = row.unit,
                }
            end
        end
    end
    return queue
end

--- The next stack to sell that the bags still hold, or nil.
--- Does the slot still hold this item, unlocked, and is it still under
--- Sell? Read and judged again just before a sale: the same item ID can
--- be another copy now (an upgrade "of the Eagle" put where a "of the
--- Monkey" was), or a choice changed since the list was drawn.
local function StillSell(item)
    if not Bags.Holds(item.bag, item.slot, item.itemID) then return false end
    local entry = Bags.ReadSlot(item.bag, item.slot)
    if not entry then return false end
    entry.quest = Bags.ReadQuest(item.bag, item.slot, item.itemID)
    return ns.Verdicts:VerdictOf(entry) == "sell"
end

function Selling:Next()
    for _, item in ipairs(self:Queue()) do
        if StillSell(item) then return item end
    end
end

--- Sell one stack from addon code. True when the game took the call.
local function SellOne(item)
    if not StillSell(item) then return false end
    local fn = Items.Resolve("C_Container.UseContainerItem")
    return fn ~= nil and pcall(fn, item.bag, item.slot)
end

--- Sell up to 12 from addon code, one every Selling.GAP seconds. Only once
--- the selling test showed the game allows it.
function Selling:SellBatch()
    if self.selling then return end
    local queue = self:Queue(self.BATCH)
    if #queue == 0 then return end

    self.selling = true
    -- A run of its own: a vendor closed and opened again before the next
    -- step must not let this one go on beside a new one (more than 12
    -- would sell, past what the Buyback tab holds).
    self.run = (self.run or 0) + 1
    local run = self.run
    self:Update()
    local index = 0

    local function Step()
        if Selling.run ~= run then return end
        index = index + 1
        local item = queue[index]
        if not item or not Selling:MerchantOpen(true) or InCombat() then
            Selling.selling = false
            Selling:Update()
            return
        end
        if SellOne(item) then
            Selling.soldIDs[item.itemID] = true
            Selling.sold = (Selling.sold or 0) + 1
            Selling.soldWorth = (Selling.soldWorth or 0) + (item.unit or 0) * (item.count or 1)
        end
        C_Timer.After(Selling.GAP, Step)
    end

    Step()
end

--------------------------------------------------------------------------------
-- The button
--------------------------------------------------------------------------------

function Selling:Create()
    if self.button then return self.button end

    -- The main action, so a gold face with dark ink lettering (the game's
    -- red in the Blizzard style), built on the game's secure template and
    -- given no OnClick of its own: the template's is what sells.
    local button = ns.Widgets.CreateButton(UIParent, L["Sell"], nil, {
        name = "BlackthornesButlerSell", template = "SecureActionButtonTemplate",
        primary = true, width = BUTTON_WIDTH, height = BUTTON_HEIGHT,
    })
    button:Hide()
    -- Inside the window out of combat (UI:Dock), so it comes to the front
    -- with it and a window in front covers it too.
    button:SetFrameStrata("DIALOG")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)

    button:HookScript("OnEnter", function(frame)
        if frame.tooltipText then
            GameTooltip:SetOwner(frame, "ANCHOR_TOP")
            GameTooltip:SetText(frame.tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Last look before the secure action runs: a vendor must still be open
    -- and the slot must still hold a Sell item, or nothing is used.
    button:SetScript("PreClick", function(frame)
        frame.batch = nil
        frame.pending = nil
        if InCombat() then return end

        if not Selling:MerchantOpen(true) or Selling.selling then
            frame:SetAttribute("type", nil)
            return
        end

        if Selling:CanSellBatch() then
            frame:SetAttribute("type", nil)
            frame.batch = true
            return
        end

        local item = Selling:Next()
        if not item then
            frame:SetAttribute("type", nil)
            return
        end
        frame:SetAttribute("type", "macro")
        frame:SetAttribute("macrotext", ("/use %d %d"):format(item.bag, item.slot))
        frame.pending = item
    end)

    button:SetScript("PostClick", function(frame)
        if rawget(frame, "batch") == true then
            frame.batch = nil
            Selling:SellBatch()
            return
        end

        local item = rawget(frame, "pending")
        frame.pending = nil
        -- Nothing is left aimed at a slot between clicks.
        if not InCombat() then
            frame:SetAttribute("type", nil)
            frame:SetAttribute("macrotext", nil)
        end
        if item then
            Selling.soldIDs[item.itemID] = true
            Selling.sold = (Selling.sold or 0) + 1
            Selling.soldWorth = (Selling.soldWorth or 0) + (item.unit or 0) * (item.count or 1)
            if Selling:TestResult() == nil then
                -- Once the click's own sale has settled.
                C_Timer.After(Selling.QUIET_WAIT, function() Selling:QuietTest(item) end)
            end
        end
        Selling:Update()
    end)

    self.button = button
    return button
end

--- Words for the button and its tooltip, for what the Sell group holds now.
function Selling:Words()
    local group = ns.Verdicts:Group("sell")
    local queue = self:Queue()
    local count = #queue
    local worth = 0
    for _, item in ipairs(queue) do worth = worth + (item.unit or 0) * (item.count or 1) end

    local text
    if self.selling then
        text = L["Selling..."]
    elseif count == 0 then
        text = L["Nothing to sell"]
    elseif self:CanSellBatch() then
        local n = math.min(count, self.BATCH)
        text = (self.sold or 0) > 0 and L.Format("Sell next %d", n) or L.Format("Sell %d", n)
    else
        local item = queue[1]
        text = L.Format("Sell %s", item.name)
        if (item.count or 1) > 1 then text = L.Format("%s x%d", text, item.count) end
    end

    local lines = {}
    lines[#lines + 1] = count == 1
        and L.Format("Sells what Butler put under Sell: %d stack, %s in all.", count, Items.FormatMoney(worth))
        or L.Format("Sells what Butler put under Sell: %d stacks, %s in all.", count, Items.FormatMoney(worth))
    if self:CanSellBatch() then
        lines[#lines + 1] = L["Each click sells up to 12. You can buy them back from the vendor's Buyback tab."]
    else
        lines[#lines + 1] = L["Each click sells one stack. You can buy back the last 12 from the vendor's Buyback tab."]
    end
    lines[#lines + 1] = L["Never sells anything under Keep or Look at it."]
    if (self.sold or 0) > 0 then
        lines[#lines + 1] = L.Format("Sold here so far: %d, %s.", self.sold, Items.FormatMoney(self.soldWorth or 0))
    end
    return text, table.concat(lines, "\n"), count, group
end

--- Where the button goes: over the Butler window's foot, right side.
function Selling:Place()
    local button, window = self.button, ns.UI and ns.UI.frame
    if not (button and window) or InCombat() then return false end
    -- On the Sell group's line while it is on screen (the owner asked
    -- 2026-10-12), else at the window's foot.
    local row = ns.UI:HeaderRow("sell")
    self.onLine = row ~= nil and ns.UI.PlaceOnLine(button, row)
    if self.onLine then return true end
    if not ns.UI:Dock(button) then return false end
    button:ClearAllPoints()
    button:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -ns.UI.SELL_INSET_X, ns.UI.SELL_INSET_Y)
    return true
end

--- Show, hide and word the button for what is under Sell now. Shown only at
--- a vendor, out of combat, while the Butler window is up and not moving.
function Selling:Update()
    local button = self.button
    local show = self:MerchantOpen() and not InCombat()
        and ns.UI and ns.UI:IsShown() and not ns.UI.dragging and ns.UI.view ~= "all"

    if not show then
        if button and not InCombat() then button:Hide() end
        if ns.UI then ns.UI:SellShown(false) end
        return
    end

    button = self:Create()
    local text, tip, count = self:Words()
    button:SetText(text)
    button.tooltipText = tip

    if count == 0 or not self:Place() then
        button:Hide()
        ns.UI:SellShown(false)
        return
    end
    button:Show()
    ns.UI:SellShown(true, not self.onLine and button:GetWidth() or nil)
end

--------------------------------------------------------------------------------
-- The selling test
--------------------------------------------------------------------------------

--- The cheapest grey in the bags, to test with.
local function CheapestGrey()
    local best
    for _, entry in pairs(Bags.slots) do
        if entry.quality == 0 and not entry.locked and not entry.quest then
            local unit = Items:SellPrice(entry.itemID) or 0
            local worth = unit * entry.count
            if unit > 0 and (not best or worth < best.worth) then
                best = { bag = entry.bag, slot = entry.slot, itemID = entry.itemID,
                    link = entry.link, worth = worth }
            end
        end
    end
    return best
end

--- Sell the cheapest grey from addon code and keep whether the game let it.
function Selling:Test()
    if not self:MerchantOpen(true) then
        ns.Print(L["open a vendor first, then run this again. It sells your cheapest grey item to see whether the game lets Butler sell."])
        return
    end
    local use = Items.Resolve("C_Container.UseContainerItem")
    if not use then
        ns.Print(L["this version of the game has no C_Container.UseContainerItem."])
        return
    end

    Bags:Fresh(function()
        local grey = CheapestGrey()
        if not grey then
            ns.Print(L["no grey item in your bags to test with. Carry one and try again."])
            return
        end

        local before = type(GetMoney) == "function" and GetMoney() or 0
        ns.Print(L.Format("trying to sell %s (%s) from addon code...", grey.link or L["a grey item"],
            Items.FormatMoney(grey.worth)))
        Selling.testing = true
        local called, err = pcall(use, grey.bag, grey.slot)
        Selling.testing = false

        C_Timer.After(1, function()
            local still = Bags.ReadSlot(grey.bag, grey.slot)
            local gone = not (still and still.itemID == grey.itemID)
            local gained = (type(GetMoney) == "function" and GetMoney() or 0) > before
            local works = called and gone and gained

            ns.db.sellTest = { at = time(), result = works and "works" or "blocked",
                error = (not called and err) and tostring(err):sub(1, 120) or nil }

            if works then
                ns.Print(L["|cff4fd18bselling from Butler works|r: the Sell button now sells up to 12 a click."])
            else
                ns.Print(L.Format("|cffe5604fselling from Butler is blocked|r (%s). The Sell button stays at one stack a click.",
                    not called and L["the game refused the call"] or not gone and L["the item stayed"] or L["no gold came in"]))
            end
            Selling:Update()
        end)
    end)
end

--- After a click sold a stack, sell the next Sell stack from addon code
--- and keep whether the game let it, so later clicks sell up to 12. Says
--- nothing: the button's words change when it works.
function Selling:QuietTest(clicked)
    if self:TestResult() ~= nil or self.selling or InCombat() then return end
    if not self:MerchantOpen(true) then return end
    local use = Items.Resolve("C_Container.UseContainerItem")
    if not use then return end
    local item
    for _, candidate in ipairs(self:Queue()) do
        local same = clicked and candidate.bag == clicked.bag and candidate.slot == clicked.slot
        if not same and StillSell(candidate) then
            item = candidate
            break
        end
    end
    if not item then return end

    local before = type(GetMoney) == "function" and GetMoney() or 0
    Selling.testing = true
    local called, err = pcall(use, item.bag, item.slot)
    Selling.testing = false

    C_Timer.After(1, function()
        local still = Bags.ReadSlot(item.bag, item.slot)
        local gone = not (still and still.itemID == item.itemID)
        local gained = (type(GetMoney) == "function" and GetMoney() or 0) > before
        local works = called and gone and gained
        if Selling:TestResult() ~= nil then return end
        ns.db.sellTest = { at = time(), result = works and "works" or "blocked", quiet = true,
            error = (not called and err) and tostring(err):sub(1, 120) or nil }
        if gone then
            Selling.soldIDs[item.itemID] = true
            Selling.sold = (Selling.sold or 0) + 1
            Selling.soldWorth = (Selling.soldWorth or 0) + (item.unit or 0) * (item.count or 1)
        end
        Selling:Update()
    end)
end

--- One line for /bbutler probe.
function Selling:ProbeText()
    local result = self:TestResult()
    if result == "works" then return "works: up to 12 a click" end
    if result == "blocked" then return "blocked: one stack a click" end
    return "not tested: the second stack a Sell click sells checks it, or /bbutler selltest"
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

--- The vendor closed. Said twice when the client sends both
--- MERCHANT_CLOSED and the interaction ending; the second does nothing.
function Selling:LeftVendor()
    if not self.merchantOpen and not (ns.UI and ns.UI.openedByVendor) then return end
    self.merchantOpen = false
    self.selling = false
    self.run = (self.run or 0) + 1
    local button = self.button
    if button and not InCombat() then
        button:SetAttribute("type", nil)
        button:SetAttribute("macrotext", nil)
        button:Hide()
    end
    if ns.UI then ns.UI:LeftVendor() end
end

--- True for the game's Merchant interaction type.
function Selling.IsMerchant(kind)
    local types = rawget(_G, "Enum") and rawget(Enum, "PlayerInteractionType")
    local merchant = type(types) == "table" and rawget(types, "Merchant") or 5
    return kind ~= nil and kind == merchant
end

function Selling:OnEnable()
    ns.RegisterEvent(self, "MERCHANT_SHOW", function()
        Selling.merchantOpen = true
        Selling.sold, Selling.soldWorth = 0, 0
        Selling.soldIDs = {}
        Selling.visit = (Selling.visit or 0) + 1
        local visit = Selling.visit
        Bags:Fresh(function()
            -- The bags can take a few frames to read. A vendor closed in the
            -- meantime (or another one opened) must not bring the window up
            -- after the player walked away (a player's report, 2026-11-01).
            if not Selling.merchantOpen or Selling.visit ~= visit then return end
            if ns.UI then ns.UI:AtVendor() end
            Selling:Update()
        end)
    end)

    ns.RegisterEvent(self, "MERCHANT_CLOSED", function() Selling:LeftVendor() end)

    -- Forever can end the vendor's interaction without MERCHANT_CLOSED, as
    -- it does for the mailbox and bank (see Errands); heard as well.
    ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, _, kind)
        if Selling.IsMerchant(kind) then Selling:LeftVendor() end
    end)

    -- Fires just before combat locks secure frames, so the button can still
    -- be hidden.
    ns.RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
        if Selling.button then Selling.button:Hide() end
        if ns.UI then ns.UI:SellShown(false) end
    end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function() Selling:Update() end)
end

-- Typed only (the owner, 2026-10-23): the first Sell click checks by itself.
ns.RegisterHiddenCommand("selltest", function() Selling:Test() end)
