-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.9.0", lines = {
        "Always Auction puts an item on the auction list from the right-click menu.",
        "A name picker sits beside the mail To box.",
        "Hovering a letter in your inbox shows what is inside.",
        "Jobs warns you when mail is about to run out.",
        "Mail Rules send items to any player you pick, and each bank alt kind can go to its own character.",
        "Waiting items say why they wait, with a Sell Anyway button.",
        "The Bags window can group by bag, and its Bank tab remembers your bank.",
        "Clear Items on the jobs menu forgets an alt's saved items.",
        "Mute All Sounds quiets every Blackthornes sound at once.",
        "Windows remember where you drag them.",
    } },
    { version = "0.8.0", lines = {
        "Keep Across Characters lets you keep a set number of an item across all your characters.",
        "Swap When Full now offers a swap for quest loot.",
    } },
    { version = "0.7.0", lines = {
        "Item icons now have a ring and a name colour that match their quality.",
        "Stack counts show on the corner of item icons.",
        "Items show a small mark and colour for what to do with them.",
        "Worth shows in gold, silver and copper coins, lined up in columns.",
    } },
}
