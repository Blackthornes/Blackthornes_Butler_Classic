-- Blackthornes Butler -- UI/VerdictTip.lua
-- Butler's verdict on item tooltips: one line, "Butler: Sell" with the
-- value it used (a player asked; the owner said yes 2026-10-13, as the
-- last line on the tooltip and only while Butler is loaded).
--
-- Only items in the bags of the character playing get the line, since a
-- verdict is about something carried. A hover reads one slot (the hovered
-- bag slot, else where Butler last saw the item) and takes the window's
-- verdict when that is up to date, else judges just that one item
-- (Verdicts:Judge keeps its answer). Nothing runs while no tooltip shows
-- an item.
--
-- Last line: the post call is added a moment after the loading screen, so
-- it runs after the lines other addons hooked at login (Butler's own Who
-- has it among them). Nothing is written on the game's tooltips: a line is
-- added, never Hide, Show or a field, and only on GameTooltip and
-- ItemRefTooltip, as UI/WhoHas.lua does.

local _, ns = ...
local L = ns.L

local VerdictTip = ns.NewModule("VerdictTip")

-- Seconds after the first loading screen before the hook goes in.
VerdictTip.DELAY = 1

-- The line's key for Off, Shift or Always (UI/TooltipShift.lua). Whether it
-- is on at all stays in ns.db.verdictTip.
VerdictTip.SHIFT_KEY = "verdictTip"
ns.TooltipShift.KEYS = { "whoHas", VerdictTip.SHIFT_KEY, "vendorPrice" }

function VerdictTip:Enabled()
    return ns.db ~= nil and ns.db.verdictTip ~= false
end

--- Turn the line on or off (Settings and /bbutler tooltip).
function VerdictTip:SetEnabled(on)
    ns.db.verdictTip = on and true or false
end

--- The bag and slot a tooltip's owner is, when it is a bag's item button
--- (its GetBagID, else its bag frame's ID, and its own ID). Read in a
--- pcall; the slot is checked against the item before it is used.
local function OwnerSlot(tooltip)
    local ok, bag, slot = pcall(function()
        local owner = tooltip.GetOwner and tooltip:GetOwner()
        if type(owner) ~= "table" or type(owner.GetID) ~= "function" then return nil end
        local bagID
        if type(owner.GetBagID) == "function" then
            bagID = owner:GetBagID()
        elseif type(owner.GetParent) == "function" then
            local parent = owner:GetParent()
            if type(parent) == "table" and type(parent.GetID) == "function" then bagID = parent:GetID() end
        end
        return bagID, owner:GetID()
    end)
    if ok and type(bag) == "number" and type(slot) == "number" and slot > 0 then return bag, slot end
    return nil
end

--- The slot as the client has it now, if it still holds `itemID`: the kept
--- entry when nothing in it changed (the window's verdict knows it), else
--- a fresh one with its quest read.
local function Fresh(bag, slot, itemID)
    local entry = ns.Bags.ReadSlot(bag, slot)
    if not (entry and entry.itemID == itemID) then return nil end
    local kept = ns.Bags.slots[bag .. ":" .. slot]
    if kept and kept.key == entry.key then return kept end
    entry.quest = ns.Bags.ReadQuest(bag, slot, itemID)
    return entry
end

--- A carried slot holding `itemID`: the hovered bag slot when the tooltip
--- belongs to one, else the first slot Butler's last read saw it in,
--- read again to be sure. Butler reads the bags only while its window or
--- a vendor is up, so a hover that finds nothing on stale bags asks for
--- one read (spread over frames), for the next hover. Nil when not carried.
function VerdictTip:Entry(itemID, tooltip)
    local bag, slot = OwnerSlot(tooltip)
    if bag then
        local entry = Fresh(bag, slot, itemID)
        if entry then return entry end
    end

    local version = ns.Bags.version
    if self.byIDVersion ~= version or not self.byID then
        local byID = {}
        for _, kept in pairs(ns.Bags.slots) do
            local id = kept.itemID
            local known = id and byID[id]
            if id and (not known or kept.bag < known.bag
                or (kept.bag == known.bag and kept.slot < known.slot)) then
                byID[id] = kept
            end
        end
        self.byID, self.byIDVersion = byID, version
    end
    local kept = self.byID[itemID]
    local entry = kept and Fresh(kept.bag, kept.slot, itemID)
    if entry then return entry end

    if ns.Bags.stale and not ns.Bags.scanning then ns.Bags:Scan() end
    return nil
end

--- The window's row for this slot, when the kept groups are up to date:
--- it knows which copies an alt's upgrade takes.
local function KeptRow(entry)
    local cache = ns.Verdicts.groupCache
    if not (cache and cache.bags == ns.Bags.version and cache.verdicts == ns.Verdicts.version) then return nil end
    for _, group in ipairs(cache.groups or {}) do
        for _, row in ipairs(group.rows or {}) do
            for _, slot in ipairs(row.slots or {}) do
                if slot == entry then return row end
            end
        end
    end
    return nil
end

--- The line for a carried item: left ("Butler: Mail to Bob Stone"),
--- right (what one is worth, or nil) and, for a mail, the reason it goes.
--- Nil when not carried.
function VerdictTip:Line(itemID, tooltip)
    local entry = itemID and self:Entry(itemID, tooltip)
    if not entry then return nil end
    ns.Verdicts:ForgetIfOld()
    local verdict, unit, to, reason
    local row = KeptRow(entry)
    if row then
        verdict, unit, to, reason = row.verdict, row.unit, row.mailTo, row.reason
    else
        local extra
        verdict, reason, unit, extra = ns.Verdicts:Judge(entry)
        to = type(extra) == "table" and extra.to or nil
    end
    local label = verdict and ns.Verdicts.LABELS[verdict]
    if not label then return nil end
    local left
    if verdict == "mail" and type(to) == "string" and to ~= "" then
        left = L.Format("Butler: Mail to %s", to)
    else
        left = L.Format("Butler: %s", label)
    end
    local right = (type(unit) == "number" and unit > 0) and L.Format("%s each", ns.Items.FormatMoney(unit)) or nil
    -- A mail says why under it (to disenchant, an upgrade, your list), so
    -- "Mail to NAME" is never read as "NAME can wear it". The words are
    -- the window's own reason, already in every language.
    local why = nil
    if verdict == "mail" and type(reason) == "string" and reason ~= "" then why = reason end
    return left, right, why
end

local function Decorates(tooltip)
    return tooltip ~= nil and (tooltip == _G.GameTooltip or tooltip == _G.ItemRefTooltip)
end

--- Add the line under everything else, then the vendor's price, then
--- "Hold Shift for more." when any of them waited for Shift. Never raises.
function VerdictTip:Decorate(tooltip, data)
    if not Decorates(tooltip) then return end
    local held = ns.WhoHas and ns.WhoHas.held[tooltip] or false
    if held then ns.WhoHas.held[tooltip] = nil end
    if self:Enabled() then
        held = self:AddLine(tooltip, data) or held
    end
    -- Under it, what a vendor charges (Logic/VendorPrices.lua), on any item.
    if ns.VendorPrices then
        local itemID = ns.WhoHas and ns.WhoHas.ItemID(tooltip, data)
        held = ns.VendorPrices:AddLine(tooltip, itemID, data) or held
    end
    if held then ns.TooltipShift:Held(tooltip) end
end

--- The line itself. True when it was held back for Shift.
function VerdictTip:AddLine(tooltip, data)
    local itemID = ns.WhoHas and ns.WhoHas.ItemID(tooltip, data)
    if not itemID then return false end
    local held = false
    local ok = pcall(function()
        local left, right, why = self:Line(itemID, tooltip)
        if not left then return end
        -- On Shift and Shift is up: only the hint, asked each build.
        if not ns.TooltipShift:Shows(self.SHIFT_KEY) then
            held = true
            return
        end
        local r, g, b = 1, 0.82, 0
        if ns.Theme and ns.Theme.Unpack then r, g, b = ns.Theme.Unpack("accent") end
        if right then
            tooltip:AddDoubleLine(left, right, r, g, b, 1, 1, 1)
        else
            tooltip:AddLine(left, r, g, b)
        end
        if why then tooltip:AddLine(why, 0.7, 0.7, 0.7, true) end
        if not data and tooltip.Show then tooltip:Show() end
    end)
    if not ok then ns.Debug("verdict tooltip failed") end
    return held
end

--- Hook item tooltips once, the same two ways Who has it does. Returns
--- which, for the probe.
function VerdictTip:Install()
    if self.installed then return self.installed end
    local processor = rawget(_G, "TooltipDataProcessor")
    local enum = rawget(_G, "Enum")
    local itemType = type(enum) == "table" and type(enum.TooltipDataType) == "table" and enum.TooltipDataType.Item
    if type(processor) == "table" and type(processor.AddTooltipPostCall) == "function" and itemType ~= nil then
        local ok = pcall(processor.AddTooltipPostCall, itemType, function(tooltip, data)
            VerdictTip:Decorate(tooltip, data)
        end)
        if ok then
            self.installed = "post call"
            return self.installed
        end
    end
    local hooked = false
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local tooltip = rawget(_G, name)
        if type(tooltip) == "table" and type(tooltip.HookScript) == "function" then
            if pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(shown)
                VerdictTip:Decorate(shown, nil)
            end) then
                hooked = true
            end
        end
    end
    self.installed = hooked and "script hook" or "none"
    return self.installed
end

--- One line for /bbutler probe.
function VerdictTip:ProbeText()
    return (self.installed or "not hooked yet") .. (self:Enabled() and "" or ", turned off")
end

function VerdictTip:OnEnable()
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if VerdictTip.installed or VerdictTip.waiting then return end
        VerdictTip.waiting = true
        local ok = pcall(function()
            C_Timer.After(VerdictTip.DELAY, function() VerdictTip:Install() end)
        end)
        if not ok then VerdictTip:Install() end
    end)
end

ns.RegisterCommand("tooltip", L["show or hide Butler's advice on the tooltips of items in your bags"], function()
    VerdictTip:SetEnabled(not VerdictTip:Enabled())
    ns.Print(VerdictTip:Enabled() and L["item tooltips show what Butler would do with them."]
        or L["item tooltips no longer show what Butler would do with them."])
end)
