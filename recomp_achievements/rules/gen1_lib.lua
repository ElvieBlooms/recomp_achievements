-- rules/gen1_lib.lua
-- ==================================================================
-- Small constructors for the official Gen 1 rules, so each entry in
-- rules/gen1_official.lua reads like its RetroAchievements description.
--
-- Every constructor returns a plain rule table (see rules/gen1.lua for
-- the field reference).  `ra` maps a game to the RA achievement id that
-- rule tracks; with official = true the rule only exists on those games
-- and shows RA's own title/description/points when the catalog is
-- installed.  title/description here are the fallback text.
-- ==================================================================

local L = {}

-- Shallow-merge extra fields into a rule.
local function with(rule, extra)
  for k, v in pairs(extra or {}) do rule[k] = v end
  if rule.official == nil then rule.official = true end
  return rule
end
L.with = with

local function set(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end
L.set = set

-- ---------------------------------------------------------- state
function L.flag(id, ra, title, flag, extra)
  return with({ id = id, ra = ra, title = title, kind = "state",
    check = function(f) return f.flag(flag) end }, extra)
end

function L.anyFlag(id, ra, title, flags, extra)
  return with({ id = id, ra = ra, title = title, kind = "state",
    check = function(f)
      for _, name in ipairs(flags) do if f.flag(name) then return true end end
      return false
    end }, extra)
end

-- all flags, with progress n/#flags
function L.allFlags(id, ra, title, flags, extra)
  return with({ id = id, ra = ra, title = title, kind = "state", goal = #flags,
    check = function(f) return f.flags(flags, true) end }, extra)
end

function L.badge(id, ra, title, badge, extra)
  return with({ id = id, ra = ra, title = title, kind = "state", category = "BADGES",
    check = function(f) return f.hasBadge(badge) end }, extra)
end

function L.owns(id, ra, title, species, extra)
  return with({ id = id, ra = ra, title = title, kind = "state", category = "POKEMON",
    check = function(f) return f.owns(species) end }, extra)
end

function L.ownsAll(id, ra, title, list, extra)
  return with({ id = id, ra = ra, title = title, kind = "state", category = "POKEMON",
    goal = #list, unit = "OWNED",
    check = function(f) return (f.ownsCount(list)) end }, extra)
end

function L.dexAtLeast(id, ra, title, n, extra)
  return with({ id = id, ra = ra, title = title, kind = "state", category = "POKEDEX",
    goal = n, unit = "OWNED",
    check = function(f) return f.dexOwned() end }, extra)
end

function L.item(id, ra, title, item, extra)
  return with({ id = id, ra = ra, title = title, kind = "state", category = "ITEMS",
    check = function(f) return f.hasItem(item) end }, extra)
end

-- Clear areas: maps is a list of map ids or a function(f) -> list.
-- what = "trainers" | "items" | "both".  Progress is a percentage, since
-- totals come from the game's own data.
function L.sweep(id, ra, title, maps, what, opts, extra)
  opts = opts or {}
  return with({ id = id, ra = ra, title = title, kind = "state", category = "CLEAR",
    goal = 100, unit = "PERCENT",
    check = function(f)
      local list = type(maps) == "function" and maps(f) or maps
      local done, total = f.sweep(list, what, opts)
      if opts.extraFlags then
        local flags = type(opts.extraFlags) == "function" and opts.extraFlags(f) or opts.extraFlags
        for _, flag in ipairs(flags) do
          total = total + 1
          if f.flag(flag) then done = done + 1 end
        end
      end
      if total == 0 then return false end
      if done >= total then return true end
      return math.floor(done * 100 / total)
    end }, extra)
end

-- ---------------------------------------------------------- events
function L.onEvent(id, ra, title, event, test, extra)
  return with({ id = id, ra = ra, title = title, kind = "event", on = event,
    test = test }, extra)
end

-- Caught a species (optionally only on maps matching a pattern).
function L.caught(id, ra, title, speciesSet, mapPattern, extra)
  return L.onEvent(id, ra, title, "pokemon.caught", function(ev, _, ctx)
    if not (ev and speciesSet[ev.species]) then return false end
    if mapPattern and not (ctx.map and tostring(ctx.map):find(mapPattern)) then return false end
    return true
  end, with({ category = "POKEMON" }, extra))
end

-- ---------------------------------------------------------- trackers
function L.tracker(id, ra, title, on, init, extra)
  return with({ id = id, ra = ra, title = title, kind = "tracker", on = on,
    init = init }, extra)
end

-- Did every Pokemon the player sent out in battle `b` satisfy pred?
function L.usedOnly(b, pred)
  if not (b and b.used and #b.used > 0) then return false end
  for _, species in ipairs(b.used) do
    if not pred(species) then return false end
  end
  return true
end

-- A gym leader beaten under conditions read from the battle that just
-- ended.  Fires on the leader's story flag, which the engine sets in the
-- battle's onFinish (after battle.ended), so ctx.lastBattle is that fight.
function L.leaderChallenge(id, ra, title, leaderFlag, trainerId, cond, extra)
  return L.tracker(id, ra, title, {
    ["flag.changed"] = function(_, ev, f, ctx)
      if not (ev and ev.name == leaderFlag and ev.value) then return end
      local b = ctx.lastBattle
      if not (b and b.trainerId == trainerId and b.result == "win") then return end
      return cond(b, f) == true
    end,
  }, nil, with({ category = "GYMS" }, extra))
end

-- "Set mode, no items in battle, no Pokemon above level N at the start"
function L.setModeCap(cap)
  return function(b)
    return b.style == "set" and not b.itemsUsed and (b.partyMaxAtStart or 999) <= cap
  end
end

-- "while only using <type> Pokemon"
function L.onlyType(typeId)
  return function(b, f)
    return L.usedOnly(b, function(s) return f.hasType(s, typeId) end)
  end
end

-- ---------------------------------------------------------- data
L.RED_EXCLUSIVES = { "EKANS", "ARBOK", "ODDISH", "GLOOM", "VILEPLUME", "MANKEY",
  "PRIMEAPE", "GROWLITHE", "ARCANINE", "SCYTHER", "ELECTABUZZ" }
L.BLUE_EXCLUSIVES = { "SANDSHREW", "SANDSLASH", "VULPIX", "NINETALES", "MEOWTH",
  "PERSIAN", "BELLSPROUT", "WEEPINBELL", "VICTREEBEL", "MAGMAR", "PINSIR" }
L.BIRDS = { "ARTICUNO", "ZAPDOS", "MOLTRES" }

L.GYMS = {
  { map = "PEWTER_GYM",    flag = "EVENT_BEAT_BROCK",    opp = "OPP_BROCK" },
  { map = "CERULEAN_GYM",  flag = "EVENT_BEAT_MISTY",    opp = "OPP_MISTY" },
  { map = "VERMILION_GYM", flag = "EVENT_BEAT_LT_SURGE", opp = "OPP_LT_SURGE" },
  { map = "CELADON_GYM",   flag = "EVENT_BEAT_ERIKA",    opp = "OPP_ERIKA" },
  { map = "FUCHSIA_GYM",   flag = "EVENT_BEAT_KOGA",     opp = "OPP_KOGA" },
  { map = "SAFFRON_GYM",   flag = "EVENT_BEAT_SABRINA",  opp = "OPP_SABRINA" },
  { map = "CINNABAR_GYM",  flag = "EVENT_BEAT_BLAINE",   opp = "OPP_BLAINE" },
  { map = "VIRIDIAN_GYM",  flag = "EVENT_BEAT_GIOVANNI", opp = "OPP_GIOVANNI" },
}

-- Pokemon League rooms, in order.  The champion fight is OPP_RIVAL3 in
-- CHAMPIONS_ROOM.
L.LEAGUE_MAPS = set({ "LORELEIS_ROOM", "BRUNOS_ROOM", "AGATHAS_ROOM", "LANCES_ROOM",
  "CHAMPIONS_ROOM" })

-- A whole League run under a party condition.  The run starts when the
-- player walks into Lorelei's room, fails on a blackout, a lost battle,
-- or leaving the League, and is won when the champion falls.
--   partyOk(party, f)    checked at the start and before every battle
--   battleOk(b, f)       checked after every League battle (optional)
--   startOk(party, f)    checked once when the run starts (optional)
function L.leagueRun(id, ra, title, partyOk, battleOk, startOk, extra)
  local function fail(state) state.run = nil end
  return L.tracker(id, ra, title, {
    ["map.entered"] = function(state, ev, f)
      local map = ev and ev.mapId
      if map == "LORELEIS_ROOM" and (not state.run) then
        local party = f.party()
        if partyOk(party, f) and (not startOk or startOk(party, f)) then
          state.run = { ok = true }
        end
      elseif state.run and not L.LEAGUE_MAPS[map] then
        fail(state)
      end
    end,
    ["battle.started"] = function(state, _, f)
      if state.run and not partyOk(f.party(), f) then fail(state) end
    end,
    ["world.blacked_out"] = function(state) fail(state) end,
    ["battle.ended"] = function(state, ev, f, ctx)
      local run = state.run
      if not run then return end
      local b = ctx.battle
      if not ev or ev.result ~= "win" then fail(state) return end
      if battleOk and not battleOk(b, f) then fail(state) return end
      if not partyOk(f.party(), f) then fail(state) return end
      if ctx.map == "CHAMPIONS_ROOM" and b and b.trainerId == "OPP_RIVAL3" then
        state.run = nil
        return true
      end
    end,
  }, nil, with({ category = "LEAGUE" }, extra))
end

function L.partyAll(pred)
  return function(party, f)
    if #party == 0 then return false end
    for _, m in ipairs(party) do if not pred(m, f) then return false end end
    return true
  end
end

return L
