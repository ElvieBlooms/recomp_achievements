-- ui/text.lua
-- Shared drawing helpers for the Game Boy screen (20 x 18 tiles of 8px).
-- Uses mod.ui.Font -- the engine's own tile font -- so popups and the
-- browser look native and need no extra assets.
--
-- The Gen 1 font has no # $ % & * + < = > @ \ ^ _ ` { | } ~, but it does
-- have a few non-ASCII glyphs (é, curly quotes, …, ♀, ♂, ×).  Official
-- RA titles and provider text can contain anything, so every string is
-- normalised here first: supported glyphs pass, common symbols become
-- words, accents are dropped, and anything else becomes a space.  Widths
-- are counted in characters, not bytes, so "Pokémon" is 7 columns.

local Text = {}

-- Multi-byte glyphs the font can draw (checked against the extracted
-- Red/Blue/Yellow font charmap).
local KEEP = {
  ["é"] = true, ["‘"] = true, ["’"] = true, ["“"] = true, ["”"] = true,
  ["…"] = true, ["♀"] = true, ["♂"] = true, ["×"] = true,
}

-- Replacements for characters the font lacks.
local SUBST = {
  ["&"] = "and", ["%"] = "pct", ["#"] = "No.", ["+"] = "plus", ["@"] = "at",
  ["<"] = "(", [">"] = ")", ["="] = "-", ["_"] = " ", ["*"] = "", ["~"] = "-",
  ["|"] = "/", ["\\"] = "/", ["^"] = "", ["`"] = "'", ["{"] = "(", ["}"] = ")",
  ["$"] = "", ["–"] = "-", ["—"] = "-", ["É"] = "E",
  ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["ã"] = "a",
  ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["í"] = "i", ["ï"] = "i",
  ["ó"] = "o", ["ô"] = "o", ["ö"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n",
  ["ç"] = "c", ["Ç"] = "C", ["Ü"] = "U", ["Ö"] = "O", ["Ä"] = "A",
  ["½"] = "1/2", ["²"] = "2", ["°"] = "",
}

-- Split a string into UTF-8 characters.
function Text.chars(s)
  local out = {}
  for ch in tostring(s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    out[#out + 1] = ch
  end
  return out
end

function Text.safe(s)
  local out = {}
  for _, ch in ipairs(Text.chars(s)) do
    if #ch == 1 then
      local b = ch:byte()
      if b < 32 or b == 127 then out[#out + 1] = " "
      elseif SUBST[ch] then out[#out + 1] = SUBST[ch]
      else out[#out + 1] = ch end
    elseif KEEP[ch] then out[#out + 1] = ch
    elseif SUBST[ch] then out[#out + 1] = SUBST[ch]
    else out[#out + 1] = " " end
  end
  return table.concat(out)
end

function Text.len(s) return #Text.chars(s) end

-- Cut to `cols` characters (after normalising).
function Text.fit(s, cols)
  local chars = Text.chars(Text.safe(s))
  if #chars <= cols then return table.concat(chars) end
  local out = {}
  for i = 1, cols do out[i] = chars[i] end
  return table.concat(out)
end

-- Word-wrap to `width` characters.  Returns a list of lines.
function Text.wrap(s, width)
  local lines, line, lineLen = {}, "", 0
  for word in Text.safe(s):gmatch("%S+") do
    local chars = Text.chars(word)
    while #chars > width do
      if lineLen > 0 then lines[#lines + 1] = line; line, lineLen = "", 0 end
      lines[#lines + 1] = table.concat(chars, "", 1, width)
      local rest = {}
      for i = width + 1, #chars do rest[#rest + 1] = chars[i] end
      chars = rest
    end
    word = table.concat(chars)
    if lineLen == 0 then
      line, lineLen = word, #chars
    elseif lineLen + 1 + #chars <= width then
      line, lineLen = line .. " " .. word, lineLen + 1 + #chars
    elseif #chars > 0 then
      lines[#lines + 1] = line
      line, lineLen = word, #chars
    end
  end
  if lineLen > 0 then lines[#lines + 1] = line end
  return lines
end

-- Draw a string at tile coordinates (tx, ty) in black.
function Text.draw(Font, s, tx, ty)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Text.safe(s), tx * 8, ty * 8)
end

-- Right-aligned so the text ends just before column `rightTx`.
function Text.drawRight(Font, s, rightTx, ty)
  s = Text.safe(s)
  Text.draw(Font, s, rightTx - Text.len(s), ty)
end

-- A status mark that does not rely on colour: filled square = earned,
-- hollow square = locked, hollow with a slash = archived, dot = reference.
function Text.mark(kind, tx, ty)
  local x, y = tx * 8 + 1, ty * 8 + 1
  love.graphics.setColor(0, 0, 0, 1)
  if kind == "earned" then
    love.graphics.rectangle("fill", x, y, 6, 6)
  elseif kind == "archived" then
    love.graphics.rectangle("line", x + 0.5, y + 0.5, 5, 5)
    love.graphics.line(x, y + 6, x + 6, y)
  elseif kind == "reference" then
    love.graphics.rectangle("fill", x + 2, y + 2, 2, 2)
  else
    love.graphics.rectangle("line", x + 0.5, y + 0.5, 5, 5)
  end
end

-- Small solid arrows drawn as shapes (the font has no < or >).
function Text.arrow(dir, tx, ty)
  local x, y = tx * 8, ty * 8
  love.graphics.setColor(0, 0, 0, 1)
  if dir == "left" then
    love.graphics.polygon("fill", x + 6, y + 1, x + 6, y + 7, x + 2, y + 4)
  else
    love.graphics.polygon("fill", x + 2, y + 1, x + 2, y + 7, x + 6, y + 4)
  end
end

return Text
