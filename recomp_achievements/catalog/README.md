# Catalogs

`red.lua`, `blue.lua` and `yellow.lua` hold the official RetroAchievements
lists for each game: title, description, points, author, display order and
type. The in-game browser and popups show this text for every rule linked
to an RA entry (see `rules/gen1_official.lua`).

Achievement titles, descriptions and related metadata are courtesy of
RetroAchievements (https://retroachievements.org) and each achievement's
author. RetroAchievements' terms permit reuse of this metadata. Their
achievement trigger logic is not used. Every check in this mod is its own.

The files are generated, not hand-written:

```
RA_API_KEY=<your key> python3 tools/fetch_ra_catalog.py red blue yellow
```

The script prints what changed since the last import, including entries
added or removed and entries whose trigger logic changed upstream, so a
rule can be reviewed. Saved progress is keyed by this mod's rule ids, so
regenerating catalogs never affects anyone's earned achievements.

Without these files the mod still works and shows its own fallback text.

`links.lua` (optional, not shipped) can map extra rules to RA ids:
`return { rule_id = { red = 1234 } }`.
