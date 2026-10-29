#!/usr/bin/env python3
"""Register the Discord bot's slash commands (run once, and again after
changing COMMANDS).

    DISCORD_APP_ID=... DISCORD_BOT_TOKEN=... python3 tools/discord_register.py

Both values are on the Discord developer portal.  The token is only used
for this call; the bot itself (discord/worker.js) never needs it.  Don't
commit it.  --dry-run prints the commands instead of sending them.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

# Usable in servers, in DMs with the bot and in other DMs, whether the bot
# was added to a server or installed by the user.
WHERE = {"integration_types": [0, 1], "contexts": [0, 1, 2]}

COMMANDS = [
    dict(WHERE, name="score", type=1,
         description="Put your Recomp Achievements score on the leaderboard",
         options=[
             {"type": 3, "name": "game", "description": "GAME on the card", "required": True,
              "choices": [{"name": "Red", "value": "red"}, {"name": "Blue", "value": "blue"},
                          {"name": "Yellow", "value": "yellow"}]},
             {"type": 3, "name": "name", "description": "TRAINER on the card",
              "required": True, "max_length": 12},
             {"type": 4, "name": "points", "description": "First number after POINTS",
              "required": True, "min_value": 0, "max_value": 9999},
             {"type": 4, "name": "earned", "description": "First number after EARNED",
              "required": True, "min_value": 0, "max_value": 999},
             {"type": 3, "name": "save_id", "description": "SAVE ID on the card",
              "required": True, "min_length": 6, "max_length": 6},
             {"type": 3, "name": "code", "description": "CHECK on the card (XXXX-XXXX)",
              "required": True, "min_length": 8, "max_length": 9},
         ]),
    dict(WHERE, name="leaderboard", type=1,
         description="Link to the Recomp Achievements leaderboard"),
]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    if args.dry_run:
        print(json.dumps(COMMANDS, indent=1))
        return 0
    app_id = os.environ.get("DISCORD_APP_ID", "").strip()
    token = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    if not app_id or not token:
        print("set DISCORD_APP_ID and DISCORD_BOT_TOKEN", file=sys.stderr)
        return 1
    req = urllib.request.Request(
        f"https://discord.com/api/v10/applications/{app_id}/commands",
        data=json.dumps(COMMANDS).encode(), method="PUT",
        headers={"Authorization": f"Bot {token}", "Content-Type": "application/json",
                 "User-Agent": "recomp-achievements-register (python)"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            names = [c["name"] for c in json.load(r)]
            print("registered:", ", ".join("/" + n for n in names))
    except urllib.error.HTTPError as err:
        print("Discord said", err.code, err.read().decode(errors="replace")[:500], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
