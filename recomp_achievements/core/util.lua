-- core/util.lua
-- Small helpers the rest of the mod shares: copying plain data, read-only
-- views, number and id checks, and UTF-8 safe text trimming.
-- It touches nothing in the engine or the save on its own.
-- ------------------

local util = {}

-- Deep copy of plain data. Functions and userdata are dropped, so the
-- result is always safe to hand to another mod or write to the save.
function util.plain(value, depth)
  depth = depth or 6
  local t = type(value)
  if t == "string" or t == "boolean" then return value end
  if t == "number" then
    -- NaN and infinity can't round-trip through the save writer.
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

-- A read-only view: reads work, writes raise an error.
-- Other mods get these so they can't edit our tables by accident.
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

-- Provider ids and local ids: 1 to 48 of a-z, 0-9, _ and -.
-- Keeps save keys readable and stops an id clashing with the ":" separator.
function util.validId(s)
  return type(s) == "string" and #s >= 1 and #s <= 48 and s:match("^[a-z0-9_%-]+$") ~= nil
end

-- Swap any bad UTF-8 byte for "?", such as a Latin-1 "é" from another mod.
-- LÖVE won't draw invalid UTF-8, so one bad title would break the menu.
function util.utf8Clean(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:byte(i)
    local len = c < 0x80 and 1 or (c >= 0xC2 and c <= 0xDF) and 2 or (c >= 0xE0 and c <= 0xEF) and 3
      or (c >= 0xF0 and c <= 0xF4) and 4 or 0
    local ok = len > 0 and i + len - 1 <= n
    for k = 1, len - 1 do
      local b = ok and s:byte(i + k)
      if not b or b < 0x80 or b > 0xBF then ok = false end
    end
    if ok then out[#out + 1] = s:sub(i, i + len - 1); i = i + len
    else out[#out + 1] = "?"; i = i + 1 end
  end
  return table.concat(out)
end

-- Length in characters, not bytes.
function util.len(s)
  local _, n = tostring(s or ""):gsub("[^\128-\191]", "")
  return n
end

-- Clean a display string and trim it to `max` characters.
-- Counts characters, not bytes, so "é" is never cut in half.
function util.text(s, max)
  if type(s) ~= "string" then return nil end
  s = util.utf8Clean((s:gsub("%c", " ")))
  if max and util.len(s) > max then
    local n, cut = 0, #s
    for i = 1, #s do
      local b = s:byte(i)
      if b < 0x80 or b >= 0xC0 then
        n = n + 1
        if n > max then cut = i - 1 break end
      end
    end
    s = s:sub(1, cut)
  end
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

-- Word-wrap to a column width. Returns a list of lines.
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
