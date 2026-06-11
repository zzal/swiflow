// Sources/Swiflow/DevAPIFormatter.swift
//
// Dev-only inspection formatter. Its only caller is `DevAPI.installAll()`
// (SwiflowDOM), which is `#if !SWIFLOW_RELEASE`-gated to an empty stub in
// release. Gating the type too keeps it (and its source-path / type-name
// strings) out of the release wasm entirely. Host/dev builds don't define
// `SWIFLOW_RELEASE`, so it stays available for `DevAPIFormatterTests`.
#if !SWIFLOW_RELEASE

@MainActor
package enum DevAPIFormatter {

    // MARK: - tree()

    package static func treeString(from root: MountNode) -> String {
        var lines: [String] = []
        walkTree(root, path: "", depth: 0, into: &lines)
        return lines.joined(separator: "\n")
    }

    private static func walkTree(
        _ node: MountNode,
        path: String,
        depth: Int,
        into lines: inout [String]
    ) {
        if let anyC = node.component {
            let typeName = String(reflecting: type(of: anyC.instance))
            let shortName = typeName.split(separator: ".").last.map(String.init) ?? typeName
            let bodyMark = (node.componentBody?.component != nil) ? " [body→]" : ""
            lines.append(String(repeating: "  ", count: depth) + shortName + " \"\(path)\"" + bodyMark)
            if let body = node.componentBody {
                walkTree(body, path: path, depth: depth + 1, into: &lines)
            }
        } else if case .environmentOverride = node.vnode, let body = node.componentBody {
            walkTree(body, path: path, depth: depth, into: &lines)
        } else {
            for (i, child) in node.children.enumerated() {
                let childPath = path.isEmpty ? String(i) : "\(path).\(i)"
                walkTree(child, path: childPath, depth: depth, into: &lines)
            }
        }
    }

    // MARK: - state(path)

    package static func stateValues(from root: MountNode, path: String) -> [String: Any]? {
        let snapshots = HMRWalker.snapshot(from: root)
        return snapshots.first(where: { $0.path == path })?.state
    }
}

#endif  // !SWIFLOW_RELEASE
