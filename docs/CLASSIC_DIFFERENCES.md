# Classic differences

Every place this Classic Era copy differs from Forever Butler, and why. Keep
it short and current: a PR that adds a Classic-only change adds its line
here in the same breath.

## The catch-up rule

Every Forever catch-up checks this note first, before sorting commits into
"fits Era", "Forever only, skip" or "needs changes for Era".

- A Forever commit that touches nothing listed here comes over as it is.
- A Forever commit that touches only a file Classic leaves out of the TOC
  (below) is "Forever only, skip", unless it also changes how the readers
  that ask for it behave.
- A Forever commit that lands on something listed here is a clash. Show the
  owner both versions side by side and offer three choices:
  - **Keep Classic's:** skip the Forever change.
  - **Take Forever's:** only when it really replaces what Classic did.
  - **Blend them (the usual pick):** bring Forever's idea over on top of
    Classic's version.
- Whatever is picked, nothing below gets lost by accident. If a pick changes
  a line here, the same PR changes the note.

## What differs

### The TOC
- `## Interface: 11509`, what the owner's Era client reports. Forever is 16001.
- `## X-Curse-Project-ID: 1763328`, Butler Classic's own project. Forever's
  1739020 must never be here: `tools/check_release.py` refuses a tag that has
  it (tested in `tools/test_check_release.py`; `tools/test_era.lua` checks
  the Classic ID is there).
- The folder and TOC (`Blackthornes_Butler`), saved data
  (`BlackthornesButlerDB`, `BlackthornesButlerCharDB`) and slash commands
  are the same as Forever's, on purpose. Never rename them.

### Forever data left out of the TOC
- `Data/ForeverItems.lua` (Forever's sell prices and bag kinds) is not
  loaded. Every reader asks for it first, so the live game answers alone.
  The file stays in the repo so Forever changes merge cleanly.
  `tools/test_foreveritems.lua` loads it by hand so its readers stay tested.
- `tools/test_era.lua` checks the TOC and that Butler loads, logs in and
  judges the bags with no sister loaded.

### Class training drops Forever's spells (`Logic/ClassTraining.lua`)
- `Data/ClassSpells.lua` is still built from Forever's tables, so
  `ClassTraining.Spells(class)` (new here) leaves out Forever's own spells
  (IDs from `CT.FOREVER_FIRST`, 1,000,000) and any the client says it does
  not have, pointing a rank's "rank before" past the dropped ones. `Work`,
  `ServiceSpell`, `ReadTrainer` and `ProbeText` read it instead of
  `ns.CLASS_SPELLS` straight.
- Forever's notes say this file is the same in Butler and Equipment. Here it
  is not: a Forever change to it is a clash to blend, keeping `CT.Spells`.
- A list made from Era's own tables would be better once they are pulled.

### The old auction house
- Era has no `C_AuctionHouse`, so Buy quest items (`Logic/QuestBuy.lua`)
  never shows. Search for quest items still asks Tradeskills when it is
  loaded. No code was changed for this; it falls out of the missing calls.

### Works alone
- Butler works without Tradeskills and the other sisters: their rows and
  lines just don't show. Nothing was changed for this either, but a Forever
  change that makes a sister required is a clash.

### Notes and docs
- `CLAUDE.md` opens with "This repo is the Classic Era copy".
- `README.md` names the Classic CurseForge project.

### Discord release posts
- `tools/announce_discord.py` and `tools/post_general.py` start both
  posts with "Classic Era: " (their `GAME`), where Forever's start with
  "Forever: ", so the two games' releases read apart. A catch-up that
  touches these tools keeps Classic's word. Tested in
  `tools/test_announce_discord.py` and `tools/test_post_general.py`.

### No Forever words for players
- The About thank-you (`About.THANKS`) has no "WoW Forever is almost here"
  paragraph (the owner, 2026-10-24). `UI/About.lua` is shared with Forever;
  a catch-up that brings the paragraph back keeps Classic's.

- One-word names (the owner, 2026-10-25): Era characters have one name.
  `BankAlt:TypeName` takes any typed name, and the bank alt hint and the
  `bankalt` and `upgrademail` help say "Name", not "Full Name".

### Era bug pass (2026-10-27)
- Riding: `GG.RidingSkill` reads the race's riding skill (75, then 150) from
  the skill list, since Era has none of Forever's later riding spells;
  `GG:NextRiding` is done at 150.
- Enchanting opens Era's craft window: `Jobs` also redraws on `CRAFT_SHOW`
  and `CRAFT_CLOSE`.
- `Bags.ReagentBag` drops a reagent bag number that is also
  `Enum.BagIndex.BankBag_1`, so bank bag 1 is never read as carried.
- `Learning` also hooks the older global `UseContainerItem` when it is a
  different function from `C_Container.UseContainerItem`.
- Swap When Full (2026-10-28, Classic only): `UI/SwapWhenFull.lua`, a popup by the loot window that destroys the cheapest item and loots one worth more while the bags are full, in one click. Off unless ticked (`swapWhenFull`).

## Not yet done
- Not yet seen in an Era client. Client calls are read in a pcall, and the
  code already falls back to the classic calls where Era lacks the newer ones.

## The house look (2026-10-29)

- Brought over from Forever's "One look across the five addons". The game
  calls it uses (`CreateFrame`, `C_Timer.After`, `GetTime`, the usual frame
  methods) are all in Era, so nothing needed a fallback.
- No Arrow Size here: the shared choice is heard and left alone.
- The Bags window's chips shrink the room round their words when the row
  would run under Group By (Classic's own fit, kept from before).

