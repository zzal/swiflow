// Sources/Swiflow/JSON/JSONValueEncoder.swift
//
// Encodes any `Encodable` into a `JSONValue` tree — the encode counterpart to
// JavaScriptKit's `JSValueDecoder`. JavaScriptKit ships no `JSValueEncoder`, and
// Foundation's `JSONEncoder` isn't available under WASM, so `PersistentStore`
// needs this to turn Swift values into a string IndexedDB can hold (via
// `JSONValue.jsonString`). It's pure Swift — no JavaScriptKit, no Foundation —
// so it compiles everywhere and is unit-tested off-WASM, exactly like
// `JSONValue` itself.
//
// Implementation: encoding containers are value types, but Codable hands the
// same container back for repeated `encode(_:forKey:)` calls and lets parents
// link children before those children are populated. To make that work without
// Foundation's NSMutable* reference types, the tree is built from `RefNode`
// reference cells: a parent links a child node into its slot immediately, the
// child encoder mutates that same node in place, and the whole tree is frozen
// into an immutable `JSONValue` once at the end.

public struct JSONValueEncoder {
    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let root = RefNode()
        try value.encode(to: _Encoder(node: root, codingPath: []))
        return root.frozen()
    }
}

// MARK: - Mutable tree

/// A reference cell holding one node of the JSON tree while it's being built.
/// Shared between a parent container and the child encoder that fills it.
private final class RefNode {
    enum Kind {
        case value(JSONValue)
        case object(ObjectStore)
        case array(ArrayStore)
    }
    /// Starts as `null`; an empty container (e.g. `{}` / `[]`) that never gets a
    /// kind assigned therefore freezes to `null`, which round-trips cleanly.
    var kind: Kind = .value(.null)

    func frozen() -> JSONValue {
        switch kind {
        case .value(let v):  return v
        case .object(let s): return .object(s.entries.mapValues { $0.frozen() })
        case .array(let s):  return .array(s.items.map { $0.frozen() })
        }
    }
}

private final class ObjectStore { var entries: [String: RefNode] = [:] }
private final class ArrayStore { var items: [RefNode] = [] }

// MARK: - Primitive mapping

private extension JSONValue {
    /// Map Swift's fixed-width integers onto `JSONValue`. Values that don't fit
    /// `Int` fall back to `.double` rather than trapping — `Int` is only 32-bit
    /// on wasm32, so an `Int64`/`UInt64` field beyond ±2³¹ would crash `Int(_:)`.
    /// (`JSON.stringify` likewise renders large numbers as plain doubles.)
    static func integer<I: BinaryInteger>(_ v: I) -> JSONValue {
        if let i = Int(exactly: v) { return .int(i) }
        return .double(Double(v))
    }
}

// MARK: - Encoder

private final class _Encoder: Encoder {
    let node: RefNode
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(node: RefNode, codingPath: [CodingKey]) {
        self.node = node
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> {
        let store: ObjectStore
        if case .object(let existing) = node.kind {
            store = existing                    // same container requested twice
        } else {
            store = ObjectStore()
            node.kind = .object(store)
        }
        return KeyedEncodingContainer(KeyedContainer(store: store, codingPath: codingPath))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let store: ArrayStore
        if case .array(let existing) = node.kind {
            store = existing
        } else {
            store = ArrayStore()
            node.kind = .array(store)
        }
        return UnkeyedContainer(store: store, codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        SingleValueContainer(node: node, codingPath: codingPath)
    }
}

// MARK: - Keyed container

private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let store: ObjectStore
    var codingPath: [CodingKey]

    private func slot(_ key: CodingKey) -> RefNode {
        let node = RefNode()
        store.entries[key.stringValue] = node
        return node
    }

    mutating func encodeNil(forKey key: Key) { store.entries[key.stringValue] = RefNode() }

    mutating func encode(_ value: Bool, forKey key: Key)   { set(.bool(value), key) }
    mutating func encode(_ value: String, forKey key: Key) { set(.string(value), key) }
    mutating func encode(_ value: Double, forKey key: Key) { set(.double(value), key) }
    mutating func encode(_ value: Float, forKey key: Key)  { set(.double(Double(value)), key) }
    mutating func encode(_ value: Int, forKey key: Key)    { set(.int(value), key) }
    mutating func encode(_ value: Int8, forKey key: Key)   { set(.integer(value), key) }
    mutating func encode(_ value: Int16, forKey key: Key)  { set(.integer(value), key) }
    mutating func encode(_ value: Int32, forKey key: Key)  { set(.integer(value), key) }
    mutating func encode(_ value: Int64, forKey key: Key)  { set(.integer(value), key) }
    mutating func encode(_ value: UInt, forKey key: Key)   { set(.integer(value), key) }
    mutating func encode(_ value: UInt8, forKey key: Key)  { set(.integer(value), key) }
    mutating func encode(_ value: UInt16, forKey key: Key) { set(.integer(value), key) }
    mutating func encode(_ value: UInt32, forKey key: Key) { set(.integer(value), key) }
    mutating func encode(_ value: UInt64, forKey key: Key) { set(.integer(value), key) }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        try value.encode(to: _Encoder(node: slot(key), codingPath: codingPath + [key]))
    }

    private func set(_ value: JSONValue, _ key: CodingKey) {
        store.entries[key.stringValue] = { let n = RefNode(); n.kind = .value(value); return n }()
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy _: NestedKey.Type, forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        _Encoder(node: slot(key), codingPath: codingPath + [key]).container(keyedBy: NestedKey.self)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        _Encoder(node: slot(key), codingPath: codingPath + [key]).unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder {
        _Encoder(node: slot(SuperKey()), codingPath: codingPath + [SuperKey()])
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        _Encoder(node: slot(key), codingPath: codingPath + [key])
    }
}

/// The "super" coding key Codable uses when an unkeyed/keyed `superEncoder()` is
/// requested without an explicit key.
private struct SuperKey: CodingKey {
    var stringValue: String { "super" }
    var intValue: Int? { nil }
    init() {}
    init?(stringValue: String) {}
    init?(intValue: Int) { nil }
}

// MARK: - Unkeyed container

private struct UnkeyedContainer: UnkeyedEncodingContainer {
    let store: ArrayStore
    var codingPath: [CodingKey]
    var count: Int { store.items.count }

    private func append() -> RefNode {
        let node = RefNode()
        store.items.append(node)
        return node
    }
    private func append(_ value: JSONValue) {
        let n = RefNode(); n.kind = .value(value); store.items.append(n)
    }

    mutating func encodeNil()            { store.items.append(RefNode()) }
    mutating func encode(_ value: Bool)   { append(.bool(value)) }
    mutating func encode(_ value: String) { append(.string(value)) }
    mutating func encode(_ value: Double) { append(.double(value)) }
    mutating func encode(_ value: Float)  { append(.double(Double(value))) }
    mutating func encode(_ value: Int)    { append(.int(value)) }
    mutating func encode(_ value: Int8)   { append(.integer(value)) }
    mutating func encode(_ value: Int16)  { append(.integer(value)) }
    mutating func encode(_ value: Int32)  { append(.integer(value)) }
    mutating func encode(_ value: Int64)  { append(.integer(value)) }
    mutating func encode(_ value: UInt)   { append(.integer(value)) }
    mutating func encode(_ value: UInt8)  { append(.integer(value)) }
    mutating func encode(_ value: UInt16) { append(.integer(value)) }
    mutating func encode(_ value: UInt32) { append(.integer(value)) }
    mutating func encode(_ value: UInt64) { append(.integer(value)) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        try value.encode(to: _Encoder(node: append(), codingPath: codingPath))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy _: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        _Encoder(node: append(), codingPath: codingPath).container(keyedBy: NestedKey.self)
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        _Encoder(node: append(), codingPath: codingPath).unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder {
        _Encoder(node: append(), codingPath: codingPath)
    }
}

// MARK: - Single-value container

private struct SingleValueContainer: SingleValueEncodingContainer {
    let node: RefNode
    var codingPath: [CodingKey]

    mutating func encodeNil()             { node.kind = .value(.null) }
    mutating func encode(_ value: Bool)   { node.kind = .value(.bool(value)) }
    mutating func encode(_ value: String) { node.kind = .value(.string(value)) }
    mutating func encode(_ value: Double) { node.kind = .value(.double(value)) }
    mutating func encode(_ value: Float)  { node.kind = .value(.double(Double(value))) }
    mutating func encode(_ value: Int)    { node.kind = .value(.int(value)) }
    mutating func encode(_ value: Int8)   { node.kind = .value(.integer(value)) }
    mutating func encode(_ value: Int16)  { node.kind = .value(.integer(value)) }
    mutating func encode(_ value: Int32)  { node.kind = .value(.integer(value)) }
    mutating func encode(_ value: Int64)  { node.kind = .value(.integer(value)) }
    mutating func encode(_ value: UInt)   { node.kind = .value(.integer(value)) }
    mutating func encode(_ value: UInt8)  { node.kind = .value(.integer(value)) }
    mutating func encode(_ value: UInt16) { node.kind = .value(.integer(value)) }
    mutating func encode(_ value: UInt32) { node.kind = .value(.integer(value)) }
    mutating func encode(_ value: UInt64) { node.kind = .value(.integer(value)) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        try value.encode(to: _Encoder(node: node, codingPath: codingPath))
    }
}
