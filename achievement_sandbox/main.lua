-- achievement_sandbox/main.lua
-- The Achievement API Sandbox, a small example provider mod.
-- It shows how any mod can add its own achievements to Recomp Achievements,
-- using each part of the public API once:
--
--   hello         instant unlock          handle:unlock
--   walker        progress counter        handle:addProgress  (goal 500)
--   nurse_joy     hidden with a counter   hidden = true       (goal 5)
--   yellow_guest  game filter             games = { "yellow" }
--   overachiever  listening to events     mod.events:on(ach.events.unlocked)
--
-- Recomp Achievements is an optional dependency in manifest.json, so the
-- engine's mod loader runs it first when it's there. When it isn't,
-- mod.find returns nil and this mod quietly does nothing.
-- Staying out of the way instead of crashing is the main pattern to copy from here.
-- It never touches the save itself; the framework keeps the records.
-- ------------------

return function(mod)
  local found = mod.find("recomp_achievements")
  if not found then
    mod.log:info("Recomp Achievements not installed; sandbox idle")
    return
  end
  local ach = found.exports

  -- This was written against API 1.x, so anything else leaves the sandbox idle.
  local major = tonumber(tostring(ach.apiVersion or ""):match("^(%d+)"))
  if major ~= 1 or not ach.supports("progress") then
    mod.log:warn("unsupported achievements API %s; sandbox idle", tostring(ach.apiVersion))
    return
  end

  -- connect() hands back a handle bound to our own namespace, "mod:achievement_sandbox:<id>".
  -- Passing `mod` fills in the name and version.
  -- `tab` (API 1.3.0 on) labels our own filter tab in the menu.
  local handle, code, message = ach.connect(mod, { tab = "SANDBOX" })
  if not handle then
    mod.log:warn("connect failed: %s %s", tostring(code), tostring(message))
    return
  end

  -- Definitions are registered every session and never saved.
  -- The framework only saves the unlock and progress records.
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

  -- The framework's ready event fires once a save is attached, so that's the
  -- moment for load-time unlocks. Before it, unlock returns nil, "no_save".
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

  -- Counts every unlock except this one.
  -- Events are plain copies, so nothing done here can change the framework's records.
  mod.events:on(ach.events.unlocked, function(ev)
    if ev and ev.key ~= "mod:achievement_sandbox:overachiever" then
      handle:addProgress("overachiever", 1)
    end
  end)
end
