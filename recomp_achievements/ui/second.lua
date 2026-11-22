-- ui/second.lua
-- The achievements menu on a second display: the AYN Thor's bottom screen,
-- or the desktop companion window. Drawn by Modern.drawSecond into a canvas
-- and handed to the engine's secondScreen bridge from render.compose, which
-- also gives us that screen's touches.
--
-- It only takes the screen while it's open, since other mods use it too:
--   * with Kanto Gear installed it's the TROPHIES app in Gear, opened from there, and
--     CLOSE hands the screen back to Gear;
--   * otherwise SECOND SCREEN: ON shows it, CLOSE hides it, and opening
--     TROPHIES on the main screen brings it back.
-- The bridge has no way to share, so two mods showing at once take turns
-- frame by frame. Gear is what keeps them apart.
-- ------------------

local Second = {}

Second.W, Second.H = 540, 620
-- refresh at least this often while shown, for unlocks and progress
Second.REFRESH = 1

-- the chips along the top; "pinned" is ours, the rest are Browser filters
Second.CHIPS = {
  { id = "all", label = "All" },
  { id = "missing", label = "Missing" },
  { id = "progress", label = "In progress" },
  { id = "missable", label = "Missable" },
  { id = "pinned", label = "Pinned" },
}

-- "action,x,y" from pollTouch (older bridges send "x,y" for a tap)
function Second.parseTouch(event)
  local action, x, y = tostring(event):match("^(%a+),(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
  if not action then
    x, y = tostring(event):match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
    action = x and "tap" or nil
  end
  if not action then return nil end
  return action, tonumber(x), tonumber(y)
end

function Second.hitAt(hits, x, y)
  for i = #hits, 1, -1 do
    local h = hits[i]
    if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then return h end
  end
  return nil
end

function Second.new(o)
  local self = {
    mod = o.mod, engine = o.engine, Browser = o.Browser, Modern = o.Modern,
    chip = 1, scroll = 0, detail = nil, hits = {}, dirty = true, nextPush = 0,
    open = false, gearOpen = false, viaGear = false, wasUp = false,
    flash = nil, flashUntil = 0, touch = nil,
  }
  return setmetatable(self, { __index = Second })
end

-- ------------------ state
function Second:now()
  return love and love.timer and love.timer.getTime() or os.clock()
end

function Second:up()
  if self.viaGear then return self.gearOpen end
  return self.mod.options:get("secondScreen") == "on" and self.open
end

function Second:rows()
  local engine = self.engine
  local id = Second.CHIPS[self.chip].id
  local ok, rows = pcall(self.Browser.model, engine, {})
  if not ok then return {} end
  if id == "pinned" then
    local out = {}
    for _, row in ipairs(rows) do
      if row.pinned and not row.unlocked then out[#out + 1] = row end
    end
    return out
  end
  return self.Browser.filtered(rows, id)
end

function Second:say(msg)
  self.flash, self.flashUntil, self.dirty = msg, self:now() + 1.5, true
end

function Second:maxScroll(n)
  local L = self.Modern.SECOND
  local visible = Second.H - L.header - L.chips - L.footer
  return math.max(0, n * L.row - visible)
end

-- ------------------ touches
function Second:tap(x, y)
  local hit = Second.hitAt(self.hits, x, y)
  if not hit then return end
  self.dirty = true
  if hit.action == "filter" then
    self.chip, self.scroll, self.detail = hit.arg, 0, nil
  elseif hit.action == "open" then
    local row = self.list and self.list[hit.arg]
    if row then self.detail = row.key end
  elseif hit.action == "back" then
    self.detail = nil
  elseif hit.action == "pin" and self.detail then
    local msg = self.Browser.togglePin(self.engine, { key = self.detail })
    if msg then self:say(msg:sub(1, 1) .. msg:sub(2):lower()) end
  elseif hit.action == "pinned" then
    self.chip = self.chip == #Second.CHIPS and 1 or #Second.CHIPS
    self.scroll = 0
  elseif hit.action == "close" then
    self:close()
  end
end

function Second:onTouch(action, x, y)
  if action == "down" then
    self.touch = { y = y, lastY = y, moved = false }
  elseif action == "move" and self.touch then
    if math.abs(y - self.touch.y) > 12 then self.touch.moved = true end
    if self.touch.moved and not self.detail then
      self.scroll = math.max(0, math.min(self:maxScroll(#(self.list or {})), self.scroll - (y - self.touch.lastY)))
      self.dirty = true
    end
    self.touch.lastY = y
  elseif action == "up" or action == "tap" then
    local t = self.touch
    self.touch = nil
    if not (t and t.moved) then self:tap(x, y) end
  elseif action == "cancel" then
    self.touch = nil
  end
end

-- ------------------ open and close
function Second:show()
  self.open, self.dirty = true, true
  if self.hook and (self.viaGear or self.mod.options:get("secondScreen") == "on") then self:hook() end
end

function Second:close()
  self.open, self.gearOpen, self.detail = false, false, nil
  self.dirty = true
end

-- ------------------ drawing
function Second:frame(screen)
  local engine = self.engine
  local mod = self.mod
  local list = self:rows()
  self.list = list
  self.scroll = math.min(self.scroll, self:maxScroll(#list))
  local detailRow
  if self.detail then
    detailRow = engine:status(self.detail)
    if detailRow then
      local p = engine.registry.providers[detailRow.provider or ""]
      detailRow.providerName = p and p.name or detailRow.provider
    else
      self.detail = nil
    end
  end
  local chips = {}
  for i, c in ipairs(Second.CHIPS) do chips[i] = { label = c.label, active = i == self.chip } end
  local ok, t = pcall(engine.totals, engine)
  local pins = engine.active and #engine.ledger:pins() or 0
  self.canvas = self.canvas or love.graphics.newCanvas(Second.W, Second.H, { dpiscale = 1 })
  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  local okD, hits = pcall(self.Modern.drawSecond, {
    W = Second.W, H = Second.H, theme = mod.options:get("menuTheme"), game = engine.game,
    gameTitle = engine.game and self.titles and self.titles[engine.game] or nil,
    totals = engine.active and ok and t or nil, chips = chips, list = list, scroll = self.scroll,
    detail = detailRow, pins = pins, pinMax = engine.ledger.PIN_MAX,
    pinnedOnly = self.chip == #Second.CHIPS,
    flash = self.flash and self:now() < self.flashUntil and self.flash or nil,
    Browser = self.Browser, reveal = mod.options:get("showHidden") == true,
  })
  love.graphics.setCanvas()
  love.graphics.pop()
  if not okD then
    if not self.warned then
      self.warned = true
      mod.log:warn("second screen draw failed: %s", tostring(hits))
    end
    return
  end
  self.hits = hits
  local okI, image = pcall(self.canvas.newImageData, self.canvas)
  if okI and image then
    local C = self.Modern.backdropHex and self.Modern.backdropHex() or 0
    pcall(screen.push, image, Second.W, Second.H, C, "secondary")
  end
end

-- render.compose, every frame
function Second:compose(ctx)
  local screen = type(ctx) == "table" and ctx.secondScreen
  local up = self:up()
  if up ~= self.wasUp then
    self.wasUp, self.dirty = up, true
    if screen and screen.setEnabled and not self.viaGear then
      -- turn the display on for us, and off again when we close, unless
      -- Gear is managing it
      pcall(screen.setEnabled, up)
    end
  end
  if not (up and screen and screen.push and screen.usable and screen.usable()) then return end
  for _ = 1, 64 do
    local event = screen.pollTouch and screen.pollTouch()
    if not event then break end
    local action, x, y = Second.parseTouch(event)
    if action then self:onTouch(action, x, y) end
  end
  local now = self:now()
  local flashing = self.flash ~= nil and now < self.flashUntil
  if flashing ~= (self.flashShown or false) then self.flashShown, self.dirty = flashing, true end
  if not self.dirty and now < self.nextPush then return end
  self:frame(screen)
  self.dirty, self.nextPush = false, now + Second.REFRESH
end

-- ------------------ install
-- o: { mod, engine, Browser, Modern, titles = { [game] = "Pokémon Red", ... } }
function Second.install(o)
  local self = Second.new(o)
  self.titles = o.titles
  local mod = self.mod
  -- Kanto Gear: an app in its Silph Store instead of the option
  local gear = mod.find and mod.find("kanto_gear")
  local modules = gear and gear.exports and gear.exports.modules
  if type(modules) == "table" and modules.api == 1 and type(modules.register) == "function" then
    local rows = {}
    for r = 1, 24 do
      local row = {}
      for c = 1, 24 do
        -- a trophy: cup, handles, stem and base
        local ch = "."
        if r >= 4 and r <= 12 and c >= 7 and c <= 18 then ch = "g" end
        if r >= 13 and r <= 14 and c >= 9 and c <= 16 then ch = "g" end
        if (c == 4 or c == 5 or c == 20 or c == 21) and r >= 5 and r <= 9 then ch = "d" end
        if r >= 15 and r <= 18 and c >= 11 and c <= 14 then ch = "d" end
        if r >= 19 and r <= 21 and c >= 7 and c <= 18 then ch = "d" end
        if r >= 6 and r <= 8 and c >= 10 and c <= 12 then ch = "p" end
        row[c] = ch
      end
      rows[r] = table.concat(row)
    end
    local ok, registered = pcall(modules.register, {
      -- TROPHIES, as on the START menu: Gear has its own ACHIEVEMENTS app
      -- (its stamps), and two of the same name in the store would be a guess.
      -- Capitals to sit with Gear's own apps.
      id = "recomp_achievements", label = "TROPHIES", category = "ADVENTURE", accent = "amber",
      description = { "RECOMP ACHIEVEMENTS BY TOUCH.", "RETROACHIEVEMENTS LISTS, PINS", "AND PROGRESS. NOT GEAR STAMPS." },
      icon = { pal = { g = "e0b040", d = "7a5a10", p = "fff3c0" }, rows = rows },
      open = function() self.gearOpen, self.dirty = true, true; return true end,
      shown = function() return self.gearOpen end,
      available = function() return true end,
    })
    self.viaGear = ok and registered == true
  end
  if not self.viaGear then
    -- with the option on it starts shown
    self.open = true
  end
  -- render.compose only once it can matter: a subscriber sends Gen 3 down
  -- the engine's slower hooked present path (game3/display.lua), so players
  -- without Gear who never turn SECOND SCREEN on don't pay for it.
  function self:hook()
    if self.hooked then return end
    self.hooked = true
    mod.hooks:wrap("render.compose", function(nextFn, renderer, ctx)
      local handled = nextFn(renderer, ctx)
      local ok, err = pcall(self.compose, self, ctx)
      if not ok and not self.warnedCompose then
        self.warnedCompose = true
        mod.log:warn("second screen failed: %s", tostring(err))
      end
      return handled
    end)
  end
  if self.viaGear or mod.options:get("secondScreen") == "on" then self:hook() end
  -- unlocks and progress redraw it on the next frame
  for _, name in ipairs({ "mod.recomp_achievements.unlocked", "mod.recomp_achievements.progress",
                          "save.loaded", "save.created" }) do
    pcall(mod.events.on, mod.events, name, function() self.dirty = true end)
  end
  return self
end

return Second
