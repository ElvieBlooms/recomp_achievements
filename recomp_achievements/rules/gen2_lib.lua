-- rules/gen2_lib.lua
-- ==================================================================
-- Building blocks for rules/gen2_official.lua, the Gen 2 counterpart of
-- rules/gen1_lib.lua.  Each constructor returns one rule table.
--
--   ra    = { gold = <RA id>, silver = <RA id>, crystal = <RA id> }
--           links the rule to RetroAchievements entries; the registry
--           only offers it on the games listed.
--   extra = optional fields merged in last (points/category/goal/unit,
--           fidelity = "interpretation" + note for local readings).
--
-- Facts come from adapters/gen2.lua.  Event flags are named the pret way
-- ("EVENT_BEAT_FALKNER"); the adapter turns names into each game's own
-- numbers (data/gen2_<game>.lua), so one rule serves Gold, Silver and
-- Crystal even where Crystal numbers its flags differently.
-- ==================================================================

local L = {}

-- Every rule here is an official one: the registry then offers it only on
-- the games its `ra` table names.
local function with(rule, extra)
  for k, v in pairs(extra or {}) do rule[k] = v end
  if rule.official == nil then rule.official = true end
  return rule
end
L.with = with

local function set(list)
  local out = {}
  for _, v in ipairs(list) do out[v] = true end
  return out
end
L.set = set

-- ---------------------------------------------------------- state
function L.state(id, ra, title, check, extra)
  return with({ id = id, ra = ra, title = title, kind = "state", check = check }, extra)
end

function L.flag(id, ra, title, flag, extra)
  return L.state(id, ra, title, function(f) return f.flag(flag) end, extra)
end

function L.allFlags(id, ra, title, flags, extra)
  return L.state(id, ra, title, function(f)
    local n = f.countFlags(flags)
    return n >= #flags or (extra and extra.goal and n) or false
  end, extra)
end

function L.anyFlag(id, ra, title, flags, extra)
  return L.state(id, ra, title, function(f)
    for _, name in ipairs(flags) do if f.flag(name) then return true end end
    return false
  end, extra)
end

function L.badge(id, ra, title, badge, extra)
  return L.state(id, ra, title, function(f) return f.hasBadge(badge) end,
    with({ category = "GYMS" }, extra))
end

function L.owns(id, ra, title, species, extra)
  return L.state(id, ra, title, function(f) return f.owns(species) end,
    with({ category = "POKEMON" }, extra))
end

function L.ownsAll(id, ra, title, list, extra)
  return L.state(id, ra, title, function(f)
    for _, s in ipairs(list) do if not f.owns(s) then return false end end
    return true
  end, with({ category = "POKEMON" }, extra))
end

function L.dexAtLeast(id, ra, title, n, extra)
  return L.state(id, ra, title, function(f) return f.dexOwned() end,
    with({ goal = n, unit = "POKEMON", category = "POKEDEX" }, extra))
end

-- Share of a generated list (trainers/items/hidden/gifts) that is done.
-- `percent` of the rows passing `keep` must be done.  Progress is in
-- percent (the list's length depends on the game version).
function L.sweep(id, ra, title, kind, keep, percent, extra)
  return L.state(id, ra, title, function(f)
    local done, total = f.sweep(kind, keep)
    if total == 0 then return false end
    return math.min(percent, math.floor(done * 100 / total))
  end, with({ category = "COMPLETION", goal = percent, unit = "PCT" }, extra))
end

-- ---------------------------------------------------------- events
function L.onEvent(id, ra, title, event, test, extra)
  return with({ id = id, ra = ra, title = title, kind = "event", on = event, test = test }, extra)
end

function L.tracker(id, ra, title, on, init, extra)
  return with({ id = id, ra = ra, title = title, kind = "tracker", on = on, init = init }, extra)
end

-- A flag the game sets at New Game to hide something, then clears and
-- sets again when the moment happens (Suicune sightings, the Machine
-- Part).  Counted when it's seen going from clear to set; `check` credits
-- old saves from something that can only be true afterwards.
function L.flagRises(id, ra, title, flag, check, extra)
  local rule = L.tracker(id, ra, title, {
    tick = function(s, _, f)
      local v = f.flag(flag)
      local rose = s.prev == false and v
      s.prev = v
      return rose or nil
    end,
  }, nil, extra)
  rule.check = check
  return rule
end

-- A wild catch of one species, optionally refusing a ball (e.g. MASTER_BALL).
function L.caught(id, ra, title, species, notBall, extra)
  return L.onEvent(id, ra, title, "pokemon.caught", function(ev)
    if not (ev and ev.species == species) then return false end
    return notBall == nil or ev.ball ~= notBall
  end, with({ category = "POKEMON" }, extra))
end

-- ---------------------------------------------------------- battles
-- Highest level of any Pokemon in the party right now (eggs excluded).
function L.partyMax(f)
  local best = 0
  for _, m in ipairs(f.party()) do
    if type(m) == "table" and not m.isEgg then best = math.max(best, tonumber(m.level) or 0) end
  end
  return best
end

function L.partyCount(f)
  local n = 0
  for _, m in ipairs(f.party()) do if type(m) == "table" and not m.isEgg then n = n + 1 end end
  return n
end

-- Every species sent out in the battle passes pred.
function L.usedOnly(b, pred)
  local any = false
  for _, s in ipairs(b.used or {}) do
    any = true
    if not pred(s) then return false end
  end
  return any
end

-- Won a battle against `trainerClass` and cond(battle, facts) holds.  Gen 2
-- battles carry the trainer class ("FALKNER") straight from the battle.
function L.beatTrainer(id, ra, title, trainerClass, cond, extra)
  return L.onEvent(id, ra, title, "battle.ended", function(ev, f, ctx)
    local b = ctx.battle
    if not (b and ev and ev.result == "win" and b.trainerId == trainerClass) then return false end
    return cond == nil or cond(b, f) == true
  end, with({ category = "GYMS" }, extra))
end

-- Challenge rules (RA's "Set mode"): the SET battle style from OPTION >
-- BATTLE STYLE, no Pokemon above `cap` at the start or the end.
L.CHALLENGE = "Challenge: set OPTION > BATTLE STYLE to SET"

function L.prettyName(id)
  local s = tostring(id):lower():gsub("_", " ")
  return (s:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

function L.setCap(cap)
  return function(b, f)
    return b.style == "set" and (b.partyMaxAtStart or 999) <= cap and L.partyMax(f) <= cap
  end
end

-- ...and only Pokemon of `typeId` were sent out (any of a list).
function L.onlyTypes(types)
  return function(b, f)
    return L.usedOnly(b, function(s)
      for _, t in ipairs(types) do if f.hasType(s, t) then return true end end
      return false
    end)
  end
end

-- Crystal's "only Johto Pokemon, no Pack items" family.
L.LEGENDARY_EXCEPT_BEASTS = set({ "LUGIA", "HO_OH", "MEWTWO", "MEW", "CELEBI", "ARTICUNO", "ZAPDOS", "MOLTRES" })
L.LUGIA_HOOH = set({ "LUGIA", "HO_OH" })
function L.johtoOnly(cap, excluded)
  return function(b, f)
    if not L.setCap(cap)(b, f) or b.itemsUsed then return false end
    return L.usedOnly(b, function(s) return f.isJohto(s) and not (excluded and excluded[s]) end)
  end
end

function L.all(...)
  local conds = { ... }
  return function(b, f)
    for _, c in ipairs(conds) do if not c(b, f) then return false end end
    return true
  end
end

-- The Elite Four and the Champion in one go.  battleOk(battle, facts) must
-- hold for every league battle (checked at its end); startOk(facts) when
-- each league battle starts.  A loss or a failed check ends the run; the
-- Champion's defeat with all four beaten in this run unlocks.
L.ELITE = { "WILL", "KOGA", "BRUNO", "KAREN" }
function L.leagueRun(id, ra, title, startOk, battleOk, extra)
  local league = set({ "WILL", "KOGA", "BRUNO", "KAREN", "CHAMPION" })
  return L.tracker(id, ra, title, {
    ["battle.started"] = function(s, ev, f, ctx)
      local who = ctx.battle and ctx.battle.trainerId
      if not league[who] then return end
      if who == "WILL" then s.beaten, s.broken = {}, false end -- a fresh attempt
      if startOk and not startOk(f) then s.broken = true end
    end,
    ["battle.ended"] = function(s, ev, f, ctx)
      local b = ctx.battle
      local who = b and b.trainerId
      if not league[who] then return end
      if not (ev and ev.result == "win") or (battleOk and not battleOk(b, f)) then
        s.broken = true
        return
      end
      s.beaten = s.beaten or {}
      s.beaten[who] = true
      if who == "CHAMPION" and not s.broken then
        for _, e in ipairs(L.ELITE) do if not s.beaten[e] then return end end
        return true
      end
    end,
  }, function(s) s.beaten, s.broken = {}, true end, with({ category = "LEAGUE" }, extra))
end

-- ---------------------------------------------------------- map data
-- keep() helpers for L.sweep: by region, by map name prefix, by item.
function L.region(...)
  local want = set({ ... })
  return function(row) return want[row[#row]] == true end
end

function L.maps(prefixes, region)
  return function(row)
    local map = row[3]
    if #row == 5 then map = row[4] end
    if region and row[#row] ~= region then return false end
    for _, p in ipairs(prefixes) do
      if map:sub(1, #p) == p then return true end
    end
    return false
  end
end

function L.isTM(row) return row[3]:match("^TM_") ~= nil or row[3]:match("^HM_") ~= nil end

return L
