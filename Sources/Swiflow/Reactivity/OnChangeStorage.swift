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
    /// call with the same `key`. The first call always seeds the stored value
    /// without firing. Call this from `onChange()`. Supply an explicit `key:`
    /// string when making multiple `onChange(of:)` calls in the same
    /// `onChange()` override — the default `#function` is identical for every
    /// call site in the same method.
    func onChange<T: Equatable>(
        of value: T,
        key: String = #function,
        perform: (T) -> Void
    ) {
        let id = ObjectIdentifier(self)
        let prev = OnChangeStorage.get(for: id, key: key) as? T
        OnChangeStorage.set(for: id, key: key, value: value)
        if let prev, prev != value { perform(value) }
    }
}
