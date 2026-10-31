# Recomp Achievements

An achievements mod for **Gen1Recomp**, inspired by
[RetroAchievements](https://retroachievements.org). It uses the achievement
lists RetroAchievements publishes for **Pokémon Red, Blue, Yellow, Gold,
Silver, Crystal, Ruby, Sapphire, Emerald, FireRed and LeafGreen** (all 1003 entries: titles,
descriptions and point values) and checks them with
its own unlock logic, written from scratch for Gen1Recomp. Everything
unlocks and is saved locally, in your game.

> **This is an unofficial fan project.** It is not made, endorsed or
> supported by RetroAchievements, and it doesn't connect to them in any way.
> Unlocks here don't count on retroachievements.org, and RetroAchievements'
> own unlock code isn't used. If you want achievements that count on your
> RetroAchievements profile, use RetroAchievements with a supported
> emulator. Please report problems with this mod here, not to
> RetroAchievements.

- **Local only.** No account, no sign-in, and nothing is ever sent to
  RetroAchievements or anywhere else. Unlocks live in your save.
- **Follows your save.** Progress is stored inside the save, so it travels
  with Gen1Recomp's Save Sync and rolls back if you load an older save.
- **Credits your existing saves.** Load a save you've been playing,
  including a cartridge save imported into Gen1Recomp, and everything the
  save can prove (badges, items, Pokédex, story progress, cleared areas) is
  unlocked with one "WELCOME BACK" popup.
- **Open to other mods.** Other mods can add their own achievements, which
  appear in the same list.

Achievement titles and descriptions are by the RetroAchievements community
and each achievement's author, and are credited in the game. See
[NOTICE.md](NOTICE.md).

## Install

1. Download `recomp_achievements-2.4.0.zip` and unzip it into Gen1Recomp's
   `mods/` folder, so you have `mods/recomp_achievements/`.
2. Start Red, Blue, Yellow, Gold, Silver, Crystal, Ruby, Sapphire, Emerald,
   FireRed or LeafGreen (Gen1Recomp 0.3.97 or newer).
3. Open the START menu and choose **TROPHIES** (**TROPHY** in Gold, Silver
   and Crystal, whose menu is narrower).

To keep achievements in step across devices, install the mod on each one.
Save Sync carries your progress but doesn't install mods.

## Using it

The menu fills the whole window and follows it as you resize: your
achievements on the left and the selected one's details on the right, or
stacked top and bottom on a phone held upright (where it stops above the
on-screen pad).

| In the menu | |
|---|---|
| UP / DOWN | move (hold to scroll) |
| LEFT / RIGHT | change filter: All, Earned, Missing, In progress, RA list, Bonus, From mods, Archived |
| A | switch the details between the description and how it's checked |
| SELECT | leaderboard card (RIGHT for About) |
| B / START | back |

A gold disc with a tick means earned, a ring means locked, a partly green
ring shows progress, and a slashed ring means archived (earned with a mod
that isn't loaded right now). Prefer the original Game Boy text-box look?
Turn on **CLASSIC MENU**.

Options are in the Mods manager:
- **UNLOCK POPUPS**
- **POPUP STYLE**: Modern (a banner in your theme, the default), Corner (a
  small card in the top-right corner) or Classic GB (the Game Boy text box)
- **PROGRESS POPUPS**: a small see-through card in the top-left corner
  when an achievement with a goal moves along ("3 / 50"); goals that count
  the same thing show only the nearest one, and up to three stack
- **UNLOCK SOUND**: a short jingle on each unlock, at the game's SFX VOL
- **BONUS ACHIEVEMENTS**: this mod's extras, which aren't part of the RA lists
- **REVEAL HIDDEN**
- **THEME**: colours for the menu and popups: Game Boy (default), Gruvbox
  Dark, Gruvbox Light, Nord or Midnight
- **MENU SIZE**: Full Screen (default) or Game Area (only the game's own
  screen, which keeps it clear of a phone's on-screen pad in landscape)
- **CLASSIC MENU**: the Game Boy-style menu instead of the modern one
- **SHOW RA REFERENCE**: adds a page listing every RA entry for the game
- **DEBUG LOG**

### Good to know

- Achievements RetroAchievements marks "Set Mode" are **Challenges** here:
  they need OPTION > BATTLE STYLE set to SET (every game here has this
  option) plus the level cap or other limits listed on the achievement's
  "How it's checked" page.
- In LeafGreen and Emerald, "defeat every trainer in the gym" means before the Gym
  Leader: once the leader falls, the game marks the remaining gym trainers
  as beaten without a fight.

- Challenges such as "on Set mode", "without resetting" or "in a single
  Safari hunt" are judged while you play. A save can't prove how something
  was done in the past, so those only count from when the mod is installed.
- "Without resetting" means within one play session. Loading a save starts
  the attempt over.
- About a quarter of the entries are a **local reading** of the RetroAchievements
  description, because Gen1Recomp can't check the original wording exactly
  (for example "unmissable" items). Each one says on its in-game ABOUT page
  exactly what counts. The full list is in [docs/COVERAGE.md](docs/COVERAGE.md).

## Leaderboard

There's an optional, community-run leaderboard at
**https://elvieblooms.github.io/recomp_achievements**. The mod never goes
online; you copy a short card into a form yourself:

1. In the game, open **START > TROPHIES** and press **SELECT**.
2. On the website, press **Submit a score**. It opens a GitHub issue form
   (you need a GitHub account). If the Discord bot is set up, you can
   instead send it `/score` with the same values.
3. Copy the game, trainer name, points, achievements earned, play time,
   save ID and check code from the card. Submit.

A bot checks the entry within a minute or two, replies (on the issue, or
by editing its Discord message) and updates the page. To update your
score later, edit the same issue, or send `/score` again from the same
Discord account.

Players are ranked by points. On equal points, the shorter TIME ranks
higher: that's your play time when you reached the score (your latest
unlock from the RetroAchievements list), so playing on afterwards doesn't
count against you.

Only achievements from the RetroAchievements lists count; bonus achievements and
achievements from other mods don't. The check code only catches typos, so
the board is an honor system. Trainer names are filtered for offensive
words, and every row has a Report link. It has nothing to do with
RetroAchievements or its leaderboards, and scores here mean nothing on
retroachievements.org.

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
  adapters/gen2.lua      Gold/Silver/Crystal save + game data -> "facts"
  adapters/gen3.lua      Ruby/Sapphire/Emerald/FireRed/LeafGreen save -> "facts"
  rules/gen1_official.lua, rules/gen2_official.lua, rules/gen3_official.lua,
  rules/gen3_emerald.lua, rules/gen3_rs.lua
                         one detector per RetroAchievements-list entry
  rules/gen1_lib.lua, rules/gen2_lib.lua, rules/gen3_lib.lua
                         the building blocks those detectors use
  rules/gen1.lua, rules/gen2.lua, rules/common.lua
                         bonus achievements
  data/gen2_*.lua        Gen 2 flag numbers, trainers and items (generated)
  data/gen3_frlg.lua     FireRed/LeafGreen flags, trainers and items (generated)
  data/gen3_emerald.lua  Emerald flags, trainers, items, moves, decorations (generated)
  data/gen3_rs.lua       Ruby/Sapphire flags, trainers, items, moves, decorations (generated)
  catalog/               RA metadata (generated)
  ui/                    menu (modern + classic), popups, unlock sound, text helpers
achievement_sandbox/   example provider mod (not part of the release)
docs/                  PROVIDER_API.md, COVERAGE.md (generated), and the
                       leaderboard website (index.html, leaderboard.json)
.github/               leaderboard issue forms and the Action that reads them
discord/               optional Discord bot (Cloudflare Worker) for submissions
tools/                 fetch_ra_catalog.py, gen_coverage.lua, build_release.sh,
                       gen2_data.py (+ gen2_flags.py), gen3_data.py,
                       leaderboard_ingest.py, discord_reply.py,
                       discord_register.py, name_blocklist.txt
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

`python3 tests/test_leaderboard.py` and `node tests/test_discord_worker.mjs`
test the leaderboard bot and the Discord bot. Setting
the leaderboard up on a fork is described in
[docs/LEADERBOARD.md](docs/LEADERBOARD.md).

`tools/build_release.sh` runs the tests, regenerates `docs/COVERAGE.md`
and writes `dist/recomp_achievements-<version>.zip`.

To refresh the RA lists (developers only; needs your own RA Web API key):
`RA_API_KEY=... python3 tools/fetch_ra_catalog.py` (all games, or name some).

### Gen 2 data

`recomp_achievements/data/gen2_*.lua` lists each game's event-flag numbers
and every map trainer, item ball, hidden item and gift, read from the
[pret](https://github.com/pret) disassemblies (pokegold and pokecrystal),
which are the same numbering Gen1Recomp uses. To rebuild it:

```
git clone https://github.com/pret/pokegold && git clone https://github.com/pret/pokecrystal
python3 tools/gen2_data.py pokegold pokecrystal
```

### Gen 3 data

`recomp_achievements/data/gen3_frlg.lua` is the same kind of table for
FireRed and LeafGreen (they share one), from
[pret/pokefirered](https://github.com/pret/pokefirered): flag, var,
species and item numbers, every map trainer, item ball, hidden item and
gift, the VS Seeker rematch table and the gym trainers the game marks
beaten after each leader. Its flag numbers are checked against the
engine's own FireRed flag table by `tests/run.lua`.

`data/gen3_emerald.lua` comes from
[pret/pokeemerald](https://github.com/pret/pokeemerald) the same way, plus
move numbers and the decoration catalogue; its flags, vars, species, items
and trainers are checked against the engine's own Emerald tables.

`data/gen3_rs.lua` comes from [pret/pokeruby](https://github.com/pret/pokeruby)
(one file covers both versions) and is checked against the engine's Ruby
tables.

```
git clone https://github.com/pret/pokefirered && git clone https://github.com/pret/pokeemerald
git clone https://github.com/pret/pokeruby
python3 tools/gen3_data.py pokefirered
python3 tools/gen3_data.py pokeemerald
python3 tools/gen3_data.py pokeruby
```

## License

MIT for the code and docs. See [LICENSE](LICENSE). The RetroAchievements
metadata in `catalog/` is not covered by the MIT license; see
[NOTICE.md](NOTICE.md).
