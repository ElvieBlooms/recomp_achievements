return function(ctx)
  local mod = ctx.mod
  local function wait(s) local t0 return function(_, c) if not t0 then t0 = c.t end; if c.t - t0 >= s then t0 = nil return true end end end
  local function shot(name) return function()
    love.graphics.captureScreenshot(function(img) img:encode("png", "e2e_" .. name .. ".png") end)
    return true end end
  local KEY = { a = "z", b = "x", start = "escape", select = "tab", up = "up", down = "down", left = "left", right = "right" }
  local function tap(b) local t0 return function(game, c)
    if not t0 then t0 = c.t; love.event.push("keypressed", KEY[b], KEY[b], false) return false end
    if c.t - t0 > 0.12 then love.event.push("keyreleased", KEY[b], KEY[b]); t0 = nil return true end end end
  local function untilField(game) return game.phase == "field" end
  local function ach() return mod.find("recomp_achievements").exports end
  local function report(tag) return function()
    local a = ach()
    local t = a.totals()
    ctx.log("%s totals earned=%d/%d points=%d/%d game=%s", tag, t.earned, t.total, t.points, t.maxPoints, tostring(a.currentGame()))
    local n = 0
    for _, r in ipairs(a.list({ unlocked = true })) do n = n + 1 if n <= 80 then ctx.log("  unlocked %s", r.key) end end
    for _, r in ipairs(a.list({ unlocked = false })) do if (r.progress or 0) > 0 then ctx.log("  progress %s %s/%s", r.key, tostring(r.progress), tostring(r.goal)) end end
    return true end end
  mod.events:on("mod.recomp_achievements.unlocked", function(ev) ctx.log("UNLOCK %s", tostring(ev and ev.key)) end)
  mod.events:on("battle.started", function(ev) ctx.log("battle.started trainerId=%s kind=%s", tostring(ev.trainerId), tostring(ev.kind)) end)
  mod.events:on("battle.ended", function(ev) ctx.log("battle.ended result=%s", tostring(ev.result)) end)
  return {
    wait(3), tap("start"), wait(5), shot("t1"), tap("a"), wait(4), shot("t2"),
    function(game, c)
      if game.phase == "field" then return true end
      ctx.k = (ctx.k or 0) + 1
      if ctx.k % 100 == 1 then love.event.push("keypressed", "z", "z", false) end
      if ctx.k % 100 == 8 then love.event.push("keyreleased", "z", "z") end
      if ctx.k == 400 then love.graphics.captureScreenshot(function(img) img:encode("png", "e2e_stuck.png") end) end
    end, shot("w0"), wait(0.5), shot("w1"), wait(0.5), shot("w2"), wait(0.5), shot("w3"), wait(1), shot("welcome"),
    report("loaded"),
    wait(4), shot("after_toasts"),
    tap("start"), wait(1),
    function(game) local SM = require("src.ui.game3.start_menu")
      ctx.downs = 0
      for i, e in ipairs(SM and SM.ENTRIES or {}) do if e.label == "MODS" then ctx.downs = i - (SM.cursor or 1) end end
      return true end,
    function(game, c)
      if ctx.downs <= 0 then return true end
      ctx.dk = (ctx.dk or 0) + 1
      if ctx.dk % 12 == 1 then love.event.push("keypressed", "down", "down", false) end
      if ctx.dk % 12 == 5 then love.event.push("keyreleased", "down", "down"); ctx.downs = ctx.downs - 1 end
    end,
    tap("a"), wait(1.5), shot("mm_list"),
    function(game)
      local MM = require("src.ui.game3.mod_manager")
      local m = MM._mgr
      ctx.log("manager open=%s", tostring(m ~= nil))
      local target
      for _, r in ipairs(m and m:rowsForScreen() or {}) do if r.mod and r.mod.id == "recomp_achievements" then target = r.mod end end
      ctx.log("found mod=%s", tostring(target ~= nil))
      m.currentMod = target; m:openOptions(target)
      ctx.log("options screen=%s cursor=%s", tostring(m.screen), tostring(m.cursor))
      return true end,
    wait(0.8), shot("mm_options"), tap("a"), wait(1.2), shot("mm_opened"),
    function(game)
      local MM = require("src.ui.game3.mod_manager")
      local Stack = require("src.ui.game3.stack")
      ctx.log("after A: manager open=%s", tostring(MM.isOpen()))
      return true end,
    tap("b"), wait(1), shot("mm_back"),
    function() ctx.log("after B: manager open=%s screen=%s", tostring(require("src.ui.game3.mod_manager").isOpen()), tostring(require("src.ui.game3.mod_manager")._mgr and require("src.ui.game3.mod_manager")._mgr.screen)) return true end,
  }
end
