// js-driver/swiflow-service-worker.js
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
//
// The manifest is written ONLY by `swiflow build`. When it's absent (404)
// this worker runs in "no manifest" mode: install precaches nothing and
// activate deletes every swiflow-* cache. That's what keeps `swiflow dev`
// honest after a `swiflow build` in the same project — a leftover build
// cache would otherwise be served cache-first over every dev rebuild.

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
const BUILD_TAG = "__SWIFLOW_BUILD_TAG__";

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

// Resolves to the parsed manifest, or `null` when the site has no manifest
// at all (404/410) — a dev server or a host that was never `swiflow build`-t.
// That's a legitimate state, not a fault: the caller precaches nothing and
// activate drops any swiflow-* caches a previous *built* visit left behind.
// Transient failures (5xx, network) still throw: failing install keeps the
// previous worker and its verified caches serving, which is the right call
// for a temporarily broken deploy.
async function loadManifest() {
  const res = await fetch(MANIFEST_URL, { cache: "no-store" });
  if (res.status === 404 || res.status === 410) return null;
  if (!res.ok) throw new Error(`swiflow-sw: manifest fetch failed (${res.status})`);
  return res.json();
}

async function sha256HexOf(buf) {
  const digest = await crypto.subtle.digest("SHA-256", buf);
  let hex = "";
  for (const b of new Uint8Array(digest)) hex += b.toString(16).padStart(2, "0");
  return hex;
}

// Fetch `absUrl` and cache it ONLY if its bytes hash to the manifest's
// sha256. The cache is *named* by that sha, so caching unverified bytes
// poisons it permanently: cleanupStale() protects the current name, and the
// fetch handler then serves the wrong bytes forever. The classic desync is
// `swiflow dev` overwriting `swiflow build`'s App.wasm without rewriting
// swiflow-manifest.json. A mismatch must NOT fail install — a failed install
// would pin the page to the previous worker's (also stale) caches. Skipping
// the file instead lets this worker activate, cleanupStale() drops the old
// caches, and the URL falls through to the network: correct bytes, just
// uncached.
async function fetchVerifiedInto(cache, absUrl, expectedSha256) {
  const res = await fetch(absUrl, { cache: "no-store" });
  if (!res.ok) {
    console.error(`swiflow-sw: precache fetch failed for ${absUrl} (${res.status}); will serve from network.`);
    return;
  }
  const actual = await sha256HexOf(await res.clone().arrayBuffer());
  if (actual !== expectedSha256) {
    console.error(
      `swiflow-sw: sha256 mismatch for ${absUrl} — manifest says ${expectedSha256.slice(0, 8)}…, ` +
      `fetched bytes hash to ${actual.slice(0, 8)}…. Build outputs and swiflow-manifest.json are out ` +
      `of sync (did a \`swiflow dev\` build overwrite \`swiflow build\` outputs?). Re-run \`swiflow build\`. ` +
      `Not cached; this URL will be served from the network.`
    );
    return;
  }
  await cache.put(absUrl, res);
}

async function precache(manifest) {
  const wasmCacheName = cacheNameFor("swiflow-wasm", manifest.wasm.sha256);
  const runtimeCacheName = runtimeCacheNameFor(manifest);
  const wasmCache = await caches.open(wasmCacheName);
  const runtimeCache = await caches.open(runtimeCacheName);
  // Resolve to absolute URLs so caches.match() (exact-URL semantics in
  // real browsers) hits correctly when requests arrive with full origins.
  const wasmAbs = new URL(manifest.wasm.url, self.location.href).href;
  await fetchVerifiedInto(wasmCache, wasmAbs, manifest.wasm.sha256);
  for (const entry of manifest.runtime) {
    const abs = new URL(entry.url, self.location.href).href;
    await fetchVerifiedInto(runtimeCache, abs, entry.sha256);
  }
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
    if (manifest) await precache(manifest);
    // Activate this build immediately instead of waiting for every tab on the
    // old worker to close — so a rebuild wins on the next reload, not
    // "eventually". Safe because caches are content-hash-keyed: this worker
    // precached under new names, and activate's cleanupStale() only deletes
    // caches NOT in the current set, so claiming live clients never rips out
    // bytes a loaded page is still using.
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    // Re-load the manifest if this SW process was evicted since install
    // (browsers can evict idle SWs between lifecycle phases).
    const manifest = self.__swiflowManifest ?? await loadManifest();
    self.__swiflowManifest = manifest;
    // No manifest → no cache is legitimate: wipe every swiflow-* cache so a
    // leftover `swiflow build` cache can't shadow dev-server responses.
    const currentNames = manifest
      ? [cacheNameFor("swiflow-wasm", manifest.wasm.sha256), runtimeCacheNameFor(manifest)]
      : [];
    await cleanupStale(currentNames);
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
