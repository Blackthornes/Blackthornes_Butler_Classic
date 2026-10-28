-- Blackthornes Butler -- Core/Init.lua
-- Namespace, module registry, event dispatch and slash-command routing.
--
-- Same shape as Blackthornes Tradeskills, Farmer, Equipment and Pets, and for the
-- same reason: Ace3 and LibStub are not known to be ported to WoW: Forever, so
-- the framework is ours and is small enough to read in one sitting.

local ADDON_NAME, ns = ...
local L = ns.L

_G.BlackthornesButler = ns

ns.ADDON_NAME = ADDON_NAME

local function GetMeta(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, field)
        if ok then return value end
    end
    if type(_G.GetAddOnMetadata) == "function" then
        local ok, value = pcall(_G.GetAddOnMetadata, ADDON_NAME, field)
        if ok then return value end
    end
    return nil
end

-- The newest version in CHANGELOG.md. The release PR that writes that
-- section changes this line too, and tools/check_release.py refuses a tag it
-- does not match. Played straight from the repository there is no packager
-- to fill in the TOC's version, so this is the one shown.
ns.RELEASED_VERSION = "0.3.0"

-- The TOC carries @project-version@, which the release packager rewrites to
-- the tag it is building, "v0.2.0" say. Running straight from the repository
-- the keyword arrives unsubstituted, so the version is the changelog's newest.
local function ReadVersion()
    local value = GetMeta("Version")
    if type(value) ~= "string" or value == "" or value:find("@", 1, true) then
        return ns.RELEASED_VERSION
    end
    -- Tags start with a "v"; the version itself does not.
    return (value:gsub("^[vV]", ""))
end

ns.VERSION = ReadVersion()

--- The version as players see it: "v0.2.0".
function ns.VersionLabel()
    return "v" .. ns.VERSION
end

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

-- The house palette, shared with Tradeskills, Farmer, Equipment and Pets so
-- the five look like one set. Good and bad news borrow Tradeskills' profit green
-- and loss red.
ns.COLORS = {
    accent    = "ffc8a44d",
    good      = "ff4fd18b",
    bad       = "ffe5604f",
    muted     = "ff7a8089",
    warn      = "ffe8c15a",
    text      = "ffe6e8ec",
}

local PREFIX = "|c" .. ns.COLORS.accent .. "Butler|r "

local function Join(...)
    local n = select("#", ...)
    if n == 0 then return "" end

    local parts = {}
    for i = 1, n do
        parts[i] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
end

-- Checks kept for Claude (the owner asked 2026-10-10): while a check such as
-- the probe runs, every line it prints is kept as well, and ns.KeepCheck
-- saves them as lastProbe in the account save, replacing the last one. The
-- game writes the save on /reload or logout, so the results can be read from
-- there instead of from screenshots.
local kept

--- A printed line as plain text: colours, links and icons taken out. A
--- secret value never reaches the save.
local function Plain(line)
    local ok, text = pcall(function()
        local isSecret = _G.issecretvalue
        if type(isSecret) == "function" and isSecret(line) then return "(secret)" end
        local plain = table.concat({ tostring(line) })
        plain = plain:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        plain = plain:gsub("|H.-|h", ""):gsub("|h", ""):gsub("|T.-|t", "")
        return plain
    end)
    return ok and text or "(unreadable)"
end

local function Keep(line)
    if kept then kept[#kept + 1] = Plain(line) end
end

function ns.Print(...)
    local frame = DEFAULT_CHAT_FRAME
    if frame then
        local line = PREFIX .. Join(...)
        frame:AddMessage(line)
        Keep(line)
    end
end

-- Raw line with no prefix, for multi-line reports where the prefix is noise.
function ns.PrintRaw(...)
    local frame = DEFAULT_CHAT_FRAME
    if frame then
        local line = Join(...)
        frame:AddMessage(line)
        Keep(line)
    end
end

function ns.Debug(...)
    if ns.db and ns.db.debug then
        ns.PrintRaw("|c" .. ns.COLORS.muted .. "Butler debug|r " .. Join(...))
    end
end

function ns.Warn(...)
    ns.Print("|c" .. ns.COLORS.warn .. Join(...) .. "|r")
end

--- Runs fn, a check that prints to chat, and saves what it printed as
--- lastProbe: which check, when, the addon version and the lines. Chat shows
--- the same as before, plus one line saying it was kept.
function ns.KeepCheck(name, fn, ...)
    kept = {}
    local ok, err = pcall(fn, ...)
    local lines = kept
    kept = nil
    if not ok then lines[#lines + 1] = "error: " .. Plain(err) end

    local db = ns.db
    if type(db) == "table" then
        db.lastProbe = {
            check = name,
            at = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or nil,
            version = ns.VERSION,
            lines = lines,
        }
        ns.Print(L["Saved for Claude, /reload to write it."])
    end
    if not ok then error(err, 0) end
end

--------------------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------------------

ns.modules = {}
ns.moduleOrder = {}

local moduleProto = {}
moduleProto.__index = moduleProto

function moduleProto:RegisterEvent(event, fn)
    return ns.RegisterEvent(self, event, fn or self[event])
end

function moduleProto:UnregisterEvent(event)
    return ns.UnregisterEvent(self, event)
end

function ns.NewModule(name)
    assert(type(name) == "string", "module name must be a string")
    assert(not ns.modules[name], "duplicate module: " .. name)

    local module = setmetatable({ moduleName = name }, moduleProto)
    ns.modules[name] = module
    ns.moduleOrder[#ns.moduleOrder + 1] = module
    ns[name] = module
    return module
end

--------------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "BlackthornesButlerEventFrame")
ns.eventFrame = eventFrame

local handlers = {}
local unknownEvents = {}

--- Register an event handler.
-- On Forever, registering an event the client does not know raises a Lua error
-- rather than failing quietly, so every registration goes through pcall.
function ns.RegisterEvent(owner, event, fn)
    if type(fn) ~= "function" then
        ns.Debug("RegisterEvent: no handler for", event)
        return false
    end

    local list = handlers[event]
    if not list then
        if unknownEvents[event] then return false end

        local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            unknownEvents[event] = err or true
            ns.Debug("event not supported by this client:", event)
            return false
        end
        list = {}
        handlers[event] = list
    end

    list[#list + 1] = { owner = owner, fn = fn }
    return true
end

function ns.UnregisterEvent(owner, event)
    local list = handlers[event]
    if not list then return false end

    for i = #list, 1, -1 do
        if list[i].owner == owner then
            table.remove(list, i)
        end
    end

    if #list == 0 then
        handlers[event] = nil
        pcall(eventFrame.UnregisterEvent, eventFrame, event)
    end
    return true
end

function ns.GetUnknownEvents()
    return unknownEvents
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end

    -- One handler erroring must not swallow the rest.
    for i = 1, #list do
        local entry = list[i]
        if entry then
            local ok, err = pcall(entry.fn, entry.owner, event, ...)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local initialized = false
local enabled = false

local function RunLifecycle(method)
    for i = 1, #ns.moduleOrder do
        local module = ns.moduleOrder[i]
        local fn = module[method]
        if type(fn) == "function" then
            local ok, err = pcall(fn, module)
            if not ok then
                ns.Warn(L.Format("module %s:%s failed", module.moduleName, method))
                geterrorhandler()(err)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 40,
    debug = false,

    -- Minimap button: where it sits on the ring, how far off the edge, and
    -- whether it is there at all. Further round than Tradeskills' (170
    -- degrees), Farmer's (200), Equipment's (230) and Pets' (260), so the
    -- five do not start stacked.
    minimapAngle = math.rad(290),
    minimapGap = 16, -- kept to match the others' saves; the button sits on the ring
    minimapHidden = false,

    -- The settings window (UI/SettingsPages.lua): its words under every row
    -- rather than in tooltips, and Tradeskills' Text size. The page it was
    -- left on is settingsPage, which has no default.
    settingsDescriptions = false,
    textSize = "normal",

    -- Window style: "titanforged" (the house look) or "blizzard" (the
    -- game's own frames, buttons and tick boxes, asked 2026-10-10). Read at
    -- login, so a change waits for /reload. See UI/BlizzardLook.lua.
    windowStyle = "titanforged",

    -- The Butler window comes up by itself at a vendor, and goes when the
    -- vendor closes.
    openAtVendor = true,

    -- And at every mailbox (where it takes over from Tradeskills' mail
    -- panel), and at the bank when there is something to move there
    -- (Logic/Errands.lua), going when it closes.
    openAtMailbox = true,
    openAtBank = true,

    -- After a mail Butler filled is sent, the next one is filled at once
    -- (Errands:Sent, asked 2026-10-11).
    fillNext = true,

    -- Gear that is an upgrade for another of the player's characters goes
    -- under Mail to them only when this is ticked (Verdicts:AltUpgradesOn;
    -- the owner asked 2026-10-13 for it off by default). Never rename it.
    altUpgrades = false,

    -- On the character Tradeskills names as the disenchanter, every green
    -- it can break goes under Disenchant, whatever it is worth
    -- (Verdicts:GreensHere; the owner asked 2026-10-14 for it off by
    -- default). Never rename it.
    disenchantGreens = false,

    -- Levelling Enchanting and Tradeskills' disenchanter take a green even
    -- when a vendor or the auction house pays more (Verdicts:SellsForMore;
    -- a player asked, the owner said yes, 2026-10-16, off by default).
    -- Never rename it.
    disenchantAnyPrice = false,

    -- A bag item a known craft makes worth more goes under Craft, with a
    -- Queue button that puts it in Tradeskills' queue (Verdicts:CraftPays;
    -- a player asked, the owner said build it, 2026-10-19, off by
    -- default). Never rename it.
    craftPays = false,

    -- The free bag space number on the backpack button (UI/FreeSpace.lua,
    -- asked 2026-10-11).
    freeSpace = true,
    -- Which of the player's characters hold an item, on its tooltip
    -- (UI/WhoHas.lua, the owner said build it 2026-10-11). Never rename it.
    whoHas = true,
    -- Butler's verdict as the last line on the tooltips of carried items
    -- (UI/VerdictTip.lua, the owner said yes 2026-10-13). Never rename it.
    verdictTip = true,
    -- A small can on the item worth the least while the bags are full
    -- (UI/Trash.lua, the owner asked 2026-10-13). Never rename it.
    trashCan = true,
    -- A popup beside the loot window that swaps the cheapest item for loot
    -- worth more while the bags are full (UI/SwapWhenFull.lua, the owner
    -- said build it 2026-10-28). Off unless ticked. Never rename it.
    swapWhenFull = false,
    -- Shift-click at a vendor opens the Buy more box, for any amount of an
    -- item at once (UI/BuyMany.lua, the owner asked 2026-10-14). Never
    -- rename it.
    buyMany = true,
    -- Moroes's "You rang?" and "Now, where was I?" when the player opens and
    -- closes the window (the owner asked 2026-10-11).
    voice = true,

    -- Butler learns from what the player does: a buyback, hand sales, hand
    -- mail (Logic/Learning.lua, asked 2026-10-11). What it learned is kept
    -- in learned and learnTally, made when first needed; never rename them.
    learn = true,

    -- At the auction house, each item an open quest needs gets a row with
    -- its price and a Buy button (Logic/QuestBuy.lua, a player asked, the
    -- owner said yes 2026-10-18, off unless ticked). Never rename it.
    questBuy = false,

    -- The cheapest craft for the next skill point in each profession, at
    -- the end of Jobs (Logic/SkillUp.lua, a player asked, the owner said
    -- build it 2026-10-19, off unless ticked). Never rename it.
    skillUpLine = false,

    -- Logging in on a character with a job for the craft queue brings the
    -- window up on its steps (Logic/Jobs.lua, asked 2026-10-11).
    jobsAtLogin = true,

    -- Class spells to train lead the Jobs group, with their cost, Train
    -- all at the trainer and a word in chat at each level
    -- (Logic/ClassTraining.lua, the owner said build it 2026-10-13). What
    -- it learns at trainers is kept in classTrainingData. Never rename
    -- either.
    classTraining = true,

    -- Gold goals at the bottom of the window: class spells, profession
    -- training and riding, each with a bar of the purse against its price
    -- (Logic/GoldGoals.lua, the owner said build it 2026-10-13). Trainers'
    -- prices and every character's goals are kept in goldGoalsData. Never
    -- rename either.
    goldGoals = true,

    -- Also kept here, never renamed (made when first needed, so not given
    -- defaults): alwaysKeep, alwaysSell and alwaysBank ([itemID] = true, the player's
    -- right-click choices), alwaysMail ([itemID] = a character's short name)
    -- sellTest (what /bbutler selltest found) and sellBelow (copper, the
    -- player's Sell below amount; nil is off) and windowScale (the
    -- window's size from its corner grip; 1 is the normal size), and
    -- jobsIgnored ([full name] = when, a character's jobs put away until it
    -- next logs in; Logic/Jobs.lua).
}

-- Per character, because bags are: what one character carries is its own.
-- Holds folded (which groups of the Butler window are folded away), made
-- when first needed.
local CHAR_DEFAULTS = {
}

local function ApplyDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if db[key] == nil then
            db[key] = value
        end
    end
end

local function LoadSavedVariables()
    if type(BlackthornesButlerDB) ~= "table" then
        BlackthornesButlerDB = {}
    end
    if type(BlackthornesButlerCharDB) ~= "table" then
        BlackthornesButlerCharDB = {}
    end

    ApplyDefaults(BlackthornesButlerDB, DEFAULTS)
    ApplyDefaults(BlackthornesButlerCharDB, CHAR_DEFAULTS)

    ns.db = BlackthornesButlerDB
    ns.charDB = BlackthornesButlerCharDB
end

ns.LoadSavedVariables = LoadSavedVariables

-- Read-only: a settings page can put window positions back from here.
ns.DEFAULTS = DEFAULTS

local bootstrap = ns.NewModule("Bootstrap")

function bootstrap:ADDON_LOADED(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME or initialized then return end
    initialized = true

    LoadSavedVariables()
    RunLifecycle("OnInitialize")
end

function bootstrap:PLAYER_LOGIN()
    if enabled then return end
    enabled = true
    RunLifecycle("OnEnable")
end

ns.RegisterEvent(bootstrap, "ADDON_LOADED", bootstrap.ADDON_LOADED)
ns.RegisterEvent(bootstrap, "PLAYER_LOGIN", bootstrap.PLAYER_LOGIN)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

ns.commands = {}
ns.commandOrder = {}

--- Register a `/bbutler <name>` subcommand.
function ns.RegisterCommand(name, usage, fn)
    ns.commands[name] = { usage = usage, fn = fn }
    ns.commandOrder[#ns.commandOrder + 1] = name
end

local function ShowHelp()
    ns.Print(("|c%sBlackthornes Butler|r %s"):format(ns.COLORS.accent, ns.VersionLabel()))

    for i = 1, #ns.commandOrder do
        local name = ns.commandOrder[i]
        local command = ns.commands[name]
        ns.PrintRaw(("  |c%s/bbutler %s|r  |c%s%s|r"):format(
            ns.COLORS.accent, name, ns.COLORS.muted, command.usage or ""))
    end
end

ns.RegisterCommand("help", L["show this list"], ShowHelp)

--- Typed only and left out of help (the owner, 2026-10-23): checks and debug
--- are for tracking down a problem, not for players. Set straight in
--- ns.commands, so help and Settings never list it.
function ns.RegisterHiddenCommand(name, fn)
    ns.commands[name] = { fn = fn, hidden = true }
end

ns.RegisterHiddenCommand("debug", function(rest)
    if not ns.db then return end
    local word = (rest or ""):lower():match("^%s*(%S*)")
    if word == "on" then
        ns.db.debug = true
    elseif word == "off" then
        ns.db.debug = false
    else
        ns.db.debug = not ns.db.debug
    end
    ns.Print(ns.db.debug and "debug on" or "debug off")
end)

SLASH_BLACKTHORNESBUTLER1 = "/bbutler"
SLASH_BLACKTHORNESBUTLER2 = "/butler"

-- Named rather than anonymous so the test suite can drive it directly; the
-- slash routing is where a command goes wrong, so it is worth testing.
function ns.HandleSlash(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local keyword, rest = input:match("^(%S+)%s*(.*)$")
    if not keyword then
        if ns.UI and ns.UI.Toggle then
            ns.UI:Toggle()
        else
            ShowHelp()
        end
        return
    end

    local command = ns.commands[keyword:lower()]
    if not command then
        ns.Warn(L.Format("unknown command: %s", keyword))
        ShowHelp()
        return
    end

    -- Wrapped because a command that errors is otherwise completely silent:
    -- this client does not show Lua errors unless scriptErrors is on, so a
    -- broken command and one that did nothing look identical from the chat
    -- frame.
    local ok, err = pcall(command.fn, rest or "")

    -- Most commands flip something the settings page shows; keep it honest
    -- if it happens to be open. Before the error handler, which may raise.
    if ns.SettingsUI then
        pcall(ns.SettingsUI.Refresh, ns.SettingsUI)
    end
    if ns.UI then
        pcall(ns.UI.Refresh, ns.UI)
    end

    if not ok then
        ns.Warn(L.Format("/bbutler %s failed: %s", keyword, tostring(err)))
        geterrorhandler()(err)
    end
end

SlashCmdList["BLACKTHORNESBUTLER"] = ns.HandleSlash
