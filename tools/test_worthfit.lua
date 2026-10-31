-- The worth column on Butler's rows shows its whole text, never "...".
-- A Later row read "8s 00c, 1 not pr..." in game: the column was a fixed
-- 96 pixels. It now grows to its measured text, up to UI.WORTH_MOST, and
-- wraps past that.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("worthfit")

local ns = env.Load()
local UI, Theme = ns.UI, ns.Theme

local row = CreateFrame("Frame", nil, UIParent)
UI.CreateRow(row)

row.worth:SetText("8s 00c")
UI.FitWorth(row)
suite.check("a short worth keeps the usual width", row.worth:GetWidth() == UI.WORTH_WIDTH, row.worth:GetWidth())

local long = "8s 00c, 1 not priced yet"
row.worth:SetText(long)
UI.FitWorth(row)
suite.check("a longer worth gets the room it needs",
    row.worth:GetWidth() >= Theme.TextWidth("small", long) and row.worth:GetWidth() <= UI.WORTH_MOST,
    row.worth:GetWidth())

row.worth:SetText(string.rep("x", 200))
UI.FitWorth(row)
suite.check("never wider than WORTH_MOST", row.worth:GetWidth() == UI.WORTH_MOST, row.worth:GetWidth())

row.worth:SetText("")
UI.FitWorth(row)
suite.check("empty goes back to the usual width", row.worth:GetWidth() == UI.WORTH_WIDTH, row.worth:GetWidth())

-- Money is the game's coins, each in its own column (UI/Coins.lua).
suite.check("the row has coin columns", row.coins ~= nil)
UI.SetMoney(row, 160)
suite.check("worth shows as coins, the words left empty",
    ns.Coins.Shown(row.coins) and row.worth:GetText() == "" and row.coins.silver:IsShown()
        and not row.coins.gold:IsShown(), row.worth:GetText())
UI.FitWorth(row)
suite.check("the column is as wide as the coins", row.worth:GetWidth() >= math.min(ns.Coins.Width(row.coins), UI.WORTH_MOST),
    row.worth:GetWidth())
UI.SetMoney(row, 0)
suite.check("nothing for no worth", not ns.Coins.Shown(row.coins) and row.worth:GetText() == "")
UI.DrawRow(row, { type = "header", group = { label = "Sell", count = 2, worth = 34000 } })
suite.check("a group's heading in coins", row.coins.gold:IsShown() and row.coins.silver:IsShown()
    and not row.coins.copper:IsShown())
UI.DrawRow(row, { type = "header", group = { label = "Keep", count = 1, worth = 0 } })
suite.check("a heading worth nothing hides them", not ns.Coins.Shown(row.coins))

suite.done()
