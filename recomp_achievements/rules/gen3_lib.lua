-- rules/gen3_lib.lua
-- ==================================================================
-- Building blocks for rules/gen3_official.lua, the Gen 3 counterpart of
-- rules/gen2_lib.lua.  Each constructor returns one rule table.
--
--   ra    = { firered = <RA id>, leafgreen = <RA id> } links the rule to
--           RetroAchievements entries; it's only offered on those games.
--   extra = optional fields merged in last (points/category/goal/unit,
--           fidelity = "interpretation" + note for local readings).
--
-- Facts come from adapters/gen3.lua.  Flags, trainers, species and items
-- use pret's names ("FLAG_GOT_EEVEE", "TRAINER_LEADER_BROCK", "SNORLAX");
-- the adapter turns them into the save's numbers (data/gen3_frlg.lua).
-- ==================================================================

local L = {}

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

function L.prettyName(id)
  local s = tostring(id):lower():gsub("_", " ")
  return (s:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

-- ---------------------------------------------------------- state
function L.state(id, ra, title, check, extra)
  return with({ id = id, ra = ra, title = title, kind = "state", check = check }, extra)
end

function L.flag(id, ra, title, flag, extra)
  return L.state(id, ra, title, function(f) return f.flag(flag) end, extra)
end

function L.allFlags(id, ra, title, flags, extra)
  extra = extra or {}
  if extra.goal == nil and #flags > 1 then extra.goal = #flags end
  return L.state(id, ra, title, function(f)
    local n = f.countFlags(flags)
    if n >= #flags then return true end
    return extra.goal and n or false
  end, extra)
end

function L.anyFlag(id, ra, title, flags, extra)
  return L.state(id, ra, title, function(f) return f.anyFlag(flags) end, extra)
end

-- The same encounter under each starter the rival could have picked.
function L.rival(stem)
  return { stem .. "_SQUIRTLE", stem .. "_BULBASAUR", stem .. "_CHARMANDER" }
end

function L.badge(id, ra, title, n, extra)
  return L.flag(id, ra, title, ("FLAG_BADGE%02d_GET"):format(n), with({ category = "GYMS" }, extra))
end

function L.hasItem(id, ra, title, item, extra)
  return L.state(id, ra, title, function(f) return f.hasItem(item) end, extra)
end

function L.var(id, ra, title, var, atLeast, extra)
  return L.state(id, ra, title, function(f) return f.var(var) >= atLeast end, extra)
end

-- ---------------------------------------------------------- Pokemon
function L.owns(id, ra, title, species, extra)
  return L.state(id, ra, title, function(f) return f.owns(species) end,
    with({ category = "POKEMON" }, extra))
end

function L.ownsAny(id, ra, title, list, extra)
  return L.state(id, ra, title, function(f)
    for _, s in ipairs(list) do if f.owns(s) then return true end end
    return false
  end, with({ category = "POKEMON" }, extra))
end

function L.dexAtLeast(id, ra, title, n, extra)
  return L.state(id, ra, title, function(f) return f.dexOwned() end,
    with({ goal = n, unit = "POKEMON", category = "POKEDEX" }, extra))
end

-- ---------------------------------------------------------- events
function L.onEvent(id, ra, title, event, test, extra)
  return with({ id = id, ra = ra, title = title, kind = "event", on = event, test = test }, extra)
end

function L.tracker(id, ra, title, on, init, extra)
  return with({ id = id, ra = ra, title = title, kind = "tracker", on = on, init = init }, extra)
end

-- ---------------------------------------------------------- areas
-- Map matching: "MtMoon" matches MtMoon and MtMoon_<anything>.  Gyms are
-- left out (their trainers are marked beaten when the leader falls, and
-- they have achievements of their own), and so are rival battles (only
-- one of the three versions is ever fought).
local function inMaps(map, list, skip)
  for _, s in ipairs(skip or {}) do
    if map == s or map:sub(1, #s + 1) == s .. "_" then return false end
  end
  if map:match("_Gym$") then return false end
  for _, m in ipairs(list) do
    if map == m or map:sub(1, #m + 1) == m .. "_" then return true end
  end
  return false
end
L.inMaps = inMaps

local NOT_SWEPT = { "TRAINER_RIVAL_", "TRAINER_CHAMPION_" }
local function sweepable(row)
  local name = row[2]
  for _, p in ipairs(NOT_SWEPT) do if name:sub(1, #p) == p then return false end end
  return true
end

-- Every trainer beaten / item found in an area.  opts:
--   maps     map names (prefix match, see inMaps)
--   skip     map names to leave out
--   kinds    which lists count: { "trainers", "items", "hidden" } by default
--   noItem   items that don't count ({ "TINY_MUSHROOM" = true })
-- Progress is in percent (the lists come from the game data at run time).
function L.area(id, ra, title, opts, extra)
  local kinds = opts.kinds or { "trainers", "items", "hidden" }
  local memo = setmetatable({}, { __mode = "k" }) -- rows never change
  local function test(row)
    local map = row[#row - 1]
    if not inMaps(map, opts.maps, opts.skip) then return false end
    if row[2]:match("^TRAINER_") then return sweepable(row) end
    if opts.noItem and opts.noItem[row[3]] then return false end
    return true
  end
  local function keep(row)
    local v = memo[row]
    if v == nil then v = test(row); memo[row] = v end
    return v
  end
  return L.state(id, ra, title, function(f)
    local done, total = 0, 0
    for _, kind in ipairs(kinds) do
      local d, t = f.sweep(kind, keep)
      done, total = done + d, total + t
    end
    if total == 0 then return false end
    if done >= total then return true end
    return math.floor(done * 100 / total)
  end, with({ category = "COMPLETION", goal = 100, unit = "PCT",
              fidelity = "interpretation" }, extra))
end

-- A gym's trainers, beaten before its leader.  The game marks them all
-- beaten when the leader falls, so wins are counted as they happen; a
-- save where every one is beaten while the leader isn't also counts.
function L.gymTrainers(id, ra, title, gym, leaderFlag, extra)
  local rule = L.tracker(id, ra, title, {
    ["battle.ended"] = function(s, ev, f, ctx)
      local b = ctx.battle
      if not (b and ev and ev.result == "win" and b.trainerId) then return end
      local list = f.data().gymTrainers and f.data().gymTrainers[gym] or {}
      s.beaten = s.beaten or {}
      for _, name in ipairs(list) do
        if name == b.trainerId then s.beaten[name] = true end
      end
      if f.flag(leaderFlag) then return end
      local n = 0
      for _, name in ipairs(list) do if s.beaten[name] or f.flag(name) then n = n + 1 end end
      return #list > 0 and n >= #list or nil
    end,
  }, function(s) s.beaten = {} end, with({ category = "GYMS" }, extra))
  rule.check = function(f)
    local list = f.data().gymTrainers and f.data().gymTrainers[gym] or {}
    if #list == 0 or f.flag(leaderFlag) then return false end
    return f.allFlags(list)
  end
  return rule
end

-- ---------------------------------------------------------- battles
function L.partyMax(f)
  local best = 0
  for _, m in ipairs(f.party()) do
    if not m.isEgg then best = math.max(best, tonumber(m.level) or 0) end
  end
  return best
end

local function partyCount(list)
  local n = 0
  for _, m in ipairs(list or {}) do if type(m) == "table" and not m.isEgg then n = n + 1 end end
  return n
end
L.partyCount = partyCount

-- Won a battle against one of `trainers` (a name or list) and cond holds.
function L.beatTrainer(id, ra, title, trainers, cond, extra)
  local want = set(type(trainers) == "table" and trainers or { trainers })
  return L.onEvent(id, ra, title, "battle.ended", function(ev, f, ctx)
    local b = ctx.battle
    if not (b and ev and ev.result == "win" and want[b.trainerId]) then return false end
    return cond == nil or cond(b, f) == true
  end, with({ category = "GYMS" }, extra))
end

-- Challenge rules (RA's "Set mode"): the SET battle style from OPTION >
-- BATTLE STYLE, at most `count` Pokemon (party size at the start), none
-- above `cap` at the start or the end.
L.CHALLENGE = "Challenge: set OPTION > BATTLE STYLE to SET"

function L.setCap(count, cap)
  return function(b, f)
    return b.style == "set" and partyCount(b.partyAtStart) <= count
      and (b.partyMaxAtStart or 999) <= cap and L.partyMax(f) <= cap
  end
end

-- The Elite Four and the Champion in one go.  `elite` lists the four,
-- `champions` the champion's versions.  startOk(facts) must hold when each
-- league battle starts; a loss or a failed check ends the run.
function L.leagueRun(id, ra, title, elite, champions, startOk, extra)
  local league, champ = set(elite), set(champions)
  for k in pairs(champ) do league[k] = true end
  return L.tracker(id, ra, title, {
    ["battle.started"] = function(s, ev, f, ctx)
      local who = ctx.battle and ctx.battle.trainerId
      if not league[who] then return end
      if who == elite[1] then s.beaten, s.broken = {}, false end -- a fresh attempt
      if startOk and not startOk(f) then s.broken = true end
    end,
    ["battle.ended"] = function(s, ev, f, ctx)
      local b = ctx.battle
      local who = b and b.trainerId
      if not league[who] then return end
      if not (ev and ev.result == "win") then s.broken = true return end
      s.beaten = s.beaten or {}
      s.beaten[who] = true
      if champ[who] and not s.broken then
        for _, e in ipairs(elite) do if not s.beaten[e] then return end end
        return true
      end
    end,
  }, function(s) s.beaten, s.broken = {}, true end, with({ category = "LEAGUE" }, extra))
end

return L
