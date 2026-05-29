// Sources/App/Counter+Styles.swift
import Swiflow

extension Counter {
    static var scopedStyles: CSSSheet? = tokens + layout + theme + animations + responsive

    // ---- tokens ----
    static let tokens = css {
        raw("""
            @property --accent {
              syntax: "<color>";
              inherits: true;
              initial-value: oklch(.65 .14 250);
            }
            """)
        rule(":root") {
            cssVar("--accent", "light-dark(oklch(.55 .18 250), oklch(.75 .14 250))")
            cssVar("--surface", "light-dark(oklch(.99 0 0), oklch(.18 .005 250))")
            cssVar("--surface-elev", "light-dark(oklch(.97 0 0), oklch(.22 .005 250))")
            cssVar("--text", "CanvasText")
            cssVar("--text-dim", "color-mix(in oklab, CanvasText 65%, Canvas)")
            cssVar("--border", "color-mix(in oklab, CanvasText 12%, transparent)")
        }
    }

    // ---- layout ----
    static let layout = css {
        host {
            display("block")
            maxWidth("520px")
            margin("2.5rem auto")
            padding("2rem")
            containerType("inline-size")
        }
        rule(".card") {
            display("flex")
            flexDirection("column")
            gap("1rem")
            padding("1.75rem")
            borderRadius("16px")
            background("var(--surface)")
            border("1px solid var(--border)")
            boxShadow("0 1px 0 var(--border), 0 24px 48px -32px rgb(0 0 0 / .25)")
        }
        rule(".header") {
            display("flex")
            alignItems("center")
            justifyContent("space-between")
            gap("0.5rem")
            margin("0")
            padding("0")
            border("0")
        }
        rule(".greeting-heading") {
            margin("0")
            fontSize("1.4rem")
            fontWeight("600")
        }
        rule(".info-trigger") {
            anchorName("--info-anchor")
            display("grid")
            placeItems("center")
            width("1.75rem")
            height("1.75rem")
            borderRadius("50%")
            border("1px solid var(--border)")
            background("transparent")
            color("var(--text-dim)")
            cursor("pointer")
            fontSize("0.9rem")
        }
        rule(".actions") {
            display("flex")
            flexWrap("wrap")
            gap("0.5rem")
        }
        rule(".greeting-row") {
            display("flex")
            gap("0.5rem")
            alignItems("center")
        }
        rule(".greeting-row input") {
            flex("1")
            padding("0.4rem 0.6rem")
            border("1px solid var(--border)")
            borderRadius("6px")
            background("Canvas")
            color("CanvasText")
        }
        rule(".checkbox-row") {
            display("flex")
            gap("0.5rem")
            alignItems("center")
            cursor("pointer")
        }
        rule(".inspector") {
            border("1px solid var(--border)")
            borderRadius("10px")
            padding("0.5rem 0.75rem")
            interpolateSize("allow-keywords")
        }
        rule(".inspector summary") {
            cursor("pointer")
            listStyle("none")
            fontSize("0.95rem")
            color("var(--text-dim)")
        }
        rule(".inspector summary::-webkit-details-marker") {
            display("none")
        }
        rule(".inspector summary::before") {
            property("content", "\"▸ \"")
            display("inline-block")
            transition("transform .15s ease")
        }
        rule(".inspector[open] summary::before") {
            transform("rotate(90deg)")
        }
        rule(".inspector-list") {
            margin("0.5rem 0 0 0")
            padding("0 0 0 1.25rem")
            color("var(--text-dim)")
            fontSize("0.9rem")
        }
    }

    // ---- theme ----
    static let theme = css {
        rule(".count") {
            margin("0")
            fontSize("1.6rem")
            fontWeight("600")
            color("var(--accent)")
            viewTransitionName("count-value")
            transition("--accent .25s ease")
        }
        rule("button") {
            padding("0.4rem 0.9rem")
            border("1px solid var(--border)")
            borderRadius("6px")
            background("var(--accent)")
            color("Canvas")
            cursor("pointer")
            fontSize("0.95rem")
        }
        rule(".secondary") {
            background("transparent")
            color("var(--text)")
        }
        rule("button:focus-visible") {
            property("outline", "2px solid var(--accent)")
            property("outline-offset", "2px")
        }
        rule("input:focus-visible") {
            property("outline", "2px solid var(--accent)")
            property("outline-offset", "2px")
        }
        rule(".checkbox-row:focus-visible") {
            property("outline", "2px solid var(--accent)")
            property("outline-offset", "2px")
        }

        // <dialog> + ::backdrop styling.
        rule(".signin-dialog") {
            border("0")
            borderRadius("16px")
            padding("0")
            background("var(--surface-elev)")
            color("var(--text)")
            boxShadow("0 24px 48px -16px rgb(0 0 0 / .45)")
            maxWidth("min(90vw, 420px)")
        }
        rule(".signin-dialog .signin") {
            padding("1.5rem")
        }
        rule(".signin-dialog::backdrop") {
            background("color-mix(in oklab, Canvas 30%, transparent)")
            backdropFilter("blur(6px)")
        }
    }

    // ---- animations ----
    static let animations = css {
        keyframes("counter-in") {
            from { opacity("0"); transform("translateY(-6px)") }
            to   { opacity("1"); transform("translateY(0)") }
        }
        host {
            animation("counter-in 0.3s ease forwards")
        }
    }

    // ---- responsive (container query via raw escape hatch) ----
    static let responsive = css {
        raw("""
            @container (max-width: 380px) {
              .swiflow-Counter .actions { flex-direction: column; align-items: stretch; }
              .swiflow-Counter .card { padding: 1.25rem; gap: 0.75rem; }
            }
            """)
    }
}
