// Tests for discord/worker.js.   node tests/test_discord_worker.mjs
// Signs requests with a throwaway Ed25519 key the way Discord does, fakes
// GitHub and Discord with a stubbed fetch, and hands the dispatched
// payload to the real tools/leaderboard_ingest.py.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import worker, { boardEmbed, checkCode, normalizeCode, parseTime, precheck, topEntries } from "../discord/worker.js";

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
  // GitHub delivers repository_dispatch with action = event_type.
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

console.log(`\n${passed} passed`);
