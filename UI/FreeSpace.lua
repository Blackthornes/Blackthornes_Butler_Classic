-- Blackthornes Butler -- UI/FreeSpace.lua
-- How many bag slots are free, as a number on the backpack button of the
-- game's bag bar (the owner picked the place from a mockup, 2026-10-11).
--
-- The number is Butler's own frame, a child of the button so it shows,
-- hides, scales and moves with it (Edit Mode included); it takes no mouse
-- and runs no game code, and nothing is written on the button. The free
-- slots of each bag go on the button's tooltip, added after the game's own
-- lines through HookScript.
--
-- Only bags that take anything count: a profession bag (herbs, ore, soul
-- shards) and the reagent bag take only certain items, so they get their
-- own tooltip lines and stay out of the number.
--
-- Smooth play: bag events only mark the count stale, and it is read once,
-- 0.2 s after the burst, a handful of calls; the text is set only when the
-- number or its colour changed. Nothing runs while the bag bar is hidden.

local _, ns = ...
local L = ns.L

local FreeSpace = ns.NewModule("FreeSpace")

-- The game's backpack button, and its own free slots count (shown only when
-- the client's "show free bag slots" option is on; Butler then stands down
-- so there are never two numbers).
FreeSpace.BUTTON = "MainMenuBarBackpackButton"
FreeSpace.GAME_COUNT = "MainMenuBarBackpackButtonCount"

-- Amber at this many free or fewer, red at RED or fewer.
FreeSpace.AMBER = 8
FreeSpace.RED = 3
FreeSpace.SETTLE = 0.2
-- The number's size on the bag button, bold with an outline (the owner,
-- 2026-10-20: the game's stack count size was hard to read).
FreeSpace.TEXT_SIZE = 18

FreeSpace.COLORS = {
    plenty = { 1, 1, 1 },
    low = { 1, 0.69, 0.16 },
    out = { 1, 0.28, 0.24 },
}

local function Call(name, ...)
    local container = _G.C_Container
    local fn = container and container[name] or _G[name]
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return select(2, unpack(results))
end

-- A client number as a plain one: a secret value (instances) or anything
-- else that will not compare reads as nil.
local function Number(value)
    local ok, n = pcall(function()
        local n = tonumber(value)
        if n and n >= 0 then return n + 0 end
    end)
    if ok and type(n) == "number" then return n end
    return nil
end

local function IsReagentBag(bag)
    local reagent = ns.Bags and ns.Bags.ReagentBag and ns.Bags.ReagentBag()
    return reagent ~= nil and bag == reagent
end

--- A bag's name in its rarity colour, read only for the tooltip: the bag
--- item in that bag slot (the backpack has none and stays as it is).
function FreeSpace.BagName(entry)
    if not (entry.bag and entry.bag > 0) then return entry.name end
    local Items = ns.Items
    local slot = Items.Call({ "C_Container.ContainerIDToInventoryID", "ContainerIDToInventoryID" }, entry.bag)
    local itemID = type(slot) == "number" and tonumber((Items.Call({ "GetInventoryItemID" }, "player", slot)))
    if not itemID then return entry.name end
    return Items:ColorName(entry.name, itemID)
end

--- What the bags hold now: free and total slots over the bags that take
--- anything, and a line for each bag. Nil when the client says nothing.
function FreeSpace.Read()
    local result = { free = 0, total = 0, bags = {}, special = {} }
    local any = false
    for _, bag in ipairs(ns.Bags.BagIDs()) do
        local total = Number(Call("GetContainerNumSlots", bag))
        if total and total > 0 then
            local free, family = Call("GetContainerNumFreeSlots", bag)
            free = Number(free)
            if free then
                any = true
                local name = Call("GetBagName", bag)
                if type(name) ~= "string" or name == "" then
                    name = bag == 0 and L["Backpack"] or L.Format("Bag %d", bag)
                end
                local entry = { bag = bag, name = name, free = free, total = total }
                family = Number(family) or ns.Items.TableBagFamily(bag) or 0
                local general = family == 0 and not IsReagentBag(bag)
                if general then
                    result.free = result.free + free
                    result.total = result.total + total
                    result.bags[#result.bags + 1] = entry
                else
                    result.special[#result.special + 1] = entry
                end
            end
        end
    end
    return any and result or nil
end

--- "plenty", "low" or "out" for this many free slots.
function FreeSpace.Level(free)
    if free <= FreeSpace.RED then return "out" end
    if free <= FreeSpace.AMBER then return "low" end
    return "plenty"
end

function FreeSpace:Enabled()
    return ns.db ~= nil and ns.db.freeSpace ~= false
end

function FreeSpace:Button()
    local button = _G[self.BUTTON]
    if type(button) == "table" then return button end
    return nil
end

--- The game's own count text on the button, or nil when it shows none.
function FreeSpace:GameText()
    local count = _G[self.GAME_COUNT]
    if type(count) ~= "table" then return nil, nil end
    local ok, text = pcall(function()
        local text = count:GetText()
        if count:IsShown() and type(text) == "string" and text ~= "" then return text end
    end)
    if ok and text then return text, count end
    return nil, count
end

--- Is the game already showing the free slots on the button? Only a number
--- that matches ours counts: the game's own count can be something else
--- (a hunter's ammo, 1307), and then Butler's takes its place.
function FreeSpace:GameCounts()
    local text = self:GameText()
    if not text then return false end
    local read = self.read
    if not read then return true end
    local shown = tonumber(text:match("%d+"))
    return shown == read.free
end

--- Put the game's own number out of sight (SetAlpha only, never Hide) while
--- ours stands in for it, and back as it was when it does not.
function FreeSpace:VeilGame(on)
    local _, count = self:GameText()
    if on then
        if count and not self.veiled then
            self.veiled = count
            pcall(count.SetAlpha, count, 0)
        end
    elseif self.veiled then
        local veiled = self.veiled
        self.veiled = nil
        pcall(veiled.SetAlpha, veiled, 1)
    end
end

--- Make the number, once, on the backpack button. False on a client with
--- no backpack button (or one a bag addon took away).
function FreeSpace:Attach()
    if self.frame then return true end
    local button = self:Button()
    if not button then return false end

    local frame = CreateFrame("Frame", nil, button)
    frame:SetAllPoints(button)
    frame:EnableMouse(false)
    if frame.SetFrameLevel and button.GetFrameLevel then
        pcall(function() frame:SetFrameLevel(button:GetFrameLevel() + 5) end)
    end

    -- The game's stack count font, so it reads like the counts beside it.
    local made, text = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "NumberFontNormal")
    if not made or not text then text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal") end
    pcall(function()
        local font = text:GetFont()
        if font then text:SetFont(font, FreeSpace.TEXT_SIZE, "THICKOUTLINE") end
    end)
    text:SetPoint("BOTTOMRIGHT", -2, 1)
    text:SetJustifyH("RIGHT")
    frame.text = text

    -- Coming back into view after a bag change it missed (the bar hidden,
    -- or the setting off) reads again.
    frame:SetScript("OnShow", function()
        if FreeSpace.stale then FreeSpace:Changed() end
    end)
    self.frame = frame

    if button.HookScript then
        pcall(button.HookScript, button, "OnEnter", function(owner)
            FreeSpace:AddTooltip(owner)
        end)
    end
    return true
end

--- Put the number on the button as it is now. Sets the text only when it
--- changed.
function FreeSpace:Draw()
    local frame = self.frame
    if not frame then return end
    local read = self.read
    local key
    if self:Enabled() and read and not self:GameCounts() then
        key = read.free .. ":" .. FreeSpace.Level(read.free)
    end
    self:VeilGame(key ~= nil and self:GameText() ~= nil)
    if key == self.drawn then return end
    self.drawn = key
    if not key then
        frame.text:SetText("")
        return
    end
    local color = self.COLORS[FreeSpace.Level(read.free)]
    frame.text:SetText(tostring(read.free))
    frame.text:SetTextColor(color[1], color[2], color[3])
end

--- The bags changed: count again once the burst is over, if anyone can
--- see the number.
function FreeSpace:Changed()
    self.stale = true
    if self.settling or not self:Enabled() then return end
    if not self:Attach() then return end
    if not self.frame:IsVisible() then return end
    self.settling = true
    C_Timer.After(self.SETTLE, function()
        FreeSpace.settling = false
        FreeSpace:Refresh()
    end)
end

--- Count now and draw it.
function FreeSpace:Refresh()
    self.stale = false
    self.read = FreeSpace.Read()
    self:Draw()
    self:DrawAmmo()
end

--- The free slots of each bag, under the game's own tooltip lines.
function FreeSpace:AddTooltip(owner)
    if not self:Enabled() or not GameTooltip then return end
    local ok = pcall(function()
        if GameTooltip.GetOwner and GameTooltip:GetOwner() ~= owner then return end
        local read = FreeSpace.Read()
        if not read then return end
        local color = FreeSpace.COLORS[FreeSpace.Level(read.free)]
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.Format("Free bag space: %d of %d", read.free, read.total),
            color[1], color[2], color[3])
        for _, entry in ipairs(read.bags) do
            GameTooltip:AddDoubleLine(FreeSpace.BagName(entry), L.Format("%d of %d free", entry.free, entry.total),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
        for _, entry in ipairs(read.special) do
            GameTooltip:AddDoubleLine(L.Format("%s (only some items)", FreeSpace.BagName(entry)),
                L.Format("%d of %d free", entry.free, entry.total), 0.6, 0.6, 0.6, 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    if not ok then ns.Debug("free space tooltip failed") end
end

--------------------------------------------------------------------------------
-- The ammo count, on the quiver or pouch itself
--------------------------------------------------------------------------------

--- How many pieces of ammo the ammo bag holds, or nil when there is no ammo
--- bag or the client will not say.
function FreeSpace.AmmoCount()
    if not (ns.Ammo and ns.Ammo.Bag) then return nil end
    local ok, found = pcall(ns.Ammo.Bag, ns.Ammo)
    if not ok or type(found) ~= "table" or not found.bag then return nil end
    local total = Number(Call("GetContainerNumSlots", found.bag))
    if not total then return nil end
    local sum = 0
    for slot = 1, total do
        local info = Call("GetContainerItemInfo", found.bag, slot)
        local count = type(info) == "table" and Number(info.stackCount)
        if count then sum = sum + count end
    end
    return sum, found.bag
end

--- The bag bar's button for a bag number (1 to 4), or nil.
function FreeSpace:BagButton(bag)
    local button = _G["CharacterBag" .. (bag - 1) .. "Slot"]
    if type(button) == "table" then return button end
    return nil
end

--- Put the ammo number on the ammo bag's button, in the game's stack count
--- font like the free slots, and take it off when there is none to show.
function FreeSpace:DrawAmmo()
    local count, bag = nil, nil
    if self:Enabled() then count, bag = FreeSpace.AmmoCount() end
    local button = bag and self:BagButton(bag)
    if self.ammoFrame and (not button or self.ammoFrame:GetParent() ~= button) then
        self.ammoText:SetText("")
        self.ammoDrawn = nil
    end
    if not (count and button) then return end
    local frame = self.ammoFrame
    if not frame or frame:GetParent() ~= button then
        frame = frame or CreateFrame("Frame", nil, button)
        frame:SetParent(button)
        frame:SetAllPoints(button)
        frame:EnableMouse(false)
        pcall(function() frame:SetFrameLevel(button:GetFrameLevel() + 5) end)
        if not self.ammoText or self.ammoFrame ~= frame then
            local made, text = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "NumberFontNormal")
            if not made or not text then text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal") end
            text:SetPoint("BOTTOMRIGHT", -3, 3)
            text:SetJustifyH("RIGHT")
            self.ammoText = text
        end
        self.ammoFrame = frame
        self.ammoDrawn = nil
    end
    local key = tostring(count)
    if key == self.ammoDrawn then return end
    self.ammoDrawn = key
    self.ammoText:SetText(key)
    self.ammoText:SetTextColor(1, 1, 1)
end

--- Turn the number on or off (Settings and /bbutler freespace).
function FreeSpace:SetEnabled(on)
    ns.db.freeSpace = on and true or false
    -- Not a key Draw can make, so it draws whatever it finds.
    self.drawn = false
    if on then
        self.stale = true
        if self:Attach() then self:Refresh() end
    else
        self:Draw()
        self:DrawAmmo()
    end
end

--- One line for /bbutler probe.
function FreeSpace:ProbeText()
    local button = self:Button() and "backpack button found" or "no backpack button"
    local read = FreeSpace.Read()
    local count = read and ("%d of %d free"):format(read.free, read.total) or "no count"
    local game = self:GameCounts() and ", the game shows its own count" or ""
    return button .. ", " .. count .. game
end

function FreeSpace:OnEnable()
    ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function() FreeSpace:Changed() end)
    ns.RegisterEvent(self, "BAG_CONTAINER_UPDATE", function() FreeSpace:Changed() end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() FreeSpace:Changed() end)
end

ns.RegisterCommand("freespace", L["show or hide the free bag space number on your backpack button"], function()
    FreeSpace:SetEnabled(not FreeSpace:Enabled())
    ns.Print(FreeSpace:Enabled() and L["free bag space shows on your backpack button."]
        or L["free bag space no longer shows on your backpack button."])
end)
