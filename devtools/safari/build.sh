#!/usr/bin/env bash
#
# Build the Swiflow DevTools Safari web extension.
#
# Step 1 (always, no Xcode needed): assemble the web-extension source dir
#   (./extension) from the single source of truth in ../chrome. The panel logic
#   is byte-for-byte identical across browsers — only the manifest diverges —
#   so we COPY the shared files here rather than maintaining a second copy.
# Step 2 (only if full Xcode is installed): run safari-web-extension-converter
#   to generate + open the macOS wrapper Xcode project under ./xcode. Without
#   full Xcode the converter is absent; we print the exact command + an install
#   hint and exit 0 — ./extension is still valid, ready-to-convert output.
#
# Re-run this any time you edit the shared panel sources in ../chrome.
# ./extension and ./xcode are gitignored build artifacts.
#
# Usage:  ./build.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(cd "$here/../chrome" && pwd)"   # ../chrome -> the Chrome extension dir
dst="$here/extension"
proj="$here/xcode"

# Files shared verbatim between the Chrome and Safari extensions. The manifest
# is intentionally NOT here — Safari uses this dir's manifest.json instead.
shared=(
  devtools.html
  devtools.js
  panel.html
  panel.js
  panel-icon.svg
  colors.css
  design_system_tokens.css
  application_tokens.css
)

# Reassemble from scratch so deletions in ../chrome don't linger here.
rm -rf "$dst"
mkdir -p "$dst"

for f in "${shared[@]}"; do
  if [[ ! -f "$src/$f" ]]; then
    echo "error: missing shared source $src/$f" >&2
    exit 1
  fi
  cp "$src/$f" "$dst/$f"
done

# The Safari manifest (this dir's manifest.json) lands as the extension's
# manifest.json. Differences from the Chrome manifest: no side_panel, no
# sidePanel/webNavigation permissions, no minimum_chrome_version.
cp "$here/manifest.json" "$dst/manifest.json"

echo "Assembled ${#shared[@]} shared file(s) + manifest into $dst"

# --- Step 2: convert to a macOS Xcode project (requires full Xcode.app) ---
converter_cmd=(
  xcrun safari-web-extension-converter "$dst"
  --macos-only
  --app-name "Swiflow DevTools"
  --bundle-identifier dev.swiflow.devtools
  --project-location "$proj"
  --no-prompt
  --force
)

if xcrun --find safari-web-extension-converter >/dev/null 2>&1; then
  echo "Converting to a macOS Xcode project under $proj ..."
  mkdir -p "$proj"
  "${converter_cmd[@]}"
else
  hint="$(printf '%q ' "${converter_cmd[@]}")"
  cat >&2 <<EOF

Full Xcode is required to convert + build the Safari extension, but
'safari-web-extension-converter' was not found (you likely have only the
Command Line Tools). To finish:

  1. Install Xcode.app from the App Store.
  2. sudo xcode-select -s /Applications/Xcode.app
  3. Re-run ./build.sh, or run the converter directly:

     ${hint}

The ./extension directory was assembled successfully and is ready to convert.
EOF
fi
