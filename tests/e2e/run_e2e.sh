#!/usr/bin/env bash
# Boot the real game headless with our mods and a test plan.
#   run_e2e.sh <game> <plan.lua> [seconds] [extra mod dirs...]
# Uses COPIES of the extracted data folder; originals are never touched.
set -u
GAME=$1; PLAN=$2; SECS=${3:-60}; shift 3 || true
HERE=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(cd "$HERE/../.." && pwd)
ENGINE=${ENGINE:-/home/claude/engine}
SRC=${GAMEDATA:-/home/claude/src_extract/pokemon-love2d}
RUN=${E2E_RUN:-$(mktemp -d)}
SAVE="$RUN/love/pokemon-love2d"
mkdir -p "$SAVE/mods" "$SAVE/saves"
cp -r "$SRC/$GAME" "$SAVE/"
[ -d "$SRC/saves/$GAME" ] && cp -r "$SRC/saves/$GAME" "$SAVE/saves/"
[ -n "${KEEP_OPTIONS:-}" ] && cp "$SRC/options.lua" "$SAVE/" 2>/dev/null
for m in ${MODS:-recomp_achievements achievement_sandbox}; do cp -r "$PROJECT/$m" "$SAVE/mods/"; done
cp -r "$HERE/e2e_driver" "$SAVE/mods/"
cp "$PLAN" "$SAVE/mods/e2e_driver/plan.lua"
echo "run dir: $RUN"
XDG_DATA_HOME="$RUN" timeout "$SECS" xvfb-run -a -s "-screen 0 800x720x24" \
  love "$ENGINE" --game="$GAME" ${SLOT:+--slot=$SLOT} 2>&1 | grep -v "^ALSA\|^AL lib" | tee "$RUN/stdout.log" | grep -E "E2E|rror|recomp|sandbox|warn" | head -${LINES_MAX:-80}
echo "exit: ${PIPESTATUS[0]}"
