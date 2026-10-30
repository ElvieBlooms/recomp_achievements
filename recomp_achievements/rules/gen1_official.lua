-- rules/gen1_official.lua
-- ==================================================================
-- Native detectors for the official RetroAchievements sets of
-- Pokemon Red (RA game 724), Blue (586) and Yellow (723).
--
-- Each rule's `ra` table says which RA achievement it tracks on which
-- game; titles, descriptions and points shown in game come from the
-- catalog files (catalog/<game>.lua).  The logic is ours, written against
-- Gen1Recomp's save and events.  RA's own trigger logic is not public and
-- is not used.
--
-- `fidelity = "interpretation"` + `note` marks rules whose check is a
-- close local reading of the goal rather than an exact one; the note is
-- shown on the achievement's ABOUT page.
--
-- Entries not listed here are shown as "not tracked yet" in the RA
-- reference view; docs/COVERAGE.md says why for each.
-- ==================================================================

return function(L)
  local rules = {}
  local function add(r) rules[#rules + 1] = r end
  local set = L.set

  -- ================================================================ STORY
  -- the Viridian Mart employee on Route 1 hands out a free Potion sample
  add(L.flag("off_free_sample", { red = 108020, blue = 540267 }, "Free sample",
    "EVENT_GOT_POTION_SAMPLE", { category = "STORY", points = 1 }))
  add(L.flag("off_town_map", { red = 108021, blue = 540268 }, "Town map",
    "EVENT_GOT_TOWN_MAP", { category = "STORY", points = 2 }))
  add(L.flag("off_pokedex", { red = 108022, blue = 540248, yellow = 81655 }, "Pokedex",
    "EVENT_GOT_POKEDEX", { category = "STORY" }))
  add(L.flag("off_poke_balls", { red = 108023, blue = 540258 }, "Five Poke Balls",
    "EVENT_GOT_POKEBALLS_FROM_OAK", { category = "STORY" }))
  add(L.anyFlag("off_fossil", { red = 4414, blue = 540284, yellow = 4441 }, "Fossil chosen",
    { "EVENT_GOT_DOME_FOSSIL", "EVENT_GOT_HELIX_FOSSIL" }, { category = "STORY" }))
  add(L.flag("off_hm01", { red = 108030, blue = 540277 }, "HM01 Cut",
    "EVENT_GOT_HM01", { category = "ITEMS" }))
  add(L.flag("off_hm05", { red = 108028, blue = 540278 }, "HM05 Flash",
    "EVENT_GOT_HM05", { category = "ITEMS" }))
  -- Oak's aides give these without setting a story flag in this port
  -- (data/scripts/story4.lua oaksAide), so the item itself is the proof.
  add(L.item("off_itemfinder", { red = 108027, blue = 540282 }, "Itemfinder", "ITEMFINDER"))
  add(L.flag("off_bicycle", { red = 108049, blue = 540283 }, "Bicycle",
    "EVENT_GOT_BICYCLE", { category = "ITEMS" }))
  add(L.with({ id = "off_silph_scope", ra = { red = 108038 }, title = "Silph Scope",
    kind = "state", category = "ITEMS",
    check = function(f) return f.hasItem("SILPH_SCOPE") or f.flag("EVENT_BEAT_GHOST_MAROWAK") end }))
  add(L.flag("off_hm02", { red = 108036, blue = 540279 }, "HM02 Fly",
    "EVENT_GOT_HM02", { category = "ITEMS" }))
  add(L.flag("off_poke_flute", { red = 4418, blue = 540285 }, "Poke Flute",
    "EVENT_GOT_POKE_FLUTE", { category = "STORY" }))
  add(L.flag("off_hm03", { red = 108046, blue = 540280 }, "HM03 Surf",
    "EVENT_GOT_HM03", { category = "ITEMS" }))
  add(L.flag("off_hm04", { red = 108048, blue = 540281 }, "HM04 Strength",
    "EVENT_GOT_HM04", { category = "ITEMS" }))
  add(L.allFlags("off_rods", { red = 108043, blue = 540272 }, "All three rods",
    { "EVENT_GOT_OLD_ROD", "EVENT_GOT_GOOD_ROD", "EVENT_GOT_SUPER_ROD" },
    { category = "ITEMS", unit = "RODS" }))
  add(L.item("off_exp_all", { red = 108044, blue = 540273 }, "Exp. All", "EXP_ALL"))
  add(L.flag("off_master_ball", { red = 108050, blue = 540275 }, "Master Ball",
    "EVENT_GOT_MASTER_BALL", { category = "ITEMS" }))
  add(L.anyFlag("off_dojo", { red = 4416, blue = 540274, yellow = 4443 }, "Dojo prize",
    { "EVENT_GOT_HITMONLEE", "EVENT_GOT_HITMONCHAN" }, { category = "STORY" }))
  add(L.flag("off_champion", { red = 4410, blue = 540257, yellow = 4437 }, "Champion",
    "EVENT_BEAT_CHAMPION_RIVAL", { category = "LEAGUE" }))
  add(L.with({ id = "off_full_team", ra = { red = 4409, blue = 540270, yellow = 4436 },
    title = "Full team", kind = "state", category = "POKEMON", goal = 6, unit = "IN PARTY",
    check = function(f) return f.partySize() end }))

  -- ================================================================ BADGES
  local badgeIds = {
    { "BOULDERBADGE", 4401, 540249, 4428 }, { "CASCADEBADGE", 4402, 540250, 4429 },
    { "THUNDERBADGE", 4403, 540251, 4430 }, { "RAINBOWBADGE", 4404, 540252, 4431 },
    { "SOULBADGE", 4405, 540253, 4432 },    { "MARSHBADGE", 4406, 540254, 4433 },
    { "VOLCANOBADGE", 4407, 540255, 4434 }, { "EARTHBADGE", 4408, 540256, 4435 },
  }
  for _, b in ipairs(badgeIds) do
    add(L.badge("off_" .. b[1]:lower(), { red = b[2], blue = b[3], yellow = b[4] },
      b[1]:sub(1, 1) .. b[1]:sub(2):lower(), b[1]))
  end

  -- ======================================================= GYM CHALLENGES
  -- Red: Challenge rules (RA's "Set mode", the SET battle style), no items
  -- in battle, level cap at the start of the fight.
  local redCaps = {
    { 1, 108058, 14 }, { 2, 108059, 21 }, { 3, 108060, 24 }, { 4, 108061, 29 },
    { 5, 108062, 43 }, { 6, 108063, 43 }, { 7, 108065, 47 }, { 8, 108068, 50 },
  }
  for _, c in ipairs(redCaps) do
    local gym = L.GYMS[c[1]]
    add(L.leaderChallenge("off_setcap_" .. gym.opp:lower(), { red = c[2] },
      "Challenge: " .. L.prettyName(gym.opp), gym.flag, gym.opp, L.setModeCap(c[3]),
      { category = "CHALLENGE", note = L.CHALLENGE .. ", use no items in the battle, and start it with "
        .. "no Pokemon above Lv." .. c[3] .. "." }))
  end
  -- Blue: beat the leader using only one type.
  local blueTypes = {
    { 1, 540298, "NORMAL" }, { 2, 540299, "BUG" }, { 3, 540300, "FIRE" },
    { 4, 540301, "ELECTRIC" }, { 5, 540302, "GRASS" }, { 6, 540303, "GHOST" },
    { 7, 540304, "FIGHTING" }, { 8, 540305, "PSYCHIC" },
  }
  for _, c in ipairs(blueTypes) do
    local gym = L.GYMS[c[1]]
    add(L.leaderChallenge("off_type_" .. gym.opp:lower(), { blue = c[2] },
      "Type challenge", gym.flag, gym.opp, L.onlyType(c[3]),
      { fidelity = "interpretation",
        note = "Counts every Pokemon you sent out in the leader battle." }))
  end
  -- Blue: every trainer and the leader in one visit.
  local blueClears = { 540306, 540307, 540308, 540309, 540310, 540311, 540312, 540313 }
  for i, raId in ipairs(blueClears) do
    local gym = L.GYMS[i]
    add(L.tracker("off_gymclear_" .. gym.map:lower(), { blue = raId }, "Gym sweep", {
      ["map.entered"] = function(state, ev, f)
        if ev and ev.mapId == gym.map then
          if not state.inside then
            local beaten = f.trainersBeaten(gym.map)
            state.inside, state.fresh = true, beaten == 0 and not f.flag(gym.flag)
          end
        else
          state.inside = false
        end
      end,
      ["flag.changed"] = function(state, ev, f)
        if not (state.inside and state.fresh and ev and ev.value) then return end
        local beaten, total = f.trainersBeaten(gym.map)
        if f.flag(gym.flag) and beaten >= total then return true end
      end,
    }, function(state, f, ctx)
      -- loading a save inside the gym counts as entering it now
      if ctx.map == gym.map then
        state.inside = true
        state.fresh = f.trainersBeaten(gym.map) == 0 and not f.flag(gym.flag)
      end
    end, { category = "GYMS" }))
  end

  -- ============================================================ LEAGUE RUNS
  local function notMew(m) return m.species ~= "MEW" and m.species ~= "MEWTWO" end
  local function maxLevel(party)
    local best = 0
    for _, m in ipairs(party) do if m.level > best then best = m.level end end
    return best
  end
  local redSet, blueSet = set(L.RED_EXCLUSIVES), set(L.BLUE_EXCLUSIVES)

  add(L.leagueRun("off_league_solo", { red = 4422 }, "Solo League",
    function(party) return #party == 1 and notMew(party[1]) end))
  add(L.leagueRun("off_league_red_excl", { red = 108169 }, "Red exclusives League",
    function(party) return #party == 6 and L.partyAll(function(m) return redSet[m.species] end)(party) end))
  add(L.leagueRun("off_league_perfect", { red = 108170 }, "Flawless League",
    function(party) return #party > 0 end,
    function(b) return b and b.playerFainted == 0 end,
    function(party) return maxLevel(party) <= 60 end))
  add(L.leagueRun("off_league_smogon", { red = 108171 }, "Challenge League",
    function(party) return #party > 0 end,
    function(b) return b and b.style == "set" and not b.itemsUsed end,
    function(party) return maxLevel(party) <= 50 end,
    { category = "CHALLENGE", note = L.CHALLENGE .. ", use no items in battle, and keep every Pokemon at Lv.50 or under." }))
  add(L.leagueRun("off_league_blue_excl", { blue = 540293 }, "Blue exclusives League",
    L.partyAll(function(m) return blueSet[m.species] end)))
  add(L.leagueRun("off_league_fairy", { blue = 540295 }, "Fairy League",
    L.partyAll(function(m) return set({ "CLEFAIRY", "CLEFABLE", "JIGGLYPUFF", "WIGGLYTUFF", "MR_MIME" })[m.species] end)))
  add(L.leagueRun("off_league_evolvable", { blue = 540296 }, "Unevolved League",
    L.partyAll(function(m, f) return f.canEvolve(m.species) end)))
  add(L.leagueRun("off_league_water", { blue = 540297 }, "Water League",
    L.partyAll(function(m, f) return f.hasType(m.species, "WATER") end)))
  add(L.leagueRun("off_league_safari", { blue = 540294 }, "Safari League",
    function(party, f)
      local ok = f.safariFamily and f.safariFamily()
      return ok ~= nil and L.partyAll(function(m) return ok[m.species] end)(party)
    end, nil, nil,
    { fidelity = "interpretation",
      note = "Safari species are read from the game's Safari Zone grass and fishing tables, plus everything they evolve into." }))
  add(L.leagueRun("off_league_pikachu", { yellow = 4449 }, "Pikachu League",
    function(party) return #party == 1 and party[1].species == "PIKACHU" end, nil, nil,
    { fidelity = "interpretation", note = "Surfing Pikachu can't be told apart, so it is allowed." }))

  -- ============================================================== POKEMON
  add(L.owns("off_snorlax", { red = 4419, blue = 540260, yellow = 4446 }, "Snorlax", "SNORLAX"))
  add(L.ownsAll("off_birds", { red = 4420, blue = 540261, yellow = 4447 }, "Legendary birds", L.BIRDS))
  add(L.owns("off_mewtwo", { red = 4421, blue = 540262, yellow = 4448 }, "Mewtwo", "MEWTWO"))
  add(L.onEvent("off_mewtwo_fair", { red = 108176 }, "Mewtwo, no Master Ball", "pokemon.caught",
    function(ev) return ev and ev.species == "MEWTWO" and ev.ball ~= "MASTER_BALL" end,
    { category = "POKEMON" }))
  add(L.ownsAll("off_red_exclusives", { red = 108141 }, "Red exclusives", L.RED_EXCLUSIVES))
  add(L.ownsAll("off_blue_exclusives", { blue = 540263 }, "Blue exclusives", L.BLUE_EXCLUSIVES))
  add(L.dexAtLeast("off_dex_red", { red = 4425 }, "Gotta catch 'em all", 124,
    { fidelity = "interpretation", note = "Counts Pokedex OWNED entries; reaching 124 in Red means every species the game offers." }))
  add(L.dexAtLeast("off_dex_blue", { blue = 540348 }, "Gotta catch 'em all", 124,
    { fidelity = "interpretation", note = "Counts Pokedex OWNED entries. Outside trades can't be detected, so they are not excluded." }))
  add(L.dexAtLeast("off_dex_yellow", { yellow = 4450 }, "Gotta catch 'em all", 129,
    { fidelity = "interpretation", note = "Counts Pokedex OWNED entries." }))
  add(L.owns("off_porygon", { blue = 540291 }, "Porygon", "PORYGON"))
  add(L.with({ id = "off_gifts", ra = { red = 108052, blue = 540271 }, title = "Gift Pokemon",
    kind = "state", category = "POKEMON", goal = 6, unit = "GIFTS",
    fidelity = "interpretation",
    note = "Counts the Magikarp salesman, Eevee, Lapras, the Dojo Pokemon, a revived Helix or Dome fossil and a revived Old Amber.",
    check = function(f)
      local n = 0
      if f.flag("EVENT_BOUGHT_MAGIKARP") then n = n + 1 end
      if f.flag("EVENT_GOT_EEVEE") then n = n + 1 end
      if f.flag("EVENT_GOT_LAPRAS") then n = n + 1 end
      if f.flag("EVENT_GOT_HITMONLEE") or f.flag("EVENT_GOT_HITMONCHAN") then n = n + 1 end
      if f.owns("OMANYTE") or f.owns("KABUTO") then n = n + 1 end
      if f.owns("AERODACTYL") then n = n + 1 end
      return n
    end }))
  add(L.with({ id = "off_statics", ra = { red = 108174, blue = 540289 }, title = "Every static Pokemon",
    kind = "state", category = "POKEMON", goal = 100, unit = "PERCENT",
    check = function(f)
      local done, total = 0, 0
      for _, id in ipairs(f.mapsMatching(".")) do
        local a, b = f.staticsDone(id)
        done, total = done + a, total + b
      end
      for _, flag in ipairs({ "EVENT_BEAT_ROUTE12_SNORLAX", "EVENT_BEAT_ROUTE16_SNORLAX" }) do
        total = total + 1
        if f.flag(flag) then done = done + 1 end
      end
      if total == 0 then return false end
      if done >= total then return true end
      return math.floor(done * 100 / total)
    end }))

  -- Safari Zone catches
  local safariPicks = {
    { "CHANSEY", 618978 }, { "KANGASKHAN", 618979 }, { "TAUROS", 618980 }, { "SCYTHER", 618981 },
  }
  for _, p in ipairs(safariPicks) do
    add(L.caught("off_safari_" .. p[1]:lower(), { red = p[2] }, "Safari catch",
      set({ p[1] }), "^SAFARI_ZONE", { category = "SAFARI" }))
  end

  -- =============================================================== TRADES
  local trades = {
    { "EVENT_TRADED_ABRA_FOR_MR_MIME", 540314, 81663 },
    { "EVENT_TRADED_NIDORAN_M_FOR_NIDORAN_F", 540315, 81662 },
    { "EVENT_TRADED_NIDORINO_FOR_NIDORINA", 540316, 81664 },
    { "EVENT_TRADED_SLOWBRO_FOR_LICKITUNG", 540317, 81671 },
    { "EVENT_TRADED_POLIWHIRL_FOR_JYNX", 540318, nil },
    { "EVENT_TRADED_SPEAROW_FOR_FARFETCHD", 540319, nil },
    { "EVENT_TRADED_RAICHU_FOR_ELECTRODE", 540320, 81678 },
    { "EVENT_TRADED_VENONAT_FOR_TANGELA", 540321, 81677 },
    { "EVENT_TRADED_PONYTA_FOR_SEEL", 540322, 81676 },
  }
  local allTradeFlags = {}
  for _, t in ipairs(trades) do
    allTradeFlags[#allTradeFlags + 1] = t[1]
    -- Yellow trades different species through the same trade slots, so
    -- the same done-flag tracks the Yellow trade at that NPC
    -- (data/scripts/story5.lua explains the shared flags).
    add(L.flag("off_" .. t[1]:lower(), { blue = t[2], yellow = t[3] }, "In-game trade",
      t[1], { category = "TRADES" }))
  end
  add(L.allFlags("off_all_trades", { red = 108053 }, "All in-game trades", allTradeFlags,
    { category = "TRADES", unit = "TRADES" }))

  -- ============================================================ AREA CLEARS
  local function maps(pattern) return function(f) return f.mapsMatching(pattern) end end
  local noFossils = function(item) return item == "DOME_FOSSIL" or item == "HELIX_FOSSIL" end
  add(L.sweep("off_clear_forest", { red = 108024 }, "Clear Viridian Forest",
    { "VIRIDIAN_FOREST" }, "both", { skip = noFossils }))
  add(L.sweep("off_clear_mt_moon", { red = 108025 }, "Clear Mt. Moon",
    maps("^MT_MOON_"), "both", { skip = noFossils },
    { fidelity = "interpretation", note = "The fossil you didn't pick doesn't count." }))
  add(L.sweep("off_clear_ss_anne", { red = 108029, blue = 540265 }, "Clear the S.S. Anne",
    maps("^SS_ANNE"), "both"))
  add(L.sweep("off_clear_hideout", { red = 108039, blue = 540259 }, "Clear the Rocket Hideout",
    maps("^ROCKET_HIDEOUT_"), "both", { extraFlags = { "EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI" } }))
  add(L.sweep("off_clear_tower", { red = 108041 }, "Clear Pokemon Tower",
    maps("^POKEMON_TOWER_"), "both"))
  add(L.sweep("off_clear_victory_road", { red = 108140 }, "Clear Victory Road",
    maps("^VICTORY_ROAD_"), "both"))
  -- Silph Co.: every trainer, every item, Giovanni, the rival, and every
  -- card-key door (the door flags come from data.field.cardKeyDoors).
  add(L.sweep("off_clear_silph", { red = 108051, blue = 540264 }, "Clear Silph Co.",
    maps("^SILPH_CO_"), "both", { extraFlags = function(f)
      local out = { "EVENT_BEAT_SILPH_CO_GIOVANNI", "EVENT_BEAT_SILPH_CO_RIVAL" }
      for _, flag in ipairs(f.cardKeyDoorFlags("^SILPH_CO_")) do out[#out + 1] = flag end
      return out
    end }))
  add(L.sweep("off_gym_item", { red = 108066, blue = 540266 }, "The gym item",
    { "VIRIDIAN_GYM" }, "items", { hidden = true }, { category = "ITEMS" }))

  -- Whole-game sweeps.  "Unmissable" leaves out the S.S. Anne (it sails
  -- away) and the fossil you didn't choose; League rooms are left out of
  -- trainers because their flags reset for rematches.
  local function overworld(f)
    local out = {}
    for _, id in ipairs(f.mapsMatching(".")) do
      if not id:find("^SS_ANNE") then out[#out + 1] = id end
    end
    return out
  end
  local function trainerMaps(f)
    local out = {}
    for _, id in ipairs(overworld(f)) do
      if not L.LEAGUE_MAPS[id] then out[#out + 1] = id end
    end
    return out
  end
  add(L.sweep("off_all_items", { red = 108367 }, "Every item",
    overworld, "items", { skip = noFossils },
    { category = "ITEMS", fidelity = "interpretation",
      note = "Every item ball and hidden item except on the S.S. Anne and the unchosen fossil." }))
  add(L.sweep("off_all_trainers", { red = 108368 }, "Every trainer",
    trainerMaps, "trainers", nil,
    { fidelity = "interpretation",
      note = "Every trainer except the S.S. Anne and the Elite Four rooms (their flags reset)." }))
  add(L.with({ id = "off_all_tms", ra = { red = 108365, blue = 540286 }, title = "Every free TM and HM",
    kind = "state", category = "ITEMS", goal = 100, unit = "PERCENT",
    fidelity = "interpretation",
    note = "Every TM/HM lying on the ground plus every TM/HM a character gives you.",
    check = function(f)
      local done, total = 0, 0
      local tm = function(item) return not (tostring(item):find("^TM") or tostring(item):find("^HM")) end
      for _, id in ipairs(overworld(f)) do
        local a, b = f.itemsFound(id, true, tm)
        done, total = done + a, total + b
      end
      local gifts = { "EVENT_GOT_TM06", "EVENT_GOT_TM11", "EVENT_GOT_TM13", "EVENT_GOT_TM18",
        "EVENT_GOT_TM21", "EVENT_GOT_TM24", "EVENT_GOT_TM27", "EVENT_GOT_TM28",
        "EVENT_GOT_TM29", "EVENT_GOT_TM31", "EVENT_GOT_TM34", "EVENT_GOT_TM35",
        "EVENT_GOT_TM36", "EVENT_GOT_TM38", "EVENT_GOT_TM39", "EVENT_GOT_TM41",
        "EVENT_GOT_TM42", "EVENT_GOT_TM46", "EVENT_GOT_TM48", "EVENT_GOT_TM49",
        "EVENT_GOT_HM01", "EVENT_GOT_HM02", "EVENT_GOT_HM03", "EVENT_GOT_HM04", "EVENT_GOT_HM05" }
      for _, flag in ipairs(gifts) do
        total = total + 1
        if f.flag(flag) then done = done + 1 end
      end
      if done >= total then return true end
      return math.floor(done * 100 / total)
    end }))

  -- Blue's regional sweeps
  local function list(...) return { ... } end
  add(L.sweep("off_items_routes", { blue = 540323 }, "Route items",
    list("ROUTE_4", "ROUTE_9", "ROUTE_10", "ROUTE_11", "ROUTE_12", "ROUTE_13", "ROUTE_17",
         "ROUTE_23", "ROUTE_25"), "items", nil, { category = "ITEMS" }))
  add(L.sweep("off_items_caves", { blue = 540324 }, "Cave items",
    function(f)
      local out = {}
      for _, p in ipairs({ "^CERULEAN_CAVE", "^POKEMON_MANSION", "^MT_MOON", "^SEAFOAM_ISLANDS" }) do
        for _, id in ipairs(f.mapsMatching(p)) do out[#out + 1] = id end
      end
      return out
    end, "items", { skip = noFossils }, { category = "ITEMS" }))
  add(L.sweep("off_items_manmade", { blue = 540325 }, "Indoor items",
    function(f)
      local out = {}
      for _, p in ipairs({ "^UNDERGROUND_PATH", "^SILPH_CO", "^POWER_PLANT" }) do
        for _, id in ipairs(f.mapsMatching(p)) do out[#out + 1] = id end
      end
      return out
    end, "items", nil, { category = "ITEMS" }))
  add(L.sweep("off_items_jizo", { blue = 540326 }, "Wild-place items",
    function(f)
      local out = { "VIRIDIAN_FOREST" }
      for _, p in ipairs({ "^SAFARI_ZONE", "^POKEMON_TOWER", "^VICTORY_ROAD" }) do
        for _, id in ipairs(f.mapsMatching(p)) do out[#out + 1] = id end
      end
      return out
    end, "items", nil, { category = "ITEMS" }))
  add(L.sweep("off_items_cities", { blue = 540327 }, "City items",
    list("CERULEAN_CITY", "VERMILION_CITY", "CELADON_CITY", "VIRIDIAN_CITY",
         "SAFFRON_CITY", "FUCHSIA_CITY"), "items", nil,
    { category = "ITEMS", fidelity = "interpretation", note = "The city maps themselves, not the buildings in them." }))
  local function routesAnd(extra, ...)
    local base = { ... }
    return function(f)
      local out = {}
      for _, id in ipairs(base) do out[#out + 1] = id end
      for _, p in ipairs(extra or {}) do
        for _, id in ipairs(f.mapsMatching(p)) do out[#out + 1] = id end
      end
      return out
    end
  end
  add(L.sweep("off_tr_humble", { blue = 540328 }, "Early trainers",
    routesAnd({ "^MT_MOON" }, "VIRIDIAN_FOREST", "ROUTE_3", "ROUTE_4"), "trainers"))
  add(L.sweep("off_tr_middle", { blue = 540329 }, "Route 24, 25, 6 trainers",
    list("ROUTE_24", "ROUTE_25", "ROUTE_6"), "trainers"))
  add(L.sweep("off_tr_east", { blue = 540330 }, "Route 11, 9, 10 trainers",
    list("ROUTE_11", "ROUTE_9", "ROUTE_10"), "trainers"))
  add(L.sweep("off_tr_dark", { blue = 540331 }, "Tunnel and tower trainers",
    routesAnd({ "^ROCK_TUNNEL", "^POKEMON_TOWER" }, "ROUTE_8"), "trainers"))
  add(L.sweep("off_tr_fields", { blue = 540332 }, "Route 12-15 trainers",
    list("ROUTE_12", "ROUTE_13", "ROUTE_14", "ROUTE_15"), "trainers"))
  add(L.sweep("off_tr_cycling", { blue = 540333 }, "Route 16-18 trainers",
    list("ROUTE_16", "ROUTE_17", "ROUTE_18"), "trainers"))
  add(L.sweep("off_tr_water", { blue = 540334 }, "Route 19-20 trainers",
    list("ROUTE_19", "ROUTE_20"), "trainers"))
  add(L.sweep("off_tr_last", { blue = 540335 }, "Late trainers",
    routesAnd({ "^POKEMON_MANSION", "^VICTORY_ROAD" }, "ROUTE_21"), "trainers"))

  -- ============================================================ GAME CORNER
  -- Free coins: the twelve hidden on the Game Corner floor, plus the three
  -- handouts from gamblers there.
  add(L.with({ id = "off_free_coins", ra = { red = 108037, blue = 540276 }, title = "Free coins",
    kind = "state", category = "CORNER", goal = 100, unit = "PERCENT",
    fidelity = "interpretation",
    note = "Every coin hidden on the Game Corner floor plus the three coin gifts from people there.",
    check = function(f)
      local done, total = f.hiddenCoinsFound("GAME_CORNER")
      for _, flag in ipairs({ "EVENT_GOT_10_COINS", "EVENT_GOT_20_COINS", "EVENT_GOT_20_COINS_2" }) do
        total = total + 1
        if f.flag(flag) then done = done + 1 end
      end
      if done >= total then return true end
      return math.floor(done * 100 / total)
    end }))
  add(L.with({ id = "off_9999_coins", ra = { red = 108182 }, title = "9,999 coins",
    kind = "state", category = "CORNER",
    check = function(f) return f.coins() >= 9999 end }))
  -- Slot wins: the slot machine remembers the symbol it paid out on
  -- (SlotMachine.winSymbol, set in resolveWin) while it shows the win.
  local function slotWin(id, raId, symbol)
    return L.tracker(id, { red = raId }, "Slot win", {
      tick = function(_, _, f)
        local top = f.topState()
        return top ~= nil and top.screenId == "SlotMachine" and top.winSymbol == symbol
      end,
    }, nil, { category = "CORNER" })
  end
  add(slotWin("off_slot_bar", 108179, "BAR"))
  add(slotWin("off_slot_seven", 108180, "7"))

  -- =============================================================== SAFARI
  -- A Safari hunt is the time save.safari exists (set when you pay at the
  -- gate, cleared when you leave or run out).
  add(L.tracker("off_safari_ten", { red = 108047, blue = 540287 }, "Ten in one hunt", {
    ["map.entered"] = function(state, _, f)
      if not f.inSafari() then state.catches = nil
      elseif not state.catches then state.catches = 0 end
    end,
    ["pokemon.caught"] = function(state, _, f)
      if not f.inSafari() then return end
      state.catches = (state.catches or 0) + 1
      if state.catches >= 10 then return true end
    end,
  }, function(state, f) if f.inSafari() then state.catches = 0 end end,
  { category = "SAFARI", fidelity = "interpretation",
    note = "Counts from the start of the hunt, or from loading a save already inside the Safari Zone." }))
  add(L.tracker("off_safari_items", { red = 108045 }, "Safari items in one hunt", {
    ["map.entered"] = function(state, _, f)
      if not f.inSafari() then state.start = nil return end
      if not state.start then
        local done = f.sweep(f.mapsMatching("^SAFARI_ZONE"), "items", { hidden = true })
        state.start = done
      end
      local done, total = f.sweep(f.mapsMatching("^SAFARI_ZONE"), "items", { hidden = true })
      if state.start == 0 and total > 0 and done >= total then return true end
    end,
    ["script.ended"] = function(state, _, f)
      if not (state.start == 0 and f.inSafari()) then return end
      local done, total = f.sweep(f.mapsMatching("^SAFARI_ZONE"), "items", { hidden = true })
      if total > 0 and done >= total then return true end
    end,
  }, nil, { category = "SAFARI", fidelity = "interpretation",
    note = "Every Safari Zone item, starting from none collected, in a single hunt." }))
  add(L.tracker("off_safari_209", { yellow = 81675 }, "209 steps left", {
    ["flag.changed"] = function(_, ev, f)
      if ev and ev.name == "EVENT_GOT_HM03" and ev.value then
        return f.safariSteps() == 209
      end
    end,
  }, nil, { category = "SAFARI", fidelity = "interpretation",
    note = "Exactly 209 Safari steps left when the HM03 is handed over; Surf use isn't checked." }))

  -- ========================================================== EXPLORATION
  add(L.onEvent("off_sleeping_giant", { red = 108138 }, "Sleeping giant", "world.interacted",
    function(ev, f)
      return ev and ev.kind == "sign" and type(ev.target) == "table"
        and ev.target.text == "TEXT_ROUTE11GATE2F_LEFT_BINOCULARS"
        and f.facing() == "up" and not f.flag("EVENT_BEAT_ROUTE12_SNORLAX")
    end, { category = "STORY", fidelity = "interpretation",
      note = "Looking through the Route 11 gate binoculars while Snorlax still sleeps on Route 12." }))
  add(L.onEvent("off_binoculars", { red = 108139, blue = 540269 }, "Mysterious bird", "world.interacted",
    function(ev, f)
      return ev and ev.kind == "sign" and type(ev.target) == "table"
        and ev.target.text == "TEXT_ROUTE15GATE2F_BINOCULARS" and f.facing() == "up"
    end, { category = "STORY" }))
  add(L.tracker("off_journals", { red = 108054, blue = 540288 }, "Every journal", {
    ["map.entered"] = function(state, ev)
      if not (ev and tostring(ev.mapId):find("^POKEMON_MANSION")) then state.read = {} end
    end,
    ["world.interacted"] = function(state, ev)
      local npc = ev and ev.kind == "npc" and ev.target
      local text = type(npc) == "table" and type(npc.def) == "table" and npc.def.text
      local journals = {
        TEXT_POKEMONMANSION2F_DIARY1 = true, TEXT_POKEMONMANSION2F_DIARY2 = true,
        TEXT_POKEMONMANSION3F_DIARY = true, TEXT_POKEMONMANSIONB1F_DIARY = true,
      }
      if not (text and journals[text]) then return end
      state.read = state.read or {}
      state.read[text] = true
      local n = 0
      for _ in pairs(state.read) do n = n + 1 end
      if n >= 4 then return true end
    end,
  }, function(state) state.read = {} end, { category = "STORY" }))
  -- The quiz gates' flags are written directly (data/scripts/story6.lua),
  -- with no flag.changed event, so this polls while you're in the gym.
  add(L.tracker("off_quiz", { red = 108056 }, "Quiz master", {
    ["map.entered"] = function(state, ev, f)
      if ev and ev.mapId == "CINNABAR_GYM" then
        if not state.inside then
          state.inside, state.battles = true, 0
          state.fresh = true
          for i = 0, 5 do
            if f.flag("EVENT_CINNABAR_GYM_GATE" .. i .. "_UNLOCKED") then state.fresh = false end
          end
        end
      else
        state.inside = false
      end
    end,
    ["battle.started"] = function(state) if state.inside then state.battles = state.battles + 1 end end,
    tick = function(state, _, f)
      if not (state.inside and state.fresh and state.battles == 0) then return end
      for i = 0, 5 do
        if not f.flag("EVENT_CINNABAR_GYM_GATE" .. i .. "_UNLOCKED") then return end
      end
      return true
    end,
  }, nil, { category = "PUZZLES", fidelity = "interpretation",
    note = "All six quiz gates opened in one visit, without a single battle." }))

  -- Ekans Dilos: reach the Silph Co. rival having beaten at most 1 Silph trainer
  add(L.onEvent("off_silph_rival_dash", { red = 108069 }, "Silph dash", "battle.started",
    function(ev, f, ctx)
      if not (ev and ev.trainerId == "OPP_RIVAL2" and tostring(ctx.map):find("^SILPH_CO")) then return end
      local beaten = f.sweep(f.mapsMatching("^SILPH_CO_"), "trainers")
      return beaten <= 1
    end, { category = "PUZZLES" }))

  -- Dearly Beloved: calm the Tower ghost with a Poke Doll, no Silph Scope.
  -- (The engine sets EVENT_BEAT_GHOST_MAROWAK directly, without a
  -- flag.changed event, so this watches the battle itself.)
  add(L.onEvent("off_poke_doll", { red = 108040 }, "Poke Doll ghost", "battle.ended",
    function(_, f, ctx)
      local b = ctx.battle
      if not (b and b.kind == "ghost" and ctx.map == "POKEMON_TOWER_6F") then return end
      if f.hasItem("SILPH_SCOPE") then return end
      for _, item in ipairs(b.itemsUsedList or {}) do
        if item == "POKE_DOLL" then return true end
      end
    end, { category = "PUZZLES" }))

  -- Blue: Fish Fear Me -- six species on Cinnabar without leaving the island
  local fishSet = set({ "MAGIKARP", "POLIWAG", "GOLDEEN", "SHELLDER", "HORSEA", "STARYU" })
  local function onCinnabar(map)
    map = tostring(map)
    return map:find("^CINNABAR") ~= nil or map:find("^POKEMON_MANSION") ~= nil
  end
  add(L.tracker("off_cinnabar_fish", { blue = 540292 }, "Cinnabar fishing", {
    ["map.entered"] = function(state, ev) if not onCinnabar(ev and ev.mapId) then state.got = {} end end,
    ["pokemon.caught"] = function(state, ev, _, ctx)
      if not (ev and onCinnabar(ctx.map) and fishSet[ev.species]) then return end
      state.got = state.got or {}
      state.got[ev.species] = true
      for s in pairs(fishSet) do if not state.got[s] then return end end
      return true
    end,
  }, function(state) state.got = {} end, { category = "POKEMON" }))

  -- Blue: Professor Oak Challenge Jr. -- catch and fully evolve a bug in the forest
  add(L.tracker("off_forest_bug", { blue = 540290 }, "Forest bug evolution", {
    ["map.entered"] = function(state, ev) if ev and ev.mapId ~= "VIRIDIAN_FOREST" then state.caught = nil end end,
    ["pokemon.caught"] = function(state, ev, _, ctx)
      if ev and ctx.map == "VIRIDIAN_FOREST" and (ev.species == "WEEDLE" or ev.species == "CATERPIE") then
        state.caught = true
      end
    end,
    ["pokemon.evolved"] = function(state, ev, _, ctx)
      if state.caught and ctx.map == "VIRIDIAN_FOREST" and ev
          and (ev.toSpecies == "BEEDRILL" or ev.toSpecies == "BUTTERFREE") then
        return true
      end
    end,
  }, nil, { category = "POKEMON", fidelity = "interpretation",
    note = "Any Weedle or Caterpie caught in the forest; the game can't tell which one evolved." }))

  -- Red: Area Unknown -- one of every Cerulean Cave species in one stay
  add(L.tracker("off_cerulean_cave", { red = 108175 }, "Cerulean Cave dex", {
    ["map.entered"] = function(state, ev)
      if not tostring(ev and ev.mapId):find("^CERULEAN_CAVE") then state.got = {} end
    end,
    ["pokemon.caught"] = function(state, ev, f, ctx)
      if not (ev and tostring(ctx.map):find("^CERULEAN_CAVE")) then return end
      if ev.ball == "MASTER_BALL" then return end
      state.got = state.got or {}
      state.got[ev.species] = true
      local need = f.encounterSpecies("^CERULEAN_CAVE")
      local any = false
      for s in pairs(need) do
        any = true
        if s ~= "MEWTWO" and not state.got[s] then return end
      end
      return any
    end,
  }, function(state) state.got = {} end, { category = "POKEMON", fidelity = "interpretation",
    note = "Species are read from the cave's walking encounter tables." }))

  -- Red: Anybody Home? -- through Viridian Forest without a wild battle,
  -- Repel or Cut, entrance to entrance.
  add(L.tracker("off_forest_dash", { red = 108026 }, "Forest dash", {
    ["map.entered"] = function(state, ev, f)
      local map, from = ev and ev.mapId, ev and ev.fromMapId
      if map == "VIRIDIAN_FOREST" then
        if from and tostring(from):find("GATE") and f.repelSteps() == 0 then
          state.run = { from = from, repels = f.repelCount() }
        end
      elseif state.run then
        local run = state.run
        state.run = nil
        if map and tostring(map):find("GATE") and map ~= run.from
            and f.repelCount() >= run.repels and f.repelSteps() == 0 then
          return true
        end
      end
    end,
    ["battle.started"] = function(state, ev) if ev and ev.kind ~= "trainer" then state.run = nil end end,
    ["sound.played"] = function(state, ev)
      if ev and ev.name == "Cut" then state.run = nil end
    end,
  }, nil, { category = "PUZZLES", fidelity = "interpretation",
    note = "Fails on any wild battle, any Repel used up, or any Cut tree cut inside the forest." }))

  add(L.onEvent("off_lawn_mower", { red = 108035 }, "Lawn mower", "sound.played",
    function(ev, f) return ev and ev.name == "Cut" and f.lastCutWasGrass() end,
    { category = "PUZZLES" }))

  -- Gym puzzles, each "starting from the gym entrance": the run starts when
  -- you walk in from the city and is judged when the leader's battle starts.
  local function gymRun(id, raId, gymMap, cityMap, opp, on, extra)
    local handlers = {
      ["map.entered"] = function(state, ev)
        if ev and ev.mapId == gymMap and ev.fromMapId == cityMap then
          state.run = { warps = 0, bumps = 0, spins = 0 }
        elseif ev and ev.mapId ~= gymMap then
          state.run = nil
        end
      end,
      ["battle.started"] = function(state, ev)
        local run = state.run
        if run and ev and ev.trainerId == opp then
          state.run = nil
          return on.judge(run)
        end
      end,
    }
    for name, fn in pairs(on.events or {}) do handlers[name] = fn end
    return L.tracker(id, { red = raId }, "Gym puzzle", handlers, nil,
      L.with({ category = "PUZZLES" }, extra))
  end
  add(gymRun("off_fuchsia_walls", 108057, "FUCHSIA_GYM", "FUCHSIA_CITY", "OPP_KOGA", {
    -- a bump re-arms the overworld's bump cooldown (OverworldController,
    -- CollisionCheckOnLand), so a rising cooldown is a new bump
    events = { frame = function(state, _, f, ctx)
      if not (state.run and ctx.map == "FUCHSIA_GYM") then return end
      local ow = f.overworld()
      local cd = ow and tonumber(ow.bumpCooldown) or 0
      if cd > (state.run.lastCd or 0) then state.run.bumps = state.run.bumps + 1 end
      state.run.lastCd = cd
    end },
    judge = function(run) return run.bumps == 0 end,
  }, { fidelity = "interpretation", note = "Any bump into a wall or person counts; reaching Koga's battle ends the run." }))
  add(gymRun("off_saffron_warps", 108064, "SAFFRON_GYM", "SAFFRON_CITY", "OPP_SABRINA", {
    events = { ["player.warped"] = function(state, ev)
      if state.run and ev and ev.fromMap == "SAFFRON_GYM" and ev.toMap == "SAFFRON_GYM" then
        state.run.warps = state.run.warps + 1
      end
    end },
    judge = function(run) return run.warps <= 4 end,
  }))
  add(gymRun("off_viridian_spin", 108067, "VIRIDIAN_GYM", "VIRIDIAN_CITY", "OPP_GIOVANNI", {
    events = { frame = function(state, _, f, ctx)
      if not (state.run and ctx.map == "VIRIDIAN_GYM") then return end
      local ow = f.overworld()
      if ow and type(ow.player) == "table" and ow.player.spinning then
        state.run.spins = state.run.spins + 1
      end
    end },
    judge = function(run) return run.spins == 0 end,
  }))

  -- Game Corner prizes and TMs in one session
  local prizeMons = set({ "ABRA", "CLEFAIRY", "NIDORINA", "DRATINI", "SCYTHER", "PORYGON" })
  add(L.tracker("off_prize_mons", { red = 108183 }, "Every prize Pokemon", {
    ["pokemon.before_give"] = function(state, ev, _, ctx)
      local species = ev and (ev.species or (type(ev.mon) == "table" and ev.mon.species))
      if not (ctx.map == "GAME_CORNER_PRIZE_ROOM" and prizeMons[species]) then return end
      state.got = state.got or {}
      state.got[species] = true
      for s in pairs(prizeMons) do if not state.got[s] then return end end
      return true
    end,
  }, function(state) state.got = {} end, { category = "CORNER" }))
  local shopTMs = { "TM_DOUBLE_TEAM", "TM_REFLECT", "TM_RAZOR_WIND", "TM_HORN_DRILL",
    "TM_EGG_BOMB", "TM_MEGA_PUNCH", "TM_MEGA_KICK", "TM_TAKE_DOWN", "TM_SUBMISSION",
    "TM_DRAGON_RAGE", "TM_HYPER_BEAM", "TM_SUBSTITUTE" }
  local function tmCheck(state, f)
    if not state.start then return end
    for _, tm in ipairs(shopTMs) do
      if f.itemCount(tm) <= (state.start[tm] or 0) then return end
    end
    return true
  end
  add(L.tracker("off_buy_tms", { red = 108366 }, "Every shop TM", {
    ["map.entered"] = function(state, _, f) return tmCheck(state, f) end,
    ["screen.popped"] = function(state, _, f) return tmCheck(state, f) end,
  }, function(state, f)
    state.start = {}
    for _, tm in ipairs(shopTMs) do state.start[tm] = f.itemCount(tm) end
  end, { category = "CORNER", fidelity = "interpretation",
    note = "One more of each Celadon Dept. Store and Game Corner TM than you had when the session started." }))

  -- Anti-Darwinism: press B during an evolution
  add(L.onEvent("off_cancel_evolution", { red = 108370 }, "Evolution cancelled", "screen.popped",
    function(ev)
      local st = ev and ev.state
      return type(st) == "table" and st.screenId == "EvolutionState" and st.canceled == true
    end, { category = "POKEMON" }))

  -- ============================================================== BATTLE
  add(L.tracker("off_crits", { red = 108033 }, "Five crits in a row", {
    ["battle.started"] = function(state) state.streak = 0 end,
    ["battle.damage_dealt"] = function(state, ev)
      local u = ev and ev.user
      if not (type(u) == "table" and (u.side == "player" or u.isPlayer == true)) then return end
      if ev.crit then state.streak = (state.streak or 0) + 1 else state.streak = 0 end
      if state.streak >= 5 then return true end
    end,
  }, nil, { category = "BATTLE" }))
  local OHKO = set({ "FISSURE", "HORN_DRILL", "GUILLOTINE" })
  add(L.tracker("off_ohko", { red = 108034 }, "Five OHKOs in a row", {
    ["battle.started"] = function(state) state.streak, state.pending = 0, nil end,
    ["battle.move_used"] = function(state, ev)
      local u = ev and ev.user
      if not (type(u) == "table" and (u.side == "player" or u.isPlayer == true)) then return end
      local move = type(ev.move) == "table" and ev.move.id or ev.move
      if OHKO[move] then
        if state.pending then state.streak = 0 end -- the last one missed
        state.pending = true
      else
        state.streak, state.pending = 0, nil
      end
    end,
    ["battle.fainted"] = function(state, ev)
      local who = ev and ev.battler
      if state.pending and type(who) == "table" and (who.side == "enemy" or who.isPlayer == false) then
        state.pending = nil
        state.streak = (state.streak or 0) + 1
        if state.streak >= 5 then return true end
      end
    end,
  }, nil, { category = "BATTLE", fidelity = "interpretation",
    note = "An OHKO move followed by the foe fainting counts as landed." }))
  add(L.tracker("off_metronome_bang", { red = 108172 }, "Metronome boom", {
    ["battle.move_used"] = function(_, ev)
      local u = ev and ev.user
      local move = type(ev and ev.move) == "table" and ev.move.id or (ev and ev.move)
      return type(u) == "table" and (u.side == "player" or u.isPlayer == true) and ev.isCalled == true
        and (move == "EXPLOSION" or move == "SELFDESTRUCT")
    end,
  }, nil, { category = "BATTLE" }))
  add(L.tracker("off_ditto", { red = 108173 }, "Ditto vs Ditto", {
    ["battle.move_used"] = function(_, ev)
      local u, t = ev and ev.user, ev and ev.target
      local move = type(ev and ev.move) == "table" and ev.move.id or (ev and ev.move)
      return move == "TRANSFORM" and type(u) == "table" and type(t) == "table"
        and (u.side == "player" or u.isPlayer == true) and u.species == "DITTO" and t.species == "DITTO"
    end,
  }, nil, { category = "BATTLE" }))
  add(L.tracker("off_thaw", { red = 108364 }, "Thawed out", {
    ["battle.started"] = function(state) state.frozen = false end,
    ["battle.turn_ended"] = function(state, ev, f, ctx)
      local raw = ev and ev.battle
      local p = type(raw) == "table" and type(raw.player) == "table" and raw.player
      local status = p and (p.status or (type(p.mon) == "table" and p.mon.status))
      if status == "FRZ" then state.frozen = true return end
      if state.frozen then
        state.frozen = false
        local b = ctx.battle
        if b and b.bagAtStart then
          local now = f.bag()
          for id, before in pairs(b.bagAtStart) do
            if (tonumber(now[id]) or 0) < (tonumber(before) or 0) then return end
          end
        end
        return status == nil or status == false
      end
    end,
  }, nil, { category = "BATTLE" }))
  add(L.tracker("off_stalemate", { red = 108042 }, "Stalemate", {
    ["battle.started"] = function(state, ev)
      local raw = ev and ev.battle
      local p = type(raw) == "table" and raw.player
      local mon = type(p) == "table" and type(p.mon) == "table" and p.mon
      state.ok = mon and mon.hp ~= nil and mon.stats and mon.hp == mon.stats.hp or false
      state.turns = 0
    end,
    ["battle.damage_dealt"] = function(state, ev) if (ev and ev.damage or 0) > 0 then state.ok = false end end,
    ["battle.battler_switched"] = function(state) state.ok = false end,
    ["battle.turn_ended"] = function(state)
      if not state.ok then return end
      state.turns = (state.turns or 0) + 1
      if state.turns >= 20 then return true end
    end,
  }, nil, { category = "BATTLE" }))
  add(L.onEvent("off_pay_day", { blue = 540336 }, "Pay Day jackpot", "battle.ended",
    function(ev, _, ctx)
      return ev and ev.result == "win" and ctx.battle and (ctx.battle.payDay or 0) > 2000
    end, { category = "BATTLE" }))

  -- ================================================================ LEVELS
  add(L.onEvent("off_halfway_solo", { red = 4411 }, "Lead to level 50", "pokemon.level_up",
    function(ev, f)
      local lead = f.party()[1]
      local mon = ev and type(ev.mon) == "table" and ev.mon
      return ev and ev.level == 50 and mon and lead ~= nil and lead.level == 50
        and lead.species == mon.species
    end, { category = "POKEMON" }))
  add(L.onEvent("off_halfway_party", { red = 4412 }, "Team to level 50", "pokemon.level_up",
    function(ev, f)
      if not (ev and ev.level == 50) then return end
      local party = f.party()
      if #party < 6 then return end
      for _, m in ipairs(party) do if m.level < 50 then return end end
      return true
    end, { category = "POKEMON" }))
  local legends = set({ "ARTICUNO", "ZAPDOS", "MOLTRES", "MEWTWO", "MEW" })
  add(L.onEvent("off_halfway_yellow", { yellow = 4439 }, "Six at level 50", "pokemon.level_up",
    function(ev, f)
      if not (ev and (ev.level or 0) >= 50) then return end
      local party = f.party()
      if #party < 6 then return end
      for _, m in ipairs(party) do
        if m.level < 50 or legends[m.species] then return end
      end
      return true
    end, { category = "POKEMON" }))

  -- ================================================================ YELLOW
  add(L.tracker("off_y_route22_early", { yellow = 81656 }, "Early rival", {
    ["flag.changed"] = function(_, ev, f)
      return ev and ev.name == "EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE" and ev.value
        and not f.visited("PEWTER_CITY")
    end,
  }, nil, { category = "STORY" }))
  local pikachuOnly = function(b)
    return L.usedOnly(b, function(s) return s == "PIKACHU" end)
  end
  local jj = {
    { "EVENT_BEAT_MT_MOON_3_JESSIE_JAMES", 81657 },
    { "EVENT_BEAT_ROCKET_HIDEOUT_4_JESSIE_JAMES", 81668 },
    { "EVENT_BEAT_POKEMONTOWER_7_JESSIE_JAMES", 81670 },
    { "EVENT_BEAT_SILPH_CO_11F_JESSIE_JAMES", 81673 },
  }
  for _, j in ipairs(jj) do
    add(L.tracker("off_y_" .. j[1]:lower(), { yellow = j[2] }, "Pikachu vs Jessie and James", {
      ["flag.changed"] = function(_, ev, _, ctx)
        if not (ev and ev.name == j[1] and ev.value) then return end
        local b = ctx.lastBattle
        return b ~= nil and b.result == "win" and pikachuOnly(b)
      end,
    }, nil, { category = "BATTLE" }))
  end
  local yFlags = {
    { "off_y_magikarp", 81658, "EVENT_BOUGHT_MAGIKARP", "STORY" },
    { "off_y_nugget_rival", 81659, "EVENT_BEAT_CERULEAN_RIVAL", "STORY" },
    { "off_y_charmander", 81660, "EVENT_54F", "POKEMON" },
    { "off_y_bulbasaur", 81661, "EVENT_GOT_BULBASAUR_IN_CERULEAN", "POKEMON" },
    { "off_y_squirtle", 81666, "EVENT_GOT_SQUIRTLE_FROM_OFFICER_JENNY", "POKEMON" },
    { "off_y_tower_rival", 81667, "EVENT_BEAT_POKEMON_TOWER_RIVAL", "STORY" },
    { "off_y_hideout", 81669, "EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI", "STORY" },
    { "off_y_silph_rival", 81672, "EVENT_BEAT_SILPH_CO_RIVAL", "STORY" },
    { "off_y_silph", 81674, "EVENT_BEAT_SILPH_CO_GIOVANNI", "STORY" },
    { "off_y_route22_rival", 81679, "EVENT_BEAT_ROUTE22_RIVAL_2ND_BATTLE", "STORY" },
  }
  for _, y in ipairs(yFlags) do
    add(L.flag(y[1], { yellow = y[2] }, "Yellow story", y[3], { category = y[4] }))
  end
  -- Cartridge saves imported into Gen1Recomp record the S.S. Anne rival
  -- only as his hidden map object, so either proof counts.
  add(L.with({ id = "off_y_ss_anne_rival", ra = { yellow = 81665 }, title = "S.S. Anne rival",
    kind = "state", category = "STORY",
    check = function(f)
      return f.flag("EVENT_BEAT_SS_ANNE_RIVAL") or f.objectHidden("SS_ANNE_2F", "SSANNE2F_RIVAL")
    end }))
  add(L.onEvent("off_y_tower_ghost", { yellow = 4445 }, "Tower ghost", "battle.started",
    function(ev, _, ctx) return ev and ev.kind == "ghost" and ctx.map == "POKEMON_TOWER_6F" end,
    { category = "STORY",
      -- beating the ghost proves you met it, so old saves get credit
      check = function(f) return f.flag("EVENT_BEAT_GHOST_MAROWAK") end }))
  add(L.tracker("off_y_gauntlet", { yellow = 81681 }, "Route 12-15 gauntlet", {
    ["map.entered"] = function(state, ev, f)
      local map = tostring(ev and ev.mapId)
      local inArea = map:find("^ROUTE_1[2-5]") ~= nil
      if not inArea then state.fresh = nil return end
      if state.fresh == nil then
        state.fresh = f.sweep({ "ROUTE_12", "ROUTE_13", "ROUTE_14", "ROUTE_15" }, "trainers") == 0
      end
    end,
    ["flag.changed"] = function(state, ev, f)
      if not (state.fresh and ev and ev.value) then return end
      local done, total = f.sweep({ "ROUTE_12", "ROUTE_13", "ROUTE_14", "ROUTE_15" }, "trainers")
      return total > 0 and done >= total
    end,
  }, nil, { category = "CLEAR", fidelity = "interpretation",
    note = "Route gates count as part of the area." }))

  -- Rock Tunnel from the Route 9 side to Lavender, never lit by Flash
  add(L.tracker("off_y_no_flash", { yellow = 81680 }, "Who needs Flash", {
    ["map.entered"] = function(state, ev, f)
      local map, from = ev and ev.mapId, ev and ev.fromMapId
      if f.flashLit() then state.run = nil end
      if map == "ROCK_TUNNEL_1F" and from == "ROUTE_10" and not state.run then
        local _, y = f.playerCell()
        if not f.flashLit() then state.run = { entryY = y or 0 } end
      elseif state.run and map == "ROUTE_10" and from == "ROCK_TUNNEL_1F" then
        local _, y = f.playerCell()
        if (y or 0) > state.run.entryY then state.run.through = true else state.run = nil end
      elseif state.run and map == "LAVENDER_TOWN" then
        local ok = state.run.through
        state.run = nil
        return ok == true
      elseif state.run and not tostring(map):find("^ROCK_TUNNEL") and map ~= "ROUTE_10" then
        state.run = nil
      end
    end,
  }, nil, { category = "PUZZLES", fidelity = "interpretation",
    note = "Enter from the north end, leave by the south end and walk into Lavender with no Flash used." }))

  -- Bill's house: Pikachu watches Bill come out of the Cell Separator
  add(L.tracker("off_y_bill_scene", { yellow = 81976 }, "Surprised Pikachu", {
    tick = function(_, _, f, ctx)
      local ow = f.overworld()
      return ctx.map == "BILLS_HOUSE" and ow ~= nil and ow.pikachuBillsScene == true
        and f.flag("EVENT_MET_BILL_2")
    end,
  }, nil, { category = "PIKACHU", points = 1 }))
  -- Trying to release your Pikachu: in the PC's RELEASE list the game
  -- refuses with a text box over the list (src/ui/BoxMenu.lua), so this
  -- looks for that box over the release list with your own Pikachu picked.
  add(L.tracker("off_y_release", { yellow = 81978 }, "Not getting away", {
    tick = function(_, _, f)
      local list, top = f.stateBelowTop(), f.topState()
      if not (list and top and list ~= top and list.kind == "pc_box_release") then return end
      local mon = f.boxMon(list.index)
      return mon ~= nil and f.isStarterPikachu(mon)
    end,
  }, nil, { category = "PIKACHU", points = 1 }))
  -- Pikachu stranded behind a ledge, doing its idle dance for a while
  add(L.tracker("off_y_ledge_dance", { yellow = 82089 }, "Look, I'm dancing", {
    tick = function(state, ev, f)
      local npc = f.pikachuNpc()
      local px, py = f.playerCell()
      if not (npc and px and npc.idle) then state.t = 0 return end
      local far = math.abs(npc.cellX - px) >= 2 or math.abs(npc.cellY - py) >= 2
      if not far then state.t = 0 return end
      state.t = (state.t or 0) + (ev and ev.dt or 0)
      if state.t >= 3 then return true end
    end,
  }, nil, { category = "PIKACHU", points = 1, fidelity = "interpretation",
    note = "Pikachu doing its idle animation two or more steps away from you for three seconds." }))

  -- Pikachu's emotions: talking to the following Pikachu shows one picked
  -- from friendship x mood (field.pikachu.moodRows) or a special case.
  -- adapters/gen1.lua:pikachuEmotion() repeats the engine's choice
  -- (src/world/PikachuFollower.lua selectEmotion) at the moment you talk.
  local emotions = {
    { 81795, 14 }, { 81796, 6 }, { 81797, 13 },
    { 81798, 9 },  { 81799, 5 }, { 81800, 12 },
    { 81801, 3 },  { 81802, 1 }, { 81803, 8 },
    { 81804, 4 },  { 81805, 15 },
    { 81806, 17 }, { 81807, 7 }, { 81808, 2 },
    { 81809, 16 }, { 81810, 10 },
    { 81811, 19 }, { 81812, 20 },
    { 81813, 18 }, { 81814, 21 }, { 81815, 24 }, { 81816, 25 },
    { 81817, 11 }, { 81818, 28 }, { 81819, 26 }, { 81820, 22 },
    { 81977, 30 },
  }
  for _, e in ipairs(emotions) do
    add(L.onEvent("off_y_pika_" .. e[1], { yellow = e[1] }, "Pikachu's mood", "world.interacted",
      function(ev, f)
        if not (ev and ev.kind == "npc" and type(ev.target) == "table" and ev.target.pikachuFollower) then
          return false
        end
        return f.pikachuEmotion() == e[2]
      end, { category = "PIKACHU", points = 1 }))
  end

  return rules
end
