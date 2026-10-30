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

There's no server to keep running and no database. The Worker is a single
file on Cloudflare's free plan. The bot never needs its bot token after
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
   It prints `registered: /score, /leaderboard, /check`. Commands can take a few
   minutes to appear in Discord.
6. **Let people use it.** On *Installation*, tick **User Install** and
   **Guild Install**, with the `applications.commands` scope (add `bot`
   for Guild Install). Share the install link. With User Install, players
   can use `/score` in a DM with the bot without sharing a server with it.
   You can also add it to your mod's Discord server.

`time` is optional so cards from mod 1.1.0 (no TIME line) still work.

## Keeping it running

- **Token expiry:** when the GitHub token expires, `/score` replies "Couldn't
  reach the leaderboard". Make a new token and run
  `npx wrangler secret put GITHUB_TOKEN` again.
- **Changing commands:** edit `COMMANDS` in `tools/discord_register.py`
  and run it again. (Updating from 1.1.0: run it once to add the `time`
  option, and `npx wrangler deploy` once for the new worker.js.)
- **Turning it off:** clear the Interactions Endpoint URL, or delete the
  Worker with `npx wrangler delete`. Issue submissions keep working.
- **Logs:** `npx wrangler tail` shows live requests. The GitHub side shows
  up under the repo's *Actions* tab like issue submissions.

## Testing

`node tests/test_discord_worker.mjs` signs fake Discord requests, stubs out
GitHub and Discord, and passes the result through the real ingest script.
