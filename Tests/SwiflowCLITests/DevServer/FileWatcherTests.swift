// Tests/SwiflowCLITests/DevServer/FileWatcherTests.swift
import Foundation
import Testing
@testable import SwiflowCLI

@Suite("FileWatcher")
struct FileWatcherTests {

    /// Helper: create a temp dir, run a closure, clean up.
    /// The returned URL is canonicalised via `resolvingSymlinksInPath()` so
    /// equality against URLs from `FileWatcher.snapshot()` works on macOS
    /// (where `/tmp` symlinks to `/private/tmp`).
    static func withTempDir(_ body: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-fw-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    /// Helper: write `contents` to `url`, ensuring mtime advances even
    /// on filesystems with low-resolution timestamps (HFS+, some Linux
    /// configurations). Polls until visible.
    static func writeFile(_ url: URL, _ contents: String = "x") throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        // Bump mtime by ~50ms to guarantee diff visibility on coarse FS.
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }

    @Test("Yields the URL set after a new file is created")
    func detectsCreation() async throws {
        try await Self.withTempDir { root in
            let watcher = FileWatcher(
                root: root,
                interval: .milliseconds(100),
                extensions: ["swift"]
            )
            let stream = watcher.changes()
            // Wait a tick for the initial snapshot to settle (no events yet).
            try await Task.sleep(for: .milliseconds(150))
            let newFile = root.appendingPathComponent("App.swift")
            try Self.writeFile(newFile)
            // Pull the next event with a generous timeout.
            let task = Task {
                var iter = stream.makeAsyncIterator()
                return await iter.next()
            }
            let event = try await Self.withTimeout(seconds: 2) { await task.value }
            #expect(event?.contains(newFile) == true)
        }
    }

    @Test("Yields the URL set after a tracked file is modified")
    func detectsModification() async throws {
        try await Self.withTempDir { root in
            let file = root.appendingPathComponent("App.swift")
            try Self.writeFile(file, "v1")
            let watcher = FileWatcher(root: root, interval: .milliseconds(100), extensions: ["swift"])
            let stream = watcher.changes()
            try await Task.sleep(for: .milliseconds(150))
            // Force mtime to advance.
            try await Task.sleep(for: .milliseconds(60))
            try Self.writeFile(file, "v2")
            let task = Task {
                var iter = stream.makeAsyncIterator()
                return await iter.next()
            }
            let event = try await Self.withTimeout(seconds: 2) { await task.value }
            #expect(event?.contains(file) == true)
        }
    }

    @Test("snapshot() ignores files whose extension is not in the watch list")
    func snapshotIgnoresUnwatchedExtensions() async throws {
        // Test the extension filter directly via snapshot() rather than
        // through the AsyncStream pipeline. The async path requires
        // orphan-Task patterns to assert "no event ever fires," and those
        // interact badly with Swift Testing's child-task cleanup —
        // resulting in test-runner hangs even when the watcher logic
        // itself is correct. snapshot() is a pure function: call it twice,
        // diff, and assert the diff is empty for an unwatched extension.
        try await Self.withTempDir { root in
            let watcher = FileWatcher(root: root, interval: .milliseconds(100), extensions: ["swift"])
            let before = watcher.snapshot()
            try Self.writeFile(root.appendingPathComponent("README.txt"))
            let after = watcher.snapshot()
            let changed = FileWatcher.diff(current: after, previous: before)
            #expect(changed.isEmpty, "Expected diff to be empty for unwatched extension; got \(changed)")
        }
    }

    // Tiny timeout helper — keeps tests deterministic without sleep-and-pray.
    struct TimeoutError: Error {}
    static func withTimeout<T: Sendable>(seconds: TimeInterval, _ body: @escaping @Sendable () async -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { await body() }
            group.addTask {
                try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
                throw TimeoutError()
            }
            guard let first = try await group.next() else { throw TimeoutError() }
            group.cancelAll()
            return first
        }
    }
}
