-- core/api.lua
-- ==================================================================
-- The public API other mods use.  It is published through mod.exports;
-- a provider reaches it with
--
--   local found = mod.find("recomp_achievements")
--   local ach = found and found.exports
--
-- Contract (full guide: docs/PROVIDER_API.md):
--   * Every call returns  true            on success
--                    or   nil, code, msg  on an expected failure.
--     Ordinary problems (unknown id, no save loaded yet, duplicate) never
--     throw; only a genuine bug inside this mod would.
--   * Providers write only inside their own namespace "mod:<provider>:".
--     That is enforced by giving each provider a HANDLE bound to its id,
--     not by trusting an id passed on every call.
--   * This is a cooperative, local API.  It cannot verify which mod is
--     really calling, so it is not anti-cheat.  Namespaces prevent
--     accidents, not malice.
--
-- Versioning: API_VERSION follows semver.  Adding methods bumps minor;
-- changing what an existing method means bumps major.  Check it with
-- ach.apiVersion or ach.supports("capability").
-- ==================================================================

local Api = {}

Api.VERSION = "1.0.0"
Api.CAPABILITIES = {
  register = true, register_many = true, unlock = true,
  progress = true, query = true, events = true, games_filter = true,
  hidden = true,
}

-- Writes per provider per second before calls start returning
-- "rate_limited".  Generous for real play, stops a runaway loop from
-- turning into a popup storm.
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

function Api.install(mod, engine, util)
  local registry, ledger = engine.registry, engine.ledger
  local exports = mod.exports
  local handles = {}

  local function fail(code, message) return nil, code, message or code end
  local function result(ok, code, message)
    if ok then return true end
    return fail(code, message)
  end

  -- ---------------------------------------------------------------
  -- Provider handle: everything a provider WRITES goes through here.
  -- ---------------------------------------------------------------
  local function makeHandle(providerId)
    -- `handle` holds the methods; `public` is the read-only face given to
    -- the provider.  Methods compare their first argument with `public` so
    -- both handle:unlock("x") and handle.unlock("x") work.
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
    -- "already_registered" with identical content counts as success.
    handle.register = method(public, function(def)
      local out, code, message = registry:add("provider", providerId, def)
      if not out then return fail(code, message) end
      return true
    end)

    -- registerMany({def, def, ...}) -> okCount, { [index] = {code, msg} }
    -- Best effort: good entries register even if some fail.
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

  -- ---------------------------------------------------------------
  -- Top-level exports
  -- ---------------------------------------------------------------
  exports.apiVersion = Api.VERSION

  exports.getVersion = method(exports, function()
    return Api.VERSION, mod.version
  end)

  exports.supports = method(exports, function(capability)
    return Api.CAPABILITIES[capability] == true
  end)

  -- connect(providerId, { name = "...", version = "..." })
  -- providerId should be your own mod.id.  Returns a handle.
  -- Calling twice with the same id returns the same handle.
  exports.connect = method(exports, function(providerId, info)
    if type(providerId) == "table" and providerId.id then
      -- convenience: ach.connect(mod) passes the whole mod object
      info = info or { name = providerId.manifest and providerId.manifest.name,
                       version = providerId.version }
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

  -- Read-only queries by full key ("core:boulder_badge",
  -- "mod:other_mod:thing").  Any mod may read any achievement.
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

  -- Which game the active save is, or nil before a save is loaded.
  exports.currentGame = method(exports, function()
    return engine.active and engine.game or nil
  end)

  -- Event names, so providers don't hard-code strings.
  exports.events = util.readonly({
    unlocked = "mod.recomp_achievements.unlocked",
    progress = "mod.recomp_achievements.progress",
    ready = "mod.recomp_achievements.ready",
  })
end

return Api
