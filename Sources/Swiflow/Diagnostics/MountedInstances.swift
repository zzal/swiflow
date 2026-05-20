// Sources/Swiflow/Diagnostics/MountedInstances.swift

#if DEBUG
/// DEBUG-only registry of every currently-mounted Component instance, used
/// to catch the `embed { self.existingCounter }` footgun documented in
/// `Sources/Swiflow/DSL/ComponentDSL.swift`.
///
/// On first mount of a component anchor, the diff records the new
/// instance here. If the diff later tries to register an instance that
/// is *still alive and already mounted somewhere*, that's the
/// reused-instance bug — and the diff fires a `swiflowDiagnostic` whose
/// message names the footgun.
///
/// **Weak storage, not raw `ObjectIdentifier`:** the registry stores
/// weak references keyed by identifier. `ObjectIdentifier` is just the
/// instance's address — Swift's allocator legitimately reuses freed
/// addresses, so a `Set<ObjectIdentifier>` would produce false positives
/// when a previously-mounted-then-freed instance's slot is reused by a
/// brand-new allocation (very common across consecutive tests). The
/// weak ref auto-nils on `deinit`, letting us distinguish "this
/// identifier still refers to a live mounted instance" from "this
/// identifier happens to match a corpse."
///
/// On unmount (`destroy()`), the diff removes the entry. The cleanup
/// is belt-and-suspenders — the weak ref would auto-nil anyway when
/// the instance deinits — but it keeps the dictionary from growing
/// monotonically across a long-running app's mount/unmount churn.
///
/// **`@MainActor`:** Component is `@MainActor`-isolated per Phase 5,
/// and the diff that consumes this registry runs on the main actor
/// too — keeping the tracker on the same actor avoids cross-actor
/// races without any locking.
///
/// **Release builds:** this entire file (and its call sites) is gated
/// `#if DEBUG`. Compiles to nothing in release.
@MainActor
package enum MountedInstances {
    /// Weak-reference holder. `Set<ObjectIdentifier>` would track only
    /// the address bits; we need lifetime awareness to detect
    /// allocator address reuse.
    package final class WeakBox {
        package weak var ref: AnyObject?
        package init(_ ref: AnyObject) { self.ref = ref }
    }

    /// Identifier → weak ref. An entry whose `ref` has become `nil`
    /// describes a dead instance whose address may have been recycled
    /// to a brand-new object; treat such entries as not-mounted.
    package static var live: [ObjectIdentifier: WeakBox] = [:]

    /// Records `instance` as mounted. Returns `true` if the registration
    /// is fresh (no live entry at the same identifier); returns `false`
    /// when `instance` is already in the set AND its prior entry's weak
    /// ref still resolves to a live object — the genuine reused-instance
    /// case — in which case the caller should fire a diagnostic.
    @discardableResult
    package static func register(_ instance: AnyObject) -> Bool {
        let id = ObjectIdentifier(instance)
        if let box = live[id], box.ref != nil {
            // Live, identifier already known — same instance is being
            // re-registered. This is the actual footgun.
            return false
        }
        // Either no prior entry, or the prior entry's weak ref is nil
        // (the previous holder of this address has deinit'd; the
        // allocator recycled the slot for a genuinely new instance).
        live[id] = WeakBox(instance)
        return true
    }

    /// Forgets `instance` (called from `destroy()` when its anchor is
    /// torn down). Idempotent — no-op if the identifier was missing.
    package static func unregister(_ instance: AnyObject) {
        live.removeValue(forKey: ObjectIdentifier(instance))
    }
}
#endif
