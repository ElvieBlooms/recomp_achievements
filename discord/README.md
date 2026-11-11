# Leaderboard Discord bot

Lets players submit their leaderboard card from Discord instead of opening
a GitHub issue. They DM the bot (or use it in a server):

```
/score game:Red name:ASH points:245 earned:32 save_id:43FJKR code:QGF3-VG65 time:12:34
```

The bot answers right away if the check code doesn't match (a typo).
Otherwise it says "Checking your score…" and edits that message a minute
later with the result: added, updated, or why it was refused. Only the
player can see these messages. `/leaderboard` replies with a link to the page.

`/check game:ruby` posts a small embed in the channel, visible to everyone,
with the top 3 for that game: name, points, achievements and play time,
linking to that game's tab on the page. It reads the public
`leaderboard.json`, so it needs no extra secrets. GitHub Pages can take a
few minutes to serve a new score.

`/extra game name save_id lines code` submits an Extra Credit score (bonus
and mod achievements) from the card's Extra Credit page; `lines` is every
line from the page separated by commas. `/check game:ruby extra:all` shows
the Extra Credit top 3, and `extra:bonus` or `extra:<mod>` one source's.

## How it works

```
Discord ──/score──▶ Cloudflare Worker (worker.js)
                      checks the signature and the check code
                      hashes the Discord user id
                      └─▶ GitHub repository_dispatch "discord-score"
                            └─▶ the same Action as issue submissions
                                  tools/leaderboard_ingest.py (limits, name
                                  filter, ownership), commits the board
                                  └─▶ tools/discord_reply.py edits the
                                        bot's message with the result
```

Recomp Achievements Online sends the same cards to the Worker's
`GET /auto`, which dispatches `online-score` or `online-extra` to the same
Action. `/link CODE` ties a save's key to a Discord account
(`online-link` moves its rows over).

There's no server to keep running. The Worker is a single file on
Cloudflare's free plan, and the only thing it stores is the /link codes and
links, in a KV namespace. The bot never needs its bot token after
setup, and the Action needs no Discord secrets at all: it replies using the
one-time token that comes with each command, which lasts 15 minutes.

The player's Discord id is never sent to GitHub or put on the board. The
Worker sends a keyed hash of it instead, so the same Discord account can
update its save later, a different one can't, and nobody can tell from the
public files who submitted. A save first submitted from GitHub can only be
updated from that GitHub account, and the reverse.

## Setup (about 20 minutes, once)

You need a Discord account, a free Cloudflare account and Node.js on your
computer.

1. **Create the Discord app.** At <https://discord.com/developers/applications>,
   choose *New Application* and name it (e.g. "Recomp Achievements").
   On *General Information*, upload `discord/assets/bot_icon.png` as the
   **App Icon**, then copy the **Application ID** and **Public Key**.
   On *Bot*, press *Reset Token* and copy the **bot token** (only needed in
   step 5).
2. **Make a GitHub token for the bot.** GitHub > Settings > Developer
   settings > Fine-grained tokens > *Generate new token*. Repository
   access: only `ElvieBlooms/recomp_achievements`. Permissions:
   **Contents: Read and write** (that's what allows dispatch events),
   nothing else. Pick an expiry and set a reminder to renew it.
3. **Deploy the Worker.** In this `discord/` folder:
   ```
   npx wrangler login
   npx wrangler secret put DISCORD_PUBLIC_KEY   # the Public Key from step 1
   npx wrangler secret put GITHUB_TOKEN         # the token from step 2
   npx wrangler secret put OWNER_SALT           # any long random text; never change it
   npx wrangler deploy
   ```
   Wrangler prints the Worker's address, like
   `https://recomp-achievements-bot.<you>.workers.dev`.
   `wrangler.toml` already has the repo name and page address; edit them
   if those change.
4. **Point Discord at it.** Back on *General Information*, paste the Worker
   address into **Interactions Endpoint URL** and save. Discord sends a
   test PING; if it saves, the Worker is answering.
5. **Register the commands.** From the repo root:
   ```
   DISCORD_APP_ID=<application id> DISCORD_BOT_TOKEN=<bot token> python3 tools/discord_register.py
   ```
   It prints `registered: /score, /leaderboard, /check, /extra, /link`. Commands can take a few
   minutes to appear in Discord.
6. **Let people use it.** On *Installation*, tick **User Install** and
   **Guild Install**, with the `applications.commands` scope (add `bot`
   for Guild Install). Share the install link. With User Install, players
   can use `/score` in a DM with the bot without sharing a server with it.
   You can also add it to your mod's Discord server.

`time` is optional so cards from mod 1.1.0 (no TIME line) still work.

### For Recomp Achievements Online

7. **Make the KV namespace** for /link, in `discord/`:
   ```
   npx wrangler kv namespace create LINKS
   ```
   Uncomment the `[[kv_namespaces]]` block in `wrangler.toml` and paste the
   id it printed. Uncomment `[[ratelimits]]` too: it caps each save at 10
   sends a minute, per save and per IP address. Then `npx wrangler deploy` and run
   `tools/discord_register.py` again for `/link`.
8. **Point the add-on at the Worker.** Set `SERVER` at the top of
   `recomp_achievements_online/main.lua` to the Worker address from step 3.
   `tools/build_release.sh` won't build the add-on until it's set.

Without the KV namespace the add-on still sends, but codes and `/link`
don't work. Without the rate limit, sends aren't capped (the add-on itself
waits two minutes between sends and only sends changed cards).

### The live leaderboard message

One message in your server that always shows the current board: a header
with how many trainers are on it, the top 3 for every game grouped by
generation, and Extra Credit. It's posted by a channel webhook and edited
by the leaderboard Action after every change, so it never makes a new post
or pings anyone. `tools/discord_board.py` builds it.

1. **Make a webhook** in the channel: Edit Channel > Integrations >
   Webhooks > New Webhook. Name it and give it the mod's icon, since that's
   who the message shows as. Copy its URL.
2. **Save the URL as a secret** in the GitHub repo: Settings > Secrets and
   variables > Actions > New repository secret, named
   `DISCORD_BOARD_WEBHOOK`. Anyone with the URL can post as the webhook,
   so keep it out of chat and commits.
3. **Post the message** from the Actions tab: run **Discord board** with
   action `post`.
   - In a **forum** channel, fill in `thread_name` (say, "Leaderboard").
     The webhook makes the forum post, and its first message is the board.
     It has to be this way round: a webhook can only edit its own
     messages, so it can't take over a post you made.
   - In a forum post that already exists, put its id in `thread_id`
     instead (right-click the post > Copy Link, the last number). The board
     is then a reply, so pin it.
   - In a normal text channel, leave both empty.
4. **Save the ids it prints** as repository variables (Settings > Secrets
   and variables > Actions > Variables): `DISCORD_BOARD_MESSAGE`, and
   `DISCORD_BOARD_THREAD` for a forum.

From then on it updates by itself a minute or so after each submission.
After editing `docs/leaderboard.json` by hand, run **Discord board** with
`update`. To see what it would post, run
`python3 tools/discord_board.py print`.

If the message is deleted, post a new one and replace the variables.

## Keeping it running

- **Token expiry:** when the GitHub token expires, `/score` replies "Couldn't
  reach the leaderboard". Make a new token and run
  `npx wrangler secret put GITHUB_TOKEN` again.
- **Changing commands:** edit `COMMANDS` in `tools/discord_register.py`
  and run it again. (Updating from 1.1.0: run it once to add the `time`
  option, and `npx wrangler deploy` once for the new worker.js.)
- **Turning it off:** clear the Interactions Endpoint URL, or delete the
  Worker with `npx wrangler delete`. Issue submissions keep working.
- **Online sends failing:** the card says ONLINE: NOT SENT and a short
  reason. "try again later" is GitHub refusing the dispatch (often the
  token) or the rate limit.
- **Logs:** `npx wrangler tail` shows live requests. The GitHub side shows
  up under the repo's *Actions* tab like issue submissions.

## Testing

`node tests/test_discord_worker.mjs` signs fake Discord requests, stubs out
GitHub and Discord, and passes the result through the real ingest script.
