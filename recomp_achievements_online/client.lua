-- client.lua
-- The parts of the online add-on that don't touch the engine: building the
-- request, reading the reply and deciding when to send. Kept pure so
-- tests/run.lua can check them without a network.
--
-- The worker (discord/worker.js) answers GET /auto with plain text:
--   ok linked                 sent, and this save is linked to Discord
--   ok code ABCD-1234         sent, not linked yet; /link ABCD-1234 links it
--   ok                        sent, not linked, no code (links not set up)
--   error <message>           not sent, and why
-- mod.fetch only does GET, so the card goes in the query string.
-- ------------------

local Client = {}

Client.ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
Client.KEY_LENGTH = 24
-- A second save within this many seconds doesn't send again.
Client.MIN_GAP = 120

function Client.newKey(rand)
  local out = {}
  for i = 1, Client.KEY_LENGTH do
    local n = rand(1, 32)
    out[i] = Client.ALPHABET:sub(n, n)
  end
  return table.concat(out)
end

function Client.validKey(key)
  return type(key) == "string" and #key == Client.KEY_LENGTH and not key:find("[^0-9A-Z]")
end

local function encode(s)
  return (tostring(s):gsub("[^%w%-%._~]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

local function query(base, fields)
  local parts = {}
  for _, kv in ipairs(fields) do
    if kv[2] ~= nil then parts[#parts + 1] = kv[1] .. "=" .. encode(kv[2]) end
  end
  return base:gsub("/*$", "") .. "/auto?" .. table.concat(parts, "&")
end

local function clock(minutes)
  if not minutes then return nil end
  return ("%d:%02d"):format(math.floor(minutes / 60), minutes % 60)
end

-- The score card from exports.leaderboardCard().
function Client.scoreUrl(base, key, card)
  return query(base, {
    { "v", 1 }, { "k", key }, { "kind", "score" }, { "game", card.game }, { "name", card.name },
    { "points", card.points }, { "earned", card.earned }, { "save_id", card.saveId },
    { "code", card.code }, { "time", clock(card.time) },
  })
end

-- The Extra Credit page from exports.extraCard(). Lines are joined with ";",
-- which the worker splits the same as /extra.
function Client.extraUrl(base, key, card)
  local lines = {}
  for _, s in ipairs(card.sources or {}) do
    lines[#lines + 1] = ("%s %d/%d %d"):format(s.id, s.earned, s.total, s.points)
  end
  return query(base, {
    { "v", 1 }, { "k", key }, { "kind", "extra" }, { "game", card.game }, { "name", card.name },
    { "save_id", card.saveId }, { "lines", table.concat(lines, ";") }, { "code", card.code },
  })
end

-- Only cards with something on them, and only when they changed since the
-- last send that worked.
function Client.wants(card, lastCode)
  return type(card) == "table" and (tonumber(card.earned) or 0) > 0 and card.code ~= lastCode
end

-- { ok = bool, linked = bool, code = "ABCD-1234" | nil, message = string | nil }
function Client.reply(body)
  local text = tostring(body or ""):match("^%s*(.-)%s*$")
  local first = text:match("^[^\n]*")
  if first:match("^ok") then
    local out = { ok = true, linked = first:match("^ok linked") ~= nil }
    out.code = first:match("^ok code ([0-9A-Z]+%-[0-9A-Z]+)$")
    return out
  end
  local msg = first:match("^error%s+(.+)$")
  return { ok = false, message = msg or "the server didn't answer as expected" }
end

-- Up to three lines of 18 characters for the leaderboard card.
function Client.note(state)
  if state.off then return { "ONLINE SCORES OFF" } end
  local lines = {}
  if state.sending then lines[1] = "ONLINE: SENDING"
  elseif state.error then lines[1] = "ONLINE: NOT SENT"
  elseif state.sent then lines[1] = "ONLINE: SENT"
  else lines[1] = "ONLINE: ON SAVE" end
  if state.linked then
    lines[2] = "LINKED TO DISCORD"
  elseif state.code then
    lines[2] = "DISCORD: /link"
    lines[3] = state.code
  elseif state.error then
    lines[2] = state.error:upper():sub(1, 18)
  end
  return lines
end

return Client
