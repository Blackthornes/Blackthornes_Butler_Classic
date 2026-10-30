-- Shared test environment: enough of the WoW client to load the addon.
--
-- Not a test itself -- runtests.py only runs tools/test_*.lua -- this is what
-- each suite calls to get a loaded addon and a chat frame that remembers what
-- was printed to it.
--
--   local env = dofile(lfs_cwd .. "/tools/testenv.lua")
--   local ns = env.Load()

local env = {}

local ROOT = lfs_cwd or "."
local ADDON = "Blackthornes_Butler"

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

-- Any method a test does not care about answers as a no-op, so a window can
-- build its panels, labels and anchors undisturbed.
local function Stub(fields)
    local frame = fields or {}

    frame._shown = frame._shown or false
    frame._height = frame._height or 300
    frame._text = frame._text or ""

    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:IsShown() return self._shown end
    function frame:SetShown(value) self._shown = value and true or false end

    function frame:SetHeight(value) self._height = value end
    function frame:GetHeight() return self._height end
    function frame:SetWidth(value) self._width = value end
    function frame:GetWidth() return self._width or 500 end

    function frame:SetText(value) self._text = tostring(value or "") end
    function frame:SetTextColor(r, g, b) self._color = { r, g, b } end
    function frame:GetText() return self._text end
    -- About as wide as the game's small font: 6 pixels a character.
    function frame:GetStringWidth() return #(self._text or "") * 6 end

    function frame:SetScript(script, fn) self._scripts[script] = fn end
    function frame:GetScript(script) return self._scripts[script] end
    -- Runs after whatever script was there, as the game's HookScript does.
    function frame:HookScript(script, fn)
        local before = self._scripts[script]
        self._scripts[script] = function(...)
            if before then before(...) end
            return fn(...)
        end
    end

    function frame:GetPoint()
        local p = self._point
        if p and #p == 5 then return p[1], p[2], p[3], p[4], p[5] end
        return "CENTER", nil, "CENTER", 0, 40
    end
    -- Nil until a test places the frame on screen, as before layout.
    function frame:GetLeft() return self._left end
    function frame:GetTop() return self._top end
    function frame:GetFrameLevel() return rawget(self, "_frameLevel") or 1 end
    function frame:SetFrameLevel(value) self._frameLevel = value end
    function frame:GetFrameStrata() return rawget(self, "_strata") or "MEDIUM" end
    function frame:SetFrameStrata(value) self._strata = value end
    function frame:SetAttribute(key, value) self._attributes[key] = value end
    function frame:GetAttribute(key) return self._attributes[key] end

    -- Recorded so a test can check where something was anchored.
    function frame:SetPoint(...) self._point = { ... } end
    function frame:SetParent(parent) self._parent = parent end
    function frame:GetParent() return rawget(self, "_parent") end
    function frame:GetCenter() return self._cx or 0, self._cy or 0 end
    function frame:GetEffectiveScale() return 1 end

    function frame:RegisterEvent(event) self._events[event] = true end
    function frame:UnregisterEvent(event) self._events[event] = nil end

    function frame:CreateTexture() return Stub() end
    function frame:CreateFontString() return Stub() end

    function frame:SetMinMaxValues(low, high) self._min, self._max = low, high end
    function frame:SetValue(value) self._value = value end
    function frame:GetValue() return self._value or 0 end

    frame._scripts = frame._scripts or {}
    frame._events = frame._events or {}
    frame._attributes = frame._attributes or {}

    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

env.Stub = Stub

--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

function env.InstallClient()
    env.chat = {}

    _G.UIParent = Stub()
    -- The arrows' shared table (one Blackthornes arrow at a time) would
    -- carry one suite's arrow into the next.
    _G.BlackthornesArrows = nil

    -- A default-sized minimap, and a cursor parked somewhere unambiguous so a
    -- simulated drag lands at a known angle.
    _G.Minimap = Stub({ _width = 140, _cx = 500, _cy = 500 })
    _G.GetCursorPosition = function() return 600, 500 end

    local function Tooltip()
        return Stub({
            _lines = {},
            SetOwner = function(self) self._lines = {} end,
            AddLine = function(self, text) self._lines[#self._lines + 1] = text end,
            NumLines = function(self) return #self._lines end,
            ClearLines = function(self) self._lines = {} end,
        })
    end
    _G.GameTooltip = Tooltip()
    _G.ItemRefTooltip = Tooltip()

    -- Timers run straight away: a test has nothing to wait for.
    _G.C_Timer = {
        After = function(_, fn) fn() end,
        NewTicker = function(_, fn) return Stub({ _fn = fn }) end,
    }

    -- Theme asks for the default font through pcall and falls back on its
    -- own, so leaving GameFontNormal absent exercises that path.
    _G.GameFontNormal = nil
    _G.Settings = nil
    _G.InterfaceOptions_AddCategory = nil

    _G.CreateFrame = function(_, name, parent)
        local frame = Stub({ _parent = parent })
        if name then _G[name] = frame end
        return frame
    end

    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, message) env.chat[#env.chat + 1] = message end,
    }

    _G.SlashCmdList = {}
    _G.UISpecialFrames = {}
    _G.geterrorhandler = function() return function(err) error(err, 0) end end

    -- Suites share one Lua state; what one suite saved must not leak into the
    -- next.
    _G.BlackthornesButlerDB = nil
    _G.BlackthornesSisterNote = nil
    _G.BlackthornesButlerCharDB = nil
    _G.UnitClass = nil
    _G.UnitLevel = nil
    _G.UnitExists = nil
    _G.UnitName = nil

    -- No bags, vendor or item calls until a suite fakes them (env.FakeBags).
    _G.C_Container = nil
    _G.C_Item = nil
    _G.C_TooltipInfo = nil
    _G.MerchantFrame = nil
    _G.InCombatLockdown = nil
    _G.GetMoney = nil
    _G.NUM_BAG_SLOTS = nil
end

--------------------------------------------------------------------------------
-- Bags
--------------------------------------------------------------------------------

--- A client with bags, items and a vendor. `items` is a list of
--- { bag, slot, id, name, count, quality, price, quest, noValue, class },
--- `price` what a vendor pays for one (nil: the item has not loaded yet).
--- Returns the fake, whose `bags[bag][slot]` the suite can change and whose
--- `used` lists the slots sold through UseContainerItem.
function env.FakeBags(items)
    local fake = { bags = {}, info = {}, used = {}, money = 0, numSlots = 16 }
    for bag = 0, 4 do fake.bags[bag] = {} end

    function fake.Put(item)
        fake.bags[item.bag][item.slot] = item
        fake.info[item.id] = item
    end
    for _, item in ipairs(items or {}) do fake.Put(item) end

    local function Link(item)
        return ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(item.id, item.name)
    end

    _G.NUM_BAG_SLOTS = 4
    _G.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and fake.numSlots or 0 end,
        GetContainerItemInfo = function(bag, slot)
            local item = fake.bags[bag] and fake.bags[bag][slot]
            if not item then return nil end
            return {
                itemID = item.id, hyperlink = Link(item), stackCount = item.count or 1,
                quality = item.quality or 1, isLocked = item.locked or false,
                hasNoValue = item.noValue or false, isBound = item.bound or false,
                iconFileID = 134400,
            }
        end,
        GetContainerItemQuestInfo = function(bag, slot)
            local item = fake.bags[bag] and fake.bags[bag][slot]
            if item and item.quest == "starts" then
                return { isQuestItem = false, questID = 99, isActive = false }
            elseif item and item.quest == "item" then
                return { isQuestItem = true, questID = nil, isActive = false }
            end
            return { isQuestItem = false, isActive = false }
        end,
        UseContainerItem = function(bag, slot)
            local item = fake.bags[bag][slot]
            fake.used[#fake.used + 1] = bag .. ":" .. slot
            if item and fake.canSell then
                fake.money = fake.money + (item.price or 0) * (item.count or 1)
                fake.bags[bag][slot] = nil
            end
        end,
    }
    _G.C_Item = {
        GetItemInfo = function(id)
            local item = fake.info[id]
            if not item or item.price == nil then return nil end
            return item.name, Link(item), item.quality, 1, 1, "Misc", "Misc", item.stack or 20, "", 134400, item.price,
                item.class or 15, item.subclass or 0, item.bind or 0
        end,
        GetItemInfoInstant = function(id)
            local item = fake.info[id]
            return id, "Misc", "Misc", item and item.equipLoc or "", 134400, item and item.class or 15, item and item.subclass or 0
        end,
        RequestLoadItemDataByID = function(id) fake.requested = id end,
    }
    _G.GetMoney = function() return fake.money end
    _G.time = _G.time or os.time
    _G.MerchantFrame = env.Stub()

    env.bags = fake
    return fake
end

--- Turn every module on, as PLAYER_LOGIN does.
function env.Enable(ns)
    for _, module in ipairs(ns.moduleOrder) do
        if module.OnEnable then module:OnEnable() end
    end
end

--- Send an event to the addon as the client would.
function env.Fire(event, ...)
    local handler = _G.BlackthornesButlerEventFrame:GetScript("OnEvent")
    -- The game shows and hides its vendor window with these.
    if event == "MERCHANT_SHOW" and _G.MerchantFrame then _G.MerchantFrame:Show() end
    if event == "MERCHANT_CLOSED" and _G.MerchantFrame then _G.MerchantFrame:Hide() end
    handler(_G.BlackthornesButlerEventFrame, event, ...)
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

--- The Lua files the TOC loads, in order. Read from the TOC itself, so a new
-- file is tested the moment it is listed and there is no second list here to
-- forget.
function env.TocFiles()
    local files = {}
    local handle = assert(io.open(ROOT .. "/" .. ADDON .. ".toc", "r"))
    for line in handle:lines() do
        line = line:gsub("\r$", "")
        if line ~= "" and not line:find("^#") and line:find("%.lua$") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    handle:close()
    return files
end

--- Load the addon exactly as the TOC does, and return its namespace.
--- `locale` ("deDE") loads it as a client in that language would.
function env.Load(locale)
    env.InstallClient()
    _G.GetLocale = nil
    if locale then _G.GetLocale = function() return locale end end

    local ns = {}
    for _, file in ipairs(env.TocFiles()) do
        local chunk = assert(loadfile(ROOT .. "/" .. file))
        chunk(ADDON, ns)
    end

    -- ADDON_LOADED installs saved variables; tests that skip the event loop
    -- still need ns.db to exist.
    ns.LoadSavedVariables()
    -- "One Window:" is on unless unticked; suites test Butler's own windows
    -- unless they tick it (test_onewindow.lua checks the default).
    if ns.db then ns.db.oneWindow = false end

    env.ns = ns
    return ns
end

--- `text` without colour codes, for checks on words that name items in
--- their rarity colour (Items:ColorName). Anything not a string as it is.
function env.Plain(text)
    if type(text) ~= "string" then return text end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

--- Everything printed to chat since the addon loaded, as one string.
function env.ChatText()
    return table.concat(env.chat, "\n")
end

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

function env.NewSuite(name)
    local suite = { name = name, checks = 0 }

    function suite.check(label, ok, detail)
        suite.checks = suite.checks + 1
        if not ok then
            error(("%s: %s%s"):format(name, label,
                detail and ("  -> " .. tostring(detail)) or ""), 0)
        end
    end

    function suite.done()
        print(("  %s: %d checks passed"):format(name, suite.checks))
    end

    return suite
end

return env
