-- Blackthornes Butler -- Logic/MailRunsOut.lua
-- Mail running out (the owner said build it, 2026-11-09, from a mockup
-- whose words he approved). A mail left in a mailbox for 30 days goes back
-- to the sender, or is gone for good when it can't go back. Tradeskills
-- reads each character's inbox when the mailbox opens and keeps, read only
-- on its Butler:Holdings() entries:
--
--   mailAt          when the inbox was read
--   mailCount       mails in the box then
--   mailSoonest     days left on the one running out first, then
--   mailSoonCount   how many ran out within 3 days, then
--   mailReturns     of those, how many go back to the sender
--   mailGone        and how many are gone for good
--
-- Butler counts the days on from `mailAt`, so a box read a week ago still
-- says the right thing. With "Mail Running Out:" ticked (`mailRunsOut`,
-- off unless ticked, account wide, never rename it):
--   * this character's Get your mail step says "Runs out in N days" in
--     orange, 3 days or less;
--   * another character on this realm and side whose mail runs out in 3
--     days or less is the First: line in Jobs, with Log Out (Logic/Jobs.lua);
--   * at login, the shared note slot says "You have mail that runs out in
--     N days." once.
--
-- Nothing is taken out of a mailbox for the player, and nothing is saved.

local _, ns = ...
local L = ns.L

local MailRunsOut = ns.NewModule("MailRunsOut")

-- Days left at or under which mail counts as running out.
MailRunsOut.DAYS = 3
-- The words' orange (the mockup's).
MailRunsOut.ORANGE = "ffff9a3c"
-- How long a reading of Holdings is kept: Jobs asks on every redraw.
MailRunsOut.KEEP = 2
-- After logging in, how long before the note: Tradeskills reads its save first.
MailRunsOut.LOGIN_DELAY = 6

local DAY = 86400

function MailRunsOut:IsOn()
    return ns.db ~= nil and ns.db.mailRunsOut == true
end

function MailRunsOut:SetOn(on)
    ns.db.mailRunsOut = on and true or nil
    self.cache = nil
    if ns.Jobs then ns.Jobs:Changed() end
    if ns.UI and ns.UI.IsShown and ns.UI:IsShown() and ns.UI.Refresh then ns.UI:Refresh(true) end
end

local function Now()
    return type(time) == "function" and time() or 0
end

local function Number(value)
    if type(value) == "number" and value == value then return value end
    return nil
end

--- What one Holdings entry says about its mail, counted on to now, or nil
--- when nothing in its box runs out within `DAYS`.
function MailRunsOut.Read(entry, now)
    if type(entry) ~= "table" then return nil end
    local soonest, at = Number(entry.mailSoonest), Number(entry.mailAt)
    if not (soonest and at) then return nil end
    now = now or Now()
    local ago = math.max(0, now - at) / DAY
    local left = soonest - ago
    -- Already run out: it went back or is gone, and the box changed.
    if left <= 0 or left > MailRunsOut.DAYS then return nil end
    return {
        name = type(entry.name) == "string" and entry.name or nil,
        left = left,
        days = math.max(1, math.ceil(left)),
        count = math.floor(Number(entry.mailCount) or 0),
        soon = math.floor(Number(entry.mailSoonCount) or 0),
        -- Counted on to now, as the row says it.
        soonDays = math.max(1, math.ceil(left)),
        returns = math.floor(Number(entry.mailReturns) or 0),
        gone = math.floor(Number(entry.mailGone) or 0),
        seen = math.floor(ago),
    }
end

--- This character's mail running out and every other character's on this
--- realm and side, soonest first. Empty when the box is unticked or
--- Tradeskills isn't loaded.
function MailRunsOut:Scan()
    local clock = type(GetTime) == "function" and GetTime() or 0
    local cache = self.cache
    if cache and clock - cache.at < MailRunsOut.KEEP and cache.version == (ns.Jobs and ns.Jobs.version) then
        return cache.here, cache.alts
    end
    local here, alts = nil, {}
    if self:IsOn() and ns.Errands and ns.Errands.Holdings then
        local list, me = ns.Errands:Holdings()
        local now = Now()
        local seen = {}
        for _, entry in ipairs(list or {}) do
            local mine = ns.Errands.Mine and ns.Errands.Mine(entry)
            local info = MailRunsOut.Read(entry, now)
            if info and mine then
                if not here or info.left < here.left then here = info end
            elseif info and info.name and not seen[info.name]
                and ns.Everyone.SameSide(entry, me)
                and not (ns.Errands.IsMe and ns.Errands:IsMe(info.name)) then
                seen[info.name] = true
                alts[#alts + 1] = info
            end
        end
        table.sort(alts, function(a, b)
            if a.left ~= b.left then return a.left < b.left end
            return a.name < b.name
        end)
    end
    self.cache = { at = clock, version = ns.Jobs and ns.Jobs.version, here = here, alts = alts }
    return here, alts
end

--- This character's mail running out, or nil.
function MailRunsOut:Here()
    local here = self:Scan()
    return here
end

--- Other characters' mail running out, soonest first.
function MailRunsOut:Alts()
    local _, alts = self:Scan()
    return alts
end

local function Orange(text)
    return "|c" .. MailRunsOut.ORANGE .. text .. "|r"
end
MailRunsOut.Orange = Orange

--- "Runs out in 2 days", for this character's Get your mail step.
function MailRunsOut.HereText(info)
    if not info then return nil end
    return info.days == 1 and L["Runs out in 1 day"] or L.Format("Runs out in %d days", info.days)
end

--- "mail runs out in 1 day", for another character's First: line.
function MailRunsOut.ShortText(info)
    return info.days == 1 and L["mail runs out in 1 day"] or L.Format("mail runs out in %d days", info.days)
end

--- "1 goes back to the sender, 1 is gone for good.", or nil with neither.
function MailRunsOut.FateText(returns, gone)
    if returns > 0 and gone > 0 then
        if returns == 1 and gone == 1 then
            return L["1 goes back to the sender, 1 is gone for good."]
        elseif returns == 1 then
            return L.Format("1 goes back to the sender, %d are gone for good.", gone)
        elseif gone == 1 then
            return L.Format("%d go back to the sender, 1 is gone for good.", returns)
        end
        return L.Format("%d go back to the sender, %d are gone for good.", returns, gone)
    elseif returns > 0 then
        return returns == 1 and L["1 goes back to the sender."]
            or L.Format("%d go back to the sender.", returns)
    elseif gone > 0 then
        return gone == 1 and L["1 is gone for good."] or L.Format("%d are gone for good.", gone)
    end
    return nil
end

--- The hover's lines: { text, color } each, color "orange", "muted" or nil.
function MailRunsOut.TipLines(info)
    local lines = {}
    lines[#lines + 1] = { info.count == 1 and L["1 mail in the box."] or L.Format("%d mails in the box.", info.count) }
    local soon = math.max(1, info.soon)
    local runs
    if info.soonDays == 1 then
        runs = soon == 1 and L["1 runs out in 1 day."] or L.Format("%d run out in 1 day.", soon)
    else
        runs = soon == 1 and L.Format("1 runs out in %d days.", info.soonDays)
            or L.Format("%d run out in %d days.", soon, info.soonDays)
    end
    lines[#lines + 1] = { runs, "orange" }
    local fate = MailRunsOut.FateText(info.returns, info.gone)
    if fate then lines[#lines + 1] = { fate } end
    lines[#lines + 1] = { " " }
    local seen
    if info.seen <= 0 then
        seen = L["Last seen today."]
    elseif info.seen == 1 then
        seen = L["Last seen 1 day ago."]
    else
        seen = L.Format("Last seen %d days ago.", info.seen)
    end
    lines[#lines + 1] = { seen, "muted" }
    return lines
end

--- The login note's words, or nil.
function MailRunsOut.NoteText(info)
    if not info then return nil end
    return info.days == 1 and L["You have mail that runs out in 1 day."]
        or L.Format("You have mail that runs out in %d days.", info.days)
end

--- Once a login: the note in the shared slot when this character's mail
--- runs out soon.
function MailRunsOut:Greet()
    self.cache = nil
    local text = MailRunsOut.NoteText(self:Here())
    if not text or self.told then return end
    self.told = true
    if ns.Notice and ns.Notice.Show then
        ns.Notice:Show(text, { icon = [[Interface\Icons\INV_Letter_15]], key = "butlerMailRunsOut" })
    else
        ns.Print(text)
    end
end

function MailRunsOut:OnEnable()
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function(_, _, isInitialLogin)
        if not isInitialLogin then return end
        if C_Timer and C_Timer.After then
            C_Timer.After(MailRunsOut.LOGIN_DELAY, function() MailRunsOut:Greet() end)
        else
            MailRunsOut:Greet()
        end
    end)
    -- The box was read at a mailbox: what shows may have changed.
    ns.RegisterEvent(self, "MAIL_CLOSED", function() MailRunsOut.cache = nil end)
end
