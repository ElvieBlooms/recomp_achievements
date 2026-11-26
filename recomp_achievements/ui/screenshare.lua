-- Screen Share: one second screen, several mods.
--
-- The engine's secondScreen bridge has one screen and no owner: every mod
-- that pushes a frame gets it shown, and whichever polls first gets the
-- touches.  So mods that carry this file agree among themselves:
--
--   * each one exports secondScreen = { api = 1, name, shown(), claimedAt(),
--     available(), open() };
--   * of the mods that are shown, the one opened most recently is in front.
--     Only that one pushes frames, reads touches and turns the display on;
--   * the rest wait behind it, keeping their place, and the next one comes
--     back the moment the front one closes;
--   * the display goes off only when the last one closes.
--
-- Field Notes and Recomp Achievements both carry this file; it's the same
-- file in each, so keep them in step (Screen Share api 1).  Mods that push
-- to the bridge their own way and only export secondScreenShown() (Galar
-- Rising's raid pad) are listed in `legacy`: while one says true, everyone
-- here stays off the screen and leaves its power alone.  Kanto Gear apps
-- pass managed = true, so the power is left to Gear.
-- ------------------

local M = { API = 1 }

-- mods known to carry this file, checked even before the mod list is read
M.KNOWN = { "field_notes", "recomp_achievements" }
-- how often to look again for mods that carry it
M.RESCAN = 2

local function now()
  return love and love.timer and love.timer.getTime() or os.clock()
end

-- o = { mod, id, name, shown = fn, available = fn, open = fn, legacy = { ids } }
--   shown():     true while this mod wants the second screen
--   available(): true when open() would put it there (for the other mods'
--                buttons); defaults to shown()
--   open():      bring it to the second screen; claim() is called after it
function M.new(o)
  local self = setmetatable({
    mod = o.mod, id = o.id, name = o.name, shownFn = o.shown,
    legacy = o.legacy or {}, at = 0, front = false, scanned = -math.huge, peersById = {},
  }, { __index = M })
  self.exports = {
    api = M.API, name = o.name,
    shown = function() return self:shown() end,
    claimedAt = function() return self.at end,
    available = function()
      if o.available then
        local ok, yes = pcall(o.available)
        return ok and yes == true
      end
      return self:shown()
    end,
    open = function()
      if o.open then pcall(o.open) end
      self:claim()
    end,
  }
  return self
end

function M:shown()
  local ok, yes = pcall(self.shownFn)
  return ok and yes == true
end

-- The player opened this mod: it goes in front of the others.
function M:claim()
  self.at = now()
end

-- Other mods carrying this file, found through their exports.
function M:peers()
  local t = now()
  if t - self.scanned >= M.RESCAN then
    self.scanned = t
    local ids, seen = {}, {}
    for _, id in ipairs(M.KNOWN) do ids[#ids + 1] = id; seen[id] = true end
    local ok, loaded = pcall(function() return self.mod.game.mods.loaded end)
    for _, m in ipairs(ok and type(loaded) == "table" and loaded or {}) do
      local id = type(m) == "table" and type(m.manifest) == "table" and m.manifest.id
      if type(id) == "string" and not seen[id] then ids[#ids + 1] = id; seen[id] = true end
    end
    self.peerIds = ids
  end
  local out = {}
  local find = self.mod.find
  if type(find) ~= "function" then return out end
  for _, id in ipairs(self.peerIds or {}) do
    if id ~= self.id then
      local okF, other = pcall(find, id)
      local s = okF and type(other) == "table" and type(other.exports) == "table" and other.exports.secondScreen
      if type(s) == "table" and s.api == M.API and type(s.shown) == "function" then
        out[#out + 1] = { id = id, share = s }
      end
    end
  end
  return out
end

local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return nil
end

-- true while a mod that pushes its own way (secondScreenShown) holds it
function M:legacyHolds()
  local find = self.mod.find
  if type(find) ~= "function" then return false end
  for _, id in ipairs(self.legacy) do
    local okF, other = pcall(find, id)
    local ex = okF and type(other) == "table" and type(other.exports) == "table" and other.exports
    -- a mod that carries this file takes turns through it instead
    local sharing = ex and type(ex.secondScreen) == "table" and ex.secondScreen.api == M.API
    if ex and not sharing and ask(ex.secondScreenShown) == true then return true end
  end
  return false
end

-- Is another shown mod in front of this one?  The later claim wins; on a
-- tie (both started shown, neither opened since) the lower id does.
function M:behind()
  for _, p in ipairs(self:peers()) do
    if ask(p.share.shown) == true then
      local at = tonumber(ask(p.share.claimedAt)) or 0
      if at > self.at or (at == self.at and p.id < self.id) then return true end
    end
  end
  return false
end

function M:anyPeerShown()
  for _, p in ipairs(self:peers()) do
    if ask(p.share.shown) == true then return true end
  end
  return false
end

-- The other mods the player could switch to from this one's screen:
-- { { name, open = fn }, ... }
function M:others()
  local out = {}
  for _, p in ipairs(self:peers()) do
    if ask(p.share.available) == true then
      out[#out + 1] = { id = p.id, name = tostring(p.share.name or p.id), open = p.share.open }
    end
  end
  return out
end

-- Every frame, from render.compose.  screen is ctx.secondScreen; managed is
-- true when Kanto Gear looks after the display's power.  Returns two
-- things: whether this mod has the screen now (push frames, poll touches),
-- and whether it has only just got it back (repaint now).
function M:frame(screen, managed)
  local want = self:shown()
  if (want or self.owesOff) and self:legacyHolds() then
    -- not a frame, a touch or a power change until they're done. If this
    -- mod had the screen, it still owes the display a power-off should it
    -- close meanwhile: done once they let go.
    self.held = true
    if self.front then self.front, self.away, self.owesOff = false, true, true end
    return false, false
  end
  self.held = false
  if want then self.owesOff = false end
  local front = want and not self:behind()
  local power = type(screen) == "table" and not managed and screen.setEnabled or nil
  local regained = false
  if front and not self.front then
    regained = true
    if power then pcall(power, true) end
  elseif not front and (self.front or self.owesOff) and not want and power and not self:anyPeerShown() then
    -- closed, and nobody else is waiting for the screen
    pcall(power, false)
  end
  if not want then self.owesOff = false end
  self.front = front
  if not front then return false, false end
  -- NaviPlay's gate hands us a stand-in bridge that reports the screen gone
  -- while NaviPlay is on it; frames still go out (some bridges only see the
  -- screen after the first one), and we repaint the moment it's back
  local seen = ask(screen and screen.detected)
  if seen == false then self.away = true
  elseif self.away then self.away, regained = false, true end
  return true, regained
end

return M
