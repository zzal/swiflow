// Sources/App/AboutPopover.swift
import Swiflow

/// AboutPopover — declarative popover using the Popover API.
///
/// The trigger lives in Counter and uses `popovertarget="about-popover"`
/// — no Swift event handler needed. CSS Anchor Positioning floats this
/// card next to the trigger (which sets `anchor-name: --info-anchor`).
@MainActor @Component
final class AboutPopover {
    var body: VNode {
        div(.id("about-popover"),
            .attr("popover", "auto"),
            .class("info-card")) {
            h3("About Swiflow")
            p("Swift, compiled to WASM, with a reactive component model.",
              .class("body"))
            link("View on GitHub",
                 .attr("href", "https://github.com/zzal/swiflow"),
                 .attr("target", "_blank"),
                 .attr("rel", "noopener"))
        }
    }
}
