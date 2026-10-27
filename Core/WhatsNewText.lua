-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.2.0", lines = {
        "You can turn off a craft Butler suggests.",
        "The Bags window has Group By beside the search.",
    } },
    { version = "0.1.0", lines = {
        "Butler is here for Classic Era. It tells you what to do with every item in your bags: keep, sell, bank or look at it.",
        "One Sell button at the vendor sells 12 items a click, so you can always buy them back.",
        "Hover an item to see what Butler says about it.",
        "Hunters can fill their quiver or ammo pouch with one click.",
        "Gold Goals shows how close you are to your next spells, training and riding.",
    } },
}
