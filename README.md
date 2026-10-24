# Blackthornes Butler

A WoW: Forever addon that tells you what to do with every item in your bags:
keep it, sell it, post it on the auction house, disenchant it, or mail it to
the alt who needs it.

Built for the WoW: Forever client (`## Interface: 16001`), without Ace3 or
LibStub, matching
[Blackthornes Farmer](https://github.com/Blackthornes/Blackthornes_Farmer),
[Blackthornes Tradeskills](https://github.com/Blackthornes/Blackthornes_Tradeskills),
[Blackthornes Equipment](https://github.com/Blackthornes/Blackthornes_Equipment)
and [Blackthornes Pets](https://github.com/Blackthornes/Blackthornes_Pets).
They share a palette and a framework on purpose, and Butler asks each of
them about your items when they are installed. Without them it still works,
from vendor prices and the game's own quest marks.

- **The Butler window** lists every item in your bags in groups, each
  with its count and what it is worth:
  - **Sell**: grey items, your Always sell list, items a vendor pays
    more for than the auction house, and, if you set an amount, anything
    worth less than it.
  - **Auction**: items worth more on the auction house, after the cut
    (marked down when they sell slowly).
  - **Disenchant**: items worth more as enchanting materials, when you can
    disenchant them.
  - **Mail**: items an alt needs for their crafts (only what your own
    crafts can spare), gear that's an upgrade for another of your
    characters, or that your enchanter alt should disenchant. Right-click
    an upgrade to stop mailing that item, or any upgrade, to that character.
  - **Look at it**: everything Butler can't judge yet, with what a vendor
    pays. Soulbound green or better gear never goes under Sell.
  - **Keep**: quest items, upgrades and tools, what your Farmer goals and
    craft queue need, your pet's food, anything a vendor won't buy, and your
    Always keep list.

  Click a group's heading to fold it; Keep starts folded. Without the other
  addons, Butler sorts by vendor price and the game's quest marks alone.
- **Right-click** an item to always keep it, always sell it, always bank it,
  always mail it to one of your characters, or let Butler decide again. The
  lists are account wide.
- **It learns from you.** Buy back something Butler sold and it keeps it
  from then on. Sell an item yourself at a vendor on two visits and it goes
  under Sell. Mail an item to the same one of your characters twice and it
  goes under Mail to them. Your own right-click choices always win, and
  right-click can forget what it learned. "Learn from what you do" in
  Settings turns it off.
- **Sell below** (Settings, or `/bbutler sellbelow 50s`): set an amount
  and anything worth less than it, at the most it could fetch from a
  vendor, the auction house or a disenchant, goes under Sell. Quest items,
  upgrades, goal and craft materials, pet food, soulbound green or better
  gear and your Always keep, bank and mail items are never included, and
  nothing sells until you click Sell. It needs Blackthornes Tradeskills for
  auction prices; off until you set it.
- **Gold fund** (Settings, Gold, or `/bbutler goldmin 50g`): set how much
  gold every character keeps, and a different amount for any one of them
  if you like. At a mailbox, a character with more is offered a gold mail
  to each of your characters below theirs (the Gold rows), never going
  below its own amount; Fill mail puts the gold in and you press Send.
  Balances are as last seen when each character played, and the row says
  how old. `/bbutler gold` lists everyone's. Needs Blackthornes
  Tradeskills; off until you set it.
- **Ammo** (hunters): at a vendor that sells ammo for your bow, crossbow
  or gun, Butler offers to fill your quiver or ammo pouch with the best
  ammo there you can use, as many as fit, and the Fill button buys it. It
  says so when your bag doesn't match your weapon. Your own ammo is never put under Sell.
- **At a mailbox,** the window comes up in place of Tradeskills' mail panel
  (close it to get that back), with a **Fill mail** button when something
  is under Mail. Each click fills the game's Send Mail page for one
  character; you check it and press Send. Once that mail goes, Butler fills
  the next one straight away, so a run of mail is one Send a character
  ("Fill the next mail" in Settings, or `/bbutler fillnext`). Needs
  Blackthornes Tradeskills.
- **At the bank,** **Move to bank** puts away everything on your Always bank
  list, and **Take from bank** brings out what your craft queue needs (with
  Tradeskills). Both move whole stacks.
- **All characters** lists every item on all your characters in one place,
  with a search box. Each line says who has it and how many in all; click
  it to see each character's bags, bank and mail, and how long ago that was
  seen. Your other characters come from Blackthornes Tradeskills, which
  remembers them as you play each one; without it you see your own bags.
- **Butler's voice:** open the window and Karazhan's butler says "You
  rang?"; close it and he picks up where he was. Never over a vendor or
  other NPC, at most once every few minutes, and off with a tick box in
  Settings.
- **Sell at a vendor.** The window comes up by itself at every vendor, with
  a Sell button at its foot when there is something to sell. Nothing sells until
  you click it, and it only ever sells what is under Sell. Each click sells
  one stack; if `/bbutler selltest` finds the game lets Butler sell from its
  own code, each click sells up to 12, which is what the vendor's Buyback
  tab holds, so every sale can be bought back.

## Install

### Linked to your working copy (recommended while developing)

Run this once, and from then on testing a branch is pulling it and typing
`/reload`:

```powershell
.\tools\link.ps1
```

It junctions `Interface\AddOns\Blackthornes_Butler` to this folder, so the
client reads your checkout directly. Nothing is copied, so there is no deploy
step to forget.

Two things `/reload` will **not** pick up, because the client only reads them at
startup:

- a file that was **added, removed or renamed**
- any change to **`Blackthornes_Butler.toc`**

After pulling a branch that did either, restart the client once.

### Copied into the client

```powershell
.\deploy.ps1              # syntax check, lint, then mirror into Interface\AddOns
.\deploy.ps1 -SkipCheck   # skip the checks (not recommended)
```

Both scripts default to `D:\Blizzard\World of Warcraft\_classic_beta_`. Pass
`-GamePath` if the client lives somewhere else.

The addon folder name has to stay `Blackthornes_Butler`, matching the `.toc`
inside it. If they differ, the client ignores the folder and says nothing.

## Use

```
/bbutler           open the Butler window (so does clicking the minimap button)
/bbutler all       every character's items in one list, with where each one is
/bbutler help      list every command
/bbutler probe     check what this client supports for bags, vendors and mail; it only reads
/bbutler settings  open the settings window (so does right-clicking the minimap button)
/bbutler vendor    turn the window coming up at a vendor on or off
/bbutler mailbox   turn the window coming up at a mailbox on or off
/bbutler bank      turn the window coming up at the bank on or off
/bbutler selltest  at a vendor, sell your cheapest grey to test whether Butler may sell 12 a click
/bbutler lists     show your Always keep, sell, bank and mail lists
/bbutler tooltip   show or hide Butler's verdict as the last line on the tooltips of items in your bags
/bbutler training  list the class spells you can train and what they cost (training on|off)
/bbutler goals     list your gold goals: class spells, profession training and riding (goals on|off)
/bbutler upgrademail   list upgrades you hold back from your characters (upgrademail undo Full Name to mail them again)
/bbutler reset confirm   empty all three lists (typed only)
```

The settings window is also under the game's Options > AddOns. Hover a
setting to see what it does, or tick **Show descriptions** to see it under
every row; **Find a setting** searches every page. **Text size** makes all
of the addon's text a point or two bigger after a `/reload`, and **Window
style** picks the house look or the game's own. Every command above has a
button there too, apart from `reset confirm`, which deletes your lists and
so stays typed.

`/butler` works too.

## Layout

| Folder | What is in it |
|---|---|
| `Core/` | Namespace, module registry, event dispatch, slash commands, saved variables |
| `Logic/` | Item prices, reading the bags, the verdicts and selling at a vendor |
| `UI/` | Theme, widgets, the house window frame, the minimap button, the Butler window and the settings window |
| `Media/` | The window frame's art (`Frame/*.tga`), drawn by `tools/make_frame_art.py` |
| `Probe/` | `/bbutler probe`, which checks what the running game actually supports instead of guessing |
| `tools/` | Checks, tests, the frame art script and the link script. Not shipped to the client |
| `docs/` | What the Forever client actually does, found with `/bbutler probe`. Not shipped |

`Blackthornes_Butler.toc` lists every Lua file in load order. A file that is
not in it does not load, and WoW says nothing about it.

## Development

```bash
python tools/syntaxcheck.py   # parse every Lua file with a real 5.1 parser
python tools/lintcalls.py     # find calls to methods, and constants, never defined
python tools/runtests.py      # run the logic tests outside WoW
```

`tools/` requires `lupa` (`python -m pip install --user lupa`).

The checks exist because WoW silently disables an addon whose first TOC file
fails to compile, and because a call to a method that no longer exists is valid
Lua that fails only when that line runs. `deploy.ps1` runs the first two before
it copies anything, and `.github/workflows/tests.yml` runs all of them on every
push, along with `tools/check_private_files.py`, which fails any push that adds
saved variables, a WTF folder, `keys.txt` or a `.env` file.

The tests load the addon against a stub client (`tools/testenv.lua`), reading
the file list straight from the TOC. A new test is a new `tools/test_*.lua`
file and nothing else.

## Releasing

Releases are cut by pushing a tag like `v0.1.0`.
`.github/workflows/release.yml` then:

1. refuses the tag unless `CHANGELOG.md` opens with a `## 0.1.0` section
   (`tools/check_release.py`);
2. runs the tests;
3. builds the player-facing zip with the
   [BigWigs packager](https://github.com/BigWigsMods/packager), uploading
   nothing;
4. checks that zip is clear to post (`tools/check_package.py`): only the
   addon's own files, and nothing that looks private, such as a Windows path,
   an email address, a saved-variables dump or a token;
5. only then uploads that same zip to each site with a token, and attaches it
   to a GitHub release.

To release from GitHub Desktop: add the new version's section to the top of
`CHANGELOG.md` and merge it to `main`, pull `main`, then **History**, right-click
the newest commit, **Create Tag...**, name it `v0.1.0`, and **Push origin**.

The version is never typed by hand. The TOC says
`## Version: @project-version@` and the packager fills in the tag. Running
straight from a clone there is no packager, so the addon shows
`ns.RELEASED_VERSION` from `Core/Init.lua`, the newest version in
CHANGELOG.md: the release PR changes both, and `tools/check_release.py`
refuses a tag they disagree with. The middle number moves for new
behaviour, the last for fixes alone; a tag like `v0.2.0-beta1` is uploaded as a beta.

`.pkgmeta` leaves `tools/`, `docs/`, `deploy.ps1`, `CLAUDE.md`, `NEWS.md` and this
README out of the zip. The CurseForge project is 1763328 (Classic Era), on the TOC's
`X-Curse-Project-ID` line.
Uploading also needs a `CF_API_KEY` repository secret in the repository's
settings on github.com. Without both, the workflow
still builds and checks the zip but uploads nothing to CurseForge.
