# Notes for Claude

Read this before working in this repo. The owner runs one Claude project per
addon, and this one (**Blackthornes_Butler**) was set up from the Farmer
project. Its sisters are **Blackthornes_Farmer**, **Blackthornes_Tradeskills**,
**Blackthornes_Equipment** and **Blackthornes_Pets** (all under
`Blackthornes/`). The projects cannot read each other's memory, so what one
needs to know about another lives in the repos, in this file and in theirs.
Keep them current: when a change here leans on something new in another
addon, or a standing rule from the owner applies to all of them, add it to
each file.

Nothing private goes in this file (no local paths, emails or account names).
It never ships: `.pkgmeta` leaves it out of the zip and
`tools/check_package.py` refuses it.

## This repo is the Classic Era copy

`Blackthornes/Blackthornes_Butler_Classic` is Butler for WoW Classic Era,
copied from `Blackthornes/Blackthornes_Butler` (Forever) with its history on
2026-10-24 (the owner said build it, after Farmer's Era copy; Tradeskills
follows in its own repo). Its releases, tests and CurseForge page are its
own. Forever comes first, and nothing done here may ever touch the Forever
addon. So:

- Never push to, or open PRs on, the Forever repo from work here. Changes
  come over from Forever on purpose (cherry-pick or copy), never the other
  way.
- The addon folder and TOC stay `Blackthornes_Butler`, the saved data
  `BlackthornesButlerDB` and `BlackthornesButlerCharDB`, so nothing is
  renamed.
- The TOC names Era's interface, `## Interface: 11509` (what the owner's
  Era client reports, 2026-10-24).
- What only Forever has is left out of the TOC: `Data/ForeverItems.lua`
  (Forever's sell prices and bag kinds; every reader asks for it first, so
  the live game answers alone). The file stays in the repo so Forever
  changes merge cleanly. `tools/test_era.lua` checks the TOC and that
  Butler loads, logs in and judges the bags with no sister loaded.
- `Data/ClassSpells.lua` is still built from Forever's tables, so
  `ClassTraining.Spells(class)` drops Forever's own spells (IDs from
  `FOREVER_FIRST`, 1,000,000) and any the client says it does not have,
  pointing a rank's "rank before" past the dropped ones. A list made from
  Era's own tables would be better once they are pulled.
- Era's auction house is the old one (no `C_AuctionHouse`), so Buy quest
  items never shows; Search still asks Tradeskills when it is loaded.
  Butler works on its own without Tradeskills: those rows and lines just
  don't show.
- Never put Forever's CurseForge ID (1739020) in the TOC:
  `tools/check_release.py` refuses a tag that does. Butler Classic is
  **1763328** (the owner made it 2026-10-24), on the TOC's
  `X-Curse-Project-ID` line, and `tools/test_era.lua` checks it is there.
- Not yet seen in an Era client. Read client calls in a pcall as everywhere
  else; the code already falls back to the classic calls where Era lacks
  the newer ones.
- The rest of this file describes the Forever addon; read it as the
  starting point, not as what Era has.

## What this addon is for

The owner picked it (2026-10-10) from ten ideas for a new addon, and named
it **Blackthornes Butler**. It answers one question for every item in the
bags: what should I do with this? Keep it (for a quest, to wear, for a
Farmer goal, for a craft in Tradeskills' queue, as pet food), sell it, post
it on the auction house, disenchant it, mail it to the alt who needs it, bank
it, or look at it yourself. The full plan, with the order the verdicts are
decided in and the four phases, is `ideas/bag-butler-plan.md` in the
project's files.

**Equipment sets** (a player asked, the owner said check and fix,
2026-10-13): anything in one of the player's equipment sets is Keep,
"In your NAME equipment set", before every other rule, so no list or
sister can sell, mail or break it (`Verdicts:InSet`, step 0;
`C_EquipmentSet` read in a pcall, else the classic set calls, else no
sets; read again on `EQUIPMENT_SETS_CHANGED` and each time the window
opens). Matched by item ID, so a spare copy of a set piece is kept too.
Tested in `tools/test_digestbugs.lua`.

Phase 1 is built and seen in game (2026-10-10): Butler on its own.
`Logic/Bags.lua` reads the bags only while the window is up or a vendor is
open, 0.2 s after a burst of bag events, 40 slots a frame, and looks further
only at slots whose key (link, count, locked) changed (`Bags.version`).
`Logic/Verdicts.lua` judges each item in order (Always keep, quest item or
quest starter, no vendor value, Always sell, price still loading, grey,
else Look at it) and groups them Sell, Look at it, Keep (`Verdicts:Groups`,
kept until `Bags.version` or `Verdicts.version` moves). `Logic/Selling.lua`
is the Sell button (see the findings file for why it is secure).
There is no Test Selling row (the owner, 2026-10-23): untested, the
first click's sale is followed by one from addon code
(`Selling:QuietTest`), kept in `sellTest` with `quiet`, which says whether
later clicks sell up to 12; `/bbutler selltest` is typed only.
Every button sits by the line it acts on (the owner, 2026-10-12: "the
buttons in Butler should go by the action that they need take"): Sell on
the Sell group's heading, Disenchant on Disenchant's, Move to bank on
Bank's, Take from bank on the Jobs heading, Fill mail on each character's
mail line, Log out on the next character's line, Craft and Fill on their
rows. A heading's button ends `UI.LINE_BUTTON_RIGHT` in from the right, so
the group's worth stays in sight; every button is anchored to its line
(`UI.PlaceOnLine` for the secure ones, `UI:PlaceErrands` for the others),
all again whenever the list draws or scrolls (`UI:PlaceButtons`). The
secure ones (Sell, Disenchant, Log out, Leave form) live inside the window
out of combat (`UI:Dock`, above `UI:InnerTop`), and as a fight starts
(`PLAYER_REGEN_DISABLED`, `UI:Undock`, `UI.fighting`) they are hidden and
handed back to UIParent, so the window can still move and close in
combat. The game brings a window to the front when it shows or is clicked
and draws it over every frame outside it in its layer, whatever their
level, so a secure button kept outside sat under the window and could not
be seen (2026-10-15), and one in a layer of its own showed through
Farmer's window (2026-10-14). Never put them back outside the window. One
whose line is out of sight waits at the window's
foot. A new button goes by its line too.
`UI/MainWindow.lua` draws the groups with `Widgets.CreateRowList` (Farmer's,
with the dark glass rows) and Butler's own right-click menu. The list's scroll bar is drawn and dragged by hand (`CreateScrollbar` in `UI/Widgets.lua`, the thumb following the cursor), not the game's Slider, which ran backwards on Forever (the owner, 2026-10-13); tested in `tools/test_scrollbar.lua`. Rows are two lines tall so a long reason or name wraps rather than
ending in "..." (the owner's rule). The window has the house size grip
below its bottom right corner (Tradeskills' window and Equipment's upgrade
quest panel have the same; asked 2026-10-11): drag to scale it 60% to 150%,
right-click for the normal size, saved as `windowScale` (account wide,
never rename it). The Sell button, a secure button outside the window, is
drawn at the window's scale. Saved and never
renamed: `alwaysKeep`, `alwaysSell`, `alwaysBank` (`[itemID] = true`),
`alwaysMail` (`[itemID]` = a character's short name), `sellTest`,
`sellBelow` (copper, nil when off),
`openAtVendor`, `openAtMailbox`, `openAtBank` (account), `folded` (per character). Not yet seen in game.

Rules from the plan that hold from the first feature on:

- **Nothing leaves the bags without the player's click.** No auto-sell, not
  even greys, unless a setting (off by default) says so. Sell all goes 12 at
  a time, what the vendor's Buyback tab holds, so every sale can be bought
  back. Quest items, upgrades, goal and queue materials, pet food under the
  limit and anything not yet judged ("Look at it") are never sold.
- **Mail only fills the game's own Send Mail form; the player presses
  Send.** Never hook or move the mail frame (Tradeskills v0.38.0 broke Send
  Mail that way).
- **Never touch a Blizzard frame:** no Hide, Show, HideUIPanel or field
  writes on the game's windows. The Butler window is its own frame, placed
  beside the bags by screen position, not parented to them.
- **Grey items are worth vendor only;** everything else is the best of
  vendor, auction (after the cut and deposit) and disenchant.

## How Butler talks to the other four

Phase 2 (2026-10-10, the owner said start): each sister has one call made
for Butler, so Butler never reaches into their insides. `Logic/Sisters.lua`
reads them, read only, inside a pcall, with no TOC dependency; a sister
that is not loaded, raises or answers something other than a table is
skipped, and a field of the wrong type counts as not given.

```lua
_G.BlackthornesTS.Butler:Advise(itemID)
  -- { auction (net copper each after the cut and deposit; nil for greys
  --   and bind on pickup), auctionNow (the same at today's cheapest
  --   listing by someone else, from a fresh scan only), belowCost (what
  --   one costs to make, when Tradeskills won't list it at its price),
  --   fast (true, false, or nil for middling),
  --   disenchant, canDisenchant, enchanter, need, mailTo, mailCount,
  --   bought (how many the account bought to disenchant), disenchanter
  --   (the disenchanter typed in its Settings, when its Mail page sends
  --   this gear there), youDisenchant (the character playing is that
  --   disenchanter), crafted (a green some recipe makes, asked only then) }
  -- Asked with the bag copy's link when its Butler.TAKES_LINK is true
  --   (2026-10-15), so a random suffix ("of the Monkey") is priced as it sells
_G.BlackthornesTS.Butler:SetBoughtToDisenchant(itemID, on, count)
  -- true, or false and why: the right-click menu's mark
_G.BlackthornesTS.Butler:FillMail(name, items, money)
  -- fills the Send Mail page; money (copper) is the gold fund's top-up
_G.BlackthornesTS.Butler:Jobs()
  -- each character's steps for the craft queue (see "Jobs on other
  --   characters")
_G.BlackthornesTS.Butler:Craft(recipeID)
  -- true and "crafting" or "opened", or false and why
_G.BlackthornesTS.Butler:SearchAuctions(items)
  -- { { itemID, count } }: true and "all" or "one", or false and why
  --   (see "Items for your quests")
_G.BlackthornesTS.Butler:Lists()
  -- { { name, id, items = { [itemID] = want } } } and its version: the
  --   player's shopping lists, for the bank alt and "Your Tradeskills
  --   lists"; id stays the same through a rename
_G.BlackthornesEquipment.Butler:Advise(link, bag, slot)
  -- { upgrade = "now" | "later" | nil, gain, sell (its bag coin), tool,
  --   alt = { key (a GUID), gain, level } when it is an upgrade for
  --   another character instead: a Mail row to the name
  --   Errands:NameOf(key) reads from Tradeskills' Holdings }
  -- nil for anything that is not gear; bag and slot let it see soulbound
_G.BlackthornesFarmer.Butler:Advise(itemID)
  -- { goal, have, target, need }: the character playing's own goals
_G.BlackthornesPets.Butler:Advise(itemID)
  -- { eats, buff, hours, count }: hours is for all the food carried and
  -- only a rough guess, so Butler shows it and never sells food on it
```

Each sister's `CLAUDE.md` lists its call under "What Butler calls here".
If one changes, change `Logic/Sisters.lua` and `Logic/Verdicts.lua` here
in the same breath. `Verdicts:Judge` keeps each item's verdict until
`Verdicts.version` moves, and `UI:Show` moves it (`Verdicts:Forget`), so the
sisters are asked once per item each time the window opens, never on a
redraw. How many of the item the bags hold (`Bags:Carried`) is part of the
kept key, since the sisters' answers move with it (an alt's `mailCount`, a
goal's `have`): only an item whose own count changed is asked again (eight
Medium Leather crafted one at a time were mailed as one, 2026-10-11). Fill
mail calls `Verdicts:Changed(true)` first, so the click sends what the alt's
queue wants then (`tools/test_mailcount.lua`). The verdicts they feed, in order, are at the top of
`Logic/Verdicts.lua`. Soulbound green or better gear is never put under
Sell: Disenchant, or Look at it. `/bbutler probe` says which sisters are
loaded and which answer Butler.

## Bought to disenchant

The owner asked (2026-10-11) for items bought on the auction house to
disenchant to be marked, easy to break, and followed by Butler.
Tradeskills keeps the marks, account wide (its `Logic/DisenchantBuys.lua`:
a buy after a search from its Disenchanting tab, or marked by hand), so
mail and the bank keep them. Butler reads `bought` from Advise
(`Verdicts:Bought`, step 8b, after the sisters' Keep; an item marked
bought is never an alt's upgrade, 2026-10-13): Disenchant whatever
else it would fetch, Mail to the enchanter when this character can't, else
Look at it. Bought rows head their group, their reason in violet; the
right-click menu's "Bought to disenchant" marks or unmarks through
`Sisters:MarkBought` (shown only with Tradeskills).

The Disenchant button (`Logic/Disenchanting.lua`) is a secure button like
Sell, inside the window out of combat (`UI:Dock`) on the Disenchant
heading, or at the foot left of the Sell or errand buttons when that is out
of sight (`UI:FootRoom` calls `Disenchanting:Update(room)`). It shows
on Your bags while something is under Disenchant (only Tradeskills puts
it there, for a character that can break it; Forever's spell checks can
say no for one that can, 2026-10-15), casts the spell by its client name
(`Disenchanting:SpellName`), and `/bbutler probe`'s "disenchant" line says
why it shows or not, and casts once a click: its PreClick aims the spell at the next
slot (bought first) through `target-bag`/`target-slot`, re-reading the slot
and its verdict first, never a "/use" macro (that equips when the cast does
not start). Hidden, its aim emptied, in combat. Not yet seen in game.

## Upgrades kept: one copy

Gear Equipment calls an upgrade for the character playing ("now" or
"later") is kept only as many copies as it wears: one, two rings or
trinkets (`Verdicts.Wears`). `KeptUpgrade` hands `{ wear }` to
`Verdicts:Groups`, which judges the rest again past it
(`Judge(entry, nil, pastKeep, true)`, `pastWear`), so they go to the
auction house, a vendor or wherever they belong (a player's five robes
were all kept, 2026-10-18). Counted by link, so two random suffixes are
each kept; soulbound copies are kept first. Tradeskills' Sell list holds
the same number (its `SisterKeeps`). Tested in
`tools/test_upgradecopies.lua`.

## Always sell and upgrades

The owner asked (2026-10-13) that an item on the Always sell list that is
gear Equipment calls an upgrade to wear now (`upgrade == "now"`) is not
sold: `Verdicts:Decide` shows it as Look at it, "On your Always sell list,
but it's an upgrade for you", and the list keeps it. Back to Sell once it is
no upgrade. It keeps what a Farmer goal or this character's craft queue
still needs too (the owner, 2026-10-14), "On your Always sell list, but
your goal needs N more" or "... your craft queue needs N", and sells
again once nothing does. Tested in `tools/test_sellupgrade.lua`.
Another character's queued craft gets its share first (`Verdicts:AltCraftShare`,
Tradeskills' `mailTo`/`mailCount`), from the Always sell list, a learned
keep and an item no vendor buys alike (a player's alchemist was never sent
its materials, 2026-10-14); soulbound and the character playing never.
Tested in `tools/test_altcraftfirst.lua`.

## Wait for a better price

The owner asked (2026-10-13) for items to auction to be folded away while
the auction house pays well under their usual price. In `Verdicts:Best`,
an Auction verdict becomes `wait` ("Wait for a better price") when
Tradeskills' `auctionNow` is under `Verdicts.LOW_NOW` (0.85) of `auction`;
the row keeps its usual worth. The group sits after Look at it and starts
folded on every character (`UI.FOLDED_AT_FIRST`, `UI.IsFolded`): an
opened one is saved as `folded.wait = false`. Nothing is sold or deleted.
It waits too when Tradeskills' Sell list would refuse it as a loss
(`belowCost`, what one costs to make, set only while "Recommend selling at
a loss" is off there; a player saw Butler say Auction for a craft
Tradeskills called a loss, 2026-10-13). A better way (disenchant) still
wins. Tested in `tools/test_waitprice.lua`. Not yet seen in game.

## Levelling Enchanting with your own greens

The owner asked (2026-10-13): a green that isn't crafted and breaks into a
material the character's own Enchanting still lacks for a guaranteed skill
point goes under Disenchant. Tradeskills works it out (its Advise's
`forEnchanting`: `{ recipe, material, materialName, short, yield }`,
the orange recipes known, cheapest first, less what the character owns in
bags, bank and mailbox) and `Verdicts:ForEnchanting`, step 8bb after the
sisters' Keep and Bought to disenchant, says Disenchant, "To level
Enchanting: RECIPE needs MATERIAL", whatever a vendor or the auction house
pays. Only while this character can break it, only greens. Once the
greens picked so far should give `short` (`yield` each), `Verdicts:Groups`
judges the rest again without it (`Judge(entry, true)`), so it stops at
enough. It wins even when the auction house pays more (the owner,
2026-10-17: a skill point beats a better sale). The player still clicks
Disenchant. Tested in `tools/test_levelenchanting.lua`.

## Always disenchant

The owner asked (2026-10-17): a green that sells for more than it breaks
into goes to Auction (the best price does that already), unless it gives
a skill point (above), and the player can say to break it anyway. The
right-click menu's "Always disenchant" (green or better only) puts it on
the player's Always disenchant list (`alwaysDisenchant`, `[itemID] =
true`, account wide, never rename it; `Verdicts:Choice` "disenchant").
Rule `disenchantList`, after the Always sell list: Disenchant when this
character can break it, else Mail to the enchanter Tradeskills names,
else Look at it; an upgrade to wear now is Look at it. Tested in
`tools/test_alwaysdisenchant.lua`.

## Craft When It Pays More

A player asked, the owner said build it (2026-10-19, from a mockup, words
approved): Butler says when a craft the character knows earns more than
selling. Off unless ticked: "Craft When It Pays More:" under CRAFTING on
the Selling page (`craftPays`, account wide, never rename it) and `/bbutler
craft on|off` (typed only, set straight in `ns.commands`, so it is not in
the help line). In `Verdicts:Best`, after the best price is worked out,
`Verdicts:CraftPays` asks Tradeskills, inside a pcall, read only:

```lua
_G.BlackthornesTS.Butler:CraftFor(itemID, carried, skip)
  -- { recipeID, name, itemID, per, crafts, perItem, needs = { { itemID, count } } }, or nil
_G.BlackthornesTS.Butler:QueueCraft(recipeID, crafts)   -- true, or false and why
```

An item goes under Craft, the first group, only when one made into it is
worth `Verdicts.CRAFT_MARGIN` (1.1) times the best price and the stack
gains at least `CRAFT_LEAST` (200) copper: "Make NAME, about X more than
selling it", or "(needs 2 Maple Seed)" for materials the bags lack. The
row's worth is that gain (`row.craft.gain`). Everything kept before the
best price still wins. The Craft heading's **Queue** button
(`UI:QueueCrafts`) calls `QueueCraft` once a recipe, for the most any row
makes, and says "Added N crafts to your Tradeskills queue." Nothing is
made, sold or moved by it. Tested in `tools/test_craftpays.lua`. If
Tradeskills changes either call, change `Sisters:CraftFor` and
`Sisters:QueueCraft` too. Not yet seen in game.
Saying no to a craft (the owner, 2026-10-26: it kept saying to make
Handstitched Leather Vests from Coarse Thread): a Craft row's right-click
has "Don't Suggest This Craft" (`Verdicts:SkipCraft`), kept account wide
in `craftSkip[recipeID] = name` (never rename it); "Crafts You Turned
Off:" with Show Again on the Selling page clears them. `CraftFor` gets the
list as a third argument so Tradeskills passes over those recipes and
offers the next best; Butler still drops a skipped answer from an older
Tradeskills. Tested in `tools/test_craftpays.lua`.

## Disenchant greens here

The owner asked (2026-10-14) for an option, off unless ticked, that on the
character set as the disenchanter says Disenchant for every green,
whatever it is worth. `Verdicts:GreensHere`, step 8be after Bought to
disenchant and Levelling Enchanting: with "Disenchant greens here" ticked
(Selling page, DISENCHANTING; `disenchantGreens`, account wide, never
rename it; `/bbutler greens [on|off]`), a green this character can break
goes under Disenchant when Tradeskills' Advise says `youDisenchant` (the
character playing is the one its Mail page names, typed or picked) and
not `crafted`. Everything kept before it (sets, lists, quest items,
upgrades and tools, goals, the craft queue, an alt's craft, pet food)
still wins; other characters keep the usual verdicts. A green that a
vendor or the auction house pays more for goes on to its best price, as
for Tradeskills' disenchanter (`BreakIt`, `SellsForMore`), unless "Always
Disenchant" is ticked (2026-10-20: a green worth 4s at auction was broken
for 1s 35c). Tested in `tools/test_disenchantgreens.lua`.

## Tradeskills' disenchanter

The owner asked (2026-10-11) for Butler to follow Tradeskills' disenchanter
setting (its Settings, Mail page: "Disenchanter" and "Mail gear up to").
Advise's `disenchanter` names that character when Tradeskills' own Mail
page would send the item there (its `QueueMail:GoesToDisenchanter`: green
up to the quality picked, can be disenchanted, never crafted gear, bind
on pickup or an upgrade for the character playing). `Verdicts:ForDisenchanter`, step 8c
after the sisters' Keep and Bought to disenchant, puts it under Mail to
that character, whatever the auction house or a vendor pays; a soulbound
copy and the character playing never get it. With nobody typed there,
Tradeskills picks the alt with the most Enchanting (more than the
character playing; its "Pick one for me", 2026-10-11), so Advise names
that one; with that unticked too, nothing changes. Since 2026-10-16 (a player asked) this takes an item only when breaking it pays at least what
a vendor or the auction house would (`Verdicts:SellsForMore`, the auction
counted as `Best` counts it), unless "Always Disenchant" on the Selling page
is ticked (`disenchantAnyPrice`, account wide, off unless ticked, never
rename it). Levelling Enchanting no longer waits on it (2026-10-17). Disenchant greens here still takes every green. Tested in `tools/test_disenchantermail.lua`.

## The bank alt

A player asked, the owner said build it (2026-10-14): whole kinds of items
mailed to one of the player's characters, to sort out later.
`Logic/BankAlt.lua`: the player picks the character (`bankAlt`, full name,
nil off) and ticks kinds read from the game's own item types
(`GetItemInfoInstant` class 7 and its subclass: cloth, leather, ore and
stone, herbs, meat, elemental, enchanting, other trade goods; and green
or better gear that binds when worn, `bindType` 2), kept in
`bankAltKinds[kind] = false` for each one unticked. With Tradeskills,
everything on one shopping list goes too (`bankAltList`, its name;
Tradeskills' `Butler:Lists()`, read once per `Verdicts.version`).
`bankAltWhen` is where it sits: "first" (Before Everything: whatever step 12
or 13 says), "vendor" (Before a vendor: only Sell and Look at it) or
"leftovers" (only Look at it). `Verdicts:Decide` asks `BankAlt:Verdict`
after `Best`, so the player's lists, sets, quest items, the sisters'
Keep, an alt's queued crafts and every other mail come first; greys
still sell, soulbound stays, and nothing goes to the character playing.
The rows are Mail to the bank alt, so Fill mail sends them. A character on the player's other account can be typed (2026-10-16:
"Type a Name:" on the page, or `/bbutler bankalt Full Name`;
`BankAlt:TypeName` wants first and last unless it is one of this
account's characters, and `BankAlt:IsKnown` turns the Send To name amber
when it is not). Auction Items (a player asked, the owner said build
it, 2026-10-22): with "Auction Items:" ticked under WHAT GOES THERE
(`bankAltAuctions`, off unless ticked), whatever Butler's final word is
Auction goes to the bank alt too, whatever its kind and in any When;
Wait, Sell and the rest stay, and a stack worth less than a mail's
postage (`Funds.POSTAGE`) stays (`BankAlt:Verdict`'s `worth`,
`MayTake`). All account
wide, never rename them. A BANK ALT page in Settings and `/bbutler
bankalt [Full Name|off|first|vendor|leftovers]`. Tested in
`tools/test_bankalt.lua`.

## All characters

A player asked for an account-wide inventory and the owner said build it
as the next phase (2026-10-10). The window's second view (`UI.view =
"all"`, the header's All characters button, `/bbutler all`, a Settings
button) lists every character's items with a search box: who has each,
how many in all, and a click opens a line per character with bags, bank
and mail and how old that read is. `Logic/Everyone.lua` builds it from one
call to Tradeskills, which already saves every character's bags, bank and
mail, inside a pcall, read only:

```lua
_G.BlackthornesTS.Butler:Holdings()
  -- { { key, name, short, realm, faction, isCurrent, linked,
  --     bags, bank, mail ([itemID] = count copies), bagsAt, bankAt, mailAt } }
```

The playing character's bags are Butler's own read (`Bags.slots`), the
freshest there is. Without Tradeskills (or when it raises) the view shows
only those bags and says so. Butler saves nothing for this view. Smooth
play: built only while shown, again when `Bags.version` moves or the window
opens, 300 counts and 40 new names a frame (`Everyone.BUDGET`,
`NAME_BUDGET`); a name the client has not loaded shows as "Item N", sorts
last and is filled in by `Everyone:NamesArrived` after `Items:Loaded`'s
burst. Search filters the built list. Your bags has its own box in the same
place (the owner said yes, 2026-10-13; `UI.bagSearch`, `UI:BagSearch`,
`UI.RowMatches`): by name or item ID, matches under their groups even when
folded, the ammo, jobs and gold lines left out while it has words, and
each view keeps its own words. Tested in `tools/test_bagsearch.lua`. The Sell button stays off in this
view, and a vendor opens the window on Your bags. Tradeskills'
`CLAUDE.md` lists `Holdings` under "What Butler calls here"; if it
changes, change `Logic/Everyone.lua` too. Not yet seen in game.

## At the mailbox and the bank

The plan's next phase (the owner said start, 2026-10-11).
`Logic/Errands.lua` watches `MAIL_SHOW`/`MAIL_CLOSED` and
`BANKFRAME_OPENED`/`BANKFRAME_CLOSED`, and the window comes up on Your bags
at every mailbox, and at the bank when there is something to do there
("Open at a mailbox" `openAtMailbox`, "Open at the bank" `openAtBank`,
account wide, on by default; `/bbutler mailbox` and `/bbutler bank` toggle
them), going when it closes. A window already up when a mailbox opens
belongs to the mailbox too, and walking away is also heard as
`PLAYER_INTERACTION_MANAGER_FRAME_HIDE` (mail or banker), in case the
client says that without `MAIL_CLOSED` (a player found the window left up,
2026-10-11).

Butler takes over the mailbox from Tradeskills' mail panel (the owner
picked it, 2026-10-11): while Butler's window is up at a mailbox,
`Errands:TellTradeskills` calls, inside a pcall and only when it changes,

```lua
_G.BlackthornesTS.Butler:Mailbox(covered)   -- true: its mail panel steps aside; false: it comes back
```

so closing Butler's window brings Tradeskills' panel back. Keep it stable;
Tradeskills' `UI/QueueMailPanel.lua` reads it.

- **Fill mail** fills the game's Send Mail page with the Mail group for one
  character a click (most items first; `Errands.filled` per visit), through
  `_G.BlackthornesTS.Butler:FillMail(name, items)` (Tradeskills'
  `QueueMail:Fill`). Mail rows carry `mailTo` and `mailCount`
  (`Verdicts:Decide`'s fifth return), and `Errands:Recipients` adds every
  item a Jobs mail step for this character names, so the mail holds what
  that line says (two herbs a Farmer goal kept were left out, 2026-10-13).
  An alt's queued craft also comes before a Farmer goal in
  `Verdicts:Kept`. A mail holds 12 stacks, so Fill mail puts the items taking the
  fewest stacks first (`Errands.FewestStacksFirst`; cheap vials were
  always last and left out, 2026-10-13), and once that mail goes,
  `Errands:Sent` fills what did not fit into the next one to the same
  character (`OnSendMail` counts what went). Tested in
  `tools/test_mailoverflow.lua`. The button sits on the first line
  that mails each character (the owner asked 2026-10-12, as Log out sits on
  the next character's line): a Jobs mail step, a gold top-up or a Mail
  row, set by `UI:PlaceMail` each time the lines are built (`UI.fillRows`,
  the row's own `row.action`, `Errands:FillMail(to)`). Only a character
  whose lines are all folded away keeps it at the window's foot. The
  player presses Send; Butler never
  sends, hooks or moves the mail frame. There are no mailbox Take buttons
  (the owner had them removed from Tradeskills; never add them unasked).
  Nothing is ever mailed to the character playing (a player found Fill
  mail addressed to themselves, 2026-10-11): `Errands:IsMe` (through
  `Verdicts:IsMe`) knows every name of it, from each `Holdings()` entry
  marked `isCurrent` or `playing`, and an Always mail entry, a `mailTo`,
  an `enchanter` or a gold top-up naming it is kept instead; Fill mail
  asks it once more last.
  Tradeskills' `FillMail` refuses it too, and its third return, the full
  name filled in, is what the chat line says.
  An item both this character's queue and an alt's want is a Mail row
  (2026-10-11, the owner: Butler handles queued crafts made on another
  character): `mailCount` is what Tradeskills spares once this
  character's crafts are kept back, so Fill mail sends that and the rest
  stays; with nothing to spare it is Keep. The Always keep list gives way
  to it the same way (`Verdicts:ForAltCraft`): the alt's share is a Mail
  row and the list keeps the rest. The Always bank list does not.
- **An alt's upgrade** (Equipment's `alt`, the owner asked 2026-10-11)
  is offered only while "Mail upgrades to your characters" is ticked
  (`altUpgrades`, account wide, off by default, never rename it;
  `Verdicts:AltUpgradesOn`, `/bbutler altupgrades`, Settings > Selling;
  the owner, 2026-10-13). Then it goes to them only as many as they wear: one, two for rings and trinkets
  (`Verdicts.Wears`, from the item's equip slot). `Verdicts:Groups` hands
  out copies in bag order, and a copy past that is judged again as if no
  alt wanted it (`Judge(entry, true)`), so it lands under Sell, Auction or
  wherever it belongs (a player found two pairs of pants in one mail).
  Clicks that act on a slot ask `Verdicts:VerdictOf(entry)`, the verdict
  the window shows, not `Judge`. Once a mail Butler filled goes, its alt
  upgrades are kept in `upgradeMailed[itemID] = { to, count, at }`
  (account wide, never rename it) and not offered again to that
  character for 30 days (`Verdicts.MAILED_KEEP`, when unclaimed mail goes
  back). Tested in `tools/test_altupgrade.lua`.
- **Holding an upgrade back** (the owner asked 2026-10-12): right-click a
  Mail upgrade row (`row.upgrade`) for "Don't mail this to NAME"
  (`Verdicts:HoldUpgrade`, `noUpgradeMail[itemID][name] = true`) or
  "Never mail upgrades to NAME" (`HoldAllUpgrades`, `noUpgradesFor[name]
  = true`), account wide by full name; never rename either. The alt
  branch skips a held item (`Verdicts:UpgradeHeld`), so it gets its next
  verdict and Fill mail leaves it. Settings > Selling > Upgrades for your
  characters picks a character, ticks Mail them upgrades and has Undo for
  its held items; `/bbutler upgrademail` lists them and `upgrademail undo
  NAME` undoes both. Tested in `tools/test_holdupgrade.lua`.
- **Fill the next mail** (the owner's goal, 2026-10-11: do the work for
  the player): once a mail Butler filled goes (`MAIL_SEND_SUCCESS`, with
  `Errands.sending` set by `FillMail`), `Errands:Sent` waits
  `Errands.NEXT_DELAY` for the bags, then fills the next character's, or
  says that's all. Only while the window is up at the mailbox and out of
  combat; a mail sent by hand fills nothing, and `MAIL_FAILED`
  (`SendFailed`) offers the same character again. "Fill the next mail"
  (`fillNext`, account wide, on unless unticked, never rename it;
  `/bbutler fillnext`). The player still presses every Send.
- **Always mail to** (the right-click menu, asked 2026-10-11) puts an item
  on the player's **Always mail** list for one of their characters
  (`alwaysMail`, `[itemID]` = the character's full name, account wide,
  never rename it; one saved as "Ana S." before names were whole is read
  as the full name by `Errands:FullName`, and left as saved):
  it goes under Mail addressed to them, all of it, less what this
  character's own queued crafts need (Tradeskills' `need`; the owner,
  2026-10-14): with the queue needing it all it is Keep, otherwise only
  the rest is mailed (`tools/test_alwaysmailqueue.lua`). On the character
  it names, it has arrived: the usual rules decide it there and only that
  character's own keep holds it (the owner, 2026-10-18; the local `Choice`
  in `Logic/Verdicts.lua` drops it, `Verdicts:Choice` still says mail), and
  the bank alt never takes it on, so it can't bounce back. The characters are
  Tradeskills' `Holdings()` on the same realm and side
  (`Errands:Characters`), so the choice shows only with Tradeskills;
  soulbound items are never offered and are kept if already listed.
- **Move to bank** puts the Bank group away: a new verdict for the
  player's **Always bank** list (`alwaysBank`, `[itemID] = true`, account
  wide, never rename it; the right-click menu and `reset confirm` cover it).
- **Take from bank** brings out what this character's own queued crafts
  want, `_G.BlackthornesTS.Butler:FromBank()`, smallest stacks first until
  each count is covered. It also brings out bank gear Equipment's
  `Advise` calls an upgrade to wear now (the owner asked 2026-10-13;
  `Errands:BankUpgrades`, the best for each slot, two for rings and
  trinkets), read only while the bank is open and kept until `Bags.version`
  moves or `PLAYERBANKSLOTS_CHANGED`.

Both bank moves use `C_Container.UseContainerItem` (the selling test found
it works from addon code), one stack every `Errands.STEP`, each slot read
again first; a stack that does not move means the other side is full, and
the run stops and says so. Nothing in combat. The bank is read only for a
click. Not yet seen in game.

## The gold fund

The owner asked (2026-10-11) for a minimum gold balance on his characters,
topped up by mail from a character with more. `Logic/Funds.lua`:
"Keep at least" on the Gold page of Settings (`goldMinimum`, copper,
account wide, nil when off; `/bbutler goldmin 50g`) and one character's
own amount (`goldMinimumFor[full name]`, 0 meaning it keeps nothing
back; the page's character picker, "They keep" and "Use the usual").
Never rename either. `Funds:Plan` reads Tradeskills' `Holdings()` (its
`gold` and `goldAt`, as last seen; live for the character playing) and,
for each character on this realm and side below its amount, biggest need
first, offers what the purse can spare above the sender's own amount, less
30 copper postage a mail. At a mailbox those are the Gold rows at the top
of the window (with how old each balance is), and `Errands:Recipients`
gives each its `money`, which Fill mail passes to Tradeskills'
`FillMail(name, items, money)`: with that character's items, or gold
alone. The player presses Send. Gold Butler filled and then saw leave the
purse (`Funds:Filled`, `PLAYER_MONEY`) is kept in `goldSent[full name]`
(never rename it) and counted toward that character until its own record
shows it took it, or 30 days pass (unclaimed mail goes back), so it is
never sent twice. `/bbutler gold` lists everyone. Smooth play: the plan is
worked out only while the window draws it, again only when the purse
(debounced 0.2 s) or a setting moves. Tested in `tools/test_funds.lua`.
Not yet seen in game.

## Filling the quiver

The owner asked (2026-10-11) for Butler to offer to fill a hunter's ammo
pouch at a vendor that can, "with the best ammo you can use, for the
weapon type you're using and pouch type you have on". `Logic/Ammo.lua`:
on a hunter (`UnitClass`), the weapon in the ranged slot (or main hand) is
a bow or crossbow (arrows) or gun (bullets), and the ammo bag is the bag
whose family holds arrows (quiver, 1) or bullets (ammo pouch, 2). At a
vendor, the window's first row is Ammo: the vendor's ammo of that kind the
hunter can use (`isUsable`, its level), most damage first (the tooltip's
"Adds X damage per second", read through the game's own
`AMMO_DAMAGE_TEMPLATE` so another language's line and decimal comma count,
the English words kept as a fallback; else item level), and how many whole lots fit
the bag's empty slots and the room left in its stacks of the same ammo.
The row's Fill button buys them, one `BuyMerchantItem(index)` (one lot)
every `Ammo.GAP`, each re-checked first; fewer lots when the purse is
short (said so), no button when it can't pay for one. The gold fund's
amount is only for mailing gold, never for spending (the owner,
2026-10-11), so Ammo and anything else that buys ignore it. A bag that
doesn't match the weapon, or no ammo bag, gets a row that says so and no
button; a full bag gets no row. `Ammo:Keeps` keeps the weapon's own ammo
out of Sell (step 4b). No setting: it shows only where it can help. Not
yet seen in game; `/bbutler probe` has an ammo line. Tested in
`tools/test_ammo.lua`.

## Forever's game tables

The owner asked (2026-10-12) for the Forever client's own game tables to be
put to use in every addon. Butler's part is `Data/ForeverItems.lua`,
written by `tools/make_forever_items.py <folder>` from the client's
ItemSparse table (kept privately in the project's files, never committed;
rerun it when Forever's build changes, never edit the data by hand). It
holds only two things: `SELL[itemID]`, what a vendor pays in copper, and
`BAGS[itemID]`, the bag family of containers that hold only some things
(quivers, ammo pouches, soul, herb, enchanting, mining and skinning bags).
The live game always wins: `Items:SellPrice` takes the tooltip, then item
info, and only for an item the client has not loaded yet answers
`Items.TableSellPrice` (not kept, so the live price replaces it on
`GET_ITEM_INFO_RECEIVED`); `Ammo:Bag` and `FreeSpace.Read` read a bag's
family from the client and fall back to `Items.TableBagFamily(bag)` only
when it gives none. `/bbutler probe` has a "forever tables" line comparing
the two for each bag. Never name where the tables were downloaded from;
say "the Forever client's game tables". Tested in
`tools/test_foreveritems.lua`.

## Learning from the player

The owner's goal (2026-10-11): the addons should work "almost like it's
magic", learning from what the player does. `Logic/Learning.lua` watches
three things the player does anyway, through post-hooks on single calls
(`hooksecurefunc` on `BuybackItem`, `C_Container.UseContainerItem` and
`SendMail`; no frame is touched) and one event each:

- a buyback of something Butler's Sell button sold this visit
  (`Selling.soldIDs`) is kept from then on;
- an item sold by hand at a vendor (not by Butler's button, a grey, quest,
  soulbound green or better, or already Sell) on `Learning.SELLS` (2)
  visits goes under Sell;
- an item mailed by hand to the same one of the player's characters
  (`Errands:Characters`, never the one playing, never mail an addon filled,
  `Learning.ADDON_SUBJECTS`) `Learning.MAILS` (2) times goes under Mail to
  them, so Fill mail sends it.

Saved, account wide, never renamed: `learned[itemID] = { verdict, to, at }`
and `learnTally = { sells, mails }`; "Learn from what you do" (`learn`, on
unless unticked) on the Errands page. A learned keep sits right after the
player's lists in `Verdicts:Decide`; a learned mail or sell only after the
sisters' Keep (steps 8d and 9b), so a habit never sells or mails an
upgrade, a goal or craft material or pet food. Any right-click pick clears
what was learned (`Verdicts:SetChoice` calls `Learning:Forget`), the menu
shows "Forget what Butler learned" for a learned item, `/bbutler lists`
shows them and `reset confirm` forgets them. Tested in
`tools/test_learning.lua`. Not yet seen in game.

## Jobs on other characters

The owner asked (2026-10-11) for a button per step that swaps to the
character who has to do it ("go craft Medium Leather on another, then
send back"). Addons don't run on the character list, so they can't pick a
character; the owner said yes to a step list with a Log out button
instead. `Logic/Jobs.lua` reads Tradeskills' `Butler:Jobs()` (one entry
per character this one can mail, never another account's: `name` in full,
`isCurrent`, `steps`; a step is a craft, `{ kind = "craft", recipeID,
itemID, name, count, forNames, ready, missing }`, or a mail, `{ kind =
"mail", to, items, crafts }`) and shows the Jobs group first on Your bags:
this character's steps (a Craft button on a craft it has the materials
for, which calls Tradeskills' `Butler:Craft(recipeID)`: it crafts with the
profession open, else opens its Queue tab, whose Open button opens the
profession), then "Next: NAME" for the other character that can get on
with a step, then "Then: NAME" for the rest. Mail steps are done with
Fill mail at a mailbox, as before.

The **Log out** button (`BlackthornesButlerLogout`) is a secure button
running the game's own `/logout` as a macro (addon code may not log out by
itself). It sits on the next character's row ("First:" or "Next:"), where
a craft's Craft button sits (the owner asked 2026-10-11: "the log out
button should be next to the step that needs the logout"), anchored to
that row inside the window (`UI:Dock`, `Jobs:UpdateLogout`, `Jobs.NextRow`, called
from the list's `onRefresh` so it follows a scroll, and from
`UI:FootRoom`). It shows only while that row is on screen, and hides in
combat, while the window moves and in All characters. There is no other
Log out button (the header and gold foot ones are gone); once nothing is
left here the footer says "Everything here is done" (`Jobs:DoneHere`).
Not yet seen in game; `/bbutler probe` has a jobs line (`Logout`,
`SLASH_LOGOUT1`).
Craft opens the profession when its window is closed (the owner,
2026-10-15, as Tradeskills' own craft button does): Tradeskills'
`Butler:Profession(recipeID)` gives `{ name, spell, open }`, and while the
first craft line on screen has `open` false, `Jobs:UpdateOpenProfession`
lays a secure button (`BlackthornesButlerOpenProfession`, type spell, inside
the window like Leave form, which wins in a form) reading "Open NAME" over
its Craft button. That click opens the window; the next Craft crafts.
`TRADE_SKILL_SHOW`/`CLOSE` redraw the lines. Tested in `tools/test_jobs.lua`.
When nothing here can be done yet and the next character can (the owner,
2026-10-11: "a sub craft on another character needs to go to a top step
if they already have the materials"), `Jobs:Plan`'s `goFirst` puts that
character's line, "First: NAME", above this character's steps, and Log out
sits on that line. Tradeskills names who holds a missing
material (`missing[i].from`, "NAME has it.") and gives that character a
mail step to the crafter (`forCraft`), the character playing too (an
item's `bank` is how many to take out of the bank first, and the step
says so); the next character is the one
whose `forCraft` mail feeds a craft here, before any other ready one.
The character playing is never one to log out for: a job named as
any name `Errands:IsMe` knows counts as here, whatever `isCurrent` says,
and a mail step to the character doing it is dropped (`Jobs.Clean`). A player
was told to log out for the character they were on, 2026-10-11.

Ignore Until Next Login (a player asked, the owner said yes, 2026-10-18):
a right-click on a character's jobs (its "Next:"/"Then:" line, or one of
this character's own steps) opens a small menu with that one line.
`Jobs:Ignore(name)` keeps the full name in `jobsIgnored[name] = time`
(account wide, made when first needed, never rename it), `Jobs:Plan`
leaves that character out, and at that character's next initial login
(`PLAYER_ENTERING_WORLD`, again `LOGIN_DELAY` later once Tradeskills
knows its names) `Jobs:Welcome` brings it back; a /reload does not.
Nothing in the queue changes. No setting. Tested in `tools/test_jobs.lua`.

Mail waiting (the owner, 2026-10-13: "if a character needs to visit the
mail for something sent to it, butler should move that up the priority
list"): Tradeskills' `Jobs()` gives a `{ kind = "pickup", items, forCraft
}` step for materials a character's crafts count on that sit in its
mailbox or are on their way, and for anything mailed to it not yet seen
arrive (its `Queue:InMailFor`, `QueueMail:InFlightItems`). `Jobs.Clean`
puts it first on that character's line ("Get your mail"), it counts as a
step that can be done now, and `Jobs:Plan` picks the next character by
rank: a `forCraft` mail that unblocks a craft here, then mail waiting for
its crafts, then any mail waiting, then the first that can get on with
it. Tested in `tools/test_jobs.lua`.

Crafts freeing bag space (the owner asked 2026-10-15): a craft step for the
character playing carries `slots` (Tradeskills' `Crafting:SlotsFreed`, nil
while "Craft what frees bag space first" is off there), and `Jobs.Order`
sorts the plain crafts by it, most first, ties and other steps staying put.
Tested in `tools/test_jobs.lua`.

A mail of materials says why (the owner, 2026-10-14): `Jobs.NoteWhy`
finds the crafts on the receiver's line still missing an item the mail
carries (`step.forSteps`), and the row reads "6 Wool Cloth, so NAME can
make 2 Bolt of Woolen Cloth.", with how Fill mail works moved to the
tooltip (`StepText`'s third return). Tested in `tools/test_jobs.lua`.

Materials and parts first (the owner, 2026-10-13: "collecting all vendor
materials and subcrafts should go to the top of the list", then "missing
materials too that need to be purchased or gathered"): `Jobs.Order` lays
out each character's steps as the mailbox visit, then what the crafts
still need to get (`Jobs.GetSteps`, added up over the crafts): "Buy from
a vendor" (`kind = "buy"`, missing materials marked `vendor`; Tradeskills'
Buy materials button at the vendor gets them) and "Buy or gather"
(`kind = "gather"`, the rest, from the auction house or the world), then
crafts whose item another craft on the line still misses, in
Tradeskills' order (it groups a profession's sub-crafts, every bar before
the anvil; a player's report, 2026-10-19) but never before a part they
are made from, then the rest as Tradeskills gave them. Left out of the get steps:
what another character holds (`from`), what any queued craft on any line
makes, and what waits in the mailbox. Both count as steps to do now.
`Jobs:Plan` puts a character who can make a part a craft here waits on
next, beside one whose mail unblocks it. The `vendor` mark (copper for
one, or true) on a craft's `missing` items is Tradeskills' to give;
without it every material to get shows under Buy or gather. Tested in
`tools/test_jobs.lua`.

Buy at the vendor (the owner, 2026-10-14: Tradeskills' Buy materials
button, over the vendor window, in Butler too): at a vendor the Buy from a
vendor row says what this one has for the queue and what it costs, or that
it sells none of it (or the auction house has it for less), and has a Buy
button. Tradeskills works it out and buys, inside a pcall:
`_G.BlackthornesTS.Butler:VendorOffer()` (`{ count, cost, items,
cheaperElsewhere, buying }`, nil away from a vendor) and
`:BuyFromVendor()` (its own button's click: the same checks, a stack a
step). `Jobs:VendorOffer` reads it on each `UI:Refresh` while a vendor is
open (`Jobs.vendorKey` is in the redraw key), once more 0.5 s after
`MERCHANT_SHOW`, and `Jobs:WatchBuying` redraws every `BUY_LOOK` seconds
while the run goes. Without Tradeskills the row is as before.
Tradeskills' own Buy materials button over the vendor window hides while
Butler is loaded and opens at vendors (the owner, 2026-10-18), so at a
vendor with something for the queue and no buy step here,
`Jobs:VendorStep` adds a Buy from a vendor row made from the offer. Tested
in `tools/test_vendorbuy.lua`.

Profession cooldowns (the owner said yes, 2026-10-12): Tradeskills'
`Jobs()` also gives each character's ready cooldown as a step, `{ kind =
"cooldown", name (its group, "Transmute"), craft, recipeID or itemID }`
(its `Logic/Cooldowns.lua`). It counts as a step that can be done now, so
it can put a character on "Next:" with Log out; a recipe's has a Craft
button (Tradeskills' `Butler:Craft` makes it once, queued or not, with the
profession open), an item's (the Salt Shaker) says to use it from the
bags. Tested in `tools/test_jobs.lua`.

Logging in (`PLAYER_ENTERING_WORLD`'s initial login, `Jobs.LOGIN_DELAY`
later) on a character with a step brings the window up and says what it is
("Jobs at login", `jobsAtLogin`, account wide, on unless unticked, never
rename it; `/bbutler joblogin`). Once the last step here is gone,
`Jobs:Noticed` says who is next, once. `/bbutler jobs` lists everyone's.
Smooth play: Tradeskills is asked only while the window draws the list,
again only when `Bags.version` or `Jobs.version` (moved as the window
opens) moves; no timer. Tested in `tools/test_jobs.lua`.

## Items for your quests

A player asked (2026-10-14, the owner said build it) to buy what open
quests need on the auction house. `Logic/Quests.lua` reads the quest log
(`C_QuestLog.GetQuestObjectives`, else `GetQuestLogLeaderBoard`, in a
pcall) for "collect N" objectives. The log gives a name and counts, never
an ID, so the ID comes from `Data/QuestItems.lua` (`ns.QUEST_ITEMS[questID]
= { itemID, ... }`, Classic's quest objectives kept only when the Forever
client's game tables say the item trades; written by
`tools/make_quest_items.py <pfQuest> <tables folder>`, never by hand), else
an item in the bags with that name, else `GetItemInfoInstant(name)`.
Forever's own quests work by name; one nothing names is looked at again
when the bags or the item come in.

- Every item an open quest collects is Keep (`Verdicts:Decide` step 2,
  `Quests:Reason`: "Westfall Stew needs 5 more", "For Westfall Stew" once
  there are enough for the hand-in), Always sell or not.
- Jobs leads with "For your quests" (`Quests:Step`, kind `quest`): what is
  still to find and trades (bind on pickup and quest-only items never),
  most needed first. At the auction house (`AUCTION_HOUSE_SHOW`) with
  Tradeskills it has a Search button (`Quests:Search`), which calls
  `_G.BlackthornesTS.Butler:SearchAuctions(items)`: every item at once,
  or, where the game takes one a search, "Next 2/5" a click.
- Quest events only mark the log stale; one read follows `Quests.SETTLE`
  later, and the items are judged again only when the signature moved.
- "Items for your quests" on the Selling page (`questItems`, account wide,
  on unless unticked, never rename it) and `/bbutler quests [on|off]`
  (alone it lists them). `/bbutler probe` has a "quest items" line.

Tested in `tools/test_quests.lua`. If `SearchAuctions` changes in
Tradeskills, change `Quests:Search` too.

Buy quest items (a player asked, the owner said yes, 2026-10-18): with
"Buy Quest Items" ticked (Selling page, `questBuy`, account wide, off
unless ticked, never rename it; `/bbutler quests buy on|off`), at the
auction house each item `Quests:ToBuy` names gets its own row under For
your quests (`QuestBuy:Rows`, type `questbuy`), with Tradeskills' public
price (`_G.BlackthornesTS_API.GetPrice`, read in a pcall) as "About X
each". Two clicks, never one: Buy calls
`C_AuctionHouse.StartCommoditiesPurchase` and the row waits for
`COMMODITY_PRICE_UPDATED`'s total, then Pay calls
`ConfirmCommoditiesPurchase`; a price that moves while it buys needs Pay
again, and short of gold Pay buys nothing. One buy at a time; closing the
auction house, an unavailable price, a failure or no answer
(`QUOTE_WAIT`, `BUY_WAIT`) lets it go. An item sold one at a time
(`GetItemCommodityStatus` 1) gets Search instead (`Quests:Search` for that
item). The gold fund never limits it. Tested in `tools/test_questbuy.lua`.

## Class training

The owner said build it (2026-10-13), in Butler and Equipment: which class
spells the character (and the other characters) can train now and soon,
and what they cost. `Logic/ClassTraining.lua`, `Data/ClassSpells.lua` and
`tools/make_class_spells.py` are the same files in both addons (a fix to
one belongs in both); neither calls the other for it. The data is
generated from the Forever client's game tables (`make_class_spells.py
<tables folder> --build <build>`; never edit it by hand, never commit the
tables): each class's trainable spells with level, rank, races and the rank
before. With `--prices <Classic world database dump> --learn <a Classic
client's SpellEffect table>` it also writes `CLASS_SPELL_PRICES`,
Classic's trainer prices (the full price where Classic had a discount),
which stand in until a trainer shows its own (`ClassTraining.PriceOf`,
`spell.guess`); never name where either came from. Real prices, which spells no trainer teaches (a quest does) and where
the trainer stands are not in the tables: the first look at a class
trainer's window keeps them, account wide, in `classTrainingData = {
prices, notTaught, trainers, characters }` (never rename it), reading the
"unavailable" lines by turning the trainer's filter on and back. Each
character notes what it can train (`characters[guid]`) for the others.
"Class training" on the Gold page (`classTraining`, on unless unticked,
never rename it) and `/bbutler training [on|off]`.

In Butler: the Jobs group leads with "Train N new spells" (Train all at a
class trainer, one spell every `ClassTraining.GAP`, only what the purse
pays for; Show the way elsewhere: Butler's own arrow (see "The arrow"),
which `Logic/WayArrow.lua` sets as `ClassTraining.Guide`; without it
Equipment's quest arrow when it is loaded (`CT:GuideFn` reads
`_G.BlackthornesEquipment.ClassTraining.Guide`), else TomTom or the game's
map pin).
The next level's spells and a "Then:" line for each other character on
this realm and side wait
in a Later group at the foot of the list, right above Gold goals (the
owner, 2026-10-13: what can be done now goes at the top;
`Jobs:LaterLines`, folded in `folded.later`; `Jobs:TrainingLines`,
`UI.UpdateTrainRow`). A character's note keeps its `realm` and `faction`;
an older note takes them from Equipment's `characterGear` or Tradeskills'
`Holdings`, and one whose side is still not known is left out until it
logs in (`ClassTraining.SameSide`; a player saw the other side's and other
realms' characters, 2026-10-18). The window comes up at a
class trainer with something to train (`Jobs:AtTrainer`). The gold fund
keeps back the playing character's `ReadyCost()` and tops another
character up by its `Other(guid).cost` (`Funds:Plan`). Tested in
`tools/test_classtraining.lua`. Not yet seen in game.
A spell is known when the client says so, when a class trainer showed it
as learned (kept by GUID in `classTrainingData.learned`, never rename it),
or when a higher rank of the same name is known (the data skips a rank now
and then; a player was told to train spells known a long time,
2026-10-19). A trainer line in another language matches by name and the
rank's number.
Skipping a spell (a player asked, the owner said build it,
2026-10-22): right-click a spell in Equipment's Training drawer to skip
it, and again to bring it back. Kept account wide in
`classTrainingData.skipped[guid][spellID] = time` (minus the time when
brought back; never rename it); the newest change wins between
Equipment's and Butler's saves (`CT.SISTERS`). A skipped spell leaves the
plan, Train all and the gold goal. Tested in
`tools/test_classtraining.lua`.

## Show the way across zones and the sea

The owner said build it (2026-10-21, from a mockup) in every addon: with
"Guide Me:" ticked under CLASS TRAINING on the Gold page (`arrowRoute`,
account wide, on unless unticked, never rename it), Show the way to a class
trainer in another zone or across the sea lists the steps in chat
(flights this character knows, the boats and zeppelins of its side, its
Hearthstone, walks through the zones between) and pins the first stop
(`ClassTraining.TripTo`, `Travel:Guide`), when no arrow took it; Butler's
own arrow takes it, so it leads the way step by step instead.
`Logic/Travel.lua`, `Data/Travel.lua`, `Data/TravelZones.lua`,
`UI/TravelCard.lua`, `UI/TravelMap.lua`, `Media/Frame/TravelDot.tga` and
the two `tools/make_travel*.py` are Farmer's, the same in every addon (a
fix to one belongs in all; Farmer's `CLAUDE.md` has the details); Butler's
side is `ns.TravelHost` at the end of `Logic/WayArrow.lua`. Tested in
`tools/test_classtraining.lua`. Not yet seen in game.

## The arrow

The owner asked (2026-10-22): Butler and Tradeskills give the same
guidance as the addons with an arrow, TomTom too. `Logic/WayArrow.lua` and
`UI/WayArrow.lua` are Pets' beast arrow (itself Farmer's goal arrow)
brought over as a copy, not a call, and `tools/make_arrow_art.py` draws
the same `Media/Arrow/*.tga`; a fix to the dial belongs in every addon
with one. Show the way to a class trainer aims it (`WayArrow:Aim`, the
place kept per character in `wayArrowPlace`, the dial's spot in
`wayArrowX`/`wayArrowY`; never rename them). It shows only while a place
is set: its close gem, or opening the trainer or a vendor once you are
there (`WayArrow:Reached`), puts it away. The dial takes no clicks and shows no hover text (the owner,
2026-10-23): drag moves it and the red gem closes it. Only one Blackthornes arrow is
on screen at a time (`_G.BlackthornesArrows`, as `"Butler"`). With TomTom
installed and "Use TomTom:" ticked (`useTomTom`, on unless unticked, Gold
page; `Logic/TomTom.lua`, the same file as Farmer's, Equipment's and
Pets'), TomTom's arrow shows the way instead of the dial. Tested in
`tools/test_wayarrow.lua`. Not yet seen in game.

## Gold goals

The owner said build it (2026-10-13, from a mockup; "the purse section
goes at the bottom of Butler"). `Logic/GoldGoals.lua` works out three
goals, filled from one purse in order: class spells (`ClassTraining`'s
ready spells, else the next level's), profession training (the next rank
once the skill reaches it, from `GoldGoals.RANKS`, Classic's usual
prices, plus Tradeskills' `Butler:LearnCost()`, the trainers' recipes the
character could learn now; since 2026-10-22, a player asked which recipe
it meant, its `recipes` list names each on the goal's hover, up to
`GoalsUI.RECIPES_SHOWN`, and a click on that row calls Tradeskills'
`LearnNext:ShowTheWayFor(recipeID)`, inside a pcall, so its arrow,
"Guide Me:", TomTom and seen spots lead to the trainer;
`GG.RecipeList`, `GG:ShowTheWay`, `GoalsUI:Click`) and riding (`GoldGoals.RIDING`). Each profession is
its own goal (the owner, 2026-10-23: "each should have their own";
`ProfessionGoals`): its rank to train now and its own recipes share a row,
"Expert Tailoring and 9 recipes", recipes alone read "9 Tailoring
recipes", and one with only a later rank keeps a dim row; the ones to pay
for now come first, cheapest first. A click goes to the rank's trainer
first (Tradeskills' `LearnNext:TrainerFor` and `:ShowTheWay`), then the
recipes' trainer. Each is
ready (green), saving (gold) or far (levels away, dim). The level cap is
read from the game (`GoldGoals.MaxLevel`: 30 in the beta, 60 at release,
60 when the game does not say); never hardcode it. A trainer's own price
and level, read at `TRAINER_SHOW` by spell name (not at a class trainer),
win over Classic's and are kept. The purse is less what the gold fund
will mail to another character (`GoldGoals.SetAside`); the fund never
limits spending.

`UI/GoldGoals.lua` draws it under the list (`UI:PlaceGoals`; the window
grows by its height, its top stays put): GOLD GOALS with the purse, a
segment per goal, and a dark glass row per goal with a glowing bar. A
click on the heading folds it (`folded.goldGoals`, per character). In All
characters the same place lists every character (`GoldGoals:Everyone`,
from each one's note in `goldGoalsData.characters[guid]`, gold from
Tradeskills' `Holdings` when it has it), with how many goals are met.
"Gold goals" on the Gold page (`goldGoals`, on unless unticked) and
`/bbutler goals [on|off]`. Never rename `goldGoals` or `goldGoalsData`.
Tested in `tools/test_goldgoals.lua`. Not yet seen in game.

## The cheapest skill-up

A player asked, the owner said build it (2026-10-19, from a mockup with
the words he approved): with "Cheapest Skill-Up:" ticked (Gold page,
PROFESSIONS; `skillUpLine`, account wide, off unless ticked, never rename
it; `/bbutler skillup on|off`), a PROFESSION LEVELING group right under
Jobs (its own fold, `folded.leveling`; the owner, 2026-10-20: the queued
crafts stay above it) has a line for each profession still being leveled: "Next skill point: ITEM"
and "PROFESSION 52/75. A sure point for about 18c." (a likely point for a
yellow craft, "you make about X back" when it pays), with Queue, then
Queued. `Logic/SkillUp.lua` reads Tradeskills, inside a pcall, read only:

```lua
_G.BlackthornesTS.Butler:NextSkillUp()
  -- { { profession, skill, max, recipeID, itemID, name, tier, cost, queued, toBuy } }
_G.BlackthornesTS.Butler:QueueSkillUp(recipeID)   -- true, or false and why
```

The pick is the top of Tradeskills' Level Up tab for each profession, so
the two always agree. A profession at its cap for now comes as `{
profession, english, skill, max, capped = true }` (2026-10-20, the owner:
point to the next trainer each step until max), and its line names the
trainer's next rank from `GoldGoals.RANKS` (`SkillUp.Train`, `GG.LineOf`):
"Train Expert Enchanting" and "Visit an Enchanting trainer to raise your
cap to 225, about X", or "You can train it at level N" while the level is
short; no Queue button, and no line past the last rank (Cooking and First
Aid stop after Journeyman). Without Tradeskills, no line. If either call
changes, change `Logic/SkillUp.lua` too. Tested in `tools/test_skillup.lua`.

Short of gold (a player asked, the owner approved the words 2026-10-22):
`toBuy` is copper for the materials the bags and bank lack. When it is
more than the purse (`GetMoney`), the line's second part is the red note
"You need about X to buy what's missing. You have Y." (`SkillUp.ShortNote`)
and the hover keeps the usual words above it. The pick follows
Tradeskills' Level Up "Can afford" box; Butler has no setting of its own.
`Funds`' `PLAYER_MONEY` redraw keeps it current. Tested in
`tools/test_skillupgold.lua`.

## What Farmer calls here

Farmer's XP bar (2026-10-13) reads class training for its level-up cheer,
inside a pcall, read only, falling back to Equipment's copy:

```lua
_G.BlackthornesButler.ClassTraining:IsOn()
_G.BlackthornesButler.ClassTraining:Plan()   -- ready, cost, unknown
```

Keep these names and fields stable (they are the shared
`Logic/ClassTraining.lua`'s, so Equipment's too); if one has to change,
change Farmer's XP bar in the same breath.

## Sell below

A player asked for anything looted below a value they set to be marked
junk, and the owner said add it to Butler (2026-10-11). "Sell below" on
the Errands page (`Widgets.CreateMoneyBox`: gold, silver and copper boxes,
saved on Enter or leaving a box) and `/bbutler sellbelow 50s` (`off` to
stop) save `sellBelow`, copper, account wide, nil when off. It is step 11
in `Verdicts:Best`: after the player's lists, quest items, no vendor value
and every sister's Keep, an item whose most (vendor, Tradeskills' auction,
a usable disenchant) is under the amount goes under Sell, "Worth less than
X". Soulbound green or better is never included, and the step is skipped
when Tradeskills gave no answer, since without an auction price junk and a
good white item look the same. It only adds to Sell: nothing is deleted,
and selling is still the Sell button. Tested in `tools/test_sellbelow.lua`.

## Free bag space

The owner asked (2026-10-11) for the free bag slots on the game's own bag,
and picked the backpack button of the bag bar from a mockup
(`mockups/butler-free-space-bag-button.png` in the project files).
`UI/FreeSpace.lua` puts a number in the button's corner in the game's stack
count font, made bigger and bold (`FreeSpace.TEXT_SIZE`, 2026-10-20): white, amber at 8 free or fewer (`FreeSpace.AMBER`), red at 3
or fewer (`FreeSpace.RED`). Only bags that take anything count; profession
bags (a bag family other than 0) and the reagent bag are listed apart on
the tooltip. Hovering the button adds each bag's free slots under the
game's own lines. "Free bag space" on the General page (`freeSpace`,
account wide, on unless unticked, never rename it) and `/bbutler
freespace` turn it off and on. When the game shows its own count on the
button (`MainMenuBarBackpackButtonCount`), Butler's stands down.

How it sits on a game frame without touching it: the number is Butler's own
frame, a child of `MainMenuBarBackpackButton` so it follows the button's
showing, scale and Edit Mode place; it takes no mouse and nothing is
written on the button, and the tooltip lines come through `HookScript`
("OnEnter"), which runs after the game's own script. No Hide, Show or
field writes. A bag addon that takes the bar away takes the number with
it. Smooth play: `BAG_UPDATE_DELAYED` and `BAG_CONTAINER_UPDATE` only mark
it stale, one read of a handful of calls follows 0.2 s later and only while
the number is visible (its `OnShow` reads what it missed), and the text is
set only when the number or its colour changed. `/bbutler probe` says
whether the button was found. Tested in `tools/test_freespace.lua`. Not
yet seen in game.

## Who has it

The owner said build it (2026-10-11). `UI/WhoHas.lua` adds lines to every item's tooltip
saying which characters hold it and where: "Your characters have 33", then
"Bob Wither   21 (20 bags, 1 mail)", most first, six names at most, the
character playing marked "(you)" and left off when only its own bags hold
it. It reads Tradeskills' `Butler:Holdings()` (the same call as All
characters), so without Tradeskills there are no lines; an old name-realm
record of the character playing (`playing` without `isCurrent`) is not
counted again. Only GameTooltip and ItemRefTooltip get lines (never the
compare tooltips), added through `TooltipDataProcessor`'s post call, or
`OnTooltipSetItem` by HookScript on a client without it; nothing is
written on the tooltip. Smooth play: a hover only looks its item up in a
lookup by item ID; bag, bank and mail events only mark it stale, and the
next hover builds it again at most once every `WhoHas.REBUILD_GAP` (1 s).
"Who has it" on the General page (`whoHas`, account wide, on unless
unticked, never rename it) and `/bbutler whohas`. Tested in
`tools/test_whohas.lua`. Not yet seen in game.

## Keep on each character

A player asked, the owner said build it (2026-10-17): keep a number of an
item on one character, and let the rest follow the usual rules. The
right-click menu's "Keep on This Character..." opens a box for the number
(0 clears it), and Settings, Errands page, KEEP ON EACH CHARACTER shows
and changes any character's list from any character. `Logic/KeepHere.lua`
keeps it account wide by GUID, `keepHere[guid] = { name, items = {
[itemID] = count } }`, with a copy of the playing character's list in its
own save (`BlackthornesButlerCharDB.keepHere`, read when the GUID can't
be, never written then); never rename either. Rule `keepHere` is first
in `Verdicts.DEFAULT_ORDER` and can be moved or turned off on the Order
page. `Verdicts:Groups` keeps enough stacks (`KeepHere.Plan`: the biggest
that fit, then the smallest past that) and judges the rest again past the
rule (`Judge(entry, nil, true)`). A kept stack holding more than the
number is split while the window is up and no fight is on
(`KeepHere:SplitNext`, `SplitContainerItem` into a free slot, at most
`SPLITS` tries an item each time the window opens); with no free slot the
whole stack is kept and the row asks for one. Nothing is sold or deleted
by it. Keep All (the owner asked the same day), beside Save in the menu
and beside the number in Settings, saves `KeepHere.MOST` (9999), shown as
"All" (`KeepHere.IsAll`, `Shown`): every stack stays, nothing is split,
and no new key is saved. Tradeskills has its own keep for its Sell list
(2026-10-18, the owner: the bigger number wins in both). The rule reads
`KeepHere:Effective`, the bigger of `Count` (Butler's own, which
Tradeskills reads) and Tradeskills' `_G.BlackthornesTS.KeepHere:Count(itemID)`,
inside a pcall, read only; the menu and Settings still show Butler's own.
If that call changes, change `KeepHere.FromTradeskills` too. Tested in `tools/test_keephere.lua`.

## Your Tradeskills lists

The owner said build it (2026-10-19, from a mockup), with Tradeskills'
own list rules (its "List rules"): each of the player's Tradeskills lists
can have Mail To (one of the player's characters) and Keep Here (that many
of each, on every character). Tradeskills only holds the lists
(`Butler:Lists()`, with each list's `id`); Butler does the work.
`Logic/ListRules.lua` keeps them account wide by list id, so a rename keeps
them: `listRules[id] = { mailTo = full name, keep = count }` (never rename
it; a list with neither has no entry, so nothing changes until a rule is
set). An item on two lists follows the first on Tradeskills' Lists view
that has a rule (`ListRules:For`). Keep Here joins `KeepHere:Effective`:
the biggest of Butler's own keep, Tradeskills' and the list's wins (the
list's name comes back second when it is the biggest). Mail To is the rule
`lists` ("Your Lists" on the Order page), after the Always mail list:
"On your NAME list, keeping N" mails the rest past the keep, "Your NAME
list keeps N here" keeps the rest; never bound items, never the character
playing, so once the items reach that character they stay, as with Always
mail. Settings, LISTS page, YOUR TRADESKILLS LISTS: a list picker, "Mail
To:" and "Keep Here:". Tested in `tools/test_listrules.lua`.

## The rule order

The owner said build it (2026-10-17, from a mockup): Settings has an ORDER
page (`UI/RuleOrder.lua`, `RuleOrderUI`) that lists the rules
`Verdicts:Decide` asks, in the order it asks them. Equipment sets and quest
items are always first (`Verdicts.FIRST`; quests now come before the
Always keep, bank and mail lists), the best price and Look at it always
last (`Verdicts.LAST`); the 23 between (`Verdicts.DEFAULT_ORDER`, each a
step in `Verdicts.STEPS`) are dragged by their grip, the others sliding
out of the way, and each has a tick box. A rule with a setting of its own
(`Verdicts.OWN_SWITCH`: alt upgrades, Disenchant greens here) ticks that
setting; Sell below and the bank alt have an Open button to their pages
instead. Saved account wide, never rename either: `ruleOrder` (the ids in
order, nil while it is the usual one; `Verdicts:Order` drops unknown and
repeated ids and puts a missing one back after the rule it follows in the
usual order, so a rule added later finds its place) and `rulesOff` (`[id]
= true`). Set Default (`Verdicts:SetDefault`, also `/bbutler order
default`) clears both; Undo Move takes back the last moves and ticks for
the session. In any order `Allowed` holds: an upgrade to wear now is never
sold, auctioned, broken or mailed except by the player's own lists,
nothing bound is mailed, nothing is mailed to the character playing. The
rows move by an OnUpdate only while one is moving. Tested in
`tools/test_ruleorder.lua`.

## Butler on tooltips

A player asked; the owner said yes (2026-10-13): "add Butler as the last
line on the tooltip and only if Butler is loaded". `UI/VerdictTip.lua`
adds one line to the tooltip of an item in the bags of the character
playing: "Butler: Sell" (or "Butler: Mail to FULL NAME"), with what one is
worth (the verdict's `unit`) on the right. Last line: its post call (or
`OnTooltipSetItem` script hook) goes in `VerdictTip.DELAY` (1 s) after the
first `PLAYER_ENTERING_WORLD`, so it runs after Who has it and the lines
other addons hook at login. Only GameTooltip and ItemRefTooltip; nothing
is written on them. Smooth play: a hover reads one slot (the hovered bag
button's `GetBagID`/`GetID`, else where Butler's last read saw the item,
read again to be sure), takes the window's row when `Verdicts.groupCache`
is current, else `Verdicts:Judge` for that one item (kept). Butler reads
the bags only while its window or a vendor is up, so a hover that finds
nothing on stale bags asks for one `Bags:Scan()`. "Butler on tooltips" on
the General page (`verdictTip`, account wide, on unless unticked, never
rename it) and `/bbutler tooltip`. Tested in `tools/test_verdicttip.lua`.
Not yet seen in game.

## Vendor price on tooltips

A player asked for what an NPC vendor charges for each item, and the owner
said build it (2026-10-22, words approved): "Vendors sell it for 25c" goes
on any item's tooltip (carried or not), under the Butler line, only when a
vendor is known to sell it; never the price the item data carries for
everything. `Logic/VendorPrices.lua` reads every vendor the player opens
(`MERCHANT_SHOW`/`UPDATE`, settled `SETTLE`, `BUDGET` items a frame,
`Ammo.MerchantItem`) and keeps the price for one account wide in
`vendorBuyPrices[itemID]` (never rename it); token items and anything under
a copper for one are skipped. Butler's own price wins; without one it asks
Tradeskills, inside a pcall, read only:

```lua
_G.BlackthornesTS.Butler:VendorPrice(itemID)   -- copper for one, or nil
```

"Vendor Price:" on the General page, Off, Shift or Always (`vendorPrice`,
on unless picked Off, never rename it; Shift key `vendorPrice`). `/bbutler
probe` has a "vendor prices" line. Tested in `tools/test_vendorprices.lua`.
If Tradeskills changes the call, change `VendorPrices.FromTradeskills`.

## Off, Shift or Always on tooltips

A player asked, the owner said yes (2026-10-18): each tooltip line an
addon adds is Off, Shift (only while Shift is held) or Always, picked on a
stepper in Settings (`SettingsUI.TooltipShiftControl`). Nobody's settings
change: a line that was on reads as Always and one that was off as Off.
`UI/TooltipShift.lua` is the same file in all five addons (a fix to it
belongs in all five): `ns.TooltipShift` `:Mode`, `:Apply`, `:Shows`
(asked every time the tooltip is built, never kept in a cache) and `:Held`
(adds "Hold Shift for more." once a tooltip, shared through
`_G.BlackthornesTooltipShift`, whose one frame redraws GameTooltip on Shift
only while a line is on Shift). Butler has two lines on the General page:
`whoHas` ("Who Has It:") and `verdictTip` ("Butler on Tooltips:").
Whether each is on stays in `whoHas` and `verdictTip`; the Shift choice is
kept account wide in `tooltipShift[key] = true` (never rename any of them;
nothing is written until Shift is picked). The verdict stays Butler's last
line, so the hint goes after it: Who has it notes a held line in
`WhoHas.held` and `VerdictTip:Decorate` adds the hint at the end (Who has
it adds it itself in the second before the verdict's hook goes in). Tested
in `tools/test_tooltipshift.lua`.

## The trash can

The owner asked (2026-10-13) for a small can on the item worth the least
when a player's bags are full. `UI/Trash.lua`: while a bag window is open
and the bags that take anything have no free slot (`Trash.FREE`, 0; the owner
asked, 2026-10-13, for it to go when a slot frees), a gold can
(`Media/Trash/TrashCan.tga`, drawn by `tools/make_trash_art.py`; rerun it,
never edit the TGA) sits on the top right of the stack worth the least
(`Trash:Pick`: the verdict's `unit` times the stack) among items Butler
would Sell, Auction or Disenchant anyway (`Trash.FROM`), priced, not
locked, not a quest item. A trade good counts as
`Trash.MATERIAL_LEAN` (1.5) times its worth, so close calls go to junk;
and two short stacks of one item that fit in one slot come first: the can
says "Stack these to make room" and a click joins them (`Trash:Merge`,
the owner 2026-10-16). Keep, Mail, Bank, Wait and Look at it never get
it. A red glow lies round that slot too, pulsing slowly (the owner,
2026-10-19; `Trash:Glow`, `Media/Trash/PickGlow.tga` from the same tool,
`Trash.GLOW_REACH`), our own frame with no mouse, shown and hidden with
the can. Butler never deletes: a click picks the item up
(`C_Container.PickupContainerItem`, after reading the slot again) and says
to drop it outside the bags, where the game's own box asks first. The can
is Butler's own button on UIParent, anchored to the game's item button
(found as Equipment's `BagIcons` does); the bag windows are only hooked
(`UpdateItems`, `OnShow`, `OnHide`). Hidden in combat, at a vendor and while
the cursor holds something. "Trash can when full" on the General page
(`trashCan`, account wide, on unless unticked, never rename it) and
`/bbutler trash`. Tested in `tools/test_trash.lua`. Not yet seen in game.
Farmer has the same can by its own prices (its `UI/Trash.lua`, same art
and tool) and stands down while `_G.BlackthornesButler.Trash` exists, so
only one shows; keep `ns.Trash` on the global, or change Farmer's
`Trash.ButlerHasIt` too.

## Swap when full

A player asked, the owner said build it from a mockup (2026-10-28): with
the bags full, a popup beside the loot window offers to swap the item the
trash can would pick (`Trash:Pick`) for loot worth more that has nowhere
to go (`SwapWhenFull:BestLoot`, `Fits`: no stack with room, no profession
bag that takes it), each at Butler's own worth. `UI/SwapWhenFull.lua`:
Swap destroys the cheap item in that one click (the owner, 2026-10-28:
ticking the box means the player wants Butler to do it; the only place
Butler deletes, `Swap:Take` picks the slot up, checks the cursor holds
that item, then `DeleteCursorItem`), and once its slot is empty and the
loot window is still open, Butler loots that item (`FollowSwap`,
`LootSlot`). Not Now and the close gem put it away until the next loot
window; hidden in a fight. "Swap When Full:" on the General page
(`swapWhenFull`, account wide, off unless ticked, never rename it).
`/bbutler probe` has a "swap when full" line. Tested in
`tools/test_swapwhenfull.lua`. Not yet seen in game.

## The Bags window

Players kept asking for a bag window in our style, and the owner said
build it inside Butler (2026-10-19, from a mockup whose words he approved,
with a one huge bag choice). Never name another bag addon in the repo,
PRs or posts. `Logic/BagView.lua` works out what it shows;
`UI/BagWindow.lua` draws it in the house frame (plate "Bags", portrait,
close gem, size grip, dark glass well). Off unless ticked: "Use Butler
Bags:" under BAGS on the General page, and `/bbutler bags [on|off]`
(alone it opens or closes the window).

- **The game's bags are never hidden.** While it is on, the game's bag
  windows (`ContainerFrameCombinedBags`, `ContainerFrame1` to 13) go under
  `ns.Veil` (`UI/Veil.lua`, Equipment's file: see-through, no mouse; a fix
  to it belongs in both), also as each one shows (HookScript OnShow). The
  bag calls (`ToggleAllBags`, `OpenAllBags`, `CloseAllBags` and the like)
  are only post-hooked and settled once a frame: a toggle flips the window,
  else an open shows it and a close hides it. Turned off, the veil comes off.
- **Squares** are the game's `ContainerFrameItemButtonTemplate` on a holder
  per bag (`SetID(bag)`, `SetID(slot)`), so clicks, drags, tooltips and
  using items are the game's own; our own button if the client refuses
  it. Made `MAKE_BUDGET` a frame, never in a fight: in a fight only what
  each square shows is painted, and the layout waits for
  `PLAYER_REGEN_ENABLED`. `/bbutler probe` has a "bag window" line.
- **Group By:** What To Do (Butler's verdict groups in Butler's order, with
  Fill mail and Move to bank on their headings), Item Type (QUEST, ARMOR,
  WEAPONS, TRADE GOODS, FOOD AND DRINK, OTHER, greys under Sell) or One
  Grid (every slot in bag order, empty ones too; a bag that takes only
  some things, such as a mining bag, on rows of its own,
  `BagView.GridSections`, so what Sort puts there is not mid-grid). Search by name or ID and
  the Upgrades, To Sell, For My Crafts and For My Goals chips dim what does
  not match. Marks come from `Verdicts` and the sisters' answers
  (`BagView:Marks`, kept per `Verdicts.version`); the gold coin is for
  vendor items only (`vendor`, the owner 2026-10-20), never auction ones; new items glow until
  hovered, by the game's own new item flag (`C_NewItems`, which lasts
  through a /reload), else by counts from the first full read this session
  (never the empty list a /reload starts with, which lit every item,
  2026-10-20); nothing saved. The game's flags are cleared for what is
  carried at that first read and whenever the window closes
  (`BagView:ClearNew`, as the game's bags do on close; veiled, they never
  did, so every slot stayed flagged), and the template's own blue glow
  (`NewItemTexture`, `BattlepayItemTexture`, its flash) is kept out of
  sight (`QuietTemplateGlow`). Tested in `tools/test_bagnewglow.lua`. Sell and Disenchant stay in the
  main Butler window. Sort uses the game's bag sort where there is one; Era has none, so
  Butler sorts itself (`Logic/BagSort.lua`, the owner said build it,
  2026-10-24): loose stacks of one item together first, then each item to
  its place (Hearthstone first, greys last, kinds in `BagSort.CLASS_ORDER`),
  one move at a time, waiting for both slots to unlock; bags that take only
  some things are sorted on their own. A fight, something on the cursor or a
  move that never settles stops it; nothing is dropped or deleted. Tested in
  `tools/test_bagsort.lua`.
- **Bank** and **Everyone** tabs are view only: the bank read live at a
  banker, else as Tradeskills last saw it; Everyone is All characters'
  list (needs Tradeskills).
- While it is on, the trash can and its red glow go on this window's
  squares instead of the game's veiled ones (`Trash.BUTLER_BAGS`,
  `BagWindow:ButtonFor`, only on Your bags, 2026-10-20: the window had
  drawn only a thin red edge, full bags or not); `Bags:Wanted` reads the
  bags while it shows; `Verdicts:Redraw` redraws it.
- **Empty Slots** (the owner said build it, 2026-10-20, from a mockup):
  a tick box left of Sort, on Your bags only, kept for each Group By in
  `bagEmptySlots` (`{ [group] = true/false }`, nil reads as
  `BagView.EMPTY_DEFAULT`: One Grid ticked, the others not, so nothing
  looked different). Ticked under What To Do or Item Type, an EMPTY SLOTS
  group comes last (`BagView:WithEmpty`); unticked under One Grid, the
  items pack with no gaps. The foot's "N free" is bigger and turns amber
  and red as Free bag space does (`BagWindow.FREE_SIZE_UP`,
  `FreeSpace.Level`).

Saved, account wide, never rename them: `bagWindow` (off unless ticked),
`bagGroupBy`, `bagItemSize`, `bagItemLevel`, `bagNewGlow`, `bagEmptySlots`, `bagScale`,
`bagPoint`, `bagRelPoint`, `bagX`, `bagY`. Tested in
`tools/test_bagwindow.lua`. Not yet seen in game.

## Butler's voice

The owner asked (2026-10-11) for Moroes, Karazhan's butler, to answer when
the player opens Butler ("You rang?", file 555818) and closes it ("Now,
where was I? Oh, yes...", 555814); he tested both IDs in game. `UI:Say`
plays the game's own file by ID (`PlaySoundFile(id, "Dialog")`), so no
Blizzard audio ships in this public repo. It must never speak over an
NPC, and the client can't say when one is talking, so a line is said only
when the player opens the window (`UI:Toggle`, `/bbutler all`) or closes
it (its OnHide, unless `LeftVendor`/`LeftPlace` closed it:
`closingByItself`), and never while a vendor, mailbox, bank or any NPC
(`UnitExists("npc")`) is open (`UI.AtAnNPC`). A window that comes up by
itself (`UI:Show`: vendor, mailbox, bank, Jobs at login) says nothing.
Each line waits `UI.VOICE_GAP` (180 s). "Butler's voice" on the General
page (`voice`, account wide, on unless unticked; never rename it). Tested
in `tools/test_voice.lua`. Not yet seen in game.

## German translation

The owner said yes (2026-10-12) to German in Butler, after Pets' pilot and
Farmer. Players are told the language as "Deutsch"; the code names stay
`deDE` and `Locale/deDE.lua`. It ships with 0.2.0.

- **English is the key and the fallback.** `Locale/Locale.lua` (first in
  the TOC, Pets' file) makes `ns.L`, whose missing keys answer the key
  itself; `L.Format(key, ...)` is `string.format` on the translation and
  puts values named by place (`%2$s ... %1$d`) in order.
- **Adding a string:** `L["English text"]` or `L.Format("English %s",
  value)`, a literal where it is written, one whole sentence a key (never
  pieces joined with `..`), both forms for a plural; add its line to
  `Locale/deDE.lua` (informal "du", a polite butler's voice) and run
  `python tools/check_locale.py` (warns only; keep it at 0 missing).
  `tools/test_locale.lua` loads Butler as a German client.
- **Left in English on purpose:** slash command words and typed words
  (`off`, g/s/c), saved and internal keys (verdict keys; `Verdicts.LABELS`
  only shows them; Ammo's `word`, with `label` shown), secure button
  macros, mail subjects that are matched (`Learning.ADDON_SUBJECTS`),
  Ammo's English DPS fallbacks, data and client names, debug lines and
  every `ProbeText` (`/bbutler probe`).
- German runs about 30% longer: buttons grow to fit and rows wrap; a new
  fixed width must wrap or grow, never end in "...".

## Simplified Chinese, French, Spanish and Russian

The owner asked (2026-10-18) for Simplified Chinese, French, Spanish and
Russian in every addon, after a player asked for Chinese. They work like
German: written by us from the English keys, never from a player's or
anyone else's file (the owner turned down a player's zip for safety).
`Locale/zhCN.lua`, `Locale/frFR.lua` ("tu"), `Locale/esES.lua` (one
Spanish for both Spanish clients: it loads on "esES" and "esMX", neutral
words, "tú") and `Locale/ruRU.lua` ("ты"), each in the game's own words
and a polite butler's voice, listed in the TOC after deDE. Talk to the
owner about "Simplified Chinese", "French" and so on, never the codes.
Every new string gets a line in all five files; `tools/check_locale.py`
checks them all. Group headings go through `:upper()`, which leaves
Chinese and Cyrillic as they are. Tested in `tools/test_locale.lua`. Not
yet seen in game.

## How this repo was set up

It copies Pets (itself Equipment's, itself Farmer's) on purpose, so check the
sisters before inventing a convention:

- **Layout** `Core/ Data/ Logic/ UI/ Probe/ tools/ docs/`, one module per file through
  `ns.NewModule`, no Ace3 or LibStub. The global is `_G.BlackthornesButler`,
  the commands `/bbutler` and `/butler`, the saved data
  `BlackthornesButlerDB` (account) and `BlackthornesButlerCharDB` (per
  character). Never rename them once released.
- **Palette** is the house one (`ns.COLORS`). `UI/Theme.lua`,
  `UI/Widgets.lua`, `UI/Minimap.lua` and `UI/Settings.lua` are Pets' with
  the pet parts taken out. The minimap button starts at 290 degrees, clear
  of Tradeskills' at 170, Farmer's at 200, Equipment's at 230 and Pets' at
  260. The TOC icon is `INV_Misc_Bag_08`.
- **Tools** (`syntaxcheck`, `lintcalls`, `runtests`, `check_release`,
  `check_package`, `check_private_files`, `announce_discord`,
  `post_general` and their tests, `link.ps1`, `deploy.ps1`) are Pets' with
  the names changed. If one of them gets a fix in a sister repo, bring it
  here too.
- **Tests** are `tools/test_*.lua`, found by name. `tools/testenv.lua` loads
  the files the TOC lists, so there is no second list to keep.
- **PRs** follow the sisters' habit: a "Before:" and an "After:" paragraph
  in plain words, then a short "How" naming the functions and tests touched,
  that the checks pass, and whether `/reload` is enough. Release PRs are
  `release/X.Y.Z` branches titled "Changelog for X.Y.Z".
- **CurseForge:** Forever's project is **1739020** (the owner created it
  2026-10-11); this Era copy's is 1763328, on the TOC's `X-Curse-Project-ID` line. The first release is 0.1.0. The
  repo needs the `CF_API_KEY`, `DISCORD_WEBHOOK_URL` and
  `DISCORD_GENERAL_WEBHOOK_URL` secrets, which he sets himself. The logo
  follows the house style: a dark 512 px tile, the gold satchel, grey
  "BLACKTHORNES" and gold "BUTLER".
- **API findings** go in `docs/FOREVER_API_FINDINGS.md`. Tradeskills',
  Equipment's and Pets' files of the same name record what the Forever client
  does for their areas; read them before relying on an API.

## The shared minimap button

A player asked, the owner said build it from a mockup (2026-10-28), in all
five addons: one minimap button for every Blackthornes addon loaded, whose
click opens a small menu (the house frame, "BLACKTHORNES" on the plate, a
dark glass row for each addon with its icon, name and what it does). A
row's left-click opens the addon, right-click its settings; Farmer's
middle-click brings back its panels and Equipment's Shift-click toggles
the upgrade quest. `UI/SharedMinimap.lua` is the same file in all five (a
fix to it belongs in all five), and so is `tools/test_sharedminimap.lua`.
There is no shared core addon: every copy signs up in
`_G.BlackthornesMinimap`, each addon joins with its own button
(`SharedMinimap:Join`), and the copy with the highest `FILE_VERSION` draws
the shared button and menu. It is on by default (the owner, 2026-10-28):
"Combine Addon Buttons:" in each addon's Settings, ticked unless unticked;
unticked, every addon keeps its own button. Only our own buttons are hidden
or shown, never the game's. Saved in every loaded addon's account save,
account wide, never rename them: `minimapButton` ("shared" or "each", nil
reads as shared), `minimapButtonAt` (the newest answer wins) and
`minimapSharedAngle`. Never call it "One for All" (another addon's name).
Every addon's own button also takes left-click to open and right-click for
settings. Not yet seen in game.

## The settings pages (from Tradeskills)

The owner asked (2026-10-09) for Tradeskills' Settings upgrade in Pets,
Equipment and Farmer, and Butler copied it. `UI/SettingsPages.lua` is the
same file in all four (a fix to it belongs in all four): category pages
along the top (`settingsPage`, the one left on), two columns a page, what a
setting does as the row's tooltip ("Show descriptions",
`settingsDescriptions`, off by default, puts it back under the rows), "Find
a setting", and Text size (`textSize` normal/large/larger adds 0/1/2 to
`Theme.sizes`, a lookup over `Theme.BASE_SIZES`; read once, so it waits for
/reload). The window fits its fullest page, so no page scrolls. Add a
setting with `pages:Row(page, column, label, description)` and
`pages:Section(page, column, "HEADING")` in `UI/Settings.lua`; every
`/bbutler` command that changes a setting has a control there, but never
one that deletes data. Chat-only commands that only list things in chat
(help, jobs, lists, upgrademail, gold, training, goals) are typed only
(the owner, 2026-10-15; `CHAT_ONLY` in `tools/test_settings.lua`). The
owner's standard for rows (2026-10-15): Title Case labels ending ":",
one-word controls ("On", "Show", "Open"), and a hover only when it is
needed (a row given nil shows no tooltip and nothing under it). The
minimap button always shows: no row, no `/bbutler minimap`, and a saved
`minimapHidden` is kept but not read. Butler has Errands, Bank alt, Gold
and General so far; the plan's other pages (Verdicts, Pet & craft,
Window) come with their features. `reset confirm`, which empties the
player's lists, stays typed.
Word choices are drop-downs, never < > pickers or word steppers (the
owner, 2026-10-23): `Widgets.CreateChoice` takes a stepper's opts
(min, max, step, value, format, onChange) on Pets' `Widgets.CreateDropdown`
and answers `SetValue(value, silent)`, `GetValue()`, `.text` and
`:Pick(value)` (what a menu click does); only numbers keep a +/- stepper.

## The house frame (Titanforged)

The owner picked this look for all the addons on 2026-10-04 from two mockups
(the other was "Arcane Glass"), and Tradeskills got it first. It's the
game's own window shape with the light turned up: a gold metal rim with
corner gems, a round portrait with the addon's emblem, the name on a plate
across the top edge and a red close gem. Buttons are raised metal with gold
labels, and the main action is solid gold with dark "ink" lettering; a
primary button given its own dark `baseColor` keeps a gold label, or it
reads as an empty box (checked in `tools/test_titanforged.lua`).

It lives in `UI/Titanforged.lua` (`Titanforged:Dress(frame, opts)`,
`:Opened(frame)`), with the art in `Media/Frame/*.tga`, drawn by
`tools/make_frame_art.py`; rerun it, never edit the TGAs. All are
Tradeskills' copies (by way of Pets). Butler's emblem is the **satchel**
(`EMBLEM = "satchel"`): a bag with a handle, the flap's edge and a coin cut
out, drawn here so it reads at the 36 px the portrait shows it. The Butler
window wears the full frame, its list in a well (`Theme.Recess`); Settings
has the plate and close gem but no portrait, which would sit over its first
heading. Butler has no Window effects setting, so `Motion.Level()` is always
"full" and the glint always runs. Anything placed inside a dressed window
stays 6 pixels in from its edge, or it covers the rim.

List rows are dark glass, as in the other addons (the owner picked it
2026-10-10 over a gold glow that lit every row): `glass`/`glassAlt` bands
in the well with a fine line under each, the gold wash only under the
mouse. A gradient that fades goes through `Theme.LightGradient`, which
hides it at 0; faded with SetAlpha alone it stayed lit on Forever.

## The fold gem

A player asked, the owner picked the mockup (2026-10-24), in all five
addons: a small gold gem left of a window's red close gem folds the window
down to its plate and opens it back up. `UI/FoldWindow.lua` is the same
file in all five (a fix to it belongs in all five), and so are
`tools/make_fold_art.py` (draws `Media/Frame/FoldGem.tga`; rerun it, never
edit the TGA) and `tools/test_foldwindow.lua`. `FoldWindow:Add(frame,
{ onToggle, canFold })` after `Titanforged:Dress`; it sits on the trim, so
`Titanforged.lua` and `BlizzardLook.lua` are untouched. Folded, the window
keeps its place and width and is `FoldWindow.HEIGHT` tall: the rim, fill
and halo stay (`FoldWindow.Keeps`, by where each lies), the bottom corners
and everything else on it hide and stay hidden while folded, and it can
still be dragged. The gem again, closing it, or opening it by a command or
the minimap button opens it full (`Unfold`). In a fight it will not fold
over a button the game guards. With the Blizzard style it is the game's
own minimize and maximize art when the client has it. Tooltips "Collapse
this window" and "Expand this window"; nothing is saved. Here: the main window and the Bags window (`UI/MainWindow.lua`, `UI/BagWindow.lua`). Folded, `UI:Dock` refuses, so the secure buttons (Sell, Disenchant, Log out and the rest) stay put away until it opens, and the Bags window says it shows no squares (`BagWindow:ShowsBags`), so the trash can leaves them.

## The Blizzard window style

The owner asked (2026-10-10) for a choice of the game's own look beside
Titanforged, in every addon; Butler has it from the start. "Window style"
in Settings (`windowStyle`, `titanforged` or `blizzard`, Titanforged by
default; read once at login, so a change waits for /reload, as Text size
does). `UI/BlizzardLook.lua` is the same file in all five (a fix to it
belongs in all five): picked, it lays the game's colours over
`Theme.colors` (grey metal, the game's gold, plain rows with a blue bar for
the one picked) and puts out the halos; `Titanforged:Dress` hands the
window to `BlizzardLook.Dress` (silver rim, a title tab where the plate
sits, a silver-ringed portrait and the game's `UIPanelCloseButton`, with the
same trim fields); and the widgets call `BlizzardLook.Button`, `.Checkbox`
and `.Thumb` to wear the game's own texture files. Butler has no hanging
tabs yet, and its Settings row is a drop-down like Text size. It
never touches a Blizzard frame. Each file is checked once
(`BlizzardLook.HasArt`); a client without one keeps that widget in the
house look, and `/bbutler probe` lists what is missing. New widgets should
look right in both styles.

## Reading the probe

The owner asked (2026-10-10) for check results without screenshots, in every
addon; Butler has it from the start. `ns.KeepCheck(name, fn)` in
`Core/Init.lua` runs a check that prints to chat, keeps every line it prints
(colours and links taken out, a secret value kept as "(secret)") and saves
them in the account save as `lastProbe = { check, at, version, lines }`,
replacing the last one; chat adds "Saved for Claude, /reload to write it."
It wraps `/bts probe` (Tradeskills, saved under `BlackthornesTSDB.global`),
`/beq probe` and `/beq arrow check` (Equipment), `/bpet probe` and `/bpet
arrow check` (Pets), `/farm arrow check` and `/farm gathering check`
(Farmer, which has no probe), and `/bbutler probe` (Butler). None has a Settings button (the owner, 2026-10-23: checks and debug are typed only, so players never see them; `RegisterHiddenCommand` keeps them out of help, Tradeskills' short help leaves them out). Never rename `lastProbe`; a new check that players run for
a report goes through `ns.KeepCheck` too, and a fix to it belongs in all
five.

When the owner says "read the probe": he has run the check and typed
`/reload` (or logged out). In the thread, connect to his device, ask for
his game's WTF folder (already approved; the path is in the project's
memory) and stage the addon's account save from
`WTF\Account\<account>\SavedVariables\` (`Blackthornes_TS.lua`,
`Blackthornes_Farmer.lua`, `Blackthornes_Equipment.lua`,
`Blackthornes_Pets.lua` or `Blackthornes_Butler.lua`), read only. Read its
`lastProbe`: `check` says which one ran and `at` when; one older than his
message means the save was not written yet, so ask him to `/reload`. Use
only the probe lines; never commit the save or copy anything else out of
it.

## Discord

The addons share a Discord server, Blackthornes AddOns (public invite
https://discord.gg/f2geDecrw2, set up 2026-10-05). After a release uploads,
`release.yml` runs `tools/announce_discord.py`, which posts the version's
CHANGELOG section to the server's #announcements through a channel webhook
kept in the `DISCORD_WEBHOOK_URL` repository secret. The owner sets that secret
himself; never ask him to paste the webhook address anywhere. Without it the
step does nothing, and a failed post never undoes the upload. The tool is the
same in all the repos; a fix to it belongs in all of them.

The owner asked (2026-10-09) for one post in #general per release too,
and (2026-10-10) for it to be short: a few bullets in plain words, a
sixth-grade reading level, warm, in his voice (short, contractions, no
jargon, no file or setting names, never his name), saying what players will
notice. Each release PR writes the new version's section in `NEWS.md`
(`## X.Y.Z`, like CHANGELOG.md; it never ships) next to the CHANGELOG
section: the bullets, then one line of thanks. After the upload
`tools/post_general.py` scans it with `check_package.py`'s PRIVATE list and
posts it through the `DISCORD_GENERAL_WEBHOOK_URL` secret, which the owner
sets himself, under a line with the addon's name and version (so each
addon's bullets are their own group) and "(full list of changes in
#announcements)". It carries no CurseForge link and no card (link previews
are turned off). No section or no secret means no post.
A player's name never goes in a report (the owner, 2026-10-09): no
CHANGELOG, #announcements post, commit or PR text names a player, and
`check_release.py` refuses a CHANGELOG section that credits one
(`names_a_player` in `post_general.py`). The #general post is the one
exception: its last line thanks, by their Discord name, everyone who asked
for or reported the changes, each name once ("Thanks Ana and Bob for the
ideas and reports!"); leave it out when nobody asked. Find who asked from
the project's threads.
The thanks line no longer goes out with the webhook post (the owner,
2026-10-13: thank each player with a real @mention, so they get a
notification): `post_general.py` leaves out the paragraph that starts
"Thanks" (`without_thanks`), and the owner's bot, on his PC, posts it under
the release post with the mentions once he approves the wording, looking
the Discord names up there. Discord IDs never go in a repo. NEWS.md keeps
the thanks line, by Discord name, as before; ask the owner for any name
that isn't known.
This tool is also the same in all the repos.
Changes to the Discord bots, the digest or the release posting tools
(like this one) never go in a CHANGELOG, #announcements or #general
section (the owner, 2026-10-10): they are not changes to the addon.

## What's New

The owner asked (2026-10-12) for the Discord #general post to show in game,
the first time it loads after an update, in one window for every addon.
`UI/WhatsNew.lua` is the same file in all five (a fix to it belongs in all
five), and so are `tools/test_whatsnew.lua`, `tools/make_whatsnew.py` and
`tools/test_make_whatsnew.py`. There is no shared core addon: every copy
signs up in `_G.BlackthornesWhatsNew` as it loads, the first to reach
PLAYER_LOGIN starts the only timer (`WhatsNew.DELAY`, 5 s, never in a
fight), and that one check gathers what is new in all of them. The copy
with the highest `FILE_VERSION` draws the window (first in
`WhatsNew.ADDONS` on a tie); raise it when a change needs the newer copy.

The words are NEWS.md's: it never ships, so `tools/make_whatsnew.py` writes
its newest three sections, bullets only (the thanks line names players and
never ships), into `Core/WhatsNewText.lua` (`ns.WHATS_NEW`; never edit it by
hand). The window shows new features only (the owner,
2026-10-13): a section's
fixes and other changes go under a "Fixes and changes:" line, which go to
Discord but not the window, and every line is plain words with no hype,
no questions to the reader, no exclamation marks and no dashes as
punctuation (the tool notes one that trips `STYLE`). **Every release PR that writes a NEWS.md section runs
`python tools/make_whatsnew.py` too**; `check_release.py` refuses a tag
while the file is behind, and `tools/test_make_whatsnew.py` fails on every
push. The bullets stay in English, also on a German client.

Shown once a version: each addon keeps the newest version shown in its own
account save (`whatsNewSeen`); after an update the sections newer than that
(at most three) show, and an addon that never kept one shows its newest.
"After an update" (`whatsNewPopup`) and "What's New motion"
(`whatsNewMotion`) are on unless unticked, off in all when off in any;
`whatsNewScale` is the size grip's, where the addon has one. Never rename
them. The `whatsnew` command and a Settings button open it any time, with
each addon's newest. It rises in, its divider draws out, each addon's card
slides up with its icon popping and a light crossing it, and the Got it
button glows (one looping animation the game plays, only while it shows);
Motion off lands it all at once. Not yet seen in game.

## The About page and the note

The owner asked (2026-10-13) for a note on how the addons are made, once at
the top of What's New and kept on an About page in every addon's Settings.
`UI/About.lua` is the same file in all five (a fix to it belongs in all
five): `About.NOTE` is the owner's wording, a paragraph a key; change it
only when he asks, in all five, with each `Locale/deDE.lua`. `About:Note`
and `About:Info` build the page's two columns (the version, the Discord in
a box to copy, how to report a bug, a thank-you that names no player, a
What's New button and the other Blackthornes addons from
`SisterNote.ADDONS`); each addon's Settings places them on its "about"
page. `UI/WhatsNew.lua` (FILE_VERSION 3) puts the note at the top of the
next window that comes up by itself, alone when nothing is new, then sets
`aboutNoteSeen` in every sister's account save (never rename it); with the
window turned off it waits. Tested in `tools/test_whatsnew.lua`.

One-time cards (the owner, 2026-10-13): an addon can put cards in
`ns.WHATS_NEW_TIPS`, each `{ key, title, icon, paragraphs, hint, button,
run, due }`. The next window that comes up by itself shows each one after
the note, only when `due()` says so (in a pcall), with a button that calls
`run()` and closes the window. Looked at once either way: the key goes in
that addon's account save as `whatsNewTipsSeen[key]` (never rename it), so
a card never comes back; with the window turned off it waits.
`UI/WhatsNew.lua` is at FILE_VERSION 4 for it. Equipment's
`Logic/UpgradeQuest.lua` has the first, for the upgrade quest, due while
it is off.

## The sister note

The owner asked (2026-10-11) for the addons to say, once, which of the
others a player does not have. `Core/SisterNote.lua` is the same file in
all five (a fix to it belongs in all five), and so is
`tools/test_sisternote.lua`. Every copy signs up in `_G.BlackthornesSisterNote`
as it loads; the first to reach PLAYER_LOGIN starts the only timer
(`SisterNote.DELAY`, 8 s, no ticker), and that one check prints one line for
all of them: the sisters not installed (`C_AddOns.DoesAddOnExist`, else
`GetAddOnInfo`'s "MISSING"), each with what it adds. One installed but
turned off is never named. Once per account: what it named is kept in every
loaded addon's account save as `sisterNoteTold[folder] = true`, so only a
sister never named before (one released later) brings it back. "Sister
addons" in Settings (`sisterNote`, on unless unticked) and the `sisters`
command on each addon: off in any is off in all, and changing it writes all.
Never rename `sisterNote` or `sisterNoteTold`. A new addon goes in
`SisterNote.ADDONS` in all the copies. It names only our own addons.

## One key per character

The owner asked (2026-10-11) that a character can never be mistaken for
another again. Old records had sent errands to the character playing:
Butler filled a mail to itself and told a player to mail Medium Leather to,
and log out for, the character they were on (an old "Name-Realm" record of
Tradeskills' beside the GUID one), and a reload wiped alts' saved gear in
Equipment. The rule, in every addon:

- **A character is its GUID** (`UnitGUID("player")`) in saved data and in
  every call between the addons. Never a first name, "Name-Realm" or a
  short name: Forever lets characters share a first name. Names are for
  showing and for a mail's To line only, always first and last.
- **A GUID the client won't read (a dungeon) means "not sure who's
  playing":** write nothing under another key, and offer nothing for an
  alt. Tradeskills remembers each character's GUID in its own file
  (`BlackthornesTSCharDB.guid`) for that case.
- **Old records stay readable and count as the same character; nothing is
  deleted.** Tradeskills folds an old "Name-Realm" record into the GUID one
  at login, once (`Config:AdoptLegacyCharacter`): it is kept whole in
  `formerCharacters[old key]` with `retiredInto` (never rename either), what
  the GUID record lacks is filled from it when it carries that GUID, and
  the queue's references to the old key follow. Farmer reads a goal tagged
  "Name-Realm" as the character's and tags it with the GUID once the
  character gathers toward it or changes it.
- **One test per addon answers "the same character?" and "the one
  playing?"; never compare keys or names by hand.** Tradeskills:
  `Characters:Same`, `:IsPlaying` and `:Canonical` (`Core/Characters.lua`),
  and `playing` on each `Butler:Holdings()` entry. Butler:
  `Errands:IsMe(name)` (full name, first name alone, any old record's name,
  any case, with or without a realm). Farmer: `Goals:IsOwner`. Equipment:
  `Alts.PlayerGUID()`.
- **Every errand that targets a character asks that test right before it
  acts and refuses the character playing:** a mail, a gold top-up, a Log
  out, an alt's upgrade, a learned habit, the disenchanter.
- Tested in Tradeskills' `tools/test_onecharacter.lua`, Butler's
  `tools/test_notme.lua`, Farmer's `tools/test_goals.lua` and Equipment's
  `tools/test_alts.lua`. This rule is in every addon's notes; keep them the
  same.

## Writing for players

Every word a player reads (labels, buttons, tooltips, Settings rows and
their descriptions, empty lists, chat lines, slash command help) reads the
way a friend who plays would say it: plain, warm and human. Write it at a sixth grade reading level. Short
sentences in everyday words, contractions welcome. Say what the player
sees or does, not how the addon works inside. No hype or sales words
("seamlessly", "effortlessly", "now you can", "powerful"), no filler, no
em-dashes, and no questions to the reader. The German in
`Locale/deDE.lua` changes with the English, in the same informal "du"
voice. Farmer's play cheers keep their "!" (drop-quality cheers, goal
marks, streaks, "Up to #N!", "Goal done: X!"), and `About.NOTE` is the
owner's own wording. This rule is in every addon's notes; keep them the
same.

## The owner's standing rules (all the addons)

- **Every list is dark glass** (the owner, 2026-10-12: "keep this as the
  standard across all Blackthornes addons", after Farmer's Kills & Loot
  panel was given the look of Tradeskills' queue). Rows or lines take
  `glass` and `glassAlt` in turn, by place, with a 1 px `border` line
  (alpha 0.6) under each; under the mouse `glassHover` and a gold edge,
  only on that row; the row picked or open is `glassActive` with a bright
  gold edge down its left. Never the older `row`/`rowAlt` bands for a
  list, a panel's lines or cards. A gradient fades through
  `Theme.LightGradient` or is hidden, never with SetAlpha alone (it stayed
  lit on Forever). This rule is in every addon's notes; keep them the same.
- **"Always check that it's clear to post."** Anything that goes public (a
  release, a CurseForge page, a post) is checked for private or unexpected
  content first, and nothing is published or uploaded without the owner's
  go-ahead. He tags releases himself.
- **Keep his data safe.** Never commit saved variables, tokens or anything
  from his machine; the upload keys are repository secrets he sets himself,
  so never ask him to paste one anywhere.
- **Changelogs come from git history.** Work out what changed since the last
  tag from the merged PRs and commits (`git log vX.Y.Z..origin/main --merges`);
  never ask the owner what went in. Claude drafts the CHANGELOG section in a PR;
  The owner merges, pulls `main`, tags and pushes.
- **A checkout shows the real version number** (the owner,
  2026-10-12). `ns.RELEASED_VERSION` in `Core/Init.lua` is the newest
  `## X.Y.Z` in CHANGELOG.md, shown when the packager has not filled in the
  TOC's `@project-version@` (he plays from a clone). The release PR that
  writes the CHANGELOG section changes it too; `tools/check_release.py`
  refuses a tag it does not match, and `tools/test_check_release.py` fails
  while the two disagree. This rule is in every addon's notes.
- **Every reply that ships code ends with the GitHub Desktop steps,** naming
  the branch: merge the PR on github.com (Ready for review, then Merge pull
  request); in GitHub Desktop switch **Current branch** to **main** and click
  **Pull origin**; then say whether the game needs `/reload` or a full restart
  (a full restart when a file is added, removed or renamed, or the TOC
  changes). For a release, add: History, right-click the newest commit,
  Create Tag, `vX.Y.Z`, Push origin. Remind him to pull `main` first, or the
  tag lands on an old commit and nothing runs.
- **CurseForge descriptions are features only.** Leave out privacy notes and
  any explanation of public emotes or their switches. Those belong in the
  README and CHANGELOG.
- **Keep his data safe, in the repo too.** `tools/check_private_files.py`
  (run by `.github/workflows/tests.yml`, tested by
  `tools/test_check_private_files.py`) fails any push or pull request that
  adds saved variables, a WTF folder, `keys.txt` or a `.env` file. It is
  the same in every repo (the owner asked 2026-10-10); a fix to it belongs
  in all of them.
- **Never shorten a character's last name** (the owner, 2026-10-11:
  "they must be included in WoW Forever"). Forever names are first and
  last together, so every place a character is named (menus, buttons,
  chat lines, lists, the mail's To line) shows the whole name, made to fit
  by growing or wrapping, never "Bob B." or the first name alone.
  Tradeskills' `Recipes:GetShortCharacterName` returns the full name now.
- **Forever is not retail for classes either.** The owner: "keep in mind this is
  WoW: Forever." Hunters have classic-style talent trees, held on Forever in
  one trait tree per class (see Equipment's findings). Never assume a retail
  or classic pet API exists (happiness, loyalty, the stable, demon summons):
  check with `/bpet probe` and record what it finds in
  `docs/FOREVER_API_FINDINGS.md`.
- **Smooth play comes first, but never at the cost of looks** (the owner,
  2026-10-09, after a hitch while crafting). Nothing on a timer or
  OnUpdate rebuilds or re-places a whole list, map or set of markers when
  only one thing moved: keep what is drawn, and redo only rows or pins
  whose inputs changed (a per-row key, a version number). Bag, loot,
  cast, skill and profession-list events arrive in bursts, several per
  craft or loot: coalesce them, read only what they changed, and skip
  work for windows that are hidden. Work over hundreds of items (recipes,
  sources, saved spots) is spread over frames (a worker with a small
  per-frame budget) rather than done in one frame, and shown when done.
  Clicks and typing still answer at once. The two causes found: Farmer's
  minimap markers gathered, sorted and re-placed every saved spot once a
  second because the clock second was in their redraw key (now only the
  fade moves, `MapMarkers:FadeMinimap`); and on every craft Tradeskills
  re-read every recipe in the profession window and repriced the whole
  craft pane in one frame (now `Recipes:NothingNewMidCraft` skips the
  re-read mid-run and `CraftPanel:RefreshInSlices` spreads the pane over
  frames). Visuals and usability are never traded away for speed. This
  rule is in all four addons' notes; keep them the same.
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`,
  modern Lua), not 1.12. Instances hand addons secret values that raise when
  compared, concatenated or formatted, so read client values inside a pcall.
  Registering an event the client does not know raises too, which is why
  `ns.RegisterEvent` wraps it.
