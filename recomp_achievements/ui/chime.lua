-- ui/chime.lua
-- ==================================================================
-- The unlock sound: a short square-wave jingle in the Game Boy's style,
-- generated in code when it's first needed.  Nothing is copied from the
-- games or from RetroAchievements, and there's no audio file to ship.
--
-- Mods have no engine SFX call, so this plays through love.audio, which
-- the sandbox allows.  It follows the game's SFX VOL option.
--
-- Two jingles:
--   unlock   a quick rising arpeggio and a held top note
--   summary  the same idea, lower and slower (WELCOME BACK)
-- ==================================================================

local Chime = {}
Chime.__index = Chime

Chime.RATE = 22050
Chime.VOLUME = 0.45     -- under the game's own SFX at full SFX VOL
Chime.MIN_GAP = 0.25    -- seconds; a burst of unlocks plays once

-- Note frequencies (Hz).
local E5, GS5, B5, E6, GS6, B6 = 659.26, 830.61, 987.77, 1318.51, 1661.22, 1975.53

-- { freq, start (s), length (s), duty (0..1), level (0..1) }
Chime.SONGS = {
  unlock = {
    { B5, 0.00, 0.07, 0.25, 0.8 },
    { E6, 0.07, 0.07, 0.25, 0.8 },
    { GS6, 0.14, 0.07, 0.25, 0.8 },
    { B6, 0.21, 0.42, 0.25, 0.9 },
    { E5, 0.21, 0.42, 0.50, 0.45 },  -- second channel under the last note
  },
  summary = {
    { E5, 0.00, 0.09, 0.25, 0.8 },
    { GS5, 0.09, 0.09, 0.25, 0.8 },
    { B5, 0.18, 0.09, 0.25, 0.8 },
    { E6, 0.27, 0.50, 0.25, 0.9 },
    { B5, 0.27, 0.50, 0.50, 0.4 },
  },
}

local function now()
  local timer = love and love.timer
  if timer and timer.getTime then return timer.getTime() end
  return os.clock()
end

-- Sample values (-1..1) for a song; pure Lua so tests can check it.
function Chime.render(song, rate)
  rate = rate or Chime.RATE
  local length = 0
  for _, n in ipairs(song) do length = math.max(length, n[2] + n[3]) end
  local count = math.floor(length * rate) + 1
  local out = {}
  for i = 1, count do out[i] = 0 end
  for _, n in ipairs(song) do
    local freq, start, dur, duty, level = n[1], n[2], n[3], n[4], n[5]
    local first = math.floor(start * rate) + 1
    local samples = math.floor(dur * rate)
    local attack = math.floor(0.004 * rate)
    for k = 0, samples - 1 do
      local i = first + k
      if i > count then break end
      local phase = (k * freq / rate) % 1
      local wave = phase < duty and 1 or -1
      -- short attack, then a linear fade: no clicks, and a bell-like tail
      local env = k < attack and k / attack or 1 - (k - attack) / (samples - attack)
      out[i] = out[i] + wave * level * env * 0.5
    end
  end
  for i = 1, count do out[i] = math.max(-1, math.min(1, out[i])) end
  return out
end

function Chime.new(mod)
  return setmetatable({ mod = mod, sources = {}, last = -math.huge }, Chime)
end

function Chime:enabled()
  return self.mod.options:get("unlockSound") ~= false
end

-- 0..1 from the game's SFX VOL (0-7); full if the option isn't there.
function Chime:gameVolume()
  local game = self.mod.game
  local options = game and game.save and game.save.options
  local level = options and tonumber(options.sfxVol)
  if not level then return 1 end
  return math.max(0, math.min(7, level)) / 7
end

function Chime:source(kind)
  if self.sources[kind] ~= nil then return self.sources[kind] or nil end
  local ok, src = pcall(function()
    local samples = Chime.render(Chime.SONGS[kind])
    local data = love.sound.newSoundData(#samples, Chime.RATE, 16, 1)
    for i, v in ipairs(samples) do data:setSample(i - 1, v) end
    return love.audio.newSource(data, "static")
  end)
  self.sources[kind] = ok and src or false -- no audio device: stay quiet
  return ok and src or nil
end

-- kind: "unlock" or "summary".  Returns true if a sound started.
function Chime:play(kind)
  if not self:enabled() then return false end
  if not (love and love.audio and love.sound) then return false end
  local t = now()
  if t - self.last < Chime.MIN_GAP then return false end
  local volume = Chime.VOLUME * self:gameVolume()
  if volume <= 0 then return false end
  local src = self:source(Chime.SONGS[kind] and kind or "unlock")
  if not src then return false end
  self.last = t
  pcall(function()
    src:stop()
    src:setVolume(volume)
    src:play()
  end)
  return true
end

return Chime
