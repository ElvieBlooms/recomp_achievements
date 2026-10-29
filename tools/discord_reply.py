#!/usr/bin/env python3
"""Post the leaderboard bot's reply back to Discord.

The Action runs this after tools/leaderboard_ingest.py for submissions
that came from the Discord bot.  It edits the bot's "checking your score"
message using the interaction token the bot passed along, which Discord
accepts for 15 minutes.  No Discord bot token is needed.

    python3 tools/discord_reply.py --event "$GITHUB_EVENT_PATH" --reply reply.md

The token is read from the event file, never from arguments or the
environment, so it doesn't show up in the public Action log.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

API = os.environ.get("DISCORD_API", "https://discord.com/api/v10")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--event", required=True)
    ap.add_argument("--reply", required=True)
    args = ap.parse_args(argv)

    with open(args.event, encoding="utf-8") as f:
        payload = json.load(f).get("client_payload") or {}
    app_id = str(payload.get("app_id", ""))
    token = str(payload.get("token", ""))
    if not re.fullmatch(r"\d{5,25}", app_id) or not re.fullmatch(r"[A-Za-z0-9_\-.]{20,600}", token):
        print("no usable interaction token in the event", file=sys.stderr)
        return 1
    try:
        with open(args.reply, encoding="utf-8") as f:
            text = f.read().strip()
    except OSError:
        text = "Something went wrong updating the board. The maintainer will take a look."
    body = json.dumps({"content": text[:1900], "allowed_mentions": {"parse": []}}).encode()
    req = urllib.request.Request(
        f"{API}/webhooks/{app_id}/{token}/messages/@original", data=body, method="PATCH",
        headers={"Content-Type": "application/json",
                 "User-Agent": "recomp-achievements-leaderboard (github actions)"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            print("discord reply:", r.status)
    except urllib.error.HTTPError as err:
        # 404 usually means the 15-minute window passed.
        print("discord reply failed:", err.code, file=sys.stderr)
        return 1
    except urllib.error.URLError as err:
        print("discord reply failed:", err.reason, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
