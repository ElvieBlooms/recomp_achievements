-- rules/gen2_official.lua
-- ==================================================================
-- One detector per entry in the RetroAchievements lists for Pokemon
-- Gold (game 576), Silver (722) and Crystal (810), written from scratch
-- against Gen1Recomp's Gen 2 state.  No RetroAchievements trigger logic is
-- used.  `ra` links each rule to the entries it answers; one rule serves
-- several games when the goal is the same.
--
-- Rules marked `fidelity = "interpretation"` are a close local reading
-- of the RA wording; their `note` says exactly what counts here.  Entries
-- this mod can't judge yet have no rule; they show in the RA REFERENCE
-- view as "not tracked yet" and don't count toward totals.
-- ==================================================================

return function(L)
  local rules = {}
  local function add(r) rules[#rules + 1] = r end
  local function interp(note, extra)
    local e = { fidelity = "interpretation", note = note }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
  end

  -- ------------------------------------------------------------ story
  add(L.state("g2o_rival_name", { gold = 5086, silver = 5113, crystal = 5636 }, "Rival named",
    function(f) return f.rivalNamed() end, { category = "STORY" }))
  add(L.flag("g2o_slowpoke_well", { gold = 5092, silver = 5118, crystal = 5934 }, "Slowpoke Well",
    "EVENT_CLEARED_SLOWPOKE_WELL", { category = "STORY" }))
  add(L.flag("g2o_rocket_hideout", { gold = 5093, silver = 5119, crystal = 5946 }, "Rocket hideout",
    "EVENT_CLEARED_ROCKET_HIDEOUT", { category = "STORY" }))
  add(L.flag("g2o_radio_tower", { gold = 5497, silver = 5498, crystal = 5947 }, "Radio Tower",
    "EVENT_CLEARED_RADIO_TOWER", { category = "STORY" }))
  add(L.state("g2o_elite_four", { gold = 5509, silver = 5520, crystal = 5949 }, "Elite Four",
    function(f) return f.flag("EVENT_BEAT_CHAMPION_LANCE") or f.hallOfFame() > 0 end, { category = "LEAGUE" }))

  -- ------------------------------------------------------------ badges
  local GYMS = {
    -- badge, trainer class, RA ids (plain badge), set-mode cap
    { "ZEPHYR",  "FALKNER",  { gold = 5070, silver = 5097, crystal = 5637 }, 9 },
    { "HIVE",    "BUGSY",    { gold = 5071, silver = 5098, crystal = 5638 }, 16 },
    { "PLAIN",   "WHITNEY",  { gold = 5072, silver = 5099, crystal = 5639 }, 20 },
    { "FOG",     "MORTY",    { gold = 5073, silver = 5100, crystal = 5640 }, 25 },
    { "STORM",   "CHUCK",    { gold = 5074, silver = 5101, crystal = 5641 }, 30 },
    { "MINERAL", "JASMINE",  { gold = 5075, silver = 5102, crystal = 5642 }, 35 },
    { "GLACIER", "PRYCE",    { gold = 5076, silver = 5103, crystal = 5643 }, 31 },
    { "RISING",  "CLAIR",    { gold = 5077, silver = 5104, crystal = 5644 }, 40 },
    { "BOULDER", "BROCK",    { gold = 5078, silver = 5105, crystal = 5645 }, 44 },
    { "CASCADE", "MISTY",    { gold = 5079, silver = 5106, crystal = 5646 }, 47 },
    { "THUNDER", "LT_SURGE", { gold = 5080, silver = 5107, crystal = 5647 }, 46 },
    { "RAINBOW", "ERIKA",    { gold = 5081, silver = 5108, crystal = 5648 }, 46 },
    { "SOUL",    "JANINE",   { gold = 5082, silver = 5109, crystal = 5649 }, 39 },
    { "MARSH",   "SABRINA",  { gold = 5083, silver = 5110, crystal = 5650 }, 48 },
    { "VOLCANO", "BLAINE",   { gold = 5084, silver = 5111, crystal = 5651 }, 50 },
    { "EARTH",   "BLUE",     { gold = 5085, silver = 5112, crystal = 5652 }, 58 },
  }
  -- Challenge rules, which RA calls "Set Mode" (the SET battle style):
  -- Gold/Silver "[Set Mode, <= Lv.N]" and Silver's type-only versions,
  -- Crystal's "Set battle style, Johto Pokemon only, no Pack items".
  local SET_MODE = {
    FALKNER = { gold = 155162, silver = 163143 }, BUGSY = { gold = 155163, silver = 163145 },
    WHITNEY = { gold = 155168, silver = 163147 }, MORTY = { gold = 155170, silver = 163149 },
    CHUCK = { gold = 155173, silver = 163153 }, JASMINE = { gold = 155174, silver = 163151 },
    PRYCE = { gold = 155175, silver = 163155 }, CLAIR = { gold = 155176, silver = 163157 },
    LT_SURGE = { gold = 155181, silver = 163165 }, SABRINA = { gold = 155182, silver = 163164 },
    ERIKA = { gold = 155183, silver = 163173 }, JANINE = { gold = 155184, silver = 163171 },
    MISTY = { gold = 155187, silver = 163167 }, BROCK = { gold = 155190, silver = 163169 },
    BLAINE = { gold = 155191, silver = 163175 }, BLUE = { gold = 155192, silver = 163188 },
  }
  local TYPE_ONLY = {
    FALKNER = { 163144, { "FLYING" } }, BUGSY = { 163146, { "BUG" } },
    WHITNEY = { 163148, { "NORMAL" } }, MORTY = { 163150, { "GHOST", "DARK" } },
    CHUCK = { 163154, { "FIGHTING" } }, JASMINE = { 163152, { "STEEL" } },
    PRYCE = { 163156, { "ICE" } }, CLAIR = { 163158, { "DRAGON" } },
    BROCK = { 163170, { "ROCK" } }, MISTY = { 163168, { "WATER" } },
    LT_SURGE = { 163166, { "ELECTRIC" } }, ERIKA = { 163174, { "GRASS" } },
    JANINE = { 163172, { "POISON" } }, SABRINA = { 163163, { "PSYCHIC_TYPE" } },
    BLAINE = { 163176, { "FIRE" } },
  }
  local JOHTO_ONLY = {
    FALKNER = { 199603 }, BUGSY = { 199604 }, WHITNEY = { 199605 }, MORTY = { 199606 },
    CHUCK = { 199607 }, JASMINE = { 199608 }, PRYCE = { 199609 },
    CLAIR = { 199610, L.LEGENDARY_EXCEPT_BEASTS }, LT_SURGE = { 199612, L.LEGENDARY_EXCEPT_BEASTS },
    SABRINA = { 199613, L.LEGENDARY_EXCEPT_BEASTS }, MISTY = { 199614, L.LUGIA_HOOH },
    ERIKA = { 199615, L.LUGIA_HOOH }, JANINE = { 199616, L.LUGIA_HOOH },
    BROCK = { 199632, L.LUGIA_HOOH }, BLAINE = { 199617, L.LUGIA_HOOH }, BLUE = { 199618, L.LUGIA_HOOH },
  }
  for _, g in ipairs(GYMS) do
    local badge, who, ids, cap = g[1], g[2], g[3], g[4]
    local slug = badge:lower()
    add(L.badge("g2o_badge_" .. slug, ids, badge:sub(1, 1) .. badge:sub(2):lower() .. " Badge", badge))
    if SET_MODE[who] then
      add(L.beatTrainer("g2o_set_" .. slug, SET_MODE[who], "Challenge: " .. L.prettyName(who), who, L.setCap(cap),
        { category = "CHALLENGE", note = L.CHALLENGE .. " and have no Pokemon above Lv." .. cap .. " at the start or end of the battle." }))
    end
    if TYPE_ONLY[who] then
      local t = TYPE_ONLY[who]
      add(L.beatTrainer("g2o_type_" .. slug, { silver = t[1] }, "Type challenge: " .. L.prettyName(who), who,
        L.all(L.setCap(cap), L.onlyTypes(t[2])),
        { category = "CHALLENGE", note = L.CHALLENGE .. ", have no Pokemon above Lv." .. cap
          .. ", and send out only " .. table.concat(t[2], "/"):gsub("PSYCHIC_TYPE", "PSYCHIC") .. "-type Pokemon." }))
    end
    if JOHTO_ONLY[who] then
      local j = JOHTO_ONLY[who]
      add(L.beatTrainer("g2o_johto_" .. slug, { crystal = j[1] }, "Johto challenge: " .. L.prettyName(who), who,
        L.johtoOnly(cap, j[2]),
        interp(L.CHALLENGE .. ", use no Pack items, have nobody above Lv." .. cap .. " at the start or end, "
          .. "and send out only Pokemon you can find in Johto (or evolved from one).", { category = "CHALLENGE" })))
    end
  end
  -- Silver: Blue with exactly Delibird, Corsola, Lickitung, Aipom, Farfetch'd, Onix
  local TERRIBLE = L.set({ "DELIBIRD", "CORSOLA", "LICKITUNG", "AIPOM", "FARFETCH_D", "ONIX" })
  add(L.beatTrainer("g2o_terrible_blue", { silver = 163187 }, "Challenge: a terrible team", "BLUE",
    function(b, f)
      if not L.setCap(58)(b, f) then return false end
      local party, seen = f.party(), {}
      if #party ~= 6 then return false end
      for _, m in ipairs(party) do
        if m.isEgg or not TERRIBLE[m.species] or seen[m.species] then return false end
        seen[m.species] = true
      end
      return true
    end, { category = "CHALLENGE", note = L.CHALLENGE .. ", have no Pokemon above Lv.58, and bring exactly "
      .. "Delibird, Corsola, Lickitung, Aipom, Farfetch'd and Onix." }))

  -- ------------------------------------------------------------ league and Red
  local function onePokemon(f) return L.partyCount(f) == 1 end
  add(L.leagueRun("g2o_five_chumps", { gold = 5511, silver = 5521, crystal = 5950 }, "League with one Pokemon",
    onePokemon, nil, interp("Every battle from Will to Lance in one run, with exactly one Pokemon in your party.")))
  add(L.leagueRun("g2o_heavenly_kings", { crystal = 199611 }, "Johto challenge: League",
    nil, L.johtoOnly(44, L.LUGIA_HOOH),
    interp("Will to Lance in one run. " .. L.CHALLENGE .. ", use no Pack items, have nobody above Lv.44, "
      .. "and send out only Johto Pokemon (no Lugia or Ho-Oh).")))
  add(L.beatTrainer("g2o_red", { gold = 5523, silver = 5525, crystal = 5958 }, "Defeat Red", "RED", nil,
    { category = "LEAGUE" }))
  add(L.beatTrainer("g2o_red_one", { gold = 5524, silver = 5526, crystal = 5959 }, "Red with one Pokemon", "RED",
    function(b, f) return #(b.partyAtStart or {}) == 1 end, { category = "LEAGUE" }))
  add(L.beatTrainer("g2o_red_johto", { crystal = 199619 }, "Johto challenge: Red", "RED",
    L.johtoOnly(65), interp(L.CHALLENGE .. ", use no Pack items, have nobody above Lv.65, and send out only "
      .. "Johto Pokemon.", { category = "CHALLENGE" })))

  -- ------------------------------------------------------------ legendaries
  add(L.ownsAll("g2o_beasts", { gold = 5087, silver = 5114 }, "Runaway Trio", { "ENTEI", "SUICUNE", "RAIKOU" }))
  add(L.owns("g2o_ho_oh", { gold = 5089, silver = 5116, crystal = 5953 }, "Ho-Oh", "HO_OH"))
  add(L.owns("g2o_lugia", { gold = 5088, silver = 5115, crystal = 5952 }, "Lugia", "LUGIA"))
  add(L.owns("g2o_suicune", { crystal = 5948 }, "Suicune", "SUICUNE"))
  add(L.ownsAll("g2o_brass_beasts", { crystal = 5951 }, "Entei and Raikou", { "ENTEI", "RAIKOU" }))
  add(L.caught("g2o_suicune_nomaster", { crystal = 199573 }, "Suicune, no Master Ball", "SUICUNE", "MASTER_BALL"))
  add(L.caught("g2o_raikou_nomaster", { crystal = 199574 }, "Raikou, no Master Ball", "RAIKOU", "MASTER_BALL"))
  add(L.caught("g2o_entei_nomaster", { crystal = 199575 }, "Entei, no Master Ball", "ENTEI", "MASTER_BALL"))
  add(L.caught("g2o_lugia_nomaster", { crystal = 199589 }, "Lugia, no Master Ball", "LUGIA", "MASTER_BALL"))
  add(L.caught("g2o_ho_oh_nomaster", { crystal = 199590 }, "Ho-Oh, no Master Ball", "HO_OH", "MASTER_BALL"))
  add(L.state("g2o_unown", { gold = 5091, silver = 5117, crystal = 5955 }, "All Unown",
    function(f) return f.unownForms() end, { goal = 26, unit = "FORMS", category = "POKEDEX" }))
  add(L.dexAtLeast("g2o_dex_gold", { gold = 5090 }, "Gotta catch 'em all", 199,
    interp("Register 199 Pokemon as caught, the same count RA gives for Silver.")))
  add(L.dexAtLeast("g2o_dex_silver", { silver = 5120 }, "Gotta catch 'em all", 199))
  add(L.dexAtLeast("g2o_dex_crystal", { crystal = 5954 }, "Gotta catch 'em all", 206))

  -- Snorlax, Sudowoodo, Lapras, red Gyarados
  add(L.state("g2o_snorlax", { gold = 155188, crystal = 199586 }, "Snorlax",
    function(f) return f.flag("EVENT_FOUGHT_SNORLAX") and f.owns("SNORLAX") end,
    interp("You've battled the Snorlax by Diglett's Cave and have Snorlax registered as caught.")))
  add(L.state("g2o_sudowoodo", { crystal = 199564 }, "Sudowoodo",
    function(f) return f.flag("EVENT_FOUGHT_SUDOWOODO") and f.owns("SUDOWOODO") end,
    interp("You've battled the Route 36 Sudowoodo and have Sudowoodo registered as caught.")))
  add(L.owns("g2o_lapras", { crystal = 199591 }, "Union Cave Lapras", "LAPRAS",
    interp("Lapras registered as caught (in Crystal it only comes from Union Cave).")))
  add(L.state("g2o_red_gyarados", { crystal = 199570 }, "Red Gyarados",
    function(f) return f.ownsWhere(function(m) return m.species == "GYARADOS" and m.shiny end) end,
    interp("You own a shiny Gyarados.")))

  -- ------------------------------------------------------------ gifts and trades
  add(L.flag("g2o_spearow", { gold = 155164 }, "Free Spearow", "EVENT_GOT_KENYA", { category = "GIFTS" }))
  add(L.flag("g2o_eevee", { gold = 155169 }, "Bill's Eevee", "EVENT_GOT_EEVEE", { category = "GIFTS" }))
  add(L.flag("g2o_shuckle", { gold = 155172 }, "Mania's Shuckle", "EVENT_GOT_SHUCKIE", { category = "GIFTS" }))
  add(L.flag("g2o_tyrogue", { gold = 155178 }, "Kiyo's Tyrogue", "EVENT_GOT_TYROGUE_FROM_KIYO", { category = "GIFTS" }))
  add(L.state("g2o_mystery_egg", { gold = 155167, silver = 163185 }, "Mystery Egg",
    function(f) return f.flag("EVENT_GOT_TOGEPI_EGG_FROM_ELMS_AIDE") and f.owns("TOGEPI") end,
    interp("You got the egg from Elm's aide and have Togepi registered as caught.", { category = "GIFTS" })))
  add(L.flag("g2o_everstone_elm", { crystal = 199582 }, "Everstone from Elm", "EVENT_GOT_EVERSTONE_FROM_ELM",
    { category = "GIFTS" }))
  add(L.flag("g2o_odd_egg", { crystal = 199561 }, "Odd Egg", "EVENT_GOT_ODD_EGG", { category = "GIFTS" }))
  add(L.state("g2o_dratini_quiz", { crystal = 199576 }, "Dragon Shrine quiz",
    function(f) return f.flag("EVENT_GOT_DRATINI") and not f.flag("EVENT_ANSWERED_DRAGON_MASTER_QUIZ_WRONG") end,
    { category = "GIFTS" }))
  add(L.allFlags("g2o_gift_mons", { crystal = 199565 }, "Every gift Pokemon",
    { "EVENT_GOT_KENYA", "EVENT_GOT_TOGEPI_EGG_FROM_ELMS_AIDE", "EVENT_GOT_SHUCKIE", "EVENT_GOT_EEVEE",
      "EVENT_GOT_TYROGUE_FROM_KIYO", "EVENT_GOT_DRATINI", "EVENT_GOT_ODD_EGG" },
    interp("Spearow, the Mystery Egg, Shuckle, Eevee, Tyrogue, Dratini and the Odd Egg.", { category = "GIFTS" })))

  -- in-game trades, by trade number (data/events/npc_trades.asm)
  local function trade(id, ra, title, n)
    add(L.state(id, ra, title, function(f) return f.traded(n) end, { category = "TRADES" }))
  end
  trade("g2o_trade_onix", { gold = 155165, silver = 163179 }, "Onix trade", 0)
  trade("g2o_trade_machop", { gold = 155166, silver = 163180 }, "Machop trade", 1)
  trade("g2o_trade_voltorb", { gold = 155171, silver = 163181 }, "Voltorb trade", 2)
  trade("g2o_trade_rhydon", { gold = 155177, silver = 163182 }, "Rhydon trade", 3)
  trade("g2o_trade_aerodactyl", { gold = 155195, silver = 163184 }, "Aerodactyl trade", 4)
  trade("g2o_trade_rapidash", { gold = 155189, silver = 163183 }, "Rapidash trade", 5)
  add(L.state("g2o_all_trades", { crystal = 199592 }, "Every in-game trade",
    function(f)
      local n = 0
      for i = 0, 6 do if f.traded(i) then n = n + 1 end end
      return n
    end, { goal = 7, unit = "TRADES", category = "TRADES" }))

  -- ------------------------------------------------------------ side quests
  add(L.state("g2o_haircut", { gold = 155179 }, "Haircut",
    function(f) return f.engineFlag("ENGINE_GOLDENROD_UNDERGROUND_GOT_HAIRCUT") end,
    interp("The Goldenrod Underground haircut is noted while today's haircut flag is set.")))
  add(L.state("g2o_kurt_ball", { gold = 155180 }, "Ball from Kurt",
    function(f)
      if f.flag("EVENT_KURT_GAVE_YOU_LURE_BALL") then return true end
      for _, b in ipairs({ "LEVEL_BALL", "LURE_BALL", "MOON_BALL", "FRIEND_BALL", "FAST_BALL", "HEAVY_BALL", "LOVE_BALL" }) do
        if f.hasItem(b) then return true end
      end
      return false
    end, interp("Kurt has given you his Lure Ball, or you hold any Apricorn ball.", { category = "SIDE" })))
  add(L.flagRises("g2o_machine_part", { gold = 155185 }, "Machine Part", "EVENT_FOUND_MACHINE_PART_IN_CERULEAN_GYM",
    function(f) return f.hasItem("MACHINE_PART") or f.flag("EVENT_RETURNED_MACHINE_PART") end,
    interp("Counted when you pick up the Machine Part in Cerulean Gym, or later from holding or returning it.",
      { category = "SIDE" })))
  add(L.flag("g2o_machine_part_return", { crystal = 199585 }, "Power restored", "EVENT_RETURNED_MACHINE_PART",
    { category = "SIDE" }))
  local GRANDPA = { "EVENT_SHOWED_LICKITUNG_TO_BILLS_GRANDPA", "EVENT_SHOWED_ODDISH_TO_BILLS_GRANDPA",
    "EVENT_SHOWED_STARYU_TO_BILLS_GRANDPA", "EVENT_SHOWED_GROWLITHE_VULPIX_TO_BILLS_GRANDPA",
    "EVENT_SHOWED_PICHU_TO_BILLS_GRANDPA" }
  add(L.allFlags("g2o_bills_grandpa", { gold = 155186, crystal = 199588 }, "Bill's grandpa", GRANDPA,
    { goal = 5, unit = "SHOWN", category = "SIDE" }))
  add(L.flag("g2o_mt_moon_rival", { gold = 155193 }, "Rival at Mt. Moon", "EVENT_BEAT_RIVAL_IN_MT_MOON",
    { category = "STORY" }))
  local SIBLINGS = { "EVENT_GOT_SHARP_BEAK_FROM_MONICA", "EVENT_GOT_PINK_BOW_FROM_TUSCANY",
    "EVENT_GOT_BLACKBELT_FROM_WESLEY", "EVENT_GOT_HARD_STONE_FROM_ARTHUR", "EVENT_GOT_POISON_BARB_FROM_FRIEDA",
    "EVENT_GOT_SPELL_TAG_FROM_SANTOS", "EVENT_GOT_MAGNET_FROM_SUNNY" }
  add(L.allFlags("g2o_week_siblings", { gold = 155194, crystal = 199559 }, "Week Siblings", SIBLINGS,
    { goal = 7, unit = "GIFTS", category = "SIDE" }))
  local DOLLS = { "EVENT_DECO_CHARMANDER_DOLL", "EVENT_DECO_CLEFAIRY_DOLL", "EVENT_DECO_PIKACHU_DOLL",
    "EVENT_DECO_BIG_SNORLAX_DOLL" }
  add(L.allFlags("g2o_mom_dolls", { silver = 163177, crystal = 199629 }, "Mom's dolls", DOLLS,
    interp("You own the four dolls Mom can buy: Charmander, Clefairy, Pikachu and the big Snorlax.",
      { goal = 4, unit = "DOLLS", category = "SIDE" })))
  add(L.state("g2o_phone_full", { silver = 163189 }, "Full phone",
    function(f) return f.phoneContacts() end, { goal = 10, unit = "NUMBERS", category = "SIDE" }))

  -- Crystal side quests
  add(L.flag("g2o_eusine_tower", { crystal = 199566 }, "Eusine in Burned Tower", "EVENT_RELEASED_THE_BEASTS",
    interp("The legendary beasts have been released in the Burned Tower, where Eusine's sidequest begins.", { category = "SIDE" })))
  add(L.flag("g2o_eusine_beat", { crystal = 199568 }, "Defeat Eusine", "EVENT_FOUGHT_EUSINE", { category = "SIDE" }))
  add(L.flag("g2o_amphy", { crystal = 199569 }, "Amphy cured", "EVENT_JASMINE_RETURNED_TO_GYM",
    interp("Jasmine has returned to her gym after you brought the SecretPotion.", { category = "STORY" })))
  local metSuicune = function(f) return f.flag("EVENT_FOUGHT_SUICUNE") or f.owns("SUICUNE") end
  add(L.flagRises("g2o_suicune_42", { crystal = 199594 }, "Suicune on Route 42", "EVENT_SAW_SUICUNE_ON_ROUTE_42",
    metSuicune, interp("Counted when Suicune runs off on Route 42; older saves count once you've battled Suicune.",
      { category = "STORY" })))
  add(L.flagRises("g2o_suicune_36", { crystal = 199595 }, "Suicune on Route 36", "EVENT_SAW_SUICUNE_ON_ROUTE_36",
    metSuicune, interp("Counted when Suicune runs off on Route 36; older saves count once you've battled Suicune.",
      { category = "STORY" })))
  add(L.flag("g2o_moomoo", { crystal = 199580 }, "Moomoo nursed", "EVENT_HEALED_MOOMOO", { category = "SIDE" }))
  add(L.state("g2o_shuckie_keep", { crystal = 199630 }, "Keep Shuckie",
    function(f)
      return f.flag("EVENT_MANIA_TOOK_SHUCKIE_OR_LET_YOU_KEEP_HIM")
        and f.ownsWhere(function(m) return m.species == "SHUCKLE" and tostring(m.ot or m.otName or ""):upper() == "MANIA" end)
    end, interp("Mania has made his decision and Shuckie (OT MANIA) is still yours.", { category = "SIDE" })))
  local PUZZLES = { "EVENT_SOLVED_KABUTO_PUZZLE", "EVENT_SOLVED_OMANYTE_PUZZLE",
    "EVENT_SOLVED_AERODACTYL_PUZZLE", "EVENT_SOLVED_HO_OH_PUZZLE" }
  add(L.state("g2o_ruins", { crystal = 199636 }, "Ruins of Alph",
    function(f)
      if not f.allFlags(PUZZLES) then return false end
      local inRuins = L.maps({ "RuinsOfAlph" })
      local d1, t1 = f.sweep("items", inRuins)
      local d2, t2 = f.sweep("hidden", inRuins)
      return d1 + d2 >= t1 + t2
    end, interp("All four chamber puzzles solved and every item ball and hidden item in the Ruins of Alph collected.",
      { category = "SIDE" })))
  add(L.state("g2o_red_scale", { crystal = 199578 }, "Red Scale traded",
    function(f) return f.hasItem("EXP_SHARE") or f.ownsWhere(function(m) return m.item == "EXP_SHARE" end) end,
    interp("You have the Exp. Share, which Mr. Pokemon trades for the Red Scale.", { category = "SIDE" })))
  add(L.flag("g2o_copycat_pass", { crystal = 199640 }, "Magnet Train Pass", "EVENT_GOT_PASS_FROM_COPYCAT",
    { category = "SIDE" }))
  add(L.state("g2o_rods", { crystal = 199639 }, "All three rods",
    function(f) return f.hasItem("OLD_ROD") and f.hasItem("GOOD_ROD") and f.hasItem("SUPER_ROD") end,
    { category = "SIDE" }))
  add(L.flag("g2o_moon_stone", { crystal = 199587 }, "Clefairy dance", "EVENT_MOUNT_MOON_SQUARE_HIDDEN_MOON_STONE",
    interp("You picked up the Moon Stone the Clefairy leave in Mt. Moon Square.", { category = "SIDE" })))
  add(L.anyFlag("g2o_phone_stone", { crystal = 199567 }, "Stone by phone",
    { "EVENT_ALAN_GAVE_FIRE_STONE", "EVENT_GINA_GAVE_LEAF_STONE", "EVENT_DANA_GAVE_THUNDERSTONE",
      "EVENT_TULLY_GAVE_WATER_STONE" }, { category = "SIDE" }))
  add(L.allFlags("g2o_rematch_vitamins", { crystal = 199602 }, "Rematch vitamins",
    { "EVENT_GOT_HP_UP_FROM_JOEY", "EVENT_GOT_PROTEIN_FROM_HUEY", "EVENT_GOT_CARBOS_FROM_VANCE",
      "EVENT_GOT_IRON_FROM_PARRY", "EVENT_GOT_CALCIUM_FROM_ERIN" },
    interp("Joey, Huey, Vance, Parry and Erin have each given you their vitamin.",
      { goal = 5, unit = "VITAMINS", category = "SIDE" })))
  add(L.state("g2o_buena", { crystal = 199597 }, "Buena's number",
    function(f) return f.flag("EVENT_BUENA_OFFERED_HER_PHONE_NUMBER") end,
    interp("Buena has offered you her number, which needs 30 Blue Card points.", { category = "SIDE" })))
  add(L.state("g2o_daisy", { crystal = 199625 }, "Daisy's grooming",
    function(f) return f.engineFlag("ENGINE_DAISYS_GROOMING") end,
    interp("Noted while today's grooming flag is set (Daisy grooms once a day).", { category = "SIDE" })))

  -- Flag-to-item handovers that only exist as a moment in time
  local function handover(id, ra, title, readyCheck, item, note)
    add(L.tracker(id, ra, title, {
      tick = function(s, _, f)
        local ready, count = readyCheck(f), f.itemCount(item)
        local got = s.ready and not ready and count > (s.count or 0)
        s.ready, s.count = ready, count
        return got or nil
      end,
    }, nil, interp(note, { category = "SIDE" })))
  end
  handover("g2o_kenji_ppup", { crystal = 199577 }, "Kenji's PP Up",
    function(f) return f.flag("EVENT_KENJI_ON_BREAK") end, "PP_UP",
    "Counted when Kenji hands over the PP Up while you're playing (it can't be read from a save).")
  handover("g2o_fan_nugget", { crystal = 199579 }, "Nugget from a Pokefan",
    function(f) return f.engineFlag("ENGINE_BEVERLY_HAS_NUGGET") or f.engineFlag("ENGINE_DEREK_HAS_NUGGET") end, "NUGGET",
    "Counted when Beverly or Derek hands over a Nugget while you're playing.")
  add(L.tracker("g2o_bike_keep", { crystal = 199638 }, "Keep the Bicycle", {
    tick = function(s, _, f)
      local on = f.engineFlag("ENGINE_BIKE_SHOP_CALL_ENABLED")
      local kept = s.on and not on and f.flag("EVENT_GOT_BICYCLE")
      s.on = on
      return kept or nil
    end,
  }, nil, interp("Counted when the bike shop's call (after you've ridden enough) comes in while you're playing.",
    { category = "SIDE" })))
  add(L.state("g2o_magikarp_record", { crystal = 199581 }, "Magikarp record",
    function(f) return f.flag("EVENT_LAKE_OF_RAGE_ELIXIR_ON_STANDBY") or f.itemCount("ELIXER") > 0 and f.flag("EVENT_LAKE_OF_RAGE_ASKED_FOR_MAGIKARP") end,
    interp("The Fishing Guru asked for a big Magikarp and you hold his Elixir (or it's waiting for you).", { category = "SIDE" })))

  -- ------------------------------------------------------------ battles and minigames (Crystal)
  local TRAINER_MAP = function(prefixes)
    return function(row) for _, p in ipairs(prefixes) do if row[3]:sub(1, #p) == p then return true end end return false end
  end
  add(L.sweep("g2o_hideout_trainers", { crystal = 199571 }, "Hideout cleared", "trainers",
    TRAINER_MAP({ "TeamRocketBase" }), 100, { category = "TRAINERS" }))
  add(L.sweep("g2o_radio_trainers", { crystal = 199572 }, "Goldenrod roundup", "trainers",
    TRAINER_MAP({ "RadioTower", "GoldenrodUnderground" }), 100, { category = "TRAINERS" }))
  add(L.sweep("g2o_ss_aqua", { crystal = 199637 }, "S.S. Aqua trainers", "trainers",
    TRAINER_MAP({ "FastShip" }), 100, interp("Every trainer on the S.S. Aqua's decks and cabins.", { category = "TRAINERS" })))
  add(L.onEvent("g2o_indigo_rival", { crystal = 199593 }, "Rival at Indigo Plateau", "battle.ended",
    function(ev, _, ctx)
      local b = ctx.battle
      return b and ev and ev.result == "win" and tostring(b.trainerId or ""):match("^RIVAL") ~= nil
        and tostring(b.map or ""):match("^INDIGO_PLATEAU") ~= nil
    end, { category = "LEAGUE" }))
  add(L.onEvent("g2o_headbutt_sleep", { crystal = 199596 }, "Sleepy Headbutt", "battle.started",
    function(ev)
      local raw = ev and ev.battle
      local enemy = type(raw) == "table" and raw.enemy
      return ev and ev.battleType == "tree" and type(enemy) == "table" and enemy.status == "sleep"
    end, { category = "BATTLE" }))
  add(L.onEvent("g2o_max_return", { crystal = 199621 }, "Gentle 'Mon", "battle.move_used",
    function(ev)
      local u, move = ev and ev.user, ev and (ev.moveId or ev.move)
      if type(move) == "table" then move = move.id or move.name end
      if type(u) ~= "table" or not (u.side == "player" or u.isPlayer) then return false end
      local h = tonumber(u.happiness or (type(u.native) == "table" and u.native.happiness))
      return h ~= nil and ((move == "RETURN" and h >= 255) or (move == "FRUSTRATION" and h <= 0))
    end, interp("Return used at 255 friendship or Frustration at 0.", { category = "BATTLE" })))
  add(L.onEvent("g2o_hidden_power", { crystal = 199626 }, "Hidden strength", "battle.damage_dealt",
    function(ev)
      local u, move = ev and ev.user, ev and (ev.moveId or ev.move)
      if type(move) == "table" then move = move.id or move.name end
      return type(u) == "table" and (u.side == "player" or u.isPlayer) and move == "HIDDEN_POWER"
        and (tonumber(ev.typeMult) or 10) > 10
    end, { category = "BATTLE" }))
  add(L.tracker("g2o_berry_juice", { crystal = 199633 }, "Berry Juice", {
    ["battle.started"] = function(s, _, f)
      s.slots = {}
      for i, m in ipairs(f.party()) do
        if m.species == "SHUCKLE" and m.item == "BERRY" then s.slots[i] = true end
      end
    end,
    ["battle.ended"] = function(s, _, f)
      local party = f.party()
      for i in pairs(s.slots or {}) do
        local m = party[i]
        if m and m.species == "SHUCKLE" and m.item == "BERRY_JUICE" then return true end
      end
      s.slots = {}
    end,
  }, nil, interp("A Shuckle that went into battle holding a Berry comes out holding Berry Juice.", { category = "BATTLE" })))

  -- Bug-Catching Contest (bug_contest.scored)
  local BUGS = L.set({ "BUTTERFREE", "BEEDRILL", "SCYTHER", "PINSIR" })
  add(L.onEvent("g2o_bug_contest", { crystal = 199622 }, "Bug contest winner", "bug_contest.scored",
    function(ev) return ev and ev.place == 1 end, { category = "SIDE" }))
  add(L.onEvent("g2o_bug_contest_cuddly", { crystal = 199623 }, "Cuddly bug winner", "bug_contest.scored",
    function(ev)
      local mon = ev and ev.mon
      return ev.place == 1 and type(mon) == "table" and not BUGS[mon.species]
    end, interp("Won first place with a Pokemon that isn't Butterfree, Beedrill, Scyther or Pinsir.", { category = "SIDE" })))
  add(L.onEvent("g2o_bug_contest_nick", { crystal = 199624 }, "Beat Cooltrainer Nick", "bug_contest.scored",
    function(ev, f)
      -- Contestants who are NOT taking part have their event flag set
      return ev.place == 1 and not f.flag("EVENT_BUG_CATCHING_CONTESTANT_1A")
    end, interp("Won first place on a day Cooltrainer Nick was one of the contestants.", { category = "SIDE" })))

  -- Game Corner (watched while the minigame screen is open)
  local function topScreen(f, ctx)
    local game = ctx.engine and ctx.engine.mod and ctx.engine.mod.game
    local states = game and game.stack and game.stack.states
    return states and states[#states] or nil
  end
  add(L.tracker("g2o_slots_golem", { crystal = 199634 }, "Golem on the slots", {
    tick = function(_, _, f, ctx)
      local top = topScreen(f, ctx)
      return top and top.screenId == "SlotMachine" and top.reel3Action == "golem" and top.matchingSevens == true or nil
    end,
  }, nil, { category = "GAME CORNER" }))
  add(L.tracker("g2o_slots_777", { crystal = 199635 }, "Triple seven", {
    tick = function(_, _, f, ctx)
      local top = topScreen(f, ctx)
      return top and top.screenId == "SlotMachine" and top.matched == 0 or nil
    end,
  }, nil, { category = "GAME CORNER" }))
  add(L.tracker("g2o_card_flip", { crystal = 199627 }, "x24 Card Flip", {
    tick = function(s, _, f, ctx)
      local top = topScreen(f, ctx)
      local coins = f.coins()
      local won = top and top.screenId == "CardFlip" and s.coins and coins - s.coins >= 72
      s.coins = coins
      return won or nil
    end,
  }, nil, interp("Counted when a single Card Flip pays 72 coins or more (the x24 card at a 3-coin bet).",
    { category = "GAME CORNER" })))
  add(L.tracker("g2o_apricorn_batch", { crystal = 199601 }, "Apricorn haul", {
    tick = function(s, _, f)
      local n = 0
      for _, b in ipairs({ "LEVEL_BALL", "LURE_BALL", "MOON_BALL", "FRIEND_BALL", "FAST_BALL", "HEAVY_BALL", "LOVE_BALL" }) do
        n = n + f.itemCount(b)
      end
      local jump = s.n and n - s.n >= 10
      s.n = n
      return jump or nil
    end,
  }, nil, interp("Counted when your Apricorn balls go up by 10 or more at once.", { category = "SIDE" })))
  add(L.tracker("g2o_move_tutor", { crystal = 199620 }, "Tutor's lesson", {
    tick = function(s, _, f, ctx)
      local known = {}
      for i, m in ipairs(f.party()) do
        for _, mv in ipairs(type(m.moves) == "table" and m.moves or {}) do
          local id = type(mv) == "table" and (mv.id or mv.move) or mv
          if id == "FLAMETHROWER" or id == "THUNDERBOLT" or id == "ICE_BEAM" then known[i .. ":" .. id] = true end
        end
      end
      local learned = false
      if s.known and tostring(ctx.map or ""):match("^GOLDENROD_CITY") then
        for k in pairs(known) do if not s.known[k] then learned = true end end
      end
      s.known = known
      return learned or nil
    end,
  }, nil, interp("Counted when a party Pokemon learns Flamethrower, Thunderbolt or Ice Beam in Goldenrod City.",
    { category = "SIDE" })))
  add(L.tracker("g2o_rooftop_sale", { crystal = 199631 }, "Rooftop sale", {
    tick = function(s, _, f, ctx)
      local money = f.money()
      local bought = s.money and money < s.money and tostring(ctx.map or "") == "GOLDENROD_DEPT_STORE_ROOF"
      s.money = money
      return bought or nil
    end,
  }, nil, interp("Counted when you spend money on the Goldenrod Dept. Store roof.", { category = "SIDE" })))

  -- Held items from wild Pokemon (catch or Thief)
  local function heldItem(id, ra, title, item)
    add(L.state(id, ra, title, function(f)
      return f.hasItem(item) or f.ownsWhere(function(m) return m.item == item end)
    end, interp("You hold a " .. item:gsub("_", " "):lower() .. ", in your Pack or on a Pokemon.", { category = "ITEMS" })))
  end
  heldItem("g2o_stick", { crystal = 199598 }, "A Stick", "STICK")
  heldItem("g2o_thick_club", { crystal = 199599 }, "A Thick Club", "THICK_CLUB")
  heldItem("g2o_lucky_egg", { crystal = 199600 }, "A Lucky Egg", "LUCKY_EGG")

  -- Battle Tower
  add(L.tracker("g2o_battle_tower", { crystal = 5936 }, "Battle Tower", {
    tick = function(_, _, f) return f.towerStreak() >= 7 or nil end,
  }, nil, interp("Counted when a Battle Tower streak reaches seven wins while you're playing.", { category = "TOWER" })))
  add(L.tracker("g2o_battle_tower_johto", { crystal = 199628 }, "Tower with Johto Pokemon", {
    tick = function(_, _, f)
      if f.towerStreak() < 7 then return nil end
      for _, m in ipairs(f.party()) do
        if m.isEgg or not f.isJohto(m.species) or L.LUGIA_HOOH[m.species] then return nil end
      end
      return true
    end,
  }, nil, interp("A seven-win streak while your party is all Johto Pokemon, without Lugia or Ho-Oh.", { category = "TOWER" })))

  -- ------------------------------------------------------------ completion
  local johto, kanto = L.region("johto"), L.region("kanto")
  local both = L.region("johto", "kanto")
  local function tms(row) return L.isTM(row) end
  -- every TM/HM from item balls and NPC gifts
  local function tmCount(f)
    local d1, t1 = f.sweep("items", tms)
    local d2, t2 = f.sweep("gifts", tms)
    return d1 + d2, t1 + t2
  end
  local function tmRule(id, ra, title, percent, extra)
    add(L.state(id, ra, title, function(f)
      local done, total = tmCount(f)
      if total == 0 then return false end
      return math.min(percent, math.floor(done * 100 / total))
    end, interp("TMs and HMs from item balls and from people, counted by the flag each one sets.",
      { goal = percent, unit = "PCT", category = "COMPLETION" })))
  end
  tmRule("g2o_tms_all", { gold = 155196, silver = 163159, crystal = 199563 }, "Every TM", 100)
  tmRule("g2o_tms_half", { silver = 163178 }, "Half the TMs", 50)

  add(L.sweep("g2o_items_50", { gold = 155197 }, "Items: 50%", "items", both, 50))
  add(L.sweep("g2o_items_100", { gold = 155198 }, "Items: 100%", "items", both, 100))
  add(L.sweep("g2o_hidden_25", { silver = 163162 }, "Hidden: 25%", "hidden", both, 25))
  add(L.sweep("g2o_hidden_50", { gold = 155199, silver = 163160 }, "Hidden: 50%", "hidden", both, 50))
  add(L.sweep("g2o_hidden_100", { gold = 155200, silver = 163161 }, "Hidden: 100%", "hidden", both, 100))
  -- Crystal: visible and hidden together, per region
  local function fieldItems(id, ra, title, keep)
    add(L.state(id, ra, title, function(f)
      local d1, t1 = f.sweep("items", keep)
      local d2, t2 = f.sweep("hidden", keep)
      if t1 + t2 == 0 then return false end
      return math.floor((d1 + d2) * 100 / (t1 + t2))
    end, { goal = 100, unit = "PCT", category = "COMPLETION" }))
  end
  fieldItems("g2o_field_johto", { crystal = 199562 }, "Johto field items", johto)
  fieldItems("g2o_field_kanto", { crystal = 199584 }, "Kanto field items", kanto)

  -- Trainers.  "Non-missable" here leaves out Team Rocket, who leave once
  -- their part of the story is over.
  local function regular(region)
    return function(row)
      return row[4] == region and not row[2]:match("GRUNT") and not row[2]:match("EXECUTIVE")
        and not row[2]:match("ROCKET")
    end
  end
  add(L.sweep("g2o_trainers_johto_50", { gold = 155201 }, "Johto trainers: 50%", "trainers", johto, 50,
    { category = "TRAINERS" }))
  add(L.sweep("g2o_trainers_johto_100", { gold = 155202 }, "Johto trainers: 100%", "trainers", johto, 100,
    { category = "TRAINERS" }))
  add(L.sweep("g2o_trainers_kanto", { gold = 155203 }, "Kanto trainers", "trainers", kanto, 100,
    { category = "TRAINERS" }))
  add(L.sweep("g2o_landly_legend", { crystal = 199560 }, "Johto trainers", "trainers", regular("johto"), 100,
    interp("Every map trainer in Johto except Team Rocket (who leave once their part of the story ends).",
      { category = "TRAINERS" })))
  add(L.sweep("g2o_urban_underdog", { crystal = 199583 }, "Kanto trainers", "trainers", regular("kanto"), 100,
    interp("Every map trainer in Kanto except Team Rocket.", { category = "TRAINERS" })))
  add(L.sweep("g2o_gift_items", { gold = 155204 }, "Every gift item", "gifts", both, 100,
    interp("Every item a person hands over and remembers handing over (each sets its own flag).",
      { category = "COMPLETION" })))

  return rules
end
