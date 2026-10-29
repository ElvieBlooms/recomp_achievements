-- Test-only driver.  Runs the steps returned by plan.lua, one at a time,
-- from the core.update hook.  A step is a function(game, ctx, dt) that
-- returns true when finished (it is called every frame until then).
return function(mod)
  local source = assert(mod:read("plan.lua"), "plan.lua missing")
  local plan = assert(load(source, "@plan.lua"))()
  local ctx = { mod = mod, t = 0, log = function(fmt, ...)
    print(("[E2E] " .. fmt):format(...)) end }
  local steps = plan(ctx)
  local i, started = 1, false
  mod.events:on("game.ready", function(ev) ctx.game = ev.game; started = true end)
  for _, name in ipairs({ "save.loaded", "save.created", "save.writing",
                          "mod.recomp_achievements.unlocked",
                          "mod.recomp_achievements.progress",
                          "mod.recomp_achievements.ready" }) do
    mod.events:on(name, function(ev)
      local extra = ev and (ev.key or ev.game or "") or ""
      ctx.log("event %s %s %s", name, tostring(extra),
        ev and ev.value and (tostring(ev.value) .. "/" .. tostring(ev.goal)) or "")
    end)
  end
  mod.hooks:wrap("core.update", function(nextFn, game, dt)
    local r = nextFn(game, dt)
    ctx.t = ctx.t + dt
    if started and steps[i] then
      local ok, done = pcall(steps[i], game, ctx, dt)
      if not ok then ctx.log("step %d ERROR %s", i, tostring(done)); i = #steps + 1
      elseif done then ctx.log("step %d done (t=%.1f)", i, ctx.t); i = i + 1 end
      if not steps[i] then ctx.log("PLAN COMPLETE") end
    end
    return r
  end)
end
