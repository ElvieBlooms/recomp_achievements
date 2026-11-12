-- core/api.lua
-- The public API other mods use, published through mod.exports. A provider
-- gets it with:
--
--   local found = mod.find("recomp_achievements")
--   local ach = found and found.exports
--
-- How it behaves (full guide: docs/PROVIDER_API.md):
--   Every call returns true on success, or nil, code, msg when something
--   expected goes wrong. Ordinary problems (unknown id, no save loaded
--   yet, a duplicate) never throw; only a real bug in this mod would.
--   Providers can only write inside their own "mod:<provider>:" space.
--   Each provider gets a handle bound to its id, so it never passes an
--   id that could be someone else's.
--   It's a friendly local API, not anti-cheat: it can't tell which mod is
--   really calling. Namespaces stop accidents, not bad intent.
--
-- Versioning: API_VERSION follows semver. New methods bump the minor
-- number; changing what a method means bumps the major. Check it with
-- ach.apiVersion or ach.supports("capability").
-- ------------------

local Api = {}

Api.VERSION = "1.5.0"
Api.CAPABILITIES = {
  register = true, register_many = true, unlock = true,
  progress = true, query = true, events = true, games_filter = true,
  hidden = true, official_totals = true, leaderboard_card = true, provider_tabs = true,
  extra_card = true, card_notes = true, card_note_press = true,
}

-- Writes per provider per second before calls return "rate_limited".
-- Plenty for real play, and stops a runaway loop becoming a popup storm.
Api.RATE_LIMIT = 120

local function clock()
  local timer = love and love.timer
  if timer and timer.getTime then return timer.getTime() end
  return os.clock()
end

-- Let a method be called as handle:fn(x) or handle.fn(x).
local function method(owner, fn)
  return function(first, ...)
    if first == owner then return fn(...) end
    return fn(first, ...)
  end
end

function Api.install(mod, engine, util, Share)
  local registry, ledger = engine.registry, engine.ledger
  local exports = mod.exports
  local handles = {}

  local function fail(code, message) return nil, code, message or code end
  local function result(ok, code, message)
    if ok then return true end
    return fail(code, message)
  end

  -- ------------------ provider handle
  -- Everything a provider writes goes through its handle.
  local function makeHandle(providerId)
    -- `handle` holds the methods and `public` is the read-only copy the
    -- provider gets. Methods check their first argument against `public`,
    -- so handle:unlock("x") and handle.unlock("x") both work.
    local handle = {}
    local public = util.readonly(handle)
    local window, writes = 0, 0

    local function key(localId)
      if not util.validId(localId) then return nil end
      return "mod:" .. providerId .. ":" .. localId
    end
    local function throttle()
      local now = clock()
      if now - window >= 1 then window, writes = now, 0 end
      writes = writes + 1
      return writes <= Api.RATE_LIMIT
    end

    handle.provider = providerId

    -- register(def) -> true | nil, code, msg
    -- Registering the same content again ("already_registered") counts as success.
    handle.register = method(public, function(def)
      local out, code, message = registry:add("provider", providerId, def)
      if not out then return fail(code, message) end
      return true
    end)

    -- registerMany({def, def, ...}) -> okCount, { [index] = {code, msg} }
    -- Good entries still register when others in the list fail.
    handle.registerMany = method(public, function(list)
      if type(list) ~= "table" then return 0, { { "invalid_definition", "expected a list" } } end
      local okCount, errors = 0, {}
      for i, def in ipairs(list) do
        local out, code, message = registry:add("provider", providerId, def)
        if out then okCount = okCount + 1 else errors[i] = { code, message } end
      end
      return okCount, errors
    end)

    handle.unlock = method(public, function(localId)
      local k = key(localId)
      if not k then return fail("invalid_id") end
      if not throttle() then return fail("rate_limited") end
      return result(engine:award(k, { how = "api" }))
    end)

    handle.setProgress = method(public, function(localId, value)
      local k = key(localId)
      if not k then return fail("invalid_id") end
      if not throttle() then return fail("rate_limited") end
      return result(engine:setProgress(k, value, { how = "api" }))
    end)

    handle.addProgress = method(public, function(localId, by)
      local k = key(localId)
      if not k then return fail("invalid_id") end
      if not throttle() then return fail("rate_limited") end
      return result(engine:addProgress(k, by == nil and 1 or by, { how = "api" }))
    end)

    handle.isUnlocked = method(public, function(localId)
      local k = key(localId)
      return k ~= nil and ledger:isUnlocked(k)
    end)

    handle.getProgress = method(public, function(localId)
      local k = key(localId)
      if not k then return fail("invalid_id") end
      local def = registry:get(k)
      if ledger:isUnlocked(k) then return def and def.goal or 1, def and def.goal end
      return ledger:progress(k), def and def.goal
    end)

    handle.get = method(public, function(localId)
      local k = key(localId)
      local row = k and engine:status(k)
      if not row then return fail("unknown_id") end
      return util.plain(row)
    end)

    handle.list = method(public, function()
      local out = {}
      for _, row in ipairs(engine:rows()) do
        if row.provider == providerId then out[#out + 1] = util.plain(row) end
      end
      return out
    end)

    return public
  end

  -- ------------------ top-level exports
  exports.apiVersion = Api.VERSION

  exports.getVersion = method(exports, function()
    return Api.VERSION, mod.version
  end)

  exports.supports = method(exports, function(capability)
    return Api.CAPABILITIES[capability] == true
  end)

  -- connect(providerId, { name = "...", version = "...", tab = "..." })
  -- Returns a handle. providerId should be your own mod.id, and calling
  -- again with the same id gives back the same handle.
  -- tab (since 1.3.0) is a short label for your own filter tab in the menu.
  exports.connect = method(exports, function(providerId, info)
    if type(providerId) == "table" and providerId.id then
      -- ach.connect(mod) works too: id, name and version come from the mod
      local defaults = { name = providerId.manifest and providerId.manifest.name,
                         version = providerId.version }
      if type(info) == "table" then
        for k, v in pairs(defaults) do if info[k] == nil then info[k] = v end end
      else
        info = defaults
      end
      providerId = providerId.id
    end
    if not util.validId(providerId) then
      return fail("invalid_provider", "provider id must look like a mod id")
    end
    if providerId == "core" then return fail("invalid_provider", "'core' is reserved") end
    if handles[providerId] then return handles[providerId] end
    registry:addProvider(providerId, type(info) == "table" and info or {})
    handles[providerId] = makeHandle(providerId)
    return handles[providerId]
  end)

  -- Read-only queries by full key, like "core:boulder_badge" or
  -- "mod:other_mod:thing". Any mod can read any achievement.
  exports.isUnlocked = method(exports, function(fullKey)
    return type(fullKey) == "string" and ledger:isUnlocked(fullKey)
  end)

  exports.get = method(exports, function(fullKey)
    local row = type(fullKey) == "string" and engine:status(fullKey)
    if not row then return fail("unknown_id") end
    return util.plain(row)
  end)

  -- list({ source = "core" | "mod:<id>", unlocked = true|false })
  exports.list = method(exports, function(filter)
    filter = type(filter) == "table" and filter or {}
    local out = {}
    for _, row in ipairs(engine:rows()) do
      if (filter.source == nil or row.source == filter.source)
          and (filter.unlocked == nil or row.unlocked == filter.unlocked) then
        out[#out + 1] = util.plain(row)
      end
    end
    return out
  end)

  exports.totals = method(exports, function(source)
    return util.plain(engine:totals(source))
  end)

  -- Official RetroAchievements entries only: { earned, total, points, maxPoints }.
  exports.officialTotals = method(exports, function()
    return util.plain(engine:officialTotals())
  end)

  -- The leaderboard card from the menu's SELECT page:
  -- { game, name, points, earned, total, maxPoints, saveId, code }.
  -- nil before a save is loaded.
  exports.leaderboardCard = method(exports, function()
    if not Share then return nil end
    local card = Share.card(engine)
    return card and util.plain(card) or nil
  end)

  -- The Extra Credit page (since 1.4.0):
  -- { game, name, saveId, points, earned, total, code,
  --   sources = { { id, label, earned, total, points }, ... } }.
  -- nil before a save is loaded.
  exports.extraCard = method(exports, function()
    if not Share then return nil end
    local card = Share.extraCard(engine)
    return card and util.plain(card) or nil
  end)

  -- A note on the leaderboard card (since 1.4.0). fn(card) returns a string
  -- or up to three strings of 18 characters; nil shows nothing. Notes
  -- replace the "enter at" text, so use it for something the player needs
  -- instead, like an online add-on's status. Calling again replaces yours.
  -- Since 1.5.0, opts.onPress(card) gets the A button on the card page;
  -- return true when you used it, or the card closes as usual.
  exports.addCardNote = method(exports, function(providerId, fn, opts)
    if type(providerId) == "table" and providerId.id then providerId = providerId.id end
    if not util.validId(providerId) then
      return fail("invalid_provider", "provider id must look like a mod id")
    end
    if not Share then return fail("unavailable") end
    local onPress = type(opts) == "table" and opts.onPress or nil
    if not Share.addNote(providerId, fn, onPress) then
      return fail("invalid_note", "fn and opts.onPress must be functions")
    end
    return true
  end)

  -- The active save's game, or nil before a save is loaded.
  exports.currentGame = method(exports, function()
    return engine.active and engine.game or nil
  end)

  -- Event names, so providers don't have to hard-code them.
  exports.events = util.readonly({
    unlocked = "mod.recomp_achievements.unlocked",
    progress = "mod.recomp_achievements.progress",
    ready = "mod.recomp_achievements.ready",
  })
end

return Api
