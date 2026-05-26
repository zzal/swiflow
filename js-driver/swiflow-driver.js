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
   * inputs), and optional targetChecked (for checkbox/radio inputs).
   */
  function serializeEvent(event) {
    const target = event.target;
    const targetValue =
      target && "value" in target ? String(target.value) : null;
    const targetChecked =
      target && "checked" in target ? Boolean(target.checked) : null;
    return {
      type: event.type,
      targetValue: targetValue,
      targetChecked: targetChecked,
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

      default:
        console.error("swiflow-driver: unknown opcode", p.op, p);
        return;
    }
  }

  window.swiflow = {
    /** Called by Swift each frame with a JSArray of patch objects. */
    applyPatches: function (patches) {
      for (let i = 0; i < patches.length; i++) {
        applyOne(patches[i]);
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

        // Re-import the new entry. Browsers cache ES-module imports
        // by URL, so the cache-busting query is what makes the new
        // module load fresh. Await it so failures fall through to
        // catch and trigger the reload fallback.
        await import(payload.jsURL);
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
  //   false → register swiflow-sw.js (production / release builds).
  //   true  → unregister all SWs scoped to this page (aggressive but correct
  //            in dev — HMR must not fight a stale cache from a prior release
  //            build). Does NOT register a new SW.
  window.swiflow.__boot = async function __boot({ swiflowDev }) {
    if (!("serviceWorker" in navigator)) return;
    if (swiflowDev) {
      // Unregister any stale swiflow-sw.js SW so HMR isn't fighting a cache.
      // Only SWs whose scriptURL ends with "swiflow-sw.js" are touched;
      // any other SWs on the same origin (e.g. a PWA) are left intact.
      const regs = await navigator.serviceWorker.getRegistrations();
      for (const reg of regs) {
        const url = (reg.active || reg.installing || reg.waiting)?.scriptURL ?? "";
        if (!url.endsWith("/swiflow-sw.js") && !url.endsWith("swiflow-sw.js")) continue;
        try { await reg.unregister(); } catch (_) {}
      }
      return;
    }
    try {
      await navigator.serviceWorker.register("swiflow-sw.js");
    } catch (e) {
      console.warn("swiflow: service worker registration failed", e);
    }
  };

  // Test seam — same logic, with explicit swiflowDev for jsdom tests.
  window.swiflow.__bootForTest = window.swiflow.__boot;

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
      await init();
    } catch (e) {
      // Surface init failures loudly: the dev-error overlay is only
      // populated by the WASM runtime, which never runs if the import
      // itself fails. Without this log, a 404 on index.js or an init()
      // throw leaves the page silently dead.
      console.warn("swiflow: WASM init failed", e);
    }
  })();
})();
