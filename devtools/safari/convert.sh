#!/usr/bin/env bash
#
# Generate the Safari Web Extension Xcode project from ./extension using
# Apple's safari-web-extension-converter. Produces a macOS app target that
# wraps the web extension; you then build / sign / notarize it in Xcode (see
# SPEC.md) or with notarize.sh.
#
# The converter ships inside Xcode.app. This machine's `xcode-select` may still
# point at the Command Line Tools, so we pin DEVELOPER_DIR to Xcode.app instead
# of requiring `sudo xcode-select -s`.
#
# Usage:  ./convert.sh
#
# Override defaults via env:
#   APP_NAME, BUNDLE_ID, XCODE_APP
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ext_dir="$here/extension"
project_dir="$here/SwiflowDevTools"   # gitignored; regenerable

APP_NAME="${APP_NAME:-Swiflow DevTools}"
BUNDLE_ID="${BUNDLE_ID:-com.swiflow.devtools}"
XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"

if [[ ! -d "$ext_dir" ]]; then
  echo "error: $ext_dir not found — run ./sync.sh first" >&2
  exit 1
fi
if [[ ! -d "$XCODE_APP" ]]; then
  echo "error: Xcode not found at $XCODE_APP (set XCODE_APP=/path/to/Xcode.app)" >&2
  exit 1
fi

export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

echo "Converting $ext_dir → $project_dir"
echo "  app:    $APP_NAME"
echo "  bundle: $BUNDLE_ID"
echo "  xcode:  $XCODE_APP"
echo

# --macos-only        a DevTools panel only exists in macOS Safari's Web
#                     Inspector; iOS Safari has no extension-panel surface.
# --copy-resources    copy ./extension into the project so the build doesn't
#                     depend on this dir's layout.
# --no-open           don't auto-launch Xcode; CI/headless friendly.
# --no-prompt         skip the interactive confirmation (would hang a script).
# --force             overwrite a previous generation in $project_dir.
xcrun safari-web-extension-converter "$ext_dir" \
  --app-name "$APP_NAME" \
  --bundle-identifier "$BUNDLE_ID" \
  --project-location "$project_dir" \
  --macos-only \
  --copy-resources \
  --no-open \
  --no-prompt \
  --force

echo
echo "Done. Open the project:"
echo "  open \"$project_dir/$APP_NAME/$APP_NAME.xcodeproj\""
echo "Then follow SPEC.md → 'Finish in Xcode'."
