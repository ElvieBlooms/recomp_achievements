-- tests/official.lua
-- ==================================================================
-- Tests for the official Red/Blue/Yellow rule set (rules/gen1_official.lua)
-- in the real 0.3.97 loader, against the real extracted game data.
-- Each test plays out the situation an RA achievement describes -- and,
-- where it matters, a near miss that must NOT unlock.
--
--   luajit tests/official.lua
-- ==================================================================

local H = dofile((os.getenv("PROJECT") or ".") .. "/tests/harness.lua")

local passed, failed, current = 0, 0, ""
local function check(cond, message)
  if cond then passed = passed + 1
  else failed = failed + 1; print(("  FAIL [%s] %s"):format(current, message)) end
end
local function eq(a, b, message)
  check(a == b, ("%s (expected %s, got %s)"):format(message, tostring(b), tostring(a)))
end
local function test(name, fn)
  current = name
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then failed = failed + 1; print(("  ERROR [%s] %s"):format(name, err)) end
  print((ok and "ok   " or "BAD  ") .. name)
end

local function boot(version)
  local env = H.boot({ "recomp_achievements" }, { version = version or "red" })
  env:newGame()
  env:place("PALLET_TOWN", 5, 5)
  return env
end
local function api(env) return env:exports("recomp_achievements") end
local function has(env, id) return api(env).isUnlocked("core:" .. id) end
local function progress(env, id) local r = api(env).get("core:" .. id); return r and r.progress end

-- ------------------------------------------------------------- coverage
test("every RA entry of all three games has a rule", function()
  for _, game in ipairs({ "red", "blue", "yellow" }) do
    local env = boot(game)
    local linked, total = 0, 0
    local rows = api(env).list()
    local byRa = {}
    for _, r in ipairs(rows) do if r.official and r.raId then byRa[r.raId] = true end end
    local f = loadfile(H.PROJECT .. "/recomp_achievements/catalog/" .. game .. ".lua")
    setfenv(f, {})
    for _, e in ipairs(f().entries) do
      total = total + 1
      if byRa[e.id] then linked = linked + 1 else print("    untracked", game, e.id, e.title) end
    end
    eq(linked, total, game .. " coverage")
  end
end)

test("rule display uses the official RA text", function()
  local env = boot("blue")
  local r = api(env).get("core:off_boulderbadge")
  eq(r.title, "Rock On", "Blue's own title")
  eq(r.raId, 540249, "Blue's RA id")
  eq(r.official, true, "official")
  local y = boot("yellow")
  eq(api(y).get("core:off_boulderbadge").title, "Showdown in Pewter City", "Yellow's title")
end)

-- --------------------------------------------------------------- state
test("flags, badges and items", function()
  local env = boot("red")
  check(not has(env, "off_free_sample"), "not before")
  env:setFlag("EVENT_GOT_POTION_SAMPLE")
  env.game.save.inventory.BOULDERBADGE = 1
  env.game.save.inventory.ITEMFINDER = 1
  env:frame()
  check(has(env, "off_free_sample"), "parcel")
  check(has(env, "off_boulderbadge"), "badge")
  check(has(env, "off_itemfinder"), "itemfinder from the bag")
  env:setFlag("EVENT_GOT_OLD_ROD"); env:setFlag("EVENT_GOT_GOOD_ROD"); env:frame()
  eq(progress(env, "off_rods"), 2, "rods 2/3")
  env:setFlag("EVENT_GOT_SUPER_ROD"); env:frame()
  check(has(env, "off_rods"), "all rods")
end)

test("Pokemon ownership, exclusives and Pokedex size", function()
  local env = boot("red")
  local owned = env.game.save.pokedex.owned
  for _, s in ipairs({ "ARTICUNO", "ZAPDOS" }) do owned[s] = true end
  env:emit("pokemon.caught", { species = "ZAPDOS" }); env:frame()
  eq(progress(env, "off_birds"), 2, "two birds")
  owned.MOLTRES = true; env:frame(6) -- no event: the 5-second recheck picks it up
  check(has(env, "off_birds"), "three birds")
  for _, s in ipairs({ "EKANS", "ARBOK", "ODDISH", "GLOOM", "VILEPLUME", "MANKEY", "PRIMEAPE",
                       "GROWLITHE", "ARCANINE", "SCYTHER", "ELECTABUZZ" }) do owned[s] = true end
  env:emit("pokemon.caught", { species = "ELECTABUZZ" }); env:frame()
  check(has(env, "off_red_exclusives"), "red exclusives")
  local n = 0
  for id in pairs(env.game.data.pokemon) do
    if n >= 124 then break end
    owned[id] = true; n = n + 1
  end
  env:emit("pokemon.caught", { species = "MEW" }); env:frame()
  check(has(env, "off_dex_red"), "124 owned")
end)

test("area sweeps read trainer headers, item pickups and object toggles", function()
  local env = boot("red")
  local f = env.game.data
  -- every trainer-header flag in Viridian Forest, every item ball, hidden item
  local def = f.maps.VIRIDIAN_FOREST
  local headers = f.trainer_headers[def.label]
  for _, h in pairs(headers) do env.game.save.flags[h.event] = true end
  local items = 0
  for _, o in ipairs(def.objects) do
    if o.item then
      items = items + 1
      if items == 1 then
        env.game.save.itemsTaken["VIRIDIAN_FOREST_obj_" .. o.index] = true -- picked up in Gen1Recomp
      else
        env.game.save.objectToggles.VIRIDIAN_FOREST = env.game.save.objectToggles.VIRIDIAN_FOREST or {}
        env.game.save.objectToggles.VIRIDIAN_FOREST[o.name] = false     -- imported cartridge save
      end
    end
  end
  env:emit("map.entered", { mapId = "VIRIDIAN_FOREST" }); env:frame()
  check(not has(env, "off_clear_forest"), "hidden items still missing")
  check((progress(env, "off_clear_forest") or 0) > 50, "progress shown as percent")
  for _, h in ipairs(f.field.hiddenItems.VIRIDIAN_FOREST) do
    env.game.save.hiddenTaken["VIRIDIAN_FOREST_" .. h.x .. "_" .. h.y] = true
  end
  env:emit("map.entered", { mapId = "VIRIDIAN_FOREST" }); env:frame()
  check(has(env, "off_clear_forest"), "forest cleared")
end)

test("static Pokemon count wins, catches and toggles", function()
  local env = boot("red")
  local save = env.game.save
  for id, def in pairs(env.game.data.maps) do
    for _, o in ipairs(def.objects or {}) do
      if o.pokemon then save.defeatedTrainers[id .. "_obj_" .. o.index] = true end
    end
  end
  env:frame()
  check(not has(env, "off_statics"), "Snorlax still asleep")
  env:setFlag("EVENT_BEAT_ROUTE12_SNORLAX"); env:setFlag("EVENT_BEAT_ROUTE16_SNORLAX"); env:frame()
  check(has(env, "off_statics"), "all statics")
end)

test("trades: Blue per trade, Yellow through the shared trade flags, Red all nine", function()
  local blue = boot("blue")
  blue:setFlag("EVENT_TRADED_ABRA_FOR_MR_MIME"); blue:frame()
  check(api(blue).isUnlocked("core:off_event_traded_abra_for_mr_mime"), "blue abra trade")
  local yellow = boot("yellow")
  yellow:setFlag("EVENT_TRADED_NIDORAN_M_FOR_NIDORAN_F"); yellow:frame()
  local row = api(yellow).get("core:off_event_traded_nidoran_m_for_nidoran_f")
  check(row.unlocked, "yellow route 5 trade")
  eq(row.title, "King of Fighters", "shows the Yellow trade's title")
  local red = boot("red")
  for _, flag in ipairs({ "EVENT_TRADED_ABRA_FOR_MR_MIME", "EVENT_TRADED_NIDORAN_M_FOR_NIDORAN_F",
      "EVENT_TRADED_NIDORINO_FOR_NIDORINA", "EVENT_TRADED_SLOWBRO_FOR_LICKITUNG",
      "EVENT_TRADED_POLIWHIRL_FOR_JYNX", "EVENT_TRADED_SPEAROW_FOR_FARFETCHD",
      "EVENT_TRADED_RAICHU_FOR_ELECTRODE", "EVENT_TRADED_VENONAT_FOR_TANGELA" }) do
    red:setFlag(flag)
  end
  red:frame()
  eq(progress(red, "off_all_trades"), 8, "8 of 9")
  red:setFlag("EVENT_TRADED_PONYTA_FOR_SEEL"); red:frame()
  check(has(red, "off_all_trades"), "all 9")
end)

test("free coins, 9999 coins", function()
  local env = boot("red")
  for _, h in ipairs(env.game.data.field.hiddenCoins.GAME_CORNER) do
    env.game.save.hiddenTaken["GAME_CORNER_" .. h.x .. "_" .. h.y] = true
  end
  for _, flag in ipairs({ "EVENT_GOT_10_COINS", "EVENT_GOT_20_COINS", "EVENT_GOT_20_COINS_2" }) do
    env.game.save.flags[flag] = true
  end
  env.game.save.coins = 9999
  env:frame(); env:emit("map.entered", { mapId = "GAME_CORNER" }); env:frame()
  check(has(env, "off_free_coins"), "all hidden coins")
  check(has(env, "off_9999_coins"), "9999 coins")
end)

test("Yellow S.S. Anne rival counts the hidden rival object of imported saves", function()
  local env = boot("yellow")
  env.game.save.objectToggles.SS_ANNE_2F = { SSANNE2F_RIVAL = false }
  env:emit("map.entered", { mapId = "VERMILION_CITY" }); env:frame()
  check(has(env, "off_y_ss_anne_rival"), "rival via toggle")
end)

-- ---------------------------------------------------------- battles
local function setParty(env, list)
  local party = {}
  for i, m in ipairs(list) do party[i] = { species = m[1], level = m[2], hp = 10 } end
  env.game.save.party = party
end

test("Red gym leader: Set mode, no items, level cap", function()
  local env = boot("red")
  setParty(env, { { "PIKACHU", 14 }, { "PIDGEY", 12 } })
  env.game.save.options.battleStyle = "set"
  env.game.save.inventory.POTION = 3
  env:battle({ trainerId = "OPP_BROCK", lead = "PIKACHU" })
  env:setFlag("EVENT_BEAT_BROCK")
  check(has(env, "off_setcap_opp_brock"), "Rock Smash")

  local miss = boot("red")
  setParty(miss, { { "PIKACHU", 15 } })
  miss.game.save.options.battleStyle = "set"
  miss:battle({ trainerId = "OPP_BROCK" })
  miss:setFlag("EVENT_BEAT_BROCK")
  check(not has(miss, "off_setcap_opp_brock"), "level 15 is over the cap")

  local items = boot("red")
  setParty(items, { { "PIKACHU", 10 } })
  items.game.save.options.battleStyle = "set"
  items.game.save.inventory.POTION = 3
  items:battle({ trainerId = "OPP_BROCK", during = function() items.game.save.inventory.POTION = 2 end })
  items:setFlag("EVENT_BEAT_BROCK")
  check(not has(items, "off_setcap_opp_brock"), "a potion was used")

  local shift = boot("red")
  setParty(shift, { { "PIKACHU", 10 } })
  shift:battle({ trainerId = "OPP_BROCK" })
  shift:setFlag("EVENT_BEAT_BROCK")
  check(not has(shift, "off_setcap_opp_brock"), "shift mode")
end)

test("Blue gym leader: only one type sent out", function()
  local env = boot("blue")
  env:battle({ trainerId = "OPP_BROCK", lead = "RATTATA", during = function()
    env:emit("battle.battler_switched", { battler = { mon = { species = "MEOWTH", level = 10, hp = 10 }, isPlayer = true } })
  end })
  env:setFlag("EVENT_BEAT_BROCK")
  check(has(env, "off_type_opp_brock"), "normal types only")
  local miss = boot("blue")
  miss:battle({ trainerId = "OPP_BROCK", lead = "RATTATA", during = function()
    miss:emit("battle.battler_switched", { battler = { mon = { species = "SQUIRTLE", level = 10, hp = 10 }, isPlayer = true } })
  end })
  miss:setFlag("EVENT_BEAT_BROCK")
  check(not has(miss, "off_type_opp_brock"), "a water type joined in")
end)

test("Blue gym sweep in one visit", function()
  local env = boot("blue")
  local headers = env.game.data.trainer_headers[env.game.data.maps.PEWTER_GYM.label]
  env:enter("PEWTER_GYM", "PEWTER_CITY")
  for _, h in pairs(headers) do env:setFlag(h.event) end
  env:setFlag("EVENT_BEAT_BROCK")
  check(has(env, "off_gymclear_pewter_gym"), "swept")
  local miss = boot("blue")
  local h1 = next(headers)
  miss:setFlag(headers[h1].event) -- beaten on an earlier visit
  miss:enter("PEWTER_GYM", "PEWTER_CITY")
  for _, h in pairs(headers) do miss:setFlag(h.event) end
  miss:setFlag("EVENT_BEAT_BROCK")
  check(not has(miss, "off_gymclear_pewter_gym"), "not in one visit")
end)

test("League run: solo, and a blackout ends the run", function()
  local env = boot("red")
  setParty(env, { { "RAICHU", 70 } })
  env:enter("LORELEIS_ROOM", "INDIGO_PLATEAU_LOBBY")
  for _, room in ipairs({ "LORELEIS_ROOM", "BRUNOS_ROOM", "AGATHAS_ROOM", "LANCES_ROOM" }) do
    env:enter(room)
    env:battle({ trainerId = "OPP_X" })
  end
  env:enter("CHAMPIONS_ROOM")
  env:battle({ trainerId = "OPP_RIVAL3" })
  check(has(env, "off_league_solo"), "Elite Stomp")
  check(not has(env, "off_league_red_excl"), "not a red-exclusive team")

  local miss = boot("red")
  setParty(miss, { { "RAICHU", 70 } })
  miss:enter("LORELEIS_ROOM", "INDIGO_PLATEAU_LOBBY")
  miss:battle({ trainerId = "OPP_LORELEI" })
  miss:emit("world.blacked_out", {})
  miss:enter("CHAMPIONS_ROOM")
  miss:battle({ trainerId = "OPP_RIVAL3" })
  check(not has(miss, "off_league_solo"), "blacked out")
end)

test("Yellow Jessie and James with only Pikachu", function()
  local env = boot("yellow")
  env:battle({ trainerId = "OPP_ROCKET", lead = "PIKACHU" })
  env:setFlag("EVENT_BEAT_MT_MOON_3_JESSIE_JAMES")
  check(has(env, "off_y_event_beat_mt_moon_3_jessie_james"), "pikachu only")
end)

test("crits, Metronome boom, Ditto, Pay Day", function()
  local env = boot("red")
  local me = { mon = { species = "DITTO", level = 30, hp = 10 }, isPlayer = true }
  local foe = { mon = { species = "DITTO", level = 30, hp = 10 }, isPlayer = false }
  env:battle({ during = function(raw)
    for _ = 1, 5 do env:emit("battle.damage_dealt", { user = me, target = foe, damage = 5, crit = true }) end
    env:emit("battle.move_used", { user = me, target = foe, move = { id = "TRANSFORM" } })
    env:emit("battle.move_used", { user = me, target = foe, move = { id = "EXPLOSION" }, isCalled = true })
  end })
  check(has(env, "off_crits"), "five crits")
  check(has(env, "off_ditto"), "ditto transform")
  check(has(env, "off_metronome_bang"), "metronome explosion")
  local blue = boot("blue")
  blue:battle({ during = function(raw)
    raw.payDay = 2100
    blue:emit("battle.turn_ended", { battle = raw, turn = 3 })
  end })
  check(api(blue).isUnlocked("core:off_pay_day"), "pay day over 2000")
end)

test("level 50 milestones", function()
  local env = boot("red")
  setParty(env, { { "PIKACHU", 50 } })
  env:emit("pokemon.level_up", { mon = { species = "PIKACHU", level = 50, hp = 10 }, level = 50, prevLevel = 49 })
  check(has(env, "off_halfway_solo"), "slot one to 50")
end)

-- -------------------------------------------------------- trackers
test("Safari: ten in one hunt", function()
  local env = boot("red")
  env.game.save.safari = { balls = 30, steps = 500 }
  env:enter("SAFARI_ZONE_CENTER", "SAFARI_ZONE_GATE")
  for i = 1, 9 do env:emit("pokemon.caught", { species = "NIDORAN_M" }) end
  check(not has(env, "off_safari_ten"), "nine")
  env:emit("pokemon.caught", { species = "CHANSEY" })
  check(has(env, "off_safari_ten"), "ten")
  check(has(env, "off_safari_chansey"), "chansey in the safari")
end)

test("slot machine wins are read off the slot screen", function()
  local env = boot("red")
  env.game.stack:push({ screenId = "SlotMachine", winSymbol = "BAR" })
  env:frame(0.3)
  check(has(env, "off_slot_bar"), "bar")
  check(not has(env, "off_slot_seven"), "not a jackpot")
end)

test("gym puzzles: Saffron in four warps, Viridian without spinners", function()
  local env = boot("red")
  env:enter("SAFFRON_GYM", "SAFFRON_CITY")
  for _ = 1, 4 do env:emit("player.warped", { fromMap = "SAFFRON_GYM", toMap = "SAFFRON_GYM" }) end
  env:battle({ trainerId = "OPP_SABRINA" })
  check(has(env, "off_saffron_warps"), "four warps")

  local miss = boot("red")
  miss:enter("VIRIDIAN_GYM", "VIRIDIAN_CITY")
  miss.game.overworld.player.spinning = true
  miss:frame()
  miss.game.overworld.player.spinning = false
  miss:battle({ trainerId = "OPP_GIOVANNI" })
  check(not has(miss, "off_viridian_spin"), "spun once")
end)

test("signs and objects: binoculars, journals", function()
  local env = boot("red")
  env:place("ROUTE_15_GATE_2F", 3, 3, "up")
  env:emit("world.interacted", { mapId = "ROUTE_15_GATE_2F", kind = "sign",
    target = { text = "TEXT_ROUTE15GATE2F_BINOCULARS" } })
  check(has(env, "off_binoculars"), "binoculars facing up")
  env:enter("POKEMON_MANSION_2F", "POKEMON_MANSION_1F")
  for _, t in ipairs({ "TEXT_POKEMONMANSION2F_DIARY1", "TEXT_POKEMONMANSION2F_DIARY2",
                       "TEXT_POKEMONMANSION3F_DIARY", "TEXT_POKEMONMANSIONB1F_DIARY" }) do
    env:emit("world.interacted", { kind = "npc", target = { def = { text = t } } })
  end
  check(has(env, "off_journals"), "all four journals")
end)

test("Yellow: trying to release your Pikachu", function()
  local env = boot("yellow")
  local pika = { species = "PIKACHU", level = 10, hp = 20, otId = 1234, ot = "RED" }
  env.game.save.boxes = { { pika } }
  env.game.save.currentBox = 1
  local list = { kind = "pc_box_release", index = 1 }
  env.game.stack:push(list)
  env:frame(0.3)
  check(not has(env, "off_y_release"), "just looking at the list")
  env.game.stack:push({ text = "PIKACHU looks unhappy about it!" })
  env:frame(0.3)
  check(has(env, "off_y_release"), "refused")
end)

test("Anti-Darwinism: B during an evolution", function()
  local env = boot("red")
  env:emit("screen.popped", { state = { screenId = "EvolutionState", canceled = true } })
  check(has(env, "off_cancel_evolution"), "cancelled")
end)

test("Yellow Pikachu's mood when you talk to it", function()
  local env = boot("yellow")
  local ow = env:place("VIRIDIAN_CITY", 5, 5, "down")
  env.game.save.pikachuHappiness = 95
  env.game.save.pikachuMood = 128
  env.game.save.party = { { species = "PIKACHU", level = 10, hp = 20, otId = 1234, ot = "RED" } }
  env:emit("world.interacted", { kind = "npc", target = { pikachuFollower = true } })
  check(has(env, "off_y_pika_81799"), "51-100 friendship, normal mood")
  env.game.save.party[1].status = "SLP"
  env:emit("world.interacted", { kind = "npc", target = { pikachuFollower = true } })
  check(has(env, "off_y_pika_81817"), "asleep")
  env.game.save.party[1].status = nil
  env.game.save.pikachuEmotionModifier = 1
  env:emit("world.interacted", { kind = "npc", target = { pikachuFollower = true } })
  check(has(env, "off_y_pika_81813"), "after catching a Pokemon")
end)

test("old saves: the Tower ghost is credited from the flag", function()
  local env = boot("yellow")
  env:setFlag("EVENT_BEAT_GHOST_MAROWAK"); env:frame()
  check(has(env, "off_y_tower_ghost"), "backfilled")
end)

test("rules for other games never unlock here", function()
  local env = boot("red")
  env:setFlag("EVENT_BOUGHT_MAGIKARP"); env:frame()
  check(not api(env).isUnlocked("core:off_y_magikarp"), "Yellow-only rule stays out of Red")
  local listed = false
  for _, r in ipairs(api(env).list()) do if r.key == "core:off_y_magikarp" then listed = true end end
  check(not listed, "not even listed")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
H.cleanup()
os.exit(failed == 0 and 0 or 1)
