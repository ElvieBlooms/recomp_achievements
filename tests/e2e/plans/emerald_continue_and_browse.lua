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
    -- open START, find our row
    tap("start"), wait(1), shot("startmenu"),
    function(game) local SM = require("src.ui.game3.start_menu")
      ctx.downs = 0
      for i, e in ipairs(SM and SM.ENTRIES or {}) do if e.label == "TROPHIES" then ctx.downs = i - (SM.cursor or 1) end end
      for i, e in ipairs(SM and SM.ENTRIES or {}) do ctx.log("entry %d %s", i, tostring(e.label)) end ctx.log("cursor %s", tostring(SM and SM.cursor)) ctx.log("downs %d", ctx.downs) return true end,
    function(game, c)
      if ctx.downs <= 0 then return true end
      ctx.dk = (ctx.dk or 0) + 1
      if ctx.dk % 12 == 1 then love.event.push("keypressed", "down", "down", false) end
      if ctx.dk % 12 == 5 then love.event.push("keyreleased", "down", "down"); ctx.downs = ctx.downs - 1 end
    end,
    wait(0.3), shot("startmenu_sel"), tap("a"), wait(1), shot("menu"),
    tap("right"), wait(0.3), shot("menu_earned"), tap("a"), wait(0.3), shot("menu_detail"),
    tap("select"), wait(0.5), shot("card"),
    function(game) ctx.log("card %s", tostring(ach().leaderboardCard and require and "ok")) return true end,
    tap("b"), wait(0.3), tap("b"), wait(0.5), shot("closed"), tap("b"), wait(0.5),
    -- a live flag change: Lorelei's errand var and a flag-based gift
    function(game)
      local d = dofile and nil
      ctx.log("flag Eevee before=%s", tostring(mod.world:getFlag("FLAG_GOT_EEVEE")))
      return true
    end,
  }
end
