// js-driver/swiflow-sw.js
//
// Swiflow service worker. Pre-caches the WASM + JS runtime keyed by
// content hash so repeat visits transfer ~0 bytes. Two caches:
//
//   swiflow-runtime-v<hash8>  — JS runtime files (index.js, runtime.js, etc.)
//   swiflow-wasm-v<sha8>      — App.wasm
//
// Split so a Swift-source edit (new App.wasm) doesn't invalidate the JS
// runtime cache, and vice versa.
//
// Manifest format (swiflow-manifest.json):
//   {
//     "version": "1",
//     "wasm":    { "url": "...", "sha256": "..." },
//     "runtime": [{ "url": "...", "sha256": "..." }, ...]
//   }

const MANIFEST_URL = new URL("swiflow-manifest.json", self.location.href).href;

// Build tag — the Swiflow CLI replaces the placeholder below on every
// `swiflow build` (DriverInstaller.stampServiceWorker), so this file's bytes
// change whenever the app changes. That is what makes the browser's
// byte-compare SW update check re-fire `install` (which precaches the new
// manifest) — without it, returning visitors would be pinned to the first
// deploy forever. Activation still follows the standard SW lifecycle: the
// new worker waits until all tabs using the old one close (we deliberately
// don't skipWaiting; see the install handler), then activates and
// immediately claims open clients (clients.claim — see the activate handler).
const BUILD_TAG = "4e3469cf2fd5-19397553fd06296e";

function cacheNameFor(prefix, sha256) {
  return `${prefix}-v${sha256.slice(0, 8)}`;
}

// FNV-1a 32-bit fold over a string. Synchronous, deterministic,
// good enough for 8-char cache-name tags.
function shortHash(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, "0");
}

function runtimeCacheNameFor(manifest) {
  // Fold ALL runtime entries' hashes so any file change rotates the name.
  const joined = manifest.runtime.map(e => e.sha256).join(":");
  return `swiflow-runtime-v${shortHash(joined)}`;
}

async function loadManifest() {
  const res = await fetch(MANIFEST_URL, { cache: "no-store" });
  if (!res.ok) throw new Error(`swiflow-sw: manifest fetch failed (${res.status})`);
  return res.json();
}

async function precache(manifest) {
  const wasmCacheName = cacheNameFor("swiflow-wasm", manifest.wasm.sha256);
  const runtimeCacheName = runtimeCacheNameFor(manifest);
  const wasmCache = await caches.open(wasmCacheName);
  const runtimeCache = await caches.open(runtimeCacheName);
  // Resolve to absolute URLs so caches.match() (exact-URL semantics in
  // real browsers) hits correctly when requests arrive with full origins.
  const wasmAbs = new URL(manifest.wasm.url, self.location.href).href;
  const runtimeAbs = manifest.runtime.map(e => new URL(e.url, self.location.href).href);
  await wasmCache.addAll([wasmAbs]);
  await runtimeCache.addAll(runtimeAbs);
  return { wasmCacheName, runtimeCacheName };
}

async function cleanupStale(currentNames) {
  const allNames = await caches.keys();
  await Promise.all(
    allNames
      .filter(n => n.startsWith("swiflow-") && !currentNames.includes(n))
      .map(n => caches.delete(n))
  );
}

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    self.__swiflowBuildTag = BUILD_TAG; // exposed for debugging/tests
    const manifest = await loadManifest();
    self.__swiflowManifest = manifest;
    await precache(manifest);
    // Don't skipWaiting here — let the next page navigation take over
    // naturally. Avoids ripping cache out from under the current page.
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    // Re-load the manifest if this SW process was evicted since install
    // (browsers can evict idle SWs between lifecycle phases).
    const manifest = self.__swiflowManifest ?? await loadManifest();
    self.__swiflowManifest = manifest;
    const wasmCacheName = cacheNameFor("swiflow-wasm", manifest.wasm.sha256);
    const runtimeCacheName = runtimeCacheNameFor(manifest);
    await cleanupStale([wasmCacheName, runtimeCacheName]);
    await self.clients.claim();
  })());
});

// Caches-first, network-fallback. Works because:
//   1. precache() stores absolute URLs, matching the full request URL exactly.
//   2. caches.match() searches all named caches — no manifest needed here.
//   3. Non-Swiflow URLs are not in any cache; they fall through to network.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  event.respondWith((async () => {
    const cached = await caches.match(event.request);
    return cached ?? fetch(event.request);
  })());
});

self.addEventListener("message", (event) => {
  // Reserved for Track 3 (progress UI). No-op for now.
});
