return function(ctx)
  local mod = ctx.mod
  local function wait(s) local t0 return function(_, c) if not t0 then t0 = c.t end; if c.t - t0 >= s then t0 = nil return true end end end
  local function shot(name) return function()
    love.graphics.captureScreenshot(function(img) img:encode("png", "e2e_" .. name .. ".png") end)
    return true end end
  local function tap(b) return function(game) mod.input:tap(game, b); return true end end
  local function top(game) local s = game.stack.states; return s[#s] end
  return {
    wait(3),
    function(game)
      local SaveData = require("src.core.SaveData")
      local loaded, rec = SaveData.load()
      ctx.log("save version=%s flags=%d", tostring(loaded and loaded.version), (function() local n=0 for _ in pairs(loaded.flags or {}) do n=n+1 end return n end)())
      game:restoreSave(loaded, rec, { freshBoot = true, continued = true })
      return true
    end,
    wait(0.5), shot("toast"), wait(1.5), tap("a"), wait(1), tap("a"), wait(2), shot("after_report"),
    function(game)
      local ach = mod.find("recomp_achievements").exports
      local t = ach.totals()
      ctx.log("totals earned=%d total=%d points=%d/%d archived=%d game=%s", t.earned, t.total, t.points, t.maxPoints, t.archived, tostring(ach.currentGame()))
      for _, r in ipairs(ach.list({ unlocked = true })) do ctx.log("  unlocked %s (%s)", r.key, tostring(r.how)) end
      for _, r in ipairs(ach.list({ unlocked = false })) do if (r.progress or 0) > 0 then ctx.log("  progress %s %d/%d", r.key, r.progress, r.goal) end end
      return true
    end,
    tap("start"), wait(0.8), shot("startmenu"),
    function(game)
      local m = top(game)
      for i, it in ipairs(m.items or {}) do ctx.log("menu %d %s", i, tostring(it.label)) end
      for i, it in ipairs(m.items or {}) do if it.label == "ACHIEVEMENTS" then m.index = i end end
      return true
    end,
    wait(0.2), shot("startmenu_sel"), tap("a"), wait(0.5), shot("browser"),
    tap("right"), wait(0.2), shot("browser_earned"),
    tap("a"), wait(0.3), shot("detail"), tap("b"), wait(0.2), tap("b"), wait(0.5),
    function(game) ctx.log("after close top=%s", tostring(top(game) and top(game).screenId)); return true end,
    function(game) ctx.log("writeSave -> %s", tostring(game:writeSave())); return true end,
    wait(1),
  }
end
