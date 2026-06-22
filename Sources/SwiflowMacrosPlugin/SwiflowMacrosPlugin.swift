// Sources/SwiflowMacrosPlugin/SwiflowMacrosPlugin.swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiflowMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ComponentMacro.self,
        StateMacro.self,
        MutationStateMacro.self,
        CSSMacro.self,
        KeyMacro.self,
        QueryTypeMacro.self,
    ]
}
