-- ui/toast.lua
-- ==================================================================
-- Unlock popups.  A small queue: one popup at a time, each slides in from
-- the top, holds, and slides out.  Drawn on the render.hud hook, which
-- runs after the frame is composed, so popups sit over gameplay without
-- being a stack state (they never steal input or pause the game).
--
-- A popup is never the proof of an unlock.  The engine writes the
-- ledger first and only then calls push(); turning popups off changes
-- nothing about what is saved.
-- ==================================================================

local Toast = {}
Toast.__index = Toast

Toast.HOLD = 2.6      -- seconds fully shown
Toast.SLIDE = 0.18    -- seconds to slide in/out
Toast.MAX_QUEUE = 12  -- extra unlocks collapse into one "+N more" popup

local function now()
  local timer = love and love.timer
  if timer and timer.getTime then return timer.getTime() end
  return os.clock()
end

function Toast.new(mod, util, Text)
  return setmetatable({ mod = mod, util = util, Text = Text, queue = {},
                        current = nil, overflow = 0 }, Toast)
end

function Toast:enabled()
  return self.mod.options:get("toasts") ~= false
end

-- def: the registry definition; shown: what to display for it on this
-- game (Registry:display -- the official RA text when linked).
function Toast:push(def, shown)
  if not self:enabled() then return end
  if #self.queue >= Toast.MAX_QUEUE then
    self.overflow = self.overflow + 1
    return
  end
  shown = shown or def
  local points = shown.points or def.points or 0
  self.queue[#self.queue + 1] = {
    heading = "ACHIEVEMENT!",
    line = shown.title or def.title,
    right = points > 0 and (tostring(points) .. "P") or "",
  }
end

function Toast:pushSummary(n)
  if not self:enabled() then return end
  self.queue[#self.queue + 1] = {
    heading = "WELCOME BACK!",
    line = ("%d PAST MILESTONES"):format(n),
    right = "", from = "",
  }
end

function Toast:clear()
  self.queue, self.current, self.overflow = {}, nil, 0
end

-- Advance the queue; returns the popup to draw and its slide offset 0..1.
function Toast:tick()
  local t = now()
  if not self.current then
    if #self.queue == 0 and self.overflow > 0 then
      self.queue[1] = { heading = "ACHIEVEMENTS!", line = ("+%d MORE"):format(self.overflow),
                        right = "", from = "" }
      self.overflow = 0
    end
    local nextOne = table.remove(self.queue, 1)
    if not nextOne then return nil end
    nextOne.started = t
    self.current = nextOne
  end
  local c = self.current
  local age = t - c.started
  local total = Toast.SLIDE * 2 + Toast.HOLD
  if age >= total then
    self.current = nil
    return self:tick()
  end
  local shown
  if age < Toast.SLIDE then shown = age / Toast.SLIDE
  elseif age > total - Toast.SLIDE then shown = (total - age) / Toast.SLIDE
  else shown = 1 end
  return c, shown
end

-- Draw in Game Boy pixel space (160 x 144), scaled onto the window.
function Toast:draw(vp)
  local c, shown = self:tick()
  if not c or not vp or not vp.gameWidth or vp.gameWidth <= 0 then return end
  local Font = self.mod.ui.Font
  local Text = self.Text
  local g = love.graphics
  g.push("all")
  g.translate(vp.gameX or 0, vp.gameY or 0)
  g.scale(vp.gameWidth / 160, vp.gameHeight / 144)
  -- Border, heading, one or two title lines, border.  Slides down from
  -- above the screen.  Long official titles wrap to a second line.
  local lines = Text.wrap(c.line, 18)
  if #lines > 2 then lines = { lines[1], Text.fit(lines[2], 17) .. "…" } end
  local height = 2 + 1 + math.max(1, #lines)
  local offset = math.floor((1 - shown) * -(height * 8))
  g.translate(0, offset)
  Font.drawBox(0, 0, 20, height)
  Text.draw(Font, c.heading, 1, 1)
  if c.right ~= "" then Text.drawRight(Font, c.right, 19, 1) end
  for i, line in ipairs(lines) do Text.draw(Font, line, 1, 1 + i) end
  g.pop()
end

function Toast:install()
  self.mod.hooks:wrap("render.hud", function(nextFn, game, vp, ...)
    local result = nextFn(game, vp, ...)
    local ok, err = pcall(self.draw, self, vp)
    if not ok and not self.warned then
      self.warned = true
      self.mod.log:warn("popup draw failed: %s", tostring(err))
    end
    return result
  end)
end

return Toast
