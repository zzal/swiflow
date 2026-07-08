// Sources/SwiflowRouter/Core/Navigator.swift

/// The browser crossing behind `RouterRoot`'s URL machine: location reads,
/// history writes, and the URL-change event listener. Deliberately
/// primitives-level — mode dispatch (which event to listen to, which URL
/// shape to write) stays in `RouterRoot`, so implementations are verbatim
/// JS (or in-memory) surfaces with no routing logic to drift.
///
/// This is the seam that makes the routing lifecycle host-testable:
/// `BrowserNavigator` (Web/) is the production implementation,
/// `MockNavigator` (test target) the recording one. Package-scoped on
/// purpose — the SwiflowDriver precedent: a testability seam, not user API.
@MainActor
package protocol Navigator: AnyObject {
    /// `location.hash` — `""` or `"#/path"`.
    var hash: String { get }
    /// `location.pathname`.
    var pathname: String { get }
    /// `location.search` — `""` or `"?k=v"`.
    var search: String { get }
    /// `location.hash = path`. The browser fires `hashchange` afterwards —
    /// asynchronously; callers must NOT assume the change listener already ran.
    func setHash(_ path: String)
    /// `history.pushState(null, "", url)`. Fires NO event (browser
    /// contract) — the caller owns any state update.
    func pushState(_ url: String)
    /// `history.replaceState(null, "", url)`. Fires NO event.
    func replaceState(_ url: String)
    /// `history.back()`.
    func back()
    /// Register `handler` for `event` on `window`. Replaces any prior
    /// registration (single-listener contract — `RouterRoot` registers
    /// exactly once, in `onAppear`).
    func startListening(to event: String, handler: @escaping @MainActor () -> Void)
    /// Remove the registered listener; no-op when nothing is registered.
    func stopListening()
}
