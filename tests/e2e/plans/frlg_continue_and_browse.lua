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
    wait(3), tap("start"), wait(5), tap("a"), wait(4), tap("a"), wait(1), untilField, shot("w0"), wait(0.5), shot("w1"), wait(0.5), shot("w2"), wait(0.5), shot("w3"), wait(1), shot("welcome"),
    report("loaded"),
    wait(4), shot("after_toasts"),
    -- open START, find our row
    tap("start"), wait(1), shot("startmenu"),
    tap("down"), wait(0.2), tap("down"), wait(0.2), tap("down"), wait(0.2), tap("down"), wait(0.2), tap("down"), wait(0.2),
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
