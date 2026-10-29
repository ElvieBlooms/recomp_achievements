-- core/registry.lua
-- ==================================================================
-- The registry holds DEFINITIONS: what an achievement is called, who
-- owns it, which games it applies to, whether it has a progress goal.
-- It is rebuilt from code every session and never saved.
--
-- Two sources feed it:
--   * "core"  -- our own native rules (rules/gen1.lua)
--   * "mod:<provider>" -- other mods, through the public API
--
-- Saved RECORDS (core/ledger.lua) point at definitions by key.  A record
-- whose definition is missing this session (provider uninstalled or
-- disabled) is shown as ARCHIVED -- never deleted.
--
-- Optional reference material:
--   * catalogs: RetroAchievements titles/descriptions per game, for the
--     "reference" view only.  Never earnable on their own.
--   * links:    which RA entry a core rule was inspired by, for credits.
-- ==================================================================

local Registry = {}
Registry.__index = Registry

Registry.LIMITS = {
  title = 32,          -- fits a GB-width line with room for a marker
  description = 160,
  category = 16,
  providerName = 24,
  maxPerProvider = 200, -- keeps a runaway provider from flooding the UI
  maxPoints = 100,
  maxGoal = 1000000,
}

-- Known version ids.  A definition's `games` list must use these.
Registry.GAMES = {
  red = 1, blue = 1, yellow = 1,
  gold = 2, silver = 2, crystal = 2,
  ruby = 3, sapphire = 3, emerald = 3, firered = 3, leafgreen = 3,
}

function Registry.new(util)
  return setmetatable({
    util = util,
    defs = {},       -- key -> definition (read-only to the outside)
    order = {},      -- keys in registration order, for stable listing
    providers = {},  -- provider id -> { id, name, version, count }
    catalogs = {},   -- game -> list of reference entries
    links = {},      -- core rule id -> { [game] = raAchievementId }
  }, Registry)
end

-- ------------------------------------------------------------------
-- Validation.  Returns a cleaned copy of the definition, or nil plus an
-- error code and a human message.  Error codes are part of the public
-- API contract (see docs/PROVIDER_API.md), so don't rename them lightly.
-- ------------------------------------------------------------------
function Registry:clean(input, source)
  local util, L = self.util, Registry.LIMITS
  if type(input) ~= "table" then return nil, "invalid_definition", "definition must be a table" end
  if not util.validId(input.id) then
    return nil, "invalid_id", "id must be 1-48 chars of a-z 0-9 _ -"
  end
  local title = util.text(input.title)
  if not title or title == "" then return nil, "invalid_title", "title is required" end
  if #title > L.title then
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
  local category = util.text(input.category or "GENERAL", L.category):upper()
  -- Core rules only: which official RA entry each game's version of this
  -- rule tracks.  { red = 1234, blue = 5678 }.  With `official = true`
  -- and no explicit games list, the rule exists only on the linked games.
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
    games = games,                 -- nil means "any game the mod runs on"
    revision = util.isInteger(input.revision) and input.revision or 1,
    source = source,
    ra = ra,
    extra = source == "core" and input.extra == true or nil,
    fidelity = source == "core" and (input.fidelity == "interpretation" and "interpretation" or "exact") or nil,
    note = util.text(input.note, 300),
  }
end

-- Register one definition under a source ("core" or "mod:<provider>").
-- Same key + identical content = no-op success (idempotent re-register).
-- Same key + different content = "duplicate_id" error, nothing changes.
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
  if sourceKind ~= "core" then
    local p = self.providers[providerId]
    if p and p.count >= Registry.LIMITS.maxPerProvider then
      return nil, "provider_limit", "provider registered too many achievements"
    end
    if p then p.count = p.count + 1 end
  end
  self.defs[def.key] = def
  self.order[#self.order + 1] = def.key
  return def
end

function Registry:get(key) return self.defs[key] end

function Registry:addProvider(id, info)
  if self.providers[id] then return self.providers[id], "already_registered" end
  self.providers[id] = {
    id = id,
    name = self.util.text(info.name or id, Registry.LIMITS.providerName),
    version = self.util.text(info.version or "?", 16),
    count = 0,
  }
  return self.providers[id]
end

-- Does a definition apply to the running game version?
function Registry.appliesTo(def, game)
  return def.games == nil or def.games[game] == true
end

-- ------------------------------------------------------------------
-- Reference catalogs (optional, display only).
-- A catalog file returns { gameId = 724, game = "red", entries = { ... } }
-- with entries { id, title, description, points, author, order }.
-- ------------------------------------------------------------------
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
-- A rule's own `ra` table wins; catalog/links.lua fills gaps.
function Registry:raIdFor(def, game)
  if def.source ~= "core" then return nil end
  if def.ra and def.ra[game] then return def.ra[game] end
  local link = self.links[def.id]
  return link and link[game] or nil
end

-- The RA entry (if any) a core rule tracks, for this game.
function Registry:referenceFor(def, game)
  local raId = self:raIdFor(def, game)
  local catalog = self.catalogs[game]
  if not (raId and catalog) then return nil end
  for _, e in ipairs(catalog.entries) do
    if e.id == raId then return e, catalog.gameId end
  end
  return nil
end

-- What to SHOW for a definition on this game.  A core rule linked to an
-- official RA entry (whose catalog is installed) shows RA's own title,
-- description and points, credited to its author.  Otherwise the rule's
-- own text.  Save keys never change either way.
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

-- Which catalog entries have a native rule linked to them on this game.
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
