#!/usr/bin/env python3
"""Read one leaderboard submission and update docs/leaderboard.json.

Submissions come from two places, both handled by the GitHub Action in
.github/workflows/leaderboard.yml:

  * a GitHub issue made from the "Submit a leaderboard score" form, and
  * the Discord bot (discord/worker.js), which sends a repository_dispatch
    event of type "discord-score".

The Action passes --event "$GITHUB_EVENT_PATH"; the script reads whichever
kind of event it is.  For a quick manual run you can use environment
variables instead:

    ISSUE_BODY="$(cat body.md)" ISSUE_NUMBER=7 ISSUE_AUTHOR=someone \
        python3 tools/leaderboard_ingest.py --board docs/leaderboard.json

It never talks to the network.  It writes a short Markdown reply to
--reply (the Action posts it on the issue or in Discord) and exits 0 when
the entry was accepted, 1 when it was rejected and 2 on a bug.

The CHECK CODE is a checksum, not a signature.  It catches typos; it does
not stop anyone who reads the mod's source from making up a score.  The
board is an honor system and says so.

The checksum must match recomp_achievements/ui/share.lua exactly.
"""

import argparse
import datetime
import json
import os
import re
import sys

ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

# Official RetroAchievements totals per game, as counted by the mod (see
# docs/COVERAGE.md).  Submissions above these are rejected.  Update them
# when the catalogs change; tests/run.lua checks they match the mod.
GAMES = {
    "red":    {"title": "Pokemon Red",    "maxPoints": 745, "total": 93},
    "blue":   {"title": "Pokemon Blue",   "maxPoints": 678, "total": 90},
    "yellow": {"title": "Pokemon Yellow", "maxPoints": 458, "total": 76},
}

NAME_MAX = 12  # Gen 1 names are 7 characters; leave room for imports
BLOCKLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "name_blocklist.txt")


# ---------------------------------------------------------------- checksum
def norm_name(name):
    """Drop ASCII whitespace and upper-case ASCII letters only, like Lua's
    gsub("%s", "") and string.upper."""
    out = []
    for ch in name:
        if ch in " \t\n\v\f\r":
            continue
        out.append(ch.upper() if "a" <= ch <= "z" else ch)
    return "".join(out)


def _hash(data, seed):
    h = seed
    for b in data:
        h = (h * 33 + b) % 4294967296
    return h


def _base32(n, digits):
    out = []
    for _ in range(digits):
        out.append(ALPHABET[n % 32])
        n //= 32
    return "".join(reversed(out))


def payload(game, name, points, earned, save_id, minutes=None):
    """v2 (mod 1.2.0+) includes the play time in minutes; v1 (1.1.0) doesn't."""
    parts = ["v1" if minutes is None else "v2", game, norm_name(name), str(points),
             str(earned), save_id.upper()]
    if minutes is not None:
        parts.append(str(minutes))
    return "|".join(parts)


def check_code(game, name, points, earned, save_id, minutes=None):
    p = payload(game, name, points, earned, save_id, minutes).encode("utf-8")
    a = _hash(p, 5381) % 1048576
    b = _hash(p, 52711) % 1048576
    s = _base32(a, 4) + _base32(b, 4)
    return s[:4] + "-" + s[4:]


def normalize_code(code):
    """Accept lower case, missing dash, and the usual Crockford look-alikes."""
    c = re.sub(r"[\s\-]", "", code.upper())
    c = c.replace("O", "0").replace("I", "1").replace("L", "1")
    return c[:4] + "-" + c[4:] if len(c) == 8 else c


# ------------------------------------------------------------ name filter
LEET = {"0": "o", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
        "@": "a", "$": "s", "!": "i", "|": "l", "+": "t"}


def load_blocklist(path=BLOCKLIST):
    lists = {"contains": set(), "exact": set()}
    section = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip().lower()
            if not line:
                continue
            if line in ("[contains]", "[exact]"):
                section = line[1:-1]
            elif section and re.fullmatch(r"[a-z]+", line):
                lists[section].add(line)
    return lists


def _squash(s):
    return re.sub(r"(.)\1+", r"\1", s)


def name_forms(name):
    """(letters, squashed) spellings of a name to test against the blocklist:
    1 is tried as both i and l."""
    out = set()
    low = name.lower()
    for one in ("i", "l"):
        letters = "".join(LEET.get(ch, one if ch == "1" else ch) for ch in low)
        letters = re.sub(r"[^a-z]", "", letters)
        if letters:
            out.add((letters, _squash(letters)))
    return out


def name_blocked(name, lists=None):
    lists = lists or load_blocklist()
    for letters, squashed in name_forms(name):
        for word in lists["contains"]:
            if word in letters or _squash(word) in squashed:
                return True
        for word in lists["exact"]:
            for form, w in ((letters, word), (squashed, _squash(word))):
                if form in (w, w + "s", w + "es"):
                    return True
    return False


# ---------------------------------------------------------- issue parsing
FIELDS = {
    "game": "Game",
    "name": "Trainer name",
    "points": "Points",
    "earned": "Achievements earned",
    "save_id": "Save ID",
    "code": "Check code",
    "time": "Play time",
}


def parse_time(raw):
    """'12:34' (hours:minutes, as on the card) -> minutes; '' -> None."""
    raw = raw.strip()
    if not raw:
        return None
    m = re.fullmatch(r"(\d{1,3})\s*[:.h]\s*(\d{2})\s*m?", raw.lower())
    if not m or int(m.group(2)) > 59:
        raise Rejected("Play time is the H:MM after TIME on the card, like 12:34.")
    return int(m.group(1)) * 60 + int(m.group(2))


def clock(minutes):
    return f"{minutes // 60}:{minutes % 60:02d}"


def parse_issue(body):
    """GitHub issue forms render as '### Label\\n\\nvalue' blocks."""
    sections = {}
    current = None
    for line in (body or "").replace("\r\n", "\n").split("\n"):
        m = re.match(r"^###\s+(.*?)\s*$", line)
        if m:
            current = m.group(1)
            sections[current] = []
        elif current is not None:
            sections[current].append(line)
    out = {}
    for key, label in FIELDS.items():
        value = "\n".join(sections.get(label, [])).strip()
        if value == "_No response_":
            value = ""
        out[key] = value
    return out


class Rejected(Exception):
    pass


def validate(fields):
    game = fields["game"].strip().lower()
    game = game.replace("pokemon", "").replace("pokémon", "").strip()
    if game not in GAMES:
        raise Rejected("Pick Red, Blue or Yellow as the game.")
    info = GAMES[game]

    name = fields["name"].strip()
    if not name or len(name) > NAME_MAX:
        raise Rejected(f"The trainer name must be 1 to {NAME_MAX} characters.")
    if any(ord(ch) < 32 or ch in "<>`\\" or 0x7f <= ord(ch) < 0xa0 for ch in name):
        raise Rejected("The trainer name has characters the board can't show.")
    if name_blocked(name):
        raise Rejected("That trainer name can't be shown on the board. "
                       "Scores from a save with a different name are welcome.")

    def whole(key, label, top):
        raw = fields[key].replace(",", "").strip()
        if not re.fullmatch(r"\d{1,5}", raw):
            raise Rejected(f"{label} must be a whole number.")
        n = int(raw)
        if n > top:
            raise Rejected(f"{label} can't be more than {top} for {info['title']}.")
        return n

    points = whole("points", "Points", info["maxPoints"])
    earned = whole("earned", "Achievements earned", info["total"])
    if (points == 0) != (earned == 0):
        raise Rejected("Points and achievements earned don't fit together.")

    # Same alphabet as the code: no O, I or L, so read those as 0 and 1
    # (the Gen 1 font's 0 looks a lot like an O).
    save_id = re.sub(r"\s", "", fields["save_id"]).upper().replace("O", "0").replace("I", "1").replace("L", "1")
    if not re.fullmatch(r"[0-9A-Z]{6}", save_id):
        raise Rejected("The save ID is the 6 characters shown on the card.")

    minutes = parse_time(fields.get("time", ""))
    code = normalize_code(fields["code"])
    expected = check_code(game, name, points, earned, save_id, minutes)
    if code != expected:
        raise Rejected("The check code doesn't match the other fields. "
                       "Check each value against the card in the game "
                       "(START > ACHIEVEMENTS > SELECT) and edit the issue.")
    return {"game": game, "name": name, "points": points, "earned": earned,
            "saveId": save_id, "time": minutes}


# ---------------------------------------------------------------- board
def empty_board():
    return {"version": 1, "updated": None, "banned": [],
            "games": {g: dict(info, entries=[]) for g, info in GAMES.items()}}


def load_board(path):
    if not os.path.exists(path):
        return empty_board()
    with open(path, encoding="utf-8") as f:
        board = json.load(f)
    board.setdefault("banned", [])
    for g, info in GAMES.items():
        slot = board.setdefault("games", {}).setdefault(g, {"entries": []})
        slot.update({k: v for k, v in info.items()})
        slot.setdefault("entries", [])
    return board


def rank(entries):
    """Most points first; on equal points the shorter play time wins (entries
    without a time, from mod 1.1.0, go after timed ones), then the earlier
    submission."""
    def key(e):
        t = e.get("time")
        return (-e["points"], t is None, t if t is not None else 0, e.get("first", ""))
    entries.sort(key=key)


def owner_of(e):
    """Who may update an entry: "gh:<login>" or "discord:<hash>"."""
    if e.get("owner"):
        return e["owner"]
    return "gh:" + str(e.get("github") or "").lower()


def upsert(board, entry, sub, now):
    banned = {str(b).lower() for b in board.get("banned", [])}
    if f"{entry['game']}:{entry['saveId']}".lower() in banned:
        raise Rejected("This save has been removed from the board by the maintainer.")
    entries = board["games"][entry["game"]]["entries"]
    for e in entries:
        if e["saveId"] == entry["saveId"]:
            if owner_of(e) != sub.owner:
                raise Rejected("That save ID is already on the board for another account.")
            e.update(name=entry["name"], points=entry["points"],
                     earned=entry["earned"], date=now, via=sub.source, time=entry["time"])
            if sub.issue:
                e["issue"] = sub.issue
            rank(entries)
            return "updated"
    row = {"name": entry["name"], "points": entry["points"],
           "earned": entry["earned"], "saveId": entry["saveId"], "time": entry["time"],
           "owner": sub.owner, "via": sub.source, "date": now, "first": now}
    if sub.source == "github":
        row.update(github=sub.login, issue=sub.issue)
    entries.append(row)
    rank(entries)
    return "added"


# ------------------------------------------------------------- submission
class Submission:
    """Where a score came from: fields to validate plus who sent it."""

    def __init__(self, source, fields, owner, login=None, issue=None):
        self.source, self.fields, self.owner = source, fields, owner
        self.login, self.issue = login, issue


def read_submission(event_path=None):
    event = {}
    if event_path:
        with open(event_path, encoding="utf-8") as f:
            event = json.load(f)
    payload = event.get("client_payload")
    if "issue" not in event and isinstance(payload, dict):
        # repository_dispatch from the Discord bot.  The bot has already
        # replaced the Discord user id with a keyed hash.
        score = payload.get("score") if isinstance(payload.get("score"), dict) else {}
        fields = {k: str(score.get(k, "")) for k in FIELDS}
        owner = str(payload.get("owner", ""))
        if not re.fullmatch(r"[0-9a-f]{16,64}", owner):
            raise Rejected("The Discord bot sent no sender id.")
        return Submission("discord", fields, "discord:" + owner)
    issue = event.get("issue") or {}
    body = issue.get("body") if issue else os.environ.get("ISSUE_BODY", "")
    login = ((issue.get("user") or {}).get("login") if issue
             else os.environ.get("ISSUE_AUTHOR", "")) or ""
    number = issue.get("number") if issue else int(os.environ.get("ISSUE_NUMBER", "0") or 0)
    return Submission("github", parse_issue(body or ""), "gh:" + login.lower(),
                      login=login, issue=number)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--board", default="docs/leaderboard.json")
    ap.add_argument("--reply", default="reply.md")
    ap.add_argument("--event", help="GitHub event JSON ($GITHUB_EVENT_PATH)")
    ap.add_argument("--now", help="timestamp override (tests)")
    args = ap.parse_args(argv)

    now = args.now or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    sub = None

    try:
        sub = read_submission(args.event)
        entry = validate(sub.fields)
        board = load_board(args.board)
        how = upsert(board, entry, sub, now)
    except Rejected as err:
        with open(args.reply, "w", encoding="utf-8") as f:
            f.write(f"Couldn't add this score: {err}\n")
        print(f"rejected: {err}")
        return 1
    except Exception as err:  # noqa: BLE001 - the player still gets a reply
        with open(args.reply, "w", encoding="utf-8") as f:
            f.write("Something went wrong updating the board. The maintainer "
                    "will take a look; you don't need to do anything.\n")
        print(f"error: {err!r}", file=sys.stderr)
        return 2

    board["updated"] = now
    os.makedirs(os.path.dirname(os.path.abspath(args.board)), exist_ok=True)
    with open(args.board, "w", encoding="utf-8") as f:
        json.dump(board, f, indent=1, ensure_ascii=False)
        f.write("\n")
    entries = board["games"][entry["game"]]["entries"]
    place = next(i for i, e in enumerate(entries) if e["saveId"] == entry["saveId"]) + 1
    info = GAMES[entry["game"]]
    with open(args.reply, "w", encoding="utf-8") as f:
        f.write(f"{'Added' if how == 'added' else 'Updated'}: **{entry['name']}** on "
                f"{info['title']} with {entry['points']}/{info['maxPoints']} points "
                f"({entry['earned']}/{info['total']} achievements"
                + (f", reached at {clock(entry['time'])} play time" if entry["time"] is not None else "")
                + "), "
                f"currently #{place}. The page updates in a minute or two.\n\n")
        if sub.source == "discord":
            f.write("To update your score later, send `/score` again with the new card.\n")
        else:
            f.write("To update your score later, edit this issue with the new card.\n")
    print(f"{how}: {entry}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
