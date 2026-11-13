# Recomp Achievements — Provider API (v1.6.0)

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
`hidden`, since 1.1.0 `official_totals` and `leaderboard_card`, since
1.3.0 `provider_tabs`, and since 1.6.0 `cart_lists`.

## 3. Connect and register

```lua
  local handle = ach.connect(mod, { tab = "NAVIPLAY" })  -- tab is optional
  -- or ach.connect("your_mod_id", { name = "...", tab = "..." })
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
    type = "missable",              -- optional, since 1.6.0: progression,
                                    -- win_condition or missable (see 6)
  })
```

**Your own tab.** Every mod with achievements in the running game gets
its own filter tab in the TROPHIES menu, next to FROM MODS. It's labelled
with `tab` from `connect` (max 12 characters, since 1.3.0) or else your
mod's name. When yours is the only mod with achievements, your tab takes
FROM MODS' place.

`games` takes version ids: `red`, `blue`, `yellow`, `gold`, `silver`,
`crystal`, `ruby`, `sapphire`, `emerald`, `firered` and `leafgreen`. If your
mod only runs on some of them, your manifest's own `games` list (`gen1`,
`gen2`, or Gen 3 version ids) still decides where it loads.

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

**Extra Credit.** Your achievements don't count on the main leaderboard,
but they do on Extra Credit: the card's Extra Credit page has a line for
your mod, keyed by your mod id (`naviplay 12/25 85`), and the site and
Discord bot keep a board for it. Point values are yours to choose (0–100
each); keep them sensible, since players compare them.

Since 1.1.0 (check with `ach.supports("leaderboard_card")`):
`ach.officialTotals()` returns `{ earned, total, points, maxPoints }` for
the RetroAchievements lists only, and `ach.leaderboardCard()`
returns what the SELECT page shows: `{ game, name, points, earned, total,
maxPoints, saveId, code }`, or nil before a save is loaded.

Since 1.2.0, `officialTotals()` also has `reachedAt`: the play time in
seconds of the latest RA-list unlock (nil with none), and the card has
`time`: the same in whole minutes.

Since 1.4.0:

- `ach.extraCard()` returns the Extra Credit page: `{ game, name, saveId,
  points, earned, total, code, sources = { { id, label, earned, total,
  points }, ... } }`, or nil before a save is loaded.
- `ach.addCardNote(mod, fn)` puts up to three lines (18 characters each)
  at the bottom of the leaderboard card, in place of the "enter at" text.
  `fn(card)` is called when the card draws and returns a string, a list
  of strings, or nil for nothing. Calling it again replaces your note.
  Recomp Achievements Online uses this for its status and link code.
- Since 1.5.0, `ach.addCardNote(mod, fn, { onPress = function(card) ... })`
  also gets the A button on the card page. Return true when you used it;
  otherwise A closes the card as usual.

Nothing changes for a mod that adds achievements when the player also has
Recomp Achievements Online: it only reads the cards above.

## 6. A custom cart's own list

A custom cart that is really a different game (a romhack ported as a
cart, say) can bring its own main list in place of the RetroAchievements
list, the way RA has its own set for a hack. Since 1.6.0:

```lua
  local handle = ach.connect(mod)
  handle:declareCartList({
    cart = "pokepink",        -- the cart's id, from its cart.json
    board = "pokepink",       -- leaderboard id; defaults to cart
    title = "Pokemon Pink",   -- shown on the card and the menu, max 32
    label = "PINK",           -- the list's tab, max 12
    games = { "yellow" },     -- optional: the versions the cart is built on
  })
  handle:registerMany(PINK_LIST)  -- everything you register is the list
```

An entry can be earned by one of this mod's own checks instead of yours:
`uses = "<rule id>"` (a rule in `rules/*.lua`, such as `"off_pokedex"`; it
returns `unknown_rule` otherwise), or a list of them, any of which earns
it. With one check, the entry takes the check's goal and unit unless it
sets its own. On the cart, the check earns your entry and
no longer shows or counts as itself. Use it for the parts of a hack that
play like the base game, and report the rest yourself as usual.

On that cart, and only there:

- Your entries are the main list. The menu's RA LIST tab becomes your
  `label`, entries show as from `title`'s list, and `type = "missable"`
  marks them MISSABLE the way RA's tag does.
- The RA-linked achievements for the base game step aside: they aren't
  listed and can't unlock. Bonus achievements and other mods' achievements
  stay as they are.
- `officialTotals()` and the leaderboard card count your list, and the
  card's `game` is your `board` (with `title` for display). Your list is
  left off Extra Credit, since it's on the main card.
- `ach.cartList()` returns `{ cart, board, title, label, provider }`.

On the plain game, or another cart, your entries aren't there: they don't
show, count or unlock (`wrong_cart`), so a cart's list never turns up as
a pile of locked achievements somewhere it can't be earned. One provider declares a cart's list; a second declaration
for the same cart returns `list_taken`. A `board` can't be a game version's
id (`invalid_list`).

**The leaderboard.** The board only takes games it knows, each with a
fixed total, so a cart's list goes on the main board once its board id
and totals are added to `GAMES` in `tools/leaderboard_ingest.py` (and the
board's other game lists: see docs/LEADERBOARD.md). Until then the card
still works and shows the list's numbers; the board refuses it.

## 7. What happens to your records

- They live in the framework's save bucket, so they rewind with older
  saves and travel with Save Sync.
- If the player uninstalls your mod, the records stay and show as
  **ARCHIVED** with their last-known title. They don't count toward
  totals and can't progress. When your mod is reinstalled with the same
  ids, they reattach.
- A fresh New Game starts empty. That is the engine's rule for every
  mod's save data.

## 8. Trust model

The API is **cooperative**. The engine can't tell the framework which mod
is calling, so a mod could call `connect("someone_else")`. Namespaces
prevent accidents, not deliberate cheating. Don't build anything that
depends on these achievements being tamper-proof.
