-- core/ledger.lua
-- ==================================================================
-- The ledger is the ONLY persistent state this mod owns.  It lives in
-- mod.save under the key "ledger", which the engine stores at
-- save.modData.recomp_achievements.ledger.  Because Save Sync ships the
-- whole serialized save (src/sync/SyncEngine.lua), the ledger rides
-- along with no extra work.
--
-- Shape (schema 1):
--   {
--     schema   = 1,
--     game     = "red",            -- version this ledger was created on
--     unlocked = { [key] = record },
--     progress = { [key] = number },
--     counters = { [name] = number }, -- private tallies for core rules
--     quarantine = { [key] = original }, -- malformed records, kept not lost
--   }
--   record = {
--     at = <os.time()>, how = "event" | "backfill" | "api",
--     source = "core" | "mod:<provider>", title = "<last known title>",
--     pt = <play time in seconds when earned; missing on 1.1.0 records>,
--   }
--
-- Keys look like "core:boulder_badge" or "mod:sandbox:first_steps".
--
-- IMPORTANT: mod.save:get returns a reference INTO the live save table,
-- so editing the ledger edits the save.  It is written to disk the next
-- time the player saves; quitting without saving rolls it back, exactly
-- like the rest of the game.  We never cache the table across loads --
-- the engine swaps the backing table on Continue/New Game -- so every
-- access goes through Ledger:get().
-- ==================================================================

local Ledger = {}
Ledger.__index = Ledger

Ledger.SCHEMA = 1
Ledger.KEY = "ledger"
Ledger.TITLE_MAX = 40 -- bytes of last-known title kept per record

-- Each step upgrades from schema N to N+1.  They must be safe to run on a
-- partially upgraded table (a crash mid-migration can happen).
local MIGRATIONS = {
  -- [1] = function(data) ... end   -- example: schema 1 -> 2 goes here
}

function Ledger.new(mod, util)
  return setmetatable({ mod = mod, util = util }, Ledger)
end

local function validKey(key)
  return type(key) == "string" and #key <= 120
    and (key:match("^core:[a-z0-9_%-]+$") or key:match("^mod:[a-z0-9_%-]+:[a-z0-9_%-]+$"))
end

-- Make sure every expected sub-table exists and each record has the right
-- shape.  Anything that does not fit moves to `quarantine` rather than
-- being deleted, so a bug never silently erases a player's history.
function Ledger:repair(data)
  data.unlocked = type(data.unlocked) == "table" and data.unlocked or {}
  data.progress = type(data.progress) == "table" and data.progress or {}
  data.counters = type(data.counters) == "table" and data.counters or {}
  data.quarantine = type(data.quarantine) == "table" and data.quarantine or {}
  for key, record in pairs(data.unlocked) do
    if not validKey(key) or type(record) ~= "table" then
      data.quarantine[tostring(key)] = self.util.plain(record)
      data.unlocked[key] = nil
    end
  end
  for key, value in pairs(data.progress) do
    if not validKey(key) or type(value) ~= "number" or value ~= value then
      data.progress[key] = nil
    end
  end
  for name, value in pairs(data.counters) do
    if type(name) ~= "string" or type(value) ~= "number" or value ~= value then
      data.counters[name] = nil
    end
  end
  return data
end

-- Returns the live ledger table for the active save, creating it on first
-- use.  `game` is the running version id, recorded on creation.
function Ledger:get(game)
  local data = self.mod.save:get(Ledger.KEY)
  if type(data) ~= "table" then
    data = { schema = Ledger.SCHEMA, game = game }
    self.mod.save:set(Ledger.KEY, data)
  end
  local schema = tonumber(data.schema) or 1
  if schema > Ledger.SCHEMA then
    -- A NEWER version of this mod wrote this save (e.g. synced from a
    -- device that updated first).  Read it, but don't migrate it down.
    self.newer = true
  else
    while schema < Ledger.SCHEMA do
      local step = MIGRATIONS[schema]
      if step then step(data) end
      schema = schema + 1
      data.schema = schema
    end
  end
  if data.game == nil then data.game = game end
  return self:repair(data)
end

-- Like get(), but never creates anything.  Used by read-only queries so
-- merely opening the browser on the title screen leaves no footprint.
function Ledger:peek()
  local data = self.mod.save:get(Ledger.KEY)
  if type(data) ~= "table" then return nil end
  return data
end

function Ledger:isUnlocked(key)
  local data = self:peek()
  return data ~= nil and type(data.unlocked) == "table" and data.unlocked[key] ~= nil
end

function Ledger:record(key)
  local data = self:peek()
  return data and type(data.unlocked) == "table" and data.unlocked[key] or nil
end

function Ledger:progress(key)
  local data = self:peek()
  local value = data and type(data.progress) == "table" and data.progress[key]
  return type(value) == "number" and value or 0
end

-- Write an unlock.  Returns false if it was already there (idempotent).
function Ledger:unlock(game, key, fields)
  local data = self:get(game)
  if data.unlocked[key] then return false end
  data.unlocked[key] = {
    at = os.time(),
    how = fields.how or "event",
    source = fields.source,
    title = self.util.text(fields.title, Ledger.TITLE_MAX),
    -- in-game play time (seconds) when it was earned, if the game has one
    pt = tonumber(fields.pt) and math.floor(tonumber(fields.pt)) or nil,
  }
  data.progress[key] = nil -- the record supersedes partial progress
  return true
end

function Ledger:setProgress(game, key, value)
  local data = self:get(game)
  if value <= 0 then data.progress[key] = nil else data.progress[key] = value end
end

function Ledger:counter(game, name)
  local data = self:get(game)
  return data.counters[name] or 0
end

function Ledger:bumpCounter(game, name, by)
  local data = self:get(game)
  data.counters[name] = (data.counters[name] or 0) + (by or 1)
  return data.counters[name]
end

-- Developer/test helper: forget one record.  Not exported to other mods.
function Ledger:revoke(game, key)
  local data = self:get(game)
  local had = data.unlocked[key] ~= nil
  data.unlocked[key] = nil
  data.progress[key] = nil
  return had
end

return Ledger
