// Sources/Swiflow/Reactivity/Environment.swift

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct EnvironmentValues {
    var storage: [ObjectIdentifier: Any] = [:]

    public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value {
        get { storage[ObjectIdentifier(K.self)] as? K.Value ?? K.defaultValue }
        set { storage[ObjectIdentifier(K.self)] = newValue }
    }

    func merging(_ overrides: EnvironmentValues) -> EnvironmentValues {
        var result = self
        for (id, val) in overrides.storage { result.storage[id] = val }
        return result
    }
}

extension EnvironmentValues: Equatable {
    public static func == (lhs: EnvironmentValues, rhs: EnvironmentValues) -> Bool {
        guard lhs.storage.count == rhs.storage.count else { return false }
        return lhs.storage.keys.allSatisfy { rhs.storage[$0] != nil }
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

enum AmbientEnvironment {
    nonisolated(unsafe) static var current: EnvironmentValues = .init()
}

@propertyWrapper
public struct Environment<Value> {
    let keyPath: KeyPath<EnvironmentValues, Value>
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { self.keyPath = keyPath }
    public var wrappedValue: Value { AmbientEnvironment.current[keyPath: keyPath] }
}
