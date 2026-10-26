-- Blackthornes Butler -- UI/WhoHas.lua
-- Who has this: a few lines on every item's tooltip saying which of the
-- player's characters hold it and where, "Ana Stone   12 (4 bags, 8 bank)"
-- (the owner said build it, 2026-10-11).
--
-- Butler keeps no record of other characters. It reads Blackthornes
-- Tradeskills' Butler:Holdings() (each character's bags, bank and mail, as
-- Logic/Everyone.lua does), inside a pcall and read only, and lays it out
-- as one lookup by item ID. Without Tradeskills there are no lines.
--
-- Smooth play (an earlier thread fixed hover lag from tooltip work): a hover
-- only looks its item up in that lookup. Bag, bank and mail events just mark
-- it stale; it is built again on the next hover that needs it, at most once
-- every REBUILD_GAP seconds, so a burst of loot costs one rebuild, not one
-- per event. Nothing runs while no tooltip shows an item.
--
-- Nothing is written on the game's tooltips: lines are added after the
-- game's own (TooltipDataProcessor's post call, or OnTooltipSetItem through
-- HookScript on a client without it), never Hide, Show or a field.
-- Only GameTooltip and ItemRefTooltip get them, so the compare tooltips
-- beside a hovered piece of gear are left alone.

local _, ns = ...
local L = ns.L

local WhoHas = ns.NewModule("WhoHas")

-- At most this many characters by name, then "and N more".
WhoHas.MOST = 6
-- Seconds between rebuilds while the bags keep changing.
WhoHas.REBUILD_GAP = 1

-- The line's key for Off, Shift or Always (UI/TooltipShift.lua). Whether it
-- is on at all stays in ns.db.whoHas.
WhoHas.SHIFT_KEY = "whoHas"

-- Tooltips whose lines waited for Shift on this build, for the hint. Butler
-- on tooltips adds it after its own line, which stays last; without that
-- hook in, the hint goes on here.
WhoHas.held = setmetatable({}, { __mode = "k" })

WhoHas.PLACES = { "bags", "bank", "mail" }
WhoHas.PLACE_WORDS = { bags = L["in bags"], bank = L["in the bank"], mail = L["in the mail"] }
WhoHas.PLACE_SHORT = { bags = L["bags"], bank = L["bank"], mail = L["mail"] }

-- [itemID] = { holders = { { name, isCurrent, bags, bank, mail, total } }, total }
WhoHas.lookup = nil
WhoHas.stale = true
WhoHas.builtAt = nil
WhoHas.version = 0

local function Now()
    local ok, now = pcall(function() return GetTime() end)
    if ok and type(now) == "number" then return now end
    return 0
end

local function Text(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

function WhoHas:Enabled()
    return ns.db ~= nil and ns.db.whoHas ~= false
end

--------------------------------------------------------------------------------
-- The lookup
--------------------------------------------------------------------------------

--- Bags, bank or mail changed: build again before the next line is drawn.
function WhoHas:Changed()
    self.stale = true
end

--- Every character's items, by item ID, from one Holdings() call. Nil
--- without Tradeskills or when its answer is no use.
function WhoHas.Build()
    local butler = ns.Everyone and ns.Everyone.Tradeskills()
    if not butler then return nil end
    local ok, list = pcall(butler.Holdings, butler)
    if not ok or type(list) ~= "table" then return nil end

    local me = ns.Everyone.PlayingEntry(list)
    local lookup = {}
    for _, entry in ipairs(list) do
        -- An old record of the character playing (beside its GUID one) is
        -- the same character with an older count: only the live one counts.
        local skip = type(entry) ~= "table" or (entry.playing == true and entry.isCurrent ~= true)
            or not ns.Everyone.Ours(entry, me)
        local name = not skip and (Text(entry.name) or Text(entry.short))
        if name then
            local character = { name = name, isCurrent = entry.isCurrent == true }
            for _, place in ipairs(WhoHas.PLACES) do
                local counts = entry[place]
                if type(counts) == "table" then
                    for itemID, count in pairs(counts) do
                        if type(itemID) == "number" and type(count) == "number" and count > 0 then
                            count = math.floor(count)
                            local item = lookup[itemID]
                            if not item then
                                item = { holders = {}, byName = {}, total = 0 }
                                lookup[itemID] = item
                            end
                            local holder = item.byName[character]
                            if not holder then
                                holder = { name = character.name, isCurrent = character.isCurrent,
                                    bags = 0, bank = 0, mail = 0, total = 0 }
                                item.byName[character] = holder
                                item.holders[#item.holders + 1] = holder
                            end
                            holder[place] = holder[place] + count
                            holder.total = holder.total + count
                            item.total = item.total + count
                        end
                    end
                end
            end
        end
    end
    -- Most first; the character playing first among equals, then by name.
    for _, item in pairs(lookup) do
        item.byName = nil
        table.sort(item.holders, function(a, b)
            if a.total ~= b.total then return a.total > b.total end
            if a.isCurrent ~= b.isCurrent then return a.isCurrent end
            return a.name < b.name
        end)
    end
    return lookup
end

--- The lookup, built again first when it is stale and the last build is
--- more than REBUILD_GAP old (else the last one stands until the next hover).
function WhoHas:Lookup()
    local now = Now()
    if self.lookup == nil or (self.stale and (self.builtAt == nil or now - self.builtAt >= self.REBUILD_GAP)) then
        self.stale = false
        self.builtAt = now
        self.lookup = WhoHas.Build() or {}
        self.version = self.version + 1
    end
    return self.lookup
end

--------------------------------------------------------------------------------
-- The lines
--------------------------------------------------------------------------------

--- Where one character keeps it: "4 in bags", or "12 (4 bags, 8 bank)".
function WhoHas.Where(holder)
    local parts, only = {}, nil
    for _, place in ipairs(WhoHas.PLACES) do
        if holder[place] > 0 then
            parts[#parts + 1] = ("%d %s"):format(holder[place], WhoHas.PLACE_SHORT[place])
            only = place
        end
    end
    if #parts == 1 then return ("%d %s"):format(holder[only], WhoHas.PLACE_WORDS[only]) end
    return ("%d (%s)"):format(holder.total, table.concat(parts, ", "))
end

--- The lines for an item: { { left, right } }, the first the heading. Nil
--- when there is nothing worth saying: nobody has it, or only the character
--- playing has it and only in its bags, which the player can see.
function WhoHas.Lines(item)
    if not item or #item.holders == 0 then return nil end
    local holders = item.holders
    if #holders == 1 and holders[1].isCurrent and holders[1].bank == 0 and holders[1].mail == 0 then
        return nil
    end
    local lines = { { L.Format("Your characters have %d", item.total) } }
    for i, holder in ipairs(holders) do
        if i > WhoHas.MOST then
            local more = #holders - WhoHas.MOST
            lines[#lines + 1] = { more == 1 and L["and 1 more character"] or L.Format("and %d more characters", more) }
            break
        end
        local name = holder.isCurrent and L.Format("%s (you)", holder.name) or holder.name
        lines[#lines + 1] = { name, WhoHas.Where(holder) }
    end
    return lines
end

--- The item ID a tooltip shows: from the data the post call hands over,
--- else from the tooltip's own item link. Nil for anything unreadable
--- (a secret value inside an instance included).
function WhoHas.ItemID(tooltip, data)
    local ok, id = pcall(function()
        if type(data) == "table" and type(data.id) == "number" then return data.id + 0 end
        if tooltip and tooltip.GetItem then
            local _, link = tooltip:GetItem()
            if type(link) == "string" then
                return tonumber(link:match("item:(%d+)"))
            end
        end
    end)
    if ok and type(id) == "number" and id > 0 then return id end
    return nil
end

local function Decorates(tooltip)
    return tooltip ~= nil and (tooltip == _G.GameTooltip or tooltip == _G.ItemRefTooltip)
end

--- Add the lines under the game's own. Never raises.
function WhoHas:Decorate(tooltip, data)
    if tooltip ~= nil then WhoHas.held[tooltip] = nil end
    if self.quiet or not self:Enabled() or not Decorates(tooltip) then return end
    local itemID = WhoHas.ItemID(tooltip, data)
    if not itemID then return end
    local ok = pcall(function()
        local lines = WhoHas.Lines(self:Lookup()[itemID])
        if not lines then return end
        -- On Shift and Shift is up: only the hint, asked each build.
        if not ns.TooltipShift:Shows(WhoHas.SHIFT_KEY) then
            local tip = ns.VerdictTip
            if tip and tip.installed then
                WhoHas.held[tooltip] = true
            else
                ns.TooltipShift:Held(tooltip)
            end
            return
        end
        local r, g, b = 1, 0.82, 0
        if ns.Theme and ns.Theme.Unpack then r, g, b = ns.Theme.Unpack("accent") end
        tooltip:AddLine(" ")
        tooltip:AddLine(lines[1][1], r, g, b)
        for i = 2, #lines do
            local line = lines[i]
            if line[2] then
                tooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 0.8, 0.8, 0.8)
            else
                tooltip:AddLine(line[1], 0.6, 0.6, 0.6)
            end
        end
        -- The post call runs before the game sizes the tooltip, but the
        -- script hook runs after, so the older client needs this.
        if not data and tooltip.Show then tooltip:Show() end
    end)
    if not ok then ns.Debug("who has it tooltip failed") end
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

--- Hook item tooltips once: the post call on a client that has it (Forever
--- does, as Tradeskills found), else OnTooltipSetItem on the two tooltips.
--- Returns which, for the probe.
function WhoHas:Install()
    if self.installed then return self.installed end
    local processor = rawget(_G, "TooltipDataProcessor")
    local enum = rawget(_G, "Enum")
    local itemType = type(enum) == "table" and type(enum.TooltipDataType) == "table" and enum.TooltipDataType.Item
    if type(processor) == "table" and type(processor.AddTooltipPostCall) == "function" and itemType ~= nil then
        local ok = pcall(processor.AddTooltipPostCall, itemType, function(tooltip, data)
            WhoHas:Decorate(tooltip, data)
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
                WhoHas:Decorate(shown, nil)
            end) then
                hooked = true
            end
        end
    end
    self.installed = hooked and "script hook" or "none"
    return self.installed
end

--- Turn the lines on or off (Settings and /bbutler whohas).
function WhoHas:SetEnabled(on)
    ns.db.whoHas = on and true or false
    self.stale = true
end

--- One line for /bbutler probe.
function WhoHas:ProbeText()
    local source = ns.Everyone and ns.Everyone.Tradeskills() and "Tradeskills answers" or "no Tradeskills, no lines"
    return (self.installed or "not hooked") .. ", " .. source .. (self:Enabled() and "" or ", turned off")
end

function WhoHas:OnEnable()
    self:Install()
    local function Changed() WhoHas:Changed() end
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "BANKFRAME_CLOSED",
        "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_CLOSED", "PLAYER_ENTERING_WORLD" }) do
        ns.RegisterEvent(self, event, Changed)
    end
end

ns.RegisterCommand("whohas", L["show or hide which of your characters have an item, on its tooltip"], function()
    WhoHas:SetEnabled(not WhoHas:Enabled())
    ns.Print(WhoHas:Enabled() and L["item tooltips say which of your characters have it."]
        or L["item tooltips no longer say which of your characters have it."])
end)
