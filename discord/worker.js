// Recomp Achievements leaderboard bot for Discord.
// =====================================================================
// A Cloudflare Worker (free tier is plenty) that answers Discord slash
// commands.  It has no database and keeps nothing: a /score command is
// checked for typos, then handed to the GitHub Action through a
// repository_dispatch event.  The Action runs the same checks as an issue
// submission (tools/leaderboard_ingest.py), updates the board and edits
// the bot's reply in Discord with the result.
//
// Commands (registered by tools/discord_register.py):
//   /score game name points earned save_id code [time]
//   /leaderboard            link to the page
//   /check game [extra]     the top 3 for a game, posted as a small embed
//                           (read from the public leaderboard.json);
//                           extra:all for Extra Credit, extra:<mod> for one mod
//   /extra game name save_id lines code
//                           an Extra Credit score (bonus and mod achievements)
//
// Secrets (wrangler secret put ...):
//   DISCORD_PUBLIC_KEY  from the Discord developer portal
//   GITHUB_TOKEN        fine-grained token, this repo only, Contents: write
//   OWNER_SALT          any long random string; never change it
// Vars (wrangler.toml):
//   GITHUB_REPO         e.g. ElvieBlooms/recomp_achievements
//   BOARD_URL           the GitHub Pages address
//
// The Discord user id is never sent to GitHub: the bot sends a keyed hash
// of it (OWNER_SALT), so only the same Discord account can update a save
// and nobody can work out who submitted from the public board file.
// =====================================================================

const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const GAMES = { red: "Pokemon Red", blue: "Pokemon Blue", yellow: "Pokemon Yellow",
                gold: "Pokemon Gold", silver: "Pokemon Silver", crystal: "Pokemon Crystal",
                firered: "Pokemon FireRed", leafgreen: "Pokemon LeafGreen", emerald: "Pokemon Emerald",
                ruby: "Pokemon Ruby", sapphire: "Pokemon Sapphire" };
const EPHEMERAL = 64;
// Embed colours, the light-theme ones from docs/index.html.
const COLORS = { red: 0xc0392b, blue: 0x2c5aa0, yellow: 0xc79a00, gold: 0xa8801a, silver: 0x6f7a86,
                 crystal: 0x2b8fa8, firered: 0xd9622b, leafgreen: 0x4f9a3a, emerald: 0x1f8f6a,
                 ruby: 0xb0233a, sapphire: 0x2a4fb0 };

// ---------------------------------------------------------- check code
// Same as recomp_achievements/ui/share.lua and tools/leaderboard_ingest.py.
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

// minutes: play time from the card (mod 1.2.0+), or null for a 1.1.0 card.
export function checkCode(game, name, points, earned, saveId, minutes = null) {
  const parts = [minutes === null ? "v1" : "v2", game, normName(name), String(points), String(earned),
                 saveId.toUpperCase()];
  if (minutes !== null) parts.push(String(minutes));
  const p = parts.join("|");
  const bytes = new TextEncoder().encode(p);
  const s = base32(hash(bytes, 5381) % 1048576, 4) + base32(hash(bytes, 52711) % 1048576, 4);
  return s.slice(0, 4) + "-" + s.slice(4);
}

// Extra Credit: "bonus 3/9 20" lines from the card's Extra Credit page.
export function extraCheckCode(game, name, saveId, sources) {
  const parts = sources.map(([i, e, t, p]) => `${i}:${e}:${t}:${p}`).sort();
  const p = ["x1", game, normName(name), String(saveId).toUpperCase(), parts.join(",")].join("|");
  const bytes = new TextEncoder().encode(p);
  const s = base32(hash(bytes, 5381) % 1048576, 4) + base32(hash(bytes, 52711) % 1048576, 4);
  return s.slice(0, 4) + "-" + s.slice(4);
}

// -> [[id, earned, total, points], ...] or a string saying what's wrong.
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

// Save IDs use the same alphabet as codes: read O as 0 and I/L as 1.
export function normalizeSaveId(raw) {
  return String(raw || "").replace(/\s/g, "").toUpperCase().replace(/O/g, "0").replace(/[IL]/g, "1");
}

// "12:34" -> 754 minutes; "" -> null; anything else -> undefined.
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

// Quick checks so a typo gets an instant answer.  The Action checks
// everything again (limits, name filter, ownership) before saving.
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
  const r = await fetch(`https://api.github.com/repos/${env.GITHUB_REPO}/dispatches`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "recomp-achievements-discord-bot",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ event_type: kind === "extra" ? "discord-extra" : "discord-score", client_payload: payload }),
  });
  if (r.status !== 204) throw new Error("GitHub said " + r.status);
}

// ---------------------------------------------------------- /check
// Same order as rank() in tools/leaderboard_ingest.py: most points, then
// the shorter play time (untimed entries after timed ones), then the
// earlier submission.
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

// Trainer names are shown as written; Markdown and mentions are escaped.
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

// Extra Credit ranking (rank_extra in tools/leaderboard_ingest.py): most
// points, then most achievements, then the earliest.  `source` narrows
// it to one mod's line ("bonus", "naviplay"), or null for the total.
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
    if (extra) {
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
    if (request.method !== "POST") return new Response("Recomp Achievements leaderboard bot", { status: 200 });
    const body = await request.text();
    if (!(await verify(request, body, env.DISCORD_PUBLIC_KEY))) {
      return new Response("bad signature", { status: 401 });
    }
    let interaction;
    try { interaction = JSON.parse(body); } catch (e) { return new Response("bad json", { status: 400 }); }

    if (interaction.type === 1) return json({ type: 1 }); // PING

    if (interaction.type === 2) {
      const name = interaction.data && interaction.data.name;
      if (name === "leaderboard") {
        return say(`The leaderboard: ${env.BOARD_URL}\nSubmit with \`/score\` and the card from START > TROPHIES > SELECT.`);
      }
      if (name === "check") {
        const o = options(interaction);
        const game = String(o.game || "").toLowerCase();
        if (!GAMES[game]) return say("Pick the game from the list.");
        if (!env.BOARD_URL) return say("The bot isn't set up yet. Please tell the maintainer.");
        let extra = o.extra == null ? null : String(o.extra).trim().toLowerCase();
        if (extra === "") extra = null;
        if (extra && extra !== "all" && !/^[a-z0-9_-]{1,48}$/.test(extra)) {
          return say("extra: is `all`, `bonus`, or a mod's name as it appears on the Extra Credit page.");
        }
        ctx.waitUntil(postCheck(env, interaction, game, extra));
        return json({ type: 5 }); // "thinking…", then the embed replaces it (public)
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
