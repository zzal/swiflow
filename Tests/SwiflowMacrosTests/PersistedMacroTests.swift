// Tests/SwiflowMacrosTests/PersistedMacroTests.swift
//
// Audit IV Wave-2 #5: @Persisted goldens. The expansion is @State's exact
// didSet plus the registry save (flag-suppressed during hydration) and the
// same $name Binding peer. NB assertMacroExpansion type-checks nothing —
// SwiflowStoreTests + MacroConsumerChecks are the real gates.
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import SwiflowMacrosPlugin

private nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "Persisted": PersistedMacro.self,
]

final class PersistedMacroTests: XCTestCase {

    // Bare form: didSet-with-save under the auto-namespaced key + $ peer.
    func testBareExpansion() {
        assertMacroExpansion(
            """
            final class Prefs {
                @Persisted var magnitude: String = "2.5"
            }
            """,
            expandedSource: """
            final class Prefs {
                var magnitude: String = "2.5" {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            magnitude = oldValue
                            return
                        }
                        if let s = runtimeScheduler, let o = runtimeOwner {
                            s.markDirty(o)
                        }
                        if !_swiflowIsHydrating {
                            let value = magnitude
                            Task {
                                try? await _PersistedStorageRegistry.current.save(value, forKey: Self._swiflowPersistNamespace + ".magnitude")
                            }
                        }
                    }
                }

                @MainActor var $magnitude: Binding<String> {
                    Binding(
                        get: { [unowned self] in
                            self.magnitude
                        },
                        set: { [unowned self] in
                            self.magnitude = $0
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    // Explicit key: used verbatim in the save.
    func testExplicitKeyExpansion() {
        assertMacroExpansion(
            """
            final class Prefs {
                @Persisted("quakes-magnitude") var magnitude: String = "2.5"
            }
            """,
            expandedSource: """
            final class Prefs {
                var magnitude: String = "2.5" {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            magnitude = oldValue
                            return
                        }
                        if let s = runtimeScheduler, let o = runtimeOwner {
                            s.markDirty(o)
                        }
                        if !_swiflowIsHydrating {
                            let value = magnitude
                            Task {
                                try? await _PersistedStorageRegistry.current.save(value, forKey: "quakes-magnitude")
                            }
                        }
                    }
                }

                @MainActor var $magnitude: Binding<String> {
                    Binding(
                        get: { [unowned self] in
                            self.magnitude
                        },
                        set: { [unowned self] in
                            self.magnitude = $0
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - @Component cooperation

    // The synthesized hydration wiring: namespace literal, flag, mount hook,
    // per-member load-assign under a SYNCHRONOUS flag window, and stateCells
    // inclusion. Registers ONLY ComponentMacro (the house idiom from
    // ComponentMacroMutationTests): @Component scans for the attribute NAME,
    // never expands it, so @Persisted stays verbatim in the golden.
    func testComponentSynthesizesHydration() {
        let componentMacros: [String: Macro.Type] = [
            "Component": ComponentMacro.self,
        ]
        assertMacroExpansion(
            """
            @Component
            final class Prefs {
                @Persisted var theme: String = "light"
                @Persisted("legacy-locale") var locale: String = "en"
                init() {}
            }
            """,
            expandedSource: """
            final class Prefs {
                @Persisted
                @MainActor var theme: String = "light"
                @Persisted("legacy-locale")
                @MainActor var locale: String = "en"
                @MainActor
                init() {}

                @MainActor private weak var runtimeOwner: AnyComponent?

                @MainActor private var runtimeScheduler: Scheduler?

                @MainActor static let stateCells: [any AnyStateCell] = [
                    StateCell<Prefs>(
                    name: "theme",
                    snapshot: {
                        $0.theme as Any
                    },
                    restore: { c, v in
                        guard let typed = _hmrCoerce(v, to: String.self) else {
                            return false
                        }
                        c.theme = typed
                        return true
                    },
                    restoreNil: { _ in
                        false
                    }
                    ),
                    StateCell<Prefs>(
                    name: "locale",
                    snapshot: {
                        $0.locale as Any
                    },
                    restore: { c, v in
                        guard let typed = _hmrCoerce(v, to: String.self) else {
                            return false
                        }
                        c.locale = typed
                        return true
                    },
                    restoreNil: { _ in
                        false
                    }
                    ),
                ]

                @MainActor func bind(owner: AnyComponent, scheduler: Scheduler) {
                    self.runtimeOwner = owner
                    self.runtimeScheduler = scheduler
                }

                static let _swiflowPersistNamespace = "Prefs"

                @MainActor var _swiflowIsHydrating = false

                @MainActor func _swiflowDidMount() {
                    Task {
                        await self._swiflowHydratePersisted()
                    }
                }

                @MainActor func _swiflowHydratePersisted() async {
                    if let v = try? await _PersistedStorageRegistry.current.load(String.self, forKey: Self._swiflowPersistNamespace + ".theme") {
                        _swiflowIsHydrating = true
                        theme = v
                        _swiflowIsHydrating = false
                    }
                    if let v = try? await _PersistedStorageRegistry.current.load(String.self, forKey: "legacy-locale") {
                        _swiflowIsHydrating = true
                        locale = v
                        _swiflowIsHydrating = false
                    }
                }
            }

            extension Prefs: Component, _ComponentRuntime {
            }
            """,
            macros: componentMacros
        )
    }

    // MARK: - Diagnostics (the six-message split)

    func testLetIsRejected() {
        assertMacroExpansion(
            """
            final class Prefs {
                @Persisted let theme: String = "light"
            }
            """,
            expandedSource: """
            final class Prefs {
                let theme: String = "light"
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Persisted requires a `var` — persisted cells must be mutable.",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    func testMissingTypeIsRejected() {
        assertMacroExpansion(
            """
            final class Prefs {
                @Persisted var theme = "light"
            }
            """,
            expandedSource: """
            final class Prefs {
                var theme = "light"
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Persisted requires an explicit type annotation (e.g. `@Persisted var count: Int = 0`).",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    // assertMacroExpansion refuses BOTH roles on a multi-binding var (its
    // own two diagnostics below) and never invokes our expansion; the REAL
    // compiler blocks only the accessor but RUNS the peer — where our
    // requiresSingleBinding guard fires. Same documented divergence as
    // StateMacroTests.testRejectsMultiBinding; the real-compiler side is
    // covered by the host-compiled checks.
    func testMultiBindingIsRejected() {
        assertMacroExpansion(
            """
            final class Prefs {
                @Persisted var a: Int = 0, b: Int = 0
            }
            """,
            expandedSource: """
            final class Prefs {
                var a: Int = 0, b: Int = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "accessor macro can only be applied to a single variable", line: 2, column: 5, severity: .error),
                DiagnosticSpec(message: "peer macro can only be applied to a single variable", line: 2, column: 5, severity: .error),
            ],
            macros: testMacros
        )
    }

    func testUserDidSetIsRejected() {
        assertMacroExpansion(
            """
            final class Prefs {
                @Persisted var theme: String = "light" {
                    didSet { print("changed") }
                }
            }
            """,
            expandedSource: """
            final class Prefs {
                var theme: String = "light" {
                    didSet { print("changed") }
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Persisted properties cannot declare their own didSet; move the side effect into a method.",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    func testComputedPropertyIsRejected() {
        assertMacroExpansion(
            """
            final class Prefs {
                @Persisted var theme: String { "light" }
            }
            """,
            expandedSource: """
            final class Prefs {
                var theme: String { "light" }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Persisted cannot be applied to a computed property — only stored properties. Remove the computed body, or drop @Persisted if this isn't meant to be a persisted cell.",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }

    func testNonLiteralKeyIsRejected() {
        assertMacroExpansion(
            """
            final class Prefs {
                @Persisted("prefix-\\(suffix)") var theme: String = "light"
            }
            """,
            expandedSource: """
            final class Prefs {
                var theme: String = "light"
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Persisted's key must be a static string literal — it is baked into the emitted storage calls. Move dynamic parts into the value, not the key.",
                    line: 2, column: 5, severity: .error
                ),
            ],
            macros: testMacros
        )
    }
}
