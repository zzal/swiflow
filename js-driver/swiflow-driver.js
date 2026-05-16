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
        // Use a template element so the raw HTML is parsed as document
        // content. The first child of the template becomes the node;
        // wrap-around to a `<span>` if the markup produced multiple nodes
        // or none, so the handle always maps to exactly one node.
        //
        // This is the ONE intentional innerHTML assignment in the driver,
        // gated on the Swift side by VNode.rawHTML(...) — a loudly-named
        // function so `git grep "rawHTML("` enumerates every site where
        // unescaped HTML enters the DOM. XSS responsibility lies with the
        // caller; the framework guarantees no other path produces unescaped
        // HTML.
        const tpl = document.createElement("template");
        tpl.innerHTML = p.html;
        let node;
        if (tpl.content.childNodes.length === 1) {
          node = tpl.content.firstChild;
        } else {
          node = document.createElement("span");
          while (tpl.content.firstChild) {
            node.appendChild(tpl.content.firstChild);
          }
        }
        nodes.set(p.handle, node);
        return;
      }
      case "destroyNode": {
        // Detach any listeners we tracked for this handle so JS GC can free
        // the wrapper functions.
        for (const key of Array.from(listeners.keys())) {
          if (key.startsWith(p.handle + ":")) {
            listeners.delete(key);
          }
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
        nodes.get(p.handle).style[p.name] = "";
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

      // Events
      case "addHandler": {
        const handlerId = p.handlerId;
        const fn = function (evt) {
          window.__swiflowDispatch(handlerId, serializeEvent(evt));
        };
        nodes.get(p.handle).addEventListener(p.event, fn);
        listeners.set(p.handle + ":" + p.event, fn);
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
})();
