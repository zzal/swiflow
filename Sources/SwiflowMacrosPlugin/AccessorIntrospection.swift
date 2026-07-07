// Sources/SwiflowMacrosPlugin/AccessorIntrospection.swift
//
// Shared by the three state-ish peer macros (@State, @MutationState,
// @ReducerState), which all reject accessor blocks but owe the author a
// diagnostic that matches what they actually wrote.

import SwiftSyntax

/// Distinguishes a computed property (a getter, with or without an explicit
/// `set`) from a stored property with a user-supplied observer
/// (`didSet`/`willSet`). Both arrive with a non-nil `accessorBlock`, but they
/// need different diagnostics: a computed property was never a storage cell
/// to begin with (telling its author to "move the didSet into a method" is
/// nonsensical — they never wrote one), while an observer IS a storage cell
/// whose side effect needs relocating.
func isComputedProperty(_ accessorBlock: AccessorBlockSyntax) -> Bool {
    switch accessorBlock.accessors {
    // Getter-only shorthand: `var x: Int { 5 }` — implicit get, no set.
    case .getter:
        return true
    // Explicit accessor list: computed iff it declares `get`/`set` and
    // neither `didSet` nor `willSet`.
    case .accessors(let list):
        var sawGetOrSet = false
        for accessor in list {
            switch accessor.accessorSpecifier.tokenKind {
            case .keyword(.didSet), .keyword(.willSet):
                return false
            case .keyword(.get), .keyword(.set):
                sawGetOrSet = true
            default:
                break
            }
        }
        return sawGetOrSet
    }
}
