// Sources/SwiflowUI/Identifier.swift

/// Monotonic source of stable, unique element ids for components that need
/// intra-component ARIA wiring — `aria-labelledby`/`aria-describedby` on overlays,
/// `<label for=…>`/`<input id=…>` on Prompt. Capture once per instance (in `init`),
/// not per `body`, so the id is stable across re-renders and two instances never
/// collide. Main-actor isolated: SwiflowUI rendering is single-threaded on the main
/// actor, so a plain counter is sufficient (no atomics needed).
@MainActor private var swIDCounter = 0

@MainActor
func nextSwID(_ prefix: String) -> String {
    swIDCounter += 1
    return "\(prefix)-\(swIDCounter)"
}
