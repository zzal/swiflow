// Sources/SwiflowMacrosPlugin/CSSStructuralParser.swift
//
// Structural (not semantic) CSS parsing for the #css macro. Understands
// comments, strings, and brace/paren/bracket balance — never property names,
// values, or selector grammar; those pass through to the browser verbatim.
// Stops at the first diagnostic: the macro discards all segments when any
// diagnostic is present, so error recovery buys nothing.
// Design: docs/superpowers/specs/2026-06-12-css-macro-design.md

import Foundation

enum CSSStructuralParser {

    struct ParseDiagnostic: Equatable {
        let message: String
        let line: Int      // 1-based within the CSS text
        let column: Int    // 1-based; counts grapheme clusters (Array(text) indexing)
    }

    enum Segment: Equatable {
        /// Emitted outside the scope wrapper (as `.raw`): at-rules that are
        /// invalid when nested, plus :root/html/body rules.
        case hoisted(String)
        /// Joined into the single `.scopedBlock` body.
        case scoped(String)
    }

    struct ParseResult: Equatable {
        var segments: [Segment]
        var diagnostics: [ParseDiagnostic]
    }

    /// At-rules that may not appear nested inside a style rule — hoisted out
    /// of the scope wrapper verbatim. (`@layer` *statements* are hoisted too,
    /// handled separately because the block form nests fine.)
    private static let hoistedAtRules: Set<String> = [
        "keyframes", "font-face", "property", "page",
        "counter-style", "font-feature-values",
    ]

    /// At-rules that make no sense in a component sheet at all.
    private static let rejectedAtRules: Set<String> = ["import", "charset", "namespace"]

    static func parse(_ css: String) -> ParseResult {
        var parser = Parser(css)
        parser.run()
        let segments = parser.segments.map { segment -> Segment in
            if case .scoped(let text) = segment {
                return .scoped(rewriteHostSelectors(text))
            }
            return segment
        }
        return ParseResult(segments: segments, diagnostics: parser.diagnostics)
    }

    // MARK: - Scanner

    private struct Parser {
        private let chars: [Character]
        private var i = 0
        private var line = 1
        private var column = 1

        private(set) var segments: [Segment] = []
        private(set) var diagnostics: [ParseDiagnostic] = []

        init(_ text: String) { chars = Array(text) }

        private var isAtEnd: Bool { i >= chars.count }

        private func peek(_ offset: Int = 0) -> Character? {
            let j = i + offset
            return j < chars.count ? chars[j] : nil
        }

        @discardableResult
        private mutating func advance() -> Character? {
            guard let c = peek() else { return nil }
            i += 1
            if c == "\n" { line += 1; column = 1 } else { column += 1 }
            return c
        }

        private mutating func emit(_ message: String, line: Int, column: Int) {
            diagnostics.append(ParseDiagnostic(message: message, line: line, column: column))
        }

        // MARK: top level

        mutating func run() {
            while !isAtEnd && diagnostics.isEmpty {
                skipWhitespaceAndComments()
                guard !isAtEnd && diagnostics.isEmpty else { break }
                if peek() == "@" {
                    parseAtRule()
                } else {
                    parseQualifiedRule()
                }
            }
        }

        private mutating func skipWhitespaceAndComments() {
            while let c = peek() {
                if c.isWhitespace {
                    advance()
                } else if c == "/" && peek(1) == "*" {
                    skipComment()
                    if !diagnostics.isEmpty { return }
                } else {
                    break
                }
            }
        }

        private mutating func skipComment() {
            let (l, col) = (line, column)
            advance(); advance() // consume "/*"
            while !isAtEnd {
                if peek() == "*" && peek(1) == "/" {
                    advance(); advance()
                    return
                }
                advance()
            }
            emit("unterminated comment", line: l, column: col)
        }

        /// Consumes a quoted string (cursor on the opening quote). CSS strings
        /// cannot contain unescaped newlines.
        private mutating func skipString() {
            let quote = peek()!
            let (l, col) = (line, column)
            advance()
            while let c = peek() {
                if c == quote { advance(); return }
                if c == "\n" { break }
                if c == "\\" { advance() } // escaped char: consume the backslash, then the char below
                advance()
            }
            emit("unterminated string", line: l, column: col)
        }

        private mutating func parseAtRule() {
            let startIndex = i
            let (l, col) = (line, column)
            advance() // "@"
            var name = ""
            while let c = peek(), c.isLetter || c == "-" {
                name.append(c)
                advance()
            }
            let lowered = name.lowercased()
            if CSSStructuralParser.rejectedAtRules.contains(lowered) {
                emit("@\(lowered) is not supported in component sheets — load global CSS from index.html",
                     line: l, column: col)
                return
            }
            // Prelude ends at ';' (statement form) or '{' (block form).
            var isStatement = false
            while let c = peek() {
                if c == ";" { advance(); isStatement = true; break }
                if c == "{" { break }
                if c == "/" && peek(1) == "*" { skipComment(); if !diagnostics.isEmpty { return }; continue }
                if c == "\"" || c == "'" { skipString(); if !diagnostics.isEmpty { return }; continue }
                advance()
            }
            if !isStatement {
                guard peek() == "{" else {
                    emit("unexpected end of CSS — expected '{' or ';' after '@\(lowered)'", line: l, column: col)
                    return
                }
                scanBlock()
                guard diagnostics.isEmpty else { return }
            }
            let text = String(chars[startIndex..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
            let hoist = CSSStructuralParser.hoistedAtRules.contains(lowered)
                || (lowered == "layer" && isStatement)
            segments.append(hoist ? .hoisted(text) : .scoped(text))
        }

        private mutating func parseQualifiedRule() {
            let startIndex = i
            let (l, col) = (line, column)
            var preludeEnd: Int?
            while let c = peek() {
                if c == "{" { preludeEnd = i; break }
                if c == "/" && peek(1) == "*" { skipComment(); if !diagnostics.isEmpty { return }; continue }
                if c == "\"" || c == "'" { skipString(); if !diagnostics.isEmpty { return }; continue }
                if c == "}" {
                    emit("unmatched '}'", line: line, column: column)
                    return
                }
                if c == ";" {
                    emit("unexpected ';' — expected a '{' block after the selector", line: line, column: column)
                    return
                }
                advance()
            }
            guard let pe = preludeEnd else {
                emit("unexpected end of CSS — expected '{'", line: l, column: col)
                return
            }
            scanBlock()
            guard diagnostics.isEmpty else { return }
            let text = String(chars[startIndex..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
            let prelude = String(chars[startIndex..<pe])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            // Parity with the DSL path's shouldScope(): these escape scoping.
            let escapes = prelude.hasPrefix(":root") || prelude.hasPrefix("html") || prelude.hasPrefix("body")
            segments.append(escapes ? .hoisted(text) : .scoped(text))
        }

        /// Returns `true` if the scanner is positioned at the start of an
        /// unquoted url-token: the preceding character is not an identifier
        /// character, the next four characters case-insensitively spell `url(`,
        /// and the first non-whitespace character after `(` is neither `"` nor
        /// `'` (the quoted form uses normal string scanning).
        private func unquotedURLStart() -> Bool {
            // Boundary: the char immediately before `i` must not be an ident char.
            if i > 0 {
                let prev = chars[i - 1]
                if prev.isLetter || prev.isNumber || prev == "-" || prev == "_" { return false }
            }
            // Case-insensitive "url(" lookahead.
            guard
                let c0 = peek(0), (c0 == "u" || c0 == "U"),
                let c1 = peek(1), (c1 == "r" || c1 == "R"),
                let c2 = peek(2), (c2 == "l" || c2 == "L"),
                let c3 = peek(3), c3 == "("
            else { return false }
            // Skip whitespace after `(` and check the next char.
            var j = i + 4
            while j < chars.count && chars[j].isWhitespace { j += 1 }
            // If we hit EOF, it's an empty url() — treat as unquoted (will be
            // consumed and then EOF terminates with an "unterminated url()" diag).
            if j >= chars.count { return true }
            let after = chars[j]
            // Quoted form: leave for normal string scanning.
            if after == "\"" || after == "'" { return false }
            return true
        }

        /// Consumes an unquoted url-token starting at the current position.
        /// Caller must have verified `unquotedURLStart()` is true.
        /// Emits "unterminated url()" if EOF is reached before the closing `)`.
        private mutating func skipUnquotedURL() {
            let (urlLine, urlCol) = (line, column)
            // Consume "url(".
            advance(); advance(); advance(); advance()
            // Consume everything up to and including the first unescaped `)`.
            while let c = peek() {
                if c == "\\" {
                    advance() // consume backslash
                    advance() // consume escaped char (or nothing at EOF)
                    continue
                }
                if c == ")" {
                    advance()
                    return
                }
                advance()
            }
            // Reached EOF without closing `)`.
            emit("unterminated url()", line: urlLine, column: urlCol)
        }

        /// Consumes a balanced `{ … }` block (cursor must be on the opening
        /// `{`). Tracks (), [] balance and checks declaration shape: a chunk
        /// terminated by ';' or '}' directly inside braces must contain ':'
        /// (chunks followed by '{' are preludes and exempt; chunks starting
        /// with '@' are nested at-rule statements and exempt).
        private mutating func scanBlock() {
            var stack: [(open: Character, line: Int, column: Int)] = []
            var chunk = ""
            var chunkStart: (line: Int, column: Int)?

            func checkChunk() {
                let t = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                let start = chunkStart
                chunk = ""
                chunkStart = nil
                guard !t.isEmpty, !t.hasPrefix("@") else { return }
                if !t.contains(":") {
                    let (l, c) = start ?? (line, column)
                    emit("expected 'property: value' — got '\(t)'", line: l, column: c)
                }
            }

            while let c = peek(), diagnostics.isEmpty {
                switch c {
                case "/" where peek(1) == "*":
                    skipComment()
                case "\"", "'":
                    skipString()
                case "{", "(", "[":
                    if c == "{" {
                        // What accumulated was a nested-rule prelude, not a declaration.
                        chunk = ""
                        chunkStart = nil
                    }
                    stack.append((c, line, column))
                    advance()
                case "}", ")", "]":
                    if c == "}" { checkChunk() }
                    guard diagnostics.isEmpty else { return }
                    guard let top = stack.last else {
                        emit("unmatched '\(c)'", line: line, column: column)
                        return
                    }
                    let expected: Character = top.open == "{" ? "}" : (top.open == "(" ? ")" : "]")
                    guard c == expected else {
                        emit("mismatched '\(c)' — expected '\(expected)' to close '\(top.open)' opened at line \(top.line)",
                             line: line, column: column)
                        return
                    }
                    stack.removeLast()
                    advance()
                    if stack.isEmpty { return } // closed the block we entered with
                case ";":
                    if stack.last?.open == "{" { checkChunk() }
                    advance()
                default:
                    // Unquoted url-token: consume opaquely — may contain {, }, ;, ,
                    // (data URIs are the classic case). Do NOT push/pop the balance
                    // stack for the ( ) pair; the body is not CSS structure.
                    if unquotedURLStart() {
                        skipUnquotedURL()
                        continue
                    }
                    // Accumulate declaration text only directly inside braces
                    // (inside parens/brackets the ':' was already seen or the
                    // content is value-internal, e.g. url(), calc()).
                    if stack.last?.open == "{" && !(c.isWhitespace && chunk.isEmpty) {
                        if chunk.isEmpty { chunkStart = (line, column) }
                        chunk.append(c)
                    }
                    advance()
                }
            }
            if diagnostics.isEmpty, let top = stack.last {
                emit("unclosed '\(top.open)'", line: top.line, column: top.column)
            }
        }
    }

    // MARK: - :host rewriting (Task 3)

    /// Placeholder until Task 3 — identity for now.
    static func rewriteHostSelectors(_ css: String) -> String { css }
}
