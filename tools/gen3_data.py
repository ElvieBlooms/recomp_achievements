#!/usr/bin/env python3
"""Build recomp_achievements/data/gen3_<family>.lua from a pret Gen 3 repo.

    python3 tools/gen3_data.py <pokefirered dir>     -> data/gen3_frlg.lua
    python3 tools/gen3_data.py <pokeemerald dir>     -> data/gen3_emerald.lua

Gen1Recomp's FireRed and LeafGreen run the decompiled scripts, so the save's
flag numbers are pret's (checked in game: FLAG_BADGE01_GET = 0x820 is set on
a save with the Boulder Badge).  FireRed and LeafGreen share every flag and
map, so one file serves both.  It lists:

  flags     FLAG_* name -> number, plus TRAINER_* -> its trainer flag
            (TRAINER_FLAGS_START + the trainer's number)
  trainerIds  trainer number -> TRAINER_* name (battle.started gives the number)
  vars      VAR_* name -> number
  species   SPECIES_* (no prefix) -> internal number (the save's numbering)
  items     ITEM_* (no prefix) -> number
  trainers  every map trainer: { flag number, TRAINER_*, map, region }
  items     ... see `balls`: { flag, ITEM, map, region } for item balls
  hidden    hidden items: { flag, ITEM, map, region }
  gifts     a script gives an item then sets a flag: { flag, FLAG_*, ITEM, map, region }
  rematches VS Seeker trainers: { flag of the strongest team, its TRAINER_*, the base TRAINER_* }
  initial   flags EventScript_ResetAllMapFlags sets at New Game (true)

region is "kanto" or "sevii" from the map's region-map section (FireRed),
"hoenn" for Emerald.  Emerald's rematches come from gRematchTable (the
Match Call / gym leader rematch table) instead of the VS Seeker's.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "recomp_achievements", "data")

DEFINE = re.compile(r"^\s*#define\s+(\w+)\s+(.+?)\s*(//.*)?$")


def read_defines(paths, prefix):
    """name -> int for every #define starting with prefix (expressions too)."""
    raw = {}
    for path in paths:
        for line in open(path, encoding="utf-8"):
            m = DEFINE.match(line)
            if m:
                raw[m.group(1)] = m.group(2).split("//")[0].strip()
    values = {}

    def ev(name, depth=0):
        if name in values:
            return values[name]
        if depth > 50 or name not in raw:
            raise KeyError(name)
        expr = raw[name]
        expr = re.sub(r"\b(\d+)u\b", r"\1", expr)

        def sub(m):
            tok = m.group(0)
            if re.fullmatch(r"0[xX][0-9a-fA-F]+|\d+", tok):
                return tok
            return str(ev(tok, depth + 1))
        py = re.sub(r"\b[A-Za-z_]\w*\b|0[xX][0-9a-fA-F]+|\b\d+\b", sub, expr)
        v = int(eval(py, {"__builtins__": {}}))  # numbers and + - * / ( ) only
        values[name] = v
        return v

    out = {}
    for name in raw:
        if name.startswith(prefix):
            try:
                out[name] = ev(name)
            except Exception:
                pass
    return out


def read_enum_items(path, tmhm_path):
    """Emerald's items.h is an enum; TMs/HMs get ITEM_TM_<MOVE> aliases."""
    out, value = {}, 0
    text = open(path, encoding="utf-8").read()
    m = re.search(r"enum\s*\{(.*?)\};", text, re.S)
    if not m:
        return out
    body = re.sub(r"//[^\n]*", "", m.group(1))
    for tok in body.split(","):
        tok = tok.strip()
        if not tok:
            continue
        mm = re.match(r"(\w+)\s*(?:=\s*(\w+))?$", tok)
        if not mm:
            continue
        if mm.group(2):
            v = mm.group(2)
            value = int(v, 0) if re.fullmatch(r"0[xX][0-9a-fA-F]+|\d+", v) else out[v]
        out[mm.group(1)] = value
        value += 1
    if os.path.exists(tmhm_path):
        t = open(tmhm_path, encoding="utf-8").read()
        for kind, first in (("TM", "ITEM_TM01"), ("HM", "ITEM_HM01")):
            mm = re.search(r"#define FOREACH_%s\(F\)(.*?)(?:\n\s*\n|#define)" % kind, t, re.S)
            if mm and first in out:
                for i, name in enumerate(re.findall(r"F\((\w+)\)", mm.group(1))):
                    out[f"ITEM_{kind}_{name}"] = out[first] + i
    return out


def label_bodies(repo):
    """Script label -> list of instruction lines, from every .inc/.s file."""
    bodies, cur = {}, None
    roots = [os.path.join(repo, "data", "maps"), os.path.join(repo, "data", "scripts"),
             os.path.join(repo, "data")]
    files = []
    for root in roots:
        for dirpath, _, names in os.walk(root):
            for n in names:
                if n.endswith(".inc") or n.endswith(".s"):
                    files.append(os.path.join(dirpath, n))
            if root.endswith("data") and dirpath == root:
                pass
    for path in sorted(set(files)):
        for line in open(path, encoding="utf-8", errors="replace"):
            m = re.match(r"^(\w+)::?\s*(@.*)?$", line.strip())
            if m:
                cur = m.group(1)
                bodies.setdefault(cur, [])
                continue
            if cur and line.strip():
                bodies[cur].append(line.strip())
    return bodies


def follow(bodies, label, seen=None, depth=0):
    """A label's lines plus the labels it falls through/branches to (one level)."""
    out = list(bodies.get(label, []))
    return out


def map_sections(repo):
    region = {}
    if not os.path.exists(os.path.join(repo, "src", "data", "region_map", "region_map_layout_kanto.h")):
        return None
    layouts = {
        "region_map_layout_kanto.h": "kanto",
        "region_map_layout_sevii_123.h": "sevii",
        "region_map_layout_sevii_45.h": "sevii",
        "region_map_layout_sevii_67.h": "sevii",
    }
    base = os.path.join(repo, "src", "data", "region_map")
    for fname, reg in layouts.items():
        for sec in re.findall(r"MAPSEC_\w+", open(os.path.join(base, fname), encoding="utf-8").read()):
            if sec != "MAPSEC_NONE":
                region.setdefault(sec, reg)
    return region


def lua_key(k):
    return k if re.fullmatch(r"[A-Za-z_]\w*", k) else "[" + lua_str(k) + "]"


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    repo = sys.argv[1] if len(sys.argv) > 1 else "/home/claude/pret/pokefirered"
    emerald = os.path.exists(os.path.join(repo, "src", "battle_frontier_2.c")) or "emerald" in os.path.basename(os.path.normpath(repo))
    ruby = "ruby" in os.path.basename(os.path.normpath(repo))
    family = "emerald" if emerald else ("rs" if ruby else "frlg")
    OUT = os.path.join(DATA, f"gen3_{family}.lua")
    inc = os.path.join(repo, "include", "constants")
    flags = read_defines([os.path.join(inc, "flags.h"), os.path.join(inc, "opponents.h")], "FLAG_")
    starts = read_defines([os.path.join(inc, "flags.h"), os.path.join(inc, "opponents.h")], "TRAINER_FLAG")
    tr_start = starts.get("TRAINER_FLAGS_START", starts.get("TRAINER_FLAG_START"))
    trainers_c = read_defines([os.path.join(inc, "opponents.h")], "TRAINER_")
    trainers_c = {k: v for k, v in trainers_c.items()
                  if k not in ("TRAINER_FLAGS_START", "TRAINER_FLAGS_END") and v < 1000}
    for name, n in trainers_c.items():
        if name != "TRAINER_NONE":
            flags[name] = tr_start + n
    vars_ = read_defines([os.path.join(inc, "vars.h")], "VAR_")
    species = read_defines([os.path.join(inc, "species.h")], "SPECIES_")
    items = read_defines([os.path.join(inc, "items.h")], "ITEM_")
    if len(items) < 50:
        items = read_enum_items(os.path.join(inc, "items.h"), os.path.join(inc, "tms_hms.h"))
    # Ruby/Sapphire name TMs ITEM_TM01_FOCUS_PUNCH: add the ITEM_TM_<MOVE> and ITEM_TM01 forms
    for name, v in list(items.items()):
        mm = re.match(r"ITEM_(TM|HM)(\d\d)_(\w+)$", name)
        if mm:
            items.setdefault(f"ITEM_{mm.group(1)}_{mm.group(3)}", v)
            items.setdefault(f"ITEM_{mm.group(1)}{mm.group(2)}", v)
    moves = read_defines([os.path.join(inc, "moves.h")], "MOVE_")
    # Emerald decorations: DECOR_* -> { id, category } (categories 0..7:
    # desk, chair, plant, ornament, mat, poster, doll, cushion)
    decor = {}
    header = os.path.join(repo, "src", "data", "decoration", "header.h")
    if not os.path.exists(header):
        header = os.path.join(repo, "src", "data", "decoration", "decorations.h")
    if (emerald or ruby) and os.path.exists(header):
        cats = ["DECORCAT_DESK", "DECORCAT_CHAIR", "DECORCAT_PLANT", "DECORCAT_ORNAMENT",
                "DECORCAT_MAT", "DECORCAT_POSTER", "DECORCAT_DOLL", "DECORCAT_CUSHION"]
        ids = read_defines([os.path.join(inc, "decorations.h")], "DECOR_")
        text = open(header, encoding="utf-8").read()
        for name, cat in re.findall(r"\.id\s*=\s*(DECOR_\w+),.*?\.category\s*=\s*(DECORCAT_\w+)", text, re.S):
            if name in ids and name != "DECOR_NONE" and cat in cats:
                decor[name[6:]] = (ids[name], cats.index(cat))

    bodies = label_bodies(repo)
    sections = map_sections(repo)

    # New Game: EventScript_ResetAllMapFlags (and what it calls)
    initial = set()
    for line in bodies.get("EventScript_ResetAllMapFlags", []):
        m = re.match(r"setflag\s+(FLAG_\w+)", line)
        if m:
            initial.add(m.group(1))

    trainer_rows, ball_rows, hidden_rows, gift_rows = [], [], [], []
    seen_trainers = set()
    maps_dir = os.path.join(repo, "data", "maps")
    for name in sorted(os.listdir(maps_dir)):
        path = os.path.join(maps_dir, name, "map.json")
        if not os.path.exists(path):
            continue
        m = json.load(open(path, encoding="utf-8"))
        region = "hoenn" if sections is None else sections.get(m.get("region_map_section"), "other")
        labels = []
        for obj in m.get("object_events") or []:
            script = obj.get("script")
            if not script:
                continue
            body = bodies.get(script, [])
            if obj.get("graphics_id") == "OBJ_EVENT_GFX_ITEM_BALL":
                it = None
                for line in body:
                    mm = re.match(r"finditem\s+ITEM_(\w+)", line)
                    if mm:
                        it = mm.group(1)
                        break
                fl = obj.get("flag")
                if it and fl in flags:
                    ball_rows.append((flags[fl], fl, it, name, region))
                continue
            labels.append(script)
        for bg in m.get("bg_events") or []:
            if bg.get("type") == "hidden_item" and bg.get("flag") in flags:
                it = str(bg.get("item", "")).replace("ITEM_", "")
                hidden_rows.append((flags[bg["flag"]], bg["flag"], it, name, region))
        # the map's own scripts: every label defined in its scripts.inc
        own = os.path.join(maps_dir, name, "scripts.inc")
        if os.path.exists(own):
            for line in open(own, encoding="utf-8", errors="replace"):
                mm = re.match(r"^(\w+)::?\s*(@.*)?$", line.strip())
                if mm:
                    labels.append(mm.group(1))
        for label in labels:
            body = bodies.get(label, [])
            last_item = None
            for line in body:
                mm = re.match(r"trainerbattle_(\w+)\s+(TRAINER_\w+)", line)
                if mm and mm.group(1) not in ("rematch", "rematch_double"):
                    tr = mm.group(2)
                    if tr in flags and tr not in seen_trainers:
                        seen_trainers.add(tr)
                        trainer_rows.append((flags[tr], tr, name, region))
                mm = re.match(r"giveitem(?:_msg)?\s+(?:\w+,\s*)?ITEM_(\w+)", line)
                if mm:
                    last_item = mm.group(1)
                mm = re.match(r"setflag\s+(FLAG_\w+)", line)
                if mm and last_item and mm.group(1) in flags and not mm.group(1).startswith("FLAG_HIDE_"):
                    gift_rows.append((flags[mm.group(1)], mm.group(1), last_item, name, region))
                    last_item = None

    def dedupe(rows):
        out, seen = [], set()
        for r in rows:
            if r[0] not in seen:
                seen.add(r[0])
                out.append(r)
        return out

    gift_rows = dedupe(gift_rows)

    # Rematches: each rematchable trainer's last (strongest) team
    rematch_rows = []
    if ruby:
        src = open(os.path.join(repo, "src", "battle_setup.c"), encoding="utf-8").read()
        table = src[src.index("gTrainerEyeTrainers[]"):]
        table = table[:table.index("};")]
        for grp in re.findall(r"\{\s*\{([^}]*)\}", table):
            ids = re.findall(r"TRAINER_\w+", grp)
            if ids and ids[-1] in flags:
                rematch_rows.append((flags[ids[-1]], ids[-1], ids[0]))
    elif emerald:
        src = open(os.path.join(repo, "src", "battle_setup.c"), encoding="utf-8").read()
        table = src[src.index("gRematchTable[REMATCH_TABLE_ENTRIES]"):]
        table = table[:table.index("};")]
        for grp in re.findall(r"REMATCH\(([^)]*)\)", table):
            ids = re.findall(r"TRAINER_\w+", grp)
            if ids and ids[-1] in flags:
                rematch_rows.append((flags[ids[-1]], ids[-1], ids[0]))
    else:
        vs = open(os.path.join(repo, "src", "vs_seeker.c"), encoding="utf-8").read()
        table = vs[vs.index("sRematches[]"):]
        table = table[:table.index("};")]
        for grp in re.findall(r"\{\s*\{([^}]*)\}", table):
            ids = [t for t in re.findall(r"TRAINER_\w+", grp)]
            if ids and ids[-1] in flags:
                rematch_rows.append((flags[ids[-1]], ids[-1], ids[0]))
    ball_rows = dedupe(ball_rows)

    # Gym trainers the game marks beaten when the leader falls (set_gym_trainers)
    gyms = {}
    switch = bodies.get("Common_EventScript_SetGymTrainers") or bodies.get("EventScript_SetGymTrainers") or []
    for line in switch:
        mm = re.match(r"case\s+(\d+),\s*(\w+)", line)
        if mm:
            gyms[int(mm.group(1))] = [l.split()[1] for l in bodies.get(mm.group(2), [])
                                      if l.startswith("settrainerflag")]
    w = []
    w.append(f"-- Generated by tools/gen3_data.py from pret/{os.path.basename(os.path.normpath(repo))} -- do not edit by hand.")
    w.append("-- Flag numbers and what the maps hold, for this mod's Gen 3 rules.")
    w.append("return {")
    w.append(f"  trainerFlagsStart = {tr_start},")
    w.append("  flags = {")
    for k, v in sorted(flags.items(), key=lambda kv: (kv[1], kv[0])):
        w.append(f"    {k} = {v},")
    w.append("  },")
    w.append("  trainerIds = {")
    for k, v in sorted(trainers_c.items(), key=lambda kv: kv[1]):
        w.append(f"    [{v}] = {lua_str(k)},")
    w.append("  },")
    w.append("  vars = {")
    for k, v in sorted(vars_.items(), key=lambda kv: (kv[1], kv[0])):
        w.append(f"    {k} = {v},")
    w.append("  },")
    w.append("  species = {")
    for k, v in sorted(species.items(), key=lambda kv: (kv[1], kv[0])):
        if v < 500:
            w.append(f"    {lua_key(k[8:])} = {v},")
    w.append("  },")
    w.append("  itemIds = {")
    for k, v in sorted(items.items(), key=lambda kv: (kv[1], kv[0])):
        if k[5:] and not k.startswith("ITEM_FIELD_ARROW") and v < 1000:
            w.append(f"    {lua_key(k[5:])} = {v},")
    w.append("  },")
    w.append("  moves = {")
    for k, v in sorted(moves.items(), key=lambda kv: (kv[1], kv[0])):
        if v < 1000 and k[5:]:
            w.append(f"    {lua_key(k[5:])} = {v},")
    w.append("  },")
    if decor:
        w.append("  decorations = {")
        for k, (v, c) in sorted(decor.items(), key=lambda kv: kv[1][0]):
            w.append(f"    {lua_key(k)} = {{ {v}, {c} }},")
        w.append("  },")
    for key, rows in (("trainers", trainer_rows), ("items", ball_rows),
                      ("hidden", hidden_rows), ("gifts", gift_rows), ("rematches", rematch_rows)):
        w.append(f"  {key} = {{")
        for r in rows:
            w.append("    { " + ", ".join(str(x) if isinstance(x, int) else lua_str(x) for x in r) + " },")
        w.append("  },")
    w.append("  gymTrainers = {")
    for i in range(1, 9):
        w.append("    { " + ", ".join(lua_str(t) for t in gyms.get(i, [])) + " },")
    w.append("  },")
    w.append("  initial = {")
    for k in sorted(initial):
        if k in flags:
            w.append(f"    [{flags[k]}] = true, -- {k}")
    w.append("  },")
    w.append("}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8").write("\n".join(w) + "\n")
    print(f"wrote {OUT}: {len(flags)} flags, {len(trainer_rows)} trainers, {len(ball_rows)} item balls, "
          f"{len(hidden_rows)} hidden, {len(gift_rows)} gifts, {len(initial)} initial")


if __name__ == "__main__":
    main()
