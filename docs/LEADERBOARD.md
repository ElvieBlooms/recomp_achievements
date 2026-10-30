# Running the leaderboard

The leaderboard is a static GitHub Pages site plus one GitHub Action. There
is no server, database or account system, and the mod never goes online.
Players submit through a GitHub issue form or, optionally, a Discord bot
(`discord/README.md`). Both go through the same Action and the same checks.

```
player's game                GitHub                          GitHub Pages
-------------                ------                          ------------
SELECT page shows   ──────▶  issue form (score.yml)
a card + check code          │
                             ▼
                    Action leaderboard.yml runs
                    tools/leaderboard_ingest.py:
                      checks the code and limits,
                      updates docs/leaderboard.json,
                      commits, replies, closes  ───────▶  docs/index.html
                                                          reads leaderboard.json
```

## One-time setup

1. The in-game card and the page point at
   **`ElvieBlooms/recomp_achievements`**. If the repo moves, change
   `Browser.BOARD_URL` in `recomp_achievements/ui/browser.lua` and
   `DEFAULT_REPO` in `docs/index.html`. (The Gen 1 font has no `_`; the
   card draws underscores as lines itself.)
2. Upload everything in this folder (including `.github/`) to `main`.
3. **Settings > Pages**: Source "Deploy from a branch", branch `main`,
   folder `/docs`. The site appears at
   `https://<owner>.github.io/<repo>/` a minute later.
4. **Settings > Actions > General > Workflow permissions**: choose "Read
   and write permissions". The Action commits `docs/leaderboard.json` and
   comments on issues.
5. **Issues > Labels**: create labels named `score` and `report`. The two
   forms apply them. Submissions still work without the `score` label,
   because the Action also matches titles starting with `[Score]`, but the
   labels make both kinds easy to filter.

Optional: set up the Discord bot with `discord/README.md`, then put its
install link in `DISCORD_INSTALL` in `docs/index.html` to show a "Submit
on Discord" button.

## What the Action checks

- The game is Red, Blue, Yellow, Gold, Silver or Crystal.
- The trainer name is 1–12 characters with nothing the page can't show,
  and doesn't match `tools/name_blocklist.txt` (see "Name filter" below).
- Points and achievements are whole numbers no higher than the game's
  RetroAchievements-list totals (Red 745/93, Blue 678/90, Yellow 458/76,
  Gold 685/72, Silver 616/75, Crystal 864/113). If the RA lists
  change, update `GAMES` in `tools/leaderboard_ingest.py`; `tests/run.lua`
  fails until the two agree.
- The play time, if given, is H:MM. Cards from mod 1.1.0 have no TIME line
  and use the older "v1" check code without it; both are accepted. Ranking
  is by points, then the shorter play time (no time sorts after any time),
  then who submitted first.
- The check code matches the other fields. It is a checksum, not a
  signature, so it only catches typos.
- One row per save ID per game. Only the account that first submitted a
  save ID (the same GitHub account, or the same Discord account) can update
  it.

The bot replies on the issue (or edits its Discord message) either way. Accepted entries are closed. A
rejected one stays open so the player can edit it, and editing re-runs the
check. If the script itself fails, the run is marked failed and you get
GitHub's usual failure email.

## Name filter

The check code covers the trainer name, so a player can't change it on the
form, but they choose it in the game. The bot rejects names that match
`tools/name_blocklist.txt` and tells the player only that the name can't be
shown. It undoes look-alike swaps (`5H1T`, `A55`), ignores symbols and
spacing (`F_U_C_K`), and squashes repeats (`FUUUCK`).

The file has two lists. Words under `[contains]` are blocked anywhere in a
name. Words under `[exact]` are blocked only as the whole name, for short
words that hide inside normal ones (`ass` in CLASS, `cock` in PEACOCK,
`hell` in HELLO). A new word only affects new submissions, so when
something gets through, add the word and also remove the entry (below).
Run `python3 tests/test_leaderboard.py` to be sure a new word doesn't
block ordinary names.

## Reports and moderation

Every row on the page has a **Report** link. It opens a short issue form
(label `report`) with the game and save ID filled in, so the reporter
doesn't have to repeat the name. The bot ignores reports; they're for you.

To remove an entry, delete its row in `docs/leaderboard.json` on GitHub
and commit; the page picks it up on the next load. To stop that save
coming back, also add `"<game>:<save ID>"` to the `banned` list at the top
of the file, for example `"banned": ["red:7RABGB"]`. The name also
appears in the submission issue; repo admins can delete that issue from
its menu. To stop all submissions, disable the workflow
under **Actions**.

Nothing on the board comes from or goes to RetroAchievements.
