-- Recomp Achievements: entry point
-- ==================================================================
-- The engine runs this file inside the mod sandbox and hands us `mod`
-- (the API 3 object built in src/mods/Loader.lua:_api).  Everything the
-- mod does is wired here, top to bottom, so this file doubles as a map
-- of the whole project:
--
--   core/util.lua      tiny helpers (copy, clamp, string checks)
--   core/ledger.lua    the save bucket: what is unlocked / in progress
--   core/registry.lua  achievement *definitions* known this session
--   core/engine.lua    the one award pipeline every unlock goes through
--   core/api.lua       the public exports other mods call
--   adapters/gen1.lua  reads Red/Blue/Yellow state into plain "facts"
--   rules/gen1.lua     native detectors (our own logic, not RA's)
--   catalog/*.lua      optional RA reference metadata (developer import)
--   ui/text.lua       font-safe text + status marks
--   ui/toast.lua       unlock popups, drawn on the render.hud hook
--   ui/browser.lua     the ACHIEVEMENTS screen opened from START
--
-- Design rule worth remembering: definitions are rebuilt every session
-- (code), records live in the save (data).  Nothing in the save is ever
-- a function, so a save without this mod installed stays loadable.
-- ==================================================================

return function(mod)
  -- ----------------------------------------------------------------
  -- import(): load one of our own files.
  --
  -- Other mods use require("mods.<id>.file"), which works but runs the
  -- file through the engine's global require.  mod:read + load keeps the
  -- file inside *our* sandbox environment and does not care what folder
  -- name the player installed us under.  Results are cached like require.
  -- ----------------------------------------------------------------
  local cache = {}
  local function import(path)
    if cache[path] ~= nil then return cache[path] end
    local source = mod:read(path)
    assert(source, "recomp_achievements: missing file " .. path)
    local chunk, err = load(source, "@" .. mod.id .. "/" .. path)
    assert(chunk, err)
    local result = chunk()
    cache[path] = result == nil and true or result
    return result
  end

  local util     = import("core/util.lua")
  local Ledger   = import("core/ledger.lua")
  local Registry = import("core/registry.lua")
  local Engine   = import("core/engine.lua")
  local Api      = import("core/api.lua")
  local Text     = import("ui/text.lua")
  local Toast    = import("ui/toast.lua")
  local Browser  = import("ui/browser.lua")
  local Share    = import("ui/share.lua")

  -- ----------------------------------------------------------------
  -- Player options.  These live in mod.options (install-wide), NOT in
  -- the save, because they are preferences rather than progress.
  -- ----------------------------------------------------------------
  mod.options:define({
    { key = "toasts", type = "toggle", label = "UNLOCK POPUPS", default = true },
    { key = "extras", type = "toggle", label = "BONUS ACHIEVEMENTS", default = true },
    { key = "showHidden", type = "toggle", label = "REVEAL HIDDEN", default = false },
    { key = "showReference", type = "toggle", label = "SHOW RA REFERENCE", default = false },
    { key = "debug", type = "toggle", label = "DEBUG LOG", default = false },
  })

  local ledger = Ledger.new(mod, util)
  local registry = Registry.new(util)
  local toast = Toast.new(mod, util, Text)
  local engine = Engine.new({
    mod = mod, util = util, ledger = ledger, registry = registry, toast = toast,
  })

  -- ----------------------------------------------------------------
  -- Built-in content for the running generation.  Phase 1 ships Gen 1
  -- only; Gen 2/3 adapters slot in here later without touching the core.
  -- ----------------------------------------------------------------
  if mod.generation == 1 then
    local adapter = import("adapters/gen1.lua").new(mod, util)
    engine:setAdapter(adapter)
    -- Official RA-linked rules first (shown with RA's text when the
    -- catalog is installed), then this mod's own bonus achievements.
    local lib = import("rules/gen1_lib.lua")
    for _, rule in ipairs(import("rules/gen1_official.lua")(lib)) do
      engine:addRule(rule)
    end
    for _, rule in ipairs(import("rules/gen1.lua")) do
      rule.extra = true
      engine:addRule(rule)
    end
    -- Reference catalogs are optional files produced by
    -- tools/fetch_ra_catalog.py.  Missing files are normal.
    for _, game in ipairs({ "red", "blue", "yellow" }) do
      if mod:info("catalog/" .. game .. ".lua") then
        local ok, catalog = pcall(import, "catalog/" .. game .. ".lua")
        if ok and type(catalog) == "table" then
          registry:addCatalog(game, catalog)
        else
          mod.log:warn("catalog/%s.lua failed to load: %s", game, tostring(catalog))
        end
      end
    end
    if mod:info("catalog/links.lua") then
      local ok, links = pcall(import, "catalog/links.lua")
      if ok and type(links) == "table" then registry:addLinks(links) end
    end
  end

  -- ----------------------------------------------------------------
  -- Public API.  Whatever sits in mod.exports when this function returns
  -- is what other mods get from mod.find("recomp_achievements").exports.
  -- ----------------------------------------------------------------
  Api.install(mod, engine, util, Share)

  -- ----------------------------------------------------------------
  -- Engine lifecycle.  See core/engine.lua for what each one does.
  -- ----------------------------------------------------------------
  engine:wire()

  -- ----------------------------------------------------------------
  -- UI: the START menu row, the browser screen and toasts.
  -- ----------------------------------------------------------------
  Browser.install(mod, engine, util, Text, Share)
  toast:install()
end
