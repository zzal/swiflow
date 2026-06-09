#!/usr/bin/env bash
#
# Build the Swiflow DevTools Safari web extension.
#
# Two stages:
#   1. Assemble the web-extension source dir (./extension) from the single
#      source of truth in ../chrome. The panel logic is byte-for-byte identical
#      across browsers — only the manifest diverges — so we COPY the shared
#      files here rather than maintaining a second copy. This stage always runs
#      and needs no Xcode.
#   2. Wrap ./extension in a macOS Xcode project (./xcode) with
#      safari-web-extension-converter. By DEFAULT this runs only the first time
#      (when the project doesn't exist yet); on later runs it is skipped so your
#      manual "Sign to Run Locally" settings survive — just rebuild in Xcode
#      (⌘R) to pick up the re-synced sources.
#
# Modes:
#   ./build.sh              Assemble, then convert only if ./xcode doesn't exist
#                           yet (otherwise skip conversion, preserving signing).
#   ./build.sh --sync-only  Assemble ./extension only; never run the converter.
#   ./build.sh --reconvert  Assemble, then always (re)generate the Xcode project.
#                           This overwrites it, so you must re-set "Sign to Run
#                           Locally" on both targets afterward.
#
# Note: re-syncing updates the CONTENTS of files already in the project. A
# brand-new file (e.g. a new icon) still has to be added to the Xcode project
# once — drag it in, or run --reconvert.
#
# ./extension and ./xcode are gitignored build artifacts.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(cd "$here/../chrome" && pwd)"   # ../chrome -> the Chrome extension dir
dst="$here/extension"
proj="$here/xcode"
app_name="Swiflow DevTools"
xcodeproj="$proj/$app_name/$app_name.xcodeproj"

usage() {
  cat <<'EOF'
Usage: ./build.sh [--sync-only | --reconvert]

Assemble ./extension from ../chrome (+ the Safari manifest.json), then wrap it
in a macOS Xcode project via safari-web-extension-converter.

  (no flag)     Assemble, then run the converter ONLY if the Xcode project
                doesn't exist yet. If it already exists, skip conversion so your
                "Sign to Run Locally" settings survive — just rebuild in Xcode.
  --sync-only   Assemble ./extension only; never run the converter.
  --reconvert   Assemble, then always regenerate the Xcode project. Overwrites
                it, so you must re-set "Sign to Run Locally" on both targets.
EOF
}

# --- Parse mode --------------------------------------------------------------
mode="auto"
case "${1:-}" in
  "")          mode="auto" ;;
  --sync-only) mode="sync-only" ;;
  --reconvert) mode="reconvert" ;;
  -h|--help)   usage; exit 0 ;;
  *)           echo "error: unknown option '$1' (try: ./build.sh --help)" >&2; usage >&2; exit 2 ;;
esac

# --- Stage 1: assemble ./extension (always) ----------------------------------
# Browser-agnostic CORE files, shared verbatim from ../chrome (the Chrome
# extension is their source of truth). NOTE: datasource.js is intentionally NOT
# here — it's the per-browser transport, and Safari supplies its own (below).
# The manifest is also not here; Safari uses this dir's manifest.json.
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

# Safari-specific encapsulation, supplied from THIS dir (not shared with
# Chrome): the messaging data source + the relay bridge it talks to.
local_files=(
  datasource.js
  bridge-sw.js
  bridge-content.js
  bridge-page.js
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

for f in "${local_files[@]}"; do
  if [[ ! -f "$here/$f" ]]; then
    echo "error: missing Safari source $here/$f" >&2
    exit 1
  fi
  cp "$here/$f" "$dst/$f"
done

# The Safari manifest (this dir's manifest.json) lands as the extension's
# manifest.json. It differs from Chrome's: no side_panel/sidePanel, and it adds
# the bridge (background + content_scripts + web_accessible_resources) plus the
# host_permissions that the messaging data source needs.
cp "$here/manifest.json" "$dst/manifest.json"

echo "Assembled ${#shared[@]} core + ${#local_files[@]} Safari file(s) + manifest into $dst"

# --- Stage 2: wrap in a macOS Xcode project (requires full Xcode.app) --------
if [[ "$mode" == "sync-only" ]]; then
  echo "Sync-only: skipped Xcode project generation. Rebuild in Xcode (⌘R) to apply."
  exit 0
fi

if [[ "$mode" == "auto" && -d "$xcodeproj" ]]; then
  echo "Xcode project already exists — skipped conversion (your signing is preserved):"
  echo "  $xcodeproj"
  echo "Rebuild in Xcode (⌘R) to pick up the re-synced sources."
  echo "(Run './build.sh --reconvert' to regenerate the project from scratch.)"
  exit 0
fi

converter_cmd=(
  xcrun safari-web-extension-converter "$dst"
  --macos-only
  --app-name "$app_name"
  --bundle-identifier dev.swiflow.devtools
  --project-location "$proj"
  --no-prompt
  --force
)

if xcrun --find safari-web-extension-converter >/dev/null 2>&1; then
  if [[ "$mode" == "reconvert" ]]; then
    echo "Regenerating the Xcode project (this resets signing — re-apply 'Sign to Run Locally')..."
  else
    echo "Generating the macOS Xcode project under $proj ..."
  fi
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
