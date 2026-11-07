# Forever sync

Where this Classic Era copy stands against Forever Butler
(`Blackthornes/Blackthornes_Butler`). Forever is only ever read from here.

Last Forever commit copied over: `112ff29` (Forever main, 2026-11-02).
The first copy was made from `3cd8d77` (Forever main, the merge of
its PR #183, 2026-10-23). This copy was made from it with its history on
2026-10-24.

Copied over since, one at a time:
- `dd85a97` Start release posts with the game name (2026-10-24, copied
  by hand with "Classic Era" in place of "Forever"; see
  `docs/CLASSIC_DIFFERENCES.md`).
- `d3fefc3` Let Butler's rows grow to fit long notes (2026-10-28, only
  its safer row measure: `UI.RowHeight` counts each label by its width
  too and leaves room for a shown button; Classic's own row growing from
  its PR #20 stays).
- `dea75f5` Let the way there card's rows grow when a step wraps
  (2026-10-28, as it is).
- `4d590bb` One minimap button for every Blackthornes addon (2026-10-28,
  Forever PR #194, cherry-picked as it is; `UI/SharedMinimap.lua` and its test
  are the same in all five Classic repos).
- `e8b1d78` Shared minimap button shows the Blackthornes thorn B (2026-10-29,
  taken as it is: `UI/SharedMinimap.lua` at FILE_VERSION 2,
  `Media/Frame/MinimapBadge.tga` and `tools/make_minimap_art.py`, the same
  in all five Classic repos).
- `7811b27` Slim the shared minimap menu: names only, sized to fit (2026-10-29,
  taken as it is: `UI/SharedMinimap.lua` at FILE_VERSION 3 and its test, the
  same in all five Classic repos).
- `c288a7d` Time arrow flights by their real length (2026-10-29, as it is).
- `dcb596e` Show the way lays our own map marker on the class trainer
  (2026-10-29, as it is; `UI/SpotMarker.lua` is the same in Farmer, Butler,
  Tradeskills and Pets Classic).
- `ccabe0b` Settings moves to the last tab, bottom right (2026-10-29,
  Forever PR #189, as it is).
- `9d29494` Right-click menu in the house look (2026-10-29, Forever PR
  #190; Classic's "Don't Suggest This Craft" line became a menu row too).
- `7564279` One look across the five addons (2026-10-29, Forever PR #200):
  `UI/HouseKit.lua`, `UI/RowMenu.lua`, `UI/Notice.lua` and
  `UI/SharedChoices.lua` as they are (the same in all five Classic repos),
  the Bags window's hanging tabs and house chips, footers, hovers, Title
  Case buttons and the General page. Left out: Arrow Size (Butler Classic
  has none). The chips give up some room round their words when a
  language runs long, so they never run under Group By.
- `407f339` One Window steps aside for an open letter (2026-10-31): docked at
  the mailbox it moves beside the letter and back, and tells side panels
  when it docks, moves or undocks (`SharedWindow.Watch`, `DockedFrame`).
  `UI/SharedWindow.lua` is FILE_VERSION 5, the same in all five Classic
  repos. Butler's buy box (`UI/BuyMany.lua`) sits past the docked window at a vendor.
- `e85da58` Set Default under Window Position keeps pages in the one
  window (2026-11-02; its test sits beside Classic's vendor test).
- `448c647` A vendor, mailbox or bank that closes before the bag read keeps
  Butler shut, by visit number (2026-11-02), on top of Classic's own
  `merchantOpen` check from PR #54; both guards stay.
- `0d0c22d`, `cbc6c57` Empty slots always show in the Bags window and EMPTY
  SLOTS counts only the bags that take anything (2026-11-02). The Empty
  Slots tick box is gone; `bagEmptySlots` stays in the save, unread. The
  search box keeps Classic's Sort button room.
- `112ff29` Bank alt "Full Stacks Only:" (2026-11-02, `bankAltFullStacks`,
  off unless ticked).

- Fixes of 2026-11-05 to 11-07 (copied 2026-11-07): `f3155dd` One Window
  keeps its size when it docks or undocks while folded
  (`UI/SharedWindow.lua` FILE_VERSION 8, the same in all five Classic
  repos); `3d46e22` Swap When Full never destroys a quest item (with
  `Swap.IsQuestLoot` from `27546f4`, but not that commit's quest loot
  swap; Classic also reads `Bags.ReadQuest` again on the click);
  `f22dec5` the Bags window sits in HIGH so the split stack box shows over
  it; `06799f2` Full Stacks Only judges full and short stacks apart.

Every catch-up reads `docs/CLASSIC_DIFFERENCES.md` first, and the PR that
brings Forever commits over updates the line above to the newest one it took.
