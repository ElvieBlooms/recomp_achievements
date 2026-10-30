# Changelog

## 2.4.0

- **Ruby and Sapphire.** All 49 entries of each version's RetroAchievements
  list are tracked, so every Gen 3 game is covered (1003 entries across
  the eleven games). Loading a save you've been playing credits what it
  can prove: badges, rival and Wally battles, the Magma/Aqua story,
  legendaries, Trick House, gift Pokémon, Battle Tower records, contest
  ribbons, secret base decorations, berries and more.
- "Caught without a Master Ball" achievements read the ball the Pokémon
  is in, so a legendary caught earlier still counts if it isn't in one.
- The leaderboard and the Discord bot accept Ruby and Sapphire scores.
  Bot owners: deploy the worker and run the register script again.

## 2.3.0

- **Emerald.** All 197 entries of the RetroAchievements list are tracked.
  Loading a save you've been playing credits what it can prove: badges,
  story, gifts, trades, Frontier symbols, Trainer Hill times, Master Rank
  contest ribbons, decorations, gym leader rematches and cleared areas.
- Emerald's "every trainer in the gym" achievements count wins before the
  Gym Leader, as in LeafGreen. The 30 area achievements ("find every item"
  and "defeat every trainer") are read from the game's map data and list
  the places they cover.
- A few Emerald moments leave nothing in the save, so they're counted
  while you play: Battle Tent prizes, the Blend Master, the clearance sale,
  a big Game Corner win, a 5x5 Cut, and stealing from rematch trainers.
  Each says how it's checked on its details page.
- Battle Frontier, Trainer Hill and secret-base battles are told apart
  from story battles, so a Frontier opponent can't count as a map trainer.
- The leaderboard and the Discord bot accept Emerald scores. Bot owners:
  deploy the worker and run the register script again.
- Ruby and Sapphire aren't covered yet; the mod doesn't load for them.

## 2.2.1

- Progress popups no longer come one after another for a single catch.
  Goals that count the same thing (the Pokédex 10, 50, 100 and the RA
  list's full Pokédex) show one card, for the nearest goal. Different
  things moving at once stack, up to three cards down the left side,
  instead of waiting in line.

## 2.2.0

- **Progress popups.** When an achievement with a goal moves along (your
  third Pokémon toward 50 in the Pokédex, a badge toward eight), a small
  see-through card shows it in the top-left corner for a couple of seconds:
  the name, "3 / 50" and a bar. It waits for any unlock popup to finish
  first, and a quick run of steps updates one card instead of stacking
  them. Big counters and "every trainer and item" areas only show each
  tenth of the way, hidden achievements stay hidden, and loading a save
  doesn't replay progress it already had. Turn it off with **PROGRESS
  POPUPS** in the mod's options.

## 2.1.1

- The START menu row is now **TROPHIES** (it was ACHIEVEMENTS in Gen 1
  and AWARDS in Gen 2). Gold, Silver and Crystal say **TROPHY**: their menu
  has room for 7 letters. In Gen 2 its MENU ACCOUNT
  help text is now short enough for the box ("Your trophies"); it used to
  run past the box and leave stray letters.
- Fixed: starting a New Game in Gold unlocked "Strong Very Much Be You!"
  (the Machine Part), and in Crystal the two Suicune sightings ("Life, the
  Universe, and Aurorae" and "Forest of Fate"). The game sets those flags in
  its opening script. Saves that got them that way have them taken back on
  load (moved to the save's quarantine list, not deleted), so they can be
  earned for real.

## 2.1.0

- **FireRed and LeafGreen.** All 189 entries of the RetroAchievements
  lists for the two games are tracked (61 + 128). Loading a save you've
  been playing credits everything it can prove (badges, story, gifts,
  trades, Trainer Tower records, Pokédex, cleared areas) in one WELCOME
  BACK popup, as with the other games.
- FireRed's eight "Set Mode" gym challenges are **Challenges** here, like
  the other games: OPTION > BATTLE STYLE set to SET, a party-size limit and
  a level cap. The two "solo" League runs count one Pokémon for every
  battle from Lorelei to the Champion.
- LeafGreen's "every trainer in the gym" achievements count wins before
  the Gym Leader, since the game marks the rest beaten once the leader
  falls. Its "every trainer and item" area achievements are read from the
  game's map data; each one lists the maps it covers.
- The leaderboard and the Discord bot accept FireRed and LeafGreen scores.
  Bot owners: deploy the worker and run the register script again.
- Ruby, Sapphire and Emerald aren't covered yet; the mod doesn't load
  for them.

## 2.0.2

- Wording only: the classic menu's "OFFICIAL" filter is now **RA LIST**,
  entries from the RetroAchievements lists say "FROM THE RA LIST" instead
  of "OFFICIAL RA SET", and the score card says "RA-list points only".
  Nothing here is official or endorsed by RetroAchievements, and the
  labels shouldn't suggest it. No changes to unlocks or saved progress.

## 2.0.1

- What RetroAchievements calls "Set Mode" is now labelled **Challenge** in
  the mod's own titles and notes, with what it means spelled out: set
  OPTION > BATTLE STYLE to SET (plus the level cap and any other limits).
  These achievements show a short reminder on their details page and the
  full rules on the "How it's checked" page. They are in a new CHALLENGE
  category. The checks themselves are unchanged.

## 2.0.0

- **Gold, Silver and Crystal.** All 260 entries of the RetroAchievements
  lists for the three games are tracked (72 + 75 + 113), plus 16 Gen 2
  bonus achievements. Existing saves are credited when they load, as in
  Gen 1. See docs/COVERAGE.md for how each one is checked.
- The menu, popups, unlock sound, themes and leaderboard card work the
  same on Gen 2. The START menu entry is called AWARDS there, because
  Gen 2's menu is narrower. CLASSIC MENU and the Classic GB popups stay
  Gen 1 only.
- The leaderboard, its issue form and the Discord bot accept Gold, Silver
  and Crystal scores.
- Gen 2 reports each battle twice; the mod counts it once.

## 1.7.0

- The achievements menu now fills the whole window, landscape or portrait,
  and resizes with it. On a phone held upright the list and details stack
  vertically and stop above the on-screen pad. It also respects notches
  and rounded corners the system reports.
- MENU SIZE option: Full Screen (default) or Game Area, the 1.6.0 size.

## 1.6.0

- Unlock popups now come in three styles (POPUP STYLE option): Modern, a
  banner in your chosen theme (the new default); Corner, a small card in
  the top-right corner that stays out of the way; and Classic GB, the
  Game Boy text box from earlier versions.
- The Game Boy palette is now the default theme. MENU THEME is now just
  THEME, since it colours the popups too.

## 1.5.0

- New bonus achievement, **Show and Tell** (1 point): open your leaderboard
  card. Sharing it is optional. Like the other bonus achievements it
  isn't from the RetroAchievements list, so it doesn't change leaderboard
  points, and the BONUS ACHIEVEMENTS option turns it off.
- MENU THEME option with five palettes: Gruvbox Dark (the new default),
  Gruvbox Light, Nord, Midnight (the 1.4.0 look) and Game Boy. Each game
  still gets its own accent colour, picked from the palette.

## 1.4.0

- New achievements menu: a list with the selected achievement's details
  beside it, filter chips, progress bars and rings, and a leaderboard card
  and About page on SELECT. It's drawn at your window's resolution and
  sized for any screen shape, ready for the Gen 2 and Gen 3 games later;
  each game gets its own accent colour.
- The old Game Boy text-box menu is still there: turn on CLASSIC MENU.
- Hold UP or DOWN to scroll the list.
- Unlock popups now always draw on top of the menu.

## 1.3.0

- Unlock sound: a short Game Boy-style jingle plays as each popup appears
  (a lower one for WELCOME BACK). It follows the game's SFX VOL, plays
  even with popups switched off, and can be turned off with the new
  UNLOCK SOUND option. The jingle is generated by the mod; no sound files
  are copied from the games.

## 1.2.0

- The leaderboard card has a TIME line: your in-game play time when you
  reached your current score (your latest official unlock), not the time
  now, so playing on after maxing out doesn't cost you. On equal points
  the leaderboard ranks the shorter time higher.
- Each unlock now records the play time it happened at. Achievements
  earned with 1.1.0 have no time, so the card uses your current play time
  for them.
- Check codes are now "v2" and include the time. 1.1.0 cards (no TIME line)
  are still accepted; they rank after timed scores with the same points.
- API 1.2.0: `leaderboardCard().time` (minutes) and
  `officialTotals().reachedAt` (seconds).

## 1.1.0

- Leaderboard card: press SELECT in the achievements browser to see your
  trainer name, official points, a save ID and a check code. Enter them in
  the project's GitHub issue form to appear on the leaderboard page. The
  mod itself still never goes online.
- The leaderboard bot filters offensive trainer names, and each row on the
  page has a Report link.
- Optional Discord bot: players can submit with `/score` instead of a
  GitHub issue.
- Credits moved to the second SELECT page (press RIGHT).
- API 1.1.0 adds `officialTotals()` and `leaderboardCard()`.

## 1.0.0

First public release. Red, Blue and Yellow.

- All 259 official RetroAchievements entries for Red (93), Blue (90) and
  Yellow (76) are tracked by detectors written for Gen1Recomp. See
  `docs/COVERAGE.md` for how each one is checked.
- Official titles, descriptions, points and author credits are shown in the
  browser and popups.
- Bonus achievements made for this mod (Pokédex milestones, trainer wins and
  more). They can be switched off with the BONUS ACHIEVEMENTS option.
- Existing saves, including cartridge saves imported into Gen1Recomp, are
  credited for everything provable from the save when they load, with a
  single "WELCOME BACK" popup.
- An ACHIEVEMENTS entry in the START menu opens the browser: filters, a
  detail page, an ABOUT page per achievement, credits on SELECT, and
  scrolling for long titles.
- Progress is stored in your save, so it follows Save Sync and rolls back
  with older saves.
- Public provider API v1.0.0 lets other mods add their own achievements. See
  `docs/PROVIDER_API.md`.
