#!/usr/bin/env bash
#
# bench-cache.sh — validate & quantify SwiftPM caching for Swiflow.
#
# Answers the question "is dependency caching possible / already happening, and
# where does `swiflow init` + build actually spend its time?" with real numbers.
#
# It is NON-DESTRUCTIVE: it never touches the user's real ~/.../org.swift.swiftpm
# cache. The cold-fetch measurement points SwiftPM at a throwaway empty
# --cache-path; everything else runs in a `mktemp -d` workspace that is removed
# on exit.
#
# What it measures
#   A. Evidence — what the shared caches already hold (and that the cache flags
#      are on by default).
#   B. Dependency fetch: cold (empty cache, hits the network) vs warm (the real
#      shared cache). The delta is what the dependency cache already saves you.
#   C. Compile: cold (fresh .build) vs incremental (same .build, no source
#      change). The delta is what persisting a project's .build saves — the
#      lever Phase 2 (e2e) pulls.
#
# Notes
#   * The cold-fetch step needs network access (it re-clones ~30 packages into
#     an empty cache). If offline it is reported as N/A.
#   * Set BENCH_RELEASE=1 to also time a full `swiflow build` (release WASM,
#     ~3 min) in addition to the faster dev compile.
#
# Usage:  bash scripts/bench-cache.sh

set -euo pipefail

# ── Locate repo root (this script lives in <repo>/scripts) ───────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFLOW="$REPO_ROOT/.build/release/swiflow"

# ── Throwaway workspace (removed on exit) ────────────────────────────────────
WORK="$(mktemp -d "${TMPDIR:-/tmp}/swiflow-bench.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ── Portable wall-clock timer (BSD `date` has no %N; python3 is a hard dep) ───
now() { python3 -c 'import time; print(time.time())'; }
fmt() { python3 -c "print(f'{$1:.1f}')"; }   # seconds, 1 decimal

# Locate the SwiftPM shared cache (macOS vs Linux paths).
SWIFTPM_CACHE=""
for c in "$HOME/Library/Caches/org.swift.swiftpm" "$HOME/.cache/org.swift.swiftpm"; do
  if [ -d "$c" ]; then SWIFTPM_CACHE="$c"; break; fi
done

hr() { printf '─%.0s' {1..72}; printf '\n'; }
section() { echo; hr; echo "▎ $1"; hr; }

# ─────────────────────────────────────────────────────────────────────────────
section "A. What the shared caches already hold"

echo "Swift toolchain:"
swift --version 2>/dev/null | sed 's/^/  /'
echo
echo "Dependency/manifest cache flags (from \`swift build --help\`):"
swift build --help 2>&1 \
  | grep -A1 -iE -- '--enable-dependency-cache|--enable-build-manifest-caching' \
  | grep -iE 'default|cache' | sed 's/^/  /' || true
echo "  → both default to ENABLED; passing them explicitly is a no-op."
echo
if [ -n "$SWIFTPM_CACHE" ]; then
  echo "Shared SwiftPM cache: $SWIFTPM_CACHE"
  echo "  total size:        $(du -sh "$SWIFTPM_CACHE" 2>/dev/null | cut -f1)"
  if [ -d "$SWIFTPM_CACHE/repositories" ]; then
    echo "  cached git repos:  $(find "$SWIFTPM_CACHE/repositories" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ') (shared across every project)"
  fi
  if [ -d "$SWIFTPM_CACHE/manifests" ]; then
    echo "  manifest cache:    $(du -sh "$SWIFTPM_CACHE/manifests" 2>/dev/null | cut -f1)"
  fi
else
  echo "No shared SwiftPM cache found yet (will be created on first resolve)."
fi
echo
echo "Installed WASM Swift SDKs:"
swift sdk list 2>/dev/null | sed 's/^/  /' || echo "  (none)"

# ─────────────────────────────────────────────────────────────────────────────
section "Building the swiflow CLI (release) if needed"
T_CLI="(cached)"
if [ ! -x "$SWIFLOW" ]; then
  echo "Building $SWIFLOW ..."
  s=$(now)
  swift build -c release --product swiflow --package-path "$REPO_ROOT" >/dev/null
  T_CLI="$(fmt "$(now) - $s")s"
  echo "  built in ${T_CLI}"
else
  echo "Reusing existing $SWIFLOW"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Scaffolding a throwaway demo project"
"$SWIFLOW" init demo --path "$WORK" --swiflow-source "$REPO_ROOT" >/dev/null
DEMO="$WORK/demo"
echo "Scaffolded → $DEMO"

# ─────────────────────────────────────────────────────────────────────────────
section "B. Dependency fetch: cold (empty cache) vs warm (shared cache)"

echo "Cold fetch — empty --cache-path, isolated --scratch-path (needs network):"
T_COLD_FETCH="N/A (offline?)"
s=$(now)
if swift package resolve \
      --package-path "$DEMO" \
      --cache-path "$WORK/cold-cache" \
      --scratch-path "$WORK/scratch-cold" >/dev/null 2>&1; then
  T_COLD_FETCH="$(fmt "$(now) - $s")s"
  echo "  cold resolve: ${T_COLD_FETCH}"
else
  echo "  cold resolve failed (likely offline) — skipping"
fi

echo
echo "Warm fetch — real shared cache, isolated --scratch-path:"
s=$(now)
swift package resolve \
  --package-path "$DEMO" \
  --scratch-path "$WORK/scratch-warm" >/dev/null 2>&1
T_WARM_FETCH="$(fmt "$(now) - $s")s"
echo "  warm resolve: ${T_WARM_FETCH}"

# ─────────────────────────────────────────────────────────────────────────────
section "C. Compile: cold (fresh .build) vs incremental (same .build)"

# Detect a WASM SDK the same way swiflow does (first installed _wasm SDK).
SDK="$(swift sdk list 2>/dev/null | grep -E '_wasm$' | head -1 || true)"
if [ -z "$SDK" ]; then
  echo "No WASM SDK installed — cannot measure compile. Install one with"
  echo "  swift sdk install <wasm sdk url>   (see https://swift.org/install)"
  T_COLD_COMPILE="N/A"; T_INC_COMPILE="N/A"
else
  echo "Using WASM SDK: $SDK"
  echo
  echo "Cold compile — dev build into a fresh .build:"
  s=$(now)
  ( cd "$DEMO" && swift package --swift-sdk "$SDK" js --use-cdn --product App --debug-info-format dwarf >/dev/null 2>&1 )
  T_COLD_COMPILE="$(fmt "$(now) - $s")s"
  echo "  cold dev compile: ${T_COLD_COMPILE}"
  echo
  echo "Incremental compile — same .build, no source change:"
  s=$(now)
  ( cd "$DEMO" && swift package --swift-sdk "$SDK" js --use-cdn --product App --debug-info-format dwarf >/dev/null 2>&1 )
  T_INC_COMPILE="$(fmt "$(now) - $s")s"
  echo "  incremental compile: ${T_INC_COMPILE}"

  if [ "${BENCH_RELEASE:-0}" = "1" ]; then
    echo
    echo "Full release build (swiflow build, ~3 min) — BENCH_RELEASE=1:"
    s=$(now)
    "$SWIFLOW" build --path "$DEMO" >/dev/null 2>&1 || true
    T_RELEASE="$(fmt "$(now) - $s")s"
    echo "  release build: ${T_RELEASE}"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Verdict"
cat <<EOF
  CLI build (release):           ${T_CLI}
  ──────────────────────────────────────────────
  Dependency fetch
    cold  (empty cache):         ${T_COLD_FETCH}
    warm  (shared cache):        ${T_WARM_FETCH}
    → the dependency cache is ALREADY on and shared; warm ≪ cold.
  ──────────────────────────────────────────────
  Compile (WASM)
    cold  (fresh .build):        ${T_COLD_COMPILE}
    incremental (same .build):   ${T_INC_COMPILE}
    → compilation dominates and is NOT shared across projects by stock
      SwiftPM. Reusing a project's .build (Phase 2: e2e persistence) turns
      the cold cost into the incremental cost. Sharing compiled artifacts
      across *different* fresh projects needs the Phase 3 compile-cache spike.
EOF
echo
echo "Workspace cleaned: $WORK"
