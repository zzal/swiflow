// Sources/SwiflowDOM/DevAPI.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

enum DevAPI {

#if !SWIFLOW_RELEASE
    // MARK: - Closure retention

    @MainActor private static var treeClosure: JSClosure?
    @MainActor private static var stateClosure: JSClosure?
    @MainActor private static var handlersClosure: JSClosure?
    @MainActor private static var perfClosure: JSClosure?

    // MARK: - Install

    /// Installs (or re-installs) `window.__swiflow` commands pointing at all
    /// currently mounted roots. Called after every `render(into:)` and
    /// `unmount(into:)` so the API always reflects the live root set.
    ///
    /// All four commands return JS objects keyed by selector when multiple
    /// roots are mounted, and return the same structure for a single root so
    /// existing usage is unchanged.
    @MainActor
    static func installAll() {
        guard JSObject.global.SWIFLOW_DEV.boolean == true else { return }

        let existing = JSObject.global.__swiflow
        let ns: JSObject
        if let obj = existing.object {
            ns = obj
        } else {
            ns = JSObject.global.Object.function!.new()
            JSObject.global.__swiflow = .object(ns)
        }

        // tree() — component tree per selector
        let tree = JSClosure { _ -> JSValue in
            let obj = JSObject.global.Object.function!.new()
            for (selector, renderer) in renderers {
                guard let mountTree = renderer.mountTree else { continue }
                obj[selector] = .string(DevAPIFormatter.treeString(from: mountTree))
            }
            return .object(obj)
        }
        ns.tree = .object(tree)
        treeClosure = tree

        // state(path) — @State values; searches all roots, first match wins
        let state = JSClosure { args -> JSValue in
            guard let path = args.first?.string else { return .null }
            for renderer in renderers.values {
                guard let mountTree = renderer.mountTree else { continue }
                if let vals = DevAPIFormatter.stateValues(from: mountTree, path: path) {
                    return encodeStateMapToJS(vals)
                }
            }
            return .null
        }
        ns.state = .object(state)
        stateClosure = state

        // handlers() — per-selector handler counts
        let handlers = JSClosure { _ -> JSValue in
            let obj = JSObject.global.Object.function!.new()
            for (selector, renderer) in renderers {
                let byScope = renderer.handlers.countPerScope()
                let total = byScope.values.reduce(0, +)
                let entry = JSObject.global.Object.function!.new()
                entry.total = .number(Double(total))
                let scopeObj = JSObject.global.Object.function!.new()
                for (path, count) in byScope {
                    scopeObj[path] = .number(Double(count))
                }
                entry.byScope = .object(scopeObj)
                obj[selector] = .object(entry)
            }
            return .object(obj)
        }
        ns.handlers = .object(handlers)
        handlersClosure = handlers

        // perf() — render stats per selector
        let perf = JSClosure { _ -> JSValue in
            let obj = JSObject.global.Object.function!.new()
            for (selector, renderer) in renderers {
                let entry = JSObject.global.Object.function!.new()
                entry.renders = .number(Double(renderer.renderCount))
                entry.lastPatchCount = .number(Double(renderer.lastPatchCount))
                entry.lastRenderMs = .number(renderer.lastRenderMs)
                obj[selector] = .object(entry)
            }
            return .object(obj)
        }
        ns.perf = .object(perf)
        perfClosure = perf
    }

#else
    /// Release builds strip the dev inspection API entirely; this stub keeps
    /// the `DevAPI.installAll()` call sites compiling. The linker dead-strips
    /// the call and the (now-unreferenced) core DevAPIFormatter.
    @MainActor static func installAll() {}
#endif
}

#endif
