# Running the leaderboard

The leaderboard is a static GitHub Pages site plus one GitHub Action. There
is no server, database or account system, and the mod never goes online.

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

1. Create the repository. The in-game card and the page assume
   **`ElvieBlooms/recomp-achievements`**. Use a hyphen, not an
   underscore: the Gen 1 font has no `_`, so the in-game URL would show a
   space. If you pick another name, change `Browser.BOARD_URL` in
   `recomp_achievements/ui/browser.lua` and `DEFAULT_REPO` in
   `docs/index.html`.
2. Upload everything in this folder (including `.github/`) to `main`.
3. **Settings > Pages**: Source "Deploy from a branch", branch `main`,
   folder `/docs`. The site appears at
   `https://<owner>.github.io/<repo>/` a minute later.
4. **Settings > Actions > General > Workflow permissions**: choose "Read
   and write permissions". The Action commits `docs/leaderboard.json` and
   comments on issues.
5. **Issues > Labels**: create a label named `score`. The form applies it.
   Submissions also work without the label because the Action also matches
   titles starting with `[Score]`, but the label makes them easy to filter.

## What the Action checks

- The game is Red, Blue or Yellow.
- The trainer name is 1–12 characters with nothing the page can't show.
- Points and achievements are whole numbers no higher than the game's
  official totals (Red 745/93, Blue 678/90, Yellow 458/76). If the RA lists
  change, update `GAMES` in `tools/leaderboard_ingest.py`; `tests/run.lua`
  fails until the two agree.
- The check code matches the other fields. It is a checksum, not a
  signature, so it only catches typos.
- One row per save ID per game. Only the GitHub account that first
  submitted a save ID can update it.

The bot replies on the issue either way. Accepted entries are closed. A
rejected one stays open so the player can edit it, and editing re-runs the
check. If the script itself fails, the run is marked failed and you get
GitHub's usual failure email.

## Moderation

It's an honor system. To remove or fix an entry, edit
`docs/leaderboard.json` on GitHub and commit; the page picks it up on the
next load. To stop submissions, disable the workflow under **Actions**.

Nothing on the board comes from or goes to RetroAchievements.
