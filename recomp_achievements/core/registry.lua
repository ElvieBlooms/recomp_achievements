-- core/registry.lua
-- The registry holds definitions: an achievement's name, owner, which games
-- it's for, and any progress goal. It's rebuilt from code every session
-- and never saved, so it doesn't touch the engine or the save.
--
-- Two sources feed it:
--   "core": this mod's own rules (rules/*.lua)
--   "mod:<provider>": other mods, through the public API
--
-- Saved records (core/ledger.lua) point at definitions by key. A record
-- with no definition this session, because its provider is missing or
-- turned off, shows as ARCHIVED and is never deleted.
--
-- Optional reference material:
--   catalogs: RetroAchievements titles and descriptions per game, for the
--     reference view only. They can't be earned on their own.
--   links: which RA entry a core rule was inspired by, for credits.
-- ------------------

local Registry = {}
Registry.__index = Registry

Registry.LIMITS = {
  title = 32,          -- one GB-width line with room for a marker
  description = 160,
  category = 16,
  providerName = 24,
  tabLabel = 12,       -- a provider's own filter tab (Browser.filtersFor)
  maxPerProvider = 200, -- stops a runaway provider flooding the menu
  maxPoints = 100,
  maxGoal = 1000000,
}

-- Known version ids. A definition's `games` list must use these.
Registry.GAMES = {
  red = 1, blue = 1, yellow = 1,
  gold = 2, silver = 2, crystal = 2,
  ruby = 3, sapphire = 3, emerald = 3, firered = 3, leafgreen = 3,
}

function Registry.new(util)
  return setmetatable({
    util = util,
    defs = {},       -- key -> definition, read-only to other mods
    order = {},      -- keys in the order they arrived, so lists stay stable
    providers = {},  -- provider id -> { id, name, version, count }
    catalogs = {},   -- game -> list of reference entries
    links = {},      -- core rule id -> { [game] = raAchievementId }
    lists = {},      -- cart id -> a cart's own list (Registry:addList)
    borrows = {},    -- core key -> { [provider] = provider key using its check }
    listOf = {},     -- provider id -> the cart list it declared
  }, Registry)
end

-- ------------------ validation
-- Returns a cleaned copy of the definition, or nil, an error code and a
-- message. The codes are part of the public API (docs/PROVIDER_API.md),
-- so don't rename them.
function Registry:clean(input, source)
  local util, L = self.util, Registry.LIMITS
  if type(input) ~= "table" then return nil, "invalid_definition", "definition must be a table" end
  if not util.validId(input.id) then
    return nil, "invalid_id", "id must be 1-48 chars of a-z 0-9 _ -"
  end
  local title = util.text(input.title)
  if not title or title == "" then return nil, "invalid_title", "title is required" end
  if util.len(title) > L.title then
    return nil, "invalid_title", ("title is longer than %d characters"):format(L.title)
  end
  local description = util.text(input.description or "", L.description)
  local points = input.points == nil and 5 or input.points
  if not util.isInteger(points) or points < 0 or points > L.maxPoints then
    return nil, "invalid_points", "points must be an integer 0-" .. L.maxPoints
  end
  local goal = input.goal
  if goal ~= nil and (not util.isInteger(goal) or goal < 1 or goal > L.maxGoal) then
    return nil, "invalid_goal", "goal must be an integer 1-" .. L.maxGoal
  end
  local games
  if input.games ~= nil then
    if type(input.games) ~= "table" or #input.games == 0 then
      return nil, "invalid_games", "games must be a non-empty list of version ids"
    end
    games = {}
    for _, g in ipairs(input.games) do
      if not Registry.GAMES[g] then
        return nil, "invalid_games", "unknown game version: " .. tostring(g)
      end
      games[g] = true
    end
  end
  -- RA's tags for an entry's role in a list: progression, win_condition
  -- or missable. Anything else is dropped rather than refused.
  local kind = input.type
  if kind ~= "progression" and kind ~= "win_condition" and kind ~= "missable" then kind = nil end
  -- A category that isn't text falls back to GENERAL instead of erroring.
  local category = (util.text(input.category, L.category) or "GENERAL"):upper()
  if category == "" then category = "GENERAL" end
  -- Core rules only: the official RA entry this rule tracks per game,
  -- like { red = 1234, blue = 5678 }. With `official = true` and no games
  -- list, the rule only exists on the linked games.
  local ra
  if source == "core" and type(input.ra) == "table" then
    ra = {}
    for g, id in pairs(input.ra) do
      if Registry.GAMES[g] and util.isInteger(id) then ra[g] = id end
    end
    if not games and input.official then
      games = {}
      for g in pairs(ra) do games[g] = true end
      if next(games) == nil then return nil, "invalid_games", "official rule has no ra links" end
    end
  end
  return {
    id = input.id,
    title = title,
    description = description,
    points = points,
    goal = goal,
    unit = util.text(input.unit, 12),
    hidden = input.hidden == true,
    category = category,
    games = games,                 -- nil means any game the mod runs on
    revision = util.isInteger(input.revision) and input.revision or 1,
    source = source,
    ra = ra,
    extra = source == "core" and input.extra == true or nil,
    fidelity = source == "core" and (input.fidelity == "interpretation" and "interpretation" or "exact") or nil,
    note = util.text(input.note, 300),
    type = kind,
    -- a cart list's entry can be earned by this mod's own checks:
    -- uses = "<core rule id>" or a list of them, any of which earns it
    -- (see Registry:add)
    uses = source ~= "core" and Registry.usesOf(util, input.uses) or nil,
  }
end

-- `uses` as a list of core keys, or nil
function Registry.usesOf(util, uses)
  if uses == nil then return nil end
  local ids = type(uses) == "table" and uses or { uses }
  local out = {}
  for _, id in ipairs(ids) do
    out[#out + 1] = util.validId(id) and ("core:" .. id) or ("core:?" .. tostring(id))
  end
  return #out > 0 and out or nil
end

-- Register one definition under "core" or "mod:<provider>".
-- The same key with the same content is a harmless repeat.
-- The same key with different content fails with "duplicate_id".
function Registry:add(sourceKind, providerId, input)
  local source = sourceKind == "core" and "core" or ("mod:" .. providerId)
  local def, code, message = self:clean(input, source)
  if not def then return nil, code, message end
  def.provider = providerId
  def.key = source .. ":" .. def.id
  local existing = self.defs[def.key]
  if existing then
    if existing.title == def.title and existing.description == def.description
        and existing.points == def.points and existing.goal == def.goal
        and existing.hidden == def.hidden and existing.revision == def.revision then
      return existing, "already_registered"
    end
    return nil, "duplicate_id", def.key .. " is already registered with different content"
  end
  if def.uses then
    for _, coreKey in ipairs(def.uses) do
      if not self.defs[coreKey] then
        return nil, "unknown_rule", coreKey .. " is not one of this mod's checks"
      end
    end
    -- one check reports progress against its own goal
    local rule = #def.uses == 1 and self.defs[def.uses[1]]
    if rule and def.goal == nil then def.goal, def.unit = rule.goal, def.unit or rule.unit end
  end
  if sourceKind ~= "core" then
    local p = self.providers[providerId]
    if p and p.count >= Registry.LIMITS.maxPerProvider then
      return nil, "provider_limit", "provider registered too many achievements"
    end
    if p then p.count = p.count + 1 end
  end
  self.defs[def.key] = def
  self.order[#self.order + 1] = def.key
  for _, coreKey in ipairs(def.uses or {}) do
    local by = self.borrows[coreKey]
    if not by then by = {}; self.borrows[coreKey] = by end
    by[providerId] = def.key
  end
  return def
end

function Registry:get(key) return self.defs[key] end

function Registry:addProvider(id, info)
  if self.providers[id] then return self.providers[id], "already_registered" end
  self.providers[id] = {
    id = id,
    name = self.util.text(info.name or id, Registry.LIMITS.providerName),
    version = self.util.text(info.version or "?", 16),
    -- label for the provider's own filter tab; falls back to its name
    tab = type(info.tab) == "string" and info.tab ~= ""
      and self.util.text(info.tab, Registry.LIMITS.tabLabel) or nil,
    count = 0,
  }
  return self.providers[id]
end

-- ------------------ cart lists
-- A custom cart can bring its own main list in place of the RA list (a
-- romhack ported as a cart, say). The provider that declares it owns the
-- list: everything it registers is the list. On that cart the list is
-- what the leaderboard card counts, under the list's own board id, and the
-- RA-linked rules step aside. Elsewhere its entries are ordinary provider
-- achievements.
--   spec = { cart = "<cart id>", board = "<leaderboard id>", title = "...",
--            label = "<tab label>", games = { "<base version>", ... } }
function Registry:addList(providerId, spec)
  local util = self.util
  if type(spec) ~= "table" then return nil, "invalid_list", "expected a table" end
  if not util.validId(spec.cart) then
    return nil, "invalid_list", "cart must be a cart id (1-48 chars of a-z 0-9 _ -)"
  end
  local board = spec.board == nil and spec.cart or spec.board
  if not util.validId(board) or Registry.GAMES[board] then
    return nil, "invalid_list", "board must be an id of its own, not a game version"
  end
  local title = util.text(spec.title or board, 32)
  local games
  if spec.games ~= nil then
    if type(spec.games) ~= "table" or #spec.games == 0 then
      return nil, "invalid_games", "games must be a non-empty list of version ids"
    end
    games = {}
    for _, g in ipairs(spec.games) do
      if not Registry.GAMES[g] then return nil, "invalid_games", "unknown game version: " .. tostring(g) end
      games[g] = true
    end
  end
  local existing = self.lists[spec.cart]
  if existing then
    if existing.provider == providerId and existing.board == board then return existing, "already_registered" end
    return nil, "list_taken", ("cart %s already has a list from %s"):format(spec.cart, existing.provider)
  end
  local list = {
    cart = spec.cart, board = board, title = title,
    label = util.text(spec.label or title, Registry.LIMITS.tabLabel):upper(),
    games = games, provider = providerId,
  }
  self.lists[spec.cart] = list
  self.listOf[providerId] = list
  return list
end

-- The list for this cart on this version, or nil.
function Registry:listFor(cart, game)
  local list = type(cart) == "string" and self.lists[cart] or nil
  if not list then return nil end
  if list.games and not list.games[game] then return nil end
  return list
end

-- Whether a definition applies to the running game version.
function Registry.appliesTo(def, game)
  return def.games == nil or def.games[game] == true
end

-- ------------------ reference catalogs
-- Optional and display only. A catalog file returns
-- { gameId = 724, game = "red", entries = { ... } }
-- with entries { id, title, description, points, author, order }.
function Registry:addCatalog(game, catalog)
  local list = {}
  for _, e in ipairs(catalog.entries or {}) do
    if type(e) == "table" and self.util.isInteger(e.id) and type(e.title) == "string" then
      list[#list + 1] = {
        id = e.id,
        title = self.util.text(e.title, 60),
        description = self.util.text(e.description or "", 200),
        points = self.util.isInteger(e.points) and e.points or 0,
        author = self.util.text(e.author or "", 32),
        order = tonumber(e.order) or e.id,
        type = self.util.text(e.type or "", 16),
      }
    end
  end
  table.sort(list, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.id < b.id
  end)
  self.catalogs[game] = { gameId = catalog.gameId, entries = list }
end

function Registry:addLinks(links)
  for ruleId, perGame in pairs(links) do
    if type(ruleId) == "string" and type(perGame) == "table" then
      self.links[ruleId] = perGame
    end
  end
end

-- The RA achievement id a core rule tracks on this game, if any.
-- The rule's own `ra` table wins; catalog/links.lua fills the gaps.
function Registry:raIdFor(def, game)
  if def.source ~= "core" then return nil end
  if def.ra and def.ra[game] then return def.ra[game] end
  local link = self.links[def.id]
  return link and link[game] or nil
end

-- The catalog entry a core rule tracks on this game, if any.
function Registry:referenceFor(def, game)
  local raId = self:raIdFor(def, game)
  local catalog = self.catalogs[game]
  if not (raId and catalog) then return nil end
  for _, e in ipairs(catalog.entries) do
    if e.id == raId then return e, catalog.gameId end
  end
  return nil
end

-- What to show for a definition on this game. A core rule linked to an
-- installed RA catalog entry shows RA's title, description and points,
-- credited to its author; anything else shows its own text.
-- Save keys stay the same either way.
function Registry:display(def, game)
  local ref, raGameId = nil, nil
  if game then ref, raGameId = self:referenceFor(def, game) end
  if ref then
    return {
      title = ref.title, description = ref.description, points = ref.points,
      official = true, raId = ref.id, raGameId = raGameId, author = ref.author,
      raType = ref.type,
    }
  end
  return { title = def.title, description = def.description, points = def.points,
           official = false }
end

-- Which catalog entries have one of our rules linked on this game.
function Registry:linkedSet(game)
  local set = {}
  for _, key in ipairs(self.order) do
    local def = self.defs[key]
    local id = self:raIdFor(def, game)
    if id and Registry.appliesTo(def, game) then set[id] = key end
  end
  return set
end

return Registry
