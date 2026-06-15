// Sources/SwiflowUI/ProgressView.swift
import Swiflow

/// A determinate progress bar. Stateless free function over a native `<progress>`
/// (native `role="progressbar"` + `aria-valuenow` for free), skinned with the
/// accent fill on a `--sw-surface-2` track. `value` is `0...1` (clamped). For an
/// indeterminate "working…" state use ``Spinner``.
///
///     ProgressView(value: 0.6)
@MainActor
public func ProgressView(value: Double, _ attributes: Attribute...) -> VNode {
    ensureBaseStyles()
    installControlSheet(id: "sw-progress", progressStyleSheet)

    let clamped = max(0, min(1, value))
    let (callerClasses, callerRest) = splitClasses(attributes)
    let classValue = (["sw-progress"] + callerClasses).joined(separator: " ")
    return element("progress",
                   attributes: [.class(classValue), .attr("value", String(clamped)), .attr("max", "1")] + callerRest)
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
    """)
}
