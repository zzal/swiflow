import Swiflow

private enum RouterKey: EnvironmentKey {
    /// The no-op default is a tolerated degradation (snapshot tests,
    /// components rendered outside a router context), so READS stay
    /// silent — but a WRITE on it means a click went dead: the classic
    /// trap is reading `@Environment(\.router)` from an event handler,
    /// where the render ambient is uninstalled and the default fills in.
    /// Each write emits a DEBUG `swiflowWarn` naming the fix instead of
    /// failing silently. (`swiflowWarn`, not `swiflowDiagnostic` — this
    /// must signal, not crash.)
    static let defaultValue = Router(
        path: "/",
        navigate: { path in
            swiflowWarn(noOpMessage("navigate(\"\(path)\")"))
        },
        replace: { path in
            swiflowWarn(noOpMessage("replace(\"\(path)\")"))
        },
        back: {
            swiflowWarn(noOpMessage("back()"))
        }
    )

    private static func noOpMessage(_ call: String) -> String {
        """
        Router.\(call) hit the no-op default router — nothing will navigate. \
        @Environment(\\.router) is only live during body: read it (and capture \
        it) inside body rather than in an event handler, and make sure a \
        RouterRoot is above this component.
        """
    }
}

public extension EnvironmentValues {
    /// The active router. Read with `@Environment(\.router) var router`.
    /// Defaults to a no-op router with `path == "/"` when no `RouterRoot`
    /// is present — useful for snapshot tests and components rendered
    /// outside a router context.
    var router: Router {
        get { self[RouterKey.self] }
        set { self[RouterKey.self] = newValue }
    }
}
