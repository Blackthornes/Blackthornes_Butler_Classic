-- Buying any amount of a vendor item at once (the owner asked 2026-10-14:
-- "the ability to purchase 200 of a vendor item at once").
--
-- What must hold:
--   1. Shift-click on a vendor's item opens the Buy more box; a plain
--      click, or Shift-click with a chat box open, does not.
--   2. The box says what the amount comes to before anything is spent.
--   3. Never more than the bags hold, the purse pays for, or the vendor has.
--   4. Buy buys a stack a call until the amount is reached, and says so.
--   5. It stops when the bags fill, the vendor closes or the player clicks
--      Stop, and says why.
--   6. Lots go one a buy; tokens and honor items are left alone.
--   7. /bbutler buy 200 water opens it; /bbutler buy off turns Shift-click off.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("buymany")

local ns = env.Load()
local fake = env.FakeBags({
    { bag = 0, slot = 1, id = 159, name = "Refreshing Spring Water", quality = 1, price = 1, count = 15 },
})
fake.money = 10000
fake.numSlots = 16

-- Water stacks to 20; the vendor's water sells one at a time for 5c,
-- arrows in lots of 200, a limited item, and a token item.
local NAMES = { [159] = "Refreshing Spring Water", [2512] = "Rough Arrow", [4470] = "Simple Wood",
    [4400] = "Shiny Token" }
local STACK = { [159] = 20, [2512] = 200, [4470] = 20, [4400] = 1 }
C_Item.GetItemInfo = function(id)
    if not NAMES[id] then return nil end
    return NAMES[id], "link", 1, 5, 1, "Misc", "Misc", STACK[id], "", 134400, 1
end
C_Item.GetItemCount = function(id)
    local total = 0
    for bag = 0, 4 do
        for _, item in pairs(fake.bags[bag]) do
            if item.id == id then total = total + (item.count or 1) end
        end
    end
    return total
end
C_Item.GetItemFamily = function() return 0 end

local vendor = {
    { id = 159, price = 5, perBuy = 1, available = -1 },
    { id = 2512, price = 10, perBuy = 200, available = -1 },
    { id = 4470, price = 3, perBuy = 1, available = 30 },
    { id = 4400, price = 0, perBuy = 1, available = -1, extended = true },
}
_G.GetMerchantNumItems = function() return #vendor end
_G.GetMerchantItemLink = function(i)
    local item = vendor[i]
    return item and ("|cffffffff|Hitem:%d::|h[%s]|h|r"):format(item.id, NAMES[item.id])
end
_G.GetMerchantItemMaxStack = function(i) return vendor[i] and STACK[vendor[i].id] end
_G.C_MerchantFrame = { GetItemInfo = function(i)
    local item = vendor[i]
    return item and { name = NAMES[item.id], texture = 1, price = item.price, stackCount = item.perBuy,
        numAvailable = item.available, isPurchasable = true, isUsable = true,
        hasExtendedCost = item.extended or false }
end }

-- Buying puts the items in the bags: on the stack first, then empty slots.
local calls = {}
local function Add(id, count)
    for bag = 0, 4 do
        for slot = 1, (bag == 0 and fake.numSlots or 0) do
            local item = fake.bags[bag][slot]
            if item and item.id == id and item.count < STACK[id] then
                local put = math.min(count, STACK[id] - item.count)
                item.count, count = item.count + put, count - put
            end
        end
    end
    for slot = 1, fake.numSlots do
        if count <= 0 then break end
        if not fake.bags[0][slot] then
            local put = math.min(count, STACK[id])
            fake.Put({ bag = 0, slot = slot, id = id, name = NAMES[id], quality = 1, price = 1, count = put })
            count = count - put
        end
    end
end
local afterBuy
_G.BuyMerchantItem = function(i, quantity)
    calls[#calls + 1] = { index = i, quantity = quantity }
    local item = vendor[i]
    local lots = quantity or 1
    local units = item.perBuy > 1 and item.perBuy or lots
    fake.money = fake.money - (item.perBuy > 1 and item.price or item.price * lots)
    if item.available > 0 then item.available = item.available - lots end
    Add(item.id, units)
    if afterBuy then afterBuy() end
end
_G.ChatEdit_GetActiveWindow = function() return nil end
local shift = false
_G.IsShiftKeyDown = function() return shift end

-- The vendor's item buttons.
local buttons = {}
for i = 1, 4 do
    local button = CreateFrame("Button", "MerchantItem" .. i .. "ItemButton")
    button.GetID = function() return i end
    _G["MerchantItem" .. i .. "ItemButton"] = button
    buttons[i] = button
end

env.Enable(ns)
local BuyMany, Box = ns.BuyMany, ns.BuyManyUI
env.Fire("MERCHANT_SHOW")

local function Click(i)
    local script = buttons[i]:GetScript("OnClick")
    if script then script(buttons[i], "LeftButton") end
end

-- 1. Shift-click opens it; a plain click does not.
Click(1)
suite.check("a plain click opens nothing", not Box:IsShown())
shift = true
_G.ChatEdit_GetActiveWindow = function() return {} end
Click(1)
suite.check("Shift-click with a chat box open links the item instead", not Box:IsShown())
_G.ChatEdit_GetActiveWindow = function() return nil end
Click(1)
suite.check("Shift-click opens the Buy more box", Box:IsShown() and Box.index == 1)
suite.check("with the item's name", env.Plain(Box.name:GetText()) == "Refreshing Spring Water")

-- 2. The box says what it comes to; Buy waits for an amount.
suite.check("nothing typed, nothing to buy", Box.plan.state == "none")
Box.box:SetText("200")
Box:Replan()
suite.check("200 comes to 200 for 10s", Box.plan.state == "buy" and Box.plan.count == 200
    and Box.plan.cost == 1000, Box.plan.count)
suite.check("the box says so", Box.total:GetText():find("200 for", 1, true) ~= nil, Box.total:GetText())
suite.check("nothing bought yet", #calls == 0)

-- The whole price shows: the box grows to fit it, never "200 for 7s...".
local function Need(text)
    return 18 + ns.Theme.TextWidth("normal", "How Many:") + 10 + 70 + 10 + ns.Theme.TextWidth("normal", text) + 4 + 18
end
suite.check("the box is wide enough for the price", Box.frame:GetWidth() >= Need(Box.total:GetText()),
    Box.frame:GetWidth())
Box:FitTotal("9999 for 999g 99s 99c")
suite.check("a long price widens the box", Box.frame:GetWidth() > 280 and Box.frame:GetWidth() >= Need("9999 for 999g 99s 99c"),
    Box.frame:GetWidth())
Box:FitTotal("")
suite.check("and it goes back to its usual size", Box.frame:GetWidth() == 280, Box.frame:GetWidth())
Box:Replan()

-- 3. Room: 15 slots free of 20 and 5 more on the stack of 15 = 305.
local plan = BuyMany:Plan(1, 400)
suite.check("never more than the bags hold", plan.count == 305 and plan.short.room == 305, plan.count)
suite.check("and the box says why", BuyMany.Describe(plan) ~= "" and
    select(2, BuyMany.Describe(plan)):find("room for 305", 1, true) ~= nil, select(2, BuyMany.Describe(plan)))
fake.money = 500
plan = BuyMany:Plan(1, 200)
suite.check("never more than the purse pays for", plan.count == 100 and plan.short.gold == 100, plan.count)
fake.money = 3
plan = BuyMany:Plan(1, 200)
suite.check("not even one: no Buy", plan.state == "poor")
fake.money = 10000
plan = BuyMany:Plan(3, 50)
suite.check("never more than a limited vendor has", plan.count == 30 and plan.short.stock == 30, plan.count)

-- 4. Buy: a stack a call until 200.
Box:Buy()
local total = 0
for _, call in ipairs(calls) do total = total + call.quantity end
suite.check("Buy bought 200 water", total == 200, total)
suite.check("a stack at most a call", calls[1].quantity == 20 and #calls == 10, #calls)
suite.check("and paid for it", fake.money == 10000 - 1000, fake.money)
suite.check("chat says what it bought", env.Plain(env.ChatText()):find("bought 200 Refreshing Spring Water", 1, true) ~= nil)
suite.check("the box closes when done", not Box:IsShown())

-- 5. The bags fill: the game's error stops it.
_G.ERR_INV_FULL = "Inventory is full."
calls = {}
Click(1)
Box.box:SetText("60")
Box:Replan()
afterBuy = function()
    if #calls == 1 then env.Fire("UI_ERROR_MESSAGE", 3, "Inventory is full.") end
end
Box:Buy()
suite.check("the bags filling stops it", #calls == 1, #calls)
suite.check("and says why", env.ChatText():find("Stopped early: your bags are full.", 1, true) ~= nil)

-- The vendor closing stops it.
calls = {}
Click(1)
Box.box:SetText("60")
Box:Replan()
afterBuy = function()
    if #calls == 2 then env.Fire("MERCHANT_CLOSED") end
end
Box:Buy()
suite.check("the vendor closing stops it", #calls == 2, #calls)
suite.check("and says so", env.ChatText():find("Stopped early: the vendor window closed.", 1, true) ~= nil)
suite.check("and the box goes", not Box:IsShown())
env.Fire("MERCHANT_SHOW")

-- Stop.
calls = {}
Click(1)
Box.box:SetText("60")
Box:Replan()
afterBuy = function()
    if #calls == 1 then Box:Buy() end
end
Box:Buy()
suite.check("Stop stops it", #calls == 1, #calls)
suite.check("and says so", env.ChatText():find("Stopped early: you clicked Stop.", 1, true) ~= nil)
afterBuy = nil

-- The bags not keeping up: it waits, then calls it stuck.
calls = {}
fake.bags[0] = {}
fake.Put({ bag = 0, slot = 1, id = 159, name = NAMES[159], quality = 1, price = 1, count = 15 })
local now = 0
_G.GetTime = function()
    now = now + 1
    return now
end
local realBuy = _G.BuyMerchantItem
_G.BuyMerchantItem = function(i, quantity) calls[#calls + 1] = { index = i, quantity = quantity } end
Click(1)
Box.box:SetText("100")
Box:Replan()
Box:Buy()
suite.check("it never runs far ahead of the bags", #calls == 3, #calls)
suite.check("and says the vendor stopped", env.ChatText():find("the vendor stopped selling it", 1, true) ~= nil)
_G.BuyMerchantItem = realBuy
_G.GetTime = nil

-- 6. Lots go one a buy, rounded up to whole lots.
calls = {}
plan = BuyMany:Plan(2, 300)
suite.check("300 arrows sold in 200s is 2 lots", plan.lots == 2 and plan.count == 400, plan.count)
BuyMany:Start(plan)
suite.check("each lot its own buy, no quantity", #calls == 2 and calls[1].quantity == nil, #calls)
plan = BuyMany:Plan(4, 5)
suite.check("token items are left to the game", plan.state == "extended")

-- 7. Typed.
Box:Hide()
ns.HandleSlash("buy 25 spring")
suite.check("/bbutler buy 25 spring opens the box", Box:IsShown() and Box.index == 1
    and Box.box:GetText() == "25")
Box:Hide()
ns.HandleSlash("buy off")
suite.check("/bbutler buy off turns it off", ns.db.buyMany == false)
Click(1)
suite.check("then Shift-click opens nothing", not Box:IsShown())
ns.HandleSlash("buy 5 water")
suite.check("typing still opens it", Box:IsShown())
Box:Hide()
ns.HandleSlash("buy on")
suite.check("/bbutler buy on turns it back on", ns.db.buyMany == true)
ns.HandleSlash("buy 5 nothinglikeit")
suite.check("a name the vendor doesn't sell says so",
    env.ChatText():find("doesn't sell anything called nothinglikeit", 1, true) ~= nil)

suite.check("the probe line reads", type(Box:ProbeText()) == "string")

suite.done()
