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

test("START menu gets ACHIEVEMENTS right before OPTION", function()
  local env = H.boot(BOTH)
  local items = env:startMenu()
  local at
  for i, item in ipairs(items) do if item.label == "ACHIEVEMENTS" then at = i end end
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
      if item.label == "ACHIEVEMENTS" then item.onSelect() end
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
  check(H.screenHas("OFFICIAL RA SET"), "origin line")
  check(H.screenHas("LOCAL ONLY"), "local-only label")
  env:press("right"); env:draw()
  check(H.screenHas("ABOUT"), "about page")
  check(H.screenHas("RA game 724") and H.screenHas("achievement 4401"), "RA ids on the about page")
  check(H.screenHas("NOT SENT TO RA"), "not-sent label")
  env:press("b"); env:draw()
  check(H.screenHas("EARNED"), "back to list")

  -- BONUS filter holds this mod's own achievements, hidden ones masked
  for _ = 1, 4 do env:press("right") end
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
    if item.label == "ACHIEVEMENTS" then item.onSelect() end
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
    if item.label == "ACHIEVEMENTS" then item.onSelect() end
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
  env.loader.modOptions.recomp_achievements = { showReference = true }
  for _, item in ipairs(env:startMenu()) do
    if item.label == "ACHIEVEMENTS" then item.onSelect() end
  end
  for _ = 1, 8 do env:press("right") end
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
    if item.label == "ACHIEVEMENTS" then item.onSelect() end
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
    if item.label == "ACHIEVEMENTS" then item.onSelect() end
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
  env.loader.modOptions.recomp_achievements = { unlockSound = false }
  env:newGame(); env:hud(); H.advance(5); clearSounds()
  earnBadge(env); env:hud()
  eq(#H.sounds, 0, "option off: silent")

  local env2 = H.boot({ "recomp_achievements" })
  env2:newGame(); env2:hud(); H.advance(5); clearSounds()
  env2.game.save.options.sfxVol = 0
  earnBadge(env2); env2:hud()
  eq(#H.sounds, 0, "SFX VOL 0: silent")

  local env3 = H.boot({ "recomp_achievements" })
  env3.loader.modOptions.recomp_achievements = { toasts = false }
  env3:newGame(); H.advance(5); clearSounds()
  earnBadge(env3)
  eq(#H.sounds, 1, "popups off: sound plays at the unlock")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
H.cleanup()
os.exit(failed == 0 and 0 or 1)
