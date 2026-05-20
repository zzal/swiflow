// Sources/SwiflowWeb/DevAPI.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

enum DevAPI {

    // MARK: - Closure retention

    nonisolated(unsafe) private static var treeClosure: JSClosure?
    nonisolated(unsafe) private static var stateClosure: JSClosure?
    nonisolated(unsafe) private static var handlersClosure: JSClosure?
    nonisolated(unsafe) private static var perfClosure: JSClosure?

    // MARK: - Install

    @MainActor
    static func install(renderer: Renderer) {
        guard JSObject.global.SWIFLOW_DEV.boolean == true else { return }

        let existing = JSObject.global.__swiflow
        let ns: JSObject
        if let obj = existing.object {
            ns = obj
        } else {
            ns = JSObject.global.Object.function!.new()
            JSObject.global.__swiflow = .object(ns)
        }

        // tree() — indented component tree as a string
        let tree = JSClosure { [weak renderer] _ -> JSValue in
            guard let mountTree = renderer?.mountTree else {
                return .string("(no tree — renderer not mounted)")
            }
            return .string(DevAPIFormatter.treeString(from: mountTree))
        }
        ns.tree = .object(tree)
        treeClosure = tree

        // state(path) — @State values for the component at path
        let state = JSClosure { [weak renderer] args -> JSValue in
            guard let mountTree = renderer?.mountTree,
                  let path = args.first?.string else {
                return .null
            }
            guard let vals = DevAPIFormatter.stateValues(from: mountTree, path: path) else {
                return .null
            }
            return encodeStateForDisplay(vals)
        }
        ns.state = .object(state)
        stateClosure = state

        // handlers() — total + per-scope counts
        let handlers = JSClosure { [weak renderer] _ -> JSValue in
            guard let renderer else { return .null }
            let byScope = renderer.handlers.countPerScope()
            let total = byScope.values.reduce(0, +)
            let obj = JSObject.global.Object.function!.new()
            obj.total = .number(Double(total))
            let scopeObj = JSObject.global.Object.function!.new()
            for (path, count) in byScope {
                scopeObj[path] = .number(Double(count))
            }
            obj.byScope = .object(scopeObj)
            return .object(obj)
        }
        ns.handlers = .object(handlers)
        handlersClosure = handlers

        // perf() — render count, last patch count, last render ms
        let perf = JSClosure { [weak renderer] _ -> JSValue in
            guard let renderer else { return .null }
            let obj = JSObject.global.Object.function!.new()
            obj.renders = .number(Double(renderer.renderCount))
            obj.lastPatchCount = .number(Double(renderer.lastPatchCount))
            obj.lastRenderMs = .number(renderer.lastRenderMs)
            return .object(obj)
        }
        ns.perf = .object(perf)
        perfClosure = perf
    }

    // MARK: - State encoding

    private static func encodeStateForDisplay(_ state: [String: Any]) -> JSValue {
        let obj = JSObject.global.Object.function!.new()
        for (k, v) in state {
            // Bool MUST be checked before Int (Swift bridges Bool to NSNumber).
            if let b = v as? Bool {
                obj[k] = .boolean(b)
            } else if let s = v as? String {
                obj[k] = .string(s)
            } else if let i = v as? Int {
                obj[k] = .number(Double(i))
            } else if let d = v as? Double {
                obj[k] = .number(d)
            } else {
                let mirror = Mirror(reflecting: v)
                if mirror.displayStyle == .optional {
                    if mirror.children.isEmpty {
                        obj[k] = .null
                    } else {
                        let payload = mirror.children.first!.value
                        if let b = payload as? Bool { obj[k] = .boolean(b) }
                        else if let s = payload as? String { obj[k] = .string(s) }
                        else if let i = payload as? Int { obj[k] = .number(Double(i)) }
                        else if let d = payload as? Double { obj[k] = .number(d) }
                    }
                }
            }
        }
        return .object(obj)
    }
}

#endif
