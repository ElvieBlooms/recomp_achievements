// discord/worker.js
// The Recomp Achievements leaderboard bot, a Cloudflare Worker that answers
// Discord slash commands sent to its interactions endpoint. The free tier is plenty.
// A /score or /extra is checked for typos, then handed to the GitHub Action
// as a repository_dispatch event.
// The Action runs the same checks as an issue submission
// (tools/leaderboard_ingest.py), updates the board and edits the bot's reply
// in Discord with the result. The bot never writes to the board itself.
//
// Commands (registered by tools/discord_register.py):
//   /score game name points earned save_id code [time]
//   /leaderboard            link to the page
//   /check game [extra]     the top 3 for a game as a small embed, read from
//                           the public leaderboard.json; extra:all for
//                           Extra Credit, extra:<mod> for one mod
//   /extra game name save_id lines code
//                           an Extra Credit score (bonus and mod achievements)
//   /check game:All         the whole board in one post: every game's top 3,
//                           Extra Credit, and what changed this week
//   /link code              ties a save sending from Recomp Achievements Online
//                           to this Discord account
//
// It also answers GET /auto for the online add-on (recomp_achievements_online).
// The add-on sends the same card fields as /score or /extra, plus k, a random
// key kept in the save. mod.fetch only does GET, so the card is in the query
// string, and the reply is plain text (see the add-on's client.lua).
//
// The only thing it keeps is in the LINKS KV namespace, for /link:
//   code:<CODE>       -> key hash, gone after an hour
//   keycode:<hash>    -> CODE, so a save gets the same code until it expires
//   link:<hash>       -> Discord owner hash, once /link has run
// A code is only made when the add-on asks (SHOW LINK CODE on), since
// whoever runs /link with it gets the save. The key itself is what proves a
// save, so a newer code from the same save can always link it again.
// Without LINKS the add-on still sends, owned by the save, and /link says it
// isn't set up. AUTO_LIMIT, a rate limiting binding, caps sends per save and
// per IP address.
//
// Secrets (wrangler secret put ...):
//   DISCORD_PUBLIC_KEY  from the Discord developer portal
//   GITHUB_TOKEN        fine-grained token, this repo only, Contents: write
//   OWNER_SALT          any long random string; changing it orphans every Discord entry
// Vars (wrangler.toml):
//   GITHUB_REPO         e.g. ElvieBlooms/recomp_achievements
//   BOARD_URL           the GitHub Pages address
//
// Online sends are owned by "online:<hash of the key>" until /link, then by
// the same "discord:<hash>" as /score, so both ways update one row. Every
// online send also carries src, the save's own "online:<hash>": a row with
// that src can always be updated by the save, whoever it's linked to.
//
// The Discord user id is never sent to GitHub. The bot sends an HMAC of it
// keyed with OWNER_SALT instead, so only the same Discord account can update
// a save, and nobody can work out who submitted from the public board file.
// ------------------

const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const GAMES = { red: "Pokemon Red", blue: "Pokemon Blue", yellow: "Pokemon Yellow",
                gold: "Pokemon Gold", silver: "Pokemon Silver", crystal: "Pokemon Crystal",
                firered: "Pokemon FireRed", leafgreen: "Pokemon LeafGreen", emerald: "Pokemon Emerald",
                ruby: "Pokemon Ruby", sapphire: "Pokemon Sapphire" };
const EPHEMERAL = 64;
// Embed colours, taken from the light theme in docs/index.html.
const COLORS = { red: 0xc0392b, blue: 0x2c5aa0, yellow: 0xc79a00, gold: 0xa8801a, silver: 0x6f7a86,
                 crystal: 0x2b8fa8, firered: 0xd9622b, leafgreen: 0x4f9a3a, emerald: 0x1f8f6a,
                 ruby: 0xb0233a, sapphire: 0x2a4fb0 };

// ---------------------------------------------------------- check code
// These must match recomp_achievements/ui/share.lua and tools/leaderboard_ingest.py exactly.
// The code is a checksum to catch typos, not a security measure.
export function normName(name) {
  let out = "";
  for (const ch of String(name)) {
    if (" \t\n\v\f\r".includes(ch)) continue;
    out += ch >= "a" && ch <= "z" ? ch.toUpperCase() : ch;
  }
  return out;
}

function hash(bytes, seed) {
  let h = seed;
  for (const b of bytes) h = (h * 33 + b) % 4294967296;
  return h;
}

function base32(n, digits) {
  let out = "";
  for (let i = 0; i < digits; i++) { out = ALPHABET[n % 32] + out; n = Math.floor(n / 32); }
  return out;
}

// minutes is the card's play time (mod 1.2.0 on), or null for a 1.1.0 card.
export function checkCode(game, name, points, earned, saveId, minutes = null) {
  const parts = [minutes === null ? "v1" : "v2", game, normName(name), String(points), String(earned),
                 saveId.toUpperCase()];
  if (minutes !== null) parts.push(String(minutes));
  const p = parts.join("|");
  const bytes = new TextEncoder().encode(p);
  const s = base32(hash(bytes, 5381) % 1048576, 4) + base32(hash(bytes, 52711) % 1048576, 4);
  return s.slice(0, 4) + "-" + s.slice(4);
}

// Extra Credit's code covers the "bonus 3/9 20" lines from the Extra Credit page.
export function extraCheckCode(game, name, saveId, sources) {
  const parts = sources.map(([i, e, t, p]) => `${i}:${e}:${t}:${p}`).sort();
  const p = ["x1", game, normName(name), String(saveId).toUpperCase(), parts.join(",")].join("|");
  const bytes = new TextEncoder().encode(p);
  const s = base32(hash(bytes, 5381) % 1048576, 4) + base32(hash(bytes, 52711) % 1048576, 4);
  return s.slice(0, 4) + "-" + s.slice(4);
}

// Returns [[id, earned, total, points], ...], or a string saying what's wrong.
// Same rules as parse_extra_lines in tools/leaderboard_ingest.py.
export function parseExtraLines(raw) {
  const out = [], seen = new Set();
  for (let chunk of String(raw || "").split(/[\n,;]+/)) {
    chunk = chunk.trim().replace(/^`+|`+$/g, "").trim();
    if (!chunk) continue;
    const m = chunk.match(/^([A-Za-z0-9_-]{1,48})\s+(\d{1,3})\s*\/\s*(\d{1,3})\s+(\d{1,5})(?:\s*p(?:ts|oints)?)?$/i);
    if (!m) return `'${chunk.slice(0, 40)}' isn't a line from the page. Each looks like 'bonus 3/9 20'.`;
    const id = m[1].toLowerCase(), e = +m[2], t = +m[3], p = +m[4];
    if (seen.has(id)) return `'${id}' is listed twice.`;
    seen.add(id);
    if (t === 0 || t > 200 || e > t) return `'${id}': achievements earned and total don't fit together.`;
    if (p > e * 100 || (p > 0 && e === 0)) return `'${id}': ${p} points can't come from ${e} achievements.`;
    out.push([id, e, t, p]);
  }
  if (!out.length) return "Add the lines from the Extra Credit page, like 'bonus 3/9 20'.";
  if (out.length > 20) return "At most 20 lines.";
  return out;
}

export function precheckExtra(o) {
  const game = String(o.game || "").toLowerCase();
  if (!GAMES[game]) return "Pick the game from the list.";
  const name = String(o.name || "").trim();
  if (!name || [...name].length > 12) return "The trainer name must be 1 to 12 characters.";
  const saveId = normalizeSaveId(o.save_id);
  if (!/^[0-9A-Z]{6}$/.test(saveId)) return "The save ID is the 6 characters shown on the page.";
  const sources = parseExtraLines(o.lines);
  if (typeof sources === "string") return sources;
  if (normalizeCode(o.code || "") !== extraCheckCode(game, name, saveId, sources)) {
    return "The extra code doesn't match the lines. Check each line, the name and the save ID " +
      "against the Extra Credit page (START > TROPHIES > SELECT, then RIGHT) and try again.";
  }
  return null;
}

export function normalizeCode(code) {
  const c = String(code).toUpperCase().replace(/[\s-]/g, "")
    .replace(/O/g, "0").replace(/[IL]/g, "1");
  return c.length === 8 ? c.slice(0, 4) + "-" + c.slice(4) : c;
}

// Save IDs share the codes' alphabet, so O reads as 0 and I or L as 1.
export function normalizeSaveId(raw) {
  return String(raw || "").replace(/\s/g, "").toUpperCase().replace(/O/g, "0").replace(/[IL]/g, "1");
}

// "12:34" gives 754 minutes, a blank gives null, anything else undefined.
export function parseTime(raw) {
  const t = String(raw == null ? "" : raw).trim().toLowerCase();
  if (!t) return null;
  const m = t.match(/^(\d{1,3})\s*[:.h]\s*(\d{2})\s*m?$/);
  if (!m || Number(m[2]) > 59) return undefined;
  return Number(m[1]) * 60 + Number(m[2]);
}

// ---------------------------------------------------------- helpers
function hex(buf) {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function unhex(s) {
  const out = new Uint8Array(s.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(s.substr(i * 2, 2), 16);
  return out;
}

async function verify(request, body, publicKey) {
  const sig = request.headers.get("X-Signature-Ed25519");
  const ts = request.headers.get("X-Signature-Timestamp");
  if (!sig || !ts || !/^[0-9a-f]+$/i.test(sig) || !/^[0-9a-f]{64}$/i.test(publicKey || "")) return false;
  try {
    const key = await crypto.subtle.importKey("raw", unhex(publicKey), { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify("Ed25519", key, unhex(sig), new TextEncoder().encode(ts + body));
  } catch (e) {
    return false;
  }
}

async function ownerHash(salt, userId) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(salt),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode("discord:" + userId));
  return hex(mac).slice(0, 32);
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status, headers: { "Content-Type": "application/json" },
  });
}

function say(content) {
  return json({ type: 4, data: { content, flags: EPHEMERAL, allowed_mentions: { parse: [] } } });
}

function options(interaction) {
  const out = {};
  for (const o of interaction.data.options || []) out[o.name] = o.value;
  return out;
}

// Quick checks so a typo gets an instant answer.
// The Action checks everything again (limits, name filter, ownership) before saving.
export function precheck(o) {
  const game = String(o.game || "").toLowerCase();
  if (!GAMES[game]) return "Pick the game from the list (red, blue, yellow, gold, silver, crystal, ruby, sapphire, firered, leafgreen or emerald).";
  const name = String(o.name || "").trim();
  if (!name || [...name].length > 12) return "The trainer name must be 1 to 12 characters.";
  const points = Number(o.points), earned = Number(o.earned);
  if (!Number.isInteger(points) || points < 0 || !Number.isInteger(earned) || earned < 0) {
    return "Points and achievements earned must be whole numbers.";
  }
  const saveId = normalizeSaveId(o.save_id);
  if (!/^[0-9A-Z]{6}$/.test(saveId)) return "The save ID is the 6 characters shown on the card.";
  const minutes = parseTime(o.time);
  if (minutes === undefined) return "Play time is the H:MM after TIME on the card, like 12:34.";
  if (normalizeCode(o.code || "") !== checkCode(game, name, points, earned, saveId, minutes)) {
    return "The check code doesn't match the other values. Check each one against the card " +
      "(START > TROPHIES > SELECT) and try again." +
      (minutes === null ? " If your card has a TIME line, add it too: time:H:MM (the time is part of the code)." : "");
  }
  return null;
}

async function sendDispatch(env, eventType, payload) {
  const r = await fetch(`https://api.github.com/repos/${env.GITHUB_REPO}/dispatches`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "recomp-achievements-discord-bot",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ event_type: eventType, client_payload: payload }),
  });
  if (r.status !== 204) throw new Error("GitHub said " + r.status);
}

async function dispatch(env, interaction, o, kind = "score") {
  const user = interaction.user || (interaction.member && interaction.member.user) || {};
  const payload = {
    owner: await ownerHash(env.OWNER_SALT, user.id),
    app_id: interaction.application_id,
    token: interaction.token,
  };
  if (kind === "extra") {
    payload.extra = {
      game: String(o.game).toLowerCase(), name: String(o.name).trim(),
      save_id: normalizeSaveId(o.save_id), extra: String(o.lines || ""), code: normalizeCode(o.code),
    };
  } else {
    payload.score = {
      game: String(o.game).toLowerCase(), name: String(o.name).trim(),
      points: String(o.points), earned: String(o.earned),
      save_id: normalizeSaveId(o.save_id), code: normalizeCode(o.code),
      time: o.time == null ? "" : String(o.time).trim(),
    };
  }
  await sendDispatch(env, kind === "extra" ? "discord-extra" : "discord-score", payload);
}

// ---------------------------------------------------------- online add-on
// Replies are short: the add-on shows them on the card, 18 characters a line.
const LINK_TTL = 60 * 60;

export function validKey(k) {
  return /^[0-9A-Z]{24}$/.test(String(k || ""));
}

async function keyHash(salt, key) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(salt),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode("key:" + key));
  return hex(mac).slice(0, 32);
}

export function newLinkCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  let s = "";
  for (const b of bytes) s += ALPHABET[b % 32];
  return s.slice(0, 4) + "-" + s.slice(4);
}

// The card fields from the query string, or a short reason it can't be sent.
export function readAuto(params) {
  if (params.get("v") !== "1") return { problem: "update the mod" };
  if (!validKey(params.get("k"))) return { problem: "bad key" };
  const kind = params.get("kind");
  const o = {};
  if (kind === "score") {
    for (const f of ["game", "name", "points", "earned", "save_id", "code", "time"]) o[f] = params.get(f) ?? "";
    if (o.time === "") o.time = null;
    if (precheck(o)) return { problem: "card didn't check" };
  } else if (kind === "extra") {
    for (const f of ["game", "name", "save_id", "lines", "code"]) o[f] = params.get(f) ?? "";
    if (precheckExtra(o)) return { problem: "card didn't check" };
  } else {
    return { problem: "update the mod" };
  }
  return { kind, key: params.get("k"), o, wantCode: params.get("link") === "1" };
}

// Whether this save may write the row the board already has for its save
// ID. The Action checks again; this only lets the add-on say so.
export function rowTaken(board, kind, o, owner, src) {
  const game = String(o.game).toLowerCase();
  const slot = kind === "extra" ? board?.extra?.[game] : board?.games?.[game];
  const saveId = normalizeSaveId(o.save_id);
  for (const e of (slot && slot.entries) || []) {
    if (e.saveId !== saveId) continue;
    const who = e.owner || "gh:" + String(e.github || "").toLowerCase();
    return !(who === owner || who === src || e.src === src);
  }
  return false;
}

function text(body) {
  return new Response(body, { status: 200, headers: { "Content-Type": "text/plain; charset=utf-8" } });
}

async function handleAuto(url, env, request) {
  if (!env.GITHUB_TOKEN || !env.GITHUB_REPO || !env.OWNER_SALT) return text("error server not set up");
  const got = readAuto(url.searchParams);
  if (got.problem) return text("error " + got.problem);
  const hash = await keyHash(env.OWNER_SALT, got.key);
  if (env.AUTO_LIMIT) {
    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    for (const key of [hash, "ip:" + ip]) {
      const { success } = await env.AUTO_LIMIT.limit({ key });
      if (!success) return text("error try again later");
    }
  }
  const linked = env.LINKS ? await env.LINKS.get("link:" + hash) : null;
  const src = "online:" + hash;
  const owner = linked ? "discord:" + linked : src;
  const o = got.o;
  if (env.BOARD_URL) {
    let board = null;
    try { board = await loadBoard(env); } catch (e) { board = null; }
    if (board && rowTaken(board, got.kind, o, owner, src)) return text("error save id taken");
  }
  const payload = { owner, src };
  if (got.kind === "extra") {
    payload.extra = {
      game: String(o.game).toLowerCase(), name: String(o.name).trim(),
      save_id: normalizeSaveId(o.save_id), extra: String(o.lines), code: normalizeCode(o.code),
    };
  } else {
    payload.score = {
      game: String(o.game).toLowerCase(), name: String(o.name).trim(),
      points: String(o.points), earned: String(o.earned),
      save_id: normalizeSaveId(o.save_id), code: normalizeCode(o.code),
      time: o.time == null ? "" : String(o.time).trim(),
    };
  }
  try {
    await sendDispatch(env, got.kind === "extra" ? "online-extra" : "online-score", payload);
  } catch (e) {
    return text("error try again later");
  }
  let reply = linked ? "ok linked" : "ok";
  if (got.wantCode && env.LINKS) {
    let code = await env.LINKS.get("keycode:" + hash);
    if (!code) {
      code = newLinkCode();
      await env.LINKS.put("code:" + code, hash, { expirationTtl: LINK_TTL });
      await env.LINKS.put("keycode:" + hash, code, { expirationTtl: LINK_TTL });
    }
    reply += " code " + code;
  }
  return text(reply);
}

async function handleLink(env, interaction) {
  if (!env.LINKS || !env.GITHUB_TOKEN || !env.GITHUB_REPO || !env.OWNER_SALT) {
    return { reply: "Linking isn't set up yet. Please tell the maintainer." };
  }
  const code = normalizeCode(options(interaction).code || "");
  const hash = /^[0-9A-Z]{4}-[0-9A-Z]{4}$/.test(code) ? await env.LINKS.get("code:" + code) : null;
  if (!hash) {
    return { reply: "That code doesn't exist or has expired (codes last an hour). Turn on SHOW LINK CODE " +
      "in the add-on's options, save, and use the code on the card (START > TROPHIES > SELECT)." };
  }
  const user = interaction.user || (interaction.member && interaction.member.user) || {};
  const owner = await ownerHash(env.OWNER_SALT, user.id);
  // A code only comes from the save itself, so a newer one always wins.
  const before = await env.LINKS.get("link:" + hash);
  await env.LINKS.put("link:" + hash, owner);
  await env.LINKS.delete("code:" + code);
  await env.LINKS.delete("keycode:" + hash);
  return {
    reply: (before && before !== owner ? "Linked, in place of the account it was linked to before. " : "Linked. ") +
      "Moving this save's scores to your account… this message will update in a minute or two.",
    payload: { src: "online:" + hash, to: "discord:" + owner,
               app_id: interaction.application_id, token: interaction.token },
  };
}

// ---------------------------------------------------------- /check
// Same order as rank() in tools/leaderboard_ingest.py: most points, then
// shortest play time with untimed entries last, then earliest submission.
export function topEntries(entries, n = 3) {
  const list = (Array.isArray(entries) ? entries : []).filter(e => e && typeof e.name === "string");
  list.sort((a, b) => {
    if ((b.points | 0) !== (a.points | 0)) return (b.points | 0) - (a.points | 0);
    const ta = a.time == null ? null : a.time, tb = b.time == null ? null : b.time;
    if ((ta === null) !== (tb === null)) return ta === null ? 1 : -1;
    if (ta !== tb) return ta - tb;
    return String(a.first || "").localeCompare(String(b.first || ""));
  });
  return list.slice(0, n);
}

function clock(minutes) {
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
}

// Shows trainer names as written, with Markdown and mentions escaped.
function plain(s) {
  return String(s).replace(/[\\*_~`|>#\[\]()-]/g, "\\$&").replace(/@/g, "@\u200b");
}

export function boardEmbed(game, slot, boardUrl) {
  const title = (slot && slot.title) || GAMES[game];
  const max = slot && slot.maxPoints, total = slot && slot.total;
  const entries = (slot && slot.entries) || [];
  const top = topEntries(entries);
  const medals = ["\u{1F947}", "\u{1F948}", "\u{1F949}"];
  const lines = top.map((e, i) => {
    let line = `${medals[i]} **${plain(e.name)}**  ${e.points | 0}${max ? " / " + max : ""} pts`;
    line += ` \u00b7 ${e.earned | 0}${total ? "/" + total : ""}`;
    if (typeof e.time === "number") line += ` \u00b7 ${clock(e.time)}`;
    return line;
  });
  const base = String(boardUrl || "").replace(/#.*$/, "");
  return {
    title: `${title}: top ${top.length || 3}`,
    url: base ? `${base}#${game}` : undefined,
    color: COLORS[game],
    description: lines.length ? lines.join("\n")
      : "No scores yet. Be the first with `/score`!",
    footer: { text: entries.length === 1 ? "1 trainer on the board"
      : `${entries.length} trainers on the board` },
  };
}

// Extra Credit ranking, same as rank_extra in tools/leaderboard_ingest.py:
// most points, then most achievements, then earliest.
// `source` narrows it to one line ("bonus", "naviplay"), or null for the total.
export function topExtra(entries, source = null, n = 3) {
  const list = [];
  for (const e of Array.isArray(entries) ? entries : []) {
    if (!e || typeof e.name !== "string") continue;
    if (source) {
      const s = e.sources && e.sources[source];
      if (!s) continue;
      list.push({ name: e.name, points: s.points | 0, earned: s.earned | 0, total: s.total | 0, first: e.first });
    } else {
      list.push({ name: e.name, points: e.points | 0, earned: e.earned | 0, first: e.first });
    }
  }
  list.sort((a, b) => (b.points - a.points) || (b.earned - a.earned)
    || String(a.first || "").localeCompare(String(b.first || "")));
  return { top: list.slice(0, n), count: list.length };
}

export function extraEmbed(game, slot, source, boardUrl) {
  const { top, count } = topExtra(slot && slot.entries, source);
  const medals = ["\u{1F947}", "\u{1F948}", "\u{1F949}"];
  const lines = top.map((e, i) => `${medals[i]} **${plain(e.name)}**  ${e.points} pts \u00b7 `
    + (source ? `${e.earned}/${e.total}` : `${e.earned} achievements`));
  const base = String(boardUrl || "").replace(/#.*$/, "");
  const what = source ? (source === "bonus" ? "Bonus" : source) : "Extra Credit";
  return {
    title: `${GAMES[game]} \u00b7 ${what}: top ${top.length || 3}`,
    url: base ? `${base}#${game}/extra${source ? "/" + source : ""}` : undefined,
    color: COLORS[game],
    description: lines.length ? lines.join("\n")
      : (source ? `No Extra Credit scores for ${what} yet.` : "No Extra Credit scores yet. Be the first with `/extra`!"),
    footer: { text: count === 1 ? "1 trainer on this board" : `${count} trainers on this board` },
  };
}

// ---------------------------------------------------------- whole board
// /check game:All. The same message tools/discord_board.py keeps live with a
// webhook; tests/test_discord_worker.mjs checks the two match.
const GENERATIONS = [
  ["Generation I", ["red", "blue", "yellow"], 0xc0392b],
  ["Generation II", ["gold", "silver", "crystal"], 0xa8801a],
  ["Generation III: Hoenn", ["ruby", "sapphire", "emerald"], 0x1f8f6a],
  ["Generation III: Kanto", ["firered", "leafgreen"], 0xd9622b],
];
const MEDALS = ["\u{1F947}", "\u{1F948}", "\u{1F949}"];
const WEEK = 7 * 86400;

function stamp(s) {
  return /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(String(s)) ? Date.parse(s) / 1000 : null;
}

function medalLines(entries, extra) {
  let top;
  if (extra) {
    top = topExtra(entries, null).top;
  } else {
    top = topEntries(entries).map((e) => ({ name: e.name, points: e.points | 0 }));
  }
  return top.map((e, i) => `${MEDALS[i]} **${plain(e.name)}** ${e.points | 0} pts`);
}

function ownerOf(e) {
  return e.owner || "gh:" + String(e.github || "").toLowerCase();
}

export function allBoard(board, boardUrl, now = Math.floor(Date.now() / 1000)) {
  const base = String(boardUrl || "").replace(/\/+$/, "");
  const games = (board && board.games) || {};
  const extras = (board && board.extra) || {};
  const ids = Object.keys(GAMES);
  const entriesOf = (slot) => (slot && Array.isArray(slot.entries) ? slot.entries : []);
  const owners = new Set();
  let fresh = 0, updated = 0;
  for (const g of ids) {
    for (const e of [...entriesOf(games[g]), ...entriesOf(extras[g])]) {
      owners.add(ownerOf(e));
      const first = stamp(e.first), date = stamp(e.date);
      if (first && now - first <= WEEK) fresh++;
      else if (date && now - date <= WEEK) updated++;
    }
  }
  const played = ids.filter((g) => entriesOf(games[g]).length > 0).length;
  const when = stamp(board && board.updated);
  const s = (n) => (n === 1 ? "" : "s");
  const desc = [`**${owners.size}** trainer${s(owners.size)} across **${played}** game${s(played)}.`
    + (when ? ` Updated <t:${when}:R>.` : "")];
  desc.push(fresh || updated ? `This week: **${fresh}** new score${s(fresh)}, **${updated}** updated.`
    : "A quiet week. Your move.");
  desc.push("Install **Recomp Achievements Online** and your score goes up when you save, "
    + "or send your card with `/score`. `/check` shows any game's top 3.");
  const embeds = [{ title: "Recomp Achievements leaderboard", url: base + "/", color: 0x2b8fa8,
                    description: desc.join("\n") }];
  for (const [title, list, color] of GENERATIONS) {
    let people = 0;
    const fields = list.map((g) => {
      const entries = entriesOf(games[g]);
      people += entries.length;
      const lines = medalLines(entries, false);
      return { name: GAMES[g].replace("Pokemon ", ""), inline: true,
               value: (lines.join("\n") || "*No scores yet*").slice(0, 1024) };
    });
    embeds.push({ title, url: `${base}/#${list[0]}`, color, fields,
                  footer: { text: people ? `${people} on the board` : "Be the first" } });
  }
  const extraFields = [];
  let first = null;
  for (const g of ids) {
    const lines = medalLines(entriesOf(extras[g]), true);
    if (lines.length) {
      first = first || g;
      extraFields.push({ name: GAMES[g].replace("Pokemon ", ""), inline: true, value: lines.join("\n").slice(0, 1024) });
    }
  }
  const extra = { title: "Extra Credit", url: `${base}/#${first || "red"}/extra`, color: 0x6f7a86,
                  footer: { text: "Bonus and mod achievements. Kept apart from the main board." } };
  if (extraFields.length) extra.fields = extraFields;
  else extra.description = "*No Extra Credit yet*";
  embeds.push(extra);
  return { embeds, allowed_mentions: { parse: [] } };
}

async function loadBoard(env) {
  const base = String(env.BOARD_URL || "").replace(/#.*$/, "").replace(/\/?$/, "/");
  const r = await fetch(`${base}leaderboard.json?t=${Date.now()}`, {
    headers: { "User-Agent": "recomp-achievements-discord-bot" }, cf: { cacheTtl: 0 },
  });
  if (!r.ok) throw new Error("board said " + r.status);
  return r.json();
}

async function postCheck(env, interaction, game, extra = null) {
  let body;
  try {
    const board = await loadBoard(env);
    if (game === "all") {
      body = allBoard(board, env.BOARD_URL);
    } else if (extra) {
      const source = extra === "all" ? null : extra;
      body = { embeds: [extraEmbed(game, board.extra && board.extra[game], source, env.BOARD_URL)] };
    } else {
      body = { embeds: [boardEmbed(game, board.games && board.games[game], env.BOARD_URL)] };
    }
  } catch (e) {
    body = { content: "Couldn't load the leaderboard right now. Please try again in a few minutes." };
  }
  await fetch(`https://discord.com/api/v10/webhooks/${interaction.application_id}/${interaction.token}/messages/@original`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...body, allowed_mentions: { parse: [] } }),
  });
}

async function editReply(interaction, content) {
  await fetch(`https://discord.com/api/v10/webhooks/${interaction.application_id}/${interaction.token}/messages/@original`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ content, allowed_mentions: { parse: [] } }),
  });
}

// ---------------------------------------------------------- entry point
export default {
  async fetch(request, env, ctx) {
    if (request.method === "GET") {
      const url = new URL(request.url);
      if (url.pathname === "/auto") return handleAuto(url, env, request);
    }
    if (request.method !== "POST") return new Response("Recomp Achievements leaderboard bot", { status: 200 });
    const body = await request.text();
    if (!(await verify(request, body, env.DISCORD_PUBLIC_KEY))) {
      return new Response("bad signature", { status: 401 });
    }
    let interaction;
    try { interaction = JSON.parse(body); } catch (e) { return new Response("bad json", { status: 400 }); }

    if (interaction.type === 1) return json({ type: 1 }); // Discord PING, answered with PONG

    if (interaction.type === 2) { // APPLICATION_COMMAND, a slash command
      const name = interaction.data && interaction.data.name;
      if (name === "leaderboard") {
        return say(`The leaderboard: ${env.BOARD_URL}\nSubmit with \`/score\` and the card from START > TROPHIES > SELECT.`);
      }
      if (name === "check") {
        const o = options(interaction);
        const game = String(o.game || "").toLowerCase();
        if (!GAMES[game] && game !== "all") return say("Pick the game from the list.");
        if (!env.BOARD_URL) return say("The bot isn't set up yet. Please tell the maintainer.");
        let extra = o.extra == null ? null : String(o.extra).trim().toLowerCase();
        if (extra === "") extra = null;
        if (extra && extra !== "all" && !/^[a-z0-9_-]{1,48}$/.test(extra)) {
          return say("extra: is `all`, `bonus`, or a mod's name as it appears on the Extra Credit page.");
        }
        ctx.waitUntil(postCheck(env, interaction, game, extra));
        return json({ type: 5 }); // deferred reply: "thinking" until the public embed replaces it
      }
      if (name === "extra") {
        const o = options(interaction);
        const problem = precheckExtra(o);
        if (problem) return say("Couldn't add this Extra Credit score: " + problem);
        if (!env.GITHUB_TOKEN || !env.GITHUB_REPO || !env.OWNER_SALT) {
          return say("The bot isn't set up yet. Please tell the maintainer.");
        }
        ctx.waitUntil(dispatch(env, interaction, o, "extra").catch(() =>
          editReply(interaction, "Couldn't reach the leaderboard right now. Please try again in a few minutes.")));
        return say("Checking your Extra Credit score… this message will update in a minute or two.");
      }
      if (name === "link") {
        const got = await handleLink(env, interaction);
        if (got.payload) {
          ctx.waitUntil(sendDispatch(env, "online-link", got.payload).catch(() =>
            editReply(interaction, "Linked, but couldn't move your scores yet. They'll move with your next save.")));
        }
        return say(got.reply);
      }
      if (name === "score") {
        const o = options(interaction);
        const problem = precheck(o);
        if (problem) return say("Couldn't add this score: " + problem);
        if (!env.GITHUB_TOKEN || !env.GITHUB_REPO || !env.OWNER_SALT) {
          return say("The bot isn't set up yet. Please tell the maintainer.");
        }
        ctx.waitUntil(dispatch(env, interaction, o).catch(() =>
          editReply(interaction, "Couldn't reach the leaderboard right now. Please try again in a few minutes.")));
        return say("Checking your score… this message will update in a minute or two.");
      }
    }
    return say("Unknown command.");
  },
};
