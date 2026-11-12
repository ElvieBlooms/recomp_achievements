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
  if not (ach and ach.supports and ach.supports("card_note_press")) then
    mod.log:warn("needs recomp_achievements 2.7.1 or newer; nothing will be sent")
    return
  end

  mod.options:define({
    { key = "onlineScores", type = "toggle", label = "ONLINE SCORES", default = true },
    { key = "sendExtra", type = "toggle", label = "SEND EXTRA CREDIT", default = true },
    -- A on the card gets a /link code and shows it until A again. The code
    -- stays hidden until asked for, since it hands the save to whoever uses
    -- it and people share screenshots of the card.
    { key = "linkButton", type = "toggle", label = "LINK CODE ON A", default = true },
  })

  -- Status for the card note. Only what this session saw; the save keeps
  -- the key, the last cards sent and whether it's linked. The link code is
  -- never saved: it lasts an hour, so it's asked for again after 50 minutes.
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

  local CODE_LIFE = 50 * 60
  local send, sendCode

  local function codeFresh()
    return state.code and state.codeAt and now() - state.codeAt < CODE_LIFE
  end

  ach.addCardNote(mod, function()
    state.off = mod.options:get("onlineScores") == false
    state.button = mod.options:get("linkButton") ~= false
    return Client.note(state)
  end, {
    onPress = function()
      if mod.options:get("onlineScores") == false or mod.options:get("linkButton") == false then
        return false
      end
      if state.error or not state.reveal then
        state.reveal, state.error = true, nil
        if not codeFresh() then state.code = nil; pcall(sendCode) end
      else
        state.reveal = false
      end
      return true
    end,
  })

  local function startNext()
    local job = table.remove(queue, 1)
    if not job and state.wantCode then
      state.wantCode = false
      pcall(sendCode)
      return
    end
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
      queue, state.wantCode = {}, false
      state.sending = false
      return
    end
    -- remembered in the save, so an unchanged card isn't sent again
    mod.save:set(job.saveKey, job.code)
    state.sent, state.error = true, nil
    state.linked = reply.linked
    mod.save:set("linked", reply.linked)
    if job.link then
      state.code, state.codeAt = reply.code, now()
      state.noCodes = reply.code == nil
    end
    startNext()
  end

  local function getKey()
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
      -- only kept once the game saves; the card says so next to a code
      state.keyUnsaved = true
    end
    return key
  end

  -- A on the card: send the card now, asking for a code, whatever changed.
  function sendCode()
    if current or #queue > 0 then state.wantCode = true; return end
    if not mod.fetch:available() then state.error = "no network"; return end
    local card = ach.leaderboardCard()
    if not Client.wants(card, nil) then state.error = "earn one first"; return end
    local key = getKey()
    queue[1] = { url = Client.scoreUrl(SERVER, key, card, true), saveKey = "lastScore",
                 code = card.code, link = true }
    state.sending, state.error = true, nil
    startNext()
  end

  function send()
    if mod.options:get("onlineScores") == false then return end
    if current or #queue > 0 then return end
    if lastAt and now() - lastAt < Client.MIN_GAP then return end
    if not mod.fetch:available() then state.error = "no network"; return end
    local key = getKey()
    local card = ach.leaderboardCard()
    if Client.wants(card, mod.save:get("lastScore")) then
      queue[#queue + 1] = { url = Client.scoreUrl(SERVER, key, card), saveKey = "lastScore", code = card.code }
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
  mod.events:on("save.writing", function()
    state.keyUnsaved = nil
    pcall(send)
  end)

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
