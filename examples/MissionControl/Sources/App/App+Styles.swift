// Sources/App/App+Styles.swift
//
// App-wide styles, owned by the root `Shell` component. `scopedStyles` is a
// `@Component` hook — the runtime injects it (scoped to `.swiflow-Shell`) when
// the type first mounts, so rules here reach every routed page as descendant
// selectors. (A plain struct like the `@main` entry can't host scopedStyles:
// nothing ever mounts it, so the sheet would silently never be installed.)
import Swiflow

extension Shell {
    @MainActor static var scopedStyles: CSSSheet? = #css("""
        .page-title {
            font-weight: 100;
            font-size: 3rem;
        }
    """)
}
