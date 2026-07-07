// Sources/MacroConsumerChecks/ComponentChecks.swift
//
// COMPILE-ONLY GATE for the component-side macros (audit III Wave-2 #9).
// `assertMacroExpansion` type-checks nothing, and the compile gates that DO
// live inside test targets (BareComponentIsolationTests & friends) use
// `private` types under `@testable import` — which disables access-control
// checking of the emitted code entirely. This target consumes the macros
// the way a real app does: PLAIN `import Swiflow`, public/package types,
// cross-module use from MacroConsumerTests.
//
// What breaks this file (and therefore CI's plain `swift build`):
//   - @Component's memberAttribute stops stamping @MainActor → the bodies'
//     `$` reads fail isolation checking (the BareComponentIsolation shape).
//   - SynthesizedAccess stops copying `public`/`package` onto projections →
//     MacroConsumerTests' cross-module reads fail access checking.
//   - @Component stops synthesizing init() for defaultless @MutationState /
//     @ReducerState members → "class has no initializers" right here.
//   - Peer macros stop stamping @MainActor on their emitted projections →
//     main-actor bodies can't read them.

import Swiflow
import SwiflowQuery

// MARK: - Public bare @Component with public @State

/// Bare (no explicit @MainActor) on purpose: the memberAttribute injection
/// is the behavior under test. `public init()` is user-declared so the type
/// is constructible cross-module.
@Component
public final class PublicCounter {
    @State public var count: Int = 0

    public var body: VNode {
        _ = $count  // projection must be @MainActor to read the isolated backing
        return .text("\(count)")
    }

    public func bump() { count += 1 }

    /// The onChange witness — stamped @MainActor by the memberAttribute
    /// role, and the imperative-sync helper must be callable inside it.
    public func onChange() {
        onChange(of: count) { _ in }
    }

    public init() {}
}

/// A realistic consumer shape: touching a component from a nonisolated
/// async context means hopping onto the main actor — the component's
/// (macro-stamped) isolated init and members all live there, and region
/// analysis pins the non-Sendable instance inside the hop.
public func crossActorBump() async -> Int {
    await MainActor.run {
        let counter = PublicCounter()
        counter.bump()
        return counter.count
    }
}

// MARK: - Auto-init synthesis (@MutationState with no default)

/// No user init and no default on `save`: @Component must synthesize
/// `init()` (the `named(init)` MemberMacro gotcha — golden tests can't
/// catch a miss, this compile can).
@Component
public final class MutationHolder {
    @MutationState public var save: RenameThing

    public var body: VNode {
        _ = $save.isPending  // public @MainActor MutationHandle projection
        return .text("saver")
    }
}

/// Same-module factory so cross-module tests can construct one without
/// depending on the synthesized init's access level.
@MainActor public func makeMutationHolder() -> MutationHolder { MutationHolder() }

// MARK: - @ReducerState, package access

public struct CheckoutFlow: Reducer {
    public struct State: Equatable {
        public var step = 0
    }
    public enum Action {
        case next
    }
    public var initialState: State { .init() }
    public func reduce(into state: inout State, _ action: Action) {
        if case .next = action { state.step += 1 }
    }
    public init() {}
}

/// `package` access on the projection: SynthesizedAccess must copy the
/// keyword, and MacroConsumerTests (same package, different module) must be
/// able to read `$flow` — a shape `private`-under-@testable gates can't check.
@Component
public final class ReducerHost {
    @ReducerState package var flow: CheckoutFlow

    public var body: VNode {
        .text("step \($flow.state.step)")
    }
}

@MainActor public func makeReducerHost() -> ReducerHost { ReducerHost() }
