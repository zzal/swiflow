// js-driver/test/sw-helpers.js
//
// Mocked SW global scope for node:test. We instantiate the SW source
// inside a vm context with our mocks in scope — closer to behavior
// than mocking imports.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createHash } from "node:crypto";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const swPath = join(here, "..", "swiflow-sw.js");

class MockCache {
  constructor() { this.store = new Map(); }
  async match(req) {
    // Exact-URL match only — mirrors real browser Cache API semantics.
    const url = typeof req === "string" ? req : req.url;
    return this.store.get(url);
  }
  async put(req, res) { this.store.set(typeof req === "string" ? req : req.url, res); }
  async addAll(urls) {
    for (const u of urls) this.store.set(u, new MockResponse(`cached:${u}`));
  }
  async keys() { return [...this.store.keys()].map(u => ({ url: u })); }
}

class MockCacheStorage {
  constructor() { this.caches = new Map(); }
  async open(name) {
    if (!this.caches.has(name)) this.caches.set(name, new MockCache());
    return this.caches.get(name);
  }
  async keys() { return [...this.caches.keys()]; }
  async delete(name) { return this.caches.delete(name); }
  async match(req) {
    for (const c of this.caches.values()) {
      const hit = await c.match(req);
      if (hit) return hit;
    }
    return undefined;
  }
}

class MockResponse {
  constructor(body, init = {}) { this.body = body; this.ok = init.ok ?? true; this.status = init.status ?? 200; }
  async json() { return typeof this.body === "string" ? JSON.parse(this.body) : this.body; }
  async arrayBuffer() {
    // Verification path: the SW hashes a clone's bytes before caching.
    return new TextEncoder().encode(String(this.body)).buffer;
  }
  clone() { return new MockResponse(this.body, { ok: this.ok, status: this.status }); }
}

/// sha256 hex of a string — what `crypto.subtle.digest` inside the SW will
/// compute for a MockResponse carrying that string body.
export function sha256Hex(str) {
  return createHash("sha256").update(str).digest("hex");
}

// The SW resolves manifest-relative URLs against its own location.
export const SW_ORIGIN = "https://x.test";

/// The default mock network body for `url` (absolute). DEFAULT_MANIFEST's
/// hashes are computed from these, so default-handler installs verify clean.
export function defaultBodyFor(absUrl) {
  return `net:${absUrl}`;
}

export function loadServiceWorker({ manifest, fetchHandler } = {}) {
  const listeners = new Map();
  const caches = new MockCacheStorage();
  const fetchLog = []; // every non-manifest URL fetched, in order
  const fetchImpl = fetchHandler ?? (async (urlOrReq) => {
    const url = typeof urlOrReq === "string" ? urlOrReq : urlOrReq.url;
    if (url.endsWith("swiflow-manifest.json")) {
      return new MockResponse(JSON.stringify(manifest));
    }
    fetchLog.push(url);
    return new MockResponse(defaultBodyFor(url));
  });

  const self = {
    addEventListener(name, fn) {
      if (!listeners.has(name)) listeners.set(name, []);
      listeners.get(name).push(fn);
    },
    skipWaiting: async () => {},
    clients: { claim: async () => {}, matchAll: async () => [] },
    location: { href: `${SW_ORIGIN}/swiflow-sw.js` },
  };

  const ctx = vm.createContext({
    self,
    caches,
    fetch: fetchImpl,
    Response: MockResponse,
    Request: class { constructor(url) { this.url = url; } },
    URL,
    console,
    // Node's WebCrypto — the SW's hash verification uses crypto.subtle.
    crypto: globalThis.crypto,
  });

  const src = readFileSync(swPath, "utf8");
  vm.runInContext(src, ctx, { filename: "swiflow-sw.js" });

  async function fire(name, ev) {
    const fns = listeners.get(name) ?? [];
    const collected = [];
    const wrapped = { ...ev, waitUntil: (p) => collected.push(p), respondWith: (p) => { ev.responded = p; } };
    for (const fn of fns) fn(wrapped);
    await Promise.all(collected);
    return ev;
  }

  return { fire, caches, listeners, fetchLog, self };
}

// Hashes match what the default fetch handler returns for each (absolutized)
// URL, so an unmodified install passes content verification.
const WASM_URL = "/.build/.../App.wasm";
const RUNTIME_URLS = [
  "/.build/.../index.js",
  "/.build/.../instantiate.js",
  "/.build/.../runtime.js",
  "/.build/.../platforms/browser.js",
];

export const DEFAULT_MANIFEST = {
  version: "1",
  wasm: { url: WASM_URL, sha256: sha256Hex(defaultBodyFor(`${SW_ORIGIN}${WASM_URL}`)) },
  runtime: RUNTIME_URLS.map(url => ({
    url,
    sha256: sha256Hex(defaultBodyFor(`${SW_ORIGIN}${url}`)),
  })),
};
