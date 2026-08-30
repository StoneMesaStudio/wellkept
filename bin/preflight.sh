#!/usr/bin/env bash
#
# preflight.sh — the one command to run before shipping this app.
#
# It rebuilds the Xcode project from project.yml, then builds and RUNS THE TESTS for every
# platform this app ships on, plus any local Swift package and any Node backend. If anything
# fails it exits non-zero — which is what stops `bin/release.sh` from notarising a broken build.
#
# WHAT gets checked is defined per-app in bin/preflight.conf (next to this file).
#
# Usage:
#   bin/preflight.sh            # run the full check
#   bin/preflight.sh --dry-run  # print what it WOULD run, without running it
#
# Escape hatch (when the gate itself is the broken thing):
#   SKIP_PREFLIGHT=1 bin/release.sh
#
# Override the iOS simulator used for tests:
#   PREFLIGHT_IOS_DEST='platform=iOS Simulator,name=iPhone 16' bin/preflight.sh
#
# ── Provenance ──────────────────────────────────────────────────────────────────────────────────
# This file is the UNION of the four copies that had drifted apart across the house, each of which
# had one improvement the others lacked. Nothing here is new invention; it is three fixes that
# already existed, finally in one file:
#
#   Lode / Scout      -derivedDataPath build/preflight  (see the block comment in run_xcode)
#   writing-app       test timeouts + TEST_NEEDS_SIGNING
#   fitness-app       the SWIFT_PACKAGES loop
#
# Keep it that way: a fix made here is meant to be copied back verbatim to the others.
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

DRYRUN="${PREFLIGHT_DRYRUN:-0}"
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRYRUN=1 ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "preflight: unknown argument: $a" >&2; exit 2 ;;
  esac
done

CONF="$ROOT/bin/preflight.conf"
[ -f "$CONF" ] || { echo "preflight: missing $CONF" >&2; exit 2; }
APP_NAME=""; CHECKS=(); BACKENDS=(); SWIFT_PACKAGES=(); TEST_NEEDS_SIGNING=0
# shellcheck disable=SC1090
source "$CONF"

PROJ="$(ls -d ./*.xcodeproj 2>/dev/null | head -1 || true)"; PROJ="${PROJ#./}"

# ---- pretty helpers -------------------------------------------------------
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }

FAILED=""
trap '[ -n "$FAILED" ] && { echo; bad "PREFLIGHT FAILED at: $FAILED"; exit 1; }' EXIT

# ---- destination tokens ---------------------------------------------------
ios_sim_dest() {
  if [ -n "${PREFLIGHT_IOS_DEST:-}" ]; then printf '%s' "$PREFLIGHT_IOS_DEST"; return; fi
  local name
  name="$(xcrun simctl list devices available 2>/dev/null \
        | sed -nE 's/^[[:space:]]*(iPhone [0-9][0-9]*)[[:space:]]*\(.*/\1/p' \
        | sort -t' ' -k2 -n | tail -1)"
  [ -n "$name" ] && printf 'platform=iOS Simulator,name=%s' "$name" \
                 || printf 'platform=iOS Simulator,name=iPhone 17'
}
expand_dest() {
  case "$1" in
    macos)         printf 'platform=macOS' ;;
    ios-sim)       ios_sim_dest ;;
    ios-generic)   printf 'generic/platform=iOS Simulator' ;;
    watch-generic) printf 'generic/platform=watchOS Simulator' ;;
    *)             printf '%s' "$1" ;;   # already a full -destination string
  esac
}

bold "Preflight — ${APP_NAME:-$(basename "$ROOT")}  ($PROJ)"
[ "$DRYRUN" = 1 ] && echo "(dry run — nothing will actually build)"

# ---- regenerate the project from project.yml ------------------------------
# Wellkept.xcodeproj is gitignored and generated. Skipping this is how a newly added .swift file
# silently isn't in the build — and a section that never compiled still passes a gate.
if [ -f project.yml ]; then
  if command -v xcodegen >/dev/null 2>&1; then
    step "xcodegen generate"
    if [ "$DRYRUN" = 1 ]; then echo "  would run: xcodegen generate"
    else xcodegen generate >/dev/null && ok "project regenerated from project.yml"; fi
    PROJ="$(ls -d ./*.xcodeproj 2>/dev/null | head -1 || true)"; PROJ="${PROJ#./}"
  else
    echo "  (xcodegen not installed — using the committed $PROJ as-is)"
  fi
fi
# In a dry run nothing was generated, so there is nothing to find — name what WOULD be built
# rather than refusing to print the plan.
if [ -z "$PROJ" ]; then
  if [ "$DRYRUN" = 1 ]; then PROJ="${APP_NAME:-App}.xcodeproj"
  else echo "preflight: no .xcodeproj, and no xcodegen to make one" >&2; exit 2; fi
fi

# ---- xcode builds / tests -------------------------------------------------
have_xcbeautify=0; command -v xcbeautify >/dev/null 2>&1 && have_xcbeautify=1

run_xcode() {  # $1 scheme  $2 dest  $3 action(build|test)
  local scheme="$1" dest="$2" action="$3"

  # ⚠️ -derivedDataPath IS LOAD-BEARING. Without it this writes `CODE_SIGNING_ALLOWED=NO` output
  # into the SAME Build/Products/… bundle that Xcode signs — so running the gate silently REPLACES
  # the runnable app with an unsigned one.
  #
  # In Lode that cost most of 2026-08-09: an unsigned build has no entitlements, so on macOS it
  # loses its sandbox container, quietly moves to `~/Library/Application Support/default.store`,
  # and is refused by the data-protection keychain. Every fix was built, gated, launched — and the
  # gate de-signed the very build being tested, so the app being run was pointed at a different
  # database from the one being inspected.
  #
  # ⚠️ It is WORSE in Wellkept, for the opposite reason. This app is deliberately unsandboxed and
  # its whole job is reading the machine. macOS ties Full Disk Access to a specific signature at a
  # specific path: de-sign the build and every permission it was granted evaporates. The app still
  # launches, still runs every check, and reports a clean bill of health on a machine it can no
  # longer see. A health tool that lies when it is blindfolded is the single worst failure
  # available here, and this one flag is what prevents it.
  #
  # The gate gets its own DerivedData. It must never touch the app anyone runs.
  local cmd=(xcodebuild -project "$PROJ" -scheme "$scheme" -destination "$dest"
             -configuration Debug
             -derivedDataPath build/preflight)

  if [ "$action" = test ]; then
    # A hung test should fail the gate, not block it forever. 120s is deliberately generous: this
    # file is byte-identical across the house and several apps run simulator-hosted suites, where a
    # tighter cap would be a NEW failure mode the day the file is copied.
    cmd+=(-parallel-testing-enabled NO
          -test-timeouts-enabled YES -default-test-execution-time-allowance 120)
    # Default stays the fast UNSIGNED path — a logic bundle needs no identity. An app whose test
    # bundle is HOSTED by the real app AND whose startup touches something entitlement-gated sets
    # TEST_NEEDS_SIGNING=1 in its own preflight.conf; unsigned, that host dies before the runner
    # connects and every test "fails" for a reason unrelated to the tests.
    if [ "${TEST_NEEDS_SIGNING:-0}" = 1 ]; then cmd+=(-allowProvisioningUpdates)
    else cmd+=(CODE_SIGNING_ALLOWED=NO); fi
  else
    cmd+=(CODE_SIGNING_ALLOWED=NO)
  fi

  cmd+=("$action")
  if [ "$DRYRUN" = 1 ]; then echo "  would run: ${cmd[*]}"; return 0; fi
  if [ "$have_xcbeautify" = 1 ]; then "${cmd[@]}" | xcbeautify --renderer terminal
  else "${cmd[@]}"; fi
}

if [ "${#CHECKS[@]}" -gt 0 ]; then
  for entry in "${CHECKS[@]}"; do
    [ -z "$entry" ] && continue
    IFS='|' read -r label scheme desttok action <<<"$entry"
    label="$(echo "$label" | xargs)"; scheme="$(echo "$scheme" | xargs)"
    desttok="$(echo "$desttok" | xargs)"; action="$(echo "$action" | xargs)"
    dest="$(expand_dest "$desttok")"
    step "$label — $action  [$scheme]"
    echo "  destination: $dest"
    FAILED="$label ($scheme)"
    run_xcode "$scheme" "$dest" "$action"
    ok "$label passed"
    FAILED=""
  done
fi

# ---- swift package tests --------------------------------------------------
# For logic that lives in a local SwiftPM package whose tests the app scheme's Test action does
# NOT run. `swift test` runs them directly.
if [ "${#SWIFT_PACKAGES[@]}" -gt 0 ]; then
  for pkg in "${SWIFT_PACKAGES[@]}"; do
    [ -z "$pkg" ] && continue
    step "swift package — $pkg  (swift test)"
    FAILED="swift package $pkg"
    if [ "$DRYRUN" = 1 ]; then echo "  would run: swift test --package-path $pkg"
    else swift test --package-path "$pkg"; fi
    ok "swift package $pkg passed"
    FAILED=""
  done
fi

# ---- node backends --------------------------------------------------------
if [ "${#BACKENDS[@]}" -gt 0 ]; then
  for b in "${BACKENDS[@]}"; do
    [ -z "$b" ] && continue
    step "backend — $b  (npm ci && npm test)"
    FAILED="backend $b"
    if [ "$DRYRUN" = 1 ]; then echo "  would run: (cd $b && npm ci && npm test)"
    else ( cd "$b" && npm ci --silent && npm test ); fi
    ok "backend $b passed"
    FAILED=""
  done
fi

echo
if [ "$DRYRUN" = 1 ]; then bold "Dry run complete — the commands above are what preflight would run."
else bold "✅ PREFLIGHT PASSED — ${APP_NAME:-app} builds and tests clean."; fi
