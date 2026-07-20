// Sources/SwiflowUI/PopoverTransition.swift
import Swiflow

/// The top-layer entry/exit animation quartet — closed state, 4-part
/// transition, open state, `@starting-style` — shared by every popover- and
/// dialog-based overlay. One authoring site; per-overlay differences are the
/// selectors, the transform vector, and any open-state display extras.
///
/// The generated block is appended AFTER the overlay's own panel-styling
/// rule — CSS merges same-selector rules, so the animation parts live here
/// without duplicating the panel rule. Nonisolated: pure string formatting,
/// called from the nonisolated global sheet initializers.
func popoverTransitionCSS(base: String, open: String,
                          closedTransform: String, openTransform: String,
                          openExtras: String = "") -> String {
    """
    \(base) {
      opacity: 0;
      transform: \(closedTransform);
      transition: opacity var(--sw-duration) var(--sw-ease),
                  transform var(--sw-duration) var(--sw-ease),
                  overlay var(--sw-duration) var(--sw-ease) allow-discrete,
                  display var(--sw-duration) var(--sw-ease) allow-discrete;
    }
    /* `display` lives on the open state only: an author `display` in the base
       rule would override the popover/dialog UA's `display:none`-when-closed
       (author beats UA regardless of specificity), leaving a closed panel
       present at opacity: 0. */
    \(open) {\(openExtras)
      opacity: 1;
      transform: \(openTransform);
    }
    @starting-style {
      \(open) { opacity: 0; transform: \(closedTransform); }
    }
    """
}
