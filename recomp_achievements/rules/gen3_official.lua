-- rules/gen3_official.lua
-- ==================================================================
-- Detectors for the RetroAchievements lists of FireRed (61) and
-- LeafGreen (128).  Titles here are the mod's own short names; when the
-- RA catalogs are installed the menu shows RA's text instead.  Ruby,
-- Sapphire and Emerald come in a later release.
--
-- Most entries read pret flags straight from the save (badges, gifts,
-- trades, rescues).  Battle rules (challenges, gym trainers, solo league
-- runs) count wins as they happen.  "Every trainer and item" sweeps are
-- read from the map data (data/gen3_frlg.lua) and noted as this mod's
-- reading of the area.
-- ==================================================================

return function(L)
  local out = {}
  local function add(r) out[#out + 1] = r end
  local RIVAL = L.rival

  -- ------------------------------------------------ story: rival
  add(L.anyFlag("g3o_rival_lab", { firered = 33592, leafgreen = 34776 }, "Rival: Oak's Lab",
    { "FLAG_BEAT_RIVAL_IN_OAKS_LAB", "TRAINER_RIVAL_OAKS_LAB_SQUIRTLE",
      "TRAINER_RIVAL_OAKS_LAB_BULBASAUR", "TRAINER_RIVAL_OAKS_LAB_CHARMANDER" }, { category = "RIVAL" }))
  add(L.anyFlag("g3o_rival_route22", { firered = 33593, leafgreen = 34777 }, "Rival: Route 22",
    RIVAL("TRAINER_RIVAL_ROUTE22_EARLY"), { category = "RIVAL" }))
  add(L.anyFlag("g3o_rival_cerulean", { firered = 33594, leafgreen = 34778 }, "Rival: Cerulean City",
    RIVAL("TRAINER_RIVAL_CERULEAN"), { category = "RIVAL" }))
  add(L.anyFlag("g3o_rival_ssanne", { firered = 33595, leafgreen = 34779 }, "Rival: S.S. Anne",
    RIVAL("TRAINER_RIVAL_SS_ANNE"), { category = "RIVAL" }))
  add(L.anyFlag("g3o_rival_tower", { firered = 33596, leafgreen = 34780 }, "Rival: Pokemon Tower",
    RIVAL("TRAINER_RIVAL_POKEMON_TOWER"), { category = "RIVAL" }))
  add(L.anyFlag("g3o_rival_silph", { firered = 33597, leafgreen = 34781 }, "Rival: Silph Co.",
    RIVAL("TRAINER_RIVAL_SILPH"), { category = "RIVAL" }))
  add(L.anyFlag("g3o_rival_route22_late", { firered = 33598, leafgreen = 34782 }, "Rival: Road to the League",
    RIVAL("TRAINER_RIVAL_ROUTE22_LATE"), { category = "RIVAL" }))

  -- ------------------------------------------------ gyms
  local GYMS = {
    { "Brock", { firered = 33601, leafgreen = 34785 } },
    { "Misty", { firered = 33602, leafgreen = 34786 } },
    { "Lt. Surge", { firered = 33603, leafgreen = 34787 } },
    { "Erika", { firered = 33604, leafgreen = 34788 } },
    { "Koga", { firered = 33605, leafgreen = 34789 } },
    { "Sabrina", { firered = 33606, leafgreen = 34790 } },
    { "Blaine", { firered = 33607, leafgreen = 34791 } },
    { "Giovanni", { firered = 33608, leafgreen = 34792 } },
  }
  for i, g in ipairs(GYMS) do
    add(L.badge("g3o_badge" .. i, g[2], "Badge: " .. g[1], i))
  end

  -- FireRed: Challenge rules (RA's "Set mode"): SET battle style, at most N
  -- Pokemon, none above the level cap.
  local LEADERS = {
    { "TRAINER_LEADER_BROCK", 195143, 2, 14 },
    { "TRAINER_LEADER_MISTY", 195146, 2, 21 },
    { "TRAINER_LEADER_LT_SURGE", 195147, 3, 24 },
    { "TRAINER_LEADER_ERIKA", 195153, 3, 29 },
    { "TRAINER_LEADER_KOGA", 195157, 4, 43 },
    { "TRAINER_LEADER_SABRINA", 195159, 4, 43 },
    { "TRAINER_LEADER_BLAINE", 195160, 4, 47 },
    { "TRAINER_LEADER_GIOVANNI", 195161, 5, 50 },
  }
  for i, c in ipairs(LEADERS) do
    local who = GYMS[i][1]
    add(L.beatTrainer("g3o_challenge" .. i, { firered = c[2] }, "Challenge: " .. who, c[1],
      L.setCap(c[3], c[4]), {
        category = "CHALLENGE",
        note = ("%s, then beat %s with %d or fewer Pokemon in your party, none above level %d."):format(
          L.CHALLENGE, who, c[3], c[4]),
      }))
  end

  -- LeafGreen: every gym trainer, before the leader
  local GYM_SWEEPS = {
    { 1, 541904, "Pewter Gym trainer", "FLAG_DEFEATED_BROCK" },
    { 2, 541907, "Cerulean Gym trainers", "FLAG_DEFEATED_MISTY" },
    { 3, 541916, "Vermilion Gym trainers", "FLAG_DEFEATED_LT_SURGE" },
    { 4, 541924, "Celadon Gym trainers", "FLAG_DEFEATED_ERIKA" },
    { 5, 541944, "Fuchsia Gym trainers", "FLAG_DEFEATED_KOGA" },
    { 6, 541955, "Saffron Gym trainers", "FLAG_DEFEATED_SABRINA" },
    { 7, 541957, "Cinnabar Gym trainers", "FLAG_DEFEATED_BLAINE" },
    { 8, 541958, "Viridian Gym trainers", "FLAG_DEFEATED_LEADER_GIOVANNI" },
  }
  for _, g in ipairs(GYM_SWEEPS) do
    add(L.gymTrainers("g3o_gymtrainers" .. g[1], { leafgreen = g[2] }, g[3], g[1], g[4], {
      note = "Beat them before the Gym Leader: once the leader falls, the game marks the rest as beaten.",
    }))
  end

  -- ------------------------------------------------ Team Rocket and the islands
  add(L.flag("g3o_rocket_celadon", { firered = 33599, leafgreen = 34783 }, "Rocket Hideout",
    "TRAINER_BOSS_GIOVANNI", { category = "STORY" }))
  add(L.flag("g3o_rocket_silph", { firered = 33600, leafgreen = 34784 }, "Silph Co.",
    "TRAINER_BOSS_GIOVANNI_2", { category = "STORY" }))
  add(L.flag("g3o_lostelle", { firered = 33626, leafgreen = 34810 }, "Lostelle Rescued",
    "FLAG_RESCUED_LOSTELLE", { category = "STORY" }))
  add(L.var("g3o_lorelei", { firered = 33627, leafgreen = 34811 }, "Icefall Cave",
    "VAR_MAP_SCENE_ICEFALL_CAVE_BACK", 1, { category = "STORY" }))
  add(L.flag("g3o_selphy", { firered = 33628, leafgreen = 34812 }, "Selphy Rescued",
    "FLAG_HIDE_LOST_CAVE_SELPHY", { category = "STORY" }))
  add(L.flag("g3o_warehouse", { firered = 33629, leafgreen = 34813 }, "Rocket Warehouse",
    "FLAG_DEFEATED_ROCKETS_IN_WAREHOUSE", { category = "STORY" }))

  -- ------------------------------------------------ the League
  add(L.anyFlag("g3o_champion", { firered = 33613, leafgreen = 34797 }, "Champion",
    { "TRAINER_CHAMPION_FIRST_SQUIRTLE", "TRAINER_CHAMPION_FIRST_BULBASAUR",
      "TRAINER_CHAMPION_FIRST_CHARMANDER", "FLAG_SYS_GAME_CLEAR" }, { category = "LEAGUE" }))
  add(L.anyFlag("g3o_champion2", { firered = 33618, leafgreen = 34802 }, "Champion Again",
    RIVAL("TRAINER_CHAMPION_REMATCH"), { category = "LEAGUE" }))
  local function solo(f) return L.partyCount(f.party()) == 1 and #f.party() == 1 end
  add(L.leagueRun("g3o_solo1", { firered = 195162 }, "Solo League",
    { "TRAINER_ELITE_FOUR_LORELEI", "TRAINER_ELITE_FOUR_BRUNO", "TRAINER_ELITE_FOUR_AGATHA",
      "TRAINER_ELITE_FOUR_LANCE" }, RIVAL("TRAINER_CHAMPION_FIRST"), solo,
    { note = "One Pokemon in your party for every battle from Lorelei to the Champion." }))
  add(L.leagueRun("g3o_solo2", { firered = 195166 }, "Solo League Rematch",
    { "TRAINER_ELITE_FOUR_LORELEI_2", "TRAINER_ELITE_FOUR_BRUNO_2", "TRAINER_ELITE_FOUR_AGATHA_2",
      "TRAINER_ELITE_FOUR_LANCE_2" }, RIVAL("TRAINER_CHAMPION_REMATCH"), solo,
    { note = "One Pokemon in your party for every battle of the second League." }))

  -- ------------------------------------------------ Trainer Tower
  local TT = { { 0, 33630, 34814, "Single" }, { 1, 33631, 34815, "Double" },
               { 2, 33632, 34816, "Knockout" }, { 3, 33633, 34817, "Mixed" } }
  for _, t in ipairs(TT) do
    add(L.state("g3o_tower_" .. t[4]:lower(), { firered = t[2], leafgreen = t[3] },
      "Trainer Tower: " .. t[4], function(f) return f.trainerTowerCleared(t[1]) end,
      { category = "TOWER" }))
  end

  -- ------------------------------------------------ catches
  add(L.owns("g3o_mewtwo", { firered = 33623, leafgreen = 34807 }, "Mewtwo", "MEWTWO"))
  add(L.owns("g3o_chansey", { firered = 33619, leafgreen = 34803 }, "Chansey", "CHANSEY"))
  add(L.owns("g3o_articuno", { firered = 33622, leafgreen = 34806 }, "Articuno", "ARTICUNO"))
  add(L.owns("g3o_zapdos", { firered = 33621, leafgreen = 34805 }, "Zapdos", "ZAPDOS"))
  add(L.owns("g3o_moltres", { firered = 33620, leafgreen = 34804 }, "Moltres", "MOLTRES"))
  add(L.ownsAny("g3o_beasts", { firered = 33624, leafgreen = 34808 }, "Legendary Beast",
    { "RAIKOU", "ENTEI", "SUICUNE" }))
  add(L.owns("g3o_snorlax", { firered = 195154, leafgreen = 541932 }, "Snorlax", "SNORLAX"))
  add(L.dexAtLeast("g3o_dex_fr", { firered = 33625 }, "FireRed Pokedex", 170,
    { fidelity = "interpretation", note = "Counted as 170 Pokemon marked caught in your Pokedex." }))
  add(L.dexAtLeast("g3o_dex_lg", { leafgreen = 34809 }, "LeafGreen Pokedex", 171,
    { fidelity = "interpretation", note = "Counted as 171 Pokemon marked caught in your Pokedex." }))

  -- ------------------------------------------------ gifts, finds and trades (both games)
  local BOTH = {
    { "magikarp", 195144, 541905, "Magikarp Salesman", "FLAG_BOUGHT_MAGIKARP" },
    { "fossil", 195145, 541906, "Mt. Moon Fossil", "FLAG_GOT_FOSSIL_FROM_MT_MOON" },
    { "amber", 195151, 541918, "Old Amber", "FLAG_GOT_OLD_AMBER" },
    { "eevee", 195152, 541921, "Eevee", "FLAG_GOT_EEVEE" },
    { "lapras", 195158, 541959, "Lapras", "FLAG_GOT_LAPRAS_FROM_SILPH" },
    { "egg", 195167, 541981, "Water Labyrinth Egg", "FLAG_GOT_TOGEPI_EGG" },
    { "farfetchd", 195148, 541911, "Trade: Farfetch'd", "FLAG_DID_CH_DING_TRADE" },
    { "mrmime", 195150, 541912, "Trade: Mr. Mime", "FLAG_DID_MIMIEN_TRADE" },
    { "jynx", 195169, 541966, "Trade: Jynx", "FLAG_DID_ZYNX_TRADE" },
    { "lickitung", 195163, 541967, "Trade: Lickitung", "FLAG_DID_MARC_TRADE" },
  }
  for _, g in ipairs(BOTH) do
    add(L.flag("g3o_" .. g[1], { firered = g[2], leafgreen = g[3] }, g[4], g[5], { category = "EVENTS" }))
  end
  local FR_ONLY = {
    { "nidoran", 195149, "Trade: Nidoran", "FLAG_DID_MS_NIDO_TRADE" },
    { "nidorina", 195155, "Trade: Nidorina", "FLAG_DID_NINA_TRADE" },
    { "tangela", 195164, "Trade: Tangela", "FLAG_DID_TANGENY_TRADE" },
    { "electrode", 195165, "Trade: Electrode", "FLAG_DID_ESPHERE_TRADE" },
    { "seel", 195168, "Trade: Seel", "FLAG_DID_SEELOR_TRADE" },
    { "karate", 195156, "Karate Master", "TRAINER_BLACK_BELT_KOICHI" },
  }
  for _, g in ipairs(FR_ONLY) do
    add(L.flag("g3o_" .. g[1], { firered = g[2] }, g[3], g[4], { category = "EVENTS" }))
  end

  -- ------------------------------------------------ LeafGreen: items and errands
  local LG = {
    { "pokedex", 541899, "Pokedex", "FLAG_SYS_POKEDEX_GET" },
    { "potion", 541901, "Free Potion", "FLAG_GOT_POTION_ON_ROUTE_1" },
    { "sspass", 541908, "S.S. Ticket", "FLAG_GOT_SS_TICKET" },
    { "oldrod", 541909, "Old Rod", "FLAG_GOT_OLD_ROD" },
    { "voucher", 541910, "Bike Voucher", "FLAG_GOT_BIKE_VOUCHER" },
    { "bicycle", 541913, "Bicycle", "FLAG_GOT_BICYCLE" },
    { "coincase", 541922, "Coin Case", "FLAG_GOT_COIN_CASE" },
    { "pokeflute", 541931, "Poke Flute", "FLAG_GOT_POKE_FLUTE" },
    { "flash", 541917, "HM05 Flash", "FLAG_GOT_HM05" },
    { "everstone", 541920, "Everstone", "FLAG_GOT_EVERSTONE_FROM_OAKS_AIDE" },
    { "fly", 541925, "HM02 Fly", "FLAG_GOT_HM02" },
    { "vsseeker", 541927, "VS Seeker", "FLAG_GOT_VS_SEEKER" },
    { "powderjar", 541928, "Powder Jar", "FLAG_GOT_POWDER_JAR" },
    { "itemfinder", 541934, "Itemfinder", "FLAG_GOT_ITEMFINDER" },
    { "soothebell", 541936, "Soothe Bell", "FLAG_HIDDEN_ITEM_POKEMON_TOWER_7F_SOOTHE_BELL" },
    { "goodrod", 541940, "Good Rod", "FLAG_GOT_GOOD_ROD" },
    { "amuletcoin", 541941, "Amulet Coin", "FLAG_GOT_AMULET_COIN_FROM_OAKS_AIDE" },
    { "superrod", 541942, "Super Rod", "FLAG_GOT_SUPER_ROD" },
    { "expshare", 541943, "Exp. Share", "FLAG_GOT_EXP_SHARE_FROM_OAKS_AIDE" },
    { "machobrace", 541961, "Macho Brace", "FLAG_HIDDEN_ITEM_VIRIDIAN_CITY_GYM_MACHO_BRACE" },
    { "magikarprecord", 541962, "Record Magikarp", "FLAG_GOT_RECORD_SETTING_MAGIKARP" },
    { "rocksmash", 541969, "HM06 Rock Smash", "FLAG_GOT_HM06" },
    { "ppmax", 541970, "Cape Brink PP Max", "FLAG_HIDDEN_ITEM_TWO_ISLAND_CAPE_BRINK_PP_MAX" },
    { "nugget", 541974, "Three Isle Path Nugget", "FLAG_GOT_NUGGET_FROM_DUNSPARCE_TUNNEL" },
    { "waterfall", 541977, "HM07 Waterfall", "FLAG_HIDE_FOUR_ISLAND_ICEFALL_CAVE_1F_HM07" },
    { "heracross", 541982, "Record Heracross", "FLAG_GOT_NEST_BALL_FROM_WATER_PATH_HOUSE_1" },
    { "secretkey", 541956, "Secret Key", "FLAG_HIDE_POKEMON_MANSION_B1F_SECRET_KEY" },
    { "national", 541973, "National Pokedex", "FLAG_SYS_NATIONAL_DEX" },
    { "ruby", 541975, "Ruby", "FLAG_GOT_RUBY" },
    { "celio", 541984, "Celio's Machine", "FLAG_SYS_CAN_LINK_WITH_RS" },
    { "sapphire", 541991, "Dotted Hole Sapphire", "FLAG_LEARNED_YES_NAH_CHANSEY" },
    { "mysterygift", 541903, "Mystery Gift", "FLAG_SYS_MYSTERY_GIFT_ENABLED" },
  }
  for _, g in ipairs(LG) do
    add(L.flag("g3o_" .. g[1], { leafgreen = g[2] }, g[3], g[4], { category = "EVENTS" }))
  end
  add(L.hasItem("g3o_townmap", { leafgreen = 541900 }, "Town Map", "TOWN_MAP", { category = "EVENTS" }))
  add(L.hasItem("g3o_teachytv", { leafgreen = 541902 }, "Teachy TV", "TEACHY_TV", { category = "EVENTS" }))
  add(L.var("g3o_tea", { leafgreen = 541926 }, "Tea for the Guards",
    "VAR_MAP_SCENE_ROUTE5_ROUTE6_ROUTE7_ROUTE8_GATES", 1, { category = "EVENTS" }))
  add(L.allFlags("g3o_surfstrength", { leafgreen = 541933 }, "Surf and Strength",
    { "FLAG_GOT_HM03", "FLAG_GOT_HM04" }, { category = "EVENTS" }))
  add(L.allFlags("g3o_leftovers", { leafgreen = 541935 }, "Hidden Leftovers",
    { "FLAG_HIDDEN_ITEM_ROUTE12_LEFTOVERS", "FLAG_HIDDEN_ITEM_ROUTE16_LEFTOVERS" }, { category = "EVENTS" }))
  add(L.allFlags("g3o_cinnabartrades", { leafgreen = 541964 }, "Cinnabar Trades",
    { "FLAG_DID_ESPHERE_TRADE", "FLAG_DID_TANGENY_TRADE", "FLAG_DID_SEELOR_TRADE" }, { category = "EVENTS" }))
  add(L.allFlags("g3o_nidoswap", { leafgreen = 541965 }, "Nido Trades",
    { "FLAG_DID_MS_NIDO_TRADE", "FLAG_DID_NINA_TRADE" }, { category = "EVENTS" }))
  add(L.allFlags("g3o_thirsty", { leafgreen = 541990 }, "Thirsty Girl's TMs",
    { "FLAG_GOT_TM16_FROM_THIRSTY_GIRL", "FLAG_GOT_TM20_FROM_THIRSTY_GIRL",
      "FLAG_GOT_TM33_FROM_THIRSTY_GIRL" }, { category = "EVENTS" }))
  add(L.state("g3o_coins", { leafgreen = 541923 }, "Game Corner Handouts", function(f)
    local gifts = { "FLAG_GOT_10_COINS_FROM_GAMBLER", "FLAG_GOT_20_COINS_FROM_GAMBLER",
                    "FLAG_GOT_20_COINS_FROM_GAMBLER_2" }
    local done, total = f.sweep("hidden", function(row) return row[#row - 1] == "CeladonCity_GameCorner" end)
    done, total = done + f.countFlags(gifts), total + #gifts
    return done >= total or done
  end, { category = "EVENTS", goal = 15 }))
  add(L.state("g3o_dojo", { leafgreen = 541954 }, "Dojo Beatdown", function(f)
    if not f.flag("FLAG_GOT_HITMON_FROM_DOJO") then return false end
    local done, total = f.sweep("trainers", function(row) return row[#row - 1] == "SaffronCity_Dojo" end)
    return total > 0 and done >= total
  end, { category = "EVENTS" }))
  add(L.state("g3o_slots", { leafgreen = 541989 }, "Triple 7s", function(f)
    return f.gameStat(28) > 0 -- GAME_STAT_SLOT_JACKPOTS
  end, { category = "EVENTS" }))
  add(L.state("g3o_cardicons", { leafgreen = 541986 }, "Trainer Card Icons", function(f)
    for _, v in ipairs({ "VAR_TRAINER_CARD_MON_ICON_1", "VAR_TRAINER_CARD_MON_ICON_2",
        "VAR_TRAINER_CARD_MON_ICON_3", "VAR_TRAINER_CARD_MON_ICON_4",
        "VAR_TRAINER_CARD_MON_ICON_5", "VAR_TRAINER_CARD_MON_ICON_6" }) do
      if f.var(v) > 0 then return true end
    end
    return false
  end, { category = "EVENTS" }))
  -- Selphy asks for a Pokemon (VAR_RESORT_GORGEOUS_REQUESTED_MON); the
  -- request is cleared when her butler hands over the reward.
  add(L.tracker("g3o_selphywish", { leafgreen = 541983 }, "Selphy's Wish", {
    tick = function(s, _, f)
      local v = f.var("VAR_RESORT_GORGEOUS_REQUESTED_MON")
      local done = (s.prev or 0) > 0 and s.prev ~= 0xFFFF and v == 0
      s.prev = v
      return done or nil
    end,
  }, nil, { category = "EVENTS", fidelity = "interpretation",
            note = "Counted when Selphy's request is cleared after you show her the Pokemon." }))
  add(L.state("g3o_fame", { leafgreen = 541985 }, "Fame Checker", function(f)
    local n = f.fameCheckerFull()
    return n >= 16 or n
  end, { category = "COMPLETION", goal = 16, unit = "PEOPLE" }))
  add(L.state("g3o_tutors", { leafgreen = 541988 }, "Move Tutors", function(f)
    local list = { "FLAG_TUTOR_MEGA_PUNCH", "FLAG_TUTOR_SWORDS_DANCE", "FLAG_TUTOR_MEGA_KICK",
      "FLAG_TUTOR_BODY_SLAM", "FLAG_TUTOR_DOUBLE_EDGE", "FLAG_TUTOR_COUNTER",
      "FLAG_TUTOR_SEISMIC_TOSS", "FLAG_TUTOR_MIMIC", "FLAG_TUTOR_METRONOME",
      "FLAG_TUTOR_SOFT_BOILED", "FLAG_TUTOR_DREAM_EATER", "FLAG_TUTOR_THUNDER_WAVE",
      "FLAG_TUTOR_EXPLOSION", "FLAG_TUTOR_ROCK_SLIDE", "FLAG_TUTOR_SUBSTITUTE" }
    local n = f.countFlags(list)
    local cape = f.anyFlag({ "FLAG_TUTOR_FRENZY_PLANT", "FLAG_TUTOR_BLAST_BURN", "FLAG_TUTOR_HYDRO_CANNON" })
    if n >= #list and cape then return true end
    return n + (cape and 1 or 0)
  end, { category = "COMPLETION", goal = 16, unit = "TUTORS", fidelity = "interpretation",
         note = "The 15 one-time tutors plus one of the ultimate moves at Cape Brink." }))
  add(L.state("g3o_vsmaster", { leafgreen = 541992 }, "VS Seeker Master", function(f)
    local done, total = f.sweep("rematches")
    if total == 0 then return false end
    return done >= total or math.floor(done * 100 / total)
  end, { category = "COMPLETION", goal = 100, unit = "PCT", fidelity = "interpretation",
         note = "Each VS Seeker trainer's strongest team beaten." }))

  -- ------------------------------------------------ LeafGreen: areas swept
  local MUSHROOMS = { TINY_MUSHROOM = true, BIG_MUSHROOM = true }
  local AREAS = {
    { "mtmoon", 541937, "Mt. Moon", { maps = { "MtMoon" }, noItem = MUSHROOMS } },
    { "ssanne", 541915, "S.S. Anne", { maps = { "SSAnne" } } },
    { "hideout", 541929, "Rocket Hideout", { maps = { "RocketHideout" } } },
    { "tower", 541930, "Pokemon Tower", { maps = { "PokemonTower" } } },
    { "silph", 541953, "Silph Co.", { maps = { "SilphCo" } } },
    { "forest", 541914, "Viridian Forest", { maps = { "ViridianForest" }, kinds = { "trainers", "items" } } },
    { "rocktunnel", 541919, "Rock Tunnel", { maps = { "RockTunnel" } } },
    { "early", 541938, "Early-Game Sweep", { maps = { "Route2", "Route3", "Route4", "ViridianCity",
      "PewterCity", "CeruleanCity" } } },
    { "cape", 541939, "Routes 24 and 25", { maps = { "Route24", "Route25" } } },
    { "safari", 541945, "Safari Zone Items", { maps = { "SafariZone" }, kinds = { "items", "hidden" } } },
    { "routes910", 541946, "Routes 9 and 10", { maps = { "Route9", "Route10" } } },
    { "powerplant", 541947, "Power Plant Items", { maps = { "PowerPlant" }, kinds = { "items", "hidden" } } },
    { "hub", 541948, "Kanto's Central Hub", { maps = { "Route6", "Route7", "Route8", "SaffronCity",
      "VermilionCity" } } },
    { "fuchsia", 541949, "Routes 11 to 15", { maps = { "Route11", "Route12", "Route13", "Route14",
      "Route15", "FuchsiaCity" } } },
    { "waters", 541950, "Routes 19 to 21", { maps = { "Route19", "Route20", "Route21" } } },
    { "seafoam", 541951, "Seafoam Islands Items", { maps = { "SeafoamIslands" }, kinds = { "items", "hidden" } } },
    { "mansion", 541952, "Pokemon Mansion", { maps = { "PokemonMansion" } } },
    { "cycling", 541960, "Cycling Road", { maps = { "Route16", "Route17", "Route18", "CeladonCity" },
      skip = { "CeladonCity_GameCorner" } } },
    { "victory", 541963, "Route 23 and Victory Road", { maps = { "Route23", "VictoryRoad" } } },
    { "ember", 541968, "Kindle Road and Mt. Ember", { maps = { "OneIsland_KindleRoad", "MtEmber" } } },
    { "capeforest", 541971, "Two and Three Island", { maps = { "TwoIsland", "ThreeIsland" },
      skip = { "ThreeIsland_DunsparceTunnel", "ThreeIsland_Port" } } },
    { "berries", 541972, "Berry Forest Berries", { maps = { "ThreeIsland_BerryForest" }, kinds = { "hidden" } } },
    { "icefall", 541976, "Four Island Items", { maps = { "FourIsland" }, kinds = { "items", "hidden" } } },
    { "five", 541978, "Five Island Region", { maps = { "FiveIsland" } } },
    { "six", 541979, "Six Island Region", { maps = { "SixIsland" } } },
    { "seven", 541980, "Seven Island Region", { maps = { "SevenIsland" } } },
    { "cave", 541987, "Cerulean Cave Items", { maps = { "CeruleanCave" }, kinds = { "items", "hidden" } } },
  }
  for _, a in ipairs(AREAS) do
    local maps = {}
    for _, m in ipairs(a[4].maps) do maps[#maps + 1] = m end
    add(L.area("g3o_area_" .. a[1], { leafgreen = a[2] }, a[3], a[4], {
      note = "Counted over these maps (gyms and rival battles aside): " .. table.concat(maps, ", ") .. ".",
    }))
  end

  return out
end
