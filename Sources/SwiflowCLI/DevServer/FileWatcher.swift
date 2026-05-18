// Sources/SwiflowCLI/DevServer/FileWatcher.swift
//
// Polling file watcher. Chosen over FSEvents/inotify (which the spec
// suggested) for two reasons: cross-platform with one code path, and
// ~30 LOC vs. ~200 for the native equivalents. 250 ms latency is under
// the user-perception threshold for save → reload and the CPU cost of
// stat'ing ~50 files every poll is negligible (typical Sources/ tree).
//
// If Phase 4 ever profiles polling as a real bottleneck, swap the
// `snapshot()` body for an FSEventStream / inotify backend. The
// AsyncStream API is the seam.

import Foundation

final class FileWatcher: Sendable {
    let root: URL
    let interval: Duration
    let extensions: Set<String>

    /// - Parameters:
    ///   - root: directory to scan recursively. Top-level files matching
    ///     `extensions` are always watched; deeper files are only watched
    ///     if their parent path doesn't start with `.` (skips `.build`,
    ///     `.swiftpm`, etc.).
    ///   - interval: poll cadence. 250 ms is the dev-server default.
    ///   - extensions: file suffixes (without dot) to track. Other files
    ///     are ignored.
    init(root: URL, interval: Duration = .milliseconds(250), extensions: Set<String>) {
        self.root = root
        self.interval = interval
        self.extensions = extensions
    }

    /// Starts polling and yields a `Set<URL>` whenever any tracked file
    /// is created, modified, or deleted. The stream continues until the
    /// consumer terminates iteration (the inner task is cancelled on
    /// stream termination).
    func changes() -> AsyncStream<Set<URL>> {
        AsyncStream { continuation in
            let task = Task { [self] in
                var previous = self.snapshot()
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: self.interval)
                    } catch {
                        break
                    }
                    let current = self.snapshot()
                    let changed = Self.diff(current: current, previous: previous)
                    if !changed.isEmpty {
                        continuation.yield(changed)
                    }
                    previous = current
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Walks `root` and returns (URL → modificationDate) for every file
    /// whose extension is in `extensions` and which isn't under a
    /// dot-prefixed directory (`.build`, `.swiftpm`, `.git`).
    ///
    /// Package-internal (not private) so tests can exercise the extension
    /// filter without going through the AsyncStream pipeline — the
    /// orphan-task patterns required to drive the async stream through a
    /// "no event ever fires" case interact badly with Swift Testing's
    /// child-task cleanup. Direct snapshot tests cover the filter intent
    /// without the threading complexity.
    func snapshot() -> [URL: Date] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [URL: Date] = [:]
        for case let url as URL in enumerator {
            let ext = url.pathExtension
            guard extensions.contains(ext) else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate else {
                continue
            }
            // Canonicalise via resolvingSymlinksInPath so equality against
            // a consumer-supplied URL (e.g. `root.appendingPathComponent("App.swift")`)
            // doesn't fail on macOS /tmp → /private/tmp symlinking. Without
            // this, the diff Set's URLs don't match what callers compare
            // against and downstream `.contains(_:)` checks silently return
            // false.
            result[url.resolvingSymlinksInPath()] = mtime
        }
        return result
    }

    /// Set-diff between two snapshots. Returns the union of created,
    /// modified, and deleted file URLs.
    static func diff(current: [URL: Date], previous: [URL: Date]) -> Set<URL> {
        var changed: Set<URL> = []
        for (url, date) in current {
            if previous[url] != date {
                changed.insert(url)
            }
        }
        for url in previous.keys where current[url] == nil {
            changed.insert(url)
        }
        return changed
    }
}
