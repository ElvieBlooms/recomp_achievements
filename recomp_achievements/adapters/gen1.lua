-- adapters/gen1.lua
-- ==================================================================
-- Turns Red/Blue/Yellow game state into plain "facts" the rules can ask
-- about.  Rules never touch the save table directly; if Gen1Recomp
-- changes how it stores something, only this file changes.
--
-- Durable sources (engine 0.3.97, all read-only):
--   save.flags[NAME] == true        pokered event flags (src/script/Flags.lua)
--   save.inventory[ITEM] = count    bag, badges included (src/inventory/Badges.lua)
--   save.pcItems[ITEM] = count      item PC
--   save.pokedex.owned/seen[SPECIES]
--   save.party / save.box           Pokemon records ({ species, level, ... })
--   save.visited[MAP] = true        towns visited (fly list; towns only)
--   save.defeatedTrainers["<MAP>_obj_<n>"]   map trainers beaten
--   save.itemsTaken["<MAP>_obj_<n>"]         item balls picked up
--   save.hiddenTaken["<MAP>_<x>_<y>"]        hidden items found
--   save.options.battleStyle        "shift" | "set"
--   save.version                    "red" | "blue" | "yellow" (untagged = red,
--                                   matching SaveData's own migration)
-- Static map data (what is on a map) comes from game.data.maps and
-- game.data.field.hiddenItems, so "every item in Viridian Forest" is
-- computed from the game's own data, not hard-coded.
--
-- Everything goes through mod.game, so no "engine_internals" permission.
-- ==================================================================

local Gen1 = {}
Gen1.__index = Gen1

Gen1.BADGES = {
  "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
  "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE",
}

local VERSIONS = { red = true, blue = true, yellow = true }

function Gen1.new(mod, util)
  return setmetatable({ mod = mod, util = util }, Gen1)
end

function Gen1:game() return self.mod.game end

function Gen1:save()
  local game = self.mod.game
  return game and game.save
end

-- In-game play time in whole seconds (the TIME on the trainer card).
function Gen1:playTime()
  local save = self:save()
  local t = save and tonumber(save.playTime)
  return t and t >= 0 and math.floor(t) or nil
end

-- The exact running version, or nil if there is no usable save yet.
function Gen1:version()
  local save = self:save()
  if type(save) ~= "table" then return nil end
  local v = save.version or "red"
  if not VERSIONS[v] then
    -- Unknown cart (a ROM hack, a future version): refuse rather than
    -- guess and hand out Red achievements on the wrong game.
    self.mod.log:warn("unknown Gen 1 version %s; achievements paused", tostring(v))
    return nil
  end
  return v
end

local function countTrue(set)
  local n = 0
  for _, v in pairs(type(set) == "table" and set or {}) do if v then n = n + 1 end end
  return n
end

local function tbl(v) return type(v) == "table" and v or {} end

-- Summarise one Pokemon record into a small plain table.
local function monSummary(mon)
  if type(mon) ~= "table" then return nil end
  return {
    species = mon.species, level = tonumber(mon.level) or 0,
    hp = tonumber(mon.hp), item = mon.item,
    nickname = mon.nickname or mon.name,
  }
end
Gen1.monSummary = monSummary

-- A snapshot of the party right now (used by battle challenges).
function Gen1:partySnapshot()
  local out = {}
  for i, mon in ipairs(tbl((self:save() or {}).party)) do out[i] = monSummary(mon) end
  return out
end

-- A shallow copy of the bag, for "used an item during battle" checks.
function Gen1:bagSnapshot()
  local out = {}
  for k, v in pairs(tbl((self:save() or {}).inventory)) do out[k] = v end
  return out
end

-- A fresh facts object per evaluation pass.  Expensive answers (counting
-- the Pokedex, scanning a map) are memoised for that pass only.
function Gen1:facts()
  local save = self:save() or {}
  local game = self:game() or {}
  local data = game.data or {}
  local memo = {}
  local facts = { version = save.version or "red" }

  -- -------------------------------------------------- flags & progress
  function facts.flag(name) return tbl(save.flags)[name] == true end

  -- true when every flag in the list is set; or a count with asCount
  function facts.flags(list, asCount)
    local n = 0
    for _, name in ipairs(list) do if facts.flag(name) then n = n + 1 end end
    if asCount then return n end
    return n == #list
  end

  -- ------------------------------------------------------------- items
  function facts.itemCount(id)
    local bag = tonumber(tbl(save.inventory)[id]) or (tbl(save.inventory)[id] and 1 or 0)
    local pc = tonumber(tbl(save.pcItems)[id]) or (tbl(save.pcItems)[id] and 1 or 0)
    return bag + pc
  end
  function facts.hasItem(id) return facts.itemCount(id) > 0 end
  function facts.hasBadge(id)
    local v = tbl(save.inventory)[id]
    return v ~= nil and v ~= false and v ~= 0
  end
  function facts.badgeCount()
    if memo.badges == nil then
      local n = 0
      for _, id in ipairs(Gen1.BADGES) do if facts.hasBadge(id) then n = n + 1 end end
      memo.badges = n
    end
    return memo.badges
  end
  function facts.money() return tonumber(save.money) or 0 end
  function facts.coins() return tonumber(save.coins) or 0 end

  -- ----------------------------------------------------------- pokedex
  function facts.dexOwned()
    if memo.owned == nil then memo.owned = countTrue(tbl(save.pokedex).owned) end
    return memo.owned
  end
  function facts.dexSeen()
    if memo.seen == nil then memo.seen = countTrue(tbl(save.pokedex).seen) end
    return memo.seen
  end
  function facts.owns(species) return tbl(tbl(save.pokedex).owned)[species] == true end
  function facts.seen(species) return tbl(tbl(save.pokedex).seen)[species] == true end
  -- how many of `list` are owned (returns count, total)
  function facts.ownsCount(list)
    local n = 0
    for _, s in ipairs(list) do if facts.owns(s) then n = n + 1 end end
    return n, #list
  end

  -- ----------------------------------------------------------- pokemon
  function facts.party()
    if memo.party == nil then
      memo.party = {}
      for i, mon in ipairs(tbl(save.party)) do memo.party[i] = monSummary(mon) end
    end
    return memo.party
  end
  function facts.partySize() return #facts.party() end
  function facts.partyMaxLevel()
    local best = 0
    for _, m in ipairs(facts.party()) do if m.level > best then best = m.level end end
    return best
  end
  -- does the party (or PC box, with includeBox) hold this species?
  function facts.has(species, includeBox)
    for _, m in ipairs(facts.party()) do if m.species == species then return true end end
    if includeBox then
      for _, mon in ipairs(tbl(save.box)) do
        if type(mon) == "table" and mon.species == species then return true end
      end
    end
    return false
  end
  function facts.highestLevel()
    local best = facts.partyMaxLevel()
    for _, mon in ipairs(tbl(save.box)) do
      local lv = type(mon) == "table" and tonumber(mon.level) or 0
      if lv > best then best = lv end
    end
    return best
  end

  -- ------------------------------------------------------ exploration
  function facts.visited(mapId) return tbl(save.visited)[mapId] == true end
  function facts.visitedCount() return countTrue(save.visited) end

  -- ------------------------------------------------- per-map clearing
  -- What a map holds, from the game's own data:
  --   trainers  the EVENT_BEAT_* flag of every trainer with a trainer
  --             header (data.trainer_headers[label][index].event) -- the
  --             flag the engine sets when you win (OverworldController).
  --             Gym leaders and scripted rivals have no header; rules add
  --             their own story flags for those.
  --   items     item balls, keyed like save.itemsTaken ("<MAP>_obj_<n>")
  --   hidden    hidden items, keyed like save.hiddenTaken ("<MAP>_<x>_<y>")
  --   statics   static Pokemon (birds, Voltorb...), keyed like
  --             save.defeatedTrainers, which the engine sets on a win/catch
  -- Cached per pass.
  -- Map contents only depend on the game data, never on the save, so they
  -- are cached for the session (keyed by the data table) instead of being
  -- rebuilt on every check.
  local static = self.static
  if not static or static.data ~= data then
    static = { data = data, maps = {}, matching = {} }
    self.static = static
  end
  local function mapContents(mapId)
    if static.maps[mapId] then return static.maps[mapId] end
    local def = tbl(data.maps)[mapId]
    local out = { trainers = {}, items = {}, hidden = {}, statics = {} }
    local headers = def and def.label and tbl(data.trainer_headers)[def.label]
    for _, obj in ipairs(tbl(def and def.objects)) do
      local key = mapId .. "_obj_" .. tostring(obj.index)
      local header = headers and headers[obj.index]
      if obj.trainerClass and type(header) == "table" and header.event then
        out.trainers[#out.trainers + 1] = header.event
      end
      if obj.item and obj.item ~= "0" and obj.item ~= 0 then
        out.items[#out.items + 1] = { key = key, item = obj.item, name = obj.name }
      end
      if obj.pokemon then out.statics[#out.statics + 1] = { key = key, name = obj.name } end
    end
    local hidden = tbl(tbl(data.field).hiddenItems)[mapId]
    for _, h in ipairs(tbl(hidden)) do
      out.hidden[#out.hidden + 1] = { key = mapId .. "_" .. tostring(h.x) .. "_" .. tostring(h.y),
                                      item = h.item }
    end
    static.maps[mapId] = out
    return out
  end
  facts.mapContents = mapContents

  -- every map id matching a Lua pattern (e.g. "^SILPH_CO_")
  function facts.mapsMatching(pattern)
    if static.matching[pattern] then return static.matching[pattern] end
    local out = {}
    for id in pairs(tbl(data.maps)) do
      if type(id) == "string" and id:find(pattern) then out[#out + 1] = id end
    end
    table.sort(out)
    static.matching[pattern] = out
    return out
  end

  -- trainers beaten on a map: returns beaten, total
  function facts.trainersBeaten(mapId)
    local list, n = mapContents(mapId).trainers, 0
    for _, flag in ipairs(list) do if facts.flag(flag) then n = n + 1 end end
    return n, #list
  end
  -- An item ball or static Pokemon is gone when the engine says so: it
  -- records pickups in save.itemsTaken / wins in save.defeatedTrainers,
  -- but saves imported from a cartridge carry the same fact as a hidden
  -- object toggle (save.objectToggles[map][name] == false), exactly what
  -- OverworldController.objectVisible checks.
  local function toggledOff(mapId, name)
    local toggles = tbl(save.objectToggles)[mapId]
    return name ~= nil and type(toggles) == "table" and toggles[name] == false
  end

  -- is a map object switched off (a beaten rival who walked away, ...)?
  function facts.objectHidden(mapId, name) return toggledOff(mapId, name) end

  -- item balls (+ hidden items unless includeHidden == false) on a map.
  -- `skip(item)` may exclude items (missable fossils...).  Returns found, total.
  function facts.itemsFound(mapId, includeHidden, skip)
    local c = mapContents(mapId)
    local n, total = 0, 0
    for _, it in ipairs(c.items) do
      if not (skip and skip(it.item)) then
        total = total + 1
        if tbl(save.itemsTaken)[it.key] or toggledOff(mapId, it.name) then n = n + 1 end
      end
    end
    if includeHidden ~= false then
      for _, it in ipairs(c.hidden) do
        if not (skip and skip(it.item)) then
          total = total + 1
          if tbl(save.hiddenTaken)[it.key] then n = n + 1 end
        end
      end
    end
    return n, total
  end
  -- static Pokemon defeated or caught on a map: returns done, total
  function facts.staticsDone(mapId)
    local list, n = mapContents(mapId).statics, 0
    for _, st in ipairs(list) do
      if tbl(save.defeatedTrainers)[st.key] or toggledOff(mapId, st.name) then n = n + 1 end
    end
    return n, #list
  end
  -- sums over several maps.  what: "trainers" | "items" | "both"
  function facts.sweep(mapIds, what, opts)
    opts = opts or {}
    local done, total = 0, 0
    for _, id in ipairs(mapIds) do
      if what ~= "items" then
        local a, b = facts.trainersBeaten(id)
        done, total = done + a, total + b
      end
      if what ~= "trainers" then
        local a, b = facts.itemsFound(id, opts.hidden, opts.skip)
        done, total = done + a, total + b
      end
    end
    return done, total
  end
  function facts.cleared(mapIds, includeHidden)
    return facts.sweep(mapIds, "both", { hidden = includeHidden })
  end

  -- ------------------------------------------------------ species data
  local function speciesDef(species) return tbl(data.pokemon)[species] end
  -- list of type ids, e.g. { "WATER", "ICE" }
  function facts.types(species)
    local def = speciesDef(species)
    local out = {}
    for _, t in ipairs(tbl(def and def.types)) do out[#out + 1] = t end
    return out
  end
  function facts.hasType(species, typeId)
    for _, t in ipairs(facts.types(species)) do if t == typeId then return true end end
    return false
  end
  function facts.canEvolve(species)
    local def = speciesDef(species)
    return def ~= nil and #tbl(def.evolutions) > 0
  end

  -- ---------------------------------------------------------- encounters
  -- species in a map's walking tables (grass / cave floors), as a set
  function facts.encounterSpecies(pattern)
    local out = {}
    for id, enc in pairs(tbl(data.encounters)) do
      if type(id) == "string" and id:find(pattern) then
        for _, slot in ipairs(tbl(tbl(tbl(enc).grass).slots)) do
          local sp = type(slot) == "table" and (slot.species or slot[2]) or slot
          if type(sp) == "string" then out[sp] = true end
        end
      end
    end
    return out
  end

  -- everything found in the Safari Zone (walking + every rod) and all
  -- of their evolutions, as a set.  Cached per pass.
  function facts.safariFamily()
    if memo.safari then return memo.safari end
    local out = facts.encounterSpecies("^SAFARI_ZONE")
    for id, rod in pairs(tbl(tbl(data.field).superRod)) do
      if type(id) == "string" and id:find("^SAFARI_ZONE") then
        for _, v in pairs(tbl(rod)) do
          local sp = type(v) == "table" and (v.species or v[2]) or v
          if type(sp) == "string" then out[sp] = true end
        end
      end
    end
    out.MAGIKARP, out.POLIWAG, out.GOLDEEN = true, true, true -- old/good rod
    local changed = true
    while changed do
      changed = false
      for sp in pairs(out) do
        for _, evo in ipairs(tbl(tbl(speciesDef(sp)).evolutions)) do
          if evo.species and not out[evo.species] then out[evo.species] = true; changed = true end
        end
      end
    end
    memo.safari = out
    return out
  end

  -- ------------------------------------------------------------ misc
  -- story flags of the card-key doors on maps matching a pattern
  function facts.cardKeyDoorFlags(pattern)
    local out = {}
    local closed = tbl(tbl(tbl(data.field).cardKeyDoors).closedDoors)
    local ids = {}
    for id in pairs(closed) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      if id:find(pattern) then
        for _, door in ipairs(tbl(closed[id])) do
          if door.event then out[#out + 1] = door.event end
        end
      end
    end
    return out
  end

  -- hidden coins picked up on a map: returns found, total
  function facts.hiddenCoinsFound(mapId)
    local n, total = 0, 0
    for _, h in ipairs(tbl(tbl(tbl(data.field).hiddenCoins)[mapId])) do
      total = total + 1
      if tbl(save.hiddenTaken)[mapId .. "_" .. tostring(h.x) .. "_" .. tostring(h.y)] then n = n + 1 end
    end
    return n, total
  end

  -- the state on top of the stack, and its screen id ("SlotMachine", ...)
  function facts.topState()
    local states = tbl(tbl(game.stack).states)
    local top = states[#states]
    return type(top) == "table" and top or nil
  end
  function facts.stateBelowTop()
    local states = tbl(tbl(game.stack).states)
    local st = states[#states - 1]
    return type(st) == "table" and st or nil
  end
  -- a Pokemon in the PC box currently open (Boxes.active)
  function facts.boxMon(index)
    local boxes = tbl(save.boxes)
    local box = tbl(boxes[save.currentBox or 1])
    local mon = box[tonumber(index) or 0]
    return type(mon) == "table" and mon or nil
  end
  -- Yellow: the starter Pikachu is the one with your own trainer id and
  -- name (PikachuFollower.isStarterPikachu)
  function facts.isStarterPikachu(mon)
    local player = tbl(save.player)
    return type(mon) == "table" and mon.species == "PIKACHU"
      and mon.otId == player.id and mon.ot == player.name
  end
  function facts.topScreen()
    local top = facts.topState()
    return top and top.screenId or nil
  end

  -- where the player stands (cells) and the map's own flags
  function facts.playerCell()
    local ow = game.overworld
    local p = type(ow) == "table" and ow.player
    if type(p) ~= "table" then return nil end
    return p.cellX, p.cellY
  end
  function facts.flashLit() return save.flashLit == true end

  -- Yellow: the following Pikachu's overworld object, if out
  function facts.pikachuNpc()
    local ow = game.overworld
    for _, npc in ipairs(tbl(type(ow) == "table" and ow.npcs)) do
      if type(npc) == "table" and npc.pikachuFollower then return npc end
    end
    return nil
  end
  function facts.overworld()
    local ow = game.overworld
    return type(ow) == "table" and ow or nil
  end

  function facts.inSafari() return type(save.safari) == "table" end
  function facts.safariSteps()
    return type(save.safari) == "table" and tonumber(save.safari.steps) or nil
  end
  function facts.repelSteps() return tonumber(save.repelSteps) or 0 end
  function facts.repelCount()
    local n = 0
    for _, id in ipairs({ "REPEL", "SUPER_REPEL", "MAX_REPEL" }) do
      n = n + (tonumber(tbl(save.inventory)[id]) or 0)
    end
    return n
  end
  function facts.bag()
    local out = {}
    for k, v in pairs(tbl(save.inventory)) do out[k] = v end
    return out
  end

  local function overworld()
    local ow = game.overworld
    return type(ow) == "table" and type(ow.map) == "table" and ow or nil
  end
  function facts.facing()
    local ow = overworld()
    return ow and type(ow.player) == "table" and ow.player.facing or nil
  end

  -- Was the most recent Cut used on tall grass rather than a tree?  The
  -- engine records the block it replaced (ow.cutBlocks) and decides
  -- "grass" by the OVERWORLD tile $52 in front of the player
  -- (OverworldController:tryCut); we look that tile up in the old block.
  function facts.lastCutWasGrass()
    local ow = overworld()
    if not (ow and ow.player and ow.player.facingCell) then return false end
    local map = ow.map
    local list = tbl(tbl(ow.cutBlocks)[map.id])
    local last = list[#list]
    if not (last and map.def and map.def.tileset == "OVERWORLD" and map.tileset) then return false end
    local fx, fy = ow.player:facingCell()
    local blocks = tbl(map.tileset.blocks)[last.block + 1]
    if type(blocks) ~= "table" then return false end
    local tx, ty = fx * 2, fy * 2 + 1
    return blocks[(ty % 4) * 4 + (tx % 4) + 1] == 0x52
  end

  -- Yellow: which emotion talking to the following Pikachu shows right
  -- now.  Mirrors src/world/PikachuFollower.lua selectEmotion (itself a
  -- port of pokeyellow engine/pikachu/pikachu_emotions.asm).
  function facts.pikachuEmotion()
    local ow = overworld()
    local field = tbl(data.field).pikachu
    if not (ow and type(field) == "table") then return nil end
    local mapId = ow.map.id
    if mapId == "POKEMON_FAN_CLUB" then
      if not save.pikachuMapScriptActive then return 29 end
      if ow.pikachuFanClubScene then return 30 end
    elseif mapId == "PEWTER_POKECENTER" then
      if ow.pikachuPewterSleepScene then return 26 end
    end
    if mapId == "BILLS_HOUSE" then
      if ow.pikachuBillsScene and not facts.flag("EVENT_BILL_SAID_USE_CELL_SEPARATOR") then return 23 end
      return facts.flag("EVENT_MET_BILL_2") and 31 or 32
    end
    for _, mon in ipairs(tbl(save.party)) do
      if facts.isStarterPikachu(mon) then
        if mon.status == "SLP" then return 11 end
        if mon.status then return 28 end
        break
      end
    end
    if tostring(mapId):find("POKEMON_TOWER_", 1, true) == 1 then return 22 end
    local modifier = save.pikachuEmotionModifier
    if modifier and tbl(field.modifierEmotions)[modifier] then
      return field.modifierEmotions[modifier]
    end
    local mood = save.pikachuMood or 128
    local column
    for _, m in ipairs(tbl(field.moodColumns)) do
      if mood <= m.limit then column = m.column break end
    end
    local h = save.pikachuHappiness or 90
    for _, r in ipairs(tbl(field.moodRows)) do
      if h <= r.limit then return r[column] end
    end
    return nil
  end

  function facts.battleStyle()
    return tostring(tbl(save.options).battleStyle or "shift"):lower()
  end

  return facts
end

return Gen1
