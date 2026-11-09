-- The name picker on the mail To line: a Pick button right of the game's
-- To box opens LAST MAILED and YOUR CHARACTERS, and a click puts the whole
-- name in the box.
--
-- What must hold:
--   1. On unless unticked, and Settings has the box, ticked.
--   2. At a mailbox with Send Mail up, the button shows, placed by screen
--      position on UIParent beside the To box.
--   3. YOUR CHARACTERS lists this realm and side, not the one playing.
--   4. LAST MAILED keeps the name of a mail that went, not one that failed,
--      and never shows the one playing.
--   5. A click on a name puts it in the To box and closes the list.
--   6. Hidden in a fight, when Send Mail is not up, away from the mailbox
--      and when unticked.
--   7. Without Tradeskills only LAST MAILED shows; with nothing, no button.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("mailpicker")

local ns = env.Load()
env.FakeBags({})
_G.GetTime = function() return 100 end

local holdings = {
    { key = "Player-1", name = "Ana Stone", realm = "Silverpine", faction = "Alliance",
        isCurrent = true, playing = true, bags = {}, bank = {}, mail = {} },
    { key = "Player-2", name = "Cara Stonefield", realm = "Silverpine", faction = "Alliance",
        bags = {}, bank = {}, mail = {} },
    { key = "Player-3", name = "Dain Emberforge", realm = "Silverpine", faction = "Alliance",
        bags = {}, bank = {}, mail = {} },
    { key = "Player-4", name = "Cid Horde", realm = "Silverpine", faction = "Horde",
        bags = {}, bank = {}, mail = {} },
}
_G.BlackthornesTS = { Butler = { Holdings = function() return holdings end } }

_G.SendMailFrame = env.Stub({ _shown = true })
function _G.SendMailFrame:IsVisible() return self._shown end
_G.SendMailNameEditBox = env.Stub({
    GetRight = function() return 300 end,
    _top = 500,
    GetBottom = function() return 480 end,
})

env.Enable(ns)
local Picker = ns.MailPicker

local function Showing() return Picker.button ~= nil and Picker.button:IsShown() end
local function Names()
    local list = {}
    for _, entry in ipairs(Picker:Entries()) do
        list[#list + 1] = entry.heading or entry.name
    end
    return table.concat(list, ", ")
end

-- 1.
suite.check("on unless unticked", Picker:Enabled())
ns.HandleSlash("settings")
local box = ns.SettingsUI.controls.namePicker
suite.check("Settings has the box, ticked", box ~= nil and box:GetChecked())

-- 2.
suite.check("nothing before a mailbox", not Showing())
env.Fire("MAIL_SHOW")
suite.check("at the mailbox the button shows", Showing())
local point = Picker.button._point or {}
suite.check("placed on UIParent beside the To box",
    point[2] == UIParent and point[4] == 304 and point[5] == 490,
    tostring(point[4]) .. "," .. tostring(point[5]))

-- 3.
suite.check("your characters, not the one playing or the other side",
    Names() == "YOUR CHARACTERS, Cara Stonefield, Dain Emberforge", Names())

-- 4.
Picker:Sending("Bob Wither")
env.Fire("MAIL_FAILED")
env.Fire("MAIL_SEND_SUCCESS")
suite.check("a failed mail is not kept", ns.db.namePickerLast == nil, tostring(ns.db.namePickerLast))
Picker:Sending("  Bob Wither ")
env.Fire("MAIL_SEND_SUCCESS")
suite.check("a mail that went is kept", ns.db.namePickerLast == "Bob Wither", tostring(ns.db.namePickerLast))
suite.check("LAST MAILED comes first",
    Names() == "LAST MAILED, Bob Wither, YOUR CHARACTERS, Cara Stonefield, Dain Emberforge", Names())
ns.db.namePickerLast = "Ana Stone"
suite.check("the one playing never shows as LAST MAILED",
    Names() == "YOUR CHARACTERS, Cara Stonefield, Dain Emberforge", Names())
ns.db.namePickerLast = "Bob Wither"

-- 5.
Picker:Toggle()
suite.check("a click opens the list", Picker.menu ~= nil and Picker.menu:IsShown())
local row
for _, r in ipairs(Picker.menu.rows) do
    if r:IsShown() and r.name == "Cara Stonefield" then row = r end
end
suite.check("the list has the name", row ~= nil)
if row then row:GetScript("OnClick")(row) end
suite.check("the whole name goes in the To box", SendMailNameEditBox:GetText() == "Cara Stonefield",
    SendMailNameEditBox:GetText())
suite.check("and the list closes", not Picker.menu:IsShown())

-- 6.
_G.InCombatLockdown = function() return true end
env.Fire("PLAYER_REGEN_DISABLED")
suite.check("hidden in a fight", not Showing())
Picker:Update()
suite.check("and stays hidden while it lasts", not Showing())
_G.InCombatLockdown = nil
env.Fire("PLAYER_REGEN_ENABLED")
suite.check("back after the fight", Showing())

SendMailFrame._shown = false
Picker:Update()
suite.check("hidden when Send Mail is not up", not Showing())
SendMailFrame._shown = true
Picker:Update()

box:GetScript("OnClick")(box)
suite.check("unticking turns it off", ns.db.namePicker == false and not Showing())
box:GetScript("OnClick")(box)
suite.check("ticking brings it back", ns.db.namePicker == true and Showing())

env.Fire("MAIL_CLOSED")
suite.check("gone when the mailbox closes", not Showing())
env.Fire("MAIL_SHOW")

-- 7.
_G.BlackthornesTS = nil
Picker:Update()
suite.check("without Tradeskills only LAST MAILED", Names() == "LAST MAILED, Bob Wither", Names())
suite.check("the button still shows", Showing())
ns.db.namePickerLast = nil
Picker:Update()
suite.check("nothing to show: no button", not Showing())
env.Fire("MAIL_CLOSED")

suite.done()
