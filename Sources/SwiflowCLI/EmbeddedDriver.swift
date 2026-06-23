// GENERATED FILE — do not edit.
//
// Regenerate by running, from the repo root:
//     swift scripts/embed-driver.swift
//
// Source: js-driver/swiflow-driver.js + js-driver/swiflow-service-worker.js + js-driver/swiflow-regions.js + js-driver/swiflow-region-guest.js

enum EmbeddedDriver {
    static let javascriptSource: String = #"""
// js-driver/swiflow-driver.js
//
// Swiflow JS driver — vanilla JavaScript, no build step.
//
// The driver owns the canonical Map<int, Node> that the Swift side references
// by integer handle. It exposes four operations to Swift through the
// `window.swiflow` global:
//
//   - applyPatches(patches): a JSArray of patch objects; the driver iterates
//                            and executes each in arrival order.
//   - mount(rootHandle, selector): attach a previously-created node into
//                                  the DOM under querySelector(selector).
//   - nodeForHandle(handle): return the DOM node for a Swift handle (used
//                            by Ref<Element>.wrappedValue), or null if
//                            unknown.
//   - registerDispatcher(fn): legacy hook reserved for future use.
//
// Per-listener wrappers call window.__swiflowDispatch(handlerId, event)
// when DOM events fire.

(function () {
  "use strict";

  /** Handle → DOM node. */
  const nodes = new Map();

  /** `${handle}:${event}` → bound listener function (for removal). */
  const listeners = new Map();

  /** Currently mounted CSS selector — set by `mount`, used by HMR. */
  let mountSelector = null;

  /** Selector → DOM Node currently attached as the swiflow root for that
   *  selector. We hold the Node ref directly (not the handle) so the
   *  `replaceMount` op can detach the previous root even if a preceding
   *  `destroyNode` already evicted it from the `nodes` map. */
  const mountedRoots = new Map();

  /** Path to the PackageToJS-emitted WASM, relative to the page. */
  const WASM_URL = "./.build/plugins/PackageToJS/outputs/Package/App.wasm";

  /**
   * Parse a raw HTML string into a single DOM node, mirroring the create-side
   * `createRawHTML` logic exactly so that `setRawHTML` produces a node of the
   * same shape (single child if the markup has one, `<span>` wrap otherwise).
   *
   * Centralised here so both `createRawHTML` and `setRawHTML` share the ONE
   * intentional HTML-property write site — `git grep "innerHTML" js-driver/`
   * enumerates every place unescaped HTML enters the DOM, and they all live
   * inside this helper plus the defensive rejection in `setProperty`.
   */
  function parseRawHTML(html) {
    const tpl = document.createElement("template");
    tpl.innerHTML = html;
    if (tpl.content.childNodes.length === 1) {
      return tpl.content.firstChild;
    }
    const wrap = document.createElement("span");
    while (tpl.content.firstChild) {
      wrap.appendChild(tpl.content.firstChild);
    }
    return wrap;
  }

  /**
   * Serialize a DOM event into the shape Swift expects.
   * EventInfo carries: type, optional targetValue (for value-bearing
   * inputs), optional targetChecked (for checkbox/radio inputs),
   * isSelfTarget (target === currentTarget — true when the event fired on the
   * bound element itself, not bubbled from a descendant), key (event.key on
   * keyboard events, else null), and the four modifier flags (present on
   * keyboard and mouse events). Called synchronously from the listener wrapper,
   * so `currentTarget` is the element the listener is attached to.
   */
  function serializeEvent(event) {
    const target = event.target;
    const targetValue =
      target && "value" in target ? String(target.value) : null;
    const targetChecked =
      target && "checked" in target ? Boolean(target.checked) : null;
    const key = typeof event.key === "string" ? event.key : null;
    return {
      type: event.type,
      targetValue: targetValue,
      targetChecked: targetChecked,
      isSelfTarget: target === event.currentTarget,
      key: key,
      shiftKey: Boolean(event.shiftKey),
      ctrlKey: Boolean(event.ctrlKey),
      altKey: Boolean(event.altKey),
      metaKey: Boolean(event.metaKey),
      // Custom events (e.g. a region's `sf:event`/`sf:error`) carry an object
      // `detail`; forward it as a JSON string so it can reach Swift through the
      // existing dispatch path. Ordinary DOM events whose `detail` is a number
      // (e.g. click count) are intentionally excluded.
      detail:
        event.detail !== null && typeof event.detail === "object"
          ? JSON.stringify(event.detail)
          : null,
    };
  }

  /**
   * Apply a single patch. The opcode is `p.op`; field names match the
   * Swift-side `PatchSerializer.encode(...)` contract.
   */
  function applyOne(p) {
    switch (p.op) {
      // Lifecycle
      case "createElement":
        nodes.set(p.handle, document.createElement(p.tag));
        return;
      case "createText":
        nodes.set(p.handle, document.createTextNode(p.text));
        return;
      case "createRawHTML": {
        // Raw HTML enters the DOM via parseRawHTML, gated on the Swift side
        // by VNode.rawHTML(...) — a loudly-named function so
        // `git grep "rawHTML("` enumerates every site where unescaped HTML
        // enters the DOM. XSS responsibility lies with the caller; the
        // framework guarantees no other path produces unescaped HTML.
        nodes.set(p.handle, parseRawHTML(p.html));
        return;
      }
      case "destroyNode": {
        // Symmetric with removeHandler: detach every tracked listener for
        // this handle from the DOM node AND drop the map entries.
        // Previously this case only deleted from the map, leaving the DOM
        // bindings until GC -- mostly harmless but inconsistent with
        // removeHandler and falsified the comment that claimed "Detach any
        // listeners". Also: parse the handle prefix numerically (was
        // startsWith-based, which would match handle 1 against keys for
        // 10/11/etc. once handles cross 10).
        const node = nodes.get(p.handle);
        for (const key of Array.from(listeners.keys())) {
          const sep = key.indexOf(":");
          if (sep < 0) continue;
          if (Number(key.slice(0, sep)) !== p.handle) continue;
          const event = key.slice(sep + 1);
          const fn = listeners.get(key);
          if (node !== undefined && fn !== undefined) {
            node.removeEventListener(event, fn);
          }
          listeners.delete(key);
        }
        nodes.delete(p.handle);
        return;
      }
      case "animateExit": {
        const node = nodes.get(p.handle);
        const parent = nodes.get(p.parentHandle);
        if (!node) return;
        node.style.animation = p.animation;
        setTimeout(function () {
          if (parent && node.parentNode === parent) {
            parent.removeChild(node);
          } else if (node.parentNode) {
            node.parentNode.removeChild(node);
          }
          nodes.delete(p.handle);
        }, p.durationMs);
        return;
      }

      // Tree structure
      case "appendChild":
        nodes.get(p.parent).appendChild(nodes.get(p.child));
        return;
      case "insertBefore":
        nodes.get(p.parent).insertBefore(
          nodes.get(p.child),
          nodes.get(p.beforeChild)
        );
        return;
      case "removeChild":
        nodes.get(p.parent).removeChild(nodes.get(p.child));
        return;

      // Mutations
      case "setAttribute":
        nodes.get(p.handle).setAttribute(p.name, p.value);
        return;
      case "removeAttribute":
        nodes.get(p.handle).removeAttribute(p.name);
        return;
      case "setProperty":
        // Defence in depth: the runtime reaches the HTML property only via
        // setRawHTML, which is the named-loud audit target. If a
        // setProperty patch ever names the HTML property — whether from a
        // differ regression or a user dropping it into
        // ElementData.properties — refuse and surface the misuse loudly
        // rather than silently injecting unescaped markup.
        if (p.name === "innerHTML") {
          throw new Error(
            "swiflow: setProperty refuses to write the innerHTML property; " +
              "use VNode.rawHTML(_:) instead"
          );
        }
        // value is already coerced to the right JS primitive by the Swift
        // adapter (string / number / boolean).
        nodes.get(p.handle)[p.name] = p.value;
        return;
      case "removeProperty":
        delete nodes.get(p.handle)[p.name];
        return;
      case "setStyle":
        nodes.get(p.handle).style[p.name] = p.value;
        return;
      case "removeStyle":
        // Use removeProperty (not `style[name] = ""`) so CSS custom properties
        // (`--foo`) and shorthands work correctly. Setting to "" leaves a
        // dangling JS property on the inline style object for `--foo`.
        nodes.get(p.handle).style.removeProperty(p.name);
        return;
      case "setText": {
        // Both Text nodes and Element nodes expose textContent; Text nodes
        // also expose .data. Prefer .data when defined.
        const node = nodes.get(p.handle);
        if (node.data !== undefined) {
          node.data = p.text;
        } else {
          node.textContent = p.text;
        }
        return;
      }
      case "setRawHTML": {
        // Re-parse and replace, mirroring the createRawHTML path through
        // parseRawHTML. Works regardless of whether the previous node was
        // an Element (HTML-property assignment would also have worked) or a
        // Text node (the markup parsed to plain text on first mount and
        // .innerHTML would have been a silent no-op). The ONLY runtime path
        // that writes the HTML property — `git grep "setRawHTML"`
        // enumerates every site.
        const next = parseRawHTML(p.html);
        const old = nodes.get(p.handle);
        if (old && old.parentNode) {
          old.parentNode.replaceChild(next, old);
        }
        nodes.set(p.handle, next);
        return;
      }

      // Events
      case "addHandler": {
        const handlerId = p.handlerId;
        const key = p.handle + ":" + p.event;
        // Self-correcting: if a previous handler was never explicitly removed
        // (would indicate a differ bug), detach it before binding the new
        // one. Otherwise both wrappers fire on the next event.
        const existing = listeners.get(key);
        if (existing !== undefined) {
          nodes.get(p.handle).removeEventListener(p.event, existing);
        }
        const fn = function (evt) {
          window.__swiflowDispatch(handlerId, serializeEvent(evt));
        };
        nodes.get(p.handle).addEventListener(p.event, fn);
        listeners.set(key, fn);
        return;
      }
      case "removeHandler": {
        const key = p.handle + ":" + p.event;
        const fn = listeners.get(key);
        if (fn !== undefined) {
          nodes.get(p.handle).removeEventListener(p.event, fn);
          listeners.delete(key);
        }
        return;
      }

      case "replaceMount": {
        // Root-swap counterpart to the initial `mount` op: emitted when the
        // root component's body produces a different element type between
        // frames (e.g. a router switching pages). The Swift side guarantees
        // `nodes[newHandle]` is populated by preceding createElement patches.
        //
        // We track the old root by Node ref (not handle) in `mountedRoots`,
        // so the detach works even if a preceding `destroyNode` already
        // evicted the old root's handle from the `nodes` map. That decoupling
        // is what lets the Renderer emit `replaceMount` at the END of the
        // patch list without having to reorder the diff's output.
        const target = document.querySelector(p.selector);
        if (target === null) {
          throw new Error(
            "swiflow-driver: replaceMount target '" + p.selector + "' not found"
          );
        }
        const oldNode = mountedRoots.get(p.selector);
        if (oldNode !== undefined && oldNode.parentNode === target) {
          target.removeChild(oldNode);
        }
        const newNode = nodes.get(p.newHandle);
        mountedRoots.set(p.selector, newNode);
        target.appendChild(newNode);
        return;
      }

      default:
        console.error("swiflow-driver: unknown opcode", p.op, p);
        return;
    }
  }

  /**
   * Pre-fetch `url` and stream the body, reporting download progress to
   * document.documentElement.dataset.swiflowProgress (a string "0".."100").
   *
   * Returns a Response over the accumulated bytes so the caller can hand
   * it to PackageToJS's init({ module }) without re-fetching.
   *
   * No intermediate writes happen when Content-Length is missing — only
   * the final "100" — because percent can't be computed without the total.
   *
   * @throws {Error} on non-ok HTTP status, or when the underlying fetch
   *                 or reader rejects (e.g., mid-stream network drop).
   *                 On reader failure the reader is cancelled before the
   *                 error propagates, so the underlying TCP connection
   *                 is released rather than held until GC.
   */
  async function fetchWithProgress(url) {
    const res = await fetch(url);
    if (!res.ok) {
      throw new Error("swiflow: fetch " + url + " failed (" + res.status + ")");
    }
    const total = parseInt(res.headers.get("Content-Length") || "", 10);
    const reader = res.body && res.body.getReader ? res.body.getReader() : null;
    if (!reader) {
      document.documentElement.dataset.swiflowProgress = "100";
      return res;
    }
    const chunks = [];
    let received = 0;
    const canReport = Number.isFinite(total) && total > 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(value);
        received += value.byteLength;
        if (canReport) {
          const pct = Math.floor((received / total) * 100);
          document.documentElement.dataset.swiflowProgress =
            String(Math.min(pct, 99));
        }
      }
    } catch (err) {
      try { await reader.cancel(); } catch (_) { /* already released */ }
      throw err;
    }
    document.documentElement.dataset.swiflowProgress = "100";
    const body = new Blob(chunks, {
      type: res.headers.get("Content-Type") || "application/wasm",
    });
    return new Response(body, { headers: res.headers, status: res.status });
  }

  window.swiflow = {
    /** Called by Swift each frame with a JSArray of patch objects.
     *  Each patch is applied in its own try/catch: one bad handle must not
     *  abort the rest of the frame (a half-applied batch is strictly worse
     *  than a batch with one skipped op). Failures are console.error'd in
     *  ALL builds — production included — and additionally routed to the
     *  dev overlay when the dev server installed it. */
    applyPatches: function (patches) {
      for (let i = 0; i < patches.length; i++) {
        try {
          applyOne(patches[i]);
        } catch (e) {
          console.error(
            "swiflow-driver: patch failed (op " +
              (patches[i] && patches[i].op) + ", index " + i + " of " +
              patches.length + ")", patches[i], e
          );
          if (typeof window.__swiflowDevError === "function") {
            window.__swiflowDevError(e);
          }
        }
      }
    },

    /** Called by Swift exactly once to attach the root node. */
    mount: function (rootHandle, selector) {
      const target = document.querySelector(selector);
      if (target === null) {
        throw new Error(
          "swiflow-driver: mount target '" + selector + "' not found"
        );
      }
      mountSelector = selector;
      mountedRoots.set(selector, nodes.get(rootHandle));
      target.appendChild(nodes.get(rootHandle));
    },

    /**
     * Resolve a Swiflow handle to the live DOM node.
     *
     * Powers `Ref<Element>.wrappedValue` — Swift calls this once per
     * dereference (no caching) so the framework always sees the current
     * node, even after a node swap (e.g. setRawHTML).
     *
     * Returns `null` for unknown handles (anchor handles, post-destroy
     * handles). Callers in Swift treat null as "ref not currently bound".
     */
    nodeForHandle: function (h) {
      const n = nodes.get(h);
      return n === undefined ? null : n;
    },

    /**
     * Legacy hook reserved for future use. The Swift side currently registers
     * its dispatcher directly as `window.__swiflowDispatch` (see Task 6); a
     * future binary-buffer wire format may re-introduce a registration step.
     */
    registerDispatcher: function (_fn) {},
  };

  // Dev-mode reload listener. Activates only when the dev server has
  // injected `window.SWIFLOW_DEV=true` before this driver runs.
  // Production builds leave the global undefined; this branch stays
  // inert and does NOT attempt the WebSocket (no DevTools console
  // noise from a failed `ws://localhost/reload` connection).
  if (window.SWIFLOW_DEV) {
    // 1. Extension guidance — printed once at page load so the developer
    //    knows how to get Swift source locations in stack traces.
    console.log(
      "[swiflow dev] For Swift source locations in stack traces,\n" +
      "install the Chrome C/C++ DevTools Extension:\n" +
      "  https://goo.gle/wasm-debugging-extension\n" +
      "Then reload DevTools — DWARF support activates automatically."
    );

    // 2. Dev error handler — called by the RAF shim when a WASM render
    //    error escapes. Emits a console.error (so the extension can translate
    //    WASM addresses to Swift file:line) and injects a full-viewport
    //    overlay so the freeze is visible without DevTools open.
    window.__swiflowDevError = function(e) {
      console.error(
        "[swiflow] render error — WASM execution stopped.\n" +
        "Reload the page to recover.\n\n" +
        (e && e.stack ? e.stack : String(e))
      );

      const existing = document.getElementById("__swiflow-error-overlay");
      if (existing) existing.remove();

      const overlay = document.createElement("div");
      overlay.id = "__swiflow-error-overlay";
      overlay.style.cssText =
        "position:fixed;inset:0;z-index:999999;background:rgba(0,0,0,0.85);" +
        "color:#fff;font-family:monospace;font-size:14px;padding:24px;" +
        "overflow:auto;white-space:pre-wrap;word-break:break-word;";

      const title = document.createElement("div");
      title.style.cssText =
        "font-size:18px;font-weight:bold;margin-bottom:16px;color:#ff6b6b;";
      title.textContent = "⚠ Swiflow render error — WASM execution stopped";

      const msg = document.createElement("pre");
      msg.style.cssText = "margin:0 0 16px;";
      msg.textContent = e && e.stack ? e.stack : String(e);

      const hint = document.createElement("div");
      hint.style.cssText = "color:#aaa;font-size:12px;margin-bottom:4px;";
      hint.textContent =
        "Install the Chrome C/C++ DevTools Extension to see Swift file:line in the stack above:";

      const link = document.createElement("a");
      link.href = "https://goo.gle/wasm-debugging-extension";
      link.target = "_blank";
      link.style.cssText =
        "color:#4dabf7;font-size:12px;display:block;margin-bottom:16px;";
      link.textContent = "https://goo.gle/wasm-debugging-extension";

      const dismiss = document.createElement("button");
      dismiss.style.cssText =
        "padding:8px 16px;background:#444;color:#fff;border:none;" +
        "cursor:pointer;font-size:14px;border-radius:4px;";
      dismiss.textContent = "Dismiss (app is frozen — reload to continue)";
      dismiss.onclick = function() { overlay.remove(); };

      overlay.appendChild(title);
      overlay.appendChild(msg);
      overlay.appendChild(hint);
      overlay.appendChild(link);
      overlay.appendChild(dismiss);
      const target = document.body || document.documentElement;
      target.appendChild(overlay);
    };

    // 3. RAF shim — wraps window.requestAnimationFrame so every callback
    //    (including SwiftWasm's render loop) runs inside a try/catch.
    //    Installed before connect() so the WASM module sees the patched
    //    version when it first calls scheduleRAFIfNeeded().
    //    bind(window) preserves the native this binding before patching.
    //    Guarded against environments without RAF (e.g. JSDOM in unit
    //    tests). Without the guard the script throws on load and the
    //    WebSocket reload connection below never opens.
    if (typeof window.requestAnimationFrame === "function") {
      var _raf = window.requestAnimationFrame.bind(window);
      window.requestAnimationFrame = function(cb) {
        return _raf(function(t) {
          try { cb(t); }
          catch(e) { window.__swiflowDevError(e); }
        });
      };
    }

    let reconnectDelay = 250;
    const maxDelay = 5000;

    // Reentrancy state for hmrSwap. See hmrSwap for the coalescing contract.
    let hmrInFlight = false;
    let hmrQueuedPayload = null;

    function connect() {
      const url = (location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/reload";
      const ws = new WebSocket(url);
      ws.onopen = function () {
        reconnectDelay = 250;
      };
      ws.onmessage = function (m) {
        let payload;
        try {
          payload = JSON.parse(m.data);
        } catch (e) {
          return;
        }
        if (!payload) return;
        if (payload.type === "reload") {
          location.reload();
          return;
        }
        if (payload.type === "hmr-swap") {
          hmrSwap(payload);
          return;
        }
      };
      ws.onclose = function () {
        // Reconnect with exponential backoff so killing+restarting
        // `swiflow dev` causes the page to silently reattach. No cap
        // on attempts — dev mode, no users.
        setTimeout(connect, reconnectDelay);
        reconnectDelay = Math.min(reconnectDelay * 2, maxDelay);
      };
      ws.onerror = function () {
        // The close handler does the retry; swallow the error to keep
        // DevTools console clean during dev-server restarts.
      };
    }

    async function hmrSwap(payload) {
      // Reentrancy guard: rapid saves can broadcast a second swap while the
      // first is still awaiting import/init. Running them concurrently
      // interleaves nodes.clear() with a module that is still mounting —
      // coalesce instead: remember the LATEST payload and run it after the
      // in-flight swap finishes (intermediate payloads are superseded).
      if (hmrInFlight) {
        hmrQueuedPayload = payload;
        return;
      }
      hmrInFlight = true;
      const t0 = performance.now();
      try {
        const snapshot =
          window.__swiflow && window.__swiflow.hmrSnapshot
            ? window.__swiflow.hmrSnapshot()
            : null;
        window.__swiflowPendingSnapshot = snapshot;

        // Drop maps + clear DOM mount target via replaceChildren()
        // (no HTML-property writes — matches the driver's XSS-safe
        // contract: setRawHTML is the only intentional HTML-writing
        // site).
        nodes.clear();
        listeners.clear();
        if (mountSelector) {
          const t = document.querySelector(mountSelector);
          if (t) t.replaceChildren();
        }

        // Remove Swiflow-injected <style> tags so the new module's
        // CSSInjector re-injects fresh CSS. Without this, the id-based
        // inject-once skip keeps serving the OLD styles after a
        // scopedStyles edit — the exact workflow HMR exists for. The
        // "swiflow-" id prefix covers component scoped sheets and
        // SwiflowUI's base token sheet; user styles are untouched.
        document.querySelectorAll('style[id^="swiflow-"]').forEach(function (s) {
          s.remove();
        });

        // Re-import the new entry, then RE-INSTANTIATE the wasm. A
        // PackageToJS index.js only *exports* init(); importing it does
        // NOT run @main, so without calling init() the cleared mount
        // target above stays empty — a blank page. This mirrors the
        // initial-boot path below (import → init({ module })). The new
        // module reads window.__swiflowPendingSnapshot on its first
        // render to restore @State. The cache-busting query on both URLs
        // is what makes the browser load fresh modules/bytes.
        //
        // The importer is overridable (window.swiflow.__importOverride)
        // so jsdom tests — which can't execute a real dynamic import() —
        // can supply a fake module. Production falls through to import().
        const importEntry =
          (window.swiflow && window.swiflow.__importOverride) ||
          ((u) => import(u));
        const { init } = await importEntry(payload.jsURL);
        await init({ module: fetchWithProgress(payload.wasmURL) });
        // NOTE: The previous WASM module's heap (old ambientRenderer,
        // old JSClosures) is not explicitly freed — the browser GC
        // reclaims it eventually. This is acceptable for a dev-only
        // code path. A page reload always clears everything cleanly.

        const dt = (performance.now() - t0).toFixed(1);
        console.log("[swiflow] hmr-swap took " + dt + "ms");
      } catch (e) {
        console.warn(
          "[swiflow] HMR swap failed, falling back to full reload:",
          e
        );
        location.reload();
        return; // reload is in flight; don't drain the queue
      } finally {
        hmrInFlight = false;
      }
      if (hmrQueuedPayload !== null) {
        const next = hmrQueuedPayload;
        hmrQueuedPayload = null;
        hmrSwap(next);
      }
    }

    connect();
  }

  // ---------------------------------------------------------------------------
  // Service worker registration + WASM entry ownership
  // ---------------------------------------------------------------------------

  // SW registration. Exposed on window.swiflow for testability; the
  // production caller is the IIFE just below.
  //
  // swiflowDev: boolean — pass true in dev builds (same flag as SWIFLOW_DEV).
  //
  //   false → register swiflow-service-worker.js (production / release builds).
  //   true  → unregister all SWs scoped to this page (aggressive but correct
  //            in dev — HMR must not fight a stale cache from a prior release
  //            build). Does NOT register a new SW.
  window.swiflow.__boot = async function __boot({ swiflowDev }) {
    if (!("serviceWorker" in navigator)) return;
    if (swiflowDev) {
      // Unregister any stale swiflow-service-worker.js SW so HMR isn't fighting a cache.
      // Only SWs whose scriptURL ends with "swiflow-service-worker.js" are touched;
      // any other SWs on the same origin (e.g. a PWA) are left intact.
      const regs = await navigator.serviceWorker.getRegistrations();
      for (const reg of regs) {
        const url = (reg.active || reg.installing || reg.waiting)?.scriptURL ?? "";
        // scriptURL is always absolute per spec, so "/swiflow-service-worker.js" alone
        // is correct. Don't fall back to the bare-suffix form: it would
        // false-positive on a third-party SW named e.g. "my-swiflow-service-worker.js".
        if (!url.endsWith("/swiflow-service-worker.js")) continue;
        try { await reg.unregister(); } catch (_) {}
      }
      // Unregistering removes the worker but NOT its caches — a prior `swiflow
      // build` leaves swiflow-* caches that even a lingering caches-first SW
      // would keep serving (stale WASM) on this very load. Deleting them here,
      // before the WASM import below (boot awaits __boot first), means the
      // dynamic import misses the cache and fetches the freshly-built bytes —
      // so dev wins on the FIRST load, not after a manual cache purge.
      if (typeof caches !== "undefined") {
        try {
          const names = await caches.keys();
          await Promise.all(
            names.filter(n => n.startsWith("swiflow-")).map(n => caches.delete(n))
          );
        } catch (_) {}
      }
      return;
    }
    try {
      await navigator.serviceWorker.register("swiflow-service-worker.js");
    } catch (e) {
      console.warn("swiflow: service worker registration failed", e);
    }
  };

  // Test seam — same logic, with explicit swiflowDev for jsdom tests.
  window.swiflow.__bootForTest = window.swiflow.__boot;

  // Test-only handle. Production paths reference fetchWithProgress directly.
  window.swiflow.__test_fetchWithProgress = fetchWithProgress;

  // Production boot: run on script-load, register SW, then dynamic-import
  // the PackageToJS entry. This used to be the user's HTML responsibility
  // (via <script type="module">). The driver now owns it so the user's
  // index.html only needs one <script> tag.
  //
  // Idempotency guard: if window.swiflow.__inited is already true when the
  // boot IIFE runs, skip the import. This handles the one-time migration
  // period where user HTML still has the old <script type="module"> block.
  (async () => {
    if (window.__SWIFLOW_SKIP_BOOT) return;
    await window.swiflow.__boot({ swiflowDev: !!window.SWIFLOW_DEV });
    if (window.swiflow.__inited) return;
    window.swiflow.__inited = true;
    try {
      // Dynamic-import the PackageToJS entry. The path is conventional and
      // matches what swiflow init's index.html template used to do inline.
      const { init } = await import(
        "./.build/plugins/PackageToJS/outputs/Package/index.js"
      );
      // fetchWithProgress is async — it cannot throw synchronously, so the
      // old try/catch "fallback" here was dead code. Rejections surface in
      // the outer catch below via `await init(...)`.
      await init({ module: fetchWithProgress(WASM_URL) });
    } catch (e) {
      // Surface init failures loudly: the dev-error overlay is only
      // populated by the WASM runtime, which never runs if the import
      // itself fails. Without this log, a 404 on index.js or an init()
      // throw leaves the page silently dead — error level so production
      // consoles surface it.
      console.error("swiflow: WASM init failed", e);
    }
  })();
})();

"""#

    static let serviceWorkerSource: String = #"""
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

async function loadManifest() {
  const res = await fetch(MANIFEST_URL, { cache: "no-store" });
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
    await precache(manifest);
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

"""#

    static let regionsSource: String = #"""
// js-driver/swiflow-regions.js
//
// Swiflow Regions browser runtime. Load via <script type="module">. Defines the
// <sf-region> custom element (main thread) and the worker-side guest host. All
// three building blocks are exported for unit testing; the element self-registers
// only in a window context (a later task wires the real worker).

const PROTOCOL = 1;

// Worker-side: translate the protocol to/from a guest ES module instance.
// `deps.post(msg)` sends an envelope; `deps.importGuest(source)` resolves the
// guest factory (real impl uses dynamic import()); `deps.raf`/`deps.caf`
// schedule/cancel a frame (defaulted below).
export function createGuestHost({ post, importGuest, raf, caf }) {
  // Drive frames with requestAnimationFrame when available, else fall back to a
  // ~60fps setTimeout: dedicated workers don't expose rAF in Safari/Firefox
  // (Chromium does), so without the fallback the guest renders once and never
  // ticks. A matching cancel is required — an uncancelled setTimeout loop would
  // double-fire across a pause/resume.
  const hasRAF = typeof requestAnimationFrame === "function";
  const now = () => (typeof performance !== "undefined" ? performance.now() : Date.now());
  const requestFrame = raf || (hasRAF ? (cb) => requestAnimationFrame(cb) : (cb) => setTimeout(() => cb(now()), 16));
  const cancelFrame = caf || (hasRAF ? (id) => cancelAnimationFrame(id) : (id) => clearTimeout(id));
  let guest = null;
  let loopId = null;
  let lastTs = 0;

  function emit(event) {
    post({ v: PROTOCOL, kind: "event", payload: JSON.stringify(event) });
  }

  function startLoop() {
    if (loopId !== null || !guest?.frame) return;
    lastTs = 0;
    const tick = (ts) => {
      if (!guest?.frame) { loopId = null; return; }
      const dt = lastTs ? ts - lastTs : 0;
      lastTs = ts;
      try { guest.frame(dt); } catch (e) { post({ v: PROTOCOL, kind: "error", payload: { code: "frame-failed", message: String(e) } }); }
      loopId = requestFrame(tick);
    };
    loopId = requestFrame(tick);
  }
  function stopLoop() { if (loopId !== null) cancelFrame(loopId); loopId = null; lastTs = 0; }

  async function handle(msg, canvas) {
    const { kind, payload } = msg;
    switch (kind) {
      case "init": {
        try {
          const factory = await importGuest(payload.source);
          const props = payload.props ? JSON.parse(payload.props) : null;
          guest = await factory(canvas, props, { emit, size: payload.size });
          post({ v: PROTOCOL, kind: "ready", payload: { protocol: PROTOCOL } });
          startLoop();
        } catch (e) {
          post({ v: PROTOCOL, kind: "error", payload: { code: "init-failed", message: String(e) } });
        }
        return;
      }
      case "props":  guest?.onProps?.(JSON.parse(payload)); return;
      case "resize": guest?.onResize?.(payload.w, payload.h, payload.dpr); return;
      case "pause":  stopLoop(); return;
      case "resume": startLoop(); return;
      case "destroy":
        stopLoop();
        try { guest?.destroy?.(); } catch { /* ignore */ }
        guest = null;
        return;
    }
  }

  return { handle };
}

// --- Main-thread: the <sf-region> custom element ---
//
// Seams (defaulted to real browser APIs by a later task, overridden in tests):
//   makeWorker()           -> a Worker-like { postMessage, terminate, onmessage }
//   makeCanvas()           -> a <canvas> (or fake) exposing transferControlToOffscreen()
//   schedule(cb)           -> coalesce work to a frame
//   observeSize(el, cb)    -> { disconnect() }; calls cb(w, h, dpr) on resize
//   observeVisible(el, cb) -> { disconnect() }; calls cb(isVisible)

export class SfRegion {
  static elementClass(win, seams) {
    return class SfRegionElement extends win.HTMLElement {
      get sfProps() { return this._propsValue ?? null; }
      set sfProps(v) {
        this._propsValue = v;
        if (!this._worker) return; // pre-connect: connectedCallback reads _propsValue
        this._propsLatest = v;
        if (this._propsDirty) return;
        this._propsDirty = true;
        this._seams.schedule(() => {
          this._propsDirty = false;
          if (this._worker) this._post({ v: 1, kind: "props", payload: this._propsLatest });
        });
      }

      connectedCallback() {
        if (this._worker) return; // idempotent / reconnection no-op
        this._seams = seams;
        this._propsLatest = this._propsValue ?? null;
        this._propsDirty = false;

        const canvas = seams.makeCanvas(this);
        if (canvas.style) { canvas.style.width = "100%"; canvas.style.height = "100%"; }
        if (canvas.nodeType) this.appendChild(canvas);
        const offscreen = canvas.transferControlToOffscreen();

        const size = this._measure();
        this._worker = seams.makeWorker(this);
        this._worker.onmessage = (e) => this._onWorkerMessage(e.data);
        // Absolutize the guest source against the page: the worker is a blob:
        // module, so it resolves import() specifiers against its own blob: base —
        // a relative/bare `data-source` would throw "Failed to resolve module
        // specifier". An absolute URL imports correctly (and `import.meta.url`
        // inside the guest then resolves its own assets, e.g. ./universe.wasm).
        const source = new URL(this.getAttribute("data-source"), this.ownerDocument.baseURI).href;
        this._post(
          { v: 1, kind: "init", canvas: offscreen, payload: { protocol: 1, source, props: this._propsLatest, size } },
          [offscreen]
        );

        this._sizeObs = seams.observeSize(this, (w, h, dpr) => this._post({ v: 1, kind: "resize", payload: { w, h, dpr } }));
        this._visObs = seams.observeVisible(this, (visible) => this._post({ v: 1, kind: visible ? "resume" : "pause", payload: null }));
      }

      disconnectedCallback() {
        if (!this._worker) return;
        this._post({ v: 1, kind: "destroy", payload: null });
        this._sizeObs?.disconnect();
        this._visObs?.disconnect();
        this._worker.terminate();
        if (this._worker._sfBlobUrl) URL.revokeObjectURL(this._worker._sfBlobUrl);
        this._worker = null;
      }

      _measure() {
        const dpr = this._seams.devicePixelRatio ?? (typeof devicePixelRatio === "number" ? devicePixelRatio : 1);
        const r = this.getBoundingClientRect ? this.getBoundingClientRect() : { width: 0, height: 0 };
        return { w: Math.max(1, Math.round(r.width * dpr)), h: Math.max(1, Math.round(r.height * dpr)), dpr };
      }

      _post(msg, transfer) { this._worker?.postMessage(msg, transfer || []); }

      _onWorkerMessage(msg) {
        switch (msg.kind) {
          case "ready": this.dispatchEvent(new win.CustomEvent("sf:ready")); return;
          case "event": this.dispatchEvent(new win.CustomEvent("sf:event", { detail: JSON.parse(msg.payload) })); return;
          // msg.payload is the {code,message} object; serializeEvent JSON-stringifies it,
          // DispatcherBridge reads it as a String, and SwiflowRegionDecoder JSON.parses + decodes RegionError.
          case "error": this.dispatchEvent(new win.CustomEvent("sf:error", { detail: msg.payload })); return;
        }
      }
    };
  }

  static install(win, seams) {
    if (win.customElements.get("sf-region")) return;
    // Custom elements default to display:inline, which ignores width/height — so a
    // `.frame(width:height:)` (set as inline px styles) wouldn't size the region and
    // it would stretch to the container's full width. Make it a block by default.
    const doc = win.document;
    if (doc && !doc.getElementById("sf-region-style")) {
      const style = doc.createElement("style");
      style.id = "sf-region-style";
      style.textContent = "sf-region{display:block}";
      (doc.head || doc.documentElement).appendChild(style);
    }
    win.customElements.define("sf-region", SfRegion.elementClass(win, seams));
  }
}

// Real browser seams. The worker re-imports THIS module and calls runWorker().
function defaultSeams(win) {
  return {
    makeWorker: () => {
      const src = `import { runWorker } from ${JSON.stringify(import.meta.url)}; runWorker();`;
      const url = URL.createObjectURL(new Blob([src], { type: "text/javascript" }));
      const w = new win.Worker(url, { type: "module" });
      w._sfBlobUrl = url; // revoked in disconnectedCallback (see SfRegion) — avoids a per-mount leak
      return w;
    },
    makeCanvas: () => win.document.createElement("canvas"),
    schedule: (cb) => win.requestAnimationFrame(cb),
    devicePixelRatio: undefined, // read live in _measure
    observeSize: (el, cb) => {
      const ro = new win.ResizeObserver((entries) => {
        const e = entries[0];
        const box = e.devicePixelContentBoxSize?.[0];
        if (box) { cb(box.inlineSize, box.blockSize, win.devicePixelRatio || 1); return; }
        const c = e.contentBoxSize?.[0] ?? { inlineSize: el.clientWidth, blockSize: el.clientHeight };
        const dpr = win.devicePixelRatio || 1;
        // NOTE (deferred to Phase C / older-Safari only): on this fallback path a DPR-only
        // change (zoom / monitor move) won't fire the ResizeObserver; a matchMedia('(resolution: …dppx)')
        // listener is needed to re-broadcast. Tracked in the design spec's deferred scope.
        cb(Math.max(1, Math.round(c.inlineSize * dpr)), Math.max(1, Math.round(c.blockSize * dpr)), dpr);
      });
      try { ro.observe(el, { box: "device-pixel-content-box" }); } catch { ro.observe(el); }
      return ro;
    },
    observeVisible: (el, cb) => {
      const io = new win.IntersectionObserver((es) => cb(es[0].isIntersecting && !win.document.hidden));
      io.observe(el);
      const onVis = () => cb(!win.document.hidden);
      win.document.addEventListener("visibilitychange", onVis);
      return { disconnect() { io.disconnect(); win.document.removeEventListener("visibilitychange", onVis); } };
    },
  };
}

// Worker entry: re-imported in the worker via the blob above. Wires the message
// loop to a createGuestHost; the init message carries the transferred
// OffscreenCanvas as `msg.canvas`.
export function runWorker() {
  let canvas = null;
  const host = createGuestHost({
    post: (m) => self.postMessage(m),
    importGuest: (source) => import(source).then((m) => m.default),
  });
  self.onmessage = (e) => {
    const msg = e.data;
    if (msg.kind === "init") {
      if (!msg.canvas) {
        self.postMessage({ v: 1, kind: "error", payload: { code: "no-canvas", message: "init missing OffscreenCanvas" } });
        return;
      }
      canvas = msg.canvas;
    }
    host.handle(msg, canvas);
  };
}

// Auto-register in a window context (no-op in the worker / in node).
if (typeof window !== "undefined" && window.customElements) {
  SfRegion.install(window, defaultSeams(window));
}

"""#

    static let guestSdkSource: String = #"""
// js-driver/swiflow-region-guest.js
//
// canvasGuest: a guest-SDK shim for Swiflow Regions. Turn a small config of hooks
// into a conforming guest factory — the shim owns the OffscreenCanvas 2D context,
// dpr-crisp sizing, resize→reflow detection, the fps EMA, and lifecycle, so the
// author writes only setup() + a per-frame draw. The raw
// (canvas, props, ctx) => guest contract stays available for advanced guests.
//
// Two layout modes, chosen by whether the config names a `cellSize`:
//
//   • RASTER mode (no `cellSize`) — the canvas buffer is the measured device
//     size; the layout context carries { width, height, dpr }; `resize` fires on
//     any device-dim change.
//   • GRID mode (`cellSize` set) — the shim derives whole cols/rows from the
//     measured size and snaps the buffer to whole cells; the layout context
//     carries { cols, rows, cell, dpr }; `resize` fires only when the cell count
//     changes.
//
// (A future typed build can model this as a discriminated GridConfig | RasterConfig.)
//
// Config hooks — `setup` and `frame` are required, the rest optional:
//   setup({ props }) → state   run once before the first paint; the returned
//                              object is the mutable state threaded into every hook
//   resize(state, layout)      layout changed — `layout` is the mode's context
//   frame(state, frameCtx)     per animation frame; frameCtx = layout +
//                              { ctx2d, dt, fps, emit } — `emit` lives here only
//   props(state, next)         the host pushed new props
//   destroy(state)             teardown

export function canvasGuest(config) {
  const { cellSize, setup, resize, frame, props, destroy } = config;
  const grid = cellSize != null;

  function guard(label, fn) {
    try { return fn(); } catch (e) { console.warn(`[region-guest] ${label} threw:`, e); }
  }

  return async function guestFactory(canvas, initialProps, host) {
    const ctx2d = canvas.getContext("2d");
    const emit = host.emit;
    const state = await setup({ props: initialProps });

    let cols = 0, rows = 0, cell = grid ? cellSize : 0;
    let width = 0, height = 0, dpr = 1, fps = 0;

    // Size the canvas buffer to a measured device size. Returns whether the
    // logical layout changed (grid cols/rows, or raster device dims).
    function applySize(devW, devH, devDpr) {
      dpr = devDpr || 1;
      let bw, bh, changed;
      if (grid) {
        const c = Math.max(8, Math.floor(devW / dpr / cellSize));
        const r = Math.max(8, Math.floor(devH / dpr / cellSize));
        cell = Math.max(1, Math.round(cellSize * dpr));
        changed = c !== cols || r !== rows;
        cols = c; rows = r; bw = c * cell; bh = r * cell;
      } else {
        changed = devW !== width || devH !== height;
        width = devW; height = devH; bw = devW; bh = devH;
      }
      if (canvas.width !== bw) canvas.width = bw;
      if (canvas.height !== bh) canvas.height = bh;
      return changed;
    }
    // The layout context handed to `resize`; `frame` builds the same shape plus
    // { ctx2d, dt, fps, emit }.
    function dims() {
      return grid ? { cols, rows, cell, dpr } : { width, height, dpr };
    }

    // Initial sizing runs inside the factory, so a throw here → host init-failed.
    const s0 = host.size || { w: 360, h: 360, dpr: 1 };
    applySize(s0.w, s0.h, s0.dpr);
    if (resize) resize(state, dims());

    return {
      onResize(w, h, d) {
        if (applySize(w, h, d) && resize) guard("resize", () => resize(state, dims()));
      },
      onProps(p) { if (props) guard("props", () => props(state, p)); },
      frame(dt) {
        if (dt > 0) fps = fps ? fps * 0.9 + (1000 / dt) * 0.1 : 1000 / dt;
        const base = { ctx2d, dt, fps, dpr, emit };
        frame(state, grid ? { ...base, cols, rows, cell } : { ...base, width, height });
      },
      destroy() { if (destroy) guard("destroy", () => destroy(state)); },
    };
  };
}

"""#
}
