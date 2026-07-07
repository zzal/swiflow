// Tests/SwiflowCLITests/RuntimeCopySyncTests.swift
//
// Audit III Wave-2 #11: the per-example runtime-JS copies are refreshed by
// `swift run swiflow-codegen driver` instead of hand-`cp`. These pin the
// sync policy: refresh-existing only — an example opts in by having the
// file, and the sync never seeds copies into examples that don't.
import Foundation
import SwiflowEmbedders
import Testing

@Suite("RuntimeCopySync")
struct RuntimeCopySyncTests {

    private func makeTree() throws -> (root: URL, jsDriver: URL, examples: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("copysync-\(UUID().uuidString)")
        let jsDriver = root.appendingPathComponent("js-driver")
        let examples = root.appendingPathComponent("examples")
        try FileManager.default.createDirectory(at: jsDriver, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: examples, withIntermediateDirectories: true)
        for name in RuntimeCopySync.runtimeFileNames {
            try "canonical \(name)\n".write(
                to: jsDriver.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return (root, jsDriver, examples)
    }

    @Test("plan pairs every EXISTING example copy with its js-driver source")
    func plansExistingCopiesOnly() throws {
        let (root, jsDriver, examples) = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        // HasDriver opts into driver+sw; Bare opts into nothing.
        let hasDriver = examples.appendingPathComponent("HasDriver")
        let bare = examples.appendingPathComponent("Bare")
        try FileManager.default.createDirectory(at: hasDriver, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try "stale\n".write(to: hasDriver.appendingPathComponent("swiflow-driver.js"), atomically: true, encoding: .utf8)
        try "stale\n".write(to: hasDriver.appendingPathComponent("swiflow-service-worker.js"), atomically: true, encoding: .utf8)

        let plan = try RuntimeCopySync.plan(jsDriverRoot: jsDriver, examplesRoot: examples)

        #expect(plan.count == 2, "only the two existing copies — never seeding Bare")
        #expect(plan.allSatisfy { $0.destination.path.contains("/HasDriver/") })
    }

    @Test("execute refreshes stale copies byte-for-byte")
    func executeRefreshes() throws {
        let (root, jsDriver, examples) = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let demo = examples.appendingPathComponent("Demo")
        try FileManager.default.createDirectory(at: demo, withIntermediateDirectories: true)
        let dest = demo.appendingPathComponent("swiflow-driver.js")
        try "stale bytes\n".write(to: dest, atomically: true, encoding: .utf8)

        let plan = try RuntimeCopySync.plan(jsDriverRoot: jsDriver, examplesRoot: examples)
        try RuntimeCopySync.execute(plan)

        #expect(try String(contentsOf: dest, encoding: .utf8) == "canonical swiflow-driver.js\n")
    }

    @Test("the plan is deterministic — sorted by example directory")
    func planIsSorted() throws {
        let (root, jsDriver, examples) = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        for name in ["Zeta", "Alpha", "Mid"] {
            let dir = examples.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "x\n".write(to: dir.appendingPathComponent("swiflow-driver.js"), atomically: true, encoding: .utf8)
        }
        let plan = try RuntimeCopySync.plan(jsDriverRoot: jsDriver, examplesRoot: examples)
        let dirs = plan.map { $0.destination.deletingLastPathComponent().lastPathComponent }
        #expect(dirs == ["Alpha", "Mid", "Zeta"])
    }
}
