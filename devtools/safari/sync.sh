#!/usr/bin/env bash
#
# Assemble the Safari web-extension source directory (./extension) from the
# single source of truth in ../chrome (the Chrome extension). The panel logic is
# byte-for-byte identical across browsers — only the manifest diverges — so we
# COPY the shared files here rather than maintaining a second hand-edited copy.
#
# Run this once before converting (see convert.sh), and again any time you edit
# the shared panel sources in ../ . The ./extension directory is gitignored: it
# is a build artifact, not source.
#
# Usage:  ./sync.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(cd "$here/../chrome" && pwd)"   # ../chrome -> the Chrome extension dir
dst="$here/extension"

# Files shared verbatim between the Chrome and Safari extensions. The manifest
# is intentionally NOT in this list — Safari uses manifest.safari.json instead.
shared=(
  devtools.html
  devtools.js
  panel.html
  panel.js
  colors.css
  design_system_tokens.css
  application_tokens.css
)

mkdir -p "$dst"

for f in "${shared[@]}"; do
  if [[ ! -f "$src/$f" ]]; then
    echo "error: missing shared source $src/$f" >&2
    exit 1
  fi
  cp "$src/$f" "$dst/$f"
done

# The Safari manifest (source of truth: manifest.safari.json) lands as the
# extension's manifest.json. Differences from the Chrome manifest:
#   - no "side_panel" / "sidePanel" permission   (Chrome-only API)
#   - no "webNavigation" permission              (panel uses devtools.network
#                                                 .onNavigated, which needs none)
#   - no "minimum_chrome_version"                (meaningless to Safari)
cp "$here/manifest.safari.json" "$dst/manifest.json"

echo "Synced ${#shared[@]} shared file(s) + manifest into $dst"
