#!/usr/bin/env python3
"""Build recomp_achievements/data/gen2_<game>.lua from the pret disassemblies.

    python3 tools/gen2_data.py <pokegold dir> <pokecrystal dir>

Gen1Recomp's Gen 2 games use the pret numbering for event flags (checked
against the engine's own src/core/gen2/FlagNames.lua and Crystal's generated
scripts), so the flag numbers here are the ones the game sets.  For each game
the file lists:

  flags     event flag name -> number
  trainers  every map trainer: beat flag, map, region (johto/kanto/other)
  items     every item ball: flag, item, map, region
  hidden    every hidden item: flag, item, map, region
  gifts     items handed over by a script that then sets a flag
            (giveitem/verbosegiveitem ... setevent), with the flag and item

Region comes from the map's landmark: before KANTO_LANDMARK is Johto,
from it to KANTO_LANDMARK_LAST is Kanto, anything else (the S.S. Aqua,
special places) is "other".  Silver shares Gold's source, so it gets the
same file contents.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen2_flags import parse_consts  # noqa: E402

OUT = os.path.join(os.path.dirname(HERE), "recomp_achievements", "data")


def landmark_regions(repo):
    path = os.path.join(repo, "constants", "landmark_constants.asm")
    value, kanto_start, kanto_end, names = 0, None, None, {}
    for raw in open(path, encoding="utf-8"):
        line = raw.split(";")[0].strip()
        if line.startswith("const_def"):
            value = 0
        elif line.startswith("DEF KANTO_LANDMARK_LAST"):
            kanto_end = value - 1
        elif line.startswith("DEF KANTO_LANDMARK"):
            kanto_start = value
        else:
            m = re.match(r"const\s+(\w+)", line)
            if m:
                names[m.group(1)] = value
                value += 1
    if kanto_end is None and "LANDMARK_ROUTE_28" in names:
        kanto_end = names["LANDMARK_ROUTE_28"]  # pokegold has no _LAST marker
    out = {}
    for name, v in names.items():
        if v == 0:
            out[name] = "other"
        elif kanto_start is not None and v < kanto_start:
            out[name] = "johto"
        elif kanto_end is not None and v <= kanto_end:
            out[name] = "kanto"
        else:
            out[name] = "other"
    return out


def map_regions(repo):
    regions = landmark_regions(repo)
    out = {}
    for raw in open(os.path.join(repo, "data", "maps", "maps.asm"), encoding="utf-8"):
        m = re.match(r"\s*map\s+(\w+),\s*\w+,\s*\w+,\s*(\w+)", raw)
        if m:
            out[m.group(1)] = regions.get(m.group(2), "other")
    return out


def initial_events(repo):
    """Flags InitializeEventsScript sets on New Game (mostly 'hide this
    object until later').  They can't be 'found', so sweeps skip them."""
    path = os.path.join(repo, "engine", "events", "std_scripts.asm")
    if not os.path.exists(path):
        return set()
    s = open(path, encoding="utf-8").read()
    a = s.find("InitializeEventsScript:")
    if a < 0:
        return set()
    b = s.find("\n\tend", a)
    return set(re.findall(r"setevent (EVENT_\w+)", s[a:b]))


def scan_maps(repo, flags):
    regions = map_regions(repo)
    initial = initial_events(repo)
    trainers, items, hidden, gifts = [], [], [], []
    seen_trainer = set()
    for fname in sorted(os.listdir(os.path.join(repo, "maps"))):
        if not fname.endswith(".asm"):
            continue
        mapname = fname[:-4]
        region = regions.get(mapname, "other")
        text = open(os.path.join(repo, "maps", fname), encoding="utf-8").read()
        lines = text.splitlines()
        # label -> itemball item
        itemball = {}
        label = None
        pending_give = []  # items given in the current label, waiting for setevent
        for raw in lines:
            line = raw.split(";")[0].rstrip()
            m = re.match(r"^(\.?\w+):", line)
            if m:
                label = m.group(1)
                pending_give = []
                continue
            s = line.strip()
            m = re.match(r"itemball\s+(\w+)", s)
            if m and label:
                itemball[label] = m.group(1)
                continue
            m = re.match(r"hiddenitem\s+(\w+),\s*(EVENT_\w+)", s)
            if m and m.group(2) in flags:
                hidden.append((flags[m.group(2)], m.group(2), m.group(1), mapname, region))
                continue
            m = re.match(r"trainer\s+\w+,\s*\w+,\s*(EVENT_\w+)", s)
            if m and m.group(1) in flags and m.group(1) not in seen_trainer:
                seen_trainer.add(m.group(1))
                trainers.append((flags[m.group(1)], m.group(1), mapname, region))
                continue
            m = re.match(r"(?:verbose)?giveitem\s+(\w+)", s)
            if m and m.group(1) != "ITEM_FROM_MEM":
                pending_give.append(m.group(1))
                continue
            m = re.match(r"setevent\s+(EVENT_\w+)", s)
            if m and pending_give and m.group(1) in flags:
                for item in pending_give:
                    gifts.append((flags[m.group(1)], m.group(1), item, mapname, region))
                pending_give = []
                continue
            if s.startswith(("end", "closetext", "waitbutton")) and not s.startswith("endif"):
                pass
        for raw in lines:
            m = re.search(r"OBJECTTYPE_ITEMBALL,\s*\w+,\s*(\w+),\s*(EVENT_\w+)", raw)
            if m and m.group(2) in flags:
                items.append((flags[m.group(2)], m.group(2), itemball.get(m.group(1), "?"), mapname, region))
    # one row per flag
    def uniq(rows):
        out, seen = [], set()
        for r in rows:
            if r[1] in initial:
                continue
            if r[0] not in seen:
                seen.add(r[0])
                out.append(r)
        return out
    return uniq(trainers), uniq(items), uniq(hidden), uniq(gifts)


# Pokemon a Johto player can get without leaving Johto or trading:
# Johto grass/water, fishing, Headbutt trees, swarms, the Bug-Catching
# Contest, roaming beasts and Johto gifts.  Used for Crystal's "only Johto
# Pokemon" challenges (a local reading of RA's wording).
JOHTO_EXTRA = ["CHIKORITA", "CYNDAQUIL", "TOTODILE", "TOGEPI", "SPEAROW", "ONIX", "MACHOP",
               "VOLTORB", "SHUCKLE", "EEVEE", "TYROGUE", "RHYDON", "DRATINI", "LAPRAS",
               "SUDOWOODO", "GYARADOS", "RAIKOU", "ENTEI", "SUICUNE", "LUGIA", "HO_OH",
               "PICHU", "CLEFFA", "IGGLYBUFF", "SMOOCHUM", "MAGBY", "ELEKID"]


def johto_species(repo):
    species = set(parse_consts(os.path.join(repo, "constants", "pokemon_constants.asm")))
    out = set(JOHTO_EXTRA)
    wild = os.path.join(repo, "data", "wild")
    if not os.path.isdir(wild):
        return []
    for fname in ("johto_grass.asm", "johto_water.asm", "fish.asm", "treemons.asm",
                  "swarm_grass.asm", "swarm_water.asm", "bug_contest_mons.asm"):
        path = os.path.join(wild, fname)
        if not os.path.exists(path):
            continue
        for raw in open(path, encoding="utf-8"):
            line = raw.split(";")[0]
            for m in re.finditer(r"\b([A-Z][A-Z0-9_]{2,})\b", line):
                word = m.group(1)
                if word in species:
                    out.add(word)
    # evolutions of those count too: a Johto Pokemon raised into its final form
    return sorted(out)


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def write(game, source, repo):
    flags = parse_consts(os.path.join(repo, "constants", "event_flags.asm"))
    trainers, items, hidden, gifts = scan_maps(repo, flags)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"gen2_{game}.lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"-- Generated by tools/gen2_data.py from {source} -- do not edit by hand.\n")
        f.write("-- Event flag numbers and what the maps hold, for this mod's Gen 2 rules.\n")
        f.write("return {\n  flags = {\n")
        for name in sorted(flags, key=lambda n: flags[n]):
            f.write(f"    {name} = {flags[name]},\n")
        f.write("  },\n  trainers = {\n")
        for fid, name, mapname, region in trainers:
            f.write(f"    {{ {fid}, {lua_str(name)}, {lua_str(mapname)}, {lua_str(region)} }},\n")
        for key, rows in (("items", items), ("hidden", hidden)):
            f.write(f"  }},\n  {key} = {{\n")
            for fid, name, item, mapname, region in rows:
                f.write(f"    {{ {fid}, {lua_str(name)}, {lua_str(item)}, {lua_str(mapname)}, {lua_str(region)} }},\n")
        f.write("  },\n  gifts = {\n")
        for fid, name, item, mapname, region in gifts:
            f.write(f"    {{ {fid}, {lua_str(name)}, {lua_str(item)}, {lua_str(mapname)}, {lua_str(region)} }},\n")
        f.write("  },\n  johto = {\n")
        for sp in johto_species(repo):
            f.write(f"    {sp} = true,\n")
        f.write("  },\n}\n")
    print(f"{game}: {len(flags)} flags, {len(trainers)} trainers, {len(items)} items, "
          f"{len(hidden)} hidden, {len(gifts)} gifts -> {os.path.relpath(path)}")


if __name__ == "__main__":
    gold_repo, crystal_repo = sys.argv[1], sys.argv[2]
    write("gold", "pret/pokegold", gold_repo)
    write("silver", "pret/pokegold", gold_repo)
    write("crystal", "pret/pokecrystal", crystal_repo)
