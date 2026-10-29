#!/usr/bin/env bash
# Build a release zip of the mod.
#   tools/build_release.sh
# Runs both test suites, regenerates docs/COVERAGE.md, then zips
# recomp_achievements/ (plus LICENSE/NOTICE/CHANGELOG/docs) into dist/.
# The example provider and all test tooling stay out of the zip.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VERSION=$(python3 -c "import json;print(json.load(open('recomp_achievements/manifest.json'))['version'])")
echo "== Recomp Achievements $VERSION"

echo "== tests"
PROJECT="$ROOT" luajit tests/run.lua | tail -1
PROJECT="$ROOT" luajit tests/official.lua | tail -1
python3 tests/test_leaderboard.py 2>&1 | tail -1

echo "== coverage"
luajit tools/gen_coverage.lua "$ROOT"

echo "== package"
STAGE=$(mktemp -d)
mkdir -p "$STAGE/recomp_achievements"
cp -r recomp_achievements/. "$STAGE/recomp_achievements/"
# never ship a developer key file or local link overrides by accident
rm -f "$STAGE/recomp_achievements/catalog/links.lua"
cp LICENSE NOTICE.md CHANGELOG.md "$STAGE/recomp_achievements/"
mkdir -p "$STAGE/recomp_achievements/docs"
cp docs/PROVIDER_API.md docs/COVERAGE.md "$STAGE/recomp_achievements/docs/"
# no driver, tests or bytecode may ever ride along
if find "$STAGE" -name "e2e_driver" -o -name "*.luac" | grep -q .; then
  echo "refusing to package test files" >&2; exit 1
fi
mkdir -p dist
rm -f "dist/recomp_achievements-$VERSION.zip"
(cd "$STAGE" && zip -qr "$ROOT/dist/recomp_achievements-$VERSION.zip" recomp_achievements)
rm -rf "$STAGE"
echo "wrote dist/recomp_achievements-$VERSION.zip"
