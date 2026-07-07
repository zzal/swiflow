// Sources/SwiflowCLI/Templates/Templates.swift
//
// Tiny module: SwiflowDep (how the generated Package.swift depends on
// Swiflow) + a `render` helper that applies the two scaffold-time tokens
// to any file's raw contents.
//
// Template contents live in EmbeddedTemplates.swift (generated from
// examples/ by `swift run swiflow-codegen templates`).

import Foundation

/// How the generated Package.swift should depend on Swiflow.
enum SwiflowDep: Equatable {
    /// A local path dep: `.package(path: "/path/to/swiflow")`.
    case path(String)
    /// A versioned URL dep: `.package(url: "...", exact: "x.y.z")`.
    case url(String, version: String)

    /// The exact `.package(...)` fragment as it appears in the generated Package.swift.
    var packageFragment: String {
        switch self {
        case .path(let p):
            return #".package(path: "\#(p)")"#
        case .url(let u, let v):
            return #".package(url: "\#(u)", exact: "\#(v)")"#
        }
    }
}

extension SwiflowDep {
    /// The repo `swiflow init` points generated `Package.swift` files at
    /// when scaffolding a versioned URL dep.
    static let officialRepositoryURL = "https://github.com/zzal/swiflow.git"
}

enum Templates {
    /// Applies the two scaffold-time substitutions to a raw template file's
    /// contents. Used by `ProjectWriter` to render each file in a template.
    ///
    /// - `{{NAME}}` ← `name`
    /// - `{{SWIFLOW_DEP}}` ← `swiflowDep.packageFragment`
    static func render(_ raw: String, name: String, swiflowDep: SwiflowDep) -> String {
        return raw
            .replacingOccurrences(of: "{{NAME}}", with: name)
            .replacingOccurrences(of: "{{SWIFLOW_DEP}}", with: swiflowDep.packageFragment)
    }
}
