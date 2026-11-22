-- tests/e2e/plans/pins_second_screen.lua
-- Pins and the second screen: continues the save, pins from the menu with
-- START, checks the tracker, then turns SECOND SCREEN on and drives it by
-- touch. The engine's second-screen bridge is swapped for one that saves
-- each pushed frame (e2e_second_N.png) and plays back queued touches.
-- Run it with tests/e2e/run_e2e.sh, which hands it to the e2e_driver mod.
-- ------------------
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
    function(game)
      local L = game.mods or (ctx.mod.game and ctx.mod.game.mods)
      L.modOptions.recomp_achievements = L.modOptions.recomp_achievements or {}
      L.modOptions.recomp_achievements.classicMenu = false
      L.modOptions.recomp_achievements.secondScreen = "on"
      -- the fake bridge
      local S = require("src.render.SecondScreen")
      ctx.frames, ctx.touches = 0, {}
      S.usable = function() return true end
      S.available = function() return true end
      S.detected = function() return true end
      S.setEnabled = function(on) ctx.log("second screen enabled=%s", tostring(on)) end
      S.pollTouch = function() return table.remove(ctx.touches, 1) end
      S.push = function(img, w, h)
        ctx.frames = ctx.frames + 1
        img:encode("png", ("e2e_second_%02d.png"):format(ctx.frames))
        ctx.log("second frame %d %dx%d", ctx.frames, w, h)
        return true
      end
      return true end,
    -- open TROPHIES (that also brings the second screen up), pin two, close
    function(game) ctx.mod.ui.push(ctx.mod.game or game, "RecompAchievements"); return true end,
    wait(0.6), tap("right"), wait(0.2), tap("right"), wait(0.2), tap("right"), wait(0.3), shot("menu_progress"),
    tap("start"), wait(0.3), shot("menu_pinned1"), tap("down"), wait(0.2), tap("down"), wait(0.2), tap("start"), wait(0.3), shot("menu_pinned2"),
    tap("left"), wait(0.2), tap("left"), wait(0.2), tap("left"), wait(0.3), shot("menu_all_pinned_top"),
    function() local a = ach() ctx.log("pinned rows: %d", #a.list({ unlocked = false })) return true end,
    tap("b"), wait(1.5), shot("tracker"),
    -- touches on the second screen: the Missing chip, its first row, then off the buttons
    wait(1.2),
    function() for _, t in ipairs({ "tap,150,116" }) do ctx.touches[#ctx.touches + 1] = t end return true end, wait(1.2),
    function() ctx.touches[#ctx.touches + 1] = "tap,200,175" return true end, wait(1.2),
    function() ctx.touches[#ctx.touches + 1] = "down,200,400"; ctx.touches[#ctx.touches + 1] = "up,200,400" return true end, wait(1.2),
    function() ctx.touches[#ctx.touches + 1] = "tap,10,580" return true end, wait(1.2),
    shot("tracker_after"),
    function() ctx.log("frames pushed: %d", ctx.frames) return true end,
  }
end
