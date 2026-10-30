return function(ctx)
  local mod = ctx.mod
  local function wait(s) local t0 return function(_, c) if not t0 then t0 = c.t end; if c.t - t0 >= s then t0 = nil return true end end end
  local function shot(name) return function()
    love.graphics.captureScreenshot(function(img) img:encode("png", "e2e_" .. name .. ".png") end)
    return true end end
  local KEY = { a = "z", b = "x", start = "escape" }
  local function tap(b) local t0 return function(game, c)
    if not t0 then t0 = c.t; love.event.push("keypressed", KEY[b], KEY[b], false) return false end
    if c.t - t0 > 0.12 then love.event.push("keyreleased", KEY[b], KEY[b]); t0 = nil return true end end end
  local function untilField(game) return game.phase == "field" end
  mod.events:on("mod.recomp_achievements.progress", function(ev) ctx.log("PROGRESS %s %s/%s", ev.key, ev.value, ev.goal) end)
  return {
    wait(3), tap("start"), wait(5), tap("a"), wait(4), tap("a"), wait(1), untilField, wait(6),
    function(game)
      game.save.dex.caught[16] = true; game.save.dex.caught[19] = true
      mod.world:setFlag("FLAG_TEMP_1", true)
      return true
    end,
    wait(0.6), shot("prog1"), wait(0.8), shot("prog2"),
  }
end
