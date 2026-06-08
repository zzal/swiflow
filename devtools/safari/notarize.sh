#!/usr/bin/env bash
#
# Sign (Developer ID) + notarize + staple the built Swiflow DevTools .app, so it
# can be shared with teammates without enabling "Allow Unsigned Extensions".
#
# TEMPLATE — fill in the placeholders / env vars below. This runs OUTSIDE the
# App Store (Developer ID distribution). Prerequisites that are NOT yet present
# on this machine (see SPEC.md → "Prerequisites"):
#   1. A "Developer ID Application: <Your Name> (TEAMID)" certificate in your
#      login keychain. Create it in Xcode → Settings → Accounts → Manage
#      Certificates → ＋ → "Developer ID Application".
#         Verify with:  security find-identity -v -p codesigning
#   2. A notarytool credential profile stored in the keychain:
#         xcrun notarytool store-credentials swiflow-notary \
#           --apple-id "you@example.com" \
#           --team-id "TEAMID" \
#           --password "app-specific-password"   # appleid.apple.com → App-Specific Passwords
#
# Usage:
#   APP_PATH="…/Swiflow DevTools.app" SIGN_ID="Developer ID Application: …" ./notarize.sh
set -euo pipefail

APP_PATH="${APP_PATH:?set APP_PATH to the built .app (Release)}"
SIGN_ID="${SIGN_ID:?set SIGN_ID to your 'Developer ID Application: …' identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-swiflow-notary}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: $APP_PATH not found" >&2
  exit 1
fi

echo "==> Codesigning (deep, hardened runtime, timestamped)"
# The wrapper app embeds the appex; --deep signs the nested extension too. The
# hardened runtime (--options runtime) is mandatory for notarization.
codesign --force --deep --timestamp \
  --options runtime \
  --sign "$SIGN_ID" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Zipping for submission"
zip_path="$(dirname "$APP_PATH")/$(basename "$APP_PATH" .app).zip"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$zip_path"

echo "==> Submitting to Apple notary service (waits for result)"
xcrun notarytool submit "$zip_path" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling the ticket to the .app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo
echo "Notarized + stapled: $APP_PATH"
echo "Distribute the .app (or a zip/dmg of it). Launch it once on each Mac to"
echo "register the extension, then enable it in Safari → Settings → Extensions."
