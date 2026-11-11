#!/usr/bin/env bash
# tools/build_release.sh
# Builds the release zips: the mod, and the Recomp Achievements Online add-on.
#   tools/build_release.sh
# Runs the test suites, regenerates docs/COVERAGE.md, then zips
# recomp_achievements/ with LICENSE, NOTICE, CHANGELOG and the docs into dist/.
# Files sit at the archive root, the shape the mod index and the launcher's
# Import mod .zip, Update and Versions expect. With a gen1recomp checkout in
# $G1R_ROOT, modkit validate --strict and lint run on the staged folder first.
# The example provider and all the test tooling stay out of the zip.
# The add-on keeps the same version as the mod, since both come from the same
# GitHub release and the launcher's Update matches <id>-<tag>.zip.
# ------------------
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VERSION=$(python3 -c "import json;print(json.load(open('recomp_achievements/manifest.json'))['version'])")
ONLINE_VERSION=$(python3 -c "import json;print(json.load(open('recomp_achievements_online/manifest.json'))['version'])")
echo "== Recomp Achievements $VERSION"
if [ "$ONLINE_VERSION" != "$VERSION" ]; then
  echo "recomp_achievements_online is $ONLINE_VERSION, the mod is $VERSION; they ship together" >&2; exit 1
fi

echo "== tests"
PROJECT="$ROOT" luajit tests/run.lua | tail -1
PROJECT="$ROOT" luajit tests/official.lua | tail -1
python3 tests/test_leaderboard.py 2>&1 | tail -1
python3 tests/test_discord_board.py 2>&1 | tail -1
node tests/test_discord_worker.mjs | tail -1

echo "== coverage"
luajit tools/gen_coverage.lua "$ROOT"

echo "== package"
STAGE=$(mktemp -d)
mkdir -p "$STAGE/recomp_achievements"
cp -r recomp_achievements/. "$STAGE/recomp_achievements/"
# Local link overrides are for development only, so they never ship.
rm -f "$STAGE/recomp_achievements/catalog/links.lua"
cp LICENSE NOTICE.md CHANGELOG.md "$STAGE/recomp_achievements/"
mkdir -p "$STAGE/recomp_achievements/docs"
cp docs/PROVIDER_API.md docs/COVERAGE.md "$STAGE/recomp_achievements/docs/"
# The e2e driver and compiled bytecode must never end up in a release.
if find "$STAGE" -name "e2e_driver" -o -name "*.luac" | grep -q .; then
  echo "refusing to package test files" >&2; exit 1
fi
if [ -n "${G1R_ROOT:-}" ] && [ -f "$G1R_ROOT/tools/modkit.py" ]; then
  echo "== modkit"
  (cd "$G1R_ROOT" && python3 tools/modkit.py validate "$STAGE/recomp_achievements" --strict \
    && python3 tools/modkit.py lint "$STAGE/recomp_achievements")
fi
mkdir -p dist
rm -f "dist/recomp_achievements-$VERSION.zip"
(cd "$STAGE/recomp_achievements" && zip -qr "$ROOT/dist/recomp_achievements-$VERSION.zip" .)
rm -rf "$STAGE"
echo "wrote dist/recomp_achievements-$VERSION.zip"

echo "== package online add-on"
if grep -q "REPLACE_ME" recomp_achievements_online/main.lua; then
  echo "skipped: set SERVER in recomp_achievements_online/main.lua to the Worker address first" >&2
  exit 0
fi
STAGE=$(mktemp -d)
mkdir -p "$STAGE/recomp_achievements_online"
cp -r recomp_achievements_online/. "$STAGE/recomp_achievements_online/"
cp NOTICE.md "$STAGE/recomp_achievements_online/"
if [ -n "${G1R_ROOT:-}" ] && [ -f "$G1R_ROOT/tools/modkit.py" ]; then
  echo "== modkit (online)"
  # modkit mounts one mod at a time, so the dependency on the main mod is
  # taken out of a scratch copy for validate; the zip keeps it.
  CHECK=$(mktemp -d)
  cp -r "$STAGE/recomp_achievements_online" "$CHECK/"
  python3 -c "import json,sys;p=sys.argv[1];m=json.load(open(p));m['dependencies']=[];json.dump(m,open(p,'w'))" \
    "$CHECK/recomp_achievements_online/manifest.json"
  (cd "$G1R_ROOT" && python3 tools/modkit.py validate "$CHECK/recomp_achievements_online" --strict \
    && python3 tools/modkit.py lint "$STAGE/recomp_achievements_online")
  rm -rf "$CHECK"
fi
rm -f "dist/recomp_achievements_online-$VERSION.zip"
(cd "$STAGE/recomp_achievements_online" && zip -qr "$ROOT/dist/recomp_achievements_online-$VERSION.zip" .)
rm -rf "$STAGE"
echo "wrote dist/recomp_achievements_online-$VERSION.zip"
