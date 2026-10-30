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
const GAMES = { red: "Pokemon Red", blue: "Pokemon Blue", yellow: "Pokemon Yellow" };
const EPHEMERAL = 64;

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
  if (!GAMES[game]) return "Pick red, blue or yellow as the game.";
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
      "(START > ACHIEVEMENTS > SELECT) and try again.";
  }
  return null;
}

async function dispatch(env, interaction, o) {
  const user = interaction.user || (interaction.member && interaction.member.user) || {};
  const payload = {
    score: {
      game: String(o.game).toLowerCase(), name: String(o.name).trim(),
      points: String(o.points), earned: String(o.earned),
      save_id: normalizeSaveId(o.save_id), code: normalizeCode(o.code),
      time: o.time == null ? "" : String(o.time).trim(),
    },
    owner: await ownerHash(env.OWNER_SALT, user.id),
    app_id: interaction.application_id,
    token: interaction.token,
  };
  const r = await fetch(`https://api.github.com/repos/${env.GITHUB_REPO}/dispatches`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "recomp-achievements-discord-bot",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ event_type: "discord-score", client_payload: payload }),
  });
  if (r.status !== 204) throw new Error("GitHub said " + r.status);
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
        return say(`The leaderboard: ${env.BOARD_URL}\nSubmit with \`/score\` and the card from START > ACHIEVEMENTS > SELECT.`);
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
