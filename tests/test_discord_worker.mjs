// tests/test_discord_worker.mjs
// Tests for the Discord bot in discord/worker.js.
// Requests are signed with a throwaway Ed25519 key the way Discord signs
// interactions, and GitHub and Discord are faked with a stubbed fetch.
// The dispatched payload then goes through the real tools/leaderboard_ingest.py,
// which also checks the JS and Python checksums agree.
//
//   node tests/test_discord_worker.mjs
// ------------------
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import worker, { readAuto, validKey, boardEmbed, checkCode, extraCheckCode, extraEmbed, normalizeCode, parseExtraLines, parseTime, precheck, precheckExtra, topEntries, topExtra } from "../discord/worker.js";

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
let passed = 0;
async function test(name, fn) {
  try { await fn(); passed++; console.log("  ok  " + name); }
  catch (e) { console.log("  FAIL " + name + "\n" + e.stack); process.exitCode = 1; }
}

const keys = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
const PUB = Buffer.from(await crypto.subtle.exportKey("raw", keys.publicKey)).toString("hex");
const ENV = { DISCORD_PUBLIC_KEY: PUB, GITHUB_TOKEN: "ghp_test", GITHUB_REPO: "ElvieBlooms/recomp_achievements",
              OWNER_SALT: "salt-for-tests", BOARD_URL: "https://elvieblooms.github.io/recomp_achievements/" };

async function signed(obj, { tamper = false } = {}) {
  const body = JSON.stringify(obj), ts = String(Math.floor(Date.now() / 1000));
  const sig = Buffer.from(await crypto.subtle.sign("Ed25519", keys.privateKey,
    new TextEncoder().encode(ts + body))).toString("hex");
  return new Request("https://bot.example/", {
    method: "POST", body: tamper ? body.replace("1", "2") : body,
    headers: { "X-Signature-Ed25519": sig, "X-Signature-Timestamp": ts, "Content-Type": "application/json" },
  });
}

function ctx() { const jobs = []; return { jobs, waitUntil: (p) => jobs.push(p) }; }

function stubFetch(handler) {
  const calls = [];
  globalThis.fetch = async (url, init) => { calls.push({ url: String(url), init }); return handler(String(url), init); };
  return calls;
}

function scoreInteraction(o, user = { id: "123456789012345678" }) {
  return { type: 2, application_id: "999888777666555444", token: "interaction-token-abcdefghijklmnop",
           user, data: { name: "score", options: Object.entries(o).map(([name, value]) => ({ name, value })) } };
}

const CARD = { game: "red", name: "ASH", points: 120, earned: 20, save_id: "ABC123" };
CARD.code = checkCode(CARD.game, CARD.name, CARD.points, CARD.earned, CARD.save_id);

await test("/check posts the top 3 for a game as a public embed", async () => {
  const board = { games: { ruby: { title: "Pokemon Ruby", maxPoints: 485, total: 49, entries: [
    { name: "SLOW", points: 400, earned: 39, time: 900, first: "2026-01-01" },
    { name: "FAST", points: 400, earned: 39, time: 600, first: "2026-01-02" },
    { name: "TOP_*", points: 485, earned: 49, time: 59999, first: "2026-01-03" },
    { name: "OLD", points: 400, earned: 39, time: null, first: "2025-01-01" },
    { name: "LOW", points: 3, earned: 1, time: 5, first: "2026-01-04" } ] },
    sapphire: { title: "Pokemon Sapphire", maxPoints: 485, total: 49, entries: [] } } };
  const calls = stubFetch((url) => url.includes("leaderboard.json")
    ? new Response(JSON.stringify(board), { status: 200 }) : new Response(null, { status: 200 }));
  const c = ctx();
  const r = await worker.fetch(await signed({ type: 2, application_id: "1", token: "tok",
    data: { name: "check", options: [{ name: "game", value: "ruby" }] } }), ENV, c);
  const reply = await r.json();
  assert.equal(reply.type, 5, "deferred");
  assert.equal(reply.data, undefined, "public, not ephemeral");
  await Promise.all(c.jobs);
  assert.match(calls[0].url, /^https:\/\/elvieblooms\.github\.io\/recomp_achievements\/leaderboard\.json\?t=\d+$/);
  assert.match(calls[1].url, /webhooks\/1\/tok\/messages\/@original$/);
  const sent = JSON.parse(calls[1].init.body);
  const e = sent.embeds[0];
  assert.equal(e.title, "Pokemon Ruby: top 3");
  assert.equal(e.url, "https://elvieblooms.github.io/recomp_achievements/#ruby");
  const lines = e.description.split("\n");
  assert.equal(lines.length, 3);
  assert.match(lines[0], /TOP\\_\\\*\*\*  485 \/ 485 pts · 49\/49 · 999:59$/);
  assert.match(lines[1], /\*\*FAST\*\*  400 \/ 485 pts · 39\/49 · 10:00$/, "equal points: shorter time first");
  assert.match(lines[2], /\*\*SLOW\*\*/, "timed before untimed");
  assert.equal(e.footer.text, "5 trainers on the board");
  assert.deepEqual(sent.allowed_mentions, { parse: [] });

  const empty = boardEmbed("sapphire", board.games.sapphire, ENV.BOARD_URL);
  assert.match(empty.description, /No scores yet/);
  assert.equal(topEntries(undefined).length, 0);
  assert.match(boardEmbed("red", { entries: [{ name: "@everyone", points: 1, earned: 1 }] }, "").description,
    /@​everyone/, "mentions defused");
});

await test("/check: unknown game, and the board unreachable", async () => {
  let r = await worker.fetch(await signed({ type: 2, data: { name: "check", options: [{ name: "game", value: "diamond" }] } }), ENV, ctx());
  assert.match((await r.json()).data.content, /from the list/);
  const calls = stubFetch((url) => new Response("nope", { status: url.includes("leaderboard.json") ? 503 : 200 }));
  const c = ctx();
  r = await worker.fetch(await signed({ type: 2, application_id: "1", token: "tok",
    data: { name: "check", options: [{ name: "game", value: "red" }] } }), ENV, c);
  assert.equal((await r.json()).type, 5);
  await Promise.all(c.jobs);
  assert.match(JSON.parse(calls[1].init.body).content, /Couldn't load the leaderboard/);
});

await test("Extra Credit: code matches Lua/Python, lines parse, precheck", () => {
  assert.equal(extraCheckCode("red", "ash", "abc123", [["naviplay", 12, 25, 85], ["bonus", 3, 9, 20]]), "G519-TP8B");
  assert.deepEqual(parseExtraLines("bonus 3/9 20; NaviPlay 12 / 25 85pts"), [["bonus", 3, 9, 20], ["naviplay", 12, 25, 85]]);
  assert.match(parseExtraLines("bonus 3/9 999"), /can't come from/);
  assert.match(parseExtraLines("hi"), /isn't a line/);
  const ok = { game: "ruby", name: "MAY", save_id: "abc123", lines: "bonus 3/9 20, naviplay 12/25 85",
               code: extraCheckCode("ruby", "MAY", "ABC123", [["bonus", 3, 9, 20], ["naviplay", 12, 25, 85]]) };
  assert.equal(precheckExtra(ok), null);
  assert.match(precheckExtra({ ...ok, lines: "bonus 3/9 21, naviplay 12/25 85" }), /extra code/);
});

await test("/extra dispatches discord-extra; Python accepts it", async () => {
  const lines = "bonus 3/9 20, naviplay 12/25 85";
  const code = extraCheckCode("ruby", "MAY", "ABC123", [["bonus", 3, 9, 20], ["naviplay", 12, 25, 85]]);
  const calls = stubFetch(() => new Response(null, { status: 204 }));
  const c = ctx();
  const r = await worker.fetch(await signed({ type: 2, application_id: "1", token: "tok", user: { id: "42" },
    data: { name: "extra", options: [{ name: "game", value: "ruby" }, { name: "name", value: "MAY" },
      { name: "save_id", value: "ABC123" }, { name: "lines", value: lines }, { name: "code", value: code }] } }), ENV, c);
  assert.match((await r.json()).data.content, /Checking your Extra Credit/);
  await Promise.all(c.jobs);
  const sent = JSON.parse(calls[0].init.body);
  assert.equal(sent.event_type, "discord-extra");
  assert.equal(sent.client_payload.extra.extra, lines);
  assert.equal(sent.client_payload.score, undefined);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "extra-"));
  const ev = path.join(dir, "ev.json");
  fs.writeFileSync(ev, JSON.stringify({ action: "discord-extra", client_payload: sent.client_payload }));
  const out = execFileSync("python3", [path.join(ROOT, "tools", "leaderboard_ingest.py"), "--event", ev,
    "--board", path.join(dir, "board.json"), "--reply", path.join(dir, "reply.md")], { encoding: "utf8" });
  assert.match(out, /added extra/);
});

await test("/check extra: combined and per-mod embeds", async () => {
  const board = { games: {}, extra: { ruby: { entries: [
    { name: "MAY", points: 105, earned: 15, first: "1", sources: { bonus: { earned: 3, total: 9, points: 20 }, naviplay: { earned: 12, total: 25, points: 85 } } },
    { name: "BRENDAN", points: 50, earned: 9, first: "2", sources: { bonus: { earned: 9, total: 9, points: 50 } } } ] } } };
  const all = extraEmbed("ruby", board.extra.ruby, null, ENV.BOARD_URL);
  assert.match(all.title, /Extra Credit: top 2/);
  assert.match(all.description.split("\n")[0], /MAY\*\*  105 pts · 15 achievements/);
  const bonus = extraEmbed("ruby", board.extra.ruby, "bonus", ENV.BOARD_URL);
  assert.match(bonus.description.split("\n")[0], /BRENDAN\*\*  50 pts · 9\/9/, "per-mod board ranks that mod's points");
  assert.equal(bonus.url, "https://elvieblooms.github.io/recomp_achievements/#ruby/extra/bonus");
  assert.equal(topExtra(board.extra.ruby.entries, "naviplay").count, 1);
  const calls = stubFetch((url) => url.includes("leaderboard.json")
    ? new Response(JSON.stringify(board), { status: 200 }) : new Response(null, { status: 200 }));
  const c = ctx();
  await worker.fetch(await signed({ type: 2, application_id: "1", token: "tok",
    data: { name: "check", options: [{ name: "game", value: "ruby" }, { name: "extra", value: "NaviPlay" }] } }), ENV, c);
  await Promise.all(c.jobs);
  assert.match(JSON.parse(calls[1].init.body).embeds[0].title, /naviplay: top 1/);
  const r = await worker.fetch(await signed({ type: 2, data: { name: "check",
    options: [{ name: "game", value: "ruby" }, { name: "extra", value: "no spaces allowed" }] } }), ENV, ctx());
  assert.match((await r.json()).data.content, /extra:/);
});

await test("check code matches the Python and Lua vectors", () => {
  assert.equal(checkCode("red", "ASH", 120, 20, "ABC123"), "DHC0-HH32");
  assert.equal(checkCode("yellow", "red ", 0, 0, "ZZZZZZ"), "1F4B-5EVD");
  assert.equal(checkCode("blue", "Gary♂", 678, 90, "0K3M9Q"), "1AB3-YHC5");
  assert.equal(normalizeCode("dhcohh32"), "DHC0-HH32");
});

await test("v2 codes (with play time) match Python and Lua", () => {
  assert.equal(checkCode("red", "ASH", 745, 93, "ABC123", 754), "K8ZM-8GYP");
  assert.equal(checkCode("red", "ASH", 745, 93, "ABC123", 0), "ESH4-99C6");
  assert.equal(checkCode("blue", "Gary\u2642", 678, 90, "0K3M9Q", 59999), "0A0S-ZNDV");
  assert.equal(parseTime("12:34"), 754);
  assert.equal(parseTime(""), null);
  assert.equal(parseTime(undefined), null);
  assert.equal(parseTime("12:60"), undefined);
  const timed = { ...CARD, time: "12:34", code: checkCode("red", "ASH", 120, 20, "ABC123", 754) };
  assert.equal(precheck(timed), null);
  assert.match(precheck({ ...timed, time: "12:43" }), /check code/);
  assert.match(precheck({ ...timed, time: "soon" }), /H:MM/);
  assert.match(precheck({ ...timed, time: undefined }), /TIME line/, "hint when the time is left out");
  assert.doesNotMatch(precheck({ ...timed, time: "12:43" }), /TIME line/);
  assert.equal(precheck({ ...timed, save_id: "abc123" }), null);
  const zero = { ...CARD, save_id: "3N0S2H", code: checkCode("red", "ASH", 120, 20, "3N0S2H") };
  assert.equal(precheck({ ...zero, save_id: "3NOS2H" }), null, "O typed for 0");
});

await test("check code matches Python on 40 random cards", () => {
  const cards = [];
  for (let i = 0; i < 40; i++) {
    cards.push([["red", "blue", "yellow"][i % 3], ["ASH", "red", "a b", "PIKA♀", "x"][i % 5],
      (i * 37) % 700, (i * 7) % 90, String(i * 12345 % 999999).padStart(6, "0"),
      i % 4 === 0 ? null : i * 97 % 60000]);
  }
  const py = execFileSync("python3", ["-c",
    "import sys,json;sys.path.insert(0,sys.argv[1]);import leaderboard_ingest as L\n" +
    "print('\\n'.join(L.check_code(*c) for c in json.load(sys.stdin)))", path.join(ROOT, "tools")],
    { input: JSON.stringify(cards) }).toString().trim().split("\n");
  cards.forEach((c, i) => assert.equal(checkCode(...c), py[i], JSON.stringify(c)));
});

await test("rejects a bad signature", async () => {
  const r = await worker.fetch(await signed({ type: 1 }, { tamper: true }), ENV, ctx());
  assert.equal(r.status, 401);
});

await test("answers Discord's PING", async () => {
  const r = await worker.fetch(await signed({ type: 1 }), ENV, ctx());
  assert.deepEqual(await r.json(), { type: 1 });
});

await test("/leaderboard links the page, privately", async () => {
  const r = await worker.fetch(await signed({ type: 2, data: { name: "leaderboard" } }), ENV, ctx());
  const j = await r.json();
  assert.equal(j.data.flags, 64);
  assert.match(j.data.content, /elvieblooms\.github\.io/);
});

await test("/score with a typo answers at once and sends nothing", async () => {
  const calls = stubFetch(() => new Response(null, { status: 204 }));
  const c = ctx();
  const r = await worker.fetch(await signed(scoreInteraction({ ...CARD, points: 121 })), ENV, c);
  assert.match((await r.json()).data.content, /check code/);
  assert.equal(c.jobs.length, 0);
  assert.equal(calls.length, 0);
  assert.match(precheck({ ...CARD, game: "diamond" }), /from the list/);
  assert.equal(precheck({ ...CARD, game: "gold", code: checkCode("gold", "ASH", 120, 20, "ABC123") }), null, "gold accepted");
  assert.match(precheck({ ...CARD, save_id: "AB" }), /save ID/);
});

let dispatched = null;
await test("/score sends a dispatch with a hashed sender and no raw user id", async () => {
  const calls = stubFetch(() => new Response(null, { status: 204 }));
  const c = ctx();
  const r = await worker.fetch(await signed(scoreInteraction({ ...CARD, code: CARD.code.toLowerCase().replace("-", "") },
    { id: "123456789012345678", username: "ash" })), ENV, c);
  assert.match((await r.json()).data.content, /Checking/);
  await Promise.all(c.jobs);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://api.github.com/repos/ElvieBlooms/recomp_achievements/dispatches");
  assert.equal(calls[0].init.headers.Authorization, "Bearer ghp_test");
  dispatched = JSON.parse(calls[0].init.body);
  assert.equal(dispatched.event_type, "discord-score");
  const p = dispatched.client_payload;
  assert.equal(p.score.code, CARD.code);
  assert.match(p.owner, /^[0-9a-f]{32}$/);
  assert.ok(!calls[0].init.body.includes("123456789012345678"), "user id leaked");
  assert.ok(!calls[0].init.body.includes("\"ash\""), "username leaked");
  assert.equal(p.token, "interaction-token-abcdefghijklmnop");
});

await test("same Discord user always gets the same owner; others don't", async () => {
  const owners = [];
  for (const user of [{ id: "1" }, { id: "1" }, { id: "2" }]) {
    const calls = stubFetch(() => new Response(null, { status: 204 }));
    const c = ctx();
    await worker.fetch(await signed({ ...scoreInteraction(CARD), user: undefined, member: { user } }), ENV, c);
    await Promise.all(c.jobs);
    owners.push(JSON.parse(calls[0].init.body).client_payload.owner);
  }
  assert.equal(owners[0], owners[1]);
  assert.notEqual(owners[0], owners[2]);
});

await test("if GitHub is down, the Discord message says so", async () => {
  const calls = stubFetch((url) => new Response(null, { status: url.includes("github") ? 503 : 200 }));
  const c = ctx();
  await worker.fetch(await signed(scoreInteraction(CARD)), ENV, c);
  await Promise.all(c.jobs);
  assert.equal(calls.length, 2);
  assert.match(calls[1].url, /discord\.com\/api\/v10\/webhooks\/999888777666555444\/interaction-token-abcdefghijklmnop\/messages\/@original/);
  assert.match(JSON.parse(calls[1].init.body).content, /try again/);
});

await test("the dispatched payload goes through the real ingest script", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "lb-"));
  const event = path.join(dir, "event.json"), board = path.join(dir, "board.json"), reply = path.join(dir, "reply.md");
  // GitHub delivers a repository_dispatch event with its event_type as the action.
  fs.writeFileSync(event, JSON.stringify({ action: "discord-score", client_payload: dispatched.client_payload }));
  execFileSync("python3", [path.join(ROOT, "tools", "leaderboard_ingest.py"), "--event", event,
    "--board", board, "--reply", reply, "--now", "2026-10-29T00:00:00Z"]);
  const entry = JSON.parse(fs.readFileSync(board, "utf8")).games.red.entries[0];
  assert.equal(entry.name, "ASH");
  assert.equal(entry.points, 120);
  assert.equal(entry.via, "discord");
  assert.equal(entry.owner, "discord:" + dispatched.client_payload.owner);
  assert.ok(!("github" in entry));
  assert.match(fs.readFileSync(reply, "utf8"), /\/score/);
});

// ---------------------------------------------------------- online add-on
function memoryKV() {
  const m = new Map();
  return { m,
    get: async (k) => (m.has(k) ? m.get(k) : null),
    put: async (k, v) => { m.set(k, v); },
    delete: async (k) => { m.delete(k); } };
}

// The URL the add-on's client.lua builds, so both ends are tested together.
function luaUrl(kind, card, key) {
  const lua = `local C = dofile(${JSON.stringify(path.join(ROOT, "recomp_achievements_online", "client.lua"))})
    local card = ${card}
    io.write(C.${kind}Url("https://bot.example", ${JSON.stringify(key)}, card))`;
  return execFileSync("luajit", ["-e", lua], { encoding: "utf8" });
}

function ingest(event) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "lb-"));
  const file = path.join(dir, "event.json"), reply = path.join(dir, "reply.md");
  fs.writeFileSync(file, JSON.stringify(event));
  let rc = 0;
  try {
    execFileSync("python3", [path.join(ROOT, "tools", "leaderboard_ingest.py"), "--event", file,
      "--board", onlineBoard, "--reply", reply, "--now", "2026-11-07T00:00:00Z"]);
  } catch (e) { rc = e.status; }
  return { rc, reply: fs.readFileSync(reply, "utf8"), board: JSON.parse(fs.readFileSync(onlineBoard, "utf8")) };
}
const onlineBoard = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "lb-")), "board.json");
const KEY = "ABCDEFGHJKMNPQRSTVWXYZ01";
let onlineCode, firstSend;

await test("online: client.lua's URL checks, sends online-score and hands out a link code", async () => {
  const url = luaUrl("score", `{ game = "red", name = "ASH", points = 120, earned = 20, saveId = "ABC123", code = ${JSON.stringify(CARD.code)} }`, KEY);
  assert.match(url, /^https:\/\/bot\.example\/auto\?v=1&k=ABCDEFGHJKMNPQRSTVWXYZ01&kind=score&game=red&name=ASH/);
  const env = { ...ENV, LINKS: memoryKV() };
  const calls = stubFetch(() => new Response(null, { status: 204 }));
  const r = await worker.fetch(new Request(url), env, ctx());
  const body = await r.text();
  assert.match(body, /^ok code [0-9A-Z]{4}-[0-9A-Z]{4}$/);
  onlineCode = body.slice(8);
  firstSend = JSON.parse(calls[0].init.body);
  assert.equal(firstSend.event_type, "online-score");
  assert.match(firstSend.client_payload.owner, /^online:[0-9a-f]{32}$/);
  assert.ok(!calls[0].init.body.includes(KEY), "the key itself never reaches GitHub");
  const again = await (await worker.fetch(new Request(url), env, ctx())).text();
  assert.equal(again, body, "same code until it expires");
  globalThis.onlineEnv = env;
});

await test("online: the send reaches the board, owned by the save", () => {
  const got = ingest({ action: "online-score", client_payload: firstSend.client_payload });
  assert.equal(got.rc, 0, got.reply);
  const e = got.board.games.red.entries[0];
  assert.equal(e.via, "online");
  assert.equal(e.owner, firstSend.client_payload.owner);
});

await test("online: /link moves the save's rows to the Discord account", async () => {
  const env = globalThis.onlineEnv;
  const calls = stubFetch(() => new Response(null, { status: 204 }));
  const c = ctx();
  const link = (code, id) => signed({ type: 2, application_id: "999888777666555444",
    token: "interaction-token-abcdefghijklmnop", user: { id },
    data: { name: "link", options: [{ name: "code", value: code }] } });
  const r = await worker.fetch(await link(onlineCode.toLowerCase().replace("-", " "), "42"), env, c);
  assert.match((await r.json()).data.content, /^Linked/);
  await Promise.all(c.jobs);
  const d = JSON.parse(calls[0].init.body);
  assert.equal(d.event_type, "online-link");
  assert.equal(d.client_payload.from, firstSend.client_payload.owner);
  assert.match(d.client_payload.to, /^discord:[0-9a-f]{32}$/);
  const got = ingest({ action: "online-link", client_payload: d.client_payload });
  assert.equal(got.rc, 0);
  assert.match(got.reply, /1 score moved/);
  assert.equal(got.board.games.red.entries[0].owner, d.client_payload.to);
  // the code is used up
  const again = await worker.fetch(await link(onlineCode, "43"), env, ctx());
  assert.match((await again.json()).data.content, /expired/);
  // later sends go as the Discord account
  const calls2 = stubFetch(() => new Response(null, { status: 204 }));
  const url = luaUrl("score", `{ game = "red", name = "ASH", points = 120, earned = 20, saveId = "ABC123", code = ${JSON.stringify(CARD.code)} }`, KEY);
  assert.equal(await (await worker.fetch(new Request(url), env, ctx())).text(), "ok linked");
  const p = JSON.parse(calls2[0].init.body).client_payload;
  assert.equal(p.owner, d.client_payload.to);
  assert.equal(p.alias, d.client_payload.from);
});

await test("online: a linked save takes over rows it sent before /link", () => {
  const board = JSON.parse(fs.readFileSync(onlineBoard, "utf8"));
  board.games.red.entries[0].owner = firstSend.client_payload.owner; // as if the relink never ran
  fs.writeFileSync(onlineBoard, JSON.stringify(board));
  const got = ingest({ action: "online-score", client_payload: {
    ...firstSend.client_payload, owner: "discord:" + "ab".repeat(16), alias: firstSend.client_payload.owner } });
  assert.equal(got.rc, 0, got.reply);
  assert.equal(got.board.games.red.entries[0].owner, "discord:" + "ab".repeat(16));
  const stranger = ingest({ action: "online-score", client_payload: { ...firstSend.client_payload, owner: "online:" + "cd".repeat(16) } });
  assert.equal(stranger.rc, 1, "someone else's key can't take the row");
});

await test("online: Extra Credit from client.lua checks too", async () => {
  const sources = [["bonus", 3, 9, 20], ["naviplay", 1, 4, 10]];
  const code = extraCheckCode("emerald", "MAY", "6F4FB8", sources);
  const url = luaUrl("extra", `{ game = "emerald", name = "MAY", saveId = "6F4FB8", code = ${JSON.stringify(code)},
    sources = { { id = "bonus", earned = 3, total = 9, points = 20 }, { id = "naviplay", earned = 1, total = 4, points = 10 } } }`, KEY);
  const calls = stubFetch(() => new Response(null, { status: 204 }));
  assert.equal(await (await worker.fetch(new Request(url), { ...ENV }, ctx())).text(), "ok");
  assert.equal(JSON.parse(calls[0].init.body).event_type, "online-extra");
});

await test("online: bad cards and old clients get a short error and send nothing", async () => {
  const calls = stubFetch(() => new Response(null, { status: 204 }));
  const base = `https://bot.example/auto?v=1&k=${KEY}&kind=score&game=red&name=ASH&points=121&earned=20&save_id=ABC123&code=${CARD.code}`;
  assert.equal(await (await worker.fetch(new Request(base), ENV, ctx())).text(), "error card didn't check");
  assert.equal(await (await worker.fetch(new Request(base.replace("v=1", "v=9")), ENV, ctx())).text(), "error update the mod");
  assert.equal(await (await worker.fetch(new Request(base.replace(KEY, "short")), ENV, ctx())).text(), "error bad key");
  assert.equal(calls.length, 0);
  assert.ok(validKey(KEY) && !validKey(KEY.toLowerCase()));
  assert.equal(readAuto(new URLSearchParams("v=1&k=" + KEY + "&kind=other")).problem, "update the mod");
  const limited = { ...ENV, AUTO_LIMIT: { limit: async () => ({ success: false }) } };
  const ok = base.replace("points=121", "points=120");
  assert.equal(await (await worker.fetch(new Request(ok), limited, ctx())).text(), "error try again later");
  const down = stubFetch(() => new Response(null, { status: 503 }));
  assert.equal(await (await worker.fetch(new Request(ok), ENV, ctx())).text(), "error try again later");
  assert.equal(down.length, 1);
});

console.log(`\n${passed} passed`);
