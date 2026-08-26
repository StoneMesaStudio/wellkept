#!/usr/bin/env bash
#
# make-shots.sh — redraw the pictures of Wellkept's own screens.
#
# Every one is rendered from the real views, with `ImageRenderer`, inside the `ViewShots` test
# bundle — no window, no launch, no permissions, nothing on this Mac read. That is the point: it
# works before the app can do anything, which is exactly when a picture is most useful.
#
#   bin/make-shots.sh                     # write the PNGs into build/shots
#   bin/make-shots.sh /some/other/folder  # write them somewhere else
#   bin/make-shots.sh --open              # …and open the folder when it's done
#
# It fails, loudly, when a view renders blank. `ImageRenderer` does not error on a view that
# declines to lay out — a `ScrollView` with no window is the classic — it returns a picture of the
# background and reports success. `ShotWriter` counts the distinct colours and records an Issue,
# which fails the test, which is what makes this script exit non-zero.
#
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

OPEN_WHEN_DONE=0
OUT=""
for a in "$@"; do
  case "$a" in
    --open)    OPEN_WHEN_DONE=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    -*)        echo "make-shots: unknown argument: $a" >&2; exit 2 ;;
    *)         OUT="$a" ;;
  esac
done
OUT="${OUT:-$ROOT/build/shots}"
mkdir -p "$OUT"

# Absolute, because the test process does not inherit this script's working directory.
OUT="$(cd "$OUT" && pwd)"

command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not found — brew install xcodegen"; exit 1; }
xcodegen generate >/dev/null

# Old shots are cleared first. A stale PNG from a suite that no longer exists is worse than a
# missing one: it looks current, and it is the picture somebody will send to John.
rm -f "$OUT"/*.png

echo "Rendering into $OUT…"

LOG="$ROOT/build/last-shots.log"
mkdir -p "$ROOT/build"

# `-derivedDataPath` for the same reason preflight has one: this must never overwrite the signed
# build in build/release that carries the app's Full Disk Access grant.
#
# ⚠️ **`TEST_RUNNER_` is not decoration.** The test process does not inherit this shell's
# environment. `xcodebuild` forwards exactly those variables whose names begin with `TEST_RUNNER_`,
# stripping the prefix on the way in — so `WELLKEPT_SHOTS_DIR=… xcodebuild test` sets the variable
# on xcodebuild and on nothing that runs the tests. The symptom is a green run that writes every
# picture into a temp folder and an output folder that stays empty.
set +e
TEST_RUNNER_WELLKEPT_SHOTS_DIR="$OUT" xcodebuild test \
    -project Wellkept.xcodeproj \
    -scheme Wellkept \
    -destination 'platform=macOS' \
    -configuration Debug \
    -derivedDataPath build/shots-derived \
    -only-testing:ViewShots \
    CODE_SIGNING_ALLOWED=NO \
    >"$LOG" 2>&1
STATUS=$?
set -e

# The harness prints one of these per picture: VIEWSHOT <path> <w>x<h> colours:<n>
grep '^VIEWSHOT ' "$LOG" | sed 's/^VIEWSHOT /  /' || true
grep '^PROBE '    "$LOG" | sed 's/^PROBE /  probe: /' || true

if [ "$STATUS" -ne 0 ]; then
  echo
  echo "Some shots failed. The reason is one of these:"
  grep -E "blank —|produced nothing|didn't compile|error:|✘" "$LOG" | head -12 | sed 's/^/  /'
  echo
  echo "Full log: $LOG"
  exit 1
fi

COUNT="$(ls -1 "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')"
if [ "$COUNT" = "0" ]; then
  # A green run that wrote nothing means the suite filter matched no tests — the same vacuous pass
  # the ColorRuleGuard's file-count assertion exists to prevent, in a different costume.
  echo "The tests passed but wrote no pictures. -only-testing:ViewShots matched nothing."
  echo "Full log: $LOG"
  exit 1
fi

echo
echo "Wrote $COUNT pictures to $OUT"
[ "$OPEN_WHEN_DONE" = 1 ] && open "$OUT"
exit 0
