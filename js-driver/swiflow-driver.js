// js-driver/swiflow-driver.js
//
// Swiflow JS driver — vanilla JavaScript, no build step.
//
// The driver owns the canonical Map<int, Node> that the Swift side references
// by integer handle. It exposes three operations to Swift through the
// `window.swiflow` global:
//
//   - applyPatches(patches): a JSArray of patch objects; the driver iterates
//                            and executes each in arrival order.
//   - mount(rootHandle, selector): attach a previously-created node into
//                                  the DOM under querySelector(selector).
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
   * Serialize a DOM event into the minimal shape Swift expects.
   * Phase 1's Event has type + optional targetValue; everything else is
   * deferred to Phase 3.
   */
  function serializeEvent(event) {
    const target = event.target;
    const targetValue =
      target && "value" in target ? String(target.value) : null;
    return { type: event.type, targetValue: targetValue };
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
      target.appendChild(nodes.get(rootHandle));
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
        if (payload && payload.type === "reload") {
          location.reload();
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
    connect();
  }
})();
