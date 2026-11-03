-- main.lua
-- Entry point for Recomp Achievements. Gen1Recomp runs this file in the mod
-- sandbox and passes in `mod`, the API 3 object (src/mods/Loader.lua:_api).
-- Everything is wired here, top to bottom, so it doubles as a map of the mod:
--
--   core/util.lua      small helpers (copy, clamp, string checks)
--   core/ledger.lua    the save bucket: what's unlocked or in progress
--   core/registry.lua  achievement definitions known this session
--   core/engine.lua    the one award path every unlock goes through
--   core/api.lua       the public exports other mods call
--   adapters/gen*.lua  read each generation's save into plain "facts"
--   rules/gen*.lua     our own detectors, checked by this mod, not RA
--   catalog/*.lua      optional RA reference text (developer import)
--   ui/text.lua        font-safe text and status marks
--   ui/toast.lua       unlock popups, drawn on the render.hud hook
--   ui/browser.lua     the ACHIEVEMENTS screen opened from START
--
-- Definitions are rebuilt from code each session; records live in the save.
-- Nothing saved is ever a function, so a save still loads without this mod.
-- ------------------

return function(mod)
  -- ------------------ import
  -- Loads one of our own files. require("mods.<id>.file") would go through
  -- the engine's global require; mod:read plus load keeps the file in our
  -- sandbox and works whatever folder name the mod is installed under.
  -- Results are cached like require.
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
  local Chime    = import("ui/chime.lua")
  local Modern   = import("ui/modern.lua")
  local Native3  = import("ui/native3.lua")
  local Share    = import("ui/share.lua")

  -- ------------------ options
  -- These live in mod.options, shared across saves, because they're
  -- preferences, not progress.
  mod.options:define({
    -- Opens the menu from the Mods manager. The options screen has no
    -- buttons, so this is a one-choice row; any press fires
    -- mod.options_changed (see Browser.install).
    { key = "openMenu", type = "choice", label = "OPEN TROPHIES", default = "go",
      choices = { { "PRESS A", "go" } } },
    -- Turn off when another mod replaces the START menu.
    { key = "startMenuEntry", type = "toggle", label = "START MENU ENTRY", default = true },
    { key = "toasts", type = "toggle", label = "UNLOCK POPUPS", default = true },
    { key = "popupStyle", type = "choice", label = "POPUP STYLE", default = "modern",
      choices = { { "MODERN", "modern" }, { "CORNER", "corner" }, { "CLASSIC GB", "classic" } } },
    { key = "progressPopups", type = "toggle", label = "PROGRESS POPUPS", default = true },
    { key = "unlockSound", type = "toggle", label = "UNLOCK SOUND", default = true },
    { key = "extras", type = "toggle", label = "BONUS ACHIEVEMENTS", default = true },
    { key = "showHidden", type = "toggle", label = "REVEAL HIDDEN", default = false },
    { key = "showReference", type = "toggle", label = "SHOW RA REFERENCE", default = false },
    { key = "menuTheme", type = "choice", label = "THEME", default = "gameboy",
      choices = { { "GAME BOY", "gameboy" }, { "GRUVBOX DARK", "gruvbox_dark" },
                  { "GRUVBOX LIGHT", "gruvbox_light" }, { "NORD", "nord" }, { "MIDNIGHT", "midnight" } } },
    { key = "menuSize", type = "choice", label = "MENU SIZE", default = "full",
      choices = { { "FULL SCREEN", "full" }, { "GAME AREA", "game" } } },
    { key = "classicMenu", type = "toggle", label = "CLASSIC MENU", default = false },
    { key = "debug", type = "toggle", label = "DEBUG LOG", default = false },
  })

  local ledger = Ledger.new(mod, util)
  local registry = Registry.new(util)
  local toast = Toast.new(mod, util, Text, Chime.new(mod))
  toast.Modern = Modern
  local engine = Engine.new({
    mod = mod, util = util, ledger = ledger, registry = registry, toast = toast,
  })
  toast.gameOf = function() return engine.game end -- popup accent colour

  -- ------------------ built-in content
  -- Each generation gets an adapter (save to facts), its RA-list rules,
  -- its bonus rules and the optional RA catalogs.
  -- rules/common.lua applies to every generation.
  local function addRules(list, extra)
    for _, rule in ipairs(list) do
      if extra then rule.extra = true end
      engine:addRule(rule)
    end
  end
  local function loadCatalogs(games)
    -- Catalogs come from tools/fetch_ra_catalog.py and are optional,
    -- so a missing file is normal.
    for _, game in ipairs(games) do
      if mod:info("catalog/" .. game .. ".lua") then
        local ok, catalog = pcall(import, "catalog/" .. game .. ".lua")
        if ok and type(catalog) == "table" then
          registry:addCatalog(game, catalog)
        else
          mod.log:warn("catalog/%s.lua failed to load: %s", game, tostring(catalog))
        end
      end
    end
  end

  local supported = true
  if mod.generation == 1 then
    engine:setAdapter(import("adapters/gen1.lua").new(mod, util))
    -- RA-linked rules first (they show RA's text when the catalog is
    -- installed), then this mod's own bonus achievements.
    addRules(import("rules/gen1_official.lua")(import("rules/gen1_lib.lua")))
    addRules(import("rules/gen1.lua"), true)
    loadCatalogs({ "red", "blue", "yellow" })
  elseif mod.generation == 2 then
    engine:setAdapter(import("adapters/gen2.lua").new(mod, util, function(v) return import("data/gen2_" .. v .. ".lua") end))
    if mod:info("rules/gen2_official.lua") then
      addRules(import("rules/gen2_official.lua")(import("rules/gen2_lib.lua")))
    end
    addRules(import("rules/gen2.lua"), true)
    loadCatalogs({ "gold", "silver", "crystal" })
  elseif mod.generation == 3 then
    -- FireRed, LeafGreen, Emerald, Ruby and Sapphire.
    engine:setAdapter(import("adapters/gen3.lua").new(mod, util, function(f) return import("data/gen3_" .. f .. ".lua") end))
    if mod:info("rules/gen3_official.lua") then
      addRules(import("rules/gen3_official.lua")(import("rules/gen3_lib.lua")))
    end
    if mod:info("rules/gen3_emerald.lua") then
      addRules(import("rules/gen3_emerald.lua")(import("rules/gen3_lib.lua")))
    end
    if mod:info("rules/gen3_rs.lua") then
      addRules(import("rules/gen3_rs.lua")(import("rules/gen3_lib.lua")))
    end
    if mod:info("rules/gen3.lua") then addRules(import("rules/gen3.lua"), true) end
    loadCatalogs({ "firered", "leafgreen", "emerald", "ruby", "sapphire" })
  else
    supported = false
    mod.log:info("this generation isn't supported yet; achievements stay off")
  end
  if supported then
    addRules(import("rules/common.lua"), true)
    if mod:info("catalog/links.lua") then
      local ok, links = pcall(import, "catalog/links.lua")
      if ok and type(links) == "table" then registry:addLinks(links) end
    end
  end

  -- ------------------ public API
  -- Whatever is in mod.exports when this returns is what other mods get
  -- from mod.find("recomp_achievements").exports.
  Api.install(mod, engine, util, Share)

  -- ------------------ engine events
  -- Save, battle and frame hooks; core/engine.lua explains each one.
  engine:wire()

  -- ------------------ UI
  -- The START menu row, the achievements screen and the popups.
  Browser.install(mod, engine, util, Text, Share, Modern, Native3)
  toast:install()
end
