// Sources/SwiflowUI/ProgressView.swift
import Swiflow

/// A determinate progress bar. Stateless free function over a native `<progress>`
/// (native `role="progressbar"` + `aria-valuenow` for free), skinned with the
/// accent fill on a `--sw-surface-2` track. `value` is `0...1` (clamped). For an
/// indeterminate "working…" state use ``Spinner``.
///
///     ProgressView(value: 0.6)
///     ProgressView(value: 0.6, animated: true)   // macOS-style sheen sweep
///
/// `animated: true` sweeps a light sheen band across the FILLED portion (the
/// macOS copy-dialog look) — purely decorative, gated on `--sw-anim-play` so
/// `prefers-reduced-motion` freezes it, like Spinner/Skeleton.
@MainActor
public func ProgressView(value: Double, label: String? = nil, animated: Bool = false,
                         _ attributes: Attribute...) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-progress", progressStyleSheet)

    let clamped = max(0, min(1, value))
    // Round in Double space (no Int cast — see wasm32 Int gotcha) so the serialized
    // attribute stays clean: String(0.1 + 0.2) would be "0.30000000000000004".
    let rounded = (clamped * 1000).rounded() / 1000

    let (callerClasses, callerRest) = splitClasses(attributes)
    var ownClasses = ["sw-progress"]
    if animated { ownClasses.append("sw-progress--animated") }
    let classValue = (ownClasses + callerClasses).joined(separator: " ")
    var attrs: [Attribute] = [.class(classValue)]
    if let label { attrs.append(.attr("aria-label", label)) }   // bare <progress> has no accessible name
    // <progress> has no user interaction, so its `value` IDL property stays in sync
    // with the content attribute — setAttribute reflects on re-render (unlike <input>).
    attrs.append(.attr("value", String(rounded)))
    attrs.append(.attr("max", "1"))
    return element("progress", attributes: attrs + callerRest)
}

let progressStyleSheet: CSSSheet = css {
    raw("""
    .sw-progress {
      appearance: none;
      -webkit-appearance: none;
      width: 100%;
      height: 0.5em;
      border: none;
      border-radius: 1em;
      overflow: hidden;
      background-color: var(--sw-surface-2);   /* track (Firefox + base) */
      color: var(--sw-accent);                 /* fill (Firefox) */
    }
    .sw-progress::-webkit-progress-bar { background-color: var(--sw-surface-2); border-radius: 1em; }
    .sw-progress::-webkit-progress-value { background-color: var(--sw-accent); border-radius: 1em; }
    .sw-progress::-moz-progress-bar { background-color: var(--sw-accent); border-radius: 1em; }

    /* --animated: a light sheen band sweeps the FILLED portion (the macOS
       copy-dialog look). White-at-alpha over the accent (the macOS glare is
       light regardless of theme); background-position percentages walk the
       no-repeat band edge-to-edge. Gated on --sw-anim-play, so
       prefers-reduced-motion freezes it (Spinner/Skeleton precedent). */
    .sw-progress--animated::-webkit-progress-value {
      background-image: linear-gradient(90deg, transparent, rgb(255 255 255 / 0.45) 35%, rgb(255 255 255 / 0.8) 50%, rgb(255 255 255 / 0.45) 65%, transparent);
      background-size: 40% 100%;
      background-repeat: no-repeat;
      animation: sw-progress-sheen 1.8s ease-in-out infinite;
      animation-play-state: var(--sw-anim-play);
    }
    .sw-progress--animated::-moz-progress-bar {
      background-image: linear-gradient(90deg, transparent, rgb(255 255 255 / 0.45) 35%, rgb(255 255 255 / 0.8) 50%, rgb(255 255 255 / 0.45) 65%, transparent);
      background-size: 40% 100%;
      background-repeat: no-repeat;
      animation: sw-progress-sheen 1.8s ease-in-out infinite;
      animation-play-state: var(--sw-anim-play);
    }
    /* -80%/180% (not 0/100%): position % maps into (track − band) space, so the
       overshoot lets the 40% band fully clear both edges — no resting sliver. */
    @keyframes sw-progress-sheen {
      from { background-position: -80% 0; }
      to   { background-position: 180% 0; }
    }
    """)
}
