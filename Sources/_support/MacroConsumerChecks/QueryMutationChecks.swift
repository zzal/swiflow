// COMPILE-ONLY GATE for @Query/@Mutation witness isolation.
// MainActorWitnessIsolation.witnessNames = ["fetch", "perform",
// "optimistic", "invalidations"] is hand-encoded string policy that must
// track the Query/Mutation protocol requirements — and nothing but a real
// compile can prove the stamping happened. Every witness below mutates
// @MainActor state, so dropping ANY name from that list turns the touch
// into a "main actor-isolated ... can not be mutated from a nonisolated
// context" error in this file, failing CI's plain `swift build`.

import Swiflow
import SwiflowQuery

/// The isolation tripwire every witness touches.
@MainActor
enum WitnessGate {
    static var touches = 0
}

public struct Thing: Equatable, Sendable {
    public let id: Int
    public var name: String
    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - @Query with @Key, public access

@Query(prefix: "things")
public struct ThingByID {
    @Key public let id: Int
    public var tags: Set<QueryTag> { ["things"] }

    public func fetch() async throws -> Thing {
        WitnessGate.touches += 1  // compiles only if fetch is @MainActor
        return Thing(id: id, name: "thing-\(id)")
    }

    public init(id: Int) { self.id = id }
}

// MARK: - @Query with a hand-declared conformance
//
// The extension macro must guard `!protocols.isEmpty` — an unconditional
// emit would double-conform this type and fail the build (the
// extension-macro-conditional-conformance regression shape).

@Query(prefix: "legacy-things")
public struct LegacyThingList: Query {
    public func fetch() async throws -> [Thing] {
        WitnessGate.touches += 1
        return []
    }
    public init() {}
}

// MARK: - @Mutation exercising all four witnessNames

@Mutation
public struct RenameThing {
    public func perform(_ newName: String) async throws -> Thing {
        WitnessGate.touches += 1  // compiles only if perform is @MainActor
        return Thing(id: 1, name: newName)
    }

    public func optimistic(_ newName: String) -> [OptimisticEdit] {
        WitnessGate.touches += 1  // compiles only if optimistic is @MainActor
        return [.update(ThingByID(id: 1)) { thing in
            Thing(id: thing.id, name: newName)
        }]
    }

    public func invalidations(input: String, output: Thing) -> [Invalidation] {
        WitnessGate.touches += 1  // compiles only if invalidations is @MainActor
        return [.exact(ThingByID(id: output.id))]
    }

    public init() {}
}
