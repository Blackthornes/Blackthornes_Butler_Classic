-- The settings window.
--
-- What matters is that every way in opens it, that each control changes the
-- same saved value its chat command does, and that the page shows what is
-- saved rather than what it last drew.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("settings")

local ns = env.Load()

local SettingsUI = ns.SettingsUI

-- A client with retail's Settings API, recording what is registered.
local registered = {}
_G.Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name } end,
    RegisterAddOnCategory = function(category) registered[#registered + 1] = category end,
}

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

suite.check("it is listed under the game's AddOns options",
    registered[1] and registered[1].name == "Blackthornes Butler")

-- Ways in.
ns.HandleSlash("settings")
suite.check("/bbutler settings opens it", SettingsUI.frame:IsShown())
ns.HandleSlash("settings")
suite.check("and closes it", not SettingsUI.frame:IsShown())
ns.HandleSlash("options")
suite.check("/bbutler options works too", SettingsUI.frame:IsShown())
suite.check("options is not listed twice in help",
    not (function()
        for _, name in ipairs(ns.commandOrder) do
            if name == "options" or name == "config" then return true end
        end
    end)())

-- The house frame: the plate and close gem, without the portrait.
local trim = SettingsUI.frame.titan
suite.check("settings wears the house frame", trim ~= nil)
suite.check("with the name on the plate", trim and trim.plate.label:GetText() == "Blackthornes Butler")
-- A stub answers any field it lacks with a function, so "no portrait"
-- means no portrait frame.
suite.check("and no portrait", trim and type(trim.portrait) ~= "table")
trim.closeButton:GetScript("OnClick")(trim.closeButton)
suite.check("the close gem closes it", not SettingsUI.frame:IsShown())
SettingsUI:Show()

local controls = SettingsUI.controls

-- The minimap button always shows, so it has no box here.
suite.check("there is no minimap box", controls.minimap == nil)

-- Debug.
-- Debug and the client check are typed only (the owner, 2026-10-23): no
-- row, and help leaves them out.
suite.check("there is no debug box", controls.debug == nil and controls.probe == nil)
ns.HandleSlash("debug")
suite.check("/bbutler debug turns debug on", ns.db.debug == true)
ns.HandleSlash("debug off")
suite.check("/bbutler debug off turns it off", ns.db.debug == false)
local listed = {}
for _, name in ipairs(ns.commandOrder) do listed[name] = true end
suite.check("help leaves out debug, probe and selltest", not listed.debug and not listed.probe
    and not listed.selltest and ns.commands.debug and ns.commands.probe and ns.commands.selltest)

-- The sister note (Core/SisterNote.lua).
suite.check("the sister addons box starts ticked", controls.sisters:GetChecked())
controls.sisters:GetScript("OnClick")(controls.sisters)
suite.check("unticking it turns the note off", ns.db.sisterNote == false)
ns.HandleSlash("sisters")
suite.check("/bbutler sisters turns it back on", ns.db.sisterNote == true and controls.sisters:GetChecked())

-- The pages along the top, as Tradeskills' Settings tab has them: Selling,
-- then General. The plan's others come with the features they hold.
local pages = SettingsUI.pages
suite.check("it opens on the first page", pages.shown == "selling", pages.shown)
suite.check("with the selling rows showing", pages.pages.selling.content:IsShown())
pages:Show("general")
suite.check("General is the second page", pages.shown == "general" and pages.pages.general.content:IsShown())
SettingsUI:Hide()
SettingsUI:Show()
suite.check("it opens again on the page left", pages.shown == "general")

-- Open at a vendor: on unless unticked, saved as the box says.
suite.check("Open at a vendor starts ticked", controls.openAtVendor:GetChecked())
controls.openAtVendor:GetScript("OnClick")(controls.openAtVendor)
suite.check("unticking it saves off", ns.db.openAtVendor == false)
ns.HandleSlash("vendor")
suite.check("/bbutler vendor turns it back on, and the box follows",
    ns.db.openAtVendor == true and controls.openAtVendor:GetChecked())

-- What a setting does is a tooltip until Show descriptions is ticked.
local minimapRow, styleRow
for _, row in ipairs(pages.pages.general.rows) do
    if row.labelText == "Free Bag Space:" then minimapRow = row end
    if row.labelText == "Window Style:" then styleRow = row end
end
suite.check("descriptions start hidden", ns.db.settingsDescriptions == false
    and not minimapRow.hint:IsShown())
GameTooltip._lines = {}
minimapRow:GetScript("OnEnter")(minimapRow)
suite.check("a row lights under the mouse", minimapRow.hover:IsShown())
suite.check("and says what it does in a tooltip", GameTooltip._lines[1] and
    GameTooltip._lines[1]:find("backpack button") ~= nil)
GameTooltip._lines = {}
styleRow:GetScript("OnEnter")(styleRow)
suite.check("a row with nothing to say shows no tooltip", #GameTooltip._lines == 0)
local before = SettingsUI.frame:GetHeight()
pages.describe:GetScript("OnClick")(pages.describe)
suite.check("Show descriptions is saved", ns.db.settingsDescriptions == true)
suite.check("and puts the words under the rows", minimapRow.hint:IsShown())
suite.check("but nothing under a row with nothing to say", (styleRow.hint:GetText() or "") == "")
suite.check("and the window keeps its size", SettingsUI.frame:GetHeight() == before)
suite.check("the page scrolls instead", pages.body:GetHeight() > (pages.scroll:GetHeight() or 0))
pages.describe:GetScript("OnClick")(pages.describe)
suite.check("unticked, the window is the same", SettingsUI.frame:GetHeight() == before)

-- Find a setting.
pages.find:SetText("motion")
pages:Search("motion")
local lit = 0
for _, entry in ipairs(pages.searchables) do
    if entry.glow:IsShown() then lit = lit + 1 end
end
suite.check("the search lights only what matches", lit == 1)
pages:Search("")
lit = 0
for _, entry in ipairs(pages.searchables) do
    if entry.glow:IsShown() then lit = lit + 1 end
end
suite.check("an empty search lights nothing", lit == 0)

-- Text size, saved as a word, waits for a reload.
controls.textSize:Pick(controls.textSize:GetValue() + 1)
suite.check("Text size saves Large", ns.db.textSize == "large")
suite.check("and offers Reload", controls.textSize.reload:IsShown())
suite.check("under the stepper, at its right edge", controls.textSize.reload._point[1] == "TOPRIGHT"
    and controls.textSize.reload._point[2] == controls.textSize
    and controls.textSize.reload._point[3] == "BOTTOMRIGHT")
suite.check("the Window style's Reload sits the same way", controls.windowStyle.reload._point[1] == "TOPRIGHT"
    and controls.windowStyle.reload._point[2] == controls.windowStyle
    and controls.windowStyle.reload._point[3] == "BOTTOMRIGHT")
-- A player found text spilling out of the General page (2026-10-13): the
-- style box was too narrow for "Titanforged" and its Reload ran past the
-- column. Nothing on a row reaches past its column now.
suite.check("the style box fits its longest word", controls.windowStyle:GetWidth()
    >= ns.Theme.TextWidth("small", "Titanforged") + 22 * 2 + 8)
controls.textSize:Pick(controls.textSize:GetValue() - 1)
suite.check("back to Normal needs no reload", ns.db.textSize == "normal"
    and not controls.textSize.reload:IsShown())

-- Word choices are drop-downs (the owner, 2026-10-23), the pickers too.
controls.textSize:GetScript("OnMouseDown")(controls.textSize)
suite.check("Text size opens a menu of its words", controls.textSize.menu:IsShown()
    and #controls.textSize.options == 3)
controls.textSize.entries[2]:GetScript("OnClick")()
suite.check("a line of it picks Large and closes it", ns.db.textSize == "large"
    and not controls.textSize.menu:IsShown())
controls.textSize:Pick(1)
do
    local picked = 0
    local picker = SettingsUI.CharacterPicker(CreateFrame("Frame"), 0, function() picked = picked + 1 end)
    suite.check("an empty picker says so", picker.text:GetText() == "No characters yet" and picker:GetName() == nil)
    picker:SetNames({ "Ana Stormwind", "Bob Wither" })
    suite.check("then shows the first whole name", picker:GetName() == "Ana Stormwind"
        and picker.text:GetText() == "Ana Stormwind")
    picker:GetScript("OnMouseDown")(picker)
    picker.entries[2]:GetScript("OnClick")()
    suite.check("a line of its menu picks that one", picker:GetName() == "Bob Wither" and picker.index == 2
        and picked == 1)
    picker:SetNames({ "Cid Hale", "Bob Wither" })
    suite.check("and the pick stays through a new list", picker:GetName() == "Bob Wither" and picked == 1)
end

-- Sell below: gold, silver and copper boxes, saved when the player leaves
-- a box or presses Enter, not on every key.
local money = controls.sellBelow
pages:Show("selling")
suite.check("Sell below starts empty (off)", money:GetValue() == 0 and ns.db.sellBelow == nil)
money.boxes.silver.editBox:SetText("50")
suite.check("typing alone saves nothing", ns.db.sellBelow == nil)
money.boxes.silver.editBox:GetScript("OnEnterPressed")(money.boxes.silver.editBox)
suite.check("Enter saves it in copper", ns.db.sellBelow == 5000, tostring(ns.db.sellBelow))
money.boxes.gold.editBox:SetText("1")
money.boxes.gold.editBox:GetScript("OnEditFocusLost")(money.boxes.gold.editBox)
suite.check("leaving a box saves it too", ns.db.sellBelow == 15000)
ns.HandleSlash("sellbelow 2s 5c")
suite.check("/bbutler sellbelow fills the boxes", money.boxes.gold:GetText() == ""
    and money.boxes.silver:GetText() == "2" and money.boxes.copper:GetText() == "5")
ns.HandleSlash("sellbelow off")
suite.check("and off empties them", money:GetValue() == 0 and ns.db.sellBelow == nil)

-- The gold fund's usual amount: the money box and /bbutler goldmin agree.
local goldBox = controls.goldMinimum
goldBox.boxes.gold.editBox:SetText("50")
goldBox.boxes.gold.editBox:GetScript("OnEditFocusLost")(goldBox.boxes.gold.editBox)
suite.check("Keep at least saves in copper", ns.db.goldMinimum == 500000, tostring(ns.db.goldMinimum))
ns.HandleSlash("goldmin 20g")
suite.check("/bbutler goldmin fills the box", goldBox.boxes.gold:GetText() == "20")
ns.HandleSlash("goldmin off")
suite.check("and off turns it off", ns.db.goldMinimum == nil and goldBox:GetValue() == 0)

-- Every /bbutler command has a button here.
local ran = {}
local realSlash = ns.HandleSlash
ns.HandleSlash = function(text) ran[#ran + 1] = text end
for _, key in ipairs({ "openWindow", "all" }) do
    controls[key]:GetScript("OnClick")(controls[key])
end
ns.HandleSlash = realSlash
suite.check("the command buttons run their commands",
    table.concat(ran, ",") == "window,all", table.concat(ran, ","))

-- Every command has a button or a control here, apart from the one that
-- deletes the player's lists, which stays typed (a house rule).
local covered = { tooltip = true, sisters = true, whatsnew = true, window = true, all = true,
    vendor = true, mailbox = true, bank = true, settings = true, reset = true,
    sellbelow = true, freespace = true, whohas = true, goldmin = true, fillnext = true, altupgrades = true,
    joblogin = true, trash = true, quests = true, bankalt = true, greens = true, buy = true, order = true, skillup = true, bags = true }
-- Chat-only commands are typed only (the owner, 2026-10-15): they print a
-- list in chat, so they have no button here. Their settings parts (training
-- on|off, goals on|off, upgrademail undo) still have controls.
local CHAT_ONLY = { help = true, jobs = true, lists = true, upgrademail = true, gold = true, training = true, goals = true }
for name in pairs(CHAT_ONLY) do covered[name] = true end
for _, name in ipairs(ns.commandOrder) do
    suite.check("/bbutler " .. name .. " has a place in Settings", covered[name] == true)
end

-- Position.
ns.db.settingsX = 400
ns.db.x = 200
SettingsUI:ResetPositions()
suite.check("putting it back forgets where it was dragged", ns.db.settingsX == nil)
suite.check("and where the Butler window was", ns.db.x == nil)

-- A client with neither options API still loads.
local ns2 = env.Load()
suite.check("no options API is not an error", ns2.SettingsUI:RegisterGameOptions() == false)

suite.done()
