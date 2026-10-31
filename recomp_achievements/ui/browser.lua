-- ui/browser.lua
-- ==================================================================
-- The ACHIEVEMENTS screen, opened from the START menu.
--
-- Layout on the 20 x 18 tile Game Boy screen:
--
--   +------------------+   rows 0-3   header: count, points, filter
--   | 12/27   PTS 85   |
--   | < ALL >          |
--   +------------------+
--   | # Rock Bottom    |   rows 4-17  list, 12 visible rows
--   | o Making Waves 1/|
--   | ...              |
--   +------------------+
--
-- Controls: UP/DOWN move, LEFT/RIGHT change filter, A opens details,
-- B (or START) goes back.  Earned = filled square, locked = hollow
-- square, archived = slashed square, so nothing depends on colour.
--
-- The screen reads plain rows from engine:rows() each time it opens or a
-- filter changes.  It holds no references into the ledger, so an unlock
-- arriving while it is open can't corrupt anything; it just shows up the
-- next time the list is rebuilt.
-- ==================================================================

local Browser = {}

Browser.SCREEN_ID = "RecompAchievements"
-- The START menu row.  Gen 2's menu has room for 7 characters before the
-- frame (POKéGEAR is 6 tiles), so it gets the singular there.
Browser.MENU_LABEL = "TROPHIES"
Browser.SHORT_LABEL = "TROPHY"
-- Where the START row goes.  insertBefore falls back to appending if the
-- anchor label isn't there (another mod renamed it, a different gen).
Browser.MENU_ANCHOR = "OPTION"

-- The SELECT page.  Kept short: it has to fit 16 rows of 18 characters.
Browser.ABOUT = {
  "ACHIEVEMENTS",
  "Lists and text from RetroAchievements and their authors.",
  "Checked by this mod and saved in your game. Nothing is sent to RA.",
  "Not affiliated with RetroAchievements.",
}

-- Where players submit the leaderboard card.  Change this if the repo
-- lives somewhere else.  The font has no "_"; drawCard draws them as
-- lines so the URL can still be typed exactly.
Browser.BOARD_URL = "elvieblooms.github.io/recomp_achievements"

-- Lines of the leaderboard card page (pure, so tests can check it).
function Browser.cardLines(card, url)
  if not card then return { "LEADERBOARD", "", "Load a save first." } end
  local lines = {
    "LEADERBOARD CARD",
    "",
    "GAME    " .. card.game:upper(),
    "TRAINER " .. tostring(card.name),
    ("POINTS  %d/%d"):format(card.points, card.maxPoints),
    ("EARNED  %d/%d"):format(card.earned, card.total),
  }
  if card.time then
    -- play time when this score was reached, H:MM like the trainer card
    lines[#lines + 1] = ("TIME    %d:%02d"):format(math.floor(card.time / 60), card.time % 60)
  end
  for _, line in ipairs({ "SAVE ID " .. card.saveId, "CHECK   " .. card.code, "",
                          "RA-list points", "only. Enter at:" }) do
    lines[#lines + 1] = line
  end
  url = url or Browser.BOARD_URL
  for i = 1, #url, 18 do lines[#lines + 1] = url:sub(i, i + 17) end
  return lines
end

-- Lines of the Extra Credit page (pure, so tests can check it).
function Browser.extraLines(card)
  if not card then return { "EXTRA CREDIT", "", "Load a save first." } end
  local lines = { "EXTRA CREDIT", "", "TRAINER " .. tostring(card.name), "SAVE ID " .. card.saveId, "" }
  if #card.sources == 0 then lines[#lines + 1] = "Nothing here yet." end
  local room = 15 - 3 - #lines
  for i, src in ipairs(card.sources) do
    if i > room then lines[#lines + 1] = ("...%d more"):format(#card.sources - i + 1) break end
    lines[#lines + 1] = ("%s %d/%d %d"):format(src.id, src.earned, src.total, src.points)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "CODE    " .. card.code
  lines[#lines + 1] = "Enter with /extra"
  return lines
end

-- Slide a long title left and back so the selected row can be read in
-- full: hold one second, scroll at 4 chars/s, hold, return.
function Browser.marquee(Text, title, width, t)
  local chars = Text.chars(Text.safe(title))
  local extra = #chars - width
  if extra <= 0 then return title end
  local hold, speed = 1, 4
  local cycle = hold * 2 + extra / speed
  local p = (t % cycle)
  local offset
  if p < hold then offset = 0
  elseif p < hold + extra / speed then offset = math.floor((p - hold) * speed)
  else offset = extra end
  return table.concat(chars, "", offset + 1, math.min(#chars, offset + width))
end

local VISIBLE = 12     -- list rows on screen
local LIST_TOP = 5     -- first list row (tile y)

local FILTERS = {
  { id = "all",      label = "ALL" },
  { id = "earned",   label = "EARNED" },
  { id = "missing",  label = "MISSING" },
  { id = "progress", label = "IN PROGRESS" },
  { id = "missable", label = "MISSABLE" },
  { id = "official", label = "RA LIST" },
  { id = "bonus",    label = "BONUS" },
  { id = "mods",     label = "FROM MODS" },
  { id = "archived", label = "ARCHIVED" },
  { id = "reference", label = "RA REFERENCE", optional = true },
}

Browser.FILTERS = FILTERS

-- The filter tabs for this game: the fixed ones, plus one per mod that
-- has achievements here ("mod:<provider id>"), labelled with the mod's
-- chosen tab label or its name.  One mod: its tab takes FROM MODS' place.
-- Two or more: FROM MODS (all of them), then each mod's own.
function Browser.filtersFor(mod, engine)
  local providers, seen = {}, {}
  local registry = engine and engine.registry
  local ok, rows = pcall(function() return engine:rows() end)
  for _, row in ipairs(ok and rows or {}) do
    local id = row.provider
    if row.source ~= "core" and not row.archived and id and not seen[id] then
      seen[id] = true
      local p = registry and registry.providers[id] or {}
      providers[#providers + 1] = { id = "mod:" .. id, provider = id,
                                    label = p.tab or p.name or id, providerTab = true }
    end
  end
  table.sort(providers, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)
  local out = {}
  for _, f in ipairs(FILTERS) do
    if f.id == "mods" and #providers > 0 then
      if #providers > 1 then out[#out + 1] = f end
      for _, p in ipairs(providers) do out[#out + 1] = p end
    elseif not f.optional or mod.options:get("showReference") then
      out[#out + 1] = f
    end
  end
  return out
end

local function passes(filter, row)
  if filter == "reference" then return row.reference == true end
  if row.reference then return false end
  if filter == "all" then return true end
  if filter == "earned" then return row.unlocked end
  if filter == "missing" then return not row.unlocked and not row.archived end
  if filter == "progress" then
    return not row.unlocked and row.goal ~= nil and (row.progress or 0) > 0
  end
  -- RetroAchievements' own "missable" tag: can be lost for good in a playthrough.
  if filter == "missable" then return row.raType == "missable" and not row.archived end
  if filter == "official" then return row.source == "core" and row.official == true end
  if filter == "bonus" then return row.source == "core" and not row.official end
  if filter == "mods" then return row.source ~= "core" and not row.archived end
  if filter:sub(1, 4) == "mod:" then
    return row.source ~= "core" and not row.archived and row.provider == filter:sub(5)
  end
  if filter == "archived" then return row.archived end
  return true
end

-- ------------------------------------------------------------------
-- View model: turn engine rows (+ reference catalog) into display rows.
-- Kept separate from drawing so tests can check it without a screen.
-- ------------------------------------------------------------------
function Browser.model(engine, opts)
  opts = opts or {}
  local rows = engine:rows()
  local registry = engine.registry
  local game = engine.game
  for _, row in ipairs(rows) do
    local p = row.provider and registry.providers[row.provider]
    row.providerName = p and p.name or row.provider
  end
  if opts.reference and game and registry.catalogs[game] then
    local linked = registry:linkedSet(game)
    for _, e in ipairs(registry.catalogs[game].entries) do
      rows[#rows + 1] = {
        key = "ref:" .. e.id, reference = true, title = e.title,
        description = e.description, points = e.points, author = e.author,
        tracked = linked[e.id] ~= nil, unlocked = false, raId = e.id, raType = e.type,
      }
    end
  end
  return rows
end

function Browser.filtered(rows, filter)
  local out = {}
  for _, row in ipairs(rows) do
    if passes(filter, row) then out[#out + 1] = row end
  end
  return out
end

-- What a row is allowed to show.  Hidden + locked = no spoilers.
function Browser.display(row, reveal)
  local secret = row.hidden and not row.unlocked and not reveal
  return {
    title = secret and "???" or row.title,
    description = secret and "A hidden achievement. Keep playing!" or row.description,
  }
end

-- ------------------------------------------------------------------
-- The screen object.  Gen 1's state stack calls update(dt) and draw();
-- popping ourselves (game.stack:pop()) closes the screen.
-- ------------------------------------------------------------------
function Browser.newScreen(mod, engine, util, Text, game, Share)
  local Font = mod.ui.Font
  local Theme = mod.ui.Theme
  -- isOpaque: the state stack stops drawing the world under us
  -- (src/core/StateStack.lua), like the Pokedex and Diploma screens.
  local self = { isMenu = true, isOpaque = true, game = game }

  local filters = Browser.filtersFor(mod, engine)
  local filterIndex, index, scroll = 1, 1, 0
  local rows, list = {}, {}
  local detail = nil -- the row being inspected, or nil for the list
  local page = 1     -- detail page: 1 = summary, 2 = about this rule
  local about = false -- SELECT pages: 1 = leaderboard card, 2 = extra credit, 3 = credits
  local clock = 0     -- drives the selected row's title scroll
  local reveal = mod.options:get("showHidden") == true
  local closing, settled = false, false -- see Modern's update

  local function rebuild()
    rows = Browser.model(engine, { reference = mod.options:get("showReference") })
    list = Browser.filtered(rows, filters[filterIndex].id)
    if index > #list then index = math.max(1, #list) end
    if index - scroll > VISIBLE then scroll = index - VISIBLE end
    if index - scroll < 1 then scroll = math.max(0, index - 1) end
  end
  rebuild()

  function self:update(dt)
    clock = clock + (tonumber(dt) or 1 / 60)
    local input = game.input
    if not input then return end
    if closing then game.stack:pop() return end
    if not settled then settled = true return end
    if about then
      if input:wasPressed("b") or input:wasPressed("a") or input:wasPressed("select") then about = false
      elseif input:wasPressed("right") and Share then about = math.min(3, about + 1)
      elseif input:wasPressed("left") and Share then about = math.max(1, about - 1) end
      return
    end
    if input:wasPressed("select") then
      about = Share and 1 or 3
      if about == 1 then pcall(engine.dispatch, engine, "ui.card_opened", {}) end
      return
    end
    if detail then
      if input:wasPressed("b") or input:wasPressed("a") then detail, page = nil, 1
      elseif input:wasPressed("right") then page = 2
      elseif input:wasPressed("left") then page = 1 end
      return
    end
    if input:wasPressed("b") or input:wasPressed("start") then
      closing = true
      return
    end
    local before = index
    if input:wasPressed("up") and index > 1 then index = index - 1 end
    if input:wasPressed("down") and index < #list then index = index + 1 end
    if index ~= before then clock = 0 end
    if input:wasPressed("left") then
      filterIndex = (filterIndex - 2) % #filters + 1
      index, scroll = 1, 0
      rebuild()
    elseif input:wasPressed("right") then
      filterIndex = filterIndex % #filters + 1
      index, scroll = 1, 0
      rebuild()
    end
    if input:wasPressed("a") and list[index] then detail = list[index] end
    if index - scroll > VISIBLE then scroll = index - VISIBLE end
    if index - scroll < 1 then scroll = index - 1 end
  end

  local function clear()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end

  local function drawList()
    local t = engine:totals()
    Font.drawBox(0, 0, 20, 4)
    Text.draw(Font, ("%d/%d"):format(t.earned, t.total), 1, 1)
    Text.drawRight(Font, ("PTS %d/%d"):format(t.points, t.maxPoints), 19, 1)
    local label = Text.fit(filters[filterIndex].label, 16)
    Text.arrow("left", 1, 2)
    Text.draw(Font, label, 10 - math.floor(Text.len(label) / 2), 2)
    Text.arrow("right", 18, 2)

    Font.drawBox(0, 4, 20, 14)
    if #list == 0 then
      Text.draw(Font, "NOTHING HERE YET", 2, LIST_TOP + 1)
      if not engine.active then Text.draw(Font, "LOAD A SAVE FIRST", 2, LIST_TOP + 3) end
      return
    end
    for i = 1, VISIBLE do
      local row = list[scroll + i]
      if not row then break end
      local ty = LIST_TOP + i - 1
      local kind = row.reference and "reference" or row.archived and "archived"
        or row.unlocked and "earned" or "locked"
      Text.mark(kind, 2, ty)
      local shown = Browser.display(row, reveal)
      local right = ""
      if not row.unlocked and row.goal and (row.progress or 0) > 0 then
        right = ("%d/%d"):format(row.progress, row.goal)
      end
      local width = 16 - (#right > 0 and #right + 1 or 0)
      local title = shown.title
      if scroll + i == index then title = Browser.marquee(Text, title, width, clock) end
      Text.draw(Font, Text.fit(title, width), 3, ty)
      if #right > 0 then Text.drawRight(Font, right, 19, ty) end
    end
    love.graphics.setColor(0, 0, 0, 1)
    Font.drawCode(Theme.cursor, 8, (LIST_TOP + index - scroll - 1) * 8)
    if scroll + VISIBLE < #list then
      Font.drawCode(Theme.moreArrow, 18 * 8, 17 * 8)
    end
  end

  -- Detail, page 1: what it is and where you stand.
  local function drawSummary(row)
    local shown = Browser.display(row, reveal)
    local y = 1
    for _, line in ipairs(Text.wrap(shown.title, 18)) do
      if y > 3 then break end
      Text.draw(Font, line, 1, y); y = y + 1
    end
    y = y + 1
    for _, line in ipairs(Text.wrap(shown.description, 18)) do
      if y > 11 then break end
      Text.draw(Font, line, 1, y); y = y + 1
    end
    -- footer: fixed rows so long text never overlaps it
    local status
    if row.reference then
      status = row.tracked and "TRACKED HERE" or "NOT TRACKED YET"
    elseif row.archived then
      status = "EARNED (ARCHIVED)"
    elseif row.unlocked then
      status = row.how == "backfill" and "EARNED (PAST SAVE)" or "EARNED"
    elseif row.goal then
      status = ("%d/%d %s"):format(row.progress or 0, row.goal, row.unit or "")
    else
      status = "LOCKED"
    end
    Text.draw(Font, Text.fit(status, 18), 1, 12)
    Text.draw(Font, Text.fit(("%dP  %s"):format(row.points or 0, row.category or ""), 18), 1, 13)
    local origin, credit
    if row.reference then
      origin, credit = "RA REFERENCE", row.author ~= "" and ("BY " .. row.author) or nil
    elseif row.source == "core" and row.official then
      origin = row.raType == "missable" and "RA LIST: MISSABLE" or "FROM THE RA LIST"
      credit = row.author and row.author ~= "" and ("BY " .. row.author) or nil
    elseif row.source == "core" then
      origin = "BONUS (NOT RA)"
    else
      origin = "MOD: " .. tostring(row.providerName or row.provider or "?")
    end
    Text.draw(Font, Text.fit(origin, 18), 1, 14)
    if row.archived then credit = "MOD NOT LOADED" end
    if credit then Text.draw(Font, Text.fit(credit, 18), 1, 15) end
    Text.draw(Font, "LOCAL ONLY", 1, 16)
    if not row.reference then Text.arrow("right", 18, 16) end
  end

  -- Detail, page 2: how this mod decides it, and the RA reference.
  local function drawAbout(row)
    Text.draw(Font, "ABOUT", 1, 1)
    local y = 3
    local function say(text)
      for _, line in ipairs(Text.wrap(text, 18)) do
        if y > 14 then return end
        Text.draw(Font, line, 1, y); y = y + 1
      end
      y = y + 1
    end
    if row.source ~= "core" then
      say("Added by the " .. tostring(row.providerName or row.provider) .. " mod.")
    elseif row.fidelity == "interpretation" then
      say("This mod's check is a close local version of the goal:")
      if row.note then say(row.note) end
    elseif row.official then
      say("Checked by this mod from your save and gameplay.")
      if row.note then say(row.note) end
    else
      say("A bonus achievement made for this mod.")
      if row.note then say(row.note) end
    end
    if row.official and row.raId then
      say(("RA game %s, achievement %s."):format(tostring(row.raGameId or "?"), tostring(row.raId)))
    end
    if row.unlocked and row.at then
      local ok, when = pcall(os.date, "%Y-%m-%d", row.at)
      if ok then say("Earned " .. when .. ".") end
    end
    Text.draw(Font, "NOT SENT TO RA", 1, 16)
    Text.arrow("left", 18, 16)
  end

  -- SELECT: what this mod is, and who the achievements come from.
  local function drawCredits()
    Font.drawBox(0, 0, 20, 18)
    local y = 1
    for _, text in ipairs(Browser.ABOUT) do
      for _, line in ipairs(Text.wrap(text, 18)) do
        if y > 15 then break end
        Text.draw(Font, line, 1, y); y = y + 1
      end
      y = y + 1
    end
    if Share then Text.arrow("left", 18, 16) end
  end

  -- SELECT page 1: what to type into the leaderboard issue form.
  local function drawCard()
    Font.drawBox(0, 0, 20, 18)
    local ok, card = pcall(Share.card, engine)
    if not ok then card = nil end
    for i, line in ipairs(Browser.cardLines(card)) do
      if i > 15 then break end
      Text.draw(Font, line, 1, i)
      if line:find("_", 1, true) then Text.underscores(line, 1, i) end
    end
    Text.arrow("right", 18, 16)
  end

  -- SELECT page 2: the Extra Credit card (bonus and mod achievements).
  local function drawExtra()
    Font.drawBox(0, 0, 20, 18)
    local ok, card = pcall(Share.extraCard, engine)
    if not ok then card = nil end
    for i, line in ipairs(Browser.extraLines(card)) do
      if i > 15 then break end
      Text.draw(Font, Text.fit(line, 18), 1, i)
      if line:find("_", 1, true) then Text.underscores(Text.fit(line, 18), 1, i) end
    end
    Text.arrow("left", 1, 16)
    Text.arrow("right", 18, 16)
  end

  local function drawDetail(row)
    Font.drawBox(0, 0, 20, 18)
    if page == 2 and not row.reference then drawAbout(row) else drawSummary(row) end
  end

  function self:draw()
    clear()
    if about == 1 then drawCard()
    elseif about == 2 then drawExtra()
    elseif about then drawCredits()
    elseif detail then drawDetail(detail)
    else drawList() end
    love.graphics.setColor(1, 1, 1, 1)
  end

  return self
end

-- ------------------------------------------------------------------
-- Wiring: register the screen and add the START row.
-- ------------------------------------------------------------------
-- Modern (ui/modern.lua) is the default menu; the CLASSIC MENU option
-- brings back the Game Boy text-box version above.
function Browser.install(mod, engine, util, Text, Share, Modern, Native3)
  mod.content.screens:register(Browser.SCREEN_ID, {
    new = function(game)
      -- CLASSIC MENU: the game's own look.  Gen 1 and Gen 2 draw with
      -- their tile font and text-box frame (below); Gen 3 with its GBA
      -- windows and font (ui/native3.lua), when the engine has them.
      local classic = mod.options:get("classicMenu")
      if classic and mod.generation == 3 and Native3 and Native3.available() then
        return Native3.newScreen({ mod = mod, engine = engine, Browser = Browser, Share = Share, game = game })
      end
      if Modern and not (classic and (mod.generation == 1 or mod.generation == 2)) then
        return Modern.newScreen({ mod = mod, engine = engine, Browser = Browser, Share = Share,
                                  game = game, boardUrl = Browser.BOARD_URL })
      end
      return Browser.newScreen(mod, engine, util, Text, game, Share)
    end,
  })

  -- The modern menu draws at window resolution, after the game frame.
  -- Installed before the popups' hook, so unlock popups stay on top.
  if Modern then
    -- Drawn BEFORE handing on, so anything later in the chain (the unlock
    -- popups included) lands on top of the menu whichever order the
    -- hooks were installed in.
    mod.hooks:wrap("render.hud", function(nextFn, game, vp, ...)
      local live = mod.game or game
      -- Gen 1/2 keep a list of states; Gen 3's mod stack is a facade
      -- with top() (src/ui/game3/mod_ui.lua)
      local stack = live and live.stack
      local top
      if stack and type(stack.states) == "table" then top = stack.states[#stack.states]
      elseif stack and type(stack.top) == "function" then
        local ok, t = pcall(stack.top, stack)
        top = ok and t or nil
      end
      if top and top.modern and top.drawWindow and type(vp) == "table" then
        local ok, err = pcall(top.drawWindow, top, vp)
        if not ok and not Browser.warned then
          Browser.warned = true
          mod.log:warn("achievements menu draw failed: %s", tostring(err))
        end
      end
      return nextFn(game, vp, ...)
    end)
  end

  local function openMenu(game)
    local live = mod.game or game
    local ok, err = pcall(mod.ui.push, live, Browser.SCREEN_ID)
    if not ok then mod.log:warn("could not open achievements: %s", tostring(err)) end
    return ok
  end
  Browser.openMenu = openMenu

  -- OPEN TROPHIES in the Mods manager: the menu opens on top of it, and
  -- B goes back there.
  mod.events:on("mod.options_changed", function(ev)
    if type(ev) == "table" and ev.mod == mod.id and ev.key == "openMenu" then
      if engine.game then openMenu(mod.game)
      else mod.log:info("OPEN TROPHIES: no game loaded yet") end
    end
  end)

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    items = nextFn(game, items)
    if type(items) ~= "table" then return items end
    if mod.options:get("startMenuEntry") == false then return items end
    mod.ui.insertBefore(items, Browser.MENU_ANCHOR, {
      -- Gen 1/2 START boxes are 10 tiles and grow to the widest label + 3,
      -- so anything over 7 letters would widen them (and push other mods'
      -- menus around): TROPHY there, TROPHIES on Gen 3.
      label = mod.generation == 3 and Browser.MENU_LABEL or Browser.SHORT_LABEL,
      -- Gen 2's MENU ACCOUNT help box: two lines, 9 characters at most
      -- (like its own "Your own" / "status")
      desc = { "Your", "trophies" },
      onSelect = function() openMenu(game) end,
    })
    return items
  end)
end

return Browser
