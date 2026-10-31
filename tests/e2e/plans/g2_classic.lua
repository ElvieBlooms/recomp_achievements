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
  return {
    wait(3),
    tap("start"), wait(3), shot("t1"), tap("a"), wait(3), shot("t2"), tap("a"), wait(3), shot("t3"), tap("a"), wait(3),
    function(game)
      local L = game.mods or (mod.game and mod.game.mods)
      ctx.log("phase=%s loader=%s", tostring(game.phase), tostring(L ~= nil))
      L.modOptions.recomp_achievements = L.modOptions.recomp_achievements or {}
      L.modOptions.recomp_achievements.classicMenu = (os.getenv("CLASSIC") ~= "0")
      return true
    end,
    wait(4), shot("field"),
    function(game) ctx.log("game=%s", tostring(mod.find("recomp_achievements").exports.currentGame())); mod.ui.push(mod.game or game, "RecompAchievements"); return true end,
    wait(0.5), shot("c_list"), tap("right"), wait(0.3), shot("c_earned"),
    tap("a"), wait(0.3), shot("c_detail"), tap("right"), wait(0.3), shot("c_about"),
    tap("b"), wait(0.3), tap("select"), wait(0.4), shot("c_card"), tap("b"), wait(0.3),
    tap("b"), wait(0.5), shot("c_closed"),
    function(game) local s = (mod.game or game).stack.states; ctx.log("closed top=%s", tostring(s[#s] and s[#s].screenId)); return true end,
  }
end
