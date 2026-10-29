# Forever sync

Where this Classic Era copy stands against Forever Butler
(`Blackthornes/Blackthornes_Butler`). Forever is only ever read from here.

Last Forever commit copied over: `3cd8d77` (Forever main, the merge of its
PR #183, 2026-10-23). This copy was made from it with its history on
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

Every catch-up reads `docs/CLASSIC_DIFFERENCES.md` first, and the PR that
brings Forever commits over updates the line above to the newest one it took.
