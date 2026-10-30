-- adapters/gen3.lua
-- ==================================================================
-- FireRed/LeafGreen (and later Ruby/Sapphire/Emerald) state as plain
-- "facts" for the rules, the same idea as adapters/gen1.lua and gen2.lua.
-- Engine 0.3.97 Gen 3 save (the live session; game.save is that table):
--
--   save.version            "firered" | "leafgreen" | "ruby" | "sapphire" | "emerald"
--   save.flags[n] = true    pret flag numbers (FLAG_BADGE01_GET = 0x820);
--                           trainer flags are TRAINER_FLAGS_START + trainer
--   save.vars[n]            pret var numbers (VAR_* >= 0x4000)
--   save.dex.caught/seen[n] internal species numbers (Treecko is 277)
--   save.party, save.storage.boxes[1..14]   mons: { species (internal), level, isEgg, ... }
--   save.bag.pockets.<POCKET> = { { id, qty }, ... }; save.storage.items the PC
--   save.gameStats[n]       pret GAME_STAT_* counters
--   save.playTime = { hours, minutes, seconds }
--   save.engineOptions[<block>].battleStyle   0 SHIFT, 1 SET
--   save.trainerTower / modData.trainerTower, save.fameChecker   (FRLG)
--
-- Flag and species names come from data/gen3_<family>.lua (tools/gen3_data.py),
-- generated from pret, so rules say "FLAG_GOT_EEVEE" and "SNORLAX".
-- ==================================================================

local Gen3 = {}
Gen3.__index = Gen3

Gen3.FAMILY = { firered = "frlg", leafgreen = "frlg" }
Gen3.KANTO = { "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO", "EARTH" }

local EMPTY = { flags = {}, trainerIds = {}, vars = {}, species = {}, itemIds = {},
                trainers = {}, items = {}, hidden = {}, gifts = {}, rematches = {}, initial = {} }

-- loadData(family) returns data/gen3_<family>.lua.
function Gen3.new(mod, util, loadData)
  local self = setmetatable({ mod = mod, util = util, loadData = loadData, cache = {}, live = {} }, Gen3)
  -- During play the game keeps flags in its script engine's own store and
  -- copies them into the save only now and then (map changes, the START
  -- menu, saving).  flag.changed reports every change as it happens, so
  -- those are kept here and win over the save until the next load.
  if mod and mod.events and mod.events.on then
    mod.events:on("flag.changed", function(ev)
      local id = type(ev) == "table" and tonumber(ev.id) or nil
      if id then self.live[id] = ev.value and true or false end
    end)
    for _, name in ipairs({ "save.loading", "save.loaded", "save.created" }) do
      mod.events:on(name, function() self.live = {} end)
    end
  end
  return self
end

function Gen3:game() return self.mod.game end

-- The live save.  When save.loaded fires, mod.game.save may not point at
-- it yet, so the engine also hands over the event's save (eventSave).
function Gen3:save()
  local game = self.mod.game
  local live = game and game.save
  if type(live) == "table" and Gen3.FAMILY[live.version] then return live end
  local ev = self.eventSave
  if type(ev) == "table" and Gen3.FAMILY[ev.version] then return ev end
  return live
end

function Gen3:version()
  local save = self:save()
  if type(save) ~= "table" then return nil end
  local v = save.version
  if not Gen3.FAMILY[v] then return nil end
  return v
end

function Gen3:data()
  local v = self:version()
  local fam = v and Gen3.FAMILY[v]
  if not fam then return EMPTY end
  if self.cache[fam] == nil then
    local ok, d = pcall(self.loadData or function() return nil end, fam)
    self.cache[fam] = ok and type(d) == "table" and d or false
    if self.cache[fam] then
      local d2 = self.cache[fam]
      d2.speciesNames = {}
      for name, n in pairs(d2.species or {}) do d2.speciesNames[n] = name end
      d2.itemNames = {}
      for name, n in pairs(d2.itemIds or {}) do d2.itemNames[n] = name end
    end
  end
  return self.cache[fam] or EMPTY
end

function Gen3:playTime()
  local save = self:save()
  local pt = save and save.playTime
  if type(pt) == "number" then return math.floor(pt) end
  if type(pt) ~= "table" then return nil end
  return (tonumber(pt.hours) or 0) * 3600 + (tonumber(pt.minutes) or 0) * 60 + (tonumber(pt.seconds) or 0)
end

local function count(t)
  local n = 0
  for _, v in pairs(t or {}) do if v then n = n + 1 end end
  return n
end

-- A species as its pret name ("SNORLAX"), from a number or a name.
function Gen3:speciesName(x)
  if type(x) == "number" then return self:data().speciesNames[x] or x end
  if type(x) == "string" then return x:upper() end
  return x
end

function Gen3:speciesId(x)
  if type(x) == "number" then return x end
  return self:data().species[tostring(x):upper()]
end

-- A flag by number or pret name (FLAG_* or TRAINER_* for its trainer flag).
function Gen3:flag(id)
  if type(id) == "string" then
    local n = self:data().flags[id]
    if not n then return nil end
    id = n
  end
  if type(id) ~= "number" then return nil end
  local live = self.live[id]
  if live ~= nil then return live end
  local save = self:save()
  local flags = save and save.flags
  if type(flags) ~= "table" then return false end
  -- the game writes numeric keys, and string ones through some paths
  local v = flags[id]
  if v == nil then v = flags[tostring(id)] end
  return v == true or v == 1
end

function Gen3:var(id)
  if type(id) == "string" then id = self:data().vars[id] end
  local save = self:save()
  local vars = save and save.vars
  if type(id) ~= "number" or type(vars) ~= "table" then return 0 end
  return tonumber(vars[id]) or tonumber(vars[tostring(id)]) or 0
end

-- Every stored Pokemon, eggs excluded unless asked.
function Gen3:eachMon(fn, withEggs)
  local save = self:save()
  if type(save) ~= "table" then return end
  local function visit(list)
    if type(list) ~= "table" then return end
    for _, mon in pairs(list) do
      if type(mon) == "table" and (mon.species or mon.speciesId) and (withEggs or not mon.isEgg) then fn(mon) end
    end
  end
  visit(save.party)
  local st = save.storage
  if type(st) == "table" and type(st.boxes) == "table" then
    for _, box in pairs(st.boxes) do
      if type(box) == "table" then visit(box.mons or box) end
    end
  end
end

local function monSpecies(self, m)
  return self:speciesName(tonumber(m.speciesId or m.species) or m.species)
end

function Gen3:partySnapshot()
  local save = self:save()
  local out = {}
  for i, mon in ipairs(save and save.party or {}) do
    if type(mon) == "table" then
      out[i] = { species = monSpecies(self, mon), level = tonumber(mon.level) or 0, isEgg = mon.isEgg }
    end
  end
  return out
end

-- item id -> quantity across the bag pockets (PC excluded: it isn't usable in battle).
function Gen3:bagSnapshot()
  local save = self:save()
  local out = {}
  local bag = save and save.bag
  for _, pocket in pairs(type(bag) == "table" and bag.pockets or {}) do
    if type(pocket) == "table" then
      for _, slot in pairs(pocket) do
        if type(slot) == "table" and slot.id then
          out[slot.id] = (out[slot.id] or 0) + (tonumber(slot.qty) or 0)
        end
      end
    end
  end
  return out
end

-- battle.started gives the trainer as a number; rules use pret names.
function Gen3:battleInfo(ev)
  local id = type(ev) == "table" and tonumber(ev.trainerId) or nil
  return { trainerName = id and self:data().trainerIds[id] or nil }
end

-- The SET/SHIFT battle style from the game's own OPTION menu.
function Gen3:battleStyle()
  local save = self:save() or {}
  for _, block in pairs(type(save.engineOptions) == "table" and save.engineOptions or {}) do
    if type(block) == "table" and tonumber(block.battleStyle) then
      return tonumber(block.battleStyle) == 1 and "set" or "shift"
    end
  end
  local o = type(save.options) == "table" and save.options or {}
  if tonumber(o.battleStyle) then return tonumber(o.battleStyle) == 1 and "set" or "shift" end
  return "shift"
end

function Gen3:facts()
  local save = self:save() or {}
  local dex = type(save.dex) == "table" and save.dex or {}
  local caught = type(dex.caught) == "table" and dex.caught or (type(dex.owned) == "table" and dex.owned) or {}
  local seen = type(dex.seen) == "table" and dex.seen or {}
  local stats = type(save.gameStats) == "table" and save.gameStats or {}
  local modData = type(save.modData) == "table" and save.modData or {}
  local self_ = self
  local f = {}
  f.version = save.version
  f.generation = 3
  f.flag = function(id) return self_:flag(id) == true end
  f.var = function(id) return self_:var(id) end
  f.allFlags = function(list) for _, id in ipairs(list) do if not f.flag(id) then return false end end return true end
  f.countFlags = function(list) local n = 0 for _, id in ipairs(list) do if f.flag(id) then n = n + 1 end end return n end
  f.anyFlag = function(list) for _, id in ipairs(list) do if f.flag(id) then return true end end return false end
  f.hasBadge = function(name)
    for i, b in ipairs(Gen3.KANTO) do
      if b == name then return f.flag(("FLAG_BADGE%02d_GET"):format(i)) end
    end
    return false
  end
  f.badgeCount = function()
    local n = 0
    for i = 1, 8 do if f.flag(("FLAG_BADGE%02d_GET"):format(i)) then n = n + 1 end end
    return n
  end
  f.money = function() return tonumber(save.money) or 0 end
  f.coins = function() return tonumber(save.coins) or 0 end
  f.speciesName = function(x) return self_:speciesName(x) end
  f.dexOwned = function() return count(caught) end
  f.dexSeen = function() return count(seen) end
  f.owns = function(species)
    local n = self_:speciesId(species)
    return n ~= nil and (caught[n] == true or caught[tostring(n)] == true)
  end
  f.party = function()
    local out = {}
    for _, m in ipairs(type(save.party) == "table" and save.party or {}) do
      if type(m) == "table" then
        out[#out + 1] = { species = monSpecies(self_, m), level = tonumber(m.level) or 0, isEgg = m.isEgg, raw = m }
      end
    end
    return out
  end
  f.partySize = function() return #f.party() end
  f.has = function(species)
    local want, found = tostring(species):upper(), false
    self_:eachMon(function(m) if monSpecies(self_, m) == want then found = true end end)
    return found
  end
  f.itemCount = function(name)
    local id = type(name) == "number" and name or self_:data().itemIds[tostring(name):upper()]
    if not id then return 0 end
    local n = self_:bagSnapshot()[id] or 0
    local st = save.storage
    for _, slot in pairs(type(st) == "table" and type(st.items) == "table" and st.items or {}) do
      if type(slot) == "table" and slot.id == id then n = n + (tonumber(slot.qty) or 0) end
    end
    return n
  end
  f.hasItem = function(name) return f.itemCount(name) > 0 end
  f.gameStat = function(n) return tonumber(stats[n]) or tonumber(stats[tostring(n)]) or 0 end
  f.battleStyle = function() return self_:battleStyle() end
  f.gameCleared = function() return save.game_cleared == true or f.flag("FLAG_SYS_GAME_CLEAR") end
  -- Trainer Tower (FRLG): a challenge is cleared once it has a best time.
  f.trainerTowerCleared = function(mode)
    local tt = type(save.trainerTower) == "table" and save.trainerTower or modData.trainerTower
    local rec = type(tt) == "table" and type(tt.records) == "table" and tt.records[mode + 1] or nil
    return type(rec) == "table" and (tonumber(rec.bestTime) or 215999) < 215999
  end
  -- Fame Checker (FRLG): people fully filled in (picture plus all 6 facts).
  f.fameCheckerFull = function()
    local recs = type(save.fameChecker) == "table" and save.fameChecker or modData.fameChecker
    if type(recs) ~= "table" then return 0 end
    local n = 0
    for i = 1, 16 do
      local r = recs[i]
      if type(r) == "table" and tonumber(r.pickState) == 2 and (tonumber(r.flavorTextFlags) or 0) % 64 == 63 then
        n = n + 1
      end
    end
    return n
  end
  f.data = function() return self_:data() end
  -- How many rows of a generated list (trainers/items/hidden/gifts) are done.
  -- keep(row) filters; rows are { flagId, name, ..., map, region }.  Flags the
  -- game sets at New Game never count (they'd look done from the start).
  f.sweep = function(kind, keep)
    local d = self_:data()
    local done, total = 0, 0
    for _, row in ipairs(d[kind] or {}) do
      if not d.initial[row[1]] and (not keep or keep(row)) then
        total = total + 1
        if f.flag(row[1]) then done = done + 1 end
      end
    end
    return done, total
  end
  return f
end

return Gen3
