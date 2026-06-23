#!/bin/sh
# install.sh — download and install the prebuilt `swiflow` CLI.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/zzal/swiflow/main/install.sh | sh
#
# Environment overrides:
#   SWIFLOW_VERSION       version to install, e.g. 0.3.1 (default: latest release)
#   SWIFLOW_INSTALL_DIR   install directory       (default: /usr/local/bin)
#
# The binary is NOT standalone: `swiflow build` / `swiflow dev` shell out to your
# Swift 6.3 toolchain and the WebAssembly SDK. Run the one-time `swift sdk install`
# from the README "Quick start" before building an app.
#
# Prebuilt binaries exist for macOS arm64 and Linux x86_64. Any other host
# (Intel Mac, Linux arm64) builds from source — see the error message below.

set -eu

REPO="zzal/swiflow"
INSTALL_DIR="${SWIFLOW_INSTALL_DIR:-/usr/local/bin}"

err()  { printf 'error: %s\n' "$1" >&2; exit 1; }
info() { printf '%s\n'        "$1" >&2; }

command -v uname >/dev/null 2>&1 || err "required command not found: uname"
command -v tar   >/dev/null 2>&1 || err "required command not found: tar"

# Downloader: prefer curl, fall back to wget. dl → stdout, dlo → file.
if command -v curl >/dev/null 2>&1; then
  dl()  { curl -fsSL "$1"; }
  dlo() { curl -fsSL -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  dl()  { wget -qO- "$1"; }
  dlo() { wget -qO "$2" "$1"; }
else
  err "need curl or wget to download"
fi

# --- Detect platform → asset suffix --------------------------------------
os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Darwin) os_name=macos ;;
  Linux)  os_name=linux ;;
  *) err "unsupported OS: $os (build from source — see README)" ;;
esac

case "$arch" in
  arm64|aarch64) arch_name=arm64 ;;
  x86_64|amd64)  arch_name=x86_64 ;;
  *) err "unsupported architecture: $arch" ;;
esac

asset_arch="${os_name}-${arch_name}"

# Only two prebuilt combos are published; anything else builds from source.
case "$asset_arch" in
  macos-arm64|linux-x86_64) ;;
  *) err "no prebuilt binary for ${asset_arch}. Build from source instead:
  swift build -c release --product swiflow" ;;
esac

# --- Resolve version ------------------------------------------------------
version="${SWIFLOW_VERSION:-}"
if [ -z "$version" ]; then
  info "Resolving latest release…"
  tag="$(dl "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -m1 '"tag_name"' \
    | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  [ -n "$tag" ] || err "could not resolve the latest release tag"
else
  case "$version" in
    v*) tag="$version" ;;
    *)  tag="v${version}" ;;
  esac
fi
version="${tag#v}"

asset="swiflow-${version}-${asset_arch}"
base="https://github.com/${REPO}/releases/download/${tag}"

# --- Download, verify, extract -------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

info "Downloading ${asset}.tar.gz …"
dlo "${base}/${asset}.tar.gz" "${tmp}/${asset}.tar.gz" \
  || err "download failed — does ${tag} ship a ${asset_arch} binary?
  See https://github.com/${REPO}/releases/tag/${tag}"

# Checksum sidecar is required for the platforms we publish; verify it.
if dlo "${base}/${asset}.tar.gz.sha256" "${tmp}/${asset}.tar.gz.sha256" 2>/dev/null; then
  info "Verifying checksum…"
  expected="$(awk '{print $1}' "${tmp}/${asset}.tar.gz.sha256")"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${tmp}/${asset}.tar.gz" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "${tmp}/${asset}.tar.gz" | awk '{print $1}')"
  else
    err "need sha256sum or shasum to verify the download"
  fi
  [ "$expected" = "$actual" ] || err "checksum mismatch
  expected: $expected
  actual:   $actual"
else
  info "warning: no checksum sidecar for ${tag}; skipping verification"
fi

info "Extracting…"
tar -C "$tmp" -xzf "${tmp}/${asset}.tar.gz"
bin="${tmp}/${asset}/swiflow"
[ -f "$bin" ] || err "archive did not contain a swiflow binary"
chmod +x "$bin"

# --- Install --------------------------------------------------------------
dest="${INSTALL_DIR}/swiflow"
mkdir -p "$INSTALL_DIR" 2>/dev/null || true
if [ -w "$INSTALL_DIR" ]; then
  mv "$bin" "$dest"
else
  info "Installing to ${INSTALL_DIR} needs elevated permissions…"
  command -v sudo >/dev/null 2>&1 || err "cannot write ${INSTALL_DIR} and sudo is unavailable; set SWIFLOW_INSTALL_DIR to a writable path"
  sudo mkdir -p "$INSTALL_DIR"
  sudo mv "$bin" "$dest"
fi

info "Installed swiflow ${version} → ${dest}"

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) info "note: ${INSTALL_DIR} is not on your PATH — add it to run 'swiflow' directly." ;;
esac
