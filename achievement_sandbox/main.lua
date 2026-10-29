-- Achievement API Sandbox
-- ==================================================================
-- A deliberately small "provider" mod: the reference for how ANY mod can
-- add achievements to Recomp Achievements.  It exercises each part of
-- the public API once:
--
--   hello         instant unlock          handle:unlock
--   walker        progress counter        handle:addProgress  (goal 500)
--   nurse_joy     hidden + counter        hidden = true       (goal 5)
--   yellow_guest  game filter             games = { "yellow" }
--   overachiever  listening to events     mod.events:on(ach.events.unlocked)
--
-- The framework is an OPTIONAL dependency (manifest.json): if it's
-- installed it loads first; if not, mod.find returns nil and this mod
-- quietly does nothing.  That "degrade, don't crash" rule is the most
-- important pattern in here.
-- ==================================================================

return function(mod)
  local found = mod.find("recomp_achievements")
  if not found then
    mod.log:info("Recomp Achievements not installed; sandbox idle")
    return
  end
  local ach = found.exports

  -- Version handshake: we were written against API 1.x.
  local major = tonumber(tostring(ach.apiVersion or ""):match("^(%d+)"))
  if major ~= 1 or not ach.supports("progress") then
    mod.log:warn("unsupported achievements API %s; sandbox idle", tostring(ach.apiVersion))
    return
  end

  -- connect() hands back a handle bound to OUR namespace
  -- ("mod:achievement_sandbox:<id>").  Passing `mod` fills in name/version.
  local handle, code, message = ach.connect(mod)
  if not handle then
    mod.log:warn("connect failed: %s %s", tostring(code), tostring(message))
    return
  end

  -- Definitions are registered every session.  They are not saved; the
  -- framework saves only the unlock/progress records.
  local okCount, errors = handle:registerMany({
    { id = "hello", title = "Hello, Framework", points = 1, category = "SANDBOX",
      description = "Load a save with the Achievement API Sandbox installed." },
    { id = "walker", title = "Sandbox Stroll", points = 5, category = "SANDBOX",
      goal = 500, unit = "STEPS",
      description = "Walk 500 steps while the sandbox is installed." },
    { id = "nurse_joy", title = "Frequent Visitor", points = 5, category = "SANDBOX",
      goal = 5, unit = "VISITS", hidden = true,
      description = "Walk into a Pokemon Center five times." },
    { id = "yellow_guest", title = "Electric Welcome", points = 2, category = "SANDBOX",
      games = { "yellow" },
      description = "Load a Pokemon Yellow save with the sandbox installed." },
    { id = "overachiever", title = "Overachiever", points = 10, category = "SANDBOX",
      goal = 5, unit = "UNLOCKS",
      description = "Earn five other achievements, from any source." },
  })
  for i, err in pairs(errors) do
    mod.log:warn("definition %d rejected: %s %s", i, tostring(err[1]), tostring(err[2]))
  end
  mod.log:info("registered %d sandbox achievements", okCount)

  -- The framework's "ready" event fires once a save is attached, which is
  -- the right moment for load-time unlocks (before it, unlock returns
  -- nil, "no_save").
  mod.events:on(ach.events.ready, function(ev)
    handle:unlock("hello")
    if ev and ev.game == "yellow" then handle:unlock("yellow_guest") end
  end)

  mod.events:on("world.stepped", function()
    handle:addProgress("walker", 1)
  end)

  mod.events:on("map.entered", function(ev)
    local id = ev and ev.mapId
    if type(id) == "string" and id:find("POKECENTER", 1, true) and ev.via == "warp" then
      handle:addProgress("nurse_joy", 1)
    end
  end)

  -- Listening: count unlocks that aren't this one.  Events are plain
  -- copies; nothing we do here can alter the framework's records.
  mod.events:on(ach.events.unlocked, function(ev)
    if ev and ev.key ~= "mod:achievement_sandbox:overachiever" then
      handle:addProgress("overachiever", 1)
    end
  end)
end
