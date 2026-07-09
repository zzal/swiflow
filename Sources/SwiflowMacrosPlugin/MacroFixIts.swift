// Sources/SwiflowMacrosPlugin/MacroFixIts.swift
import SwiftDiagnostics
import SwiftSyntax

/// Fix-It labels for the mechanical macro diagnostics — cases where there is
/// exactly one correct edit, so the compiler can offer an editor "Fix" button.
/// Non-mechanical diagnostics (missing type, computed property, no default)
/// carry no Fix-It: there is no single right edit.
enum SwiflowFixItMessage: FixItMessage {
    case letToVar
    case structToFinalClass
    case addFinal

    var message: String {
        switch self {
        case .letToVar: return "Replace 'let' with 'var'"
        case .structToFinalClass: return "Replace 'struct' with 'final class'"
        case .addFinal: return "Add 'final'"
        }
    }

    var fixItID: MessageID {
        let id: String
        switch self {
        case .letToVar: id = "letToVar"
        case .structToFinalClass: id = "structToFinalClass"
        case .addFinal: id = "addFinal"
        }
        return MessageID(domain: "SwiflowMacros", id: "fixit.\(id)")
    }
}

/// Builders for the mechanical Fix-Its. Each preserves the surrounding trivia so
/// the applied edit stays correctly spaced (the `final` modifier inherits the
/// introducer's leading trivia — indentation/newline — and the keyword it
/// precedes is re-anchored to a single space).
enum MacroFixIt {
    /// `let x` → `var x` — swap the binding specifier token, keeping its trivia.
    static func letToVar(_ bindingSpecifier: TokenSyntax) -> FixIt {
        let varKeyword = TokenSyntax.keyword(.var)
            .with(\.leadingTrivia, bindingSpecifier.leadingTrivia)
            .with(\.trailingTrivia, bindingSpecifier.trailingTrivia)
        return FixIt(
            message: SwiflowFixItMessage.letToVar,
            changes: [.replace(oldNode: Syntax(bindingSpecifier), newNode: Syntax(varKeyword))]
        )
    }

    /// `struct T` → `final class T` — turn the `struct` keyword into `class` and
    /// prepend a `final` modifier that takes over the keyword's leading trivia.
    static func structToFinalClass(_ decl: StructDeclSyntax) -> FixIt {
        let structKeyword = decl.structKeyword
        let finalModifier = DeclModifierSyntax(name: .keyword(.final))
            .with(\.leadingTrivia, structKeyword.leadingTrivia)
            .with(\.trailingTrivia, .space)
        let classKeyword = TokenSyntax.keyword(.class)
            .with(\.leadingTrivia, [])
            .with(\.trailingTrivia, structKeyword.trailingTrivia)
        return FixIt(
            message: SwiflowFixItMessage.structToFinalClass,
            changes: [
                .replace(oldNode: Syntax(decl.modifiers), newNode: Syntax(DeclModifierListSyntax([finalModifier]))),
                .replace(oldNode: Syntax(structKeyword), newNode: Syntax(classKeyword)),
            ]
        )
    }

    /// `class T` → `final class T` — prepend a `final` modifier before whatever
    /// currently introduces the declaration (an existing modifier like `public`,
    /// else the `class` keyword), inheriting its leading trivia.
    static func addFinal(_ decl: ClassDeclSyntax) -> FixIt {
        if let first = decl.modifiers.first {
            let finalModifier = DeclModifierSyntax(name: .keyword(.final))
                .with(\.leadingTrivia, first.leadingTrivia)
                .with(\.trailingTrivia, .space)
            let rest = decl.modifiers.map { $0 == first ? first.with(\.leadingTrivia, []) : $0 }
            let newModifiers = DeclModifierListSyntax([finalModifier] + rest)
            return FixIt(
                message: SwiflowFixItMessage.addFinal,
                changes: [.replace(oldNode: Syntax(decl.modifiers), newNode: Syntax(newModifiers))]
            )
        } else {
            let classKeyword = decl.classKeyword
            let finalModifier = DeclModifierSyntax(name: .keyword(.final))
                .with(\.leadingTrivia, classKeyword.leadingTrivia)
                .with(\.trailingTrivia, .space)
            let newClassKeyword = classKeyword.with(\.leadingTrivia, [])
            return FixIt(
                message: SwiflowFixItMessage.addFinal,
                changes: [
                    .replace(oldNode: Syntax(decl.modifiers), newNode: Syntax(DeclModifierListSyntax([finalModifier]))),
                    .replace(oldNode: Syntax(classKeyword), newNode: Syntax(newClassKeyword)),
                ]
            )
        }
    }
}
