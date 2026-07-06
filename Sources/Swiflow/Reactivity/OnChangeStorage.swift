// Sources/Swiflow/Reactivity/OnChangeStorage.swift

@MainActor
enum OnChangeStorage {
    private static var table: [ObjectIdentifier: [String: Any]] = [:]

    static func get(for id: ObjectIdentifier, key: String) -> Any? {
        table[id]?[key]
    }

    static func set(for id: ObjectIdentifier, key: String, value: Any) {
        if table[id] == nil { table[id] = [:] }
        table[id]![key] = value
    }

    static func remove(for id: ObjectIdentifier) {
        table.removeValue(forKey: id)
    }
}

public extension Component {
    /// Fires `perform(newValue)` only when `value` has changed since the last
    /// call with the same key. The first call always seeds the stored value
    /// without firing. Call this from `onChange()`.
    ///
    /// The key defaults to the call site (`fileID:line`), composed from
    /// `fileID`/`line` rather than baked into `key`'s own default value —
    /// `#fileID`/`#line` only expand per call site when they're a bare
    /// literal default; wrapped in a string-interpolation default they'd
    /// resolve once, at this declaration. Two `onChange(of:)` calls in the
    /// same `onChange()` override therefore track independently with no
    /// explicit `key:`. A call site inside a loop still needs an explicit
    /// `key:` — `#line` is identical for every iteration, so looped calls
    /// would otherwise collide with each other.
    func onChange<T: Equatable>(
        of value: T,
        key: String? = nil,
        fileID: String = #fileID,
        line: Int = #line,
        perform: (T) -> Void
    ) {
        let resolvedKey = key ?? "\(fileID):\(line)"
        let id = ObjectIdentifier(self)
        let prev = OnChangeStorage.get(for: id, key: resolvedKey) as? T
        OnChangeStorage.set(for: id, key: resolvedKey, value: value)
        if let prev, prev != value { perform(value) }
    }
}
