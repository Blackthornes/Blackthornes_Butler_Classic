-- Blackthornes Butler -- UI/MailContents.lua
-- What a mail holds, on the tooltip of its row in the inbox (the owner
-- said build it from a mockup, 2026-11-09, on by default).
--
-- Under the game's own tooltip lines: IN THIS MAIL, then each attachment
-- with its icon, its name in its quality colour and "xN", then Gold:
-- (the mail's money), Items worth: (Butler's usual prices, greys at
-- vendor, left out when nothing is priced), Runs out in: (orange at 3
-- days or less) and, for cash on delivery, Costs: in red. A mail with no
-- items and no money shows only Runs out in.
--
-- The inbox is never moved, hidden or written to: the inbox rows only get
-- an OnEnter post hook (HookScript), and only lines are added to
-- GameTooltip. Everything is read in a pcall; nothing is saved.

local _, ns = ...
local L = ns.L

local MailContents = ns.NewModule("MailContents")

-- Days left at or under which Runs out in turns orange.
MailContents.SOON = 3
-- Attachments a mail can carry, when the client does not say.
MailContents.SLOTS = 12
-- Rows on one inbox page, when the client does not say.
MailContents.ROWS = 7

local ORANGE = "ffff8c1a"

function MailContents:Enabled()
    return ns.db ~= nil and ns.db.mailContents ~= false
end

--- Turn the lines on or off (Settings).
function MailContents:SetEnabled(on)
    ns.db.mailContents = on and true or false
end

local function Call(name, ...)
    local fn = rawget(_G, name)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

--- What one of an item is worth to Butler: a vendor's price for greys,
--- else the best of a vendor and Tradeskills' auction price (after its
--- cut). Nil when nothing prices it.
function MailContents.Worth(itemID, link, quality)
    if type(itemID) ~= "number" then return nil end
    local vendor = ns.Items:SellPrice(itemID)
    if quality == 0 then
        return (type(vendor) == "number" and vendor > 0) and vendor or nil
    end
    local auction
    if ns.Sisters then
        local ts = ns.Sisters:Ask("ts", { itemID = itemID, link = link })
        auction = ts and ns.Sisters.Number(ts, "auction") or nil
    end
    local best = math.max(type(vendor) == "number" and vendor or 0, auction or 0)
    return best > 0 and best or nil
end

--- "1 day", "5 days": whole days left, never under 1, as the mail
--- running out warning counts them.
function MailContents.DaysText(left)
    local days = math.max(1, math.ceil(left))
    return days == 1 and L["1 day"] or L.Format("%d days", days), days
end

--- What mail `index` holds: { items = { { name, icon, count, quality,
--- worth } }, money, cod, days, daysLeft, worth }, or nil when the client
--- will not say.
function MailContents:Read(index)
    if type(index) ~= "number" then return nil end
    local _, _, _, _, money, cod, daysLeft, hasItem = Call("GetInboxHeaderInfo", index)
    if type(daysLeft) ~= "number" then return nil end
    local info = {
        items = {},
        money = (type(money) == "number" and money > 0) and money or nil,
        cod = (type(cod) == "number" and cod > 0) and cod or nil,
        daysLeft = daysLeft,
    }
    if hasItem then
        local slots = tonumber(rawget(_G, "ATTACHMENTS_MAX_RECEIVE")) or self.SLOTS
        local total, priced = 0, false
        for slot = 1, slots do
            local name, itemID, icon, count, quality = Call("GetInboxItem", index, slot)
            if type(name) == "string" and name ~= "" then
                local link = Call("GetInboxItemLink", index, slot)
                if type(itemID) ~= "number" and type(link) == "string" then
                    itemID = tonumber(link:match("item:(%d+)"))
                end
                count = (type(count) == "number" and count > 0) and count or 1
                local unit = self.Worth(itemID, link, quality)
                if unit then
                    total = total + unit * count
                    priced = true
                end
                info.items[#info.items + 1] = {
                    name = name, icon = icon, count = count, quality = quality,
                    worth = unit and unit * count or nil,
                }
            end
        end
        info.worth = priced and total or nil
    end
    return info
end

--- The lines for `info`: { left, right, r, g, b } each, in order.
function MailContents.Lines(info)
    local lines = {}
    local function Add(left, right, r, g, b)
        lines[#lines + 1] = { left = left, right = right, r = r or 1, g = g or 1, b = b or 1 }
    end
    local white = "|c" .. ns.COLORS.text
    if #info.items > 0 or info.money or info.cod then
        local r, g, b = 1, 0.82, 0
        if ns.Theme and ns.Theme.Unpack then r, g, b = ns.Theme.Unpack("accent") end
        Add(L["IN THIS MAIL"], nil, r, g, b)
        for _, item in ipairs(info.items) do
            local hex = ns.Items.QualityHex(item.quality) or ns.COLORS.text
            local icon = item.icon and ("|T" .. tostring(item.icon) .. ":14:14:0:0|t ") or ""
            Add(icon .. "|c" .. hex .. item.name .. "|r", L.Format("x%d", item.count))
        end
        if info.money then Add(L["Gold:"], ns.Items.FormatMoney(info.money)) end
        if info.worth then Add(L["Items worth:"], ns.Items.FormatMoney(info.worth)) end
    end
    local text, days = MailContents.DaysText(info.daysLeft)
    local color = days <= MailContents.SOON and ORANGE or ns.COLORS.text
    Add(L["Runs out in:"], "|c" .. color .. text .. "|r")
    if info.cod then
        Add("|c" .. ns.COLORS.bad .. L["Costs:"] .. "|r", ns.Items.FormatMoney(info.cod))
    end
    lines.white = white
    return lines
end

--- The mail a row stands for: its own index when the game set one, else
--- its place on the page shown.
local function RowIndex(button, row)
    local index = rawget(button, "index")
    if type(index) == "number" then return index end
    local inbox = rawget(_G, "InboxFrame")
    local page = type(inbox) == "table" and tonumber(rawget(inbox, "pageNum")) or 1
    local perPage = tonumber(rawget(_G, "INBOXITEMS_TO_DISPLAY")) or MailContents.ROWS
    return (page - 1) * perPage + row
end

--- Add the lines to GameTooltip for the row under the mouse. Never raises.
function MailContents:OnEnter(button, row)
    if not self:Enabled() then return end
    local ok = pcall(function()
        local index = RowIndex(button, row)
        local count = Call("GetInboxNumItems")
        if type(count) == "number" and index > count then return end
        local info = self:Read(index)
        if not info then return end
        local tooltip = rawget(_G, "GameTooltip")
        if type(tooltip) ~= "table" then return end
        if tooltip:GetOwner() ~= button then
            tooltip:SetOwner(button, "ANCHOR_RIGHT")
        end
        for _, line in ipairs(MailContents.Lines(info)) do
            if line.right then
                tooltip:AddDoubleLine(line.left, line.right, line.r, line.g, line.b, 1, 1, 1)
            else
                tooltip:AddLine(line.left, line.r, line.g, line.b)
            end
        end
        tooltip:Show()
    end)
    if not ok and ns.Debug then ns.Debug("mail contents tooltip failed") end
end

--- Hook each inbox row once. True once they are hooked.
function MailContents:Install()
    if self.installed then return true end
    local rows = tonumber(rawget(_G, "INBOXITEMS_TO_DISPLAY")) or self.ROWS
    local hooked = 0
    for row = 1, rows do
        local button = rawget(_G, "MailItem" .. row .. "Button")
        if type(button) == "table" and type(button.HookScript) == "function" then
            local ok = pcall(button.HookScript, button, "OnEnter", function(self)
                MailContents:OnEnter(self, row)
            end)
            if ok then hooked = hooked + 1 end
        end
    end
    self.installed = hooked > 0
    return self.installed
end

--- One line for /bbutler probe.
function MailContents:ProbeText()
    return (self.installed and "inbox rows hooked" or "not hooked yet")
        .. (self:Enabled() and "" or ", turned off")
end

function MailContents:OnEnable()
    -- The inbox rows exist from login; looked for again at the first
    -- mailbox in case the client makes them late.
    self:Install()
    ns.RegisterEvent(self, "MAIL_SHOW", function() MailContents:Install() end)
end
