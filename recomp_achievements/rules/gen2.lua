-- rules/gen2.lua
-- ==================================================================
-- BONUS achievements for Gold, Silver and Crystal: goals made for this
-- mod, not from the RetroAchievements lists (those will live in
-- rules/gen2_official.lua).  main.lua marks them `extra`, so the BONUS
-- ACHIEVEMENTS option switches them off.
--
-- They only use facts that read the same way on all three versions
-- (badges, Pokedex, party, Unown, Hall of Fame), so none of them needs
-- Crystal's event-flag numbers.  Ids start with "g2_" so they can never
-- collide with a Gen 1 id.
-- ==================================================================

local function state(id, title, description, points, category, check, extra)
  local rule = { id = id, title = title, description = description, points = points,
                 category = category, kind = "state", check = check }
  for k, v in pairs(extra or {}) do rule[k] = v end
  return rule
end

local function dex(id, title, n, points)
  return state(id, title, ("Register %d Pokemon as caught in your Pokedex."):format(n), points, "POKEDEX",
    function(f) return f.dexOwned() end, { goal = n, unit = "POKEMON" })
end

return {
  state("g2_first_partner", "New Bark Beginnings", "Get your first Pokemon.", 2, "STORY",
    function(f) return f.partySize() > 0 or f.dexOwned() > 0 end),
  state("g2_johto_badges", "Johto Champion Material", "Collect all eight Johto badges.", 10, "BADGES",
    function(f) return f.badgeCount() end, { goal = 8, unit = "BADGES" }),
  state("g2_hall_of_fame", "Enter the Hall", "Defeat the Elite Four and Lance and enter the Hall of Fame.", 10, "STORY",
    function(f) return f.hallOfFame() > 0 end),
  state("g2_kanto_badges", "Back to Kanto", "Collect all eight Kanto badges.", 10, "BADGES",
    function(f) return f.kantoBadgeCount() end, { goal = 8, unit = "BADGES" }),
  state("g2_sixteen_badges", "Sixteen Badges", "Hold every badge in Johto and Kanto.", 25, "BADGES",
    function(f) return f.badgeCount() + f.kantoBadgeCount() end, { goal = 16, unit = "BADGES" }),
  dex("g2_dex_10", "Pokedex Starter", 10, 2),
  dex("g2_dex_50", "Pokedex Explorer", 50, 5),
  dex("g2_dex_100", "Pokedex Researcher", 100, 10),
  dex("g2_dex_200", "Pokedex Expert", 200, 25),
  state("g2_unown_all", "Ruins Scholar", "Catch all 26 forms of Unown.", 10, "POKEDEX",
    function(f) return f.unownForms() end, { goal = 26, unit = "FORMS" }),
  state("g2_shiny", "Something Shiny", "Own a shiny Pokemon.", 5, "POKEMON",
    function(f) return f.shinyCount() > 0 end),
  state("g2_level_100", "Peak Performance", "Raise a Pokemon to level 100.", 10, "POKEMON",
    function(f) return f.highestLevel() >= 100 end),
  {
    id = "g2_first_catch", title = "Gotcha!", description = "Catch a wild Pokemon.",
    points = 2, category = "POKEMON", kind = "event", on = "pokemon.caught",
    test = function() return true end,
  },
  {
    id = "g2_first_evolution", title = "What's Happening?", description = "Evolve a Pokemon.",
    points = 2, category = "POKEMON", kind = "event", on = "pokemon.evolved",
    test = function() return true end,
  },
  {
    id = "g2_hatch", title = "Fresh From the Egg", description = "Hatch a Pokemon Egg.",
    points = 3, category = "POKEMON", kind = "event", on = "egg.hatched",
    test = function() return true end,
  },
  {
    id = "g2_trainer_wins", title = "Johto Veteran", description = "Win 100 battles against trainers.",
    points = 10, category = "BATTLE", goal = 100, unit = "WINS", kind = "event", on = "battle.ended",
    test = function(ev, _, ctx)
      local b = ctx.battle
      return b and b.kind == "trainer" and ev and ev.result == "win" and 1 or false
    end,
  },
}
