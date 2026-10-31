-- ui/modern.lua
-- ==================================================================
-- The modern achievements menu: a list on the left, the selected
-- achievement's details on the right, drawn with smooth text at the
-- window's own resolution.
--
-- How it fits into the game: the screen is still an ordinary state on
-- the game's stack (it takes input and hides the world like any menu),
-- but its own draw() only blanks the game frame.  The real drawing
-- happens on the render.hud hook, which runs after the frame is scaled
-- into the window and hands us the game's rectangle in window pixels.
-- Every generation's engine calls render.hud with that rectangle, so the
-- same menu works on Gen 1, 2 and 3; only the accent colour changes.
--
-- Everything is sized from one unit, u = one Game Boy pixel at the
-- current scale, so the layout keeps its proportions in any window.
-- ==================================================================

local Modern = {}

-- ------------------------------------------------------------------
-- Look
-- ------------------------------------------------------------------
-- Palettes.  Each names its surfaces, text shades and a set of hues;
-- the game's accent is picked from the hues (Modern.GAME_HUE), so every
-- palette has a matching red, blue, yellow and so on.
local function hex(h, a)
  return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255,
           tonumber(h:sub(6, 7), 16) / 255, a or 1 }
end

Modern.THEMES = {
  -- https://github.com/morhetz/gruvbox (dark, hard contrast background)
  gruvbox_dark = {
    label = "GRUVBOX DARK",
    backdrop = hex("#1d2021"), panel = hex("#282828"), raised = hex("#3c3836"),
    track = hex("#3c3836"), border = hex("#504945"),
    text = hex("#ebdbb2"), muted = hex("#bdae93"), faint = hex("#928374"),
    earned = hex("#fabd2f"), progress = hex("#b8bb26"), onAccent = hex("#1d2021"),
    hues = { red = hex("#fb4934"), blue = hex("#83a598"), yellow = hex("#fabd2f"),
             green = hex("#b8bb26"), aqua = hex("#8ec07c"), orange = hex("#fe8019"),
             purple = hex("#d3869b"), gray = hex("#a89984") },
  },
  gruvbox_light = {
    label = "GRUVBOX LIGHT",
    backdrop = hex("#f9f5d7"), panel = hex("#f2e5bc"), raised = hex("#ebdbb2"),
    track = hex("#d5c4a1"), border = hex("#bdae93"),
    text = hex("#3c3836"), muted = hex("#665c54"), faint = hex("#928374"),
    earned = hex("#b57614"), progress = hex("#79740e"), onAccent = hex("#f9f5d7"),
    hues = { red = hex("#9d0006"), blue = hex("#076678"), yellow = hex("#b57614"),
             green = hex("#79740e"), aqua = hex("#427b58"), orange = hex("#af3a03"),
             purple = hex("#8f3f71"), gray = hex("#7c6f64") },
  },
  midnight = {
    label = "MIDNIGHT",
    backdrop = { 0.05, 0.06, 0.08, 1 }, panel = { 0.10, 0.11, 0.14, 1 }, raised = { 0.15, 0.16, 0.20, 1 },
    track = { 0.18, 0.19, 0.23, 1 }, border = { 0.30, 0.32, 0.38, 1 },
    text = { 0.94, 0.95, 0.97, 1 }, muted = { 0.64, 0.67, 0.74, 1 }, faint = { 0.42, 0.45, 0.52, 1 },
    earned = { 0.98, 0.80, 0.30, 1 }, progress = { 0.46, 0.85, 0.56, 1 }, onAccent = { 0.06, 0.07, 0.09, 1 },
    hues = { red = { 0.93, 0.34, 0.31 }, blue = { 0.36, 0.56, 0.96 }, yellow = { 0.98, 0.80, 0.26 },
             green = { 0.40, 0.78, 0.45 }, aqua = { 0.45, 0.80, 0.92 }, orange = { 0.95, 0.42, 0.24 },
             purple = { 0.72, 0.55, 0.92 }, gray = { 0.70, 0.74, 0.80 } },
  },
  -- https://www.nordtheme.com
  nord = {
    label = "NORD",
    backdrop = hex("#2e3440"), panel = hex("#3b4252"), raised = hex("#434c5e"),
    track = hex("#434c5e"), border = hex("#4c566a"),
    text = hex("#eceff4"), muted = hex("#d8dee9"), faint = hex("#8f9bb3"),
    earned = hex("#ebcb8b"), progress = hex("#a3be8c"), onAccent = hex("#2e3440"),
    hues = { red = hex("#bf616a"), blue = hex("#81a1c1"), yellow = hex("#ebcb8b"),
             green = hex("#a3be8c"), aqua = hex("#88c0d0"), orange = hex("#d08770"),
             purple = hex("#b48ead"), gray = hex("#d8dee9") },
  },
  -- the original Game Boy's four greens
  gameboy = {
    label = "GAME BOY",
    backdrop = hex("#9bbc0f"), panel = hex("#8bac0f"), raised = hex("#7c9c0e"),
    track = hex("#7c9c0e"), border = hex("#306230"),
    text = hex("#0f380f"), muted = hex("#306230"), faint = hex("#306230"),
    earned = hex("#0f380f"), progress = hex("#306230"), onAccent = hex("#9bbc0f"),
    hues = { red = hex("#0f380f"), blue = hex("#0f380f"), yellow = hex("#0f380f"),
             green = hex("#0f380f"), aqua = hex("#0f380f"), orange = hex("#0f380f"),
             purple = hex("#0f380f"), gray = hex("#306230") },
  },
}
Modern.THEME_ORDER = { "gameboy", "gruvbox_dark", "gruvbox_light", "nord", "midnight" }
Modern.DEFAULT_THEME = "gameboy"

-- Which hue each game uses as its accent.
Modern.GAME_HUE = {
  red = "red", blue = "blue", yellow = "yellow", green = "green",
  gold = "yellow", silver = "gray", crystal = "aqua",
  ruby = "red", sapphire = "blue", emerald = "green",
  firered = "orange", leafgreen = "green",
}

-- The colours in use, filled from the chosen palette (Modern.apply).
local C = {}

function Modern.apply(name)
  local theme = Modern.THEMES[name] or Modern.THEMES[Modern.DEFAULT_THEME]
  for k, v in pairs(theme) do C[k] = v end
  return theme
end
Modern.apply(Modern.DEFAULT_THEME)

function Modern.accent(game)
  return C.hues[Modern.GAME_HUE[game or ""] or "yellow"] or C.earned
end

-- Kept for callers that want a game's colour outside a palette.
Modern.ACCENTS = {}
for game, hue in pairs(Modern.GAME_HUE) do Modern.ACCENTS[game] = Modern.THEMES.midnight.hues[hue] end

-- What players pick in the leaderboard form's Game field.
Modern.SHORT_NAMES = {
  red = "Red", blue = "Blue", yellow = "Yellow", green = "Green", gold = "Gold", silver = "Silver",
  crystal = "Crystal", ruby = "Ruby", sapphire = "Sapphire", emerald = "Emerald",
  firered = "FireRed", leafgreen = "LeafGreen",
}

Modern.GAME_NAMES = {
  red = "Pokémon Red", blue = "Pokémon Blue", yellow = "Pokémon Yellow", green = "Pokémon Green",
  gold = "Pokémon Gold", silver = "Pokémon Silver", crystal = "Pokémon Crystal",
  ruby = "Pokémon Ruby", sapphire = "Pokémon Sapphire", emerald = "Pokémon Emerald",
  firered = "Pokémon FireRed", leafgreen = "Pokémon LeafGreen",
}

-- Filter names for this menu (same ids as Browser's filters).
Modern.FILTER_LABELS = {
  all = "All", earned = "Earned", missing = "Missing", progress = "In progress", missable = "Missable",
  official = "RA list", bonus = "Bonus", mods = "From mods", archived = "Archived",
  reference = "RA reference",
}

local REPEAT_DELAY, REPEAT_RATE = 0.35, 0.07

-- ------------------------------------------------------------------
-- Small drawing helpers
-- ------------------------------------------------------------------
local G -- love.graphics, bound when drawing

local function color(c, alpha)
  G.setColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

local fonts = {}
local function font(px)
  px = math.max(6, math.floor(px + 0.5))
  if not fonts[px] then fonts[px] = G.newFont(px) end
  return fonts[px]
end

local function text(f, s, x, y, c, alpha)
  G.setFont(f)
  color(c, alpha)
  G.print(s, math.floor(x + 0.5), math.floor(y + 0.5))
end

local function textRight(f, s, right, y, c)
  text(f, s, right - f:getWidth(s), y, c)
end

-- Shorten to fit `width` pixels, ending in an ellipsis.
function Modern.ellipsize(f, s, width)
  s = tostring(s or "")
  if f:getWidth(s) <= width then return s end
  local chars = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
  local lo, hi = 0, #chars
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if f:getWidth(table.concat(chars, "", 1, mid) .. "…") <= width then lo = mid else hi = mid - 1 end
  end
  return table.concat(chars, "", 1, lo) .. "…"
end

local function wrap(f, s, width)
  local _, lines = f:getWrap(tostring(s or ""), width)
  return lines or { s }
end

local function rrect(mode, x, y, w, h, r, c, alpha)
  color(c, alpha)
  G.rectangle(mode, x, y, w, h, r, r)
end

local function bar(x, y, w, h, frac, c)
  rrect("fill", x, y, w, h, h / 2, C.track)
  frac = math.max(0, math.min(1, frac or 0))
  if frac > 0 then rrect("fill", x, y, math.max(h, w * frac), h, h / 2, c) end
end

-- Status icon: gold disc with a tick when earned, a ring when locked, a
-- partly filled ring for progress, a slashed ring when archived.
local function icon(cx, cy, r, row)
  G.setLineWidth(math.max(1, r * 0.22))
  if row.reference then
    color(C.faint); G.circle("fill", cx, cy, r * 0.35)
    return
  end
  if row.unlocked and not row.archived then
    color(C.earned); G.circle("fill", cx, cy, r)
    color(C.onAccent)
    G.setLineWidth(math.max(1.5, r * 0.28))
    G.line(cx - r * 0.45, cy + r * 0.02, cx - r * 0.12, cy + r * 0.35, cx + r * 0.48, cy - r * 0.32)
    return
  end
  color(C.faint); G.circle("line", cx, cy, r)
  if row.archived then
    G.line(cx - r * 0.6, cy + r * 0.6, cx + r * 0.6, cy - r * 0.6)
  elseif row.goal and (row.progress or 0) > 0 then
    local frac = math.min(1, row.progress / row.goal)
    color(C.progress)
    G.arc("line", "open", cx, cy, r, -math.pi / 2, -math.pi / 2 + frac * math.pi * 2, 24)
  end
end

-- A button cap: rounded box with a label, or a direction triangle.
local function keycap(x, y, h, label, f)
  local w
  if label == "updown" or label == "leftright" then w = h * 1.25 else w = math.max(h, f:getWidth(label) + h * 0.6) end
  G.setLineWidth(math.max(1, h * 0.07))
  rrect("line", x, y, w, h, h * 0.25, C.faint)
  color(C.muted)
  local cx, cy, s = x + w / 2, y + h / 2, h * 0.18
  if label == "updown" then
    G.polygon("fill", cx - s, cy - s * 0.4, cx + s, cy - s * 0.4, cx, cy - s * 1.6)
    G.polygon("fill", cx - s, cy + s * 0.4, cx + s, cy + s * 0.4, cx, cy + s * 1.6)
  elseif label == "leftright" then
    G.polygon("fill", cx - s * 0.4, cy - s, cx - s * 0.4, cy + s, cx - s * 1.6, cy)
    G.polygon("fill", cx + s * 0.4, cy - s, cx + s * 0.4, cy + s, cx + s * 1.6, cy)
  else
    G.setFont(f)
    G.print(label, math.floor(cx - f:getWidth(label) / 2 + 0.5), math.floor(cy - f:getHeight() / 2 + 0.5))
  end
  return w
end

local function dateOf(at)
  local ok, s = pcall(os.date, "%b %d, %Y", at)
  return ok and s or nil
end

-- What the side panel says about where an achievement comes from.
function Modern.origin(row)
  if row.reference then return "RetroAchievements list entry (reference)" end
  if row.source == "core" and row.official then
    local by = row.author and row.author ~= "" and (" · by " .. row.author) or ""
    local miss = row.raType == "missable" and " · Missable" or ""
    return "From the RetroAchievements list" .. miss .. by
  end
  if row.source == "core" then return "Bonus achievement (not from RetroAchievements)" end
  return "Added by the " .. tostring(row.providerName or row.provider or "?") .. " mod"
end

function Modern.status(row)
  if row.reference then return row.tracked and "Tracked here" or "Not tracked yet", C.muted end
  if row.archived then return "Archived", C.muted end
  if row.unlocked then return row.how == "backfill" and "Earned · from your save" or "Earned", C.earned end
  if row.goal and (row.progress or 0) > 0 then return "In progress", C.progress end
  return "Locked", C.faint
end

-- ------------------------------------------------------------------
-- Where the menu goes: the whole window (landscape or portrait), minus
-- any notch or rounded-corner insets the OS reports.  Falls back to the
-- game's own rectangle if the engine didn't say how big the window is.
-- ------------------------------------------------------------------
function Modern.region(vp, size)
  local W, H = tonumber(vp.width), tonumber(vp.height)
  if size == "game" or not (W and H and W > 0 and H > 0) then
    return vp.gameX or 0, vp.gameY or 0, vp.gameWidth or 160, vp.gameHeight or 144
  end
  local x, y = 0, 0
  local win = love.window
  if win and win.getSafeArea then
    local ok, sx, sy, sw, sh = pcall(win.getSafeArea)
    if ok and sw and sh and sw > 0 and sh > 0 and sw <= W and sh <= H then
      x, y, W, H = sx, sy, sw, sh
    end
  end
  return x, y, W, H
end

-- Height of the touch pad's deck in portrait, following the engine's own
-- default layout (src/core/TouchControls.lua defaultLayout).
function Modern.deckHeight(ww, wh)
  local dpadW = math.min(180, math.min(ww, wh) * 0.34)
  local lrH = dpadW * 0.56 * 0.5
  return math.floor(dpadW * 0.12 + dpadW + lrH * 1.4 + wh * 0.09 + 6)
end

-- One "Game Boy pixel" of layout: the game's own scale, so text is the
-- same size as in the game, but never so big the menu can't fit.
function Modern.unit(vp, W, H)
  local gw, gh = vp.gameWidth or W, vp.gameHeight or H
  local u = math.min(gw / 160, gh / 144)
  return math.max(0.5, math.min(u, W / 150, H / 128))
end

-- ------------------------------------------------------------------
-- Unlock popups in the menu's style (ui/toast.lua decides when)
-- ------------------------------------------------------------------
-- c: { kind = "unlock" | "summary" | "more", title, points }
-- shown: 0..1 slide-in amount.  opts: { style = "modern" | "corner",
-- theme = palette name, game = running game id }
function Modern.drawToast(c, shown, vp, opts)
  G = love.graphics
  Modern.apply(opts.theme)
  local x0, y0 = vp.gameX or 0, vp.gameY or 0
  local W, H = vp.gameWidth or 160, vp.gameHeight or 144
  local u = math.min(W / 160, H / 144)
  local accent = Modern.accent(opts.game)
  local heading = c.kind == "summary" and "Welcome back" or c.kind == "more" and "More achievements"
    or "Achievement unlocked"
  local pts = (c.points or 0) > 0 and ("+" .. c.points) or ""
  local ease = 1 - (1 - shown) * (1 - shown)

  G.push("all")
  G.setScissor(x0, y0, W, H)
  if opts.style == "corner" then
    -- a small card in the top-right corner that slides in from the side
    local fTitle, fTiny = font(4.4 * u), font(3.6 * u)
    local pad, r = 2.6 * u, 3.4 * u
    local w = math.floor(W * 0.46)
    local h = pad * 2 + fTiny:getHeight() + fTitle:getHeight()
    local x = x0 + W - 3 * u - w + (1 - ease) * (w + 4 * u)
    local y = y0 + 3 * u
    rrect("fill", x, y, w, h, 2.5 * u, C.panel, 0.96)
    G.setLineWidth(math.max(1, 0.3 * u))
    rrect("line", x, y, w, h, 2.5 * u, C.border)
    icon(x + pad + r, y + h / 2, r, { unlocked = true })
    local tx = x + pad * 2 + r * 2
    local ptsW = pts ~= "" and fTiny:getWidth(pts) + 1.5 * u or 0
    text(fTiny, heading, tx, y + pad, C.faint)
    if pts ~= "" then textRight(fTiny, pts, x + w - pad, y + pad, accent) end
    text(fTitle, Modern.ellipsize(fTitle, c.title or "", x + w - pad - tx), tx, y + pad + fTiny:getHeight(), C.text)
  else
    -- a banner across the top that slides down
    local fTitle, fSmall = font(5.6 * u), font(4.2 * u)
    local pad, r = 4 * u, 5 * u
    local w = W - 8 * u
    local h = pad * 2 + fSmall:getHeight() + fTitle:getHeight() * 1.1
    local x = x0 + 4 * u
    local y = y0 + 4 * u - (1 - ease) * (h + 6 * u)
    rrect("fill", x, y, w, h, 3 * u, C.panel, 0.97)
    G.setLineWidth(math.max(1, 0.3 * u))
    rrect("line", x, y, w, h, 3 * u, C.border)
    rrect("fill", x, y + 2.5 * u, 1.2 * u, h - 5 * u, 0.6 * u, accent)
    icon(x + pad + r, y + h / 2, r, { unlocked = true })
    local tx = x + pad * 2 + r * 2
    local right = x + w - pad
    if pts ~= "" then
      local pw = fSmall:getWidth(pts) + 4 * u
      local ph = fSmall:getHeight() + 1.6 * u
      rrect("fill", right - pw, y + (h - ph) / 2, pw, ph, ph / 2, accent)
      text(fSmall, pts, right - pw + 2 * u, y + (h - ph) / 2 + 0.8 * u, C.onAccent)
      right = right - pw - 3 * u
    end
    text(fSmall, heading, tx, y + pad, C.faint)
    text(fTitle, Modern.ellipsize(fTitle, c.title or "", right - tx), tx, y + pad + fSmall:getHeight(), C.text)
  end
  G.pop()
end

-- A progress note: a small, see-through card in the top-left corner,
-- "3 / 50" with a bar, for a moment after an achievement moves along.
function Modern.drawProgress(c, shown, vp, opts)
  G = love.graphics
  Modern.apply(opts.theme)
  local x0, y0 = vp.gameX or 0, vp.gameY or 0
  local W, H = vp.gameWidth or 160, vp.gameHeight or 144
  local u = math.min(W / 160, H / 144)
  local accent = Modern.accent(opts.game)
  local ease = 1 - (1 - shown) * (1 - shown)
  local fTitle, fTiny = font(3.9 * u), font(3.3 * u)
  local pad, r = 2.2 * u, 2.8 * u
  local w = math.floor(W * 0.42)
  local barH = math.max(2, 1.1 * u)
  local h = pad * 2 + fTitle:getHeight() + barH + 1.4 * u
  local x = x0 + 3 * u - (1 - ease) * (w + 4 * u)
  local y = y0 + 3 * u + ((opts.slot or 1) - 1) * (h + 1.5 * u)
  local count = c.unit == "PCT" and (("%d%%"):format(c.value)) or ("%d / %d"):format(c.value, c.goal)
  G.push("all")
  G.setScissor(x0, y0, W, H)
  rrect("fill", x, y, w, h, 2.2 * u, C.panel, 0.72 * ease)
  local frac = c.goal > 0 and math.min(1, c.value / c.goal) or 0
  local cx, cy = x + pad + r, y + h / 2
  G.setLineWidth(math.max(1, r * 0.3))
  color(C.faint, 0.8); G.circle("line", cx, cy, r)
  color(accent)
  if frac > 0 then G.arc("line", "open", cx, cy, r, -math.pi / 2, -math.pi / 2 + frac * math.pi * 2, 24) end
  local tx = x + pad * 2 + r * 2
  local right = x + w - pad
  local cw = fTiny:getWidth(count)
  text(fTiny, count, right - cw, y + pad + (fTitle:getHeight() - fTiny:getHeight()) / 2, accent)
  text(fTitle, Modern.ellipsize(fTitle, c.title or "", right - cw - 2 * u - tx), tx, y + pad, C.text, 0.95)
  bar(tx, y + pad + fTitle:getHeight() + 0.8 * u, right - tx, barH, frac, accent)
  G.pop()
end

-- ------------------------------------------------------------------
-- Screen
-- ------------------------------------------------------------------
-- deps: { mod, engine, Browser, Share, game }
function Modern.newScreen(deps)
  local mod, engine, Browser, Share, game = deps.mod, deps.engine, deps.Browser, deps.Share, deps.game
  local self = { isMenu = true, isOpaque = true, game = game, modern = true }

  local filters = {}
  for _, f in ipairs(Browser.FILTERS) do
    if not f.optional or mod.options:get("showReference") then filters[#filters + 1] = f end
  end
  local reveal = mod.options:get("showHidden") == true
  local st = { filter = 1, index = 1, scroll = 0, rows = {}, list = {}, page = 1, modal = nil,
               held = nil, heldFor = 0, repeatAt = 0, visible = 6 }
  self.state = st

  local function rebuild()
    st.rows = Browser.model(engine, { reference = mod.options:get("showReference") })
    st.list = Browser.filtered(st.rows, filters[st.filter].id)
    st.index = math.max(1, math.min(st.index, #st.list))
  end
  rebuild()

  local function move(delta)
    if #st.list == 0 then return end
    local before = st.index
    st.index = math.max(1, math.min(#st.list, st.index + delta))
    if st.index ~= before then st.page = 1 end
  end

  local function setFilter(delta)
    st.filter = (st.filter - 1 + delta) % #filters + 1
    st.index, st.scroll, st.page = 1, 0, 1
    rebuild()
  end

  function self:update(dt)
    dt = tonumber(dt) or 1 / 60
    local input = game.input
    if not input then return end
    -- Close a frame after B/START and ignore the frame we opened on, so
    -- the press never reaches the screen underneath (the Mods manager
    -- when opened from OPEN TROPHIES).
    if st.closing then game.stack:pop() return end
    if not st.settled then st.settled = true return end
    local function pressed(b) return input:wasPressed(b) end
    if st.modal then
      if pressed("b") or pressed("a") or pressed("select") or pressed("start") then st.modal = nil
      elseif pressed("right") then st.modal = 2
      elseif pressed("left") then st.modal = 1 end
      return
    end
    if pressed("b") or pressed("start") then st.closing = true return end
    if pressed("select") then
      st.modal = Share and 1 or 2
      if st.modal == 1 then pcall(engine.dispatch, engine, "ui.card_opened", {}) end
      return
    end
    if pressed("a") and st.list[st.index] and not st.list[st.index].reference then
      st.page = st.page == 1 and 2 or 1
    end
    if pressed("left") then setFilter(-1) end
    if pressed("right") then setFilter(1) end
    if pressed("up") then move(-1); st.held, st.heldFor = "up", 0 end
    if pressed("down") then move(1); st.held, st.heldFor = "down", 0 end
    -- hold to scroll
    if st.held and input.isDown and input:isDown(st.held) then
      st.heldFor = st.heldFor + dt
      if st.heldFor >= REPEAT_DELAY then
        st.repeatAt = st.repeatAt + dt
        while st.repeatAt >= REPEAT_RATE do
          st.repeatAt = st.repeatAt - REPEAT_RATE
          move(st.held == "up" and -1 or 1)
        end
      end
    else
      st.held, st.heldFor, st.repeatAt = nil, 0, 0
    end
  end

  -- Gen 2 paints the window white behind an opaque screen unless the
  -- screen draws the whole window itself; this is that, in our backdrop.
  function self:drawsWidescreen() return true end
  function self:drawWidescreen(w, h)
    Modern.apply(mod.options:get("menuTheme"))
    love.graphics.setColor(C.backdrop)
    love.graphics.rectangle("fill", 0, 0, w or 4000, h or 4000)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- The game frame under the menu: plain dark, so nothing shows through
  -- if the window draw is late by a frame.
  function self:draw()
    Modern.apply(mod.options:get("menuTheme"))
    love.graphics.setColor(C.backdrop)
    love.graphics.rectangle("fill", 0, 0, 1000, 1000)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- ----------------------------------------------------------------
  -- Window-space drawing (called from the render.hud hook)
  -- ----------------------------------------------------------------
  function self:drawWindow(vp)
    G = love.graphics
    local size = mod.options:get("menuSize")
    local x0, y0, W, H = Modern.region(vp, size)
    local u = Modern.unit(vp, W, H)
    local portrait = size ~= "game" and H > W * 1.2
    local p = 6 * u
    Modern.apply(mod.options:get("menuTheme"))
    local accent = Modern.accent(engine.game)
    local fTitle, fBody, fSmall, fTiny = font(8 * u), font(5.4 * u), font(4.6 * u), font(4 * u)
    local hair = math.max(1, 0.35 * u)

    G.push("all")
    G.setScissor(x0, y0, W, H)
    rrect("fill", x0, y0, W, H, 0, C.backdrop)
    -- On a phone held upright the on-screen pad sits along the bottom, so
    -- the content stops above it (the backdrop still fills the screen).
    if portrait then H = H - Modern.deckHeight(vp.width or W, vp.height or H) end
    -- a thin accent line along the top edge
    rrect("fill", x0, y0, W, 1.2 * u, 0, accent)

    -- header ------------------------------------------------------
    local t = engine:totals()
    local hx, hy = x0 + p, y0 + p * 0.9
    text(fTitle, "Achievements", hx, hy, C.text)
    local gameName = Modern.GAME_NAMES[engine.game or ""] or (engine.game and engine.game:upper()) or "No save loaded"
    local nameW = fSmall:getWidth(gameName)
    local dotR = 1.6 * u
    textRight(fSmall, gameName, x0 + W - p, hy + (fTitle:getHeight() - fSmall:getHeight()) / 2, C.muted)
    color(accent); G.circle("fill", x0 + W - p - nameW - dotR * 2.4, hy + fTitle:getHeight() / 2, dotR)

    local by = hy + fTitle:getHeight() + 2.5 * u
    local stats = ("%d / %d earned  ·  %d / %d pts"):format(t.earned, t.total, t.points, t.maxPoints)
    local statsW = fTiny:getWidth(stats)
    local barW = W - 2 * p - statsW - 5 * u
    bar(hx, by + fTiny:getHeight() / 2 - 1.2 * u, barW, 2.4 * u, t.total > 0 and t.earned / t.total or 0, accent)
    textRight(fTiny, stats, x0 + W - p, by, C.muted)

    -- filter chips, scrolled so the current one is on screen
    local cy = by + fTiny:getHeight() + 3 * u
    local chipH = fSmall:getHeight() + 2.4 * u
    local chips, total = {}, 0
    for i, f in ipairs(filters) do
      local label = Modern.FILTER_LABELS[f.id] or f.label
      local w = fSmall:getWidth(label) + 6 * u
      chips[i] = { label = label, w = w, x = total }
      total = total + w + 2.5 * u
    end
    local avail = W - 2 * p
    local cur = chips[st.filter]
    local shift = 0
    if total > avail then
      shift = math.max(0, math.min(total - avail, cur.x + cur.w / 2 - avail / 2))
    end
    G.setScissor(x0 + p, y0, avail, H)
    G.setLineWidth(hair)
    for i, c in ipairs(chips) do
      local cx = hx + c.x - shift
      if i == st.filter then
        rrect("fill", cx, cy, c.w, chipH, chipH / 2, accent)
        text(fSmall, c.label, cx + 3 * u, cy + 1.2 * u, C.onAccent)
      else
        rrect("line", cx, cy, c.w, chipH, chipH / 2, C.border)
        text(fSmall, c.label, cx + 3 * u, cy + 1.2 * u, C.muted)
      end
    end
    G.setScissor(x0, y0, W, H)

    -- body --------------------------------------------------------
    local footH = fTiny:getHeight() + 4 * u
    local top = cy + chipH + 3.5 * u
    local bottom = y0 + H - footH
    -- landscape: list left, details right.  portrait: list above details.
    local listW, px, py, pw, ph
    if portrait then
      listW = W - 2 * p
      local split = top + math.floor((bottom - top) * 0.58)
      px, py, pw, ph = hx, split + 2 * u, listW, bottom - split - 2 * u
      bottom = split
    else
      listW = math.floor((W - 3 * p) * 0.54)
      px, py = hx + listW + p, top
      pw, ph = x0 + W - p - px, bottom - top
    end
    local lx = hx
    local rowH = fBody:getHeight() + fTiny:getHeight() + 3.6 * u
    st.visible = math.max(1, math.floor((bottom - top) / rowH))
    if st.index - st.scroll > st.visible then st.scroll = st.index - st.visible end
    if st.index - st.scroll < 1 then st.scroll = math.max(0, st.index - 1) end

    if #st.list == 0 then
      local msg = engine.active and "Nothing here yet" or "Load a save to see achievements"
      text(fBody, msg, lx + (listW - fBody:getWidth(msg)) / 2, top + (bottom - top) / 2 - fBody:getHeight(), C.faint)
    end
    -- rows below the last full one would be cut off by the footer, so
    -- only whole rows are drawn

    G.setScissor(lx - 1, top, listW + 2, bottom - top)
    for i = 1, st.visible do
      local n = st.scroll + i
      local row = st.list[n]
      if not row then break end
      local ry = top + (i - 1) * rowH
      if n == st.index then
        rrect("fill", lx, ry, listW, rowH - 1.2 * u, 2.5 * u, C.raised)
        rrect("fill", lx, ry + 2 * u, 1.2 * u, rowH - 5.2 * u, 0.6 * u, accent)
      end
      local r = 3.6 * u
      icon(lx + 4 * u + r, ry + (rowH - 1.2 * u) / 2, r, row)
      local tx = lx + 6 * u + 2 * r
      local shown = Browser.display(row, reveal)
      local pts = (row.points or 0) > 0 and tostring(row.points) or ""
      local ptsW = pts ~= "" and fTiny:getWidth(pts) + 2 * u or 0
      local titleColor = (row.unlocked or n == st.index) and C.text or C.muted
      text(fBody, Modern.ellipsize(fBody, shown.title, listW - (tx - lx) - ptsW - 3 * u), tx, ry + 1.2 * u, titleColor)
      if pts ~= "" then textRight(fTiny, pts, lx + listW - 3 * u, ry + 1.2 * u + (fBody:getHeight() - fTiny:getHeight()) / 2, C.faint) end
      local sy = ry + 1.2 * u + fBody:getHeight() + 0.4 * u
      local subW = listW - (tx - lx) - 3 * u
      if not row.unlocked and row.goal and (row.progress or 0) > 0 then
        local label = ("%d / %d"):format(row.progress, row.goal)
        local lw = fTiny:getWidth(label)
        bar(tx, sy + fTiny:getHeight() / 2 - 0.8 * u, subW - lw - 3 * u, 1.6 * u, row.progress / row.goal, C.progress)
        textRight(fTiny, label, tx + subW, sy, C.muted)
      else
        local sub
        if row.unlocked and row.at then sub = "Earned " .. (dateOf(row.at) or "")
        elseif row.archived then sub = "Archived · mod not loaded"
        elseif row.raType == "missable" then sub = "Missable · " .. tostring(shown.description or "")
        else sub = shown.description end
        text(fTiny, Modern.ellipsize(fTiny, sub, subW), tx, sy, C.faint)
      end
    end
    G.setScissor(x0, y0, W, H)
    -- scrollbar
    if #st.list > st.visible then
      local trackH = bottom - top
      local thumbH = math.max(6 * u, trackH * st.visible / #st.list)
      local thumbY = top + (trackH - thumbH) * (st.scroll / math.max(1, #st.list - st.visible))
      rrect("fill", lx + listW + 0.8 * u, thumbY, 1 * u, thumbH, 0.5 * u, C.faint, 0.7)
    end

    -- side panel ----------------------------------------------------
    rrect("fill", px, py, pw, ph - 1.2 * u, 3 * u, C.panel)
    local row = st.list[st.index]
    if row then
      local ip = 5 * u
      local ix, iy, iw = px + ip, py + ip, pw - 2 * ip
      local shown = Browser.display(row, reveal)
      local bigR = 6 * u
      icon(ix + bigR, iy + bigR, bigR, row)
      local label, scolor = Modern.status(row)
      local lx2 = ix + bigR * 2 + 4 * u
      text(fSmall, Modern.ellipsize(fSmall, label, ix + iw - lx2), lx2, iy + bigR - fSmall:getHeight() / 2, scolor)
      local y = iy + bigR * 2 + 4 * u
      local limit = py + ph - 1.2 * u - ip - fTiny:getHeight() - 2 * u
      local function para(f, s, c, gap)
        for _, line in ipairs(wrap(f, s, iw)) do
          if y + f:getHeight() > limit then return end
          text(f, line, ix, y, c); y = y + f:getHeight()
        end
        y = y + (gap or 2.5 * u)
      end
      if st.page == 1 then
        para(fBody, shown.title, C.text, 1 * u)
        if (row.points or 0) > 0 then para(fSmall, row.points .. (row.points == 1 and " point" or " points"), accent, 3 * u) end
        para(fSmall, shown.description, C.muted, 3.5 * u)
        if row.category == "CHALLENGE" then
          -- RA's text says "Set Mode"; spell out what that means here
          para(fTiny, "Challenge: needs OPTION > BATTLE STYLE set to SET. A shows the full rules.", accent, 3 * u)
        end
        if not row.unlocked and row.goal then
          local labelP = ("%d / %d %s"):format(row.progress or 0, row.goal, (row.unit or ""):lower())
          if y + fTiny:getHeight() * 2 < limit then
            bar(ix, y, iw, 2 * u, (row.progress or 0) / row.goal, C.progress)
            y = y + 3.5 * u
            text(fTiny, labelP, ix, y, C.muted); y = y + fTiny:getHeight() + 3 * u
          end
        end
        para(fTiny, Modern.origin(row), C.faint, 1 * u)
        if row.unlocked and row.at then para(fTiny, "Earned " .. (dateOf(row.at) or ""), C.faint, 1 * u) end
      else
        para(fBody, "How it's checked", C.text, 2.5 * u)
        local how
        if row.source ~= "core" then how = "Checked by the " .. tostring(row.providerName or row.provider) .. " mod."
        elseif row.fidelity == "interpretation" then
          how = "A close local version of the RetroAchievements goal, adapted for Gen1Recomp." .. (row.note and ("\n\n" .. row.note) or "")
        elseif row.official and row.note then
          -- the rules first (challenges): they're what the player needs
          how = row.note .. "\n\nChecked by this mod with its own logic."
        elseif row.official then
          how = "Checked by this mod from your save and gameplay, with its own logic written for Gen1Recomp."
        else how = "A bonus achievement made for this mod." .. (row.note and ("\n\n" .. row.note) or "") end
        para(fSmall, how, C.muted, 3.5 * u)
        if row.official and row.raId then
          para(fTiny, ("RetroAchievements game %s, achievement %s"):format(tostring(row.raGameId or "?"), tostring(row.raId)), C.faint, 1 * u)
        end
        para(fTiny, "Unlocked locally. Nothing is sent to RetroAchievements.", C.faint, 1 * u)
      end
      if not row.reference then
        local hintY = py + ph - 1.2 * u - ip - fTiny:getHeight()
        local capH = fTiny:getHeight() + 1.2 * u
        local w = keycap(ix, hintY - 0.6 * u, capH, "A", fTiny)
        text(fTiny, st.page == 1 and "How it's checked" or "Back to details", ix + w + 2 * u, hintY, C.faint)
      end
    end

    -- footer --------------------------------------------------------
    local fy = y0 + H - footH + 1.2 * u
    local capH = fTiny:getHeight() + 1.2 * u
    local fx = hx
    local function hint(cap, label)
      local w = keycap(fx, fy, capH, cap, fTiny)
      text(fTiny, label, fx + w + 1.6 * u, fy + 0.6 * u, C.faint)
      fx = fx + w + 1.6 * u + fTiny:getWidth(label) + 4.5 * u
    end
    hint("leftright", "Filter")
    hint("updown", "Move")
    if Share then hint("SELECT", "Leaderboard") end
    hint("B", "Back")

    if st.modal then self:drawModal(x0, y0, W, H, u, accent, fonts) end
    G.pop()
  end

  -- SELECT: the leaderboard card (page 1) and the credits (page 2).
  function self:drawModal(x0, y0, W, H, u, accent)
    local fBody, fSmall, fTiny = font(5.6 * u), font(4.6 * u), font(4 * u)
    rrect("fill", x0, y0, W, H, 0, C.backdrop, 0.78)
    local mw, mh = W * 0.84, H * 0.80
    local mx, my = x0 + (W - mw) / 2, y0 + (H - mh) / 2
    rrect("fill", mx, my, mw, mh, 4 * u, C.panel)
    rrect("fill", mx, my, mw, 1.2 * u, 0, accent)
    local ip = 6 * u
    local x, y = mx + ip, my + ip
    -- tabs
    local tabs = Share and { "Leaderboard card", "About" } or { "About" }
    local tx = x
    for i, label in ipairs(tabs) do
      local active = (Share and i or 2) == st.modal
      text(fSmall, label, tx, y, active and C.text or C.faint)
      if active then rrect("fill", tx, y + fSmall:getHeight() + 0.8 * u, fSmall:getWidth(label), 0.8 * u, 0.4 * u, accent) end
      tx = tx + fSmall:getWidth(label) + 6 * u
    end
    y = y + fSmall:getHeight() + 5 * u
    local iw = mw - 2 * ip
    if st.modal == 1 and Share then
      local ok, card = pcall(Share.card, engine)
      if not ok or not card then
        text(fBody, "Load a save first.", x, y, C.muted)
      else
        local clock = card.time and ("%d:%02d"):format(math.floor(card.time / 60), card.time % 60) or "–"
        local fields = {
          { "Game", Modern.SHORT_NAMES[card.game] or card.game }, { "Trainer", tostring(card.name) },
          { "Points", ("%d / %d"):format(card.points, card.maxPoints) },
          { "Earned", ("%d / %d"):format(card.earned, card.total) },
          { "Time", clock }, { "Save ID", card.saveId }, { "Check code", card.code },
        }
        local labelW = fSmall:getWidth("Check code") + 6 * u
        for _, f in ipairs(fields) do
          text(fSmall, f[1], x, y + (fBody:getHeight() - fSmall:getHeight()) / 2, C.faint)
          text(fBody, f[2], x + labelW, y, f[1] == "Check code" and accent or C.text)
          y = y + fBody:getHeight() + 1.4 * u
        end
        y = y + 2.5 * u
        local stop = my + mh - ip - fTiny:getHeight() * 2 - 3 * u
        for _, line in ipairs(wrap(fTiny, "Only achievements from the RetroAchievements list count. Enter these at " ..
            (deps.boardUrl or "") .. " or with /score on Discord.", iw)) do
          if y + fTiny:getHeight() > stop then break end
          text(fTiny, line, x, y, C.muted); y = y + fTiny:getHeight()
        end
      end
    else
      for _, s in ipairs({
        "Recomp Achievements is an unofficial fan project inspired by RetroAchievements.",
        "Achievement lists, titles and descriptions are by RetroAchievements and their authors. Unlocks are checked by this mod and saved in your game; nothing is sent to RetroAchievements.",
        "Not affiliated with, endorsed by or supported by RetroAchievements.",
      }) do
        for _, line in ipairs(wrap(fSmall, s, iw)) do
          if y + fSmall:getHeight() > my + mh - ip - fTiny:getHeight() * 2 - 3 * u then break end
          text(fSmall, line, x, y, C.muted); y = y + fSmall:getHeight()
        end
        y = y + 3 * u
      end
    end
    -- hints along the bottom edge
    local capH = fTiny:getHeight() + 1.2 * u
    local hy = my + mh - ip - capH
    local function capWidth(label) return math.max(capH, fTiny:getWidth(label) + capH * 0.6) end
    local closeX = mx + mw - ip - fTiny:getWidth("Close") - 1.6 * u - capWidth("B")
    local w = keycap(closeX, hy, capH, "B", fTiny)
    text(fTiny, "Close", closeX + w + 1.6 * u, hy + 0.6 * u, C.faint)
    if Share then
      local cw = keycap(mx + ip, hy, capH, "leftright", fTiny)
      text(fTiny, "Switch", mx + ip + cw + 1.6 * u, hy + 0.6 * u, C.faint)
    end
  end

  return self
end

return Modern
