-- main.lua
-- Recomp Achievements Online. An add-on for recomp_achievements that sends
-- the leaderboard card to the board when you save, so you don't have to
-- copy it out by hand. Everything else (the achievements, the menu, the
-- API other mods use) stays in recomp_achievements, which is why this is a
-- separate mod: leaving it out keeps the main mod fully offline.
--
-- What it sends, to discord/worker.js on Cloudflare: the card's game,
-- trainer name, points, achievements earned, play time, save ID and check
-- code, the Extra Credit lines if that's on, and a random key kept in this
-- save. The key is how the worker knows the save, and what /link ties to
-- a Discord account. Nothing is sent to RetroAchievements.
-- ------------------

-- The Cloudflare Worker that runs the Discord bot.
local SERVER = "https://recomp-achievements-bot.recomp-achievements-bot.workers.dev"

return function(mod)
  local source = assert(mod:read("client.lua"), "recomp_achievements_online: missing client.lua")
  local Client = assert(load(source, "@" .. mod.id .. "/client.lua"))()

  local found = mod.find("recomp_achievements")
  local ach = found and found.exports
  if not (ach and ach.supports and ach.supports("card_notes")) then
    mod.log:warn("needs recomp_achievements 2.7.0 or newer; nothing will be sent")
    return
  end

  mod.options:define({
    { key = "onlineScores", type = "toggle", label = "ONLINE SCORES", default = true },
    { key = "sendExtra", type = "toggle", label = "SEND EXTRA CREDIT", default = true },
    -- Asks for a /link code on the next save and shows it on the card.
    -- Off by default, since the code hands the save to whoever uses it.
    { key = "showLinkCode", type = "toggle", label = "SHOW LINK CODE", default = false },
  })

  -- Status for the card note. Only what this session saw; the save keeps
  -- the key, the last cards sent and whether it's linked. The link code is
  -- never saved: it lasts an hour.
  local state = {}
  local queue, current, lastAt = {}, nil, nil

  local function now()
    local timer = love and love.timer
    return timer and timer.getTime and timer.getTime() or os.clock()
  end

  local function reset()
    if current then pcall(mod.fetch.cancel, mod.fetch, current.handle) end
    queue, current = {}, nil
    state = { linked = mod.save:get("linked", false) == true }
  end

  ach.addCardNote(mod, function()
    state.off = mod.options:get("onlineScores") == false
    state.showCode = mod.options:get("showLinkCode") == true
    return Client.note(state)
  end)

  local function startNext()
    local job = table.remove(queue, 1)
    if not job then state.sending = false; return end
    local handle, why = mod.fetch:get(job.url, { accept = "text/plain", maxSeconds = 20 })
    if not handle then
      state.sending, state.error = false, tostring(why or "couldn't send")
      queue = {}
      return
    end
    job.handle = handle
    current = job
  end

  local function finish(job, result)
    current = nil
    local reply = result.status == "ok" and Client.reply(result.body)
      or { ok = false, message = result.err or "no connection" }
    if not reply.ok then
      state.error = reply.message
      queue = {}
      state.sending = false
      return
    end
    -- remembered in the save, so an unchanged card isn't sent again
    mod.save:set(job.saveKey, job.code)
    state.sent, state.error = true, nil
    state.linked = reply.linked
    mod.save:set("linked", reply.linked)
    if job.link then state.code = reply.code end
    startNext()
  end

  local function send()
    if mod.options:get("onlineScores") == false then return end
    if current or #queue > 0 then return end
    if lastAt and now() - lastAt < Client.MIN_GAP then return end
    if not mod.fetch:available() then state.error = "no network"; return end
    local key = mod.save:get("key")
    if not Client.validKey(key) then
      local rand = love and love.math and love.math.random
      if not rand then
        -- plain math.random starts from the same seed for everyone
        math.randomseed(os.time() + math.floor(now() * 1000))
        rand = math.random
      end
      key = Client.newKey(rand)
      mod.save:set("key", key)
    end
    local card = ach.leaderboardCard()
    -- SHOW LINK CODE sends the card even if it hasn't changed, to get a code
    local link = mod.options:get("showLinkCode") == true and not state.code
    if Client.wants(card, not link and mod.save:get("lastScore") or nil) then
      queue[#queue + 1] = { url = Client.scoreUrl(SERVER, key, card, link), saveKey = "lastScore",
                            code = card.code, link = link }
    end
    if mod.options:get("sendExtra") ~= false then
      local extra = ach.extraCard()
      if Client.wants(extra, mod.save:get("lastExtra")) then
        queue[#queue + 1] = { url = Client.extraUrl(SERVER, key, extra), saveKey = "lastExtra", code = extra.code }
      end
    end
    if #queue == 0 then return end
    lastAt = now()
    state.sending, state.error = true, nil
    startNext()
  end

  mod.events:on("save.loaded", reset)
  mod.events:on("save.created", reset)
  -- Just before the file is written, so a new key goes into this save. The
  -- reply comes later, so the codes it confirms ride on the next save.
  mod.events:on("save.writing", function() pcall(send) end)

  mod.hooks:wrap("core.update", function(nextFn, game, dt, ...)
    local result = nextFn(game, dt, ...)
    if current then
      local r = mod.fetch:poll(current.handle) or { status = "error", err = "lost the request" }
      if r.status ~= "pending" then
        pcall(mod.fetch.release, mod.fetch, current.handle)
        finish(current, r)
      end
    end
    return result
  end)

  reset()
end
