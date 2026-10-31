-- ui/native3.lua
-- ==================================================================
-- The CLASSIC MENU for Gen 3: the achievements menu drawn the way the
-- game draws its own menus (and the way Gen1Recomp draws its Gen 3 Mods
-- manager): the blue help bar with button icons, a title window, the
-- player's chosen window frame, the game's font and the ▶ cursor, on the
-- 240x160 GBA screen.
--
-- It uses the engine's Gen 3 drawing modules (src/ui/game3/*).  Those
-- aren't part of the documented mod API, so Native3.available() checks
-- for every function used first; if anything is missing (a future
-- engine), main/browser fall back to the modern menu.
--
--   list    UP/DOWN pick, LEFT/RIGHT filter, A details, SELECT card, B back
--   detail  LEFT/RIGHT page (summary / how it's checked), A or B back
--   card    LEFT/RIGHT page (leaderboard card / credits), B back
-- ==================================================================

local Native3 = {}

local VISIBLE = 7                 -- rows in the content window
local WIN_X, WIN_Y, WIN_W, WIN_H = 16, 56, 208, 96
local ROW_Y0, ROW_STEP = WIN_Y + 2, 13
local CURSOR_X, ICON_X, LABEL_X, RIGHT_X = WIN_X, WIN_X + 9, WIN_X + 20, WIN_X + WIN_W - 18
local TEXT_W = WIN_W - 16
local HELP_BG = { 0 / 255, 123 / 255, 197 / 255, 1 }

local function load()
  local need = {
    Window = "src.ui.game3.window", Chrome = "src.ui.game3.chrome",
    Font = "src.ui.game3.frlg_font", Pokedex = "src.ui.game3.pokedex_chrome",
  }
  local m = {}
  for k, path in pairs(need) do
    local ok, mod = pcall(require, path)
    if not ok or type(mod) ~= "table" then return nil end
    m[k] = mod
  end
  local fns = { m.Window.printPx, m.Window.userFrame, m.Window.template, m.Window.cursorPx,
                m.Chrome.fixedStdFrame, m.Font.measure, m.Font.wrap, m.Font.drawGlyph,
                m.Pokedex.drawControlInfo }
  for i = 1, #fns do if type(fns[i]) ~= "function" then return nil end end
  if type(m.Font.COLOR) ~= "table" or type(m.Font.STDPAL) ~= "table" then return nil end
  return m
end

local libs
function Native3.available()
  if libs == nil then libs = load() or false end
  return libs ~= false
end

-- The game font reads {TOKENS}; achievement text must never be taken for one.
function Native3.clean(s)
  return (tostring(s or ""):gsub("{", "("):gsub("}", ")"):gsub("[\r\n]+", " "))
end

-- Cut a string to a pixel width, with "…" when it had to be cut.
local function fit(G, s, w, opts)
  s = Native3.clean(s)
  if G.Font.measure(s, opts) <= w then return s end
  local chars = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
  local n = #chars
  while n > 0 do
    local t = table.concat(chars, "", 1, n) .. "…"
    if G.Font.measure(t, opts) <= w then return t end
    n = n - 1
  end
  return ""
end
Native3.fit = fit

function Native3.newScreen(o)
  local G = libs or load()
  local mod, engine, Browser, Share, game = o.mod, o.engine, o.Browser, o.Share, o.game
  local C = G.Font.COLOR
  -- pokefirered stdpal_0 greens/grays, as plain RGB for the status icons
  local PAL = {
    [2] = { 98 / 255, 98 / 255, 98 / 255 }, [3] = { 213 / 255, 213 / 255, 205 / 255 },
    [6] = { 32 / 255, 156 / 255, 8 / 255 }, [7] = { 148 / 255, 246 / 255, 148 / 255 },
    [8] = { 49 / 255, 82 / 255, 205 / 255 },
  }
  local self = { isMenu = true, isOpaque = true, gbaCanvas = true, game = game, native3 = true }

  local filters = Browser.filtersFor(mod, engine)
  local filterIndex, index, scroll = 1, 1, 0
  local rows, list = {}, {}
  local detail, page = nil, 1
  local card = false               -- false, 1 (leaderboard card), 2 (extra credit), 3 (credits)
  local reveal = mod.options:get("showHidden") == true
  local closing, settled = false, false
  local blink = 0

  local function rebuild()
    rows = Browser.model(engine, { reference = mod.options:get("showReference") })
    list = Browser.filtered(rows, filters[filterIndex].id)
    if index > #list then index = math.max(1, #list) end
    if index - scroll > VISIBLE then scroll = index - VISIBLE end
    if index - scroll < 1 then scroll = math.max(0, index - 1) end
  end
  rebuild()
  self.rebuild = rebuild

  -- ---------------------------------------------------------- input
  function self:update(dt)
    blink = blink + 1
    local input = game.input
    if not input then return end
    -- never act on the press that opened us, and close a frame after B,
    -- so neither press reaches the screen underneath
    if closing then game.stack:pop() return end
    if not settled then settled = true return end
    local function pressed(b) return input:wasPressed(b) end
    if card then
      if pressed("b") or pressed("a") or pressed("select") then card = false
      elseif pressed("right") and Share then card = math.min(3, card + 1)
      elseif pressed("left") and Share then card = math.max(1, card - 1) end
      return
    end
    if pressed("select") then
      card = Share and 1 or 3
      if card == 1 then pcall(engine.dispatch, engine, "ui.card_opened", {}) end
      return
    end
    if detail then
      if pressed("b") or pressed("a") then detail, page = nil, 1
      elseif pressed("right") and not detail.reference then page = 2
      elseif pressed("left") then page = 1 end
      return
    end
    if pressed("b") or pressed("start") then closing = true return end
    if pressed("up") and index > 1 then index = index - 1 end
    if pressed("down") and index < #list then index = index + 1 end
    if pressed("left") then
      filterIndex = (filterIndex - 2) % #filters + 1
      index, scroll = 1, 0
      rebuild()
    elseif pressed("right") then
      filterIndex = filterIndex % #filters + 1
      index, scroll = 1, 0
      rebuild()
    end
    if pressed("a") and list[index] then detail, page = list[index], 1 end
    if index - scroll > VISIBLE then scroll = index - VISIBLE end
    if index - scroll < 1 then scroll = math.max(0, index - 1) end
  end

  -- ---------------------------------------------------------- drawing
  local function print(s, x, y, colors, opts)
    G.Window.printPx(s, x, y, { colors = colors or C.NORMAL, small = opts and opts.small,
                                maxWidth = opts and opts.maxWidth })
  end
  local function printRight(s, rx, y, colors, opts)
    s = Native3.clean(s)
    print(s, rx - G.Font.measure(s, opts), y, colors, opts)
  end

  local function frameType()
    local ok, Options = pcall(require, "src.core.game3.options")
    local engineOpts = (game and game.options) or (game and game.save and game.save.options) or {}
    if ok and type(Options) == "table" and type(Options.block) == "function" then
      local okB, cart = pcall(Options.block, engineOpts)
      return okB and cart and tonumber(cart.frameType) or 0
    end
    return 0
  end

  local function chrome(help, title, right)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(HELP_BG)
    love.graphics.rectangle("fill", 0, 0, 240, 16)
    love.graphics.setColor(1, 1, 1, 1)
    G.Pokedex.drawControlInfo(help, 0xE4, 0)
    G.Chrome.fixedStdFrame(2, 3, 26, 2)
    local rw = right and (G.Font.measure(Native3.clean(right)) + 8) or 0
    print(fit(G, title, 192 - rw), 24, 25)
    if right then printRight(right, 216, 25, C.DARK_GRAY) end
    G.Window.userFrame(G.Window.template(2, 7, 26, 12), frameType())
  end

  -- earned: filled green; in progress: half; locked: hollow; archived: gray
  local function icon(kind, x, y, part)
    local g = love.graphics
    local function px(c) g.setColor(c[1], c[2], c[3], 1) end
    local dark = kind == "earned" and PAL[6] or PAL[2]
    px(dark)
    g.rectangle("fill", x + 1, y, 5, 1); g.rectangle("fill", x + 1, y + 6, 5, 1)
    g.rectangle("fill", x, y + 1, 1, 5); g.rectangle("fill", x + 6, y + 1, 1, 5)
    if kind == "earned" then
      px(PAL[7]); g.rectangle("fill", x + 1, y + 1, 5, 5)
      px(PAL[6]); g.rectangle("fill", x + 2, y + 3, 1, 1); g.rectangle("fill", x + 3, y + 4, 1, 1)
      g.rectangle("fill", x + 4, y + 2, 1, 2)
    elseif kind == "progress" then
      px(PAL[7]); g.rectangle("fill", x + 1, y + 1 + (5 - part), 5, part)
    elseif kind == "archived" or kind == "reference" then
      px(PAL[3]); g.rectangle("fill", x + 1, y + 1, 5, 5)
    end
    g.setColor(1, 1, 1, 1)
  end

  local function arrows(first, last, total)
    local k = blink
    local bob = (math.floor(k / 16) % 2)
    if first > 1 then G.Font.drawGlyph(G.Font.CHAR_UP_ARROW or 0x79, 212, WIN_Y + bob, { colors = C.RED }) end
    if last < total then G.Font.drawGlyph(G.Font.CHAR_DOWN_ARROW or 0x7A, 212, WIN_Y + WIN_H - 14 - bob, { colors = C.RED }) end
  end

  local function drawList()
    local t = engine:totals()
    local f = filters[filterIndex]
    local label = f.label
    chrome("{DPAD_UPDOWN}PICK {DPAD_LEFTRIGHT}FILTER {A_BUTTON}INFO {B_BUTTON}BACK",
           "TROPHIES: " .. label, ("%d/%d  %dP"):format(t.earned, t.total, t.points))
    if #list == 0 then
      print("NOTHING HERE YET.", LABEL_X, ROW_Y0, C.DARK_GRAY)
      if not engine.active then print("LOAD A SAVE FIRST.", LABEL_X, ROW_Y0 + ROW_STEP, C.DARK_GRAY) end
      return
    end
    local first, last = scroll + 1, math.min(#list, scroll + VISIBLE)
    for i = first, last do
      local row = list[i]
      local y = ROW_Y0 + (i - first) * ROW_STEP
      local shown = Browser.display(row, reveal)
      local kind, part = "locked", 0
      if row.reference then kind = "reference"
      elseif row.archived then kind = "archived"
      elseif row.unlocked then kind = "earned"
      elseif row.goal and (row.progress or 0) > 0 then
        kind, part = "progress", math.max(1, math.min(4, math.floor((row.progress / row.goal) * 5)))
      end
      icon(kind, ICON_X, y + 3, part)
      local right
      if kind == "progress" then right = ("%d/%d"):format(row.progress, row.goal)
      elseif not row.reference then right = tostring(row.points or 0) end
      local rw = right and (G.Font.measure(right) + 6) or 0
      local col = (row.unlocked or row.reference) and C.NORMAL or C.DARK_GRAY
      print(fit(G, shown.title, RIGHT_X - LABEL_X - rw), LABEL_X, y, col)
      if right then printRight(right, RIGHT_X, y, kind == "progress" and C.BLUE or C.DARK_GRAY) end
      if i == index then G.Window.cursorPx(CURSOR_X, y) end
    end
    arrows(first, last, #list)
  end

  local function statusOf(row)
    if row.reference then return row.tracked and "TRACKED HERE" or "NOT TRACKED YET", C.DARK_GRAY end
    if row.archived then return "EARNED (MOD NOT LOADED)", C.DARK_GRAY end
    if row.unlocked then
      local when = ""
      if row.at then
        local ok, d = pcall(os.date, "%Y-%m-%d", row.at)
        if ok then when = " " .. d end
      end
      return (row.how == "backfill" and "EARNED FROM SAVE" or "EARNED") .. when, C.GREEN
    end
    if row.goal then
      return ("%d/%d %s"):format(row.progress or 0, row.goal, row.unit or ""), C.BLUE
    end
    return "NOT YET EARNED", C.RED
  end

  local function originOf(row)
    local by = row.author and row.author ~= "" and (" · BY " .. row.author) or ""
    if row.reference then return "RA LIST ENTRY" .. by end
    if row.source == "core" and row.official then
      return (row.raType == "missable" and "RA LIST · MISSABLE" or "RA LIST") .. by
    end
    if row.source == "core" then return "BONUS (NOT RA)" end
    return "MOD: " .. tostring(row.providerName or row.provider or "?")
  end

  -- wrapped lines in the content window; returns the next y
  local function para(text, y, maxY, colors, opts)
    local wrapped = G.Font.wrap(Native3.clean(text), TEXT_W, opts)
    local lines = {}
    if type(wrapped) == "table" then lines = wrapped
    else for l in (tostring(wrapped) .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end end
    local pitch = (opts and opts.small) and 12 or 14
    for _, line in ipairs(lines) do
      if y + pitch > maxY then break end
      print(line, LABEL_X - 4, y, colors, opts)
      y = y + pitch
    end
    return y
  end

  local function drawDetail(row)
    local shown = Browser.display(row, reveal)
    local pts = row.reference and "" or ("%dP"):format(row.points or 0)
    if page == 2 then
      chrome("{DPAD_LEFTRIGHT}PAGE {B_BUTTON}BACK", "HOW IT'S CHECKED", nil)
      local y = ROW_Y0
      local how
      if row.source ~= "core" then
        how = "Added by the " .. tostring(row.providerName or row.provider) .. " mod."
      elseif row.fidelity == "interpretation" then
        how = "A close local version of the goal." .. (row.note and (" " .. row.note) or "")
      elseif row.official then
        how = "Checked by this mod from your save and play." .. (row.note and (" " .. row.note) or "")
      else
        how = "A bonus achievement made for this mod." .. (row.note and (" " .. row.note) or "")
      end
      y = para(how, y, WIN_Y + WIN_H - 26, C.NORMAL, { small = true })
      if row.official and row.raId then
        print(("RA GAME %s · ACHIEVEMENT %s"):format(tostring(row.raGameId or "?"), tostring(row.raId)),
              LABEL_X - 4, WIN_Y + WIN_H - 26, C.DARK_GRAY, { small = true })
      end
      print("UNLOCKED LOCALLY. NOT SENT TO RA.", LABEL_X - 4, WIN_Y + WIN_H - 14, C.DARK_GRAY, { small = true })
      return
    end
    chrome("{DPAD_LEFTRIGHT}PAGE {B_BUTTON}BACK", shown.title, pts)
    local footer = WIN_Y + WIN_H - 28
    para(shown.description, ROW_Y0, footer, C.NORMAL)
    local status, scol = statusOf(row)
    print(fit(G, status, TEXT_W), LABEL_X - 4, footer, scol)
    print(fit(G, originOf(row), TEXT_W, { small = true }), LABEL_X - 4, footer + 14, C.DARK_GRAY, { small = true })
  end

  -- Text with "_" in it: the font has none, so print spaces and draw the
  -- underscores as lines (URLs and mod ids must be typed exactly).
  local function printU(text, x, y, colors, rgb, small)
    small = small == nil and true or small
    local opts = { small = small }
    print((text:gsub("_", " ")), x, y, colors, opts)
    local at = 1
    while true do
      local i = text:find("_", at, true)
      if not i then break end
      local x0 = x + G.Font.measure((text:sub(1, i - 1):gsub("_", " ")), opts)
      local w = G.Font.measure(" ", opts)
      love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1)
      love.graphics.rectangle("fill", x0, y + 15, math.max(3, w), 1)
      love.graphics.setColor(1, 1, 1, 1)
      at = i + 1
    end
  end

  local function drawExtra()
    chrome("{DPAD_LEFTRIGHT}PAGE {B_BUTTON}BACK", "EXTRA CREDIT", nil)
    local ok, c = pcall(Share.extraCard, engine)
    if not ok or not c then
      print("LOAD A SAVE FIRST.", LABEL_X, ROW_Y0, C.DARK_GRAY)
      return
    end
    local small = { small = true }
    local y = ROW_Y0
    print("TRAINER", LABEL_X - 4, y, C.DARK_GRAY, small); print(c.name, LABEL_X + 52, y, C.NORMAL, small)
    y = y + 11
    print("SAVE ID", LABEL_X - 4, y, C.DARK_GRAY, small); print(c.saveId, LABEL_X + 52, y, C.NORMAL, small)
    y = y + 13
    local maxRows = 4
    if #c.sources == 0 then print("NOTHING HERE YET.", LABEL_X - 4, y, C.DARK_GRAY, small); y = y + 11 end
    for i, src in ipairs(c.sources) do
      if i > maxRows then print(("…%d MORE"):format(#c.sources - maxRows), LABEL_X - 4, y, C.DARK_GRAY, small); y = y + 11 break end
      local line = Share.extraLine(src)
      printU(line, LABEL_X - 4, y, C.NORMAL, PAL[2])
      y = y + 11
    end
    print("CODE", LABEL_X - 4, WIN_Y + WIN_H - 12, C.DARK_GRAY, small)
    print(c.code, LABEL_X + 52, WIN_Y + WIN_H - 12, C.BLUE, small)
  end

  local function drawCard()
    if card == 2 then return drawExtra() end
    if card == 3 then
      chrome("{DPAD_LEFTRIGHT}PAGE {B_BUTTON}BACK", "ABOUT", nil)
      local y = ROW_Y0
      for i = 2, #Browser.ABOUT do
        y = para(Browser.ABOUT[i], y, WIN_Y + WIN_H - 2, C.NORMAL, { small = true }) + 2
      end
      return
    end
    chrome("{DPAD_LEFTRIGHT}PAGE {B_BUTTON}BACK", "LEADERBOARD CARD", nil)
    local ok, c = pcall(Share.card, engine)
    if not ok or not c then
      print("LOAD A SAVE FIRST.", LABEL_X, ROW_Y0, C.DARK_GRAY)
      return
    end
    local lines = {
      { "GAME", tostring(c.game):upper() },
      { "TRAINER", tostring(c.name) },
      { "POINTS", ("%d/%d"):format(c.points, c.maxPoints) },
      { "EARNED", ("%d/%d"):format(c.earned, c.total) },
    }
    if c.time then lines[#lines + 1] = { "TIME", ("%d:%02d"):format(math.floor(c.time / 60), c.time % 60) } end
    lines[#lines + 1] = { "SAVE ID", c.saveId }
    lines[#lines + 1] = { "CHECK", c.code }
    local step = #lines > 6 and 11 or 13
    for i, l in ipairs(lines) do
      local y = ROW_Y0 + (i - 1) * step
      print(l[1], LABEL_X - 4, y, C.DARK_GRAY, { small = true })
      print(l[2], LABEL_X + 52, y, C.NORMAL, { small = true })
    end
    -- the font has no "_": printU draws it as a line (the URL needs it)
    printU(Browser.BOARD_URL, LABEL_X - 4, WIN_Y + WIN_H - 12, C.BLUE, PAL[8])
  end

  function self:draw()
    love.graphics.push("all")
    if card then drawCard()
    elseif detail then drawDetail(detail)
    else drawList() end
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
  end

  return self
end

return Native3
