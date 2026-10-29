#!/usr/bin/env python3
"""
fetch_ra_catalog.py: build Recomp Achievements' reference catalogs from
RetroAchievements' public Web API.

This is a DEVELOPER tool, run once by you on your own machine. The mod
itself never contacts RetroAchievements and needs no key. Only public
metadata is written (title, description, points, author, display order,
type, badge name and the logic *hash*). RA's trigger logic is not
available from this endpoint and is not used.

Usage
-----
  # key from an environment variable (never written anywhere)
  RA_API_KEY=xxxxxxxx python3 tools/fetch_ra_catalog.py

  # or from a file that is NOT in the repo
  python3 tools/fetch_ra_catalog.py --key-file ~/.ra_key

  # pick games (default: red blue yellow)
  python3 tools/fetch_ra_catalog.py red blue

  # offline: convert JSON you saved from the endpoint yourself
  python3 tools/fetch_ra_catalog.py --from-json saved/ red

Writes recomp_achievements/catalog/<game>.lua and prints a change report
against any catalog already there. Get your key from your RA account's
settings page ("Web API Key").
"""

import argparse
import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ENDPOINT = "https://retroachievements.org/API/API_GetGameExtended.php"
USER_AGENT = "RecompAchievementsCatalogTool/1.0 (offline Gen1Recomp mod; metadata only)"

# RA game ids for the base (core) sets.  Phase 1 uses the first three.
GAMES = {
    "red": 724, "blue": 586, "yellow": 723,
    "gold": 576, "silver": 722, "crystal": 810,
    "ruby": 790, "sapphire": 791, "emerald": 668,
    "firered": 515, "leafgreen": 788,
}

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "..", "recomp_achievements", "catalog")


def lua_str(value):
    """A Lua string literal that round-trips any text safely."""
    s = "" if value is None else str(value)
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif o < 32 or o == 127:
            out.append("\\%03d" % o)
        else:
            out.append(ch)
    out.append('"')
    # Lua strings are byte strings; UTF-8 passes through as-is.
    return "".join(out)


def fetch(game_id, key, timeout=20):
    query = urllib.parse.urlencode({"i": game_id, "y": key, "f": 3})
    req = urllib.request.Request(ENDPOINT + "?" + query, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read(8 * 1024 * 1024 + 1)
    except urllib.error.HTTPError as e:
        # never echo the URL: it contains the key
        raise SystemExit("RA returned HTTP %d for game %d (check your key)" % (e.code, game_id))
    except urllib.error.URLError as e:
        raise SystemExit("could not reach RetroAchievements for game %d: %s" % (game_id, e.reason))
    if len(body) > 8 * 1024 * 1024:
        raise SystemExit("response for game %d is unexpectedly large" % game_id)
    return json.loads(body.decode("utf-8"))


def normalize(game, raw):
    """Validate the response and reduce it to the fields the mod uses."""
    if not isinstance(raw, dict):
        raise SystemExit("%s: response is not a JSON object" % game)
    gid = int(raw.get("ID") or raw.get("id") or 0)
    if gid != GAMES[game]:
        raise SystemExit("%s: expected RA game %d, got %r" % (game, GAMES[game], gid))
    achievements = raw.get("Achievements") or raw.get("achievements") or {}
    if isinstance(achievements, dict):
        achievements = list(achievements.values())
    entries, seen = [], set()
    for a in achievements:
        def g(*names):
            for n in names:
                if n in a:
                    return a[n]
            return None
        aid = int(g("ID", "id"))
        if aid in seen:
            raise SystemExit("%s: duplicate achievement id %d" % (game, aid))
        seen.add(aid)
        title = (g("Title", "title") or "").strip()
        if not title:
            raise SystemExit("%s: achievement %d has no title" % (game, aid))
        entries.append({
            "id": aid,
            "title": title,
            "description": (g("Description", "description") or "").strip(),
            "points": int(g("Points", "points") or 0),
            "author": (g("Author", "author") or "").strip(),
            "order": int(g("DisplayOrder", "displayOrder") or 0),
            "type": (g("type", "Type") or "") or "",
            "badge": str(g("BadgeName", "badgeName") or ""),
            "fingerprint": str(g("MemAddr", "memAddr") or ""),
            "modified": str(g("DateModified", "dateModified") or ""),
        })
    entries.sort(key=lambda e: (e["order"], e["id"]))
    return {
        "game": game, "gameId": gid,
        "title": raw.get("Title") or raw.get("title") or game,
        "entries": entries,
    }


def to_lua(cat):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [
        "-- Generated by tools/fetch_ra_catalog.py -- do not edit by hand.",
        "-- Source: RetroAchievements Web API, API_GetGameExtended (f=3, core set).",
        "-- Achievement titles, descriptions and metadata courtesy of RetroAchievements",
        "-- and the credited authors; see https://retroachievements.org/game/%d" % cat["gameId"],
        "-- Reference data only: unlocking is done by this mod's own rules.",
        "return {",
        "  game = %s," % lua_str(cat["game"]),
        "  gameId = %d," % cat["gameId"],
        "  title = %s," % lua_str(cat["title"]),
        "  fetched = %s," % lua_str(now),
        "  count = %d," % len(cat["entries"]),
        "  entries = {",
    ]
    for e in cat["entries"]:
        lines.append(
            "    { id = %d, order = %d, points = %d, type = %s,\n"
            "      title = %s,\n"
            "      description = %s,\n"
            "      author = %s, badge = %s,\n"
            "      fingerprint = %s, modified = %s },"
            % (e["id"], e["order"], e["points"], lua_str(e["type"]),
               lua_str(e["title"]), lua_str(e["description"]),
               lua_str(e["author"]), lua_str(e["badge"]),
               lua_str(e["fingerprint"]), lua_str(e["modified"])))
    lines += ["  },", "}", ""]
    return "\n".join(lines)


def read_existing(path):
    """Pull ids/titles/fingerprints out of an existing generated file (best effort)."""
    import re
    if not os.path.exists(path):
        return None
    text = open(path, encoding="utf-8").read()
    found = {}
    for m in re.finditer(r'\{ id = (\d+),.*?title = "((?:[^"\\]|\\.)*)",.*?fingerprint = "([^"]*)"',
                         text, re.S):
        found[int(m.group(1))] = (m.group(2), m.group(3))
    return found


def report(game, old, cat):
    if old is None:
        print("  %s: new catalog, %d entries" % (game, len(cat["entries"])))
        return
    # compare in escaped form, the same form read_existing() sees in the file
    new = {e["id"]: (lua_str(e["title"])[1:-1], e["fingerprint"]) for e in cat["entries"]}
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    retitled = [i for i in new if i in old and new[i][0] != old[i][0]]
    relogic = [i for i in new if i in old and new[i][1] != old[i][1]]
    print("  %s: %d entries (+%d added, -%d removed, %d retitled, %d logic changed)"
          % (game, len(new), len(added), len(removed), len(retitled), len(relogic)))
    for i in removed:
        print("    removed %d %s  <- check links.lua; earned records are kept" % (i, old[i][0]))
    for i in relogic:
        print("    logic changed upstream: %d %s  <- review the native rule" % (i, new[i][0]))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("games", nargs="*", default=["red", "blue", "yellow"])
    ap.add_argument("--key-file")
    ap.add_argument("--from-json", metavar="DIR",
                    help="read <DIR>/<game>.json instead of calling the API")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    for g in args.games:
        if g not in GAMES:
            raise SystemExit("unknown game %r (choose from %s)" % (g, ", ".join(GAMES)))

    key = None
    if not args.from_json:
        if args.key_file:
            key = open(os.path.expanduser(args.key_file), encoding="utf-8").read().strip()
        else:
            key = os.environ.get("RA_API_KEY", "").strip()
            if not key:
                # forgive RA_API_Key / ra_api_key and friends
                for name, value in os.environ.items():
                    if name.upper() == "RA_API_KEY" and value.strip():
                        key = value.strip()
                        break
        if not key:
            raise SystemExit("no key: set RA_API_KEY or pass --key-file (or use --from-json)")

    os.makedirs(args.out, exist_ok=True)
    for n, game in enumerate(args.games):
        if args.from_json:
            raw = json.load(open(os.path.join(args.from_json, game + ".json"), encoding="utf-8"))
        else:
            if n:
                time.sleep(1.0)  # be polite: one request per second
            raw = fetch(GAMES[game], key)
        cat = normalize(game, raw)
        path = os.path.join(args.out, game + ".lua")
        old = read_existing(path)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(to_lua(cat))
        report(game, old, cat)
    print("done. Wrote catalogs to", os.path.normpath(args.out))


if __name__ == "__main__":
    main()
