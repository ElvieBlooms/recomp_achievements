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
    for _, r in ipairs(a.list({ unlocked = true })) do ctx.log("  unlocked %s", r.key) end
    for _, r in ipairs(a.list({ unlocked = false })) do if (r.progress or 0) > 0 then ctx.log("  progress %s %s/%s", r.key, tostring(r.progress), tostring(r.goal)) end end
    return true end end
  mod.events:on("mod.recomp_achievements.unlocked", function(ev) ctx.log("UNLOCK %s", tostring(ev and ev.key)) end)
  mod.events:on("battle.started", function(ev) ctx.log("battle.started trainerId=%s kind=%s", tostring(ev.trainerId), tostring(ev.kind)) end)
  mod.events:on("battle.ended", function(ev) ctx.log("battle.ended result=%s", tostring(ev.result)) end)
  ctx.liam = 142
  local LIAM
  return {
    wait(3), tap("start"), wait(5), tap("a"), wait(4), tap("a"), wait(1), untilField, wait(2), shot("lg_welcome"),
    report("loaded"),
    function(game) ctx.log("mod.game==game %s", tostring(mod.game == game)) ctx.log("save.version=%s name=%s gen=%s", tostring(game.save and game.save.version), tostring(game.save and game.save.name), tostring(game.save and game.save.generation)) return true end,
    function() ctx.log("setFlag potion -> %s", tostring(mod.world:setFlag("FLAG_GOT_POTION_ON_ROUTE_1", true))) return true end,
    wait(1.5), shot("lg_potion"),
    function(game) ctx.log("after setFlag: save.flags[560]=%s session.flags[560]=%s getFlag=%s same=%s", tostring(game.save.flags[560]), tostring(game.session and game.session.flags[560]), tostring(mod.world:getFlag("FLAG_GOT_POTION_ON_ROUTE_1")), tostring(game.session == game.save)) return true end,
    function(game)
      local Trainers = require("src.core.game3.scripting.trainers")
      local BB = require("src.core.game3.battle_bridge")
      LIAM = 414 + 0
      local d = dofile and nil
      -- TRAINER_CAMPER_LIAM from our data table
      local data = mod.find("recomp_achievements") and nil
      local foe = Trainers.foeFromId(ctx.liam)
      ctx.log("foe for %s: %s", tostring(ctx.liam), tostring(foe and foe.trainerId))
      local ok, err = BB.start(nil, game, foe, { trainerId = ctx.liam })
      ctx.log("trainer battle start %s %s", tostring(ok), tostring(err))
      return true
    end,
    wait(5), shot("lg_battle"),
    function(game)
      local BB = require("src.core.game3.battle_bridge")
      BB.finishPending("win")
      return true
    end,
    wait(4), shot("lg_after_battle"),
    report("after"),
  }
end
