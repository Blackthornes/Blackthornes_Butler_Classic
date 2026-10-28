-- A row grows to hold its wrapped text, and the rows below it move down
-- rather than being written over (a long reason in German ran over the
-- rows under it, 2026-10-21).
--
-- What must hold:
--   1. Each row starts where the one above it ends.
--   2. A row is never shorter than the list's row height.
--   3. Rows that do not fit are hidden, never drawn past the list's foot.
--   4. Scrolled to the end, the last item is in sight, tall rows or not.
--   5. Without fitRow every row keeps the usual height.
--   6. UI.RowHeight is the tallest text plus room, never under 30.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rowgrow")

local ns = env.Load()
env.Enable(ns)

local parent = CreateFrame("Frame")
local list = ns.Widgets.CreateRowList(parent, {
    rowHeight = 30,
    fitRow = function(row, data) return data.tall end,
})
list._height = 200
list.scrollbar._height = 200

local data = {}
for i = 1, 20 do data[i] = { i = i, tall = (i % 3 == 0) and 60 or 30 } end
list:SetData(data)

local function Shown()
    local shown = {}
    for _, row in ipairs(list.rows) do
        if row:IsShown() then shown[#shown + 1] = row end
    end
    return shown
end

local shown = Shown()
local top, ok, short = 0, true, false
for _, row in ipairs(shown) do
    if row.top ~= top then ok = false end
    if row:GetHeight() < 30 then short = true end
    top = top + row:GetHeight()
end
suite.check("1. each row starts where the one above ends", ok)
suite.check("2. no row is shorter than the row height", not short)
suite.check("3. the rows shown fit in the list", top <= 200, tostring(top))
-- 30 + 30 + 60 + 30 + 30 = 180; the next is 60 tall and does not fit.
suite.check("3. a row that does not fit is hidden", #shown == 5, tostring(#shown))
suite.check("1. a tall row is as tall as its text", shown[3]:GetHeight() == 60,
    tostring(shown[3]:GetHeight()))

-- 4. Scroll as far as the list goes.
list.offset = 1000
list:Refresh()
local last = Shown()
last = last[#last]
suite.check("4. scrolled to the end, the last item is in sight",
    last and last.data == data[#data], last and last.data and tostring(last.data.i))
local sum = 0
for _, row in ipairs(Shown()) do sum = sum + row:GetHeight() end
suite.check("4. and nothing runs past the foot", sum <= 200, tostring(sum))

-- 5.
local plain = ns.Widgets.CreateRowList(parent, { rowHeight = 20 })
plain._height = 200
plain:SetData(data)
local count, same = 0, true
for _, row in ipairs(plain.rows) do
    if row:IsShown() then
        count = count + 1
        if row:GetHeight() ~= 20 then same = false end
    end
end
suite.check("5. without fitRow the rows keep their height", same and count == 10, tostring(count))
suite.check("5. and scroll as far as before", plain:MaxOffset() == 10, tostring(plain:MaxOffset()))

-- 6.
local function Label(height) return { GetStringHeight = function() return height end } end
local row = { name = Label(12), reason = Label(52), worth = Label(12) }
suite.check("6. a four-line reason makes the row taller", ns.UI.RowHeight(row) == 56,
    tostring(ns.UI.RowHeight(row)))
row = { name = Label(26), reason = Label(26), worth = Label(12) }
suite.check("6. two lines keep the usual height", ns.UI.RowHeight(row) == 30,
    tostring(ns.UI.RowHeight(row)))
row = { name = {}, reason = {}, worth = {} }
suite.check("6. no height from the client keeps the usual height", ns.UI.RowHeight(row) == 30,
    tostring(ns.UI.RowHeight(row)))

suite.done()
