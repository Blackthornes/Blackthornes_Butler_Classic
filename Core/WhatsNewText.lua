-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.5.0", lines = {
        "Every window has a new look that matches the other Blackthornes add-ons.",
    } },
    { version = "0.4.0", lines = {
        "The minimap button has a new Blackthornes badge.",
        "Show the way now puts a gold marker on your map.",
    } },
    { version = "0.3.0", lines = {
        "Swap When Full offers to swap your cheapest item for better loot when your bags are full.",
        "One minimap button now opens all your Blackthornes add-ons.",
    } },
}
