#!/usr/bin/env python3
"""Event flag numbers for Gold/Silver and Crystal, read from the pret
disassemblies (constants/event_flags.asm), the same source Gen1Recomp uses.

    python3 tools/gen2_flags.py <pokegold dir> <pokecrystal dir>

Prints a quick check; used by tools/gen2_data.py.
"""
import re
import sys


def parse_consts(path, prefix=None):
    value, out = 0, {}
    for raw in open(path, encoding="utf-8"):
        line = raw.split(";")[0].strip()
        if not line:
            continue
        m = re.match(r"const_def(?:\s+(-?\d+))?", line)
        if m:
            value = int(m.group(1) or 0)
            continue
        m = re.match(r"const_next\s+(\d+)", line)
        if m:
            value = int(m.group(1))
            continue
        m = re.match(r"const_skip(?:\s+(\d+))?", line)
        if m:
            value += int(m.group(1) or 1)
            continue
        m = re.match(r"const\s+(\w+)", line)
        if m:
            if prefix is None or m.group(1).startswith(prefix):
                out[m.group(1)] = value
            value += 1
    return out


if __name__ == "__main__":
    gold = parse_consts(sys.argv[1] + "/constants/event_flags.asm")
    crystal = parse_consts(sys.argv[2] + "/constants/event_flags.asm")
    print(len(gold), len(crystal), gold.get("EVENT_BEAT_FALKNER"), crystal.get("EVENT_BEAT_FALKNER"))
