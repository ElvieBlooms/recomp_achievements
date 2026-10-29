-- core/util.lua
-- Small, dependency-free helpers shared by every other file.

local util = {}

-- Deep copy of plain data.  Functions and userdata are dropped, which is
-- exactly what we want for anything handed to another mod or written to
-- a save: the result is always safe to serialize.
function util.plain(value, depth)
  depth = depth or 6
  local t = type(value)
  if t == "string" or t == "boolean" then return value end
  if t == "number" then
    -- NaN and infinity cannot round-trip through the save writer
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
  end
  if t ~= "table" or depth == 0 then return nil end
  local out = {}
  for k, v in pairs(value) do
    local kt = type(k)
    if kt == "string" or kt == "number" then
      out[k] = util.plain(v, depth - 1)
    end
  end
  return out
end

-- A read-only view: indexing works, writes raise an error.  Handed to
-- other mods so they cannot reach in and edit our registry by accident.
function util.readonly(t)
  return setmetatable({}, {
    __index = t,
    __newindex = function() error("recomp_achievements: read-only table", 2) end,
    __metatable = false,
  })
end

function util.clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function util.isInteger(n)
  return type(n) == "number" and n == n and n % 1 == 0
    and n ~= math.huge and n ~= -math.huge
end

-- Identifier rule for provider ids and local ids: lowercase letters,
-- digits, underscore, dash; 1..48 chars.  Keeps keys readable in the save
-- and impossible to confuse with the "provider:local" separator.
function util.validId(s)
  return type(s) == "string" and #s >= 1 and #s <= 48 and s:match("^[a-z0-9_%-]+$") ~= nil
end

-- Trim a display string to a byte budget (the GB font is fixed width, so
-- bytes ~ columns for the ASCII we allow).  Control chars are removed.
function util.text(s, max)
  if type(s) ~= "string" then return nil end
  s = s:gsub("%c", " ")
  if max and #s > max then s = s:sub(1, max) end
  return s
end

function util.count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

function util.sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- Word-wrap to a column width.  Returns a list of lines.
function util.wrap(text, width)
  local lines, line = {}, ""
  for word in tostring(text or ""):gmatch("%S+") do
    while #word > width do
      if line ~= "" then lines[#lines + 1] = line; line = "" end
      lines[#lines + 1] = word:sub(1, width)
      word = word:sub(width + 1)
    end
    if line == "" then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

return util
