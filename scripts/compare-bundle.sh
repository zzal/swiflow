#!/bin/sh
# Compare current-bundle.json against scripts/bundle-baseline.json.
# Exit 0 if total gzip growth <= 5%, else exit 1 — unless PR_LABELS
# contains "bundle-size-skip" AND growth <= 20%.
#
# When $GITHUB_OUTPUT is set, also writes the report under the `report` key.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="$REPO_ROOT/scripts/bundle-baseline.json"
CURRENT="$REPO_ROOT/current-bundle.json"

if [ ! -f "$BASELINE" ]; then
    echo "error: baseline missing at $BASELINE" >&2
    exit 2
fi
if [ ! -f "$CURRENT" ]; then
    echo "error: $CURRENT missing — run Scripts/measure-bundle.sh first" >&2
    exit 2
fi

PR_LABELS="${PR_LABELS:-}"

python3 - "$BASELINE" "$CURRENT" "$PR_LABELS" <<'PYEOF'
import json, os, sys

baseline_path, current_path, pr_labels = sys.argv[1], sys.argv[2], sys.argv[3]
baseline = json.load(open(baseline_path))
current = json.load(open(current_path))

def human(b):
    if b >= 1024 * 1024:
        return f"{b / 1024 / 1024:.2f} MB"
    if b >= 1024:
        return f"{b / 1024:.1f} KB"
    return f"{b} B"

def pct(c, b):
    if b == 0:
        return "n/a"
    return f"{(c - b) / b * 100:+.2f}%"

b_total = baseline["total_gzip_bytes"]
c_total = current["total_gzip_bytes"]
delta_pct = (c_total - b_total) / b_total * 100

if delta_pct > 20:
    status = "❌ Growth exceeds 20% hard limit — bump the baseline in this PR."
    exit_code = 1
elif delta_pct > 5:
    if "bundle-size-skip" in pr_labels:
        status = "⚠️  Growth exceeds 5% budget but `bundle-size-skip` label is set — passing."
        exit_code = 0
    else:
        status = "❌ Growth exceeds 5% budget. Apply the `bundle-size-skip` label and bump `scripts/bundle-baseline.json` if intentional."
        exit_code = 1
else:
    status = "✅ Within budget (≤5% growth allowed)."
    exit_code = 0

report = f"""### 📦 Bundle size

| Artifact          | Baseline   | This PR    | Δ |
| ----------------- | ---------: | ---------: | ---: |
| App.wasm          | {human(baseline['wasm_bytes'])} | {human(current['wasm_bytes'])} | {pct(current['wasm_bytes'], baseline['wasm_bytes'])} |
| App.wasm (gzip)   | {human(baseline['wasm_gzip_bytes'])} | {human(current['wasm_gzip_bytes'])} | {pct(current['wasm_gzip_bytes'], baseline['wasm_gzip_bytes'])} |
| JS runtime          | {human(baseline['js_bytes'])} | {human(current['js_bytes'])} | {pct(current['js_bytes'], baseline['js_bytes'])} |
| JS runtime (gzip)   | {human(baseline['js_gzip_bytes'])} | {human(current['js_gzip_bytes'])} | {pct(current['js_gzip_bytes'], baseline['js_gzip_bytes'])} |
| **Total (gzip)**  | **{human(b_total)}** | **{human(c_total)}** | **{delta_pct:+.2f}%** |

{status}

<sub>Baseline: Swift {baseline['swift_version']}, WASM SDK {baseline['wasm_sdk_version']}, measured {baseline['measured_at']}.</sub>
"""

print(report)

github_output = os.environ.get("GITHUB_OUTPUT")
if github_output:
    with open(github_output, "a") as f:
        f.write("report<<EOF_REPORT\n")
        f.write(report)
        f.write("\nEOF_REPORT\n")

sys.exit(exit_code)
PYEOF
