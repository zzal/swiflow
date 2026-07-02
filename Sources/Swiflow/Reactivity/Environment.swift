// Sources/Swiflow/Reactivity/Environment.swift

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct EnvironmentValues {
    private struct StoredValue {
        let any: Any
        let equals: (Any) -> Bool
    }

    private var storage: [ObjectIdentifier: StoredValue] = [:]

    public init() {}

    /// Preferred overload when `K.Value` conforms to `Equatable`. Captures a
    /// value-aware equality closure at write time, so two `EnvironmentValues`
    /// holding the same key→value pair compare equal in `==`.
    ///
    /// Call sites that go through computed properties (e.g. `env.locale = "fr"`
    /// → `self[LocaleKey.self] = newValue`) always reach this overload, because
    /// the property layer holds the concrete `K.Value: Equatable` constraint.
    /// Direct subscript calls (`env[SomeKey.self] = ...`) need the same constraint
    /// in their generic context to pick this overload; otherwise they fall through
    /// to the conservative non-Equatable subscript below.
    public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value where K.Value: Equatable {
        get { storage[ObjectIdentifier(K.self)]?.any as? K.Value ?? K.defaultValue }
        set {
            let v = newValue
            storage[ObjectIdentifier(K.self)] = StoredValue(any: v, equals: { ($0 as? K.Value) == v })
        }
    }

    /// Fallback overload for `K.Value` types that do NOT conform to `Equatable`.
    /// Captures `{ _ in false }` so any comparison conservatively returns
    /// "not equal" — the diff will re-merge the subtree on every render.
    /// This matches the pre-Equatable behavior for non-Equatable env values
    /// (e.g. `Router`).
    public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value {
        get { storage[ObjectIdentifier(K.self)]?.any as? K.Value ?? K.defaultValue }
        set {
            storage[ObjectIdentifier(K.self)] = StoredValue(any: newValue, equals: { _ in false })
        }
    }

    func merging(_ overrides: EnvironmentValues) -> EnvironmentValues {
        var result = self
        for (id, val) in overrides.storage { result.storage[id] = val }
        return result
    }
}

/// Reflexivity caveat: `x == x` is NOT guaranteed to be `true`. Any key whose
/// `Value` does not conform to `Equatable` (e.g. `Router`) was written through
/// the conservative subscript above, which captures `equals: { _ in false }` —
/// so comparing that key's stored value against itself returns `false`. This
/// is intentional (a false "changed" is safe: it just triggers an extra
/// re-merge), but callers relying on `EnvironmentValues` for reflexive
/// equality checks (e.g. memoization) will see spurious inequality wherever
/// non-`Equatable` env values are in play.
extension EnvironmentValues: Equatable {
    public static func == (lhs: EnvironmentValues, rhs: EnvironmentValues) -> Bool {
        guard lhs.storage.count == rhs.storage.count else { return false }
        for (id, lhsVal) in lhs.storage {
            guard let rhsVal = rhs.storage[id] else { return false }
            if !lhsVal.equals(rhsVal.any) || !rhsVal.equals(lhsVal.any) { return false }
        }
        return true
    }
}

public enum ColorScheme: Equatable, Sendable { case light, dark }

private enum LocaleKey: EnvironmentKey { static let defaultValue = "en" }
private enum ColorSchemeKey: EnvironmentKey { static let defaultValue = ColorScheme.light }

extension EnvironmentValues {
    public var locale: String {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }
}

@MainActor
enum AmbientEnvironment {
    static var current: EnvironmentValues = .init()
}

@propertyWrapper
public struct Environment<Value> {
    let keyPath: KeyPath<EnvironmentValues, Value>
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { self.keyPath = keyPath }
    @MainActor
    public var wrappedValue: Value { AmbientEnvironment.current[keyPath: keyPath] }
}
