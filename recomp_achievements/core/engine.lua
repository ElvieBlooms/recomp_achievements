-- core/engine.lua
-- ==================================================================
-- The award pipeline.  EVERY unlock and progress change -- from our own
-- rules or from another mod -- goes through Engine:award / Engine:progress
-- so that validation, saving, popups and broadcast events can never
-- drift apart.
--
--   gameplay event --> rule test --> Engine:award --> ledger (save)
--                                                 \-> toast (popup)
--                                                 \-> mod.<id>.unlocked event
--
-- Two kinds of core rules (see rules/gen1.lua):
--   kind = "state": a predicate over durable game state (badges, flags,
--     Pokedex count).  Re-checked whenever something MIGHT have changed,
--     and once on load -- which is how an old save gets credit for what
--     it already did ("backfill").
--   kind = "event": reacts to one engine event (a catch, an evolution, a
--     trainer win).  Cannot be backfilled: there is no proof it happened.
--     Returning a number adds to a counter toward `goal`.
--
-- Lifecycle safety: between save.loading and save.loaded the old save's
-- table is going away, so nothing may be awarded.  `self.active` guards
-- that window and the title screen.
-- ==================================================================

local Engine = {}
Engine.__index = Engine

local EVENT_PREFIX = "mod.recomp_achievements."

-- Engine events that might change durable state.  Any of them marks the
-- state rules "dirty"; the actual check runs once, on the next frame.
-- Batching like this keeps a flurry of flag changes inside one script from
-- costing more than a single evaluation, and makes sure we read state
-- AFTER the script finished writing it.
local DIRTY_EVENTS = {
  "flag.changed", "battle.ended", "map.entered", "script.ended",
  "pokemon.caught", "pokemon.evolved", "pokemon.received", "trade.completed",
  "pokemon.level_up", "screen.popped", "world.interacted",
}
-- Some state changes have no event at all (coins from a slot machine,
-- an item bought in a mart, a flag a script writes directly), so state
-- rules are also re-checked on a slow timer as a safety net.
local RECHECK_SECONDS = 5

function Engine.new(opts)
  local self = setmetatable({}, Engine)
  self.mod = opts.mod
  self.util = opts.util
  self.ledger = opts.ledger
  self.registry = opts.registry
  self.toast = opts.toast
  self.rules = {}          -- core rules by id
  self.stateRules = {}     -- ordered list of kind=="state"
  self.eventRules = {}     -- engine event name -> list of rules
  self.trackers = {}       -- ordered list of kind=="tracker"
  self.trackerEvents = {}  -- engine event name -> list of trackers
  self.map = nil           -- current map id (from map.entered)
  self.adapter = nil
  self.active = false      -- a real save context is attached
  self.game = nil          -- running version id ("red", "blue", ...)
  self.dirty = false
  self.battle = nil        -- what battle.started told us, for battle.ended
  return self
end

function Engine:log(fmt, ...)
  if self.mod.options:get("debug") then self.mod.log:info(fmt, ...) end
end

function Engine:setAdapter(adapter)
  self.adapter = adapter
end

-- ------------------------------------------------------------------
-- Core rules
-- ------------------------------------------------------------------
function Engine:addRule(rule)
  local def, code, message = self.registry:add("core", "core", rule)
  if not def then
    -- A broken built-in rule is our bug: log loudly, keep running.
    self.mod.log:error("core rule %s rejected: %s %s", tostring(rule.id), code, message)
    return
  end
  local entry = { def = def, rule = rule }
  self.rules[rule.id] = entry
  -- Event rules and trackers may ALSO carry a state `check`: proof that
  -- can be read from the save (so an old save gets credit too).
  if rule.kind ~= "state" and type(rule.check) == "function" then
    self.stateRules[#self.stateRules + 1] = entry
  end
  if rule.kind == "state" then
    self.stateRules[#self.stateRules + 1] = entry
  elseif rule.kind == "event" then
    local list = self.eventRules[rule.on]
    if not list then list = {}; self.eventRules[rule.on] = list end
    list[#list + 1] = entry
  elseif rule.kind == "tracker" then
    -- A tracker keeps in-memory state for the current play session (it is
    -- reset whenever a save is loaded or created, so "without resetting"
    -- comes for free) and reacts to several events.
    --   rule.init(state, facts, ctx)               optional
    --   rule.on[eventName](state, ev, facts, ctx)  -> true | number | nil
    entry.state = {}
    self.trackers[#self.trackers + 1] = entry
    for name in pairs(rule.on or {}) do
      local list = self.trackerEvents[name]
      if not list then list = {}; self.trackerEvents[name] = list end
      list[#list + 1] = entry
    end
  else
    self.mod.log:error("core rule %s has unknown kind %s", rule.id, tostring(rule.kind))
  end
end

-- ------------------------------------------------------------------
-- The award pipeline
-- ------------------------------------------------------------------

-- Why an award may be refused.  Returned to API callers as error codes.
function Engine:canAward(key)
  if not self.active or not self.game then return false, "no_save" end
  local def = self.registry:get(key)
  if not def then return false, "unknown_id" end
  if not self.registry.appliesTo(def, self.game) then return false, "wrong_game" end
  if def.extra and not self:extrasOn() then return false, "disabled" end
  return true, def
end

-- "Extras" are built-in achievements that are NOT official RA entries
-- (e.g. Seasoned Battler).  Players who want the official lists only can
-- switch them off; nothing already earned is deleted.
function Engine:extrasOn()
  return self.mod.options:get("extras") ~= false
end

-- Title/description/points to show for a definition on the running game.
function Engine:display(def)
  return self.registry:display(def, self.game)
end

-- opts.how    "event" | "backfill" | "api"
-- opts.silent true to skip the popup (backfill batches its own summary)
function Engine:award(key, opts)
  opts = opts or {}
  local ok, def = self:canAward(key)
  if not ok then return false, def end
  if self.ledger:isUnlocked(key) then return false, "already_unlocked" end
  local shown = self:display(def)
  local wrote = self.ledger:unlock(self.game, key, {
    how = opts.how, source = def.source, title = shown.title,
    pt = self:playTime(),
  })
  if not wrote then return false, "already_unlocked" end
  self:log("unlocked %s (%s)", key, opts.how or "event")
  -- Popup only AFTER the record exists: a popup is never the proof.
  if not opts.silent then self.toast:push(def, shown) end
  self:broadcast("unlocked", {
    key = key, id = def.id, source = def.source, provider = def.provider,
    title = shown.title, points = shown.points, how = opts.how or "event",
    official = shown.official, raId = shown.raId,
  })
  return true
end

-- Whether a step forward deserves a progress note.  Not for the backfill
-- when a save loads, not for hidden ones (the note would spoil them), and
-- for big or percent goals only each tenth of the way, so a steps counter
-- or an area sweep doesn't chatter.
function Engine:showsProgress(def, before, value, opts)
  opts = opts or {}
  if opts.silent or opts.how == "backfill" or not self.toast.pushProgress then return false end
  if def.hidden and not self.mod.options:get("showHidden") then return false end
  if def.extra and self.mod.options:get("extras") == false then return false end
  if def.unit == "PCT" or def.goal > 400 then
    local step = def.goal / 10
    return math.floor(value / step) > math.floor(before / step)
  end
  return true
end

-- Absolute progress.  Clamped to [0, goal]; reaching the goal awards.
function Engine:setProgress(key, value, opts)
  local ok, def = self:canAward(key)
  if not ok then return false, def end
  if self.ledger:isUnlocked(key) then return false, "already_unlocked" end
  if not def.goal then return false, "no_goal" end
  if type(value) ~= "number" or value ~= value then return false, "invalid_value" end
  value = self.util.clamp(math.floor(value), 0, def.goal)
  local before = self.ledger:progress(key)
  if value >= def.goal then return self:award(key, opts) end
  if value == before then return true end
  self.ledger:setProgress(self.game, key, value)
  if value > before and self:showsProgress(def, before, value, opts) then
    self.toast:pushProgress(def, self:display(def), value, def.goal)
  end
  self:broadcast("progress", {
    key = key, id = def.id, source = def.source, provider = def.provider,
    value = value, goal = def.goal,
  })
  return true
end

function Engine:addProgress(key, by, opts)
  local ok, why = self:canAward(key)
  if not ok then return false, why end
  if self.ledger:isUnlocked(key) then return false, "already_unlocked" end
  if type(by) ~= "number" or by ~= by or by < 0 then return false, "invalid_value" end
  return self:setProgress(key, self.ledger:progress(key) + by, opts)
end

-- Custom events other mods can listen to with
--   mod.events:on("mod.recomp_achievements.unlocked", fn)
-- Payloads are plain data copies; listeners cannot mutate our state.
function Engine:broadcast(name, payload)
  local ok, err = pcall(self.mod.events.emit, self.mod.events,
    EVENT_PREFIX .. name, self.util.plain(payload))
  if not ok then self.mod.log:warn("broadcast %s failed: %s", name, tostring(err)) end
end

-- ------------------------------------------------------------------
-- Rule evaluation
-- ------------------------------------------------------------------

-- Run one rule function with errors contained: a buggy rule must never
-- take the game down.  Returns the rule's result or nil.
function Engine:try(entry, fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then
    self.mod.log:warn("rule %s failed: %s", entry.def.id, tostring(result))
    return nil
  end
  return result
end

-- Check every state rule against current state.  Returns how many unlocked.
function Engine:evaluateState(how, silent)
  if not (self.active and self.adapter) then return 0 end
  local facts = self.adapter:facts()
  local unlocked = 0
  for _, entry in ipairs(self.stateRules) do
    local def = entry.def
    if self.registry.appliesTo(def, self.game) and not self.ledger:isUnlocked(def.key) then
      local result = self:try(entry, entry.rule.check, facts, self.game)
      if result == true then
        if self:award(def.key, { how = how, silent = silent }) then unlocked = unlocked + 1 end
      elseif type(result) == "number" and def.goal then
        local wasUnlocked = self.ledger:isUnlocked(def.key)
        self:setProgress(def.key, result, { how = how, silent = silent })
        if not wasUnlocked and self.ledger:isUnlocked(def.key) then unlocked = unlocked + 1 end
      end
    end
  end
  self.dirty = false
  return unlocked
end

function Engine:context()
  return { battle = self.battle, lastBattle = self.lastBattle, game = self.game,
           map = self.map, engine = self }
end

-- Apply what a rule function returned: true awards, a number is progress
-- (added for event rules, absolute for trackers).
function Engine:apply(def, result, additive)
  if result == true then
    self:award(def.key, { how = "event" })
  elseif type(result) == "number" and def.goal then
    if additive then
      if result > 0 then self:addProgress(def.key, result, { how = "event" }) end
    else
      self:setProgress(def.key, result, { how = "event" })
    end
  end
end

function Engine:resetTrackers()
  local facts = self.adapter and self.adapter:facts()
  local ctx = self:context()
  for _, entry in ipairs(self.trackers) do
    entry.state = {}
    if entry.rule.init and facts then
      self:try(entry, entry.rule.init, entry.state, facts, ctx)
    end
  end
end

-- Event rules and trackers: called with the engine event payload.
function Engine:dispatch(name, payload)
  if not (self.active and self.adapter) then return end
  local trackers = self.trackerEvents[name]
  if trackers then
    -- facts/ctx are built lazily: per-frame trackers on a game where they
    -- don't apply (or are already earned) then cost nothing
    local facts, ctx
    for _, entry in ipairs(trackers) do
      local def = entry.def
      if self.registry.appliesTo(def, self.game) and not self.ledger:isUnlocked(def.key) then
        facts = facts or self.adapter:facts()
        ctx = ctx or self:context()
        local result = self:try(entry, entry.rule.on[name], entry.state, payload, facts, ctx)
        self:apply(def, result, false)
      end
    end
  end
  local list = self.eventRules[name]
  if not list then return end
  local facts = self.adapter:facts()
  local ctx = self:context()
  for _, entry in ipairs(list) do
    local def = entry.def
    if self.registry.appliesTo(def, self.game) and not self.ledger:isUnlocked(def.key) then
      local result = self:try(entry, entry.rule.test, payload, facts, ctx)
      self:apply(def, result, true)
    end
  end
end

-- Reconcile after a save becomes active: credit durable milestones the
-- save already has, quietly, then show ONE summary popup instead of a
-- burst of twenty.
function Engine:reconcile()
  local n = self:evaluateState("backfill", true)
  if n == 1 then
    -- a single one reads better as a normal popup
    local newest, newestAt
    local data = self.ledger:peek()
    for key, record in pairs(data and data.unlocked or {}) do
      if record.how == "backfill" and (not newestAt or (record.at or 0) >= newestAt) then
        newest, newestAt = key, record.at or 0
      end
    end
    local def = newest and self.registry:get(newest)
    if def then self.toast:push(def, self:display(def)) end
  elseif n > 1 then
    self.toast:pushSummary(n)
  end
  return n
end

-- ------------------------------------------------------------------
-- Save context
-- ------------------------------------------------------------------
function Engine:attach(how)
  self.game = self.adapter and self.adapter:version() or nil
  self.active = self.game ~= nil
  self.battle = nil
  self.toast:clear()
  if not self.active then return end
  local data = self.ledger:get(self.game) -- create / migrate / repair now, not mid-award
  self:dropNewGameMisfires(data)
  local save = self.adapter and self.adapter:save()
  self.map = save and save.player and save.player.map or nil
  self.lastBattle = nil
  self:resetTrackers()
  self:log("attached to %s save (%s)", self.game, how)
  -- Reconcile first, so providers listening for "ready" see a ledger that
  -- already reflects what this save has done.
  if how ~= "created" then self:reconcile() end
  self:broadcast("ready", { game = self.game, how = how })
end

-- 2.0.0 to 2.1.0 unlocked these Gen 2 achievements at the start of a New
-- Game: the game sets their flags during its opening script.  None can
-- really be earned in the first half hour, so such records are moved to the
-- ledger's quarantine (kept, not deleted) and the achievement can be
-- earned again for real.
Engine.NEW_GAME_MISFIRES = {
  ["core:g2o_machine_part"] = true,
  ["core:g2o_suicune_42"] = true,
  ["core:g2o_suicune_36"] = true,
}

function Engine:dropNewGameMisfires(data)
  if type(data) ~= "table" or type(data.unlocked) ~= "table" then return end
  for key in pairs(Engine.NEW_GAME_MISFIRES) do
    local rec = data.unlocked[key]
    if type(rec) == "table" and rec.how == "event" and tonumber(rec.pt) and tonumber(rec.pt) < 1800 then
      data.quarantine = type(data.quarantine) == "table" and data.quarantine or {}
      rec.dropped = "unlocked at New Game by mistake"
      data.quarantine[key] = rec
      data.unlocked[key] = nil
      self:log("removed %s: it fired at New Game", key)
    end
  end
end

function Engine:detach()
  self.active = false
  self.battle = nil
end

-- ------------------------------------------------------------------
-- Wiring to engine events and hooks
-- ------------------------------------------------------------------
function Engine:wire()
  local mod, events = self.mod, self.mod.events

  -- At boot the engine builds a throwaway skeleton save for the title
  -- screen and fires save.created for it BEFORE game.ready
  -- (src/core/Game.lua:99-121).  That save is never played, so we ignore
  -- it; save.created after game.ready is a real NEW GAME.
  events:on("game.ready", function() self.booted = true end)
  events:on("save.loading", function() self:detach() end)
  -- The event's own save is handed to the adapter too: on Gen 3,
  -- mod.game.save can still be unset when save.loaded fires.
  local function seen(ev)
    if self.adapter and type(ev) == "table" and type(ev.save) == "table" then
      self.adapter.eventSave = ev.save
    end
  end
  events:on("save.loaded", function(ev) seen(ev); self:attach("loaded") end)
  events:on("save.created", function(ev)
    if self.booted then seen(ev); self:attach("created") else self:detach() end
  end)
  -- A checkpoint restore can rewind the save table, ledger included.  Drop
  -- any queued popups (they may describe a future that no longer exists)
  -- and re-check state.
  events:on("checkpoint.restored", function()
    self.toast:clear()
    self.battle = nil
    if self.active then self.dirty = true; self:resetTrackers() end
  end)
  -- Flush pending state checks right before the save is written, so an
  -- unlock earned this very frame is included in the file.
  events:on("save.writing", function()
    if self.active and self.dirty then self:evaluateState("event", false) end
  end)

  for _, name in ipairs(DIRTY_EVENTS) do
    events:on(name, function() if self.active then self.dirty = true end end)
  end

  -- ---------------------------------------------------------------
  -- Battle context.  battle.ended's payload only says win/lose, so we
  -- keep our own notes from the start of the fight, which "challenge"
  -- rules read through ctx.battle:
  --   kind, trainerId ("OPP_BROCK"), species/level (wild), style
  --   ("shift"/"set"), partyAtStart, partyMaxAtStart,
  --   playerFainted (count), movesUsed (count), itemsUsed (bool, set
  --   at the end by comparing the bag before and after)
  -- ---------------------------------------------------------------
  events:on("battle.started", function(ev)
    ev = ev or {}
    local adapter = self.adapter
    -- Gen 2 reports each battle twice; keep the first report and fill in
    -- the trainer from whichever copy has it.
    local info = adapter and adapter.battleInfo and adapter:battleInfo(ev) or {}
    if info.key ~= nil and self.battle and self.battle.key == info.key then
      self.battle.trainerId = self.battle.trainerId or info.trainerId
      return
    end
    local party = adapter and adapter.partySnapshot and adapter:partySnapshot() or {}
    local maxLevel = 0
    for _, m in ipairs(party) do if (m.level or 0) > maxLevel then maxLevel = m.level end end
    local facts = adapter and adapter:facts()
    -- the player's lead Pokemon, read off the raw battle object
    local raw = type(ev.battle) == "table" and ev.battle or nil
    local lead = raw and type(raw.player) == "table" and type(raw.player.mon) == "table"
      and raw.player.mon.species or nil
    self.battle = {
      key = info.key,
      kind = ev.kind, trainerId = info.trainerName or ev.trainerId or info.trainerId, species = ev.species, level = ev.level,
      style = facts and facts.battleStyle and facts.battleStyle() or nil,
      partyAtStart = party, partyMaxAtStart = maxLevel,
      bagAtStart = adapter and adapter.bagSnapshot and adapter:bagSnapshot() or nil,
      playerFainted = 0, movesUsed = 0, map = self.map,
      used = lead and { lead } or {}, -- species the player sent out
      payDay = 0,
    }
    for k, v in pairs(info.extra or {}) do self.battle[k] = v end
    self:dispatch("battle.started", ev)
  end)
  if mod:supports("events", "battle.fainted") then
    events:on("battle.fainted", function(ev)
      local b, who = self.battle, ev and ev.battler
      if b and type(who) == "table" and (who.side == "player" or who.isPlayer == true) then
        b.playerFainted = b.playerFainted + 1
      end
    end)
  end
  if mod:supports("events", "battle.move_used") then
    events:on("battle.move_used", function(ev)
      local b, user = self.battle, ev and ev.user
      if b and type(user) == "table" and (user.side == "player" or user.isPlayer == true) then
        b.movesUsed = b.movesUsed + 1
      end
    end)
  end
  if mod:supports("events", "battle.battler_switched") then
    events:on("battle.battler_switched", function(ev)
      local b, who = self.battle, ev and ev.battler
      if b and type(who) == "table" and (who.side == "player" or who.isPlayer == true)
          and who.species then
        b.used[#b.used + 1] = who.species
      end
    end)
  end
  if mod:supports("events", "battle.turn_ended") then
    events:on("battle.turn_ended", function(ev)
      local b, raw = self.battle, ev and ev.battle
      if b and type(raw) == "table" and tonumber(raw.payDay) then
        b.payDay = math.max(b.payDay, tonumber(raw.payDay))
      end
    end)
  end
  events:on("battle.ended", function(ev)
    local b = self.battle
    local info = self.adapter and self.adapter.battleInfo and self.adapter:battleInfo(ev) or {}
    if not b and info.key ~= nil and self.lastBattle and self.lastBattle.key == info.key then
      -- the second report of a battle that already ended (Gen 2); a catch
      -- only arrives here, so let it update the result
      if ev and ev.result == "caught" then self.lastBattle.result = "caught" end
      return
    end
    if b and b.bagAtStart and self.adapter then
      -- Any bag item that went DOWN during the fight was used (balls
      -- included).  Rules that allow balls can check b.itemsUsedList.
      local now = self.adapter:bagSnapshot()
      b.itemsUsedList = {}
      for id, before in pairs(b.bagAtStart) do
        local a, c = tonumber(before) or 0, tonumber(now[id]) or 0
        if c < a then b.itemsUsedList[#b.itemsUsedList + 1] = id end
      end
      b.itemsUsed = #b.itemsUsedList > 0
    end
    if b then b.result = ev and ev.result end
    self:dispatch("battle.ended", ev)
    -- kept for rules that react to the story flag a win sets afterwards
    -- (gym leaders' EVENT_BEAT_* are set in the battle's onFinish)
    self.lastBattle = b
    self.battle = nil
  end)

  -- Where the player is (trackers ask "inside the gym?").  Registered
  -- before the dispatcher below, so trackers see the new map id.
  events:on("map.entered", function(ev)
    if ev and ev.mapId then self.map = ev.mapId end
  end)

  -- Every other event a core rule or tracker asked for.
  local wired = { ["battle.started"] = true, ["battle.ended"] = true }
  local names = {}
  for name in pairs(self.eventRules) do names[name] = true end
  for name in pairs(self.trackerEvents) do names[name] = true end
  -- driven from core.update below, not engine events
  names.tick, names.frame = nil, nil
  -- sent by this mod's own menus (rules/common.lua)
  for name in pairs(names) do if name:match("^ui%.") then names[name] = nil end end
  for name in pairs(names) do
    if not wired[name] then
      wired[name] = true
      local supported = mod:supports("events", name)
      if supported then
        events:on(name, function(ev) self:dispatch(name, ev) end)
      else
        self:log("event %s not supported here; its rules stay locked", name)
      end
    end
  end

  -- Deferred state evaluation: at most once per frame, and only when
  -- something marked it dirty.  core.update wraps the whole game step.
  -- "tick" and "frame" are pseudo-events for trackers that must watch
  -- state the engine has no event for (Pikachu's idle dance, a wall
  -- bump).  "frame" runs every frame, "tick" four times a second; each
  -- only if some tracker subscribed, and handlers return early when the
  -- player isn't where they care about.
  local TICK = 0.25
  local tickClock = 0
  mod.hooks:wrap("core.update", function(nextFn, game, dt)
    local result = nextFn(game, dt)
    if self.active then
      self.recheckClock = (self.recheckClock or 0) + (tonumber(dt) or 0)
      if self.recheckClock >= RECHECK_SECONDS then
        self.recheckClock = 0
        self.dirty = true
      end
    end
    if self.trackerEvents.frame and self.active then
      local ok, err = pcall(self.dispatch, self, "frame", { dt = dt })
      if not ok then mod.log:warn("frame failed: %s", tostring(err)) end
    end
    if self.trackerEvents.tick and self.active then
      tickClock = tickClock + (tonumber(dt) or 0)
      if tickClock >= TICK then
        local elapsed = tickClock
        tickClock = 0
        local ok, err = pcall(self.dispatch, self, "tick", { dt = elapsed })
        if not ok then mod.log:warn("tick failed: %s", tostring(err)) end
      end
    end
    if self.dirty and self.active then
      local ok, err = pcall(self.evaluateState, self, "event", false)
      if not ok then
        self.dirty = false
        mod.log:warn("state evaluation failed: %s", tostring(err))
      end
    end
    return result
  end)
end

-- ------------------------------------------------------------------
-- Read model for the browser and the public query API.
-- Builds plain rows; nothing returned here aliases live tables.
-- ------------------------------------------------------------------
function Engine:status(key)
  local def = self.registry:get(key)
  local record = self.ledger:record(key)
  if not def and not record then return nil end
  local row = {
    key = key,
    unlocked = record ~= nil,
    at = record and record.at,
    how = record and record.how,
    progress = record == nil and self.ledger:progress(key) or nil,
  }
  if def then
    local shown = self:display(def)
    row.id, row.title, row.description = def.id, shown.title, shown.description
    row.points, row.goal, row.unit = shown.points, def.goal, def.unit
    row.official, row.raId, row.raGameId = shown.official, shown.raId, shown.raGameId
    row.author, row.raType = shown.author, shown.raType
    row.extra, row.fidelity, row.note = def.extra, def.fidelity, def.note
    row.hidden, row.category = def.hidden, def.category
    row.source, row.provider = def.source, def.provider
    row.available = self.game ~= nil and self.registry.appliesTo(def, self.game)
      and not (def.extra and not self:extrasOn())
    row.archived = false
  else
    -- Saved but no definition this session: provider missing.
    row.title = record.title or key
    row.description = ""
    row.source = record.source
    row.provider = key:match("^mod:([^:]+):")
    row.available = false
    row.archived = true
    row.points = 0
  end
  return row
end

-- All rows relevant to the running game: every definition that applies,
-- plus archived records from the save.
function Engine:rows()
  local rows, seen = {}, {}
  for _, key in ipairs(self.registry.order) do
    local def = self.registry.defs[key]
    if self.game == nil or self.registry.appliesTo(def, self.game) then
      local row = self:status(key)
      -- switched-off extras disappear unless already earned
      if row.available or row.unlocked or self.game == nil then
        rows[#rows + 1] = row
      end
      seen[key] = true
    end
  end
  local data = self.ledger:peek()
  for _, key in ipairs(self.util.sortedKeys(data and data.unlocked)) do
    if not seen[key] then rows[#rows + 1] = self:status(key) end
  end
  return rows
end

-- Totals count ONLY earnable, available achievements, never reference
-- catalog entries and never archived ones.
function Engine:totals(filterSource)
  local t = { earned = 0, total = 0, points = 0, maxPoints = 0, archived = 0 }
  for _, row in ipairs(self:rows()) do
    if row.archived then
      t.archived = t.archived + 1
    elseif row.available and (not filterSource or row.source == filterSource) then
      t.total = t.total + 1
      t.maxPoints = t.maxPoints + (row.points or 0)
      if row.unlocked then
        t.earned = t.earned + 1
        t.points = t.points + (row.points or 0)
      end
    end
  end
  return t
end

-- In-game play time in seconds, or nil if the adapter can't tell.
function Engine:playTime()
  local a = self.adapter
  if not (a and a.playTime) then return nil end
  local ok, t = pcall(a.playTime, a)
  return ok and t or nil
end

-- Official RetroAchievements entries only (no bonus, no other mods):
-- the numbers the public leaderboard compares.  `reachedAt` is the play
-- time (seconds) of the latest official unlock, or nil with none.
function Engine:officialTotals()
  local t = { earned = 0, total = 0, points = 0, maxPoints = 0 }
  for _, row in ipairs(self:rows()) do
    if row.source == "core" and row.official and row.available then
      t.total = t.total + 1
      t.maxPoints = t.maxPoints + (row.points or 0)
      if row.unlocked then
        t.earned = t.earned + 1
        t.points = t.points + (row.points or 0)
        -- the score was reached at the latest unlock's play time; records
        -- from before 1.2.0 have none, so fall back to the time now
        local record = self.ledger:record(row.key)
        local pt = record and tonumber(record.pt) or self:playTime()
        if pt and (t.reachedAt == nil or pt > t.reachedAt) then t.reachedAt = pt end
      end
    end
  end
  return t
end

return Engine
