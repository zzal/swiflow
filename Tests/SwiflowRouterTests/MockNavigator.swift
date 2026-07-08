// Tests/SwiflowRouterTests/MockNavigator.swift
@testable import SwiflowRouter

/// Recording `Navigator` for host tests (the scripted-runner house pattern):
/// settable location state, recorded write calls, and an explicit
/// `fireChange()` standing in for the browser's async event dispatch —
/// tests script the browser's half themselves, keeping the event-driven
/// flow visible in the test body. No history-stack emulation on purpose.
@MainActor
final class MockNavigator: Navigator {
    var hash: String = ""
    var pathname: String = "/"
    var search: String = ""

    private(set) var setHashCalls: [String] = []
    private(set) var pushedURLs: [String] = []
    private(set) var replacedURLs: [String] = []
    private(set) var backCount = 0
    private(set) var listeningTo: String?
    private(set) var stopListeningCount = 0
    private var handler: (@MainActor () -> Void)?

    func setHash(_ path: String) {
        setHashCalls.append(path)
        // Mirror the browser: `location.hash = "/x"` reads back as "#/x".
        hash = path.hasPrefix("#") ? path : "#" + path
    }
    func pushState(_ url: String) { pushedURLs.append(url) }
    func replaceState(_ url: String) { replacedURLs.append(url) }
    func back() { backCount += 1 }
    func startListening(to event: String, handler: @escaping @MainActor () -> Void) {
        listeningTo = event
        self.handler = handler
    }
    func stopListening() {
        stopListeningCount += 1
        listeningTo = nil
        handler = nil
    }
    /// The browser's half: deliver the registered URL-change event.
    func fireChange() { handler?() }
}
