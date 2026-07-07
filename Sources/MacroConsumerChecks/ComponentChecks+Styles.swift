// Sources/MacroConsumerChecks/ComponentChecks+Styles.swift
//
// The documented scopedStyles-in-extension pattern: @Component's
// memberAttribute role can't reach extension members, so the explicit
// @MainActor here is required — this file pins that the pattern keeps
// compiling (and that #css emits a CSSSheet usable in that position).

import Swiflow

extension PublicCounter {
    @MainActor public static var scopedStyles: CSSSheet? = #css("""
        &.consumer-check {
          color: rebeccapurple;
        }
        """)
}
