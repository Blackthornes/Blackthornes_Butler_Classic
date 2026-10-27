-- Blackthornes Butler -- Logic/Learning.lua
-- Butler learns from what the player does anyway (the owner asked
-- 2026-10-11: the addons should work "almost like it's magic"), so a
-- choice never has to be made twice from the right-click menu:
--
--   * Bought back after Butler's Sell button sold it: kept from then on
--     ("You bought this back, so Butler keeps it").
--   * Sold by hand at a vendor on two visits: under Sell from then on
--     ("You usually sell these").
--   * Mailed by hand to the same one of the player's characters twice:
--     under Mail to them from then on, so Fill mail sends it.
--
-- Learned choices are weaker than the player's own lists: an Always keep,
-- sell, bank or mail choice wins and clears what was learned, and so does
-- Let Butler decide. A learned keep comes right after the lists (keeping
-- always beats selling); a learned sell or mail only after every sister's
-- Keep, so an upgrade, a goal, a queued craft or pet food is never sold or
-- mailed away on a habit. Soulbound green or better is never learned as
-- Sell, and soulbound is never mailed. Only mail to one of the player's own
-- characters (Tradeskills' record) teaches anything, never to the
-- character playing; mail an addon filled (its subject) teaches nothing.
--
-- Nothing is sold, mailed or moved here: it only changes the verdict, and
-- the player still clicks Sell, Fill mail and Send.
--
-- Saved, account wide, never renamed: BlackthornesButlerDB.learned
-- ([itemID] = { verdict = "keep" | "sell" | "mail", to, at }) and
-- .learnTally ({ sells = { [itemID] = visits }, mails = { [itemID] =
-- { [name] = sends } } }). "Learn from what you do" (`learn`, on unless
-- unticked) turns the watching off; what was learned stays until the
-- player clears it.
--
-- Smooth play: three hooks on single calls (BuybackItem, UseContainerItem
-- at a vendor, SendMail) and one event each; no timers, no bag scans.

local _, ns = ...
local L = ns.L

local Learning = ns.NewModule("Learning")

local Items = ns.Items
local Bags = ns.Bags

-- Visits a hand sale must happen on, and sends to one character, before
-- Butler takes it as a habit.
Learning.SELLS = 2
Learning.MAILS = 2

-- Mail that another addon filled in: already its choice, so not the
-- player's habit.
Learning.ADDON_SUBJECTS = {
    ["From Blackthornes Butler"] = true,
    ["Gold from Blackthornes Butler"] = true,
    ["Crafts for your queue"] = true,
    ["Gear to disenchant"] = true,
    ["Materials for the craft queue"] = true,
}

local REASONS = {
    keep = L["You bought this back, so Butler keeps it"],
    sell = L["You usually sell these"],
}

local function Text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function Learned()
    if not ns.db then return {} end
    if type(ns.db.learned) ~= "table" then ns.db.learned = {} end
    return ns.db.learned
end

local function Tally(kind)
    if not ns.db then return {} end
    if type(ns.db.learnTally) ~= "table" then ns.db.learnTally = {} end
    local tally = ns.db.learnTally
    if type(tally[kind]) ~= "table" then tally[kind] = {} end
    return tally[kind]
end

--- Is Butler watching what the player does?
function Learning:On()
    return not (ns.db and ns.db.learn == false)
end

--- What Butler learned for an item: "keep", "sell" or "mail" (and who, for
--- mail), or nil.
function Learning:Get(itemID)
    local entry = itemID and Learned()[itemID]
    if type(entry) ~= "table" then return nil end
    local verdict = entry.verdict
    if verdict == "mail" then
        local to = Text(entry.to)
        if not to then return nil end
        return "mail", to
    end
    if verdict == "keep" or verdict == "sell" then return verdict end
    return nil
end

--- The row's reason for a learned verdict.
function Learning.Reason(verdict, to)
    if verdict == "mail" then return L.Format("You usually mail this to %s", to or "?") end
    return REASONS[verdict]
end

--- Forget what was learned about an item, and the counting toward it.
--- Called when the player picks from the right-click menu.
function Learning:Forget(itemID)
    if not itemID or not ns.db then return end
    Learned()[itemID] = nil
    Tally("sells")[itemID] = nil
    Tally("mails")[itemID] = nil
end

--- Forget everything learned (/bbutler reset confirm).
function Learning:ForgetAll()
    if not ns.db then return end
    ns.db.learned = {}
    ns.db.learnTally = {}
end

local function ItemName(itemID)
    local name, link = Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, itemID)
    return link or name or L.Format("item %s", tostring(itemID))
end

--- Take a habit as learned, say so once in chat and judge again.
function Learning:Learn(itemID, verdict, to)
    if not itemID then return end
    local now = type(time) == "function" and time() or 0
    Learned()[itemID] = { verdict = verdict, to = to, at = now }
    Tally("sells")[itemID] = nil
    Tally("mails")[itemID] = nil
    local name = ItemName(itemID)
    if verdict == "keep" then
        ns.Print(L.Format("%s: you bought it back, so Butler keeps it from now on. Right-click it in the Butler window to change that.", name))
    elseif verdict == "sell" then
        ns.Print(L.Format("%s: you sell these, so Butler puts them under Sell from now on. Right-click it in the Butler window to change that.", name))
    else
        ns.Print(L.Format("%s: you mail these to %s, so Butler puts them under Mail from now on. Right-click it in the Butler window to change that.", name, to))
    end
    if ns.Verdicts then ns.Verdicts:Changed(true) end
end

--------------------------------------------------------------------------------
-- Bought back
--------------------------------------------------------------------------------

--- What the vendor's Buyback tab holds, by index: read when the vendor
--- opens and after a burst of vendor updates, so a buyback can still be
--- named should the game have moved its list on already.
function Learning:ReadBuyback()
    local list = {}
    local count = Items.Call({ "GetNumBuybackItems" })
    if type(count) == "number" then
        for index = 1, math.min(count, 12) do
            local link = Items.Call({ "GetBuybackItemLink" }, index)
            local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
            list[index] = itemID
        end
    end
    self.buyback = list
end

--- Coalesce MERCHANT_UPDATE, which comes several times a sale.
function Learning:BuybackChanged()
    if self.buybackSoon then return end
    self.buybackSoon = true
    C_Timer.After(0.2, function()
        Learning.buybackSoon = false
        if ns.Selling and ns.Selling:MerchantOpen() then Learning:ReadBuyback() end
    end)
end

--- The player bought back the item at `index`. Kept from now on when
--- Butler's Sell button sold it this visit and the player had not put it
--- on Always sell themselves.
function Learning:OnBuyback(index)
    if not self:On() then return end
    local link = Items.Call({ "GetBuybackItemLink" }, index)
    local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    if not itemID and self.buyback then itemID = self.buyback[index] end
    if not itemID then return end

    local sold = ns.Selling and ns.Selling.soldIDs
    if not (sold and sold[itemID]) then return end
    if ns.Verdicts:Choice(itemID) then return end
    if self:Get(itemID) == "keep" then return end
    self:Learn(itemID, "keep")
end

--------------------------------------------------------------------------------
-- Sold by hand
--------------------------------------------------------------------------------

--- The slot as Butler last read it, for when the game has emptied it.
local function KnownSlot(bag, slot)
    return Bags.slots[bag .. ":" .. slot]
end

--- Is this use of a bag slot Butler's own Sell button or Sell all?
local function ButlerSelling(bag, slot)
    local Selling = ns.Selling
    if not Selling then return false end
    if Selling.selling or Selling.testing then return true end
    local button = Selling.button
    local pending = button and rawget(button, "pending")
    return type(pending) == "table" and pending.bag == bag and pending.slot == slot
end

--- A bag slot was used. At an open vendor that sells it: count it once
--- the slot has emptied, unless Butler's own button sold it or Butler
--- already says Sell.
function Learning:OnUse(bag, slot)
    if not self:On() then return end
    if not (ns.Selling and ns.Selling:MerchantOpen(true)) then return end
    if type(bag) ~= "number" or type(slot) ~= "number" then return end
    if ButlerSelling(bag, slot) then return end
    -- A spell aimed at the item (Butler's Disenchant button aims through
    -- this same call) is no sale.
    local okAim, aiming = pcall(function() return SpellIsTargeting and SpellIsTargeting() end)
    if okAim and aiming then return end

    local entry = Bags.ReadSlot(bag, slot) or KnownSlot(bag, slot)
    if not (entry and entry.itemID) then return end
    local itemID = entry.itemID
    if (entry.quality or 1) == 0 or entry.noValue then return end
    if entry.bound and (entry.quality or 0) >= 2 then return end
    if ns.Verdicts:Choice(itemID) or self:Get(itemID) then return end
    if not entry.quest then entry.quest = KnownSlot(bag, slot) and KnownSlot(bag, slot).quest end
    if entry.quest then return end
    if ns.Verdicts:VerdictOf(entry) == "sell" then return end

    -- Counted once the game has taken it (the slot empties when the vendor
    -- pays), and once a visit, so a stack split in two is one sale.
    -- Still there, even locked (a cast on it under way), is no sale.
    C_Timer.After(1, function()
        local still = Bags.ReadSlot(bag, slot)
        if still and still.itemID == itemID then return end
        Learning:CountSale(itemID)
    end)
end

function Learning:CountSale(itemID)
    local visit = self.soldByHand or {}
    self.soldByHand = visit
    if visit[itemID] then return end
    visit[itemID] = true

    local sells = Tally("sells")
    sells[itemID] = (tonumber(sells[itemID]) or 0) + 1
    if sells[itemID] >= self.SELLS then self:Learn(itemID, "sell") end
end

--------------------------------------------------------------------------------
-- Mailed by hand
--------------------------------------------------------------------------------

--- The player's character a typed recipient names: a full name as
--- Tradeskills keeps it, or the first name alone when only one character
--- has it, with any "-Realm" taken off. nil for anyone else and for the
--- character playing (Errands:Characters leaves it out).
function Learning:Recipient(recipient)
    local ok, typed = pcall(function() return recipient .. "" end)
    if not ok then return nil end
    typed = typed:gsub("%-.*$", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if typed == "" then return nil end
    local found
    for _, name in ipairs(ns.Errands:Characters()) do
        local lower = name:lower()
        if lower == typed then return name end
        if lower:match("^(%S+)") == typed then
            if found then return nil end
            found = name
        end
    end
    return found
end

--- What is attached to the mail being sent: a list of item IDs.
function Learning.Attachments()
    local ids = {}
    local most = tonumber(rawget(_G, "ATTACHMENTS_MAX_SEND")) or 12
    for slot = 1, most do
        local name, itemID = Items.Call({ "GetSendMailItem" }, slot)
        local okID, id = pcall(function() return itemID + 0 end)
        if name ~= nil and okID and id then ids[#ids + 1] = id end
    end
    return ids
end

--- SendMail was called: what it carries is counted once the game says it
--- went (MAIL_SEND_SUCCESS); a failed send is forgotten.
function Learning:OnSendMail(recipient, subject)
    self.pending = nil
    if not self:On() then return end
    local okSubject, said = pcall(function() return (subject or "") .. "" end)
    if okSubject and self.ADDON_SUBJECTS[said] then return end
    local to = self:Recipient(recipient)
    if not to or (ns.Verdicts and ns.Verdicts:IsMe(to)) then return end
    local ids = self.Attachments()
    if #ids == 0 then return end
    self.pending = { to = to, ids = ids }
end

function Learning:OnSendSuccess()
    local pending = self.pending
    self.pending = nil
    if not pending then return end

    local mails = Tally("mails")
    local counted = {}
    for _, itemID in ipairs(pending.ids) do
        if not counted[itemID] and not ns.Verdicts:Choice(itemID) then
            counted[itemID] = true
            local learned, learnedTo = self:Get(itemID)
            if not (learned == "mail" and learnedTo == pending.to) and learned ~= "keep" then
                local byName = type(mails[itemID]) == "table" and mails[itemID] or {}
                mails[itemID] = byName
                byName[pending.to] = (tonumber(byName[pending.to]) or 0) + 1
                if byName[pending.to] >= self.MAILS then self:Learn(itemID, "mail", pending.to) end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Learning:OnEnable()
    if type(hooksecurefunc) ~= "function" then return end

    if type(rawget(_G, "BuybackItem")) == "function" then
        pcall(hooksecurefunc, "BuybackItem", function(index) Learning:OnBuyback(index) end)
    end
    local container = rawget(_G, "C_Container")
    local modern = type(container) == "table" and container.UseContainerItem or nil
    if type(modern) == "function" then
        pcall(hooksecurefunc, container, "UseContainerItem", function(bag, slot)
            Learning:OnUse(bag, slot)
        end)
    end
    -- Era also has the older global. Watch it too, only when it is a call
    -- of its own, so one sale is never seen twice.
    local older = rawget(_G, "UseContainerItem")
    if type(older) == "function" and older ~= modern then
        pcall(hooksecurefunc, "UseContainerItem", function(bag, slot)
            Learning:OnUse(bag, slot)
        end)
    end
    if type(rawget(_G, "SendMail")) == "function" then
        pcall(hooksecurefunc, "SendMail", function(recipient, subject)
            Learning:OnSendMail(recipient, subject)
        end)
    end

    ns.RegisterEvent(self, "MERCHANT_SHOW", function()
        Learning.soldByHand = {}
        Learning:ReadBuyback()
    end)
    ns.RegisterEvent(self, "MERCHANT_UPDATE", function() Learning:BuybackChanged() end)
    ns.RegisterEvent(self, "MAIL_SEND_SUCCESS", function() Learning:OnSendSuccess() end)
    ns.RegisterEvent(self, "MAIL_FAILED", function() Learning.pending = nil end)
end

--- Lines for /bbutler lists: what Butler learned.
function Learning:PrintLearned()
    local ids = {}
    for itemID in pairs(Learned()) do
        if self:Get(itemID) then ids[#ids + 1] = itemID end
    end
    table.sort(ids)
    if #ids == 0 then
        ns.PrintRaw(L.Format("  |c%sLearned from you:|r none yet", ns.COLORS.muted))
        return
    end
    local parts = {}
    for _, itemID in ipairs(ids) do
        local verdict, to = self:Get(itemID)
        local what = verdict == "mail" and L.Format("mail to %s", to) or verdict == "keep" and L["keep"] or L["sell"]
        parts[#parts + 1] = ("%s (%s)"):format(ItemName(itemID), what)
    end
    ns.PrintRaw(L.Format("  |c%sLearned from you (%d):|r %s", ns.COLORS.muted, #ids, table.concat(parts, ", ")))
end
