// Sources/SwiflowMacrosPlugin/PersistedKeyDerivation.swift
import SwiftSyntax

/// ONE key-derivation implementation shared by PersistedMacro's didSet and
/// ComponentMacro's synthesized hydrate — the two emission sites cannot
/// drift apart (sibling-inconsistency is the audit's dominant defect shape).
enum PersistedKeyDerivation {
    /// The explicit key literal from `@Persisted("legacy-key")`, or nil for
    /// bare `@Persisted` — and also nil for a non-literal argument, which
    /// `hasNonLiteralKey` distinguishes so callers can diagnose it.
    static func explicitKey(from attribute: AttributeSyntax) -> String? {
        guard let args = attribute.arguments?.as(LabeledExprListSyntax.self),
              let first = args.first else { return nil }
        guard let literal = first.expression.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
            return nil
        }
        return segment.content.text
    }

    /// True when the attribute HAS an argument that is not a plain static
    /// string literal (interpolation, variable, …) — diagnosable misuse:
    /// the key is baked into emitted source, so it must be static.
    static func hasNonLiteralKey(_ attribute: AttributeSyntax) -> Bool {
        guard let args = attribute.arguments?.as(LabeledExprListSyntax.self),
              !args.isEmpty else { return false }
        return explicitKey(from: attribute) == nil
    }

    /// The Swift EXPRESSION (source text) for the storage key.
    static func keyExpression(explicitKey: String?, propertyName: String) -> String {
        if let explicitKey { return "\"\(explicitKey)\"" }
        return "Self._swiflowPersistNamespace + \".\(propertyName)\""
    }
}
