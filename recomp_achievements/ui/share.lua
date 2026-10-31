-- ui/share.lua
-- ==================================================================
-- The leaderboard card: what a player types into the GitHub issue form
-- to put their score on the public leaderboard page.
--
-- The mod itself never goes online.  It only shows the numbers plus a
-- short CHECK CODE.  The code is a checksum over the other fields, so the
-- GitHub Action that reads the form can catch typos.  It is NOT security:
-- anyone can read this file and compute a code, so the leaderboard is an
-- honor system, and its page says so.
--
-- The same checksum is implemented in tools/leaderboard_ingest.py; the
-- two must stay identical (tests/run.lua checks known values).
-- ==================================================================

local Share = {}

-- v2 adds the play time (whole minutes) when the score was reached.
-- v1 codes (mod 1.1.0, no TIME line) are still accepted by the bot.
Share.VERSION = "v2"

-- Crockford base32: no I, L, O or U, so the code is easy to read off a
-- Game Boy screen and type.
local ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

-- Normalise a trainer name the way the server does before hashing:
-- uppercase ASCII letters, drop spaces.  Non-ASCII glyphs (é, ♂, ♀) are
-- kept as their UTF-8 bytes.
function Share.normName(name)
  return (tostring(name or ""):gsub("%s", ""):upper())
end

-- 32-bit djb2-style hash, kept below 2^53 at every step so plain Lua
-- numbers are exact (no bit library needed).
local function hash(s, seed)
  local h = seed
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 4294967296
  end
  return h
end

local function base32(n, digits)
  local out = {}
  for i = digits, 1, -1 do
    local d = n % 32
    out[i] = ALPHABET:sub(d + 1, d + 1)
    n = math.floor(n / 32)
  end
  return table.concat(out)
end

-- The canonical string the checksum covers.  `f.time` is in minutes.
function Share.payload(f)
  local parts = { f.time ~= nil and "v2" or "v1", f.game, Share.normName(f.name),
    tostring(f.points), tostring(f.earned), tostring(f.saveId):upper() }
  if f.time ~= nil then parts[#parts + 1] = tostring(math.floor(f.time)) end
  return table.concat(parts, "|")
end

-- Minutes as H:MM, like the trainer card's TIME.
function Share.clock(minutes)
  minutes = math.floor(tonumber(minutes) or 0)
  return ("%d:%02d"):format(math.floor(minutes / 60), minutes % 60)
end

-- 8 characters, shown as XXXX-XXXX: 20 bits from each of two hashes.
function Share.code(f)
  local p = Share.payload(f)
  local a = hash(p, 5381) % 1048576
  local b = hash(p, 52711) % 1048576
  local s = base32(a, 4) .. base32(b, 4)
  return s:sub(1, 4) .. "-" .. s:sub(5, 8)
end

-- A short id for this playthrough, so the leaderboard keeps one row per
-- playthrough.  It comes from the engine's save.meta.playthroughId, which
-- stays the same across saves and Save Sync and changes with a New Game.
-- Saves without one get a random id kept in the ledger instead.
function Share.saveId(save, ledgerData)
  local meta = type(save) == "table" and save.meta
  local pid = type(meta) == "table" and meta.playthroughId
  if pid ~= nil and tostring(pid) ~= "" then
    return base32(hash("pid|" .. tostring(pid), 5381) % 1073741824, 6)
  end
  if type(ledgerData.saveId) == "string" and ledgerData.saveId:match("^[0-9A-Z]+$") then
    return ledgerData.saveId
  end
  local rand = (love and love.math and love.math.random) or math.random
  local n = 0
  for _ = 1, 6 do n = n * 32 + rand(0, 31) end
  ledgerData.saveId = base32(n, 6)
  return ledgerData.saveId
end

-- Everything the card shows, or nil when no save is loaded.
function Share.card(engine)
  if not (engine.active and engine.game) then return nil end
  local data = engine.ledger:get(engine.game)
  local save = engine.adapter and engine.adapter:save() or {}
  -- Gen 1/2 keep the name under save.player; Gen 3 at save.name
  local name = type(save.player) == "table" and save.player.name
    or (type(save.name) == "string" and save.name ~= "" and save.name) or "?"
  local t = engine:officialTotals()
  local f = {
    game = engine.game, name = name, points = t.points, earned = t.earned,
    total = t.total, maxPoints = t.maxPoints, saveId = Share.saveId(save, data),
    -- play time when this score was reached (the last official unlock)
    time = engine:playTime() and math.floor((t.reachedAt or 0) / 60) or nil,
  }
  f.code = Share.code(f)
  return f
end

-- ------------------------------------------------------------------
-- Extra Credit: the achievements the main board leaves out, this mod's
-- bonus ones and other mods', each source on its own line so the board
-- can rank the combined total and every mod separately.
--
--   source id: "bonus", or the providing mod's id ("naviplay")
--   line:      "<id> <earned>/<total> <points>"   e.g. "bonus 3/9 20"
--
-- The extra code covers game, name, save id and every source, sorted by
-- id, in the same checksum as the main card (prefix "x1").
-- ------------------------------------------------------------------
Share.EXTRA_VERSION = "x1"

function Share.extraLine(s)
  return ("%s %d/%d %d"):format(s.id, s.earned, s.total, s.points)
end

function Share.extraPayload(f)
  local list = {}
  for _, s in ipairs(f.sources or {}) do
    list[#list + 1] = ("%s:%d:%d:%d"):format(s.id, s.earned, s.total, s.points)
  end
  table.sort(list)
  return table.concat({ Share.EXTRA_VERSION, f.game, Share.normName(f.name),
                        tostring(f.saveId):upper(), table.concat(list, ",") }, "|")
end

function Share.extraCode(f)
  local p = Share.extraPayload(f)
  local a = hash(p, 5381) % 1048576
  local b = hash(p, 52711) % 1048576
  local s = base32(a, 4) .. base32(b, 4)
  return s:sub(1, 4) .. "-" .. s:sub(5, 8)
end

-- Sources from the engine's rows: earned/total/points per source, for
-- achievements that apply to this game (archived ones aren't counted:
-- their mod isn't loaded, so the total can't be known).
function Share.extraSources(engine)
  local by, order = {}, {}
  local ok, rows = pcall(function() return engine:rows() end)
  for _, row in ipairs(ok and rows or {}) do
    local id
    if row.source == "core" and not row.official then id = "bonus"
    elseif row.source ~= "core" and row.provider and not row.archived then id = row.provider end
    if id then
      local s = by[id]
      if not s then
        local p = engine.registry and engine.registry.providers[id]
        s = { id = id, label = id == "bonus" and "BONUS" or (p and (p.tab or p.name)) or id,
              earned = 0, total = 0, points = 0 }
        by[id] = s; order[#order + 1] = s
      end
      s.total = s.total + 1
      if row.unlocked then
        s.earned = s.earned + 1
        s.points = s.points + math.floor(tonumber(row.points) or 0)
      end
    end
  end
  table.sort(order, function(a, b)
    if a.id == "bonus" then return b.id ~= "bonus" end
    if b.id == "bonus" then return false end
    return a.id < b.id
  end)
  return order
end

function Share.extraCard(engine)
  local main = Share.card(engine)
  if not main then return nil end
  local f = { game = main.game, name = main.name, saveId = main.saveId,
              sources = Share.extraSources(engine), points = 0, earned = 0, total = 0 }
  for _, s in ipairs(f.sources) do
    f.points, f.earned, f.total = f.points + s.points, f.earned + s.earned, f.total + s.total
  end
  f.code = Share.extraCode(f)
  return f
end

return Share
