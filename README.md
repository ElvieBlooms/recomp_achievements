# Recomp Achievements

Achievements for **Gen1Recomp**: the official RetroAchievements lists for
**Pokémon Red, Blue and Yellow**, all 259 entries, checked as you play and
saved in your game.

- **Works offline.** No account, no sign-in, and nothing is ever sent to
  RetroAchievements. Unlocks are local to your game.
- **Follows your save.** Progress is stored inside the save, so it travels
  with Gen1Recomp's Save Sync and rolls back if you load an older save.
- **Credits your existing saves.** Load a save you've been playing,
  including a cartridge save imported into Gen1Recomp, and everything the
  save can prove (badges, items, Pokédex, story progress, cleared areas) is
  unlocked with one "WELCOME BACK" popup.
- **Open to other mods.** Other mods can add their own achievements, which
  appear in the same list.

Achievement text is by RetroAchievements and its authors. This mod is not
affiliated with RetroAchievements. See [NOTICE.md](NOTICE.md).

## Install

1. Download `recomp_achievements-1.1.0.zip` and unzip it into Gen1Recomp's
   `mods/` folder, so you have `mods/recomp_achievements/`.
2. Start Red, Blue or Yellow (Gen1Recomp 0.3.97 or newer).
3. Open the START menu and choose **ACHIEVEMENTS**.

To keep achievements in step across devices, install the mod on each one.
Save Sync carries your progress but doesn't install mods.

## Using it

| In the browser | |
|---|---|
| UP / DOWN | move |
| LEFT / RIGHT | change filter: ALL, EARNED, MISSING, IN PROGRESS, OFFICIAL, BONUS, FROM MODS, ARCHIVED |
| A | details (RIGHT on the details shows how this mod checks it) |
| SELECT | leaderboard card (RIGHT for credits) |
| B / START | back |

A filled square means earned, a hollow square means locked, and a slashed
square means archived (earned with a mod that isn't loaded right now).

Options are in the Mods manager:
- **UNLOCK POPUPS**
- **BONUS ACHIEVEMENTS**: this mod's extras, which aren't part of the RA lists
- **REVEAL HIDDEN**
- **SHOW RA REFERENCE**: adds a page listing every RA entry for the game
- **DEBUG LOG**

### Good to know

- Challenges such as "on Set mode", "without resetting" or "in a single
  Safari hunt" are judged while you play. A save can't prove how something
  was done in the past, so those only count from when the mod is installed.
- "Without resetting" means within one play session. Loading a save starts
  the attempt over.
- About a fifth of the entries are a **local reading** of the official
  description, because Gen1Recomp can't check the original wording exactly
  (for example "unmissable" items). Each one says on its in-game ABOUT page
  exactly what counts. The full list is in [docs/COVERAGE.md](docs/COVERAGE.md).

## Leaderboard

There's an optional public leaderboard at
**https://elvieblooms.github.io/recomp-achievements**. The mod never goes
online; you copy a short card into a form yourself:

1. In the game, open **START > ACHIEVEMENTS** and press **SELECT**.
2. On the website, press **Submit a score**. It opens a GitHub issue form
   (you need a GitHub account).
3. Copy the game, trainer name, points, achievements earned, save ID and
   check code from the card. Submit.

A bot checks the entry within a minute or two, replies on the issue and
updates the page. To update your score later, edit the same issue with
the new card.

Only the official RetroAchievements list counts; bonus achievements and
achievements from other mods don't. The check code only catches typos, so
the board is an honor system. It has nothing to do with RetroAchievements
or its leaderboards.

## For mod authors

Other mods can register achievements, report unlocks and progress, and
listen for unlocks:

```lua
local found = mod.find("recomp_achievements")
if found then
  local ach = found.exports.connect(mod)
  ach:register({ id = "chatterbox", title = "Chatterbox", goal = 50,
                 description = "Hear 50 voice lines." })
  ach:addProgress("chatterbox", 1)
end
```

The full contract is in [docs/PROVIDER_API.md](docs/PROVIDER_API.md), and
`achievement_sandbox/` is a complete example mod.

## Repository layout

```
recomp_achievements/   the mod (this folder is what ships)
  main.lua               wiring; start reading here
  core/                  ledger (save data), registry, engine, public API
  adapters/gen1.lua      Red/Blue/Yellow save + game data -> "facts"
  rules/gen1_official.lua  one detector per official RA entry
  rules/gen1_lib.lua     the building blocks those detectors use
  rules/gen1.lua         bonus achievements
  catalog/               RA metadata (generated)
  ui/                    browser, popups, text helpers
achievement_sandbox/   example provider mod (not part of the release)
docs/                  PROVIDER_API.md, COVERAGE.md (generated), and the
                       leaderboard website (index.html, leaderboard.json)
.github/               leaderboard issue form and the Action that reads it
tools/                 fetch_ra_catalog.py, gen_coverage.lua, build_release.sh,
                       leaderboard_ingest.py
tests/                 headless tests in the real Gen1Recomp mod loader
tests/e2e/             runs the actual game under Xvfb with a test driver
```

## Development

The tests boot Gen1Recomp's real mod loader (sandbox, manifest checks,
event and hook system, save serializer) under LuaJIT, with the real
extracted Red/Blue/Yellow game data:

```
ENGINE=<unzipped gen1recomp-0.3.97.love> GAMEDATA=<Gen1Recomp data folder> \
  luajit tests/run.lua && luajit tests/official.lua
```

`tests/e2e/run_e2e.sh <game> <plan.lua>` runs the actual game (LÖVE 11.5 +
Xvfb) on a copy of your data folder with a test-only driver mod. The driver
can load saves, press buttons and take screenshots. Never ship
`tests/e2e/e2e_driver`.

`python3 tests/test_leaderboard.py` tests the leaderboard bot. Setting
the leaderboard up on a fork is described in
[docs/LEADERBOARD.md](docs/LEADERBOARD.md).

`tools/build_release.sh` runs the tests, regenerates `docs/COVERAGE.md`
and writes `dist/recomp_achievements-<version>.zip`.

To refresh the RA lists (developers only; needs your own RA Web API key):
`RA_API_KEY=... python3 tools/fetch_ra_catalog.py red blue yellow`.

## License

MIT for the code and docs. See [LICENSE](LICENSE). The RetroAchievements
metadata in `catalog/` is not covered by the MIT license; see
[NOTICE.md](NOTICE.md).
