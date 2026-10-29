#!/usr/bin/env python3
"""Read one leaderboard submission (a GitHub issue form) and update
docs/leaderboard.json.

The GitHub Action in .github/workflows/leaderboard.yml runs this with the
issue's body, number and author in environment variables.  It can also be
run by hand:

    ISSUE_BODY="$(cat body.md)" ISSUE_NUMBER=7 ISSUE_AUTHOR=someone \
        python3 tools/leaderboard_ingest.py --board docs/leaderboard.json

It never talks to the network.  It writes a short Markdown reply to
--reply (the Action posts it on the issue) and exits 0 when the entry was
accepted, 1 when it was rejected.

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

VERSION = "v1"
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


def payload(game, name, points, earned, save_id):
    return "|".join([VERSION, game, norm_name(name), str(points), str(earned),
                     save_id.upper()])


def check_code(game, name, points, earned, save_id):
    p = payload(game, name, points, earned, save_id).encode("utf-8")
    a = _hash(p, 5381) % 1048576
    b = _hash(p, 52711) % 1048576
    s = _base32(a, 4) + _base32(b, 4)
    return s[:4] + "-" + s[4:]


def normalize_code(code):
    """Accept lower case, missing dash, and the usual Crockford look-alikes."""
    c = re.sub(r"[\s\-]", "", code.upper())
    c = c.replace("O", "0").replace("I", "1").replace("L", "1")
    return c[:4] + "-" + c[4:] if len(c) == 8 else c


# ---------------------------------------------------------- issue parsing
FIELDS = {
    "game": "Game",
    "name": "Trainer name",
    "points": "Points",
    "earned": "Achievements earned",
    "save_id": "Save ID",
    "code": "Check code",
}


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

    save_id = fields["save_id"].strip().upper()
    if not re.fullmatch(r"[0-9A-Z]{6}", save_id):
        raise Rejected("The save ID is the 6 characters shown on the card.")

    code = normalize_code(fields["code"])
    expected = check_code(game, name, points, earned, save_id)
    if code != expected:
        raise Rejected("The check code doesn't match the other fields. "
                       "Check each value against the card in the game "
                       "(START > ACHIEVEMENTS > SELECT) and edit the issue.")
    return {"game": game, "name": name, "points": points, "earned": earned,
            "saveId": save_id}


# ---------------------------------------------------------------- board
def empty_board():
    return {"version": 1, "updated": None,
            "games": {g: dict(info, entries=[]) for g, info in GAMES.items()}}


def load_board(path):
    if not os.path.exists(path):
        return empty_board()
    with open(path, encoding="utf-8") as f:
        board = json.load(f)
    for g, info in GAMES.items():
        slot = board.setdefault("games", {}).setdefault(g, {"entries": []})
        slot.update({k: v for k, v in info.items()})
        slot.setdefault("entries", [])
    return board


def rank(entries):
    entries.sort(key=lambda e: (-e["points"], -e["earned"], e.get("first", "")))


def upsert(board, entry, author, issue, now):
    entries = board["games"][entry["game"]]["entries"]
    for e in entries:
        if e["saveId"] == entry["saveId"]:
            if e.get("github") and author and e["github"].lower() != author.lower():
                raise Rejected("That save ID is already on the board for another "
                               "GitHub account.")
            e.update(name=entry["name"], points=entry["points"],
                     earned=entry["earned"], date=now, issue=issue)
            rank(entries)
            return "updated"
    entries.append({"name": entry["name"], "points": entry["points"],
                    "earned": entry["earned"], "saveId": entry["saveId"],
                    "github": author, "issue": issue, "date": now, "first": now})
    rank(entries)
    return "added"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--board", default="docs/leaderboard.json")
    ap.add_argument("--reply", default="reply.md")
    ap.add_argument("--now", help="timestamp override (tests)")
    args = ap.parse_args(argv)

    body = os.environ.get("ISSUE_BODY", "")
    author = os.environ.get("ISSUE_AUTHOR", "")
    issue = int(os.environ.get("ISSUE_NUMBER", "0") or 0)
    now = args.now or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        entry = validate(parse_issue(body))
        board = load_board(args.board)
        how = upsert(board, entry, author, issue, now)
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
                f"({entry['earned']}/{info['total']} achievements), "
                f"currently #{place}. The page updates in a minute or two.\n\n"
                "To update your score later, edit this issue with the new card.\n")
    print(f"{how}: {entry}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
