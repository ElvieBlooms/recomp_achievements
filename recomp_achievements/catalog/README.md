# Catalogs

One file per game (`red.lua` through `leafgreen.lua`, eleven in all) holds
the official RetroAchievements list for that game: title, description,
points, author, display order and type. The in-game browser and popups
show this text for every rule linked to an RA entry (see
`rules/gen1_official.lua`, `gen2_official.lua`, `gen3_official.lua`,
`gen3_emerald.lua` and `gen3_rs.lua`).

Achievement titles, descriptions and related metadata are courtesy of
RetroAchievements (https://retroachievements.org) and each achievement's
author. RetroAchievements' terms permit reuse of this metadata. Their
achievement trigger logic is not used. Every check in this mod is its own.

The files are generated, not hand-written:

```
RA_API_KEY=<your key> python3 tools/fetch_ra_catalog.py red blue yellow gold silver crystal \
  ruby sapphire emerald firered leafgreen
```

The script prints what changed since the last import, including entries
added or removed and entries whose trigger logic changed upstream, so a
rule can be reviewed. Saved progress is keyed by this mod's rule ids, so
regenerating catalogs never affects anyone's earned achievements.

Without these files the mod still works and shows its own fallback text.

`links.lua` (optional, not shipped) can map extra rules to RA ids:
`return { rule_id = { red = 1234 } }`.
