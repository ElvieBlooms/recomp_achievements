-- rules/gen3_emerald.lua
-- ==================================================================
-- Detectors for the RetroAchievements list of Emerald (197 entries),
-- built with rules/gen3_lib.lua.  Names (flags, vars, trainers, items,
-- species, moves, decorations) are pret's, turned into the save's numbers
-- by data/gen3_emerald.lua.
--
-- Most entries read story flags and vars from the save.  Battle-based ones
-- (gym trainers before the leader, stealing from rematches, the Battle
-- Tower apprentice) count wins as they happen.  Area sweeps are read from
-- the map data.  A few moments the save can't prove afterwards (Battle
-- Tent prizes, the Blend Master, a 5x5 Cut) are counted while you play and
-- say so on their "How it's checked" page.
-- ==================================================================

return function(L)
  local out = {}
  local function add(r) out[#out + 1] = r end
  local E = function(id) return { emerald = id } end
  local function interp(note, extra)
    extra = extra or {}
    extra.fidelity = "interpretation"
    extra.note = note
    return extra
  end
  -- the rival is May or Brendan (the other gender), with any starter
  local function rival(place)
    local list = {}
    for _, who in ipairs({ "BRENDAN", "MAY" }) do
      for _, mon in ipairs({ "MUDKIP", "TREECKO", "TORCHIC" }) do
        list[#list + 1] = ("TRAINER_%s_%s_%s"):format(who, place, mon)
      end
    end
    return list
  end

  -- ------------------------------------------------ story
  add(L.flag("em_birch", E(537183), "Professor Birch Rescued", "FLAG_RESCUED_BIRCH", { category = "STORY" }))
  add(L.flag("em_potion", E(537203), "Oldale Potion", "FLAG_RECEIVED_POTION_OLDALE", { category = "EVENTS" }))
  add(L.anyFlag("em_rival103", E(27592), "Rival: Route 103",
    (function() local l = rival("ROUTE_103"); l[#l + 1] = "FLAG_DEFEATED_RIVAL_ROUTE103"; return l end)(),
    { category = "RIVAL" }))
  add(L.var("em_wally_catch", E(537184), "Wally's First Pokemon", "VAR_PETALBURG_CITY_STATE", 3,
    interp("Counted once Wally has caught his Ralts (Petalburg City moves on).", { category = "STORY" })))
  add(L.flag("em_devon_goods", E(537185), "Devon Goods Recovered", "FLAG_RECOVERED_DEVON_GOODS", { category = "STORY" }))
  add(L.flag("em_wailmer_pail", E(537126), "Wailmer Pail", "FLAG_RECEIVED_WAILMER_PAIL", { category = "EVENTS" }))
  add(L.flag("em_quick_claw", E(537204), "Trainer School", "FLAG_RECEIVED_QUICK_CLAW", { category = "EVENTS" }))
  add(L.flag("em_trade_seedot", E(537133), "Trade: Seedot", "FLAG_RUSTBORO_NPC_TRADE_COMPLETED", { category = "EVENTS" }))
  add(L.flag("em_pokenav", E(537186), "PokeNav", "FLAG_RECEIVED_POKENAV", { category = "STORY" }))
  add(L.anyFlag("em_rival_rustboro", E(537115), "Rival: Rustboro",
    (function() local l = rival("RUSTBORO"); l[#l + 1] = "FLAG_DEFEATED_RIVAL_RUSTBORO"
      l[#l + 1] = "FLAG_DEFEATED_RIVAL_ROUTE_104"; return l end)(), { category = "RIVAL" }))
  add(L.flag("em_trend", E(537205), "Trendsetter", "FLAG_SYS_CHANGED_DEWFORD_TREND", { category = "EVENTS" }))
  add(L.flag("em_old_rod", E(537206), "Old Rod", "FLAG_RECEIVED_OLD_ROD", { category = "EVENTS" }))
  add(L.flag("em_letter", E(537187), "Letter Delivered", "FLAG_DELIVERED_STEVEN_LETTER", { category = "STORY" }))
  add(L.flag("em_exp_share", E(537214), "Exp. Share", "FLAG_RECEIVED_EXP_SHARE", { category = "EVENTS" }))
  add(L.flag("em_seashore", E(537207), "Seashore House", "FLAG_RECEIVED_6_SODA_POP", { category = "EVENTS" }))
  add(L.flag("em_powder_jar", E(537208), "Powder Jar", "FLAG_RECEIVED_POWDER_JAR", { category = "EVENTS" }))
  add(L.flag("em_soothe_bell", E(537210), "Soothe Bell", "FLAG_RECEIVED_SOOTHE_BELL", { category = "EVENTS" }))
  add(L.allFlags("em_museum", E(537188), "Oceanic Museum", { "TRAINER_GRUNT_MUSEUM_1", "TRAINER_GRUNT_MUSEUM_2" },
    { category = "STORY", goal = nil }))
  add(L.anyFlag("em_rival110", E(27593), "Rival: Route 110", rival("ROUTE_110"), { category = "RIVAL" }))
  add(L.flag("em_bike", E(537211), "Rydel's Bike", "FLAG_RECEIVED_BIKE", { category = "EVENTS" }))
  add(L.flag("em_coin_case", E(537212), "Coin Case", "FLAG_RECEIVED_COIN_CASE", { category = "EVENTS" }))
  add(L.flag("em_wally_mauville", E(537189), "Wally at Mauville", "FLAG_DEFEATED_WALLY_MAUVILLE", { category = "RIVAL" }))
  add(L.allFlags("em_glasses", E(537213), "Lost Glasses",
    { "FLAG_HIDDEN_ITEM_ROUTE_116_BLACK_GLASSES", "FLAG_HIDE_ROUTE_116_DROPPED_GLASSES_MAN" },
    interp("Counted once you've found the Black Glasses and the man on Route 116 has gone off looking.",
      { category = "EVENTS", goal = nil })))
  add(L.flag("em_winstrates", E(537127), "Winstrate Family", "FLAG_RECEIVED_MACHO_BRACE", { category = "EVENTS" }))
  add(L.flag("em_lotad_doll", E(537215), "Lanette's Doll", "FLAG_RECEIVED_DOLL_LANETTE", { category = "EVENTS" }))
  add(L.var("em_cozmo", E(537190), "Meteor Falls", "VAR_METEOR_FALLS_STATE", 1, { category = "STORY" }))
  add(L.flag("em_chimney", E(27604), "Mt. Chimney", "FLAG_DEFEATED_EVIL_TEAM_MT_CHIMNEY", { category = "STORY" }))
  add(L.hasItem("em_lava_cookie", E(537216), "Lava Cookie", "LAVA_COOKIE",
    interp("You hold a Lava Cookie (they're sold on Mt. Chimney).", { category = "EVENTS" })))
  add(L.flag("em_meteorite", E(537217), "Meteorite Returned", "FLAG_RECEIVED_TM_RETURN",
    interp("Professor Cozmo has given you TM27 Return for the Meteorite.", { category = "EVENTS" })))
  add(L.flag("em_jagged_grunt", E(537201), "Jagged Pass Grunt", "FLAG_BEAT_MAGMA_GRUNT_JAGGED_PASS", { category = "STORY" }))
  add(L.flag("em_egg", E(537131), "Lavaridge Egg", "FLAG_RECEIVED_LAVARIDGE_EGG", { category = "EVENTS" }))
  add(L.anyFlag("em_mirage_fossil", E(57267), "Mirage Tower Fossil", { "FLAG_CHOSE_CLAW_FOSSIL", "FLAG_CHOSE_ROOT_FOSSIL" },
    { category = "EVENTS" }))
  add(L.flag("em_mom_prize", E(537218), "Mom's Prize", "FLAG_RECEIVED_AMULET_COIN", { category = "EVENTS" }))
  add(L.flag("em_new_mauville", E(57271), "New Mauville", "FLAG_GOT_TM_THUNDERBOLT_FROM_WATTSON", { category = "EVENTS" }))
  add(L.flag("em_good_rod", E(537219), "Good Rod", "FLAG_RECEIVED_GOOD_ROD", { category = "EVENTS" }))
  add(L.owns("em_feebas", E(57265), "Feebas", "FEEBAS"))
  add(L.area("em_weather_grunts", E(537200), "Weather Institute Grunts",
    { maps = { "Route119_WeatherInstitute" }, kinds = { "trainers" }, trainerPrefix = "TRAINER_GRUNT_" },
    { note = "Every Team Aqua grunt in the Weather Institute." }))
  add(L.flag("em_weather", E(27605), "Weather Institute", "TRAINER_SHELLY_WEATHER_INSTITUTE", { category = "STORY" }))
  add(L.anyFlag("em_rival119", E(27594), "Rival: Route 119", rival("ROUTE_119"), { category = "RIVAL" }))
  add(L.flag("em_trade_plusle", E(537134), "Trade: Plusle", "FLAG_FORTREE_NPC_TRADE_COMPLETED", { category = "EVENTS" }))
  add(L.flag("em_hidden_power", E(537220), "TM10 Hidden Power", "FLAG_RECEIVED_TM_HIDDEN_POWER", { category = "EVENTS" }))
  add(L.flag("em_kecleon_gym", E(537191), "Invisible Obstacle", "FLAG_KECLEON_FLED_FORTREE", { category = "STORY" }))
  add(L.anyFlag("em_rival_lilycove", E(27595), "Rival: Lilycove", rival("LILYCOVE"), { category = "RIVAL" }))
  add(L.var("em_pyre", E(537192), "Mt. Pyre Summit", "VAR_MT_PYRE_STATE", 1, { category = "STORY" }))
  add(L.area("em_magma_hideout", E(537194), "Magma Hideout",
    { maps = { "MagmaHideout" }, trainerPrefix = "TRAINER_GRUNT_" },
    { note = "Every Team Magma grunt plus every item and hidden item in the Magma Hideout." }))
  add(L.flag("em_maxie_hideout", E(27606), "Maxie in the Hideout", "TRAINER_MAXIE_MAGMA_HIDEOUT", { category = "STORY" }))
  add(L.area("em_aqua_hideout", E(537195), "Aqua Hideout",
    { maps = { "AquaHideout" }, trainerPrefix = "TRAINER_GRUNT_" },
    { note = "Every Team Aqua grunt plus every item and hidden item in the Aqua Hideout." }))
  add(L.flag("em_matt", E(27607), "Aqua Hideout Admin", "TRAINER_MATT", { category = "STORY" }))
  add(L.flag("em_super_rod", E(537222), "Super Rod", "FLAG_RECEIVED_SUPER_ROD", { category = "EVENTS" }))
  add(L.flag("em_mental_herb", E(537223), "Wingull Postal Service", "FLAG_RECEIVED_MENTAL_HERB", { category = "EVENTS" }))
  add(L.hasItem("em_shell_bell", E(57272), "Shell Bell", "SHELL_BELL",
    interp("You hold a Shell Bell in your Bag (made from 4 Shoal Salt and 4 Shoal Shells).", { category = "EVENTS" })))
  add(L.area("em_space_grunts", E(537202), "Space Center Grunts",
    { maps = { "MossdeepCity_SpaceCenter" }, kinds = { "trainers" }, trainerPrefix = "TRAINER_GRUNT_" },
    { note = "Every Team Magma grunt in the Mossdeep Space Center." }))
  add(L.flag("em_space_center", E(27608), "Space Center", "FLAG_DEFEATED_MAGMA_SPACE_CENTER", { category = "STORY" }))
  add(L.area("em_seafloor", E(537196), "Seafloor Cavern",
    { maps = { "SeafloorCavern" }, trainerPrefix = "TRAINER_GRUNT_" },
    { note = "Every Team Aqua grunt plus every item in the Seafloor Cavern." }))
  add(L.flag("em_archie", E(27609), "Archie", "TRAINER_ARCHIE", { category = "STORY" }))
  add(L.state("em_rayquaza_calm", E(537193), "Sootopolis Showdown", function(f)
    return f.var("VAR_SOOTOPOLIS_CITY_STATE") >= 6 or f.flag("FLAG_BADGE08_GET")
  end, interp("Counted once Rayquaza has calmed Sootopolis and the Gym opens.", { category = "STORY" })))
  add(L.allFlags("em_hms", E(537233), "Every HM", { "FLAG_RECEIVED_HM_CUT", "FLAG_RECEIVED_HM_FLY",
    "FLAG_RECEIVED_HM_SURF", "FLAG_RECEIVED_HM_STRENGTH", "FLAG_RECEIVED_HM_FLASH", "FLAG_RECEIVED_HM_ROCK_SMASH",
    "FLAG_RECEIVED_HM_WATERFALL", "FLAG_RECEIVED_HM_DIVE" }, { category = "EVENTS" }))
  add(L.state("em_size", E(537226), "Size Matters", function(f)
    local function broken(v) local x = f.var(v) return x ~= 0 and x ~= 0x8000 end
    local n = (broken("VAR_SEEDOT_SIZE_RECORD") and 1 or 0) + (broken("VAR_LOTAD_SIZE_RECORD") and 1 or 0)
    return n >= 2 or n
  end, interp("Both brothers' size records (Seedot and Lotad) have been beaten.", { category = "EVENTS", goal = 2 })))
  add(L.flag("em_scanner", E(57270), "Scanner Delivered", "FLAG_EXCHANGED_SCANNER", { category = "EVENTS" }))
  add(L.flag("em_trade_horsea", E(537135), "Trade: Horsea", "FLAG_PACIFIDLOG_NPC_TRADE_COMPLETED", { category = "EVENTS" }))
  add(L.hasItem("em_frustration", E(537224), "TM21 Frustration", "TM_FRUSTRATION",
    interp("TM21 Frustration is in your TM Case.", { category = "EVENTS" })))
  add(L.flag("em_sealed", E(537225), "Sealed Chamber", "FLAG_REGI_DOORS_OPENED", { category = "EVENTS" }))
  add(L.owns("em_regirock", E(27621), "Regirock", "REGIROCK"))
  add(L.owns("em_regice", E(27622), "Regice", "REGICE"))
  add(L.owns("em_registeel", E(27623), "Registeel", "REGISTEEL"))
  add(L.owns("em_rayquaza", E(27620), "Rayquaza", "RAYQUAZA"))
  add(L.ownsAny("em_lati", E(30885), "Latias or Latios", { "LATIAS", "LATIOS" }))
  add(L.owns("em_groudon", E(27618), "Groudon", "GROUDON"))
  add(L.owns("em_kyogre", E(27619), "Kyogre", "KYOGRE"))
  add(L.var("em_scott_all", E(537197), "Scott Everywhere", "VAR_SCOTT_STATE", 13,
    interp("Scott's meeting counter reached its last step (13).", { category = "EVENTS" })))
  add(L.flag("em_wally_vr", E(27610), "Wally at Victory Road", "FLAG_DEFEATED_WALLY_VICTORY_ROAD", { category = "RIVAL" }))
  add(L.anyFlag("em_champion", E(27615), "Champion", { "FLAG_SYS_GAME_CLEAR", "TRAINER_WALLACE" }, { category = "LEAGUE" }))
  add(L.state("em_fossil2", E(57268), "Second Fossil", function(f)
    local root = f.hasItem("ROOT_FOSSIL") or f.owns("LILEEP") or f.owns("CRADILY")
    local claw = f.hasItem("CLAW_FOSSIL") or f.owns("ANORITH") or f.owns("ARMALDO")
    return root and claw
  end, interp("You have both fossils' lines: the Root and Claw Fossils, or Lileep and Anorith (or their evolutions).",
    { category = "EVENTS" })))
  add(L.flag("em_beldum", E(537132), "Beldum", "FLAG_RECEIVED_BELDUM", { category = "EVENTS" }))
  add(L.tracker("em_sale", E(537228), "Clearance Sale", {
    tick = function(s, _, f, ctx)
      local money = f.money()
      local spent = s.money and s.money - money >= 3000
        and tostring(ctx.map or ""):upper():match("LILYCOVE") and tostring(ctx.map or ""):upper():match("ROOFTOP")
      s.money = money
      return spent and true or nil
    end,
  }, nil, interp("Counted when 3,000 or more leaves your wallet at once on the Lilycove Department Store roof.",
    { category = "EVENTS" })))
  add(L.tracker("em_game_corner", E(537229), "Win Big", {
    tick = function(s, _, f, ctx)
      local coins = f.coins()
      local won = s.coins and coins - s.coins >= 500 and tostring(ctx.map or ""):upper():match("GAME_CORNER")
      s.coins = coins
      return won and true or nil
    end,
  }, nil, interp("Counted when your coins jump by 500 or more at once in the Mauville Game Corner.",
    { category = "EVENTS" })))
  add(L.tracker("em_blend_master", E(537231), "Blend Master", {
    tick = function(s, _, f)
      local n = f.pokeblockCount()
      local present = not f.flag("FLAG_HIDE_LILYCOVE_CONTEST_HALL_BLEND_MASTER")
      local made = present and s.blocks and n > s.blocks
      s.blocks = n
      return made and true or nil
    end,
  }, nil, interp("Counted when your Pokeblock Case gains a block while the Blend Master is in the Contest Hall.",
    { category = "EVENTS" })))
  add(L.flag("em_gabby_ty", E(537230), "Gabby & Ty", "TRAINER_GABBY_AND_TY_6",
    interp("Gabby and Ty's last (sixth) team beaten.", { category = "EVENTS" })))
  add(L.state("em_berry_wife", E(537235), "Berry Master's Wife", function(f)
    local n = f.countFlags({ "FLAG_RECEIVED_SPELON_BERRY", "FLAG_RECEIVED_PAMTRE_BERRY", "FLAG_RECEIVED_WATMEL_BERRY",
      "FLAG_RECEIVED_DURIN_BERRY", "FLAG_RECEIVED_BELUE_BERRY" })
    return n >= 4 or n
  end, { category = "EVENTS", goal = 4, unit = "BERRIES" }))
  add(L.state("em_daily_berries", E(537236), "Daily Berries", function(f)
    local list = { "FLAG_DAILY_CONTEST_LOBBY_RECEIVED_BERRY", "FLAG_DAILY_ROUTE_114_RECEIVED_BERRY",
      "FLAG_DAILY_ROUTE_111_RECEIVED_BERRY", "FLAG_DAILY_BERRY_MASTER_RECEIVED_BERRY",
      "FLAG_DAILY_ROUTE_120_RECEIVED_BERRY", "FLAG_DAILY_LILYCOVE_RECEIVED_BERRY",
      "FLAG_DAILY_FLOWER_SHOP_RECEIVED_BERRY", "FLAG_DAILY_BERRY_MASTERS_WIFE",
      "FLAG_DAILY_SOOTOPOLIS_RECEIVED_BERRY" }
    return f.countFlags(list) >= #list
  end, interp("All nine daily Berry gifts collected on the same day.", { category = "EVENTS" })))
  add(L.state("em_tutors", E(537234), "Move Tutors", function(f)
    local list = { "FLAG_MOVE_TUTOR_TAUGHT_DOUBLE_EDGE", "FLAG_MOVE_TUTOR_TAUGHT_DYNAMICPUNCH",
      "FLAG_MOVE_TUTOR_TAUGHT_EXPLOSION", "FLAG_MOVE_TUTOR_TAUGHT_FURY_CUTTER", "FLAG_MOVE_TUTOR_TAUGHT_METRONOME",
      "FLAG_MOVE_TUTOR_TAUGHT_MIMIC", "FLAG_MOVE_TUTOR_TAUGHT_ROLLOUT", "FLAG_MOVE_TUTOR_TAUGHT_SLEEP_TALK",
      "FLAG_MOVE_TUTOR_TAUGHT_SUBSTITUTE", "FLAG_MOVE_TUTOR_TAUGHT_SWAGGER" }
    local n = f.countFlags(list)
    return n >= #list or n
  end, { category = "COMPLETION", goal = 10, unit = "TUTORS" }))

  -- ------------------------------------------------ Battle Frontier
  add(L.state("em_scott_4bp", E(537198), "Scott's 4 BP", function(f)
    return f.flag("FLAG_SCOTT_GIVES_BATTLE_POINTS") and f.var("VAR_SCOTT_STATE") >= 13
  end, interp("Scott has given you Battle Points after meeting him every time (4 BP).", { category = "FRONTIER" })))
  add(L.flag("em_trade_meowth", E(537136), "Trade: Meowth", "FLAG_BATTLE_FRONTIER_TRADE_DONE", { category = "EVENTS" }))
  add(L.owns("em_sudowoodo", E(537199), "Sudowoodo", "SUDOWOODO"))
  add(L.state("em_gambler", E(537227), "High Roller", function(f)
    return f.var("VAR_FRONTIER_GAMBLER_STATE") == 2 and f.var("VAR_FRONTIER_GAMBLER_AMOUNT_BET") == 2
  end, interp("Counted while the gambler owes you your winnings from a 15 BP bet.", { category = "FRONTIER" })))
  add(L.state("em_apprentice", E(537237), "Apprentice Trained", function(f)
    return f.apprenticesFinished() > 0
  end, interp("An apprentice you trained is saved in the Battle Tower.", { category = "FRONTIER" })))
  local function apprentice(id) id = tonumber(id) return id ~= nil and id >= 400 and id < 404 end
  add(L.onEvent("em_apprentice_beat", E(537238), "Beat Your Apprentice", "battle.ended", function(ev, f, ctx)
    local b = ctx.battle
    return b ~= nil and ev and ev.result == "win" and b.battleTower == true and apprentice(b.trainerId)
  end, interp("Won a Battle Tower battle against a record-mixed apprentice.", { category = "FRONTIER" })))
  add(L.onEvent("em_apprentice_team", E(537239), "Team Up", "battle.ended", function(ev, f, ctx)
    local b = ctx.battle
    local ids = f.frontier().trainerIds
    local partner = type(ids) == "table" and (ids[18] or ids["18"]) or nil
    return b ~= nil and ev and ev.result == "win" and b.battleTower == true and b.multi == true
      and apprentice(partner)
  end, interp("Won a Battle Tower multi battle with an apprentice as your partner.", { category = "FRONTIER" })))
  local BRAINS = {
    { "ANABEL", "TOWER", 57297, 57298, "Anabel" }, { "TUCKER", "DOME", 57285, 57286, "Tucker" },
    { "SPENSER", "PALACE", 57293, 57294, "Spenser" }, { "GRETA", "ARENA", 57289, 57290, "Greta" },
    { "NOLAND", "FACTORY", 57291, 57292, "Noland" }, { "LUCY", "PIKE", 57287, 57288, "Lucy" },
    { "BRANDON", "PYRAMID", 57295, 57296, "Brandon" },
  }
  for _, b in ipairs(BRAINS) do
    add(L.flag("em_silver_" .. b[2]:lower(), E(b[3]), "Silver Symbol: " .. b[5], "FLAG_SYS_" .. b[2] .. "_SILVER",
      { category = "FRONTIER" }))
    add(L.flag("em_gold_" .. b[2]:lower(), E(b[4]), "Gold Symbol: " .. b[5], "FLAG_SYS_" .. b[2] .. "_GOLD",
      { category = "FRONTIER" }))
  end
  add(L.allFlags("em_scott_rewards", E(537240), "Scott's Rewards", { "FLAG_SCOTT_GIVES_BATTLE_POINTS",
    "FLAG_COLLECTED_ALL_SILVER_SYMBOLS", "FLAG_COLLECTED_ALL_GOLD_SYMBOLS", "FLAG_RECEIVED_SILVER_SHIELD",
    "FLAG_RECEIVED_GOLD_SHIELD" }, { category = "FRONTIER" }))
  add(L.flag("em_steven", E(27617), "Steven", "FLAG_DEFEATED_METEOR_FALLS_STEVEN", { category = "LEAGUE" }))
  add(L.dexAtLeast("em_dex", E(57275), "Hoenn and Beyond", 212,
    interp("Counted as 212 Pokemon marked caught in your Pokedex.")))

  -- ------------------------------------------------ Trick House
  local PUZZLES = { { 1, 537241 }, { 2, 537242 }, { 3, 537243 }, { 4, 537244 }, { 6, 537245 }, { 7, 537246 },
                    { 8, 537247 } }
  for _, p in ipairs(PUZZLES) do
    add(L.area("em_trick" .. p[1], E(p[2]), "Trick House Puzzle " .. p[1],
      { maps = { "Route110_TrickHousePuzzle" .. p[1] } },
      { note = "Every trainer and item in Trick House puzzle " .. p[1] .. "." }))
  end
  add(L.var("em_trick_master", E(57269), "Trick Master", "VAR_TRICK_HOUSE_LEVEL", 8,
    interp("All eight Trick House puzzles cleared and their prizes collected.", { category = "EVENTS" })))
  add(L.flag("em_trick_nugget", E(537248), "Trick Master's Nugget", "FLAG_HIDDEN_ITEM_TRICK_HOUSE_NUGGET",
    { category = "EVENTS" }))

  -- ------------------------------------------------ Trainer Hill, contests
  local HILL = { { 0, 57276, "Normal" }, { 1, 57277, "Variety" }, { 2, 57278, "Unique" }, { 3, 57279, "Expert" } }
  for _, h in ipairs(HILL) do
    add(L.state("em_hill_" .. h[3]:lower(), E(h[2]), "Trainer Hill: " .. h[3],
      function(f) return f.trainerHillCleared(h[1]) end, { category = "FRONTIER" }))
  end
  local CONTESTS = { { "cool", 57280, "Cool" }, { "beauty", 57281, "Beauty" }, { "cute", 57282, "Cute" },
                     { "smart", 57283, "Smart" }, { "tough", 57284, "Tough" } }
  for _, c in ipairs(CONTESTS) do
    add(L.state("em_contest_" .. c[1], E(c[2]), "Master Rank: " .. c[3],
      function(f) return f.ribbonRank(c[1]) >= 4 end,
      interp("One of your Pokemon has the Master Rank " .. c[3] .. " ribbon.", { category = "CONTESTS" })))
  end
  add(L.allFlags("em_scarves", E(537232), "Every Scarf", { "FLAG_RECEIVED_RED_SCARF", "FLAG_RECEIVED_BLUE_SCARF",
    "FLAG_RECEIVED_PINK_SCARF", "FLAG_RECEIVED_GREEN_SCARF", "FLAG_RECEIVED_YELLOW_SCARF" }, { category = "CONTESTS" }))
  add(L.flag("em_glass", E(537221), "Glass Ornament", "FLAG_RECEIVED_GLASS_ORNAMENT", { category = "CONTESTS" }))

  -- ------------------------------------------------ collections
  add(L.state("em_flutes", E(537152), "Every Flute", function(f)
    local n = 0
    for _, it in ipairs({ "BLUE_FLUTE", "YELLOW_FLUTE", "RED_FLUTE", "WHITE_FLUTE", "BLACK_FLUTE" }) do
      if f.hasItem(it) then n = n + 1 end
    end
    return n >= 5 or n
  end, { category = "COLLECTION", goal = 5, unit = "FLUTES" }))
  -- people's item gifts (flags set right after giveitem), leaving out daily
  -- and weekly gifts, Shoal Cave pickups, choices and story key items
  local GIFT_SKIP = { "FLAG_DAILY_", "FLAG_TEMP_", "FLAG_RECEIVED_SHOAL_", "FLAG_CHOSE_", "FLAG_COLLECTED_",
    "FLAG_REGISTERED_", "FLAG_SYS_", "FLAG_RECOVERED_", "FLAG_RETURNED_", "FLAG_EXCHANGED_",
    "FLAG_RECEIVED_FANCLUB_TM_THIS_WEEK", "FLAG_RECEIVED_RED_OR_BLUE_ORB", "FLAG_RECEIVED_METEORITE",
    "FLAG_RECEIVED_SPELON_BERRY", "FLAG_RECEIVED_PAMTRE_BERRY", "FLAG_RECEIVED_WATMEL_BERRY",
    "FLAG_RECEIVED_DURIN_BERRY", "FLAG_RECEIVED_BELUE_BERRY", "FLAG_GOT_BASEMENT_KEY_FROM_WATTSON" }
  local function giftRow(row)
    for _, p in ipairs(GIFT_SKIP) do if row[2]:sub(1, #p) == p then return false end end
    return true
  end
  add(L.state("em_gifts", E(537125), "Gifted Kid", function(f)
    local done, total = f.sweep("gifts", giftRow)
    if total == 0 then return false end
    return done >= total or math.floor(done * 100 / total)
  end, interp("Every item a person hands you, leaving out daily and weekly gifts, Shoal Cave pickups, choices and story key items.",
    { category = "COLLECTION", goal = 100, unit = "PCT" })))
  add(L.state("em_kecleon", E(537137), "Eagle Eye", function(f)
    local list = { "FLAG_HIDE_ROUTE_119_KECLEON_1", "FLAG_HIDE_ROUTE_119_KECLEON_2", "FLAG_HIDE_ROUTE_120_KECLEON_1",
      "FLAG_HIDE_ROUTE_120_KECLEON_2", "FLAG_HIDE_ROUTE_120_KECLEON_3", "FLAG_HIDE_ROUTE_120_KECLEON_4",
      "FLAG_HIDE_ROUTE_120_KECLEON_5", "FLAG_HIDE_ROUTE_120_KECLEON_BRIDGE", "FLAG_KECLEON_FLED_FORTREE" }
    local n = f.countFlags(list)
    return n >= #list or n
  end, { category = "COLLECTION", goal = 9, unit = "KECLEON" }))
  add(L.state("em_volt_tackle", E(537138), "Volt Tackle Pichu", function(f)
    return f.knowsMove({ "PICHU", "PIKACHU", "RAICHU" }, "VOLT_TACKLE")
  end, interp("You have a Pichu (or its evolution) that knows Volt Tackle, which only comes from breeding.",
    { category = "POKEMON" })))
  -- Cutting a 5x5 patch replaces 25 grass blocks in the same moment.
  add(L.tracker("em_cut", E(537450), "Iai Mon", {
    ["world.block_replaced"] = function(s, ev, f, ctx)
      local t = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
      if not s.at or t - s.at > 0.5 then s.at, s.n = t, 0 end
      s.n = s.n + 1
      return s.n >= 25 or nil
    end,
  }, nil, interp("Counted when 25 or more grass blocks are cut within half a second (one Cut on a 5x5 patch).",
    { category = "EVENTS" })))
  local function steal(id, ra, title, item, who)
    add(L.beatTrainer(id, E(ra), title, { who .. "_4", who .. "_5" }, function(b, f)
      local itemId = f.data().itemIds[item]
      local before = b.bagAtStart and itemId and tonumber(b.bagAtStart[itemId]) or 0
      return itemId ~= nil and f.itemCount(item) > before
    end, interp("Beat this trainer's fourth or fifth rematch team and leave the battle with one more " ..
      item:gsub("_", " "):lower() .. " than you started with.", { category = "EVENTS" })))
  end
  steal("em_steal_belt", 537249, "Black Belt Thief", "BLACK_BELT", "TRAINER_NOB")
  steal("em_steal_powder", 537250, "Silver Powder Thief", "SILVER_POWDER", "TRAINER_JEFFREY")
  steal("em_steal_fang", 537251, "Dragon Fang Thief", "DRAGON_FANG", "TRAINER_NICOLAS")
  add(L.state("em_secret_base", E(57266), "Secret Base Furnished", function(f)
    local n = f.secretBaseDecorations()
    return n >= 16 or n
  end, { category = "COLLECTION", goal = 16, unit = "SLOTS" }))
  add(L.state("em_room", E(537124), "Bedroom Furnished", function(f)
    local n = f.roomDecorations()
    return n >= 12 or n
  end, { category = "COLLECTION", goal = 12, unit = "SLOTS" }))
  -- decoration collections: every decoration of these categories (0 desk,
  -- 1 chair, 2 plant, 3 ornament, 4 mat, 5 poster, 6 doll, 7 cushion)
  local function decor(id, ra, title, cats, skip, need, note)
    add(L.state(id, E(ra), title, function(f)
      local want, have = 0, 0
      local owned = {}
      for _, c in ipairs(cats) do for k in pairs(f.decorations(c)) do owned[k] = true end end
      for name, d in pairs(f.data().decorations or {}) do
        local inCat = false
        for _, c in ipairs(cats) do if d[2] == c then inCat = true end end
        if inCat and not (skip and skip[name]) then
          want = want + 1
          if owned[d[1]] then have = have + 1 end
        end
      end
      if want == 0 then return false end
      local goal = want - (need or 0)
      return have >= goal or math.floor(have * 100 / goal)
    end, interp(note, { category = "COLLECTION", goal = 100, unit = "PCT" })))
  end
  decor("em_decor_furniture", 537148, "Furniture Collector", { 0, 1, 2 }, nil, 0,
    "Every desk, chair and plant, in your PC or placed.")
  decor("em_decor_fun", 537149, "Fun Collector", { 3, 5 }, nil, 1,
    "Every ornament and poster, missing at most one (the tent you didn't pick).")
  decor("em_decor_comfort", 537150, "Comfort Collector", { 4, 7 }, nil, 0, "Every cushion and mat.")
  decor("em_decor_dolls", 537151, "Doll Collector", { 6 },
    { SEEDOT_DOLL = true, REGIROCK_DOLL = true, REGICE_DOLL = true, REGISTEEL_DOLL = true }, 0,
    "Every doll except the Seedot, Regirock, Regice and Registeel dolls.")

  -- ------------------------------------------------ strongest teams (rematches)
  local REMATCH = {
    { "WALLY_VR", 537139, "Wally's Strongest" }, { "ROXANNE", 537140, "Roxanne's Strongest" },
    { "BRAWLY", 537141, "Brawly's Strongest" }, { "WATTSON", 537142, "Wattson's Strongest" },
    { "FLANNERY", 537143, "Flannery's Strongest" }, { "NORMAN", 537144, "Norman's Strongest" },
    { "WINONA", 537145, "Winona's Strongest" }, { "TATE_AND_LIZA", 537146, "Tate & Liza's Strongest" },
    { "JUAN", 537147, "Juan's Strongest" },
  }
  for _, r in ipairs(REMATCH) do
    add(L.flag("em_strongest_" .. r[1]:lower(), E(r[2]), r[3], "TRAINER_" .. r[1] .. "_5",
      { category = "GYMS" }))
  end

  -- ------------------------------------------------ gyms
  local GYMS = {
    { 1, "Roxanne", 27596, 537116, "FLAG_DEFEATED_RUSTBORO_GYM", "Rustboro" },
    { 2, "Brawly", 27597, 537117, "FLAG_DEFEATED_DEWFORD_GYM", "Dewford" },
    { 3, "Wattson", 27598, 537118, "FLAG_DEFEATED_MAUVILLE_GYM", "Mauville" },
    { 4, "Flannery", 27599, 537119, "FLAG_DEFEATED_LAVARIDGE_GYM", "Lavaridge" },
    { 5, "Norman", 27600, 537120, "FLAG_DEFEATED_PETALBURG_GYM", "Petalburg" },
    { 6, "Winona", 27601, 537121, "FLAG_DEFEATED_FORTREE_GYM", "Fortree" },
    { 7, "Tate & Liza", 27602, 537122, "FLAG_DEFEATED_MOSSDEEP_GYM", "Mossdeep" },
    { 8, "Juan", 27603, 537123, "FLAG_DEFEATED_SOOTOPOLIS_GYM", "Sootopolis" },
  }
  for _, g in ipairs(GYMS) do
    add(L.badge("em_badge" .. g[1], E(g[3]), "Badge: " .. g[2], g[1]))
    add(L.gymTrainers("em_gymtrainers" .. g[1], E(g[4]), g[6] .. " Gym Trainers", g[1], g[5], {
      note = "Beat them before the Gym Leader: once the leader falls, the game marks the rest as beaten.",
    }))
  end

  -- ------------------------------------------------ Battle Tents
  local function tent(id, ra, title, field)
    add(L.tracker(id, E(ra), title, {
      tick = function(s, _, f)
        local prize = tonumber(f.frontier()[field]) or 0
        local got = (s.prize or 0) > 0 and prize == 0
        s.prize = prize
        return got or nil
      end,
    }, nil, interp("Counted when the Battle Tent hands over your prize while you're playing.",
      { category = "FRONTIER" })))
  end
  tent("em_tent_slateport", 537128, "Slateport Battle Tent", "slateportTentPrize")
  tent("em_tent_verdanturf", 537129, "Verdanturf Battle Tent", "verdanturfTentPrize")
  tent("em_tent_fallarbor", 537130, "Fallarbor Battle Tent", "fallarborTentPrize")

  -- ------------------------------------------------ areas
  local AREAS = {
    { "littleroot", 537167, 537153, "Littleroot",
      { "LittlerootTown", "Route101", "OldaleTown", "Route103", "Route102" } },
    { "petalburg", 537168, 537154, "Petalburg", { "PetalburgCity", "Route104", "Route105", "PetalburgWoods" } },
    { "rustboro", 537169, 537155, "Rustboro", { "RustboroCity", "Route115", "Route116", "RusturfTunnel" } },
    { "dewford", 537170, 537156, "Dewford",
      { "DewfordTown", "GraniteCave", "Route106", "Route107", "Route108", "AbandonedShip" } },
    { "slateport", 537171, 537157, "Slateport", { "SlateportCity", "Route109", "Route110" } },
    { "mauville", 537172, 537158, "Mauville",
      { "MauvilleCity", "VerdanturfTown", "Route117", "Route118", "NewMauville" } },
    { "lavaridge", 537173, 537159, "Lavaridge",
      { "LavaridgeTown", "Route111", "Route112", "FieryPath", "MtChimney", "JaggedPass" } },
    { "fallarbor", 537174, 537160, "Fallarbor", { "FallarborTown", "Route113", "Route114", "MeteorFalls" } },
    { "fortree", 537175, 537161, "Fortree",
      { "FortreeCity", "Route119", "Route120", "ScorchedSlab", "Route121" } },
    { "lilycove", 537176, 537162, "Lilycove", { "LilycoveCity", "SafariZone", "Route122", "MtPyre", "Route123" } },
    { "mossdeep", 537177, 537163, "Mossdeep", { "MossdeepCity", "Route124", "Route125", "ShoalCave" } },
    { "sootopolis", 537178, 537164, "Sootopolis", { "SootopolisCity", "Route126", "Route127" } },
    { "evergrande", 537179, 537165, "Ever Grande", { "EverGrandeCity", "Route128", "Route129", "VictoryRoad" } },
    { "pacifidlog", 537180, 537166, "Pacifidlog",
      { "PacifidlogTown", "Route130", "Route131", "Route132", "Route133", "Route134" } },
    { "frontier", 537182, 537181, "S.S. Tidal & Frontier", { "SSTidalCorridor", "SSTidalLowerDeck", "SSTidalRooms", "BattleFrontier" } },
  }
  -- the Trick House puzzles have achievements of their own
  local SKIP = { "Route110_TrickHouse" }
  for _, a in ipairs(AREAS) do
    local list = table.concat(a[5], ", ")
    add(L.area("em_items_" .. a[1], E(a[2]), a[4] .. " Items",
      { maps = a[5], skip = SKIP, kinds = { "items", "hidden" } },
      { note = "Every item ball and hidden item in: " .. list .. "." }))
    add(L.area("em_trainers_" .. a[1], E(a[3]), a[4] .. " Trainers",
      { maps = a[5], skip = SKIP, kinds = { "trainers" } },
      { note = "Every trainer (gyms and rival battles aside) in: " .. list .. "." }))
  end

  return out
end
