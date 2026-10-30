-- adapters/gen2.lua
-- ==================================================================
-- Gold, Silver and Crystal state as plain "facts" for the rules, the
-- same idea as adapters/gen1.lua.  Engine 0.3.97 Gen 2 layout
-- (src/core/gen2/Save.lua):
--
--   save.version                    "gold" | "silver" | "crystal"
--   save.player.{name,id,money,coins,badges,kantoBadges}
--       badges / kantoBadges keyed by name ("ZEPHYR" = true); older
--       saves key by index, so both are accepted
--   save.inventory[ITEM] = count    every pocket; pocket from data.items
--   save.pcItems[ITEM] = count
--   save.pokedex.caught / seen[SPECIES] = true
--   save.party, save.boxes[1..14]   mon records { species, level, shiny, isEgg, ... }
--   save.unownDex                   list of Unown letters caught
--   save.hallOfFame.count           Hall of Fame entries
--   save.phoneContacts[id] = true
--   save.playTime = { hours, minutes, seconds }
--
-- Event flags: the live copy is game.world.events (save.events is only
-- refreshed when the game saves).  Gold/Silver also accept symbolic names
-- through mod.world:getFlag; Crystal numbers its flags differently and
-- the engine has no name table for it, so name lookups return nil there
-- until we ship one.
-- ==================================================================

local Gen2 = {}
Gen2.__index = Gen2

Gen2.JOHTO = { "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL", "STORM", "GLACIER", "RISING" }
Gen2.KANTO = { "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO", "EARTH" }

local VERSIONS = { gold = true, silver = true, crystal = true }

-- loadData(version) returns data/gen2_<version>.lua (flag numbers, map
-- trainers and items, Johto species); see tools/gen2_data.py.
function Gen2.new(mod, util, loadData)
  return setmetatable({ mod = mod, util = util, loadData = loadData, cache = {} }, Gen2)
end

-- The generated tables for the running game, or an empty shell.
function Gen2:data()
  local v = self:version()
  if not v then return { flags = {}, trainers = {}, items = {}, hidden = {}, gifts = {}, johto = {} } end
  if self.cache[v] == nil then
    local ok, d = pcall(self.loadData or function() return nil end, v)
    self.cache[v] = ok and type(d) == "table" and d or false
  end
  return self.cache[v] or { flags = {}, trainers = {}, items = {}, hidden = {}, gifts = {}, johto = {} }
end

function Gen2:game() return self.mod.game end

function Gen2:save()
  local game = self.mod.game
  return game and game.save
end

function Gen2:version()
  local save = self:save()
  if type(save) ~= "table" then return nil end
  local v = save.version
  if not VERSIONS[v] then
    -- the boot placeholder or something we don't understand: no ledger
    return nil
  end
  return v
end

-- Play time in whole seconds.
function Gen2:playTime()
  local save = self:save()
  local pt = save and save.playTime
  if type(pt) == "number" then return math.floor(pt) end
  if type(pt) ~= "table" then return nil end
  return (tonumber(pt.hours) or 0) * 3600 + (tonumber(pt.minutes) or 0) * 60 + (tonumber(pt.seconds) or 0)
end

local function count(t)
  local n = 0
  if type(t) == "table" then for _, v in pairs(t) do if v then n = n + 1 end end end
  return n
end

-- Badge tables key by name, or (older saves) by 1-based index.
local function hasBadge(tbl, list, name)
  if type(tbl) ~= "table" then return false end
  if tbl[name] then return true end
  for i, n in ipairs(list) do if n == name then return tbl[i] == true end end
  return false
end

local function badgeCount(tbl, list)
  local n = 0
  for _, name in ipairs(list) do if hasBadge(tbl, list, name) then n = n + 1 end end
  return n
end

-- Every stored Pokemon, eggs excluded unless asked.
function Gen2:eachMon(fn, withEggs)
  local save = self:save()
  if type(save) ~= "table" then return end
  local function visit(list)
    if type(list) ~= "table" then return end
    for _, mon in ipairs(list) do
      if type(mon) == "table" and (withEggs or not mon.isEgg) then fn(mon) end
    end
  end
  visit(save.party)
  if type(save.boxes) == "table" then
    for _, box in pairs(save.boxes) do visit(box) end
  end
end

-- A live event flag by numeric id, or by name on Gold/Silver.
function Gen2:flag(id)
  local game = self:game()
  if type(id) == "number" then
    local events = game and game.world and game.world.events
    if events and events.get then
      local ok, v = pcall(events.get, events, id)
      if ok then return v == true or v == 1 end
    end
    -- no live world (title screen): decode the saved bit array
    local save = self:save()
    local bytes = save and save.events
    if type(bytes) == "table" then
      local byte = tonumber(bytes[math.floor(id / 8)]) or 0
      return math.floor(byte / 2 ^ (id % 8)) % 2 == 1
    end
    return false
  end
  if type(id) == "string" then
    local n = self:data().flags[id]
    if n then return self:flag(n) end
  end
  if type(id) == "string" and self.mod.world and self.mod.world.getFlag then
    local ok, v = pcall(self.mod.world.getFlag, self.mod.world, id)
    if ok then return v == true or v == 1 end
  end
  return nil
end

-- ENGINE_* flags (daily events, the Unown dex, ...) by name.
function Gen2:engineFlag(name)
  local game = self:game()
  local world = game and game.world
  if world and world.engineFlagId and world.engineFlag then
    local ok, v = pcall(function() return world:engineFlag(world:engineFlagId(name)) end)
    if ok then return v == true or v == 1 end
  end
  local order = game and game.data and game.data.gen2Constants and game.data.gen2Constants.engineFlagOrder
  local save = self:save()
  if type(order) == "table" and save and type(save.engineFlags) == "table" then
    for i, n in ipairs(order) do
      if n == name then return save.engineFlags[i - 1] == true end
    end
  end
  return false
end

-- Species data from the game (types, evolutions).
function Gen2:species(name)
  local game = self:game()
  local mons = game and game.data and game.data.pokemon
  return type(mons) == "table" and mons[name] or nil
end

-- Johto Pokemon (data/gen2_*.lua `johto`) and anything they evolve into.
function Gen2:isJohto(species)
  local set = self:data().johto or {}
  if set[species] then return true end
  if not self.preEvo then
    self.preEvo = {}
    local game = self:game()
    for name, entry in pairs(game and game.data and game.data.pokemon or {}) do
      for _, evo in ipairs(type(entry) == "table" and entry.evolutions or {}) do
        if evo.into then self.preEvo[evo.into] = name end
      end
    end
  end
  local seen = {}
  local cur = self.preEvo[species]
  while cur and not seen[cur] do
    if set[cur] then return true end
    seen[cur] = true
    cur = self.preEvo[cur]
  end
  return false
end

function Gen2:partySnapshot()
  local save = self:save()
  local out = {}
  for i, mon in ipairs(save and save.party or {}) do
    if type(mon) == "table" then out[i] = { species = mon.species, level = mon.level, isEgg = mon.isEgg } end
  end
  return out
end

function Gen2:bagSnapshot()
  local save = self:save()
  local out = {}
  for id, n in pairs(save and save.inventory or {}) do out[id] = tonumber(n) or 0 end
  return out
end

-- Gen 2 sends battle.started and battle.ended twice per battle (once from
-- the battle itself, once from the battle screen).  This gives both
-- copies the same key so the engine can keep one, plus the trainer class
-- (e.g. "FALKNER") the second copy leaves out.
function Gen2:battleInfo(ev)
  local raw = type(ev) == "table" and ev.battle or nil
  if type(raw) ~= "table" then return {} end
  local core = type(raw.battle) == "table" and raw.battle or raw
  local trainer = type(core.trainer) == "table" and core.trainer or nil
  return { key = core, trainerId = trainer and (trainer.classId or trainer.id) or nil }
end

function Gen2:facts()
  local save = self:save() or {}
  local player = type(save.player) == "table" and save.player or {}
  local inv = type(save.inventory) == "table" and save.inventory or {}
  local pc = type(save.pcItems) == "table" and save.pcItems or {}
  local dex = type(save.pokedex) == "table" and save.pokedex or {}
  local caught = type(dex.caught) == "table" and dex.caught or (type(dex.owned) == "table" and dex.owned) or {}
  local seen = type(dex.seen) == "table" and dex.seen or {}
  local self_ = self
  local f = {}
  f.version = save.version
  f.flag = function(id) return self_:flag(id) == true end
  f.anyFlag = function(...) for _, id in ipairs({ ... }) do if f.flag(id) then return true end end return false end
  f.itemCount = function(id) return (tonumber(inv[id]) or 0) + (tonumber(pc[id]) or 0) end
  f.hasItem = function(id) return f.itemCount(id) > 0 end
  f.hasBadge = function(name) return hasBadge(player.badges, Gen2.JOHTO, name) or hasBadge(player.kantoBadges, Gen2.KANTO, name) end
  f.badgeCount = function() return badgeCount(player.badges, Gen2.JOHTO) end
  f.kantoBadgeCount = function() return badgeCount(player.kantoBadges, Gen2.KANTO) end
  f.money = function() return tonumber(player.money) or 0 end
  f.coins = function() return tonumber(player.coins) or 0 end
  f.dexOwned = function() return count(caught) end
  f.dexSeen = function() return count(seen) end
  f.owns = function(species) return caught[species] == true end
  f.party = function() return type(save.party) == "table" and save.party or {} end
  f.partySize = function() return #f.party() end
  f.highestLevel = function()
    local best = 0
    self_:eachMon(function(m) best = math.max(best, tonumber(m.level) or 0) end)
    return best
  end
  f.has = function(species)
    local found = false
    self_:eachMon(function(m) if m.species == species then found = true end end)
    return found
  end
  f.shinyCount = function()
    local n = 0
    self_:eachMon(function(m) if m.shiny then n = n + 1 end end)
    return n
  end
  f.unownForms = function() return type(save.unownDex) == "table" and #save.unownDex or 0 end
  f.hallOfFame = function()
    local h = save.hallOfFame
    return type(h) == "table" and (tonumber(h.count) or (type(h.teams) == "table" and #h.teams) or 0) or 0
  end
  f.phoneContacts = function() return count(save.phoneContacts) end
  -- story and sidequest facts
  f.engineFlag = function(name) return self_:engineFlag(name) end
  f.allFlags = function(list) for _, id in ipairs(list) do if not f.flag(id) then return false end end return true end
  f.countFlags = function(list) local n = 0 for _, id in ipairs(list) do if f.flag(id) then n = n + 1 end end return n end
  f.rivalNamed = function()
    local r = save.rival
    return type(r) == "table" and type(r.name) == "string" and r.name ~= "" and r.name ~= "???"
  end
  f.traded = function(id) return type(save.tradeFlags) == "table" and save.tradeFlags[id] == true end
  f.battleStyle = function()
    local game = self_:game()
    local o = (game and game.options) or save.options or {}
    return o.battleStyle and tostring(o.battleStyle):lower() or nil
  end
  f.ownsWhere = function(test)
    local found = false
    self_:eachMon(function(m) if not found and test(m) then found = true end end)
    return found
  end
  f.types = function(species)
    local s = self_:species(species)
    return s and s.types or {}
  end
  f.hasType = function(species, t)
    for _, x in ipairs(f.types(species)) do if x == t then return true end end
    return false
  end
  f.isJohto = function(species) return self_:isJohto(species) end
  f.data = function() return self_:data() end
  -- How many rows of a generated list (trainers/items/hidden/gifts) are done.
  -- keep(row) filters; rows are { flagId, flagName, ..., region }.
  f.sweep = function(kind, keep)
    local done, total = 0, 0
    for _, row in ipairs(self_:data()[kind] or {}) do
      if not keep or keep(row) then
        total = total + 1
        if f.flag(row[1]) then done = done + 1 end
      end
    end
    return done, total
  end
  f.towerStreak = function()
    local t = save.battleTower
    return type(t) == "table" and tonumber(t.streak) or 0
  end
  return f
end

return Gen2
