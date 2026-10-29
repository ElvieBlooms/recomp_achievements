-- rules/gen1.lua
-- ==================================================================
-- BONUS achievements for Red, Blue and Yellow: goals made for this mod
-- that are not in the official RetroAchievements sets (those live in
-- rules/gen1_official.lua).  main.lua marks every rule here `extra`, so
-- players can switch them off with the BONUS ACHIEVEMENTS option.
--
-- These are OUR detectors, written against Gen1Recomp's own state.  The
-- objectives are inspired by the kinds of goals in the RetroAchievements
-- sets (badges, legendaries, Pokedex milestones), but no RA trigger
-- logic is used or needed -- RA only publishes a hash of that logic, and
-- its terms reserve it.  Titles here are written for this mod.
--
-- Rule fields
--   id, title, description, points, category, hidden, goal, games
--       -> become the registry definition (see core/registry.lua)
--   kind = "state"  check(facts, game) -> true | number | false
--       re-checked whenever state may have changed and on load, so old
--       saves are credited ("backfill").  A number is progress toward goal.
--   kind = "event"  on = "<engine event>"
--                   test(payload, facts, ctx) -> true | number | false
--       a number is ADDED to progress (a counter).  Never backfilled.
--
-- Stable ids matter: the id is the save key ("core:<id>").  Renaming a
-- title is safe; renaming an id orphans every player's record.
-- ==================================================================

local function flagRule(id, title, description, flag, points, category, extra)
  local rule = {
    id = id, title = title, description = description,
    points = points, category = category, kind = "state",
    check = function(f) return f.flag(flag) end,
  }
  for k, v in pairs(extra or {}) do rule[k] = v end
  return rule
end

local function badgeRule(id, title, badge, leader, city)
  return {
    id = id, title = title, category = "BADGES", points = 5, kind = "state",
    description = ("Defeat %s in %s and earn the %s."):format(leader, city, badge:sub(1, 1) .. badge:sub(2):lower():gsub("badge$", " Badge")),
    check = function(f) return f.hasBadge(badge) end,
  }
end

local function dexRule(id, title, goal, points)
  return {
    id = id, title = title, category = "POKEDEX", points = points, goal = goal,
    unit = "OWNED", kind = "state",
    description = ("Register %d Pokemon as owned in your Pokedex."):format(goal),
    check = function(f) return f.dexOwned() end,
  }
end

return {
  -- ---------------------------------------------------------- STORY
  flagRule("first_partner", "First Partner",
    "Receive your first Pokemon from Prof. Oak.",
    "EVENT_GOT_STARTER", 2, "STORY"),
  -- --------------------------------------------------------- BADGES
  {
    id = "all_badges", title = "Badge Case", category = "BADGES", points = 10,
    goal = 8, unit = "BADGES", kind = "state",
    description = "Collect all eight Kanto badges.",
    check = function(f) return f.badgeCount() end,
  },

  -- ------------------------------------------------------ HMs/ITEMS
  {
    id = "hm_collector", title = "Hidden Machinery", category = "ITEMS",
    points = 10, goal = 5, unit = "HMS", kind = "state",
    description = "Obtain all five HMs: Cut, Fly, Surf, Strength and Flash.",
    check = function(f)
      local n = 0
      for _, flag in ipairs({ "EVENT_GOT_HM01", "EVENT_GOT_HM02", "EVENT_GOT_HM03",
                              "EVENT_GOT_HM04", "EVENT_GOT_HM05" }) do
        if f.flag(flag) then n = n + 1 end
      end
      return n
    end,
  },
  {
    id = "wake_snorlax", title = "Rise and Shine", category = "ITEMS",
    points = 5, goal = 2, unit = "SNORLAX", kind = "state",
    description = "Wake both sleeping Snorlax blocking Routes 12 and 16.",
    check = function(f)
      return (f.flag("EVENT_BEAT_ROUTE12_SNORLAX") and 1 or 0)
           + (f.flag("EVENT_BEAT_ROUTE16_SNORLAX") and 1 or 0)
    end,
  },

  -- ----------------------------------------------------- LEGENDARY
  flagRule("articuno", "Cold Front", "Battle Articuno in the Seafoam Islands.",
    "EVENT_BEAT_ARTICUNO", 10, "LEGENDARY"),
  flagRule("zapdos", "Power Surge", "Battle Zapdos at the Power Plant.",
    "EVENT_BEAT_ZAPDOS", 10, "LEGENDARY"),
  flagRule("moltres", "Trial by Fire", "Battle Moltres on Victory Road.",
    "EVENT_BEAT_MOLTRES", 10, "LEGENDARY"),
  flagRule("mewtwo", "Genetic Showdown", "Face Mewtwo in the depths of Cerulean Cave.",
    "EVENT_BEAT_MEWTWO", 25, "LEGENDARY", { hidden = true }),

  -- ------------------------------------------------------- POKEDEX
  dexRule("dex_10", "Getting Started", 10, 5),
  dexRule("dex_50", "Halfway Home", 50, 10),
  dexRule("dex_100", "Centurion", 100, 15),
  dexRule("dex_150", "Gotta Catch 'Em All", 150, 50),

  -- --------------------------------------------- EVENTS (no backfill)
  {
    id = "first_catch", title = "Gotcha!", category = "MOMENTS", points = 3,
    kind = "event", on = "pokemon.caught",
    description = "Catch a wild Pokemon with a Poke Ball.",
    test = function(ev) return ev ~= nil end,
  },
  {
    id = "first_evolution", title = "What? It's Evolving!", category = "MOMENTS",
    points = 5, kind = "event", on = "pokemon.evolved",
    description = "Watch one of your Pokemon evolve.",
    test = function(ev) return ev ~= nil and ev.toSpecies ~= nil end,
  },
  {
    id = "trainer_wins", title = "Seasoned Battler", category = "MOMENTS",
    points = 10, goal = 25, unit = "WINS", kind = "event", on = "battle.ended",
    description = "Win 25 trainer battles. Counted from when this mod was installed.",
    test = function(ev, _, ctx)
      if ev and ev.result == "win" and ctx.battle and ctx.battle.kind == "trainer" then
        return 1
      end
    end,
  },
}
