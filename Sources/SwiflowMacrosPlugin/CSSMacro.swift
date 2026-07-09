// Sources/SwiflowMacrosPlugin/CSSMacro.swift
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Freestanding `#css("…")` expression macro. Validates the literal's CSS
/// *structure* at compile time (balance, declaration shape — never property
/// names or values) and expands to `CSSSheet(entries:)`: hoisted at-rules as
/// `.raw`, everything else merged into one `.scopedBlock` that the runtime
/// wraps in `.<scopeClass> { … }` for native-nesting scoping.
/// Design: docs/superpowers/specs/2026-06-12-css-macro-design.md
public struct CSSMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let empty: ExprSyntax = "CSSSheet(entries: [])"

        guard let argument = node.arguments.first?.expression,
              let literal = argument.as(StringLiteralExprSyntax.self) else {
            context.diagnose(Diagnostic(
                node: node.arguments.first.map { Syntax($0) } ?? Syntax(node),
                message: CSSMacroDiagnostic.requiresStaticLiteral))
            return empty
        }

        var text = ""
        for segment in literal.segments {
            guard let plain = segment.as(StringSegmentSyntax.self) else {
                // Interpolation segment — same guidance as a non-literal arg.
                context.diagnose(Diagnostic(
                    node: Syntax(literal),
                    message: CSSMacroDiagnostic.requiresStaticLiteral))
                return empty
            }
            text += plain.content.text
        }

        let result = CSSStructuralParser.parse(text)
        guard result.diagnostics.isEmpty else {
            // Anchor each diagnostic at the offending token INSIDE the literal
            // (not the literal's start) so the editor gutter matches the
            // reported line/column. Interpolation is rejected above, so there is
            // exactly one plain segment and `text` is its content verbatim.
            let segment = literal.segments.first?.as(StringSegmentSyntax.self)
            for d in result.diagnostics {
                let position = segment.map {
                    $0.position.advanced(by: Self.utf8Offset(in: text, line: d.line, column: d.column))
                }
                context.diagnose(Diagnostic(
                    node: Syntax(literal),
                    position: position,
                    message: CSSMacroDiagnostic.css(d)))
            }
            return empty
        }

        // Hoisted entries keep source order *among themselves*; scoped
        // segments merge into one block placed where the first of them
        // appeared, so a mid-sheet @keyframes deliberately lands after the
        // block. Harmless: every hoistable at-rule is order-independent
        // at the stylesheet level.
        var entryExprs: [String] = []
        var scopedParts: [String] = []
        var scopedSlot: Int?
        for segment in result.segments {
            switch segment {
            case .hoisted(let css):
                entryExprs.append(".raw(\(StringLiteralExprSyntax(content: css).description))")
            case .scoped(let css):
                if scopedSlot == nil {
                    scopedSlot = entryExprs.count
                    entryExprs.append("") // placeholder, filled below
                }
                scopedParts.append(css)
            }
        }
        if let slot = scopedSlot {
            let body = scopedParts.joined(separator: "\n\n")
            entryExprs[slot] = ".scopedBlock(\(StringLiteralExprSyntax(content: body).description))"
        }
        return "CSSSheet(entries: [\(raw: entryExprs.joined(separator: ", "))])"
    }

    /// UTF-8 byte offset into `text` of the parser's 1-based (line, column),
    /// mirroring the parser's own advance: `line` counts `\n`, `column` counts
    /// grapheme clusters and resets to 1 after a newline. Clamps to end.
    static func utf8Offset(in text: String, line: Int, column: Int) -> Int {
        var curLine = 1, curColumn = 1, utf8 = 0
        for ch in text {
            if curLine == line && curColumn == column { return utf8 }
            if ch == "\n" { curLine += 1; curColumn = 1 } else { curColumn += 1 }
            utf8 += ch.utf8.count
        }
        return utf8
    }
}

enum CSSMacroDiagnostic: DiagnosticMessage {
    case requiresStaticLiteral
    case css(CSSStructuralParser.ParseDiagnostic)

    var message: String {
        switch self {
        case .requiresStaticLiteral:
            return "#css requires a static string literal — pass dynamic values via CSS custom properties (.style(\"--x\", value)) and read them with var(--x)"
        case .css(let d):
            return "CSS error at line \(d.line), column \(d.column): \(d.message)"
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .requiresStaticLiteral:
            return MessageID(domain: "SwiflowMacros", id: "css.requiresStaticLiteral")
        case .css:
            return MessageID(domain: "SwiflowMacros", id: "css.structural")
        }
    }

    var severity: DiagnosticSeverity { .error }
}
