-- tests/run.lua
-- ==================================================================
-- End-to-end tests for Recomp Achievements + the sandbox provider,
-- running inside the real Gen1Recomp 0.3.97 mod loader (see harness.lua).
--
--   luajit tests/run.lua            (from the project folder)
--   ENGINE=/path/to/unzipped/gen1recomp-0.3.97.love luajit tests/run.lua
--
-- Each test is a short story: set up a save, do something a player would
-- do, check what the framework says through its PUBLIC API.
-- ==================================================================

local H = dofile((os.getenv("PROJECT") or ".") .. "/tests/harness.lua")

local passed, failed, current = 0, 0, ""
local function check(cond, message)
  if cond then passed = passed + 1
  else
    failed = failed + 1
    print(("  FAIL [%s] %s"):format(current, message))
  end
end
local function eq(a, b, message)
  check(a == b, ("%s (expected %s, got %s)"):format(message, tostring(b), tostring(a)))
end
local function test(name, fn)
  current = name
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    failed = failed + 1
    print(("  ERROR [%s] %s"):format(name, err))
  end
  print((ok and "ok   " or "BAD  ") .. name)
end

local BOTH = { "recomp_achievements", "achievement_sandbox" }
local function ach(env) return env:exports("recomp_achievements") end
local function ledgerOf(save)
  return save.modData and save.modData.recomp_achievements
    and save.modData.recomp_achievements.ledger
end

-- ------------------------------------------------------------------
test("both mods load in dependency order with no errors", function()
  local env = H.boot(BOTH)
  check(env.ok, "loader:load returned false: " .. table.concat(env.loader.errors, "; "))
  eq(env.loader.order[1], "recomp_achievements", "framework loads first")
  eq(env.loader.order[2], "achievement_sandbox", "provider loads second")
  eq(ach(env).apiVersion, "1.2.0", "api version")
  check(ach(env).supports("progress"), "supports progress")
  check(not ach(env).supports("leaderboards"), "unknown capability is false")
end)

test("START menu gets TROPHIES right before OPTION", function()
  local env = H.boot(BOTH)
  local items = env:startMenu()
  local at
  for i, item in ipairs(items) do if (item.label == "TROPHIES" or item.label == "TROPHY") then at = i end end
  check(at ~= nil, "row present")
  eq(items[at + 1] and items[at + 1].label, "OPTION", "row sits before OPTION")
end)

test("the title-screen skeleton save is ignored", function()
  local env = H.boot(BOTH)
  eq(ach(env).currentGame(), nil, "not attached at the title screen")
  check(ledgerOf(env.game.save) == nil, "skeleton save left untouched")
  env:hud()
  check(not H.screenHas("ACHIEVEMENT!"), "no popup on the title screen")
end)

test("nothing can unlock before a save is attached", function()
  local env = H.boot(BOTH)
  local handle = ach(env).connect("probe_mod")
  handle:register({ id = "x", title = "X" })
  local ok, code = handle:unlock("x")
  eq(ok, nil, "unlock refused")
  eq(code, "no_save", "error code")
  eq(ach(env).currentGame(), nil, "no current game")
end)

test("new game: provider ready-unlock lands in the save bucket and pops a toast", function()
  local env = H.boot(BOTH)
  env:newGame()
  eq(ach(env).currentGame(), "red", "attached to red")
  check(ach(env).isUnlocked("mod:achievement_sandbox:hello"), "hello unlocked")
  local ledger = ledgerOf(env.game.save)
  check(ledger and ledger.unlocked["mod:achievement_sandbox:hello"], "record is inside save.modData")
  eq(ledger.schema, 1, "schema stamped")
  local screen = env:hud()
  check(H.screenHas("ACHIEVEMENT!"), "toast heading drawn: " .. table.concat(screen, " | "))
  check(H.screenHas("Hello, Framework"), "toast title drawn")
end)

test("state rules wait for the next frame, then unlock once", function()
  local env = H.boot(BOTH)
  env:newGame()
  env:setFlag("EVENT_GOT_STARTER")
  check(not ach(env).isUnlocked("core:first_partner"), "not yet -- evaluation is deferred")
  env:frame()
  check(ach(env).isUnlocked("core:first_partner"), "unlocked after a frame")
  local count = 0
  env.loader.events:on("mod.recomp_achievements.unlocked", function() count = count + 1 end)
  env:setFlag("EVENT_GOT_POKEDEX"); env:frame(); env:frame()
  eq(count, 1, "exactly one unlocked event for the official Pokedex entry (no repeats)")
end)

test("badges unlock and feed the 8-badge progress goal", function()
  local env = H.boot(BOTH)
  env:newGame()
  env.game.save.inventory.BOULDERBADGE = 1
  env.game.save.inventory.CASCADEBADGE = 1
  env:setFlag("EVENT_BEAT_MISTY")
  env:frame()
  check(ach(env).isUnlocked("core:off_boulderbadge"), "boulder")
  check(ach(env).isUnlocked("core:off_cascadebadge"), "cascade")
  local row = ach(env).get("core:all_badges")
  eq(row.progress, 2, "badge case progress")
  eq(row.goal, 8, "badge case goal")
end)

test("pokedex thresholds use owned count", function()
  local env = H.boot(BOTH)
  env:newGame()
  local names = { "BULBASAUR", "IVYSAUR", "VENUSAUR", "CHARMANDER", "CHARMELEON",
    "CHARIZARD", "SQUIRTLE", "WARTORTLE", "BLASTOISE", "CATERPIE", "METAPOD", "BUTTERFREE" }
  for _, n in ipairs(names) do env.game.save.pokedex.owned[n] = true end
  env:emit("pokemon.caught", { species = "BUTTERFREE", isNew = true })
  env:frame()
  check(ach(env).isUnlocked("core:dex_10"), "dex 10")
  eq(ach(env).get("core:dex_50").progress, 12, "dex 50 progress")
  check(ach(env).isUnlocked("core:first_catch"), "first catch (event rule)")
end)

test("trainer-win counter counts trainer wins only", function()
  local env = H.boot(BOTH)
  env:newGame()
  for _ = 1, 3 do
    env:emit("battle.started", { kind = "trainer", trainerId = "BUG_CATCHER" })
    env:emit("battle.ended", { result = "win" })
  end
  env:emit("battle.started", { kind = "wild", species = "PIDGEY" })
  env:emit("battle.ended", { result = "win" })
  env:emit("battle.started", { kind = "trainer" })
  env:emit("battle.ended", { result = "lose" })
  eq(ach(env).get("core:trainer_wins").progress, 3, "three trainer wins counted")
end)

test("Save Sync round trip: device B sees everything, no repeat popups", function()
  local a = H.boot(BOTH)
  a:newGame()
  a.game.save.inventory.BOULDERBADGE = 1
  a:setFlag("EVENT_GOT_STARTER"); a:frame()
  for _ = 1, 7 do a:emit("world.stepped", { mapId = "ROUTE_1" }) end
  local blob = a:writeBlob()

  local b = H.boot(BOTH)          -- a second install = a second device
  b:loadBlob(blob)
  check(ach(b).isUnlocked("core:off_boulderbadge"), "boulder synced")
  check(ach(b).isUnlocked("core:first_partner"), "first partner synced")
  check(ach(b).isUnlocked("mod:achievement_sandbox:hello"), "provider unlock synced")
  eq(ach(b).get("mod:achievement_sandbox:walker").progress, 7, "provider progress synced")
  b:hud()
  check(not H.screenHas("ACHIEVEMENT!") and not H.screenHas("WELCOME BACK"),
    "nothing re-awarded on load, so no popup")

  -- B earns more and syncs back to A
  b.game.save.inventory.CASCADEBADGE = 1
  b:setFlag("EVENT_BEAT_MISTY"); b:frame()
  a:loadBlob(b:writeBlob())
  check(ach(a).isUnlocked("core:off_cascadebadge"), "B's unlock came back to A")
end)

test("loading an older save rolls achievements back with it", function()
  local env = H.boot(BOTH)
  env:newGame()
  local before = env:writeBlob()
  env.game.save.inventory.BOULDERBADGE = 1
  env:setFlag("EVENT_BEAT_BROCK"); env:frame()
  check(ach(env).isUnlocked("core:off_boulderbadge"), "earned (unsaved)")
  env:loadBlob(before)
  check(not ach(env).isUnlocked("core:off_boulderbadge"), "rolled back with the older save")
end)

test("old save without a ledger is backfilled quietly with one summary popup", function()
  -- framework only: the sandbox's own load-time unlocks would add popups
  local env = H.boot({ "recomp_achievements" })
  local old = H.newSave("red")
  old.modData = nil -- predates the mod entirely
  old.flags.EVENT_GOT_STARTER = true
  old.flags.EVENT_GOT_POKEDEX = true
  old.flags.EVENT_BEAT_CHAMPION_RIVAL = true
  for _, b in ipairs({ "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE" }) do old.inventory[b] = 1 end
  local SaveSerializer = require("src.core.SaveSerializer")
  env:loadBlob(SaveSerializer.encode(old))
  check(ach(env).isUnlocked("core:off_champion"), "champion backfilled")
  eq(ach(env).get("core:off_champion").how, "backfill", "marked as backfill")
  check(not ach(env).isUnlocked("core:first_catch"), "event-only rules are NOT backfilled")
  env:hud()
  check(H.screenHas("WELCOME BACK"), "single summary toast")
  H.advance(10); env:hud()
  check(not H.screenHas("ACHIEVEMENT!"), "no burst of individual toasts afterwards")
end)

test("provider missing on the other device: records archived, not lost", function()
  local a = H.boot(BOTH)
  a:newGame()
  local blob = a:writeBlob()

  local b = H.boot({ "recomp_achievements" }) -- no sandbox here
  b:loadBlob(blob)
  local row = ach(b).get("mod:achievement_sandbox:hello")
  check(row and row.archived, "shown as archived")
  check(row and row.unlocked, "still unlocked")
  eq(row and row.title, "Hello, Framework", "last-known title kept")
  local totals = ach(b).totals()
  eq(totals.archived, 1, "counted as archived")
  local earned = totals.earned
  for _, r in ipairs(ach(b).list({ source = "mod:achievement_sandbox" })) do
    check(r.archived, "no live sandbox definitions on B")
  end
  check(earned == 0, "archived records don't inflate earned totals")

  -- B saves (record must survive), A loads it back with the provider present
  a:loadBlob(b:writeBlob())
  local back = ach(a).get("mod:achievement_sandbox:hello")
  check(back and back.unlocked and not back.archived, "reattached when provider is back")
end)

test("save stays intact when the mod is uninstalled entirely", function()
  local a = H.boot(BOTH)
  a:newGame()
  a:setFlag("EVENT_GOT_STARTER"); a:frame()
  local blob = a:writeBlob()
  local plain = H.boot({}) -- vanilla install
  plain:loadBlob(blob)
  local blob2 = plain:writeBlob()
  local again = H.boot(BOTH)
  again:loadBlob(blob2)
  check(ach(again).isUnlocked("core:first_partner"), "ledger rode through a mod-free install")
end)

test("provider API contract", function()
  local env = H.boot(BOTH)
  env:newGame()
  local api = ach(env)
  local p = api.connect("probe_mod", { name = "Probe" })
  check(p ~= nil, "connect")
  check(api.connect("probe_mod") == p, "connect is idempotent")
  local ok, code = api.connect("core")
  eq(code, "invalid_provider", "'core' is reserved")
  ok, code = api.connect("Bad Id!")
  eq(code, "invalid_provider", "provider id validated")

  check(p:register({ id = "one", title = "One", points = 3 }), "register")
  check(p:register({ id = "one", title = "One", points = 3 }), "identical re-register ok")
  ok, code = p:register({ id = "one", title = "Different", points = 3 })
  eq(code, "duplicate_id", "conflicting re-register refused")
  eq(api.get("mod:probe_mod:one").title, "One", "original kept")
  ok, code = p:register({ id = "UPPER", title = "x" }); eq(code, "invalid_id", "bad id")
  ok, code = p:register({ id = "t", title = string.rep("x", 40) }); eq(code, "invalid_title", "long title")
  ok, code = p:register({ id = "g", title = "G", goal = 0 }); eq(code, "invalid_goal", "goal >= 1")
  ok, code = p:register({ id = "v", title = "V", games = { "pong" } }); eq(code, "invalid_games", "games checked")

  ok, code = p:unlock("nope"); eq(code, "unknown_id", "unknown id")
  check(p:unlock("one"), "unlock")
  ok, code = p:unlock("one"); eq(code, "already_unlocked", "second unlock refused")
  ok, code = p:unlock("core:off_champion"); eq(code, "invalid_id", "cannot reach outside namespace")

  check(p:register({ id = "count", title = "Count", goal = 10 }), "register goal")
  check(p:setProgress("count", 4), "set")
  check(p:addProgress("count", 3), "add")
  eq(p:getProgress("count"), 7, "progress 7")
  check(p:setProgress("count", 2), "absolute set can lower")
  eq(p:getProgress("count"), 2, "progress 2")
  check(p:setProgress("count", 999), "over goal clamps and awards")
  check(p:isUnlocked("count"), "unlocked at goal")
  ok, code = p:setProgress("one", 1); eq(code, "already_unlocked", "progress on unlocked")
  check(p:register({ id = "plain", title = "Plain" }), "no goal")
  ok, code = p:setProgress("plain", 1); eq(code, "no_goal", "progress needs a goal")
  ok, code = p:addProgress("count2", 1); eq(code, "unknown_id", "unknown id on addProgress")
  ok, code = p:addProgress("count", -1); eq(code, "already_unlocked", "unlocked checked first")
  check(p:register({ id = "neg", title = "Neg", goal = 5 }), "register neg")
  ok, code = p:addProgress("neg", -1); eq(code, "invalid_value", "negative increment refused")

  check(p:register({ id = "yel", title = "Y", games = { "yellow" } }), "yellow only")
  ok, code = p:unlock("yel"); eq(code, "wrong_game", "not on red")
  local listed = false
  for _, r in ipairs(api.list()) do if r.key == "mod:probe_mod:yel" then listed = true end end
  check(not listed, "other-game definitions are not listed")

  -- returned rows are copies
  local row = api.get("mod:probe_mod:one")
  row.unlocked = false
  check(api.isUnlocked("mod:probe_mod:one"), "mutating a returned row changes nothing")
  local writeOk = pcall(function() p.unlock = nil end)
  check(not writeOk, "handle is read-only")

  -- two providers with the same local id stay separate
  local q = api.connect("other_mod")
  check(q:register({ id = "one", title = "Other One" }), "same local id, other provider")
  check(not q:isUnlocked("one"), "separate namespaces")
end)

test("rate limit stops runaway providers", function()
  local env = H.boot(BOTH)
  env:newGame()
  local p = ach(env).connect("spammy")
  p:register({ id = "c", title = "C", goal = 1000000 })
  local refused
  for i = 1, 200 do
    local ok, code = p:addProgress("c", 1)
    if not ok then refused = code; break end
  end
  eq(refused, "rate_limited", "refused after the per-second budget")
  H.advance(1.1)
  check(p:addProgress("c", 1), "allowed again a second later")
end)

test("malformed ledger records are quarantined, not fatal", function()
  local env = H.boot(BOTH)
  local save = H.newSave("red")
  save.modData = { recomp_achievements = { ledger = {
    schema = 1, game = "red",
    unlocked = { ["core:first_partner"] = { at = 1 }, ["garbage key"] = { at = 2 },
                 ["core:off_pokedex"] = "not a table" },
    progress = { ["core:dex_50"] = "lots" },
  } } }
  local SaveSerializer = require("src.core.SaveSerializer")
  env:loadBlob(SaveSerializer.encode(save))
  check(ach(env).isUnlocked("core:first_partner"), "good record kept")
  local ledger = ledgerOf(env.game.save)
  check(ledger.quarantine["garbage key"] ~= nil, "bad key quarantined")
  check(ledger.quarantine["core:off_pokedex"] == nil and ledger.unlocked["core:off_pokedex"] == nil
    or ledger.quarantine["core:off_pokedex"] ~= nil, "non-table record moved")
  eq(ach(env).get("core:dex_50").progress, 0, "bad progress dropped")
end)

test("checkpoint restore drops queued popups", function()
  local env = H.boot(BOTH)
  env:newGame()
  env:emit("checkpoint.restored", { kind = "battle" })
  env:hud()
  check(not H.screenHas("ACHIEVEMENT!"), "queue cleared")
end)

test("browser: open from START, filter, details, hidden, close", function()
  local env = H.boot(BOTH)
  env:newGame()
  env.game.save.inventory.BOULDERBADGE = 1
  env:setFlag("EVENT_BEAT_BROCK"); env:frame()
  local function open()
    for _, item in ipairs(env:startMenu()) do
      if (item.label == "TROPHIES" or item.label == "TROPHY") then item.onSelect() end
    end
  end
  open()
  local screen = env.game.stack:top()
  check(screen ~= nil and screen.isMenu and screen.isOpaque, "opaque screen pushed")
  local lines = env:draw()
  local t = ach(env).totals()
  check(H.screenHas(("^%d/%d"):format(t.earned, t.total)), "header count: " .. (lines[1] or ""))
  check(H.screenHas("ALL"), "filter label")

  env:press("right"); env:draw()
  check(H.screenHas("EARNED"), "filter moved to EARNED")
  check(H.screenHas("Rock%-Solid"), "official title of the earned badge shown")
  env:press("a"); env:draw()
  check(H.screenHas("Defeat Brock"), "official description")
  check(H.screenHas("FROM THE RA LIST"), "origin line")
  check(H.screenHas("LOCAL ONLY"), "local-only label")
  env:press("right"); env:draw()
  check(H.screenHas("ABOUT"), "about page")
  check(H.screenHas("RA game 724") and H.screenHas("achievement 4401"), "RA ids on the about page")
  check(H.screenHas("NOT SENT TO RA"), "not-sent label")
  env:press("b"); env:draw()
  check(H.screenHas("EARNED"), "back to list")

  -- BONUS filter holds this mod's own achievements, hidden ones masked
  for _ = 1, 5 do env:press("right") end
  env:draw()
  check(H.screenHas("BONUS"), "bonus filter")
  local hidden = false
  for _ = 1, 20 do
    if H.screenHas("%?%?%?") then hidden = true break end
    env:press("down"); env:draw()
  end
  check(hidden, "hidden bonus achievement masked")
  check(not H.screenHas("Genetic Showdown"), "hidden title not leaked")
  env:press("b")
  check(env.game.stack:top() == nil, "closed")
end)

test("browser: long titles scroll on the selected row; SELECT then RIGHT shows credits", function()
  local Browser = dofile(H.PROJECT .. "/recomp_achievements/ui/browser.lua")
  local Text = dofile(H.PROJECT .. "/recomp_achievements/ui/text.lua")
  eq(Browser.marquee(Text, "Short", 16, 99), "Short", "short titles never move")
  eq(Browser.marquee(Text, "Rock-Solid Boulder Badge", 16, 0), "Rock-Solid Bould", "holds at the start")
  eq(Browser.marquee(Text, "Rock-Solid Boulder Badge", 16, 3.5), "Boulder Badge"
    and Browser.marquee(Text, "Rock-Solid Boulder Badge", 16, 3.5), "lid Boulder Badg", "scrolls")
  local env = H.boot(BOTH)
  env:newGame()
  for _, item in ipairs(env:startMenu()) do
    if (item.label == "TROPHIES" or item.label == "TROPHY") then item.onSelect() end
  end
  env:press("select"); env:press("right"); env:draw()
  check(H.screenHas("RetroAchievements"), "credits page")
  check(H.screenHas("Nothing"), "local-only statement")
  env:press("b"); env:draw()
  check(H.screenHas("ALL"), "back to the list")
end)

test("browser with no save shows a hint instead of crashing", function()
  local env = H.boot(BOTH)
  for _, item in ipairs(env:startMenu()) do
    if (item.label == "TROPHIES" or item.label == "TROPHY") then item.onSelect() end
  end
  env:draw()
  check(#env:draw() > 0, "renders something sane")
end)

test("framework alone, and provider alone, both load cleanly", function()
  local solo = H.boot({ "recomp_achievements" })
  check(solo.ok, "framework alone")
  local idle = H.boot({ "achievement_sandbox" })
  check(idle.ok, "provider alone")
  check(H.logHas("sandbox idle"), "provider says it is idle")
end)

test("yellow: version-filtered provider achievement appears and unlocks", function()
  local env = H.boot(BOTH, { version = "yellow" })
  env:newGame()
  eq(ach(env).currentGame(), "yellow", "yellow detected")
  check(ach(env).isUnlocked("mod:achievement_sandbox:yellow_guest"), "yellow guest")
end)

test("reference view lists RA entries; only tracked ones count", function()
  local env = H.boot(BOTH)
  env:newGame()
  local before = ach(env).totals().total
  env.loader.modOptions.recomp_achievements.showReference = true
  for _, item in ipairs(env:startMenu()) do
    if (item.label == "TROPHIES" or item.label == "TROPHY") then item.onSelect() end
  end
  for _ = 1, 9 do env:press("right") end
  env:draw()
  check(H.screenHas("RA REFERENCE"), "reference filter")
  check(H.screenHas("Free Points"), "catalog entry listed")
  eq(ach(env).totals().total, before, "catalog entries never change totals")
  env:press("a"); env:draw()
  check(H.screenHas("TRACKED HERE"), "tracked entry marked")
end)

test("catalog files are optional: without them rules show local text", function()
  local env = H.boot({ "recomp_achievements" }, { noCatalog = true })
  env:newGame()
  env.game.save.inventory.BOULDERBADGE = 1
  env:setFlag("EVENT_BEAT_BROCK"); env:frame()
  local row = ach(env).get("core:off_boulderbadge")
  check(row.unlocked, "still earned")
  eq(row.title, "Boulderbadge", "local fallback title")
  eq(row.official, false, "not shown as official without the catalog")
end)

-- ---------------------------------------------------------- leaderboard
local function loadShare()
  return assert(loadfile(H.PROJECT .. "/recomp_achievements/ui/share.lua"))()
end

test("check code matches tools/leaderboard_ingest.py", function()
  local Share = loadShare()
  -- values printed by tools/leaderboard_ingest.py check_code()
  eq(Share.code({ game = "red", name = "ASH", points = 120, earned = 20, saveId = "ABC123" }), "DHC0-HH32", "red")
  eq(Share.code({ game = "yellow", name = "red ", points = 0, earned = 0, saveId = "ZZZZZZ" }), "1F4B-5EVD", "spaces + case")
  eq(Share.code({ game = "blue", name = "Gary\226\153\130", points = 678, earned = 90, saveId = "0K3M9Q" }), "1AB3-YHC5", "utf-8 name")
  check(Share.code({ game = "red", name = "ASH", points = 121, earned = 20, saveId = "ABC123" }) ~= "DHC0-HH32", "points change the code")
end)

test("python parity holds for random cards", function()
  local Share = loadShare()
  local cards, lines = {}, {}
  local names = { "ASH", "red", "BLUE", "a b", "PIKA\226\153\128", "x" }
  for i = 1, 40 do
    local c = { game = ({ "red", "blue", "yellow" })[i % 3 + 1], name = names[i % #names + 1],
      points = (i * 37) % 700, earned = (i * 7) % 90, saveId = ("%06d"):format(i * 12345 % 999999) }
    cards[i] = c
    lines[i] = table.concat({ c.game, c.name, c.points, c.earned, c.saveId }, "\t")
  end
  local tmp = os.tmpname()
  local f = io.open(tmp, "wb"); f:write(table.concat(lines, "\n")); f:close()
  local py = io.popen(("python3 -c \"import sys;sys.path.insert(0,'%s/tools');import leaderboard_ingest as L\n"
    .. "for l in open('%s',encoding='utf-8').read().split('\\n'):\n g,n,p,e,s=l.split('\\t');print(L.check_code(g,n,int(p),int(e),s))\""):format(H.PROJECT, tmp))
  local i = 0
  for code in py:lines() do
    i = i + 1
    eq(code, Share.code(cards[i]), "card " .. i)
  end
  py:close(); os.remove(tmp)
  eq(i, 40, "python answered every card")
end)

test("official totals match the leaderboard's per-game maximums", function()
  local src = assert(io.open(H.PROJECT .. "/tools/leaderboard_ingest.py")):read("*a")
  for _, game in ipairs({ "red", "blue", "yellow" }) do
    local env = H.boot({ "recomp_achievements" }, { version = game })
    env:newGame()
    local t = ach(env).officialTotals and ach(env).officialTotals() or nil
    check(t ~= nil, "officialTotals exported")
    local mp, tot = src:match('"' .. game .. '":%s*{[^}]-"maxPoints":%s*(%d+),%s*"total":%s*(%d+)')
    eq(t.maxPoints, tonumber(mp), game .. " max points")
    eq(t.total, tonumber(tot), game .. " total")
    eq(t.earned, 0, game .. " nothing earned on a new game")
  end
end)

test("leaderboard card: official points only, stable save id, shown on SELECT", function()
  local env = H.boot(BOTH)
  env:newGame()
  env.game.save.inventory.BOULDERBADGE = 1
  env:setFlag("EVENT_BEAT_BROCK"); env:frame()
  local card = ach(env).leaderboardCard()
  check(card and card.points > 0 and card.earned >= 1, "badge counted")
  local t = ach(env).officialTotals()
  eq(card.points, t.points, "card uses official totals")
  check(ach(env).totals().points > card.points, "bonus/mod points are left out")
  check(card.saveId:match("^[0-9A-Z]+$") and #card.saveId == 6, "6-char save id")
  eq(ach(env).leaderboardCard().saveId, card.saveId, "save id is stable")
  eq(card.code, loadShare().code(card), "code over the shown fields")
  for _, item in ipairs(env:startMenu()) do
    if (item.label == "TROPHIES" or item.label == "TROPHY") then item.onSelect() end
  end
  env:press("select"); env:draw()
  check(H.screenHas("LEADERBOARD CARD"), "card page")
  check(H.screenHas(card.code:gsub("%-", "%%-")), "code shown")
  check(H.screenHas("SAVE ID " .. card.saveId), "save id shown")
  env:press("right"); env:draw()
  check(H.screenHas("RetroAchievements"), "credits on RIGHT")
  env:press("left"); env:draw()
  check(H.screenHas("LEADERBOARD CARD"), "back on LEFT")
end)

test("v2 check code (with play time) matches Python", function()
  local Share = loadShare()
  eq(Share.code({ game = "red", name = "ASH", points = 745, earned = 93, saveId = "ABC123", time = 754 }), "K8ZM-8GYP", "red 12:34")
  eq(Share.code({ game = "red", name = "ASH", points = 745, earned = 93, saveId = "ABC123", time = 0 }), "ESH4-99C6", "zero time is v2, not v1")
  eq(Share.code({ game = "blue", name = "Gary\226\153\130", points = 678, earned = 90, saveId = "0K3M9Q", time = 59999 }), "0A0S-ZNDV", "long time")
end)

test("card TIME is the play time when the score was reached", function()
  local env = H.boot({ "recomp_achievements" })
  env:newGame()
  env.game.save.playTime = 3600 + 125            -- 1:02 when the badge is earned
  env.game.save.inventory.BOULDERBADGE = 1
  env:setFlag("EVENT_BEAT_BROCK"); env:frame()
  local key = "core:off_boulderbadge"
  eq(ach(env).isUnlocked(key), true, "badge earned")
  env.game.save.playTime = 5 * 3600               -- playing on doesn't change it
  local card = ach(env).leaderboardCard()
  eq(card.time, 62, "minutes at the last official unlock")
  eq(card.code, loadShare().code(card), "v2 code over the shown fields")
  for _, item in ipairs(env:startMenu()) do
    if (item.label == "TROPHIES" or item.label == "TROPHY") then item.onSelect() end
  end
  env:press("select"); env:draw()
  check(H.screenHas("TIME    1:02"), "TIME line on the card")
  check(H.screenHas(card.code:gsub("%-", "%%-")), "code shown")
end)

test("a new game's card has 0:00 and old records fall back to the current time", function()
  local env = H.boot({ "recomp_achievements" })
  env:newGame()
  env.game.save.playTime = 600
  eq(ach(env).leaderboardCard().time, 0, "nothing earned yet")
  env.game.save.inventory.BOULDERBADGE = 1
  env:setFlag("EVENT_BEAT_BROCK"); env:frame()
  -- simulate a record written by 1.1.0 (no play time)
  local ledger = env.game.save.modData.recomp_achievements.ledger
  for _, rec in pairs(ledger.unlocked) do rec.pt = nil end
  env.game.save.playTime = 7200
  eq(ach(env).leaderboardCard().time, 120, "falls back to the play time now")
end)

-- ---------------------------------------------------------- unlock sound
local function clearSounds() for i = #H.sounds, 1, -1 do H.sounds[i] = nil end end
local function earnBadge(env)
  env.game.save.inventory.BOULDERBADGE = 1
  env:setFlag("EVENT_BEAT_BROCK"); env:frame()
end

test("unlock sound: the jingle is generated in range", function()
  local Chime = assert(loadfile(H.PROJECT .. "/recomp_achievements/ui/chime.lua"))()
  for kind, song in pairs(Chime.SONGS) do
    local s = Chime.render(song)
    check(#s > Chime.RATE * 0.5 and #s < Chime.RATE * 1.0, kind .. " is about half a second")
    local peak = 0
    for _, v in ipairs(s) do peak = math.max(peak, math.abs(v)) end
    check(peak > 0.3 and peak <= 1, kind .. " is audible and doesn't clip")
    eq(s[#s] == s[#s] and math.abs(s[#s]) < 0.05, true, kind .. " fades out")
  end
end)

test("unlock sound plays when the popup appears, at the game's SFX volume", function()
  local env = H.boot({ "recomp_achievements" })
  env:newGame()
  env:hud(); H.advance(5); env:hud(); clearSounds()
  env.game.save.options.sfxVol = 7
  earnBadge(env)
  eq(#H.sounds, 0, "nothing until the popup shows")
  env:hud()
  eq(#H.sounds, 1, "one sound with the popup")
  check(math.abs(H.sounds[1].volume - 0.45) < 1e-6, "full SFX VOL")
  env:hud(); eq(#H.sounds, 1, "not again on the next frame")
  H.advance(5); clearSounds()
  env.game.save.options.sfxVol = 3
  env.game.save.inventory.CASCADEBADGE = 1
  env:setFlag("EVENT_BEAT_MISTY"); env:frame(); env:hud()
  check(#H.sounds >= 1 and math.abs(H.sounds[1].volume - 0.45 * 3 / 7) < 1e-6, "scaled by SFX VOL")
end)

test("unlock sound respects its option, SFX VOL 0, and works without popups", function()
  local env = H.boot({ "recomp_achievements" })
  env.loader.modOptions.recomp_achievements.unlockSound = false
  env:newGame(); env:hud(); H.advance(5); clearSounds()
  earnBadge(env); env:hud()
  eq(#H.sounds, 0, "option off: silent")

  local env2 = H.boot({ "recomp_achievements" })
  env2:newGame(); env2:hud(); H.advance(5); clearSounds()
  env2.game.save.options.sfxVol = 0
  earnBadge(env2); env2:hud()
  eq(#H.sounds, 0, "SFX VOL 0: silent")

  local env3 = H.boot({ "recomp_achievements" })
  env3.loader.modOptions.recomp_achievements.toasts = false
  env3:newGame(); H.advance(5); clearSounds()
  earnBadge(env3)
  eq(#H.sounds, 1, "popups off: sound plays at the unlock")
end)

-- ---------------------------------------------------------- modern menu
local function openMenu(env)
  for _, item in ipairs(env:startMenu()) do
    if (item.label == "TROPHIES" or item.label == "TROPHY") then item.onSelect() end
  end
  local states = env.game.stack.states
  return states[#states]
end
local BIG = { gameX = 80, gameY = 0, gameWidth = 800, gameHeight = 720, scale = 5 }

test("modern menu is the default and draws at window resolution", function()
  local env = H.boot({ "recomp_achievements" }, { modern = true })
  env:newGame()
  env.game.save.inventory.BOULDERBADGE = 1
  env:setFlag("EVENT_BEAT_BROCK"); env:frame()
  local screen = openMenu(env)
  check(screen and screen.modern, "modern screen on top")
  env:hud(BIG)
  local txt = H.windowText()
  check(txt:find("Achievements", 1, true), "title")
  check(txt:find("Pokémon Red", 1, true), "game name")
  check(txt:find("All", 1, true) and txt:find("RA list", 1, true), "filter chips")
  check(not txt:find("OFFICIAL", 1, true), "no 'official' wording")
  local first = screen.state.list[1]
  check(first and txt:find(first.title:sub(1, 4), 1, true), "the first achievement row")
  check(txt:find("Earned", 1, true), "status text")
end)

test("modern menu: filters, A for how it's checked, SELECT for the card", function()
  local env = H.boot({ "recomp_achievements" }, { modern = true })
  env:newGame()
  env.game.save.inventory.BOULDERBADGE = 1
  env:setFlag("EVENT_BEAT_BROCK"); env:frame()
  local screen = openMenu(env)
  env:press("right"); env:hud(BIG)
  eq(screen.state.filter, 2, "RIGHT moves to the next filter")
  for _, row in ipairs(screen.state.list) do eq(row.unlocked, true, "earned filter shows earned rows") end
  env:press("a"); env:hud(BIG)
  check(H.windowText():find("How it's checked", 1, true), "A shows how it's checked")
  env:press("select"); env:hud(BIG)
  local card = ach(env).leaderboardCard()
  local txt = H.windowText()
  check(txt:find("Leaderboard card", 1, true), "card tab")
  check(txt:find(card.code, 1, true), "check code shown")
  check(txt:find(card.saveId, 1, true), "save id shown")
  env:press("right"); env:hud(BIG)
  check(H.windowText():find("unofficial", 1, true), "About page")
  env:press("b"); env:hud(BIG)
  eq(screen.state.modal, nil, "B closes the card")
  env:press("b")
  local states = env.game.stack.states
  check(states[#states] ~= screen, "B again closes the menu")
end)

test("modern menu fits Gen 2 and Gen 3 screen shapes and hides spoilers", function()
  local env = H.boot({ "recomp_achievements" }, { modern = true })
  env:newGame()
  openMenu(env)
  for _, vp in ipairs({
    { gameX = 0, gameY = 0, gameWidth = 960, gameHeight = 640, scale = 4 },   -- 240x160 (GBA)
    { gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144, scale = 1 },   -- tiny window
    { gameX = 100, gameY = 0, gameWidth = 1440, gameHeight = 1296, scale = 9 },
  }) do
    env:hud(vp)
    check(H.windowText():find("Achievements", 1, true), "draws at " .. vp.gameWidth .. "x" .. vp.gameHeight)
  end
  local Modern = assert(loadfile(H.PROJECT .. "/recomp_achievements/ui/modern.lua"))()
  local f = love.graphics.newFont(10)
  eq(Modern.ellipsize(f, "Short", 1000), "Short", "fits")
  check(f:getWidth(Modern.ellipsize(f, "A very long achievement title indeed", 60)) <= 60, "ellipsized to width")
  for game in pairs(Modern.GAME_NAMES) do check(Modern.ACCENTS[game], game .. " has an accent") end
end)

test("CLASSIC MENU option brings back the Game Boy menu", function()
  local env = H.boot({ "recomp_achievements" }, { modern = true })
  env.loader.modOptions.recomp_achievements.classicMenu = true
  env:newGame()
  local screen = openMenu(env)
  check(screen and not screen.modern, "classic screen")
  env:draw()
  check(H.screenHas("ALL"), "classic filter label")
end)

-- ---------------------------------------------------------- show and tell + themes
test("Show and Tell: opening the leaderboard card earns 1 bonus point", function()
  for _, modern in ipairs({ true, false }) do
    local env = H.boot({ "recomp_achievements" }, { modern = modern })
    env:newGame()
    local before = ach(env).officialTotals()
    eq(ach(env).isUnlocked("core:show_and_tell"), false, "locked at first")
    openMenu(env)
    env:press("select"); env:frame()
    eq(ach(env).isUnlocked("core:show_and_tell"), true, (modern and "modern" or "classic") .. " menu awards it")
    local row = ach(env).get("core:show_and_tell")
    eq(row.points, 1, "one point")
    eq(row.official, false, "not from the RA list")
    eq(ach(env).officialTotals().points, before.points, "leaderboard points unchanged")
  end
end)

test("Show and Tell follows the BONUS ACHIEVEMENTS option", function()
  local env = H.boot({ "recomp_achievements" }, { modern = true })
  env.loader.modOptions.recomp_achievements.extras = false
  env:newGame()
  openMenu(env)
  env:press("select"); env:frame()
  eq(ach(env).isUnlocked("core:show_and_tell"), false, "bonus off: not awarded")
end)

test("menu palettes: every theme is complete and the option switches it", function()
  local Modern = assert(loadfile(H.PROJECT .. "/recomp_achievements/ui/modern.lua"))()
  local keys = { "backdrop", "panel", "raised", "track", "border", "text", "muted", "faint",
                 "earned", "progress", "onAccent", "hues" }
  for _, name in ipairs(Modern.THEME_ORDER) do
    local theme = Modern.THEMES[name]
    for _, k in ipairs(keys) do check(theme[k] ~= nil, name .. " has " .. k) end
    for game, hue in pairs(Modern.GAME_HUE) do check(theme.hues[hue], name .. " has a " .. hue .. " for " .. game) end
  end
  eq(Modern.DEFAULT_THEME, "gameboy", "Game Boy palette by default")
  local env = H.boot({ "recomp_achievements" }, { modern = true })
  env:newGame()
  openMenu(env)
  for _, name in ipairs(Modern.THEME_ORDER) do
    env.loader.modOptions.recomp_achievements.menuTheme = name
    env:hud(BIG)
    check(H.windowText():find("Achievements", 1, true), name .. " draws")
  end
  env.loader.modOptions.recomp_achievements.menuTheme = "no_such_theme"
  env:hud(BIG)
  check(H.windowText():find("Achievements", 1, true), "unknown theme falls back")
end)

test("popup styles: modern banner, corner card and classic all draw", function()
  for _, style in ipairs({ "modern", "corner", "classic" }) do
    local env = H.boot({ "recomp_achievements" }, { modern = true })
    env.loader.modOptions.recomp_achievements.popupStyle = style
    env:newGame(); env:hud(BIG); H.advance(5)
    env.game.save.inventory.BOULDERBADGE = 1
    env:setFlag("EVENT_BEAT_BROCK"); env:frame()
    local title = ach(env).get("core:off_boulderbadge").title
    env:hud(BIG)
    if style == "classic" then
      check(H.screenHas("ACHIEVEMENT!"), "classic Game Boy box")
    else
      local txt = H.windowText()
      check(txt:find("Achievement unlocked", 1, true), style .. " heading")
      check(txt:find(title:sub(1, 5), 1, true), style .. " shows the title")
      check(txt:find("+", 1, true), style .. " shows points")
    end
  end
end)

test("modern menu fills the window (landscape and portrait) or just the game area", function()
  local env = H.boot({ "recomp_achievements" }, { modern = true })
  env:newGame()
  openMenu(env)
  local Modern = assert(loadfile(H.PROJECT .. "/recomp_achievements/ui/modern.lua"))()
  local land = { width = 1280, height = 720, gameX = 240, gameY = 0, gameWidth = 800, gameHeight = 720 }
  local x, y, w, h = Modern.region(land)
  eq(w, 1280, "full window width"); eq(h, 720, "full window height"); eq(x, 0, "from the left edge")
  x, y, w, h = Modern.region(land, "game")
  eq(w, 800, "game area width"); eq(x, 240, "game area x")
  local phone = { width = 540, height = 1170, gameX = 0, gameY = 0, gameWidth = 540, gameHeight = 486 }
  check(Modern.deckHeight(540, 1170) > 200 and Modern.deckHeight(540, 1170) < 500, "pad deck reserved in portrait")
  check(Modern.unit(phone, 540, 1170) <= 540 / 150, "text fits the narrow screen")
  for _, vp in ipairs({ land, phone, { width = 3840, height = 2160, gameX = 720, gameY = 0, gameWidth = 2400, gameHeight = 2160 } }) do
    env:hud(vp)
    check(H.windowText():find("Achievements", 1, true), ("draws at %dx%d"):format(vp.width, vp.height))
  end
  env.loader.modOptions.recomp_achievements.menuSize = "game"
  env:hud(land)
  check(H.windowText():find("Achievements", 1, true), "game-area mode draws")
end)

-- ---------------------------------------------------------- gen 2 adapter
test("Gen 2 adapter reads Gold/Silver/Crystal saves", function()
  local Gen2 = assert(loadfile(H.PROJECT .. "/recomp_achievements/adapters/gen2.lua"))()
  local save = {
    version = "crystal",
    player = { name = "KRIS", money = 3000, coins = 50,
               badges = { ZEPHYR = true, HIVE = true }, kantoBadges = { [1] = true } },
    inventory = { POTION = 2, BICYCLE = 1 }, pcItems = { POTION = 1 },
    pokedex = { caught = { CHIKORITA = true, PIDGEY = true }, seen = { CHIKORITA = true, PIDGEY = true, HOOTHOOT = true } },
    party = { { species = "BAYLEEF", level = 18 }, { species = "TOGEPI", isEgg = true, level = 5 } },
    boxes = { { { species = "PIDGEY", level = 100, shiny = true } } },
    unownDex = { "A", "B", "C" },
    hallOfFame = { count = 1 },
    playTime = { hours = 3, minutes = 4, seconds = 5 },
    events = { [151] = 4 }, -- flag 1210 = byte 151, bit 2
  }
  local mod = { game = { save = save }, world = nil }
  local a = Gen2.new(mod, {})
  eq(a:version(), "crystal", "version")
  eq(a:playTime(), 3 * 3600 + 4 * 60 + 5, "play time in seconds")
  local f = a:facts()
  eq(f.badgeCount(), 2, "johto badges by name")
  eq(f.kantoBadgeCount(), 1, "kanto badges by index (old saves)")
  eq(f.hasBadge("HIVE"), true, "hive badge")
  eq(f.itemCount("POTION"), 3, "bag + PC")
  eq(f.dexOwned(), 2, "caught"); eq(f.dexSeen(), 3, "seen")
  eq(f.highestLevel(), 100, "boxes count, eggs don't")
  eq(f.has("TOGEPI"), false, "eggs aren't owned yet")
  eq(f.shinyCount(), 1, "shiny in a box")
  eq(f.unownForms(), 3, "unown"); eq(f.hallOfFame(), 1, "hall of fame")
  eq(f.flag(1210), true, "saved flag bit decoded without a live world")
  eq(f.flag(1209), false, "neighbouring bit")
  eq(Gen2.new({ game = { save = { version = "red" } } }, {}):version(), nil, "not a Gen 2 save")
  -- battle de-duplication key: both copies of a battle report agree
  local core = { trainer = { classId = "FALKNER" } }
  local first, second = a:battleInfo({ battle = core }), a:battleInfo({ battle = { battle = core } })
  check(first.key == second.key, "same key for both reports")
  eq(first.trainerId, "FALKNER", "trainer from the battle")
  eq(second.trainerId, "FALKNER", "trainer through the battle screen")
end)

test("Gen 2 bonus rules load and check against facts", function()
  local rules = assert(loadfile(H.PROJECT .. "/recomp_achievements/rules/gen2.lua"))()
  local ids = {}
  for _, r in ipairs(rules) do
    check(not ids[r.id], "unique id " .. r.id); ids[r.id] = true
    check(r.id:match("^g2_"), r.id .. " is prefixed")
    check(#r.title <= 32, r.title .. " fits")
  end
  local f = { partySize = function() return 1 end, dexOwned = function() return 0 end,
              badgeCount = function() return 8 end, kantoBadgeCount = function() return 3 end }
  for _, r in ipairs(rules) do
    if r.id == "g2_first_partner" then eq(r.check(f), true, "partner") end
    if r.id == "g2_johto_badges" then eq(r.check(f), 8, "johto progress") end
    if r.id == "g2_sixteen_badges" then eq(r.check(f), 11, "sixteen progress") end
  end
end)

test("Gen 2 RA rules: every list entry linked once, every flag name real", function()
  local P = H.PROJECT .. "/recomp_achievements/"
  local rules = dofile(P .. "rules/gen2_official.lua")(dofile(P .. "rules/gen2_lib.lua"))
  local data, cats, linked = {}, {}, {}
  for _, g in ipairs({ "gold", "silver", "crystal" }) do
    data[g] = dofile(P .. "data/gen2_" .. g .. ".lua")
    cats[g] = dofile(P .. "catalog/" .. g .. ".lua")
    linked[g] = {}
  end
  local ids = {}
  for _, r in ipairs(rules) do
    check(not ids[r.id], "unique " .. r.id); ids[r.id] = true
    check(#r.title <= 32, "title fits " .. r.title)
    eq(r.official, true, r.id .. " is official")
    for g, raId in pairs(r.ra) do
      check(not linked[g][raId], g .. " " .. raId .. " linked once")
      linked[g][raId] = true
      if r.check then
        local asked = {}
        local f = setmetatable({}, { __index = function(_, k)
          if k == "flag" then return function(n) if type(n) == "string" then asked[n] = true end return false end end
          if k == "allFlags" or k == "countFlags" then
            return function(list) for _, x in ipairs(list) do asked[x] = true end return k == "countFlags" and 0 or false end
          end
          if k == "sweep" then return function() return 0, 10 end end
          if k == "party" then return function() return {} end end
          local bools = { owns = true, ownsWhere = true, hasItem = true, rivalNamed = true, traded = true,
                          hasBadge = true, engineFlag = true, hasType = true, isJohto = true, anyFlag = true }
          if bools[k] then return function() return false end end
          return function() return 0 end
        end })
        local ok, err = pcall(r.check, f)
        check(ok, r.id .. " check runs: " .. tostring(err))
        for n in pairs(asked) do check(data[g].flags[n] ~= nil, g .. " knows " .. n) end
      end
    end
  end
  for g, c in pairs(cats) do
    for _, e in ipairs(c.entries) do check(linked[g][e.id], g .. " entry " .. e.id .. " " .. e.title .. " has a rule") end
  end
end)

test("Gen 2 data: flag numbers match the engine's Gold table and New-Game flags are skipped", function()
  local P = H.PROJECT .. "/recomp_achievements/"
  local gold = dofile(P .. "data/gen2_gold.lua")
  eq(gold.flags.EVENT_BEAT_FALKNER, 1213, "Falkner")
  eq(gold.flags.EVENT_BEAT_WHITNEY, 1215, "Whitney")
  local crystal = dofile(P .. "data/gen2_crystal.lua")
  eq(crystal.flags.EVENT_BEAT_WHITNEY, 1215, "Crystal Whitney (from its generated scripts)")
  for _, row in ipairs(crystal.hidden) do
    check(row[2] ~= "EVENT_FOUND_MACHINE_PART_IN_CERULEAN_GYM", "machine part isn't a hidden-item row")
  end
  check(#crystal.trainers > 300 and #crystal.items > 150 and #crystal.hidden > 70, "lists are populated")
end)


-- ---------------------------------------------------------------- Gen 3
local function gen3Save(over)
  local save = {
    version = "leafgreen", name = "ELVIE",
    flags = {}, vars = {},
    dex = { caught = { [1] = true, [143] = true }, seen = { [1] = true, [143] = true, [16] = true } },
    party = { { species = 2, speciesId = 2, level = 16 } },
    storage = { boxes = { { wallpaper = 1, [1] = { species = 150, level = 70 } } }, items = { { id = 13, qty = 2 } } },
    bag = { pockets = { ITEMS = { { id = 13, qty = 3 } }, KEY_ITEMS = { { id = 361, qty = 1 } } } },
    gameStats = { [28] = 0 },
    playTime = { hours = 1, minutes = 2, seconds = 3 },
    engineOptions = { frlg = { battleStyle = 1 } },
  }
  for k, v in pairs(over or {}) do save[k] = v end
  return save
end

local function gen3Adapter(save)
  local P = H.PROJECT .. "/recomp_achievements/"
  local Gen3 = assert(loadfile(P .. "adapters/gen3.lua"))()
  return Gen3.new({ game = { save = save } }, {}, function(f) return dofile(P .. "data/gen3_" .. f .. ".lua") end)
end

test("Gen 3 adapter reads FireRed/LeafGreen saves", function()
  local save = gen3Save()
  local a = gen3Adapter(save)
  eq(a:version(), "leafgreen", "version")
  eq(a:playTime(), 3723, "play time")
  local d = a:data()
  save.flags[d.flags.FLAG_BADGE01_GET] = true
  save.flags[d.flags.TRAINER_LEADER_BROCK] = true
  local f = a:facts()
  eq(f.flag("FLAG_BADGE01_GET"), true, "flag by name")
  eq(f.flag(0x820), true, "flag by number (pret's FLAG_BADGE01_GET)")
  eq(f.flag("TRAINER_LEADER_BROCK"), true, "trainer flag by name")
  eq(f.badgeCount(), 1, "badges"); eq(f.hasBadge("BOULDER"), true, "boulder")
  eq(f.owns("SNORLAX"), true, "dex by species name"); eq(f.owns("MEW"), false, "not caught")
  eq(f.dexOwned(), 2, "caught"); eq(f.dexSeen(), 3, "seen")
  eq(f.party()[1].species, "IVYSAUR", "party species named")
  eq(f.has("MEWTWO"), true, "boxed mons count")
  eq(f.itemCount("POTION"), 5, "bag + PC")
  eq(f.hasItem("TEACHY_TV"), false, "no Teachy TV")
  eq(f.hasItem(d.itemNames[361]), true, "key item by name")
  eq(f.battleStyle(), "set", "battle style from the game's OPTION menu")
  eq(a:battleInfo({ trainerId = 414 }).trainerName, d.trainerIds[414], "trainer number -> name")
  eq(gen3Adapter({ version = "emerald" }):version(), "emerald", "Emerald")
  eq(gen3Adapter({ version = "ruby" }):version(), "ruby", "Ruby")
  eq(gen3Adapter({ version = "crystal" }):version(), nil, "not a Gen 3 save")
end)

test("Gen 3 data: flag numbers match the engine's own FireRed table", function()
  local d = dofile(H.PROJECT .. "/recomp_achievements/data/gen3_frlg.lua")
  eq(d.flags.FLAG_BADGE01_GET, 0x820, "badge 1")
  eq(d.flags.TRAINER_LEADER_BROCK, d.trainerFlagsStart + 414, "trainer flags follow TRAINER_FLAGS_START")
  local path = H.GAMEDATA .. "/firered/data/generated/gba/flags_table.lua"
  local chunk = loadfile(path)
  if chunk then
    local ft, n = chunk(), 0
    for name, id in pairs(d.flags) do
      if name:match("^FLAG_") and ft.FLAGS[name] ~= nil then
        n = n + 1
        if ft.FLAGS[name] ~= id then check(false, name .. " " .. id .. " vs engine " .. ft.FLAGS[name]) end
      end
    end
    check(n > 1000, "compared " .. n .. " flags")
  end
  check(#d.trainers > 400 and #d.items > 150 and #d.hidden > 150 and #d.rematches > 200, "lists are populated")
  for i = 1, 8 do check(#d.gymTrainers[i] >= 1, "gym " .. i .. " trainers") end
end)

test("Gen 3 RA rules: every FireRed/LeafGreen entry linked once, every name real, checks run", function()
  local P = H.PROJECT .. "/recomp_achievements/"
  local rules = dofile(P .. "rules/gen3_official.lua")(dofile(P .. "rules/gen3_lib.lua"))
  local d = dofile(P .. "data/gen3_frlg.lua")
  local linked = { firered = {}, leafgreen = {} }
  local ids = {}
  local save = gen3Save({ dex = { caught = { [1] = true }, seen = {} },
                         bag = { pockets = {} }, storage = { boxes = {}, items = {} } })
  local f = gen3Adapter(save):facts()
  -- every name a rule asks the adapter about must exist in the data
  local asked = {}
  local function spy(name) return function(x, ...)
    if type(x) == "string" then asked[x] = name end
    if type(x) == "table" then for _, n in ipairs(x) do asked[n] = name end end
    return f[name](x, ...) end end
  local probe = setmetatable({ flag = spy("flag"), allFlags = spy("allFlags"), countFlags = spy("countFlags"),
    anyFlag = spy("anyFlag"), var = spy("var"), owns = spy("owns"), hasItem = spy("hasItem") }, { __index = f })
  for _, r in ipairs(rules) do
    check(not ids[r.id], "unique " .. r.id); ids[r.id] = true
    check(#r.title <= 32, "title fits " .. r.title)
    eq(r.official, true, r.id .. " is official")
    for g, raId in pairs(r.ra) do
      check(linked[g], r.id .. " links a FireRed/LeafGreen entry")
      check(not linked[g][raId], g .. " " .. raId .. " linked once")
      linked[g][raId] = true
    end
    if r.check then
      local ok, v = pcall(r.check, probe)
      check(ok, r.id .. " check runs: " .. tostring(v))
      check(v ~= true, r.id .. " isn't done on a 1-badge save")
    end
  end
  for n, how in pairs(asked) do
    if how == "var" then check(d.vars[n] ~= nil, "var " .. n)
    elseif how == "owns" then check(d.species[n] ~= nil, "species " .. n)
    elseif how == "hasItem" then check(d.itemIds[n] ~= nil, "item " .. n)
    else check(d.flags[n] ~= nil, "flag " .. n) end
  end
  local src = assert(io.open(H.PROJECT .. "/tools/leaderboard_ingest.py")):read("*a")
  for _, g in ipairs({ "firered", "leafgreen" }) do
    local c = dofile(P .. "catalog/" .. g .. ".lua")
    local pts = 0
    for _, e in ipairs(c.entries) do
      check(linked[g][e.id], g .. " entry " .. e.id .. " " .. e.title .. " has a rule")
      pts = pts + e.points
    end
    local mp, tot = src:match('"' .. g .. '":%s*{[^}]-"maxPoints":%s*(%d+),%s*"total":%s*(%d+)')
    eq(tonumber(mp), pts, g .. " leaderboard max points")
    eq(tonumber(tot), #c.entries, g .. " leaderboard total")
  end
end)

test("Gen 3 rules: areas, gym trainers, challenges and solo league runs", function()
  local P = H.PROJECT .. "/recomp_achievements/"
  local L = dofile(P .. "rules/gen3_lib.lua")
  local rules = {}
  for _, r in ipairs(dofile(P .. "rules/gen3_official.lua")(L)) do rules[r.id] = r end
  local save = gen3Save()
  local a = gen3Adapter(save)
  local d = a:data()
  local function facts() return a:facts() end
  -- an area: Viridian Forest trainers + item balls (not hidden items)
  local forest = rules.g3o_area_forest
  local pct = forest.check(facts())
  eq(pct, 0, "nothing done yet")
  for _, row in ipairs(d.trainers) do if row[3] == "ViridianForest" then save.flags[row[1]] = true end end
  pct = forest.check(facts())
  check(type(pct) == "number" and pct > 0 and pct < 100, "trainers alone are part of it: " .. tostring(pct))
  for _, row in ipairs(d.items) do if row[4] == "ViridianForest" then save.flags[row[1]] = true end end
  eq(forest.check(facts()), true, "trainers and item balls: done")
  -- gym trainers count only while the leader stands
  local pewter = rules.g3o_gymtrainers1
  eq(pewter.check(facts()), false, "Liam not beaten")
  save.flags[d.flags.TRAINER_CAMPER_LIAM] = true
  eq(pewter.check(facts()), true, "Liam beaten, Brock not yet")
  save.flags[d.flags.FLAG_DEFEATED_BROCK] = true
  eq(pewter.check(facts()), false, "after Brock the flag proves nothing")
  local ctx = { battle = { trainerId = "TRAINER_CAMPER_LIAM" } }
  local s = {}
  save.flags[d.flags.FLAG_DEFEATED_BROCK] = nil
  eq(pewter.on["battle.ended"](s, { result = "win" }, facts(), ctx), true, "a live win counts")
  -- FireRed challenge: SET style, two Pokemon at most, level 14 cap
  local brock = rules.g3o_challenge1
  local b = { trainerId = "TRAINER_LEADER_BROCK", style = "set", partyMaxAtStart = 12,
              partyAtStart = { { species = "IVYSAUR", level = 12 }, { species = "PIDGEY", level = 9 } } }
  save.party = { { species = 2, level = 13 } }
  eq(brock.test({ result = "win" }, facts(), { battle = b }), true, "within the rules")
  b.style = "shift"
  eq(brock.test({ result = "win" }, facts(), { battle = b }), false, "SHIFT style doesn't count")
  b.style = "set"; b.partyAtStart[3] = { species = "RATTATA", level = 5 }
  eq(brock.test({ result = "win" }, facts(), { battle = b }), false, "three Pokemon is too many")
  b.partyAtStart[3] = nil; save.party = { { species = 2, level = 15 } }
  eq(brock.test({ result = "win" }, facts(), { battle = b }), false, "levelled past the cap mid-fight")
  -- solo league: one Pokemon in the party for all five battles
  local solo = rules.g3o_solo1
  local st = {}
  solo.init(st)
  save.party = { { species = 6, level = 70 } }
  local order = { "TRAINER_ELITE_FOUR_LORELEI", "TRAINER_ELITE_FOUR_BRUNO", "TRAINER_ELITE_FOUR_AGATHA",
                  "TRAINER_ELITE_FOUR_LANCE", "TRAINER_CHAMPION_FIRST_SQUIRTLE" }
  local result
  for _, who in ipairs(order) do
    local c = { battle = { trainerId = who } }
    solo.on["battle.started"](st, {}, facts(), c)
    result = solo.on["battle.ended"](st, { result = "win" }, facts(), c)
  end
  eq(result, true, "five wins with one Pokemon")
  st = {}; solo.init(st)
  for i, who in ipairs(order) do
    save.party = i == 3 and { { species = 6, level = 70 }, { species = 3, level = 60 } } or { { species = 6, level = 70 } }
    local c = { battle = { trainerId = who } }
    solo.on["battle.started"](st, {}, facts(), c)
    result = solo.on["battle.ended"](st, { result = "win" }, facts(), c)
  end
  check(result ~= true, "a second Pokemon at Agatha breaks the run")
end)


test("Gen 2: a New Game's opening script doesn't unlock the flag-rise achievements", function()
  local P = H.PROJECT .. "/recomp_achievements/"
  local rules = {}
  for _, r in ipairs(dofile(P .. "rules/gen2_official.lua")(dofile(P .. "rules/gen2_lib.lua"))) do rules[r.id] = r end
  local flags = {}
  local f = { flag = function(n) return flags[n] == true end }
  for _, id in ipairs({ "g2o_suicune_42", "g2o_suicune_36", "g2o_machine_part" }) do
    local r, s = rules[id], {}
    local flag = id == "g2o_machine_part" and "EVENT_FOUND_MACHINE_PART_IN_CERULEAN_GYM"
      or (id == "g2o_suicune_42" and "EVENT_SAW_SUICUNE_ON_ROUTE_42" or "EVENT_SAW_SUICUNE_ON_ROUTE_36")
    flags = {}
    eq(r.on.tick(s, nil, f), nil, id .. ": new save, nothing set")
    flags[flag] = true; flags.EVENT_INITIALIZED_EVENTS = true -- the opening script
    eq(r.on.tick(s, nil, f), nil, id .. ": set by the opening script")
    flags[flag] = nil -- the story clears it...
    eq(r.on.tick(s, nil, f), nil, id .. ": cleared")
    flags[flag] = true -- ...and the real moment sets it again
    eq(r.on.tick(s, nil, f), true, id .. ": the real moment counts")
  end
end)

test("Gen 2 New Game misfires from 2.0 are taken back on load", function()
  local Engine = dofile(H.PROJECT .. "/recomp_achievements/core/engine.lua")
  local data = { unlocked = {
    ["core:g2o_suicune_42"] = { how = "event", pt = 95 },
    ["core:g2o_suicune_36"] = { how = "event", pt = 40000 },
    ["core:g2o_machine_part"] = { how = "backfill", pt = 10 },
  } }
  local fake = setmetatable({ log = function() end }, { __index = Engine })
  Engine.dropNewGameMisfires(fake, data)
  eq(data.unlocked["core:g2o_suicune_42"], nil, "fired at play time 1:35: removed")
  check(data.quarantine["core:g2o_suicune_42"] ~= nil, "kept in quarantine")
  check(data.unlocked["core:g2o_suicune_36"] ~= nil, "earned 11 hours in: kept")
  check(data.unlocked["core:g2o_machine_part"] ~= nil, "credited from a real save: kept")
end)


test("progress notes: a small card for each step forward, none for a loaded save's backfill", function()
  local env = H.boot({ "recomp_achievements" })
  env:newGame()
  env.game.save.inventory.BOULDERBADGE = 1
  env:setFlag("EVENT_BEAT_BROCK"); env:frame()
  -- the badge unlock pops first; the note waits its turn
  env:hud()
  check(H.screenHas("ACHIEVEMENT!") or H.windowText():find("unlocked", 1, true), "unlock popup first")
  check(not H.windowText():find("1 / 8", 1, true), "note waits for the unlock popup")
  H.advance(4); env:hud(); H.advance(0.5); env:hud()
  check(H.windowText():find("1 / 8", 1, true), "then the badge case note: " .. H.windowText())
  H.advance(3); env:hud()
  check(not H.windowText():find("1 / 8", 1, true), "and it goes away")
  -- switched off
  env.loader.modOptions.recomp_achievements.progressPopups = false
  env.game.save.inventory.CASCADEBADGE = 1
  env:setFlag("EVENT_BEAT_MISTY"); env:frame()
  H.advance(4); env:hud(); H.advance(0.5); env:hud()
  check(not H.windowText():find("2 / 8", 1, true), "PROGRESS POPUPS off")
  -- a loaded save's progress arrives as backfill: no notes
  local env2 = H.boot({ "recomp_achievements" })
  local old = H.newSave("red")
  old.modData = nil
  for _, b in ipairs({ "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE" }) do old.inventory[b] = 1 end
  env2:loadBlob(require("src.core.SaveSerializer").encode(old))
  for _ = 1, 4 do env2:frame(); H.advance(1.5); env2:hud() end
  check(not H.windowText():find("3 / 8", 1, true), "no note for progress the save already had")
end)


test("progress cards: same count shows only the nearest goal; up to three stack", function()
  local Toast = dofile(H.PROJECT .. "/recomp_achievements/ui/toast.lua")
  local opts = {}
  local T = Toast.new({ options = { get = function(_, k) return opts[k] end } }, {}, {}, nil)
  local function def(key, unit) return { key = key, title = key, unit = unit } end
  -- one catch moves three Pokedex goals at once
  T:pushProgress(def("dex50", "POKEMON"), nil, 12, 50)
  T:pushProgress(def("dex100", "POKEMON"), nil, 12, 100)
  T:pushProgress(def("dex10", "POKEMON"), nil, 12, 151) -- the RA list's full dex
  T:pushProgress(def("badges", "BADGES"), nil, 3, 8)
  T:pushProgress(def("steps", "STEPS"), nil, 400, 1000)
  T:pushProgress(def("money", "COINS"), nil, 50, 100)
  local cards = T:tickProgress()
  eq(#cards, 3, "three at once")
  eq(cards[1][1].key, "dex50", "only the nearest Pokedex goal")
  eq(cards[1][1].goal, 50, "12 / 50")
  eq(cards[2][1].key, "badges", "a different thing gets its own card")
  eq(cards[3][1].key, "steps", "third card")
  H.advance(3)
  cards = T:tickProgress()
  eq(#cards, 1, "the fourth card follows once the first ones go")
  eq(cards[1][1].key, "money", "the waiting card")
  -- a nearer goal arriving later takes over the card
  T:clear()
  T:pushProgress(def("dex100", "POKEMON"), nil, 9, 100)
  T:pushProgress(def("dex10", "POKEMON"), nil, 9, 10)
  cards = T:tickProgress()
  eq(#cards, 1, "one card"); eq(cards[1][1].goal, 10, "9 / 10 wins over 9 / 100")
end)


test("Emerald: every RA entry linked once, every name real, checks run on a fresh and a finished save", function()
  local P = H.PROJECT .. "/recomp_achievements/"
  local rules = dofile(P .. "rules/gen3_emerald.lua")(dofile(P .. "rules/gen3_lib.lua"))
  local d = dofile(P .. "data/gen3_emerald.lua")
  local linked, ids = {}, {}
  for _, r in ipairs(rules) do
    check(not ids[r.id], "unique " .. r.id); ids[r.id] = true
    check(#r.title <= 32, "title fits " .. r.title)
    for g, raId in pairs(r.ra) do
      eq(g, "emerald", r.id .. " is an Emerald rule")
      check(not linked[raId], "linked once " .. raId); linked[raId] = true
    end
  end
  local c = dofile(P .. "catalog/emerald.lua")
  local pts = 0
  for _, e in ipairs(c.entries) do
    check(linked[e.id], "entry " .. e.id .. " " .. e.title .. " has a rule"); pts = pts + e.points
  end
  local src = assert(io.open(H.PROJECT .. "/tools/leaderboard_ingest.py")):read("*a")
  local mp, tot = src:match('"emerald":%s*{[^}]-"maxPoints":%s*(%d+),%s*"total":%s*(%d+)')
  eq(tonumber(mp), pts, "leaderboard max points"); eq(tonumber(tot), #c.entries, "leaderboard total")
  -- every quoted pret name in the rules exists
  local text = assert(io.open(P .. "rules/gen3_emerald.lua")):read("*a")
  for name in text:gmatch('"([A-Z][A-Z0-9_]+)"') do
    if name:match("_$") then -- a prefix, not a name
    elseif name:match("^FLAG_") or (name:match("^TRAINER_") and name:match("_%d$")) then check(d.flags[name] ~= nil, "flag " .. name)
    elseif name:match("^VAR_") then check(d.vars[name] ~= nil, "var " .. name) end
  end
  -- checks run against a blank save without errors and claim nothing
  local a = gen3Adapter({ version = "emerald", flags = {}, vars = {}, dex = { caught = {}, seen = {} },
    party = {}, storage = { boxes = {}, items = {} }, bag = { pockets = {} } })
  local f = a:facts()
  for _, r in ipairs(rules) do
    if r.check then
      local ok, v = pcall(r.check, f)
      check(ok, r.id .. " runs: " .. tostring(v))
      check(v ~= true, r.id .. " not done on a blank save")
    end
  end
  -- names and numbers agree with the engine's own Emerald tables, when available
  local ENGINE = os.getenv("ENGINE") or "/home/claude/engine"
  local okF, ft = pcall(dofile, ENGINE .. "/src/core/game3/constants/emerald/flags.lua")
  if okF then
    local n = 0
    for name, id in pairs(d.flags) do
      if name:match("^FLAG_") and ft.byName[name] then n = n + 1; eq(ft.byName[name], id, name) end
    end
    check(n > 1000, "compared " .. n .. " flags")
  end
end)


test("Ruby/Sapphire: every RA entry linked once, every name real, checks run", function()
  local P = H.PROJECT .. "/recomp_achievements/"
  local rules = dofile(P .. "rules/gen3_rs.lua")(dofile(P .. "rules/gen3_lib.lua"))
  local d = dofile(P .. "data/gen3_rs.lua")
  local linked, ids = { ruby = {}, sapphire = {} }, {}
  for _, r in ipairs(rules) do
    check(not ids[r.id], "unique " .. r.id); ids[r.id] = true
    check(#r.title <= 32, "title fits " .. r.title)
    for g, raId in pairs(r.ra) do
      check(linked[g] ~= nil, r.id .. " is a Ruby/Sapphire rule")
      check(not linked[g][raId], "linked once " .. raId); linked[g][raId] = true
    end
  end
  local src = assert(io.open(H.PROJECT .. "/tools/leaderboard_ingest.py")):read("*a")
  for _, g in ipairs({ "ruby", "sapphire" }) do
    local c = dofile(P .. "catalog/" .. g .. ".lua")
    local pts = 0
    for _, e in ipairs(c.entries) do check(linked[g][e.id], g .. " " .. e.id .. " " .. e.title .. " has a rule"); pts = pts + e.points end
    local mp, tot = src:match('"' .. g .. '":%s*{[^}]-"maxPoints":%s*(%d+),%s*"total":%s*(%d+)')
    eq(tonumber(mp), pts, g .. " leaderboard max points"); eq(tonumber(tot), #c.entries, g .. " leaderboard total")
  end
  local text = assert(io.open(P .. "rules/gen3_rs.lua")):read("*a")
  for name in text:gmatch('"([A-Z][A-Z0-9_]+)"') do
    if name:match("_$") then
    elseif name:match("^FLAG_") or name:match("^TRAINER_") then check(d.flags[name] ~= nil, "flag " .. name)
    elseif name:match("^VAR_") then check(d.vars[name] ~= nil, "var " .. name) end
  end
  for _, g in ipairs({ "ruby", "sapphire" }) do
    local f = gen3Adapter({ version = g, flags = {}, vars = {}, dex = { caught = {}, seen = {} },
      party = {}, storage = { boxes = {}, items = {} }, bag = { pockets = {} } }):facts()
    for _, r in ipairs(rules) do
      if r.check and r.ra[g] then
        local ok, v = pcall(r.check, f)
        check(ok, r.id .. " runs: " .. tostring(v)); check(v ~= true, r.id .. " not done on a blank save")
      end
    end
  end
  local ENGINE = os.getenv("ENGINE") or "/home/claude/engine"
  local okF, ft = pcall(dofile, ENGINE .. "/src/core/game3/constants/ruby/flags.lua")
  if okF then
    local n = 0
    for name, id in pairs(d.flags) do
      if name:match("^FLAG_") and ft.byName[name] then n = n + 1; eq(ft.byName[name], id, name) end
    end
    check(n > 500, "compared " .. n .. " flags")
  end
end)


test("Ruby/Sapphire: villain fights follow pokeruby's version.inc", function()
  local P = H.PROJECT .. "/recomp_achievements/"
  local rules = dofile(P .. "rules/gen3_rs.lua")(dofile(P .. "rules/gen3_lib.lua"))
  local d = dofile(P .. "data/gen3_rs.lua")
  local want = {
    rs_chimney_r = "TRAINER_MAXIE_3", rs_weather_r = "TRAINER_COURTNEY_1", rs_hideout_r = "TRAINER_TABITHA_1",
    rs_seafloor_r = "TRAINER_MAXIE_2", rs_master_ball_r = "FLAG_ITEM_MAGMA_HIDEOUT_B1F_1",
    rs_chimney_s = "TRAINER_ARCHIE_3", rs_weather_s = "TRAINER_SHELLY_1", rs_hideout_s = "TRAINER_MATT_1",
    rs_seafloor_s = "TRAINER_ARCHIE_2", rs_master_ball_s = "FLAG_ITEM_AQUA_HIDEOUT_B1F_2",
  }
  local byId = {}
  for _, r in ipairs(rules) do byId[r.id] = r end
  for id, name in pairs(want) do
    local game = id:sub(-1) == "r" and "ruby" or "sapphire"
    local f = gen3Adapter({ version = game, flags = { [d.flags[name]] = true }, vars = {},
      dex = { caught = {}, seen = {} }, party = {}, storage = { boxes = {}, items = {} }, bag = { pockets = {} } }):facts()
    eq(byId[id].check(f), true, id .. " reads " .. name)
  end
end)


test("browser: MISSABLE filter holds RA's missable entries and says so", function()
  local env = H.boot(BOTH)
  env:newGame(); env:frame()
  local Browser = dofile(H.PROJECT .. "/recomp_achievements/ui/browser.lua")
  local Modern = dofile(H.PROJECT .. "/recomp_achievements/ui/modern.lua")
  local ids = {}
  for _, f in ipairs(Browser.FILTERS) do ids[#ids + 1] = f.id end
  eq(table.concat(ids, ","), "all,earned,missing,progress,missable,official,bonus,mods,archived,reference", "filter order")
  check(Modern.FILTER_LABELS.missable == "Missable", "modern label")
  local rows = ach(env).list({})
  local cat = dofile(H.PROJECT .. "/recomp_achievements/catalog/red.lua")
  local want = 0
  for _, e in ipairs(cat.entries) do if e.type == "missable" then want = want + 1 end end
  check(want > 0, "Red has missables")
  -- open the menu and step to MISSABLE
  for _, item in ipairs(env:startMenu()) do
    if item.label == "TROPHIES" or item.label == "TROPHY" then item.onSelect() end
  end
  for _ = 1, 4 do env:press("right") end
  env:draw()
  check(H.screenHas("MISSABLE"), "filter label")
  env:press("a"); env:draw()
  check(H.screenHas("RA LIST: MISSABLE"), "details say missable")
  env:press("b"); env:press("b")
  -- the view model: every missable rule row passes, nothing else
  local n = 0
  for _, r in ipairs(rows) do
    if r.raType == "missable" then n = n + 1 end
  end
  eq(n, want, "every Red missable is a row with raType")
end)


test("START MENU ENTRY off hides the row; OPEN TROPHIES opens the menu from the Mods manager", function()
  local env = H.boot(BOTH)
  env:newGame(); env:frame()
  local function hasRow()
    for _, item in ipairs(env:startMenu()) do
      if item.label == "TROPHIES" or item.label == "TROPHY" then return true end
    end
    return false
  end
  check(hasRow(), "row there by default")
  env.loader.modOptions.recomp_achievements.startMenuEntry = false
  check(not hasRow(), "row gone when the option is off")
  check(env.game.stack:top() == nil, "nothing open yet")
  -- the manager emits this when the OPEN TROPHIES row is pressed
  env.loader.events:emit("mod.options_changed", { mod = "recomp_achievements", key = "openMenu", value = "go" })
  local top = env.game.stack:top()
  check(top ~= nil and top.isMenu, "menu opened")
  env:draw()
  check(H.screenHas("ALL"), "menu draws")
  env:press("b")
  check(env.game.stack:top() == nil, "B closes it")
  -- other keys and other mods don't open it
  env.loader.events:emit("mod.options_changed", { mod = "recomp_achievements", key = "toasts", value = false })
  env.loader.events:emit("mod.options_changed", { mod = "someone_else", key = "openMenu", value = "go" })
  check(env.game.stack:top() == nil, "only our OPEN TROPHIES row opens it")
  env.loader.modOptions.recomp_achievements.startMenuEntry = true
  check(hasRow(), "row back when turned on again")
end)


test("Gen 1 START row is short enough to keep the menu 10 tiles wide", function()
  local env = H.boot(BOTH)
  env:newGame(); env:frame()
  local label
  for _, item in ipairs(env:startMenu()) do
    if item.label == "TROPHIES" or item.label == "TROPHY" then label = item.label end
  end
  eq(label, "TROPHY", "Gen 1 uses the short label")
  check(#label + 3 <= 10, "fits the original box (widest label + 3 <= 10)")
end)


test("native Gen 3 menu: text never reads as font tokens; Gen 1 harness falls back", function()
  local N = dofile(H.PROJECT .. "/recomp_achievements/ui/native3.lua")
  eq(N.clean("Catch {PLAYER}'s\nMon"), "Catch (PLAYER)'s Mon", "braces and newlines")
  local env = H.boot(BOTH)
  env:newGame(); env:frame()
  env.loader.modOptions.recomp_achievements.classicMenu = true
  for _, item in ipairs(env:startMenu()) do
    if item.label == "TROPHY" then item.onSelect() end
  end
  local top = env.game.stack:top()
  check(top ~= nil and not top.native3 and not top.modern, "Gen 1 CLASSIC MENU is the text-box one")
  env:press("b")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
H.cleanup()
os.exit(failed == 0 and 0 or 1)
