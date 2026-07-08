// Sources/MacroConsumerChecks/PersistedChecks.swift
//
// COMPILE-ONLY GATE for @Persisted (audit IV Wave-2 #5). Consumes the macro
// the way a real app does: PLAIN imports, a public @Component, public
// @Persisted members read from a main-actor body.
//
// What breaks this file (and therefore CI's plain `swift build`):
//   - PersistedMacro's peer stops stamping @MainActor / copying access onto
//     the `$name` projection → the body's isolation/access checks fail.
//   - @Component stops synthesizing `_swiflowPersistNamespace` /
//     `_swiflowIsHydrating` / `_swiflowHydratePersisted` → the emitted
//     didSet and `_swiflowDidMount` reference missing members.
//   - The emitted code's `_PersistedStorageRegistry` reference breaks →
//     the SwiflowStore layering regressed.
//   - `Component._swiflowDidMount` loses its default or the synthesized
//     override's signature drifts → conformance error right here.

import Swiflow
import SwiflowStore

// MARK: - Public bare @Component with public @Persisted members

@Component
public final class PersistedConsumer {
    @Persisted public var theme: String = "light"
    @Persisted("shared-locale") public var locale: String = "en"

    public var body: VNode {
        div {
            p { VNode.text(theme) }
            // The $ projection must be reachable and bindable, exactly like
            // @State's (cross-module reads live in MacroConsumerTests).
            input(.value($theme))
            p { VNode.text(locale) }
        }
    }
}
