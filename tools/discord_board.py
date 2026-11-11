#!/usr/bin/env python3
# tools/discord_board.py
"""Keep a live copy of the leaderboard in one Discord message.

The message is posted once through a channel webhook, then edited after
every board change by .github/workflows/leaderboard.yml. A webhook can only
edit its own messages, so for a forum the webhook makes the post itself
(--thread-name) and its first message is the board.

    # once, to make the message (prints the ids to save in the repo)
    DISCORD_BOARD_WEBHOOK=https://discord.com/api/webhooks/... \\
        python3 tools/discord_board.py post --thread-name "Leaderboard"

    # after each change (the Action does this)
    python3 tools/discord_board.py update

    # see what it would send
    python3 tools/discord_board.py print

The webhook URL is a secret (anyone with it can post as the webhook), so it
only comes from the environment and is never printed. DISCORD_BOARD_MESSAGE
and DISCORD_BOARD_THREAD are plain ids. update does nothing and exits 0 when
they aren't set, so the Action works before any of this is set up.

The ranking is the board's own (rank and rank_extra in
leaderboard_ingest.py), and the colours match discord/worker.js.
"""
# ------------------

import argparse
import calendar
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import leaderboard_ingest as L  # noqa: E402

BOARD_URL = "https://elvieblooms.github.io/recomp_achievements"
USER_AGENT = "DiscordBot (https://github.com/ElvieBlooms/recomp_achievements, 1)"
WEBHOOK = re.compile(r"https://(?:canary\.|ptb\.)?discord(?:app)?\.com/api/webhooks/\d+/[\w-]+")
MEDALS = ["\U0001F947", "\U0001F948", "\U0001F949"]

GENERATIONS = [
    ("Generation I", ["red", "blue", "yellow"], 0xC0392B),
    ("Generation II", ["gold", "silver", "crystal"], 0xA8801A),
    ("Generation III: Hoenn", ["ruby", "sapphire", "emerald"], 0x1F8F6A),
    ("Generation III: Kanto", ["firered", "leafgreen"], 0xD9622B),
]

# Discord's limits for one message.
MAX_EMBEDS, MAX_TOTAL, MAX_FIELD = 10, 6000, 1024


def plain(s):
    """A name as plain text: no markdown, no pings."""
    s = re.sub(r"([\\*_~`|>#\[\]()-])", r"\\\1", str(s))
    return s.replace("@", "@​")


def short_title(game):
    return L.GAMES[game]["title"].replace("Pokemon ", "")


def unix(stamp):
    """2026-11-10T10:11:24Z -> seconds, or None."""
    try:
        t = datetime.datetime.strptime(str(stamp), "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    return calendar.timegm(t.timetuple())


def top_lines(entries, extra=False):
    entries = [dict(e) for e in entries if isinstance(e, dict) and isinstance(e.get("name"), str)]
    for e in entries:
        e["points"], e["earned"] = int(e.get("points") or 0), int(e.get("earned") or 0)
    (L.rank_extra if extra else L.rank)(entries)
    lines = []
    for i, e in enumerate(entries[:3]):
        lines.append(f"{MEDALS[i]} **{plain(e['name'])}** {e['points']} pts")
    return lines


def trainers(board):
    owners = set()
    for section in ("games", "extra"):
        for slot in board.get(section, {}).values():
            for e in slot.get("entries", []):
                owners.add(L.owner_of(e))
    return len(owners)


def build(board, board_url=BOARD_URL):
    """The message body: a header, one embed per generation, Extra Credit."""
    base = board_url.rstrip("/")
    games = board.get("games", {})
    played = [g for g in L.GAMES if games.get(g, {}).get("entries")]
    count = trainers(board)
    when = unix(board.get("updated"))
    desc = [f"**{count}** trainer{'' if count == 1 else 's'} across **{len(played)}** "
            f"game{'' if len(played) == 1 else 's'}."
            + (f" Updated <t:{when}:R>." if when else "")]
    desc.append("Install **Recomp Achievements Online** and your score goes up when you save, "
                "or send your card with `/score`. `/check` shows any game's top 3.")
    embeds = [{
        "title": "Recomp Achievements leaderboard",
        "url": base + "/",
        "color": 0x2B8FA8,
        "description": "\n".join(desc),
    }]
    for title, ids, color in GENERATIONS:
        fields, people = [], 0
        for g in ids:
            entries = games.get(g, {}).get("entries", [])
            people += len(entries)
            lines = top_lines(entries)
            fields.append({"name": short_title(g), "inline": True,
                           "value": ("\n".join(lines) or "*No scores yet*")[:MAX_FIELD]})
        embeds.append({
            "title": title, "url": f"{base}/#{ids[0]}", "color": color, "fields": fields,
            "footer": {"text": f"{people} on the board" if people else "Be the first"},
        })
    extra_fields, first = [], None
    for g in L.GAMES:
        lines = top_lines(board.get("extra", {}).get(g, {}).get("entries", []), extra=True)
        if lines:
            first = first or g
            extra_fields.append({"name": short_title(g), "inline": True, "value": "\n".join(lines)[:MAX_FIELD]})
    extra = {"title": "Extra Credit", "url": f"{base}/#{first or 'red'}/extra", "color": 0x6F7A86,
             "footer": {"text": "Bonus and mod achievements. Kept apart from the main board."}}
    if extra_fields:
        extra["fields"] = extra_fields
    else:
        extra["description"] = "*No Extra Credit yet*"
    embeds.append(extra)
    return {"embeds": embeds[:MAX_EMBEDS], "allowed_mentions": {"parse": []}}


def size(message):
    """Characters Discord counts toward its 6000 per message."""
    n = 0
    for e in message["embeds"]:
        n += len(e.get("title", "")) + len(e.get("description", ""))
        n += len(e.get("footer", {}).get("text", ""))
        for f in e.get("fields", []):
            n += len(f["name"]) + len(f["value"])
    return n


def request(method, url, body, opener=urllib.request.urlopen):
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Content-Type": "application/json", "User-Agent": USER_AGENT})
    try:
        with opener(req, timeout=20) as r:
            text = r.read().decode("utf-8") or "{}"
            return r.status, json.loads(text)
    except urllib.error.HTTPError as e:
        return e.code, {"message": e.read().decode("utf-8", "replace")[:200]}


def webhook_from_env():
    url = os.environ.get("DISCORD_BOARD_WEBHOOK", "").strip()
    if not url:
        return None
    if not WEBHOOK.fullmatch(url):
        raise SystemExit("discord_board: DISCORD_BOARD_WEBHOOK doesn't look like a Discord webhook URL")
    return url


def post(board, thread_name=None, thread_id=None, opener=urllib.request.urlopen):
    url = webhook_from_env()
    if not url:
        raise SystemExit("discord_board: set DISCORD_BOARD_WEBHOOK first")
    body = build(board)
    query = "?wait=true"
    if thread_id:
        query += "&thread_id=" + str(int(thread_id))
    elif thread_name:
        body["thread_name"] = str(thread_name)[:100]
    status, got = request("POST", url + query, body, opener)
    if status != 200:
        raise SystemExit(f"discord_board: Discord said {status}: {got.get('message', '')}")
    print("Posted. Add these as repository variables (Settings > Secrets and variables >")
    print("Actions > Variables):")
    print(f"  DISCORD_BOARD_MESSAGE = {got['id']}")
    if thread_id or thread_name:
        print(f"  DISCORD_BOARD_THREAD = {got.get('channel_id', thread_id)}")
    return got


def update(board, opener=urllib.request.urlopen):
    url = webhook_from_env()
    message = os.environ.get("DISCORD_BOARD_MESSAGE", "").strip()
    thread = os.environ.get("DISCORD_BOARD_THREAD", "").strip()
    if not (url and message):
        print("discord_board: not set up, nothing to update")
        return 0
    if not message.isdigit() or (thread and not thread.isdigit()):
        raise SystemExit("discord_board: DISCORD_BOARD_MESSAGE and DISCORD_BOARD_THREAD are numbers")
    target = f"{url}/messages/{message}" + (f"?thread_id={thread}" if thread else "")
    body = build(board)
    status, got = request("PATCH", target, body, opener)
    if status != 200:
        print(f"discord_board: Discord said {status}: {got.get('message', '')}", file=sys.stderr)
        return 1
    print("discord_board: updated")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("action", choices=["update", "post", "print"])
    ap.add_argument("--board", default=os.path.join(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))), "docs", "leaderboard.json"))
    ap.add_argument("--thread-name", help="post: make a forum post with this title")
    ap.add_argument("--thread-id", help="post: into this existing thread")
    args = ap.parse_args(argv)
    board = L.load_board(args.board)
    if args.action == "print":
        message = build(board)
        print(json.dumps(message, indent=1, ensure_ascii=False))
        print(f"{size(message)} of {MAX_TOTAL} characters", file=sys.stderr)
        return 0
    if args.action == "post":
        post(board, args.thread_name, args.thread_id)
        return 0
    return update(board)


if __name__ == "__main__":
    sys.exit(main())
