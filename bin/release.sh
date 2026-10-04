#!/usr/bin/env bash
#
# release.sh — build, sign, notarise and package Wellkept for direct download.
#
# Wellkept never goes to the Mac App Store (guideline 2.4.5 forbids most of what it does), so
# Apple's blessing arrives a different way: the app is signed with a Developer ID certificate, sent
# to Apple's notary service, and the resulting ticket is *stapled* into the app and the disk image.
# Stapling is the part people forget — without it a Mac that is offline, or behind a captive
# portal, refuses to open the app.
#
#   bin/release.sh              # the full thing
#   bin/release.sh --dry-run    # print what it would do
#
# Escape hatch, for when the gate is the thing that is broken:
#   SKIP_PREFLIGHT=1 bin/release.sh
#
# This will not be run for a while. It exists now so that the first release is not invented under
# pressure at the end of a long day.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "release: unknown argument: $a" >&2; exit 2 ;;
  esac
done

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
die()  { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then echo "  would run: $*"; else "$@"; fi; }

APP_NAME="Wellkept"
BUNDLE_ID="studio.stonemesa.wellkept"
DIST="$ROOT/dist"
BUILD="$ROOT/build/release-signed"
APP="$BUILD/$APP_NAME.app"

VERSION="$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?/\1/p' project.yml | head -1)"
[ -n "$VERSION" ] || die "Could not read MARKETING_VERSION out of project.yml."
DMG="$DIST/$APP_NAME-$VERSION.dmg"

bold "Releasing $APP_NAME $VERSION"

# ---- 1. The certificate ---------------------------------------------------
# A "Developer ID Application" certificate is a different thing from the "Apple Distribution"
# certificate used for TestFlight, and only it can be notarised. Nothing below works without one.
step "Developer ID certificate"
# Apple retires the original Developer ID authority on 2027-02-01, and every certificate it issued
# stops working that day; its replacements come from the G2 authority. So a Mac
# can hold several Developer ID certificates under one name, which makes the name ambiguous to
# codesign. Sign by SHA-1 instead, and take the certificate that expires last.
pick_developer_id() {
  local valid line hash="" pem="" end epoch best="" best_epoch=0
  valid="$(security find-identity -v -p codesigning \
      | sed -nE 's/^ *[0-9]+\) ([0-9A-F]{40}) "Developer ID Application: .*"$/\1/p')"
  while IFS= read -r line; do
    case "$line" in
      "SHA-1 hash: "*) hash="${line#SHA-1 hash: }"; pem="" ;;
      "-----BEGIN CERTIFICATE-----") pem="$line" ;;
      "-----END CERTIFICATE-----")
        pem="$pem"$'\n'"$line"
        printf '%s\n' "$valid" | grep -qx "$hash" || continue
        end="$(printf '%s\n' "$pem" | openssl x509 -noout -enddate | sed 's/^notAfter=//')"
        epoch="$(date -j -u -f "%b %e %T %Y %Z" "$end" +%s)"
        if [ "$epoch" -gt "$best_epoch" ]; then best="$hash"; best_epoch="$epoch"; fi ;;
      *) [ -n "$pem" ] && pem="$pem"$'\n'"$line" ;;
    esac
  done < <(security find-certificate -a -Z -p -c "Developer ID Application")
  [ -n "$best" ] && printf '%s %s\n' "$best" "$best_epoch"
  return 0
}
PICKED="$(pick_developer_id)"
IDENTITY="${PICKED%% *}"
IDENTITY_NAME="$(security find-identity -v -p codesigning \
    | sed -nE "s/.*$IDENTITY \"(.*)\"\$/\1/p" | head -1)"
if [ -z "$IDENTITY" ]; then
  die "No Developer ID Application certificate on this Mac.

  developer.apple.com ▸ Certificates ▸ + ▸ Developer ID Application ▸
  G2 Sub-CA (Xcode 11.4.1 or later), then upload a certificate signing request.

  Only the account holder can do it. Not in Xcode: on 2026-10-03 its Manage
  Certificates ▸ + issued a certificate from the authority that expires on
  2027-02-01. The \"Apple Distribution\" certificate already installed is for
  TestFlight and the App Store; the notary service will not accept it."
fi
ok "$IDENTITY_NAME"
EXPIRES="${PICKED##* }"
DAYS_LEFT=$(( (EXPIRES - $(date +%s)) / 86400 ))
if [ "$DAYS_LEFT" -lt 60 ]; then
  printf '  \033[33m!\033[0m This certificate expires in %s days (%s). Create a new Developer ID\n' \
    "$DAYS_LEFT" "$(date -r "$EXPIRES" +%Y-%m-%d)"
  printf '    Application certificate at developer.apple.com, choosing G2 Sub-CA.\n'
fi

# ⭐ The team is read out of the certificate, never checked into the repo. A Developer ID identity
# is spelled "Developer ID Application: Some Name (TEAMID1234)", so the answer is already sitting
# in the string we just matched — and a hardcoded team in a public file is an account identifier
# for anybody who clones it. `WELLKEPT_TEAM_ID` overrides, for a Mac with several teams installed.
TEAM_ID="${WELLKEPT_TEAM_ID:-$(printf '%s' "$IDENTITY_NAME" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')}"
[ -n "$TEAM_ID" ] || die "Could not read a team out of the certificate:
  $IDENTITY_NAME
  Set WELLKEPT_TEAM_ID=XXXXXXXXXX and run this again."
ok "team $TEAM_ID"

# ---- 2. Notary credentials ------------------------------------------------
# The issuer is team-wide, so the key any of the studio's apps uses works here too.
step "Notary credentials"
CREDS=""
for candidate in "$HOME/.appstoreconnect/wellkept.env" "$HOME/.appstoreconnect/catchall.env"; do
  [ -f "$candidate" ] && { CREDS="$candidate"; break; }
done
[ -n "$CREDS" ] || die "No App Store Connect credentials found.

  Expected ~/.appstoreconnect/wellkept.env or ~/.appstoreconnect/catchall.env with:
    APP_STORE_CONNECT_KEY_ID=...
    APP_STORE_CONNECT_ISSUER_ID=...
    APP_STORE_CONNECT_KEY_PATH=\$HOME/.appstoreconnect/private_keys/AuthKey_<ID>.p8"
# shellcheck disable=SC1090
source "$CREDS"
: "${APP_STORE_CONNECT_KEY_ID:?missing in $CREDS}"
: "${APP_STORE_CONNECT_ISSUER_ID:?missing in $CREDS}"
: "${APP_STORE_CONNECT_KEY_PATH:?missing in $CREDS}"
[ -f "$APP_STORE_CONNECT_KEY_PATH" ] || die "Key file not found: $APP_STORE_CONNECT_KEY_PATH"
ok "using $(basename "$CREDS")"

# ---- 3. The gate ----------------------------------------------------------
if [ "${SKIP_PREFLIGHT:-0}" = 1 ]; then
  echo "  (preflight skipped by SKIP_PREFLIGHT=1)"
else
  step "Preflight"
  run bin/preflight.sh
fi

# ---- 4. Build, signed for distribution ------------------------------------
step "Build"
run rm -rf "$BUILD" "$DIST"
run mkdir -p "$BUILD" "$DIST"
run xcodegen generate
run xcodebuild \
  -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/release-derived \
  CONFIGURATION_BUILD_DIR="$BUILD" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build
[ "$DRY" = 1 ] || [ -d "$APP" ] || die "The build reported success but produced no app at $APP"
ok "built"

# ---- 5. Check the signature before Apple does -----------------------------
# Cheaper to fail here than to wait out a notary round trip and be told the same thing.
step "Verify the hardened runtime and the entitlements"
if [ "$DRY" = 0 ]; then
  codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'

  # Captured, not piped. `codesign -dvv | grep -q` looks like the obvious check and is a trap:
  # grep exits the moment it matches, codesign takes SIGPIPE, and under `pipefail` the pipeline
  # reports failure — so a build that is perfectly correct fails the test for having passed it.
  DESCRIPTION="$(codesign -dvv "$APP" 2>&1 || true)"
  printf '%s\n' "$DESCRIPTION" | grep -E "Authority|Timestamp|TeamIdentifier|flags" | sed 's/^/  /'

  case "$DESCRIPTION" in
    *"flags="*runtime*) ;;
    *) die "The hardened runtime is not on. Notarisation will refuse this build." ;;
  esac
  case "$DESCRIPTION" in
    *"TeamIdentifier=$TEAM_ID"*) ;;
    *) die "This build is not signed by Stone Mesa Studio ($TEAM_ID)." ;;
  esac

  ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
  [ -n "$ENTITLEMENTS" ] || die "Entitlements are unreadable."

  # The debug entitlement. `xcodebuild build` injects it; `xcodebuild archive` does not, which is
  # why this only ever bites the first time somebody ships without archiving. Apple's notary
  # service rejects it outright, and finding that out costs a full round trip — so it is checked
  # here, where the answer is instant.
  case "$ENTITLEMENTS" in
    *get-task-allow*)
      die "The build carries com.apple.security.get-task-allow — the debug entitlement.
  Notarisation refuses it. CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO is what keeps it out." ;;
  esac

  # ⚠️ Wellkept is deliberately UNSANDBOXED — it reads the machine, which is the whole product.
  # A sandbox entitlement arriving by accident (a stray Xcode "fix", a copied entitlements file)
  # would not fail to build and would not fail to launch. It would ship an app that quietly sees
  # a container instead of a Mac and reports it as healthy. Checked here because there is no
  # later moment where anybody would notice.
  #
  # ⚠️ **The KEY set to false is the correct configuration, and this check used to reject it.**
  # `App/Support/Wellkept.entitlements` declares `app-sandbox` as `<false/>` on purpose — saying so
  # out loud is better than an absence somebody later reads as an oversight, and Scout ships the
  # same pair. Matching the key name alone failed the first real release on the very line that
  # documents the decision. What must fail is the key set to TRUE.
  SANDBOXED=$(/usr/bin/plutil -extract com.apple.security.app-sandbox raw -o - - <<<"$ENTITLEMENTS" 2>/dev/null || echo false)
  if [ "$SANDBOXED" = "true" ] || [ "$SANDBOXED" = "1" ]; then
      die "This build carries the app-sandbox entitlement, set to true.
  Wellkept is unsandboxed on purpose: sandboxed, it can see almost none of the disk and would
  report an empty machine as a healthy one. Check App/Support/Wellkept.entitlements."
  fi
fi
ok "signed with a timestamp and the hardened runtime, unsandboxed, no debug entitlement"

# ---- 6. Notarise the app --------------------------------------------------
# The app is notarised on its own first, then stapled, and only then packaged — so the ticket
# travels with the app even after somebody drags it out of the disk image.
step "Notarise the app"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
run /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
run xcrun notarytool submit "$ZIP" \
  --key "$APP_STORE_CONNECT_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait
run xcrun stapler staple "$APP"
run rm -f "$ZIP"
ok "notarised and stapled"

# ---- 7. Disk image --------------------------------------------------------
step "Disk image"
STAGE="$DIST/stage"
run mkdir -p "$STAGE"
run cp -R "$APP" "$STAGE/"
# The Applications symlink is the whole of the install instructions.
run ln -s /Applications "$STAGE/Applications"
run hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
run rm -rf "$STAGE"
run codesign --sign "$IDENTITY" --timestamp "$DMG"
ok "$(basename "$DMG")"

# ---- 8. Notarise the disk image too ---------------------------------------
# Otherwise the first thing a new user sees is Gatekeeper refusing the download itself.
step "Notarise the disk image"
run xcrun notarytool submit "$DMG" \
  --key "$APP_STORE_CONNECT_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait
run xcrun stapler staple "$DMG"
ok "notarised and stapled"

# ---- 9. What a stranger's Mac will say ------------------------------------
step "What a stranger's Mac will say"
if [ "$DRY" = 0 ]; then
  spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/  /'
  xcrun stapler validate "$DMG" 2>&1 | sed 's/^/  /'
fi

echo
bold "✅ $(basename "$DMG") is ready to publish."
echo "   $DMG"
echo
echo "Next: the download page on stonemesastudio.com, and the file on GitHub Releases."
echo "The updater bakes that address in permanently, so it is settled before the first release,"
echo "not after."
