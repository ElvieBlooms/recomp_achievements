return function(ctx)
  local mod = ctx.mod
  local function wait(s) local t0 return function(_, c) if not t0 then t0 = c.t end; if c.t - t0 >= s then t0 = nil return true end end end
  local function shot(name) return function()
    love.graphics.captureScreenshot(function(img) img:encode("png", "e2e_" .. name .. ".png") end)
    return true end end
  mod.events:on("mod.recomp_achievements.progress", function(ev) ctx.log("PROGRESS %s %s/%s", ev.key, ev.value, ev.goal); ctx.sawProgress = true end)
  return {
    wait(3),
    function(game)
      local SaveData = require("src.core.SaveData")
      local loaded, rec = SaveData.load()
      game:restoreSave(loaded, rec, { freshBoot = true, continued = true })
      return true
    end,
    wait(8),
    function(game)
      ctx.sawProgress = false
      local n = 0
      for _, sp in ipairs({ "PIDGEY", "RATTATA", "SPEAROW", "EKANS", "SANDSHREW", "NIDORAN_F", "ZUBAT", "ODDISH" }) do
        if not game.save.pokedex.owned[sp] then game.save.pokedex.owned[sp] = true; n = n + 1 end
        if n >= 2 then break end
      end
      game.save.money = (game.save.money or 0) + 1

      return true
    end,
    function() return ctx.sawProgress end, wait(0.4), shot("c1"), wait(0.4), shot("c2"), wait(0.6), shot("c3"),
  }
end
