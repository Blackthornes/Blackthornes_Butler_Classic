-- Blackthornes Butler -- Probe/Probe.lua
-- /bbutler probe: ask the running client what it actually supports for bags,
-- vendors and mail, rather than trusting documentation written for another
-- version of the game, and say which of the other Blackthornes addons are
-- loaded for Butler to ask.
--
-- Same idea as Tradeskills' /bts probe, Equipment's /beq probe and Pets'
-- /bpet probe. It only reads: nothing is changed, sold, sent or saved apart
-- from the probe's own lines (ns.KeepCheck). Every call is inside a pcall,
-- because Forever hands out secret values in instances that raise when
-- touched.
--
-- The item list and Sell at a vendor lean on these; what the client answers
-- goes in docs/FOREVER_API_FINDINGS.md, so later features are built on it
-- instead of on a guess. It also says what /bbutler selltest found.

local _, ns = ...

local Probe = ns.NewModule("Probe")

-- The calls the plan needs: reading the bags (retail C_Container and the
-- classic globals), an item's price, quality and quest flags, selling at a
-- vendor, the mail form, and the bank.
local APIS = {
    "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo",
    "C_Container.GetContainerNumFreeSlots", "C_Container.GetBagName",
    "C_Container.GetContainerItemLink", "C_Container.GetContainerItemQuestInfo",
    "C_Container.UseContainerItem", "C_Container.PickupContainerItem",
    "GetContainerNumSlots", "GetContainerItemInfo", "UseContainerItem",
    "C_Item.GetItemInfo", "GetItemInfo", "C_Item.GetItemInfoInstant", "GetItemInfoInstant",
    "C_Item.RequestLoadItemDataByID", "C_Item.IsBound", "C_TooltipInfo.GetBagItem",
    "C_MerchantFrame.IsSellAllJunkEnabled", "C_MerchantFrame.SellAllJunkItems",
    "GetNumBuybackItems", "GetBuybackItemInfo", "GetBuybackItemLink", "BuybackItem",
    "SendMail", "hooksecurefunc",
    "SetSendMailShowing", "ClickSendMailItemButton", "GetSendMailItem",
    "C_Bank.CanUseBank", "C_QuestLog.GetNumQuestLogEntries",
    "GetMerchantNumItems", "GetMerchantItemLink", "C_MerchantFrame.GetItemInfo",
    "GetMerchantItemInfo", "BuyMerchantItem", "GetInventoryItemID", "C_TooltipInfo.GetMerchantItem",
}

-- The other four, and the call each answers Butler through ("Butler:Advise",
-- Logic/Sisters.lua).
local SISTERS = {
    { name = "Tradeskills", global = "BlackthornesTS" },
    { name = "Equipment", global = "BlackthornesEquipment" },
    { name = "Farmer", global = "BlackthornesFarmer" },
    { name = "Pets", global = "BlackthornesPets" },
}

local function Line(label, value)
    local ok, text = pcall(tostring, value)
    ns.PrintRaw(("  |c%s%s|r  %s"):format(ns.COLORS.muted, label, ok and text or "(unreadable)"))
end

local function Resolve(path)
    local value = _G
    for part in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

local function Has(path)
    return type(Resolve(path)) == "function"
end

local function Line(label, value)
    local ok, text = pcall(tostring, value)
    ns.PrintRaw(("  |c%s%s|r  %s"):format(ns.COLORS.muted, label, ok and text or "(unreadable)"))
end

--- A client value as plain text. In instances and on some units Forever hands
--- back secret values. tostring of one stays secret, and so does joining it
--- with "..", which the client allows; only table.concat and comparisons
--- raise. So ask the client first, where it can say, and otherwise prove the
--- text survives table.concat before handing it on.
local function Text(value)
    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" then
        local ok, secret = pcall(isSecret, value)
        if not ok or secret then return "(secret)" end
    end
    local ok, text = pcall(function()
        local plain = tostring(value)
        return table.concat({ plain })
    end)
    return ok and text or "(secret)"
end

--- A table a call returned, as its size and up to eight of its fields, so a
--- list of pets or a pet's info can be read without a second probe. A list
--- shows its first entry's fields.
local function Summary(tbl)
    local ok, text = pcall(function()
        local count = 0
        for _ in pairs(tbl) do count = count + 1 end
        local sample, label = tbl, "table of " .. count
        if type(tbl[1]) == "table" then
            sample, label = tbl[1], label .. ", first"
        end
        local keys = {}
        for key in pairs(sample) do keys[#keys + 1] = Text(key) end
        table.sort(keys)
        local parts = {}
        for i = 1, math.min(#keys, 8) do
            local value = sample[keys[i]]
            if value == nil then value = sample[tonumber(keys[i])] end
            parts[i] = keys[i] .. "=" .. (type(value) == "table" and "table" or Text(value))
        end
        return label .. (#parts > 0 and (": " .. table.concat(parts, ", ")) or "")
    end)
    return ok and text or "a table (unreadable)"
end

--- Call a global (or a dotted C_ path) inside a pcall and join what it
--- returns, or say why not.
local function Read(name, ...)
    if not Has(name) then return "absent" end
    local results = { pcall(Resolve(name), ...) }
    if not results[1] then return "raised" end
    if #results == 1 then return "nothing" end
    if type(results[2]) == "table" then return Summary(results[2]) end

    local parts = {}
    for i = 2, #results do parts[#parts + 1] = Text(results[i]) end
    return table.concat(parts, ", ")
end

--- Whether a sister addon is loaded, and whether it answers Butler yet.
local function Sister(info)
    local global = rawget(_G, info.global)
    if type(global) ~= "table" then return "not loaded" end
    local version = type(global.VERSION) == "string" and global.VERSION or "?"
    local butler = rawget(global, "Butler")
    local answers = type(butler) == "table" and type(butler.Advise) == "function"
    return ("loaded (%s), %s"):format(version, answers and "answers Butler" or "no Butler call (update it)")
end

--- The first item in the backpack, as the bag calls read it.
local function FirstItem()
    for slot = 1, 40 do
        local info = Resolve("C_Container.GetContainerItemInfo")
        if type(info) ~= "function" then return "C_Container.GetContainerItemInfo absent" end
        local ok, item = pcall(info, 0, slot)
        if not ok then return "raised" end
        if type(item) == "table" then
            return ("slot %d: %s"):format(slot, Summary(item))
        end
    end
    return "backpack empty"
end

-- How many items the Forever client's game tables give Butler, and for each
-- bag slot the family the client says beside the one the tables say, so a
-- report shows whether the two agree (Data/ForeverItems.lua).
local function ForeverTables()
    local data = ns.ForeverItems
    if not data then return "missing" end
    local prices, bags = 0, 0
    for _ in pairs(data.SELL or {}) do prices = prices + 1 end
    for _ in pairs(data.BAGS or {}) do bags = bags + 1 end
    local parts = { ("%d sell prices, %d bag kinds"):format(prices, bags) }
    for bag = 1, tonumber(_G.NUM_BAG_SLOTS) or 4 do
        local live = select(2, ns.Items.Call({ "C_Container.GetContainerNumFreeSlots", "GetContainerNumFreeSlots" }, bag))
        local ok, text = pcall(function() return tostring(live) end)
        parts[#parts + 1] = ("bag %d %s/%s"):format(bag, ok and text or "(secret)", tostring(ns.Items.TableBagFamily(bag)))
    end
    return table.concat(parts, ", ")
end

function Probe:Run()
    ns.Print("probe: what this client supports for bags, vendors and mail")

    -- Two lines rather than one per call, so the whole probe fits in the
    -- chat window without scrolling.
    local present, missing = {}, {}
    for _, api in ipairs(APIS) do
        if Has(api) then
            present[#present + 1] = api
        else
            missing[#missing + 1] = api
        end
    end
    Line("has", #present > 0 and table.concat(present, ", ") or "none of them")
    Line("missing", #missing > 0 and table.concat(missing, ", ") or "nothing")

    -- The Blizzard window style draws with the game's own art; this says
    -- which pieces the client has (UI/BlizzardLook.lua).
    if ns.BlizzardLook then
        for _, text in ipairs(ns.BlizzardLook.ProbeLines()) do
            local name, value = text:match("^(.-): (.*)$")
            Line(name or "style", value or text)
        end
    end

    for _, info in ipairs(SISTERS) do
        Line(info.name, Sister(info))
    end

    Line("backpack slots", Read("C_Container.GetContainerNumSlots", 0))
    Line("first item", FirstItem())
    Line("buyback", Read("GetNumBuybackItems"))
    if ns.Selling then Line("sell from Butler", ns.Selling:ProbeText()) end
    if ns.Disenchanting then Line("disenchant", ns.Disenchanting:ProbeText()) end
    if ns.FreeSpace then Line("free bag space", ns.FreeSpace:ProbeText()) end
    if ns.WhoHas then Line("who has it", ns.WhoHas:ProbeText()) end
    if ns.VerdictTip then Line("verdict on tooltips", ns.VerdictTip:ProbeText()) end
    if ns.VendorPrices then Line("vendor prices", ns.VendorPrices:ProbeText()) end
    if ns.Trash then Line("trash can", ns.Trash:ProbeText()) end
    if ns.SwapWhenFull then Line("swap when full", ns.SwapWhenFull:ProbeText()) end
    if ns.Ammo then Line("ammo", ns.Ammo:ProbeText()) end
    if ns.BuyManyUI then Line("buy more", ns.BuyManyUI:ProbeText()) end
    if ns.ClassTraining then Line("class training", ns.ClassTraining:ProbeText()) end
    if ns.GoldGoals then Line("gold goals", ns.GoldGoals:ProbeText()) end
    Line("forever tables", ForeverTables())
    if ns.Jobs then Line("jobs", ns.Jobs:ProbeText()) end
    if ns.Quests then Line("quest items", ns.Quests:ProbeText()) end
    if ns.QuestBuy then Line("buy quest items", ns.QuestBuy:ProbeText()) end
    if ns.BagWindow then Line("bag window", ns.BagWindow:ProbeText()) end
end

ns.RegisterHiddenCommand("probe", function()
    ns.KeepCheck("probe", Probe.Run, Probe)
end)
