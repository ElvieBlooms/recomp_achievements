# Changelog

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
