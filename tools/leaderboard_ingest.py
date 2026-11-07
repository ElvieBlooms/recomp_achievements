#!/usr/bin/env python3
# tools/leaderboard_ingest.py
"""Read one leaderboard submission and update docs/leaderboard.json.

Submissions come from two places, both handled by the GitHub Action in
.github/workflows/leaderboard.yml:

  * an issues event, from the "Submit a leaderboard score" or
    "Submit an Extra Credit score" issue form, and
  * the Discord bot (discord/worker.js), which sends a repository_dispatch
    event of type "discord-score" or "discord-extra".

The Action passes --event "$GITHUB_EVENT_PATH" and the script works out
which kind of event it is. The submission is read from that file, so
nothing a player typed ever goes on a command line. For a quick manual run
you can use environment variables instead:

    ISSUE_BODY="$(cat body.md)" ISSUE_NUMBER=7 ISSUE_AUTHOR=someone \
        python3 tools/leaderboard_ingest.py --board docs/leaderboard.json

It never talks to the network. It writes a short Markdown reply to --reply
(the Action posts it on the issue or back in Discord) and exits 0 when the
entry was accepted, 1 when it was rejected and 2 on a bug.

The check code is a checksum, not a signature. It catches typos, but it
can't stop anyone who reads the mod's source from making up a score. The
board is an honour system and says so.

The checksum must match recomp_achievements/ui/share.lua and
discord/worker.js exactly.
"""
# ------------------

import argparse
import datetime
import json
import os
import re
import sys

ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

# Official RetroAchievements totals per game, as the mod counts them (see
# docs/COVERAGE.md). Anything above these is rejected.
# Update them when the catalogs change; tests/run.lua checks they match the mod.
GAMES = {
    "red":    {"title": "Pokemon Red",    "maxPoints": 745, "total": 93},
    "blue":   {"title": "Pokemon Blue",   "maxPoints": 678, "total": 90},
    "yellow": {"title": "Pokemon Yellow", "maxPoints": 458, "total": 76},
    "gold":    {"title": "Pokemon Gold",    "maxPoints": 685, "total": 72},
    "silver":  {"title": "Pokemon Silver",  "maxPoints": 616, "total": 75},
    "crystal": {"title": "Pokemon Crystal", "maxPoints": 864, "total": 113},
    "firered":   {"title": "Pokemon FireRed",   "maxPoints": 453, "total": 61},
    "leafgreen": {"title": "Pokemon LeafGreen", "maxPoints": 781, "total": 128},
    "emerald":   {"title": "Pokemon Emerald",   "maxPoints": 2086, "total": 197},
    "ruby":      {"title": "Pokemon Ruby",      "maxPoints": 485, "total": 49},
    "sapphire":  {"title": "Pokemon Sapphire",  "maxPoints": 485, "total": 49},
}

NAME_MAX = 12  # Gen 1 names are 7 characters, but later games and imports need more room
BLOCKLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "name_blocklist.txt")


# ---------------------------------------------------------------- checksum
def norm_name(name):
    """Drop ASCII whitespace and upper-case ASCII letters only.

    Matches Lua's gsub("%s", "") and string.upper, so non-ASCII letters stay as they are."""
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
    """Build the text the check code is taken from.

    v2 (mod 1.2.0 on) adds the play time in minutes. v1 cards from 1.1.0 have no time."""
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


# Extra Credit covers bonus and mod achievements, one line per source.
EXTRA_MAX_SOURCES = 20
EXTRA_MAX_TOTAL = 200      # matches Registry.LIMITS.maxPerProvider
EXTRA_MAX_POINTS = 100     # per achievement, matches Registry.LIMITS.maxPoints


def extra_payload(game, name, save_id, sources):
    """Build the Extra Credit checksum text from [(id, earned, total, points)], sorted like the mod."""
    parts = sorted(f"{i}:{e}:{t}:{p}" for i, e, t, p in sources)
    return "|".join(["x1", game, norm_name(name), save_id.upper(), ",".join(parts)])


def extra_check_code(game, name, save_id, sources):
    p = extra_payload(game, name, save_id, sources).encode("utf-8")
    a = _hash(p, 5381) % 1048576
    b = _hash(p, 52711) % 1048576
    s = _base32(a, 4) + _base32(b, 4)
    return s[:4] + "-" + s[4:]


def parse_extra_lines(raw):
    """Turn lines like 'bonus 3/9 20' into [(id, earned, total, points)].

    Lines can be split by newlines, commas or semicolons."""
    out, seen = [], set()
    for chunk in re.split(r"[\n,;]+", raw or ""):
        chunk = chunk.strip().strip("`").strip()
        if not chunk:
            continue
        m = re.fullmatch(r"([A-Za-z0-9_\-]{1,48})\s+(\d{1,3})\s*/\s*(\d{1,3})\s+(\d{1,5})(?:\s*p(?:ts|oints)?)?",
                         chunk, re.I)
        if not m:
            raise Rejected(f"'{chunk[:40]}' isn't a line from the card. Each line looks like "
                           "'bonus 3/9 20': the name, earned/total, then points.")
        sid = m.group(1).lower()
        e, t, p = int(m.group(2)), int(m.group(3)), int(m.group(4))
        if sid in seen:
            raise Rejected(f"'{sid}' is listed twice.")
        seen.add(sid)
        if t == 0 or t > EXTRA_MAX_TOTAL or e > t:
            raise Rejected(f"'{sid}': achievements earned and total don't fit together.")
        if p > e * EXTRA_MAX_POINTS or (p > 0 and e == 0):
            raise Rejected(f"'{sid}': {p} points can't come from {e} achievements.")
        out.append((sid, e, t, p))
    if not out:
        raise Rejected("Add the lines from the Extra Credit page, like 'bonus 3/9 20'.")
    if len(out) > EXTRA_MAX_SOURCES:
        raise Rejected(f"At most {EXTRA_MAX_SOURCES} lines.")
    return out


def normalize_code(code):
    """Accept lower case, a missing dash, and O, I or L typed for 0 and 1."""
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
    """Spell a name out as (letters, squashed) pairs to test against the blocklist.

    A 1 could be an i or an l, so both are tried."""
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


EXTRA_FIELDS = {
    "game": "Game",
    "name": "Trainer name",
    "save_id": "Save ID",
    "extra": "Extra credit lines",
    "code": "Extra code",
}


def parse_time(raw):
    """Turn the card's H:MM play time into minutes, or None when it's left blank."""
    raw = raw.strip()
    if not raw:
        return None
    m = re.fullmatch(r"(\d{1,3})\s*[:.h]\s*(\d{2})\s*m?", raw.lower())
    if not m or int(m.group(2)) > 59:
        raise Rejected("Play time is the H:MM after TIME on the card, like 12:34.")
    return int(m.group(1)) * 60 + int(m.group(2))


def clock(minutes):
    return f"{minutes // 60}:{minutes % 60:02d}"


def issue_sections(body):
    sections = {}
    current = None
    for line in (body or "").replace("\r\n", "\n").split("\n"):
        m = re.match(r"^###\s+(.*?)\s*$", line)
        if m:
            current = m.group(1)
            sections[current] = []
        elif current is not None:
            sections[current].append(line)
    return sections


def parse_issue(body, fields=None):
    """Pull the fields out of an issue form body, which GitHub writes as '### Label' blocks."""
    sections = issue_sections(body)
    out = {}
    for key, label in (fields or FIELDS).items():
        value = "\n".join(sections.get(label, [])).strip()
        if value == "_No response_":
            value = ""
        out[key] = value
    return out


def is_extra_issue(body):
    return EXTRA_FIELDS["extra"] in issue_sections(body)


class Rejected(Exception):
    pass


def check_game(raw):
    game = raw.strip().lower()
    game = game.replace("pokemon", "").replace("pokémon", "").strip()
    if game not in GAMES:
        raise Rejected("Pick the game from the list (Red, Blue, Yellow, Gold, Silver, Crystal, "
                       "Ruby, Sapphire, Emerald, FireRed or LeafGreen).")
    return game


def check_name(raw):
    name = raw.strip()
    if not name or len(name) > NAME_MAX:
        raise Rejected(f"The trainer name must be 1 to {NAME_MAX} characters.")
    if any(ord(ch) < 32 or ch in "<>`\\" or 0x7f <= ord(ch) < 0xa0 for ch in name):
        raise Rejected("The trainer name has characters the board can't show.")
    if name_blocked(name):
        raise Rejected("That trainer name can't be shown on the board. "
                       "Scores from a save with a different name are welcome.")
    return name


def check_save_id(raw):
    # Uses the check code's alphabet, which has no O, I or L, so those read as 0 and 1.
    # The Gen 1 font's 0 looks a lot like an O.
    save_id = re.sub(r"\s", "", raw).upper().replace("O", "0").replace("I", "1").replace("L", "1")
    if not re.fullmatch(r"[0-9A-Z]{6}", save_id):
        raise Rejected("The save ID is the 6 characters shown on the card.")
    return save_id


def validate_extra(fields):
    game = check_game(fields["game"])
    name = check_name(fields["name"])
    save_id = check_save_id(fields["save_id"])
    sources = parse_extra_lines(fields["extra"])
    if normalize_code(fields["code"]) != extra_check_code(game, name, save_id, sources):
        raise Rejected("The extra code doesn't match the lines. Check each line, the name and "
                       "the save ID against the Extra Credit page (START > TROPHIES > SELECT, "
                       "then RIGHT) and try again.")
    return {"game": game, "name": name, "saveId": save_id,
            "points": sum(p for _, _, _, p in sources), "earned": sum(e for _, e, _, _ in sources),
            "sources": {i: {"earned": e, "total": t, "points": p} for i, e, t, p in sources}}


def validate(fields):
    game = check_game(fields["game"])
    info = GAMES[game]
    name = check_name(fields["name"])

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

    save_id = check_save_id(fields["save_id"])

    minutes = parse_time(fields.get("time", ""))
    code = normalize_code(fields["code"])
    expected = check_code(game, name, points, earned, save_id, minutes)
    if code != expected:
        raise Rejected("The check code doesn't match the other fields. "
                       "Check each value against the card in the game "
                       "(START > TROPHIES > SELECT) and edit the issue."
                       + (" If your card has a TIME line, fill in Play time too; "
                          "the time is part of the code." if minutes is None else ""))
    return {"game": game, "name": name, "points": points, "earned": earned,
            "saveId": save_id, "time": minutes}


# ---------------------------------------------------------------- board
def empty_board():
    return {"version": 1, "updated": None, "banned": [],
            "games": {g: dict(info, entries=[]) for g, info in GAMES.items()},
            "extra": {g: {"entries": []} for g in GAMES}}


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
        board.setdefault("extra", {}).setdefault(g, {}).setdefault("entries", [])
    return board


def rank(entries):
    """Sort by most points, then shortest play time, then earliest submission.

    Entries with no time, from mod 1.1.0, go after the timed ones on equal points."""
    def key(e):
        t = e.get("time")
        return (-e["points"], t is None, t if t is not None else 0, e.get("first", ""))
    entries.sort(key=key)


def rank_extra(entries):
    """Sort Extra Credit by most points, then most achievements, then earliest."""
    entries.sort(key=lambda e: (-e["points"], -e["earned"], e.get("first", "")))


def upsert_extra(board, entry, sub, now):
    banned = {str(b).lower() for b in board.get("banned", [])}
    if f"{entry['game']}:{entry['saveId']}".lower() in banned:
        raise Rejected("This save has been removed from the board by the maintainer.")
    entries = board["extra"][entry["game"]]["entries"]
    for e in entries:
        if e["saveId"] == entry["saveId"]:
            if owner_of(e) not in (sub.owner, sub.alias):
                raise Rejected("That save ID is already on the board for another account.")
            e["owner"] = sub.owner
            e.update(name=entry["name"], points=entry["points"], earned=entry["earned"],
                     sources=entry["sources"], date=now, via=sub.source)
            if sub.issue:
                e["issue"] = sub.issue
            rank_extra(entries)
            return "updated"
    row = {"name": entry["name"], "points": entry["points"], "earned": entry["earned"],
           "sources": entry["sources"], "saveId": entry["saveId"], "owner": sub.owner,
           "via": sub.source, "date": now, "first": now}
    if sub.source == "github":
        row.update(github=sub.login, issue=sub.issue)
    entries.append(row)
    rank_extra(entries)
    return "added"


def owner_of(e):
    """Return who may update an entry: "gh:<login>", "discord:<hash>" or
    "online:<hash>" (a save sending from the online add-on, not linked yet).

    Old entries without an owner fall back to their GitHub login."""
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
            if owner_of(e) not in (sub.owner, sub.alias):
                raise Rejected("That save ID is already on the board for another account.")
            e["owner"] = sub.owner
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
ONLINE_OWNER = re.compile(r"(online|discord):[0-9a-f]{16,64}")


def relink(board, frm, to):
    """Give every row owned by frm (a save's online key) to to (a Discord
    account). Returns how many moved."""
    moved = 0
    slots = [board.get("games", {}).get(g, {}) for g in GAMES]
    slots += [board.get("extra", {}).get(g, {}) for g in GAMES]
    for slot in slots:
        for e in slot.get("entries", []):
            if owner_of(e) == frm:
                e["owner"] = to
                moved += 1
    return moved


class Submission:
    """One score to check: its fields, where it came from and who sent it."""

    def __init__(self, source, fields, owner, login=None, issue=None, kind="score", alias=None):
        self.source, self.fields, self.owner = source, fields, owner
        self.login, self.issue, self.kind = login, issue, kind
        # another owner whose rows this sender may take over: the save's own
        # "online:" owner once it's linked to Discord
        self.alias = alias


def read_submission(event_path=None):
    event = {}
    if event_path:
        with open(event_path, encoding="utf-8") as f:
            event = json.load(f)
    payload = event.get("client_payload")
    action = str(event.get("action") or "")
    if "issue" not in event and isinstance(payload, dict) and action.startswith("online-"):
        # From Recomp Achievements Online, through the worker's GET /auto, or
        # a /link moving a save's rows to a Discord account.
        if action == "online-link":
            frm, to = str(payload.get("from", "")), str(payload.get("to", ""))
            if not (ONLINE_OWNER.fullmatch(frm) and frm.startswith("online:")
                    and ONLINE_OWNER.fullmatch(to) and to.startswith("discord:")):
                raise Rejected("The link request was missing who it was for.")
            return Submission("discord", {}, to, kind="link", alias=frm)
        kind = "extra" if isinstance(payload.get("extra"), dict) else "score"
        data = payload.get(kind) if isinstance(payload.get(kind), dict) else {}
        fields = {k: str(data.get(k, "")) for k in (EXTRA_FIELDS if kind == "extra" else FIELDS)}
        owner, alias = str(payload.get("owner", "")), payload.get("alias")
        if not ONLINE_OWNER.fullmatch(owner):
            raise Rejected("The online add-on sent no sender id.")
        alias = str(alias) if alias is not None and ONLINE_OWNER.fullmatch(str(alias)) else None
        return Submission("online", fields, owner, kind=kind, alias=alias)
    if "issue" not in event and isinstance(payload, dict):
        # A repository_dispatch from the Discord bot. The bot has already swapped
        # the Discord user id for a keyed hash, so the raw id never reaches GitHub.
        kind = "extra" if isinstance(payload.get("extra"), dict) else "score"
        data = payload.get(kind) if isinstance(payload.get(kind), dict) else {}
        fields = {k: str(data.get(k, "")) for k in (EXTRA_FIELDS if kind == "extra" else FIELDS)}
        owner = str(payload.get("owner", ""))
        if not re.fullmatch(r"[0-9a-f]{16,64}", owner):
            raise Rejected("The Discord bot sent no sender id.")
        return Submission("discord", fields, "discord:" + owner, kind=kind)
    issue = event.get("issue") or {}
    body = issue.get("body") if issue else os.environ.get("ISSUE_BODY", "")
    login = ((issue.get("user") or {}).get("login") if issue
             else os.environ.get("ISSUE_AUTHOR", "")) or ""
    number = issue.get("number") if issue else int(os.environ.get("ISSUE_NUMBER", "0") or 0)
    if is_extra_issue(body or ""):
        return Submission("github", parse_issue(body or "", EXTRA_FIELDS), "gh:" + login.lower(),
                          login=login, issue=number, kind="extra")
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
        if sub.kind == "link":
            board = load_board(args.board)
            moved = relink(board, sub.alias, sub.owner)
            board["updated"] = now
            with open(args.board, "w", encoding="utf-8") as f:
                json.dump(board, f, indent=1, ensure_ascii=False)
                f.write("\n")
            with open(args.reply, "w", encoding="utf-8") as f:
                f.write(f"Linked. {moved} score{'' if moved == 1 else 's'} moved to your Discord account. "
                        "From now on this save's scores are yours to update with `/score` too.\n")
            print(f"linked: {moved} moved")
            return 0
        if sub.kind == "extra":
            entry = validate_extra(sub.fields)
            board = load_board(args.board)
            how = upsert_extra(board, entry, sub, now)
        else:
            entry = validate(sub.fields)
            board = load_board(args.board)
            how = upsert(board, entry, sub, now)
    except Rejected as err:
        with open(args.reply, "w", encoding="utf-8") as f:
            f.write(f"Couldn't add this score: {err}\n")
        print(f"rejected: {err}")
        return 1
    except Exception as err:  # noqa: BLE001 - so the player still gets a reply
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
    if sub.kind == "extra":
        entries = board["extra"][entry["game"]]["entries"]
        place = next(i for i, e in enumerate(entries) if e["saveId"] == entry["saveId"]) + 1
        info = GAMES[entry["game"]]
        with open(args.reply, "w", encoding="utf-8") as f:
            f.write(f"{'Added' if how == 'added' else 'Updated'} Extra Credit: **{entry['name']}** on "
                    f"{info['title']} with {entry['points']} points from {entry['earned']} bonus and "
                    f"mod achievements, currently #{place} overall. The page updates in a minute or two.\n\n")
            f.write("To update it later, send `/extra` again with the new page.\n" if sub.source == "discord"
                    else "To update it later, edit this issue with the new page.\n")
        print(f"{how} extra: {entry}")
        return 0
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
