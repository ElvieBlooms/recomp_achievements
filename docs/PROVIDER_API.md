# Recomp Achievements — Provider API (v1.2.0)

How another Gen1Recomp mod adds its own achievements, reports progress,
and listens for unlocks. `achievement_sandbox/main.lua` is a complete,
working example of everything on this page.

Everything here is local to the player's machine. The framework does not
use the network, does not need any account, and never reports anything to
RetroAchievements or anyone else.

## 1. Declare the dependency

```json
"optional_dependencies": ["recomp_achievements@>=0.1.0"]
```

When the framework is installed, this makes the loader run it first. When
it isn't installed, your mod still loads. Use `"dependencies"` instead
only if your mod is pointless without achievements.

## 2. Find the API and check the version

```lua
return function(mod)
  local found = mod.find("recomp_achievements")
  if not found then return end                  -- not installed: do nothing
  local ach = found.exports
  local major = tonumber(tostring(ach.apiVersion):match("^(%d+)"))
  if major ~= 1 then return end                 -- written for 1.x
```

`ach.supports(name)` answers for these capabilities: `register`,
`register_many`, `unlock`, `progress`, `query`, `events`, `games_filter`,
`hidden`, and since 1.1.0 `official_totals` and `leaderboard_card`.

## 3. Connect and register

```lua
  local handle = ach.connect(mod)   -- or ach.connect("your_mod_id", { name = "..." })
  handle:register({
    id = "chatterbox",              -- a-z 0-9 _ -, max 48; never change it
    title = "Chatterbox",           -- max 32 chars
    description = "Hear 50 voice lines.",   -- max 160 chars
    points = 10,                    -- 0..100, default 5
    goal = 50, unit = "LINES",      -- optional: makes it a progress achievement
    hidden = false,                 -- true = "???" until earned
    category = "AUDIO",             -- optional, max 16 chars
    games = { "red", "blue" },      -- optional; omit for every game
    revision = 1,                   -- optional
  })
```

Register on every boot. Definitions aren't saved; only the player's
records are. Your achievements are saved under the key
`mod:<your_mod_id>:<id>`. The handle only ever writes inside that
namespace.

`handle:registerMany(list)` registers a batch on a best-effort basis. It
returns `okCount, errors`, where `errors[i] = { code, message }` for each
entry that failed.

## 4. Report

| Call | Effect |
|---|---|
| `handle:unlock(id)` | Awards it once. A second call returns `already_unlocked`. |
| `handle:setProgress(id, n)` | Sets absolute progress, clamped to `0..goal`. Reaching the goal awards it. |
| `handle:addProgress(id, n)` | Adds to progress (default 1). |
| `handle:isUnlocked(id)` | Returns a boolean. |
| `handle:getProgress(id)` | Returns `value, goal`. |
| `handle:get(id)` / `handle:list()` | Returns copies of your rows. |

Every call returns `true`, or `nil, code, message`. Calls never throw for
ordinary problems.

| Code | Meaning |
|---|---|
| `no_save` | No save is loaded yet (title screen, or mid-load). Try again after the `ready` event. |
| `unknown_id` | Nothing is registered under that id. |
| `invalid_id` | The id doesn't follow the id rules. |
| `wrong_game` | The definition's `games` list excludes the running game. |
| `already_unlocked` | It was already earned. |
| `no_goal` | Progress was reported for an achievement without a `goal`. |
| `invalid_value` | The value is not a number, or is a negative increment. |
| `duplicate_id` | Re-registered with different content. The original is kept. |
| `invalid_title` / `invalid_points` / `invalid_goal` / `invalid_games` / `invalid_definition` | The definition failed validation. |
| `invalid_provider` | Bad provider id. `core` is reserved. |
| `provider_limit` | More than 200 definitions from one provider. |
| `rate_limited` | More than 120 writes in one second. |

## 5. Listen

```lua
mod.events:on(ach.events.ready, function(ev) end)     -- { game, how = "loaded"|"created" }
mod.events:on(ach.events.unlocked, function(ev) end)  -- { key, id, source, provider, title, points, how, official, raId }
mod.events:on(ach.events.progress, function(ev) end)  -- { key, id, source, provider, value, goal }
```

`ready` fires once a save is attached. Old saves are reconciled first.
That makes it the right moment for "on load" unlocks. Payloads are
copies, so changing them changes nothing.

Anyone can read any achievement:
`ach.isUnlocked("core:champion")`, `ach.get(key)`,
`ach.list({ source = "core", unlocked = true })`, `ach.totals()` and
`ach.currentGame()`.

Since 1.1.0 (check with `ach.supports("leaderboard_card")`):
`ach.officialTotals()` returns `{ earned, total, points, maxPoints }` for
the official RetroAchievements list only, and `ach.leaderboardCard()`
returns what the SELECT page shows: `{ game, name, points, earned, total,
maxPoints, saveId, code }`, or nil before a save is loaded.

Since 1.2.0, `officialTotals()` also has `reachedAt`: the play time in
seconds of the latest official unlock (nil with none), and the card has
`time`: the same in whole minutes.

## 6. What happens to your records

- They live in the framework's save bucket, so they rewind with older
  saves and travel with Save Sync.
- If the player uninstalls your mod, the records stay and show as
  **ARCHIVED** with their last-known title. They don't count toward
  totals and can't progress. When your mod is reinstalled with the same
  ids, they reattach.
- A fresh New Game starts empty. That is the engine's rule for every
  mod's save data.

## 7. Trust model

The API is **cooperative**. The engine can't tell the framework which mod
is calling, so a mod could call `connect("someone_else")`. Namespaces
prevent accidents, not deliberate cheating. Don't build anything that
depends on these achievements being tamper-proof.
