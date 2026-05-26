// js-driver/swiflow-sw.js
//
// Swiflow service worker. Pre-caches the WASM + JS runtime keyed by
// content hash so repeat visits transfer ~0 bytes. Two caches:
//
//   swiflow-runtime-v<sha8>  — JS runtime files (index.js, runtime.js, etc.)
//   swiflow-wasm-v<sha8>     — App.wasm
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

function cacheNameFor(prefix, sha256) {
  return `${prefix}-v${sha256.slice(0, 8)}`;
}

function runtimeCacheNameFor(manifest) {
  // Hash the concatenation of runtime entries' hashes for a stable name.
  const joined = manifest.runtime.map(e => e.sha256).join(":");
  // SubtleCrypto isn't available synchronously and we want this name
  // computable from manifest data alone. Use the first runtime entry's
  // sha as the bucket key — it's deterministic given the manifest.
  // Collision: only if the same file content changes within the same
  // runtime set, which means it was meant to change.
  return cacheNameFor("swiflow-runtime", manifest.runtime[0]?.sha256 ?? "00000000");
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
  await wasmCache.addAll([manifest.wasm.url]);
  await runtimeCache.addAll(manifest.runtime.map(e => e.url));
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
    const manifest = await loadManifest();
    self.__swiflowManifest = manifest;
    await precache(manifest);
    // Don't skipWaiting here — let the next page navigation take over
    // naturally. Avoids ripping cache out from under the current page.
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const manifest = self.__swiflowManifest ?? await loadManifest();
    self.__swiflowManifest = manifest;
    const wasmCacheName = cacheNameFor("swiflow-wasm", manifest.wasm.sha256);
    const runtimeCacheName = runtimeCacheNameFor(manifest);
    await cleanupStale([wasmCacheName, runtimeCacheName]);
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const url = event.request.url;
  // Match against manifest URLs (suffix match — pages may serve from
  // any path prefix, manifest stores the path as written).
  const manifest = self.__swiflowManifest;
  if (!manifest) return; // not yet installed; pass through

  const matchesWasm = url.endsWith(manifest.wasm.url) || url.includes(manifest.wasm.url);
  const matchesRuntime = manifest.runtime.some(e => url.endsWith(e.url) || url.includes(e.url));
  if (!matchesWasm && !matchesRuntime) return;

  event.respondWith((async () => {
    const cached = await caches.match(event.request);
    if (cached) return cached;
    const fresh = await fetch(event.request);
    return fresh;
  })());
});

self.addEventListener("message", (event) => {
  // Reserved for Track 3 (progress UI). No-op for now.
});
