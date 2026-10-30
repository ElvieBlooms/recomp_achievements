-- tests/harness.lua
-- ==================================================================
-- Boots the REAL Gen1Recomp mod loader (src/mods/Loader.lua from the
-- 0.3.97 package) headless under LuaJIT, with our mods installed in a
-- temporary folder.  Everything a mod touches -- the sandbox, manifest
-- validation, dependency order, mod.exports / mod.find, the API 3 event
-- boundary, hooks, mod.save, the content registry -- is the engine's own
-- code.  Only the game itself is faked: a save table, an input object and
-- a state stack, which is what Gen 1's Game object hands mods.
--
-- Drawing is captured as text: love.graphics and the tile Font are
-- replaced by recorders, so a test can assert "the screen shows 3/27".
--
-- Run:  ENGINE=/path/to/extracted/love luajit tests/run.lua
-- ==================================================================

local ENGINE = os.getenv("ENGINE") or "/home/claude/engine"
local PROJECT = os.getenv("PROJECT") or (debug.getinfo(1, "S").source:match("^@(.*)/tests/") or ".")
package.path = ENGINE .. "/?.lua;" .. ENGINE .. "/?/init.lua;" .. package.path

local H = {}
H.PROJECT = PROJECT

-- ------------------------------------------------------------------
-- Recording love.graphics + Font, installed BEFORE engine UI modules load.
-- ------------------------------------------------------------------
local drawn = {}
H.drawn = drawn
local function noop() end
_G.love = _G.love or {}
love.graphics = setmetatable({
  getColor = function() return 1, 1, 1, 1 end,
}, { __index = function() return noop end })
local clockNow = 0
love.timer = { getTime = function() return clockNow end }
function H.advance(seconds) clockNow = clockNow + seconds end

-- Fake love.sound / love.audio: every play is recorded in H.sounds.
H.sounds = {}
love.sound = { newSoundData = function(n, rate, bits, channels)
  return { n = n, rate = rate, setSample = function() end }
end }
love.audio = { newSource = function(data)
  local src = { data = data }
  function src:stop() end
  function src:setVolume(v) self.volume = v end
  function src:play() H.sounds[#H.sounds + 1] = { samples = self.data.n, volume = self.volume } end
  return src
end }

local FakeFont = {}
function FakeFont.draw(text, x, y)
  drawn[#drawn + 1] = { text = text, tx = x / 8, ty = y / 8 }
  return #text * 8
end
function FakeFont.drawBox() end
function FakeFont.drawCode(code, x, y)
  drawn[#drawn + 1] = { code = code, tx = x / 8, ty = y / 8 }
end
function FakeFont.width(text) return #text * 8 end
function FakeFont.split(text) local t = {} for c in text:gmatch(".") do t[#t + 1] = c end return t end
package.loaded["src.render.Font"] = FakeFont
package.loaded["src.ui.Theme"] = { cursor = 0xED, cursorHollow = 0xEC, moreArrow = 0xEE }

-- the screen as a list of text lines, row by row
function H.screenText()
  local rows = {}
  for _, d in ipairs(drawn) do
    if d.text then
      local r = math.floor(d.ty + 0.5)
      rows[r] = rows[r] or {}
      table.insert(rows[r], { x = d.tx, text = d.text })
    end
  end
  local out = {}
  for r = 0, 40 do
    if rows[r] then
      table.sort(rows[r], function(a, b) return a.x < b.x end)
      local line = {}
      for _, piece in ipairs(rows[r]) do line[#line + 1] = piece.text end
      out[#out + 1] = table.concat(line, " ")
    end
  end
  return out
end
function H.clearDrawn() for i = #drawn, 1, -1 do drawn[i] = nil end end
function H.screenHas(pattern)
  for _, line in ipairs(H.screenText()) do
    if line:find(pattern) then return true, line end
  end
  return false
end

local GameVersion = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Loader = require("src.mods.Loader")
local SaveSerializer = require("src.core.SaveSerializer")
local Logger = require("src.core.Logger")

-- capture engine log lines (warnings from mods land here)
H.logs = {}
for _, level in ipairs({ "info", "warn", "error", "debug" }) do
  Logger[level] = function(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    H.logs[#H.logs + 1] = level .. ": " .. (ok and line or tostring(fmt))
  end
end
function H.logHas(pattern)
  for _, l in ipairs(H.logs) do if l:find(pattern) then return true, l end end
  return false
end

-- ------------------------------------------------------------------
-- A plain-Lua filesystem rooted at a temp dir (the engine's fs contract).
-- ------------------------------------------------------------------
local function sh(cmd) local p = io.popen(cmd); local out = p:read("*a"); p:close(); return out end
local function makeFs(root)
  local fs = {}
  local function full(path) return root .. "/" .. path end
  function fs.getInfo(path)
    local kind = sh("if [ -d '" .. full(path) .. "' ]; then echo d; elif [ -f '"
      .. full(path) .. "' ]; then echo f; fi")
    if kind:find("d") then return { type = "directory" } end
    if kind:find("f") then
      local f = io.open(full(path), "rb")
      local size = f:seek("end"); f:close()
      return { type = "file", size = size }
    end
    return nil
  end
  function fs.getDirectoryItems(path)
    local out = {}
    for name in sh("ls -1 '" .. full(path) .. "' 2>/dev/null"):gmatch("[^\n]+") do out[#out + 1] = name end
    return out
  end
  function fs.read(path)
    local f = io.open(full(path), "rb")
    if not f then return nil, "not found" end
    local s = f:read("*a"); f:close(); return s
  end
  function fs.load(path)
    local s = fs.read(path)
    if not s then return nil, "not found: " .. path end
    return loadstring(s, "@" .. path)
  end
  return fs
end

-- ------------------------------------------------------------------
-- Fake game: what mods see as mod.game on Gen 1.
-- ------------------------------------------------------------------
local function newInput()
  local input = { pressed = {} }
  function input:wasPressed(b) return self.pressed[b] == true end
  function input:isDown() return false end
  return input
end

local function newStack()
  local stack = { states = {} }
  function stack:push(s) self.states[#self.states + 1] = s; if s.enter then s:enter() end end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

function H.newSave(version)
  return {
    version = version, flags = {}, inventory = {}, party = {},
    pokedex = { seen = {}, owned = {} }, money = 3000, modData = {},
    player = { name = "RED", id = 1234, map = "PALLET_TOWN" },
    options = { battleStyle = "shift" }, defeatedTrainers = {}, itemsTaken = {},
    hiddenTaken = {}, objectToggles = {}, visited = {}, box = {},
  }
end

-- ------------------------------------------------------------------
-- Boot: install the named mods into a fresh temp root and run the loader.
-- ------------------------------------------------------------------
H.GAMEDATA = os.getenv("GAMEDATA") or "/home/claude/src_extract/pokemon-love2d"
local dataCache = {}
function H.loadData(version)
  if not dataCache[version] then
    local d = {}
    for _, name in ipairs({ "maps", "pokemon", "items", "field", "trainer_headers",
                            "encounters", "trainers", "moves", "constants" }) do
      local path = ("%s/%s/data/generated/%s.lua"):format(H.GAMEDATA, version, name)
      local chunk = loadfile(path)
      if chunk then d[name] = chunk() end
    end
    dataCache[version] = d
  end
  -- a fresh shallow copy per boot: the loader merges mod content into it
  local out = {}
  for k, v in pairs(dataCache[version]) do out[k] = v end
  return out
end

H.roots = {}
function H.boot(modIds, opts)
  opts = opts or {}
  local version = opts.version or "red"
  GameVersion.set(version)
  Runtime.reset()
  local root = os.tmpname() .. "_root"
  sh("mkdir -p '" .. root .. "/mods'")
  for _, id in ipairs(modIds) do
    sh(("cp -r '%s/%s' '%s/mods/%s'"):format(PROJECT, id, root, id))
  end
  if opts.noCatalog then
    sh(("rm -f '%s/mods/recomp_achievements/catalog/'*.lua"):format(root))
  end
  if opts.files then
    for path, content in pairs(opts.files) do
      local f = io.open(root .. "/" .. path, "wb"); f:write(content); f:close()
    end
  end
  H.roots[#H.roots + 1] = root
  local loader = Loader.new({ fs = makeFs(root), generation = 1, version = version })
  -- The real extracted game data for this version (maps, species, the
  -- field tables, trainer headers...), so rules are tested against the
  -- same tables they read in game.  GAMEDATA points at the folder that
  -- holds red/ blue/ yellow/ (Gen1Recomp's data folder).
  local data = H.loadData(version)
  local game = {
    data = data, input = newInput(), stack = newStack(),
    save = H.newSave(version), mods = loader,
  }
  loader.game = game -- what Loader:_game() hands to mod.game
  local ok = loader:load(data, {})
  -- what Game:init does next: adopt the title-screen skeleton save, then
  -- announce the game is ready (src/core/Game.lua:99-121)
  loader.modSave = game.save.modData
  Runtime.emit("save.created", { save = game.save })
  Runtime.emit("game.ready", { game = game })
  local env = { loader = loader, game = game, data = data, ok = ok, version = version }
  return setmetatable(env, { __index = H.Env })
end

H.Env = {}
local Env = H.Env

function Env:mod(id) return self.loader.mods[id] end
function Env:exports(id) return self.loader.exports[id] end
function Env:emit(name, payload) Runtime.emit(name, payload or {}) end

-- Game:adoptSave + the event the engine fires (src/core/Game.lua:1348)
function Env:adopt(save, event)
  save.modData = save.modData or {}
  self.game.save = save
  self.loader.modSave = save.modData
  Runtime.emit(event == "created" and "save.created" or "save.loaded", { save = save })
end

function Env:newGame()
  Runtime.emit("save.loading", {})
  self:adopt(H.newSave(self.version), "created")
end

-- What Save Sync does to a slot: the whole save is serialized to a blob
-- and decoded on the far side (src/sync/SyncEngine.lua list()/write()).
function Env:writeBlob()
  Runtime.emit("save.writing", { save = self.game.save })
  return SaveSerializer.encode(self.game.save)
end

function Env:loadBlob(blob)
  local save = assert(SaveSerializer.decode(blob))
  Runtime.emit("save.loading", {})
  self:adopt(save, "loaded")
  return save
end

-- One game frame: core.update wraps the step (src/core/PlatformHooks.lua)
function Env:frame(dt)
  Runtime.call("core.update", function() end, self.game, dt or 1 / 60)
end

function Env:setFlag(name)
  self.game.save.flags[name] = true
  Runtime.emit("flag.changed", { name = name, value = true })
end

-- A minimal overworld for rules that look at the player's map/position.
function Env:place(mapId, x, y, facing)
  local data = self.game.data
  local def = data.maps and data.maps[mapId] or { id = mapId }
  local ow = self.game.overworld or { npcs = {} }
  ow.map = { id = mapId, def = def }
  ow.player = ow.player or {}
  ow.player.cellX, ow.player.cellY, ow.player.facing = x or 0, y or 0, facing or "down"
  local d = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  function ow.player:facingCell()
    local v = d[self.facing] or { 0, 0 }
    return self.cellX + v[1], self.cellY + v[2]
  end
  self.game.overworld = ow
  return ow
end

-- Walk into a map the way the engine announces it.
function Env:enter(mapId, fromMapId, x, y)
  local before = self.game.overworld and self.game.overworld.map and self.game.overworld.map.id
  self:place(mapId, x, y)
  self.game.save.player.map = mapId
  Runtime.emit("map.entered", { mapId = mapId, fromMapId = fromMapId or before, via = "warp" })
end

-- One battle, start to finish, with what the engine emits.
--   opts: kind, trainerId, lead (species), result, payDay, fainted, ...
function Env:battle(opts)
  local raw = { player = { mon = { species = opts.lead or "PIKACHU", hp = 10, stats = { hp = 10 } } } }
  self:emit("battle.started", { battle = raw, kind = opts.kind or "trainer",
    trainerId = opts.trainerId, species = opts.species })
  if opts.during then opts.during(raw) end
  self:emit("battle.ended", { battle = raw, result = opts.result or "win" })
  return raw
end

function Env:press(button)
  self.game.input.pressed = { [button] = true }
  local top = self.game.stack:top()
  if top and top.update then top:update(1 / 60) end
  self.game.input.pressed = {}
end

function Env:draw()
  H.clearDrawn()
  local top = self.game.stack:top()
  if top and top.draw then top:draw() end
  return H.screenText()
end

function Env:hud()
  H.clearDrawn()
  Runtime.call("render.hud", function() end, self.game,
    { gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144, scale = 1 })
  return H.screenText()
end

function Env:startMenu()
  local items = {
    { label = "POKéDEX" }, { label = "POKéMON" }, { label = "ITEM" },
    { label = "RED" }, { label = "SAVE" }, { label = "OPTION" }, { label = "QUIT" },
  }
  return Runtime.call("ui.start_menu.items", function(_, i) return i end, self.game, items)
end

function H.cleanup()
  for _, root in ipairs(H.roots) do sh("rm -rf '" .. root .. "'") end
end

return H
