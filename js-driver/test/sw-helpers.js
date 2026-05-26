// js-driver/test/sw-helpers.js
//
// Mocked SW global scope for node:test. We instantiate the SW source
// inside a vm context with our mocks in scope — closer to behavior
// than mocking imports.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const swPath = join(here, "..", "swiflow-sw.js");

class MockCache {
  constructor() { this.store = new Map(); }
  async match(req) {
    const url = typeof req === "string" ? req : req.url;
    if (this.store.has(url)) return this.store.get(url);
    // Also match by suffix — the cache stores manifest-relative paths
    // (e.g. "/.build/.../App.wasm") but requests arrive with a full
    // origin (e.g. "https://x.test/.build/.../App.wasm").
    for (const [key, val] of this.store) {
      if (url.endsWith(key) || url.includes(key)) return val;
    }
    return undefined;
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
  clone() { return new MockResponse(this.body, { ok: this.ok, status: this.status }); }
}

export function loadServiceWorker({ manifest, fetchHandler } = {}) {
  const listeners = new Map();
  const caches = new MockCacheStorage();
  const fetchImpl = fetchHandler ?? (async (urlOrReq) => {
    const url = typeof urlOrReq === "string" ? urlOrReq : urlOrReq.url;
    if (url.endsWith("swiflow-manifest.json")) {
      return new MockResponse(JSON.stringify(manifest));
    }
    return new MockResponse(`net:${url}`);
  });

  const self = {
    addEventListener(name, fn) {
      if (!listeners.has(name)) listeners.set(name, []);
      listeners.get(name).push(fn);
    },
    skipWaiting: async () => {},
    clients: { claim: async () => {}, matchAll: async () => [] },
    location: { href: "https://x.test/swiflow-sw.js" },
  };

  const ctx = vm.createContext({
    self,
    caches,
    fetch: fetchImpl,
    Response: MockResponse,
    Request: class { constructor(url) { this.url = url; } },
    URL,
    console,
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

  return { fire, caches, listeners };
}

export const DEFAULT_MANIFEST = {
  version: "1",
  wasm: { url: "/.build/.../App.wasm", sha256: "a".repeat(64) },
  runtime: [
    { url: "/.build/.../index.js",       sha256: "b".repeat(64) },
    { url: "/.build/.../instantiate.js", sha256: "c".repeat(64) },
    { url: "/.build/.../runtime.js",     sha256: "d".repeat(64) },
    { url: "/.build/.../platforms/browser.js", sha256: "e".repeat(64) },
  ],
};
