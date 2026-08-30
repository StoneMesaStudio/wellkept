#!/usr/bin/env bash
#
# make-launcher.sh — build the double-clickable "Rebuild Wellkept" app and put it where the
# other rebuild launchers live.
#
#   ./bin/make-launcher.sh
#
# Run this once. Re-run it only to change how the launcher itself behaves, or to give it the app
# icon once one exists — what the launcher DOES lives in `bin/rebuild-and-launch.sh`, which it
# calls by path, so ordinary fixes need no rebuild of the applet.
#
# It exists because the person building this app does not open Xcode. This applet is the entire
# build interface: double click, wait, the new build is running.

set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"

APP_NAME="Wellkept"
# ~/Library/Scripts, beside Rebuild Scout, Rebuild Lode, Rebuild Waypoint and the rest. That is
# where they live; the Desktop was Scout's choice and copying it would have scattered them.
DEST="$HOME/Library/Scripts/Rebuild $APP_NAME.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The AppleScript is generated rather than committed as a separate file so the project path is
# baked in literally — an applet has no notion of a working directory.
cat > "$WORK/launcher.applescript" <<APPLESCRIPT
-- Rebuild $APP_NAME
--
-- A thin shim. All it does is run bin/rebuild-and-launch.sh and turn a failure into a dialog a
-- human will actually read. Every decision that matters — building to the one path macOS ties Full
-- Disk Access to, refusing to launch a build whose signature is wrong, quitting the stale copy,
-- launching through \`open\` — lives in that script.
--
-- No "tell application" against anything but the shell: sending another app an Apple Event needs
-- macOS automation permission, and this exists to remove chores, not add a dialog.

on run
	set repoPath to "$PROJECT_ROOT"
	set buildScript to quoted form of (repoPath & "/bin/rebuild-and-launch.sh")

	display notification "Building the latest code…" with title "Rebuild $APP_NAME"

	try
		-- Combines stderr into stdout so a failure's reason survives to the dialog below.
		set output to do shell script buildScript & " 2>&1"
		-- The script's last line is already a sentence; show that rather than a status code.
		display notification (last paragraph of output) with title "Rebuild $APP_NAME"
	on error errMsg
		-- \`do shell script\` puts the script's own output in the error message on a non-zero
		-- exit, which is exactly the readable sentence the build script prints. Shown as-is.
		set cleanMsg to errMsg
		if cleanMsg starts with "Error: " then
			set cleanMsg to text 8 thru -1 of cleanMsg
		end if
		display dialog cleanMsg with title "Rebuild $APP_NAME — didn't work" buttons {"Show Log", "OK"} default button "OK" with icon caution
		if button returned of result is "Show Log" then
			do shell script "open -R " & quoted form of (repoPath & "/build/last-build.log") & " 2>/dev/null || true"
		end if
	end try
end run
APPLESCRIPT

rm -rf "$DEST"
osacompile -o "$DEST" "$WORK/launcher.applescript"

# ── Icon ────────────────────────────────────────────────────────────────────────────────────────
# Until the stethoscope master lands in the asset catalog, the launcher keeps the generic applet
# face. When `icon_1024.png` is there, this block gives the launcher the same face — built from the
# app's own master, so the two cannot drift apart.
# `bin/make-icon.sh` names the largest file for its point size and scale, so the 1024-pixel master
# is `icon_512x512@2x.png`. Looking for `icon_1024.png` silently found nothing and left the applet
# with the generic face.
SRC="$PROJECT_ROOT/App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
if [[ -f "$SRC" ]]; then
    ICONSET="$WORK/wellkept.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$DEST/Contents/Resources/applet.icns"
    touch "$DEST"
else
    echo "(no icon_1024.png yet — the launcher keeps the generic applet icon)"
fi

echo "Built: $DEST"
echo "Double-click it to rebuild $APP_NAME and relaunch it."
