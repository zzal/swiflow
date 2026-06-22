// Sources/SwiflowQuery/QueryKeyConvertible.swift

/// A type whose identity can be encoded into `QueryKey` components.
///
/// `QueryKeyComponent` is deliberately a closed 2-case enum (`.string` / `.int`)
/// — the type-safe alternative to `AnyHashable` (no Int/Int64/String confusion,
/// debuggable, prefix-cascadable). Any type used as a `@Key` in a `@Query`
/// must therefore project its identity into those two cases.
///
/// `@Query` emits a uniform `_qkc(_:)` dispatch over every `@Key` property in
/// source order, so the macro never needs to know a property's concrete type —
/// the conformance carries that knowledge. Most keys are a single component; the
/// array return supports composite identities (e.g. a `Coordinate` keying as
/// `[.int(lat), .int(lon)]`).
///
/// The protocol is deliberately *non-isolated*: encoding a value into key
/// components is a pure read with no shared state, so it is freely callable from
/// the `@MainActor`-isolated `Query.queryKey` getter while keeping conformances
/// on plain value types (enums, structs) free of actor annotations.
public protocol QueryKeyConvertible {
    var keyComponents: [QueryKeyComponent] { get }
}

extension Int: QueryKeyConvertible {
    public var keyComponents: [QueryKeyComponent] { [.int(self)] }
}

extension String: QueryKeyConvertible {
    public var keyComponents: [QueryKeyComponent] { [.string(self)] }
}

/// `Bool` keys as a stable string (`"true"` / `"false"`), never `.int(0/1)`, so a
/// boolean key and an integer id at the same position can never collide — and so
/// cache dumps stay readable.
extension Bool: QueryKeyConvertible {
    public var keyComponents: [QueryKeyComponent] { [.string(self ? "true" : "false")] }
}

/// Enums (and other `RawRepresentable`s) whose raw value is itself convertible
/// key by that raw value, opt-in:
///
///     enum Window: String, QueryKeyConvertible { case hour, day, week }
///     @Key let window: Window     // → .string("day")
///
/// The conformance is opt-in — the type declares `: QueryKeyConvertible` — so it
/// never silently swallows a `RawRepresentable` the author didn't intend as a key.
/// `RawValue: QueryKeyConvertible` covers the common `String`- and `Int`-raw enums.
extension RawRepresentable where RawValue: QueryKeyConvertible {
    public var keyComponents: [QueryKeyComponent] { rawValue.keyComponents }
}

/// Underscored: an implementation detail of `@Query`'s expansion, not public
/// API to call directly. Its generic constraint turns a missing conformance into
/// the canonical "requires that 'Foo' conform to 'QueryKeyConvertible'"
/// diagnostic — anchored to the user's `@Key var foo: Foo` — instead of a cryptic
/// "no member 'keyComponents'" error pointing inside invisible generated code.
///
/// `@inlinable` so the one-line indirection is free in optimized builds (a query
/// value, and thus its `queryKey`, is constructed on every render).
@inlinable
public func _qkc<T: QueryKeyConvertible>(_ value: T) -> [QueryKeyComponent] {
    value.keyComponents
}
