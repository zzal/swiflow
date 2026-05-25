#!/bin/sh
# Measure the Counter example WASM + JS bundle size.
# Writes <repo-root>/current-bundle.json and prints a Markdown table.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE_DIR="$REPO_ROOT/examples/HelloWorld"
SWIFLOW_BIN="$REPO_ROOT/.build/release/swiflow"

if [ ! -x "$SWIFLOW_BIN" ]; then
    echo "==> Building swiflow CLI (release)..." >&2
    (cd "$REPO_ROOT" && swift build -c release --product swiflow)
fi

echo "==> Cleaning example build..." >&2
(cd "$EXAMPLE_DIR" && swift package clean)

echo "==> Building Counter WASM bundle..." >&2
(cd "$EXAMPLE_DIR" && "$SWIFLOW_BIN" build)

OUT_DIR="$EXAMPLE_DIR/.build/plugins/PackageToJS/outputs/Package"
WASM="$OUT_DIR/App.wasm"

if [ ! -f "$WASM" ]; then
    echo "error: WASM artifact not found at $WASM" >&2
    exit 1
fi

file_bytes() { wc -c < "$1" | tr -d ' '; }
gzip_bytes() { gzip -9 -c "$1" | wc -c | tr -d ' '; }

WASM_BYTES=$(file_bytes "$WASM")
WASM_GZIP=$(gzip_bytes "$WASM")

# Sum all .js files in the PackageToJS output (index.js, runtime.js,
# instantiate.js, platforms/browser.js, etc.). The HTML imports index.js
# which transitively pulls in the rest, so all of them land in the browser.
JS_BYTES=0
JS_GZIP=0
for js in $(find "$OUT_DIR" -name '*.js' | sort); do
    JS_BYTES=$((JS_BYTES + $(file_bytes "$js")))
    JS_GZIP=$((JS_GZIP + $(gzip_bytes "$js")))
done

TOTAL_GZIP=$((WASM_GZIP + JS_GZIP))

SWIFT_VERSION=$(swift --version 2>&1 | head -1 | sed 's/.*Swift version //; s/ .*//')
WASM_SDK_VERSION=$(swift sdk list 2>/dev/null | grep -i wasm | head -1 | sed 's/^swift-//; s/_wasm.*//' || echo "unknown")
MEASURED_AT=$(date -u +%Y-%m-%d)

cat > "$REPO_ROOT/current-bundle.json" <<EOF
{
  "example": "examples/HelloWorld",
  "swift_version": "$SWIFT_VERSION",
  "wasm_sdk_version": "$WASM_SDK_VERSION",
  "measured_at": "$MEASURED_AT",
  "wasm_bytes": $WASM_BYTES,
  "wasm_gzip_bytes": $WASM_GZIP,
  "js_bytes": $JS_BYTES,
  "js_gzip_bytes": $JS_GZIP,
  "total_gzip_bytes": $TOTAL_GZIP
}
EOF

printf "\n"
printf "| Artifact          | Bytes       | Gzipped     |\n"
printf "| ----------------- | ----------: | ----------: |\n"
printf "| App.wasm          | %11s | %11s |\n" "$WASM_BYTES" "$WASM_GZIP"
printf "| JS runtime (all)  | %11s | %11s |\n" "$JS_BYTES" "$JS_GZIP"
printf "| **Total (gzip)**  |             | %11s |\n" "$TOTAL_GZIP"
printf "\nWrote %s\n" "$REPO_ROOT/current-bundle.json"
