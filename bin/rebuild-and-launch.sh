#!/bin/bash
#
# Rebuild Wellkept from source and launch it — no Xcode window required.
#
# This is the engine behind the "Rebuild Wellkept" app on the Desktop (built by
# `bin/make-launcher.sh`). It lives in the repo, not inside that applet, so the logic is
# version-controlled and one edit here fixes the launcher too.
#
#   ./bin/rebuild-and-launch.sh          # build, verify the signature, then launch
#   ./bin/rebuild-and-launch.sh --build  # build and verify only, don't launch
#
# Exit 0 = built and launched. Non-zero = something failed, and the reason is the last thing on
# stdout — the launcher shows exactly that text in its dialog, so it has to read as a sentence to
# someone who is not going to open a log.

set -uo pipefail

# ── PATH, explicitly ────────────────────────────────────────────────────────────────────────────
# A GUI-launched applet inherits a bare PATH, NOT the one from the shell profile. `xcodegen` lives
# in Homebrew, so without this line the launcher fails with "xcodegen: command not found" while the
# identical command works fine in Terminal.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

APP_NAME="Wellkept"
BUNDLE_ID="studio.stonemesa.wellkept"

# ⭐ The signing team is read off this Mac, never checked into the repo — it is an account
# identifier and this file is public. Every codesigning identity is spelled
# "…: Some Name (TEAMID1234)", so the team is already in the keychain listing.
#
# ⚠️ **Developer ID first, and that ordering is load-bearing.** A Mac signed into more than one
# Apple account lists several identities, and taking whichever comes first would sign this build
# under a team that is not the one Full Disk Access was granted to — so it would build, launch,
# see almost nothing, and report a healthy Mac. The signature gate below catches it, but only
# after a wasted build. `WELLKEPT_TEAM_ID` overrides both.
TEAM_ID="${WELLKEPT_TEAM_ID:-}"
if [[ -z "$TEAM_ID" ]]; then
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    TEAM_ID="$(printf '%s\n' "$IDENTITIES" \
        | sed -nE 's/.*"Developer ID Application: .*\(([A-Z0-9]{10})\)".*/\1/p' | head -1)"
    [[ -z "$TEAM_ID" ]] && TEAM_ID="$(printf '%s\n' "$IDENTITIES" \
        | sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p' | head -1)"
fi
if [[ -z "$TEAM_ID" ]]; then
    echo "There's no code-signing certificate on this Mac, so the build can't be signed."
    echo "Open Xcode ▸ Settings ▸ Accounts and add one, then try again."
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || { echo "Can't find the Wellkept project folder."; exit 1; }

LAUNCH=1
[[ "${1:-}" == "--build" ]] && LAUNCH=0

# ── Where the app lands, and why it must not move ───────────────────────────────────────────────
# macOS ties Full Disk Access to a specific app — and for a locally-signed build, to the path it
# was granted at. Building somewhere new means granting Full Disk Access again, which for THIS app
# is not a cosmetic annoyance: without it Wellkept cannot see most of the disk, and a health check
# that cannot see the machine is a health check that says everything is fine.
BUILD_DIR="$PROJECT_ROOT/build/release"
APP="$BUILD_DIR/$APP_NAME.app"
LOG="$PROJECT_ROOT/build/last-build.log"
SIGFILE="$PROJECT_ROOT/build/last-signature.txt"
mkdir -p "$PROJECT_ROOT/build"

# ── 1. Regenerate the Xcode project ─────────────────────────────────────────────────────────────
# Wellkept.xcodeproj is gitignored and generated from project.yml, whose globs pick up App/.
# Skipping this is how a newly added .swift file silently isn't in the build.
if ! xcodegen generate >"$LOG" 2>&1; then
    echo "Couldn't prepare the Xcode project."
    echo
    tail -12 "$LOG"
    exit 1
fi

# ── 2. Build ────────────────────────────────────────────────────────────────────────────────────
# Signed, because the permission grants above follow the signature as well as the path. An unsigned
# or re-signed build looks like a different app to macOS and starts from nothing.
echo "Building…"
if ! xcodebuild \
        -project "$APP_NAME.xcodeproj" \
        -scheme "$APP_NAME" \
        -configuration Release \
        -destination 'platform=macOS' \
        -allowProvisioningUpdates \
        -derivedDataPath build/launch-derived \
        CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        build >"$LOG" 2>&1; then
    echo "The build failed."
    echo
    # The compiler's own error lines, not the thousands of lines of noise around them.
    grep -E "error:" "$LOG" | head -8 | sed 's/^.*\/\([^/]*\.swift\)/\1/' || tail -12 "$LOG"
    echo
    echo "Full log: $LOG"
    exit 1
fi

[[ -d "$APP" ]] || { echo "The build reported success but produced no app. Full log: $LOG"; exit 1; }

# ── 3. The signature gate ───────────────────────────────────────────────────────────────────────
#
# ⚠️ **This script refuses to launch a build whose signature is wrong, and that matters more in
# Wellkept than anywhere else in the house.**
#
# Full Disk Access is granted to a signature at a path. An ad-hoc-signed or unsigned build is a
# different app as far as macOS is concerned: it launches perfectly, shows every section, runs
# every check — and sees almost nothing, because TCC silently returns empty rather than raising an
# error. The visible result is a Mac that looks healthy. Shipping "everything is fine" from a
# blindfolded scan is the worst thing this app can do, so a bad signature stops here rather than
# being discovered from a screenshot.
#
# Three questions, cheapest first.
SIGNATURE_PROBLEM=""

# (a) Is the seal intact? A stale bundle with new files copied in fails this.
if ! codesign --verify --deep --strict "$APP" >>"$LOG" 2>&1; then
    SIGNATURE_PROBLEM="the code signature doesn't verify"
fi

# Captured, not piped. `codesign -dvv | grep -q` looks like the obvious check and is a trap: grep
# exits the moment it matches, codesign takes SIGPIPE, and under pipefail the pipeline reports
# failure — so a build that is perfectly correct fails the test for having passed it.
DESCRIPTION="$(codesign -dvv "$APP" 2>&1)"

# (b) Ad-hoc means "signed by nobody". macOS will not keep a permission grant for it.
if [[ -z "$SIGNATURE_PROBLEM" ]] && [[ "$DESCRIPTION" == *"Signature=adhoc"* ]]; then
    SIGNATURE_PROBLEM="it is ad-hoc signed, which macOS treats as a brand-new app every time"
fi

# (c) The right team. A build signed by some other identity keeps none of this app's grants.
if [[ -z "$SIGNATURE_PROBLEM" ]] && [[ "$DESCRIPTION" != *"TeamIdentifier=$TEAM_ID"* ]]; then
    SIGNATURE_PROBLEM="it isn't signed by Stone Mesa Studio ($TEAM_ID)"
fi

if [[ -n "$SIGNATURE_PROBLEM" ]]; then
    echo "Built, but not launched: $SIGNATURE_PROBLEM."
    echo
    echo "macOS ties Full Disk Access to the signature. This build would run, find almost"
    echo "nothing, and tell you your Mac is fine. Fix the signing before using it."
    echo
    echo "Full log: $LOG"
    exit 1
fi

# The identity itself, remembered between runs. When it changes, every permission this app was
# granted has just been revoked by macOS — the app will look unchanged and behave as if the disk
# is empty, so it is worth saying out loud rather than leaving to be discovered.
AUTHORITY="$(printf '%s\n' "$DESCRIPTION" | sed -nE 's/^Authority=(.*)$/\1/p' | head -1)"
SIGNATURE_CHANGED=0
if [[ -f "$SIGFILE" ]] && [[ "$(cat "$SIGFILE")" != "$AUTHORITY" ]]; then
    SIGNATURE_CHANGED=1
fi
printf '%s\n' "$AUTHORITY" > "$SIGFILE"

if [[ "$LAUNCH" == "0" ]]; then
    echo "Built and signature-checked. Not launching (--build)."
    exit 0
fi

# ── 4. Quit the copy that is already running ────────────────────────────────────────────────────
FORCED=0
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "$APP_NAME" >/dev/null || break
    sleep 0.3
done
if pgrep -x "$APP_NAME" >/dev/null; then
    pkill -9 -x "$APP_NAME" >/dev/null 2>&1
    FORCED=1
    sleep 0.5
fi

# ── 5. Launch ───────────────────────────────────────────────────────────────────────────────────
# Through `open`, never by running the binary directly: a directly-executed binary is a different
# thing to macOS and does not carry the app's permissions with it — the same blindfold as an
# unsigned build, arrived at a different way.
#
# Worth retrying rather than giving up. The build replaces the bundle at a path LaunchServices
# already knows, and for a second or two afterwards `open` can answer -600 (procNotFound) — it is
# still holding the registration for the copy that was just quit. Waiting it out fixes it; if it
# does not, re-registering the bundle does.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
LAUNCH_ERROR=""

launch_app() {
    LAUNCH_ERROR="$(open "$APP" 2>&1)"
    [[ -z "$LAUNCH_ERROR" ]]
}

if ! launch_app; then
    sleep 1
    if ! launch_app; then
        [[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$APP" >/dev/null 2>&1
        sleep 1
        if ! launch_app; then
            echo "Built successfully, but macOS wouldn't launch it."
            echo
            echo "$LAUNCH_ERROR"
            echo
            echo "Opening it from the Finder usually works: $APP"
            exit 1
        fi
    fi
fi

# `open` returns as soon as the request is accepted, which is not the same as the app running.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "$APP_NAME" >/dev/null && break
    sleep 0.3
done
if ! pgrep -x "$APP_NAME" >/dev/null; then
    echo "macOS accepted the launch but $APP_NAME isn't running. The app is at: $APP"
    exit 1
fi

# ── 6. What to say ──────────────────────────────────────────────────────────────────────────────
# One sentence, because it becomes the text of a notification.
if [[ "$SIGNATURE_CHANGED" == "1" ]]; then
    echo "$APP_NAME rebuilt and relaunched — but the signing certificate changed, so its Full Disk Access has been reset."
elif [[ "$FORCED" == "1" ]]; then
    echo "$APP_NAME rebuilt and relaunched. The old copy had to be forced to quit."
else
    echo "$APP_NAME rebuilt and relaunched."
fi

# ── 7. Warn about another copy that would shadow this one ───────────────────────────────────────
# A copy in /Applications answers to Spotlight, the Dock and `open -a Wellkept` by name — so the
# one that opens could quietly be an older build, with its own separate set of permissions.
INSTALLED="/Applications/$APP_NAME.app"
if [[ -d "$INSTALLED" ]]; then
    THIS_BUILT=$(stat -f %m "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || echo 0)
    THAT_BUILT=$(stat -f %m "$INSTALLED/Contents/MacOS/$APP_NAME" 2>/dev/null || echo 0)
    if (( THAT_BUILT < THIS_BUILT )); then
        echo
        echo "Heads up: there is an older $APP_NAME in your Applications folder. Opening it from"
        echo "Spotlight or the Dock gets that one, not this build."
    fi
fi
exit 0
