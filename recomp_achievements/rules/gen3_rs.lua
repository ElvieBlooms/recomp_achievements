-- rules/gen3_rs.lua
-- ==================================================================
-- Detectors for the RetroAchievements lists of Ruby (49) and Sapphire
-- (49), built with rules/gen3_lib.lua.  Names are pret/pokeruby's, turned
-- into the save's numbers by data/gen3_rs.lua (both games share it).
--
-- Team Magma runs Ruby's story and Team Aqua Sapphire's.  The two games
-- use different trainer numbers for the same fights; which is which comes
-- from pokeruby's constants/version.inc (Ruby: TRAINER_MT_CHIMNEY_GRUNT_3
-- is TRAINER_MAXIE_3, Sapphire: TRAINER_ARCHIE_3, and so on).
-- ==================================================================

return function(L)
  local out = {}
  local function add(r) out[#out + 1] = r end
  local R = function(id) return { ruby = id } end
  local S = function(id) return { sapphire = id } end
  local RS = function(r, s) return { ruby = r, sapphire = s } end
  local function interp(note, extra)
    extra = extra or {}
    extra.fidelity = "interpretation"
    extra.note = note
    return extra
  end
  -- Brendan/May with any starter: rival battle n uses _n, _n+3, _n+6
  local function rival(n)
    local list = {}
    for _, who in ipairs({ "BRENDAN", "MAY" }) do
      for _, k in ipairs({ n, n + 3, n + 6 }) do list[#list + 1] = ("TRAINER_%s_%d"):format(who, k) end
    end
    return list
  end
  local MASTER_BALL = 1 -- item number of the Master Ball (the ball a Pokemon was caught in)

  -- ------------------------------------------------ rival, badges, league
  add(L.anyFlag("rs_rival1", RS(31199, 31146), "Rival: Route 103",
    (function() local l = rival(1); l[#l + 1] = "FLAG_DEFEATED_RIVAL_ROUTE103"; return l end)(), { category = "RIVAL" }))
  add(L.anyFlag("rs_rival2", RS(31200, 31147), "Rival: Route 110", rival(2), { category = "RIVAL" }))
  add(L.anyFlag("rs_rival3", RS(31201, 31148), "Rival: Route 119", rival(3), { category = "RIVAL" }))
  add(L.anyFlag("rs_rival4", RS(31202, 31149), "Rival: Lilycove", {
    "TRAINER_BRENDAN_LILYCOVE_MUDKIP", "TRAINER_BRENDAN_LILYCOVE_TREECKO", "TRAINER_BRENDAN_LILYCOVE_TORCHIC",
    "TRAINER_MAY_LILYCOVE_MUDKIP", "TRAINER_MAY_LILYCOVE_TREECKO", "TRAINER_MAY_LILYCOVE_TORCHIC" },
    { category = "RIVAL" }))
  local BADGES = { "Roxanne", "Brawly", "Wattson", "Flannery", "Norman", "Winona", "Tate & Liza", "Wallace" }
  local RUBY_BADGE = { 31206, 31207, 31208, 31209, 31210, 31211, 31212, 31213 }
  local SAPPHIRE_BADGE = { 31151, 31152, 31153, 31154, 31155, 31156, 31157, 31158 }
  for i, who in ipairs(BADGES) do
    add(L.badge("rs_badge" .. i, RS(RUBY_BADGE[i], SAPPHIRE_BADGE[i]), "Badge: " .. who, i))
  end
  add(L.flag("rs_wally_vr", RS(31218, 31164), "Wally at Victory Road", "FLAG_DEFEATED_WALLY_VICTORY_ROAD",
    { category = "RIVAL" }))
  add(L.anyFlag("rs_champion", RS(31223, 31169), "Champion", { "FLAG_SYS_GAME_CLEAR", "TRAINER_STEVEN" },
    { category = "LEAGUE" }))

  -- ------------------------------------------------ the villains
  -- (Ruby raids the Magma Hideout, Sapphire the Aqua Hideout.)
  add(L.flag("rs_master_ball_r", R(31205), "Hideout Master Ball", "FLAG_ITEM_MAGMA_HIDEOUT_B1F_1", { category = "STORY" }))
  add(L.flag("rs_master_ball_s", S(31163), "Hideout Master Ball", "FLAG_ITEM_AQUA_HIDEOUT_B1F_2", { category = "STORY" }))
  add(L.flag("rs_chimney_r", R(31214), "Maxie at Mt. Chimney", "TRAINER_MAXIE_3", { category = "STORY" }))
  add(L.flag("rs_weather_r", R(31215), "Courtney at the Institute", "TRAINER_COURTNEY_1", { category = "STORY" }))
  add(L.flag("rs_hideout_r", R(31216), "Tabitha in the Hideout", "TRAINER_TABITHA_1", { category = "STORY" }))
  add(L.flag("rs_seafloor_r", R(31217), "Maxie in the Seafloor Cavern", "TRAINER_MAXIE_2", { category = "STORY" }))
  add(L.flag("rs_chimney_s", S(31159), "Archie at Mt. Chimney", "TRAINER_ARCHIE_3", { category = "STORY" }))
  add(L.flag("rs_weather_s", S(31160), "Shelly at the Institute", "TRAINER_SHELLY_1", { category = "STORY" }))
  add(L.flag("rs_hideout_s", S(31161), "Matt in the Hideout", "TRAINER_MATT_1", { category = "STORY" }))
  add(L.flag("rs_seafloor_s", S(31162), "Archie in the Seafloor Cavern", "TRAINER_ARCHIE_2", { category = "STORY" }))

  -- ------------------------------------------------ legendaries
  add(L.owns("rs_groudon", R(31224), "Groudon", "GROUDON"))
  add(L.owns("rs_rayquaza_r", R(31225), "Rayquaza", "RAYQUAZA"))
  add(L.owns("rs_regirock_r", R(31226), "Regirock", "REGIROCK"))
  add(L.owns("rs_regice_r", R(31227), "Regice", "REGICE"))
  add(L.owns("rs_registeel_r", R(31228), "Registeel", "REGISTEEL"))
  add(L.owns("rs_latios", R(31229), "Latios", "LATIOS"))
  add(L.owns("rs_latias", S(31176), "Latias", "LATIAS"))
  -- "without the Master Ball": the Pokemon you have is in another ball
  local function noMaster(id, ra, title, species)
    add(L.state(id, ra, title, function(f)
      return f.anyMon(function(name, m) return name == species and tonumber(m.pokeball) ~= MASTER_BALL end)
    end, interp("You have a " .. L.prettyName(species) .. " that wasn't caught in a Master Ball.",
      { category = "POKEMON" })))
  end
  noMaster("rs_kyogre", S(31171), "Kyogre, No Master Ball", "KYOGRE")
  noMaster("rs_rayquaza_s", S(31172), "Rayquaza, No Master Ball", "RAYQUAZA")
  noMaster("rs_regirock_s", S(31173), "Regirock, No Master Ball", "REGIROCK")
  noMaster("rs_regice_s", S(31174), "Regice, No Master Ball", "REGICE")
  noMaster("rs_registeel_s", S(31175), "Registeel, No Master Ball", "REGISTEEL")
  noMaster("rs_latios_pro", R(92003), "Latios, No Master Ball", "LATIOS")

  -- ------------------------------------------------ side stories (both)
  add(L.flag("rs_new_mauville", RS(91983, 92019), "New Mauville", "FLAG_GOT_TM_THUNDERBOLT_FROM_WATTSON",
    { category = "EVENTS" }))
  add(L.var("rs_trick_master", RS(91984, 92012), "Trick Master", "VAR_TRICK_HOUSE_ROOMS_COMPLETED", 8,
    interp("All eight Trick House puzzles cleared.", { category = "EVENTS" })))
  add(L.hasItem("rs_shell_bell", RS(91985, 92021), "Shell Bell", "SHELL_BELL",
    interp("You hold a Shell Bell in your Bag (made from 4 Shoal Salt and 4 Shoal Shells).", { category = "EVENTS" })))
  add(L.flag("rs_scanner", RS(91986, 92020), "Scanner Delivered", "FLAG_EXCHANGED_SCANNER", { category = "EVENTS" }))
  add(L.flag("rs_orb", RS(91987, 92024), "Orb Returned", "FLAG_RETURNED_RED_OR_BLUE_ORB", { category = "EVENTS" }))

  -- ------------------------------------------------ Ruby
  local function holds(item)
    return function(f)
      return f.hasItem(item) or f.anyMon(function(_, m) return tonumber(m.heldItem or m.item) == f.data().itemIds[item] end)
    end
  end
  add(L.state("rs_black_belt", R(91988), "Black Belt", holds("BLACK_BELT"),
    interp("You hold a Black Belt, in your Bag or on a Pokemon.", { category = "ITEMS" })))
  add(L.state("rs_silver_powder", R(91989), "Silver Powder", holds("SILVER_POWDER"),
    interp("You hold a Silver Powder, in your Bag or on a Pokemon.", { category = "ITEMS" })))
  add(L.state("rs_dragon_fang", R(91990), "Dragon Fang", holds("DRAGON_FANG"),
    interp("You hold a Dragon Fang, in your Bag or on a Pokemon.", { category = "ITEMS" })))
  add(L.state("rs_tms", R(89506), "Machine Collector", function(f)
    -- a TM counts when it's in your Bag now, or when its one-off pickup or gift is done
    local done = {}
    for _, kind in ipairs({ "items", "hidden", "gifts" }) do
      for _, row in ipairs(f.data()[kind] or {}) do
        local n = tostring(row[#row - 2]):match("^TM(%d%d)")
        if n and f.flag(row[1]) then done[tonumber(n)] = true end
      end
    end
    local have = 0
    for i = 1, 50 do
      if done[i] or f.itemCount(("TM%02d"):format(i)) > 0 then have = have + 1 end
    end
    return have >= 50 or have
  end, interp("Each of the 50 TMs is in your Bag, or its one-off pickup or gift is done.",
    { category = "COLLECTION", goal = 50, unit = "TMS" })))
  add(L.state("rs_gift_mons", R(92002), "Gift and Trade Pokemon", function(f)
    local list = { "FLAG_SYS_POKEMON_GET", "FLAG_RECEIVED_CASTFORM", "FLAG_RECEIVED_BELDUM",
      "FLAG_RECEIVED_LAVARIDGE_EGG", "FLAG_RECEIVED_FOSSIL_MON", "FLAG_RUSTBORO_NPC_TRADE_COMPLETED",
      "FLAG_FORTREE_NPC_TRADE_COMPLETED", "FLAG_PACIFIDLOG_NPC_TRADE_COMPLETED" }
    local n = f.countFlags(list)
    return n >= #list or n
  end, interp("Your starter, Castform, Beldum, the Lavaridge Egg, a revived fossil and the three in-game trades.",
    { category = "POKEMON", goal = 8, unit = "POKEMON" })))
  add(L.state("rs_stationary", R(92005), "Pest Control", function(f)
    local list = { "FLAG_HIDE_KECLEON_ROUTE119_1", "FLAG_HIDE_KECLEON_ROUTE119_2", "FLAG_HIDE_KECLEON_ROUTE120_1",
      "FLAG_HIDE_KECLEON_ROUTE120_2", "FLAG_HIDE_KECLEON_ROUTE120_3", "FLAG_HIDE_KECLEON_ROUTE120_4",
      "FLAG_HIDE_KECLEON_ROUTE120_5", "FLAG_HIDE_KECLEON_ROUTE120_6", "FLAG_HIDE_KECLEON_ROUTE120_7",
      "FLAG_KECLEON_FLED_FORTREE", "FLAG_HIDE_ELECTRODE_1_HIDEOUT", "FLAG_HIDE_ELECTRODE_2_HIDEOUT",
      "FLAG_HIDE_VOLTORB_1_NEW_MAUVILLE", "FLAG_HIDE_VOLTORB_2_NEW_MAUVILLE", "FLAG_HIDE_VOLTORB_3_NEW_MAUVILLE" }
    local n = f.countFlags(list)
    return n >= #list or n
  end, interp("Every hidden Kecleon, the hideout Electrode and New Mauville's Voltorb have been dealt with.",
    { category = "POKEMON", goal = 15, unit = "POKEMON" })))
  -- Azurill (75% female) becomes a Marill (50%); the same Pokemon reads
  -- female before and male after when its personality's low byte is 127-190.
  add(L.onEvent("rs_azurill", R(91997), "Successful Transition", "pokemon.evolved", function(ev)
    if not (ev and ev.fromSpecies == "AZURILL" and ev.toSpecies == "MARILL") then return false end
    local p = type(ev.mon) == "table" and tonumber(ev.mon.personality) or nil
    if not p then return false end
    local low = p % 256
    return low >= 127 and low < 191
  end, interp("Counted when a female Azurill evolves into a male Marill while you're playing.",
    { category = "POKEMON" })))
  add(L.state("rs_size", R(91995), "Size Does Matter", function(f)
    local function broken(v) local x = f.var(v) return x ~= 0 and x ~= 0x8100 end
    local n = (broken("VAR_SHROOMISH_SIZE_RECORD") and 1 or 0) + (broken("VAR_BARBOACH_SIZE_RECORD") and 1 or 0)
    return n >= 2 or n
  end, interp("Both brothers' size records (Shroomish and Barboach) have been beaten.",
    { category = "EVENTS", goal = 2 })))
  add(L.state("rs_absol", R(92001), "Chain of My Chains", function(f)
    return f.knowsMove({ "ABSOL" }, "BATON_PASS")
  end, interp("You have an Absol that knows Baton Pass, which it can only get by breeding.", { category = "POKEMON" })))
  add(L.flag("rs_mystery_club", R(91996), "Mystery Event Club", "FLAG_SYS_EXDATA_ENABLE",
    interp("Mystery Events are switched on (the Petalburg Pokemon Center questionnaire).", { category = "EVENTS" })))
  add(L.state("rs_trainer_eyes", R(91991), "Renowned Trainer", function(f)
    local done, total = 0, 0
    for _, row in ipairs(f.data().rematches or {}) do
      total = total + 1
      if f.flag(row[3]) then done = done + 1 end
    end
    if total == 0 then return false end
    return done >= total or math.floor(done * 100 / total)
  end, interp("Every trainer who can join the Trainer's Eyes list has been beaten once.",
    { category = "COMPLETION", goal = 100, unit = "PCT" })))
  local LEGENDARY = L.set({ "ARTICUNO", "ZAPDOS", "MOLTRES", "MEWTWO", "MEW", "RAIKOU", "ENTEI", "SUICUNE",
    "LUGIA", "HO_OH", "CELEBI", "REGIROCK", "REGICE", "REGISTEEL", "LATIAS", "LATIOS", "KYOGRE", "GROUDON",
    "RAYQUAZA", "JIRACHI", "DEOXYS", "DRATINI", "DRAGONAIR", "DRAGONITE", "LARVITAR", "PUPITAR", "TYRANITAR",
    "BAGON", "SHELGON", "SALAMENCE", "BELDUM", "METANG", "METAGROSS" })
  add(L.beatTrainer("rs_owning_wally", R(92004), "Owning Wally", "TRAINER_WALLY_6", function(b, f)
    local party = {}
    for _, m in ipairs(b.partyAtStart or {}) do if not m.isEgg then party[#party + 1] = m end end
    return #party == 1 and not LEGENDARY[party[1].species]
  end, interp("Beat Wally's strongest Victory Road rematch team with one Pokemon in your party, not a legendary or a pseudo-legendary line.",
    { category = "RIVAL" })))
  local ELITE = { "TRAINER_SIDNEY", "TRAINER_PHOEBE", "TRAINER_GLACIA", "TRAINER_DRAKE" }
  local function exclusives(list)
    local want = L.set(list)
    return function(f)
      local party = f.party()
      if #party ~= 6 then return false end
      for _, m in ipairs(party) do if m.isEgg or not want[m.species] then return false end end
      return true
    end
  end
  add(L.leagueRun("rs_epic_sweep", R(92000), "Epic Sweep", ELITE, { "TRAINER_STEVEN" },
    exclusives({ "SEEDOT", "NUZLEAF", "SHIFTRY", "MAWILE", "ZANGOOSE", "SOLROCK" }),
    interp("Six Ruby-only Pokemon (Seedot's line, Mawile, Zangoose, Solrock) from Sidney to Steven in one go.")))
  add(L.leagueRun("rs_exclusive_s", S(92023), "Exclusive Excellence", ELITE, { "TRAINER_STEVEN" },
    exclusives({ "LOTAD", "LOMBRE", "LUDICOLO", "SABLEYE", "SEVIPER", "LUNATONE" }),
    interp("Six Sapphire-only Pokemon (Lotad's line, Sableye, Seviper, Lunatone) from Sidney to Steven in one go.")))
  local function towerRecord(f, i)
    local r = f.battleTower().recordWinStreaks
    return type(r) == "table" and (tonumber(r[i]) or tonumber(r[tostring(i)]) or 0) or 0
  end
  add(L.state("rs_tower50", R(91992), "Master", function(f)
    local n = towerRecord(f, 1)
    return n >= 50 or n
  end, { category = "TOWER", goal = 50, unit = "WINS" }))
  add(L.state("rs_tower100", R(91993), "Grandmaster", function(f)
    local n = towerRecord(f, 2)
    return n >= 50 or n
  end, { category = "TOWER", goal = 50, unit = "WINS" }))
  add(L.state("rs_tower_any", R(91994), "Champion of Champions", function(f)
    local n = math.max(towerRecord(f, 1), towerRecord(f, 2), tonumber(f.battleTower().bestBattleTowerWinStreak) or 0)
    return n >= 100 or n
  end, { category = "TOWER", goal = 100, unit = "WINS" }))
  add(L.owns("rs_feebas", R(91999), "Feebas", "FEEBAS"))
  add(L.dexAtLeast("rs_dex", R(91998), "Ruby Pokedex", 177,
    interp("Counted as 177 Pokemon marked caught in your Pokedex.")))

  -- ------------------------------------------------ Sapphire
  add(L.state("rs_cycling", S(92006), "Going All Out", function(f)
    local frames = f.var("VAR_CYCLING_ROAD_RECORD_TIME_L") + f.var("VAR_CYCLING_ROAD_RECORD_TIME_H") * 65536
    return frames > 0 and frames <= 570 and f.var("VAR_CYCLING_ROAD_RECORD_COLLISIONS") == 0
  end, interp("Your Cycling Road record is 9.5 seconds or less with no collisions.", { category = "EVENTS" })))
  add(L.state("rs_lottery", S(92018), "Lottery Winner", function(f)
    return f.gameStat(46) > 0 -- GAME_STAT_WON_POKEMON_LOTTERY
  end, { category = "EVENTS" }))
  add(L.badge("rs_dewford_wall", S(92017), "Heaven's Door", 2,
    interp("Counted with the Knuckle Badge, which puts your name up in the Dewford Gym.", { category = "EVENTS" })))
  add(L.state("rs_base", S(92008), "Secret Base Furnished", function(f)
    local n = f.secretBaseDecorations()
    return n >= 16 or n
  end, { category = "COLLECTION", goal = 16, unit = "SLOTS" }))
  add(L.state("rs_note_mats", S(92009), "GBA Orchestra", function(f)
    local owned = f.decorations(4)
    local d = f.data().decorations or {}
    for _, name in ipairs({ "C_LOW_NOTE_MAT", "D_NOTE_MAT", "E_NOTE_MAT", "F_NOTE_MAT", "G_NOTE_MAT",
                             "A_NOTE_MAT", "B_NOTE_MAT", "C_HIGH_NOTE_MAT" }) do
      if not (d[name] and owned[d[name][1]]) then return false end
    end
    return true
  end, interp("You own all eight Note Mats, the full scale the Pallet Town tune needs.", { category = "COLLECTION" })))
  local function decor(id, ra, title, cats, skip, minPct, note)
    add(L.state(id, ra, title, function(f)
      local want, have, owned = 0, 0, {}
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
      local pct = math.floor(have * 100 / want)
      return pct >= minPct or math.floor(pct * 100 / minPct)
    end, interp(note, { category = "COLLECTION", goal = 100, unit = "PCT" })))
  end
  decor("rs_decor_furniture", S(92013), "Chairman of the Board", { 0, 1, 7 }, nil, 100,
    "Every chair, desk and cushion, in your PC or placed.")
  decor("rs_decor_fresh", S(92014), "Fresh Air", { 2, 4, 5 }, nil, 100, "Every mat, plant and poster.")
  decor("rs_decor_dolls", S(92015), "Dollhouse", { 6 },
    { SEEDOT_DOLL = true, REGIROCK_DOLL = true, REGICE_DOLL = true, REGISTEEL_DOLL = true }, 90,
    "Most dolls: 90% of them, leaving out the Seedot and Regi dolls.")
  decor("rs_decor_ornaments", S(92016), "Ornament Collector", { 3 }, nil, 90, "Most ornaments: 90% of them.")
  add(L.state("rs_berries", S(92022), "Berry Maniac", function(f)
    local skip = L.set({ "WIKI_BERRY", "MAGO_BERRY", "AGUAV_BERRY", "DURIN_BERRY", "LIECHI_BERRY", "ENIGMA_BERRY" })
    local ids = f.data().itemIds
    local have, want = 0, 0
    for name, id in pairs(ids) do
      if name:match("_BERRY$") and id >= ids.CHERI_BERRY and id <= ids.ENIGMA_BERRY and not skip[name] then
        want = want + 1
        if f.itemCount(id) > 0 then have = have + 1 end
      end
    end
    return (want > 0 and have >= want) or have
  end, interp("One of every Berry in your Bag or PC, except Wiki, Mago, Aguav, Durin, Liechi and the Enigma Berry.",
    { category = "COLLECTION", goal = 37, unit = "BERRIES" })))
  add(L.state("rs_pokeblock", S(92007), "Blending the Blender", function(f)
    for _, b in pairs(f.pokeblocks()) do
      if type(b) == "table" then
        local lv = math.max(tonumber(b.spicy) or 0, tonumber(b.dry) or 0, tonumber(b.sweet) or 0,
                            tonumber(b.bitter) or 0, tonumber(b.sour) or 0)
        if (tonumber(b.color) or 0) > 0 and lv >= 51 then return true end
      end
    end
    return false
  end, interp("A Pokeblock of level 51 or higher is in your Pokeblock Case.", { category = "CONTESTS" })))
  add(L.state("rs_master_contest", S(92011), "Contest Star", function(f)
    for _, c in ipairs({ "cool", "beauty", "cute", "smart", "tough" }) do
      if f.ribbonRank(c) >= 4 then return true end
    end
    return false
  end, interp("One of your Pokemon has a Master Rank contest ribbon.", { category = "CONTESTS" })))
  local PORTRAITS = { { 9, 92028, "Cool" }, { 10, 92029, "Beauty" }, { 11, 92027, "Cute" },
                      { 12, 92025, "Smart" }, { 13, 92026, "Tough" } }
  for _, p in ipairs(PORTRAITS) do
    add(L.state("rs_portrait_" .. p[3]:lower(), S(p[2]), "Portrait: " .. p[3],
      function(f) return f.museum(p[1]) end,
      interp("The Lilycove Museum shows a portrait in the " .. p[3] .. " Master Rank frame.", { category = "CONTESTS" })))
  end
  add(L.state("rs_ribbon_master", S(92010), "Ribbon Master", function(f)
    return f.anyMon(function(_, m)
      local r = tonumber(m.ribbons)
      if not r then return false end
      for shift = 0, 12, 3 do if math.floor(r / 2 ^ shift) % 8 < 4 then return false end end
      for bit = 15, 19 do if math.floor(r / 2 ^ bit) % 2 == 0 then return false end end
      return true
    end)
  end, interp("One Pokemon with all 25 Ribbons: every contest rank in all five categories plus Champion, Winning, Victory, Artist and Effort.",
    { category = "CONTESTS" })))

  return out
end
