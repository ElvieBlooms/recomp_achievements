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
Browser.MENU_LABEL = "ACHIEVEMENTS"
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
  { id = "official", label = "OFFICIAL" },
  { id = "bonus",    label = "BONUS" },
  { id = "mods",     label = "FROM MODS" },
  { id = "archived", label = "ARCHIVED" },
  { id = "reference", label = "RA REFERENCE", optional = true },
}

local function passes(filter, row)
  if filter == "reference" then return row.reference == true end
  if row.reference then return false end
  if filter == "all" then return true end
  if filter == "earned" then return row.unlocked end
  if filter == "missing" then return not row.unlocked and not row.archived end
  if filter == "progress" then
    return not row.unlocked and row.goal ~= nil and (row.progress or 0) > 0
  end
  if filter == "official" then return row.source == "core" and row.official == true end
  if filter == "bonus" then return row.source == "core" and not row.official end
  if filter == "mods" then return row.source ~= "core" and not row.archived end
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
        tracked = linked[e.id] ~= nil, unlocked = false, raId = e.id,
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
function Browser.newScreen(mod, engine, util, Text, game)
  local Font = mod.ui.Font
  local Theme = mod.ui.Theme
  -- isOpaque: the state stack stops drawing the world under us
  -- (src/core/StateStack.lua), like the Pokedex and Diploma screens.
  local self = { isMenu = true, isOpaque = true, game = game }

  local filters = {}
  for _, f in ipairs(FILTERS) do
    if not f.optional or mod.options:get("showReference") then filters[#filters + 1] = f end
  end
  local filterIndex, index, scroll = 1, 1, 0
  local rows, list = {}, {}
  local detail = nil -- the row being inspected, or nil for the list
  local page = 1     -- detail page: 1 = summary, 2 = about this rule
  local about = false -- the SELECT credits page
  local clock = 0     -- drives the selected row's title scroll
  local reveal = mod.options:get("showHidden") == true

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
    if about then
      if input:wasPressed("b") or input:wasPressed("a") or input:wasPressed("select") then about = false end
      return
    end
    if input:wasPressed("select") then about = true return end
    if detail then
      if input:wasPressed("b") or input:wasPressed("a") then detail, page = nil, 1
      elseif input:wasPressed("right") then page = 2
      elseif input:wasPressed("left") then page = 1 end
      return
    end
    if input:wasPressed("b") or input:wasPressed("start") then
      game.stack:pop()
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
    local label = filters[filterIndex].label
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
      origin, credit = "OFFICIAL RA SET", row.author and row.author ~= "" and ("BY " .. row.author) or nil
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
        if y > 16 then return end
        Text.draw(Font, line, 1, y); y = y + 1
      end
      y = y + 1
    end
  end

  local function drawDetail(row)
    Font.drawBox(0, 0, 20, 18)
    if page == 2 and not row.reference then drawAbout(row) else drawSummary(row) end
  end

  function self:draw()
    clear()
    if about then drawCredits()
    elseif detail then drawDetail(detail)
    else drawList() end
    love.graphics.setColor(1, 1, 1, 1)
  end

  return self
end

-- ------------------------------------------------------------------
-- Wiring: register the screen and add the START row.
-- ------------------------------------------------------------------
function Browser.install(mod, engine, util, Text)
  mod.content.screens:register(Browser.SCREEN_ID, {
    new = function(game) return Browser.newScreen(mod, engine, util, Text, game) end,
  })

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    items = nextFn(game, items)
    if type(items) ~= "table" then return items end
    mod.ui.insertBefore(items, Browser.MENU_ANCHOR, {
      label = Browser.MENU_LABEL,
      onSelect = function()
        local live = mod.game or game
        local ok, err = pcall(mod.ui.push, live, Browser.SCREEN_ID)
        if not ok then mod.log:warn("could not open achievements: %s", tostring(err)) end
      end,
    })
    return items
  end)
end

return Browser
